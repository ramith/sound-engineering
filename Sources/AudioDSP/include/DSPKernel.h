#ifndef DSP_KERNEL_H
#define DSP_KERNEL_H

#include "DoubleBufferSnapshot.h"
#include "TargetState.h"
#include <AudioToolbox/AudioToolbox.h>
#include <memory>

// Forward declarations of module classes
namespace AdaptiveSound
{
    class EQModule;
    class ClarityModule;
    class LoudnessModule;
    class BRIRModule;
    class LimiterModule;

    // DSP Kernel: orchestrates 5-module signal chain
    // EQ → Clarity → BRIR → Loudness → Limiter
    class DSPKernel
    {
      public:
        DSPKernel();
        ~DSPKernel();

        // Initialize with sample rate and buffer frame size
        void initialize(uint32_t sampleRate, uint32_t maxFrames) noexcept;

        // Process audio buffer with current parameter snapshot
        void process(AudioBufferList* ioData, uint32_t inNumberFrames) noexcept;

        // Publish new parameter state from off-RT thread
        void publishTargetState(const TargetState& newState) noexcept
        {
            targetStateSnapshot_.publish(newState);
        }

      private:
        uint32_t sampleRate_ = 48000;
        uint32_t maxFrames_ = 512;

        // 5-module signal chain
        std::unique_ptr<EQModule> eqModule_;
        std::unique_ptr<ClarityModule> clarityModule_;
        std::unique_ptr<BRIRModule> brirModule_;
        std::unique_ptr<LoudnessModule> loudnessModule_;
        std::unique_ptr<LimiterModule> limiterModule_;

        // Lock-free parameter transport
        DoubleBufferSnapshot<TargetState> targetStateSnapshot_;
    };

} // namespace AdaptiveSound

#endif // DSP_KERNEL_H
