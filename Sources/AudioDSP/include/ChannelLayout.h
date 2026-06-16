#ifndef ADAPTIVE_SOUND_CHANNEL_LAYOUT_H
#define ADAPTIVE_SOUND_CHANNEL_LAYOUT_H

#include "AudioConstants.h"
#include <array>
#include <cstdint>

namespace AdaptiveSound
{

    // Decoded channel-role descriptor, computed OFF-RT from the CoreAudio AudioChannelLayoutTag.
    // Carries the per-slot BS.1770-5 loudness weights (L/R/C = 1.0, surround ≈ 1.41 / +1.5 dB,
    // LFE = 0), the ITU-R BS.775 speaker azimuth/elevation for binaural rendering, and an LFE
    // flag. Published via its OWN snapshot (NOT folded into TargetState) so the render thread
    // reads precomputed arrays and never inspects a layout tag — defeating the AAC-vs-broadcast
    // ordering trap by construction. Trivially copyable. Populated/wired in Sprint 5b S2.
    struct ChannelLayout
    {
        uint32_t numChannels = 2U;
        std::array<float, kMaxChannels> lufsWeight{};       // BS.1770-5 per-channel weight
        std::array<float, kMaxChannels> brirAzimuthDeg{};   // ITU-R BS.775 speaker azimuth
        std::array<float, kMaxChannels> brirElevationDeg{}; // ITU-R BS.775 speaker elevation
        std::array<uint8_t, kMaxChannels> isLfe{};          // 1 = LFE slot (excluded from binaural)
    };

} // namespace AdaptiveSound

#endif // ADAPTIVE_SOUND_CHANNEL_LAYOUT_H
