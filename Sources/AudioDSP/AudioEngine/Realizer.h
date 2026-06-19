#ifndef ADAPTIVE_SOUND_REALIZER_H
#define ADAPTIVE_SOUND_REALIZER_H

#include "../EQ/EQModuleCoefficients.h" // computeBiquadCascade (off-main EQ design)
#include "../include/DSPKernel.h"
#include "../include/TargetState.h"
#include <array>
#include <cstdint>
#include <dispatch/dispatch.h>
#include <memory>
#include <type_traits>

namespace AdaptiveSound
{
    // ------------------------------------------------------------------------
    // Realizer (S6 Tier-3, sub-step 3a) — single-producer, off-main control owner.
    //
    // The Realizer owns the canonical `TargetState` (moved OUT of the AdaptiveSoundAU
    // @interface, so it is structurally unreachable except through this object) and a
    // shared_ptr<DSPKernel> to publish through. It is the SOLE caller of
    // DSPKernel::publishTargetState — retiring the load-bearing single-producer comments
    // at DSPKernel.mm / EQModule.h.
    //
    // Ownership: held by a std::shared_ptr by AdaptiveSoundAU. Control-plane entry points
    // hop to a dedicated serial dispatch_queue (`com.adaptivesound.realizer`, off-main /
    // off-RT) capturing a shared_ptr<Realizer> via shared_from_this — NEVER the ObjC `self`
    // — so intents in flight keep the Realizer + kernel alive until the queue drains.
    //
    // Coalescing (design §1.3): per-intent-kind slots (NOT a std::atomic of 31 floats).
    // Each control-thread entry point writes its slot and posts a drain block ONLY on a
    // clean->dirty transition; the drain reads-and-clears the dirty slots, recomputes only
    // the dirty parts (EQ dirty -> computeBiquadCascade here, off-main), applies a
    // field-level read-modify-write to the canonical state, bumps sequenceNumber, and calls
    // publishTargetState ONCE. The intensity slot is separate from the EQ slot, so an
    // interleaved intensity intent is never dropped.
    //
    // Threading: the entry points are called from a single control thread today (the
    // @MainActor — see AudioUnitRegistrationBridge.h). The slot writes are therefore
    // un-guarded. If a second control thread ever calls in, guard the slots with a small
    // off-RT mutex (NOT an atomic) — see the design doc §1.3.
    //
    // Feed-forward vs feedback (design §1, founder decision 1): the Realizer is the sole
    // producer of feed-FORWARD control in TargetState (EQ coeffs, intensity, ...).
    // Measurement-driven FEEDBACK (LoudnessModule's makeup gain) stays module-local and is
    // NOT routed through this queue. publishChannelLayoutTag likewise stays a direct call to
    // the loudness worker; the feed-forward plane and the loudness side-channel plane are
    // unordered w.r.t. each other (design §1.4).
    // ------------------------------------------------------------------------
    class Realizer : public std::enable_shared_from_this<Realizer>
    {
      public:
        // The pending-EQ coalescing slot. POD; copied by value on the control thread.
        struct PendingEqGains
        {
            std::array<float, static_cast<size_t>(EQModuleCoefficients::kNumBands)> gainsDb{};
            float sampleRate = 0.0F;
            bool dirty = false;
        };

        // The pending-intensity coalescing slot. POD; copied by value on the control thread.
        struct PendingIntensity
        {
            float value = 1.0F;
            bool dirty = false;
        };

        // Construct around the kernel the Realizer publishes through. `kernel` must outlive
        // the Realizer; AdaptiveSoundAU guarantees this by draining the queue (shutdown())
        // before releasing the kernel.
        explicit Realizer(std::shared_ptr<DSPKernel> kernel);
        ~Realizer();

        Realizer(const Realizer&) = delete;
        Realizer& operator=(const Realizer&) = delete;
        Realizer(Realizer&&) = delete;
        Realizer& operator=(Realizer&&) = delete;

        // --- Control-plane entry points (off-RT, single control thread) -----------------

        // Set the pending-EQ slot (31-band gains in dB + design sample rate) and post a
        // drain on a clean->dirty transition. The biquad cascade is computed off-main inside
        // the drain, not here. `count` must equal EQModuleCoefficients::kNumBands and
        // sampleRate must be > 0, else this is a no-op returning false.
        bool setPendingEqGains(const float* gainsDb, uint32_t count, double sampleRate);

        // Set the pending-intensity slot (clamped to [0,1]) and post a drain on a
        // clean->dirty transition.
        void setPendingIntensity(float value);

        // Teardown / draining barrier (design §1, the review's BLOCKER). Quiesces the queue
        // with dispatch_sync(queue, ^{}) so no queued block runs after the caller drops its
        // shared_ptr<Realizer> and releases the kernel. Idempotent. Must be called by
        // AdaptiveSoundAU BEFORE releasing the kernel.
        void shutdown();

        // --- Synchronously-callable intent application (testability, design §1.7) -------
        // These do the read-modify-write + (for EQ) the cascade design + the single publish
        // on the CALLING thread. The dispatch wrapper (the drain block) just hops to the
        // serial queue and calls these. A future unit test can drive the RMW logic directly
        // without a dispatch hop.

        // Apply a 31-band EQ gain vector: design the cascade, RMW canonical_.eq, bump
        // sequenceNumber, publish once. Caller owns `gains`.
        void applyEqGains(
            const std::array<float, static_cast<size_t>(EQModuleCoefficients::kNumBands)>& gains,
            float sampleRate);

        // Apply an intensity value (already clamped): RMW canonical_.intensityLinear, bump
        // sequenceNumber, publish once.
        void applyIntensity(float value);

        // Read-only canonical-state accessor for tests/diagnostics (control thread only).
        const TargetState& canonicalState() const noexcept { return canonical_; }

      private:
        // Drain the dirty coalescing slots: read-and-clear, recompute only what changed,
        // RMW canonical_, bump sequenceNumber, publish ONCE. Runs on the serial queue (or
        // synchronously from a test). Asserts it owns the canonical-state mutation path.
        void drain();

        // Publish the canonical state through the kernel (the sole publishTargetState call
        // site). Asserts the realizer queue in debug.
        void publishCanonical();

        std::shared_ptr<DSPKernel> kernel_;  // outlives us (drained before release)
        dispatch_queue_t queue_ = nullptr;   // serial, off-main; sole publisher
        TargetState canonical_{};            // canonical feed-forward state (moved out of the AU)

        // Coalescing slots, written on the control thread, read-and-cleared in drain().
        PendingEqGains pendingEqGains_{};
        PendingIntensity pendingIntensity_{};
        bool shutdown_ = false;
    };

    // -fno-exceptions discipline (design §6): the intent/slot PODs must be trivially copyable
    // so they can be byte-copied into a captured drain block without surprises.
    static_assert(std::is_trivially_copyable<Realizer::PendingEqGains>::value,
                  "Realizer::PendingEqGains must be trivially copyable");
    static_assert(std::is_trivially_copyable<Realizer::PendingIntensity>::value,
                  "Realizer::PendingIntensity must be trivially copyable");

} // namespace AdaptiveSound

#endif // ADAPTIVE_SOUND_REALIZER_H
