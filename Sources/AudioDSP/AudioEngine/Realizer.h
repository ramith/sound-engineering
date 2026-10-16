#pragma once

#include "../EQ/GraphicEQDesigner.h" // the Realizer's own designer (owner-local, architect F9)
#include "../include/DSPKernel.h"
#include "../include/TargetState.h"
#include "../Loudness/TrackLoudnessGain.h" // the loudness-neutral EQ gain (EQ1c)
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
    // the newest intent (a burst overwrites it); the drain take()s it. Both run under the
    // Realizer's slotMutex_ (off-RT), never on the RT thread. Whether to post a drain is decided
    // ONCE for all slots (Realizer::drainPosted_), not per slot: per-slot posting let every real
    // drain re-arm each slot, so the serial queue grew without bound under a mixed burst and a
    // re-allocation (dispatch_sync) waited seconds behind it. T is a trivially copyable POD.
    // ------------------------------------------------------------------------
    template <typename T> class PendingSlot
    {
        static_assert(std::is_trivially_copyable_v<T>, "an intent must be trivially copyable");

      public:
        // Store the newest intent, replacing any not yet taken.
        void write(const T& value) noexcept
        {
            value_ = value;
            dirty_ = true;
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
    // @MainActor) write a coalescing slot and post a drain to a serial queue only when none is
    // pending (at most ONE untaken drain is ever queued, whatever the mix of intents); the drain
    // realises only what changed, read-modify-writes the canonical state and publishes ONCE. The
    // EQ is designed HERE, on the queue, by the Realizer's own GraphicEQDesigner (never shared
    // with the UI's), into the finished (k, m1) the RT module runs, with the glide time from the
    // τ rule (EQTargets.h).
    //
    // Re-allocation (engine-plan §6): reinitializeKernel() runs on the queue (dispatch_sync), so it
    // is serialised with every publish: it re-initialises the kernel, re-solves the EQ from the
    // stored points and re-derives the crossfeed at the new rate, and publishes once — the EQ
    // module snaps to that first target, so a rate or channel change never fades in from flat.
    //
    // Loudness-neutral gain (EQ1c, decision 26): the EQ module plays the curve and then −ΔL, how
    // much louder the curve makes the current track. The track analyzer and the playback bridge
    // post the track's profile, a failed analysis and the audible track change
    // (publishTrackLoudnessProfile / reportTrackLoudnessFailure / setCurrentTrack — never the EQ
    // view model); TrackLoudnessGain decides the gain and its glide, and the Realizer publishes it
    // in canonical_.eq.outputGainDb, so it rides the EQ module's smoother. An EQ edit carries a
    // decimated estimate with its coefficients, refreshed in full after 150 ms idle (A6). A track
    // whose analysis failed runs the kernel's causal estimate (DSPKernel::startCausalLoudness).
    //
    // Threading: the slots and drainPosted_ are guarded by slotMutex_ (control-thread write vs
    // drain take). Never taken on the RT thread. Everything else is queue-owned.
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

        // The crossfeed intent; the coefficients are derived from it at the owned rate. A preset
        // plays at its full strength: there is no depth control (R1.1-A).
        struct CrossfeedIntent
        {
            uint32_t enabled = 0U;
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

        // Crossfeed: on/off, and the preset (clamped to the valid CrossfeedPreset range).
        void setPendingCrossfeed(uint32_t enabled, uint32_t preset);

        // --- Track loudness (any thread; each posts to the queue) ------------------------
        // A track's loudness profile from the analyzer (a prefix, then the whole track; the
        // engine keeps this reference, so the caller may drop its own). token 0 or a null
        // profile is ignored.
        void publishTrackLoudnessProfile(uint64_t token,
                                         std::shared_ptr<const TrackLoudnessProfile> profile);
        // The analyzer could not profile `token` at all: it falls back to the causal estimate.
        void reportTrackLoudnessFailure(uint64_t token);
        // `token` became the audible track: at a gapless seam (`gaplessSeam`), or by a fresh
        // start. The same token again is a no-op (a re-establish of the same file).
        void setCurrentTrack(uint64_t token, bool gaplessSeam);

        // --- The output (any thread; posts to the queue) ----------------------------------
        // The output's transport (kAudioDevicePropertyTransportType FourCC; 0 = unknown): sets
        // the EQ-only path's limiter ceiling (founder decision 29, Limiting/OutputCeiling.h).
        void setOutputTransport(uint32_t transportType);

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
        // Ends any causal loudness estimate.
        void shutdown();

        // Off-RT, never on the queue itself: returns once every block posted before the call has
        // run (tests and diagnostics read queue-owned state after it).
        void barrier();

        // --- Synchronously-callable intent application (tests; design §1.7) -------------
        // The read-modify-write + single publish, run ON the queue (dispatch_sync; inline when
        // already there), so a test never races the queue's own blocks (the loudness refresh).
        void applyEq(const EqIntent& intent);
        void applyIntensity(float value);
        void applyCrossfeed(const CrossfeedIntent& intent);

        // Tests/diagnostics: COPIES of the canonical state and of the loudness-gain state, taken
        // on the queue (dispatch_sync), so a reader never races the queue's own blocks (the
        // loudness refresh, a causal snapshot) however busy it is.
        [[nodiscard]] TargetState canonicalState();
        [[nodiscard]] TrackLoudnessGain loudnessGain();

      private:
        void drain();
        void reinitializeOnQueue(uint32_t sampleRate, uint32_t maxFrames);
        void postDrain();
        // Write `intent` into `slot` under slotMutex_; true when the caller must post a drain
        // (none was pending). Defined in Realizer.mm, its only user.
        template <typename T> [[nodiscard]] bool writeSlot(PendingSlot<T>& slot, const T& intent);
        // Design the stored EQ intent at sampleRate_ into canonical_.eq (glide by the τ rule).
        void realizeEq();
        void realizeCrossfeed();
        void publishCanonical();

        // Loudness (queue): publish a gain-only change; keep the causal estimate running exactly
        // when TrackLoudnessGain wants it (`restart`: a new estimate even if one runs); the 150 ms
        // idle refresh after an edit.
        void applyGainChange(const TrackLoudnessGain::Change& change);
        void syncCausalEstimate(bool restart);
        void stopCausalEstimate();
        void scheduleLoudnessRefresh();
        void applyCausalSnapshot(uint64_t generation,
                                 std::shared_ptr<const TrackLoudnessProfile> profile);
        // Run `work()` on the queue and wait (inline when already on it). Defined in Realizer.mm.
        template <typename Work> void runOnQueue(const Work& work);

        std::shared_ptr<DSPKernel> kernel_; // outlives us (drained before release)
        dispatch_queue_t queue_ = nullptr;  // serial, off-main; sole publisher

        // --- Queue-owned -----------------------------------------------------------------
        TargetState canonical_{};
        std::unique_ptr<GraphicEQDesigner> designer_;
        EqIntent eq_{};
        CrossfeedIntent crossfeed_{};
        GraphicEQDesign publishedDesign_{}; // the τ rule's "from" endpoint (rate 0: none yet)
        double sampleRate_ = 0.0;
        std::atomic<double> designRate_{0.0}; // sampleRate_, readable from any thread
        TrackLoudnessGain loudness_;
        bool causalRunning_ = false;
        uint64_t causalGeneration_ = 0U;  // bumped per estimate: stale snapshots are dropped
        uint64_t refreshGeneration_ = 0U; // bumped per edit: only the last edit's refresh runs

        // --- Coalescing slots (control thread writes, drain takes; under slotMutex_) --------
        std::mutex slotMutex_;
        PendingSlot<EqIntent> pendingEq_;
        PendingSlot<IntensityIntent> pendingIntensity_;
        PendingSlot<CrossfeedIntent> pendingCrossfeed_;
        bool drainPosted_ = false; // a drain is queued and has not yet taken the slots
        bool shutdown_ = false;
    };

} // namespace AdaptiveSound
