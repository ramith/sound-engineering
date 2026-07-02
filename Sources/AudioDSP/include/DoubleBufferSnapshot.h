#ifndef ADAPTIVE_SOUND_DOUBLE_BUFFER_SNAPSHOT_H
#define ADAPTIVE_SOUND_DOUBLE_BUFFER_SNAPSHOT_H

#include "AudioConstants.h"
#include <array>
#include <atomic>
#include <cstddef>
#include <cstdint>
#include <cstring>
#include <type_traits>

namespace AdaptiveSound
{

    // Lock-free single-producer / single-consumer parameter snapshot (RT-safe transport).
    //
    // ## Why not a plain 2-slot double buffer (the previous design — S6 finding RACE-1)
    //
    // The earlier version returned `const T&` into an active slot and the RT reader held that
    // reference for the WHOLE render block. Two off-RT `publish()` calls during one block (e.g. an
    // EQ drain then an intensity drain landing back-to-back on the Realizer's serial queue, or a
    // fast slider drag) flip the active index twice; the second publish then writes the very slot
    // the reader still references → a TORN read that mixes two parameter generations (or tears a
    // single biquad set) for one block → a click / transient instability. This was a genuine data
    // race, not just staleness.
    //
    // ## Design (seqlock with an ATOMIC payload — wait-free reader, TSan-clean)
    //
    // The producer writes the payload as relaxed atomic words bracketed by an odd/even version
    // counter (`seq_`, release). The consumer copies the words (relaxed) between two acquire-loads
    // of `seq_` and accepts the copy only when both loads are equal and even — i.e. no publish
    // straddled the copy. Every shared access (`seq_` and the payload `words_`) is a `std::atomic`,
    // so a concurrent producer write / consumer read is well-defined (not UB) and ThreadSanitizer
    // reports no race — unlike a fence-based seqlock, whose non-atomic payload TSan flags.
    //
    // ## RT-safety
    //
    // The consumer is WAIT-FREE: at most `kMaxSnapshotReadRetries` copies, no lock, no allocation,
    // no unbounded spin. On the (astronomically rare) event that every attempt is straddled, it
    // returns false and the caller keeps its previous good snapshot — parameters are ramped, so one
    // extra block of a one-generation-stale-but-consistent value is inaudible. Single producer:
    // `publish()` must be driven from ONE control thread (the Realizer's serial queue).
    //
    // The historical name `DoubleBufferSnapshot` is retained (it is the RT parameter snapshot type
    // referenced throughout the kernel); the mechanism is now the seqlock described above.
    template <typename T> class alignas(kCacheLineBytes) DoubleBufferSnapshot
    {
        static_assert(std::is_trivially_copyable<T>::value,
                      "DoubleBufferSnapshot<T> requires a trivially-copyable T (it is byte-copied "
                      "through atomic words, and the reader re-copies on a straddled retry).");
        static_assert(sizeof(T) % sizeof(uint64_t) == 0,
                      "DoubleBufferSnapshot<T> requires sizeof(T) to be a multiple of 8 so the "
                      "payload maps exactly onto 64-bit atomic words (TargetState is 320 B).");

        static constexpr std::size_t kWords = sizeof(T) / sizeof(uint64_t);

        // Bounded read-retry budget. A single rarely-publishing producer needs ~0 retries; the cap
        // makes the reader wait-free even under a pathological publish storm (fall back to last good).
        static constexpr int kMaxSnapshotReadRetries = 8;

      public:
        // Seed the storage with a DEFAULT-constructed T so a consumer that copies BEFORE any
        // publish observes T's default member values (identity params: intensityLinear=1.0,
        // masterGainLinear=1.0, …), NOT zeroed bytes. The previous double-buffer value-initialized
        // its slots to a default T; preserving that is load-bearing — the golden master is the
        // DEFAULT full-chain output (which needs intensityLinear=1.0), and zeroed bytes would make
        // an unpublished read bypass to raw passthrough and change the hash.
        DoubleBufferSnapshot() noexcept { publish(T{}); }

        // Off-RT writer (SINGLE producer): publish a new snapshot.
        // `seq_` is odd while the word stores are in flight, even once a consistent generation is
        // committed. The even store is release so a consumer that acquire-loads it sees every word.
        void publish(const T& newState) noexcept
        {
            std::array<uint64_t, kWords> tmp{};
            std::memcpy(tmp.data(), &newState, sizeof(T));

            const uint64_t begin = seq_.load(std::memory_order_relaxed) + 1U; // -> odd
            seq_.store(begin, std::memory_order_release);
            for (std::size_t i = 0; i < kWords; ++i)
            {
                words_[i].store(tmp[i], std::memory_order_relaxed);
            }
            seq_.store(begin + 1U, std::memory_order_release); // -> even (published)
        }

        // RT reader (SINGLE consumer): copy the current snapshot into `out`.
        // Returns true on a consistent (non-torn) copy; false when a publish straddled every attempt
        // within the retry budget (the caller then keeps its previous snapshot). Wait-free.
        [[nodiscard]] bool tryCopySnapshot(T& out) const noexcept
        {
            for (int attempt = 0; attempt < kMaxSnapshotReadRetries; ++attempt)
            {
                const uint64_t before = seq_.load(std::memory_order_acquire);
                if ((before & 1U) != 0U)
                {
                    continue; // a publish is mid-flight; retry (bounded)
                }
                std::array<uint64_t, kWords> tmp{};
                for (std::size_t i = 0; i < kWords; ++i)
                {
                    tmp[i] = words_[i].load(std::memory_order_relaxed);
                }
                const uint64_t after = seq_.load(std::memory_order_acquire);
                if (before == after)
                {
                    std::memcpy(&out, tmp.data(), sizeof(T));
                    return true; // no publish straddled the copy → consistent
                }
            }
            return false; // contended beyond the budget; caller retains its last good snapshot
        }

      private:
        std::array<std::atomic<uint64_t>, kWords> words_ = {};
        alignas(kCacheLineBytes) std::atomic<uint64_t> seq_{0};
    };

} // namespace AdaptiveSound

#endif // ADAPTIVE_SOUND_DOUBLE_BUFFER_SNAPSHOT_H
