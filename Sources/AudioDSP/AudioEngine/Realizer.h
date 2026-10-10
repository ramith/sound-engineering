#pragma once

#include "../EQ/GraphicEQDesigner.h" // the Realizer's own designer (owner-local, architect F9)
#include "../include/DSPKernel.h"
#include "../include/TargetState.h"
#include "../Spatial/CrossfeedModule.h" // kMaxCrossfeedDelayFrames (off-RT coeff clamp)
#include <array>
#include <atomic>
#include <cstdint>
#include <dispatch/dispatch.h>
#include <memory>
#include <mutex>
#include <type_traits>

namespace AdaptiveSound
{
    // ------------------------------------------------------------------------
    // PendingSlot<T> — one coalescing intent slot (architect A-F15). The control thread write()s
    // the newest intent and learns whether the slot just went clean → dirty (post one drain then);
    // the drain take()s it. Both run under the Realizer's slotMutex_ (off-RT), never on the RT
    // thread. T is a trivially copyable intent POD.
    // ------------------------------------------------------------------------
    template <typename T> class PendingSlot
    {
        static_assert(std::is_trivially_copyable_v<T>, "an intent must be trivially copyable");

      public:
        // Store the newest intent. True when the slot was clean (the caller posts a drain).
        bool write(const T& value) noexcept
        {
            const bool wasClean = !dirty_;
            value_ = value;
            dirty_ = true;
            return wasClean;
        }

        // Take the pending intent, if any, leaving the slot clean.
        [[nodiscard]] bool take(T& out) noexcept
        {
            if (!dirty_)
            {
                return false;
            }
            out = value_;
            dirty_ = false;
            return true;
        }

      private:
        T value_{};
        bool dirty_ = false;
    };

    // ------------------------------------------------------------------------
    // Realizer (S6 Tier-3 3a; Sprint EQ EQ1b) — the single off-RT producer of feed-forward control.
    //
    // It owns the canonical TargetState and a shared_ptr<DSPKernel>, and it OWNS the design sample
    // rate: every intent is realised at the rate the kernel was last initialised at, so nothing
    // upstream passes a rate (engine-plan §6). Control-plane entry points (one control thread, the
    // @MainActor) write a coalescing slot and post a drain to a serial queue on a clean → dirty
    // transition; the drain realises only what changed, read-modify-writes the canonical state and
    // publishes ONCE. The EQ is designed HERE, on the queue, by the Realizer's own
    // GraphicEQDesigner (never shared with the UI's), into the finished (k, m1) the RT module runs,
    // with the glide time from the τ rule (EQTargets.h).
    //
    // Re-allocation (engine-plan §6): reinitializeKernel() runs on the queue (dispatch_sync), so it
    // is serialised with every publish: it re-initialises the kernel, re-solves the EQ from the
    // stored points and re-derives the crossfeed at the new rate, and publishes once — the EQ
    // module snaps to that first target, so a rate or channel change never fades in from flat.
    //
    // Threading: the slots are guarded by slotMutex_ (control-thread write vs drain read). Never
    // taken on the RT thread. Everything else is queue-owned.
    // ------------------------------------------------------------------------
    class Realizer : public std::enable_shared_from_this<Realizer>
    {
      public:
        // The EQ intent: the 31 points the UI draws (already clamped to ±12) and On/Off.
        struct EqIntent
        {
            std::array<float, kEqBandCount> points{};
            bool isOn = false;
        };

        struct IntensityIntent
        {
            float value = 1.0F;
        };

        // The crossfeed intent; the coefficients are derived from it at the owned rate.
        struct CrossfeedIntent
        {
            uint32_t enabled = 0U;
            float level = 0.0F;
            uint32_t preset = 0U; // CrossfeedPreset value
        };

        // Construct around the kernel the Realizer publishes through, initialised at `sampleRate`.
        // `kernel` must outlive the Realizer; AdaptiveSoundAU guarantees this by draining the
        // queue (shutdown()) before releasing the kernel.
        Realizer(std::shared_ptr<DSPKernel> kernel, double sampleRate);
        ~Realizer();

        Realizer(const Realizer&) = delete;
        Realizer& operator=(const Realizer&) = delete;
        Realizer(Realizer&&) = delete;
        Realizer& operator=(Realizer&&) = delete;

        // --- Control-plane entry points (off-RT, single control thread) -----------------

        // The EQ: `count` (must be 31) points in dB, and On/Off. The trust boundary (engine-plan
        // §7, guard layer 1): a NULL pointer, a wrong count or any non-finite point is rejected
        // (false; the last good EQ keeps playing); finite points are clamped to ±12 dB.
        bool setPendingEq(const float* pointsDb, uint32_t count, bool isOn);

        // Intensity, clamped to [0,1].
        void setPendingIntensity(float value);

        // Crossfeed: level clamped to [0,1], preset to the valid CrossfeedPreset range.
        void setPendingCrossfeed(uint32_t enabled, float level, uint32_t preset);

        // The rate the EQ is designed at (the kernel's rate). Any thread.
        [[nodiscard]] double eqDesignSampleRate() const noexcept
        {
            return designRate_.load(std::memory_order_acquire);
        }

        // --- Allocation thread ------------------------------------------------------------

        // Re-initialise the kernel at a (possibly new) rate and frame ceiling, then re-realise
        // every intent at that rate and publish once. Runs on the Realizer's queue via
        // dispatch_sync. Call from allocateRenderResources (the AU is not rendering then).
        void reinitializeKernel(uint32_t sampleRate, uint32_t maxFrames);

        // Teardown / draining barrier. Idempotent. Must be called before releasing the kernel.
        void shutdown();

        // --- Synchronously-callable intent application (tests; design §1.7) -------------
        // The read-modify-write + single publish on the CALLING thread; the drain calls these.
        void applyEq(const EqIntent& intent);
        void applyIntensity(float value);
        void applyCrossfeed(const CrossfeedIntent& intent);

        // Read-only canonical-state accessor for tests/diagnostics.
        const TargetState& canonicalState() const noexcept
        {
            return canonical_;
        }

      private:
        void drain();
        void reinitializeOnQueue(uint32_t sampleRate, uint32_t maxFrames);
        void postDrain();
        // Design the stored EQ intent at sampleRate_ into canonical_.eq (glide by the τ rule).
        void realizeEq();
        void realizeCrossfeed();
        void publishCanonical();

        std::shared_ptr<DSPKernel> kernel_; // outlives us (drained before release)
        dispatch_queue_t queue_ = nullptr;  // serial, off-main; sole publisher

        // --- Queue-owned -----------------------------------------------------------------
        TargetState canonical_{};
        std::unique_ptr<GraphicEQDesigner> designer_;
        EqIntent eq_{};
        CrossfeedIntent crossfeed_{};
        std::array<double, kEqBandCount> publishedGainsDb_{}; // the τ rule's "from" endpoint
        double sampleRate_ = 0.0;
        std::atomic<double> designRate_{0.0}; // sampleRate_, readable from any thread

        // --- Coalescing slots (control thread writes, drain takes; under slotMutex_) --------
        std::mutex slotMutex_;
        PendingSlot<EqIntent> pendingEq_;
        PendingSlot<IntensityIntent> pendingIntensity_;
        PendingSlot<CrossfeedIntent> pendingCrossfeed_;
        bool shutdown_ = false;
    };

} // namespace AdaptiveSound
