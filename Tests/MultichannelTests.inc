// MultichannelTests.inc
//
// Multichannel epic safety net (Sprint 5b S0-M1 through M4), large-buffer
// regression fence, and N-channel BS.1770-5 loudness tests (Gate C/D/E).
// #included into Tests/DSPKernelNullTest.cpp after TestSupport.h.
//
// Tests: GoldenMaster_StereoN2_v1, MultichannelView_Decode,
//        PerChannelIndependence_N4_6_8, EQ_FrequencyResponseAccuracy_N4,
//        EQ_CoefficientSwapNoClick_N4, Limiter_LinkedGainLockstep,
//        Limiter_HotNoiseSoak_N8, Reconfiguration_Stereo_5p1_Stereo,
//        Loudness_Multichannel_BS1770_Weights, ChannelLayout_Decode_GateD,
//        Loudness_DecodedLayout_Weights, Kernel_LargeBuffer_LimiterTailCorrect,
//        Kernel_LargeBuffer_EQGainNoCutoff, Kernel_LargeBuffer_ConsecutiveBuffers.
// Helpers (area-local): perChannelIndependenceForN, limiterHotNoiseSoakBody
//   (declared in LimiterTests.inc), limiterLinkedGainVerifyGR (LimiterTests.inc),
//   largeBufferLimiterTailCheckForSize, bs1770SubcaseXxx, decodedSubcaseXxx,
//   oracle namespace.

// ---------------------------------------------------------------------------
// Multichannel epic safety net (Sprint 5b, S0-M1).
//
// T-C1 GOLDEN MASTER: a bit-exact regression fence for the current STEREO DSP output. A
// deterministic 1 s chirp is processed through a non-trivial state (+6 dB @ 1 kHz EQ boost +
// ACTIVE true-peak limiter), and a 64-bit FNV-1a signature of the L+R output is asserted against
// a committed constant. Any refactor that changes the stereo output (even one ULP) flips the hash.
// This is the fence the whole N-channel migration must never break at N=2. Re-baseline ONLY on a
// deliberate, founder-approved DSP change (see the QA plan). Same-toolchain/arch fence.
//
// T-C2..T-C5 are PENDING placeholders for later milestones (they keep the plan visible without
// failing the gate). They are filled in their target sprint.
// ---------------------------------------------------------------------------

static auto testGoldenMasterStereoN2() -> void
{
    static const char* const kName = "GoldenMaster_StereoN2_v1";
    constexpr uint32_t kSR = TestConstants::kSampleRate48k;
    constexpr uint32_t kChunk = TestConstants::kFrames512;
    constexpr uint32_t kTotal = TestConstants::kTotalFrames1s;
    constexpr float kBoostDb = 6.0F;
    // Committed bit-exact signature of the current stereo output. See header note for re-baseline.
    constexpr uint64_t kGoldenHash = 0xE7267654BA01D315ULL;
    constexpr uint64_t kFnvOffsetBasis = 0xCBF29CE484222325ULL;

    // Deterministic 1 s linear chirp 20 Hz -> 20 kHz, amplitude 0.5 (no RNG).
    std::vector<float> chirp(kTotal);
    for (uint32_t idx = 0U; idx < kTotal; ++idx)
    {
        const float timeSec = static_cast<float>(idx) / static_cast<float>(kSR);
        const float freq =
            TestConstants::kChirpF0 + (TestConstants::kChirpF1 - TestConstants::kChirpF0) *
                                          (timeSec / TestConstants::kChirpDuration);
        chirp[idx] =
            std::sin(2.0F * std::numbers::pi_v<float> * freq * timeSec) * TestConstants::kChirpAmpl;
    }

    // Non-trivial state: +6 dB @ 1 kHz EQ + ACTIVE true-peak limiter (default ceiling < 1.0).
    DSPKernel kernel;
    kernel.initialize(kSR, kChunk);
    TargetState state = makeIdentityState();
    std::array<float, kEqBands> gains{};
    gains[kBand1kHzIndex] = kBoostDb;
    state.eq = EQModuleCoefficients::computeBiquadCascade(gains, static_cast<float>(kSR));
    state.limiter.truePeakCeilingLinear =
        kTruePeakCeilingLinear; // active (overrides identity bypass)
    kernel.publishTargetState(state);

    // Process in 512-frame chunks; capture L and R output.
    std::vector<float> outLeft;
    std::vector<float> outRight;
    outLeft.reserve(kTotal);
    outRight.reserve(kTotal);
    TestABL abl(kChunk);
    uint32_t offset = 0U;
    while (offset < kTotal)
    {
        const uint32_t chunk = std::min(kChunk, kTotal - offset);
        std::memcpy(abl.left.data(), chirp.data() + offset, chunk * sizeof(float));
        std::memcpy(abl.right.data(), chirp.data() + offset, chunk * sizeof(float));
        abl.setFrameCount(chunk);
        kernel.process(abl.abl(), chunk);
        for (uint32_t idx = 0U; idx < chunk; ++idx)
        {
            outLeft.push_back(abl.left[idx]);
            outRight.push_back(abl.right[idx]);
        }
        offset += chunk;
    }

    const uint64_t hash = fnv1aFloats(outRight, fnv1aFloats(outLeft, kFnvOffsetBasis));

    std::ostringstream info;
    info << "  [info] " << kName << ": output hash = 0x" << std::hex << hash << "\n";
    logInfo(info.str());

    if (hash != kGoldenHash)
    {
        std::ostringstream oss;
        oss << "golden-master hash mismatch: got 0x" << std::hex << hash << ", expected 0x"
            << kGoldenHash
            << " (stereo DSP output changed — intended? then re-baseline per QA plan)";
        logFail(kName, oss.str());
        return;
    }
    logPass(kName);
}

// T-C2: MultichannelView is the sole ABL-decode point — unit-test its semantics directly.
// (Bit-exactness of the chain THROUGH the view is already covered by T-C1, which now runs the
// kernel via the MultichannelView path.)
static auto testMultichannelViewDecode() -> void
{
    static const char* const kName = "MultichannelView_Decode";
    constexpr uint32_t kFrames = TestConstants::kFrames512;

    TestABL abl(kFrames);
    const MultichannelView view = MultichannelView::fromABL(abl.abl(), kFrames);

    if (view.channels() != 2U)
    {
        logFail(kName, "expected 2 channels from a stereo ABL");
        return;
    }
    if (view.frames() != kFrames)
    {
        logFail(kName, "frames() did not echo the frame count");
        return;
    }
    if (view.channel(0) != abl.left.data() || view.channel(1) != abl.right.data())
    {
        logFail(kName, "channel pointers do not match the ABL buffers");
        return;
    }
    if (view.channel(2) != nullptr || view.channel(kMaxChannels) != nullptr)
    {
        logFail(kName, "out-of-range channel() must return nullptr");
        return;
    }

    // Null ABL → empty view, no crash.
    const MultichannelView nullView = MultichannelView::fromABL(nullptr, kFrames);
    if (nullView.channels() != 0U || nullView.channel(0) != nullptr)
    {
        logFail(kName, "null ABL must yield an empty view");
        return;
    }
    logPass(kName);
}

// T-C3: Per-channel independence — N-channel EQ does not mix channels.
//
// For each N in {4, 6, 8}: feed channel k a pure sine at a distinct DFT-bin-aligned
// frequency through the kernel with an identity EQ (numBiquads=0, masterGain=1).
// After processing, assert:
//   - The OUTPUT channel k contains energy at its OWN frequency (power > noise floor).
//   - The OUTPUT channel k contains NO energy at any OTHER channel's frequency
//     (cross-channel power ratio < −60 dB relative to the self-channel power).
// This catches channel-swap, crosstalk, and accidental delay-state sharing.
//
// Frequencies are chosen as exact DFT bins at N=kPerChTestFrames samples (bin k has
// frequency k × fs/N), so the Goertzel measurement at each bin captures an integer
// number of cycles — rectangular-window orthogonality makes cross-bin leakage ≈ 0
// (numerical noise floor ~−120 dB), well below the −60 dB threshold. Using non-harmonic
// bins avoids the harmonic-aliasing leakage that would occur at f0, 2f0, 3f0… bins.
//
// Energy is measured with the Goertzel algorithm — O(N) per bin, no heap allocation.
// Reference: Proakis & Manolakis, "Digital Signal Processing", §8.3.

// Shared body for per-channel independence test for a given numCh.
// Returns "" on pass, non-empty on failure.
static auto perChannelIndependenceForN(uint32_t numCh) -> std::string
{
    constexpr uint32_t kFrames = TestConstants::kPerChTestFrames;
    constexpr float kSR = static_cast<float>(TestConstants::kSampleRate48k);
    constexpr float kAmp = TestConstants::kPerChAmplitude;
    constexpr double kXtalkThreshDb = TestConstants::kCrosstalkThresholdDb;

    DSPKernel kernel;
    kernel.initialize(TestConstants::kSampleRate48k, kFrames);
    const TargetState state = makeIdentityState();
    kernel.publishTargetState(state);

    TestABLN abl(numCh, kFrames);
    for (uint32_t ch = 0U; ch < numCh; ++ch)
    {
        const float freq =
            static_cast<float>(TestConstants::kPerChBins[ch]) * kSR / static_cast<float>(kFrames);
        for (uint32_t idx = 0U; idx < kFrames; ++idx)
        {
            abl.channels[ch][idx] = kAmp * std::sin(2.0F * std::numbers::pi_v<float> * freq *
                                                    static_cast<float>(idx) / kSR);
        }
    }
    kernel.process(abl.abl(), kFrames);

    for (uint32_t ch = 0U; ch < numCh; ++ch)
    {
        const float selfFreq =
            static_cast<float>(TestConstants::kPerChBins[ch]) * kSR / static_cast<float>(kFrames);
        const float* outBuf = abl.channels[ch].data();
        const double selfPower = goertzelPower(outBuf, kFrames, selfFreq, kSR);
        if (selfPower <= 0.0)
        {
            std::ostringstream oss;
            oss << "N=" << numCh << " ch" << ch << ": self tone (" << selfFreq
                << " Hz) has zero power after identity EQ";
            return oss.str();
        }
        for (uint32_t otherCh = 0U; otherCh < numCh; ++otherCh)
        {
            if (otherCh == ch)
            {
                continue;
            }
            const float otherFreq = static_cast<float>(TestConstants::kPerChBins[otherCh]) * kSR /
                                    static_cast<float>(kFrames);
            const double crosstalkPower = goertzelPower(outBuf, kFrames, otherFreq, kSR);
            const double ratioDb = 10.0 * std::log10(crosstalkPower / selfPower + 1e-300);
            if (ratioDb > kXtalkThreshDb)
            {
                std::ostringstream oss;
                oss << "N=" << numCh << " ch" << ch << ": crosstalk from ch" << otherCh << " ("
                    << otherFreq << " Hz) at " << ratioDb << " dB (threshold " << kXtalkThreshDb
                    << " dB)";
                return oss.str();
            }
        }
    }
    return {};
}

static auto testPerChannelIndependence() -> void
{
    static const char* const kName = "PerChannelIndependence_N4_6_8";
    constexpr std::array<uint32_t, 3U> kNValues = {
        TestConstants::kNChannels4, TestConstants::kNChannels6, TestConstants::kNChannels8};
    for (const uint32_t numCh : kNValues)
    {
        const std::string err = perChannelIndependenceForN(numCh);
        if (!err.empty())
        {
            logFail(kName, err);
            return;
        }
    }
    logPass(kName);
}

// T-C3b: EQ frequency-response accuracy at N=4.
//
// Boost one band (+6 dB @ 1 kHz) applied identically to all channels. Feed each
// channel the same 1 kHz sine, process through the kernel with the boosted EQ, and
// assert that every channel's output RMS (over the settled second half) is +6 dB ±1 dB
// relative to the flat-EQ baseline. This confirms the SAME coefficient cascade is
// applied to all N channels and that no channel is dropped or misrouted.
static auto testEQFrequencyResponseAccuracyN4() -> void
{
    static const char* const kName = "EQ_FrequencyResponseAccuracy_N4";
    constexpr uint32_t kNumCh = TestConstants::kNChannels4;
    constexpr uint32_t kFrames = TestConstants::kTotalFrames1s;
    constexpr float kSR = static_cast<float>(TestConstants::kSampleRate48k);

    const auto runN4 = [&](const std::array<float, kEqBands>& gains) -> std::vector<double>
    {
        DSPKernel kernel;
        kernel.initialize(TestConstants::kSampleRate48k, kFrames);

        TargetState state = makeIdentityState();
        state.eq = EQModuleCoefficients::computeBiquadCascade(gains, kSR);
        kernel.publishTargetState(state);

        TestABLN abl(kNumCh, kFrames);
        for (uint32_t ch = 0U; ch < kNumCh; ++ch)
        {
            for (uint32_t idx = 0U; idx < kFrames; ++idx)
            {
                abl.channels[ch][idx] =
                    kEqTestAmplitude * std::sin(2.0F * std::numbers::pi_v<float> * kEqTestToneHz *
                                                static_cast<float>(idx) / kSR);
            }
        }
        kernel.process(abl.abl(), kFrames);

        std::vector<double> rmsVals(kNumCh);
        const size_t halfFrame = static_cast<size_t>(kFrames) / 2U;
        for (uint32_t ch = 0U; ch < kNumCh; ++ch)
        {
            rmsVals[ch] = sliceRms(abl.channels[ch], halfFrame, static_cast<size_t>(kFrames));
        }
        return rmsVals;
    };

    std::array<float, kEqBands> flatGains{};
    std::array<float, kEqBands> boostedGains{};
    boostedGains[kBand1kHzIndex] = kEqBoostDb;

    const std::vector<double> flatRms = runN4(flatGains);
    const std::vector<double> boostRms = runN4(boostedGains);

    for (uint32_t ch = 0U; ch < kNumCh; ++ch)
    {
        if (flatRms[ch] <= 0.0)
        {
            logFail(kName, "flat-EQ output was silent on ch" + std::to_string(ch));
            return;
        }
        const double measuredDb = 20.0 * std::log10(boostRms[ch] / flatRms[ch]);
        if (std::abs(measuredDb - static_cast<double>(kEqBoostDb)) >
            static_cast<double>(kEqFrToleranceDb))
        {
            std::ostringstream oss;
            oss << "ch" << ch << ": measured " << measuredDb << " dB at 1 kHz, expected "
                << kEqBoostDb << " ± " << kEqFrToleranceDb;
            logFail(kName, oss.str());
            return;
        }
    }
    logPass(kName);
}

// T-C3c: Click-free coefficient swap at N=4.
//
// N=4 variant of testEQCoefficientSwapNoClick. Flat -> +12 dB @ 1 kHz mid-stream.
// For each channel the boundary step must be ≤ 3× the settled-tail max per-sample step.
static auto testEQCoefficientSwapNoClickN4() -> void
{
    static const char* const kName = "EQ_CoefficientSwapNoClick_N4";
    const std::string err = eqSwapNoClickBody(TestConstants::kNChannels4, kName);
    if (!err.empty())
    {
        logFail(kName, err);
        return;
    }
    logPass(kName);
}

// T-C4: Limiter_LinkedGainLockstep — S1-B3 linked-gain correctness test.
//
// Build a 4-channel buffer where:
//   ch0: a HOT 1 kHz sine at amplitude 0.999 (above the −1 dBTP ceiling of 0.891) → forces GR.
//   ch1/ch2/ch3: moderate steady sines at distinct DFT-bin-aligned frequencies,
//                amplitude 0.30 (below ceiling on their own, ≈ −10 dBFS).
//
// Process through the kernel with the active true-peak ceiling.  The single shared
// grBuf_ is driven solely by ch0's peak; all channels are attenuated by the SAME
// envelope.  This is the "linked gain" invariant: every channel duck by the same GR.
//
// Proof method:
//   1. Prime the limiter ring with kLimiterLookaheadFrames silence frames so the
//      look-ahead ring starts with zeros (avoids a half-full-ring bias on the first GR).
//   2. Save a copy of the tone channels' input before processing.
//   3. Feed the 4-channel block through the kernel.
//   4. After processing, for each tone channel (1..3) and each output sample index
//      where the DELAYED input is non-trivially non-zero (|delayed_input| > 0.1):
//        applied_gain[ch][i] = output[ch][i] / delayed_input[ch][i]
//      where delayed_input[ch][i] = saved_input[ch][i] (the primed-silence + current
//      block means output[i] = grBuf_[i] * input[i] for ALL i in the block, because
//      the ring was pre-loaded with zeros for the entire lookahead window — the ring
//      readHead is at kLimiterLookaheadFrames at entry to the test block, so
//      output[i] reads ring[kLimiterLookaheadFrames + i mod kLimiterRingSize] which
//      was written at sample i of the current block, exactly kLimiterLookaheadFrames
//      in advance).
//   5. Compute the inter-channel GR difference (in dB) between tone channels at every
//      active sample and assert it is < 0.01 dB.
//
// "Active limiting" guard: confirm that at least one output sample on ch0 is
// measurably below the input amplitude (i.e. GR > 0 dB), so the test actually
// exercises the linked path and is not vacuously passing on a silent signal.
//
// Reference: linked-gain limiter design — Giannoulis/Massberg/Reiss JAES 2012;
//            the look-ahead ring mechanic — LimiterModule.h initialize() comments.
static auto testLimiterLinkedGainLockstep() -> void
{
    static const char* const kName = "Limiter_LinkedGainLockstep";
    constexpr uint32_t kNumCh = 4U;
    constexpr uint32_t kFrames = 512U;
    constexpr uint32_t kSR = TestConstants::kSampleRate48k;
    constexpr float kSRf = static_cast<float>(kSR);
    constexpr float kHotFreq = 1000.0F;
    constexpr float kHotAmpl = 0.999F;
    constexpr float kToneAmpl = 0.30F;
    constexpr float kToneFreq1 = static_cast<float>(TestConstants::kPerChBins[1]) * kSRf /
                                 static_cast<float>(TestConstants::kPerChTestFrames);
    constexpr float kToneFreq2 = static_cast<float>(TestConstants::kPerChBins[2]) * kSRf /
                                 static_cast<float>(TestConstants::kPerChTestFrames);
    constexpr float kToneFreq3 = static_cast<float>(TestConstants::kPerChBins[3]) * kSRf /
                                 static_cast<float>(TestConstants::kPerChTestFrames);
    constexpr float kCeiling = kTruePeakCeilingLinear;
    constexpr double kGrDiffThreshDb = 0.01;
    constexpr float kMinInputForRatio = 0.05F;

    // Step 1: build kernel and prime the lookahead ring with silence.
    DSPKernel kernel;
    kernel.initialize(kSR, kFrames);
    TargetState state{};
    state.intensityLinear = 1.0F;
    state.eq.numBiquads = 0U;
    state.eq.masterGainLinear = 1.0F;
    state.clarity.enabled = 0U;
    state.loudness.enabled = 0U;
    state.limiter.truePeakCeilingLinear = kCeiling;
    kernel.publishTargetState(state);
    TestABLN prime(kNumCh, kLimiterLookaheadFrames);
    kernel.process(prime.abl(), kLimiterLookaheadFrames);

    // Step 2: fill the test block (hot ch0 + tones ch1..3); save tone inputs.
    TestABLN abl(kNumCh, kFrames);
    for (uint32_t i = 0U; i < kFrames; ++i)
    {
        abl.channels[0][i] = kHotAmpl * std::sin(2.0F * std::numbers::pi_v<float> * kHotFreq *
                                                 static_cast<float>(i) / kSRf);
    }
    const std::array<float, 3U> kToneFreqs = {kToneFreq1, kToneFreq2, kToneFreq3};
    for (uint32_t ch = 1U; ch < kNumCh; ++ch)
    {
        for (uint32_t i = 0U; i < kFrames; ++i)
        {
            abl.channels[ch][i] =
                kToneAmpl * std::sin(2.0F * std::numbers::pi_v<float> * kToneFreqs[ch - 1U] *
                                     static_cast<float>(i) / kSRf);
        }
    }
    std::vector<std::vector<float>> savedInput(kNumCh, std::vector<float>(kFrames));
    for (uint32_t ch = 1U; ch < kNumCh; ++ch)
    {
        savedInput[ch] = abl.channels[ch];
    }

    // Step 3: process.
    kernel.process(abl.abl(), kFrames);

    // Step 4: verify limiter engaged on ch0.
    float ch0MaxOut = 0.0F;
    for (uint32_t i = 0U; i < kFrames; ++i)
    {
        ch0MaxOut = std::max(ch0MaxOut, std::abs(abl.channels[0][i]));
    }
    if (ch0MaxOut >= kHotAmpl - 0.01F)
    {
        logFail(kName, "ch0 output peak not reduced — limiter did not engage; GR path not tested");
        return;
    }

    // Step 5: verify inter-channel GR lockstep via helper.
    uint32_t activeSamples = 0U;
    const std::string grErr = limiterLinkedGainVerifyGR(abl,
                                                        savedInput,
                                                        kNumCh,
                                                        kFrames,
                                                        kLimiterLookaheadFrames,
                                                        kMinInputForRatio,
                                                        kGrDiffThreshDb,
                                                        activeSamples);
    if (!grErr.empty())
    {
        logFail(kName, grErr);
        return;
    }

    if (activeSamples == 0U)
    {
        logFail(kName,
                "no samples with sufficient input amplitude for ratio measurement — "
                "test configuration error");
        return;
    }

    std::ostringstream info;
    info << "  [info] " << kName << ": ch0_maxOut=" << ch0MaxOut << " ceiling=" << kCeiling
         << " activeSamples=" << activeSamples << "\n";
    logInfo(info.str());
    logPass(kName);
}

// T-C4b: Limiter N=8 hot-noise ceiling soak — S1-B3 N>2 safety net.
//
// Drive all 8 channels with full-scale-ish hot white noise (distinct per-channel
// RNG seeds) for 50 buffers.  After the first buffer (lookahead warm-up), assert:
//   (a) Every output sample on every channel is <= ceiling + 0.01 dB in linear.
//   (b) No NaN or Inf appears in any channel.
// This exercises the N=8 path through the new per-channel ring loops and confirms
// the linked-gain bus handles 8 independent peaks without overflow or NaN.
static auto testLimiterHotNoiseSoakN8() -> void
{
    static const char* const kName = "Limiter_HotNoiseSoak_N8";
    constexpr uint32_t kNumCh = 8U;
    // Use 8 distinct seeds so each channel carries a different noise sequence,
    // maximising the chance of independent inter-sample peaks that stress the
    // fan-in max() and the ring wrap across 8 slots.
    constexpr std::array<uint32_t, kNumCh> kSeeds = {0xA1B2C3D4U,
                                                     0xE5F60718U,
                                                     0x29304152U,
                                                     0x63748596U,
                                                     0xA7B8C9DAU,
                                                     0xEBFC0D1EU,
                                                     0x2F304152U,
                                                     0x73849506U};
    const std::string err =
        limiterHotNoiseSoakBody(kNumCh, 50U, kSeeds.data(), /*printInfo=*/true, kName);
    if (!err.empty())
    {
        logFail(kName, err);
        return;
    }
    logPass(kName);
}

static auto testReconfigurationContinuity() -> void
{
    logPending(
        "Reconfiguration_Stereo_5p1_Stereo",
        "S2: stereo -> 5.1 -> stereo in one kernel instance: no NaN, no crash, ceiling held");
}

// ---------------------------------------------------------------------------
// S1-C2a: Loudness_Multichannel_BS1770_Weights  (Gate C)
//
// Validates the N-channel ITU-R BS.1770-5 LufsMeter upgrade.
//
// BS.1770-5 channel weights used throughout (ITU-R BS.1770-5, Annex 1, Table 1):
//   L  = slot 0  G = 1.0
//   R  = slot 1  G = 1.0
//   C  = slot 2  G = 1.0
//   LFE= slot 3  G = 0.0  (EXCLUDED from loudness sum)
//   Ls = slot 4  G = 1.41 (~+1.5 dB, exact value 10^(1.5/10))
//   Rs = slot 5  G = 1.41
//
// ORACLE: an independent, straightforward second-path BS.1770-5 implementation
// written inline, distinct from the production LufsMeter.  It applies the same
// K-weighting coefficients (identical analytic bilinear-transform form) and the
// same two-pass gated integration algorithm, but is a self-contained loop with
// no shared code with LufsMeter.  This stands in for a libebur128 reference,
// which is not available in this build environment.  Reference:
//   ITU-R BS.1770-5 (2023), Annex 1.
// The oracle has no histogram — it integrates a single continuous measurement
// to keep the code small and auditable, suitable for the deterministic
// calibrated-tone and calibrated-noise signals used here.
//
// Sub-cases:
//   (a) Stereo-identity: 5.1 buffer with L/R active and C/LFE/Ls/Rs=0 reads
//       the SAME integrated LUFS (within 1e-6) as the stereo meter fed only L/R.
//   (b) Surround weight (+1.5 dB) and LFE exclusion (G=0): known tone on Ls+Rs
//       reads ~+1.5 dB above the same tone on L+R; LFE-only signal reads silence.
//   (c) Full 5.1 calibrated case against the independent oracle (±0.2 LU).
// ---------------------------------------------------------------------------

namespace
{
    // BS.1770-5 channel weights for ITU 5.1 (L, R, C, LFE, Ls, Rs).
    // Reference: ITU-R BS.1770-5, Annex 1, Table 1.
    // kBs1770GSurround = 10^(1.5/10) ≈ 1.41253754…  (exactly +1.5 dB in power).
    constexpr double kBs1770GLRC = 1.0;
    constexpr double kBs1770GLFE = 0.0;
    constexpr double kBs1770GSurround = 1.41253754462275643; // 10^(1.5/10)
    constexpr uint32_t kNum51Channels = 6U;

    // Build the weight array for 5.1 (L, R, C, LFE, Ls, Rs).
    auto make51Weights() -> std::array<double, kMaxChannels>
    {
        std::array<double, kMaxChannels> w{};
        w[0] = kBs1770GLRC;      // L
        w[1] = kBs1770GLRC;      // R
        w[2] = kBs1770GLRC;      // C
        w[3] = kBs1770GLFE;      // LFE (excluded)
        w[4] = kBs1770GSurround; // Ls
        w[5] = kBs1770GSurround; // Rs
        return w;
    }

    // Generate interleaved N-channel audio: one channel carries a 1 kHz sine at
    // peakDbfs; all other channels are silent.  sampleRate at 48 kHz.
    auto makeInterleavedNch(uint32_t numCh,
                            uint32_t activeCh,
                            double peakDbfs,
                            double seconds,
                            uint32_t sampleRate) -> std::vector<float>
    {
        const double amp = std::pow(10.0, peakDbfs / 20.0);
        const auto frames = static_cast<size_t>(seconds * sampleRate);
        std::vector<float> buf(frames * numCh, 0.0F);
        for (size_t frm = 0U; frm < frames; ++frm)
        {
            const double s =
                amp * std::sin(2.0 * std::numbers::pi * 1000.0 * static_cast<double>(frm) /
                               static_cast<double>(sampleRate));
            buf[(frm * numCh) + activeCh] = static_cast<float>(s);
        }
        return buf;
    }

    // Same as above but two channels active in phase (additive).
    auto makeInterleavedNch2Active(uint32_t numCh,
                                   uint32_t activeCh0,
                                   uint32_t activeCh1,
                                   double peakDbfs,
                                   double seconds,
                                   uint32_t sampleRate) -> std::vector<float>
    {
        const double amp = std::pow(10.0, peakDbfs / 20.0);
        const auto frames = static_cast<size_t>(seconds * sampleRate);
        std::vector<float> buf(frames * numCh, 0.0F);
        for (size_t frm = 0U; frm < frames; ++frm)
        {
            const double s =
                amp * std::sin(2.0 * std::numbers::pi * 1000.0 * static_cast<double>(frm) /
                               static_cast<double>(sampleRate));
            buf[(frm * numCh) + activeCh0] = static_cast<float>(s);
            buf[(frm * numCh) + activeCh1] = static_cast<float>(s);
        }
        return buf;
    }

    // ---------------------------------------------------------------------------
    // Independent BS.1770-5 oracle (stands in for libebur128).
    //
    // This is a separate, self-contained implementation of the BS.1770-5
    // integrated-loudness algorithm.  It shares NO code with the production
    // LufsMeter — it recomputes K-weighting from scratch and performs its own
    // gating.  It is deliberately simple (single-pass accumulation on gated
    // blocks, no histogram) and appropriate only for the calibrated deterministic
    // signals in this test.
    //
    // Reference: ITU-R BS.1770-5 (2023), Annex 1.
    // ---------------------------------------------------------------------------

    struct OracleBiquad
    {
        double b0{1.0}, b1{0.0}, b2{0.0}, a1{0.0}, a2{0.0};
        double z1{0.0}, z2{0.0};

        auto process(double x) noexcept -> double
        {
            const double y = b0 * x + z1;
            z1 = b1 * x - a1 * y + z2;
            z2 = b2 * x - a2 * y;
            return y;
        }
    };

    struct OracleKWeight
    {
        OracleBiquad shelf{};
        OracleBiquad rlb{};

        auto process(double x) noexcept -> double
        {
            return rlb.process(shelf.process(x));
        }
    };

    // Build oracle K-weight filters at the given sample rate using the same
    // analytic bilinear-transform form as LufsMeter (for consistency).
    auto makeOracleKWeight(double sampleRate) -> OracleKWeight
    {
        OracleKWeight kw;
        // Stage 1: high-shelf
        {
            const double warp = std::tan(M_PI * kKwShelfF0Hz / sampleRate);
            const double Vh = std::pow(kDecibelBase, kKwShelfGainDb / kDbAmplitudeScale);
            const double Vb = std::pow(Vh, kKwShelfVbExponent);
            const double a0 = 1.0 + (warp / kKwShelfQ) + (warp * warp);
            kw.shelf.b0 = (Vh + (Vb * warp / kKwShelfQ) + (warp * warp)) / a0;
            kw.shelf.b1 = 2.0 * ((warp * warp) - Vh) / a0;
            kw.shelf.b2 = (Vh - (Vb * warp / kKwShelfQ) + (warp * warp)) / a0;
            kw.shelf.a1 = 2.0 * ((warp * warp) - 1.0) / a0;
            kw.shelf.a2 = (1.0 - (warp / kKwShelfQ) + (warp * warp)) / a0;
        }
        // Stage 2: RLB high-pass
        {
            const double warp = std::tan(M_PI * kKwRlbF0Hz / sampleRate);
            const double a0 = 1.0 + (warp / kKwRlbQ) + (warp * warp);
            kw.rlb.b0 = 1.0 / a0;
            kw.rlb.b1 = -2.0 / a0;
            kw.rlb.b2 = 1.0 / a0;
            kw.rlb.a1 = 2.0 * ((warp * warp) - 1.0) / a0;
            kw.rlb.a2 = (1.0 - (warp / kKwRlbQ) + (warp * warp)) / a0;
        }
        return kw;
    }

    // Convert an energy value to LUFS (BS.1770-5 block loudness formula).
    auto energyToLufs(double energy) -> double
    {
        return (energy > kTinyEnergy) ? (kLufsOffset + kDbPowerScale * std::log10(energy))
                                      : kSilenceLufs;
    }

    // Two-pass gated integration over a vector of absolute-gated block energies.
    // Returns integrated LUFS (BS.1770-5 §2.3).
    auto oracleTwoPassGate(const std::vector<double>& blockEnergies) -> double
    {
        if (blockEnergies.empty())
        {
            return kSilenceLufs;
        }
        // Pass 1: absolute-gated mean → relative threshold.
        double sumEnergy1 = 0.0;
        for (const double e : blockEnergies)
        {
            sumEnergy1 += e;
        }
        const double meanEnergy1 = sumEnergy1 / static_cast<double>(blockEnergies.size());
        const double relThresh = (meanEnergy1 > kTinyEnergy)
                                     ? (energyToLufs(meanEnergy1) + kRelativeGateOffsetLu)
                                     : kSilenceLufs;
        // Pass 2: relative-gated mean → loudness.
        double sumEnergy2 = 0.0;
        size_t count2 = 0U;
        for (const double e : blockEnergies)
        {
            if (energyToLufs(e) >= relThresh)
            {
                sumEnergy2 += e;
                ++count2;
            }
        }
        if (count2 == 0U)
        {
            return energyToLufs(meanEnergy1);
        }
        return energyToLufs(sumEnergy2 / static_cast<double>(count2));
    }

    // Compute BS.1770-5 integrated LUFS for an interleaved N-channel buffer using
    // the independent oracle (NOT production LufsMeter).
    auto oracleIntegratedLufs(const std::vector<float>& buf,
                              uint32_t numCh,
                              const std::array<double, kMaxChannels>& weights,
                              uint32_t sampleRate) -> double
    {
        // Build one K-weight filter per channel (independent state).
        std::vector<OracleKWeight> filters(numCh);
        for (uint32_t ch = 0U; ch < numCh; ++ch)
        {
            filters[ch] = makeOracleKWeight(static_cast<double>(sampleRate));
        }

        const auto hopFrames =
            static_cast<uint32_t>(std::lround(kHopSeconds * static_cast<double>(sampleRate)));
        const double blockFrames = static_cast<double>(hopFrames) * kBlockHops;
        const size_t totalFrames = buf.size() / numCh;

        std::array<double, kShortTermHops> ring{};
        uint32_t ringHead = 0U;
        uint32_t ringFilled = 0U;
        std::vector<double> hopAccum(numCh, 0.0);
        uint32_t hopCount = 0U;

        std::vector<double> blockEnergies;
        blockEnergies.reserve(totalFrames / hopFrames + 10U);

        for (size_t frm = 0U; frm < totalFrames; ++frm)
        {
            for (uint32_t ch = 0U; ch < numCh; ++ch)
            {
                const double ky = filters[ch].process(static_cast<double>(buf[(frm * numCh) + ch]));
                hopAccum[ch] += ky * ky;
            }
            ++hopCount;
            if (hopCount < hopFrames)
            {
                continue;
            }
            // Hop complete: weighted sum, reset.
            double hopEnergy = 0.0;
            for (uint32_t ch = 0U; ch < numCh; ++ch)
            {
                hopEnergy += weights[ch] * hopAccum[ch];
                hopAccum[ch] = 0.0;
            }
            hopCount = 0U;
            ring[ringHead] = hopEnergy;
            ringHead = (ringHead + 1U) % static_cast<uint32_t>(kShortTermHops);
            if (ringFilled < static_cast<uint32_t>(kShortTermHops))
            {
                ++ringFilled;
            }
            if (ringFilled < static_cast<uint32_t>(kBlockHops))
            {
                continue;
            }
            // Block complete: sum kBlockHops most-recent hops.
            double blockSum = 0.0;
            for (int hIdx = 0; hIdx < kBlockHops; ++hIdx)
            {
                const uint32_t pos = (ringHead + static_cast<uint32_t>(kShortTermHops) - 1U -
                                      static_cast<uint32_t>(hIdx)) %
                                     static_cast<uint32_t>(kShortTermHops);
                blockSum += ring[pos];
            }
            const double energy = blockSum / blockFrames;
            if (energyToLufs(energy) >= kAbsoluteGateLufs)
            {
                blockEnergies.push_back(energy);
            }
        }

        return oracleTwoPassGate(blockEnergies);
    }

} // namespace

// ---------------------------------------------------------------------------
// Sub-case helpers for testLoudnessMultichannelBS1770Weights and
// testLoudnessDecodedLayoutWeights. Each returns "" on pass, non-empty on failure.
// ---------------------------------------------------------------------------

// (a) Stereo-identity: 5.1 meter with only L/R active must match stereo meter.
static auto
bs1770SubcaseStereoIdentity(const char* kName, uint32_t kSR, double kDuration, double kPeak)
    -> std::string
{
    LufsMeter stereoMeter;
    stereoMeter.prepare(kSR);
    {
        const double amp = std::pow(10.0, kPeak / 20.0);
        const auto frames = static_cast<size_t>(kDuration * kSR);
        std::vector<float> stereoBuf(frames * 2U);
        for (size_t frm = 0U; frm < frames; ++frm)
        {
            const double s = amp * std::sin(2.0 * std::numbers::pi * 1000.0 *
                                            static_cast<double>(frm) / static_cast<double>(kSR));
            stereoBuf[2U * frm] = static_cast<float>(s);
            stereoBuf[(2U * frm) + 1U] = static_cast<float>(s);
        }
        stereoMeter.addInterleavedStereo(stereoBuf.data(), frames);
    }
    const double stereoLufs = stereoMeter.integratedLufs();

    LufsMeter meter51;
    meter51.prepare(kSR);
    meter51.configureChannels(kNum51Channels, make51Weights());
    {
        const double amp = std::pow(10.0, kPeak / 20.0);
        const auto frames = static_cast<size_t>(kDuration * kSR);
        std::vector<float> buf51(frames * kNum51Channels, 0.0F);
        for (size_t frm = 0U; frm < frames; ++frm)
        {
            const double s = amp * std::sin(2.0 * std::numbers::pi * 1000.0 *
                                            static_cast<double>(frm) / static_cast<double>(kSR));
            buf51[frm * kNum51Channels + 0U] = static_cast<float>(s);
            buf51[frm * kNum51Channels + 1U] = static_cast<float>(s);
        }
        meter51.addInterleaved(buf51.data(), frames, kNum51Channels);
    }
    const double lufs51LROnly = meter51.integratedLufs();
    const double deltaA = std::abs(lufs51LROnly - stereoLufs);

    std::ostringstream infoA;
    infoA << "  [info] " << kName << " (a): stereo=" << stereoLufs
          << " 5.1_LR_only=" << lufs51LROnly << " delta=" << deltaA << "\n";
    logInfo(infoA.str());

    if (deltaA > 1e-6)
    {
        std::ostringstream oss;
        oss << "(a) stereo-identity: expected delta < 1e-6, got " << deltaA
            << " (stereo=" << stereoLufs << " 5.1_LR=" << lufs51LROnly << ")";
        return oss.str();
    }
    return {};
}

// (b1) Surround weight: Ls+Rs signal must read ~+1.5 dB above L+R at same peak amplitude.
static auto
bs1770SubcaseSurroundWeight(const char* kName, uint32_t kSR, double kDuration, double kPeak)
    -> std::string
{
    LufsMeter meterSurround;
    meterSurround.prepare(kSR);
    meterSurround.configureChannels(kNum51Channels, make51Weights());
    {
        const auto buf = makeInterleavedNch2Active(kNum51Channels, 4U, 5U, kPeak, kDuration, kSR);
        meterSurround.addInterleaved(
            buf.data(), static_cast<size_t>(kDuration * kSR), kNum51Channels);
    }
    const double lufsSurround = meterSurround.integratedLufs();

    LufsMeter meterLR;
    meterLR.prepare(kSR);
    meterLR.configureChannels(kNum51Channels, make51Weights());
    {
        const auto buf = makeInterleavedNch2Active(kNum51Channels, 0U, 1U, kPeak, kDuration, kSR);
        meterLR.addInterleaved(buf.data(), static_cast<size_t>(kDuration * kSR), kNum51Channels);
    }
    const double lufsLR = meterLR.integratedLufs();

    const double expectedBoostDb = kDbPowerScale * std::log10(kBs1770GSurround);
    const double measuredBoostDb = lufsSurround - lufsLR;
    const double deltaB1 = std::abs(measuredBoostDb - expectedBoostDb);

    std::ostringstream infoB1;
    infoB1 << "  [info] " << kName << " (b1): LR=" << lufsLR << " Surround=" << lufsSurround
           << " measuredBoost=" << measuredBoostDb << " expectedBoost=" << expectedBoostDb
           << " delta=" << deltaB1 << "\n";
    logInfo(infoB1.str());

    if (deltaB1 > 0.05)
    {
        std::ostringstream oss;
        oss << "(b1) surround +1.5 dB weight: measured boost=" << measuredBoostDb
            << " expected=" << expectedBoostDb << " delta=" << deltaB1;
        return oss.str();
    }
    return {};
}

// (b2) LFE exclusion: LFE-only signal must produce no gated blocks (G=0).
static auto
bs1770SubcaseLfeExclusion(const char* kName, uint32_t kSR, double kDuration, double kPeak)
    -> std::string
{
    LufsMeter meterLFE;
    meterLFE.prepare(kSR);
    meterLFE.configureChannels(kNum51Channels, make51Weights());
    {
        const auto buf = makeInterleavedNch(kNum51Channels, 3U, kPeak, kDuration, kSR);
        meterLFE.addInterleaved(buf.data(), static_cast<size_t>(kDuration * kSR), kNum51Channels);
    }
    const double lufsLFE = meterLFE.integratedLufs();

    std::ostringstream infoB2;
    infoB2 << "  [info] " << kName << " (b2): LFE_only=" << lufsLFE
           << " (expect kSilenceLufs=" << kSilenceLufs << ")\n";
    logInfo(infoB2.str());

    if (lufsLFE > kAbsoluteGateLufs)
    {
        std::ostringstream oss;
        oss << "(b2) LFE exclusion: LFE-only signal must produce no gated blocks; got " << lufsLFE
            << " LUFS (should be <= " << kAbsoluteGateLufs << ")";
        return oss.str();
    }
    return {};
}

// (c) Full calibrated 5.1 vs. independent oracle (≤0.2 LU tolerance).
static auto bs1770SubcaseFullCalibrated(const char* kName, uint32_t kSR, double kDuration)
    -> std::string
{
    const double ampL = std::pow(10.0, -20.0 / 20.0);
    const double ampR = std::pow(10.0, -22.0 / 20.0);
    const double ampC = std::pow(10.0, -25.0 / 20.0);
    const double ampLFE = std::pow(10.0, -10.0 / 20.0);
    const double ampLs = std::pow(10.0, -24.0 / 20.0);
    const double ampRs = std::pow(10.0, -26.0 / 20.0);
    const double amps51[kNum51Channels] = {ampL, ampR, ampC, ampLFE, ampLs, ampRs};

    const auto frames = static_cast<size_t>(kDuration * kSR);
    std::vector<float> buf51full(frames * kNum51Channels);
    for (size_t frm = 0U; frm < frames; ++frm)
    {
        const double phase =
            2.0 * std::numbers::pi * 1000.0 * static_cast<double>(frm) / static_cast<double>(kSR);
        for (uint32_t ch = 0U; ch < kNum51Channels; ++ch)
        {
            buf51full[(frm * kNum51Channels) + ch] =
                static_cast<float>(amps51[ch] * std::sin(phase));
        }
    }

    LufsMeter meterFull;
    meterFull.prepare(kSR);
    meterFull.configureChannels(kNum51Channels, make51Weights());
    meterFull.addInterleaved(buf51full.data(), frames, kNum51Channels);
    const double lufsProduction = meterFull.integratedLufs();

    const double lufsOracle = oracleIntegratedLufs(buf51full, kNum51Channels, make51Weights(), kSR);
    const double deltaC = std::abs(lufsProduction - lufsOracle);

    std::ostringstream infoC;
    infoC << "  [info] " << kName << " (c): production=" << lufsProduction
          << " oracle=" << lufsOracle << " delta=" << deltaC << "\n";
    logInfo(infoC.str());

    if (deltaC > 0.2)
    {
        std::ostringstream oss;
        oss << "(c) 5.1 full calibrated: production=" << lufsProduction << " oracle=" << lufsOracle
            << " delta=" << deltaC << " (threshold 0.2 LU)";
        return oss.str();
    }
    return {};
}

static auto testLoudnessMultichannelBS1770Weights() -> void
{
    static const char* const kName = "Loudness_Multichannel_BS1770_Weights";
    constexpr uint32_t kSR = TestConstants::kSampleRate48k;
    constexpr double kDuration = 15.0;
    constexpr double kPeak = -23.0; // dBFS

    // Run the four sub-cases in order; any failure is reported immediately.
    std::string err = bs1770SubcaseStereoIdentity(kName, kSR, kDuration, kPeak);
    if (!err.empty())
    {
        logFail(kName, err);
        return;
    }

    err = bs1770SubcaseSurroundWeight(kName, kSR, kDuration, kPeak);
    if (!err.empty())
    {
        logFail(kName, err);
        return;
    }

    err = bs1770SubcaseLfeExclusion(kName, kSR, kDuration, kPeak);
    if (!err.empty())
    {
        logFail(kName, err);
        return;
    }

    err = bs1770SubcaseFullCalibrated(kName, kSR, kDuration);
    if (!err.empty())
    {
        logFail(kName, err);
        return;
    }

    logPass(kName);
}

// ---------------------------------------------------------------------------
// Large-buffer regression fence (buffer-size desync bug fix verification).
// ---------------------------------------------------------------------------

// Helper: run the limiter-tail correctness check for a single buffer size.
// Returns "" on pass, non-empty error string on failure.
static auto largeBufferLimiterTailCheckForSize(uint32_t bufSize) -> std::string
{
    constexpr uint32_t kSR = TestConstants::kSampleRate48k;
    constexpr float kCeiling = kTruePeakCeilingLinear;
    constexpr float kCeilingTol = 0.01F;
    constexpr float kHotAmpl = 0.999F;
    constexpr uint32_t kBoundary = kDefaultMaxFrames; // old 512 safeCount boundary

    DSPKernel kernel;
    kernel.initialize(kSR, bufSize);
    TargetState state{};
    state.intensityLinear = 1.0F;
    state.eq.numBiquads = 0U;
    state.eq.masterGainLinear = 1.0F;
    state.clarity.enabled = 0U;
    state.loudness.enabled = 0U;
    state.limiter.truePeakCeilingLinear = kCeiling;
    kernel.publishTargetState(state);

    TestABLN prime(2U, kLimiterLookaheadFrames);
    kernel.process(prime.abl(), kLimiterLookaheadFrames);

    TestABLN abl(2U, bufSize);
    for (uint32_t i = 0U; i < bufSize; ++i)
    {
        abl.channels[0][i] = kHotAmpl;
        abl.channels[1][i] = kHotAmpl;
    }
    kernel.process(abl.abl(), bufSize);

    uint32_t nanCount = 0U;
    uint32_t aboveCeiling = 0U;
    for (uint32_t i = 0U; i < bufSize; ++i)
    {
        const float s = abl.channels[0][i];
        if (!std::isfinite(s))
        {
            ++nanCount;
        }
        else if (std::abs(s) > kCeiling + kCeilingTol)
        {
            ++aboveCeiling;
        }
    }

    if (nanCount > 0U || aboveCeiling > 0U)
    {
        std::ostringstream oss;
        oss << "bufSize=" << bufSize << " NaN/Inf=" << nanCount
            << " samples_above_ceiling=" << aboveCeiling << " (ceiling=" << kCeiling
            << " + tol=" << kCeilingTol << ")";
        return oss.str();
    }

    if (bufSize <= kBoundary)
    {
        return {}; // not a large-buffer case; no boundary check needed
    }

    double headGainSum = 0.0;
    uint32_t headCnt = 0U;
    double tailGainSum = 0.0;
    uint32_t tailCnt = 0U;
    for (uint32_t i = kLimiterLookaheadFrames; i < kBoundary; ++i)
    {
        headGainSum += static_cast<double>(std::abs(abl.channels[0][i])) / kHotAmpl;
        ++headCnt;
    }
    for (uint32_t i = kBoundary; i < bufSize; ++i)
    {
        tailGainSum += static_cast<double>(std::abs(abl.channels[0][i])) / kHotAmpl;
        ++tailCnt;
    }

    if (headCnt > 0U && tailCnt > 0U)
    {
        const double avgHeadGain = headGainSum / static_cast<double>(headCnt);
        const double avgTailGain = tailGainSum / static_cast<double>(tailCnt);
        if (avgTailGain > avgHeadGain + 0.05)
        {
            std::ostringstream oss;
            oss << "bufSize=" << bufSize << " tail avg gain (" << avgTailGain
                << ") >> head avg gain (" << avgHeadGain
                << ") — limiter tail-safeCount boundary still present";
            return oss.str();
        }
    }
    return {};
}

static auto testLargeBufferLimiterTailCorrect() -> void
{
    static const char* const kName = "Kernel_LargeBuffer_LimiterTailCorrect";
    constexpr std::array<uint32_t, 2U> kBufSizes = {1024U, 4096U};
    for (const uint32_t bufSize : kBufSizes)
    {
        const std::string err = largeBufferLimiterTailCheckForSize(bufSize);
        if (!err.empty())
        {
            logFail(kName, err);
            return;
        }
    }
    logPass(kName);
}

static auto testLargeBufferEQGainNoCutoff() -> void
{
    static const char* const kName = "Kernel_LargeBuffer_EQGainNoCutoff";
    constexpr uint32_t kSR = TestConstants::kSampleRate48k;
    constexpr uint32_t kBufSize = 1024U;

    DSPKernel kernel;
    kernel.initialize(kSR, kBufSize);

    // masterGain=2.0 forces the ramp path; ramp starts at unity (snapped) and
    // trends toward 2.0, so every output sample > input * 0.9 at minimum.
    TargetState state{};
    state.intensityLinear = 1.0F;
    state.eq.numBiquads = 0U;
    state.eq.masterGainLinear = 2.0F;
    state.clarity.enabled = 0U;
    state.loudness.enabled = 0U;
    state.limiter.truePeakCeilingLinear = 10.0F; // bypass limiter
    kernel.publishTargetState(state);

    // DC signal at 0.5 — with masterGain=2.0 the ramp trend means all output > 0.4.
    TestABLN abl(2U, kBufSize);
    for (uint32_t i = 0U; i < kBufSize; ++i)
    {
        abl.channels[0][i] = 0.5F;
        abl.channels[1][i] = 0.5F;
    }
    kernel.process(abl.abl(), kBufSize);

    // Before the fix: samples [512..1023] were multiplied by stale rampBuf_[i-512]
    // values from initialize()'s fill (0.0), so output[512..] ≈ 0.
    // After the fix: the ramp continues through all 1024 samples; output > 0.4.
    constexpr float kMinExpected = 0.4F; // ramp at unity * 0.5 input = 0.5 at minimum
    constexpr uint32_t kBoundary = kDefaultMaxFrames;

    bool tailSilent = false;
    float minTailOutput = 1.0F;
    for (uint32_t i = kBoundary; i < kBufSize; ++i)
    {
        const float s = abl.channels[0][i];
        if (std::abs(s) < minTailOutput)
        {
            minTailOutput = std::abs(s);
        }
        if (std::abs(s) < kMinExpected)
        {
            tailSilent = true;
        }
    }

    // Also assert no step at the 512 boundary.
    const float stepAt512 = std::abs(abl.channels[0][kBoundary] - abl.channels[0][kBoundary - 1U]);
    // The ramp is monotonically increasing toward 2.0; the per-sample gain step is tiny.
    // Before the fix: a ~-0.14 linear discontinuity. After the fix: smooth ramp.
    constexpr float kMaxAllowedStep = 0.05F; // generous: ramp changes < 0.001 per sample

    if (tailSilent)
    {
        std::ostringstream oss;
        oss << "tail [" << kBoundary << ".." << kBufSize - 1U << "] min output=" << minTailOutput
            << " < " << kMinExpected << " — EQ master-gain ramp was not applied past frame "
            << kBoundary;
        logFail(kName, oss.str());
        return;
    }
    if (stepAt512 > kMaxAllowedStep)
    {
        std::ostringstream oss;
        oss << "step at frame " << kBoundary << ": " << stepAt512 << " linear (max allowed "
            << kMaxAllowedStep << ") — EQ ramp discontinuity at safeCount boundary";
        logFail(kName, oss.str());
        return;
    }
    logPass(kName);
}

static auto testLargeBufferConsecutiveBuffers() -> void
{
    static const char* const kName = "Kernel_LargeBuffer_ConsecutiveBuffers";
    constexpr uint32_t kSR = TestConstants::kSampleRate48k;
    constexpr uint32_t kBufSize = 1024U;
    constexpr float kCeiling = kTruePeakCeilingLinear;
    constexpr float kCeilingTol = 0.01F;
    constexpr float kHotAmpl = 0.999F;
    constexpr uint32_t kNumBlocks = 6U;

    DSPKernel kernel;
    kernel.initialize(kSR, kBufSize);

    TargetState state{};
    state.intensityLinear = 1.0F;
    state.eq.numBiquads = 0U;
    state.eq.masterGainLinear = 1.0F;
    state.clarity.enabled = 0U;
    state.loudness.enabled = 0U;
    state.limiter.truePeakCeilingLinear = kCeiling;
    kernel.publishTargetState(state);

    // Feed kNumBlocks 1024-frame buffers of a 1 kHz sine above the ceiling.
    float worstTailPeak = 0.0F;
    uint32_t failBlock = 0U;
    bool failed = false;

    for (uint32_t blk = 0U; blk < kNumBlocks; ++blk)
    {
        TestABLN abl(2U, kBufSize);
        for (uint32_t i = 0U; i < kBufSize; ++i)
        {
            const float phase = 2.0F * std::numbers::pi_v<float> * 1000.0F *
                                static_cast<float>((blk * kBufSize) + i) / static_cast<float>(kSR);
            abl.channels[0][i] = kHotAmpl * std::sin(phase);
            abl.channels[1][i] = abl.channels[0][i];
        }
        kernel.process(abl.abl(), kBufSize);

        // Check tail: before the fix the ring desyncs progressively, so blocks 2+
        // would show increasing corruption in the tail.
        for (uint32_t i = kDefaultMaxFrames; i < kBufSize; ++i)
        {
            const float absS = std::abs(abl.channels[0][i]);
            if (absS > worstTailPeak)
            {
                worstTailPeak = absS;
            }
            if (!failed && absS > kCeiling + kCeilingTol)
            {
                failed = true;
                failBlock = blk;
            }
        }
    }

    if (failed)
    {
        std::ostringstream oss;
        oss << "tail [" << kDefaultMaxFrames << ".." << kBufSize - 1U
            << "] exceeded ceiling on block " << failBlock << ": worst_tail_peak=" << worstTailPeak
            << " ceiling=" << kCeiling << " — ring desync or safeCount boundary not fixed";
        logFail(kName, oss.str());
        return;
    }
    logPass(kName);
}

// ---------------------------------------------------------------------------
// M1-1 Gate D: ChannelLayout_Decode_GateD
// ---------------------------------------------------------------------------

namespace
{
    // Shared tolerance and expected-value constants (same across all sub-cases).
    // Kept at namespace scope so each sub-function can use them without re-declaring.
    constexpr float kGateDWeightTol = 1e-5F;
    constexpr float kGateDazimTol = 1e-4F;
    constexpr float kGateDExpLRC = 1.0F;
    constexpr float kGateDExpLFE = 0.0F;
    constexpr float kGateDExpSurr = 1.41253754F; // 10^(1.5/10) per BS.1770-5 Annex 1 Table 1
    // Azimuth spot-checks (BS.775-4; + = left/CCW from centre)
    constexpr float kGateDExpAzimL = 30.0F; // L
    constexpr float kGateDExpAzimC = 0.0F;  // C

    // Returns "" on success, a non-empty error string on failure.
    // Stereo (2): L R
    auto gateDCheckStereo() -> std::string
    {
        const ChannelLayout lay = decodeChannelLayout(kAudioChannelLayoutTag_Stereo);
        if (lay.numChannels != 2U)
        {
            return "Stereo: numChannels != 2";
        }
        if (std::abs(lay.lufsWeight[0] - kGateDExpLRC) > kGateDWeightTol)
        {
            return "Stereo: slot0 (L) lufsWeight != 1.0";
        }
        if (lay.isLfe[0] != 0U)
        {
            return "Stereo: slot0 (L) isLfe != 0";
        }
        if (std::abs(lay.brirAzimuthDeg[0] - kGateDExpAzimL) > kGateDazimTol)
        {
            return "Stereo: slot0 (L) brirAzimuthDeg != +30";
        }
        if (std::abs(lay.lufsWeight[1] - kGateDExpLRC) > kGateDWeightTol)
        {
            return "Stereo: slot1 (R) lufsWeight != 1.0";
        }
        if (lay.isLfe[1] != 0U)
        {
            return "Stereo: slot1 (R) isLfe != 0";
        }
        return {};
    }

    // MPEG 5.1 A: L R C LFE Ls Rs  (LFE at slot 3, surrounds at 4/5)
    auto gateDCheck51A() -> std::string
    {
        const ChannelLayout layA = decodeChannelLayout(kAudioChannelLayoutTag_MPEG_5_1_A);
        if (layA.numChannels != 6U)
        {
            return "5_1_A: numChannels != 6";
        }
        if (std::abs(layA.lufsWeight[0] - kGateDExpLRC) > kGateDWeightTol || layA.isLfe[0] != 0U)
        {
            return "5_1_A: slot0 (L) wrong";
        }
        // slot 2: C — ordering trap proof: must be C (weight=1) not surround
        if (std::abs(layA.lufsWeight[2] - kGateDExpLRC) > kGateDWeightTol || layA.isLfe[2] != 0U)
        {
            return "5_1_A: slot2 (C) weight or isLfe wrong";
        }
        if (std::abs(layA.brirAzimuthDeg[2] - kGateDExpAzimC) > kGateDazimTol)
        {
            return "5_1_A: slot2 (C) brirAzimuthDeg != 0";
        }
        // slot 3: LFE — THE TRAP: LFE is at index 3 in _A, at index 5 in _B
        if (std::abs(layA.lufsWeight[3] - kGateDExpLFE) > kGateDWeightTol || layA.isLfe[3] != 1U)
        {
            return "5_1_A: slot3 must be LFE — ordering trap";
        }
        // slots 4/5: Ls/Rs (surround)
        if (std::abs(layA.lufsWeight[4] - kGateDExpSurr) > kGateDWeightTol || layA.isLfe[4] != 0U)
        {
            return "5_1_A: slot4 (Ls) surround weight wrong";
        }
        if (std::abs(layA.lufsWeight[5] - kGateDExpSurr) > kGateDWeightTol || layA.isLfe[5] != 0U)
        {
            return "5_1_A: slot5 (Rs) surround weight wrong";
        }
        if (std::abs(layA.brirAzimuthDeg[0] - kGateDExpAzimL) > kGateDazimTol)
        {
            return "5_1_A: slot0 (L) brirAzimuthDeg != +30";
        }
        return {};
    }

    // MPEG 5.1 B: L R Ls Rs C LFE  (LFE at slot 5, surrounds at 2/3)
    // DIFFERENT ordering from _A — this is the whole point of Gate D.
    auto gateDCheck51B() -> std::string
    {
        const ChannelLayout layB = decodeChannelLayout(kAudioChannelLayoutTag_MPEG_5_1_B);
        if (layB.numChannels != 6U)
        {
            return "5_1_B: numChannels != 6";
        }
        // slot 2: Ls — ordering trap proof: must be surround (weight=1.41) not C (weight=1)
        if (std::abs(layB.lufsWeight[2] - kGateDExpSurr) > kGateDWeightTol || layB.isLfe[2] != 0U)
        {
            return "5_1_B: slot2 must be Ls (surround) — ordering trap";
        }
        // slot 3: Rs — ordering trap proof: must be surround, not LFE
        if (std::abs(layB.lufsWeight[3] - kGateDExpSurr) > kGateDWeightTol || layB.isLfe[3] != 0U)
        {
            return "5_1_B: slot3 must be Rs (surround) — ordering trap";
        }
        // slot 4: C
        if (std::abs(layB.lufsWeight[4] - kGateDExpLRC) > kGateDWeightTol || layB.isLfe[4] != 0U)
        {
            return "5_1_B: slot4 (C) wrong";
        }
        if (std::abs(layB.brirAzimuthDeg[4] - kGateDExpAzimC) > kGateDazimTol)
        {
            return "5_1_B: slot4 (C) brirAzimuthDeg != 0";
        }
        // slot 5: LFE — THE TRAP: LFE is at index 5 in _B, at index 3 in _A
        if (std::abs(layB.lufsWeight[5] - kGateDExpLFE) > kGateDWeightTol || layB.isLfe[5] != 1U)
        {
            return "5_1_B: slot5 must be LFE — ordering trap";
        }
        if (std::abs(layB.brirAzimuthDeg[0] - kGateDExpAzimL) > kGateDazimTol)
        {
            return "5_1_B: slot0 (L) brirAzimuthDeg != +30";
        }
        return {};
    }

    // MPEG 7.1 A: L R C LFE Ls Rs Lc Rc
    auto gateDCheck71A() -> std::string
    {
        const ChannelLayout lay71A = decodeChannelLayout(kAudioChannelLayoutTag_MPEG_7_1_A);
        if (lay71A.numChannels != 8U)
        {
            return "7_1_A: numChannels != 8";
        }
        if (std::abs(lay71A.lufsWeight[3] - kGateDExpLFE) > kGateDWeightTol ||
            lay71A.isLfe[3] != 1U)
        {
            return "7_1_A: slot3 must be LFE";
        }
        if (std::abs(lay71A.lufsWeight[4] - kGateDExpSurr) > kGateDWeightTol ||
            lay71A.isLfe[4] != 0U)
        {
            return "7_1_A: slot4 (Ls) surround weight wrong";
        }
        if (std::abs(lay71A.lufsWeight[6] - kGateDExpLRC) > kGateDWeightTol ||
            lay71A.isLfe[6] != 0U)
        {
            return "7_1_A: slot6 (Lc) weight wrong";
        }
        if (std::abs(lay71A.brirAzimuthDeg[2] - kGateDExpAzimC) > kGateDazimTol)
        {
            return "7_1_A: slot2 (C) brirAzimuthDeg != 0";
        }
        return {};
    }

    // MPEG 7.1 C: L R C LFE Ls Rs Rls Rrs
    auto gateDCheck71C() -> std::string
    {
        const ChannelLayout lay71C = decodeChannelLayout(kAudioChannelLayoutTag_MPEG_7_1_C);
        if (lay71C.numChannels != 8U)
        {
            return "7_1_C: numChannels != 8";
        }
        if (std::abs(lay71C.lufsWeight[3] - kGateDExpLFE) > kGateDWeightTol ||
            lay71C.isLfe[3] != 1U)
        {
            return "7_1_C: slot3 must be LFE";
        }
        if (std::abs(lay71C.lufsWeight[4] - kGateDExpSurr) > kGateDWeightTol ||
            lay71C.isLfe[4] != 0U)
        {
            return "7_1_C: slot4 (Ls) surround weight wrong";
        }
        if (std::abs(lay71C.lufsWeight[6] - kGateDExpSurr) > kGateDWeightTol ||
            lay71C.isLfe[6] != 0U)
        {
            return "7_1_C: slot6 (Rls) back-surround weight wrong";
        }
        if (std::abs(lay71C.lufsWeight[7] - kGateDExpSurr) > kGateDWeightTol ||
            lay71C.isLfe[7] != 0U)
        {
            return "7_1_C: slot7 (Rrs) back-surround weight wrong";
        }
        if (std::abs(lay71C.brirAzimuthDeg[0] - kGateDExpAzimL) > kGateDazimTol)
        {
            return "7_1_C: slot0 (L) brirAzimuthDeg != +30";
        }
        return {};
    }

    // Unknown tag — neutral fallback: numChannels from tag bits, all weights 1.0, no LFE.
    auto gateDCheckUnknown() -> std::string
    {
        constexpr uint32_t kFakeChCount = 4U;
        constexpr AudioChannelLayoutTag kUnknownTag =
            static_cast<AudioChannelLayoutTag>((0xFFFFU << 16U) | kFakeChCount);
        const ChannelLayout layUnk = decodeChannelLayout(kUnknownTag);
        if (layUnk.numChannels != kFakeChCount)
        {
            return "unknown tag: numChannels != 4";
        }
        for (uint32_t ch = 0U; ch < kFakeChCount; ++ch)
        {
            if (std::abs(layUnk.lufsWeight[ch] - kGateDExpLRC) > kGateDWeightTol)
            {
                return "unknown tag: slot" + std::to_string(ch) + " lufsWeight != 1.0";
            }
            if (layUnk.isLfe[ch] != 0U)
            {
                return "unknown tag: slot" + std::to_string(ch) + " isLfe != 0";
            }
        }
        return {};
    }
} // namespace

static auto testChannelLayoutDecodeGateD() -> void
{
    static const char* const kName = "ChannelLayout_Decode_GateD";

    // Run each sub-case; bail on the first failure (matches the pattern used
    // by all other Gate tests in this suite).
    const std::string stereoErr = gateDCheckStereo();
    if (!stereoErr.empty())
    {
        logFail(kName, stereoErr);
        return;
    }

    const std::string err51A = gateDCheck51A();
    if (!err51A.empty())
    {
        logFail(kName, err51A);
        return;
    }

    const std::string err51B = gateDCheck51B();
    if (!err51B.empty())
    {
        logFail(kName, err51B);
        return;
    }

    const std::string err71A = gateDCheck71A();
    if (!err71A.empty())
    {
        logFail(kName, err71A);
        return;
    }

    const std::string err71C = gateDCheck71C();
    if (!err71C.empty())
    {
        logFail(kName, err71C);
        return;
    }

    const std::string errUnk = gateDCheckUnknown();
    if (!errUnk.empty())
    {
        logFail(kName, errUnk);
        return;
    }

    logPass(kName);
}

// ---------------------------------------------------------------------------
// M1-2 Gate E: Loudness_DecodedLayout_Weights
// ---------------------------------------------------------------------------

// Sub-case (b): Surround weight and LFE exclusion via decoded weights.
// Measures Ls+Rs vs L+R delta (must be in [minDelta,maxDelta]) and confirms
// LFE-only signal reads silence.  Returns "" on pass, non-empty on failure.
static auto decodedSubcaseSurroundAndLfe(const char* kName,
                                         const std::array<double, kMaxChannels>& weights,
                                         uint32_t kSR,
                                         double kDuration,
                                         double kPeak,
                                         double minDelta,
                                         double maxDelta) -> std::string
{
    LufsMeter meterSurr;
    meterSurr.prepare(kSR);
    meterSurr.configureChannels(kNum51Channels, weights);
    {
        const auto buf = makeInterleavedNch2Active(kNum51Channels, 4U, 5U, kPeak, kDuration, kSR);
        meterSurr.addInterleaved(buf.data(), static_cast<size_t>(kDuration * kSR), kNum51Channels);
    }
    const double lufsSurr = meterSurr.integratedLufs();

    LufsMeter meterLR;
    meterLR.prepare(kSR);
    meterLR.configureChannels(kNum51Channels, weights);
    {
        const auto buf = makeInterleavedNch2Active(kNum51Channels, 0U, 1U, kPeak, kDuration, kSR);
        meterLR.addInterleaved(buf.data(), static_cast<size_t>(kDuration * kSR), kNum51Channels);
    }
    const double lufsLR = meterLR.integratedLufs();

    const double surroundDelta = lufsSurr - lufsLR;
    std::ostringstream infoB;
    infoB << "  [info] " << kName << " (b): lufsSurr=" << lufsSurr << " lufsLR=" << lufsLR
          << " delta=" << surroundDelta << "\n";
    logInfo(infoB.str());

    if (surroundDelta < minDelta || surroundDelta > maxDelta)
    {
        std::ostringstream oss;
        oss << "(b) surround weight delta=" << surroundDelta << " not in [" << minDelta << ", "
            << maxDelta << "] (expected ~+1.5 dB from decoded G=1.41)";
        return oss.str();
    }

    LufsMeter meterLfe;
    meterLfe.prepare(kSR);
    meterLfe.configureChannels(kNum51Channels, weights);
    {
        const auto buf = makeInterleavedNch(kNum51Channels, 3U, kPeak, kDuration, kSR);
        meterLfe.addInterleaved(buf.data(), static_cast<size_t>(kDuration * kSR), kNum51Channels);
    }
    const double lufsLfe = meterLfe.integratedLufs();
    std::ostringstream infoLfe;
    infoLfe << "  [info] " << kName << " (b-lfe): lufsLfe=" << lufsLfe << "\n";
    logInfo(infoLfe.str());

    if (lufsLfe > kAbsoluteGateLufs)
    {
        std::ostringstream oss;
        oss << "(b) LFE channel with decoded weight 0.0 reads " << lufsLfe
            << " LUFS (expected <= " << kAbsoluteGateLufs << " / silence)";
        return oss.str();
    }
    return {};
}

// Sub-case (c): Full 5.1 all-channels-same-sine vs. independent oracle.
// All 6 channels carry the same 1 kHz sine at kPeak; LFE weight=0 so it
// contributes nothing.  Returns "" on pass, non-empty on failure.
static auto decodedSubcaseOracleFullSine(const char* kName,
                                         const std::array<double, kMaxChannels>& weights,
                                         uint32_t kSR,
                                         double kDuration,
                                         double kPeak,
                                         double oracleTol) -> std::string
{
    const auto frames51 = static_cast<size_t>(kDuration * kSR);
    const double amp = std::pow(10.0, kPeak / 20.0);
    std::vector<float> buf51full(frames51 * kNum51Channels, 0.0F);
    for (size_t frm = 0U; frm < frames51; ++frm)
    {
        const double s = amp * std::sin(2.0 * std::numbers::pi * 1000.0 * static_cast<double>(frm) /
                                        static_cast<double>(kSR));
        for (uint32_t ch = 0U; ch < kNum51Channels; ++ch)
        {
            buf51full[(frm * kNum51Channels) + ch] = static_cast<float>(s);
        }
    }

    LufsMeter meterFull;
    meterFull.prepare(kSR);
    meterFull.configureChannels(kNum51Channels, weights);
    meterFull.addInterleaved(buf51full.data(), frames51, kNum51Channels);
    const double lufsFull = meterFull.integratedLufs();

    const double lufsOracle = oracleIntegratedLufs(buf51full, kNum51Channels, weights, kSR);
    const double deltaC = std::abs(lufsFull - lufsOracle);

    std::ostringstream infoC;
    infoC << "  [info] " << kName << " (c): meter=" << lufsFull << " oracle=" << lufsOracle
          << " delta=" << deltaC << "\n";
    logInfo(infoC.str());

    if (deltaC > oracleTol)
    {
        std::ostringstream oss;
        oss << "(c) decoded-weight meter=" << lufsFull << " vs oracle=" << lufsOracle
            << " delta=" << deltaC << " > " << oracleTol << " LU";
        return oss.str();
    }
    return {};
}

static auto testLoudnessDecodedLayoutWeights() -> void
{
    static const char* const kName = "Loudness_DecodedLayout_Weights";
    constexpr uint32_t kSR = TestConstants::kSampleRate48k;
    constexpr double kDuration = 15.0;
    constexpr double kPeak = -23.0;           // dBFS
    constexpr double kSurroundDeltaMin = 1.0; // surrounds must read ≥ 1 dB above L+R
    constexpr double kSurroundDeltaMax = 2.0; // and ≤ 2 dB above (tolerance on +1.5 dB)
    constexpr double kOracleTol = 0.2;        // ±0.2 LU vs. oracle

    // Decode the 5.1-A layout (L R C LFE Ls Rs) to obtain BS.1770-5 weights.
    const ChannelLayout decoded51A = decodeChannelLayout(kAudioChannelLayoutTag_MPEG_5_1_A);
    std::array<double, kMaxChannels> decodedWeights{};
    for (uint32_t ch = 0U; ch < kMaxChannels; ++ch)
    {
        decodedWeights[ch] = static_cast<double>(decoded51A.lufsWeight[ch]);
    }

    std::string err = decodedSubcaseSurroundAndLfe(
        kName, decodedWeights, kSR, kDuration, kPeak, kSurroundDeltaMin, kSurroundDeltaMax);
    if (!err.empty())
    {
        logFail(kName, err);
        return;
    }

    err = decodedSubcaseOracleFullSine(kName, decodedWeights, kSR, kDuration, kPeak, kOracleTol);
    if (!err.empty())
    {
        logFail(kName, err);
        return;
    }

    logPass(kName);
}
