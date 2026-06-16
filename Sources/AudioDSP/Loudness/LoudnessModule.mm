#include "LoudnessModule.h"
#include <Accelerate/Accelerate.h>
#include <algorithm>
#include <cassert>
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
static_assert(std::atomic<uint32_t>::is_always_lock_free,
              "LoudnessModule requires lock-free uint32 atomics for RT safety");

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
    // Size scratch buffers to maxFrames_ (off-RT; the only allocation site).
    // process() asserts frameCount <= maxFrames_ so these are the tight upper bounds.
    rampBuf_.assign(maxFrames_, 0.0F);
    pushBuf_.assign(static_cast<std::size_t>(maxFrames_) * kMaxChannels, 0.0F);
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
    const uint32_t numChannels = block.channels();
    if (numChannels == 0U)
    {
        return;
    }

    // Gather channel pointers once (RT-safe: no alloc, stack array only).
    std::array<float*, kMaxChannels> bufs{};
    for (uint32_t ch = 0U; ch < numChannels; ++ch)
    {
        bufs[ch] = block.channel(ch);
    }
    if (bufs[0] == nullptr)
    {
        return;
    }

    // frameCount must not exceed the buffer capacity established in initialize().
    assert(frameCount <= maxFrames_); // NOLINT(cppcoreguidelines-pro-bounds-array-to-pointer-decay)

    // Relay control to the worker (cheap atomics — never blocks).
    enabled_.store(params.enabled, std::memory_order_relaxed);
    targetLufs_.store(params.lufsTarget, std::memory_order_relaxed);
    channelCount_.store(numChannels, std::memory_order_release);

    // Process the full frameCount — rampBuf_ and pushBuf_ are sized to maxFrames_
    // (and maxFrames_*kMaxChannels) in initialize(), so no overrun is possible.
    const uint32_t safeCount = std::min(frameCount, maxFrames_);

    if (params.enabled == 0U)
    {
        // Disabled → smoothly return to unity; do not feed the meter.
        makeupGainRamp_.target = kUnityGainLinear;
    }
    else
    {
        // Interleave N channels into pushBuf_ and push to the ring (drop on full — never blocks).
        for (uint32_t frm = 0U; frm < safeCount; ++frm)
        {
            for (uint32_t ch = 0U; ch < numChannels; ++ch)
            {
                pushBuf_[(static_cast<std::size_t>(frm) * numChannels) +
                         static_cast<std::size_t>(ch)] =
                    (bufs[ch] != nullptr) ? bufs[ch][frm] : 0.0F;
            }
        }
        const std::size_t want = static_cast<std::size_t>(safeCount) * numChannels;
        const std::size_t pushed = sampleRing_.tryPushBlock(pushBuf_.data(), want);
        if (pushed < want)
        {
            droppedFrames_.fetch_add((want - pushed) / numChannels, std::memory_order_relaxed);
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
    // applies to ch0/ch1 exactly as the prior left/right pair (bit-exact).
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

    // Track the channel count we last configured the meter for.
    // Initialize to 0 so the first real count always triggers a configure.
    uint32_t configuredCh = 0U;

    while (!stopToken.stop_requested())
    {
        // Read the channel count published by process() (acquire pairs with release store).
        const uint32_t nowCh = channelCount_.load(std::memory_order_acquire);
        if (nowCh == 0U)
        {
            std::this_thread::sleep_for(std::chrono::milliseconds(kWorkerIdleSleepMs));
            continue;
        }

        // On channel-count change: drain the ring then reconfigure the meter so we
        // never mix pre- and post-change interleave layouts in the same feed call.
        if (nowCh != configuredCh)
        {
            // Drain: pop-and-discard until the ring reports empty.
            while (sampleRing_.popBlock(workerChunk_.data(), workerChunk_.size()) > 0U)
            {
            }

            // S2 wires the real ChannelLayout BS.1770-5 weights (LFE=0, surround=1.41) here.
            // For S1 all channels use the stereo-equivalent weight of 1.0.
            std::array<double, kMaxChannels> weights{};
            weights.fill(kBs1770WeightLRC);
            meter_.configureChannels(nowCh, weights);
            configuredCh = nowCh;
        }

        // Frame-aligned pop: round the chunk capacity down to a whole number of frames
        // so we never feed a partial frame to the meter.
        const std::size_t cap = (workerChunk_.size() / configuredCh) * configuredCh;
        const std::size_t got = sampleRing_.popBlock(workerChunk_.data(), cap);
        if (got == 0U)
        {
            std::this_thread::sleep_for(std::chrono::milliseconds(kWorkerIdleSleepMs));
            continue;
        }

        // got is always a multiple of configuredCh because:
        //   - process() only ever pushes multiples of numChannels, and
        //   - cap is frame-aligned, so popBlock returns at most cap elements;
        //   - any partial-frame remainder is left in the ring for the next iteration.
        const std::size_t frames = got / configuredCh;

        const uint32_t prevGated = meter_.gatedBlockCount();
        meter_.addInterleaved(workerChunk_.data(), frames, configuredCh);
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
