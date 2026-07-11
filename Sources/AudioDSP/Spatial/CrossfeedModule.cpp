#include "CrossfeedModule.h"

#include <algorithm> // std::clamp

namespace AdaptiveSound
{

    // Enable/level ramp time constant. Mirrors the EQ master-gain / loudness makeup / intensity
    // smoothers (32 ms one-pole, QW1 §3) so a crossfeed enable/disable or level change is click-free;
    // settles to ~98% in 5τ ≈ 160 ms.
    static constexpr float kCrossfeedRampTauSeconds = 0.032F;

    // Stereo channel indices and the count crossfeed operates on. Crossfeed is stereo-ONLY; any other
    // channel count early-returns (bit-exact pass-through).
    static constexpr uint32_t kStereoChannels = 2U;
    static constexpr uint32_t kLeftChannel = 0U;
    static constexpr uint32_t kRightChannel = 1U;

    void CrossfeedModule::initialize(uint32_t sampleRate, uint32_t maxFrames) noexcept
    {
        sampleRate_ = sampleRate;
        maxFrames_ = maxFrames;

        // Clear both cross-path delay lines + LPF memory so the first buffer starts from silence
        // (off-RT; the RT path never touches this state's size).
        crossPaths_.fill(CrossPath{});

        // Configure the enable/level ramp and SNAP it to the initial (off) value, so a fresh module
        // starts fully dry (bit-exact pass-through) and the first enable ramps in click-free rather
        // than jumping from an undefined state. target=0 == off; process() drives target=enabled.
        mixRamp_.initialize(kCrossfeedRampTauSeconds, static_cast<float>(sampleRate));
        mixRamp_.target = 0.0F;
        mixRamp_.snap();
    }

    void CrossfeedModule::process(const CrossfeedParams& params,
                                  const MultichannelView& block) noexcept
    {
        // Hard guard: crossfeed is STEREO-ONLY. A non-stereo view is ALWAYS a bit-exact pass-through
        // (early return, no blend, regardless of enable/ramp state). Snap the ramp off so a later
        // stereo+enabled call ramps cleanly from zero.
        if (block.channels() != kStereoChannels)
        {
            mixRamp_.current = 0.0F;
            mixRamp_.target = 0.0F;
            return;
        }

        // Settled-off bit-exact branch (mirrors the DSPKernel intensity HARD branch, QW1 §3): when
        // crossfeed is disabled AND the mix ramp has already glided to zero, early-return → BIT-EXACT
        // pass-through (the canary the golden master pins). We do NOT early-return on enabled==0 while
        // the ramp is still above zero — that would snap-cut the crossfeed and CLICK (CF-7); instead
        // we keep processing with target=0 so it ramps down click-free, then this branch takes over.
        constexpr float kMixSettledEpsilon = 1e-5F;
        if (params.enabled == 0U && mixRamp_.current <= kMixSettledEpsilon)
        {
            mixRamp_.current = 0.0F; // snap exactly to 0 so the branch stays bit-exact and settled
            mixRamp_.target = 0.0F;
            return;
        }

        float* left = block.channel(kLeftChannel);
        float* right = block.channel(kRightChannel);
        if (left == nullptr || right == nullptr)
        {
            return; // defensive: a malformed stereo view → leave the buffers untouched.
        }

        // Drive the ramp toward the target: 1.0 when enabled (full crossfeed), 0.0 when disabling
        // (glide down click-free, then the settled-off branch above early-returns). The per-sample mix
        // blends the crossfed (wet) result against the dry input so enable/disable + level changes are
        // click-free.
        mixRamp_.target = (params.enabled != 0U) ? 1.0F : 0.0F;

        // Hoist the coefficients (constant across the buffer; they only change off-RT between buffers).
        const float gDirect = params.gDirect;
        const float gCross = params.gCross;
        const float lpfB0 = params.lpfB0;     // (1 - p)
        const float lpfPole = params.lpfPole; // p
        // Clamp the delay to the fixed line capacity so a bad off-RT value can never index OOB.
        const int delayFrames = std::clamp(params.delayFrames, 0, kMaxCrossfeedDelayFrames - 1);
        const auto delay = static_cast<uint32_t>(delayFrames);

        CrossPath& pathRtoL = crossPaths_[0]; // R fed into the LEFT output
        CrossPath& pathLtoR = crossPaths_[1]; // L fed into the RIGHT output

        const uint32_t frames = block.frames();
        for (uint32_t frame = 0U; frame < frames; ++frame)
        {
            // READ BOTH channels FIRST (the #1 crossfeed bug is reading the just-written value). The
            // dry samples that feed each cross path are the CURRENT inputs, captured before any write.
            const float dryL = left[frame];
            const float dryR = right[frame];

            // --- Cross path R→L: delay R by D, then one-pole low-pass the delayed sample. ---
            // Read the delayed sample (D taps back) BEFORE overwriting this slot with the new input,
            // so a zero delay (D=0) reads-then-writes the same slot and degenerates to no delay.
            const uint32_t readIdxRL = (pathRtoL.writeIndex + kMaxCrossfeedDelayFrames - delay) %
                                       static_cast<uint32_t>(kMaxCrossfeedDelayFrames);
            const float delayedR = pathRtoL.delayLine[readIdxRL];
            pathRtoL.delayLine[pathRtoL.writeIndex] = dryR;
            pathRtoL.writeIndex =
                (pathRtoL.writeIndex + 1U) % static_cast<uint32_t>(kMaxCrossfeedDelayFrames);
            // y[n] = (1-p)·x[n] + p·y[n-1]
            pathRtoL.lpfState = (lpfB0 * delayedR) + (lpfPole * pathRtoL.lpfState);
            const float crossToL = pathRtoL.lpfState;

            // --- Cross path L→R: delay L by D, then one-pole low-pass the delayed sample. ---
            const uint32_t readIdxLR = (pathLtoR.writeIndex + kMaxCrossfeedDelayFrames - delay) %
                                       static_cast<uint32_t>(kMaxCrossfeedDelayFrames);
            const float delayedL = pathLtoR.delayLine[readIdxLR];
            pathLtoR.delayLine[pathLtoR.writeIndex] = dryL;
            pathLtoR.writeIndex =
                (pathLtoR.writeIndex + 1U) % static_cast<uint32_t>(kMaxCrossfeedDelayFrames);
            pathLtoR.lpfState = (lpfB0 * delayedL) + (lpfPole * pathLtoR.lpfState);
            const float crossToR = pathLtoR.lpfState;

            // Gain-neutral crossfeed: wet = gDirect·direct + gCross·(LP-filtered, delayed cross).
            const float wetL = (gDirect * dryL) + (gCross * crossToL);
            const float wetR = (gDirect * dryR) + (gCross * crossToR);

            // Per-sample click-free blend between dry (mix=0) and full crossfeed (mix=1).
            const float mix = mixRamp_.tick();
            const float dryGain = 1.0F - mix;

            // WRITE BOTH channels LAST, after both new values are computed (read-both-then-write-both).
            left[frame] = (dryGain * dryL) + (mix * wetL);
            right[frame] = (dryGain * dryR) + (mix * wetR);
        }
    }

} // namespace AdaptiveSound
