#include "FileDecodeSource.h"
#include <chrono>
#include <cmath>
#include <cstdio>
#include <thread>
#include <vector>
#include <cstdlib>
using namespace AdaptiveSound;
int main(int argc, char** argv) {
    const char* backend = argc > 3 ? argv[3] : "apple";
    setenv("ADAPTIVESOUND_DECODER", backend, 1);
    double target = std::atof(argv[2]);
    FileDecodeSource s;
    if (!s.open(argv[1])) return 1;
    std::this_thread::sleep_for(std::chrono::milliseconds(200));
    std::vector<float> buf(4800 * 2);
    s.pullFloat(buf.data(), 4800, 2);
    long long ll = std::llround(std::max(target, 0.0) * s.sampleRate());
    bool ok = s.seek(target);
    std::this_thread::sleep_for(std::chrono::milliseconds(200));
    uint32_t got = s.pullFloat(buf.data(), 4800, 2);
    std::printf("[%s] seek(%g): llround(target*rate)=%lld ok=%d produced=%u first L/R codes: %ld %ld  %ld %ld\n", backend, target, ll, ok, got,
                std::lround(buf[0] * 32768), std::lround(buf[1] * 32768), std::lround(buf[2] * 32768), std::lround(buf[3] * 32768));
}
