#pragma once

//
// GaplessSource.h — Pure-path gapless PureModeSource (Stage 2 of the gapless feature).
//
// REPLACES the bridge's CountingSource. Wraps the engine's single PureModeSource* and owns the
// current + a pre-armed next FileDecodeSource. At the current track's TRUE end-of-file the RT
// render thread atomically swaps to the armed-next source WITHIN ONE pullFloat call (drain the
// rest of A, then immediately pull B into the same host buffer) → sample-accurate, no gap, no
// inserted/dropped/duplicated frame.
//
// SAME-RATE, SAME-WIDTH ONLY: this source does no resampling and no channel mapping. armNext
// refuses a track that is not sameRateGaplessCompatible() with the active one; the control plane
// (the C-ABI bridge) pre-checks the same predicate so a rate/format mismatch is handled off-RT
// (drop + signal "needs reconfigure"), never at the seam.
//
// The arm contract (council D41; the bridge's side is in PureModeBridge.h):
//   * One slot, never replaced: armNext refuses while a track is armed. To change the pick, the
//     caller takes the old one off first (clearNext — an exactly-once exchange with the seam
//     claim, so the old pick either already became current or never will).
//   * The end is final: once the active track hit its true EOF with nothing armed (ended()), the
//     session is over — armNext refuses, and an arm that lost the race with the end is never
//     adopted. The caller starts the next track fresh (setCurrent).
//   * Arming frees the slot the last seam retired (reapRetired, off-RT), so a track armed right
//     after a seam, before the poll plane reaped, still arms.
//
// CoreAudio-FREE: pure C++ owning FileDecodeSources. Compiles into the C++ test harness.
// -fno-exceptions / -fno-rtti clean (no throw / dynamic_cast / typeid).
//
// Thread model:
//   * Control plane (off-RT): setCurrent / armNext / clearNext / reapRetired / resetActiveBase.
//     setCurrent has the precondition that render is stopped. The others are safe while render
//     runs because every shared transition goes through an atomic with the documented ordering.
//   * Poll plane (off-RT): transitionCount / renderedFramesCurrent / currentSampleRate / ended.
//     Lock-free reads for the position display + auto-advance polling.
//   * RT plane: pullFloat — NEVER allocates, locks, logs, throws, or touches Obj-C. The only
//     work is the seam-straddle (two FileDecodeSource::pullFloat calls + a handful of atomics).
//
// RT thread NEVER joins a thread. A track retired at the seam is parked in retired_; the poll
// plane (reapRetired, called from pureModeEnginePollTrackAdvance) joins + frees it off-RT.
//

#include "FileDecodeSource.h"
#include "PureModeSource.h"

#include <array>
#include <atomic>
#include <cstdint>
#include <memory>

namespace AdaptiveSound
{
    // Pure free function (CoreAudio-FREE, unit-testable): are two same-rate sources gapless-
    // compatible? They must agree on sample rate (±1 Hz), channel count, float-ness, and source
    // bit depth. decoderKind is DELIBERATELY excluded — Apple↔FFmpeg may legitimately differ for
    // the same audio and must not block a same-format gapless seam.
    [[nodiscard]] bool sameRateGaplessCompatible(const FileDecodeSource& cur,
                                                 const FileDecodeSource& next) noexcept;

    // A PureModeSource that plays a queue of pre-opened FileDecodeSources gaplessly, swapping at
    // each track's true end-of-file on the RT render thread.
    class GaplessSource final : public PureModeSource
    {
      public:
        GaplessSource() = default;
        ~GaplessSource() override = default;

        GaplessSource(const GaplessSource&) = delete;
        GaplessSource& operator=(const GaplessSource&) = delete;
        GaplessSource(GaplessSource&&) = delete;
        GaplessSource& operator=(GaplessSource&&) = delete;

        // --- Control plane (off-RT) ---

        // Install the currently-playing source. PRECONDITION: render is stopped (no concurrent
        // pullFloat). Resets transition/ended/seek state for a fresh session. Takes ownership.
        void setCurrent(std::unique_ptr<FileDecodeSource> source) noexcept;

        // Arm the next source to play gaplessly at the active track's true EOF. Returns true on
        // success. Refuses (returns false):
        //   * while a track is armed — one slot, never replaced: the caller clears it first;
        //   * once the session ended (ended()) — the end is final;
        //   * a source that is not sameRateGaplessCompatible() with the active track (the running
        //     stream's rate and width), or when there is no active track; the caller pre-checks
        //     the same predicate to tell "needs reconfigure" from an error.
        // Before arming it frees the slot the last seam retired (reapRetired: joins that source's
        // decode thread, off-RT), so an arm right after a seam never waits for the poll plane.
        // Takes ownership by value: on EITHER outcome `source` has been moved-from (a refused
        // source is freed off-RT as the parameter goes out of scope, joining its decode thread).
        [[nodiscard]] bool armNext(std::unique_ptr<FileDecodeSource> source) noexcept;

        // Take the armed track off the slot (the user changed the pick, or cleared it). Joins the
        // dropped source's decode thread off-RT. Safe while render runs: the exchange races the RT
        // seam claim so exactly one side wins — the armed track either already became current or
        // never will (no double-adopt, no leak).
        void clearNext() noexcept;

        // Join + free a source retired at the last seam, off-RT. Called by the poll plane
        // (pureModeEnginePollTrackAdvance) and by armNext. No-op when nothing is parked.
        void reapRetired() noexcept;

        // Re-base the ACTIVE track's per-track frame counter after a seek so position display
        // restarts from `frames` (the seek target, in active-track frames). Does NOT touch the
        // armed next or the transition count.
        void resetActiveBase(uint64_t frames) noexcept;

        // Borrow the ACTIVE track's source for a control-plane operation (seek, or a compatibility
        // check against a candidate next track). Returns nullptr when there is no active track.
        // The returned pointer is owned by this GaplessSource; the caller MUST NOT delete it and
        // MUST NOT retain it past the control-plane operation. Read it with render held
        // (HALOutputEngine::holdRender): the render thread swaps the active track at a seam, and a
        // seek needs pullFloat quiet (FileDecodeSource::seek's precondition).
        [[nodiscard]] FileDecodeSource* activeSource() const noexcept;

        // --- Poll plane (off-RT) ---

        // Monotonic count of completed seams. An increase means the armed-next became active.
        [[nodiscard]] uint64_t transitionCount() const noexcept;

        // Frames the ACTIVE track has rendered since it became active (re-zeroes at each seam).
        [[nodiscard]] uint64_t renderedFramesCurrent() const noexcept;

        // Sample rate of the ACTIVE track (Hz). 0 when there is no active track.
        [[nodiscard]] double currentSampleRate() const noexcept;

        // True once the active track hit its true EOF with no armed next (playlist exhausted).
        // Final for the session: no later arm seams (armNext refuses; an arm that slipped in
        // behind the end is never adopted). Only setCurrent clears it.
        [[nodiscard]] bool ended() const noexcept;

        // --- Observability (off-RT; conformance-test surface) ---
        //
        // These exist so the Pure gapless conformance suite can PIN the poll-reaps-source contract:
        // pureModeEnginePollTrackAdvance() must keep reaping retired sources off-RT or decode
        // threads leak. They are plain off-RT atomic reads — never touched on the RT thread — so
        // they add nothing to the seam-straddle hot path.

        // True while a source is parked in the retired slot awaiting reapRetired() (i.e. a seam has
        // fired but the poll plane has not yet joined+freed the old source's decode thread). Goes
        // false once reapRetired() (called by pureModeEnginePollTrackAdvance) frees it.
        [[nodiscard]] bool hasPendingReap() const noexcept;

        // Monotonic count of sources actually reaped (freed off-RT) by reapRetired(). Increments by
        // exactly one each time a parked retired source is joined+freed; a no-op reap (nothing
        // parked) does not bump it. A future change that stops polling would freeze this count even
        // as transitionCount() climbs — that is the leak the conformance test guards against.
        [[nodiscard]] uint64_t reapCount() const noexcept;

        // --- RT plane ---

        // RT render thread: drain interleaved float, straddling the A→B seam within this one call.
        // noexcept, allocation-free, lock-free. See the .cpp for the exact ordering rationale.
        uint32_t pullFloat(float* out, uint32_t frames, uint32_t channels) noexcept override;

      private:
        // One queued track: its source + a per-track rendered-frame counter (off-RT readable) and
        // a per-track seek base (off-RT only). Stored in a fixed array so a Track* is stable for
        // the lifetime of this GaplessSource (the atomics below hold Track*).
        struct Track
        {
            std::unique_ptr<FileDecodeSource> source;
            std::atomic<uint64_t> renderedFrames{0U};
            uint64_t seekBaseFrames{0U};
        };

        // Two stable slots are enough: at most one active + one armed at any instant. After a seam
        // the retired slot is reaped (its source freed) before it can be re-armed — armNext reaps
        // it first — so two never collides.
        static constexpr std::size_t kTrackSlots = 2U;
        std::array<Track, kTrackSlots> tracks_{};

        std::atomic<Track*> active_{nullptr};    // the track the RT thread is rendering
        std::atomic<Track*> armedNext_{nullptr}; // the one-slot pre-armed next track (or null)
        std::atomic<Track*> retired_{nullptr};   // a track parked at the last seam, awaiting reap
        std::atomic<uint64_t> transitions_{0U};  // completed seam count
        std::atomic<bool> ended_{false};         // playlist exhausted (true EOF, no armed next)
        std::atomic<uint64_t> reapCount_{0U};    // off-RT: sources actually reaped by reapRetired

        // Pick the free slot for arming the next track: the one that is neither active nor retired.
        // Returns nullptr if both non-active slots are occupied (should not happen — armNext
        // refuses a second arm and reaps the retired slot first). Non-const: it hands back a
        // mutable slot for the caller to populate.
        [[nodiscard]] Track* freeSlotForArm() noexcept;
    };
} // namespace AdaptiveSound
