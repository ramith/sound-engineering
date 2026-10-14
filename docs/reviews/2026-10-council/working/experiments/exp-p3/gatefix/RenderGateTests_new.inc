// RenderGateTests.inc
//
// Sprint G / R1: the render gate (RenderGate.h) the Pure seek and the HAL engine teardown hold
// instead of stopping the output unit. The render callback enters it before it pulls the source
// and leaves it after; the control plane closes it and opens it again. Pure: no HAL, no device.
// #included into Tests/DSPKernelNullTest.cpp after TestSupport.h.
//
// What is asserted is the gate's GUARANTEE, not a latency: exclusion (never a render and a seek on
// the source at once — under `make tsan` also a data-race check, the "source" being a plain buffer
// ordered only by the gate) and progress (a close() waits for at most the one pass already inside;
// a pass that starts after it is turned away — the property the first gate lacked, which let a
// back-to-back render starve close() on a loaded CI runner). No assertion rests on a wall clock:
// the progress property is checked on one thread, step by step; the threaded tests force their
// interleavings with atomics and wait with RenderGate::kWaitForever — they need the scheduler to
// run a runnable thread, never a deadline that a loaded runner can miss.
//
// Tests: RenderGate_ClosedGateTurnsRenderAway, RenderGate_CloseWaitsForRenderInside,
//        RenderGate_PendingCloseBarsReentry, RenderGate_ConcurrentNeverOverlaps.

#include "RenderGate.h"

static auto testRenderGateClosedGateTurnsRenderAway() -> void
{
    static const char* const kName = "RenderGate_ClosedGateTurnsRenderAway";
    using AdaptiveSound::RenderGate;
    std::string err;
    RenderGate gate;
    if (!gate.tryEnter())
    {
        err += "a fresh gate turned the render away; ";
    }
    gate.leave();
    if (!gate.close(std::chrono::microseconds{0}))
    {
        err += "close() on an idle gate failed; ";
    }
    if (!gate.isClosed() || gate.tryEnter())
    {
        err += "a closed gate let a render in; ";
    }
    if (!gate.close(std::chrono::microseconds{0}))
    {
        err += "close() on a closed gate is not idempotent; ";
    }
    gate.open();
    if (gate.isClosed() || !gate.tryEnter())
    {
        err += "open() did not let the render in again; ";
    }
    // open() while a render is inside must not reopen anything: the close below still waits.
    gate.open();
    if (gate.close(std::chrono::microseconds{0}))
    {
        err += "open() during a render let close() succeed with the render inside; ";
    }
    gate.leave();
    if (!gate.close(std::chrono::microseconds{0}))
    {
        err += "close() failed after the render left; ";
    }
    if (err.empty())
    {
        logPass(kName);
    }
    else
    {
        logFail(kName, err);
    }
}

// A pass inside the gate holds close() until it leaves: a zero-timeout close() gives up and
// reopens; a waiting close() is pending (closed to new passes) yet does not return while the pass
// is inside, and returns true once it leaves.
static auto testRenderGateCloseWaitsForRenderInside() -> void
{
    static const char* const kName = "RenderGate_CloseWaitsForRenderInside";
    using AdaptiveSound::RenderGate;
    std::string err;
    RenderGate gate;
    if (!gate.tryEnter()) // this thread is the render, now inside
    {
        logFail(kName, "a fresh gate turned the render away");
        return;
    }
    if (gate.close(std::chrono::microseconds{0}))
    {
        err += "close() succeeded while a render was inside; ";
    }
    if (gate.isClosed())
    {
        err += "a timed-out close() left the gate closed; ";
    }
    std::atomic<bool> closerReturned{false};
    std::atomic<bool> closed{false};
    std::thread closer(
        [&]
        {
            closed.store(gate.close(RenderGate::kWaitForever), std::memory_order_relaxed);
            closerReturned.store(true, std::memory_order_release);
        });
    while (!gate.isClosed()) // the close is pending: no new pass may start
    {
        std::this_thread::yield();
    }
    if (closerReturned.load(std::memory_order_acquire))
    {
        err += "close() returned while the render was still inside; ";
    }
    gate.leave();
    closer.join();
    if (!closed.load(std::memory_order_relaxed))
    {
        err += "close() did not succeed once the render left; ";
    }
    if (err.empty())
    {
        logPass(kName);
    }
    else
    {
        logFail(kName, err);
    }
}

// The progress guarantee, step by step on one thread (no clock, no scheduler). A close requested
// while a pass is inside takes effect at once: once that pass leaves, the render's NEXT pass is
// turned away and the wait for quiet is over. The first gate had no such step — its close() could
// only win in the instant between two passes — so a render re-entering back to back starved it.
static auto testRenderGatePendingCloseBarsReentry() -> void
{
    static const char* const kName = "RenderGate_PendingCloseBarsReentry";
    using AdaptiveSound::RenderGate;
    std::string err;
    RenderGate gate;
    if (!gate.tryEnter()) // a pass is inside
    {
        logFail(kName, "a fresh gate turned the render away");
        return;
    }
    if (!gate.requestClose())
    {
        err += "requestClose() did not see the pass inside; ";
    }
    if (!gate.isClosed())
    {
        err += "a requested close did not close the gate to new passes at once; ";
    }
    if (gate.awaitQuiet(std::chrono::microseconds{0}))
    {
        err += "the gate reported quiet with a pass inside; ";
    }
    gate.leave();
    // Back to back, as a render loop does it: the pending close must win.
    if (gate.tryEnter())
    {
        err += "the render re-entered past a pending close (the starvation path); ";
        gate.leave();
    }
    if (!gate.awaitQuiet(std::chrono::microseconds{0}))
    {
        err += "the gate was not quiet once the one pass inside had left; ";
    }
    // A close requested on an idle gate has nothing to wait for.
    gate.open();
    if (gate.requestClose())
    {
        err += "requestClose() on an idle gate reported a pass inside; ";
    }
    gate.open();
    if (!gate.tryEnter())
    {
        err += "open() did not let the render in again; ";
    }
    gate.leave();
    if (err.empty())
    {
        logPass(kName);
    }
    else
    {
        logFail(kName, err);
    }
}

// A render thread pulls from a plain buffer inside the gate while the control plane closes the
// gate, rewrites the buffer (a seek) and opens it, over and over. Exclusion is checked twice: an
// atomic occupancy count must never see both sides at once, and every pull must read a buffer
// whose words all carry ONE generation (a torn read means the seek ran under a render).
namespace
{
    struct RenderGateRace
    {
        static constexpr size_t kWords = 64U;

        AdaptiveSound::RenderGate gate;
        std::array<uint64_t, kWords> source{}; // plain memory: only the gate orders access
        std::atomic<int> occupancy{0};
        std::atomic<uint64_t> overlaps{0U};
        std::atomic<uint64_t> torn{0U};
        std::atomic<uint64_t> pulls{0U};
        std::atomic<uint64_t> turnedAway{0U};
        std::atomic<bool> stop{false};
        std::chrono::steady_clock::duration slowestClose{}; // control thread only (info)

        // Count this side in; a second side already inside is an overlap.
        void occupy()
        {
            if (occupancy.fetch_add(1, std::memory_order_acq_rel) != 0)
            {
                overlaps.fetch_add(1U, std::memory_order_relaxed);
            }
        }

        void vacate()
        {
            occupancy.fetch_sub(1, std::memory_order_acq_rel);
        }

        // The render: one pull, as the HAL callback does it.
        void renderOnce()
        {
            if (!gate.tryEnter())
            {
                turnedAway.fetch_add(1U, std::memory_order_relaxed);
                return;
            }
            occupy();
            const uint64_t first = source[0];
            if (!std::ranges::all_of(source, [first](uint64_t word) { return word == first; }))
            {
                torn.fetch_add(1U, std::memory_order_relaxed);
            }
            vacate();
            gate.leave();
            pulls.fetch_add(1U, std::memory_order_relaxed);
        }

        void renderLoop()
        {
            while (!stop.load(std::memory_order_acquire))
            {
                renderOnce();
            }
        }

        // Keep the gate closed until the render has been turned away once, so the run is known
        // to have interleaved (the render loop never stops trying, so this always ends).
        void awaitTurnAway()
        {
            const uint64_t before = turnedAway.load(std::memory_order_relaxed);
            while (turnedAway.load(std::memory_order_relaxed) == before)
            {
                std::this_thread::yield();
            }
        }

        // The control plane: one seek. False when the gate would not close (a correct gate always
        // does: it waits for the one pass inside, however busy the render is).
        auto seekOnce(int generation) -> bool
        {
            const auto began = std::chrono::steady_clock::now();
            if (!gate.close(AdaptiveSound::RenderGate::kWaitForever))
            {
                return false;
            }
            slowestClose = std::max(slowestClose, std::chrono::steady_clock::now() - began);
            if (generation % 100 == 0)
            {
                awaitTurnAway();
            }
            occupy();
            source.fill(static_cast<uint64_t>(generation));
            vacate();
            gate.open();
            return true;
        }

        [[nodiscard]] auto verdict() const -> std::string
        {
            std::string err;
            if (overlaps.load() != 0U)
            {
                err += std::format("{} overlaps of render and seek; ", overlaps.load());
            }
            if (torn.load() != 0U)
            {
                err += std::format("{} pulls read a half-rewritten source; ", torn.load());
            }
            if (pulls.load() == 0U || turnedAway.load() == 0U)
            {
                err += std::format("no interleaving (pulls {}, turned away {}); ",
                                   pulls.load(),
                                   turnedAway.load());
            }
            return err;
        }
    };
} // namespace

static auto testRenderGateConcurrentNeverOverlaps() -> void
{
    static const char* const kName = "RenderGate_ConcurrentNeverOverlaps";
    constexpr int kSeeks = 2000;
    RenderGateRace race;
    std::thread render([&race] { race.renderLoop(); });
    // Start seeking only once the render is pulling, so the two really interleave.
    while (race.pulls.load(std::memory_order_relaxed) == 0U)
    {
        std::this_thread::yield();
    }
    std::string err;
    for (int seek = 1; seek <= kSeeks && err.empty(); ++seek)
    {
        if (!race.seekOnce(seek))
        {
            err = std::format("close() failed at seek {}; ", seek);
        }
    }
    race.stop.store(true, std::memory_order_release);
    render.join();
    err += race.verdict();
    if (err.empty())
    {
        logInfo(std::format(
            "  [info] {}: {} seeks, {} pulls, {} turned away, slowest close {} µs\n",
            kName,
            kSeeks,
            race.pulls.load(),
            race.turnedAway.load(),
            std::chrono::duration_cast<std::chrono::microseconds>(race.slowestClose).count()));
        logPass(kName);
    }
    else
    {
        logFail(kName, err);
    }
}
