#pragma once

//
// RenderGate.h — quiet a render callback, and KNOW it is quiet, without stopping the device.
//
// Why (S10.8 G): a Pure seek must move the decoder while the HAL render callback is not pulling
// from it (FileDecodeSource::seek's precondition). It used to stop the output unit for that, and
// the stop was HALOutputEngine::stop() = teardown(): the unit was disposed, the restart failed and
// every Pure seek went silent. Stopping the unit is a poor barrier anyway: on a dying device
// AudioOutputUnitStop can fail or wait seconds on the HAL. The gate needs no HAL call. The render
// callback ENTERS it before it pulls and LEAVES it after; the control plane CLOSES it, waiting only
// for a render already inside (bounded by one render pass, never by the device), and while it is
// closed the callback outputs silence; OPEN lets it pull again.
//
// One atomic word, three states:
//   render:  Open -> Rendering (CAS, acquire) ... Rendering -> Open (store, release)
//   control: Open -> Closed (CAS, acquire: pairs with the render's release, so everything the last
//            render did happens-before what the control plane does next); Closed -> Open (CAS,
//            release: the control plane's writes happen-before the next render's acquire).
// Only the control plane can close or open, only from the matching state, so an open() can never
// let a close() succeed while a render is inside. Named atomics, no standalone fence, so
// ThreadSanitizer models every edge (see the null test's RenderGate suite).
//
// RT side: tryEnter() / leave() — wait-free, no allocation, lock or syscall.
// Control side: close() / open() — one control thread at a time (the Pure C-ABI runs on the
// bridge's engineQueue).
//

#include <atomic>
#include <chrono>
#include <cstdint>
#include <thread>

namespace AdaptiveSound
{

    class RenderGate
    {
      public:
        // RT: true -> the caller may pull and MUST call leave() after; false -> closed: render
        // silence and do not touch the source.
        [[nodiscard]] bool tryEnter() noexcept
        {
            State expected = State::Open;
            return state_.compare_exchange_strong(
                expected, State::Rendering, std::memory_order_acquire, std::memory_order_relaxed);
        }

        // RT: the render that entered is done with the source.
        void leave() noexcept
        {
            state_.store(State::Open, std::memory_order_release);
        }

        // Control plane: close the gate, waiting at most `timeout` for a render already inside to
        // leave. True when closed (or already closed): no render is pulling, and none will until
        // open(). False when a render stayed inside past the timeout: the gate is left as it was.
        [[nodiscard]] bool close(std::chrono::microseconds timeout) noexcept
        {
            const auto deadline = std::chrono::steady_clock::now() + timeout;
            for (;;)
            {
                State expected = State::Open;
                if (state_.compare_exchange_weak(expected,
                                                 State::Closed,
                                                 std::memory_order_acquire,
                                                 std::memory_order_acquire))
                {
                    return true;
                }
                if (expected == State::Closed)
                {
                    return true;
                }
                if (expected == State::Open)
                {
                    continue; // a spurious weak-CAS failure, not a render inside: try again
                }
                if (std::chrono::steady_clock::now() >= deadline)
                {
                    return false;
                }
                std::this_thread::sleep_for(kPollStep);
            }
        }

        // Control plane: let the render pull again. A no-op unless closed.
        void open() noexcept
        {
            State expected = State::Closed;
            (void)state_.compare_exchange_strong(
                expected, State::Open, std::memory_order_release, std::memory_order_relaxed);
        }

        [[nodiscard]] bool isClosed() const noexcept
        {
            return state_.load(std::memory_order_acquire) == State::Closed;
        }

      private:
        enum class State : uint8_t
        {
            Open,
            Rendering,
            Closed,
        };

        // A render pass is well under a millisecond of CPU; poll at a fraction of it.
        static constexpr std::chrono::microseconds kPollStep{50};

        std::atomic<State> state_{State::Open};
    };

} // namespace AdaptiveSound
