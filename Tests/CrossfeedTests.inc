// CrossfeedTests.inc
//
// QW1 §6 — crossfeed DSP conformance (CF-1..CF-9). The crossfeed stage is fully gated in this
// C++ harness; CF-10 (ebur128 neutrality) lives in LoudnessOracleTests.inc, CF-11 (4-surface
// Realizer RMW) in RealizerTests.inc, CF-12 (RT-alloc soak) in SoakRtAllocTests.inc.
//
// #included into Tests/DSPKernelNullTest.cpp after IntensityTests.inc.
//
// Tests:
//   CF-1 Crossfeed_Bypass_BitExact_GoldenMaster  — module present-but-off re-asserts the hash.
//   CF-2 Crossfeed_NonStereo_PassThrough          — N=1 / N=6 byte-identical.
//   CF-3 Crossfeed_Mono_LevelNeutral              — mono (L==R) sum loudness-neutral.
//   CF-4 Crossfeed_ChannelSeparation              — cross/direct = alpha per preset, both ways.
//   CF-5 Crossfeed_LpfCharacteristic              — -3 dB at fc; >=9 dB down at 8 kHz.
//   CF-6 Crossfeed_NoNaNInf                       — noise / transient / DC stay finite.
//   CF-7 Crossfeed_ClickFreeEnableDisable         — boundaryStep <= 3x settledMaxStep.
//   CF-8 Crossfeed_CoeffRecomputeAcrossRates      — separation consistent 44.1/48/192k; D<64.
//   CF-9 Crossfeed_ReadBothWriteBoth              — distinct L/R tones vs analytic (the #1 bug).

#include "../Sources/AudioDSP/AudioEngine/Realizer.h"
#include "../Sources/AudioDSP/Spatial/CrossfeedModule.h"

namespace
{
    // Crossfeed preset indices (mirror CrossfeedPreset; named to avoid magic numbers).
    constexpr uint32_t kCfPresetRelaxed = 0U;
    constexpr uint32_t kCfPresetBauer = 1U; // Swift-facing "Default"
    constexpr uint32_t kCfPresetStrong = 2U;

    // Reference alpha / fc per preset (QW1 §2 table) — the analytic targets the tests compare to.
    constexpr float kCfAlphaRelaxed = 0.335F;
    constexpr float kCfAlphaBauer = 0.355F;
    constexpr float kCfAlphaStrong = 0.501F;
    constexpr float kCfFcRelaxed = 650.0F;
    constexpr float kCfFcBauer = 700.0F;
    constexpr float kCfFcStrong = 700.0F;

    // Derive a CrossfeedParams POD using the SHIPPING off-RT derivation path (the Realizer), so the
    // tests exercise the exact coefficient math production uses. A throwaway Realizer + a fresh
    // kernel is cheap; applyCrossfeed packs the canonical state synchronously on this thread.
    auto deriveCfParams(uint32_t enabled, float level, uint32_t preset, uint32_t sampleRate)
        -> CrossfeedParams
    {
        auto kernel = std::make_shared<DSPKernel>();
        kernel->initialize(sampleRate, TestConstants::kFrames512);
        auto realizer = std::make_shared<AdaptiveSound::Realizer>(kernel);
        realizer->applyCrossfeed(enabled, level, preset, static_cast<double>(sampleRate));
        const CrossfeedParams params = realizer->canonicalState().crossfeed;
        realizer->shutdown();
        return params;
    }

    // Run a stereo pair (L,R buffers) through a freshly-initialised CrossfeedModule at a fixed
    // params, returning the processed L,R. The module snaps its mix ramp to off in initialize(),
    // so we WARM it (feed the same input repeatedly) to drive the ramp to its settled state before
    // capturing — matching the runIntensityOnce warm-up pattern.
    struct StereoOut
    {
        std::vector<float> left;
        std::vector<float> right;
    };

    auto runCrossfeedSettled(const CrossfeedParams& params, uint32_t sampleRate,
                             const std::vector<float>& inL, const std::vector<float>& inR)
        -> StereoOut
    {
        const auto frames = static_cast<uint32_t>(inL.size());
        constexpr uint32_t kWarm = 256U; // >> 5 tau so the mix ramp settles before capture
        CrossfeedModule module;
        module.initialize(sampleRate, frames);

        TestABL abl(frames);
        for (uint32_t b = 0U; b <= kWarm; ++b)
        {
            std::memcpy(abl.left.data(), inL.data(), frames * sizeof(float));
            std::memcpy(abl.right.data(), inR.data(), frames * sizeof(float));
            const MultichannelView view = MultichannelView::fromABL(abl.abl(), frames);
            module.process(params, view);
        }
        return StereoOut{abl.left, abl.right};
    }
} // namespace

// ===========================================================================
// CF-1: bypass is bit-exact (module present-but-off) → re-asserts the golden master hash.
// This is the canary: with crossfeed inserted into the chain but DISABLED, the full stereo
// chain output must hash to exactly 0xE7267654BA01D315 (zero tolerance). It reuses the same
// chirp + non-trivial state as GoldenMaster_StereoN2_v1; the default-off CrossfeedParams keep
// the chain byte-identical to the pre-QW1 output.
// ===========================================================================
static auto testCrossfeedBypassBitExactGoldenMaster() -> void
{
    static const char* const kName = "Crossfeed_Bypass_BitExact_GoldenMaster";
    constexpr uint32_t kSR = TestConstants::kSampleRate48k;
    constexpr uint32_t kChunk = TestConstants::kFrames512;
    constexpr uint32_t kTotal = TestConstants::kTotalFrames1s;
    constexpr float kBoostDb = 6.0F;
    constexpr uint64_t kGoldenHash = 0xE7267654BA01D315ULL;
    constexpr uint64_t kFnvOffsetBasis = 0xCBF29CE484222325ULL;

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

    DSPKernel kernel;
    kernel.initialize(kSR, kChunk);
    TargetState state = makeIdentityState();
    std::array<float, kEqBands> gains{};
    gains[kBand1kHzIndex] = kBoostDb;
    state.eq = EQModuleCoefficients::computeBiquadCascade(gains, static_cast<float>(kSR));
    state.limiter.truePeakCeilingLinear = kTruePeakCeilingLinear; // active
    // Crossfeed explicitly OFF (the default; stated for documentary clarity).
    state.crossfeed = CrossfeedParams{};
    kernel.publishTargetState(state);

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
        oss << "golden-master hash mismatch with crossfeed present-but-off: got 0x" << std::hex
            << hash << ", expected 0x" << kGoldenHash << " — crossfeed broke the bypass anchor";
        logFail(kName, oss.str());
        return;
    }
    logPass(kName);
}

// ===========================================================================
// CF-2: non-stereo pass-through. N=1 and N=6 must be byte-identical even with crossfeed ENABLED
// (the module is stereo-only; channels()!=2 → early-return bit-exact).
// ===========================================================================
static auto testCrossfeedNonStereoPassThrough() -> void
{
    static const char* const kName = "Crossfeed_NonStereo_PassThrough";
    constexpr uint32_t kSR = TestConstants::kSampleRate48k;
    constexpr uint32_t kFrames = TestConstants::kFrames512;

    const CrossfeedParams params = deriveCfParams(1U, 1.0F, kCfPresetBauer, kSR);

    for (const uint32_t numCh : {TestConstants::kMono, TestConstants::kNChannels6})
    {
        CrossfeedModule module;
        module.initialize(kSR, kFrames);

        TestABLN abl(numCh, kFrames);
        std::vector<std::vector<float>> reference(numCh);
        for (uint32_t ch = 0U; ch < numCh; ++ch)
        {
            for (uint32_t i = 0U; i < kFrames; ++i)
            {
                const float s = 0.3F * std::sin(2.0F * std::numbers::pi_v<float> *
                                                 (200.0F + 50.0F * static_cast<float>(ch)) *
                                                 static_cast<float>(i) / static_cast<float>(kSR));
                abl.channels[ch][i] = s;
            }
            reference[ch] = abl.channels[ch];
        }

        const MultichannelView view = MultichannelView::fromABL(abl.abl(), kFrames);
        module.process(params, view);

        for (uint32_t ch = 0U; ch < numCh; ++ch)
        {
            if (std::memcmp(abl.channels[ch].data(), reference[ch].data(),
                            kFrames * sizeof(float)) != 0)
            {
                std::ostringstream oss;
                oss << "N=" << numCh << " ch" << ch << " not byte-identical (stereo-only gate broken)";
                logFail(kName, oss.str());
                return;
            }
        }
    }
    logPass(kName);
}

// ===========================================================================
// CF-3: mono level-neutral. For a MONO source (L==R), the gain-neutral design (gDirect=1/(1+α),
// gCross=α/(1+α)) makes the steady-state sum loudness-neutral: at DC/low frequency the cross-path
// LPF passes near-unity, so Lout = (gDirect+gCross)·L = ((1+α)/(1+α))·L = L. We probe with a LOW
// (60 Hz) mono tone — well below every preset fc — where the design's "sum is unity" claim is the
// operative one: |Δ| <= 0.1 dB Bauer ("Default"), <= 0.3 dB Strong.
//
// (At HIGHER frequencies the cross-path LPF deliberately attenuates the cross contribution → the
// summed mono level falls; that is the inherent, benign crossfeed coloration the design flags
// (QW1 §2 risk 1), NOT a level-neutrality violation. CF-10's ebur128 oracle covers real-content
// loudness; CF-5 covers the LPF shape.)
// ===========================================================================
static auto testCrossfeedMonoLevelNeutral() -> void
{
    static const char* const kName = "Crossfeed_Mono_LevelNeutral";
    constexpr uint32_t kSR = TestConstants::kSampleRate48k;
    constexpr uint32_t kFrames = 16384U;
    constexpr float kLowToneHz = 60.0F; // << every preset fc → cross-path LPF ~ unity

    // Correlated (mono) low-frequency tone — the design's loudness-neutral case.
    std::vector<float> mono(kFrames);
    for (uint32_t i = 0U; i < kFrames; ++i)
    {
        mono[i] = 0.25F * std::sin(2.0F * std::numbers::pi_v<float> * kLowToneHz *
                                   static_cast<float>(i) / static_cast<float>(kSR));
    }

    struct Case
    {
        const char* label;
        uint32_t preset;
        double tolDb;
    };
    const std::array<Case, 2U> cases = {{
        {"Bauer", kCfPresetBauer, 0.1},
        {"Strong", kCfPresetStrong, 0.3},
    }};

    std::string fail;
    double measuredBauer = 0.0;
    double measuredStrong = 0.0;
    for (const auto& c : cases)
    {
        const CrossfeedParams params = deriveCfParams(1U, 1.0F, c.preset, kSR);
        const StereoOut out = runCrossfeedSettled(params, kSR, mono, mono);

        // Measure the settled second half (after the mix ramp + delay line fill).
        const double inRms = sliceRms(mono, kFrames / 2U, kFrames);
        const double outRms = sliceRms(out.left, kFrames / 2U, kFrames);
        if (inRms <= 0.0)
        {
            fail += "\n  input RMS is zero";
            continue;
        }
        const double deltaDb = 20.0 * std::log10(outRms / inRms);
        if (c.preset == kCfPresetBauer) { measuredBauer = deltaDb; }
        if (c.preset == kCfPresetStrong) { measuredStrong = deltaDb; }

        std::ostringstream info;
        info << "  [info] " << kName << ": " << c.label << " mono level delta = " << deltaDb
             << " dB (tol +-" << c.tolDb << ")\n";
        logInfo(info.str());

        if (std::abs(deltaDb) > c.tolDb)
        {
            std::ostringstream oss;
            oss << "\n  " << c.label << " mono level delta " << deltaDb << " dB exceeds +-" << c.tolDb;
            fail += oss.str();
        }
    }

    std::ostringstream summary;
    summary << "  [measured] CF-3 mono level-neutral: Bauer=" << measuredBauer
            << " dB, Strong=" << measuredStrong << " dB\n";
    logInfo(summary.str());

    if (!fail.empty())
    {
        logFail(kName, "mono level neutrality failure:" + fail);
        return;
    }
    logPass(kName);
}

// ===========================================================================
// CF-4: channel separation. Feed a tone in ONE channel only (the other silent); the cross-channel
// leakage at the output relative to the direct channel must equal the preset's cross-level alpha
// (in dB), within tolerance, in BOTH directions (L-only and R-only). Measured at a LOW frequency
// (well below fc) so the LPF passes the cross path near-unity, isolating the gain ratio.
//   Relaxed: -9.5 dB +-1.5,  Bauer: -9.0 +-1.5,  Strong: -6.0 +-1.5.
// gCross/gDirect = (α/(1+α)) / (1/(1+α)) = α, so 20·log10(α) is the analytic separation.
// ===========================================================================
static auto testCrossfeedChannelSeparation() -> void
{
    static const char* const kName = "Crossfeed_ChannelSeparation";
    constexpr uint32_t kSR = TestConstants::kSampleRate48k;
    constexpr uint32_t kFrames = 16384U;
    constexpr float kProbeHz = 120.0F; // well below every preset fc → LPF ~ unity on the cross path
    constexpr double kTolDb = 1.5;

    std::vector<float> tone(kFrames);
    const std::vector<float> silence(kFrames, 0.0F);
    for (uint32_t i = 0U; i < kFrames; ++i)
    {
        tone[i] = 0.25F * std::sin(2.0F * std::numbers::pi_v<float> * kProbeHz *
                                   static_cast<float>(i) / static_cast<float>(kSR));
    }

    struct Case
    {
        const char* label;
        uint32_t preset;
        float alpha;
    };
    const std::array<Case, 3U> cases = {{
        {"Relaxed", kCfPresetRelaxed, kCfAlphaRelaxed},
        {"Bauer", kCfPresetBauer, kCfAlphaBauer},
        {"Strong", kCfPresetStrong, kCfAlphaStrong},
    }};

    std::string fail;
    double measuredBauer = 0.0;
    double measuredRelaxed = 0.0;
    double measuredStrong = 0.0;
    for (const auto& c : cases)
    {
        const CrossfeedParams params = deriveCfParams(1U, 1.0F, c.preset, kSR);
        const double expectedDb = 20.0 * std::log10(static_cast<double>(c.alpha));

        // L-only: tone in L, silence in R. The CROSS into R is the leakage; the DIRECT in L is the
        // reference. Measure RMS over the second half (after the ramp + delay-line fill settle).
        const StereoOut outL = runCrossfeedSettled(params, kSR, tone, silence);
        const double directL = sliceRms(outL.left, kFrames / 2U, kFrames);
        const double crossToR = sliceRms(outL.right, kFrames / 2U, kFrames);

        // R-only: tone in R, silence in L → cross into L.
        const StereoOut outR = runCrossfeedSettled(params, kSR, silence, tone);
        const double directR = sliceRms(outR.right, kFrames / 2U, kFrames);
        const double crossToL = sliceRms(outR.left, kFrames / 2U, kFrames);

        if (directL <= 0.0 || directR <= 0.0)
        {
            fail += "\n  direct-channel RMS is zero";
            continue;
        }
        const double sepLtoR = 20.0 * std::log10(crossToR / directL);
        const double sepRtoL = 20.0 * std::log10(crossToL / directR);
        if (c.preset == kCfPresetBauer) { measuredBauer = sepLtoR; }
        if (c.preset == kCfPresetRelaxed) { measuredRelaxed = sepLtoR; }
        if (c.preset == kCfPresetStrong) { measuredStrong = sepLtoR; }

        std::ostringstream info;
        info << "  [info] " << kName << ": " << c.label << " sep L->R=" << sepLtoR
             << " dB R->L=" << sepRtoL << " dB (expected " << expectedDb << " +-" << kTolDb << ")\n";
        logInfo(info.str());

        if (std::abs(sepLtoR - expectedDb) > kTolDb || std::abs(sepRtoL - expectedDb) > kTolDb)
        {
            std::ostringstream oss;
            oss << "\n  " << c.label << " separation L->R=" << sepLtoR << " R->L=" << sepRtoL
                << " expected " << expectedDb << " +-" << kTolDb;
            fail += oss.str();
        }
    }

    std::ostringstream summary;
    summary << "  [measured] CF-4 separation (L->R): Relaxed=" << measuredRelaxed
            << " dB, Bauer=" << measuredBauer << " dB, Strong=" << measuredStrong << " dB\n";
    logInfo(summary.str());

    if (!fail.empty())
    {
        logFail(kName, "channel-separation failure:" + fail);
        return;
    }
    logPass(kName);
}

// ===========================================================================
// CF-5: LPF characteristic on the cross path. Probe the cross-channel leakage (tone in one
// channel, measure the other) at fc and at 8 kHz, normalised to the low-frequency (120 Hz)
// leakage. The one-pole LPF must be ~-3 dB at fc and >= 9 dB down at 8 kHz, relative to the LF
// reference. Use the Bauer preset (fc = 700 Hz).
// ===========================================================================
static auto testCrossfeedLpfCharacteristic() -> void
{
    static const char* const kName = "Crossfeed_LpfCharacteristic";
    constexpr uint32_t kSR = TestConstants::kSampleRate48k;
    constexpr uint32_t kFrames = 32768U;
    constexpr float kFc = kCfFcBauer;     // 700 Hz
    constexpr float kRefHz = 120.0F;      // LF reference (LPF ~ unity)
    constexpr float k8kHz = 8000.0F;

    const CrossfeedParams params = deriveCfParams(1U, 1.0F, kCfPresetBauer, kSR);

    // Cross-channel RMS for a tone at freqHz placed in L only (leakage appears in R).
    const auto crossRmsAt = [&](float freqHz) -> double
    {
        std::vector<float> tone(kFrames);
        const std::vector<float> silence(kFrames, 0.0F);
        for (uint32_t i = 0U; i < kFrames; ++i)
        {
            tone[i] = 0.25F * std::sin(2.0F * std::numbers::pi_v<float> * freqHz *
                                       static_cast<float>(i) / static_cast<float>(kSR));
        }
        const StereoOut out = runCrossfeedSettled(params, kSR, tone, silence);
        return sliceRms(out.right, kFrames / 2U, kFrames);
    };

    const double ref = crossRmsAt(kRefHz);
    if (ref <= 0.0)
    {
        logFail(kName, "LF reference cross RMS is zero");
        return;
    }
    const double atFcDb = 20.0 * std::log10(crossRmsAt(kFc) / ref);
    const double at8kDb = 20.0 * std::log10(crossRmsAt(k8kHz) / ref);

    std::ostringstream info;
    info << "  [info] " << kName << ": LPF @ fc(" << kFc << ")=" << atFcDb << " dB, @ 8kHz="
         << at8kDb << " dB (rel. to " << kRefHz << " Hz)\n";
    logInfo(info.str());

    std::string fail;
    // -3 dB at fc, +-1.0 dB slack (one-pole exact-RC is -3.01 dB at fc by construction).
    if (std::abs(atFcDb - (-3.0)) > 1.0)
    {
        std::ostringstream oss;
        oss << "\n  LPF at fc=" << atFcDb << " dB, expected ~-3 dB +-1.0";
        fail += oss.str();
    }
    // >= 9 dB down at 8 kHz (a one-pole gives ~21 dB down here; 9 dB is a conservative floor).
    if (at8kDb > -9.0)
    {
        std::ostringstream oss;
        oss << "\n  LPF at 8kHz=" << at8kDb << " dB, expected <= -9 dB";
        fail += oss.str();
    }
    if (!fail.empty())
    {
        logFail(kName, "LPF characteristic failure:" + fail);
        return;
    }
    logPass(kName);
}

// ===========================================================================
// CF-6: no NaN / Inf for noise, a transient, and DC. Crossfeed enabled (Strong, the deepest).
// ===========================================================================
static auto testCrossfeedNoNaNInf() -> void
{
    static const char* const kName = "Crossfeed_NoNaNInf";
    constexpr uint32_t kSR = TestConstants::kSampleRate48k;
    constexpr uint32_t kFrames = 4096U;

    const CrossfeedParams params = deriveCfParams(1U, 1.0F, kCfPresetStrong, kSR);

    // Battery: white noise, a unit transient (impulse at 0), and DC.
    std::vector<std::pair<std::vector<float>, std::vector<float>>> battery;
    {
        std::vector<float> nL(kFrames);
        std::vector<float> nR(kFrames);
        // NOLINTBEGIN(cert-msc32-c,cert-msc51-cpp)
        std::mt19937 gen(0xBADF00DU);
        // NOLINTEND(cert-msc32-c,cert-msc51-cpp)
        std::uniform_real_distribution<float> dist(-0.9F, 0.9F);
        for (uint32_t i = 0U; i < kFrames; ++i)
        {
            nL[i] = dist(gen);
            nR[i] = dist(gen);
        }
        battery.emplace_back(nL, nR);
    }
    {
        std::vector<float> tL(kFrames, 0.0F);
        std::vector<float> tR(kFrames, 0.0F);
        tL[0] = 1.0F;
        tR[0] = -1.0F;
        battery.emplace_back(tL, tR);
    }
    {
        const std::vector<float> dcL(kFrames, 0.5F);
        const std::vector<float> dcR(kFrames, -0.5F);
        battery.emplace_back(dcL, dcR);
    }

    for (size_t c = 0U; c < battery.size(); ++c)
    {
        const StereoOut out = runCrossfeedSettled(params, kSR, battery[c].first, battery[c].second);
        for (uint32_t i = 0U; i < kFrames; ++i)
        {
            if (!std::isfinite(out.left[i]) || !std::isfinite(out.right[i]))
            {
                logFail(kName, "non-finite output in battery case " + std::to_string(c));
                return;
            }
        }
    }
    logPass(kName);
}

// ===========================================================================
// CF-7: click-free enable/disable. Feed a phase-continuous tone; toggle crossfeed ENABLED
// mid-stream, then DISABLED again. The step across each boundary must be <= 3x the settled
// per-sample step (the EQ-swap no-click bound). The 32 ms mix ramp guarantees this.
// ===========================================================================
static auto testCrossfeedClickFreeEnableDisable() -> void
{
    static const char* const kName = "Crossfeed_ClickFreeEnableDisable";
    constexpr uint32_t kSR = TestConstants::kSampleRate48k;
    constexpr uint32_t kBlock = TestConstants::kFrames512;
    constexpr uint32_t kBlocks = 64U; // ~0.68 s — ample to settle the ramp each phase
    constexpr float kToneHz = 440.0F;

    // Toggling crossfeed off keeps the strength selection (the UI flow): same level+preset, only
    // enabled flips. The off POD therefore carries the active coefficients so the module's mix ramp
    // glides the still-crossfed wet down to dry (click-free), then settles bit-exact.
    const CrossfeedParams onParams = deriveCfParams(1U, 1.0F, kCfPresetStrong, kSR);
    const CrossfeedParams offParams = deriveCfParams(0U, 1.0F, kCfPresetStrong, kSR);

    CrossfeedModule module;
    module.initialize(kSR, kBlock);

    std::vector<float> outL;
    outL.reserve(static_cast<size_t>(kBlock) * kBlocks * 3U);
    uint32_t sampleIdx = 0U;

    const auto runPhase = [&](const CrossfeedParams& p, uint32_t blocks) -> void
    {
        for (uint32_t b = 0U; b < blocks; ++b)
        {
            TestABL abl(kBlock);
            for (uint32_t i = 0U; i < kBlock; ++i)
            {
                const float s = 0.3F * std::sin(2.0F * std::numbers::pi_v<float> * kToneHz *
                                                static_cast<float>(sampleIdx + i) /
                                                static_cast<float>(kSR));
                abl.left[i] = s;
                abl.right[i] = s;
            }
            sampleIdx += kBlock;
            const MultichannelView view = MultichannelView::fromABL(abl.abl(), kBlock);
            module.process(p, view);
            for (uint32_t i = 0U; i < kBlock; ++i)
            {
                outL.push_back(abl.left[i]);
            }
        }
    };

    runPhase(offParams, kBlocks);
    const size_t enableBoundary = outL.size();
    runPhase(onParams, kBlocks);
    const size_t onSettledEnd = outL.size(); // end of the (settled) ON phase
    const size_t disableBoundary = outL.size();
    runPhase(offParams, kBlocks);

    // The no-click bound compares the transition step to the SETTLED per-sample step of the SAME
    // regime — the crossfed (ON) waveform has steeper intrinsic slopes than the dry (OFF) tone
    // (the delayed+filtered cross path adds slew), so a single dry-regime reference would unfairly
    // flag the crossfed signal's own steps as a "click". We take the max settled step across BOTH
    // a settled OFF block (final block) and a settled ON block (last block of the on phase).
    const auto maxStepInBlock = [&](size_t end) -> float
    {
        float m = 0.0F;
        for (size_t i = end - kBlock + 1U; i < end; ++i)
        {
            m = std::max(m, std::abs(outL[i] - outL[i - 1U]));
        }
        return m;
    };
    const float offSettledStep = maxStepInBlock(outL.size());
    const float onSettledStep = maxStepInBlock(onSettledEnd);
    const float settledMaxStep = std::max(offSettledStep, onSettledStep);
    const float enableStep = std::abs(outL[enableBoundary] - outL[enableBoundary - 1U]);
    const float disableStep = std::abs(outL[disableBoundary] - outL[disableBoundary - 1U]);

    std::ostringstream info;
    info << "  [info] " << kName << ": enableStep=" << enableStep << " disableStep=" << disableStep
         << " settledMaxStep=" << settledMaxStep << " (off=" << offSettledStep
         << " on=" << onSettledStep << ")\n";
    logInfo(info.str());

    if (settledMaxStep <= 0.0F)
    {
        logFail(kName, "settled step is zero (tone not present?)");
        return;
    }
    if (enableStep > 3.0F * settledMaxStep || disableStep > 3.0F * settledMaxStep)
    {
        std::ostringstream oss;
        oss << "audible toggle click: enableStep=" << enableStep << " disableStep=" << disableStep
            << " > 3x settledMaxStep=" << settledMaxStep;
        logFail(kName, oss.str());
        return;
    }
    logPass(kName);
}

// ===========================================================================
// CF-8: coefficient recompute on sample-rate change. The Realizer re-derives the POD per rate;
// channel separation (alpha) must be consistent within +-0.5 dB across 44.1/48/192 kHz, and the
// derived ITD delayFrames must satisfy < 64 at every rate (the fixed-line invariant).
// ===========================================================================
static auto testCrossfeedCoeffRecomputeAcrossRates() -> void
{
    static const char* const kName = "Crossfeed_CoeffRecomputeAcrossRates";
    constexpr float kProbeHz = 120.0F; // LF: LPF ~ unity so we isolate the alpha gain
    constexpr uint32_t kFrames = 16384U;
    constexpr double kConsistencyTolDb = 0.5;

    const std::array<uint32_t, 3U> rates = {44100U, 48000U, 192000U};
    const double expectedDb = 20.0 * std::log10(static_cast<double>(kCfAlphaBauer));

    std::string fail;
    double firstSep = 0.0;
    bool haveFirst = false;
    for (const uint32_t sr : rates)
    {
        const CrossfeedParams params = deriveCfParams(1U, 1.0F, kCfPresetBauer, sr);

        // Fixed-line invariant: derived ITD must fit the 64-tap delay line at every rate.
        if (params.delayFrames < 0 || params.delayFrames >= kMaxCrossfeedDelayFrames)
        {
            std::ostringstream oss;
            oss << "\n  delayFrames=" << params.delayFrames << " at " << sr
                << " Hz violates < " << kMaxCrossfeedDelayFrames;
            fail += oss.str();
        }

        std::vector<float> tone(kFrames);
        const std::vector<float> silence(kFrames, 0.0F);
        for (uint32_t i = 0U; i < kFrames; ++i)
        {
            tone[i] = 0.25F * std::sin(2.0F * std::numbers::pi_v<float> * kProbeHz *
                                       static_cast<float>(i) / static_cast<float>(sr));
        }
        const StereoOut out = runCrossfeedSettled(params, sr, tone, silence);
        const double direct = sliceRms(out.left, kFrames / 2U, kFrames);
        const double cross = sliceRms(out.right, kFrames / 2U, kFrames);
        if (direct <= 0.0)
        {
            fail += "\n  direct RMS zero";
            continue;
        }
        const double sepDb = 20.0 * std::log10(cross / direct);

        std::ostringstream info;
        info << "  [info] " << kName << ": " << sr << " Hz sep=" << sepDb << " dB delayFrames="
             << params.delayFrames << " (expected sep " << expectedDb << ")\n";
        logInfo(info.str());

        if (!haveFirst)
        {
            firstSep = sepDb;
            haveFirst = true;
        }
        else if (std::abs(sepDb - firstSep) > kConsistencyTolDb)
        {
            std::ostringstream oss;
            oss << "\n  separation drift at " << sr << " Hz: " << sepDb << " dB vs " << firstSep
                << " dB (> " << kConsistencyTolDb << ")";
            fail += oss.str();
        }
    }

    if (!fail.empty())
    {
        logFail(kName, "coeff-recompute consistency failure:" + fail);
        return;
    }
    logPass(kName);
}

// ===========================================================================
// CF-9: read-both-then-write-both guard (the #1 crossfeed bug). Feed DISTINCT L and R tones at
// different frequencies. The output L must contain the analytic blend gDirect·L + gCross·(LPF·
// delayed·R), and likewise for R — NOT a value contaminated by the just-written L. We verify by
// reconstructing the expected output OFFLINE with the same coefficients and comparing per-sample
// (steady-state region) within +-1 dB of the measured-vs-analytic energy. A read-one/write-one
// bug would feed the freshly-written L into R's cross path → measurable divergence.
// ===========================================================================
static auto testCrossfeedReadBothWriteBoth() -> void
{
    static const char* const kName = "Crossfeed_ReadBothWriteBoth";
    constexpr uint32_t kSR = TestConstants::kSampleRate48k;
    constexpr uint32_t kFrames = 16384U;
    constexpr float kFreqL = 300.0F;
    constexpr float kFreqR = 900.0F;

    const CrossfeedParams params = deriveCfParams(1U, 1.0F, kCfPresetBauer, kSR);

    std::vector<float> inL(kFrames);
    std::vector<float> inR(kFrames);
    for (uint32_t i = 0U; i < kFrames; ++i)
    {
        inL[i] = 0.3F * std::sin(2.0F * std::numbers::pi_v<float> * kFreqL *
                                 static_cast<float>(i) / static_cast<float>(kSR));
        inR[i] = 0.3F * std::sin(2.0F * std::numbers::pi_v<float> * kFreqR *
                                 static_cast<float>(i) / static_cast<float>(kSR));
    }

    const StereoOut out = runCrossfeedSettled(params, kSR, inL, inR);

    // Offline reference (mix fully settled to 1.0). Reproduce the exact per-sample math:
    //   crossToL[n] = LPF(delayed R)[n];  outL[n] = gDirect·L[n] + gCross·crossToL[n].
    const auto delay = static_cast<uint32_t>(params.delayFrames);
    std::vector<float> refL(kFrames, 0.0F);
    std::vector<float> refR(kFrames, 0.0F);
    float lpfRL = 0.0F; // R->L cross-path LPF state
    float lpfLR = 0.0F; // L->R cross-path LPF state
    std::array<float, kMaxCrossfeedDelayFrames> dlR{};
    std::array<float, kMaxCrossfeedDelayFrames> dlL{};
    uint32_t wR = 0U;
    uint32_t wL = 0U;
    for (uint32_t n = 0U; n < kFrames; ++n)
    {
        const float dryL = inL[n];
        const float dryR = inR[n];

        const uint32_t rIdxR = (wR + kMaxCrossfeedDelayFrames - delay) %
                               static_cast<uint32_t>(kMaxCrossfeedDelayFrames);
        const float delayedR = dlR[rIdxR];
        dlR[wR] = dryR;
        wR = (wR + 1U) % static_cast<uint32_t>(kMaxCrossfeedDelayFrames);
        lpfRL = (params.lpfB0 * delayedR) + (params.lpfPole * lpfRL);

        const uint32_t rIdxL = (wL + kMaxCrossfeedDelayFrames - delay) %
                               static_cast<uint32_t>(kMaxCrossfeedDelayFrames);
        const float delayedL = dlL[rIdxL];
        dlL[wL] = dryL;
        wL = (wL + 1U) % static_cast<uint32_t>(kMaxCrossfeedDelayFrames);
        lpfLR = (params.lpfB0 * delayedL) + (params.lpfPole * lpfLR);

        refL[n] = (params.gDirect * dryL) + (params.gCross * lpfRL);
        refR[n] = (params.gDirect * dryR) + (params.gCross * lpfLR);
    }

    // Compare energy in the settled region: module-vs-analytic within +-1 dB on both channels.
    const double moduleL = sliceRms(out.left, kFrames / 2U, kFrames);
    const double moduleR = sliceRms(out.right, kFrames / 2U, kFrames);
    const double refLrms = sliceRms(refL, kFrames / 2U, kFrames);
    const double refRrms = sliceRms(refR, kFrames / 2U, kFrames);
    if (refLrms <= 0.0 || refRrms <= 0.0)
    {
        logFail(kName, "analytic reference RMS is zero");
        return;
    }
    const double dLdB = 20.0 * std::log10(moduleL / refLrms);
    const double dRdB = 20.0 * std::log10(moduleR / refRrms);

    std::ostringstream info;
    info << "  [info] " << kName << ": module-vs-analytic L=" << dLdB << " dB R=" << dRdB
         << " dB (read-both-then-write-both)\n";
    logInfo(info.str());

    if (std::abs(dLdB) > 1.0 || std::abs(dRdB) > 1.0)
    {
        std::ostringstream oss;
        oss << "read/write-order divergence: L=" << dLdB << " dB R=" << dRdB
            << " dB vs analytic (> +-1 dB) — likely a read-one/write-one bug";
        logFail(kName, oss.str());
        return;
    }
    logPass(kName);
}
