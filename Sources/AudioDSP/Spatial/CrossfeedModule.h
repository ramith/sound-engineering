#pragma once

#include "../include/AudioConstants.h"
#include "../include/MultichannelView.h"
#include "../include/ParameterRamp.h"
#include "../include/TargetState.h"
#include <array>
#include <AudioToolbox/AudioToolbox.h>
#include <cmath>
#include <cstdint>

namespace AdaptiveSound
{

    // The inter-aural delay constant (QW1 §2): delayFrames = round(0.0003178·fs) seconds.
    constexpr double kCrossfeedItdSeconds = 0.0003178;

    // Round a non-negative double to the nearest integer at compile time. Floor(x + 0.5) is the
    // round-half-up rule; written without `static_cast<int>(x + 0.5)` so it is not flagged by
    // bugprone-incorrect-roundings (the std::lround the checker suggests is not constexpr in this
    // toolchain). For the small, exactly-representable ITD products here the floor form is exact.
    [[nodiscard]] constexpr auto roundToNearestInt(double value) -> int
    {
        constexpr double kRoundHalf = 0.5; // round-half-up threshold (named to satisfy lint)
        const auto truncated = static_cast<int>(value);
        return ((value - static_cast<double>(truncated)) >= kRoundHalf) ? (truncated + 1)
                                                                        : truncated;
    }

    // Fixed worst-case ITD delay-line capacity. The largest supported rate (192 kHz) gives
    // round(0.0003178·192000) = round(61.0) = 61, so a 64-element line covers every rate with
    // headroom. A power-of-two cap also makes the wrap mask cheap. (QW1 §2; refactoring F7.)
    constexpr int kMaxCrossfeedDelayFrames = 64;

    // Compile-time guard (refactoring F7): the 192 kHz worst case MUST fit the fixed line.
    // round(0.0003178 * 192000) = 61 < 64. Computed as a constexpr so a future rate bump that
    // would overflow the array trips at build time rather than corrupting the RT path.
    constexpr int kCrossfeedDelay192k = roundToNearestInt(kCrossfeedItdSeconds * 192000.0);
    static_assert(kCrossfeedDelay192k < kMaxCrossfeedDelayFrames,
                  "192 kHz ITD delay must fit the fixed crossfeed delay line");

    // ---------------------------------------------------------------------------
    // CrossfeedModule (QW1 §2/§3) — symmetrical stereo headphone crossfeed.
    //
    //   Lout = gDirect·L + gCross·H(z)·z^-D·R
    //   Rout = gDirect·R + gCross·H(z)·z^-D·L
    //
    // where H(z) is a one-pole low-pass on the CROSS path only (exact-RC form, p = exp(-2π·fc/fs))
    // and z^-D is the ITD delay (D = round(0.0003178·fs)). Direct path is unfiltered/undelayed.
    // Coefficients (gDirect/gCross/lpfB0/lpfPole/delayFrames) are derived OFF-RT in the Realizer
    // and arrive in CrossfeedParams; process() is pure scalar per-sample DSP, no allocation.
    //
    // Shape mirrors EQModule: initialize(sr,maxFrames) + process(const CrossfeedParams&,
    // MultichannelView&); all copy/move deleted. RT-safe (FTZ is set on the render thread).
    //
    // The #1 crossfeed implementation bug is read-one/write-one (writing the new L before reading
    // the old L to feed R). This module READS BOTH L,R then WRITES BOTH — see process().
    // ---------------------------------------------------------------------------
    class CrossfeedModule
    {
      public:
        CrossfeedModule() = default;
        ~CrossfeedModule() = default;

        CrossfeedModule(const CrossfeedModule&) = delete;
        CrossfeedModule& operator=(const CrossfeedModule&) = delete;
        CrossfeedModule(CrossfeedModule&&) = delete;
        CrossfeedModule& operator=(CrossfeedModule&&) = delete;

        // Off-RT: reset the per-cross-path state (delay lines, LPF memory) and snap the
        // enable/level ramp to the initial (off) value so the first buffer does not fade in.
        void initialize(uint32_t sampleRate, uint32_t maxFrames) noexcept;

        // RT: apply crossfeed in place on the stereo MultichannelView. Top-of-process early
        // return on `enabled == 0 || channels() != 2` → BIT-EXACT pass-through. Stereo-only.
        void process(const CrossfeedParams& params, const MultichannelView& block) noexcept;

      private:
        // One cross path (R→L or L→R): a fixed circular ITD delay line plus the one-pole LPF
        // memory. Trivial state; value-initialised to silence in initialize(). The delay line is
        // sized to the 192 kHz worst case so process() never allocates or resizes.
        struct CrossPath
        {
            std::array<float, kMaxCrossfeedDelayFrames> delayLine{};
            uint32_t writeIndex = 0U; // next write position into delayLine (circular)
            float lpfState = 0.0F;    // one-pole LPF memory y[n-1]
        };

        // Index 0 = the R→L cross path (feeds the left output); index 1 = the L→R cross path
        // (feeds the right output). Exactly two — crossfeed is stereo-only.
        std::array<CrossPath, 2U> crossPaths_{};

        // Enable/level smoother (32 ms one-pole, QW1 §3) for click-free enable/disable and level
        // changes. target ∈ {0,1}: 0 = bypass-blend, 1 = full crossfeed. The processed (wet) and
        // dry signals are blended by mix_ so toggling never clicks. Snapped to 0 (off) in
        // initialize().
        ParameterRamp mixRamp_{};

        uint32_t sampleRate_ = kDefaultSampleRate;
        uint32_t maxFrames_ = kDefaultMaxFrames;
    };

} // namespace AdaptiveSound
