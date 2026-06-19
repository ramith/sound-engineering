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
// SAME-RATE ONLY: this source does no resampling. The control plane (the C-ABI bridge) must
// pre-check sameRateGaplessCompatible() before arming the next track; a rate/format mismatch is
// handled off-RT (drop + signal "needs reconfigure"), never at the seam.
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

        // Arm the next source to play gaplessly at the active track's true EOF. The caller MUST
        // have pre-checked sameRateGaplessCompatible() against the active track. Takes ownership by
        // value: on EITHER outcome `source` has been moved-from. One-slot — refuses a second arm
        // while one is pending (returns false; the refused source is freed off-RT as the parameter
        // goes out of scope, joining its decode thread). Returns true on success.
        [[nodiscard]] bool armNext(std::unique_ptr<FileDecodeSource> source) noexcept;

        // Clear the armed-next slot (e.g. the user cleared the on-deck track). Joins the dropped
        // source's decode thread off-RT. Safe while render runs: the exchange races the RT seam
        // claim so exactly one side wins (no double-adopt, no leak).
        void clearNext() noexcept;

        // Join + free a source retired at the last seam, off-RT. Call from the poll plane
        // (pureModeEnginePollTrackAdvance). No-op when nothing is parked.
        void reapRetired() noexcept;

        // Re-base the ACTIVE track's per-track frame counter after a seek so position display
        // restarts from `frames` (the seek target, in active-track frames). Does NOT touch the
        // armed next or the transition count.
        void resetActiveBase(uint64_t frames) noexcept;

        // Borrow the ACTIVE track's source for a control-plane operation (seek, or a compatibility
        // check against a candidate next track). Returns nullptr when there is no active track.
        // The returned pointer is owned by this GaplessSource; the caller MUST NOT delete it and
        // MUST NOT retain it past the control-plane operation. For a seek the caller is responsible
        // for the FileDecodeSource::seek precondition (render stopped).
        [[nodiscard]] FileDecodeSource* activeSource() const noexcept;

        // --- Poll plane (off-RT) ---

        // Monotonic count of completed seams. An increase means the armed-next became active.
        [[nodiscard]] uint64_t transitionCount() const noexcept;

        // Frames the ACTIVE track has rendered since it became active (re-zeroes at each seam).
        [[nodiscard]] uint64_t renderedFramesCurrent() const noexcept;

        // Sample rate of the ACTIVE track (Hz). 0 when there is no active track.
        [[nodiscard]] double currentSampleRate() const noexcept;

        // True once the active track hit its true EOF with no armed next (playlist exhausted).
        [[nodiscard]] bool ended() const noexcept;

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
        // the retired slot is reaped (its source freed) before it can be re-armed, so two never
        // collides.
        static constexpr std::size_t kTrackSlots = 2U;
        std::array<Track, kTrackSlots> tracks_{};

        std::atomic<Track*> active_{nullptr};    // the track the RT thread is rendering
        std::atomic<Track*> armedNext_{nullptr}; // the one-slot pre-armed next track (or null)
        std::atomic<Track*> retired_{nullptr};   // a track parked at the last seam, awaiting reap
        std::atomic<uint64_t> transitions_{0U};  // completed seam count
        std::atomic<bool> ended_{false};         // playlist exhausted (true EOF, no armed next)

        // Pick the free slot for arming the next track: the one that is neither active nor retired.
        // Returns nullptr if both non-active slots are occupied (should not happen — armNext
        // refuses a second arm and reapRetired frees the retired slot first). Non-const: it hands
        // back a mutable slot for the caller to populate.
        [[nodiscard]] Track* freeSlotForArm() noexcept;
    };
} // namespace AdaptiveSound
