// seq <rate> <cmds.f32 K x 31> <frames.f64 K switch frames> <len> <probeHz> <out.f64 envelope>
// Publishes like the Realizer: design each command, rampsFor(previous published, next). Probe = cos/sin pair on L/R.
#include "EQ/GraphicEQDesigner.h"
#include "EQ/EQModule.h"
#include "EQ/EQTargets.h"
#include <cstdio>
#include <cstdlib>
#include <vector>
#include <cmath>
#include <fenv.h>
using namespace AdaptiveSound;
template<class T> std::vector<T> rd(const char* p){FILE*f=fopen(p,"rb");fseek(f,0,SEEK_END);long n=ftell(f);fseek(f,0,SEEK_SET);std::vector<T> v(n/sizeof(T));fread(v.data(),sizeof(T),v.size(),f);fclose(f);return v;}
int main(int, char** argv){
  double fs=atof(argv[1]); auto cmds=rd<float>(argv[2]); auto sw=rd<double>(argv[3]); long len=atol(argv[4]); double hz=atof(argv[5]);
  size_t K=cmds.size()/31; auto* d=new GraphicEQDesigner(); std::vector<EQParams> ps(K); GraphicEQDesign prev{};
  for(size_t k=0;k<K;++k){GraphicEQDesign des{}; if(!d->design(std::span<const float,31>(cmds.data()+k*31,31),fs,des)) return 3;
    ps[k]= k==0? EQTargets::toParams(des,0.01f) : EQTargets::toParams(des,EQTargets::rampsFor(prev,des)); prev=des;}
  EQModule m; m.initialize((uint32_t)fs,512); fesetenv(FE_DFL_DISABLE_DENORMS_ENV);
  std::vector<float> L(512),R(512); FILE* out=fopen(argv[6],"wb"); size_t cur=0;
  for(long pos=0;pos<len;pos+=64){ int fr=(int)std::min<long>(64,len-pos);
    while(cur+1<K && pos>=(long)sw[cur+1]) ++cur;
    for(int i=0;i<fr;++i){double ph=2*M_PI*hz*(pos+i)/fs; L[i]=0.25f*(float)cos(ph); R[i]=0.25f*(float)sin(ph);}
    AudioBufferList* abl=(AudioBufferList*)calloc(1,sizeof(AudioBufferList)+sizeof(AudioBuffer)*2); abl->mNumberBuffers=2; abl->mBuffers[0].mData=L.data(); abl->mBuffers[1].mData=R.data();
    m.update(ps[cur]); m.process(MultichannelView::fromABL(abl,fr));
    for(int i=0;i<fr;++i){double e=std::hypot((double)L[i],(double)R[i])/0.25; fwrite(&e,8,1,out);} free(abl);}
  fclose(out); return 0;}
