// P3 breaker harness H1: Pure-path bit-exactness of the REAL convertFloatToNative + FileDecodeSource.
// Oracle: integer identity (an N-bit integer source must leave the device format as the same integer,
// left-justified into wider words). Exhaustive over every 16-bit and every 24-bit code.
#include "PureModeFormat.h"
#include "FileDecodeSource.h"
#include "wav.h"

#include <chrono>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <thread>
#include <vector>

using namespace AdaptiveSound;

static int failures = 0;
#define CHECK(c, ...) do { if (!(c)) { ++failures; std::printf("FAIL: " __VA_ARGS__); std::printf("\n"); } } while (0)

static uint32_t le32(const uint8_t* p) { return p[0] | (p[1] << 8) | (p[2] << 16) | (uint32_t(p[3]) << 24); }
static int16_t le16(const uint8_t* p) { return int16_t(p[0] | (p[1] << 8)); }

// Convert one block via the REAL production function.
static std::vector<uint8_t> conv(const std::vector<float>& f, uint32_t ch, uint32_t bits, bool isFloat, bool packed,
                                 bool high, size_t bytesPerSample) {
    std::vector<uint8_t> out(f.size() * bytesPerSample, 0xAB);
    convertFloatToNative(f.data(), out.data(), uint32_t(f.size() / ch), ch, bits, isFloat, !isFloat, packed, high, false);
    return out;
}

static void pureFunctionExhaustive() {
    // 16-bit codes, the decoder's int->float convention (/2^15).
    std::vector<float> f16(65536);
    for (int v = -32768; v < 32768; ++v) f16[size_t(v + 32768)] = float(v) / 32768.0f;
    auto o16 = conv(f16, 1, 16, false, true, false, 2);
    auto o16to24lo = conv(f16, 1, 24, false, false, false, 4);
    auto o16to32 = conv(f16, 1, 32, false, true, false, 4);
    int bad16 = 0, bad1624 = 0, bad1632 = 0;
    for (int v = -32768; v < 32768; ++v) {
        size_t i = size_t(v + 32768);
        bad16 += le16(&o16[2 * i]) != v;
        bad1624 += int32_t(le32(&o16to24lo[4 * i]) << 8) >> 8 != v * 256;
        bad1632 += int32_t(le32(&o16to32[4 * i])) != v * 65536;
    }
    std::printf("[pure fn] 16->16 mismatches %d / 65536; 16->24in32 %d; 16->32 %d\n", bad16, bad1624, bad1632);
    CHECK(bad16 == 0 && bad1624 == 0 && bad1632 == 0, "16-bit exhaustive");

    // 24-bit codes (/2^23).
    const int N = 1 << 24;
    std::vector<float> f24(static_cast<size_t>(N));
    for (int v = -(1 << 23); v < (1 << 23); ++v) f24[size_t(v + (1 << 23))] = float(v) / 8388608.0f;
    auto lo = conv(f24, 1, 24, false, false, false, 4);
    auto hi = conv(f24, 1, 24, false, false, true, 4);
    auto p32 = conv(f24, 1, 32, false, true, false, 4);
    long badLo = 0, badHi = 0, bad32 = 0;
    for (int v = -(1 << 23); v < (1 << 23); ++v) {
        size_t i = size_t(v + (1 << 23));
        uint32_t wl = le32(&lo[4 * i]), wh = le32(&hi[4 * i]), w32 = le32(&p32[4 * i]);
        badLo += (wl != (uint32_t(v) & 0xFFFFFFu));
        badHi += (wh != (uint32_t(v) << 8));
        bad32 += (int32_t(w32) != v * 256);
    }
    std::printf("[pure fn] 24->24in32(low) mismatches %ld / %d; 24->24in32(high) %ld; 24->32 %ld\n", badLo, N, badHi, bad32);
    CHECK(badLo == 0 && badHi == 0 && bad32 == 0, "24-bit exhaustive");

    // Requantisation behaviour (a 24-bit source on a 16-bit-only device): truncation toward zero.
    long dead = 0;
    int minNeg = 0;
    for (int v = -(1 << 23); v < (1 << 23); ++v) {
        size_t i = size_t(v + (1 << 23));
        std::vector<float> one{f24[i]};
        auto o = conv(one, 1, 16, false, true, false, 2);
        int16_t q = le16(o.data());
        if (q == 0) ++dead;
        (void)minNeg;
    }
    std::printf("[pure fn] 24->16 requantise: %ld of 2^24 codes map to 0 (floor would map 256, round-nearest 256)\n", dead);

    // Float sources: +1.0 and slightly-over values.
    std::vector<float> edge{1.0f, -1.0f, 1.0000001f, 0.99999994f, -0.99999994f};
    auto e16 = conv(edge, 1, 16, false, true, false, 2);
    std::printf("[pure fn] float edges ->16: +1.0=%d -1.0=%d 1.0000001=%d 0.99999994=%d -0.99999994=%d\n",
                le16(&e16[0]), le16(&e16[2]), le16(&e16[4]), le16(&e16[6]), le16(&e16[8]));
}

// Low-level sine requantised 24->16 by the production truncation vs round-to-nearest: harmonic level.
static void truncationDistortion() {
    // 997 Hz at -70 dBFS (24-bit source) requantised to a 16-bit device by the production truncation,
    // vs round-to-nearest. Error = output - exact source; report error power and its correlated part.
    const int fs = 48000, n = 480000;
    const double f0 = 997.0, amp = std::pow(10.0, -70.0 / 20.0);
    std::vector<float> x(n);
    for (int i = 0; i < n; ++i) x[size_t(i)] = float(std::round(amp * std::sin(2 * M_PI * f0 * i / fs) * 8388608.0) / 8388608.0);
    auto o = conv(x, 1, 16, false, true, false, 2);
    double et = 0, er = 0, sig = 0, h3t = 0, h3r = 0, h3ti = 0, h3ri = 0;
    for (int i = 0; i < n; ++i) {
        double xs = x[size_t(i)];
        double t = le16(&o[2 * size_t(i)]) / 32768.0, r = std::round(xs * 32768.0) / 32768.0;
        et += (t - xs) * (t - xs); er += (r - xs) * (r - xs); sig += xs * xs;
        double c = std::cos(2 * M_PI * 3 * f0 * i / fs), s = std::sin(2 * M_PI * 3 * f0 * i / fs);
        h3t += (t - xs) * c; h3ti += (t - xs) * s; h3r += (r - xs) * c; h3ri += (r - xs) * s;
    }
    double a3t = 2 * std::hypot(h3t, h3ti) / n, a3r = 2 * std::hypot(h3r, h3ri) / n;
    std::printf("[requant 24->16, 997 Hz @ -70 dBFS] error power re signal: truncate %.1f dB, round %.1f dB; "
                "H3 amplitude re fundamental: truncate %.1f dB, round %.1f dB\n",
                10 * std::log10(et / sig), 10 * std::log10(er / sig), 20 * std::log10(a3t / amp), 20 * std::log10(a3r / amp + 1e-30));
}

// Real decoder end-to-end: write WAVs holding every code, decode with the given backend, convert.
static std::vector<float> decodeAll(const std::string& path, const char* backend, uint32_t& chOut) {
    setenv("ADAPTIVESOUND_DECODER", backend, 1);
    FileDecodeSource src;
    std::vector<float> all;
    if (!src.open(path.c_str())) { std::printf("open failed (%s)\n", backend); return all; }
    chOut = src.channels();
    std::vector<float> buf(4096 * chOut);
    for (;;) {
        uint32_t got = src.pullFloat(buf.data(), 4096, chOut);
        all.insert(all.end(), buf.begin(), buf.begin() + long(got * chOut));
        if (got < 4096) {
            if (src.exhausted()) break;
            std::this_thread::sleep_for(std::chrono::microseconds(200));
        }
    }
    unsetenv("ADAPTIVESOUND_DECODER");
    return all;
}

static void decoderEndToEnd(const std::string& dir) {
    // 16-bit stereo: L = every code ascending, R = every code descending.
    std::vector<int32_t> s16;
    for (int v = -32768; v < 32768; ++v) { s16.push_back(v); s16.push_back(-1 - v); }
    const std::string p16 = dir + "/all16.wav";
    writeWav(p16, s16, {}, 2, 44100, 16, false);
    std::vector<int32_t> s24;
    s24.reserve(size_t(1) << 24);
    for (int v = -(1 << 23); v < (1 << 23); v += 1) { s24.push_back(v); }
    // stereo: pair consecutive codes -> 2^23 frames
    const std::string p24 = dir + "/all24.wav";
    writeWav(p24, s24, {}, 2, 96000, 24, false);

    for (const char* be : {"apple", "ffmpeg"}) {
        uint32_t ch = 0;
        auto d16 = decodeAll(p16, be, ch);
        long bad = 0;
        if (d16.size() != s16.size()) std::printf("[%s] 16-bit decoded %zu samples, expected %zu\n", be, d16.size(), s16.size());
        auto o = conv(d16, 2, 16, false, true, false, 2);
        for (size_t i = 0; i < std::min(d16.size(), s16.size()); ++i) bad += le16(&o[2 * i]) != s16[i];
        std::printf("[decode %s] 16-bit file -> 16-bit device: %ld mismatches of %zu\n", be, bad, s16.size());
        CHECK(bad == 0 && d16.size() == s16.size(), "decode 16 %s", be);

        auto d24 = decodeAll(p24, be, ch);
        if (d24.size() != s24.size()) std::printf("[%s] 24-bit decoded %zu samples, expected %zu\n", be, d24.size(), s24.size());
        auto o24 = conv(d24, 2, 24, false, false, true, 4);
        auto o32 = conv(d24, 2, 32, false, true, false, 4);
        long b24 = 0, b32 = 0;
        for (size_t i = 0; i < std::min(d24.size(), s24.size()); ++i) {
            b24 += le32(&o24[4 * i]) != (uint32_t(s24[i]) << 8);
            b32 += int32_t(le32(&o32[4 * i])) != s24[i] * 256;
        }
        std::printf("[decode %s] 24-bit file -> 24in32(high): %ld mismatches; -> 32-bit: %ld (of %zu)\n", be, b24, b32, s24.size());
        CHECK(b24 == 0 && b32 == 0 && d24.size() == s24.size(), "decode 24 %s", be);
    }
}

int main(int argc, char** argv) {
    const std::string dir = argc > 1 ? argv[1] : ".";
    pureFunctionExhaustive();
    truncationDistortion();
    decoderEndToEnd(dir);
    std::printf("H1 done: %d failure(s)\n", failures);
    return failures ? 1 : 0;
}
