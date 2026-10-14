// Probe-only: expose LimiterModule internals to fuzz the monotonic-deque window max against brute force.
#include <cstdint>
#include <array>
#include <vector>
#define private public
#include "Limiting/LimiterModule.h"
#undef private
#include <cstdio>
#include <random>
#include <deque>
using namespace AdaptiveSound;
int main(){
  for (uint32_t fs : {44100u, 48000u, 96000u, 192000u, 384000u}) {
    auto* lim = new LimiterModule(); lim->initialize(fs, 512);
    const uint32_t L = lim->lookaheadFrames_;
    std::mt19937 rng(fs); std::uniform_real_distribution<double> u(0,1); std::vector<double> hist; size_t bad=0;
    for (size_t n=0;n<2000000;++n){ double v = (u(rng)<0.3)? 0.5 : u(rng)*u(rng); if (n%5000<50) v=1.0-n*1e-9; hist.push_back(v);
      double got = lim->updatePeakDeque(v); double ref=0; for (size_t k=(n+1>L? n+1-L:0); k<=n; ++k) ref=std::max(ref,hist[k]);
      if (got!=ref) ++bad; if (lim->dequeCount_>kPeakDequeCapacity) { printf("overflow\n"); return 1; } }
    printf("fs=%u L=%u (=%.3f ms) mismatches=%zu\n", fs, L, 1000.0*L/fs, bad); delete lim; }
}
