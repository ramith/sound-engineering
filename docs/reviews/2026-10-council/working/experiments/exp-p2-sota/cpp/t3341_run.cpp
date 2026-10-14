// Runs the REAL LufsMeter + TruePeakKernel on EBU Tech 3341 minimum-requirement signals.
#include "Loudness/LufsMeter.h"
#include "include/TruePeakKernel.h"
#include <cstdio>
#include <vector>
#include <string>
#include <cmath>
using namespace AdaptiveSound;
int main(int argc, char** argv){
  const char* path=argv[1]; int fs=atoi(argv[2]); int ch=atoi(argv[3]);
  FILE* f=fopen(path,"rb"); fseek(f,0,SEEK_END); long bytes=ftell(f); fseek(f,0,SEEK_SET);
  std::vector<float> x(bytes/4); fread(x.data(),4,x.size(),f); fclose(f);
  size_t frames=x.size()/ch;
  LufsMeter m; m.prepare(fs);
  if (ch==6){ std::array<double,kMaxChannels> w{}; w={1,1,1,0,1.41253754,1.41253754,0,0}; m.configureChannels(6,w); }
  double maxM=-200,maxS=-200; std::vector<double> Ms; 
  const size_t hop=(size_t)std::lround(0.1*fs);
  for (size_t off=0; off<frames; off+=hop){ size_t n=std::min(hop,frames-off); m.addInterleaved(x.data()+off*ch,n,ch);
    maxM=std::max(maxM,m.momentaryLufs()); maxS=std::max(maxS,m.shortTermLufs()); Ms.push_back(m.momentaryLufs()); }
  TruePeakKernel::Coefficients c; TruePeakKernel::computeCoefficients(c);
  double tp=0, sp=0;
  for (int k=0;k<ch;++k){ TruePeakKernel::History h{}; for (size_t i=0;i<frames;++i){ for (int t=TruePeakKernel::kNumTaps-1;t>0;--t) h[t]=h[t-1]; h[0]=x[i*ch+k]; tp=std::max(tp,TruePeakKernel::phasePeak(h,c)); sp=std::max(sp,(double)std::fabs(x[i*ch+k])); } }
  // For c09/c12 report S/M after settle (constant check): min & max after 3 s (S) / 1 s (M)
  printf("%-26s I=%8.3f  maxM=%8.3f  maxS=%8.3f  TP=%7.3f dBTP (samplePeak %7.3f)\n", strrchr(path,'/')+1, m.integratedLufs(), maxM, maxS, 20*std::log10(tp), 20*std::log10(sp));
}
