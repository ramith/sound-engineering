// Drives the REAL LoudnessModule (worker thread + LufsMeter + updateMakeupGain) across a 3-"track"
// session with NO reset between tracks (as in production: nothing resets the meter on a track change).
#include "Loudness/LoudnessModule.h"
#include "Loudness/LufsMeter.h"
#include <cstdio>
#include <vector>
#include <cmath>
#include <random>
#include <thread>
using namespace AdaptiveSound;
struct ABL2 { std::vector<float> l, r; std::vector<char> mem; AudioBufferList* abl;
  ABL2(uint32_t n): l(n), r(n) { mem.resize(sizeof(AudioBufferList)+sizeof(AudioBuffer)); abl=(AudioBufferList*)mem.data();
    abl->mNumberBuffers=2; abl->mBuffers[0]={1,(UInt32)(n*4),l.data()}; abl->mBuffers[1]={1,(UInt32)(n*4),r.data()}; } };
int main() {
  const uint32_t fs=48000, blk=512;
  struct Track { const char* name; double gain; double seconds; };
  // pink-ish noise; gains chosen for ≈ -9 LUFS (loud pop master) and ≈ -26 LUFS (quiet classical)
  std::vector<Track> tracks = {{"A loud",0.9,150},{"B quiet",0.12,150},{"C loud",0.9,150}};
  // calibrate the levels with the real LufsMeter first
  std::mt19937 rng(3); std::normal_distribution<double> g(0,1);
  auto pinkGen=[&](){ static double b0=0,b1=0,b2=0; double w=g(rng); b0=0.99765*b0+w*0.0990460; b1=0.96300*b1+w*0.2965164; b2=0.57000*b2+w*1.0526913; return (b0+b1+b2+w*0.1848)*0.11; };
  LoudnessModule mod; mod.initialize(fs, blk);
  LoudnessParams p{}; p.enabled=1; p.lufsTarget=-16.f;
  ABL2 b(blk); double t=0; uint32_t nb=0;
  for (auto& tr: tracks) {
    LufsMeter m; m.prepare(fs);
    size_t total=(size_t)(tr.seconds*fs);
    for (size_t off=0; off<total; off+=blk) {
      for (uint32_t i=0;i<blk;++i){ float s=(float)(tr.gain*pinkGen()); b.l[i]=s; b.r[i]=s; }
      m.addNonInterleavedStereo(b.l.data(), b.r.data(), blk);
      mod.process(p, MultichannelView::fromABL(b.abl, blk));
      t += (double)blk/fs; if ((++nb % 32)==0) std::this_thread::sleep_for(std::chrono::microseconds(1500));
      static double nextPrint=0; if (t>=nextPrint) { printf("t=%6.1f s  track %-8s  measured(module I)=%7.2f LUFS  makeup=%+6.2f dB\n", t, tr.name, mod.measuredLufsIntegrated(), 20*std::log10(mod.currentMakeupGainLinear())); nextPrint += 15; }
    }
    printf("   -> track %s own integrated loudness = %.2f LUFS (target -16: ideal track gain %+.2f dB)\n", tr.name, m.integratedLufs(), -16-m.integratedLufs());
  }
  std::this_thread::sleep_for(std::chrono::milliseconds(200));
  printf("dropped frames: %llu\n", (unsigned long long)mod.droppedFrameCount());
}
