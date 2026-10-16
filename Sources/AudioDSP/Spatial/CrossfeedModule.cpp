#include "CrossfeedModule.h"

namespace AdaptiveSound
{

    // The enable glide's time constant. Mirrors the EQ master-gain / loudness makeup / intensity
    // smoothers (32 ms one-pole, QW1 §3) so turning crossfeed on or off is click-free; ~98 % in
    // 5τ ≈ 160 ms.
    static constexpr float kCrossfeedRampTauSeconds = 0.032F;

    // The glide counts as ended this close to its endpoint, and is snapped there: at 0 the module
    // is a bit-exact pass-through, at 1 it is exactly bs2b. The glide toward 1 needs the wider
    // margin: a float one-pole stalls ~0.5e-4 short of 1 (council D60), as the kernel's Intensity
    // ramp does (kIntensitySettledEpsilon); toward 0 it does not stall.
    static constexpr float kMixOffEpsilon = 1e-5F;
    static constexpr float kMixOnEpsilon = 1e-4F;

    // Stereo channel indices and the count crossfeed operates on. Crossfeed is stereo-ONLY; any
    // other channel count early-returns (bit-exact pass-through).
    static constexpr uint32_t kStereoChannels = 2U;
    static constexpr uint32_t kLeftChannel = 0U;
    static constexpr uint32_t kRightChannel = 1U;

    void CrossfeedModule::initialize(uint32_t sampleRate, uint32_t maxFrames) noexcept
    {
        sampleRate_ = sampleRate;
        maxFrames_ = maxFrames;
        state_.fill(ChannelState{});

        // Snapped to off: a fresh module is a bit-exact pass-through, and the first enable glides
        // in click-free rather than jumping from an undefined state.
        mixRamp_.initialize(kCrossfeedRampTauSeconds, static_cast<float>(sampleRate));
        mixRamp_.target = 0.0F;
        mixRamp_.snap();
    }

    bool CrossfeedModule::isBypassed(const CrossfeedParams& params,
                                     uint32_t channels) const noexcept
    {
        return channels != kStereoChannels ||
               (params.enabled == 0U && mixRamp_.current <= kMixOffEpsilon);
    }

    void CrossfeedModule::process(const CrossfeedParams& params,
                                  const MultichannelView& block) noexcept
    {
        // Stereo only: any other width is a bit-exact pass-through, whatever the glide's state; it
        // snaps off so a later stereo, enabled block glides in from zero.
        if (block.channels() != kStereoChannels)
        {
            mixRamp_.current = 0.0F;
            mixRamp_.target = 0.0F;
            return;
        }

        // Off, and the glide out has ended: a bit-exact pass-through (the golden master's
        // canary). Off while the glide is still above zero keeps processing toward 0 — an
        // early return there would cut the crossfeed off and CLICK (CF-7). The filter memory is
        // cleared here, so a later enable starts from silence, not from a stale tail.
        if (isBypassed(params, kStereoChannels))
        {
            mixRamp_.current = 0.0F;
            mixRamp_.target = 0.0F;
            state_.fill(ChannelState{});
            return;
        }

        float* left = block.channel(kLeftChannel);
        float* right = block.channel(kRightChannel);
        if (left == nullptr || right == nullptr)
        {
            return; // defensive: a malformed stereo view → leave the buffers untouched.
        }

        mixRamp_.target = (params.enabled != 0U) ? 1.0F : 0.0F;
        if (mixRamp_.target == 1.0F && (1.0F - mixRamp_.current) <= kMixOnEpsilon)
        {
            mixRamp_.current = 1.0F; // on: exactly bs2b from here
        }

        // The coefficients are constant across the block (they change only off-RT, between blocks).
        const float directB0 = params.directB0;
        const float directB1 = params.directB1;
        const float directPole = params.directPole;
        const float crossB0 = params.crossB0;
        const float crossPole = params.crossPole;
        ChannelState& stateL = state_[kLeftChannel];
        ChannelState& stateR = state_[kRightChannel];

        const uint32_t frames = block.frames();
        for (uint32_t frame = 0U; frame < frames; ++frame)
        {
            // READ BOTH channels FIRST (the #1 crossfeed bug is reading the just-written value).
            const float dryL = left[frame];
            const float dryR = right[frame];

            // Each channel's direct path, the high-boost shelf (bs2b hi_filter):
            //   y[n] = b0·x[n] + b1·x[n−1] + pole·y[n−1]
            stateL.directOut =
                (directB0 * dryL) + (directB1 * stateL.directIn) + (directPole * stateL.directOut);
            stateL.directIn = dryL;
            stateR.directOut =
                (directB0 * dryR) + (directB1 * stateR.directIn) + (directPole * stateR.directOut);
            stateR.directIn = dryR;

            // Each channel's cross path, the low-pass (bs2b lo_filter):
            //   y[n] = b0·x[n] + pole·y[n−1]
            stateL.crossOut = (crossB0 * dryL) + (crossPole * stateL.crossOut);
            stateR.crossOut = (crossB0 * dryR) + (crossPole * stateR.crossOut);

            // Each ear: its own channel's direct path plus the other channel's cross path.
            const float wetL = stateL.directOut + stateR.crossOut;
            const float wetR = stateR.directOut + stateL.crossOut;

            // The enable glide, per sample: 0 = the input, 1 = bs2b (exactly, once snapped).
            const float mix = mixRamp_.tick();
            const float dryGain = 1.0F - mix;

            // WRITE BOTH channels LAST, after both new values are computed.
            left[frame] = (dryGain * dryL) + (mix * wetL);
            right[frame] = (dryGain * dryR) + (mix * wetR);
        }
    }

} // namespace AdaptiveSound
