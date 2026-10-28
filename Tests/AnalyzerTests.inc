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

#include "../Sources/AudioDSP/Loudness/ChannelRoles.h"

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
