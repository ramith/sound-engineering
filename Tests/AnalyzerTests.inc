// AnalyzerTests.inc
//
// The one analysis pass: the two kernels, folds × 4, histograms, LFE statistics, compact profiles (§S1).
// #included into Tests/DSPKernelNullTest.cpp after TestSupport.h; its rows go in the kTests block
// marked "AnalyzerTests.inc" there, so the two lanes never edit the same lines of the table.
//
// R1.1-B W4, lane 1-B (docs/design/level-and-fold/README.md §1.2, §2, §5, §S1, §S1b).
//
// Roles (step 2):
//   AN-R1 Roles_FromTags          — Apple's tags, expanded by AudioToolbox, give each slot its label's role:
//                                   AAC/ALAC 5.1 (C L R Ls Rs LFE), WAVE 5.1 B (L R C LFE Rls Rrs), WAVE 7.1,
//                                   MPEG 7.1 A/C, quad, 3.0, 6.1, mono, stereo.
//   AN-R2 Roles_FromDescriptions  — tag 0 with one description per channel (the corpus's 7.0 FLAC); a label
//                                   the fold has no row for (a height, a discrete n) is Unknown in its slot.
//   AN-R3 Roles_FromBitmap        — a channel bitmap, in bit order.
//   AN-R4 Roles_CountFallbacks    — no layout, DiscreteInOrder, Unknown, all-discrete labels or a layout for
//                                   another count: RFC 9639's WAV order for 1 … 8.
//   AN-R5 Roles_Guards            — a NULL roles array, 0 or 9 channels: false, nothing written.
//   AN-R6 Roles_Bs1770Weights     — BS.1770-5 Table 3 / Annex 3 Table 5 by role: surrounds 1.41, a lone back
//                                   pair 1.41, a back pair beside a side pair (7.x) 1.0, the LFE 0.
//
// The analyzer (step 3):
//   AN-T1 AnalysisTP_VsExactReference   — the reading (max of 8×24, 8×64 and the samples) against the exact
//                                         band-limited reconstruction (Whittaker–Shannon over the whole
//                                         sequence) on ISP, multi-tone, pulse, HF-burst and loud-master
//                                         fixtures: ≤ 0.1 dB up to 20 kHz (§10); 21–22 kHz bursts and
//                                         full-band clipped white noise logged.
//   AN-T2 AnalysisTP_NotBelowShippedKernel — never below the limiter's own 8×24 reading nor the sample peak.
//   AN-T3 AnalysisTP_PruningIsExact     — the pruned reading equals the brute-force one; the bound prunes.
//   AN-M1 Analyzer_LoudnessVsEbur128    — L_N for stereo, 5.1, 7.1 (side 1.41, back 1.0) and mono, and L_F at
//                                         all four LFE variants, against libebur128 on the same samples.
//   AN-M2 Analyzer_HistogramsAndPool    — the histograms pool to libebur128's histogram-mode loudness (one
//                                         track and two together); head and tail blocks.
//   AN-M3 Analyzer_FoldVariantsAndEdges — no LFE: four equal variants; stereo: no fold; an LFE raises the
//                                         fold with its gain; silence; a stream under one block.
//   AN-M4 Analyzer_AbiGuards            — the C entries refuse bad input and write nothing.
//   AN-F1 LfeStats_MatchesPrototype     — the LFE statistics through the C-ABI against the design prototype's
//                                         numbers (proto/p4_lfe_v2.py) on deterministic fixtures, and the
//                                         decisions they lead to (FoldLfeRule).
//   AN-P1 CompactProfile_PredictsLikeFull — the persisted profile (1/24 octave, capped at 1200 blocks,
//                                         binary16) predicts ΔL within the design's 0.023 dB of today's full
//                                         profile: the gate programmes (exact under the cap), a −45 LUFS one
//                                         (binary16's range), and 4-minute ones (thinned to every 2nd block).
//   AN-P2 CompactProfile_RoundTrip      — analyzer → binary16 → asLoudnessProfileFromCompact → the same bits;
//                                         its guards; the predictor reads a 1/12-octave profile on its own grid.

#include "../Sources/AudioDSP/Loudness/AnalysisTruePeak.h"
#include "../Sources/AudioDSP/Loudness/ChannelRoles.h"
#include "../Sources/AudioDSP/Loudness/TrackAnalyzer.h"
#include "../Sources/AudioDSP/Loudness/TrackLoudnessHandle.h"
#include "../Sources/AudioDSP/Spatial/FoldLfeRule.h"

namespace
{
    using AnRole = AdaptiveSound::ChannelRole;

    // An AudioChannelLayout with room for kMaxChannels descriptions (the struct is variable-length).
    struct AnLayout
    {
        alignas(AudioChannelLayout)
            std::array<std::byte,
                       offsetof(AudioChannelLayout, mChannelDescriptions) +
                           (kMaxChannels * sizeof(AudioChannelDescription))> bytes{};

        [[nodiscard]] auto get() -> AudioChannelLayout*
        {
            return reinterpret_cast<AudioChannelLayout*>(bytes.data());
        }

        static auto tagged(AudioChannelLayoutTag tag) -> AnLayout
        {
            AnLayout layout;
            layout.get()->mChannelLayoutTag = tag;
            return layout;
        }

        static auto bitmap(AudioChannelBitmap bits) -> AnLayout
        {
            AnLayout layout;
            layout.get()->mChannelLayoutTag = kAudioChannelLayoutTag_UseChannelBitmap;
            layout.get()->mChannelBitmap = bits;
            return layout;
        }

        static auto described(std::initializer_list<AudioChannelLabel> labels) -> AnLayout
        {
            AnLayout layout;
            AudioChannelLayout* raw = layout.get();
            raw->mChannelLayoutTag = kAudioChannelLayoutTag_UseChannelDescriptions;
            raw->mNumberChannelDescriptions = static_cast<UInt32>(labels.size());
            AudioChannelDescription* descriptions = &raw->mChannelDescriptions[0];
            size_t slot = 0U;
            for (const AudioChannelLabel label : labels)
            {
                descriptions[slot].mChannelLabel = label;
                ++slot;
            }
            return layout;
        }
    };

    [[nodiscard]] auto anRoleName(AnRole role) -> const char*
    {
        switch (role)
        {
            case AnRole::Unknown:
                return "?";
            case AnRole::L:
                return "L";
            case AnRole::R:
                return "R";
            case AnRole::C:
                return "C";
            case AnRole::Lfe:
                return "LFE";
            case AnRole::Ls:
                return "Ls";
            case AnRole::Rs:
                return "Rs";
            case AnRole::Lb:
                return "Lb";
            case AnRole::Rb:
                return "Rb";
            case AnRole::Cs:
                return "Cs";
            case AnRole::Lc:
                return "Lc";
            case AnRole::Rc:
                return "Rc";
            case AnRole::Lw:
                return "Lw";
            case AnRole::Rw:
                return "Rw";
            case AnRole::Mono:
                return "Mono";
        }
        return "!";
    }

    // Resolve through the C entry (the one Swift calls) and compare with `want`; "" when equal.
    [[nodiscard]] auto anExpectRoles(const char* what,
                                     const AudioChannelLayout* layout,
                                     std::initializer_list<AnRole> want) -> std::string
    {
        const auto channels = static_cast<uint32_t>(want.size());
        std::array<uint8_t, kMaxChannels> got{};
        got.fill(0xEEU);
        if (!asResolveChannelRoles(layout, channels, got.data()))
        {
            return std::format("\n  {}: the resolver refused {} channels", what, channels);
        }
        std::string gotText;
        std::string wantText;
        bool same = true;
        size_t slot = 0U;
        for (const AnRole role : want)
        {
            same = same && got[slot] == static_cast<uint8_t>(role);
            gotText += std::format(" {}", anRoleName(static_cast<AnRole>(got[slot])));
            wantText += std::format(" {}", anRoleName(role));
            ++slot;
        }
        if (channels < kMaxChannels && got[channels] != 0xEEU)
        {
            return std::format("\n  {}: wrote past slot {}", what, channels - 1U);
        }
        return same ? std::string{}
                    : std::format("\n  {}: roles{} want{}", what, gotText, wantText);
    }
} // namespace

// ===========================================================================
// AN-R1: a layout tag's labels give the roles (Apple's expansion), whatever the slot order.
// ===========================================================================
static auto testRolesFromTags() -> void
{
    static const char* const kName = "Roles_FromTags";
    using enum AnRole;
    std::string fail;
    const auto check =
        [&fail](const char* what, AudioChannelLayoutTag tag, std::initializer_list<AnRole> want)
    {
        AnLayout layout = AnLayout::tagged(tag);
        fail += anExpectRoles(what, layout.get(), want);
    };
    check("Mono", kAudioChannelLayoutTag_Mono, {Mono});
    check("Stereo", kAudioChannelLayoutTag_Stereo, {L, R});
    check("MPEG 3.0 A", kAudioChannelLayoutTag_MPEG_3_0_A, {L, R, C});
    check("Quadraphonic", kAudioChannelLayoutTag_Quadraphonic, {L, R, Ls, Rs});
    check("WAVE 4.0 B (quad, rear pair)", kAudioChannelLayoutTag_WAVE_4_0_B, {L, R, Lb, Rb});
    check("WAVE 5.0 B", kAudioChannelLayoutTag_WAVE_5_0_B, {L, R, C, Lb, Rb});
    check("MPEG 5.1 A", kAudioChannelLayoutTag_MPEG_5_1_A, {L, R, C, Lfe, Ls, Rs});
    check("MPEG 5.1 B", kAudioChannelLayoutTag_MPEG_5_1_B, {L, R, Ls, Rs, C, Lfe});
    check("AAC 5.1 (AAC / ALAC order)", kAudioChannelLayoutTag_AAC_5_1, {C, L, R, Ls, Rs, Lfe});
    check("WAVE 5.1 B (the FLAC 5.1)", kAudioChannelLayoutTag_WAVE_5_1_B, {L, R, C, Lfe, Lb, Rb});
    check("AAC 6.1", kAudioChannelLayoutTag_AAC_6_1, {C, L, R, Ls, Rs, Cs, Lfe});
    check("WAVE 6.1", kAudioChannelLayoutTag_WAVE_6_1, {L, R, C, Lfe, Cs, Ls, Rs});
    check("MPEG 7.1 A", kAudioChannelLayoutTag_MPEG_7_1_A, {L, R, C, Lfe, Ls, Rs, Lc, Rc});
    check("MPEG 7.1 C", kAudioChannelLayoutTag_MPEG_7_1_C, {L, R, C, Lfe, Ls, Rs, Lb, Rb});
    check("WAVE 7.1", kAudioChannelLayoutTag_WAVE_7_1, {L, R, C, Lfe, Lb, Rb, Ls, Rs});
    if (!fail.empty())
    {
        logFail(kName, fail);
        return;
    }
    logPass(kName);
}

// ===========================================================================
// AN-R2: tag 0 with a description per channel (the corpus's 7.0 FLAC: L R C Rls Rrs Ls Rs, no tag).
// ===========================================================================
static auto testRolesFromDescriptions() -> void
{
    static const char* const kName = "Roles_FromDescriptions";
    using enum AnRole;
    std::string fail;
    AnLayout seven = AnLayout::described({
        kAudioChannelLabel_Left,
        kAudioChannelLabel_Right,
        kAudioChannelLabel_Center,
        kAudioChannelLabel_RearSurroundLeft,
        kAudioChannelLabel_RearSurroundRight,
        kAudioChannelLabel_LeftSurround,
        kAudioChannelLabel_RightSurround,
    });
    fail += anExpectRoles("7.0 by labels", seven.get(), {L, R, C, Lb, Rb, Ls, Rs});
    // A height and a discrete label have no fold row: Unknown in their own slots, the others kept.
    AnLayout heights = AnLayout::described({
        kAudioChannelLabel_Left,
        kAudioChannelLabel_Right,
        kAudioChannelLabel_Center,
        kAudioChannelLabel_LFEScreen,
        kAudioChannelLabel_LeftSurround,
        kAudioChannelLabel_RightSurround,
        kAudioChannelLabel_VerticalHeightLeft,
        kAudioChannelLabel_Discrete_7,
    });
    fail +=
        anExpectRoles("5.1.2 by labels", heights.get(), {L, R, C, Lfe, Ls, Rs, Unknown, Unknown});
    AnLayout sides = AnLayout::described({
        kAudioChannelLabel_Left,
        kAudioChannelLabel_Right,
        kAudioChannelLabel_LeftSurroundDirect,
        kAudioChannelLabel_RightSurroundDirect,
        kAudioChannelLabel_LeftBackSurround,
        kAudioChannelLabel_RightBackSurround,
        kAudioChannelLabel_LeftWide,
        kAudioChannelLabel_RightWide,
    });
    fail +=
        anExpectRoles("direct, back and wide labels", sides.get(), {L, R, Ls, Rs, Lb, Rb, Lw, Rw});
    if (!fail.empty())
    {
        logFail(kName, fail);
        return;
    }
    logPass(kName);
}

// ===========================================================================
// AN-R3: a channel bitmap names its channels in bit order.
// ===========================================================================
static auto testRolesFromBitmap() -> void
{
    static const char* const kName = "Roles_FromBitmap";
    using enum AnRole;
    std::string fail;
    AnLayout fivePointOne =
        AnLayout::bitmap(kAudioChannelBit_Left | kAudioChannelBit_Right | kAudioChannelBit_Center |
                         kAudioChannelBit_LFEScreen | kAudioChannelBit_LeftSurround |
                         kAudioChannelBit_RightSurround);
    fail += anExpectRoles("bitmap L R C LFE Ls Rs", fivePointOne.get(), {L, R, C, Lfe, Ls, Rs});
    AnLayout quad =
        AnLayout::bitmap(kAudioChannelBit_Left | kAudioChannelBit_Right |
                         kAudioChannelBit_LeftSurround | kAudioChannelBit_RightSurround);
    fail += anExpectRoles("bitmap L R Ls Rs", quad.get(), {L, R, Ls, Rs});
    if (!fail.empty())
    {
        logFail(kName, fail);
        return;
    }
    logPass(kName);
}

// ===========================================================================
// AN-R4: a layout that names no speaker — or describes another count — falls back to the count, WAV order.
// ===========================================================================
static auto testRolesCountFallbacks() -> void
{
    static const char* const kName = "Roles_CountFallbacks";
    using enum AnRole;
    const std::array<std::initializer_list<AnRole>, kMaxChannels> wavOrder = {
        {
            {Mono},
            {L, R},
            {L, R, C},
            {L, R, Lb, Rb},
            {L, R, C, Lb, Rb},
            {L, R, C, Lfe, Lb, Rb},
            {L, R, C, Lfe, Cs, Ls, Rs},
            {L, R, C, Lfe, Lb, Rb, Ls, Rs},
        },
    };
    std::string fail;
    for (uint32_t count = 1U; count <= kMaxChannels; ++count)
    {
        const auto& want = wavOrder[count - 1U];
        fail += anExpectRoles(std::format("no layout, {} ch", count).c_str(), nullptr, want);
        AnLayout discrete = AnLayout::tagged(kAudioChannelLayoutTag_DiscreteInOrder | count);
        fail +=
            anExpectRoles(std::format("DiscreteInOrder | {}", count).c_str(), discrete.get(), want);
        AnLayout unknown = AnLayout::tagged(kAudioChannelLayoutTag_Unknown | count);
        fail += anExpectRoles(std::format("Unknown | {}", count).c_str(), unknown.get(), want);
    }
    // D0…D5 (the ITU / EBU signals as the decoder reports them): every label discrete.
    AnLayout d0d5 = AnLayout::described({
        kAudioChannelLabel_Discrete_0,
        kAudioChannelLabel_Discrete_1,
        kAudioChannelLabel_Discrete_2,
        kAudioChannelLabel_Discrete_3,
        kAudioChannelLabel_Discrete_4,
        kAudioChannelLabel_Discrete_5,
    });
    fail += anExpectRoles("D0…D5", d0d5.get(), wavOrder[5]);
    // A 5.1 tag on an 8-channel stream does not describe it.
    AnLayout wrongCount = AnLayout::tagged(kAudioChannelLayoutTag_MPEG_5_1_A);
    fail += anExpectRoles("5.1 tag, 8 channels", wrongCount.get(), wavOrder[7]);
    if (!fail.empty())
    {
        logFail(kName, fail);
        return;
    }
    logPass(kName);
}

// ===========================================================================
// AN-R5: the C entry's guards — nothing written on a refusal.
// ===========================================================================
static auto testRolesGuards() -> void
{
    static const char* const kName = "Roles_Guards";
    std::array<uint8_t, kMaxChannels + 1U> roles{};
    roles.fill(0xEEU);
    const bool nullRoles = asResolveChannelRoles(nullptr, 2U, nullptr);
    const bool zero = asResolveChannelRoles(nullptr, 0U, roles.data());
    const bool nine = asResolveChannelRoles(nullptr, kMaxChannels + 1U, roles.data());
    const bool untouched = std::ranges::all_of(roles, [](uint8_t value) { return value == 0xEEU; });
    if (nullRoles || zero || nine || !untouched)
    {
        logFail(
            kName,
            std::format(
                "NULL roles {}, 0 ch {}, 9 ch {}, untouched {}", nullRoles, zero, nine, untouched));
        return;
    }
    logPass(kName);
}

// ===========================================================================
// AN-R6: BS.1770-5 weights by role (Table 3; Annex 3 Table 5).
// ===========================================================================
static auto testRolesBs1770Weights() -> void
{
    static const char* const kName = "Roles_Bs1770Weights";
    using enum AnRole;
    constexpr double kSurround = 1.41253754;
    constexpr double kTol = 1e-6;
    std::string fail;
    const auto expect = [&fail](const char* what,
                                std::initializer_list<AnRole> roles,
                                std::initializer_list<double> want)
    {
        const std::vector<AnRole> list(roles);
        const auto weights = bs1770Weights(list);
        size_t slot = 0U;
        for (const double each : want)
        {
            if (std::abs(weights[slot] - each) > kTol)
            {
                fail += std::format(
                    "\n  {}: slot {} weighs {}, want {}", what, slot, weights[slot], each);
            }
            ++slot;
        }
    };
    expect("5.1", {L, R, C, Lfe, Ls, Rs}, {1.0, 1.0, 1.0, 0.0, kSurround, kSurround});
    expect("5.1 rear", {L, R, C, Lfe, Lb, Rb}, {1.0, 1.0, 1.0, 0.0, kSurround, kSurround});
    expect("7.1",
           {L, R, C, Lfe, Lb, Rb, Ls, Rs},
           {1.0, 1.0, 1.0, 0.0, 1.0, 1.0, kSurround, kSurround});
    expect("6.1", {L, R, C, Lfe, Cs, Ls, Rs}, {1.0, 1.0, 1.0, 0.0, 1.0, kSurround, kSurround});
    expect("wides, centres, unknown, mono",
           {Lw, Rw, Lc, Rc, Unknown, Mono},
           {kSurround, kSurround, 1.0, 1.0, 1.0, 1.0});
    if (!fail.empty())
    {
        logFail(kName, fail);
        return;
    }
    logPass(kName);
}

// ===========================================================================
// The analyzer (step 3): shared fixtures
// ===========================================================================
namespace
{
    constexpr double kAnRate = 48000.0;
    using AnPlanes = std::vector<std::vector<float>>;

    // The exact band-limited reconstruction's peak: Whittaker–Shannon over the whole, silent-ended sequence,
    // x(m + φ) = Σ_n x[n]·sinc(m + φ − n), at every 1/32 sample of every position (vDSP dot products against
    // one precomputed sinc row per fraction), then refined at 1/1024 sample around the 16 best grid points.
    [[nodiscard]] auto anExactPeak(const std::vector<double>& x) -> double
    {
        constexpr size_t kFractions = 32U;
        constexpr int kRefine = 32;
        constexpr size_t kRefined = 16U;
        const size_t length = x.size();
        const auto sinc = [](double d)
        {
            return (std::abs(d) < 1e-12) ? 1.0
                                         : std::sin(std::numbers::pi * d) / (std::numbers::pi * d);
        };
        const auto valueAt = [&x, &sinc](double t)
        {
            double sum = 0.0;
            for (size_t n = 0U; n < x.size(); ++n)
            {
                sum += x[n] * sinc(t - static_cast<double>(n));
            }
            return sum;
        };
        // g_f[j] = sinc(φ + L − 1 − j): then x(m + φ) = Σ_n x[n]·g_f[n + L − 1 − m].
        std::vector<std::pair<double, double>> grid; // (|value|, position)
        std::vector<double> row((2U * length) - 1U);
        for (size_t fraction = 0U; fraction < kFractions; ++fraction)
        {
            const double phi = static_cast<double>(fraction) / kFractions;
            for (size_t j = 0U; j < row.size(); ++j)
            {
                row[j] = sinc(phi + static_cast<double>(length) - 1.0 - static_cast<double>(j));
            }
            for (size_t m = 0U; m < length; ++m)
            {
                double value = 0.0;
                vDSP_dotprD(x.data(),
                            1,
                            row.data() + (length - 1U - m),
                            1,
                            &value,
                            static_cast<vDSP_Length>(length));
                grid.emplace_back(std::abs(value), static_cast<double>(m) + phi);
            }
        }
        std::partial_sort(grid.begin(),
                          grid.begin() + static_cast<ptrdiff_t>(kRefined),
                          grid.end(),
                          [](const auto& a, const auto& b) { return a.first > b.first; });
        double peak = grid.front().first;
        for (size_t best = 0U; best < kRefined; ++best)
        {
            for (int step = -kRefine; step <= kRefine; ++step)
            {
                const double t = grid[best].second + (static_cast<double>(step) /
                                                      (kRefine * static_cast<double>(kFractions)));
                peak = std::max(peak, std::abs(valueAt(t)));
            }
        }
        return peak;
    }

    // The analysis reading of one channel, through the Detector.
    [[nodiscard]] auto anAnalysisPeak(const std::vector<double>& x) -> double
    {
        AnalysisTruePeak::Detector detector(1U);
        const std::array<const double*, 1U> channel = {x.data()};
        detector.process(channel, x.size());
        detector.flush();
        return detector.peakLinear();
    }

    // The analysis reading without pruning: every sample, both kernels, every phase, and the samples.
    [[nodiscard]] auto anBruteForcePeak(const std::vector<double>& x) -> double
    {
        TruePeakKernel::Coefficients shortBank{};
        TruePeakKernel::computeCoefficients(shortBank);
        AnalysisTruePeak::LongCoefficients longBank{};
        AnalysisTruePeak::computeLongCoefficients(longBank);
        std::vector<double> padded(AnalysisTruePeak::kHistory, 0.0);
        padded.insert(padded.end(), x.begin(), x.end());
        padded.insert(padded.end(), AnalysisTruePeak::kHistory, 0.0);
        double peak = 0.0;
        for (size_t n = AnalysisTruePeak::kHistory; n < padded.size(); ++n)
        {
            peak = std::max(peak, std::abs(padded[n]));
            for (uint32_t phase = 0U; phase < 8U; ++phase)
            {
                double shortDot = 0.0;
                for (uint32_t k = 0U; k < AnalysisTruePeak::kShortTaps; ++k)
                {
                    shortDot +=
                        shortBank[(phase * AnalysisTruePeak::kShortTaps) + k] * padded[n - k];
                }
                double longDot = 0.0;
                for (uint32_t k = 0U; k < AnalysisTruePeak::kLongTaps; ++k)
                {
                    longDot += longBank[(phase * AnalysisTruePeak::kLongTaps) + k] * padded[n - k];
                }
                peak = std::max({peak, std::abs(shortDot), std::abs(longDot)});
            }
        }
        return peak;
    }

    // A 4096-sample fixture at 48 kHz: `tone(n)` over the middle 2048 samples under a Hann taper.
    [[nodiscard]] auto anBurst(const std::function<double(double)>& tone) -> std::vector<double>
    {
        constexpr size_t kLength = 4096U;
        constexpr size_t kStart = 1024U;
        constexpr size_t kSpan = 2048U;
        std::vector<double> x(kLength, 0.0);
        for (size_t n = 0U; n < kSpan; ++n)
        {
            const double taper =
                0.5 - (0.5 * std::cos(2.0 * std::numbers::pi * static_cast<double>(n) /
                                      static_cast<double>(kSpan)));
            x[kStart + n] = taper * tone(static_cast<double>(n) / kAnRate);
        }
        return x;
    }

    [[nodiscard]] auto anDb(double linear) -> double
    {
        return 20.0 * std::log10(linear);
    }

    // The analyzer, through the C entries, over planar float channels with `roles`; fed in irregular chunks.
    struct AnRun
    {
        AsTrackAnalyzer* analyzer = nullptr;
        AsTrackAnalysis analysis{};
        bool ok = false;

        AnRun() = default;
        AnRun(const AnRun&) = delete;
        AnRun& operator=(const AnRun&) = delete;
        AnRun(AnRun&&) = delete;
        AnRun& operator=(AnRun&&) = delete;
        ~AnRun()
        {
            asTrackAnalyzerDestroy(analyzer);
        }

        [[nodiscard]] auto histogram(uint8_t basis) const -> std::vector<AsLoudnessBin>
        {
            std::vector<AsLoudnessBin> bins(asTrackAnalyzerHistogram(analyzer, basis, nullptr, 0U));
            (void)asTrackAnalyzerHistogram(
                analyzer, basis, bins.data(), static_cast<uint32_t>(bins.size()));
            return bins;
        }
    };

    auto anAnalyse(AnRun& run,
                   const AnPlanes& planes,
                   std::initializer_list<AnRole> roleList,
                   double rate = kAnRate) -> void
    {
        std::vector<uint8_t> roles;
        for (const AnRole role : roleList)
        {
            roles.push_back(static_cast<uint8_t>(role));
        }
        run.analyzer =
            asTrackAnalyzerCreate(rate, static_cast<uint32_t>(roles.size()), roles.data());
        if (run.analyzer == nullptr || planes.size() != roles.size())
        {
            return;
        }
        constexpr std::array<size_t, 4> kChunks = {4096U, 777U, 12000U, 1U};
        std::vector<const float*> pointers(planes.size());
        const size_t frames = planes.front().size();
        size_t done = 0U;
        for (size_t step = 0U; done < frames; ++step)
        {
            const size_t chunk = std::min(kChunks[step % kChunks.size()], frames - done);
            for (size_t ch = 0U; ch < planes.size(); ++ch)
            {
                pointers[ch] = planes[ch].data() + done;
            }
            if (!asTrackAnalyzerFeed(run.analyzer,
                                     pointers.data(),
                                     static_cast<uint32_t>(pointers.size()),
                                     static_cast<uint32_t>(chunk)))
            {
                return;
            }
            done += chunk;
        }
        run.ok = asTrackAnalyzerFinish(run.analyzer, &run.analysis);
    }

    // libebur128 (integrated, or histogram mode) with an explicit channel map. NaN on any error.
    [[nodiscard]] auto anEbur128(const AnPlanes& planes,
                                 std::initializer_list<int> channelMap,
                                 int mode = EBUR128_MODE_I) -> double
    {
        const auto count = static_cast<unsigned>(planes.size());
        ebur128_state* state = ebur128_init(count, static_cast<unsigned long>(kAnRate), mode);
        if (state == nullptr)
        {
            return std::numeric_limits<double>::quiet_NaN();
        }
        unsigned slot = 0U;
        for (const int channel : channelMap)
        {
            (void)ebur128_set_channel(state, slot++, channel);
        }
        std::vector<double> interleaved(planes.front().size() * count);
        for (size_t frame = 0U; frame < planes.front().size(); ++frame)
        {
            for (size_t ch = 0U; ch < count; ++ch)
            {
                interleaved[(frame * count) + ch] = static_cast<double>(planes[ch][frame]);
            }
        }
        double lufs = std::numeric_limits<double>::quiet_NaN();
        if (ebur128_add_frames_double(state, interleaved.data(), planes.front().size()) !=
                EBUR128_SUCCESS ||
            ebur128_loudness_global(state, &lufs) != EBUR128_SUCCESS)
        {
            lufs = std::numeric_limits<double>::quiet_NaN();
        }
        ebur128_destroy(&state);
        return lufs;
    }

    // The BS.775 fold at `variant` of planar channels with `roles`, through the one table (FoldMatrix.h).
    [[nodiscard]] auto anFold(const AnPlanes& planes,
                              std::initializer_list<AnRole> roleList,
                              uint8_t variant) -> AnPlanes
    {
        const std::vector<AnRole> roles(roleList);
        const auto matrix =
            makeBs775Fold(std::span<const AnRole>(roles), variant).value_or(FoldMatrix{});
        AnPlanes out(2U, std::vector<float>(planes.front().size()));
        for (size_t frame = 0U; frame < planes.front().size(); ++frame)
        {
            for (size_t side = 0U; side < 2U; ++side)
            {
                double sum = 0.0;
                for (size_t ch = 0U; ch < planes.size(); ++ch)
                {
                    sum += static_cast<double>(matrix.gain[side][ch]) *
                           static_cast<double>(planes[ch][frame]);
                }
                out[side][frame] = static_cast<float>(sum);
            }
        }
        return out;
    }

    // A 5.1 programme (L R C LFE Ls Rs) of the gate programmes, with a loud 40 Hz LFE tone.
    [[nodiscard]] auto anSurround(double seconds) -> AnPlanes
    {
        const TlProgramme pink = tlPinkProgramme(kAnRate, seconds, 31U);
        const TlProgramme bass = tl808Programme(kAnRate, seconds, 32U);
        const TlProgramme strings = tlOrchestralProgramme(kAnRate, seconds, 33U);
        std::vector<float> lfe(pink.frames());
        for (size_t frame = 0U; frame < lfe.size(); ++frame)
        {
            lfe[frame] = static_cast<float>(0.5 * std::sin(2.0 * std::numbers::pi * 40.0 *
                                                           static_cast<double>(frame) / kAnRate));
        }
        return {
            pink.channels[0],
            pink.channels[1],
            bass.channels[0],
            lfe,
            strings.channels[0],
            strings.channels[1],
        };
    }
} // namespace

// ===========================================================================
// AN-T1: the reading against the exact band-limited reconstruction.
// ===========================================================================
static auto testAnalysisTpVsExactReference() -> void
{
    static const char* const kName = "AnalysisTP_VsExactReference";
    constexpr double kBoundDb = 0.1;
    struct Case
    {
        const char* name;
        std::function<double(double)> tone;
        bool withinBand; // ≤ 20 kHz: bounded; above: logged
    };
    std::mt19937 rng(7U);
    std::uniform_real_distribution<double> uniform(-1.0, 1.0);
    const TlProgramme master = tlLoudMasterProgramme(kAnRate, 2.0, 44U);
    std::vector<double> noise(2048U);
    for (double& each : noise)
    {
        each = std::clamp(0.9 * uniform(rng), -0.4, 0.4); // hard-clipped noise: not band-limited
    }
    const std::vector<Case> cases = {
        {
            "fs/4 at 45° (ISP +3 dB)",
            [](double t)
            {
                return 0.5 *
                       std::sin((2.0 * std::numbers::pi * 12000.0 * t) + (std::numbers::pi / 4.0));
            },
            true,
        },
        {
            "1 k + 5 k + 11 kHz",
            [](double t)
            {
                return 0.3 * (std::sin(2.0 * std::numbers::pi * 1000.0 * t) +
                              std::sin((2.0 * std::numbers::pi * 5000.0 * t) + 1.0) +
                              std::sin((2.0 * std::numbers::pi * 11000.0 * t) + 2.0));
            },
            true,
        },
        {
            "band-limited pulse (20 kHz) at 1/3 sample",
            [](double t)
            {
                const double d = (t * kAnRate) - 1024.37;
                const double arg = 2.0 * 20000.0 / kAnRate * d;
                return 0.7 * ((std::abs(arg) < 1e-12)
                                  ? 1.0
                                  : std::sin(std::numbers::pi * arg) / (std::numbers::pi * arg));
            },
            true,
        },
        {
            "19 kHz burst",
            [](double t) { return 0.8 * std::sin((2.0 * std::numbers::pi * 19000.0 * t) + 0.3); },
            true,
        },
        {
            "20 kHz burst",
            [](double t) { return 0.8 * std::sin((2.0 * std::numbers::pi * 20000.0 * t) + 0.7); },
            true,
        },
        {
            "21 kHz burst",
            [](double t) { return 0.8 * std::sin((2.0 * std::numbers::pi * 21000.0 * t) + 0.5); },
            false,
        },
        {
            "22 kHz burst",
            [](double t) { return 0.8 * std::sin((2.0 * std::numbers::pi * 22000.0 * t) + 1.1); },
            false,
        },
        {
            "loud master excerpt (soft-clipped mix)",
            [&master](double t)
            {
                return static_cast<double>(
                    master.channels[0][static_cast<size_t>(std::lround(t * kAnRate)) + 48000U]);
            },
            true,
        },
        {
            "clipped white noise (flat to 24 kHz)",
            [&noise](double t)
            { return noise[static_cast<size_t>(std::lround(t * kAnRate)) % noise.size()]; },
            false,
        },
    };
    std::string fail;
    for (const Case& each : cases)
    {
        const std::vector<double> x = anBurst(each.tone);
        const double exact = anExactPeak(x);
        const double reading = anAnalysisPeak(x);
        const double errorDb = anDb(reading) - anDb(exact);
        logInfo(std::format("  {:42} exact {:+7.3f} dBTP  analysis {:+7.3f}  error {:+.3f} dB",
                            each.name,
                            anDb(exact),
                            anDb(reading),
                            errorDb));
        if (each.withinBand && std::abs(errorDb) > kBoundDb)
        {
            fail += std::format("\n  {}: {:+.3f} dB from the exact reconstruction (bound ±{} dB)",
                                each.name,
                                errorDb,
                                kBoundDb);
        }
    }
    if (!fail.empty())
    {
        logFail(kName, fail);
        return;
    }
    logPass(kName);
}

// ===========================================================================
// AN-T2: never below the limiter's own 8×24 reading on the same samples, nor below the sample peak.
// ===========================================================================
static auto testAnalysisTpNotBelowShippedKernel() -> void
{
    static const char* const kName = "AnalysisTP_NotBelowShippedKernel";
    const TlProgramme loud = tlLoudMasterProgramme(kAnRate, 4.0, 41U);
    TruePeakKernel::Coefficients bank{};
    TruePeakKernel::computeCoefficients(bank);
    std::string fail;
    for (size_t ch = 0U; ch < loud.channels.size(); ++ch)
    {
        std::vector<double> x(loud.channels[ch].begin(), loud.channels[ch].end());
        TruePeakKernel::History history{};
        double shipped = 0.0;
        double samplePeak = 0.0;
        const size_t tail = AnalysisTruePeak::kShortTaps;
        for (size_t n = 0U; n < x.size() + tail; ++n)
        {
            std::copy_backward(history.begin(), history.end() - 1, history.end());
            history[0] = (n < x.size()) ? x[n] : 0.0;
            shipped = std::max(shipped, TruePeakKernel::phasePeak(history, bank));
            samplePeak = std::max(samplePeak, std::abs(history[0]));
        }
        const double reading = anAnalysisPeak(x);
        logInfo(
            std::format("  channel {}: analysis {:+.4f} dBTP, the limiter's kernel {:+.4f}, sample "
                        "peak {:+.4f}",
                        ch,
                        anDb(reading),
                        anDb(shipped),
                        anDb(samplePeak)));
        if (reading < shipped * (1.0 - 1e-12) || reading < samplePeak)
        {
            fail +=
                std::format("\n  channel {}: analysis {} below the limiter's {} or the samples' {}",
                            ch,
                            reading,
                            shipped,
                            samplePeak);
        }
    }
    if (!fail.empty())
    {
        logFail(kName, fail);
        return;
    }
    logPass(kName);
}

// ===========================================================================
// AN-T3: the pruned reading is exactly the brute-force one, and the bound does prune.
// ===========================================================================
static auto testAnalysisTpPruningIsExact() -> void
{
    static const char* const kName = "AnalysisTP_PruningIsExact";
    const TlProgramme dynamic = tlPinkProgramme(kAnRate, 3.0, 42U);
    const TlProgramme loud = tlLoudMasterProgramme(kAnRate, 2.0, 43U);
    std::string fail;
    for (const auto* programme : {&dynamic, &loud})
    {
        const std::vector<double> x(programme->channels[0].begin(), programme->channels[0].end());
        AnalysisTruePeak::Detector detector(1U);
        const std::array<const double*, 1U> channel = {x.data()};
        detector.process(channel, x.size());
        detector.flush();
        const double brute = anBruteForcePeak(x);
        const double share = static_cast<double>(detector.evaluatedRuns()) /
                             static_cast<double>(detector.totalRuns());
        logInfo(std::format("  {}: pruned {:.15f}, brute force {:.15f}; runs evaluated {:.1f} %",
                            programme == &dynamic ? "dynamic pink" : "loud master",
                            detector.peakLinear(),
                            brute,
                            100.0 * share));
        if (std::abs(detector.peakLinear() - brute) > 1e-12 * brute)
        {
            fail += std::format(
                "\n  pruned {} differs from brute force {}", detector.peakLinear(), brute);
        }
        if (programme == &dynamic && !(share < 0.5))
        {
            fail += std::format("\n  the bound let {:.1f} % of a dynamic programme's runs through",
                                100.0 * share);
        }
    }
    if (!fail.empty())
    {
        logFail(kName, fail);
        return;
    }
    logPass(kName);
}

// ===========================================================================
// AN-M1: L_N and L_F against libebur128 on the same samples.
// ===========================================================================
static auto testAnalyzerLoudnessVsEbur128() -> void
{
    static const char* const kName = "Analyzer_LoudnessVsEbur128";
    using enum AnRole;
    constexpr double kTolLu = 0.01;
    constexpr double kTpTolDb = 0.3; // libebur128 interpolates 4×, below 20 kHz
    std::string fail;
    const auto expect = [&fail](const char* what, double ours, double reference, double tolerance)
    {
        logInfo(std::format("  {:34} analysis {:+8.3f}  libebur128 {:+8.3f}  Δ {:+.4f}",
                            what,
                            ours,
                            reference,
                            ours - reference));
        if (!(std::abs(ours - reference) <= tolerance))
        {
            fail += std::format(
                "\n  {}: {} vs libebur128 {} (tolerance {})", what, ours, reference, tolerance);
        }
    };
    // Stereo.
    const TlProgramme pink = tlPinkProgramme(kAnRate, 20.0, 51U);
    {
        AnRun run;
        anAnalyse(run, pink.channels, {L, R});
        expect("stereo L_N",
               run.analysis.integratedLufs,
               anEbur128(pink.channels, {EBUR128_LEFT, EBUR128_RIGHT}),
               kTolLu);
        std::vector<float> interleaved(pink.frames() * 2U);
        for (size_t frame = 0U; frame < pink.frames(); ++frame)
        {
            interleaved[2U * frame] = pink.channels[0][frame];
            interleaved[(2U * frame) + 1U] = pink.channels[1][frame];
        }
        double referencePeak = 0.0;
        (void)ebur128TruePeak(interleaved, kOracleRate48k, referencePeak);
        expect("stereo TP_N (dBTP)", run.analysis.truePeakDbtp, anDb(referencePeak), kTpTolDb);
        if (run.analysis.folds != 0U || !std::isnan(run.analysis.foldedLufs[0]))
        {
            fail += "\n  stereo: a fold was measured";
        }
    }
    // Mono: one channel, weight 1 (the planner adds the dual-mono +3.01 LU, not the analysis).
    {
        const AnPlanes mono = {pink.channels[0]};
        AnRun run;
        anAnalyse(run, mono, {Mono});
        expect("mono L_N", run.analysis.integratedLufs, anEbur128(mono, {EBUR128_CENTER}), kTolLu);
    }
    // 5.1: Ls/Rs 1.41, LFE excluded; and the fold at every LFE variant.
    const AnPlanes surround = anSurround(20.0);
    {
        AnRun run;
        anAnalyse(run, surround, {L, R, C, Lfe, Ls, Rs});
        expect("5.1 L_N",
               run.analysis.integratedLufs,
               anEbur128(surround,
                         {
                             EBUR128_LEFT,
                             EBUR128_RIGHT,
                             EBUR128_CENTER,
                             EBUR128_UNUSED,
                             EBUR128_LEFT_SURROUND,
                             EBUR128_RIGHT_SURROUND,
                         }),
               kTolLu);
        for (uint8_t variant = 0U; variant < AS_FOLD_LFE_VARIANTS; ++variant)
        {
            const AnPlanes folded = anFold(surround, {L, R, C, Lfe, Ls, Rs}, variant);
            expect(std::format("5.1 L_F, LFE variant {}", variant).c_str(),
                   run.analysis.foldedLufs[variant],
                   anEbur128(folded, {EBUR128_LEFT, EBUR128_RIGHT}),
                   kTolLu);
        }
    }
    // 7.1 in WAV order: the sides at M±090 (1.41), the backs at M±135 (1.0).
    {
        AnPlanes wide = surround;
        wide.insert(wide.begin() + 4, {surround[4], surround[5]}); // L R C LFE Lb Rb Ls Rs
        for (float& sample : wide[4])
        {
            sample *= 0.5F;
        }
        AnRun run;
        anAnalyse(run, wide, {L, R, C, Lfe, Lb, Rb, Ls, Rs});
        expect("7.1 L_N",
               run.analysis.integratedLufs,
               anEbur128(wide,
                         {
                             EBUR128_LEFT,
                             EBUR128_RIGHT,
                             EBUR128_CENTER,
                             EBUR128_UNUSED,
                             EBUR128_Mp135,
                             EBUR128_Mm135,
                             EBUR128_Mp090,
                             EBUR128_Mm090,
                         }),
               kTolLu);
    }
    if (!fail.empty())
    {
        logFail(kName, fail);
        return;
    }
    logPass(kName);
}

// ===========================================================================
// AN-M2: the histograms pool as libebur128's histogram mode does; head and tail.
// ===========================================================================
static auto testAnalyzerHistogramsAndPool() -> void
{
    static const char* const kName = "Analyzer_HistogramsAndPool";
    using enum AnRole;
    constexpr double kPoolTolLu = 0.01;
    std::string fail;
    const TlProgramme first = tlPinkProgramme(kAnRate, 20.0, 61U);
    TlProgramme second = tlOrchestralProgramme(kAnRate, 20.0, 62U);
    AnRun runFirst;
    AnRun runSecond;
    anAnalyse(runFirst, first.channels, {L, R});
    anAnalyse(runSecond, second.channels, {L, R});
    const std::vector<AsLoudnessBin> binsFirst = runFirst.histogram(0U);
    const std::vector<AsLoudnessBin> binsSecond = runSecond.histogram(0U);
    // One member: the histogram-mode reference, and (typically within 0.005 LU) the exact gate.
    {
        const AsLoudnessBin* lists[] = {binsFirst.data()};
        const uint32_t counts[] = {static_cast<uint32_t>(binsFirst.size())};
        const double pooled = asLoudnessPoolHistograms(lists, counts, 1U);
        const double reference = anEbur128(
            first.channels, {EBUR128_LEFT, EBUR128_RIGHT}, EBUR128_MODE_I | EBUR128_MODE_HISTOGRAM);
        logInfo(std::format(
            "  one track: pooled {:+.4f}, libebur128 histogram {:+.4f}, exact gate {:+.4f}",
            pooled,
            reference,
            runFirst.analysis.integratedLufs));
        if (!(std::abs(pooled - reference) <= kPoolTolLu) ||
            !(std::abs(pooled - runFirst.analysis.integratedLufs) <= 0.05))
        {
            fail += std::format("\n  one track: pooled {} vs histogram-mode {} / exact {}",
                                pooled,
                                reference,
                                runFirst.analysis.integratedLufs);
        }
    }
    // Two members: libebur128's ebur128_loudness_global_multiple, histogram mode.
    {
        const AsLoudnessBin* lists[] = {binsFirst.data(), binsSecond.data()};
        const uint32_t counts[] = {
            static_cast<uint32_t>(binsFirst.size()),
            static_cast<uint32_t>(binsSecond.size()),
        };
        const double pooled = asLoudnessPoolHistograms(lists, counts, 2U);
        std::array<ebur128_state*, 2> states{};
        for (size_t member = 0U; member < 2U; ++member)
        {
            const TlProgramme& programme = (member == 0U) ? first : second;
            states[member] = ebur128_init(
                2U, static_cast<unsigned long>(kAnRate), EBUR128_MODE_I | EBUR128_MODE_HISTOGRAM);
            std::vector<double> interleaved(programme.frames() * 2U);
            for (size_t frame = 0U; frame < programme.frames(); ++frame)
            {
                interleaved[2U * frame] = programme.channels[0][frame];
                interleaved[(2U * frame) + 1U] = programme.channels[1][frame];
            }
            (void)ebur128_add_frames_double(states[member], interleaved.data(), programme.frames());
        }
        double reference = std::numeric_limits<double>::quiet_NaN();
        (void)ebur128_loudness_global_multiple(states.data(), 2U, &reference);
        for (ebur128_state*& state : states)
        {
            ebur128_destroy(&state);
        }
        logInfo(std::format(
            "  two tracks: pooled {:+.4f}, libebur128 global_multiple {:+.4f}", pooled, reference));
        if (!(std::abs(pooled - reference) <= kPoolTolLu))
        {
            fail += std::format("\n  two tracks: pooled {} vs libebur128 {}", pooled, reference);
        }
    }
    // Head and tail: a 997 Hz stereo tone of amplitude A reads 20·log10(A) LUFS per block.
    {
        const size_t frames = static_cast<size_t>(6.0 * kAnRate);
        AnPlanes tone(2U, std::vector<float>(frames));
        for (size_t frame = 0U; frame < frames; ++frame)
        {
            const double seconds = static_cast<double>(frame) / kAnRate;
            double amplitude = 0.01; // the last 2 s: −40 LUFS
            if (seconds < 2.0)
            {
                amplitude = 0.1; // −20 LUFS
            }
            else if (seconds < 4.0)
            {
                amplitude = 0.03;
            }
            const auto value =
                static_cast<float>(amplitude * std::sin(2.0 * std::numbers::pi * 997.0 *
                                                        static_cast<double>(frame) / kAnRate));
            tone[0][frame] = value;
            tone[1][frame] = value;
        }
        AnRun run;
        anAnalyse(run, tone, {L, R});
        logInfo(std::format("  head {:+.3f} LUFS (want −20.000), tail {:+.3f} (want −40.000)",
                            run.analysis.headBlockLufs,
                            run.analysis.tailBlockLufs));
        if (!(std::abs(run.analysis.headBlockLufs + 20.0) <= 0.02) ||
            !(std::abs(run.analysis.tailBlockLufs + 40.0) <= 0.02))
        {
            fail += std::format(
                "\n  head {} / tail {}", run.analysis.headBlockLufs, run.analysis.tailBlockLufs);
        }
    }
    if (!fail.empty())
    {
        logFail(kName, fail);
        return;
    }
    logPass(kName);
}

// ===========================================================================
// AN-M3: the fold's variants; stereo; silence; a stream under one block.
// ===========================================================================
static auto testAnalyzerFoldVariantsAndEdges() -> void
{
    static const char* const kName = "Analyzer_FoldVariantsAndEdges";
    using enum AnRole;
    std::string fail;
    const AnPlanes surround = anSurround(8.0);
    // 5.0 (no LFE): one fold, reported at every variant; no LFE statistics.
    {
        const AnPlanes five = {surround[0], surround[1], surround[2], surround[4], surround[5]};
        AnRun run;
        anAnalyse(run, five, {L, R, C, Ls, Rs});
        for (uint8_t variant = 1U; variant < AS_FOLD_LFE_VARIANTS; ++variant)
        {
            if (run.analysis.foldedLufs[variant] != run.analysis.foldedLufs[0] ||
                run.analysis.foldedTruePeakDbtp[variant] != run.analysis.foldedTruePeakDbtp[0] ||
                run.histogram(1U + variant).size() != run.histogram(1U).size())
            {
                fail += std::format("\n  5.0: variant {} differs from variant 0", variant);
            }
        }
        if (run.analysis.folds != 1U || !std::isfinite(run.analysis.foldedLufs[0]) ||
            run.analysis.lfe.activeBlocks != 0U || !std::isnan(run.analysis.lfe.medianR2))
        {
            fail += "\n  5.0: no fold measured, or LFE statistics without an LFE";
        }
    }
    // 5.1 with a loud LFE: the fold rises with the LFE's gain.
    {
        AnRun run;
        anAnalyse(run, surround, {L, R, C, Lfe, Ls, Rs});
        const auto& folded = run.analysis.foldedLufs;
        logInfo(std::format("  5.1 L_F by variant: {:+.2f} {:+.2f} {:+.2f} {:+.2f}",
                            folded[0],
                            folded[1],
                            folded[2],
                            folded[3]));
        const bool rises = folded[0] < folded[1] && folded[1] < folded[2] && folded[2] < folded[3];
        if (!rises)
        {
            fail += "\n  5.1: the fold does not rise with the LFE variant's gain";
        }
    }
    // Silence: no gated block (NaN), the peak floor, silent blocks.
    {
        const AnPlanes silence(2U, std::vector<float>(static_cast<size_t>(2.0 * kAnRate), 0.0F));
        AnRun run;
        anAnalyse(run, silence, {L, R});
        if (!std::isnan(run.analysis.integratedLufs) || run.analysis.truePeakDbtp != kSilenceLufs ||
            run.analysis.headBlockLufs != kSilenceLufs || !run.histogram(0U).empty())
        {
            fail += std::format("\n  silence: L {} TP {} head {}",
                                run.analysis.integratedLufs,
                                run.analysis.truePeakDbtp,
                                run.analysis.headBlockLufs);
        }
    }
    // 300 ms: no whole block.
    {
        AnPlanes sting(2U, std::vector<float>(static_cast<size_t>(0.3 * kAnRate)));
        for (size_t frame = 0U; frame < sting[0].size(); ++frame)
        {
            sting[0][frame] = sting[1][frame] =
                static_cast<float>(0.5 * std::sin(0.05 * static_cast<double>(frame)));
        }
        AnRun run;
        anAnalyse(run, sting, {L, R});
        if (!run.ok || !std::isnan(run.analysis.integratedLufs) ||
            !std::isnan(run.analysis.headBlockLufs) ||
            std::abs(run.analysis.durationSeconds - 0.3) > 1e-9 ||
            !std::isfinite(run.analysis.truePeakDbtp))
        {
            fail += "\n  a 300 ms stream: not measured as having no block";
        }
    }
    if (!fail.empty())
    {
        logFail(kName, fail);
        return;
    }
    logPass(kName);
}

// ===========================================================================
// AN-M4: the C entries' guards.
// ===========================================================================
static auto testAnalyzerAbiGuards() -> void
{
    static const char* const kName = "Analyzer_AbiGuards";
    std::string fail;
    const std::array<uint8_t, 9> roles = {1, 2, 3, 4, 5, 6, 7, 8, 9};
    const std::array<uint8_t, 2> badRole = {1, 15};
    if (asTrackAnalyzerCreate(kAnRate, 2U, nullptr) != nullptr ||
        asTrackAnalyzerCreate(kAnRate, 0U, roles.data()) != nullptr ||
        asTrackAnalyzerCreate(kAnRate, 9U, roles.data()) != nullptr ||
        asTrackAnalyzerCreate(kAnRate, 2U, badRole.data()) != nullptr ||
        asTrackAnalyzerCreate(4000.0, 2U, roles.data()) != nullptr ||
        asTrackAnalyzerCreate(std::numeric_limits<double>::quiet_NaN(), 2U, roles.data()) !=
            nullptr)
    {
        fail +=
            "\n  create accepted a NULL, a count of 0 or 9, role 15, or a rate outside the domain";
    }
    AsTrackAnalyzer* analyzer = asTrackAnalyzerCreate(kAnRate, 2U, roles.data());
    std::vector<float> left(4800, 0.25F);
    std::vector<float> right(4800, 0.25F);
    const std::array<const float*, 2> channels = {left.data(), right.data()};
    right[17] = std::numeric_limits<float>::infinity();
    AsTrackAnalysis analysis{};
    if (asTrackAnalyzerFeed(analyzer, channels.data(), 2U, 4800U) ||
        asTrackAnalyzerFeed(analyzer, channels.data(), 1U, 4800U) ||
        asTrackAnalyzerFeed(nullptr, channels.data(), 2U, 4800U) ||
        asTrackAnalyzerFeed(analyzer, nullptr, 2U, 4800U))
    {
        fail += "\n  feed accepted a non-finite sample, a wrong count or a NULL";
    }
    right[17] = 0.25F;
    if (!asTrackAnalyzerFeed(analyzer, channels.data(), 2U, 4800U) ||
        !asTrackAnalyzerFinish(analyzer, &analysis) ||
        std::abs(analysis.durationSeconds - 0.1) > 1e-12)
    {
        fail += "\n  a valid feed after a rejected one did not count exactly its own frames";
    }
    if (asTrackAnalyzerFinish(analyzer, &analysis) ||
        asTrackAnalyzerFeed(analyzer, channels.data(), 2U, 4800U) ||
        asTrackAnalyzerFinish(nullptr, &analysis) || asTrackAnalyzerFinish(analyzer, nullptr))
    {
        fail += "\n  finish twice, feed after finish, or a NULL was accepted";
    }
    AsLoudnessBin sentinel{0xFFFFFFFFU, 0xFFFFFFFFU, -1.0};
    if (asTrackAnalyzerHistogram(nullptr, 0U, &sentinel, 1U) != 0U ||
        asTrackAnalyzerProfile(nullptr, 0U, nullptr, 0U) != 0U ||
        asTrackAnalyzerProfileInfo(analyzer, 0U, nullptr) ||
        asTrackAnalyzerProfileInfo(analyzer, 1U, nullptr) || sentinel.bin != 0xFFFFFFFFU)
    {
        fail += "\n  a NULL analyzer or info was accepted";
    }
    asTrackAnalyzerDestroy(analyzer);
    asTrackAnalyzerDestroy(nullptr);
    const AsLoudnessBin outOfRange{800U, 1U, 1.0};
    const AsLoudnessBin* lists[] = {&outOfRange};
    const uint32_t one[] = {1U};
    if (!std::isnan(asLoudnessPoolHistograms(nullptr, one, 1U)) ||
        !std::isnan(asLoudnessPoolHistograms(lists, one, 1U)) ||
        !std::isnan(asLoudnessPoolHistograms(lists, one, 0U)))
    {
        fail += "\n  the pool accepted a NULL, a bin past the last, or no member";
    }
    if (!fail.empty())
    {
        logFail(kName, fail);
        return;
    }
    logPass(kName);
}

// ===========================================================================
// AN-F1: the LFE statistics through the C-ABI against the design prototype's numbers.
//
// The fixtures are rebuilt here exactly as proto-side `pinned.py` builds them (splitmix64 of the sample index
// for noise; closed-form sines; an RBJ low-pass in direct form II transposed, as scipy.signal.lfilter runs it),
// rounded to float32, and the expected numbers are the prototype's (proto/p4_lfe_v2.py band500 + stats, with
// np.percentile(r2, 90)) on those float32 channels. 20 s of 5.1 at 48 kHz, L R C LFE Ls Rs:
//   copy         LFE = L + R + C                         → a copy: Omit
//   independent  LFE = its own 45 Hz-band noise, swelling → Include (rule 4, p90 under 0.3)
//   delayed      LFE = L + R + C, 25 ms late              → a copy found at its lag: Omit
//   redirected   mains first-differenced (bass out), LFE = the bass → the fit inverts it: Include (rule 3)
// ===========================================================================
namespace
{
    constexpr size_t kAnLfeFrames = static_cast<size_t>(20.0 * kAnRate);

    [[nodiscard]] auto anSplitmixNoise(uint64_t stream) -> std::vector<double>
    {
        std::vector<double> out(kAnLfeFrames);
        for (size_t n = 0U; n < out.size(); ++n)
        {
            uint64_t z = (static_cast<uint64_t>(n) + (stream << 32U)) * 0x9E3779B97F4A7C15ULL;
            z = (z ^ (z >> 30U)) * 0xBF58476D1CE4E5B9ULL;
            z = (z ^ (z >> 27U)) * 0x94D049BB133111EBULL;
            z ^= z >> 31U;
            out[n] = (static_cast<double>(z >> 11U) * 0x1.0p-53 * 2.0) - 1.0;
        }
        return out;
    }

    [[nodiscard]] auto anLowPass(const std::vector<double>& x, double hz) -> std::vector<double>
    {
        const double w0 = 2.0 * std::numbers::pi * hz / kAnRate;
        const double alpha = std::sin(w0) / (2.0 * 0.7071067811865476);
        const double cw = std::cos(w0);
        const double a0 = 1.0 + alpha;
        const double b0 = (1.0 - cw) / 2.0 / a0;
        const double b1 = (1.0 - cw) / a0;
        const double a1 = -2.0 * cw / a0;
        const double a2 = (1.0 - alpha) / a0;
        std::vector<double> y(x.size());
        double z1 = 0.0;
        double z2 = 0.0;
        for (size_t n = 0U; n < x.size(); ++n)
        {
            y[n] = (b0 * x[n]) + z1;
            z1 = (b1 * x[n]) - (a1 * y[n]) + z2;
            z2 = (b0 * x[n]) - (a2 * y[n]);
        }
        return y;
    }

    struct AnLfeExpected
    {
        const char* name;
        uint32_t active;
        double lagMs, lagPeak, coherent, medianR2, p90, excess20, explainDb;
        AsLfeVerdict verdict;
    };

    // L R C LFE Ls Rs for one pinned kind.
    [[nodiscard]] auto anLfeFixture(const char* kind) -> AnPlanes
    {
        static const std::vector<std::vector<double>> noise = []
        {
            constexpr uint64_t kStreams = 7U;
            std::vector<std::vector<double>> streams;
            streams.reserve(kStreams);
            for (uint64_t stream = 0U; stream < kStreams; ++stream)
            {
                streams.push_back(anSplitmixNoise(stream));
            }
            return streams;
        }();
        std::vector<double> time(kAnLfeFrames);
        std::vector<double> bass = anLowPass(noise[0], 90.0);
        for (size_t n = 0U; n < kAnLfeFrames; ++n)
        {
            time[n] = static_cast<double>(n) / kAnRate;
            bass[n] *= 8.0 * (0.6 + (0.4 * std::sin(2.0 * std::numbers::pi * 0.25 * time[n])));
        }
        const std::string_view name(kind);
        std::vector<double> source = bass;
        if (name == "redirected")
        {
            for (size_t n = kAnLfeFrames; n-- > 1U;)
            {
                source[n] = (bass[n] - bass[n - 1U]) * 8.0;
            }
            source[0] = bass[0] * 8.0;
        }
        const std::array<double, 5> bassShare = {0.6, 0.6, 0.3, 0.0, 0.0};
        std::array<std::vector<double>, 5> mains;
        for (size_t main = 0U; main < mains.size(); ++main)
        {
            mains[main].resize(kAnLfeFrames);
            for (size_t n = 0U; n < kAnLfeFrames; ++n)
            {
                mains[main][n] = (bassShare[main] * source[n]) + (0.03 * noise[main + 1U][n]);
            }
        }
        std::vector<double> lfe(kAnLfeFrames, 0.0);
        if (name == "copy" || name == "delayed")
        {
            const size_t delay = (name == "delayed") ? 1200U : 0U;
            for (size_t n = delay; n < kAnLfeFrames; ++n)
            {
                lfe[n] = (mains[0][n - delay] + mains[1][n - delay]) + mains[2][n - delay];
            }
        }
        else if (name == "independent")
        {
            const std::vector<double> sub = anLowPass(noise[6], 45.0);
            for (size_t n = 0U; n < kAnLfeFrames; ++n)
            {
                lfe[n] =
                    8.0 * (0.5 + (0.5 * std::sin(2.0 * std::numbers::pi * 0.3 * time[n]))) * sub[n];
            }
        }
        else
        {
            for (size_t n = 0U; n < kAnLfeFrames; ++n)
            {
                lfe[n] = 1.5 * bass[n];
            }
        }
        const auto toFloat = [](const std::vector<double>& x)
        {
            std::vector<float> out(x.size());
            std::ranges::transform(
                x, out.begin(), [](double value) { return static_cast<float>(value); });
            return out;
        };
        return {
            toFloat(mains[0]),
            toFloat(mains[1]),
            toFloat(mains[2]),
            toFloat(lfe),
            toFloat(mains[3]),
            toFloat(mains[4]),
        };
    }
} // namespace

static auto testLfeStatsMatchesPrototype() -> void
{
    static const char* const kName = "LfeStats_MatchesPrototype";
    using enum AnRole;
    // proto/p4_lfe_v2.py on the same float32 channels (lane 1-B's pinned.py).
    const auto expected = std::to_array<AnLfeExpected>({
        {
            "copy",
            197U,
            0.0,
            0.99997849,
            1.0,
            1.0,
            1.0,
            0.0,
            0.002811,
            AsLfeVerdictOmitCopy,
        },
        {
            "independent",
            191U,
            66.0,
            0.04519904,
            0.0,
            0.01602594,
            0.09630754,
            0.87434555,
            -23.671105,
            AsLfeVerdictIncludeIndependent,
        },
        {
            "delayed",
            197U,
            24.0,
            0.91779516,
            1.0,
            0.99994925,
            0.99996323,
            0.00507614,
            0.043437,
            AsLfeVerdictOmitCopy,
        },
        {
            "redirected",
            197U,
            -4.0,
            0.66358743,
            0.98477157,
            0.96177428,
            0.97983680,
            1.0,
            30.998842,
            AsLfeVerdictIncludeRedirected,
        },
    });
    constexpr double kR2Tol = 1e-5;
    constexpr double kExplainTolDb = 0.01;
    std::string fail;
    for (const AnLfeExpected& want : expected)
    {
        AnRun run;
        anAnalyse(run, anLfeFixture(want.name), {L, R, C, Lfe, Ls, Rs});
        const AsLfeStats& got = run.analysis.lfe;
        const double oneBlock = 1.0 / static_cast<double>(want.active) + 1e-6;
        const AsLfeVerdict verdict = foldDecideLfe(got);
        logInfo(
            std::format("  {:12} active {} lag {:+.0f} ms peak {:.6f} coh {:.6f} med {:.6f} p90 "
                        "{:.6f} exc20 {:.6f} EG {:+.4f} dB → {}",
                        want.name,
                        got.activeBlocks,
                        got.lagMs,
                        got.lagPeak,
                        got.coherentShare,
                        got.medianR2,
                        got.p90R2,
                        got.excess20Share,
                        got.explainGainDb,
                        static_cast<int>(verdict)));
        const bool same = run.ok && got.activeBlocks == want.active && got.lagMs == want.lagMs &&
                          std::abs(got.lagPeak - want.lagPeak) <= kR2Tol &&
                          std::abs(got.coherentShare - want.coherent) <= oneBlock &&
                          std::abs(got.medianR2 - want.medianR2) <= kR2Tol &&
                          std::abs(got.p90R2 - want.p90) <= kR2Tol &&
                          std::abs(got.excess20Share - want.excess20) <= oneBlock &&
                          std::abs(got.explainGainDb - want.explainDb) <= kExplainTolDb &&
                          verdict == want.verdict;
        if (!same)
        {
            fail += std::format("\n  {}: not the prototype's statistics or decision (see the log)",
                                want.name);
        }
    }
    if (!fail.empty())
    {
        logFail(kName, fail);
        return;
    }
    logPass(kName);
}

// ===========================================================================
// AN-P1: the persisted compact profile predicts ΔL as today's full profile does. (The design's 1/12-octave
// form on non-overlapping blocks missed by up to 0.22 dB here — 0.05–0.10 dB from its grid alone on the 808
// and the loud master; the 1/24-octave grid with a 1200-block cap stays within 0.014 dB at 20, 120 and 240 s.)
// ===========================================================================
namespace
{
    // The analyzer's basis-0 compact profile, round-tripped through its persisted binary16 form.
    [[nodiscard]] auto anCompactProfile(const AnPlanes& planes)
        -> std::shared_ptr<const TrackLoudnessProfile>
    {
        AnRun run;
        anAnalyse(run, planes, {AnRole::L, AnRole::R});
        AsCompactProfileInfo info{};
        if (!run.ok || !asTrackAnalyzerProfileInfo(run.analyzer, 0U, &info))
        {
            return nullptr;
        }
        std::vector<uint16_t> powers(asTrackAnalyzerProfile(run.analyzer, 0U, nullptr, 0U));
        (void)asTrackAnalyzerProfile(
            run.analyzer, 0U, powers.data(), static_cast<uint32_t>(powers.size()));
        return profileFromCompact(info.sampleRate,
                                  info.bandsPerOctave,
                                  info.bandCount,
                                  info.blockCount,
                                  info.blockStrideHops,
                                  powers);
    }
} // namespace

static auto testCompactProfilePredictsLikeFull() -> void
{
    static const char* const kName = "CompactProfile_PredictsLikeFull";
    constexpr double kBoundDb = 0.023; // the design's measured bound (§6, challenger #2)
    auto designer = eqMakeDesigner();
    TlProgramme quiet = tlGatePink();
    tlNormalise(quiet, -45.0);
    const TlProgramme longLoud = tlLoudMasterProgramme(kAnRate, 240.0, 14U);
    const TlProgramme long808 = tl808Programme(kAnRate, 240.0, 12U);
    const auto programmes = std::to_array<std::pair<const char*, const TlProgramme*>>({
        {"pink", &tlGatePink()},
        {"tonal 808", &tlGate808()},
        {"orchestral", &tlGateOrchestral()},
        {"loud master", &tlGateLoudMaster()},
        {"pink at -45 LUFS", &quiet},
        {"loud master, 4 min", &longLoud},
        {"tonal 808, 4 min", &long808},
    });
    double worst = 0.0;
    std::string fail;
    for (const auto& [label, programme] : programmes)
    {
        const auto full = tlProfile(*programme, tlStereoWeights()).whole;
        const auto compact = anCompactProfile(programme->channels);
        const uint32_t stride =
            (programme->frames() > static_cast<size_t>(120.0 * kAnRate)) ? 2U : 1U;
        if (!full || !compact || compact->bandsPerOctave != TrackLoudness::kBandsPerOctave ||
            compact->blockStrideHops != stride)
        {
            fail += std::format("\n  {}: no profile, or not the persisted grid and stride", label);
            continue;
        }
        for (const TlCurve& curve : tlGateCurves())
        {
            GraphicEQDesign design{};
            double fullDb = 0.0;
            double compactDb = 0.0;
            if (!designer->design(curve.points, kAnRate, design) ||
                !predictLoudnessChangeDb(*full, design, 1U, fullDb) ||
                !predictLoudnessChangeDb(*compact, design, 1U, compactDb))
            {
                fail += std::format("\n  {} / {}: no prediction", label, curve.name);
                continue;
            }
            worst = std::max(worst, std::abs(compactDb - fullDb));
            if (std::abs(compactDb - fullDb) > kBoundDb)
            {
                fail += std::format("\n  {} / {}: compact {:+.4f} vs full {:+.4f} dB",
                                    label,
                                    curve.name,
                                    compactDb,
                                    fullDb);
            }
        }
    }
    logInfo(std::format(
        "  worst |compact − full| ΔL over 7 programmes × 8 curves: {:.4f} dB (bound {} dB)",
        worst,
        kBoundDb));
    if (!fail.empty())
    {
        logFail(kName, fail);
        return;
    }
    logPass(kName);
}

// ===========================================================================
// AN-P2: the compact profile's round trip through its persisted form, and its guards.
// ===========================================================================
static auto testCompactProfileRoundTrip() -> void
{
    static const char* const kName = "CompactProfile_RoundTrip";
    std::string fail;
    AnRun run;
    anAnalyse(run, tlGatePink().channels, {AnRole::L, AnRole::R});
    AsCompactProfileInfo info{};
    if (!run.ok || !asTrackAnalyzerProfileInfo(run.analyzer, 0U, &info) ||
        info.bandsPerOctave != 24U || info.blockStrideHops != 1U || info.sampleRate != kAnRate ||
        info.bandCount != TrackLoudness::bandCount(kAnRate) || info.blockCount != 197U)
    {
        logFail(kName,
                std::format("info: {} bpo, stride {}, {} bands, {} blocks",
                            info.bandsPerOctave,
                            info.blockStrideHops,
                            info.bandCount,
                            info.blockCount));
        return;
    }
    const uint32_t required = asTrackAnalyzerProfile(run.analyzer, 0U, nullptr, 0U);
    std::vector<uint16_t> powers(required, 0xABCDU);
    if (required != info.blockCount * info.bandCount ||
        asTrackAnalyzerProfile(run.analyzer, 0U, powers.data(), required - 1U) != required ||
        powers.front() != 0xABCDU)
    {
        fail += "\n  a short capacity wrote, or the count is not blocks × bands";
    }
    (void)asTrackAnalyzerProfile(run.analyzer, 0U, powers.data(), required);
    AsLoudnessProfile* rebuilt = asLoudnessProfileFromCompact(&info, powers.data(), required);
    AsLoudnessProfileInfo rebuiltInfo{};
    if (rebuilt == nullptr || !asLoudnessProfileGetInfo(rebuilt, &rebuiltInfo) ||
        !rebuiltInfo.wholeTrack || rebuiltInfo.blockCount != info.blockCount ||
        rebuiltInfo.bandCount != info.bandCount ||
        std::abs(rebuiltInfo.sourceLoudnessLufs - run.analysis.integratedLufs) > 0.3)
    {
        fail += std::format("\n  the rebuilt profile: {} blocks, {:+.3f} LUFS (the track {:+.3f})",
                            rebuiltInfo.blockCount,
                            rebuiltInfo.sourceLoudnessLufs,
                            run.analysis.integratedLufs);
    }
    // The persisted form is a fixed point: binary16 → profile → binary16 gives the same bits.
    if (rebuilt != nullptr)
    {
        std::vector<uint16_t> again(required);
        if (compactPowers(*rebuilt->profile, again) != required || again != powers)
        {
            fail += "\n  binary16 → profile → binary16 changed the bits";
        }
    }
    asLoudnessProfileDestroy(rebuilt);
    // Guards: a count that is not blocks × bands, another grid's band count, a stride of 0, a grid of 1/7,
    // a NaN or infinite pattern, a NULL.
    AsCompactProfileInfo bad = info;
    std::vector<uint16_t> broken = powers;
    broken[3] = 0x7E00U; // NaN
    std::vector<uint16_t> infinite = powers;
    infinite[5] = 0x7C00U; // +∞
    const bool refusesCount =
        asLoudnessProfileFromCompact(&info, powers.data(), required - 1U) == nullptr;
    bad.bandCount = info.bandCount + 1U;
    const bool refusesBands =
        asLoudnessProfileFromCompact(&bad, powers.data(), required) == nullptr;
    bad = info;
    bad.blockStrideHops = 0U;
    const bool refusesStride =
        asLoudnessProfileFromCompact(&bad, powers.data(), required) == nullptr;
    bad = info;
    bad.bandsPerOctave = 7U;
    const bool refusesGrid = asLoudnessProfileFromCompact(&bad, powers.data(), required) == nullptr;
    // A 1/12-octave profile is read on its own grid: a flat block with all its power in one band, under a
    // +6 dB bell centred on that band's 1/12-octave centre, rises by the curve's played gain there.
    {
        const uint32_t coarseBands =
            TrackLoudness::bandCount(kAnRate, TrackLoudness::kCoarseBandsPerOctave);
        const uint32_t band = coarseBands / 2U;
        std::vector<uint16_t> coarse(coarseBands, 0U);
        coarse[band] = 0x3C00U; // binary16 1.0 → power 2^-10
        const auto profile = profileFromCompact(
            kAnRate, TrackLoudness::kCoarseBandsPerOctave, coarseBands, 1U, 1U, coarse);
        const double centre =
            TrackLoudness::bandCentreHz(band, kAnRate, TrackLoudness::kCoarseBandsPerOctave);
        std::vector<double> response(coarseBands, 0.0);
        response[band] = 6.0;
        double change = 0.0;
        if (!profile || !predictLoudnessChangeDb(*profile, response, 1U, change) ||
            std::abs(change - 6.0) > 1e-9 || coarseBands != 124U ||
            !(std::abs(centre - (20.0 * std::exp2((band - 0.5) / 12.0))) < 1.0))
        {
            fail += std::format("\n  a 1/12-octave profile: {} bands, ΔL {} (want 6), centre {} Hz",
                                coarseBands,
                                change,
                                centre);
        }
    }
    const bool refusesNan = asLoudnessProfileFromCompact(&info, broken.data(), required) == nullptr;
    const bool refusesInf =
        asLoudnessProfileFromCompact(&info, infinite.data(), required) == nullptr;
    const bool refusesNull =
        asLoudnessProfileFromCompact(nullptr, powers.data(), required) == nullptr &&
        asLoudnessProfileFromCompact(&info, nullptr, required) == nullptr;
    if (!(refusesCount && refusesBands && refusesStride && refusesGrid && refusesNan &&
          refusesInf && refusesNull))
    {
        fail += std::format("\n  guards: count {} bands {} stride {} grid {} NaN {} ∞ {} NULL {}",
                            refusesCount,
                            refusesBands,
                            refusesStride,
                            refusesGrid,
                            refusesNan,
                            refusesInf,
                            refusesNull);
    }
    if (!fail.empty())
    {
        logFail(kName, fail);
        return;
    }
    logPass(kName);
}
