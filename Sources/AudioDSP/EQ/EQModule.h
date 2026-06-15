#ifndef EQ_MODULE_H
#define EQ_MODULE_H
#include "../include/AudioConstants.h"
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

        EQModule(const EQModule&) = delete;
        EQModule& operator=(const EQModule&) = delete;
        EQModule(EQModule&&) = delete;
        EQModule& operator=(EQModule&&) = delete;

        void initialize(uint32_t sampleRate, uint32_t maxFrames) noexcept;
        void process(const EQParams& params, AudioBufferList* ioData, uint32_t frameCount) noexcept;

      private:
        // Pre-allocated delay state for vDSP_biquad processing
        // For each biquad stage, we need [z1_L, z2_L, z1_R, z2_R]
        std::array<std::vector<float>, kMaxBiquads> biquadDelay_;

        // vDSP_biquad_Setup opaque pointer (defined in Accelerate framework)
        void* cascadeSetup_ = nullptr;

        // Cached coefficient array for vDSP (5 coeffs per stage × kMaxBiquads)
        std::vector<double> cascadeCoeffs_;

        uint32_t sampleRate_ = kDefaultSampleRate;
        uint32_t maxFrames_ = kDefaultMaxFrames;
    };

} // namespace AdaptiveSound
#endif
