// LevelPlanTests.inc
//
// The leveling planner: the level stage, the cap and turn-down with the leveling gain, Compare matched (§S3).
// #included into Tests/DSPKernelNullTest.cpp after TestSupport.h; its rows go in the kTests block
// marked "LevelPlanTests.inc" there, so the two lanes never edit the same lines of the table.
//
// R1.1-B W4, lane 1 (docs/design/level-and-fold/README.md). The seam (step 1):
//   LP-1 LevelPlan_RoleNumbers_Fixed           — the persisted role numbers and the seam's sizes.
//   LP-2 LevelPlan_FoldMatrix_Table             — the BS.775 rows from roles (§S1b's table).
//   LP-3 LevelPlan_FoldMatrix_WorstCaseTrim     — §4's fallback trims: 5.1 −8.94 / −8.04, 7.1 −9.93 / −9.03 dB.
//   LP-4 LevelPlan_WorkingCeiling               — C_work −1.282 dBTP (Bluetooth, unknown), −0.380 (wired).
//   LP-5 LevelPlan_LfeVariantGains              — 0, 0.5, 1.0, +4 dB; 0 out of range.
//   LP-6 Kernel_CrossfeedEngaged_FollowsWhatPlays — S2: on a stereo block while it plays; never on 6 channels.
// The planner (step 4; §1.3, §4, §6):
//   LP-7  Planner_Unfolded            — g = min(−18 − L, C_work − TP_N, +12); P = TP_N; no trim.
//   LP-8  Planner_WorkedExample       — §4's 5.1 on Bluetooth: trim, P, L, g from the measured fold.
//   LP-9  Planner_Mono_DualMono       — a mono file on ≥ 2 outputs is levelled as dual mono (+3.01 LU, F8).
//   LP-10 Planner_UnknownLoudness     — F4 (no gated block, ≤ −70 LUFS, the unknown mode) and NI-7 (a known hot
//                                       peak cuts below −5); the fold's fallback trim is not cut twice.
//   LP-11 Planner_PeakRate            — an unknown peak, or one measured at another rate, counts as 0 dBTP
//                                       (raised to it above full scale).
//   LP-12 Planner_FoldFallback        — no fold numbers, or roles that differ: the matrix's worst case.
//   LP-13 Planner_ProtectiveReplan    — F5: g and the variant frozen, trim′ and P′ against the new ceiling.
//   LP-14 Planner_OffAndNoDecision    — Off keeps g = 0 and the trim; no decision is Off with the fallback.
//   LP-15 Planner_GainToTarget_Oracle — decision → planner → apply → libebur128: −18 LUFS within 0.2 LU, stereo,
//                                       folded 5.1 and mono (EBUR128_DUAL_MONO's convention).
// The level stage (step 4; §1.3, §6, §7 — TrackLoudnessGain and the Realizer, through the real kernel):
//   LP-16 LevelStage_Rules            — g from plans; G = min(−ΔL, C_cap); P0 holds with the EQ Off and no
//                                       gain; Compare at g + T; the τ per event; a saved profile is final;
//                                       B_eff's cut allowance measured on the refresh; a shared group gain
//                                       never above the new cap.
//   LP-17 Level_NoMotionInsideSong    — g and G sampled 100× on an analysed track, EQ On and Off: max − min = 0;
//                                       the fresh start with a saved profile snaps (no glide).
//   LP-18 Level_CapHolds_NoGainReduction
//                                     — the −9 LUFS music-like master, a bass preset and Leveling Off (the cap
//                                       binds), leveled on Bluetooth and wired, the EQ Off with a leveling gain:
//                                       the limiter never acts (GR < 0.01 dB), crossfeed off.
//   LP-19 Level_Compare_Matched       — Compare plays at the EQ-on loudness within 0.2 dB (libebur128), the
//                                       cap binding and not.
//   LP-20 Level_ModeChange_NoGainReduction
//                                     — NI-4: a Track → Album change mid-song glides the effects unit at 0.15 s
//                                       with GR < 0.01 dB (the spatial unit's half is lane 2's).
//   LP-22 Level_AgcGone_IntensitySweep — the session AGC is gone (M8): Intensity 0 → 1 → 0 with Leveling Off
//                                       leaves the integrated loudness within 0.1 dB (libebur128).
//   LP-23 GoldenMaster_StereoN2_P1Leveled_v1
//                                     — the shipping path's bit-exact signature: P1, the EQ Off, g = −7.07 dB
//                                       through the Realizer and a real plan (architect N8).
//   LP-21 Level_KnownIssue_EnvelopeLogged
//                                     — C5: TP + B_eff is a fixture-dependent bound, not a strict one: a driven
//                                       808 under a +5 dB 20–125 Hz boost and a clipped master under a −12 dB
//                                       cut at 100 Hz LOG their gain reduction (no one-fixture number asserted);
//                                       the limiter still holds the ceiling.

#include "../Sources/AudioDSP/Planning/TrackPlan.h"
#include "../Sources/AudioDSP/Spatial/FoldMatrix.h"

namespace
{
    // The roles of the layouts the tests fold, in their slot order.
    using LpRole = AdaptiveSound::ChannelRole;
    constexpr std::array<LpRole, 6U> kLpRoles51 = {
        LpRole::L,
        LpRole::R,
        LpRole::C,
        LpRole::Lfe,
        LpRole::Ls,
        LpRole::Rs,
    };
    constexpr std::array<LpRole, 8U> kLpRoles71 = {
        LpRole::L,
        LpRole::R,
        LpRole::C,
        LpRole::Lfe,
        LpRole::Ls,
        LpRole::Rs,
        LpRole::Lb,
        LpRole::Rb,
    };

    // kAudioDeviceTransportType FourCCs (CoreAudio/AudioHardwareBase.h).
    constexpr uint32_t kLpBluetooth = kAudioDeviceTransportTypeBluetooth;
    constexpr uint32_t kLpBuiltIn = kAudioDeviceTransportTypeBuiltIn;

    [[nodiscard]] auto lpWorkingCeiling(uint32_t transport) -> double
    {
        return workingCeilingDbtp(outputCeilingLinear(transport));
    }

    [[nodiscard]] auto lpNear(double value, double expected, double tolerance) -> bool
    {
        return std::isfinite(value) && std::abs(value - expected) <= tolerance;
    }

    constexpr double kLpNaN = std::numeric_limits<double>::quiet_NaN();
    constexpr double kLpEngineRate = 48000.0;

    // An output state: `transport`, N channels with `roles`, M outputs, at the engine's rate.
    [[nodiscard]] auto lpOutput(uint32_t transport, std::span<const LpRole> roles, uint32_t outputs)
        -> AsOutputState
    {
        AsOutputState output{};
        output.transportType = transport;
        output.engineRateHz = kLpEngineRate;
        output.sourceChannels = static_cast<uint32_t>(roles.size());
        output.outputChannels = outputs;
        for (size_t ch = 0U; ch < roles.size(); ++ch)
        {
            output.sourceRoles[ch] = static_cast<uint8_t>(roles[ch]);
        }
        return output;
    }

    // A leveled decision measured at the engine's rate with `roles`: L_N and TP_N (NaN = unknown).
    [[nodiscard]] auto lpDecision(double loudnessLufs,
                                  double truePeakDbtp,
                                  std::span<const LpRole> roles) -> AsTrackLeveling
    {
        AsTrackLeveling decision{};
        decision.mode = AsLevelingModeLeveled;
        decision.source = AsLevelingSourceAnalysis;
        decision.lfeVariant = AsLfeVariantOmit;
        decision.channelCount = static_cast<uint8_t>(roles.size());
        for (size_t ch = 0U; ch < roles.size(); ++ch)
        {
            decision.roles[ch] = static_cast<uint8_t>(roles[ch]);
        }
        decision.peakRateHz = kLpEngineRate;
        decision.loudnessLufs = loudnessLufs;
        decision.truePeakDbtp = truePeakDbtp;
        for (size_t variant = 0U; variant < static_cast<size_t>(AS_FOLD_LFE_VARIANTS); ++variant)
        {
            decision.foldedLufs[variant] = kLpNaN;
            decision.foldedTruePeakDbtp[variant] = kLpNaN;
        }
        return decision;
    }

    // The same with the fold measured at `variant`: L_F and TP_F there.
    [[nodiscard]] auto lpFoldedDecision(double loudnessLufs,
                                        double truePeakDbtp,
                                        double foldedLufs,
                                        double foldedTruePeakDbtp,
                                        std::span<const LpRole> roles,
                                        uint8_t variant = AsLfeVariantOmit) -> AsTrackLeveling
    {
        AsTrackLeveling decision = lpDecision(loudnessLufs, truePeakDbtp, roles);
        decision.hasFolded = 1U;
        decision.lfeVariant = variant;
        decision.foldedLufs[variant] = foldedLufs;
        decision.foldedTruePeakDbtp[variant] = foldedTruePeakDbtp;
        return decision;
    }

    constexpr std::array<LpRole, 2U> kLpRolesStereo = {
        LpRole::L,
        LpRole::R,
    };
    constexpr std::array<LpRole, 1U> kLpRolesMono = {
        LpRole::Mono,
    };

    // Collects failed expectations as one message.
    struct LpExpect
    {
        std::string failures;

        void near(const char* what, double value, double expected, double tolerance = 1e-9)
        {
            if (!lpNear(value, expected, tolerance))
            {
                failures += std::format("\n  {}: {:+.4f}, want {:+.4f}", what, value, expected);
            }
        }

        void that(bool condition, const char* what)
        {
            if (!condition)
            {
                failures += std::format("\n  {}", what);
            }
        }
    };

    // libebur128's true peak (dBTP) over every channel of planar audio. NaN on a libebur128 error.
    auto lpEbur128TruePeakDbtp(const std::vector<std::vector<float>>& channels, double sampleRate)
        -> double
    {
        const auto count = static_cast<unsigned>(channels.size());
        ebur128_state* state =
            ebur128_init(count, static_cast<unsigned long>(sampleRate), EBUR128_MODE_TRUE_PEAK);
        if (state == nullptr)
        {
            return kLpNaN;
        }
        const size_t frames = channels.front().size();
        std::vector<float> interleaved(frames * count);
        for (size_t frame = 0U; frame < frames; ++frame)
        {
            for (size_t ch = 0U; ch < count; ++ch)
            {
                interleaved[(frame * count) + ch] = channels[ch][frame];
            }
        }
        double peak = 0.0;
        bool ok = ebur128_add_frames_float(state, interleaved.data(), frames) == EBUR128_SUCCESS;
        for (unsigned ch = 0U; ch < count && ok; ++ch)
        {
            double channelPeak = 0.0;
            ok = ebur128_true_peak(state, ch, &channelPeak) == EBUR128_SUCCESS;
            peak = std::max(peak, channelPeak);
        }
        ebur128_destroy(&state);
        return (ok && peak > 0.0) ? 20.0 * std::log10(peak) : kLpNaN;
    }

    // `channels` independent pink noises of `seconds` at the engine's rate, together measuring `lufs`
    // (libebur128, its default channel map).
    auto lpPinkChannels(size_t channels, double seconds, uint32_t seed, double lufs)
        -> std::vector<std::vector<float>>
    {
        std::mt19937 rng(seed);
        const auto frames = static_cast<size_t>(seconds * kLpEngineRate);
        std::vector<std::vector<float>> planar(channels, std::vector<float>(frames));
        for (std::vector<float>& channel : planar)
        {
            const std::vector<double> noise = tlPinkNoise(frames, rng);
            std::ranges::transform(
                noise, channel.begin(), [](double sample) { return static_cast<float>(sample); });
        }
        const double measured = tlEbur128Lufs(planar, kLpEngineRate);
        const auto gain = static_cast<float>(std::pow(10.0, (lufs - measured) / 20.0));
        for (std::vector<float>& channel : planar)
        {
            for (float& sample : channel)
            {
                sample *= gain;
            }
        }
        return planar;
    }

    // `matrix` applied to `planar`, then scaled by `gainDb`: the stereo the fold plays.
    auto lpFoldTo(const FoldMatrix& matrix,
                  const std::vector<std::vector<float>>& planar,
                  double gainDb) -> std::vector<std::vector<float>>
    {
        const double gain = std::pow(10.0, gainDb / 20.0);
        const size_t frames = planar.front().size();
        std::vector<std::vector<float>> stereo(2U, std::vector<float>(frames, 0.0F));
        for (size_t side = 0U; side < 2U; ++side)
        {
            for (size_t ch = 0U; ch < planar.size(); ++ch)
            {
                const double weight = static_cast<double>(matrix.gain[side][ch]) * gain;
                for (size_t frame = 0U; frame < frames; ++frame)
                {
                    stereo[side][frame] +=
                        static_cast<float>(weight * static_cast<double>(planar[ch][frame]));
                }
            }
        }
        return stereo;
    }

    // `planar` scaled by `gainDb`.
    auto lpScaled(std::vector<std::vector<float>> planar, double gainDb)
        -> std::vector<std::vector<float>>
    {
        const auto gain = static_cast<float>(std::pow(10.0, gainDb / 20.0));
        for (std::vector<float>& channel : planar)
        {
            for (float& sample : channel)
            {
                sample *= gain;
            }
        }
        return planar;
    }
} // namespace

// ===========================================================================
// LP-1: the role numbers are persisted with every analysis (AS_TRACK_ANALYSIS_VERSION): Unknown 0,
// L 1, R 2, C 3, Lfe 4, Ls 5, Rs 6, Lb 7, Rb 8, Cs 9, Lc 10, Rc 11, Lw 12, Rw 13, Mono 14 (§S1b).
// ===========================================================================
static auto testLevelPlanRoleNumbersFixed() -> void
{
    static const char* const kName = "LevelPlan_RoleNumbers_Fixed";
    const auto pinned = std::to_array<std::pair<int, int>>({
        {AsChannelRoleUnknown, 0},
        {AsChannelRoleL, 1},
        {AsChannelRoleR, 2},
        {AsChannelRoleC, 3},
        {AsChannelRoleLfe, 4},
        {AsChannelRoleLs, 5},
        {AsChannelRoleRs, 6},
        {AsChannelRoleLb, 7},
        {AsChannelRoleRb, 8},
        {AsChannelRoleCs, 9},
        {AsChannelRoleLc, 10},
        {AsChannelRoleRc, 11},
        {AsChannelRoleLw, 12},
        {AsChannelRoleRw, 13},
        {AsChannelRoleMono, 14},
    });
    for (const auto& [role, number] : pinned)
    {
        if (role != number)
        {
            logFail(
                kName,
                std::format("role {} is numbered {}: the persisted numbering moved", number, role));
            return;
        }
    }
    if (AS_MAX_CHANNELS != 8 || AS_FOLD_LFE_VARIANTS != 4 || AsLfeVariantOmit != 0 ||
        AsLfeVariantMusic != 1 || AsLfeVariantFull != 2 || AsLfeVariantFilm != 3)
    {
        logFail(kName, "the seam's channel slots or LFE variant numbering moved");
        return;
    }
    logPass(kName);
}

// ===========================================================================
// LP-2: the BS.775 fold's rows (§S1b): L/R 1.0 into its side; C 0.7071 to both; one surround pair
// 0.7071 into its side; side AND back pairs (7.1) 0.5 each (founder decision 5); Cs and an unknown
// role 0.5 to both; Lc/Lw 1.0 into its side; the LFE at its variant's gain to both.
// ===========================================================================
static auto testLevelPlanFoldMatrixTable() -> void
{
    static const char* const kName = "LevelPlan_FoldMatrix_Table";
    constexpr float kTol = 1e-6F;
    std::string fail;
    const auto expectRow = [&fail](const char* what,
                                   const FoldMatrix& matrix,
                                   size_t side,
                                   std::initializer_list<float> row)
    {
        size_t ch = 0U;
        for (const float want : row)
        {
            if (std::abs(matrix.gain[side][ch] - want) > kTol)
            {
                fail += std::format("\n  {}: row {} slot {} is {}, want {}",
                                    what,
                                    side,
                                    ch,
                                    matrix.gain[side][ch],
                                    want);
            }
            ++ch;
        }
    };

    const auto fold51 = makeBs775Fold(std::span<const LpRole>(kLpRoles51), AsLfeVariantMusic);
    const auto fold71 = makeBs775Fold(std::span<const LpRole>(kLpRoles71), AsLfeVariantOmit);
    const std::array<LpRole, 5U> back50 = {
        LpRole::L,
        LpRole::R,
        LpRole::C,
        LpRole::Lb,
        LpRole::Rb,
    };
    const auto foldBack50 = makeBs775Fold(std::span<const LpRole>(back50), AsLfeVariantOmit);
    const std::array<LpRole, 7U> odd = {
        LpRole::Lc,
        LpRole::Rc,
        LpRole::Cs,
        LpRole::Unknown,
        LpRole::Lw,
        LpRole::Rw,
        LpRole::Mono,
    };
    const auto foldOdd = makeBs775Fold(std::span<const LpRole>(odd), AsLfeVariantOmit);
    if (!fold51 || !fold71 || !foldBack50 || !foldOdd)
    {
        logFail(kName, "a fold of 5 to 8 known channels was refused");
        return;
    }
    constexpr float kC = 0.70710678F;
    expectRow("5.1 (LFE −6 dB)", *fold51, 0U, {1.0F, 0.0F, kC, 0.5F, kC, 0.0F});
    expectRow("5.1 (LFE −6 dB)", *fold51, 1U, {0.0F, 1.0F, kC, 0.5F, 0.0F, kC});
    expectRow("7.1", *fold71, 0U, {1.0F, 0.0F, kC, 0.0F, 0.5F, 0.0F, 0.5F, 0.0F});
    expectRow("7.1", *fold71, 1U, {0.0F, 1.0F, kC, 0.0F, 0.0F, 0.5F, 0.0F, 0.5F});
    expectRow("5.0 back pair", *foldBack50, 0U, {1.0F, 0.0F, kC, kC, 0.0F});
    expectRow("Lc Rc Cs ? Lw Rw Mono", *foldOdd, 0U, {1.0F, 0.0F, 0.5F, 0.5F, 1.0F, 0.0F, kC});
    expectRow("Lc Rc Cs ? Lw Rw Mono", *foldOdd, 1U, {0.0F, 1.0F, 0.5F, 0.5F, 0.0F, 1.0F, kC});
    if (makeBs775Fold(std::span<const LpRole>(), AsLfeVariantOmit).has_value())
    {
        fail += "\n  a fold of no channels was built";
    }
    if (!fail.empty())
    {
        logFail(kName, "the fold's rows differ from the table:" + fail);
        return;
    }
    logPass(kName);
}

// ===========================================================================
// LP-3: with no folded analysis, the trim is the matrix's worst case against a 0 dBTP source (§4):
// 5.1 −8.94 dB on Bluetooth and −8.04 wired; 7.1 (surrounds at 0.5) −9.93 and −9.03.
// ===========================================================================
static auto testLevelPlanFoldMatrixWorstCaseTrim() -> void
{
    static const char* const kName = "LevelPlan_FoldMatrix_WorstCaseTrim";
    constexpr double kTolDb = 0.01;
    const auto fold51 = makeBs775Fold(std::span<const LpRole>(kLpRoles51), AsLfeVariantOmit);
    const auto fold71 = makeBs775Fold(std::span<const LpRole>(kLpRoles71), AsLfeVariantOmit);
    if (!fold51 || !fold71)
    {
        logFail(kName, "no fold for 5.1 or 7.1");
        return;
    }
    const double nan = std::numeric_limits<double>::quiet_NaN();
    const auto cases = std::to_array<std::tuple<const char*, double, double>>({
        {"5.1 Bluetooth", foldTrimDb(lpWorkingCeiling(kLpBluetooth), nan, *fold51), -8.94},
        {"5.1 wired", foldTrimDb(lpWorkingCeiling(kLpBuiltIn), nan, *fold51), -8.04},
        {"7.1 Bluetooth", foldTrimDb(lpWorkingCeiling(kLpBluetooth), nan, *fold71), -9.93},
        {"7.1 wired", foldTrimDb(lpWorkingCeiling(kLpBuiltIn), nan, *fold71), -9.03},
    });
    std::string fail;
    for (const auto& [what, trim, want] : cases)
    {
        logInfo(std::format(
            "  [info] {}: {} fallback trim {:+.3f} dB (§4: {:+.2f})\n", kName, what, trim, want));
        if (!lpNear(trim, want, kTolDb))
        {
            fail += std::format("\n  {}: {:+.3f} dB, want {:+.2f}", what, trim, want);
        }
    }
    // A measured fold peak is used as is; a peak under the ceiling needs no trim.
    if (!lpNear(foldTrimDb(-1.282, 5.56, *fold51), -6.842, 1e-9) ||
        foldTrimDb(-1.282, -3.0, *fold51) != 0.0)
    {
        fail += "\n  a measured fold peak is not trimmed to min(0, C_work − TP_F)";
    }
    if (!fail.empty())
    {
        logFail(kName, "the fallback trim differs from §4:" + fail);
        return;
    }
    logPass(kName);
}

// ===========================================================================
// LP-4: C_work = 20·log10(ceiling × kIspSafetyMargin) − 0.01 dB (§1.1): −1.282 dBTP on Bluetooth and
// on an unknown output (−1 dBTP), −0.380 on a wired or built-in one (−0.1 dBTP).
// ===========================================================================
static auto testLevelPlanWorkingCeiling() -> void
{
    static const char* const kName = "LevelPlan_WorkingCeiling";
    constexpr double kTolDb = 0.001;
    const double bluetooth = lpWorkingCeiling(kLpBluetooth);
    const double unknown = lpWorkingCeiling(0U);
    const double wired = lpWorkingCeiling(kLpBuiltIn);
    logInfo(std::format("  [info] {}: Bluetooth {:+.4f}, unknown {:+.4f}, wired {:+.4f} dBTP\n",
                        kName,
                        bluetooth,
                        unknown,
                        wired));
    if (!lpNear(bluetooth, -1.282, kTolDb) || !lpNear(unknown, -1.282, kTolDb) ||
        !lpNear(wired, -0.380, kTolDb))
    {
        logFail(
            kName,
            std::format("C_work Bluetooth {:+.4f} / unknown {:+.4f} / wired {:+.4f}, want −1.282 / "
                        "−1.282 / −0.380",
                        bluetooth,
                        unknown,
                        wired));
        return;
    }
    logPass(kName);
}

// ===========================================================================
// LP-5: the LFE variants' per-side gains (§5): 0, 0.5, 1.0 and +4 dB; 0 for a variant out of range —
// through the C entry the app and the decision builder use.
// ===========================================================================
static auto testLevelPlanLfeVariantGains() -> void
{
    static const char* const kName = "LevelPlan_LfeVariantGains";
    const double filmDb =
        20.0 * std::log10(static_cast<double>(asLfeVariantGain(AsLfeVariantFilm)));
    if (asLfeVariantGain(AsLfeVariantOmit) != 0.0F || asLfeVariantGain(AsLfeVariantMusic) != 0.5F ||
        asLfeVariantGain(AsLfeVariantFull) != 1.0F || !lpNear(filmDb, 4.0, 1e-5) ||
        asLfeVariantGain(AS_FOLD_LFE_VARIANTS) != 0.0F)
    {
        logFail(kName,
                std::format("variant gains {} / {} / {} / {:+.5f} dB / out of range {}",
                            asLfeVariantGain(0U),
                            asLfeVariantGain(1U),
                            asLfeVariantGain(2U),
                            filmDb,
                            asLfeVariantGain(AS_FOLD_LFE_VARIANTS)));
        return;
    }
    logPass(kName);
}

// ===========================================================================
// LP-6 (S2): the kernel says whether the crossfeed PLAYS — what the "XF" chip shows. On a stereo block
// with crossfeed on: engaged. Turned off: still engaged while it glides out, then not. On a 6-channel
// block (a folded file) never, whatever is asked. A fresh initialize() says not engaged.
// ===========================================================================
static auto testKernelCrossfeedEngagedFollowsWhatPlays() -> void
{
    static const char* const kName = "Kernel_CrossfeedEngaged_FollowsWhatPlays";
    constexpr uint32_t kSR = TestConstants::kSampleRate48k;
    constexpr uint32_t kFrames = TestConstants::kFrames512;
    constexpr int kGlideOutBlocks = 100; // ~1 s: far past the crossfeed's glide out
    DSPKernel kernel;
    kernel.initialize(kSR, kFrames);
    TargetState state = makeIdentityState();
    const auto render = [&kernel](uint32_t channels)
    {
        TestABLN abl(channels, kFrames);
        for (auto& channel : abl.channels)
        {
            std::ranges::fill(channel, 0.1F);
        }
        kernel.process(abl.abl(), kFrames);
    };

    if (kernel.crossfeedEngaged())
    {
        logFail(kName, "engaged before anything rendered");
        return;
    }
    state.crossfeed = deriveCfParams(1U, kCfPresetDefault, kSR);
    kernel.publishTargetState(state);
    render(TestConstants::kStereo);
    const bool onStereo = kernel.crossfeedEngaged();
    render(TestConstants::kNChannels6);
    const bool onSix = kernel.crossfeedEngaged();
    render(TestConstants::kStereo);
    state.crossfeed.enabled = 0U;
    kernel.publishTargetState(state);
    render(TestConstants::kStereo);
    const bool glidingOut = kernel.crossfeedEngaged();
    for (int block = 0; block < kGlideOutBlocks; ++block)
    {
        render(TestConstants::kStereo);
    }
    const bool afterGlide = kernel.crossfeedEngaged();
    state.crossfeed.enabled = 1U;
    kernel.publishTargetState(state);
    render(TestConstants::kStereo);
    kernel.initialize(kSR, kFrames);
    const bool afterInitialize = kernel.crossfeedEngaged();
    if (!onStereo || onSix || !glidingOut || afterGlide || afterInitialize)
    {
        logFail(kName,
                std::format(
                    "engaged: on stereo {}, on 6 channels {}, gliding out {}, after the glide {}, "
                    "after initialize {} (want true, false, true, false, false)",
                    onStereo,
                    onSix,
                    glidingOut,
                    afterGlide,
                    afterInitialize));
        return;
    }
    logPass(kName);
}

// ===========================================================================
// LP-7: an unfolded track (§1.3): g = min(−18 − L, C_work − TP_N, +12), P = TP_N, no trim. A quiet track
// rises to −18; a hot master is turned down to it; a peaky quiet one stops at the peak cap; a near-silent
// hiss stops at +12 (F4).
// ===========================================================================
static auto testPlannerUnfolded() -> void
{
    static const char* const kName = "Planner_Unfolded";
    const std::span<const LpRole> stereo(kLpRolesStereo);
    const AsOutputState wired = lpOutput(kLpBuiltIn, stereo, 2U);
    const AsOutputState bluetooth = lpOutput(kLpBluetooth, stereo, 2U);
    LpExpect expect;

    AsTrackLeveling quiet = lpDecision(-24.0, -8.0, stereo);
    const AsTrackPlan raised = asPlanTrack(&quiet, &wired, nullptr);
    expect.near("quiet: g", raised.levelGainDb, 6.0);
    expect.near("quiet: P", raised.peakDbtp, -8.0);
    expect.near("quiet: L", raised.loudnessLufs, -24.0);
    expect.that(raised.mode == AsLevelingModeLeveled && raised.folds == 0U &&
                    raised.foldTrimDb == 0.0,
                "quiet: leveled, no fold, no trim");
    expect.that(raised.version == static_cast<uint32_t>(AS_TRACK_PLAN_VERSION),
                "the plan's version");

    AsTrackLeveling hot = lpDecision(-8.0, 1.2, stereo);
    expect.near("hot: g", asPlanTrack(&hot, &bluetooth, nullptr).levelGainDb, -10.0);

    AsTrackLeveling peaky = lpDecision(-30.0, -3.0, stereo);
    expect.near("peaky: g at the peak cap",
                asPlanTrack(&peaky, &wired, nullptr).levelGainDb,
                lpWorkingCeiling(kLpBuiltIn) + 3.0);

    AsTrackLeveling hiss = lpDecision(-60.0, -40.0, stereo);
    expect.near("hiss: g at +12", asPlanTrack(&hiss, &wired, nullptr).levelGainDb, 12.0);

    if (!expect.failures.empty())
    {
        logFail(kName, "the unfolded plan breaks §1.3:" + expect.failures);
        return;
    }
    logPass(kName);
}

// ===========================================================================
// LP-8: §4's worked example — 5.1 on Bluetooth, TP_N +0.23, TP_F +5.56, L_N −6.50, L_F −4.10 (computed
// there without ε; here every cap is ε = 0.01 dB lower): trim = C_work − TP_F (−6.84), P = TP_N (+0.23),
// L = L_F + trim (−10.94), g = −18 − L (−7.06).
// ===========================================================================
static auto testPlannerWorkedExample() -> void
{
    static const char* const kName = "Planner_WorkedExample";
    const std::span<const LpRole> roles(kLpRoles51);
    const AsOutputState bluetooth = lpOutput(kLpBluetooth, roles, 2U);
    AsTrackLeveling decision = lpFoldedDecision(-6.50, 0.23, -4.10, 5.56, roles);
    const AsTrackPlan plan = asPlanTrack(&decision, &bluetooth, nullptr);
    const double cWork = lpWorkingCeiling(kLpBluetooth);
    LpExpect expect;
    expect.that(plan.folds == 1U && plan.foldFromAnalysis == 1U,
                "5.1 on stereo folds, from the measured fold");
    expect.near("trim", plan.foldTrimDb, cWork - 5.56);
    expect.near("P", plan.peakDbtp, 0.23);
    expect.near("L", plan.loudnessLufs, -4.10 + (cWork - 5.56));
    expect.near("g", plan.levelGainDb, -18.0 - (-4.10 + (cWork - 5.56)));
    expect.near("C_work", plan.workingCeilingDbtp, cWork);
    logInfo(std::format(
        "  [info] {}: trim {:+.3f}, P {:+.3f}, L {:+.3f}, g {:+.3f} dB (§4: −6.84, +0.23, −10.93, "
        "−7.07 without ε)\n",
        kName,
        plan.foldTrimDb,
        plan.peakDbtp,
        plan.loudnessLufs,
        plan.levelGainDb));
    if (!expect.failures.empty())
    {
        logFail(kName, "§4's worked example does not reproduce:" + expect.failures);
        return;
    }
    logPass(kName);
}

// ===========================================================================
// LP-9: a mono file plays on both sides at 0 dB (F8; the founder's XM4 listen, C1): on ≥ 2 outputs it is
// levelled as dual mono, 10·log10(2) = 3.01 LU above its one-channel measure. On a mono output, as measured.
// ===========================================================================
static auto testPlannerMonoDualMono() -> void
{
    static const char* const kName = "Planner_Mono_DualMono";
    const std::span<const LpRole> mono(kLpRolesMono);
    const double dualMono = 10.0 * std::log10(2.0);
    AsTrackLeveling decision = lpDecision(-21.0, -6.0, mono);
    const AsOutputState stereoOut = lpOutput(kLpBuiltIn, mono, 2U);
    const AsOutputState monoOut = lpOutput(kLpBuiltIn, mono, 1U);
    LpExpect expect;
    const AsTrackPlan onStereo = asPlanTrack(&decision, &stereoOut, nullptr);
    expect.near("L on 2 outputs", onStereo.loudnessLufs, -21.0 + dualMono);
    expect.near("g on 2 outputs", onStereo.levelGainDb, -18.0 - (-21.0 + dualMono));
    expect.that(onStereo.folds == 0U, "mono never folds");
    const AsTrackPlan onMono = asPlanTrack(&decision, &monoOut, nullptr);
    expect.near("L on 1 output", onMono.loudnessLufs, -21.0);
    expect.near("g on 1 output", onMono.levelGainDb, 3.0);
    if (!expect.failures.empty())
    {
        logFail(kName, "mono is not levelled as it plays:" + expect.failures);
        return;
    }
    logPass(kName);
}

// ===========================================================================
// LP-10: unknown loudness (F4, NI-7). No gated block, a loudness at or under −70 LUFS, or the unknown mode:
// g = min(0, −5 − trim, C_work − P). Unfolded, that is −5 dB; a fold's fallback trim already cuts more than
// −5, so only the peak cap remains; a known hot peak (a +5 dBTP sting) cuts below −5, so the limiter never acts.
// ===========================================================================
static auto testPlannerUnknownLoudness() -> void
{
    static const char* const kName = "Planner_UnknownLoudness";
    const std::span<const LpRole> stereo(kLpRolesStereo);
    const std::span<const LpRole> roles51(kLpRoles51);
    const AsOutputState bluetooth = lpOutput(kLpBluetooth, stereo, 2U);
    const AsOutputState folded = lpOutput(kLpBluetooth, roles51, 2U);
    const double cWork = lpWorkingCeiling(kLpBluetooth);
    LpExpect expect;

    AsTrackLeveling noGatedBlock = lpDecision(kLpNaN, kLpNaN, stereo);
    const AsTrackPlan unknown = asPlanTrack(&noGatedBlock, &bluetooth, nullptr);
    expect.near("no gated block: g", unknown.levelGainDb, -5.0);
    expect.that(std::isnan(unknown.loudnessLufs), "no gated block: L stays unknown");

    AsTrackLeveling silent = lpDecision(-72.0, -50.0, stereo);
    expect.near("−72 LUFS: g", asPlanTrack(&silent, &bluetooth, nullptr).levelGainDb, -5.0);

    AsTrackLeveling cutMode = lpDecision(-12.0, -1.0, stereo);
    cutMode.mode = AsLevelingModeUnknownCut;
    cutMode.source = AsLevelingSourceUnknownCut;
    expect.near(
        "the unknown mode: g", asPlanTrack(&cutMode, &bluetooth, nullptr).levelGainDb, -5.0);

    AsTrackLeveling sting = lpDecision(kLpNaN, 5.0, stereo);
    expect.near("a +5 dBTP sting: g (NI-7)",
                asPlanTrack(&sting, &bluetooth, nullptr).levelGainDb,
                cWork - 5.0);

    AsTrackLeveling surround = lpDecision(kLpNaN, kLpNaN, roles51);
    const AsTrackPlan fallback = asPlanTrack(&surround, &folded, nullptr);
    expect.near("5.1 fallback: trim", fallback.foldTrimDb, -8.94, 0.01);
    expect.near("5.1 fallback: g, the trim not cut twice",
                fallback.levelGainDb,
                std::min(0.0, cWork - 0.0));
    if (!expect.failures.empty())
    {
        logFail(kName, "the unknown-loudness rule breaks F4 / NI-7:" + expect.failures);
        return;
    }
    logPass(kName);
}

// ===========================================================================
// LP-11: the peak the plan protects (§6; architect N6). Unknown, or measured at a rate other than the
// engine's (a tag's peak), it counts as 0 dBTP — raised to it only above full scale, so a track is never
// raised on an unverified peak.
// ===========================================================================
static auto testPlannerPeakRate() -> void
{
    static const char* const kName = "Planner_PeakRate";
    const std::span<const LpRole> stereo(kLpRolesStereo);
    const AsOutputState wired = lpOutput(kLpBuiltIn, stereo, 2U);
    LpExpect expect;
    AsTrackLeveling unknown = lpDecision(-30.0, kLpNaN, stereo);
    expect.near("unknown TP: P", asPlanTrack(&unknown, &wired, nullptr).peakDbtp, 0.0);
    AsTrackLeveling tagLow = lpDecision(-30.0, -3.0, stereo);
    tagLow.peakRateHz = 0.0;
    expect.near("a −3 dBTP tag peak: P", asPlanTrack(&tagLow, &wired, nullptr).peakDbtp, 0.0);
    AsTrackLeveling otherRate = lpDecision(-30.0, 1.0, stereo);
    otherRate.peakRateHz = 44100.0;
    expect.near("+1 dBTP at 44.1 kHz: P", asPlanTrack(&otherRate, &wired, nullptr).peakDbtp, 1.0);
    AsTrackLeveling engineRate = lpDecision(-30.0, -3.0, stereo);
    expect.near("−3 dBTP at the engine's rate: P",
                asPlanTrack(&engineRate, &wired, nullptr).peakDbtp,
                -3.0);
    if (!expect.failures.empty())
    {
        logFail(kName, "the protected peak is not the limiter's:" + expect.failures);
        return;
    }
    logPass(kName);
}

// ===========================================================================
// LP-12: the fold's fallback (§4, §S1b): without fold numbers, or with roles that differ from playback's,
// the trim is the matrix's worst case over the N-channel peak: min(0, C_work − (Σ|row| + TP_N)), and L the
// N-channel measure plus the trim.
// ===========================================================================
static auto testPlannerFoldFallback() -> void
{
    static const char* const kName = "Planner_FoldFallback";
    const std::span<const LpRole> roles51(kLpRoles51);
    const AsOutputState bluetooth = lpOutput(kLpBluetooth, roles51, 2U);
    const double cWork = lpWorkingCeiling(kLpBluetooth);
    const auto fold = makeBs775Fold(roles51, AsLfeVariantOmit);
    if (!fold)
    {
        logFail(kName, "no 5.1 fold");
        return;
    }
    const double expectedTrim = std::min(0.0, cWork - (fold->worstRowGainDb() - 2.0));
    LpExpect expect;
    AsTrackLeveling unmeasured = lpDecision(-14.0, -2.0, roles51);
    const AsTrackPlan plan = asPlanTrack(&unmeasured, &bluetooth, nullptr);
    expect.that(plan.folds == 1U && plan.foldFromAnalysis == 0U, "no fold numbers: the fallback");
    expect.near("trim", plan.foldTrimDb, expectedTrim);
    expect.near("P", plan.peakDbtp, std::max(-2.0, fold->worstRowGainDb() - 2.0 + expectedTrim));
    expect.near("L", plan.loudnessLufs, -14.0 + expectedTrim);

    // Fold numbers measured with other roles (the AAC order, C L R …) are not this file's.
    AsTrackLeveling otherRoles = lpFoldedDecision(-14.0, -2.0, -15.0, 1.0, roles51);
    std::swap(otherRoles.roles[0], otherRoles.roles[2]);
    const AsTrackPlan mismatch = asPlanTrack(&otherRoles, &bluetooth, nullptr);
    expect.that(mismatch.foldFromAnalysis == 0U, "roles that differ from playback's: the fallback");
    expect.near("roles that differ: trim", mismatch.foldTrimDb, expectedTrim);
    if (!expect.failures.empty())
    {
        logFail(kName, "the fold's fallback breaks §4:" + expect.failures);
        return;
    }
    logPass(kName);
}

// ===========================================================================
// LP-13: the protective re-plan at an output change (F5): g and the LFE variant stay frozen; the trim and P
// follow the new ceiling — trim′ = min(0, C_work′ − (TP_F[v] + g)), P′ = max(TP_N, TP_F[v] + trim′). F5's
// example: g +5.62, TP_F −3.5, TP_N −6, moving to Bluetooth: trim′ −3.40 dB.
// ===========================================================================
static auto testPlannerProtectiveReplan() -> void
{
    static const char* const kName = "Planner_ProtectiveReplan";
    const std::span<const LpRole> roles51(kLpRoles51);
    const AsOutputState bluetooth = lpOutput(kLpBluetooth, roles51, 2U);
    const double cWork = lpWorkingCeiling(kLpBluetooth);
    AsTrackLeveling decision =
        lpFoldedDecision(-24.0, -6.0, -23.62, -3.5, roles51, AsLfeVariantMusic);
    AsTrackPlan frozen{};
    frozen.version = static_cast<uint32_t>(AS_TRACK_PLAN_VERSION);
    frozen.mode = AsLevelingModeLeveled;
    frozen.lfeVariant = AsLfeVariantMusic;
    frozen.levelGainDb = 5.62;
    const AsTrackPlan replanned = asPlanTrack(&decision, &bluetooth, &frozen);
    LpExpect expect;
    expect.near("g frozen", replanned.levelGainDb, 5.62);
    expect.that(replanned.lfeVariant == AsLfeVariantMusic, "the variant frozen");
    expect.near("trim′", replanned.foldTrimDb, cWork - (-3.5 + 5.62));
    expect.near("trim′ (F5: −3.40)", replanned.foldTrimDb, -3.40, 0.01);
    expect.near("P′", replanned.peakDbtp, std::max(-6.0, -3.5 + (cWork - 2.12)));
    if (!expect.failures.empty())
    {
        logFail(kName, "the protective re-plan breaks F5:" + expect.failures);
        return;
    }
    logPass(kName);
}

// ===========================================================================
// LP-14: Leveling Off keeps g = 0 and still protects the fold (the trim); no decision at audibility (a bug
// state) plans Off with the matrix's worst-case trim, never 0.
// ===========================================================================
static auto testPlannerOffAndNoDecision() -> void
{
    static const char* const kName = "Planner_OffAndNoDecision";
    const std::span<const LpRole> roles51(kLpRoles51);
    const AsOutputState bluetooth = lpOutput(kLpBluetooth, roles51, 2U);
    const double cWork = lpWorkingCeiling(kLpBluetooth);
    LpExpect expect;
    AsTrackLeveling off = lpFoldedDecision(-6.5, 0.23, -4.1, 5.56, roles51);
    off.mode = AsLevelingModeOff;
    const AsTrackPlan offPlan = asPlanTrack(&off, &bluetooth, nullptr);
    expect.that(offPlan.mode == AsLevelingModeOff, "Off is planned Off");
    expect.near("Off: g", offPlan.levelGainDb, 0.0);
    expect.near("Off: the trim still protects the fold", offPlan.foldTrimDb, cWork - 5.56);
    const AsTrackPlan none = asPlanTrack(nullptr, &bluetooth, nullptr);
    expect.that(none.mode == AsLevelingModeOff && none.folds == 1U, "no decision: Off, folding");
    expect.near("no decision: g", none.levelGainDb, 0.0);
    expect.near("no decision: the worst-case trim", none.foldTrimDb, -8.94, 0.01);
    const AsTrackPlan noOutput = asPlanTrack(nullptr, nullptr, nullptr);
    expect.near("no output: an unknown stereo output's C_work",
                noOutput.workingCeilingDbtp,
                lpWorkingCeiling(0U));
    if (!expect.failures.empty())
    {
        logFail(kName, "Off or a missing decision is not safe:" + expect.failures);
        return;
    }
    logPass(kName);
}

// ===========================================================================
// LP-15: the gain to −18 LUFS, end to end (§10's first row): a decision measured with libebur128 → the
// planner → the gain (and, folded, the BS.775 fold and its trim) applied → libebur128 again: −18 LUFS within
// 0.2 LU where the cap allows. Stereo, a folded 5.1, and mono played on two outputs (both sides at 0 dB —
// the dual-mono convention, EBUR128_DUAL_MONO's 3.01 LU).
// ===========================================================================
static auto testPlannerGainToTargetOracle() -> void
{
    static const char* const kName = "Planner_GainToTarget_Oracle";
    constexpr double kSeconds = 8.0;
    constexpr double kToleranceLu = 0.2;
    const AsOutputState wiredStereo =
        lpOutput(kLpBuiltIn, std::span<const LpRole>(kLpRolesStereo), 2U);
    LpExpect expect;

    // Stereo: quiet noise, raised.
    const auto stereo = lpPinkChannels(2U, kSeconds, 71U, -26.0);
    AsTrackLeveling stereoDecision = lpDecision(tlEbur128Lufs(stereo, kLpEngineRate),
                                                lpEbur128TruePeakDbtp(stereo, kLpEngineRate),
                                                std::span<const LpRole>(kLpRolesStereo));
    const AsTrackPlan stereoPlan = asPlanTrack(&stereoDecision, &wiredStereo, nullptr);
    const double stereoOut = tlEbur128Lufs(lpScaled(stereo, stereoPlan.levelGainDb), kLpEngineRate);

    // 5.1, folded with the LFE omitted: the decision carries the fold's own loudness and peak.
    const std::span<const LpRole> roles51(kLpRoles51);
    const auto surround = lpPinkChannels(6U, kSeconds, 72U, -22.0);
    const auto fold = makeBs775Fold(roles51, AsLfeVariantOmit);
    if (!fold)
    {
        logFail(kName, "no 5.1 fold");
        return;
    }
    const auto foldedSource = lpFoldTo(*fold, surround, 0.0);
    // libebur128's 5.1 map is the file's: L R C LFE(unused) Ls Rs.
    AsTrackLeveling surroundDecision =
        lpFoldedDecision(tlEbur128Lufs(surround, kLpEngineRate),
                         lpEbur128TruePeakDbtp(surround, kLpEngineRate),
                         tlEbur128Lufs(foldedSource, kLpEngineRate),
                         lpEbur128TruePeakDbtp(foldedSource, kLpEngineRate),
                         roles51);
    const AsOutputState folding = lpOutput(kLpBuiltIn, roles51, 2U);
    const AsTrackPlan surroundPlan = asPlanTrack(&surroundDecision, &folding, nullptr);
    const double foldedOut =
        tlEbur128Lufs(lpFoldTo(*fold, surround, surroundPlan.foldTrimDb + surroundPlan.levelGainDb),
                      kLpEngineRate);

    // Mono, measured on its one channel, played on both sides at 0 dB.
    const auto mono = lpPinkChannels(1U, kSeconds, 73U, -24.0);
    AsTrackLeveling monoDecision = lpDecision(tlEbur128Lufs(mono, kLpEngineRate),
                                              lpEbur128TruePeakDbtp(mono, kLpEngineRate),
                                              std::span<const LpRole>(kLpRolesMono));
    const AsOutputState monoOnStereo =
        lpOutput(kLpBuiltIn, std::span<const LpRole>(kLpRolesMono), 2U);
    const AsTrackPlan monoPlan = asPlanTrack(&monoDecision, &monoOnStereo, nullptr);
    const auto played = lpScaled(mono, monoPlan.levelGainDb);
    const double monoOut =
        tlEbur128Lufs(std::vector<std::vector<float>>{played[0], played[0]}, kLpEngineRate);

    logInfo(std::format(
        "  [info] {}: stereo g {:+.2f} → {:.3f} LUFS; 5.1 folded trim {:+.2f}, g {:+.2f} → {:.3f} "
        "LUFS; mono g {:+.2f} → {:.3f} LUFS\n",
        kName,
        stereoPlan.levelGainDb,
        stereoOut,
        surroundPlan.foldTrimDb,
        surroundPlan.levelGainDb,
        foldedOut,
        monoPlan.levelGainDb,
        monoOut));
    expect.near("stereo", stereoOut, kLevelingTargetLufs, kToleranceLu);
    expect.near("folded 5.1", foldedOut, kLevelingTargetLufs, kToleranceLu);
    expect.near("mono on two outputs", monoOut, kLevelingTargetLufs, kToleranceLu);
    if (!expect.failures.empty())
    {
        logFail(kName, "the planned gain does not land at −18 LUFS:" + expect.failures);
        return;
    }
    logPass(kName);
}

namespace
{
    constexpr uint64_t kLpTrackA = 0x1E7E15A1ULL;
    constexpr uint64_t kLpTrackB = 0x1E7E15B2ULL;
    constexpr size_t kLpPresetBassBoost = 5U;
    constexpr double kLpGrToleranceDb = 0.01;

    // The limiter's own 8×24 true-peak reading (dBTP) over every channel: the peak the effects limiter
    // sees, so a plan built on it protects exactly what the limiter measures. (The analysis takes the max
    // of this and an 8×64 reading — lane 1-B's.)
    auto lpKernelTruePeakDbtp(const TlChannels& channels) -> double
    {
        TruePeakKernel::Coefficients coeffs{};
        TruePeakKernel::computeCoefficients(coeffs);
        double peak = 0.0;
        for (const std::vector<float>& channel : channels)
        {
            TruePeakKernel::History history{};
            for (const float sample : channel)
            {
                std::copy_backward(history.begin(), history.end() - 1, history.end());
                history.front() = static_cast<double>(sample);
                peak = std::max(peak, TruePeakKernel::phasePeak(history, coeffs));
            }
        }
        return (peak > 0.0) ? 20.0 * std::log10(peak) : kLpNaN;
    }

    // A stereo decision for `programme` as the analysis would measure it at the engine's rate.
    auto lpMeasuredDecision(const TlProgramme& programme, uint8_t mode = AsLevelingModeLeveled)
        -> AsTrackLeveling
    {
        AsTrackLeveling decision =
            lpDecision(tlEbur128Lufs(programme.channels, programme.sampleRate),
                       lpKernelTruePeakDbtp(programme.channels),
                       std::span<const LpRole>(kLpRolesStereo));
        decision.mode = mode;
        return decision;
    }

    // The plan of `decision` on a stereo output of `transport`.
    auto lpStereoPlan(const AsTrackLeveling& decision, uint32_t transport) -> AsTrackPlan
    {
        const AsOutputState output =
            lpOutput(transport, std::span<const LpRole>(kLpRolesStereo), 2U);
        return asPlanTrack(&decision, &output, nullptr);
    }

    // Wait for the Realizer's idle refresh (the full ΔL and the cut allowance), if one is pending.
    auto lpSettle(LnEngine& engine) -> bool
    {
        engine.realizer->barrier();
        return !engine.realizer->loudnessGain().needsRefresh() ||
               rig::waitUntil("the idle refresh ran (needsRefresh() false)",
                              [&] { return !engine.realizer->loudnessGain().needsRefresh(); });
    }

    // What the limiter did to `programme` on `engine`: the largest gain reduction (dB) past `skipSeconds`,
    // found by rendering a twin kernel that gets the same state with its limiter bypassed (zero latency),
    // and comparing it with the engine's output a look-ahead later. `perBlock(firstFrame)` runs before each
    // block (a mid-song event); the twin follows the Realizer's state block by block.
    struct LpGrRun
    {
        double maxGrDb = 0.0;
        double outputPeakDbtp = 0.0; // the engine's output, the limiter's own 8×24 reading
        TlChannels output;
    };
    auto lpGainReduction(LnEngine& engine,
                         const TlProgramme& programme,
                         double skipSeconds,
                         const std::function<void(size_t)>& perBlock = {}) -> LpGrRun
    {
        // The twin starts at the engine's state, as the app's kernel does (its Intensity snaps there).
        DSPKernel twin;
        TargetState first = engine.realizer->canonicalState();
        first.limiter.truePeakCeilingLinear = 2.0F;
        first.limiter.eqOnlyCeilingLinear = 2.0F;
        twin.publishTargetState(first);
        twin.initialize(static_cast<uint32_t>(kEngineFs), kEngineBlock);
        const auto channels = static_cast<uint32_t>(programme.channels.size());
        const size_t frames = programme.frames();
        TestABLN live(channels, kEngineBlock);
        TestABLN dry(channels, kEngineBlock);
        LpGrRun run;
        run.output.assign(channels, std::vector<float>(frames));
        TlChannels bypassed(channels, std::vector<float>(frames));
        for (size_t done = 0U; done < frames; done += kEngineBlock)
        {
            const auto block = static_cast<uint32_t>(std::min<size_t>(kEngineBlock, frames - done));
            if (perBlock)
            {
                perBlock(done);
                engine.realizer->barrier();
            }
            TargetState state = engine.realizer->canonicalState();
            state.limiter.truePeakCeilingLinear = 2.0F; // ≥ 1: bypassed (identity, no look-ahead)
            state.limiter.eqOnlyCeilingLinear = 2.0F;
            twin.publishTargetState(state);
            for (uint32_t ch = 0U; ch < channels; ++ch)
            {
                const float* src = programme.channels[ch].data() + done;
                std::copy_n(src, block, live.channels[ch].begin());
                std::copy_n(src, block, dry.channels[ch].begin());
            }
            engine.kernel->process(live.abl(), block);
            twin.process(dry.abl(), block);
            for (uint32_t ch = 0U; ch < channels; ++ch)
            {
                const auto at = static_cast<std::ptrdiff_t>(done);
                std::copy_n(live.channels[ch].begin(), block, run.output[ch].begin() + at);
                std::copy_n(dry.channels[ch].begin(), block, bypassed[ch].begin() + at);
            }
        }
        const auto delay = static_cast<size_t>(
            std::llround(static_cast<double>(kLimiterLookaheadSeconds) * kEngineFs));
        const auto skip = static_cast<size_t>(skipSeconds * kEngineFs);
        constexpr double kAudibleFloor = 1e-3; // −60 dBFS: below it a ratio says nothing
        for (size_t ch = 0U; ch < channels; ++ch)
        {
            for (size_t frame = skip; frame + delay < frames; ++frame)
            {
                const double drySample = std::abs(static_cast<double>(bypassed[ch][frame]));
                const double wetSample =
                    std::abs(static_cast<double>(run.output[ch][frame + delay]));
                if (drySample > kAudibleFloor && wetSample > 0.0)
                {
                    run.maxGrDb = std::max(run.maxGrDb, 20.0 * std::log10(drySample / wetSample));
                }
            }
        }
        run.outputPeakDbtp = lpKernelTruePeakDbtp(run.output);
        return run;
    }
} // namespace

// ===========================================================================
// LP-16: the level stage's rules (TrackLoudnessGain), unit by unit.
// ===========================================================================
static auto testLevelStageRules() -> void
{
    static const char* const kName = "LevelStage_Rules";
    const GraphicEQDesign warm = engineDesign(kEqPresetCurves[kEqPresetWarm], kEngineFs);
    const GraphicEQDesign cut = engineDesign(eqFlatCurveWith(10U, -12.0F), kEngineFs);
    const TlProgramme programme = lnNoiseProgramme(20.0, 91U, 150.0, -18.0);
    const TlProfiles profiles =
        tlProfile(programme, tlStereoWeights(), static_cast<size_t>(10.0 * kEngineFs));
    const double own = lnOwnGainDb(*profiles.whole, kEqPresetCurves[kEqPresetWarm]);
    const std::span<const LpRole> stereo(kLpRolesStereo);
    const AsTrackPlan quiet = lnQuietPlan();
    AsTrackLeveling hotMaster = lpDecision(-9.0, 0.5, stereo);
    hotMaster.mode = AsLevelingModeOff;
    const AsTrackPlan hot = lpStereoPlan(hotMaster, kLpBuiltIn);
    AsTrackLeveling levelled = lpDecision(-11.0, -1.0, stereo);
    const AsTrackPlan cutBy7 = lpStereoPlan(levelled, kLpBuiltIn);
    LpExpect expect;

    // P0: the EQ Off and no leveling gain apply nothing, whatever the peak.
    TrackLoudnessGain gain(kEngineFs);
    (void)gain.onProfile(kLpTrackA, profiles.whole);
    (void)gain.onPlan(kLpTrackA, AsPlanEventFreshStart, hot, false);
    expect.that(gain.onDesign(warm, false) == 0.0,
                "the EQ Off, Leveling Off, a hot master: exactly 0 dB (P0)");
    // The EQ Off with a leveling gain: g alone (G = 0 by construction at plan time).
    (void)gain.onPlan(kLpTrackA, AsPlanEventModeChange, cutBy7, false);
    expect.near("the EQ Off, leveled: g", gain.gainDb(), cutBy7.levelGainDb);
    expect.near("the EQ Off, leveled: G", gain.neutralDb(), 0.0);
    expect.near("the plan's g", cutBy7.levelGainDb, -7.0);
    // The EQ On, a quiet master: −ΔL, the cap out of the way.
    (void)gain.onPlan(kLpTrackA, AsPlanEventModeChange, quiet, false);
    expect.near("the EQ On, quiet: g + G = −ΔL", gain.onDesign(warm, true), own, 1e-9);
    // The EQ On, a hot master with Leveling Off: the cap binds — quieter by the turn-down.
    const auto turnDown = gain.onPlan(kLpTrackA, AsPlanEventModeChange, hot, false);
    const double bEff =
        std::max(TrackLoudnessGain::playedBoundDb(warm), TrackLoudnessGain::kCutAllowanceDb);
    expect.near("B_eff (a boost curve: its B)", gain.peakBoundDb(), bEff);
    expect.near("C_cap", gain.capDb(), hot.workingCeilingDbtp - (0.5 + 0.0 + bEff));
    expect.near("the EQ On, hot: G = C_cap", gain.gainDb(), std::min(own, gain.capDb()));
    expect.that(gain.capDb() < own, "vacuous: the cap does not bind on the hot master");
    expect.that(turnDown.has_value() &&
                    turnDown->rampSeconds == TrackLoudnessGain::kModeChangeRampSeconds,
                "a mode change glides at 0.15 s");
    // Compare: the identity at g + T, T = G + ΔL ≤ 0.
    expect.near("Compare, hot: g + T", gain.onDesign(warm, true, true), gain.capDb() - own);
    (void)gain.onPlan(kLpTrackA, AsPlanEventModeChange, quiet, false);
    expect.near("Compare, quiet: T = 0", gain.gainDb(), 0.0);
    (void)gain.onDesign(warm, true);

    // The τ per event; plans for a track no longer audible change nothing.
    const auto seam = gain.onPlan(kLpTrackB, AsPlanEventGaplessSeam, hot, false);
    expect.that(seam.has_value() && seam->rampSeconds == TrackLoudnessGain::kTrackChangeRampSeconds,
                "a gapless seam glides at 10 ms");
    const auto output = gain.onPlan(kLpTrackB, AsPlanEventOutputChange, quiet, false);
    expect.that(output.has_value() &&
                    output->rampSeconds == TrackLoudnessGain::kOutputChangeRampSeconds,
                "an output change glides at 10 ms");
    expect.that(!gain.onPlan(kLpTrackA, AsPlanEventModeChange, hot, false).has_value(),
                "a mode change for a track no longer audible changes nothing");

    // A saved profile (C2) is final: the fresh start snaps to it; the analyzer's profiles change nothing.
    TrackLoudnessGain saved(kEngineFs);
    (void)saved.onDesign(warm, true);
    expect.that(!saved.onProfile(kLpTrackA, profiles.whole, true).has_value(),
                "a saved profile waits for audibility");
    const auto start = saved.onPlan(kLpTrackA, AsPlanEventFreshStart, quiet, false);
    expect.that(start.has_value() &&
                    start->rampSeconds == TrackLoudnessGain::kFreshStartRampSeconds,
                "the fresh start snaps (1 ms)");
    expect.near("the saved profile's −ΔL at once", saved.gainDb(), own, 1e-9);
    expect.that(
        !saved.onProfile(kLpTrackA, profiles.prefix).has_value() &&
            !saved
                 .onProfile(
                     kLpTrackA,
                     tlProfile(lnNoiseProgramme(20.0, 92U, 0.0, -18.0), tlStereoWeights()).whole)
                 .has_value(),
        "the analyzer's later profiles change nothing");
    expect.near("still the saved profile's", saved.gainDb(), own, 1e-9);

    // B_eff's cut allowance: a curve whose B is under 0.7 dB counts 0.7 dB until the refresh measures ‖h‖₁.
    TrackLoudnessGain cutting(kEngineFs);
    (void)cutting.onPlan(kLpTrackA, AsPlanEventFreshStart, hot, false);
    (void)cutting.onDesign(cut, true);
    // A lone −12 dB band is not cut-only once solved: its neighbours overshoot (+0.67 dB here) — still
    // under the allowance, so the allowance decides B_eff.
    expect.that(TrackLoudnessGain::playedBoundDb(cut) < TrackLoudnessGain::kCutAllowanceDb,
                "vacuous: the cut's B is not under the 0.7 dB allowance");
    expect.near("before the refresh: the full allowance",
                cutting.peakBoundDb(),
                TrackLoudnessGain::kCutAllowanceDb);
    expect.that(cutting.needsRefresh(), "a cut-only curve schedules the refresh");
    (void)cutting.onRefresh();
    const double l1 = TrackLoudnessGain::impulseL1Db(cut);
    expect.near("after: min(‖h‖₁, 0.7)",
                cutting.peakBoundDb(),
                std::min(l1, TrackLoudnessGain::kCutAllowanceDb));
    expect.that(l1 > 0.0 &&
                    TrackLoudnessGain::impulseL1Db(engineDesign(EqCurve{}, kEngineFs)) == 0.0,
                "‖h‖₁ of a cut exceeds 1; of the identity it is 1");

    // A continuous seam shares the playing neutral gain — never above the new track's cap.
    TrackLoudnessGain group(kEngineFs);
    (void)group.onDesign(warm, true);
    (void)group.onProfile(kLpTrackA, profiles.whole);
    (void)group.onPlan(kLpTrackA, AsPlanEventFreshStart, quiet, false);
    (void)group.onProfile(
        kLpTrackB, tlProfile(lnNoiseProgramme(20.0, 93U, 0.0, -18.0), tlStereoWeights()).whole);
    (void)group.onPlan(kLpTrackB, AsPlanEventGaplessSeam, hot, true);
    expect.that(group.neutralDb() <= group.capDb() + 1e-12,
                "a shared group gain above the new cap");
    logInfo(
        std::format("  [info] {}: −ΔL {:+.3f} dB; hot master: B_eff {:+.3f}, C_cap {:+.3f}; a "
                    "cut's ‖h‖₁ {:+.3f} dB\n",
                    kName,
                    own,
                    bEff,
                    hot.workingCeilingDbtp - (0.5 + bEff),
                    l1));
    if (!expect.failures.empty())
    {
        logFail(kName, "the level stage breaks its rules:" + expect.failures);
        return;
    }
    logPass(kName);
}

// ===========================================================================
// LP-17: no motion inside a song (§6, §10): on an analysed track — its saved profile in before it is
// audible — g and G are sampled 100× across 10 s with the EQ On and Off: max − min = 0. The fresh start
// snaps: 20 ms in, the gain is already the song's.
// ===========================================================================
static auto testLevelNoMotionInsideSong() -> void
{
    static const char* const kName = "Level_NoMotionInsideSong";
    constexpr double kSeconds = 10.0;
    constexpr size_t kSamples = 100U;
    const TlProgramme programme = lnHead(tlGatePink(), kSeconds);
    const std::shared_ptr<const TrackLoudnessProfile> profile =
        tlProfile(programme, tlStereoWeights()).whole;
    const AsTrackPlan plan = lpStereoPlan(lpMeasuredDecision(programme), kLpBluetooth);
    std::string fail;
    for (const bool isOn : {true, false})
    {
        LnEngine engine(kEqPresetCurves[kEqPresetWarm], isOn, kLpBluetooth);
        if (!lpSettle(engine))
        {
            return;
        }
        engine.realizer->publishTrackLoudnessProfile(kLpTrackA, profile, true);
        engine.realizer->applyTrackPlan(kLpTrackA, AsPlanEventFreshStart, plan, false);
        engine.realizer->barrier();
        const size_t every = programme.frames() / kSamples;
        const auto from = static_cast<size_t>(0.02 * kEngineFs);
        double lowest = std::numeric_limits<double>::infinity();
        double highest = -lowest;
        (void)lnRender(*engine.kernel,
                       programme,
                       0U,
                       programme.frames(),
                       [&](size_t first)
                       {
                           if (first >= from && first % every < kEngineBlock)
                           {
                               const double applied = engine.appliedGainDb();
                               lowest = std::min(lowest, applied);
                               highest = std::max(highest, applied);
                           }
                       });
        const double published = engine.realizer->canonicalState().eq.outputGainDb;
        logInfo(std::format(
            "  [info] {}: EQ {}: g {:+.3f}, published {:+.3f} dB; applied {:+.6f} … {:+.6f}\n",
            kName,
            isOn ? "On" : "Off",
            plan.levelGainDb,
            published,
            lowest,
            highest));
        if (!(highest - lowest <= 1e-12) || std::abs(highest - published) > 1e-9)
        {
            fail += std::format(
                "\n  EQ {}: the gain moved {:.6f} dB inside the song (from 20 ms; published "
                "{:+.6f})",
                isOn ? "On" : "Off",
                highest - lowest,
                published);
        }
    }
    if (!fail.empty())
    {
        logFail(kName, "the level moved inside a song:" + fail);
        return;
    }
    logPass(kName);
}

// ===========================================================================
// LP-18: the cap holds (§1.3, §4): with the planned P (the limiter's own reading), g and B_eff, the effects
// limiter never acts — GR < 0.01 dB past the first 5 ms (§6), crossfeed off. The −9 LUFS music-like master
// (808, pink and strings through a soft clipper), peaking over full scale, under the Bass Boost preset:
// Leveling Off (the cap binds: "quieter by the turn-down") on wired and Bluetooth; leveled on both; and the
// EQ Off with a leveling gain.
// ===========================================================================
static auto testLevelCapHoldsNoGainReduction() -> void
{
    static const char* const kName = "Level_CapHolds_NoGainReduction";
    constexpr double kSeconds = 10.0;
    constexpr double kSkipSeconds = 0.005;
    // The −9 LUFS master raised 2 dB in float: peaks over full scale, as the founder's loud MP3s decode
    // (+2 dBFS, the record's test material) — hot enough that the Bass Boost drives the limiter without
    // the cap.
    TlProgramme master = lnHead(tlGateLoudMaster(), kSeconds);
    master.channels = lpScaled(master.channels, 2.0);
    const std::shared_ptr<const TrackLoudnessProfile> profile =
        tlProfile(master, tlStereoWeights()).whole;
    struct Case
    {
        const char* label;
        uint8_t mode;
        uint32_t transport;
        bool eqOn;
    };
    const auto cases = std::to_array<Case>({
        {
            .label = "Leveling Off, Bass Boost, wired",
            .mode = AsLevelingModeOff,
            .transport = kLpBuiltIn,
            .eqOn = true,
        },
        {
            .label = "Leveling Off, Bass Boost, Bluetooth",
            .mode = AsLevelingModeOff,
            .transport = kLpBluetooth,
            .eqOn = true,
        },
        {
            .label = "leveled, Bass Boost, wired",
            .mode = AsLevelingModeLeveled,
            .transport = kLpBuiltIn,
            .eqOn = true,
        },
        {
            .label = "leveled, Bass Boost, Bluetooth",
            .mode = AsLevelingModeLeveled,
            .transport = kLpBluetooth,
            .eqOn = true,
        },
        {
            .label = "leveled, EQ Off, Bluetooth",
            .mode = AsLevelingModeLeveled,
            .transport = kLpBluetooth,
            .eqOn = false,
        },
    });
    std::string fail;
    for (const Case& test : cases)
    {
        LnEngine engine(kEqPresetCurves[kLpPresetBassBoost], test.eqOn, test.transport);
        if (!lpSettle(engine))
        {
            return;
        }
        const AsTrackPlan plan =
            lpStereoPlan(lpMeasuredDecision(master, test.mode), test.transport);
        engine.realizer->publishTrackLoudnessProfile(kLpTrackA, profile, true);
        engine.realizer->applyTrackPlan(kLpTrackA, AsPlanEventFreshStart, plan, false);
        engine.realizer->barrier();
        const LpGrRun run = lpGainReduction(engine, master, kSkipSeconds);
        const TrackLoudnessGain gain = engine.realizer->loudnessGain();
        logInfo(std::format(
            "  [info] {}: {}: P {:+.2f} dBTP, g {:+.2f}, G {:+.2f} (−ΔL capped at {:+.2f}), B_eff "
            "{:+.2f}; GR {:.4f} dB; output {:+.3f} dBTP (C_work {:+.3f})\n",
            kName,
            test.label,
            plan.peakDbtp,
            plan.levelGainDb,
            gain.neutralDb(),
            gain.capDb(),
            gain.peakBoundDb(),
            run.maxGrDb,
            run.outputPeakDbtp,
            plan.workingCeilingDbtp));
        if (!(run.maxGrDb < kLpGrToleranceDb))
        {
            fail += std::format("\n  {}: the limiter took {:.4f} dB", test.label, run.maxGrDb);
        }
    }
    if (!fail.empty())
    {
        logFail(kName, "the cap left the limiter work:" + fail);
        return;
    }
    logPass(kName);
}

// ===========================================================================
// LP-19: Compare is matched (§7, §10): the curve's identity at g + T plays at the EQ-on loudness within
// 0.2 dB (libebur128) — the cap binding (Leveling Off on the hot master) and not (leveled).
// ===========================================================================
static auto testLevelCompareMatched() -> void
{
    static const char* const kName = "Level_Compare_Matched";
    constexpr double kSeconds = 10.0;
    constexpr double kToleranceDb = 0.2;
    const TlProgramme master = lnHead(tlGateLoudMaster(), kSeconds);
    const std::shared_ptr<const TrackLoudnessProfile> profile =
        tlProfile(master, tlStereoWeights()).whole;
    std::string fail;
    for (const uint8_t mode :
         {static_cast<uint8_t>(AsLevelingModeOff), static_cast<uint8_t>(AsLevelingModeLeveled)})
    {
        const AsTrackPlan plan = lpStereoPlan(lpMeasuredDecision(master, mode), kLpBuiltIn);
        std::array<double, 2U> lufs{};
        for (const bool comparing : {false, true})
        {
            LnEngine engine(kEqPresetCurves[kLpPresetBassBoost], true, kLpBuiltIn);
            AdaptiveSound::Realizer::EqIntent intent =
                engineEqIntent(kEqPresetCurves[kLpPresetBassBoost], true);
            intent.comparing = comparing;
            engine.realizer->applyEq(intent);
            if (!lpSettle(engine))
            {
                return;
            }
            engine.realizer->publishTrackLoudnessProfile(kLpTrackA, profile, true);
            engine.realizer->applyTrackPlan(kLpTrackA, AsPlanEventFreshStart, plan, false);
            engine.realizer->barrier();
            const TlChannels out = lnRender(*engine.kernel, master, 0U, master.frames());
            lufs.at(comparing ? 1U : 0U) = tlEbur128Lufs(out, kEngineFs);
        }
        const double mismatch = lufs[1] - lufs[0];
        logInfo(
            std::format("  [info] {}: {}: EQ On {:.3f} LUFS, Compare {:.3f} LUFS ({:+.3f} dB)\n",
                        kName,
                        mode == AsLevelingModeOff ? "Leveling Off (the cap binds)" : "leveled",
                        lufs[0],
                        lufs[1],
                        mismatch));
        if (!(std::abs(mismatch) <= kToleranceDb))
        {
            fail += std::format("\n  mode {}: Compare {:+.3f} dB off the EQ On", mode, mismatch);
        }
    }
    if (!fail.empty())
    {
        logFail(kName, "Compare is not level-matched:" + fail);
        return;
    }
    logPass(kName);
}

// ===========================================================================
// LP-20 (NI-4): the listener changes the Leveling mode mid-song — Track to Album, the album's anchor 4 dB
// higher. The effects unit glides at 0.15 s and the limiter never acts on the way (GR < 0.01 dB). The
// spatial unit gets the same plan in the same turn (lane 2's half of the row).
// ===========================================================================
static auto testLevelModeChangeNoGainReduction() -> void
{
    static const char* const kName = "Level_ModeChange_NoGainReduction";
    constexpr double kSeconds = 8.0;
    const TlProgramme master = lnHead(tlGateLoudMaster(), kSeconds);
    const std::shared_ptr<const TrackLoudnessProfile> profile =
        tlProfile(master, tlStereoWeights()).whole;
    AsTrackLeveling track = lpMeasuredDecision(master);
    AsTrackLeveling album = track;
    album.loudnessLufs =
        track.loudnessLufs - 4.0; // the album's anchor: its loudest song, 4 dB under this
    const AsTrackPlan trackPlan = lpStereoPlan(track, kLpBluetooth);
    const AsTrackPlan albumPlan = lpStereoPlan(album, kLpBluetooth);
    std::string fail;
    for (const bool eqOn : {false, true})
    {
        LnEngine engine(kEqPresetCurves[kEqPresetWarm], eqOn, kLpBluetooth);
        if (!lpSettle(engine))
        {
            return;
        }
        engine.realizer->publishTrackLoudnessProfile(kLpTrackA, profile, true);
        engine.realizer->applyTrackPlan(kLpTrackA, AsPlanEventFreshStart, trackPlan, false);
        engine.realizer->barrier();
        const auto change = static_cast<size_t>(3.0 * kEngineFs);
        const LpGrRun run =
            lpGainReduction(engine,
                            master,
                            0.005,
                            [&](size_t first)
                            {
                                if (first <= change && change < first + kEngineBlock)
                                {
                                    engine.realizer->applyTrackPlan(
                                        kLpTrackA, AsPlanEventModeChange, albumPlan, false);
                                }
                            });
        logInfo(std::format("  [info] {}: EQ {}: g {:+.2f} → {:+.2f} dB at 3 s; GR {:.4f} dB\n",
                            kName,
                            eqOn ? "On" : "Off",
                            trackPlan.levelGainDb,
                            albumPlan.levelGainDb,
                            run.maxGrDb));
        if (!(albumPlan.levelGainDb > trackPlan.levelGainDb))
        {
            fail += "\n  vacuous: the album plan does not raise the gain";
        }
        if (!(run.maxGrDb < kLpGrToleranceDb))
        {
            fail += std::format("\n  EQ {}: the limiter took {:.4f} dB through the glide",
                                eqOn ? "On" : "Off",
                                run.maxGrDb);
        }
    }
    if (!fail.empty())
    {
        logFail(kName, "a mode change made the limiter act:" + fail);
        return;
    }
    logPass(kName);
}

namespace
{
    // `programme` driven `driveDb` into a hard clip at ±1 (a clipped master).
    auto lpClipped(const TlProgramme& programme, double driveDb) -> TlProgramme
    {
        TlProgramme clipped = programme;
        const auto drive = static_cast<float>(std::pow(10.0, driveDb / 20.0));
        for (std::vector<float>& channel : clipped.channels)
        {
            for (float& sample : channel)
            {
                sample = std::clamp(sample * drive, -1.0F, 1.0F);
            }
        }
        return clipped;
    }
} // namespace

// ===========================================================================
// LP-21 (C5; known issue): the closure with the EQ On rests on TP_H ≤ TP + B_eff, a fixture-dependent
// bound, not a strict one. The verify pass measured TP_H − TP up to +2.5 dB on boost curves and +1.9 dB on
// cut-only curves over driven masters (the design's +1.56 / +0.69 were one fixture each). These fixtures LOG
// the gain reduction the limiter takes — the real figures are measured on the founder's hot masters
// (AnalyzeTracks) — and assert only that the limiter holds the ceiling.
// ===========================================================================
static auto testLevelKnownIssueEnvelopeLogged() -> void
{
    static const char* const kName = "Level_KnownIssue_EnvelopeLogged";
    constexpr double kSeconds = 8.0;
    EqCurve sub808{};
    for (size_t band = 0U; band <= 7U; ++band) // 20 … 100 Hz, and 125 Hz: +5 dB over 20–125 Hz
    {
        sub808.at(band) = 5.0F;
    }
    sub808.at(8U) = 5.0F;
    struct Case
    {
        const char* label;
        TlProgramme programme;
        EqCurve curve;
    };
    const auto cases = std::to_array<Case>({
        {
            .label = "a driven 808 under +5 dB on 20–125 Hz",
            .programme = lpClipped(lnHead(tlGate808(), kSeconds), 6.0),
            .curve = sub808,
        },
        {
            .label = "a clipped master under −12 dB at 100 Hz",
            .programme = lpClipped(lnHead(tlGateLoudMaster(), kSeconds), 6.0),
            .curve = eqFlatCurveWith(10U, -12.0F),
        },
    });
    const double ceiling =
        workingCeilingDbtp(outputCeilingLinear(kLpBluetooth)) + kWorkingCeilingGuardDb;
    std::string fail;
    for (const Case& test : cases)
    {
        LnEngine engine(test.curve, true, kLpBluetooth);
        if (!lpSettle(engine))
        {
            return;
        }
        const AsTrackPlan plan =
            lpStereoPlan(lpMeasuredDecision(test.programme, AsLevelingModeOff), kLpBluetooth);
        engine.realizer->publishTrackLoudnessProfile(
            kLpTrackA, tlProfile(test.programme, tlStereoWeights()).whole, true);
        engine.realizer->applyTrackPlan(kLpTrackA, AsPlanEventFreshStart, plan, false);
        engine.realizer->barrier();
        const LpGrRun run = lpGainReduction(engine, test.programme, 0.005);
        const TrackLoudnessGain gain = engine.realizer->loudnessGain();
        logInfo(
            std::format("  [info] {} (known issue, logged): {}: TP {:+.2f} dBTP, B_eff {:+.2f} dB "
                        "→ GR {:.3f} dB; "
                        "output {:+.3f} dBTP\n",
                        kName,
                        test.label,
                        plan.peakDbtp,
                        gain.peakBoundDb(),
                        run.maxGrDb,
                        run.outputPeakDbtp));
        // The limiter still holds: its own reading of the output stays at its working ceiling (+ its
        // detector's documented residual).
        if (!std::isfinite(run.maxGrDb) || !(run.outputPeakDbtp <= ceiling + 0.3))
        {
            fail += std::format("\n  {}: GR {:.3f} dB, output {:+.3f} dBTP over the ceiling",
                                test.label,
                                run.maxGrDb,
                                run.outputPeakDbtp);
        }
    }
    if (!fail.empty())
    {
        logFail(kName, "the limiter did not hold:" + fail);
        return;
    }
    logPass(kName);
}

// ===========================================================================
// LP-22 (M8): the session AGC is gone. With Leveling Off and the EQ Off, Intensity 0 → 1 → 0 changes the
// integrated loudness by no more than 0.1 dB (libebur128) at each settled endpoint: nothing renormalises the
// level any more (before R1.1-B the normaliser pulled Intensity 1 to −16 LUFS). The equal-power blend's mid-knob
// hump is S17's (C-40), so only the endpoints are measured.
// ===========================================================================
static auto testLevelAgcGoneIntensitySweep() -> void
{
    static const char* const kName = "Level_AgcGone_IntensitySweep";
    constexpr double kWindowSeconds = 8.0;
    constexpr double kSettleSeconds = 1.0;
    constexpr double kToleranceDb = 0.1;
    TlProgramme programme =
        lnHead(tlGatePink(), kSettleSeconds + kWindowSeconds); // −18 LUFS, peaks well under 0
    programme.channels = lpScaled(programme.channels, -6.0);   // −24 LUFS: the limiter idle
    const auto settle = static_cast<size_t>(kSettleSeconds * kEngineFs);
    std::array<double, 3U> lufs{};
    size_t step = 0U;
    for (const float intensity : {0.0F, 1.0F, 0.0F})
    {
        LnEngine engine(EqCurve{}, false, kLpBluetooth);
        engine.realizer->applyIntensity(intensity);
        engine.realizer->applyTrackPlan(kLpTrackA, AsPlanEventFreshStart, lnQuietPlan(), false);
        engine.realizer->barrier();
        const TlChannels out = lnRender(*engine.kernel, programme, 0U, programme.frames());
        TlChannels window(out.size());
        for (size_t ch = 0U; ch < out.size(); ++ch)
        {
            window[ch].assign(out[ch].begin() + static_cast<std::ptrdiff_t>(settle), out[ch].end());
        }
        lufs.at(step) = tlEbur128Lufs(window, kEngineFs);
        ++step;
    }
    logInfo(std::format("  [info] {}: Intensity 0 → 1 → 0: {:.3f} → {:.3f} → {:.3f} LUFS\n",
                        kName,
                        lufs[0],
                        lufs[1],
                        lufs[2]));
    if (!(std::abs(lufs[1] - lufs[0]) <= kToleranceDb) ||
        !(std::abs(lufs[2] - lufs[0]) <= kToleranceDb))
    {
        logFail(kName,
                std::format("the level moved with Intensity: {:.3f} → {:.3f} → {:.3f} LUFS",
                            lufs[0],
                            lufs[1],
                            lufs[2]));
        return;
    }
    logPass(kName);
}

// ===========================================================================
// LP-23 (architect N8): the shipping path's golden master — the stereo golden master's chirp at Intensity 0
// (P1), the EQ Off, through the Realizer with a plan whose leveling gain is −7.07 dB (§4's worked example's g,
// on a Bluetooth output): a 64-bit FNV-1a of the L+R output against a committed constant.
// ===========================================================================
static auto testGoldenMasterStereoP1Leveled() -> void
{
    static const char* const kName = "GoldenMaster_StereoN2_P1Leveled_v1";
    constexpr uint32_t kSR = TestConstants::kSampleRate48k;
    constexpr uint32_t kTotal = TestConstants::kTotalFrames1s;
    constexpr uint64_t kFnvOffsetBasis = 0xCBF29CE484222325ULL;
    TlProgramme chirp{kEngineFs, TlChannels(2U, std::vector<float>(kTotal))};
    for (uint32_t idx = 0U; idx < kTotal; ++idx)
    {
        const float timeSec = static_cast<float>(idx) / static_cast<float>(kSR);
        const float freq =
            TestConstants::kChirpF0 + (TestConstants::kChirpF1 - TestConstants::kChirpF0) *
                                          (timeSec / TestConstants::kChirpDuration);
        const float sample =
            std::sin(2.0F * std::numbers::pi_v<float> * freq * timeSec) * TestConstants::kChirpAmpl;
        chirp.channels[0][idx] = sample;
        chirp.channels[1][idx] = sample;
    }
    // §4's stereo numbers: L −10.93 LUFS, TP +0.23 dBTP on Bluetooth → g = −18 − L = −7.07 dB.
    const AsTrackPlan plan = lpStereoPlan(
        lpDecision(-10.93, 0.23, std::span<const LpRole>(kLpRolesStereo)), kLpBluetooth);
    LnEngine engine(EqCurve{}, false, kLpBluetooth);
    engine.realizer->applyTrackPlan(kLpTrackA, AsPlanEventFreshStart, plan, false);
    engine.realizer->barrier();
    const TlChannels out = lnRender(*engine.kernel, chirp, 0U, chirp.frames());
    const uint64_t hash = fnv1aFloats(out[1], fnv1aFloats(out[0], kFnvOffsetBasis));
    logInfo(std::format(
        "  [info] {}: g {:+.2f} dB; output hash = 0x{:016X}\n", kName, plan.levelGainDb, hash));
    if (!lpNear(plan.levelGainDb, -7.07, 1e-9))
    {
        logFail(kName, std::format("the plan's g is {:+.4f} dB, not −7.07", plan.levelGainDb));
        return;
    }
    if (hash != TestConstants::kGoldenMasterStereoP1LeveledHash)
    {
        logFail(kName,
                std::format("golden-master hash mismatch: got 0x{:016X}, expected 0x{:016X} (the "
                            "shipping path's "
                            "output changed — intended? then re-baseline)",
                            hash,
                            TestConstants::kGoldenMasterStereoP1LeveledHash));
        return;
    }
    logPass(kName);
}
