#pragma once

// ChannelLayoutDecoder — OFF-RT decoder: CoreAudio AudioChannelLayoutTag → ChannelLayout.
//
// Translates a CoreAudio tag into a fully pre-populated ChannelLayout descriptor so
// the render thread never needs to inspect layout tags or compute weights at run time.
// Call this once on the control thread whenever the format changes; publish the result
// via the same lock-free snapshot mechanism used for TargetState.
//
// Supported tags (per-slot orderings verified against CoreAudioBaseTypes.h):
//
//   kAudioChannelLayoutTag_Stereo          — L R
//   kAudioChannelLayoutTag_MPEG_5_1_A      — L R C LFE Ls Rs        (the TRAP: LFE at slot 3)
//   kAudioChannelLayoutTag_MPEG_5_1_B      — L R Ls Rs C LFE        (the TRAP: LFE at slot 5)
//   kAudioChannelLayoutTag_MPEG_7_1_A      — L R C LFE Ls Rs Lc Rc
//   kAudioChannelLayoutTag_MPEG_7_1_C      — L R C LFE Ls Rs Rls Rrs  (AudioUnit_7_1 / ITU-3_4_1)
//   unknown / custom                       — neutral fallback: all weights 1.0, no LFE, azimuth 0
//
// Per-slot values:
//   lufsWeight : L/R/C = 1.0  |  LFE = 0.0  |  Ls/Rs/Lss/Rss = kBs1770SurroundWeight
//                (ITU-R BS.1770-5, Annex 1, Table 1)
//   brirAzimuthDeg  : BS.775-4 nominal positions; sign convention = +left / CCW from centre
//   brirElevationDeg: 0.0 for all ear-level layouts
//   isLfe           : 1 at the LFE slot, 0 elsewhere
//
// Azimuth sign convention (stated explicitly, as required by consumers):
//   + = left of centre (counter-clockwise when viewed from above).
//   Examples: L = +30°, R = −30°, Ls = +110°, Rs = −110°.
//   This matches the common binaural/HRTF convention where left = positive azimuth.
//
// References:
//   ITU-R BS.1770-5 (2023), Annex 1, Table 1  — channel weights
//   ITU-R BS.775-4  (2022), §3 and Tables      — nominal speaker azimuths
//   Apple CoreAudioBaseTypes.h (SDK)           — tag → channel-order comments
//
// Implementation file: ChannelLayoutDecoder.mm (pulls in CoreAudioTypes; keep this
// header free of CoreAudio includes so DSP-only translation units stay clean).

#include "../include/ChannelLayout.h"
#include <CoreAudioTypes/CoreAudioBaseTypes.h>

namespace AdaptiveSound
{

    // Decode `tag` into a fully-populated ChannelLayout.
    //
    // Noexcept, allocation-free (plain struct return), control-thread-only.
    // Returns the neutral fallback (numChannels derived from tag, all weights 1.0,
    // no LFE, azimuth 0) for any unrecognised or custom tag.
    [[nodiscard]] auto decodeChannelLayout(AudioChannelLayoutTag tag) noexcept -> ChannelLayout;

} // namespace AdaptiveSound
