// H6: the REAL RtSwappableResource under a publish/adopt race; T counts live instances.
#include "RtSwappableResource.h"
#include <atomic>
#include <cstdio>
#include <memory>
#include <thread>
using namespace AdaptiveSound;
static std::atomic<long> live{0}, made{0};
struct Res { long v; explicit Res(long x) : v(x) { live++; made++; } ~Res() { live--; } };
int main() {
    long leakedTotal = 0;
    for (int round = 0; round < 200; ++round) {
        {
            RtSwappableResource<Res> r;
            std::atomic<bool> stop{false};
            std::thread rt([&] { long seen = 0; while (!stop.load(std::memory_order_relaxed)) { Res* a = r.adopt(); if (a) seen += a->v & 1; } (void)seen; });
            for (int i = 0; i < 20000; ++i) r.publish(std::make_unique<Res>(i));
            stop = true; rt.join();
            r.reclaim();
        }   // dtor frees active/pending/toRelease
        leakedTotal = live.load();
    }
    std::printf("RtSwappableResource: %ld resources made, %ld still alive after every instance was destroyed (leaked orphans)\n",
                made.load(), leakedTotal);
}
