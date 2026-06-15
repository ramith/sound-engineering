#ifndef ADAPTIVE_SOUND_DOUBLE_BUFFER_SNAPSHOT_H
#define ADAPTIVE_SOUND_DOUBLE_BUFFER_SNAPSHOT_H

#include "AudioConstants.h"
#include <array>
#include <atomic>
#include <utility>

namespace AdaptiveSound
{

    // Lock-free double-buffer for RT-safe parameter transport
    // Single producer (off-RT): publish(newState) writes inactive slot, swaps index with
    // release-store Single consumer (RT): acquireSnapshot() reads active slot with acquire-load
    // (zero-cost on ARM64)
    template <typename T> class alignas(kCacheLineBytes) DoubleBufferSnapshot
    {
      public:
        // Off-RT writer: publish new parameter state
        void publish(const T& newState) noexcept
        {
            const uint32_t inactive = 1U - activeIndex_.load(std::memory_order_acquire);
            slots_[inactive] = newState; // Plain struct copy (T is trivially copyable)
            activeIndex_.store(inactive, std::memory_order_release);
        }

        // RT reader: acquire current snapshot (one acquire-load, valid for entire buffer)
        const T& acquireSnapshot() const noexcept
        {
            const uint32_t idx = activeIndex_.load(std::memory_order_acquire);
            return slots_[idx];
        }

      private:
        std::array<T, 2> slots_ = {};
        alignas(kCacheLineBytes) std::atomic<uint32_t> activeIndex_{0};
    };

} // namespace AdaptiveSound

#endif // ADAPTIVE_SOUND_DOUBLE_BUFFER_SNAPSHOT_H
