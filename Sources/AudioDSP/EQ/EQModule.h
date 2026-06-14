#ifndef EQ_MODULE_H
#define EQ_MODULE_H
#include "../include/TargetState.h"
#include <array>
#include <AudioToolbox/AudioToolbox.h>
#include <vector>

namespace AdaptiveSound
{

    class EQModule
    {
      public:
        EQModule() = default;
        ~EQModule();

        void initialize(uint32_t sampleRate, uint32_t maxFrames) noexcept;
        void process(const EQParams&, AudioBufferList*, uint32_t) noexcept;

      private:
        // Pre-allocated delay state for vDSP_biquad processing
        // For each biquad stage, we need [z1_L, z2_L, z1_R, z2_R]
        std::array<std::vector<float>, kMaxBiquads> biquadDelay_;

        // vDSP_biquad_Setup opaque pointer (defined in Accelerate framework)
        void* cascadeSetup_ = nullptr;

        // Cached coefficient array for vDSP (5 coeffs per stage × kMaxBiquads)
        std::vector<double> cascadeCoeffs_;

        uint32_t sampleRate_ = 48000;
        uint32_t maxFrames_ = 512;
    };

} // namespace AdaptiveSound
#endif
