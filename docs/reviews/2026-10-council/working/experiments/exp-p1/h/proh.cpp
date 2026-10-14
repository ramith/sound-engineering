// pred <srcRate> <outRate> <channels> <planar.f32 (ch x n)> <cmds.f32 K x 31> <out.f64>
// writes: sourceLufs, blockCount, then per command: ok, ΔL (all blocks), ΔL(step 4)
#include "Loudness/TrackLoudnessProfiler.h"
#include "Loudness/TrackLoudnessProfile.h"
#include "EQ/GraphicEQDesigner.h"
#include <cstdio>
#include <cstdlib>
#include <vector>
#include <cmath>
using namespace AdaptiveSound;
template<class T> std::vector<T> rd(const char* p){FILE*f=fopen(p,"rb");fseek(f,0,SEEK_END);long n=ftell(f);fseek(f,0,SEEK_SET);std::vector<T> v(n/sizeof(T));fread(v.data(),sizeof(T),v.size(),f);fclose(f);return v;}
int main(int, char** argv){
  double fsIn=atof(argv[1]), fsOut=atof(argv[2]); int ch=atoi(argv[3]); auto x=rd<float>(argv[4]); auto cmds=rd<float>(argv[5]);
  size_t n=x.size()/ch; TrackLoudnessProfiler::Format f{}; f.sampleRate=fsIn; f.channelCount=ch; for(int c=0;c<ch;++c) f.channelWeights[c]=1.0;
  auto p=TrackLoudnessProfiler::create(f); std::vector<const float*> ptr(ch);
  for(size_t pos=0;pos<n;pos+=65536){ size_t fr=std::min<size_t>(65536,n-pos); for(int c=0;c<ch;++c) ptr[c]=x.data()+c*n+pos; if(!p->feed(std::span<const float* const>(ptr.data(),ch),fr)) return 4;}
  auto prof=p->finish(); FILE* out=fopen(argv[6],"wb"); double s=prof->sourceLoudnessLufs, bc=prof->blockCount; fwrite(&s,8,1,out); fwrite(&bc,8,1,out);
  auto* d=new GraphicEQDesigner(); size_t K=cmds.size()/31;
  for(size_t k=0;k<K;++k){ GraphicEQDesign des{}; bool ok=d->design(std::span<const float,31>(cmds.data()+k*31,31),fsOut,des); double dl=NAN, dl4=NAN;
    bool a = ok && predictLoudnessChangeDb(*prof, des, 1U, dl); auto prior = makePinkPriorProfile(fsIn); bool b = ok && predictLoudnessChangeDb(*prior, des, 1U, dl4);
    double okd=(a&&b)?1:0; fwrite(&okd,8,1,out); fwrite(&dl,8,1,out); fwrite(&dl4,8,1,out);}
  // the profile itself, for my own Python predictor variant
  FILE* pf=fopen((std::string(argv[6])+".prof").c_str(),"wb"); fwrite(prof->bandPower.data(),4,prof->bandPower.size(),pf); fclose(pf);
  fclose(out); return 0;}
