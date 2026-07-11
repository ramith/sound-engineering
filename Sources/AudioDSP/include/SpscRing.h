#pragma once

// SpscRing — bounded, lock-free, allocation-free single-producer / single-consumer
// ring buffer (rigtorp/SPSCQueue design).
//
//   Producer (RT render thread): tryPushBlock — DROPS on full, never blocks.
//   Consumer (off-RT worker):    popBlock.
//
// Per Timur Doumler's real-time audio rule, the RT producer must never block,
// lock, or allocate; under starvation it drops (the caller records the shortfall).
//
// Design (rigtorp): power-of-two capacity (mask instead of modulo); one slot is
// left unused to distinguish full from empty; head_/tail_ are cache-line aligned
// and padded to avoid false sharing; each side keeps a LOCAL cached copy of the
// other index so the common case touches no shared cache line. Acquire on consume,
// release on publish.
//
// References:
//   - Erik Rigtorp, "Optimizing a ring buffer for throughput" / rigtorp/SPSCQueue.
//   - Timur Doumler, "Using locks in real-time audio processing, safely".

#include "AudioConstants.h"
#include <array>
#include <atomic>
#include <cstddef>

namespace AdaptiveSound
{

    template <typename T, std::size_t Capacity> class SpscRing
    {
        static_assert((Capacity & (Capacity - 1U)) == 0U, "Capacity must be a power of two");
        static_assert(Capacity >= 2U, "Capacity must be at least 2");
        static_assert(std::atomic<std::size_t>::is_always_lock_free,
                      "SpscRing requires lock-free size_t atomics for RT safety");

      public:
        SpscRing() = default;
        ~SpscRing() = default;
        SpscRing(const SpscRing&) = delete;
        SpscRing& operator=(const SpscRing&) = delete;
        SpscRing(SpscRing&&) = delete;
        SpscRing& operator=(SpscRing&&) = delete;

        // Producer (RT): write up to `count` elements; returns the number actually
        // written. A return < count means the ring is full and the remainder was
        // dropped. noexcept, no allocation, never blocks.
        [[nodiscard]] auto tryPushBlock(const T* src, std::size_t count) noexcept -> std::size_t
        {
            std::size_t tail = tail_.load(std::memory_order_relaxed);
            std::size_t written = 0U;
            while (written < count)
            {
                const std::size_t next = (tail + 1U) & kMask;
                if (next == cachedHead_)
                {
                    cachedHead_ = head_.load(std::memory_order_acquire);
                    if (next == cachedHead_)
                    {
                        break; // full
                    }
                }
                slots_[tail] = src[written];
                tail = next;
                ++written;
            }
            if (written != 0U)
            {
                tail_.store(tail, std::memory_order_release);
            }
            return written;
        }

        // Consumer (worker): read up to `count` elements into dst; returns the number
        // actually read (< count means the ring drained). noexcept.
        [[nodiscard]] auto popBlock(T* dst, std::size_t count) noexcept -> std::size_t
        {
            std::size_t head = head_.load(std::memory_order_relaxed);
            std::size_t read = 0U;
            while (read < count)
            {
                if (head == cachedTail_)
                {
                    cachedTail_ = tail_.load(std::memory_order_acquire);
                    if (head == cachedTail_)
                    {
                        break; // empty
                    }
                }
                dst[read] = slots_[head];
                head = (head + 1U) & kMask;
                ++read;
            }
            if (read != 0U)
            {
                head_.store(head, std::memory_order_release);
            }
            return read;
        }

        // True when the ring holds no elements (head == tail). RT-safe: acquire-loads both
        // indices, no allocation, no lock. Used by FileDecodeSource::exhausted() (the gapless
        // true-EOF predicate) on the RT consumer side. A producer may concurrently push, so a
        // false return is conservatively-correct (there is data); a true return means there was no
        // data at the observation point — combined with finished_ (no more will ever arrive) this
        // is a sound end-of-stream signal.
        [[nodiscard]] auto isEmpty() const noexcept -> bool
        {
            return head_.load(std::memory_order_acquire) == tail_.load(std::memory_order_acquire);
        }

        // Reset the ring to empty. NOT thread-safe: the caller MUST guarantee that NEITHER the
        // producer NOR the consumer is concurrently accessing the ring. Used by
        // FileDecodeSource::seek, which joins the decode thread (producer) and runs only when the
        // RT consumer is stopped, so it is the sole accessor when it discards buffered pre-seek
        // audio.
        void reset() noexcept
        {
            tail_.store(0U, std::memory_order_relaxed);
            head_.store(0U, std::memory_order_relaxed);
            cachedHead_ = 0U;
            cachedTail_ = 0U;
        }

      private:
        static constexpr std::size_t kMask = Capacity - 1U;

        std::array<T, Capacity> slots_{};

        // Producer-owned cache line: shared tail_ (release on push) + cached head.
        alignas(kCacheLineBytes) std::atomic<std::size_t> tail_{0U};
        std::size_t cachedHead_ = 0U;

        // Consumer-owned cache line: shared head_ (release on pop) + cached tail.
        alignas(kCacheLineBytes) std::atomic<std::size_t> head_{0U};
        std::size_t cachedTail_ = 0U;
    };

} // namespace AdaptiveSound
