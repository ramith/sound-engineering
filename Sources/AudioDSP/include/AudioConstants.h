#pragma once

#include <cstddef>
#include <cstdint>

namespace AdaptiveSound
{

    constexpr uint32_t kDefaultSampleRate = 48000U;
    constexpr uint32_t kDefaultMaxFrames = 512U;
    // Maximum channels the DSP pipeline allocates per-channel state for (mono..7.1).
    // The multichannel epic pre-allocates all per-channel storage at this ceiling so the
    // render thread never reallocates; the active channel count (≤ this) is read per render.
    constexpr uint32_t kMaxChannels = 8U;
    constexpr int kCoeffsPerBiquad = 5;    // vDSP packs [b0,b1,b2,a1,a2]
    constexpr size_t kCacheLineBytes = 64; // ARM64 / Apple Silicon cache line
    constexpr float kTruePeakCeilingLinear =
        0.891F; // approx -1 dBTP (10^(-1/20)=0.8913; literal is approximate)
    // True-peak limiter look-ahead is a fixed TIME, not a fixed frame count: the gain
    // envelope must reach target within a constant number of attack time-constants
    // regardless of sample rate, or the −1 dBTP ceiling is exceeded at hi-res rates
    // (Stage-1 review AC-2). LimiterModule derives the actual frame count as
    // round(kLimiterLookaheadSeconds · fs) in initialize(). kLimiterLookaheadFrames is
    // the value AT THE DEFAULT 48 kHz rate — the reference the golden-master/limiter
    // tests prime with, and the pre-initialize() default. kMaxLimiterLookaheadFrames
    // bounds the fixed-capacity peak deque at the highest supported rate.
    constexpr float kLimiterLookaheadSeconds = 0.003F; // 3 ms true-peak look-ahead
    constexpr uint32_t kMaxSupportedSampleRate = 192000U;
    constexpr uint32_t kLimiterLookaheadFrames = 144U;     // = round(3 ms · 48 kHz)
    constexpr uint32_t kMaxLimiterLookaheadFrames = 576U;  // = round(3 ms · 192 kHz)
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
