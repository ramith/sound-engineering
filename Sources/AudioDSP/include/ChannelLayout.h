#pragma once

#include "AudioConstants.h"
#include "TrackPlanBridge.h" // AsChannelRole: the fixed role numbers (pure C)
#include <array>
#include <cstdint>

namespace AdaptiveSound
{

    // A channel's role, from its label (R1.1-B, level-and-fold S1b). The C enum AsChannelRole
    // (TrackPlanBridge.h) is the persisted form, and every enumerator here IS its C value, so the two
    // numberings cannot drift; the null test (LevelPlanTests.inc) pins the numbers themselves.
    enum class ChannelRole : uint8_t
    {
        Unknown = AsChannelRoleUnknown,
        L = AsChannelRoleL,
        R = AsChannelRoleR,
        C = AsChannelRoleC,
        Lfe = AsChannelRoleLfe,
        Ls = AsChannelRoleLs,
        Rs = AsChannelRoleRs,
        Lb = AsChannelRoleLb,
        Rb = AsChannelRoleRb,
        Cs = AsChannelRoleCs,
        Lc = AsChannelRoleLc,
        Rc = AsChannelRoleRc,
        Lw = AsChannelRoleLw,
        Rw = AsChannelRoleRw,
        Mono = AsChannelRoleMono,
    };
    static_assert(static_cast<uint32_t>(AS_MAX_CHANNELS) == kMaxChannels,
                  "the C seam's channel slots are the pipeline's");

    // Decoded channel-role descriptor, computed OFF-RT from the CoreAudio AudioChannelLayoutTag.
    // Carries the per-slot BS.1770-5 loudness weights (L/R/C = 1.0, surround ≈ 1.41 / +1.5 dB,
    // LFE = 0), the ITU-R BS.775 speaker azimuth/elevation for binaural rendering, an LFE flag and
    // each slot's role (the fold's matrix is built from the roles, S1b). Published via its OWN
    // snapshot (NOT folded into TargetState) so the render thread reads precomputed arrays and never
    // inspects a layout tag — defeating the AAC-vs-broadcast ordering trap by construction.
    // Trivially copyable. Populated/wired in Sprint 5b S2.
    struct ChannelLayout
    {
        uint32_t numChannels = 2U;
        std::array<float, kMaxChannels> lufsWeight{};       // BS.1770-5 per-channel weight
        std::array<float, kMaxChannels> brirAzimuthDeg{};   // ITU-R BS.775 speaker azimuth
        std::array<float, kMaxChannels> brirElevationDeg{}; // ITU-R BS.775 speaker elevation
        std::array<uint8_t, kMaxChannels> isLfe{};          // 1 = LFE slot (excluded from binaural)
        std::array<ChannelRole, kMaxChannels> role{}; // each slot's role; Unknown when not known
    };

} // namespace AdaptiveSound
