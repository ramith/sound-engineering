#ifndef DSP_KERNEL_H
#define DSP_KERNEL_H

#include "AudioConstants.h"
#include "ChannelLayout.h"
#include "DoubleBufferSnapshot.h"
#include "ParameterRamp.h"
#include "TargetState.h"
#include <AudioToolbox/AudioToolbox.h>
#include <memory>
#include <vector>

// Forward declarations of module classes
namespace AdaptiveSound
{
    class EQModule;
    class ClarityModule;
    class LoudnessModule;
    class BRIRModule;
    class CrossfeedModule;
    class LimiterModule;

    // DSP Kernel: orchestrates the wet-region coloration + safety signal chain
    // EQ → Clarity → BRIR → Crossfeed → [intensity blend] → Loudness → Limiter
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

        // Off-RT (control thread): forward decoded BS.1770-5 per-channel weights to
        // the loudness measurement worker.  S2 calls this when the source file's layout
        // tag changes.  Harmless no-op if loudnessModule_ is not yet initialised.
        void publishChannelLayout(const ChannelLayout& layout) noexcept;

      private:
        uint32_t sampleRate_ = kDefaultSampleRate;
        uint32_t maxFrames_ = kDefaultMaxFrames;

        // Signal chain modules. Crossfeed sits in the wet region, adjacent to BRIR's slot
        // (QW1 §2): EQ → Clarity → BRIR → Crossfeed, then the intensity blend, then
        // Loudness → Limiter.
        std::unique_ptr<EQModule> eqModule_;
        std::unique_ptr<ClarityModule> clarityModule_;
        std::unique_ptr<BRIRModule> brirModule_;
        std::unique_ptr<CrossfeedModule> crossfeedModule_;
        std::unique_ptr<LoudnessModule> loudnessModule_;
        std::unique_ptr<LimiterModule> limiterModule_;

        // Lock-free parameter transport (seqlock SPSC snapshot).
        DoubleBufferSnapshot<TargetState> targetStateSnapshot_;

        // RT-thread-owned snapshot state (S6 RACE-1). `currentState_` is the last CONSISTENT
        // snapshot the RT thread committed; `process()` copies the published snapshot into
        // `scratchState_` and promotes it to `currentState_` only on a non-torn read, otherwise it
        // keeps the previous `currentState_` (one-block-stale but consistent). Both are
        // pre-allocated members (no RT allocation) and touched ONLY on the RT thread, so they need
        // no locking.
        TargetState currentState_{};
        TargetState scratchState_{};

        // --- Steerable wet/dry intensity (S6 Tier-3 §3b) ---
        //
        // Intensity scales the COLORATION stages (EQ→Clarity→BRIR = "wet") against the
        // unprocessed "dry" input via an equal-power crossfade, BEFORE Loudness+Limiter
        // (so the limiter guards the final output and loudness measures what is heard).
        //
        // Ramped to avoid zipper noise; snapped to the initial intensity in initialize()
        // so there is no launch fade-in. The endpoints are taken via HARD branches gated
        // on "settled" (|current-target| < ε AND target ∈ {0,1}) — a ramped value only
        // approaches 0/1 asymptotically and `dry + 1·(wet-dry)` is NOT bit-equal to wet,
        // so the bit-exact paths must never run the crossfade math.
        ParameterRamp intensityRamp_{};

        // Planar dry-scratch: maxFrames_ × kMaxChannels, allocated in initialize().
        // Channel ch lives at dryScratch_.data() + ch*maxFrames_. Holds a per-channel
        // copy of the input taken BEFORE any module mutates the block. Never allocated
        // on the RT path (process() asserts frames ≤ maxFrames_).
        std::vector<float> dryScratch_;

        // Per-sample crossfade-gain scratch (maxFrames_ each), allocated in initialize().
        // wetGain[i] = sin(r[i]·π/2), dryGain[i] = cos(r[i]·π/2), r[i] = ramped intensity.
        std::vector<float> wetGainBuf_;
        std::vector<float> dryGainBuf_;
    };

} // namespace AdaptiveSound

#endif // DSP_KERNEL_H
