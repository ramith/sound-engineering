#ifndef LIMITER_MODULE_H
#define LIMITER_MODULE_H
#include "../include/TargetState.h"
#include <AudioToolbox/AudioToolbox.h>

namespace AdaptiveSound
{

    class LimiterModule
    {
      public:
        LimiterModule() = default;
        void initialize(uint32_t sampleRate, uint32_t maxFrames) noexcept
        {
        }
        void process(const LimiterParams&, AudioBufferList*, uint32_t) noexcept
        {
        }
    };

} // namespace AdaptiveSound
#endif
