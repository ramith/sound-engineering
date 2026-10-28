#pragma once

// ChannelRoles — the one channel-role resolver, and the BS.1770-5 weights of a set of roles (R1.1-B; the
// level-and-fold design, docs/design/level-and-fold/README.md §S1b, M3).
//
// ROLES COME FROM LABELS, NEVER FROM POSITION. A file's layout names each channel: by a layout tag (Apple's
// table expands it — AudioToolbox's kAudioFormatProperty_ChannelLayoutForTag), by a channel bitmap
// (kAudioFormatProperty_ChannelLayoutForBitmap), or by one AudioChannelDescription per channel (tag 0, as the
// corpus's 7-channel FLAC arrives). Each label maps to one AsChannelRole (roleForLabel). Only a layout that
// names no speaker at all — none reported, DiscreteInOrder, Unknown, every label Discrete_n / Unused — or one
// that describes a different channel count from the stream's, falls back to the channel COUNT, in WAV order
// (RFC 9639 §8.6.2 table, as the ITU and EBU loudness signals and legacy WAVs arrive):
//   1 Mono · 2 L R · 3 L R C · 4 L R Lb Rb · 5 L R C Lb Rb · 6 L R C Lfe Lb Rb · 7 L R C Lfe Cs Ls Rs ·
//   8 L R C Lfe Lb Rb Ls Rs
// A lone back pair (Lb/Rb with no Ls/Rs) is THE surround pair of a 4.0 / 5.x layout — the fold plays it at
// 0.7071 (FoldMatrix.h) and BS.1770 weights it as a surround (bs1770Weights below).
//
// One resolver: the Swift ChannelRoles (TrackLoudnessKit) calls asResolveChannelRoles once per file, and its
// result goes by value to the analysis, the effects unit and the planner. A change to the label table or the
// count fallbacks is an AS_TRACK_ANALYSIS_VERSION bump (roles are persisted with every analysis).
//
// THREADS. Pure; any thread, off the real-time path (Apple's tag and bitmap tables are read through
// AudioToolbox's AudioFormat services).

#include "../include/AudioConstants.h"
#include "../include/ChannelLayout.h"
#include <array>
#include <CoreAudioTypes/CoreAudioBaseTypes.h>
#include <cstdint>
#include <span>

namespace AdaptiveSound
{
    // The role a channel label names; Unknown for a label the fold has no row for (heights, discrete,
    // ambisonic, mid/side, narration, …).
    [[nodiscard]] ChannelRole roleForLabel(AudioChannelLabel label) noexcept;

    // The count fallback (RFC 9639, WAV order) for `channels` channels, 1 … kMaxChannels, into roles[0 …).
    // False — writing nothing — for a count out of range or a span too short.
    [[nodiscard]] bool countFallbackRoles(uint32_t channels, std::span<ChannelRole> roles) noexcept;

    // The roles of a stream of `channels` channels whose layout is `layout` (nullptr: none reported), from
    // its labels; the count fallback when the layout names no speaker or describes another channel count.
    // False — writing nothing — for a count out of 1 … kMaxChannels or a span shorter than `channels`.
    [[nodiscard]] bool resolveChannelRoles(const AudioChannelLayout* layout,
                                           uint32_t channels,
                                           std::span<ChannelRole> roles) noexcept;

    // ITU-R BS.1770-5's channel weights for a set of roles (Annex 1 Table 3; Annex 3 Tables 4 and 5 by
    // position): L, R, C, Mono, Lc, Rc, Cs and Unknown 1.0; the LFE 0 (excluded); the side surrounds Ls/Rs
    // (M±110 in 5.x, M±090 in 7.x) and the wides Lw/Rw (M±060) 1.41 (+1.5 dB); a back pair Lb/Rb 1.41 when it
    // is the layout's only surround pair (M±110 of 4.0 / 5.x) and 1.0 beside a side pair (M±135 of 7.x).
    // Slots beyond roles.size() are 0.
    [[nodiscard]] std::array<double, kMaxChannels>
    bs1770Weights(std::span<const ChannelRole> roles) noexcept;
} // namespace AdaptiveSound
