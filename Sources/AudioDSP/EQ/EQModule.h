#ifndef EQ_MODULE_H
#define EQ_MODULE_H
#include "../include/TargetState.h"
#include <AudioToolbox/AudioToolbox.h>

namespace AdaptiveSound
{

    class EQModule
    {
      public:
        EQModule() = default;
        void initialize(uint32_t sampleRate, uint32_t maxFrames) noexcept
        {
        }
        void process(const EQParams&, AudioBufferList*, uint32_t) noexcept
        {
        }
    };

} // namespace AdaptiveSound
#endif
