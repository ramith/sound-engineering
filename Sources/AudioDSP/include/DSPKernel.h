// `#pragma once` is the standardized include-guard convention across this include tree
// (Stage-2 review IDM-2 — the tree was a mix of `#pragma once` and bare, collision-prone
// `#ifndef` guards; unified on `#pragma once`, which also removes the bare-macro risk).
#pragma once

#include "AudioConstants.h"
#include "ChannelLayout.h"
#include "DoubleBufferSnapshot.h"
#include "ParameterRamp.h"
#include "TargetState.h"
#include <AudioToolbox/AudioToolbox.h>
#include <cstdint>
#include <functional>
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
    class CausalLoudnessTap;
    class MultichannelView;
    struct TrackLoudnessProfile;

    // DSP Kernel: the signal chain, EQ FIRST (Sprint EQ decision 25):
    //
    //   EQ → [dry tap] → Clarity → BRIR → Crossfeed → [Intensity blend] → Loudness → Limiter
    //
    // The EQ sits ahead of the Intensity blend, so what the EQ graph draws is what plays at every
    // Intensity; the blend's dry signal is the EQ'd signal. Four paths (engine-plan §5.1):
    //
    //   P0 bit-perfect  Intensity settled at 0 AND the EQ settled at its identity for ≥ 2 s:
    //                   the input is returned untouched (the limiter's look-ahead ring is primed).
    //   P1 EQ-only      Intensity settled at 0 otherwise: EQ → Limiter (no normaliser, so
    //                   EQ On ↔ Off stays level-fair against the bit-perfect Off).
    //   P2 full         Intensity settled at 1: EQ → coloration → Loudness → Limiter.
    //   P3 blend        otherwise: EQ → dry snapshot → coloration → equal-power blend → Loudness
    //                   (its contribution faded as min(1, r/0.1), amendment 2, gliding at most a
    //                   full 0 ↔ 1 per 2 s, decision 33) → Limiter. P1 and P2 wait for that glide:
    //                   until it ends the blend runs at the endpoint.
    //
    // P0 ↔ P1/P3 switches cross-fade the undelayed input and the limiter's 3 ms-delayed output over
    // 5 ms at constant power (correlation-compensated, amendment 17), so a switch neither skips nor
    // repeats audio nor dips; the 2 s hysteresis keeps a short Compare hold at Intensity 0 from
    // switching at all.
    class DSPKernel
    {
      public:
        DSPKernel();
        ~DSPKernel();

        DSPKernel(const DSPKernel&) = delete;
        DSPKernel& operator=(const DSPKernel&) = delete;
        DSPKernel(DSPKernel&&) = delete;
        DSPKernel& operator=(DSPKernel&&) = delete;

        // Initialize with sample rate and buffer frame size (off-RT; never while rendering).
        void initialize(uint32_t sampleRate, uint32_t maxFrames) noexcept;

        // Process audio buffer with current parameter snapshot (RT).
        void process(AudioBufferList* ioData, uint32_t inNumberFrames) noexcept;

        // Publish new parameter state from the off-RT (control/Realizer) thread. Single producer.
        void publishTargetState(const TargetState& newState) noexcept;

        // Off-RT (control thread): forward decoded BS.1770-5 per-channel weights to
        // the loudness measurement worker.  S2 calls this when the source file's layout
        // tag changes.  Harmless no-op if loudnessModule_ is not yet initialised.
        void publishChannelLayout(const ChannelLayout& layout) noexcept;

        // Off-RT (the Realizer's queue): the causal running loudness estimate of the kernel's input
        // (CausalLoudnessTap, EQ1c) — the fallback for a track whose loudness analysis failed.
        // start: a fresh estimate whose profile-so-far reaches `sink` (on the tap's worker) after
        // every second of audio; stop: no further calls once it returns. initialize() ends any
        // estimate (the Realizer restarts it after a re-allocation).
        void startCausalLoudness(
            std::function<void(std::shared_ptr<const TrackLoudnessProfile>)> sink) noexcept;
        void stopCausalLoudness() noexcept;
        // Diagnostics (any thread): the frames the current causal estimate has analysed.
        [[nodiscard]] uint64_t causalLoudnessFedFrames() const noexcept;

        // Read-only view of the EQ stage between process() calls (tests/diagnostics only).
        [[nodiscard]] const EQModule* eqModule() const noexcept
        {
            return eqModule_.get();
        }

      private:
        // Run the wet-region coloration chain (Clarity → BRIR → Crossfeed) in place.
        void runColorationChain(const TargetState& state, const MultichannelView& block) noexcept;
        // The processed paths P1–P3 (everything but the bit-perfect return), in place.
        void runProcessedPath(const TargetState& state,
                              const MultichannelView& block,
                              bool intensityAtZero,
                              bool intensityAtOne) noexcept;
        // P3: EQ'd dry tap → coloration → equal-power blend → weighted Loudness → Limiter.
        void runBlendPath(const TargetState& state, const MultichannelView& block) noexcept;
        // Copy the block into a planar scratch (channel ch at scratch + ch·maxFrames_).
        void copyBlock(const MultichannelView& block, std::vector<float>& scratch) const noexcept;
        // Cross-fade the processed block with the bypass copy, gliding bypassMix_ toward `toward`.
        void crossfadeWithBypass(const MultichannelView& block, float toward) noexcept;
        // The correlation (clamped to [0, 1]) of the processed block and the bypass copy.
        [[nodiscard]] float streamCorrelation(const MultichannelView& block,
                                              uint32_t frames) const noexcept;
        // The normaliser's contribution an Intensity asks for: min(1, r/0.1).
        [[nodiscard]] static float loudnessContributionAt(float intensity) noexcept;

        uint32_t sampleRate_ = kDefaultSampleRate;
        uint32_t maxFrames_ = kDefaultMaxFrames;

        // Signal chain modules.
        std::unique_ptr<EQModule> eqModule_;
        std::unique_ptr<ClarityModule> clarityModule_;
        std::unique_ptr<BRIRModule> brirModule_;
        std::unique_ptr<CrossfeedModule> crossfeedModule_;
        std::unique_ptr<LoudnessModule> loudnessModule_;
        std::unique_ptr<LimiterModule> limiterModule_;
        std::unique_ptr<CausalLoudnessTap> causalTap_; // the input, for the causal estimate

        // Lock-free parameter transport (wait-free SPSC triple-buffer snapshot).
        DoubleBufferSnapshot<TargetState> targetStateSnapshot_;

        // RT-thread-owned snapshot state (S6 RACE-1): the stable per-block copy of the snapshot.
        TargetState currentState_{};
        TargetState scratchState_{};

        // --- Steerable wet/dry intensity (S6 Tier-3 §3b) ---
        // Ramped to avoid zipper noise; snapped to the initial intensity in initialize(). The
        // endpoints take HARD branches gated on "settled": a ramped value only approaches 0/1
        // asymptotically, and `dry + 1·(wet-dry)` is NOT bit-equal to wet.
        ParameterRamp intensityRamp_{};

        // Planar scratches, maxFrames_ × kMaxChannels each, allocated in initialize():
        // the blend's EQ'd dry tap, and the undelayed input for the bypass cross-fade.
        std::vector<float> dryScratch_;
        std::vector<float> bypassScratch_;

        // Per-sample scratch (maxFrames_ each): the equal-power gains and the normaliser's
        // contribution weight.
        std::vector<float> wetGainBuf_;
        std::vector<float> dryGainBuf_;
        std::vector<float> loudnessWeightBuf_;

        // The normaliser's contribution (0 … 1) and its largest per-sample move (decision 33).
        float loudnessContribution_ = 1.0F;
        float loudnessContributionStep_ = 0.0F;

        // --- The bit-perfect path (P0) ---
        float bypassMix_ = 0.0F;          // weight of the undelayed input: 1 = P0, 0 = processed
        float bypassMixStep_ = 1.0F;      // per-sample change of bypassMix_ (5 ms cross-fade)
        float bypassCorrelation_ = 0.0F;  // the two streams' ρ, measured when a fade starts
        uint64_t identityHeldFrames_ = 0; // frames Intensity 0 + EQ identity has held so far
        uint64_t bypassHoldFrames_ = 0;   // the 2 s hysteresis before P0
        bool firstBlock_ = true;          // the first block after initialize() snaps the path
    };

} // namespace AdaptiveSound
