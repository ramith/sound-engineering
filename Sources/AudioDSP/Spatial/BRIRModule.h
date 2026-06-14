#ifndef BRIR_MODULE_H
#define BRIR_MODULE_H
#include "../include/TargetState.h"
#include <AudioToolbox/AudioToolbox.h>

namespace AdaptiveSound
{

    class BRIRModule
    {
      public:
        BRIRModule() = default;
        void initialize(uint32_t sampleRate, uint32_t maxFrames) noexcept
        {
        }
        void process(const BRIRParams&, AudioBufferList*, uint32_t) noexcept
        {
        }
    };

} // namespace AdaptiveSound
#endif
