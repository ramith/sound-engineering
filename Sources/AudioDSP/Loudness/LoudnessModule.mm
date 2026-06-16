#include "LoudnessModule.h"
#include <Accelerate/Accelerate.h>
#include <algorithm>
#include <chrono>
#include <cmath>

namespace AdaptiveSound
{

// All RT⇄worker hand-offs must be genuinely lock-free or the RT-safety guarantee
// is void. Enforce at compile time (mirrors EQModule.mm).
static_assert(std::atomic<float>::is_always_lock_free,
              "LoudnessModule requires lock-free float atomics for RT safety");
static_assert(std::atomic<uint8_t>::is_always_lock_free,
              "LoudnessModule requires lock-free uint8 atomics for RT safety");
static_assert(std::atomic<uint64_t>::is_always_lock_free,
              "LoudnessModule requires lock-free uint64 atomics for RT safety");

namespace
{
    // Ramp is treated as settled within this absolute gain epsilon (≈ −120 dB).
    constexpr float kGainSettleEpsilon = 1e-6F;

    // AArch64 FPCR flush-to-zero bit (FZ). See DSPKernel.mm / ARM DDI 0487 §A1.4.3.
    constexpr uint64_t kFpcrFlushToZeroBit = 24U;

    // Enable flush-to-zero on the calling (measurement) thread. FPCR is per-thread,
    // so the worker — which runs the K-weighting biquads — must set it itself.
    void enableFlushToZeroOnThisThread() noexcept
    {
#ifdef __aarch64__
        uint64_t fpcr = 0;
        __asm__ volatile("mrs %0, fpcr" : "=r"(fpcr));
        fpcr |= (1ULL << kFpcrFlushToZeroBit);
        __asm__ volatile("msr fpcr, %0" : : "r"(fpcr));
#endif
    }
} // namespace

LoudnessModule::~LoudnessModule() = default; // jthread RAII: request_stop()+join()

void LoudnessModule::initialize(uint32_t sampleRate, uint32_t maxFrames) noexcept
{
    sampleRate_ = sampleRate;
    maxFrames_ = maxFrames;

    meter_.prepare(static_cast<double>(sampleRate));

    makeupGainRamp_.initialize(kMakeupRampTauSeconds, static_cast<float>(sampleRate));
    makeupGainRamp_.target = kUnityGainLinear;
    makeupGainRamp_.snap();

    currentMakeupDb_ = 0.0;
    lastGatedBlocks_ = 0U;
    rampBuf_.fill(0.0F);
    pushBuf_.fill(0.0F);
    makeupGainLinear_.store(kUnityGainLinear, std::memory_order_release);

    // Start the worker LAST, after all state it touches is initialized. jthread
    // move-assignment stops+joins any previous worker (safe to re-initialize).
    measurementThread_ =
        std::jthread([this](const std::stop_token& stopToken) { runMeasurementLoop(stopToken); });
}

void LoudnessModule::process(const LoudnessParams& params, const MultichannelView& block) noexcept
{
    const uint32_t frameCount = block.frames();
    if (frameCount == 0U)
    {
        return;
    }
    const uint32_t numChannels = (block.channels() >= 2U) ? 2U : block.channels();
    if (numChannels == 0U)
    {
        return;
    }
    float* leftBuf = block.channel(0);
    float* rightBuf = (numChannels >= 2U) ? block.channel(1) : nullptr;
    if (leftBuf == nullptr)
    {
        return;
    }

    // Relay control to the worker (cheap atomics — never blocks).
    enabled_.store(params.enabled, std::memory_order_relaxed);
    targetLufs_.store(params.lufsTarget, std::memory_order_relaxed);

    const uint32_t safeCount = std::min(frameCount, kDefaultMaxFrames);

    if (params.enabled == 0U)
    {
        // Disabled → smoothly return to unity; do not feed the meter.
        makeupGainRamp_.target = kUnityGainLinear;
    }
    else
    {
        // Push interleaved stereo to the worker (drop on full — never blocks).
        for (uint32_t i = 0U; i < safeCount; ++i)
        {
            const std::size_t pair = static_cast<std::size_t>(i) * 2U;
            pushBuf_[pair] = leftBuf[i];
            pushBuf_[pair + 1U] = (rightBuf != nullptr) ? rightBuf[i] : leftBuf[i];
        }
        const std::size_t want = static_cast<std::size_t>(safeCount) * 2U;
        const std::size_t pushed = sampleRing_.tryPushBlock(pushBuf_.data(), want);
        if (pushed < want)
        {
            droppedFrames_.fetch_add((want - pushed) / 2U, std::memory_order_relaxed);
        }

        makeupGainRamp_.target = makeupGainLinear_.load(std::memory_order_acquire);
    }

    // Identity fast path: ramp settled at unity → leave the signal untouched.
    const bool settled =
        std::abs(makeupGainRamp_.current - makeupGainRamp_.target) < kGainSettleEpsilon;
    if (settled && (makeupGainRamp_.target == kUnityGainLinear))
    {
        return;
    }

    for (uint32_t i = 0U; i < safeCount; ++i)
    {
        rampBuf_[i] = makeupGainRamp_.tick();
    }
    const vDSP_Length count = static_cast<vDSP_Length>(safeCount);

    // Fan the single makeup-gain envelope out to ALL channels (one ramp for all —
    // the makeup gain is a broadband, channel-independent scalar). At N=2 this
    // applies to ch0/ch1 exactly as the prior left/right pair (bit-exact). The
    // meter push above stays stereo until S1-C2 upgrades LufsMeter to N-channel.
    for (uint32_t ch = 0U; ch < block.channels(); ++ch)
    {
        float* buf = block.channel(ch);
        if (buf != nullptr)
        {
            vDSP_vmul(buf, 1, rampBuf_.data(), 1, buf, 1, count);
        }
    }
}

void LoudnessModule::runMeasurementLoop(const std::stop_token& stopToken) noexcept
{
    enableFlushToZeroOnThisThread();

    while (!stopToken.stop_requested())
    {
        const std::size_t got = sampleRing_.popBlock(workerChunk_.data(), workerChunk_.size());
        if (got == 0U)
        {
            std::this_thread::sleep_for(std::chrono::milliseconds(kWorkerIdleSleepMs));
            continue;
        }

        const uint32_t prevGated = meter_.gatedBlockCount();
        meter_.addInterleavedStereo(workerChunk_.data(), got / 2U);
        const uint32_t nowGated = meter_.gatedBlockCount();

        publishTelemetry();
        if (nowGated > prevGated)
        {
            updateMakeupGain(nowGated - prevGated);
        }
    }
}

void LoudnessModule::updateMakeupGain(uint32_t newGatedBlocks) noexcept
{
    if (meter_.gatedBlockCount() < kLoudnessMinGatedBlocks)
    {
        return; // hold unity until enough program has been measured
    }
    const double integrated = meter_.integratedLufs();
    if (integrated <= kSilenceLufs)
    {
        return;
    }
    const double target = std::clamp(
        static_cast<double>(targetLufs_.load(std::memory_order_relaxed)) - integrated,
        kMakeupClampLoDb, kMakeupClampHiDb);

    // Slew-limit so the makeup gain changes slower than the downstream limiter's
    // ~100 ms release (one 0.1 dB step per gated block ≈ 1 dB/s of program).
    const double maxStep = kMakeupSlewDbPerBlock * static_cast<double>(newGatedBlocks);
    currentMakeupDb_ += std::clamp(target - currentMakeupDb_, -maxStep, maxStep);

    const double linear = std::pow(kDecibelBase, currentMakeupDb_ / kDbAmplitudeScale);
    makeupGainLinear_.store(static_cast<float>(linear), std::memory_order_release);
}

void LoudnessModule::publishTelemetry() noexcept
{
    measuredLufsIntegrated_.store(static_cast<float>(meter_.integratedLufs()),
                                  std::memory_order_release);
    measuredLufsShortTerm_.store(static_cast<float>(meter_.shortTermLufs()),
                                 std::memory_order_release);
    measuredLufsMomentary_.store(static_cast<float>(meter_.momentaryLufs()),
                                 std::memory_order_release);
}

auto LoudnessModule::measuredLufsIntegrated() const noexcept -> float
{
    return measuredLufsIntegrated_.load(std::memory_order_acquire);
}
auto LoudnessModule::measuredLufsShortTerm() const noexcept -> float
{
    return measuredLufsShortTerm_.load(std::memory_order_acquire);
}
auto LoudnessModule::measuredLufsMomentary() const noexcept -> float
{
    return measuredLufsMomentary_.load(std::memory_order_acquire);
}
auto LoudnessModule::currentMakeupGainLinear() const noexcept -> float
{
    return makeupGainLinear_.load(std::memory_order_acquire);
}
auto LoudnessModule::droppedFrameCount() const noexcept -> uint64_t
{
    return droppedFrames_.load(std::memory_order_relaxed);
}

} // namespace AdaptiveSound
