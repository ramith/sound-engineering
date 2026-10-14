// Deterministic repro of the clear-then-arm window, on the REAL GaplessSource with ONE added test hook
// (GaplessSource_instrumented.cpp: the RT thread pauses right after its seam claim / after retiring),
// so the control plane's clearNext(); armNext(C) lands inside the seam the way a preempted RT thread
// would let it. Fixtures: A 1000, B 2000 (armed), C 3000 (the new pick).
#include "FileDecodeSource.h"
#include "GaplessSource.h"
#include "wav.h"
#include <atomic>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <map>
#include <memory>
#include <string>
#include <thread>
#include <vector>
using namespace AdaptiveSound;
void (*p3_seam_hook)(int) = nullptr;
static std::atomic<int> pauseAt{0}, paused{0};
static std::atomic<bool> resume{false};
static void hook(int where) {
    if (where != pauseAt.load()) return;
    pauseAt = 0;
    paused = where;
    while (!resume.load()) std::this_thread::yield();
}
int main(int argc, char** argv) {
    std::string dir = argc > 1 ? argv[1] : ".";
    auto fx = [&](const char* n, int code, int frames) { std::vector<int32_t> v(size_t(frames) * 2, code); std::string p = dir + "/" + n; writeWav(p, v, {}, 2, 48000, 16, false); return p; };
    auto pA = fx("wA.wav", 1000, 2048), pB = fx("wB.wav", 2000, 1024), pC = fx("wC.wav", 3000, 1024);
    auto open = [](const std::string& p) { auto s = std::make_unique<FileDecodeSource>(); (void)s->open(p.c_str()); while (!s->decoderFinished()) std::this_thread::yield(); return s; };
    for (int where : {1, 2}) {
        GaplessSource g;
        g.setCurrent(open(pA));
        (void)g.armNext(open(pB));
        auto c = open(pC);
        p3_seam_hook = hook; pauseAt = where; paused = 0; resume = false;
        std::vector<int> heard;
        std::atomic<bool> stop{false};
        std::thread rt([&] {
            std::vector<float> buf(64 * 2);
            for (int b = 0; b < 200 && !stop; ++b) {
                std::fill(buf.begin(), buf.end(), 0.f);
                g.pullFloat(buf.data(), 64, 2);
                for (int i = 0; i < 64; ++i) heard.push_back(int(std::lround(buf[2 * i] * 32768)));
            }
        });
        while (paused.load() == 0) std::this_thread::yield();
        // The bridge's re-arm, back to back: take the old pick off, arm the new one.
        g.clearNext();
        const bool armed = g.armNext(std::move(c));
        const bool endedAtArm = g.ended();
        resume = true;
        rt.join();
        std::map<int, int> count; std::vector<int> order;
        for (int x : heard) if (x != 0 && count[x]++ == 0) order.push_back(x);
        std::printf("RT paused %s: armNext(C)=%d (ended=%d -> the bridge's DEBUG assert %s); heard:", where == 1 ? "after its claim" : "after retiring A",
                    armed, endedAtArm, (!armed && !endedAtArm) ? "FIRES" : "holds");
        for (int x : order) std::printf(" %d x%d", x, count[x]);
        std::printf("; transitions=%llu ended=%d\n", (unsigned long long)g.transitionCount(), g.ended());
        g.reapRetired();
        std::printf("   after the poll plane's reapRetired: activeSource()=%p (null = the reap freed the ACTIVE track)\n", (void*)g.activeSource());
        p3_seam_hook = nullptr;
    }
}
