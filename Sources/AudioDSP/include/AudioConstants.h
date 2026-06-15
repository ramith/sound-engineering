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
    constexpr float kLimiterLookaheadFrames = 48.F;        // default look-ahead window in frames
    constexpr float kDefaultLufsTarget = -16.F;            // integrated loudness target (dB LUFS)
    constexpr float kClarityDefaultThresholdLinear = 0.1F; // compressor threshold (linear)
    constexpr float kClarityDefaultKneeWidthLinear =
        0.1F; // soft-knee half-width (linear) -- DISTINCT from threshold
    constexpr float kClarityDefaultRatioRecip = 0.5F; // 1/ratio for 2:1 compression

} // namespace AdaptiveSound

#endif // ADAPTIVE_SOUND_AUDIO_CONSTANTS_H
