#include "FileDecodeSource.h"
#include <algorithm>
#include <chrono>
#include <cstdio>
#include <memory>
#include <vector>
using namespace AdaptiveSound;
int main(int, char** argv) {
    std::vector<double> us;
    for (int i = 0; i < 200; ++i) {
        auto t0 = std::chrono::steady_clock::now();
        auto s = std::make_unique<FileDecodeSource>();
        bool ok = s->open(argv[1]);
        us.push_back(std::chrono::duration<double, std::micro>(std::chrono::steady_clock::now() - t0).count());
        if (!ok) return 1;
    }
    std::sort(us.begin(), us.end());
    std::printf("FileDecodeSource::open on a cached local WAV: min %.0f us, p50 %.0f us, max %.0f us\n", us[0], us[100], us.back());
}
