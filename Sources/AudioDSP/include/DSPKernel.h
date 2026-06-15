#ifndef DSP_KERNEL_H
#define DSP_KERNEL_H

#include "AudioConstants.h"
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

        DSPKernel(const DSPKernel&) = delete;
        DSPKernel& operator=(const DSPKernel&) = delete;
        DSPKernel(DSPKernel&&) = delete;
        DSPKernel& operator=(DSPKernel&&) = delete;

        // Initialize with sample rate and buffer frame size
        void initialize(uint32_t sampleRate, uint32_t maxFrames) noexcept;

        // Process audio buffer with current parameter snapshot
        void process(AudioBufferList* ioData, uint32_t inNumberFrames) noexcept;

        // Publish new parameter state from the off-RT (control/Realizer) thread.
        // Builds the EQ vDSP setup off-RT (issue #3) before publishing the snapshot.
        void publishTargetState(const TargetState& newState) noexcept;

      private:
        uint32_t sampleRate_ = kDefaultSampleRate;
        uint32_t maxFrames_ = kDefaultMaxFrames;

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
