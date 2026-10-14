// Real CrossfeedModule; params derived with the Realizer's formula (Realizer.mm:74-117, copied verbatim in math).
#include "Spatial/CrossfeedModule.h"
#include <cstdio>
#include <vector>
#include <cmath>
using namespace AdaptiveSound;
struct ABL2 { std::vector<float> l, r; std::vector<char> mem; AudioBufferList* abl;
  ABL2(uint32_t n): l(n), r(n) { mem.resize(sizeof(AudioBufferList)+sizeof(AudioBuffer)); abl=(AudioBufferList*)mem.data();
    abl->mNumberBuffers=2; abl->mBuffers[0]={1,(UInt32)(n*4),l.data()}; abl->mBuffers[1]={1,(UInt32)(n*4),r.data()}; } };
int main(){
  const uint32_t fs=48000, blk=512;
  struct P{const char* n; float fc, a;} ps[]={{"Relaxed",650,0.335f},{"Bauer",700,0.355f},{"Strong",700,0.501f}};
  for (auto& pr: ps) {
    CrossfeedParams p{}; p.enabled=1; float alpha=pr.a; p.gDirect=1/(1+alpha); p.gCross=alpha/(1+alpha);
    float pole=std::exp(-(6.28318530717958647692f*pr.fc)/fs); p.lpfPole=pole; p.lpfB0=1-pole; p.delayFrames=(int)std::lround(0.0003178*fs);
    printf("%-8s mono-in response (dB):", pr.n);
    for (double f: {100.0, 500.0, 900.0, 1000.0, 1200.0, 2000.0, 3000.0, 5000.0, 10000.0}) {
      CrossfeedModule m; m.initialize(fs, blk); ABL2 b(blk); double num=0, den=0;
      for (int k=0;k<200;++k){ for (uint32_t i=0;i<blk;++i){ double t=(k*blk+i)/(double)fs; float s=(float)(0.25*std::sin(2*M_PI*f*t)); b.l[i]=s; b.r[i]=s; }
        m.process(p, MultichannelView::fromABL(b.abl, blk));
        if (k>=100) for (uint32_t i=0;i<blk;++i){ double t=(k*blk+i)/(double)fs; double s=0.25*std::sin(2*M_PI*f*t); num+=b.l[i]*(double)b.l[i]; den+=s*s; } }
      printf(" %g:%+.2f", f, 10*std::log10(num/den));
    }
    printf("\n");
  }
}
