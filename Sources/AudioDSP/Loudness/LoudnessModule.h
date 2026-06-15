#ifndef LOUDNESS_MODULE_H
#define LOUDNESS_MODULE_H
#include "../include/TargetState.h"
#include <AudioToolbox/AudioToolbox.h>

namespace AdaptiveSound
{

    class LoudnessModule
    {
      public:
        LoudnessModule() = default;
        void initialize(uint32_t sampleRate, uint32_t maxFrames) noexcept
        {
        }
        void
        process(const LoudnessParams& params, AudioBufferList* ioData, uint32_t frameCount) noexcept
        {
        }
    };

} // namespace AdaptiveSound
#endif
