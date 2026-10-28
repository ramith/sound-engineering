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
