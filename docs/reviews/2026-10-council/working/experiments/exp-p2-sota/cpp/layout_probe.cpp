// Real LoudnessModule + ChannelLayoutDecoder: what does the normaliser measure for a 6-ch stream
// (a) right after initialize() (= after any AU re-allocation; nobody republishes the layout), and
// (b) after publishing the tags AVAudioFile actually reports for common 5.1 files?
#include "Loudness/LoudnessModule.h"
#include "Loudness/ChannelLayoutDecoder.h"
#include <cstdio>
#include <vector>
#include <cmath>
#include <thread>
using namespace AdaptiveSound;
static double run(LoudnessModule& mod, int activeCh, uint32_t fs) {
  const uint32_t blk=512; std::vector<std::vector<float>> ch(6, std::vector<float>(blk));
  std::vector<char> mem(sizeof(AudioBufferList)+5*sizeof(AudioBuffer)); auto* abl=(AudioBufferList*)mem.data(); abl->mNumberBuffers=6;
  for(int c=0;c<6;++c) abl->mBuffers[c]={1,blk*4,ch[c].data()};
  LoudnessParams p{}; p.enabled=1; double t=0;
  for (int b=0;b<(int)(6.0*fs/blk);++b){ for(int c=0;c<6;++c) for(uint32_t i=0;i<blk;++i) ch[c][i] = (c==activeCh)? (float)(0.0708*std::sin(2*M_PI*1000.0*(b*blk+i)/fs)) : 0.f;
    mod.process(p, MultichannelView::fromABL(abl, blk)); if (b%32==0) std::this_thread::sleep_for(std::chrono::microseconds(1500)); }
  std::this_thread::sleep_for(std::chrono::milliseconds(100));
  return mod.measuredLufsIntegrated(); }
int main(){
  const uint32_t fs=48000; const char* names[6]={"L","R","C","ch3","ch4","ch5"};
  printf("-23 dBFS 1 kHz in ONE channel of a 6-ch stream; BS.1770 expects -23.0 (L/R/C), excluded (LFE), -21.5 (Ls/Rs)\n");
  struct Case{ const char* label; bool publish; AudioChannelLayoutTag tag; };
  Case cases[]={{"after initialize() (no publish)",false,0},{"MPEG_5_1_A (correct)",true,kAudioChannelLayoutTag_MPEG_5_1_A},
                {"MPEG_5_1_D / AAC_5_1 (ALAC/AAC .m4a)",true,kAudioChannelLayoutTag_MPEG_5_1_D},{"DiscreteInOrder|6 (plain WAV)",true,kAudioChannelLayoutTag_DiscreteInOrder|6}};
  for (auto& cs: cases){ printf("  %-38s", cs.label);
    for (int a=0;a<6;++a){ LoudnessModule mod; mod.initialize(fs,512); if (cs.publish) mod.publishChannelLayout(decodeChannelLayout(cs.tag));
      double v=run(mod,a,fs); printf(" %s=%6.1f", names[a], v); }
    printf("\n"); }
}
