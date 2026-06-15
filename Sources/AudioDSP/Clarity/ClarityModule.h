#ifndef CLARITY_MODULE_H
#define CLARITY_MODULE_H
#include "../include/TargetState.h"
#include <AudioToolbox/AudioToolbox.h>

namespace AdaptiveSound
{

    class ClarityModule
    {
      public:
        ClarityModule() = default;
        void initialize(uint32_t /*sampleRate*/, uint32_t /*maxFrames*/) noexcept
        {
        }
        void process(const ClarityParams& /*params*/,
                     AudioBufferList* /*ioData*/,
                     uint32_t /*frameCount*/) noexcept
        {
        }
    };

} // namespace AdaptiveSound
#endif
