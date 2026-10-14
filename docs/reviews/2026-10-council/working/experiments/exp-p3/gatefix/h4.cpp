// H4: RenderGate liveness. The REAL RenderGate.h vs a prototype "fair" gate (close announces itself:
// Rendering -> Closing, so the render cannot re-enter and close waits at most for the pass inside).
// Render duty cycles: HAL-like (128 frames @ 48 kHz, 100 us of work), heavy (75% duty), and the
// null-test's hot loop (no sleep). Optional CPU hogs oversubscribe the cores.
#include "RenderGate.h"

#include <algorithm>
#include <atomic>
#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <random>
#include <string>
#include <thread>
#include <vector>

using Clock = std::chrono::steady_clock;

struct FairGate {
    enum S : uint8_t { Open, Rendering, Closing, Closed };
    std::atomic<uint8_t> s{Open};
    bool tryEnter() noexcept { uint8_t e = Open; return s.compare_exchange_strong(e, Rendering, std::memory_order_acquire, std::memory_order_relaxed); }
    void leave() noexcept {
        uint8_t e = Rendering;
        if (!s.compare_exchange_strong(e, Open, std::memory_order_release, std::memory_order_relaxed))
            s.store(Closed, std::memory_order_release);   // e == Closing: hand the gate to the closer
    }
    bool close(std::chrono::microseconds timeout) noexcept {
        const auto deadline = Clock::now() + timeout;
        for (;;) {
            uint8_t e = s.load(std::memory_order_acquire);
            if (e == Closed) return true;
            if (e == Open) { if (s.compare_exchange_weak(e, Closed, std::memory_order_acquire, std::memory_order_acquire)) return true; continue; }
            if (e == Rendering) { s.compare_exchange_weak(e, Closing, std::memory_order_acq_rel, std::memory_order_acquire); continue; }
            // Closing: the render inside will hand over on leave(); no new render can enter.
            if (Clock::now() >= deadline) {
                uint8_t c = Closing;
                if (s.compare_exchange_strong(c, Rendering, std::memory_order_relaxed)) return false;
                continue;
            }
            std::this_thread::sleep_for(std::chrono::microseconds(50));
        }
    }
    void open() noexcept { uint8_t e = Closed; s.compare_exchange_strong(e, Open, std::memory_order_release, std::memory_order_relaxed); }
};

static void spin(std::chrono::microseconds d) { auto t = Clock::now() + d; while (Clock::now() < t) {} }

template <class Gate> static void run(const char* gateName, const char* mode, int hogs, int trials) {
    Gate gate;
    std::atomic<bool> stop{false};
    std::atomic<int> inside{0};
    std::atomic<long> overlaps{0};
    std::thread render([&] {
        auto next = Clock::now();
        while (!stop.load(std::memory_order_relaxed)) {
            const bool hal = std::string(mode) == "hal", heavy = std::string(mode) == "heavy";
            if (gate.tryEnter()) {
                if (inside.fetch_add(1) != 0) overlaps++;
                spin(std::chrono::microseconds(hal ? 100 : heavy ? 2000 : 2));
                inside.fetch_sub(1);
                gate.leave();
            }
            if (hal || heavy) {
                next += std::chrono::microseconds(hal ? 2667 : 2667);
                std::this_thread::sleep_until(next);
            }
        }
    });
    std::vector<std::thread> hogThreads;
    for (int i = 0; i < hogs; ++i) hogThreads.emplace_back([&] { volatile double x = 0; while (!stop.load(std::memory_order_relaxed)) x += 1.0; });
    std::this_thread::sleep_for(std::chrono::milliseconds(50));
    std::vector<double> lat;
    int fails = 0;
    std::mt19937 rng(42);
    for (int t = 0; t < trials; ++t) {
        auto t0 = Clock::now();
        bool ok = gate.close(std::chrono::microseconds(100000));   // production kHoldRenderTimeout
        auto us = std::chrono::duration<double, std::micro>(Clock::now() - t0).count();
        if (!ok) ++fails; else {
            if (inside.fetch_add(1) != 0) overlaps++;
            inside.fetch_sub(1);
            gate.open();
        }
        lat.push_back(us);
        std::this_thread::sleep_for(std::chrono::microseconds(std::uniform_int_distribution<int>(0, 3000)(rng)));
    }
    stop = true;
    render.join();
    for (auto& h : hogThreads) h.join();
    std::sort(lat.begin(), lat.end());
    auto pct = [&](double p) { return lat[size_t(p * (lat.size() - 1))]; };
    std::printf("%-10s %-6s hogs=%-2d trials=%d  close latency us: p50 %.0f  p99 %.0f  max %.0f  | timeouts(100 ms) %d  overlaps %ld\n",
                gateName, mode, hogs, trials, pct(0.5), pct(0.99), lat.back(), fails, overlaps.load());
}

int main(int argc, char** argv) {
    const int hogs = argc > 1 ? std::atoi(argv[1]) : 0;
    const int trials = argc > 2 ? std::atoi(argv[2]) : 500;
    for (const char* m : {"hal", "heavy", "hot"}) {
        run<AdaptiveSound::RenderGate>("RenderGate", m, hogs, trials);
        run<FairGate>("FairGate", m, hogs, trials);
    }
}
