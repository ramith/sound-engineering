#pragma once
#include "../include/MultichannelView.h"
#include "../include/TargetState.h"
#include <AudioToolbox/AudioToolbox.h>

namespace AdaptiveSound
{

    // Binaural BRIR convolution is a future epic (S18); this is an explicit pass-through
    // stub. It stores the init state the real module will need and guards process() on it,
    // so both methods are genuine instance methods matching the module interface rather than
    // static no-ops.
    class BRIRModule
    {
      public:
        BRIRModule() = default;

        void initialize(uint32_t sampleRate, uint32_t maxFrames) noexcept
        {
            sampleRate_ = sampleRate;
            maxFrames_ = maxFrames;
        }

        // const while it is a pass-through (no mutable DSP state yet); becomes non-const like the
        // other modules' process() when BRIR convolution lands.
        void process(const BRIRParams& /*params*/, const MultichannelView& /*block*/) const noexcept
        {
            if (maxFrames_ == 0U)
            {
                return; // not initialized
            }
            // No BRIR convolution yet — bit-exact pass-through.
        }

      private:
        uint32_t sampleRate_ = 0U;
        uint32_t maxFrames_ = 0U;
    };

} // namespace AdaptiveSound
