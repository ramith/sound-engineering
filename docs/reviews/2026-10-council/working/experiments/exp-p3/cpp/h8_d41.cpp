// H8: the REAL GaplessSource @ 1ebf323 under the D41 races (one RT thread pulling, one control thread).
//  E1 clear vs seam      : B armed; the control clears at a random offset around A's end.
//  E2 arm vs end         : nothing armed; the control arms B at a random offset around A's end.
//  E3 clear+arm vs seam  : B armed; the control does clearNext(); armNext(C) back to back (the
//                          bridge's re-arm with no file open in between) at a random offset.
// Every trial's audible output is read off the constant-code fixtures (A 1000, B 2000, C 3000).
#include "FileDecodeSource.h"
#include "GaplessSource.h"
#include "wav.h"

#include <atomic>
#include <chrono>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <map>
#include <memory>
#include <random>
#include <string>
#include <thread>
#include <vector>

using namespace AdaptiveSound;

static std::string g_dir;
static std::string fixture(const char* name, int code, int frames) {
    std::vector<int32_t> v(size_t(frames) * 2, code);
    std::string p = g_dir + "/" + name;
    writeWav(p, v, {}, 2, 48000, 16, false);
    return p;
}
static std::unique_ptr<FileDecodeSource> open(const std::string& p) {
    auto s = std::make_unique<FileDecodeSource>();
    if (!s->open(p.c_str())) { std::printf("open failed %s\n", p.c_str()); std::exit(2); }
    return s;
}
static void waitFilled(FileDecodeSource* s) {   // the decoder has pushed everything (short fixtures)
    while (!s->decoderFinished()) std::this_thread::yield();
}

struct Trial {
    std::vector<int> heard;   // L-channel codes in order, silence = 0
    uint64_t transitions = 0;
    bool ended = false;
    int armResult = -1;
};

// The render: pull 64-frame blocks until told to stop.
static void renderLoop(GaplessSource& g, std::atomic<bool>& stop, std::vector<int>& heard) {
    std::vector<float> buf(64 * 2);
    while (!stop.load(std::memory_order_acquire)) {
        std::fill(buf.begin(), buf.end(), 0.0f);
        const uint32_t got = g.pullFloat(buf.data(), 64, 2);
        for (uint32_t i = 0; i < 64; ++i) {
            const int code = int(std::lround(buf[2 * i] * 32768.0f));
            if (heard.empty() || heard.back() != code || code != 0) heard.push_back(code);
        }
        (void)got;
        for (volatile int i = 0; i < 1500; i = i + 1) {}   // pace: a block every few microseconds
    }
}

// Compress the heard sequence to its runs: e.g. "1000 2000" or "1000 0".
static std::string runs(const std::vector<int>& h) {
    std::string s;
    int last = -1;
    for (int c : h) if (c != last) { s += (s.empty() ? "" : " ") + std::to_string(c); last = c; }
    return s;
}

static void spin(int n) { for (volatile int i = 0; i < n; i = i + 1) {} }

int main(int argc, char** argv) {
    g_dir = argc > 1 ? argv[1] : ".";
    const int trials = argc > 2 ? std::atoi(argv[2]) : 2000;
    const std::string pA = fixture("d41A.wav", 1000, 2048), pB = fixture("d41B.wav", 2000, 1024), pC = fixture("d41C.wav", 3000, 1024);
    std::mt19937 rng(7);

    for (int exp = 1; exp <= 3; ++exp) {
        std::map<std::string, int> outcomes;
        int violations = 0;
        for (int t = 0; t < trials; ++t) {
            GaplessSource g;
            auto a = open(pA); waitFilled(a.get());
            g.setCurrent(std::move(a));
            if (exp != 2) { auto b = open(pB); waitFilled(b.get()); if (!g.armNext(std::move(b))) { std::printf("prime arm failed\n"); return 2; } }
            std::unique_ptr<FileDecodeSource> late = open(exp == 3 ? pC : pB);
            waitFilled(late.get());
            std::atomic<bool> stop{false};
            std::vector<int> heard; heard.reserve(4096);
            std::thread rt([&] { renderLoop(g, stop, heard); });
            // Land near A's end (2048 frames = 32 blocks): wait for ~1900 rendered frames, then a random spin.
            while (g.transitionCount() == 0 && !g.ended() && g.renderedFramesCurrent() < 1900) std::this_thread::yield();
            spin(std::uniform_int_distribution<int>(0, exp == 3 ? 4000 : 20000)(rng));
            int armRes = -1;
            if (exp == 1) g.clearNext();
            if (exp == 2) armRes = g.armNext(std::move(late)) ? 1 : 0;
            if (exp == 3) { g.clearNext(); armRes = g.armNext(std::move(late)) ? 1 : 0; }
            const bool endedAtArm = g.ended();
            // Let it play out: past A's end, and past B/C (1024 frames) if a seam happened.
            for (int k = 0; k < 2000 && !(g.ended() || g.transitionCount() >= 1); ++k) std::this_thread::sleep_for(std::chrono::microseconds(50));
            std::this_thread::sleep_for(std::chrono::milliseconds(3));
            stop = true; rt.join();
            g.reapRetired();
            const std::string r = runs(heard);
            const uint64_t tr = g.transitionCount();
            const bool ended = g.ended();
            std::string key = "heard [" + r + "] transitions=" + std::to_string(tr) + " ended=" + std::to_string(ended);
            if (armRes >= 0) key += " armNext=" + std::to_string(armRes) + (armRes == 0 && !endedAtArm ? " (refused while NOT ended: the DEBUG assert's case)" : "");
            // Allowed outcomes: every track heard whole (A 2048, B/C 1024 frames or none), one seam per
            // track heard after A, the session ends, a refused arm only once the end happened, and the
            // tracks heard after A form one of the experiment's allowed sequences.
            std::map<int, int> count;
            std::vector<int> after;
            for (int c : heard) { if (c != 0) { if (count[c]++ == 0 && c != 1000) after.push_back(c); } }
            bool whole = count[1000] == 2048 && (count[2000] == 0 || count[2000] == 1024) && (count[3000] == 0 || count[3000] == 1024);
            bool seamsMatch = tr == after.size();
            bool refusedOk = armRes != 0 || endedAtArm;
            std::vector<std::vector<int>> allowed;
            if (exp == 1) allowed = {{}, {2000}};
            if (exp == 2) allowed = armRes == 0 ? std::vector<std::vector<int>>{{}} : std::vector<std::vector<int>>{{}, {2000}};
            if (exp == 3) allowed = {{}, {3000}, {2000}, {2000, 3000}};
            bool seqOk = false;
            for (auto& al : allowed) seqOk |= (al == after);
            bool ok = whole && seamsMatch && refusedOk && seqOk && ended;
            if (!ok) key += "   <-- VIOLATION" + std::string(!whole ? " (a track not heard whole)" : "") + (!seamsMatch ? " (seam count != tracks heard)" : "") +
                            (!refusedOk ? " (refused while not ended)" : "") + (!seqOk ? " (sequence)" : "");
            outcomes[key]++;
            if (!ok) ++violations;
            g.clearNext();   // frees an arm that lost to the end (never adopted)
        }
        std::printf("\nE%d %s: %d trials, %d outside the allowed outcomes\n", exp,
                    exp == 1 ? "clear vs seam" : exp == 2 ? "arm vs end" : "clearNext()+armNext(C) back to back vs seam", trials, violations);
        for (auto& [k, v] : outcomes) std::printf("  %6d  %s\n", v, k.c_str());
    }
    return 0;
}
