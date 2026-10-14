// Probe: how long does RenderGate::close() take against a busy (never-yielding) renderer,
// vs a periodic (HAL-like) renderer? Measures the worst close() latency over N closes.
#include "RenderGate.h"
#include <atomic>
#include <chrono>
#include <cstdio>
#include <thread>
#include <vector>
#include <algorithm>
using namespace std::chrono;
int main(int argc, char** argv) {
    const bool periodic = argc > 1 && argv[1][0] == 'p';
    AdaptiveSound::RenderGate gate;
    std::atomic<bool> stop{false};
    std::atomic<uint64_t> pulls{0};
    std::thread render([&] {
        while (!stop.load(std::memory_order_acquire)) {
            if (gate.tryEnter()) {
                volatile int sink = 0; for (int i = 0; i < 64; ++i) sink += i; (void)sink;
                gate.leave();
                pulls.fetch_add(1, std::memory_order_relaxed);
            }
            if (periodic) std::this_thread::sleep_for(microseconds(2000));
        }
    });
    while (pulls.load() == 0) std::this_thread::yield();
    std::vector<double> lat;
    int failures = 0;
    for (int i = 0; i < 2000; ++i) {
        auto t0 = steady_clock::now();
        if (!gate.close(seconds{1})) { ++failures; continue; }
        lat.push_back(duration<double, std::micro>(steady_clock::now() - t0).count());
        gate.open();
    }
    stop = true; render.join();
    std::sort(lat.begin(), lat.end());
    std::printf("%s renderer: closes=%zu failures=%d p50=%.1fus p99=%.1fus max=%.1fus\n",
                periodic ? "periodic" : "busy", lat.size(), failures,
                lat[lat.size()/2], lat[lat.size()*99/100], lat.back());
}
