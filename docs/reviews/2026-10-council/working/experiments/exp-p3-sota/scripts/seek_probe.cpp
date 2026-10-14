// Drives the REAL FileDecodeSource: seek(s) must land on frame llround(s*rate) of the stream that
// open() decodes from the start (the "sample-accurate seek" contract, FileDecodeSource.h:58-64).
#include "FileDecodeSource.h"
#include <chrono>
#include <cmath>
#include <cstdio>
#include <thread>
#include <vector>
using namespace AdaptiveSound;
static std::vector<float> pullN(FileDecodeSource& s, size_t frames) {
    const uint32_t ch = s.channels();
    std::vector<float> out; std::vector<float> buf(512 * ch);
    while (out.size() < frames * ch) {
        uint32_t got = s.pullFloat(buf.data(), 512, ch);
        out.insert(out.end(), buf.begin(), buf.begin() + size_t(got) * ch);
        if (got < 512) { if (s.exhausted()) break; std::this_thread::sleep_for(std::chrono::milliseconds(2)); }
    }
    out.resize(std::min(out.size(), frames * ch));
    return out;
}
int main(int argc, char** argv) {
    const char* path = argv[1]; const double target = atof(argv[2]);
    FileDecodeSource ref; if (!ref.open(path)) { std::printf("open failed\n"); return 1; }
    const double rate = ref.sampleRate(); const uint32_t ch = ref.channels();
    const size_t tgt = size_t(std::llround(target * rate));
    std::vector<float> all = pullN(ref, tgt + 8192);
    FileDecodeSource s; if (!s.open(path)) return 1;
    std::this_thread::sleep_for(std::chrono::milliseconds(50));
    if (!s.seek(target)) { std::printf("seek failed\n"); return 1; }
    std::vector<float> got = pullN(s, 4096);
    // find the offset of got[0..1023] inside `all` around tgt
    long best = 0; double bestErr = 1e9;
    for (long d = -4000; d <= 4000; ++d) {
        long base = long(tgt) + d; if (base < 0 || size_t(base + 1024) * ch > all.size()) continue;
        double e = 0; for (size_t k = 0; k < 1024 * ch; ++k) e = std::max(e, double(std::fabs(got[k] - all[size_t(base) * ch + k])));
        if (e < bestErr) { bestErr = e; best = d; }
    }
    std::printf("%s backend=%s rate=%.0f ch=%u: seek(%.3f) landed at frame %+ld relative to llround(s*rate) (max|e| at best alignment = %.2e)\n",
                path, s.decoderKind() == DecoderKind::FFmpeg ? "ffmpeg" : "apple", rate, ch, target, best, bestErr);
    return 0;
}
