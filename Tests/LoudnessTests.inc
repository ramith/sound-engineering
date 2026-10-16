// LoudnessTests.inc
//
// Loudness tests (Sprint 4 — BS.1770-5 LufsMeter, stereo-only subset).
// #included into Tests/DSPKernelNullTest.cpp after TestSupport.h.
//
// Tests: Loudness_KWeightingLowCut, Loudness_IntegratedAccuracy,
//        Loudness_AbsoluteGate, Loudness_RelativeGate, Loudness_MakeupRoundTrip,
//        Loudness_WorkersSleepWhileIdle.
// Helpers (shared — also used by MultichannelTests.inc): feedStereoSine,
//        feedStereoSilence, kLufsTol.

#include "../Sources/AudioDSP/Loudness/LoudnessModule.h"
#include <sys/resource.h>

// ===========================================================================
// Loudness tests (Sprint 4 — BS.1770-5 LufsMeter). Driven synchronously; no
// threading. Reference values per EBU Tech 3341. Tolerance 0.15 LU (the meter
// is within EBU's ±0.1 LU; the extra margin guards against startup transients).
// ===========================================================================

static const double kLufsTol = 0.15;

// Feed `seconds` of an in-phase stereo sine at `peakDbfs` peak amplitude.
static auto feedStereoSine(
    LufsMeter& meter, double peakDbfs, double freqHz, double seconds, uint32_t sampleRate) -> void
{
    const double amp = std::pow(10.0, peakDbfs / 20.0);
    const auto frames = static_cast<size_t>(seconds * sampleRate);
    std::vector<float> buf(frames * 2U);
    for (size_t n = 0; n < frames; ++n)
    {
        const double s =
            amp * std::sin(2.0 * std::numbers::pi * freqHz * static_cast<double>(n) / sampleRate);
        buf[2 * n] = static_cast<float>(s);
        buf[(2 * n) + 1] = static_cast<float>(s);
    }
    meter.addInterleavedStereo(buf.data(), frames);
}

static auto feedStereoSilence(LufsMeter& meter, double seconds, uint32_t sampleRate) -> void
{
    const auto frames = static_cast<size_t>(seconds * sampleRate);
    std::vector<float> buf(frames * 2U, 0.0F);
    meter.addInterleavedStereo(buf.data(), frames);
}

// Test 15: K-weighting attenuates low frequencies (RLB high-pass + shelf).
// A 40 Hz tone must read substantially lower than a 1 kHz tone at the same peak.
static auto testLoudnessKWeightingLowCut() -> void
{
    static const char* const kName = "Loudness_KWeightingLowCut";
    LufsMeter low;
    low.prepare(TestConstants::kSampleRate48k);
    feedStereoSine(low, -20.0, 40.0, 10.0, TestConstants::kSampleRate48k);

    LufsMeter mid;
    mid.prepare(TestConstants::kSampleRate48k);
    feedStereoSine(mid, -20.0, 1000.0, 10.0, TestConstants::kSampleRate48k);

    const double delta = mid.integratedLufs() - low.integratedLufs();
    if (delta < 3.0)
    {
        std::ostringstream oss;
        oss << "40 Hz should read >=3 LU below 1 kHz; 1k=" << mid.integratedLufs()
            << " 40=" << low.integratedLufs() << " delta=" << delta;
        logFail(kName, oss.str());
        return;
    }
    logPass(kName);
}

// Test 16: Integrated LUFS accuracy for stereo 1 kHz sines (EBU Tech 3341):
// an in-phase stereo sine at X dBFS peak measures X LUFS.
static auto testLoudnessIntegratedAccuracy() -> void
{
    static const char* const kName = "Loudness_IntegratedAccuracy";
    const double levels[] = {-23.0, -33.0, -18.0};
    for (double peak : levels)
    {
        LufsMeter meter;
        meter.prepare(TestConstants::kSampleRate48k);
        feedStereoSine(meter, peak, 1000.0, 15.0, TestConstants::kSampleRate48k);
        const double measured = meter.integratedLufs();
        if (std::abs(measured - peak) > kLufsTol)
        {
            std::ostringstream oss;
            oss << "1 kHz @ " << peak << " dBFS peak: expected " << peak << " LUFS, got "
                << measured << " (delta " << std::abs(measured - peak) << ")";
            logFail(kName, oss.str());
            return;
        }
    }
    logPass(kName);
}

// Test 17: Absolute gate (-70 LUFS) discards silence — a 2 s silence prefix must
// not drag the integrated value below the 8 s of -23 dBFS sine that follows.
static auto testLoudnessAbsoluteGate() -> void
{
    static const char* const kName = "Loudness_AbsoluteGate";
    LufsMeter meter;
    meter.prepare(TestConstants::kSampleRate48k);
    feedStereoSilence(meter, 2.0, TestConstants::kSampleRate48k);
    feedStereoSine(meter, -23.0, 1000.0, 8.0, TestConstants::kSampleRate48k);
    const double measured = meter.integratedLufs();
    if (std::abs(measured - (-23.0)) > 0.3)
    {
        std::ostringstream oss;
        oss << "silence+(-23 dBFS) expected ~-23 LUFS, got " << measured;
        logFail(kName, oss.str());
        return;
    }
    logPass(kName);
}

// Test 18: Relative gate (-10 LU) discards a quiet segment >10 LU below the mean.
// 8 s at -23 dBFS then 8 s at -50 dBFS → integrated ~= the loud segment only.
static auto testLoudnessRelativeGate() -> void
{
    static const char* const kName = "Loudness_RelativeGate";
    LufsMeter meter;
    meter.prepare(TestConstants::kSampleRate48k);
    feedStereoSine(meter, -23.0, 1000.0, 8.0, TestConstants::kSampleRate48k);
    feedStereoSine(meter, -50.0, 1000.0, 8.0, TestConstants::kSampleRate48k);
    const double measured = meter.integratedLufs();
    if (std::abs(measured - (-23.0)) > 0.5)
    {
        std::ostringstream oss;
        oss << "loud+quiet expected ~-23 LUFS (quiet gated out), got " << measured;
        logFail(kName, oss.str());
        return;
    }
    logPass(kName);
}

// Test 19: Makeup-gain round-trip. Measure a signal, apply makeup = target -
// measured, re-measure → target (±tol). Validates measurement + gain arithmetic.
static auto testLoudnessMakeupRoundTrip() -> void
{
    static const char* const kName = "Loudness_MakeupRoundTrip";
    constexpr double kTarget = -14.0;

    LufsMeter pass1;
    pass1.prepare(TestConstants::kSampleRate48k);
    feedStereoSine(pass1, -20.0, 1000.0, 15.0, TestConstants::kSampleRate48k);
    const double measured = pass1.integratedLufs();

    const double makeupDb = kTarget - measured;
    const double gain = std::pow(10.0, makeupDb / 20.0);

    // Re-measure the same signal scaled by the makeup gain.
    LufsMeter pass2;
    pass2.prepare(TestConstants::kSampleRate48k);
    feedStereoSine(
        pass2, -20.0 + (20.0 * std::log10(gain)), 1000.0, 15.0, TestConstants::kSampleRate48k);
    const double remeasured = pass2.integratedLufs();
    if (std::abs(remeasured - kTarget) > kLufsTol)
    {
        std::ostringstream oss;
        oss << "after +makeup, expected " << kTarget << " LUFS, got " << remeasured;
        logFail(kName, oss.str());
        return;
    }
    logPass(kName);
}

// Test: the shared TruePeakKernel (S10.8 PR E — now also the METER path's detector)
// recovers the inter-sample peak of a quarter-rate sine sampled at ±45° — the classic
// ISP case: every SAMPLE lands at A·sin(45°) ≈ 0.7071·A, so a sample-peak meter
// under-reads by 3.01 dB while the true peak is A. Budget 0.35 dB (the same
// interpolator-gap class the libebur128 oracle uses).
static auto testLoudnessTruePeakKernelInterSample() -> void
{
    static const char* const kName = "Loudness_TruePeakKernel_InterSample";
    using namespace AdaptiveSound::TruePeakKernel;

    Coefficients coeffs{};
    computeCoefficients(coeffs);

    constexpr double kAmp = 0.5; // −6.02 dBTP true peak
    constexpr double kTruePeakDb = -6.0206;
    History hist{};
    double maxIsp = 0.0;
    double maxSample = 0.0;
    for (uint32_t n = 0U; n < 4800U; ++n)
    {
        // fs/4 sine, +45° phase: samples alternate ±kAmp·0.7071 exactly between peaks.
        const double s = kAmp
            * std::sin((std::numbers::pi / 2.0 * static_cast<double>(n)) + (std::numbers::pi / 4.0));
        for (uint32_t k = kNumTaps - 1U; k > 0U; --k)
        {
            hist[k] = hist[k - 1U];
        }
        hist[0] = s;
        maxSample = std::max(maxSample, std::abs(s));
        maxIsp = std::max(maxIsp, phasePeak(hist, coeffs));
    }

    const double ispDb = 20.0 * std::log10(maxIsp);
    const double sampleDb = 20.0 * std::log10(maxSample);
    // The sample grid must actually miss the crest (the premise of the test)…
    if (sampleDb > kTruePeakDb - 2.5)
    {
        std::ostringstream oss;
        oss << "test premise broken: sample peak " << sampleDb << " dB is too close to the crest";
        logFail(kName, oss.str());
        return;
    }
    // …and the kernel must recover it.
    if (std::abs(ispDb - kTruePeakDb) > 0.35)
    {
        std::ostringstream oss;
        oss << "true peak: expected " << kTruePeakDb << " dBTP, kernel read " << ispDb
            << " (sample peak " << sampleDb << ")";
        logFail(kName, oss.str());
        return;
    }
    logPass(kName);
}

// The C-ABI surface under test below (the harness compiles LoudnessMeterBridge.cpp).
#include "../Sources/AudioDSP/include/DeviceBridge.h"

// Test: the C-ABI meter bridge end-to-end (S10.8 PR E break-it rider) — the tap-thread
// path the kernel test above does NOT cover: per-sample shift-register continuity across
// buffer boundaries, the MONO aliasing path (right == nullptr), and the dBTP mapping.
// Same fs/4 +45° signal: the bridge's truePeakDb must recover −6.02 dBTP even though
// every sample the bridge sees is 3 dB below the crest.
static auto testLoudnessMeterBridgeTruePeak() -> void
{
    static const char* const kName = "Loudness_MeterBridge_TruePeak";
    void* meter = loudnessMeterCreate(TestConstants::kSampleRate48k);
    if (meter == nullptr)
    {
        logFail(kName, "loudnessMeterCreate returned null");
        return;
    }

    constexpr double kAmp = 0.5; // −6.02 dBTP true peak
    constexpr double kTruePeakDb = -6.0206;
    constexpr uint32_t kChunk = 512U; // multiple buffers → history must carry across calls
    std::array<float, kChunk> buf{};
    uint32_t n = 0U;
    for (uint32_t chunk = 0U; chunk < 8U; ++chunk)
    {
        for (uint32_t i = 0U; i < kChunk; ++i, ++n)
        {
            buf[i] = static_cast<float>(
                kAmp
                * std::sin((std::numbers::pi / 2.0 * static_cast<double>(n))
                           + (std::numbers::pi / 4.0)));
        }
        loudnessMeterAddStereo(meter, buf.data(), nullptr, kChunk); // MONO path
    }

    const CLoudnessReadout out = loudnessMeterRead(meter);
    loudnessMeterDestroy(meter);

    // Decay headroom: the peak recurs every 4 samples, so per-buffer decay (0.85) never
    // erodes the latch below the budget within a run this dense.
    if (std::abs(out.truePeakDb - kTruePeakDb) > 0.4)
    {
        std::ostringstream oss;
        oss << "bridge true peak: expected " << kTruePeakDb << " dBTP, read " << out.truePeakDb;
        logFail(kName, oss.str());
        return;
    }
    logPass(kName);
}

// ---------------------------------------------------------------------------
// Loudness_WorkersSleepWhileIdle (council C-46 / KI-UI-03; DSP-09): the analysis workers — the
// normaliser's meter (LoudnessModule) and the causal loudness estimate (CausalLoudnessTap) — sleep
// while no audio reaches them, and wake for the next block. Nothing reaches them while playback is
// paused (the engine stops); the normaliser is fed only while leveling is on and off the bit-perfect
// path, the causal tap only while its estimate runs. Before R1.1 they polled: the normaliser every 5 ms (200 wake-ups a second), the causal tap
// every 50 ms (10 ms with an estimate running), for the AU's whole life. Wake-ups are counted as the
// process's context switches (getrusage), what the battery sees; the test thread's own sleep is one.
// ---------------------------------------------------------------------------
static auto testLoudnessWorkersSleepWhileIdle() -> void
{
    static const char* const kName = "Loudness_WorkersSleepWhileIdle";
    constexpr uint32_t kSR = TestConstants::kSampleRate48k;
    constexpr uint32_t kBlock = TestConstants::kFrames512;
    // A parked worker wakes for nothing; the margin is the sanitizers' own background threads.
    constexpr long kMaxIdleWakes = 10;
    const auto contextSwitches = []
    {
        rusage usage{};
        getrusage(RUSAGE_SELF, &usage);
        return usage.ru_nvcsw + usage.ru_nivcsw;
    };
    // Let the workers drain what they were handed and settle (a worker naps for 200 ms before it
    // parks: longer than any render interval), then count 300 ms of idle.
    const auto idleWakes = [&]
    {
        std::this_thread::sleep_for(std::chrono::milliseconds(350));
        const long before = contextSwitches();
        std::this_thread::sleep_for(std::chrono::milliseconds(300));
        return contextSwitches() - before;
    };
    // `seconds` of a 1 kHz tone at `amplitude`, block by block, about as fast as a render thread
    // delivers it (the rings hold ~680 ms; a pause every 10 blocks lets the workers keep up).
    const auto play =
        [](const std::function<void(TestABL&)>& process, double seconds, float amplitude)
    {
        TestABL block(kBlock);
        const auto blocks = static_cast<uint32_t>(seconds * kSR / kBlock);
        uint64_t n = 0U;
        for (uint32_t b = 0U; b < blocks; ++b)
        {
            for (uint32_t i = 0U; i < kBlock; ++i, ++n)
            {
                block.left[i] =
                    amplitude * std::sin(2.0F * std::numbers::pi_v<float> * 1000.0F *
                                         static_cast<float>(n) / static_cast<float>(kSR));
                block.right[i] = block.left[i];
            }
            process(block);
            if (b % 10U == 9U)
            {
                std::this_thread::sleep_for(std::chrono::milliseconds(5));
            }
        }
    };

    std::string fail;
    std::string counts;
    {
        // The normaliser measuring, then paused, then playing again.
        LoudnessModule module;
        module.initialize(kSR, kBlock);
        LoudnessParams params{};
        params.enabled = 1U;
        const auto measure = [&](TestABL& block)
        { module.process(params, MultichannelView::fromABL(block.abl(), kBlock)); };
        play(measure, 0.5, 0.1F);
        const long paused = idleWakes();
        counts += std::format(" normaliser paused {};", paused);
        if (paused > kMaxIdleWakes)
        {
            fail +=
                std::format("\n  the normaliser's worker woke {} times in 300 ms of pause", paused);
        }
        play(measure, 1.0, 0.316F); // 10 dB louder: the worker must wake and measure it
        std::this_thread::sleep_for(std::chrono::milliseconds(100));
        const float momentary = module.measuredLufsMomentary();
        if (!(momentary > -14.0F))
        {
            fail += std::format(
                "\n  after the pause the normaliser read {:.1f} LUFS momentary, not the louder "
                "tone (≈ −10.7)",
                momentary);
        }
    }
    {
        // A kernel with leveling off (the faithful default) and no causal estimate: neither worker
        // is fed while it plays.
        DSPKernel kernel;
        kernel.initialize(kSR, kBlock);
        kernel.publishTargetState(makeIdentityState());
        const auto render = [&](TestABL& block) { kernel.process(block.abl(), kBlock); };
        play(render, 0.5, 0.1F);
        const long bitPerfect = idleWakes();
        counts += std::format(" kernel at rest {};", bitPerfect);
        if (bitPerfect > kMaxIdleWakes)
        {
            fail += std::format("\n  a kernel at rest woke {} times in 300 ms", bitPerfect);
        }
        // A causal estimate started while nothing plays waits for audio, then analyses it.
        kernel.startCausalLoudness([](const std::shared_ptr<const TrackLoudnessProfile>&) {});
        const long waiting = idleWakes();
        counts += std::format(" causal estimate waiting {}", waiting);
        if (waiting > kMaxIdleWakes)
        {
            fail += std::format("\n  a causal estimate waiting for audio woke {} times in 300 ms",
                                waiting);
        }
        play(render, 1.0, 0.1F);
        std::this_thread::sleep_for(std::chrono::milliseconds(100));
        const uint64_t fed = kernel.causalLoudnessFedFrames();
        kernel.stopCausalLoudness();
        if (fed < kSR / 2U)
        {
            fail += std::format("\n  the causal estimate analysed {} frames of 1 s of audio", fed);
        }
    }
    logInfo(std::format("[info] {}: context switches in 300 ms of idle —{}\n", kName, counts));
    if (!fail.empty())
    {
        logFail(kName, "the analysis workers do not sleep while idle:" + fail);
        return;
    }
    logPass(kName);
}
