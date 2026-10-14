// H3: drive the REAL GaplessSource + FileDecodeSource (Pure path) through adversarial cases.
//  (a) re-arm while one is armed (the docs-reconciler lead: Shuffle/Repeat/queue edit mid-song)
//  (b) a mono file on a 2-channel device (the render pulls with the DEVICE channel count)
//  (c) non-finite float samples reaching the device conversion (no scrub on the Pure path)
//  (d) a seek the backend refuses: what plays next, and where the position counter says we are
//  (e) a very short middle track: can the following track be armed in time?
#include "FileDecodeSource.h"
#include "GaplessSource.h"
#include "PureModeFormat.h"
#include "wav.h"

#include <chrono>
#include <cmath>
#include <cstdio>
#include <memory>
#include <string>
#include <thread>
#include <vector>

using namespace AdaptiveSound;
static int failures = 0;

static std::unique_ptr<FileDecodeSource> openSrc(const std::string& p) {
    auto s = std::make_unique<FileDecodeSource>();
    if (!s->open(p.c_str())) { std::printf("open failed: %s\n", p.c_str()); return nullptr; }
    return s;
}
// Write a stereo 16-bit 48k file whose every sample = `code` (a track fingerprint).
static std::string constWav(const std::string& dir, const char* name, int code, int frames, int ch = 2) {
    std::vector<int32_t> v(size_t(frames) * size_t(ch), code);
    std::string p = dir + "/" + name;
    writeWav(p, v, {}, uint32_t(ch), 48000, 16, false);
    return p;
}
// Pull like the HAL render: fixed block, device channel count, sleep a bit between blocks so the
// decode threads keep the rings full (a real IO cycle is ~10 ms).
static std::vector<float> pullBlocks(GaplessSource& g, int blocks, uint32_t frames, uint32_t ch) {
    std::vector<float> out, buf(size_t(frames) * ch);
    for (int b = 0; b < blocks; ++b) {
        std::fill(buf.begin(), buf.end(), 0.0f);
        uint32_t got = g.pullFloat(buf.data(), frames, ch);
        (void)got;
        out.insert(out.end(), buf.begin(), buf.end());
        std::this_thread::sleep_for(std::chrono::milliseconds(1));
        g.reapRetired();
    }
    return out;
}

static void rearm(const std::string& dir) {
    std::printf("\n(a) mid-song re-arm\n");
    auto pA = constWav(dir, "A.wav", 1000, 48000 / 10);   // 100 ms
    auto pB = constWav(dir, "B.wav", 2000, 48000);
    auto pC = constWav(dir, "C.wav", 3000, 48000);
    GaplessSource g;
    g.setCurrent(openSrc(pA));
    std::this_thread::sleep_for(std::chrono::milliseconds(50));
    // The bridge (PureModeBridge.cpp:353-363): compat check, then armNext; a refusal returns
    // kNextTrackError (0). We call the same GaplessSource::armNext the bridge calls.
    bool armedB = g.armNext(openSrc(pB));
    bool armedC = g.armNext(openSrc(pC));   // the VM re-arms to C (Shuffle/Repeat change, queue edit)
    std::printf("armNext(B) -> %s, armNext(C) -> %s  (bridge result for C: %d = %s)\n", armedB ? "true" : "false",
                armedC ? "true" : "false", armedC ? 2 : 0, armedC ? "armed" : "kNextTrackError");
    auto out = pullBlocks(g, 30, 512, 2);   // 300 ms: through A's end into the next track
    int firstAfterA = -1;
    for (size_t i = 0; i < out.size(); i += 2) {
        int code = int(std::lround(out[i] * 32768.0));
        if (code != 1000) { firstAfterA = code; break; }
    }
    std::printf("transitions=%llu; the track heard after A has fingerprint %d (%s)\n",
                (unsigned long long)g.transitionCount(), firstAfterA,
                firstAfterA == 2000 ? "B: the OLD on-deck track" : firstAfterA == 3000 ? "C: the re-armed track" : "?");
    if (firstAfterA != 3000) { ++failures; std::printf("CONFIRMED: Pure ignores the re-arm; the app names C, the device plays B\n"); }
    // What the bridge could do instead: clearNext() then armNext(C).
    GaplessSource g2;
    g2.setCurrent(openSrc(pA));
    (void)g2.armNext(openSrc(pB));
    g2.clearNext();
    bool armedC2 = g2.armNext(openSrc(pC));
    auto out2 = pullBlocks(g2, 30, 512, 2);
    int first2 = -1;
    for (size_t i = 0; i < out2.size(); i += 2) {
        int code = int(std::lround(out2[i] * 32768.0));
        if (code != 1000) { first2 = code; break; }
    }
    std::printf("remedy check (clearNext then armNext): armNext(C) -> %s, heard after A: %d\n", armedC2 ? "true" : "false", first2);
}

static void monoOnStereoDevice(const std::string& dir) {
    std::printf("\n(b) mono file, 2-channel device (HALOutputEngine render pulls rfChannels_ = device width)\n");
    auto pM = constWav(dir, "mono.wav", 5000, 48000, 1);
    GaplessSource g;
    g.setCurrent(openSrc(pM));
    std::this_thread::sleep_for(std::chrono::milliseconds(50));
    std::vector<float> buf(512 * 2);
    uint64_t produced = 0;
    double peak = 0;
    for (int b = 0; b < 200; ++b) {   // 2.1 s of render (> the 1 s file)
        uint32_t got = g.pullFloat(buf.data(), 512, 2);
        produced += got;
        for (float s : buf) peak = std::max(peak, double(std::fabs(s)));
    }
    std::printf("frames produced over 102400 requested: %llu; output peak %.3f; ended()=%d; position frames=%llu\n",
                (unsigned long long)produced, peak, g.ended() ? 1 : 0, (unsigned long long)g.renderedFramesCurrent());
    if (produced == 0 && !g.ended()) { ++failures; std::printf("CONFIRMED: silent forever, never ends, position frozen at 0\n"); }
}

static void nonFinite(const std::string& dir) {
    std::printf("\n(c) non-finite float samples on the Pure path\n");
    std::vector<float> f = {INFINITY, -INFINITY, NAN, 0.5f, 1e30f, -1e30f};
    std::string p = dir + "/nonfinite.wav";
    writeWav(p, {}, f, 2, 48000, 32, true);
    auto s = openSrc(p);
    std::this_thread::sleep_for(std::chrono::milliseconds(50));
    std::vector<float> out(6, 0.f);
    uint32_t got = s->pullFloat(out.data(), 3, 2);
    std::printf("decoded %u frames: ", got);
    for (float v : out) std::printf("%g ", v);
    std::vector<uint8_t> i16(12);
    convertFloatToNative(out.data(), i16.data(), 3, 2, 16, false, true, true, false, false);
    std::printf("\n-> int16 device: ");
    for (int i = 0; i < 6; ++i) std::printf("%d ", int(int16_t(i16[2 * size_t(i)] | (i16[2 * size_t(i) + 1] << 8))));
    std::vector<uint8_t> f32(24);
    convertFloatToNative(out.data(), f32.data(), 3, 2, 32, true, false, true, false, false);
    float back[6];
    std::memcpy(back, f32.data(), 24);
    std::printf("\n-> float32 device (memcpy): ");
    for (float v : back) std::printf("%g ", v);
    std::printf("\n");
}

static void failedSeek(const std::string& dir) {
    std::printf("\n(d) a refused seek (FileDecodeSource::seek returns false)\n");
    // Ramp file: sample k carries (k mod 30000) so we can read the frame index back.
    const int frames = 48000 * 20;
    std::vector<int32_t> v(size_t(frames) * 2);
    for (int k = 0; k < frames; ++k) { v[2 * size_t(k)] = k % 30000; v[2 * size_t(k) + 1] = k / 30000; }
    std::string p = dir + "/ramp.wav";
    writeWav(p, v, {}, 2, 48000, 16, false);
    auto s = openSrc(p);
    std::this_thread::sleep_for(std::chrono::milliseconds(300));   // let the ring fill
    std::vector<float> buf(4800 * 2);
    uint32_t got = s->pullFloat(buf.data(), 4800, 2);   // play 100 ms
    auto idx = [&](size_t f) { return int(std::lround(buf[2 * f] * 32768.0)) + 30000 * int(std::lround(buf[2 * f + 1] * 32768.0)); };
    int lastPlayed = idx(got - 1);
    for (double target : {1.0e7, 1.0e15, -5.0, 1.0e300}) {
        auto s2 = openSrc(p);
        std::this_thread::sleep_for(std::chrono::milliseconds(300));
        got = s2->pullFloat(buf.data(), 4800, 2);
        lastPlayed = idx(got - 1);
        bool ok = s2->seek(target);
        std::this_thread::sleep_for(std::chrono::milliseconds(100));
        got = s2->pullFloat(buf.data(), 4800, 2);
        int next = got ? idx(0) : -1;
        std::printf("seek(%g) -> %s; last frame played before %d, first frame after %d (frames produced %u)%s\n",
                    target, ok ? "true" : "false", lastPlayed, next, got,
                    (!ok && next != lastPlayed + 1) ? "  <-- refused seek skipped audio" : "");
    }
}

static void shortMiddleTrack(const std::string& dir) {
    std::printf("\n(e) A -> B(5 ms) -> C: can C be armed before B ends?\n");
    auto pA = constWav(dir, "A2.wav", 1000, 4800);
    auto pB = constWav(dir, "B2.wav", 2000, 240);
    auto pC = constWav(dir, "C2.wav", 3000, 48000);
    GaplessSource g;
    g.setCurrent(openSrc(pA));
    std::this_thread::sleep_for(std::chrono::milliseconds(50));
    (void)g.armNext(openSrc(pB));
    std::this_thread::sleep_for(std::chrono::milliseconds(50));
    std::vector<float> buf(512 * 2);
    bool cArmed = false;
    for (int b = 0; b < 40; ++b) {
        g.pullFloat(buf.data(), 512, 2);
        if (g.transitionCount() == 1 && !cArmed) {
            // The VM arms C only after its tick sees the transition; the bridge's poll reaps first.
            cArmed = g.armNext(openSrc(pC));
            std::printf("armNext(C) right after the seam, BEFORE a reap: %s\n", cArmed ? "true" : "false");
            g.reapRetired();
            cArmed = g.armNext(openSrc(pC));
            std::printf("armNext(C) after the reap: %s\n", cArmed ? "true" : "false");
        }
    }
    std::printf("transitions=%llu ended=%d\n", (unsigned long long)g.transitionCount(), g.ended() ? 1 : 0);
}

int main(int argc, char** argv) {
    const std::string dir = argc > 1 ? argv[1] : ".";
    rearm(dir);
    monoOnStereoDevice(dir);
    nonFinite(dir);
    failedSeek(dir);
    shortMiddleTrack(dir);
    std::printf("\nH3 done: %d confirmed defect(s)\n", failures);
    return 0;
}
