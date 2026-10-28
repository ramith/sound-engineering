#pragma once

//
// WorkerParking.h — an analysis worker's sleep while nothing reaches it (council C-46 / KI-UI-03;
// DSP-09). The kernel's ring-fed worker — the causal loudness estimate (CausalLoudnessTap; the session
// normaliser's meter went with the normaliser, R1.1-B) — used to poll their ring forever, every 5–50 ms, also while
// playback was paused, on the bit-perfect path and with leveling off: about 200 wake-ups a second for
// nothing. Now a worker NAPS briefly while audio flows (its ring empties between render blocks) and,
// after a stretch longer than any render interval with nothing, PARKS: it blocks with no timeout and
// wakes only when it is handed something, or asked to stop.
//
// The producer (the render thread, real-time) calls notify() after each push: one atomic add, one
// load, and a futex wake only while the worker is parked — once per resume, never in steady playback.
// A control thread calls it after a change the worker must act on (an estimate started).
//
// For tests and diagnostics, any thread may ask whether the worker is parked with nothing handed to it
// (`isParked`) and how many times it has come back from a nap or a park (`wakeCount`): a parked worker's
// count stands still until it is handed work. Only the worker writes these; the render thread never
// touches them.
//
// No lost wake-up, carried on named sequentially consistent atomics (no standalone fence, so
// ThreadSanitizer models every edge): the worker sets `parked_`, reads `wakes_`, then checks for work
// once more; the producer publishes its work, bumps `wakes_`, then reads `parked_`. In their single
// total order, either the bump comes before the worker's read — whose acquire then sees the published
// work, so it does not wait — or after it: then the producer's read of `parked_` sees it set and wakes
// the worker (whose `wait` also returns at once once `wakes_` has moved).
//

#include <atomic>
#include <chrono>
#include <cstdint>
#include <stop_token>
#include <thread>

namespace AdaptiveSound
{
    class WorkerParking
    {
      public:
        // `nap`: the worker's sleep while audio is expected; after `parkAfter` of finding nothing it
        // parks. Keep `parkAfter` above the longest render interval (4096 frames at 22.05 kHz is
        // 186 ms), so steady playback never parks.
        WorkerParking(std::chrono::milliseconds nap, std::chrono::milliseconds parkAfter) noexcept
            : nap_(nap), napsBeforeParking_(static_cast<uint32_t>(parkAfter / nap))
        {
        }

        // Worker: it found nothing to do. Nap, or — idle long enough — park until `hasWork()` or a
        // stop. `hasWork` is the worker's own acquire check (its ring not empty, say).
        template <typename HasWork>
        void idle(const std::stop_token& stopToken, const HasWork& hasWork) noexcept
        {
            if (idleNaps_ < napsBeforeParking_)
            {
                ++idleNaps_;
                std::this_thread::sleep_for(nap_);
                countWake();
                return;
            }
            park(stopToken, hasWork);
        }

        // Worker: block until `hasWork()` holds or a stop is asked (no nap first).
        template <typename HasWork>
        void park(const std::stop_token& stopToken, const HasWork& hasWork) noexcept
        {
            parked_.store(true, std::memory_order_seq_cst);
            const uint32_t seen = wakes_.load(std::memory_order_seq_cst);
            if (!hasWork() && !stopToken.stop_requested())
            {
                waitingAt_.store(seen, std::memory_order_relaxed);
                waiting_.store(true, std::memory_order_release);
                wakes_.wait(seen, std::memory_order_seq_cst);
                waiting_.store(false, std::memory_order_relaxed);
            }
            parked_.store(false, std::memory_order_relaxed);
            countWake();
        }

        // Worker: it found work — the next idle stretch naps again before it parks.
        void worked() noexcept
        {
            idleNaps_ = 0U;
        }

        // Producer (real-time) or control thread: something for the worker, published before this
        // call. Also the wake-up for a stop (from the worker's std::stop_callback).
        void notify() noexcept
        {
            wakes_.fetch_add(1U, std::memory_order_seq_cst);
            if (parked_.load(std::memory_order_seq_cst))
            {
                wakes_.notify_one();
            }
        }

        // Any thread (tests, diagnostics): whether the worker is parked — blocked with nothing handed to
        // it since it began to wait, so it stays parked until something is.
        [[nodiscard]] bool isParked() const noexcept
        {
            return waiting_.load(std::memory_order_acquire) &&
                   wakes_.load(std::memory_order_acquire) ==
                       waitingAt_.load(std::memory_order_relaxed);
        }

        // Any thread (tests, diagnostics): how many times the worker has come back from a nap or a park.
        [[nodiscard]] uint64_t wakeCount() const noexcept
        {
            return wakeCount_.load(std::memory_order_relaxed);
        }

      private:
        // Worker only: it is back from a nap or a park.
        void countWake() noexcept
        {
            wakeCount_.fetch_add(1U, std::memory_order_relaxed);
        }

        std::atomic<uint64_t> wakeCount_{0U}; // diagnostics, written by the worker alone
        std::atomic<uint32_t> wakes_{0U};
        std::atomic<uint32_t> waitingAt_{0U}; // diagnostics: `wakes_` when the worker began to wait
        std::atomic<bool> parked_{false};
        std::atomic<bool> waiting_{false}; // diagnostics: the worker is in (or entering) the wait
        std::chrono::milliseconds nap_;
        uint32_t napsBeforeParking_;
        uint32_t idleNaps_ = 0U; // worker-only
    };
} // namespace AdaptiveSound
