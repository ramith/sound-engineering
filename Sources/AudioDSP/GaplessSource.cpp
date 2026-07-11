//
// GaplessSource.cpp — Pure-path gapless PureModeSource (Stage 2).
//
// CoreAudio-FREE / Obj-C-FREE. -fno-exceptions / -fno-rtti clean. Compiled into both the AudioDSP
// target and the C++ test harness (it owns FileDecodeSources, which are themselves CoreAudio glue,
// but GaplessSource itself touches no CoreAudio symbol).
//
// ============================================================================
// Concurrency / memory-ordering rationale (the seam)
// ============================================================================
//
// There is exactly ONE RT consumer (pullFloat) and a small set of off-RT control/poll callers.
// The shared state is four atomics: active_, armedNext_, retired_, transitions_ (+ ended_, and
// each Track's renderedFrames). The seam swap must (a) hand the RT thread the armed source exactly
// once, (b) never let the RT thread join/allocate, and (c) be race-safe against a concurrent
// clearNext().
//
// At the active track's TRUE end-of-file (finished_ ∧ ring drained ∧ no carry — exhausted()):
//
//   nxt = armedNext_.exchange(nullptr, acq_rel);
//
// The exchange is the linchpin. It atomically reads-and-clears the armed slot, so:
//   * if clearNext() runs concurrently and ALSO exchanges the slot, exactly one of {RT seam,
//     clearNext} observes the non-null pointer and the other observes null — there is no
//     double-adopt and no lost source (the loser leaves the slot empty; whoever read the pointer
//     owns the follow-up: the RT thread adopts it as active, clearNext joins+frees it).
//   * acq_rel: the acquire half makes the armed FileDecodeSource's prior off-RT construction
//     (open(), decode-thread spawn, format cache) visible to the RT thread before it pulls; the
//     release half publishes the RT thread's pre-seam writes to a concurrent clearNext.
//
// On the no-next branch (nxt == null) we set ended_ (release) and return the short fill; the
// engine zero-pads and the poll plane sees ended().
//
// On the take branch we publish the retirement + adoption with release stores:
//   retired_.store(cur, release);   // park the old active for off-RT reap (RT never joins)
//   active_.store(nxt, release);    // the RT thread itself is the only writer of active_ at a
//                                   // seam; subsequent pullFloats acquire-load it
//   ...pull B into the same buffer...
//   transitions_.fetch_add(1, acq_rel);  // publishes the completed seam to the poll plane
//
// active_ is written ONLY by setCurrent (off-RT, render stopped) and by pullFloat (RT). Those
// never overlap (setCurrent's precondition), so the RT thread is the sole writer of active_ while
// running and the acquire-load at the top of every pullFloat sees its own prior release-store.
//
// retired_ is written by the RT thread (release) and read+cleared by reapRetired (off-RT). Only
// one track can be parked at a time: a second seam cannot occur until reapRetired frees the slot
// (armNext refuses to arm into the not-yet-reaped slot), so retired_ never overwrites a live
// pending reap.
//
// renderedFrames is per-Track: written by the RT thread (release fetch_add), read by the poll
// plane (acquire). seekBaseFrames is off-RT only (set by setCurrent/resetActiveBase while the
// position is read off-RT; the position read tolerates the benign race of base-vs-counter the
// same way the prior CountingSource did).
//

#include "include/GaplessSource.h"

#include <algorithm>
#include <atomic>
#include <cassert>
#include <cstdint>
#include <memory>
#include <utility>

namespace AdaptiveSound
{
    bool sameRateGaplessCompatible(const FileDecodeSource& cur,
                                   const FileDecodeSource& next) noexcept
    {
        constexpr double kRateToleranceHz = 1.0;
        const double rateDelta = cur.sampleRate() - next.sampleRate();
        const double absRateDelta = (rateDelta < 0.0) ? -rateDelta : rateDelta;
        return absRateDelta <= kRateToleranceHz && cur.channels() == next.channels() &&
               cur.sourceIsFloat() == next.sourceIsFloat() &&
               cur.sourceBitsPerChannel() == next.sourceBitsPerChannel();
    }

    void GaplessSource::setCurrent(std::unique_ptr<FileDecodeSource> source) noexcept
    {
        // PRECONDITION: render is stopped — we are the sole accessor of every slot/atomic here.
        // Tear the session down to a clean slate, then install `source` into slot 0.
        active_.store(nullptr, std::memory_order_relaxed);
        armedNext_.store(nullptr, std::memory_order_relaxed);
        retired_.store(nullptr, std::memory_order_relaxed);
        transitions_.store(0U, std::memory_order_relaxed);
        ended_.store(false, std::memory_order_relaxed);
        reapCount_.store(0U, std::memory_order_relaxed);

        for (Track& track : tracks_)
        {
            track.source.reset();
            track.renderedFrames.store(0U, std::memory_order_relaxed);
            track.seekBaseFrames = 0U;
        }

        Track& slot = tracks_[0];
        slot.source = std::move(source);
        slot.renderedFrames.store(0U, std::memory_order_relaxed);
        slot.seekBaseFrames = 0U;
        // Release: publish the slot's contents before the RT thread can acquire-load active_.
        active_.store(&slot, std::memory_order_release);
    }

    GaplessSource::Track* GaplessSource::freeSlotForArm() noexcept
    {
        // Callable only while armedNext_ == nullptr: with no slot armed the RT thread cannot be
        // mid-seam (the seam straddle only fires on a non-null armed pointer), so the slot this
        // returns is free of any concurrent RT access.
        assert(armedNext_.load(std::memory_order_acquire) == nullptr);
        const Track* active = active_.load(std::memory_order_acquire);
        const Track* retired = retired_.load(std::memory_order_acquire);
        Track* const slot = std::ranges::find_if(tracks_,
                                                 [active, retired](const Track& track)
                                                 { return &track != active && &track != retired; });
        return slot != tracks_.end() ? slot : nullptr;
    }

    bool GaplessSource::armNext(std::unique_ptr<FileDecodeSource> source) noexcept
    {
        if (source == nullptr)
        {
            return false;
        }
        // One-slot: refuse a second arm. `source` was moved into this by-value parameter on the
        // call, so on this early return its dtor frees the refused FileDecodeSource (joining its
        // decode thread) off-RT — exactly what we want.
        if (armedNext_.load(std::memory_order_acquire) != nullptr)
        {
            return false;
        }
        Track* slot = freeSlotForArm();
        if (slot == nullptr)
        {
            return false; // both non-active slots occupied (retired not yet reaped)
        }
        slot->source = std::move(source);
        slot->renderedFrames.store(0U, std::memory_order_relaxed);
        slot->seekBaseFrames = 0U;
        // Release: publish the armed source's construction before the RT thread can adopt it via
        // the seam exchange (acq_rel) → active_.
        armedNext_.store(slot, std::memory_order_release);
        return true;
    }

    void GaplessSource::clearNext() noexcept
    {
        // Race the RT seam claim: exactly one of {this, the RT seam exchange} reads the non-null
        // pointer. If we win, the slot is ours to tear down; if the RT thread already adopted it,
        // we observe null and do nothing (the adopted track is now active / will be retired).
        Track* slot = armedNext_.exchange(nullptr, std::memory_order_acq_rel);
        if (slot != nullptr)
        {
            slot->source.reset(); // joins the dropped source's decode thread off-RT
            slot->renderedFrames.store(0U, std::memory_order_relaxed);
            slot->seekBaseFrames = 0U;
        }
    }

    void GaplessSource::reapRetired() noexcept
    {
        // Acquire-load + clear so a fresh seam can park the next retirement. The RT thread parked
        // this with a release store, so the source's last RT use happens-before this reset.
        Track* slot = retired_.exchange(nullptr, std::memory_order_acq_rel);
        if (slot != nullptr)
        {
            slot->source.reset(); // joins the retired source's decode thread off-RT
            slot->renderedFrames.store(0U, std::memory_order_relaxed);
            slot->seekBaseFrames = 0U;
            // Observability (off-RT only): record that a parked source was actually reaped, so the
            // conformance suite can pin the poll-reaps-source contract (a future change that stops
            // polling would freeze this even as transitions_ climbs → leaked decode threads).
            reapCount_.fetch_add(1U, std::memory_order_release);
        }
    }

    void GaplessSource::resetActiveBase(uint64_t frames) noexcept
    {
        Track* active = active_.load(std::memory_order_acquire);
        if (active != nullptr)
        {
            active->seekBaseFrames = frames;
            active->renderedFrames.store(0U, std::memory_order_release);
        }
    }

    FileDecodeSource* GaplessSource::activeSource() const noexcept
    {
        const Track* active = active_.load(std::memory_order_acquire);
        return (active != nullptr) ? active->source.get() : nullptr;
    }

    uint64_t GaplessSource::transitionCount() const noexcept
    {
        return transitions_.load(std::memory_order_acquire);
    }

    uint64_t GaplessSource::renderedFramesCurrent() const noexcept
    {
        const Track* active = active_.load(std::memory_order_acquire);
        if (active == nullptr)
        {
            return 0U;
        }
        return active->seekBaseFrames + active->renderedFrames.load(std::memory_order_acquire);
    }

    double GaplessSource::currentSampleRate() const noexcept
    {
        const Track* active = active_.load(std::memory_order_acquire);
        return (active != nullptr && active->source != nullptr) ? active->source->sampleRate()
                                                                : 0.0;
    }

    bool GaplessSource::ended() const noexcept
    {
        return ended_.load(std::memory_order_acquire);
    }

    bool GaplessSource::hasPendingReap() const noexcept
    {
        return retired_.load(std::memory_order_acquire) != nullptr;
    }

    uint64_t GaplessSource::reapCount() const noexcept
    {
        return reapCount_.load(std::memory_order_acquire);
    }

    uint32_t GaplessSource::pullFloat(float* out, uint32_t frames, uint32_t channels) noexcept
    {
        Track* cur = active_.load(std::memory_order_acquire);
        if (cur == nullptr || cur->source == nullptr)
        {
            return 0U; // no source — the engine emits a full buffer of silence
        }

        const uint32_t produced = cur->source->pullFloat(out, frames, channels);
        cur->renderedFrames.fetch_add(produced, std::memory_order_release);
        if (produced == frames)
        {
            return produced; // full fill — common case, no seam
        }

        // Short fill. Distinguish a TRANSIENT underrun (ring momentarily empty but the decoder is
        // still running) from the track's TRUE end-of-file. exhausted() is the safe true-EOF
        // predicate: finished_ flips ONLY after the decode thread's final pushAll, so a true EOF
        // means there is genuinely nothing more for this track.
        if (!cur->source->exhausted())
        {
            return produced; // HOLD — the engine zero-pads the remainder this callback
        }

        // True EOF. Try to adopt the armed-next source. The exchange guarantees exactly one
        // consumer of the armed pointer (no double-adopt if clearNext races).
        Track* nxt = armedNext_.exchange(nullptr, std::memory_order_acq_rel);
        if (nxt == nullptr)
        {
            ended_.store(true, std::memory_order_release); // playlist end
            return produced;
        }

        // Seam straddle: retire the old active off-RT (RT NEVER joins), adopt the next, and pull
        // its head into the SAME host buffer right behind A's tail → sample-accurate concatenation.
        retired_.store(cur, std::memory_order_release);
        active_.store(nxt, std::memory_order_release);

        // RT-path insurance: mirror the active-track guard. A slot with a null source can never be
        // pulled; treat it as playlist end rather than dereferencing a null pointer on the RT
        // thread.
        if (nxt->source == nullptr)
        {
            ended_.store(true, std::memory_order_release);
            return produced;
        }

        float* const seamOut = out + (static_cast<std::size_t>(produced) * channels);
        const uint32_t more = nxt->source->pullFloat(seamOut, frames - produced, channels);
        nxt->renderedFrames.fetch_add(more, std::memory_order_release);
        transitions_.fetch_add(1U, std::memory_order_acq_rel);
        return produced + more;
    }
} // namespace AdaptiveSound
