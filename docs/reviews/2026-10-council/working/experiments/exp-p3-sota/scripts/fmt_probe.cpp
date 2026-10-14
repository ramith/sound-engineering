// Drives the REAL convertFloatToNative (worktree PureModeFormat.cpp) with cases the tests omit.
#include "PureModeFormat.h"
#include <cstdio>
#include <cstdint>
#include <cstring>
#include <vector>
#include <cmath>
using namespace AdaptiveSound;
int main() {
    // 1) 24-bit PACKED (3 bytes/sample, kAudioFormatFlagIsPacked, mBitsPerChannel=24): the HAL
    //    render bound computes bytesPerSample = ceil(24/8) = 3, so the buffer it hands over is
    //    frames*ch*3 bytes. Count how many bytes convertFloatToNative writes past that.
    const uint32_t frames = 512, ch = 2;
    const size_t bufBytes = size_t(frames) * ch * 3;  // what a packed-24 ABL buffer holds
    std::vector<uint8_t> mem(bufBytes + 4096, 0xAA);     // guard zone after the buffer
    std::vector<float> src(size_t(frames) * ch, 0.25f);
    convertFloatToNative(src.data(), mem.data(), frames, ch, 24, /*isFloat*/false, /*signed*/true,
                         /*packed*/true, /*alignedHigh*/false, /*bigEndian*/false);
    size_t lastWritten = 0;
    for (size_t i = 0; i < mem.size(); ++i) if (mem[i] != 0xAA) lastWritten = i;
    std::printf("packed-24: buffer=%zu bytes, last byte written at offset %zu -> overrun %zd bytes\n",
                bufBytes, lastWritten, (ssize_t)lastWritten + 1 - (ssize_t)bufBytes);
    // Also: is the layout 3-byte? read sample 1 as 3-byte LE
    int32_t s1 = mem[3] | (mem[4] << 8) | (int8_t(mem[5]) << 16);
    std::printf("packed-24: sample[1] read as 3-byte LE = %d (expected 0.25*2^23 = %d)\n", s1, int(0.25 * 8388608));

    // 2) truncation vs round-to-nearest: values off the integer grid (lossy decode / gain / 24->16)
    const float lsb16 = 1.0f / 32768.0f;
    float vals[] = {0.75f * lsb16, -0.75f * lsb16, 1.6f * lsb16, -1.6f * lsb16};
    for (float v : vals) {
        int16_t out = 0;
        convertFloatToNative(&v, &out, 1, 1, 16, false, true, true, false, false);
        std::printf("int16: in=%+.2f LSB -> out=%d (round-to-nearest would give %ld)\n",
                    v / lsb16, out, std::lround(double(v) * 32768.0));
    }
    // 3) mean error of truncation on a low-level sine (DC bias / dead zone) for int16
    double errSum = 0, errSq = 0; int n = 48000; int zeroRun = 0;
    for (int i = 0; i < n; ++i) {
        float v = 3.0f * lsb16 * float(std::sin(2 * M_PI * 997.0 * i / 48000.0));
        int16_t out; convertFloatToNative(&v, &out, 1, 1, 16, false, true, true, false, false);
        double e = double(out) - double(v) * 32768.0; errSum += e; errSq += e * e;
        if (out == 0) ++zeroRun;
    }
    std::printf("int16 trunc on a 3-LSB sine: mean err %.3f LSB, rms err %.3f LSB (round: rms 0.289), zeros %d/%d\n",
                errSum / n, std::sqrt(errSq / n), zeroRun, n);
    return 0;
}
