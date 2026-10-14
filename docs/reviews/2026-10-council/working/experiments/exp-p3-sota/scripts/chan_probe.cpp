// HALOutputEngine::render pulls `rfChannels_` = the AU/device channel count (HALOutputEngine.mm:821,845).
// Drive the REAL GaplessSource/FileDecodeSource the way render does for a file whose channel count
// differs from the device's (mono file on a stereo device; stereo file on a 4-ch interface).
#include "FileDecodeSource.h"
#include "GaplessSource.h"
#include <chrono>
#include <cstdio>
#include <memory>
#include <thread>
#include <vector>
using namespace AdaptiveSound;
int main(int argc, char** argv) {
    const char* path = argv[1]; const uint32_t deviceCh = uint32_t(atoi(argv[2]));
    auto src = std::make_unique<FileDecodeSource>(); if (!src->open(path)) return 1;
    const uint32_t fileCh = src->channels();
    GaplessSource g; g.setCurrent(std::move(src));
    std::this_thread::sleep_for(std::chrono::milliseconds(100));
    std::vector<float> buf(512 * deviceCh, 9.f);
    uint64_t produced = 0; double peak = 0;
    for (int i = 0; i < 200; ++i) {
        produced += g.pullFloat(buf.data(), 512, deviceCh);
        for (float v : buf) peak = std::max(peak, double(std::fabs(v)));
        std::this_thread::sleep_for(std::chrono::milliseconds(1));
    }
    std::printf("file ch=%u, device ch=%u: frames produced over 200 render calls = %llu, output peak = %.3f, position = %.3f s\n",
                fileCh, deviceCh, (unsigned long long)produced, peak, double(g.renderedFramesCurrent()) / g.currentSampleRate());
}
