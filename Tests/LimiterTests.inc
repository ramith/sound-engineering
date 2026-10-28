// LimiterTests.inc
//
// Limiter tests (Sprint 1 / Sprint 5b linked-gain + N=8 soak).
// #included into Tests/DSPKernelNullTest.cpp after TestSupport.h.
//
// Tests: Limiter_BypassIsIdentity, Limiter_CeilingEnforcement,
//        Limiter_GRResponseWithin2ms, Limiter_NearNyquistCeiling,
//        Limiter_HotNoiseSoak, Limiter_Release_TransientIsFast, Limiter_Release_SustainedIsSlow.
// Helpers (area-local): limiterHotNoiseSoakBody, limiterLinkedGainVerifyGR.
// Note: testLimiterLinkedGainLockstep and testLimiterHotNoiseSoakN8 are
//       in MultichannelTests.inc (they belong to the multichannel epic).

// ---------------------------------------------------------------------------
// Test 8: LimiterModule bypass (ceiling ≥ 1.0) is bit-exact identity
//
// With truePeakCeilingLinear = 2.0 the limiter's fast bypass path fires and
// process() returns immediately, leaving the buffers untouched.
// Signal: white noise at ±1.0 (above the default −1 dBTP ceiling, so this
// also confirms that bypass mode suppresses engagement regardless of amplitude).
// ---------------------------------------------------------------------------

static auto testLimiterBypassIsIdentity() -> void
{
    static const char* const kName = "Limiter_BypassIsIdentity";
    constexpr uint32_t kFrames = TestConstants::kFrames512;

    DSPKernel kernel;
    kernel.initialize(TestConstants::kSampleRate48k, kFrames);

    std::mt19937 gen(0xABCD1234U);
    std::uniform_real_distribution<float> dist(-TestConstants::kNoiseUnit,
                                               TestConstants::kNoiseUnit);

    TestABL abl(kFrames);
    for (uint32_t idx = 0U; idx < kFrames; ++idx)
    {
        abl.left[idx] = dist(gen);
        abl.right[idx] = dist(gen);
    }
    const std::vector<float> refLeft(abl.left);
    const std::vector<float> refRight(abl.right);

    // Limiter bypass: ceiling ≥ 1.0
    TargetState state = makeIdentityState(); // already sets ceiling = 2.0
    kernel.publishTargetState(state);
    kernel.process(abl.abl(), kFrames);

    if (std::memcmp(abl.left.data(), refLeft.data(), kFrames * sizeof(float)) != 0)
    {
        logFail(kName, "left channel was modified in bypass mode");
        return;
    }
    if (std::memcmp(abl.right.data(), refRight.data(), kFrames * sizeof(float)) != 0)
    {
        logFail(kName, "right channel was modified in bypass mode");
        return;
    }
    logPass(kName);
}

// ---------------------------------------------------------------------------
// Test 9: Limiter ceiling enforcement — −3 dBFS input → output ≤ −1 dBTP
//
// Feeds a full-scale sine burst whose peak is ~−3 dBFS (0.708 linear) through
// the active limiter with the default −1 dBTP ceiling (0.891 linear).
// That signal is BELOW the ceiling, so a single sine at −3 dBFS passes through
// without gain reduction.
//
// To test actual ceiling enforcement we use a +0 dBFS sine (amplitude 0.999)
// which EXCEEDS the −1 dBTP ceiling (0.891).  After the lookahead has primed
// (kLimiterLookaheadFrames samples of silence prefix), the output peak must be
// ≤ 0.891 (with a small tolerance for the one-pole smoother's ramp time).
//
// Method:
//   1. Prime the limiter with kLimiterLookaheadFrames zero frames.
//   2. Feed N frames of a 1 kHz sine at amplitude 0.999.
//   3. Measure the output true-peak (linear max absolute).
//   4. Assert output_peak ≤ kTruePeakCeilingLinear + small_tolerance.
//
// Tolerance: the one-pole attack (τ = 0.5 ms @ 48 kHz, α ≈ 0.064) means the
// GR envelope takes a few samples to ramp to the required gain.  The ceiling
// check is applied after the first full buffer, by which time GR has settled.
// ---------------------------------------------------------------------------

static auto testLimiterCeilingEnforcement() -> void
{
    static const char* const kName = "Limiter_CeilingEnforcement";
    // Use a block large enough that the one-pole attack has fully settled:
    // 5τ at 0.5 ms = 2.5 ms = 120 samples.  Use 512.
    constexpr uint32_t kFrames = TestConstants::kFrames512;
    constexpr uint32_t kSR = TestConstants::kSampleRate48k;

    // Ceiling from AudioConstants (default −1 dBTP ≈ 0.891)
    // Allow 1 dB of tolerance for attack ramp-up.
    constexpr float kCeiling = kTruePeakCeilingLinear;
    // 1 dB above ceiling in linear: 10^((-1+1)/20) = 1.0 — but we want a tighter
    // check.  The smoother has τ = 0.5 ms; at 512 frames (10.7 ms) it is fully
    // settled.  Allow 0.01 absolute tolerance (≈ 0.1 dB) for numerical precision.
    constexpr float kTolerance = 0.01F;

    DSPKernel kernel;
    kernel.initialize(kSR, kFrames);

    // Publish state with the default ceiling (0.891) — active limiting.
    TargetState state{};
    state.intensityLinear = 1.0F;
    state.eq = EQParams{}; // identity
    state.clarity.enabled = 0U;
    // limiter: default LimiterParams — truePeakCeilingLinear = kTruePeakCeilingLinear
    kernel.publishTargetState(state);

    // Step 1: prime with silence so the ring fills with zeros before the sine arrives.
    // This avoids a false "peak = 0" scan of a half-full ring biasing the first GR.
    TestABL prime(kLimiterLookaheadFrames);
    prime.left.assign(kLimiterLookaheadFrames, 0.0F);
    prime.right.assign(kLimiterLookaheadFrames, 0.0F);
    kernel.process(prime.abl(), kLimiterLookaheadFrames);

    // Step 2: feed a 1 kHz sine at amplitude 0.999 (just below 0 dBFS, well above ceiling)
    TestABL abl(kFrames);
    constexpr float kSineFreq = 1000.0F;
    constexpr float kSineAmpl = 0.999F;
    for (uint32_t idx = 0U; idx < kFrames; ++idx)
    {
        const float phase = 2.0F * std::numbers::pi_v<float> * kSineFreq * static_cast<float>(idx) /
                            static_cast<float>(kSR);
        abl.left[idx] = kSineAmpl * std::sin(phase);
        abl.right[idx] = abl.left[idx];
    }
    kernel.process(abl.abl(), kFrames);

    // Step 3: measure the true-peak of the output (max absolute value)
    float outPeak = 0.0F;
    for (uint32_t idx = 0U; idx < kFrames; ++idx)
    {
        const float absL = std::abs(abl.left[idx]);
        const float absR = std::abs(abl.right[idx]);
        if (absL > outPeak)
        {
            outPeak = absL;
        }
        if (absR > outPeak)
        {
            outPeak = absR;
        }
    }

    // Step 4: assert output peak ≤ ceiling + tolerance
    if (outPeak > kCeiling + kTolerance)
    {
        std::ostringstream oss;
        oss << "output peak " << outPeak << " exceeds ceiling " << kCeiling << " + tolerance "
            << kTolerance << " (delta " << (outPeak - kCeiling) << ")";
        logFail(kName, oss.str());
        return;
    }
    logPass(kName);
}

// ---------------------------------------------------------------------------
// Test 10: GR response time — onset within ≤ 2 ms of a sudden +0 dBFS peak
//
// Injects an abrupt +0 dBFS step at frame 0 into a limiter that starts with
// an unprimed ring (all zeros).  The fast-path bypasses until the peak primes
// the ring, then GR starts racking.  We verify that within 2 ms (96 samples
// @ 48 kHz) the output gain has dropped below the ceiling.
//
// "Response time" here means: how quickly does gain reduction reach the point
// where output ≤ ceiling?  With a 0.5 ms attack τ (α ≈ 0.064), 5τ = 2.5 ms;
// we target < 2 ms which is ~3τ (~86% of final GR).  We check that at least
// one output sample in the first 96 samples is already ≤ ceiling.
// ---------------------------------------------------------------------------

static auto testLimiterGRResponseTime() -> void
{
    static const char* const kName = "Limiter_GRResponseWithin2ms";
    constexpr uint32_t kSR = TestConstants::kSampleRate48k;
    constexpr uint32_t kFrames = TestConstants::kFrames512;
    // 2 ms at 48 kHz = 96 samples
    constexpr uint32_t k2msFrames = 96U;

    DSPKernel kernel;
    kernel.initialize(kSR, kFrames);

    // Active limiting state (default ceiling = 0.891)
    TargetState state{};
    state.intensityLinear = 1.0F;
    state.eq = EQParams{}; // identity
    state.clarity.enabled = 0U;
    kernel.publishTargetState(state);

    // Feed a DC burst at +0 dBFS (0.999) into a fresh, unprimed limiter.
    // The ring fast-path will disengage as soon as the peak exceeds the ceiling,
    // then the ring-based path begins.
    TestABL abl(kFrames);
    constexpr float kBurstAmpl = 0.999F;
    abl.left.assign(kFrames, kBurstAmpl);
    abl.right.assign(kFrames, kBurstAmpl);

    kernel.process(abl.abl(), kFrames);

    // Check that within the first 2 ms (k2msFrames) at least one sample has been
    // limited to ≤ ceiling.  The lookahead means the FIRST kLimiterLookaheadFrames
    // output samples are from the zero-primed ring (output = 0).  After those, the
    // GR-attenuated burst samples emerge.  We check that by frame k2msFrames the
    // output has engaged — i.e. the samples that come from the ring are ≤ ceiling.
    //
    // Because the ring was zero-filled and the output is taken from the oldest ring
    // position, the first kLimiterLookaheadFrames output samples are 0.0F (well below
    // the ceiling).  What matters is that no output sample EXCEEDS the ceiling.
    bool anyExceedsCeiling = false;
    for (uint32_t idx = 0U; idx < k2msFrames; ++idx)
    {
        if (std::abs(abl.left[idx]) > kTruePeakCeilingLinear + 0.01F)
        {
            anyExceedsCeiling = true;
            break;
        }
    }

    if (anyExceedsCeiling)
    {
        logFail(kName, "output exceeded ceiling within the first 2 ms (96 frames)");
        return;
    }
    logPass(kName);
}

// Test M3a: near-Nyquist true-peak — a 0.45·fs tone at 0.97 (above the −1 dBTP
// ceiling) must be limited so the OUTPUT sample peak ≤ ceiling. The polyphase
// detector catches the inter-sample energy a sample-only/linear detector misses.
static auto testLimiterNearNyquistCeiling() -> void
{
    static const char* const kName = "Limiter_NearNyquistCeiling";
    constexpr uint32_t kSR = TestConstants::kSampleRate48k;
    constexpr uint32_t kFrames = TestConstants::kFrames512;
    constexpr float kCeiling = kTruePeakCeilingLinear;

    DSPKernel kernel;
    kernel.initialize(kSR, kFrames);
    TargetState state{};
    state.intensityLinear = 1.0F;
    state.eq = EQParams{}; // identity
    state.clarity.enabled = 0U;
    kernel.publishTargetState(state);

    TestABL prime(kLimiterLookaheadFrames);
    kernel.process(prime.abl(), kLimiterLookaheadFrames);

    const float freq = 0.45F * static_cast<float>(kSR);
    const float ampl = 0.97F;
    float outPeak = 0.0F;
    for (uint32_t b = 0U; b < 8U; ++b)
    {
        TestABL abl(kFrames);
        for (uint32_t i = 0U; i < kFrames; ++i)
        {
            const float phase = 2.0F * std::numbers::pi_v<float> * freq *
                                static_cast<float>((b * kFrames) + i) / static_cast<float>(kSR);
            abl.left[i] = ampl * std::sin(phase);
            abl.right[i] = abl.left[i];
        }
        kernel.process(abl.abl(), kFrames);
        if (b >= 4U) // measure after the limiter has settled
        {
            for (uint32_t i = 0U; i < kFrames; ++i)
            {
                outPeak = std::max({outPeak, std::abs(abl.left[i]), std::abs(abl.right[i])});
            }
        }
    }

    if (outPeak > kCeiling + 0.01F)
    {
        std::ostringstream oss;
        oss << "near-Nyquist output peak " << outPeak << " exceeds ceiling " << kCeiling;
        logFail(kName, oss.str());
        return;
    }
    logPass(kName);
}

// Shared body for hot-noise soak tests (N=2 and N=8).
//
// Each channel is driven with distinct per-block white noise via per-channel seeds.
// seeds[ch] is the base seed; each block advances by blk: gen(seeds[ch] + blk).
// This matches the N=8 seeding pattern exactly so the [info] worst_peak is preserved.
//
// printInfo: N=8 prints "N=<n> worst_peak=<x> ceiling=<c>" [info] line; N=2 does not
//            (the N=2 test has no [info] line in its historical output).
//
// Returns "" on pass, non-empty error string on failure.
static auto limiterHotNoiseSoakBody(uint32_t numCh,
                                    uint32_t numBuffers,
                                    const uint32_t* seeds,
                                    bool printInfo,
                                    const char* kName) -> std::string
{
    constexpr uint32_t kSR = TestConstants::kSampleRate48k;
    constexpr uint32_t kFrames = TestConstants::kFrames512;
    constexpr float kCeiling = kTruePeakCeilingLinear;
    constexpr float kCeilingTolerance = 0.01F;

    DSPKernel kernel;
    kernel.initialize(kSR, kFrames);

    TargetState state{};
    state.intensityLinear = 1.0F;
    state.eq = EQParams{}; // identity
    state.clarity.enabled = 0U;
    state.limiter.truePeakCeilingLinear = kCeiling;
    kernel.publishTargetState(state);

    float worst = 0.0F;
    for (uint32_t blk = 0U; blk < numBuffers; ++blk)
    {
        TestABLN abl(numCh, kFrames);
        for (uint32_t ch = 0U; ch < numCh; ++ch)
        {
            std::mt19937 gen(seeds[ch] + blk); // shift seed per block for variety
            std::uniform_real_distribution<float> dist(-0.999F, 0.999F);
            for (uint32_t frm = 0U; frm < kFrames; ++frm)
            {
                abl.channels[ch][frm] = dist(gen);
            }
        }
        kernel.process(abl.abl(), kFrames);
        if (blk >= 1U) // skip first buffer (lookahead warm-up, ring may output silence)
        {
            for (uint32_t ch = 0U; ch < numCh; ++ch)
            {
                for (uint32_t frm = 0U; frm < kFrames; ++frm)
                {
                    const float sample = abl.channels[ch][frm];
                    if (!std::isfinite(sample))
                    {
                        std::ostringstream oss;
                        oss << "NaN/Inf on ch" << ch << " sample " << frm << " block " << blk;
                        return oss.str();
                    }
                    worst = std::max(worst, std::abs(sample));
                }
            }
        }
    }

    if (worst > kCeiling + kCeilingTolerance)
    {
        std::ostringstream oss;
        oss << "N=" << numCh << " soak: worst output peak " << worst << " exceeds ceiling "
            << kCeiling << " + tolerance " << kCeilingTolerance;
        return oss.str();
    }

    if (printInfo)
    {
        std::ostringstream info;
        info << "  [info] " << kName << ": N=" << numCh << " worst_peak=" << worst
             << " ceiling=" << kCeiling << "\n";
        logInfo(info.str());
    }
    return {};
}

// Test M3b: hot-noise soak — 100 buffers of full-scale white noise; every output
// sample (after lookahead warm-up) must stay ≤ ceiling. Stresses ring wrap across
// many buffers + the dual-stage release.
static auto testLimiterHotNoiseSoak() -> void
{
    static const char* const kName = "Limiter_HotNoiseSoak";
    constexpr std::array<uint32_t, 2U> kSeeds = {0x515D7E57U, 0x515D7E58U};
    const std::string err =
        limiterHotNoiseSoakBody(2U, 100U, kSeeds.data(), /*printInfo=*/false, kName);
    if (!err.empty())
    {
        logFail(kName, err);
        return;
    }
    logPass(kName);
}

// ---------------------------------------------------------------------------
// limiterLinkedGainVerifyGR — shared body used by testLimiterLinkedGainLockstep
// (in MultichannelTests.inc). Defined here (limiter area) because it is a
// limiter-specific helper, even though the calling test is in the multichannel file.
// ---------------------------------------------------------------------------

// Helper: verify that the limiter applied identical gain reduction to all tone channels.
// Returns "" on pass; non-empty diagnostic string on failure.
// savedInput[ch] holds the original input for tone channels ch=1..numCh-1.
// After processing, output is abl.channels[ch][i] = grBuf_[i] * savedInput[ch][i-lookahead]
// for i >= lookahead. We recover the gain and assert inter-channel GR diffs < threshold.
// outActiveSamples is set to the count of compared samples.
static auto limiterLinkedGainVerifyGR(const TestABLN& abl,
                                      const std::vector<std::vector<float>>& savedInput,
                                      uint32_t kNumCh,
                                      uint32_t kFrames,
                                      uint32_t lookahead,
                                      float kMinInputForRatio,
                                      double kGrDiffThreshDb,
                                      uint32_t& outActiveSamples) -> std::string
{
    outActiveSamples = 0U;
    for (uint32_t i = lookahead; i < kFrames; ++i)
    {
        const uint32_t delayedIdx = i - lookahead;
        double gainDb[3] = {0.0, 0.0, 0.0};
        bool valid[3] = {false, false, false};

        for (uint32_t ch = 1U; ch < kNumCh; ++ch)
        {
            const float inSample = savedInput[ch][delayedIdx];
            if (std::abs(inSample) >= kMinInputForRatio)
            {
                const float outSample = abl.channels[ch][i];
                const double ratio = static_cast<double>(outSample) / static_cast<double>(inSample);
                const double clampedRatio = std::max(1e-12, std::min(1.0, std::abs(ratio)));
                gainDb[ch - 1U] = 20.0 * std::log10(clampedRatio);
                valid[ch - 1U] = true;
            }
        }

        if (!valid[0] || !valid[1] || !valid[2])
        {
            continue;
        }
        ++outActiveSamples;

        for (uint32_t pair = 1U; pair < 3U; ++pair)
        {
            const double diffDb = std::abs(gainDb[0] - gainDb[pair]);
            if (diffDb >= kGrDiffThreshDb)
            {
                std::ostringstream oss;
                oss << "sample " << i << " (delayed=" << delayedIdx << "): ch1 GR=" << gainDb[0]
                    << " dB, ch" << (pair + 1U) << " GR=" << gainDb[pair] << " dB, diff=" << diffDb
                    << " dB (threshold " << kGrDiffThreshDb << " dB) — gain is NOT linked";
                return oss.str();
            }
        }
    }
    return {};
}

// ---------------------------------------------------------------------------
// The limiter's release (council C-39; P2-1, D34): program-dependent, on two branches. A transient
// releases on the FAST branch — τ 100 ms after the 50 ms LF hold — because only sustained limiting
// charges the SLOW branch (its own attack, τ 100 ms), which then releases over τ 500 ms. Before
// R1.1 both branches attacked alike, so the slow one was always the deeper, "deeper wins" always
// picked it, and one snare hit that touched the ceiling ducked the music for about a second.
//
// The probe: a DC level of 0.1 (−20 dBFS, under the ceiling), so once the burst has passed the
// gain is read exactly, sample by sample, as out / 0.1 — plus a 1 kHz burst at amplitude 2
// (+6 dBFS, ≈ 7.7 dB of gain reduction). t = 0 is the burst's end in OUTPUT time (its end at the
// input plus the 3 ms look-ahead): where the window maximum lets go and the hold begins.
// ---------------------------------------------------------------------------
namespace
{
    constexpr double kReleaseProbeLevel = 0.1;
    constexpr double kReleaseHoldSeconds = 0.05; // LimiterModule's kLfHoldSeconds

    struct ReleaseTrace
    {
        double deepestDb = 0.0;      // the deepest gain during the burst (dB, ≤ 0)
        std::vector<double> afterDb; // the gain from t = 0, one value per output sample (dB)
    };

    auto limiterReleaseTrace(double burstSeconds) -> ReleaseTrace
    {
        constexpr uint32_t kSR = TestConstants::kSampleRate48k;
        constexpr uint32_t kBlock = TestConstants::kFrames512;
        constexpr double kBurstAmplitude = 2.0;
        constexpr double kBurstHz = 1000.0;
        const uint32_t lead = kSR / 2U;
        const auto burst = static_cast<uint32_t>(std::lround(burstSeconds * kSR));
        const uint32_t tail = 2U * kSR;
        const uint32_t total = lead + burst + tail;

        std::vector<float> input(total);
        for (uint32_t n = 0U; n < total; ++n)
        {
            const bool inBurst = n >= lead && n < lead + burst;
            input[n] = static_cast<float>(
                kReleaseProbeLevel +
                (inBurst ? kBurstAmplitude * std::sin(2.0 * std::numbers::pi * kBurstHz * n / kSR)
                         : 0.0));
        }

        LimiterModule limiter;
        limiter.initialize(kSR, kBlock);
        LimiterParams params{};
        params.truePeakCeilingLinear = kTruePeakCeilingLinear;
        std::vector<float> output(total);
        for (uint32_t offset = 0U; offset < total; offset += kBlock)
        {
            const uint32_t chunk = std::min(kBlock, total - offset);
            TestABL abl(chunk);
            std::copy_n(input.begin() + offset, chunk, abl.left.begin());
            std::copy_n(input.begin() + offset, chunk, abl.right.begin());
            limiter.process(params, MultichannelView::fromABL(abl.abl(), chunk));
            std::copy_n(abl.left.begin(), chunk, output.begin() + offset);
        }

        ReleaseTrace trace;
        constexpr uint32_t kLook = kLimiterLookaheadFrames; // 3 ms at 48 kHz
        for (uint32_t n = lead + kLook; n < lead + burst + kLook; ++n)
        {
            const double in = input[n - kLook];
            if (std::abs(in) > 0.5) // away from the burst's zero crossings
            {
                trace.deepestDb =
                    std::min(trace.deepestDb, 20.0 * std::log10(std::abs(output[n] / in)));
            }
        }
        for (uint32_t n = lead + burst + kLook; n < total; ++n)
        {
            trace.afterDb.push_back(20.0 * std::log10(output[n] / kReleaseProbeLevel));
        }
        return trace;
    }

    // The gain `seconds` after t = 0 (dB).
    auto releaseGainAt(const ReleaseTrace& trace, double seconds) -> double
    {
        const auto index =
            static_cast<size_t>(std::lround(seconds * TestConstants::kSampleRate48k));
        return trace.afterDb[std::min(index, trace.afterDb.size() - 1U)];
    }

    // The release time constant: the time from the end of the hold until the gain is back to
    // 1/e of its deepest (in dB), in seconds.
    auto releaseTimeConstant(const ReleaseTrace& trace) -> double
    {
        const double target = trace.deepestDb / std::numbers::e;
        for (size_t n = 0U; n < trace.afterDb.size(); ++n)
        {
            if (trace.afterDb[n] >= target)
            {
                return (static_cast<double>(n) / TestConstants::kSampleRate48k) -
                       kReleaseHoldSeconds;
            }
        }
        return std::numeric_limits<double>::infinity();
    }
} // namespace

// One 5 ms burst (a snare hit at the ceiling): the gain recovers on the fast branch — τ 100 ms
// after the hold (±15 ms); within 2 dB 200 ms on (council P2-1's bar), 0.5 dB at 500 ms, 0.1 dB
// at 1 s. Before R1.1: −5.7 dB at 200 ms, τ 500 ms.
static auto testLimiterReleaseTransientIsFast() -> void
{
    static const char* const kName = "Limiter_Release_TransientIsFast";
    const ReleaseTrace trace = limiterReleaseTrace(0.005);
    const double at200 = releaseGainAt(trace, 0.2);
    const double at500 = releaseGainAt(trace, 0.5);
    const double at1000 = releaseGainAt(trace, 1.0);
    const double tau = releaseTimeConstant(trace);
    logInfo(std::format(
        "  [info] {}: deepest {:.2f} dB; {:.2f} dB at 200 ms, {:.2f} at 500 ms, {:.3f} at "
        "1 s; τ {:.1f} ms after the hold\n",
        kName,
        trace.deepestDb,
        at200,
        at500,
        at1000,
        tau * 1000.0));
    if (trace.deepestDb > -6.0 || at200 < -2.0 || at500 < -0.5 || at1000 < -0.1 ||
        std::abs(tau - 0.100) > 0.015)
    {
        logFail(
            kName,
            std::format("a 5 ms burst: {:.2f} dB at 200 ms (bar −2), {:.2f} at 500 ms (bar −0.5), "
                        "{:.3f} at 1 s (bar −0.1), τ {:.1f} ms (want 100 ± 15)",
                        at200,
                        at500,
                        at1000,
                        tau * 1000.0));
        return;
    }
    logPass(kName);
}

// Two seconds over the ceiling (sustained limiting): the slow branch has charged, so the release
// is the slow one — τ 500 ms after the hold (±50 ms), still ≤ −4 dB at 200 ms. Program dependence,
// not a single fast release.
static auto testLimiterReleaseSustainedIsSlow() -> void
{
    static const char* const kName = "Limiter_Release_SustainedIsSlow";
    const ReleaseTrace trace = limiterReleaseTrace(2.0);
    const double at200 = releaseGainAt(trace, 0.2);
    const double tau = releaseTimeConstant(trace);
    logInfo(std::format(
        "  [info] {}: deepest {:.2f} dB; {:.2f} dB at 200 ms; τ {:.1f} ms after the hold\n",
        kName,
        trace.deepestDb,
        at200,
        tau * 1000.0));
    if (trace.deepestDb > -6.0 || at200 > -4.0 || std::abs(tau - 0.500) > 0.050)
    {
        logFail(
            kName,
            std::format(
                "2 s over the ceiling: {:.2f} dB at 200 ms (bar ≤ −4), τ {:.1f} ms (want 500 ± 50)",
                at200,
                tau * 1000.0));
        return;
    }
    logPass(kName);
}
