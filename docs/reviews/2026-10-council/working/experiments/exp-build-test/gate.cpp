#include "RenderGate.h"
#include <array>
#include <algorithm>
#include <cstdio>
#include <cstdlib>
using namespace AdaptiveSound;
int main(int argc,char**argv){
  int hogs = argc>1?atoi(argv[1]):0; // extra spinning threads
  RenderGate g; std::array<std::atomic<uint64_t>,64> src{}; std::atomic<bool> stop{false}, hogstop{false};
  std::atomic<uint64_t> pulls{0};
  std::thread r([&]{ while(!stop.load()){ if(g.tryEnter()){ uint64_t f=src[0].load(); volatile bool ok=true; for(auto&w:src) if(w.load()!=f) ok=false; g.leave(); pulls++; } } });
  std::vector<std::thread> hs; for(int i=0;i<hogs;i++) hs.emplace_back([&]{ volatile uint64_t x=0; while(!hogstop.load()) x++; });
  while(pulls==0) std::this_thread::yield();
  double worst=0, total=0; int fails=0; const int N=2000;
  for(int s=1;s<=N;s++){
    auto t0=std::chrono::steady_clock::now();
    bool ok=g.close(std::chrono::seconds{1});
    double ms=std::chrono::duration<double,std::milli>(std::chrono::steady_clock::now()-t0).count();
    if(!ok){fails++;continue;}
    worst=std::max(worst,ms); total+=ms;
    for(auto&w:src) w.store(s); g.open();
  }
  stop=true; r.join(); hogstop=true; for(auto&h:hs)h.join();
  printf("hogs=%d fails=%d worst_close_ms=%.3f mean=%.4f\n",hogs,fails,worst,total/N);
}
