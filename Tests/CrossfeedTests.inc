// CrossfeedTests.inc
//
// The headphone crossfeed: bs2b, faithfully (council C-42), as an output stage of its own that plays
// at its preset's full strength whatever Intensity is (founder decision 2026-10-14, KI-SND-05).
//
// #included into Tests/DSPKernelNullTest.cpp after IntensityTests.inc.
//
// The oracle is bs2b itself: libbs2b's init() and cross_feed_d() (src/bs2b.c, libbs2b 3.1.0, MIT,
// © 2005 Boris Mikhaylov), transcribed below in double precision from the published source, with
// the levels bs2b.h defines. libbs2b is not linked (OQ-17). The UI's three strengths are bs2b's own
// levels (council P2-3): Relaxed = BS2B_JMEIER_CLEVEL (650 Hz, 9.5 dB), Default = BS2B_CMOY_CLEVEL
// (700 Hz, 6.0 dB), Strong = BS2B_DEFAULT_CLEVEL (700 Hz, 4.5 dB) — bs2b's default is its strongest.
//
// Tests (module):
//   CF-1 Crossfeed_Bypass_BitExact_GoldenMaster  — module present-but-off re-asserts the hash.
//   CF-2 Crossfeed_NonStereo_PassThrough          — N=1 / N=6 byte-identical.
//   CF-3 Crossfeed_CentreFlat_vs_bs2b             — centre (L = R) response 0.1–10 kHz = bs2b's.
//   CF-4 Crossfeed_ChannelSeparation              — low-frequency feed = the bs2b level, both ways.
//   CF-5 Crossfeed_LpfCharacteristic              — the cross path is −3 dB at the bs2b cut.
//   CF-6 Crossfeed_NoNaNInf                       — noise / transient / DC stay finite.
//   CF-7 Crossfeed_ClickFreeEnableDisable         — boundaryStep <= 3x settledMaxStep.
//   CF-8 Crossfeed_CoeffRecomputeAcrossRates      — bs2b at 44.1 / 48 / 96 / 192 kHz.
//   CF-9 Crossfeed_MatchesBs2bReference           — sample for sample against cross_feed_d().
// Tests (the kernel's own crossfeed stage):
//   CF-13 Crossfeed_PlaysAtAnyIntensity           — full preset strength at Intensity 0, ½ and 1.
//   CF-14 Crossfeed_Off_BitExact                  — on is audible; off is bit-exact (P0 and P1).
// Elsewhere: CF-10 (libebur128 neutrality) in LoudnessOracleTests.inc, CF-11 (Realizer RMW) in
// RealizerTests.inc, CF-12 (RT-alloc soak) in SoakRtAllocTests.inc, and the true-peak ceiling with
// crossfeed on in LimiterTruePeakTests.inc (Limiter_TruePeak_CeilingWithCrossfeed).

#include "../Sources/AudioDSP/AudioEngine/Realizer.h"
#include "../Sources/AudioDSP/Spatial/CrossfeedModule.h"

namespace
{
    // The UI's strengths by their CrossfeedPreset index (the value SettingsKit stores).
    constexpr uint32_t kCfPresetRelaxed = 0U; // bs2b Jmeier
    constexpr uint32_t kCfPresetDefault = 1U; // bs2b Cmoy
    constexpr uint32_t kCfPresetStrong = 2U;  // bs2b default

    // bs2b.h's level for each preset: the cut frequency (Hz) and the feed (dB). The oracle's inputs.
    struct Bs2bLevel
    {
        const char* label;
        uint32_t preset;
        double fcutHz;
        double feedDb;
    };
    constexpr std::array<Bs2bLevel, 3U> kBs2bLevels = {
        {
            {.label = "Relaxed (bs2b Jmeier)", .preset = kCfPresetRelaxed, .fcutHz = 650.0, .feedDb = 9.5},
            {.label = "Default (bs2b Cmoy)", .preset = kCfPresetDefault, .fcutHz = 700.0, .feedDb = 6.0},
            {.label = "Strong (bs2b default)", .preset = kCfPresetStrong, .fcutHz = 700.0, .feedDb = 4.5},
        },
    };

    // bs2b, as published (src/bs2b.c): init() builds a first-order low-pass for the cross path (cut
    // Fc_lo, gain G_lo) and a first-order high-boost shelf for the direct path (Fc_hi, 1 − G_hi at
    // DC), plus the gain that keeps the centre at 0 dB at DC; cross_feed_d() runs them. Double
    // precision throughout, as cross_feed_d() does.
    class Bs2bReference
    {
      public:
        Bs2bReference(double fcutHz, double feedDb, double sampleRate) noexcept
        {
            const double gbLo = (feedDb * -5.0 / 6.0) - 3.0; // GB_lo: low-pass gain (dB)
            const double gbHi = (feedDb / 6.0) - 3.0;        // GB_hi: high-boost gain (dB)
            const double gLo = std::pow(10.0, gbLo / 20.0);
            const double gHi = 1.0 - std::pow(10.0, gbHi / 20.0);
            const double fcHi = fcutHz * std::pow(2.0, (gbLo - (20.0 * std::log10(gHi))) / 12.0);

            double pole = std::exp(-2.0 * std::numbers::pi * fcutHz / sampleRate);
            b1Lo_ = pole;
            a0Lo_ = gLo * (1.0 - pole);

            pole = std::exp(-2.0 * std::numbers::pi * fcHi / sampleRate);
            b1Hi_ = pole;
            a0Hi_ = 1.0 - (gHi * (1.0 - pole));
            a1Hi_ = -pole;

            gain_ = 1.0 / (1.0 - gHi + gLo);
        }

        // cross_feed_d(): one stereo frame, in place.
        void process(double& left, double& right) noexcept
        {
            loL_ = (a0Lo_ * left) + (b1Lo_ * loL_);
            loR_ = (a0Lo_ * right) + (b1Lo_ * loR_);
            hiL_ = (a0Hi_ * left) + (a1Hi_ * asisL_) + (b1Hi_ * hiL_);
            hiR_ = (a0Hi_ * right) + (a1Hi_ * asisR_) + (b1Hi_ * hiR_);
            asisL_ = left;
            asisR_ = right;
            left = (hiL_ + loR_) * gain_;
            right = (hiR_ + loL_) * gain_;
        }

        // The same coefficients' steady-state responses at freqHz: the direct path, gain·H_hi(z),
        // and the cross path, gain·H_lo(z), on the unit circle.
        [[nodiscard]] auto direct(double freqHz, double sampleRate) const -> std::complex<double>
        {
            const std::complex<double> zInv = unitDelay(freqHz, sampleRate);
            return gain_ * (a0Hi_ + (a1Hi_ * zInv)) / (1.0 - (b1Hi_ * zInv));
        }
        [[nodiscard]] auto cross(double freqHz, double sampleRate) const -> std::complex<double>
        {
            const std::complex<double> zInv = unitDelay(freqHz, sampleRate);
            return gain_ * a0Lo_ / (1.0 - (b1Lo_ * zInv));
        }
        // Centre (L = R) content: |direct + cross|, in dB.
        [[nodiscard]] auto centreDb(double freqHz, double sampleRate) const -> double
        {
            return 20.0 * std::log10(std::abs(direct(freqHz, sampleRate) + cross(freqHz, sampleRate)));
        }
        // One channel only: the far ear against the near one, in dB.
        [[nodiscard]] auto separationDb(double freqHz, double sampleRate) const -> double
        {
            return 20.0 *
                   std::log10(std::abs(cross(freqHz, sampleRate)) / std::abs(direct(freqHz, sampleRate)));
        }

      private:
        [[nodiscard]] static auto unitDelay(double freqHz, double sampleRate) -> std::complex<double>
        {
            return std::polar(1.0, -2.0 * std::numbers::pi * freqHz / sampleRate);
        }

        double a0Lo_ = 0.0;
        double b1Lo_ = 0.0;
        double a0Hi_ = 0.0;
        double a1Hi_ = 0.0;
        double b1Hi_ = 0.0;
        double gain_ = 1.0;
        double loL_ = 0.0;
        double loR_ = 0.0;
        double hiL_ = 0.0;
        double hiR_ = 0.0;
        double asisL_ = 0.0;
        double asisR_ = 0.0;
    };

    // The CrossfeedParams the Realizer publishes for a preset at sampleRate: the SHIPPING off-RT
    // derivation, so the tests check the coefficients production plays. A throwaway Realizer over a
    // fresh kernel; applyCrossfeed packs the canonical state synchronously on this thread.
    auto deriveCfParams(uint32_t enabled, uint32_t preset, uint32_t sampleRate) -> CrossfeedParams
    {
        auto kernel = std::make_shared<DSPKernel>();
        kernel->initialize(sampleRate, TestConstants::kFrames512);
        auto realizer =
            std::make_shared<AdaptiveSound::Realizer>(kernel, static_cast<double>(sampleRate));
        realizer->applyCrossfeed({.enabled = enabled, .preset = preset});
        const CrossfeedParams params = realizer->canonicalState().crossfeed;
        realizer->shutdown();
        return params;
    }

    struct StereoOut
    {
        std::vector<float> left;
        std::vector<float> right;
    };

    // A continuous stereo stream through a fresh CrossfeedModule, in 512-frame blocks (as the
    // kernel calls it). The module's enable ramp starts at off, so a caller measures after it has
    // settled (≫ 5 × 32 ms).
    auto runCrossfeedStream(const CrossfeedParams& params,
                            uint32_t sampleRate,
                            const std::vector<float>& inL,
                            const std::vector<float>& inR) -> StereoOut
    {
        constexpr uint32_t kBlock = TestConstants::kFrames512;
        const auto frames = static_cast<uint32_t>(inL.size());
        CrossfeedModule module;
        module.initialize(sampleRate, kBlock);
        StereoOut out{.left = inL, .right = inR};
        for (uint32_t offset = 0U; offset < frames; offset += kBlock)
        {
            const uint32_t chunk = std::min(kBlock, frames - offset);
            TestABL abl(chunk);
            std::copy_n(inL.begin() + offset, chunk, abl.left.begin());
            std::copy_n(inR.begin() + offset, chunk, abl.right.begin());
            module.process(params, MultichannelView::fromABL(abl.abl(), chunk));
            std::copy_n(abl.left.begin(), chunk, out.left.begin() + offset);
            std::copy_n(abl.right.begin(), chunk, out.right.begin() + offset);
        }
        return out;
    }

    // The same stream through a whole DSPKernel (state published BEFORE initialize(), so the
    // Intensity ramp and the normaliser's share start settled where the state asks).
    auto runKernelStream(const TargetState& state,
                         uint32_t sampleRate,
                         const std::vector<float>& inL,
                         const std::vector<float>& inR) -> StereoOut
    {
        constexpr uint32_t kBlock = TestConstants::kFrames512;
        const auto frames = static_cast<uint32_t>(inL.size());
        DSPKernel kernel;
        kernel.publishTargetState(state);
        kernel.initialize(sampleRate, kBlock);
        StereoOut out{.left = inL, .right = inR};
        for (uint32_t offset = 0U; offset < frames; offset += kBlock)
        {
            const uint32_t chunk = std::min(kBlock, frames - offset);
            TestABL abl(chunk);
            std::copy_n(inL.begin() + offset, chunk, abl.left.begin());
            std::copy_n(inR.begin() + offset, chunk, abl.right.begin());
            kernel.process(abl.abl(), chunk);
            std::copy_n(abl.left.begin(), chunk, out.left.begin() + offset);
            std::copy_n(abl.right.begin(), chunk, out.right.begin() + offset);
        }
        return out;
    }

    // A sine of `amplitude` at freqHz, `frames` long.
    auto cfTone(double freqHz, double amplitude, uint32_t frames, uint32_t sampleRate)
        -> std::vector<float>
    {
        std::vector<float> tone(frames);
        for (uint32_t n = 0U; n < frames; ++n)
        {
            tone[n] = static_cast<float>(
                amplitude * std::sin(2.0 * std::numbers::pi * freqHz * n / sampleRate));
        }
        return tone;
    }

    // The amplitude of the sine at freqHz in buf[start, end): the least-squares fit of
    // a·sin + b·cos, exact for a steady tone over any window (no whole-period requirement).
    auto toneAmplitude(const std::vector<float>& buf,
                       size_t start,
                       size_t end,
                       double freqHz,
                       uint32_t sampleRate) -> double
    {
        double ss = 0.0;
        double cc = 0.0;
        double sc = 0.0;
        double xs = 0.0;
        double xc = 0.0;
        for (size_t n = start; n < end; ++n)
        {
            const double phase = 2.0 * std::numbers::pi * freqHz * static_cast<double>(n) / sampleRate;
            const double s = std::sin(phase);
            const double c = std::cos(phase);
            const double x = buf[n];
            ss += s * s;
            cc += c * c;
            sc += s * c;
            xs += x * s;
            xc += x * c;
        }
        const double det = (ss * cc) - (sc * sc);
        const double a = ((xs * cc) - (xc * sc)) / det;
        const double b = ((xc * ss) - (xs * sc)) / det;
        return std::hypot(a, b);
    }

    // The steady second half of a 1 s stream: where the 32 ms enable ramp has long settled.
    constexpr uint32_t kCfStreamFrames = 48000U;
    constexpr size_t kCfSettledFrom = kCfStreamFrames / 2U;
} // namespace

// ===========================================================================
// CF-1: bypass is bit-exact (module present-but-off) → re-asserts the golden master hash.
// This is the canary: with crossfeed inserted into the chain but DISABLED, the full stereo
// chain output must hash to exactly GoldenMaster_StereoN2_v1's (TestConstants::
// kGoldenMasterStereoN2Hash, zero tolerance). It reuses the same chirp + non-trivial state; the
// default-off CrossfeedParams keep the chain byte-identical to the chain without a crossfeed.
// ===========================================================================
static auto testCrossfeedBypassBitExactGoldenMaster() -> void
{
    static const char* const kName = "Crossfeed_Bypass_BitExact_GoldenMaster";
    constexpr uint32_t kSR = TestConstants::kSampleRate48k;
    constexpr uint32_t kChunk = TestConstants::kFrames512;
    constexpr uint32_t kTotal = TestConstants::kTotalFrames1s;
    constexpr float kBoostDb = 6.0F;
    constexpr uint64_t kGoldenHash = TestConstants::kGoldenMasterStereoN2Hash;
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
    state.eq = makeEqParams(gains, kSR);
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

    const CrossfeedParams params = deriveCfParams(1U, kCfPresetDefault, kSR);

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
// CF-3: centre (L = R) content keeps bs2b's response. bs2b is a smooth shelf for centred sound —
// 0 dB at DC falling to −1.06 / −1.48 / −1.75 dB (Relaxed / Default / Strong) — because its delay
// is the cross low-pass's own group delay against a high-boost shelf on the direct path (council
// P2-3). The pre-R1.1 crossfeed added an explicit 0.318 ms delay on top and a flat direct path, and
// notched a centred voice by −4.2 to −6.3 dB near 1 kHz. Every probe 0.1–10 kHz must match the bs2b
// oracle within 0.02 dB, and none may fall below bs2b's own floor of −1.8 dB.
// ===========================================================================
static auto testCrossfeedCentreFlatVsBs2b() -> void
{
    static const char* const kName = "Crossfeed_CentreFlat_vs_bs2b";
    constexpr uint32_t kSR = TestConstants::kSampleRate48k;
    constexpr double kAmp = 0.25;
    constexpr double kOracleTolDb = 0.02;
    constexpr double kBs2bFloorDb = -1.8; // the deepest bs2b level (default) bottoms at −1.75 dB
    constexpr std::array<double, 13U> kProbesHz = {
        100.0,  150.0,  200.0,  300.0,  500.0,  700.0,   1000.0, //
        1500.0, 2000.0, 3000.0, 5000.0, 7000.0, 10000.0,
    };

    std::string fail;
    for (const Bs2bLevel& level : kBs2bLevels)
    {
        const CrossfeedParams params = deriveCfParams(1U, level.preset, kSR);
        const Bs2bReference oracle(level.fcutHz, level.feedDb, kSR);
        double worstDevDb = 0.0;
        double lowestDb = 0.0;
        double lowestAtHz = 0.0;
        for (const double hz : kProbesHz)
        {
            const std::vector<float> tone = cfTone(hz, kAmp, kCfStreamFrames, kSR);
            const StereoOut out = runCrossfeedStream(params, kSR, tone, tone);
            for (const std::vector<float>* channel : {&out.left, &out.right})
            {
                const double gainDb =
                    20.0 * std::log10(toneAmplitude(*channel, kCfSettledFrom, kCfStreamFrames, hz, kSR) /
                                      kAmp);
                worstDevDb = std::max(worstDevDb, std::abs(gainDb - oracle.centreDb(hz, kSR)));
                if (gainDb < lowestDb)
                {
                    lowestDb = gainDb;
                    lowestAtHz = hz;
                }
            }
        }
        logInfo(std::format("  [info] {}: {}: centre lowest {:.3f} dB at {} Hz; worst deviation from "
                            "bs2b {:.4f} dB\n",
                            kName,
                            level.label,
                            lowestDb,
                            lowestAtHz,
                            worstDevDb));
        if (worstDevDb > kOracleTolDb || lowestDb < kBs2bFloorDb)
        {
            fail += std::format("\n  {}: centre {:.2f} dB at {} Hz (bs2b floor {} dB); worst deviation "
                                "from bs2b {:.3f} dB (tolerance {} dB)",
                                level.label,
                                lowestDb,
                                lowestAtHz,
                                kBs2bFloorDb,
                                worstDevDb,
                                kOracleTolDb);
        }
    }
    if (!fail.empty())
    {
        logFail(kName, "the centre is not bs2b's:" + fail);
        return;
    }
    logPass(kName);
}

// ===========================================================================
// CF-4: channel separation. A tone in ONE channel: the far ear's level against the near ear's is
// the bs2b response (oracle, 0.02 dB), which at low frequency is the preset's feed level — −9.5 /
// −6.0 / −4.5 dB (bs2b.h; ±0.2 dB at 50 Hz). Both directions.
// ===========================================================================
static auto testCrossfeedChannelSeparation() -> void
{
    static const char* const kName = "Crossfeed_ChannelSeparation";
    constexpr uint32_t kSR = TestConstants::kSampleRate48k;
    constexpr double kProbeHz = 50.0;
    constexpr double kAmp = 0.25;
    constexpr double kOracleTolDb = 0.02;
    constexpr double kFeedTolDb = 0.2;

    const std::vector<float> tone = cfTone(kProbeHz, kAmp, kCfStreamFrames, kSR);
    const std::vector<float> silence(kCfStreamFrames, 0.0F);
    const auto amplitude = [&](const std::vector<float>& buf)
    { return toneAmplitude(buf, kCfSettledFrom, kCfStreamFrames, kProbeHz, kSR); };

    std::string fail;
    for (const Bs2bLevel& level : kBs2bLevels)
    {
        const CrossfeedParams params = deriveCfParams(1U, level.preset, kSR);
        const double expectedDb = Bs2bReference(level.fcutHz, level.feedDb, kSR).separationDb(kProbeHz, kSR);
        const StereoOut leftOnly = runCrossfeedStream(params, kSR, tone, silence);
        const StereoOut rightOnly = runCrossfeedStream(params, kSR, silence, tone);
        const double leftToRightDb = 20.0 * std::log10(amplitude(leftOnly.right) / amplitude(leftOnly.left));
        const double rightToLeftDb = 20.0 * std::log10(amplitude(rightOnly.left) / amplitude(rightOnly.right));
        logInfo(std::format("  [info] {}: {}: L→R {:.3f} dB, R→L {:.3f} dB (bs2b {:.3f} dB; feed −{} dB)\n",
                            kName,
                            level.label,
                            leftToRightDb,
                            rightToLeftDb,
                            expectedDb,
                            level.feedDb));
        for (const double sepDb : {leftToRightDb, rightToLeftDb})
        {
            if (std::abs(sepDb - expectedDb) > kOracleTolDb || std::abs(sepDb + level.feedDb) > kFeedTolDb)
            {
                fail += std::format("\n  {}: separation {:.3f} dB, bs2b {:.3f} dB, feed −{} dB",
                                    level.label,
                                    sepDb,
                                    expectedDb,
                                    level.feedDb);
            }
        }
    }
    if (!fail.empty())
    {
        logFail(kName, "separation is not bs2b's:" + fail);
        return;
    }
    logPass(kName);
}

// ===========================================================================
// CF-5: the cross path is bs2b's first-order low-pass: −3 dB at the preset's cut against its
// low-frequency level (±0.1 dB), and well down by 8 kHz (≤ −18 dB; a one-pole is ~−21 dB there).
// ===========================================================================
static auto testCrossfeedLpfCharacteristic() -> void
{
    static const char* const kName = "Crossfeed_LpfCharacteristic";
    constexpr uint32_t kSR = TestConstants::kSampleRate48k;
    constexpr double kRefHz = 20.0;
    constexpr double kHighHz = 8000.0;
    constexpr double kAmp = 0.25;

    std::string fail;
    for (const Bs2bLevel& level : kBs2bLevels)
    {
        const CrossfeedParams params = deriveCfParams(1U, level.preset, kSR);
        const std::vector<float> silence(kCfStreamFrames, 0.0F);
        const auto crossAmplitude = [&](double hz)
        {
            const StereoOut out =
                runCrossfeedStream(params, kSR, cfTone(hz, kAmp, kCfStreamFrames, kSR), silence);
            return toneAmplitude(out.right, kCfSettledFrom, kCfStreamFrames, hz, kSR);
        };
        const double reference = crossAmplitude(kRefHz);
        const double atCutDb = 20.0 * std::log10(crossAmplitude(level.fcutHz) / reference);
        const double atHighDb = 20.0 * std::log10(crossAmplitude(kHighHz) / reference);
        logInfo(std::format("  [info] {}: {}: cross path {:.3f} dB at {} Hz, {:.2f} dB at 8 kHz\n",
                            kName,
                            level.label,
                            atCutDb,
                            level.fcutHz,
                            atHighDb));
        if (std::abs(atCutDb + 3.01) > 0.1 || atHighDb > -18.0)
        {
            fail += std::format(
                "\n  {}: {:.3f} dB at the cut, {:.2f} dB at 8 kHz", level.label, atCutDb, atHighDb);
        }
    }
    if (!fail.empty())
    {
        logFail(kName, "the cross path is not bs2b's low-pass:" + fail);
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

    const CrossfeedParams params = deriveCfParams(1U, kCfPresetStrong, kSR);

    // Battery: white noise, a unit transient (impulse at 0), and DC.
    std::vector<std::pair<std::vector<float>, std::vector<float>>> battery;
    {
        std::vector<float> nL(kFrames);
        std::vector<float> nR(kFrames);
        std::mt19937 gen(0xBADF00DU);
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
        const StereoOut out = runCrossfeedStream(params, kSR, battery[c].first, battery[c].second);
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

    // Toggling crossfeed off keeps the strength selection (the UI flow): the same preset, only
    // enabled flips. The off POD therefore carries the active coefficients so the module's mix ramp
    // glides the still-crossfed wet down to dry (click-free), then settles bit-exact.
    const CrossfeedParams onParams = deriveCfParams(1U, kCfPresetStrong, kSR);
    const CrossfeedParams offParams = deriveCfParams(0U, kCfPresetStrong, kSR);

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
    // regime — the crossfed (ON) waveform's slopes differ from the dry (OFF) tone's (the
    // filtered cross path and the high-boost direct path change the slew), so a single dry-regime reference would unfairly
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
// CF-8: the Realizer re-derives bs2b at each rate: the separation at 50 Hz matches the oracle at
// that rate (0.02 dB) and is the same feed level at 44.1, 48, 96 and 192 kHz (0.05 dB).
// ===========================================================================
static auto testCrossfeedCoeffRecomputeAcrossRates() -> void
{
    static const char* const kName = "Crossfeed_CoeffRecomputeAcrossRates";
    constexpr double kProbeHz = 50.0;
    constexpr double kAmp = 0.25;
    constexpr double kOracleTolDb = 0.02;
    constexpr double kConsistencyTolDb = 0.05;
    constexpr std::array<uint32_t, 4U> kRates = {44100U, 48000U, 96000U, 192000U};
    const Bs2bLevel& level = kBs2bLevels[1U]; // Default (Cmoy)

    std::string fail;
    std::optional<double> firstSepDb;
    for (const uint32_t rate : kRates)
    {
        const CrossfeedParams params = deriveCfParams(1U, level.preset, rate);
        const uint32_t frames = rate; // 1 s at every rate
        const std::vector<float> silence(frames, 0.0F);
        const StereoOut out = runCrossfeedStream(params, rate, cfTone(kProbeHz, kAmp, frames, rate), silence);
        const double sepDb = 20.0 * std::log10(toneAmplitude(out.right, frames / 2U, frames, kProbeHz, rate) /
                                               toneAmplitude(out.left, frames / 2U, frames, kProbeHz, rate));
        const double expectedDb = Bs2bReference(level.fcutHz, level.feedDb, rate).separationDb(kProbeHz, rate);
        logInfo(std::format("  [info] {}: {} Hz: separation {:.4f} dB (bs2b {:.4f} dB)\n",
                            kName,
                            rate,
                            sepDb,
                            expectedDb));
        if (std::abs(sepDb - expectedDb) > kOracleTolDb)
        {
            fail += std::format("\n  {} Hz: {:.4f} dB vs bs2b {:.4f} dB", rate, sepDb, expectedDb);
        }
        if (!firstSepDb)
        {
            firstSepDb = sepDb;
        }
        else if (std::abs(sepDb - *firstSepDb) > kConsistencyTolDb)
        {
            fail += std::format("\n  {} Hz drifts to {:.4f} dB from {:.4f} dB", rate, sepDb, *firstSepDb);
        }
    }
    if (!fail.empty())
    {
        logFail(kName, "bs2b is not re-derived per rate:" + fail);
        return;
    }
    logPass(kName);
}

// ===========================================================================
// CF-9: sample for sample, the module IS bs2b: distinct L and R content (two tones plus
// independent noise) through the module and through cross_feed_d() (the oracle, double precision)
// agree within 1e-5 once the enable ramp has settled. This also guards the #1 crossfeed bug —
// writing the new L before reading it for R (read-one/write-one) — which no level test can see.
// ===========================================================================
static auto testCrossfeedMatchesBs2bReference() -> void
{
    static const char* const kName = "Crossfeed_MatchesBs2bReference";
    constexpr uint32_t kSR = TestConstants::kSampleRate48k;
    constexpr uint32_t kFrames = 2U * kSR;
    constexpr double kTolerance = 1e-5;

    std::vector<float> inL(kFrames);
    std::vector<float> inR(kFrames);
    std::mt19937 gen(0xB52B0001U);
    std::uniform_real_distribution<float> noise(-0.1F, 0.1F);
    for (uint32_t n = 0U; n < kFrames; ++n)
    {
        const double t = static_cast<double>(n) / kSR;
        inL[n] = static_cast<float>(0.3 * std::sin(2.0 * std::numbers::pi * 300.0 * t)) + noise(gen);
        inR[n] = static_cast<float>(0.3 * std::sin(2.0 * std::numbers::pi * 900.0 * t)) + noise(gen);
    }

    std::string fail;
    for (const Bs2bLevel& level : kBs2bLevels)
    {
        const StereoOut out = runCrossfeedStream(deriveCfParams(1U, level.preset, kSR), kSR, inL, inR);
        Bs2bReference oracle(level.fcutHz, level.feedDb, kSR);
        double worst = 0.0;
        uint32_t worstAt = 0U;
        for (uint32_t n = 0U; n < kFrames; ++n)
        {
            double left = inL[n];
            double right = inR[n];
            oracle.process(left, right);
            if (n < kSR) // the first second: the enable ramp settling
            {
                continue;
            }
            const double err = std::max(std::abs(out.left[n] - left), std::abs(out.right[n] - right));
            if (err > worst)
            {
                worst = err;
                worstAt = n;
            }
        }
        logInfo(std::format("  [info] {}: {}: worst |module − bs2b| = {:.3g} at frame {}\n",
                            kName,
                            level.label,
                            worst,
                            worstAt));
        if (worst > kTolerance)
        {
            fail += std::format("\n  {}: |module − bs2b| = {:.3g} at frame {}", level.label, worst, worstAt);
        }
    }
    if (!fail.empty())
    {
        logFail(kName, "the module is not bs2b sample for sample:" + fail);
        return;
    }
    logPass(kName);
}

// ===========================================================================
// CF-13: crossfeed plays on its own (founder decision 2026-10-14, KI-SND-05). It is an output stage
// of the kernel — after the Intensity blend, before the limiter — so it plays at its preset's full
// strength whatever Intensity is: at 0 (the faithful default, where it was silent), at ½ and at 1.
// A tone in the left channel only: the right ear gets bs2b's cross path, the left its direct path,
// each matching the oracle (0.02 dB) — the ratio at every Intensity, the levels where no blend or
// normaliser touches them (Intensity 0 and 1).
// ===========================================================================
static auto testCrossfeedPlaysAtAnyIntensity() -> void
{
    static const char* const kName = "Crossfeed_PlaysAtAnyIntensity";
    constexpr uint32_t kSR = TestConstants::kSampleRate48k;
    constexpr double kProbeHz = 300.0;
    constexpr double kAmp = 0.1;
    constexpr double kTolDb = 0.02;
    const Bs2bLevel& level = kBs2bLevels[2U]; // Strong (bs2b default)
    const Bs2bReference oracle(level.fcutHz, level.feedDb, kSR);
    const double directDb = 20.0 * std::log10(std::abs(oracle.direct(kProbeHz, kSR)));
    const double crossDb = 20.0 * std::log10(std::abs(oracle.cross(kProbeHz, kSR)));

    const std::vector<float> tone = cfTone(kProbeHz, kAmp, kCfStreamFrames, kSR);
    const std::vector<float> silence(kCfStreamFrames, 0.0F);
    std::string fail;
    for (const float intensity : {0.0F, 0.5F, 1.0F})
    {
        TargetState state = makeIdentityState(); // EQ flat, normaliser off, limiter bypassed
        state.intensityLinear = intensity;
        state.crossfeed = deriveCfParams(1U, level.preset, kSR);
        const StereoOut out = runKernelStream(state, kSR, tone, silence);
        const double nearDb =
            20.0 * std::log10(toneAmplitude(out.left, kCfSettledFrom, kCfStreamFrames, kProbeHz, kSR) / kAmp);
        const double farDb =
            20.0 * std::log10(toneAmplitude(out.right, kCfSettledFrom, kCfStreamFrames, kProbeHz, kSR) / kAmp);
        logInfo(std::format("  [info] {}: Intensity {}: near {:.3f} dB, far {:.3f} dB (bs2b {:.3f} / {:.3f})\n",
                            kName,
                            intensity,
                            nearDb,
                            farDb,
                            directDb,
                            crossDb));
        const bool ratioOff = !std::isfinite(farDb - nearDb) ||
                              std::abs((farDb - nearDb) - (crossDb - directDb)) > kTolDb;
        const bool levelsOff = (intensity == 0.0F || intensity == 1.0F) &&
                               (std::abs(nearDb - directDb) > kTolDb || std::abs(farDb - crossDb) > kTolDb);
        if (ratioOff || levelsOff)
        {
            fail += std::format("\n  Intensity {}: near {:.3f} dB, far {:.3f} dB; bs2b near {:.3f}, far {:.3f}",
                                intensity,
                                nearDb,
                                farDb,
                                directDb,
                                crossDb);
        }
    }
    if (!fail.empty())
    {
        logFail(kName, "crossfeed does not play at full strength at every Intensity:" + fail);
        return;
    }
    logPass(kName);
}

// ===========================================================================
// CF-14: crossfeed off is bit-exact. (a) At Intensity 0 with the EQ flat, crossfeed on is audible;
// turned off it glides out (~160 ms) and, after the 2 s hold, the kernel is back on the bit-perfect
// path — the output IS the input, bit for bit. (b) With the EQ on (P1), a crossfeed turned on and
// then off leaves the output bit-identical to a kernel whose crossfeed was never on (the level stays
// under the limiter's ceiling, so the limiter's history cannot differ), and an off crossfeed that
// still carries its coefficients plays bit-identically to the default, coefficient-free one.
// ===========================================================================
static auto testCrossfeedOffBitExact() -> void
{
    static const char* const kName = "Crossfeed_Off_BitExact";
    constexpr uint32_t kSR = TestConstants::kSampleRate48k;
    constexpr uint32_t kOnFrames = kSR;       // 1 s on
    constexpr uint32_t kOffFrames = 3U * kSR; // ramp out + the 2 s hold + the 5 ms fade, and more
    constexpr uint32_t kTail = kSR / 2U;      // the last 0.5 s is compared
    constexpr uint32_t kTotal = kOnFrames + kOffFrames;
    constexpr float kAudibleFloor = 0.01F;    // −40 dBFS of difference: plainly audible

    std::vector<float> inL(kTotal);
    std::vector<float> inR(kTotal);
    for (uint32_t n = 0U; n < kTotal; ++n)
    {
        const double t = static_cast<double>(n) / kSR;
        inL[n] = static_cast<float>(0.3 * std::sin(2.0 * std::numbers::pi * 300.0 * t));
        inR[n] = static_cast<float>(0.2 * std::sin(2.0 * std::numbers::pi * 500.0 * t));
    }
    const CrossfeedParams on = deriveCfParams(1U, kCfPresetStrong, kSR);
    const CrossfeedParams offCarrying = deriveCfParams(0U, kCfPresetStrong, kSR);

    // Run `phases` back to back through one kernel; each phase is (state, frames).
    const auto runPhases = [&](const std::vector<std::pair<TargetState, uint32_t>>& phases) -> StereoOut
    {
        constexpr uint32_t kBlock = TestConstants::kFrames512;
        DSPKernel kernel;
        kernel.publishTargetState(phases.front().first);
        kernel.initialize(kSR, kBlock);
        StereoOut out{.left = inL, .right = inR};
        uint32_t offset = 0U;
        for (const auto& [state, frames] : phases)
        {
            kernel.publishTargetState(state);
            const uint32_t end = offset + frames;
            while (offset < end)
            {
                const uint32_t chunk = std::min(kBlock, end - offset);
                TestABL abl(chunk);
                std::copy_n(inL.begin() + offset, chunk, abl.left.begin());
                std::copy_n(inR.begin() + offset, chunk, abl.right.begin());
                kernel.process(abl.abl(), chunk);
                std::copy_n(abl.left.begin(), chunk, out.left.begin() + offset);
                std::copy_n(abl.right.begin(), chunk, out.right.begin() + offset);
                offset += chunk;
            }
        }
        return out;
    };
    const auto tailEqual = [&](const StereoOut& a, const std::vector<float>& refL, const std::vector<float>& refR)
    {
        const size_t from = kTotal - kTail;
        return std::memcmp(a.left.data() + from, refL.data() + from, kTail * sizeof(float)) == 0 &&
               std::memcmp(a.right.data() + from, refR.data() + from, kTail * sizeof(float)) == 0;
    };
    const auto maxDifference = [&](const StereoOut& a, uint32_t from, uint32_t to)
    {
        float worst = 0.0F;
        for (uint32_t n = from; n < to; ++n)
        {
            worst = std::max({worst, std::abs(a.left[n] - inL[n]), std::abs(a.right[n] - inR[n])});
        }
        return worst;
    };

    std::string fail;

    // (a) Intensity 0, EQ flat: on → audible; off → the bit-perfect path again.
    TargetState flat = makeIdentityState();
    flat.intensityLinear = 0.0F;
    TargetState flatOn = flat;
    flatOn.crossfeed = on;
    TargetState flatOff = flat;
    flatOff.crossfeed = offCarrying;
    const StereoOut a = runPhases({{flatOn, kOnFrames}, {flatOff, kOffFrames}});
    const float audible = maxDifference(a, kOnFrames / 2U, kOnFrames);
    logInfo(std::format("  [info] {}: Intensity 0, EQ flat: crossfeed on changes the output by up to "
                        "{:.4f}\n",
                        kName,
                        audible));
    if (audible < kAudibleFloor)
    {
        fail += std::format("\n  crossfeed on at Intensity 0 changed the output by only {:.3g} (silent)", audible);
    }
    if (!tailEqual(a, inL, inR))
    {
        fail += std::format("\n  crossfeed off at Intensity 0: not bit-exact {} s later (max |Δ| {:.3g})",
                            kOffFrames / kSR,
                            maxDifference(a, kTotal - kTail, kTotal));
    }

    // (b) Intensity 0, EQ on (P1), the limiter active but untouched by this level.
    std::array<float, kEqBands> gains{};
    gains[kBand1kHzIndex] = 3.0F;
    TargetState eqOn = makeIdentityState();
    eqOn.intensityLinear = 0.0F;
    eqOn.eq = makeEqParams(gains, kSR);
    eqOn.limiter.truePeakCeilingLinear = kTruePeakCeilingLinear;
    TargetState eqOnCrossfeed = eqOn;
    eqOnCrossfeed.crossfeed = on;
    TargetState eqOnOffCarrying = eqOn;
    eqOnOffCarrying.crossfeed = offCarrying;
    const StereoOut never = runPhases({{eqOn, kTotal}});
    const StereoOut toggled = runPhases({{eqOnCrossfeed, kOnFrames}, {eqOnOffCarrying, kOffFrames}});
    const StereoOut carrying = runPhases({{eqOnOffCarrying, kTotal}});
    if (!tailEqual(toggled, never.left, never.right))
    {
        fail += "\n  EQ on: crossfeed on then off is not bit-identical to crossfeed never on";
    }
    if (std::memcmp(carrying.left.data(), never.left.data(), kTotal * sizeof(float)) != 0 ||
        std::memcmp(carrying.right.data(), never.right.data(), kTotal * sizeof(float)) != 0)
    {
        fail += "\n  EQ on: an off crossfeed carrying its coefficients is not bit-identical to the default";
    }

    if (!fail.empty())
    {
        logFail(kName, "crossfeed on/off:" + fail);
        return;
    }
    logPass(kName);
}
