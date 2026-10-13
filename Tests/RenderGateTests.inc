// RenderGateTests.inc
//
// Sprint G: the render gate (RenderGate.h) the Pure seek and the HAL engine teardown hold instead
// of stopping the output unit. The render callback enters it before it pulls the source and
// leaves it after; the control plane closes it (waiting only for a render already inside) and
// opens it again. Pure: no HAL, no device. #included into Tests/DSPKernelNullTest.cpp after
// TestSupport.h. Under `make tsan` the concurrent test also proves there is no data race: the
// "source" both sides write is a plain, non-atomic buffer, ordered only by the gate.
//
// Tests: RenderGate_ClosedGateTurnsRenderAway, RenderGate_CloseWaitsForRenderInside,
//        RenderGate_ConcurrentNeverOverlaps.

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

static auto testRenderGateCloseWaitsForRenderInside() -> void
{
    static const char* const kName = "RenderGate_CloseWaitsForRenderInside";
    using AdaptiveSound::RenderGate;
    std::string err;
    RenderGate gate;
    std::atomic<bool> inside{false};
    std::atomic<bool> release{false};
    std::thread render(
        [&]
        {
            if (gate.tryEnter())
            {
                inside.store(true, std::memory_order_release);
                while (!release.load(std::memory_order_acquire))
                {
                    std::this_thread::sleep_for(std::chrono::microseconds{100});
                }
                gate.leave();
            }
        });
    while (!inside.load(std::memory_order_acquire))
    {
        std::this_thread::yield();
    }
    // The render is inside: a short close times out and changes nothing.
    if (gate.close(std::chrono::microseconds{2000}))
    {
        err += "close() succeeded while a render was inside; ";
    }
    if (gate.isClosed())
    {
        err += "a timed-out close() left the gate closed; ";
    }
    // Let the render leave shortly; a generous close waits for it and succeeds.
    std::thread releaser(
        [&]
        {
            std::this_thread::sleep_for(std::chrono::milliseconds{5});
            release.store(true, std::memory_order_release);
        });
    if (!gate.close(std::chrono::microseconds{2000000}))
    {
        err += "close() did not succeed once the render left; ";
    }
    releaser.join();
    render.join();
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

        // Keep the gate closed until the render has been turned away once (bounded), so the run
        // is known to have interleaved.
        void awaitTurnAway()
        {
            const uint64_t before = turnedAway.load(std::memory_order_relaxed);
            const auto deadline = std::chrono::steady_clock::now() + std::chrono::milliseconds{100};
            while (turnedAway.load(std::memory_order_relaxed) == before &&
                   std::chrono::steady_clock::now() < deadline)
            {
                std::this_thread::yield();
            }
        }

        // The control plane: one seek. False when the gate would not close.
        auto seekOnce(int generation) -> bool
        {
            if (!gate.close(std::chrono::seconds{1}))
            {
                return false;
            }
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
            err = std::format("close() timed out at seek {}; ", seek);
        }
    }
    race.stop.store(true, std::memory_order_release);
    render.join();
    err += race.verdict();
    if (err.empty())
    {
        logInfo(std::format("  [info] {}: {} seeks, {} pulls, {} turned away\n",
                            kName,
                            kSeeks,
                            race.pulls.load(),
                            race.turnedAway.load()));
        logPass(kName);
    }
    else
    {
        logFail(kName, err);
    }
}
