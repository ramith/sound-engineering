// H5: the REAL SpscRing and DoubleBufferSnapshot under a sequence-number oracle (TSan build).
#include "SpscRing.h"
#include "DoubleBufferSnapshot.h"
#include <atomic>
#include <cstdio>
#include <random>
#include <thread>
#include <vector>
using namespace AdaptiveSound;
int main(int argc, char** argv) {
    const uint64_t total = argc > 1 ? std::strtoull(argv[1], nullptr, 10) : 20000000ULL;
    // --- SpscRing: sequence continuity across wrap-around, partial pushes (tryPushBlock) and all-or-none (tryPushAll)
    static SpscRing<uint32_t, 1024> ring;
    std::atomic<bool> done{false};
    uint64_t bad = 0, popped = 0;
    std::thread prod([&] {
        std::mt19937 r(1);
        uint32_t next = 0;
        std::vector<uint32_t> blk(700);
        while (next < total) {
            size_t n = std::uniform_int_distribution<size_t>(1, 700)(r);
            for (size_t i = 0; i < n; ++i) blk[i] = next + uint32_t(i);
            if (r() & 1) { size_t w = ring.tryPushBlock(blk.data(), n); next += uint32_t(w); }
            else if (ring.tryPushAll(blk.data(), n)) next += uint32_t(n);
        }
        done = true;
    });
    std::thread cons([&] {
        std::mt19937 r(2);
        std::vector<uint32_t> out(900);
        uint32_t expect = 0;
        for (;;) {
            size_t n = std::uniform_int_distribution<size_t>(1, 900)(r);
            size_t got = ring.popBlock(out.data(), n);
            for (size_t i = 0; i < got; ++i) { if (out[i] != expect) ++bad; expect = out[i] + 1; }
            popped += got;
            if (got == 0 && done.load() && ring.isEmpty()) break;
        }
    });
    prod.join(); cons.join();
    std::printf("SpscRing: %llu elements through a 1024-slot ring (%.0f wraps), sequence breaks %llu\n",
                (unsigned long long)popped, double(popped) / 1023.0, (unsigned long long)bad);
    // --- triple buffer: a payload whose every word carries one generation; generations must be monotonic.
    struct P { uint64_t w[32]; };
    static DoubleBufferSnapshot<P> snap;
    std::atomic<bool> stop{false};
    uint64_t torn = 0, backwards = 0, reads = 0, fresh = 0;
    std::thread pub([&] { P p{}; for (uint64_t g = 1; !stop.load(std::memory_order_relaxed); ++g) { for (auto& x : p.w) x = g; snap.publish(p); } });
    std::thread rd([&] {
        uint64_t last = 0;
        for (uint64_t i = 0; i < total / 4; ++i) {
            P p; (void)snap.tryCopySnapshot(p);
            for (auto x : p.w) if (x != p.w[0]) { ++torn; break; }
            if (p.w[0] < last) ++backwards;
            if (p.w[0] > last) ++fresh;
            last = p.w[0]; ++reads;
        }
        stop = true;
    });
    pub.join(); rd.join();
    std::printf("TripleBuffer: %llu reads, %llu fresh generations seen, torn %llu, went backwards %llu\n",
                (unsigned long long)reads, (unsigned long long)fresh, (unsigned long long)torn, (unsigned long long)backwards);
    return (bad || torn || backwards) ? 1 : 0;
}
