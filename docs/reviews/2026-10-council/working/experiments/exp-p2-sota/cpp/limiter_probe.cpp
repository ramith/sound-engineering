// Drives the REAL LimiterModule.h. (1) release law: after a single transient, what τ does GR recover with?
// (2) dumps output for adversarial signals so an independent 64x oracle can measure true peak.
#include "Limiting/LimiterModule.h"
#include <cstdio>
#include <vector>
#include <cmath>
#include <random>
using namespace AdaptiveSound;
struct ABL2 { std::vector<float> l, r; AudioBufferList* abl; std::vector<char> mem;
  ABL2(uint32_t n): l(n), r(n) { mem.resize(sizeof(AudioBufferList)+sizeof(AudioBuffer)); abl=(AudioBufferList*)mem.data();
    abl->mNumberBuffers=2; abl->mBuffers[0]={1,(UInt32)(n*4),l.data()}; abl->mBuffers[1]={1,(UInt32)(n*4),r.data()}; } };
static std::vector<float> run(const std::vector<float>& x, uint32_t fs, float ceil, uint32_t block, std::vector<float>* grOut=nullptr) {
  LimiterModule lim; lim.initialize(fs, block); LimiterParams p{}; p.truePeakCeilingLinear = ceil;
  std::vector<float> y(x.size()); ABL2 b(block);
  for (size_t off=0; off<x.size(); off+=block) { uint32_t n = (uint32_t)std::min<size_t>(block, x.size()-off);
    for (uint32_t i=0;i<n;++i){ b.l[i]=x[off+i]; b.r[i]=x[off+i]; }
    b.abl->mBuffers[0].mDataByteSize=n*4; b.abl->mBuffers[1].mDataByteSize=n*4;
    lim.process(p, MultichannelView::fromABL(b.abl, n));
    for (uint32_t i=0;i<n;++i) y[off+i]=b.l[i]; }
  return y; }
int main(int argc, char** argv) {
  const uint32_t fs = argc>1 ? (uint32_t)atoi(argv[1]) : 48000; const float ceil = 0.891F; const uint32_t blk = 512;
  // (1) release probe: steady 1 kHz sine at -10 dBFS (no GR) with one 5 ms burst at +6 dBFS in the middle.
  size_t N = fs*4; std::vector<float> x(N);
  for (size_t n=0;n<N;++n) { double a = 0.316; if (n>=fs && n<fs+fs/200) a = 2.0; x[n]=(float)(a*std::sin(2*M_PI*1000.0*n/fs)); }
  auto y = run(x, fs, ceil, blk);
  const size_t L = (size_t)std::lround(0.003*fs);
  // gain = y[n]/x[n-L] at sine peaks; print GR (dB) at times after the burst
  printf("fs=%u release probe (GR after a 5 ms +6 dBFS burst on a -10 dBFS sine):\n", fs);
  for (double t : {1.010, 1.05, 1.06, 1.1, 1.2, 1.3, 1.5, 1.7, 2.0, 2.5, 3.0}) {
    size_t c = (size_t)(t*fs); double best=0; size_t bi=c;
    for (size_t n=c; n<c+fs/1000*2; ++n) if (std::fabs(x[n-L])>best){best=std::fabs(x[n-L]); bi=n;}
    printf("  t=%.3f s  GR=%7.3f dB\n", t, 20*std::log10(std::fabs(y[bi]/x[bi-L])));
  }
  // (2) adversarial signals for the true-peak oracle: written as raw float32 mono
  std::mt19937 rng(7); std::normal_distribution<double> g(0,1);
  struct Sig { const char* name; std::vector<float> v; };
  std::vector<Sig> sigs;
  { // isolated full-recovery transients at +20 dBFS (20+ dB GR from rest), 2 s apart, broadband click+HF tone
    std::vector<float> v(fs*8,0.f);
    for (int k=0;k<3;++k){ size_t s0=fs*(1+2*k); for (size_t n=0;n<fs/100;++n) v[s0+n]=(float)(10.0*std::sin(2*M_PI*(fs*0.45)*n/fs+0.7)); }
    sigs.push_back({"burst_+20dB_0.45fs", v}); }
  { std::vector<float> v(fs*8,0.f);
    for (int k=0;k<3;++k){ size_t s0=fs*(1+2*k); for (size_t n=0;n<fs/100;++n) v[s0+n]=(float)(10.0*g(rng)); }
    sigs.push_back({"noiseburst_+20dB", v}); }
  { std::vector<float> v(fs*8,0.f); // single-sample impulses (Nyquist-rich) at +12 dBFS
    for (int k=0;k<6;++k){ size_t s0=fs*(1+k); v[s0]=4.0f; v[s0+1]=-4.0f; }
    sigs.push_back({"doublet_+12dB", v}); }
  { std::vector<float> v(fs*6,0.f); // loud master proxy: clipped pink-ish noise at +6 dBFS RMS-ish
    double b0=0,b1=0,b2=0; for (size_t n=0;n<v.size();++n){ double w=g(rng); b0=0.99765*b0+w*0.0990460; b1=0.96300*b1+w*0.2965164; b2=0.57000*b2+w*1.0526913; double p=(b0+b1+b2+w*0.1848)*0.6; v[n]=(float)std::clamp(p*2.0,-1.0,1.0)*1.9f; }
    sigs.push_back({"clipped_pink_x1.9", v}); }
  for (auto& s : sigs) {
    auto out = run(s.v, fs, ceil, blk);
    char fn[256]; snprintf(fn, sizeof fn, "%s/out_%s_%u.f32", argc>2?argv[2]:".", s.name, fs);
    FILE* f=fopen(fn,"wb"); fwrite(out.data(),4,out.size(),f); fclose(f);
    snprintf(fn, sizeof fn, "%s/in_%s_%u.f32", argc>2?argv[2]:".", s.name, fs);
    f=fopen(fn,"wb"); fwrite(s.v.data(),4,s.v.size(),f); fclose(f);
  }
  return 0; }
