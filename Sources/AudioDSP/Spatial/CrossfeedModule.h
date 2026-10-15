#pragma once

#include "../include/AudioConstants.h"
#include "../include/MultichannelView.h"
#include "../include/ParameterRamp.h"
#include "../include/TargetState.h"
#include <array>
#include <AudioToolbox/AudioToolbox.h>
#include <cstdint>

namespace AdaptiveSound
{

    // ---------------------------------------------------------------------------
    // CrossfeedModule — headphone crossfeed, bs2b (council C-42, R1.1-A).
    //
    // Bauer stereophonic-to-binaural, as libbs2b implements it (src/bs2b.c, cross_feed_d(); MIT,
    // © 2005 Boris Mikhaylov — re-implemented here from the published algorithm, not linked:
    // OQ-17). Each ear hears its own channel through a first-order HIGH-BOOST shelf (the direct
    // path) plus the other channel through a first-order LOW-PASS (the cross path):
    //
    //   Lout = Hhi(z)·L + Hlo(z)·R        Hhi(z) = (directB0 + directB1·z⁻¹) / (1 − directPole·z⁻¹)
    //   Rout = Hhi(z)·R + Hlo(z)·L        Hlo(z) =  crossB0                  / (1 − crossPole·z⁻¹)
    //
    // The interaural delay is the low-pass's own group delay against the shelf's (≈ 0.25 ms at
    // low frequencies, a ±30° loudspeaker pair): there is no delay line. The shelf is what keeps a
    // centred (L = R) voice smooth — a shelf of 0 dB at DC to −1.1 … −1.8 dB at high frequencies,
    // no notch. The crossfeed this replaces stacked an explicit 0.318 ms delay on the low-pass's
    // own and left the direct path flat, so a centred voice lost 4.2–6.3 dB near 1 kHz (council
    // P2-3). The coefficients — bs2b's init(), with its output gain folded into the numerators —
    // are derived OFF-RT in the Realizer and arrive in CrossfeedParams; process() is scalar
    // per-sample DSP, no allocation.
    //
    // It is an output stage of the kernel of its own, ahead of the limiter, at its preset's full
    // strength whatever Intensity is (founder decision 2026-10-14). Enabling or disabling glides
    // over a 32 ms one-pole between the input and the crossfed signal; once the glide out has
    // ended it is a bit-exact pass-through again (isBypassed()). Stereo only: any other width
    // passes through untouched.
    //
    // The #1 crossfeed implementation bug is read-one/write-one (writing the new L before reading
    // the old L to feed R). This module READS BOTH L, R then WRITES BOTH — see process().
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

        // Off-RT: clear the filter memory and snap the enable glide to off, so the first buffer
        // neither fades in from an undefined state nor plays a stale tail.
        void initialize(uint32_t sampleRate, uint32_t maxFrames) noexcept;

        // RT: crossfeed in place on a stereo view. A non-stereo view, or crossfeed off with its
        // glide out ended, is a BIT-EXACT pass-through (an early return).
        void process(const CrossfeedParams& params, const MultichannelView& block) noexcept;

        // Whether process() would leave a block of `channels` untouched: crossfeed off and its
        // glide out ended, or not stereo. The kernel's bit-perfect path (P0) asks this.
        [[nodiscard]] bool isBypassed(const CrossfeedParams& params,
                                      uint32_t channels) const noexcept;

      private:
        // One input channel's filter memory: its direct-path shelf (last input, last output) and
        // its cross-path low-pass (last output). Index 0 = L, 1 = R.
        struct ChannelState
        {
            float directIn = 0.0F;
            float directOut = 0.0F;
            float crossOut = 0.0F;
        };
        std::array<ChannelState, 2U> state_{};

        // The enable glide (32 ms one-pole, QW1 §3): 0 = the input, 1 = the crossfed signal.
        // Snapped to 0 in initialize(); snapped to its endpoint once settled, so off is bit-exact
        // and on is exactly bs2b.
        ParameterRamp mixRamp_{};

        uint32_t sampleRate_ = kDefaultSampleRate;
        uint32_t maxFrames_ = kDefaultMaxFrames;
    };

} // namespace AdaptiveSound
