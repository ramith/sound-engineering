#ifndef ADAPTIVE_SOUND_DOUBLE_BUFFER_SNAPSHOT_H
#define ADAPTIVE_SOUND_DOUBLE_BUFFER_SNAPSHOT_H

#include "AudioConstants.h"
#include <array>
#include <atomic>
#include <cstdint>
#include <cstring>
#include <type_traits>

namespace AdaptiveSound
{

    // Wait-free single-producer / single-consumer parameter snapshot (RT-safe transport).
    //
    // ## Why this replaces the fence-based seqlock (settled by research + 2-expert review)
    //
    // The previous design was a seqlock whose synchronization rode on a standalone
    // `std::atomic_thread_fence`. That is correct on ARM64, but ThreadSanitizer does NOT model
    // standalone fences (the `__tsan_atomic_thread_fence` gap): the instrumented binary is
    // effectively barrier-stripped, so TSan sees REAL torn reads and `make tsan` flakes red. This
    // implementation carries ALL synchronization on ONE named atomic via acquire/release only — no
    // standalone fence anywhere — so TSan both models the ordering AND lowers it to real ARM
    // barriers (`stlr`/`ldar`/`ldaxr+stlxr`).
    //
    // ## Design: wait-free SPSC triple buffer + one atomic control word
    //
    //   - `slots_[3]`  three PLAIN (non-atomic) T slots. Each slot is only ever touched by ONE
    //                  thread at a time; ownership + happens-before are handed off by an
    //                  acquire/release exchange on the single control atomic. The payload move is
    //                  therefore a plain `memcpy` — no atomic words, no seqlock, no reader retry.
    //   - `control_`   one `std::atomic<uint32_t>`: low 2 bits = the READY slot index (0..2),
    //                  bit 2 = FRESH flag (a publish has landed since the consumer's last claim).
    //   - `writeIndex_`  producer-owned plain member: the slot the producer writes next.
    //   - `readIndex_`   consumer-owned plain member: the slot the consumer holds (its last good).
    //
    // At every instant the three indices {writeIndex_, readIndex_, index(control_)} are a
    // PERMUTATION of {0,1,2} — all distinct (the "3-slot SPSC invariant", proven below). Hence the
    // producer's write slot is never the consumer's read slot, and the ready slot in `control_` is
    // a parked buffer touched by neither thread's payload access.
    //
    // ## PRECONDITION: exactly one producer thread and one consumer thread (SPSC)
    //
    // `publish()` must be driven from ONE control thread (the Realizer's serial queue).
    // `tryCopySnapshot()` must be driven from ONE RT thread. `writeIndex_` is mutated only by the
    // producer, `readIndex_` only by the consumer, and `control_` is the sole cross-thread word.
    // Two producers or two consumers would break the invariant and race — not supported.
    //
    // ## PROOF
    //
    // (0) 3-slot SPSC permutation invariant. Model the logical state as (W,R,C) =
    //     (writeIndex_, readIndex_, index(control_)). Initially (0,1,2) — distinct. `control_` is
    //     mutated ONLY by the two `exchange`s below, which the atomic's modification order totally
    //     orders. `publish` does `C := W` (via exchange) then `W := oldC`: a transposition of W and
    //     C. A fresh `tryCopySnapshot` does `C := R` (via exchange) then `R := oldC`: a
    //     transposition of R and C. Each RMW reads the LIVE C (not a stale copy), so every
    //     transaction is a transposition regardless of interleaving; a transposition of a
    //     permutation is a permutation. Therefore {W,R,C} stay pairwise distinct — in particular
    //     W != R — after every exchange. The only skew is the tiny window between an exchange and
    //     its trailing plain index update, during which NO slot memory is touched (see below), so
    //     the skew never coincides with a payload access.
    //
    // (1) Accepted copy is never torn / mixed-generation. The producer touches slot memory ONLY in
    //     the `memcpy` sequenced-BEFORE its release-exchange; the consumer touches slot memory ONLY
    //     in the `memcpy` sequenced-AFTER its acquire-exchange. A slot the consumer claims is the
    //     index the producer released; the consumer's acquire-exchange reads the value the
    //     producer's release-exchange wrote into `control_`, so the two RMWs stand in a
    //     synchronizes-with relation ([atomics.order]: an acquire RMW that reads a release store's
    //     value synchronizes with it). Thus the producer's whole-struct `memcpy` into that slot
    //     happens-before the consumer's `memcpy` out of it — the reader sees a single, complete
    //     generation. And because W != R at all times, the producer is never writing the slot the
    //     consumer reads. No tearing, no mixed generation, no UB. (The last-good path re-reads the
    //     consumer's OWN slot, which the producer never writes — also race-free.)
    //
    // (2) The reader is WAIT-FREE. `tryCopySnapshot` executes a bounded, constant number of steps:
    //     one acquire load, at most one acquire exchange, one `memcpy`. No loop, no retry, no lock,
    //     no allocation, no CAS spin. It ALWAYS returns true (fresh -> newest generation; not fresh
    //     -> last good). The `bool` is retained only for API compatibility with existing callers.
    //
    // (3) No standalone fence is needed. Every cross-thread ordering edge is carried by an operation
    //     ON `control_`: BOTH `exchange`s are `acq_rel` (release publishes / acquires reuse — PROOF
    //     (1) and (5)), plus the reader's `load(acquire)` peek. A release operation orders all prior
    //     accesses before it; a synchronizing acquire orders all later accesses after it. No
    //     `std::atomic_thread_fence` — so TSan models every edge exactly.
    //
    // (4) Correct on weakly-ordered ARM64. The C++ release/acquire synchronizes-with edge is honored
    //     on every conforming platform, including weakly-ordered ARM64, where the release store/RMW
    //     lowers to `stlr`/`stlxr` and the acquire load/RMW to `ldar`/`ldaxr` — real hardware
    //     barriers that forbid the reordering a torn read would require.
    //
    // (5) No write-after-read race on slot REUSE — why BOTH exchanges are `acq_rel`, not
    //     release/acquire. The buffers cycle bidirectionally: a slot the CONSUMER releases (its
    //     exchange writes its old `readIndex_` into `control_`) is later handed to the PRODUCER (the
    //     producer's exchange reads that value → `writeIndex_`) and OVERWRITTEN on the next publish.
    //     The consumer's reads of that slot are sequenced-before its exchange; for the producer's
    //     overwrite not to race them we need consumer-read →sw→ producer-write, i.e. the consumer's
    //     exchange must RELEASE those reads and the producer's exchange must ACQUIRE them. So each
    //     exchange is BOTH a release (of the reuse edge for the OTHER thread) and an acquire (of the
    //     publish/reuse edge from it) — `acq_rel`. Release/acquire-only leaves this WAR edge
    //     unsynchronized: a real data race under the C++ memory model (and on ARM64), merely rare
    //     enough to slip a handful of TSan runs. This is the subtle edge; the research + expert
    //     review caught it, so both RMWs are `acq_rel`.
    //
    // The historical name `DoubleBufferSnapshot` is retained (it is THE RT parameter-snapshot type
    // referenced throughout the kernel); the mechanism is now the triple buffer described above.
    template <typename T> class alignas(kCacheLineBytes) DoubleBufferSnapshot
    {
        static_assert(std::is_trivially_copyable_v<T>,
                      "DoubleBufferSnapshot<T> requires a trivially-copyable T: each slot is "
                      "published/consumed by a plain memcpy under exclusive single-thread "
                      "ownership.");
        // NOTE: the previous `sizeof(T) % 8 == 0` assert is deliberately GONE — the payload is no
        // longer marshaled through 64-bit atomic words, so T has no size-multiple requirement.

        // control_ bit layout: [1:0] = ready slot index (0..2), [2] = fresh flag.
        static constexpr uint32_t kIndexMask = 0x3U;
        static constexpr uint32_t kFreshBit = 0x4U;

        static constexpr uint32_t packControl(uint32_t index, bool fresh) noexcept
        {
            return (index & kIndexMask) | (fresh ? kFreshBit : 0U);
        }
        static constexpr uint32_t indexOf(uint32_t control) noexcept
        {
            return control & kIndexMask;
        }
        static constexpr bool isFresh(uint32_t control) noexcept
        {
            return (control & kFreshBit) != 0U;
        }

      public:
        // Seed EVERY slot with a DEFAULT-constructed T so that a consumer copying BEFORE any publish
        // — via either the fresh-claim path or the last-good path — observes T's default member
        // values (identity params: intensityLinear=1.0, masterGainLinear=1.0, …), NOT zeroed bytes.
        // This is load-bearing: the golden master is the DEFAULT full-chain output, and zeroed bytes
        // would bypass to raw passthrough and change the hash. `slots_{}` value-initializes each
        // element, invoking T's default member initializers. The trailing publish rotates the buffer
        // once and sets the fresh flag so the first consumer claim picks up a defined ready slot.
        DoubleBufferSnapshot() noexcept
        {
            publish(T{});
        }

        // Off-RT writer (SINGLE producer). Publish a new snapshot.
        void publish(const T& newState) noexcept
        {
            // The producer exclusively owns slots_[writeIndex_] (writeIndex_ != readIndex_ always,
            // PROOF (0)), so this whole-struct copy races with nothing.
            std::memcpy(&slots_[writeIndex_], &newState, sizeof(T));

            // ACQ_REL-exchange: atomically install writeIndex_ as the new ready slot (fresh=1) and
            // read back the previously-ready index. RELEASE makes the memcpy above visible to the
            // consumer's acquire-exchange that later claims this slot (the publish edge, PROOF (1)).
            // ACQUIRE is ALSO required (NOT a mere superset): the returned index may be a slot the
            // CONSUMER just released (the buffers cycle bidirectionally), which this producer will
            // OVERWRITE on its next publish — a write-after-read against the consumer's prior reads of
            // that slot. The acquire synchronizes-with the consumer's release-exchange so those reads
            // happen-before the reuse (PROOF (5)). By PROOF (0) the returned index is neither the
            // ready slot nor the consumer's current read slot.
            const uint32_t previous =
                control_.exchange(packControl(writeIndex_, true), std::memory_order_acq_rel);
            writeIndex_ = indexOf(previous);
        }

        // RT reader (SINGLE consumer). Copy the current snapshot into `out`. WAIT-FREE.
        //
        // Returns true on every call (API-compat with the former seqlock, whose bool signaled a
        // straddle): fresh -> the newest published generation; not fresh -> the last good snapshot
        // (parameters are ramped, so one block of a consistent one-generation-stale value is
        // inaudible). NON-const: it advances buffer ownership (readIndex_/control_).
        [[nodiscard]] bool tryCopySnapshot(T& out) noexcept
        {
            // ACQUIRE-load the control word to read the fresh flag. (The load-bearing acquire is the
            // exchange below; this load's acquire is a harmless, conventional superset.)
            const uint32_t control = control_.load(std::memory_order_acquire);
            if (isFresh(control))
            {
                // Claim the ready slot: ACQ_REL-exchange installs our current readIndex_ as the new
                // ready slot with fresh cleared, and hands back the previously-ready index. ACQUIRE
                // synchronizes-with the producer's release-exchange that published that slot, so the
                // producer's memcpy into it happens-before our memcpy out of it (PROOF (1)). RELEASE
                // is ALSO required (NOT a mere superset): this exchange hands our current readIndex_
                // back to the producer as a reusable slot, and we have just finished READING it on
                // prior calls; the release publishes those reads so the producer's later acquire-
                // exchange — and its subsequent overwrite — happen-after them (the WAR edge, PROOF
                // (5)). The RMW reads the LIVE control value, so even if the producer published again
                // between the load and here, we claim the freshest ready slot (PROOF (0)).
                const uint32_t previous =
                    control_.exchange(packControl(readIndex_, false), std::memory_order_acq_rel);
                readIndex_ = indexOf(previous);
            }
            // Copy the consumer-owned slot — freshly claimed above, or the last-good slot when not
            // fresh. The producer never writes readIndex_ (writeIndex_ != readIndex_), so this copy
            // races with nothing.
            std::memcpy(&out, &slots_[readIndex_], sizeof(T));
            return true;
        }

      private:
        // Three plain slots. Value-initialized to default T (identity params) — see the ctor.
        std::array<T, 3> slots_{};

        // The single cross-thread word, on its OWN cache line so the payload slots never falsely
        // share with it. writeIndex_/readIndex_ trail it on the same line: both are already touched
        // on every operation that touches control_ (the inherent SPSC handoff point), so co-locating
        // them adds no traffic beyond control_'s own contention. Initial state (W,R,C)=(0,1,2) is a
        // valid permutation; fresh starts clear (the ctor's publish sets it).
        alignas(kCacheLineBytes) std::atomic<uint32_t> control_{packControl(2U, false)};
        uint32_t writeIndex_{0U}; // producer-owned
        uint32_t readIndex_{1U};  // consumer-owned
    };

} // namespace AdaptiveSound

#endif // ADAPTIVE_SOUND_DOUBLE_BUFFER_SNAPSHOT_H
