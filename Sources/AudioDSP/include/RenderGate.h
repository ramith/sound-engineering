#pragma once

//
// RenderGate.h — quiet a render callback, and KNOW it is quiet, without stopping the device.
//
// Why (S10.8 G): a Pure seek must move the decoder while the HAL render callback is not pulling
// from it (FileDecodeSource::seek's precondition). It used to stop the output unit for that, and
// the stop was HALOutputEngine::stop() = teardown(): the unit was disposed, the restart failed and
// every Pure seek went silent. Stopping the unit is a poor barrier anyway: on a dying device
// AudioOutputUnitStop can fail or wait seconds on the HAL. The gate needs no HAL call. The render
// callback ENTERS it before it pulls and LEAVES it after; the control plane CLOSES it and, while it
// is closed, the callback outputs silence; OPEN lets it pull again.
//
// The guarantee close() gives (R1 fix): it waits for AT MOST the one render pass already inside,
// never for a render that starts after it. One atomic word with two bits:
//   kClosed     set by requestClose() (fetch_or), cleared by open() — only the control plane writes it;
//   kRendering  set by the render's tryEnter (CAS 0 -> kRendering) and cleared by leave()
//               (fetch_and) — only the render writes it.
// All four operations are read-modify-writes of ONE atomic, so they are totally ordered (its
// modification order). close() = requestClose() + awaitQuiet(). requestClose()'s fetch_or is the
// linearization point: a tryEnter ordered after it sees kClosed and fails, so kRendering can only
// still be set by a pass that entered BEFORE it — the in-flight one — and awaitQuiet() waits for
// that bit alone to clear. The render's side stays wait-free (one CAS in, one fetch_and out), and
// requestClose() is wait-free too: the control plane wins at once, however often the render runs.
//
// The first version (one state, close = CAS Open -> Closed, polled every 50 µs) promised the same
// in its comment but did not keep it: close() could only win in the instant between one pass's
// leave() and the next pass's tryEnter(), so a render re-entering back to back starved it. The null
// test's back-to-back render made a GitHub runner's close() time out after 1 s (main a206107);
// a periodic HAL IO thread leaves most of its period open, which hid it in the app.
//
// Ordering: tryEnter's acquire pairs with open()'s release (the control plane's writes — a moved
// decoder — happen-before the next pass); leave()'s release pairs with close()'s acquire (every
// access of the last pass happens-before what the control plane does next). Named atomics, no
// standalone fence, so ThreadSanitizer models every edge (the null test's RenderGate suite).
//
// One render thread at a time (the AUHAL calls its render callback serially) — kRendering is a
// bit, not a count — and one control thread at a time (the Pure C-ABI runs on the bridge's
// engineQueue).
//

#include "BoundedWait.h"

#include <atomic>
#include <chrono>
#include <cstdint>

namespace AdaptiveSound
{

    class RenderGate
    {
      public:
        // A timeout meaning "no deadline" for close() / awaitQuiet().
        static constexpr std::chrono::microseconds kWaitForever = AdaptiveSound::kWaitForever;

        // RT: true -> the caller may pull and MUST call leave() after; false -> closed: render
        // silence and do not touch the source. Wait-free.
        [[nodiscard]] bool tryEnter() noexcept
        {
            uint8_t expected = 0U;
            return state_.compare_exchange_strong(
                expected, kRendering, std::memory_order_acquire, std::memory_order_relaxed);
        }

        // RT: the pass that entered is done with the source. Wait-free; keeps a pending kClosed.
        void leave() noexcept
        {
            state_.fetch_and(static_cast<uint8_t>(~kRendering), std::memory_order_release);
        }

        // Control plane: close the gate to new passes, then wait for the pass already inside, if
        // any, to leave — requestClose() + awaitQuiet(). True when closed with no pass inside: no
        // render pulls until open(). The wait is for that ONE pass (well under a millisecond of RT
        // work on the HAL IO thread). `timeout` is a safety net against a render thread stopped
        // mid-pass, which an RT render never is: on it the gate reopens, nothing changed, and
        // close() returns false. kWaitForever: no deadline.
        [[nodiscard]] bool close(std::chrono::microseconds timeout) noexcept
        {
            if (!requestClose() || awaitQuiet(timeout))
            {
                return true;
            }
            open();
            return false;
        }

        // Control plane, step 1 — wait-free: from now on every tryEnter() fails. Returns whether a
        // pass that entered before it is still inside (then call awaitQuiet before touching the
        // source).
        [[nodiscard]] bool requestClose() noexcept
        {
            return (state_.fetch_or(kClosed, std::memory_order_acq_rel) & kRendering) != 0U;
        }

        // Control plane, step 2: wait until the pass inside (the only one there can be after
        // requestClose) has left. True once it has; false if `timeout` passed first.
        [[nodiscard]] bool awaitQuiet(std::chrono::microseconds timeout) const noexcept
        {
            // A pass is short: BoundedWait yields a few times, then sleeps in small steps.
            return waitUntil(
                [this] { return (state_.load(std::memory_order_acquire) & kRendering) == 0U; },
                timeout);
        }

        // Control plane: let the render pull again. A no-op unless closed.
        void open() noexcept
        {
            state_.fetch_and(static_cast<uint8_t>(~kClosed), std::memory_order_release);
        }

        // Closed to new passes (a pass already inside may still be finishing until close()
        // returns true).
        [[nodiscard]] bool isClosed() const noexcept
        {
            return (state_.load(std::memory_order_acquire) & kClosed) != 0U;
        }

      private:
        static constexpr uint8_t kRendering = 1U << 0U;
        static constexpr uint8_t kClosed = 1U << 1U;

        std::atomic<uint8_t> state_{0U};
    };

} // namespace AdaptiveSound
