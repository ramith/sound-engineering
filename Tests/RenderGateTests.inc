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
//        RenderGate_PendingCloseBarsReentry, RenderGate_TeardownCloseNeverReopens,
//        RenderGate_ConcurrentNeverOverlaps.

#include "RenderGate.h"

// Yield until `done()` holds, at most kSpinBound times. The waits below need a runnable thread to
// be scheduled, never a deadline, so a correct gate ends them in a few yields; only a regression
// exhausts the bound — and then the test FAILS instead of hanging the suite. No wall clock.
template <typename Done> static auto spinUntil(Done done) -> bool
{
    constexpr uint64_t kSpinBound = 20'000'000U;
    for (uint64_t spin = 0U; spin < kSpinBound; ++spin)
    {
        if (done())
        {
            return true;
        }
        std::this_thread::yield();
    }
    return done();
}

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
    // The close is pending: no new pass may start. (The first gate never got here while a pass
    // was inside — bounded so that regression fails rather than hangs.)
    if (!spinUntil([&gate] { return gate.isClosed(); }))
    {
        err += "a waiting close() never closed the gate to new passes; ";
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

// The teardown sequence (HALOutputEngine::teardown): requestClose, then a wait for quiet that may
// give up, and NEVER a reopen. Even when the wait gives up with a pass inside, the gate stays
// closed: once that pass leaves, no new pass can start against a source its owner is freeing (the
// owner parks the source if the pass never leaves — HALOutputEngine::renderMayStillRun). One
// thread, no clock.
static auto testRenderGateTeardownCloseNeverReopens() -> void
{
    static const char* const kName = "RenderGate_TeardownCloseNeverReopens";
    using AdaptiveSound::RenderGate;
    std::string err;
    RenderGate gate;
    if (!gate.tryEnter()) // a pass is inside when teardown begins
    {
        logFail(kName, "a fresh gate turned the render away");
        return;
    }
    if (!gate.requestClose() || gate.awaitQuiet(std::chrono::microseconds{0}))
    {
        err += "teardown did not see the pass inside; ";
    }
    if (!gate.isClosed())
    {
        err += "a teardown that gave up waiting left the gate open; ";
    }
    gate.leave();
    if (gate.tryEnter())
    {
        err += "a new pass started after the teardown gave up waiting; ";
        gate.leave();
    }
    if (!gate.awaitQuiet(std::chrono::microseconds{0}))
    {
        err += "the gate was not quiet once the pass left; ";
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

// A render thread pulls from a plain buffer inside the gate while the control plane closes the
// gate, rewrites the buffer (a seek) and opens it, over and over. Exclusion is checked twice: an
// atomic occupancy count must never see both sides at once, and every pull must read a buffer
// whose words all carry ONE generation (a torn read means the seek ran under a render). Every seek
// waits for at least one pull since the previous one, so each generation is read while the next
// seek may be closing in — the torn-read check samples every seek, not a few.
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
        uint64_t pullsAtLastSeek = 0U;                      // control thread only

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
            pulls.fetch_add(1U, std::memory_order_relaxed); // counted inside: a pass that read
            vacate();
            gate.leave();
        }

        void renderLoop()
        {
            while (!stop.load(std::memory_order_acquire))
            {
                renderOnce();
            }
        }

        // The control plane: one seek, after at least one pull since the previous one. "" when
        // done, else what went wrong (a correct gate always closes: it waits for the one pass
        // inside, however busy the render is).
        auto seekOnce(int generation) -> std::string
        {
            if (!spinUntil([this]
                           { return pulls.load(std::memory_order_relaxed) > pullsAtLastSeek; }))
            {
                return std::format("no render pull after seek {}; ", generation - 1);
            }
            const auto began = std::chrono::steady_clock::now();
            if (!gate.close(AdaptiveSound::RenderGate::kWaitForever))
            {
                return std::format("close() failed at seek {}; ", generation);
            }
            slowestClose = std::max(slowestClose, std::chrono::steady_clock::now() - began);
            if (generation % 100 == 0)
            {
                // Hold the gate until the render has been turned away once: the run interleaves.
                const uint64_t before = turnedAway.load(std::memory_order_relaxed);
                if (!spinUntil([this, before]
                               { return turnedAway.load(std::memory_order_relaxed) != before; }))
                {
                    gate.open();
                    return std::format("the render never tried a closed gate at seek {}; ",
                                       generation);
                }
            }
            occupy();
            source.fill(static_cast<uint64_t>(generation));
            vacate();
            pullsAtLastSeek = pulls.load(std::memory_order_relaxed); // stable: no pass is inside
            gate.open();
            return "";
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
    std::string err;
    for (int seek = 1; seek <= kSeeks && err.empty(); ++seek)
    {
        err = race.seekOnce(seek); // the first one waits for the render's first pull
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
