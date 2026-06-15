#ifndef ADAPTIVE_SOUND_AUDIO_CONSTANTS_H
#define ADAPTIVE_SOUND_AUDIO_CONSTANTS_H

#include <cstddef>
#include <cstdint>

namespace AdaptiveSound
{

    constexpr uint32_t kDefaultSampleRate = 48000U;
    constexpr uint32_t kDefaultMaxFrames = 512U;
    constexpr int kCoeffsPerBiquad = 5;    // vDSP packs [b0,b1,b2,a1,a2]
    constexpr size_t kCacheLineBytes = 64; // ARM64 / Apple Silicon cache line
    constexpr float kTruePeakCeilingLinear =
        0.891F; // approx -1 dBTP (10^(-1/20)=0.8913; literal is approximate)
    constexpr uint32_t kLimiterLookaheadFrames = 48U;      // default look-ahead window in frames
    constexpr float kDefaultLufsTarget = -16.F;            // integrated loudness target (dB LUFS)
    constexpr float kClarityDefaultThresholdLinear = 0.1F; // compressor threshold (linear)
    constexpr float kClarityDefaultKneeWidthLinear =
        0.1F; // soft-knee half-width (linear) -- DISTINCT from threshold
    constexpr float kClarityDefaultRatioRecip = 0.5F; // 1/ratio for 2:1 compression

    // EQ gain / audible-band limits (product/DSP-system level, shared)
    constexpr float kEQMaxGainDb = 12.0F;         // per-band gain clamp magnitude
    constexpr float kAudibleBandMinHz = 20.0F;    // lower edge of the audible band (Hz)
    constexpr float kAudibleBandMaxHz = 20000.0F; // upper edge of the audible band (Hz)

} // namespace AdaptiveSound

#endif // ADAPTIVE_SOUND_AUDIO_CONSTANTS_H
