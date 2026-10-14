#include <cstdio>
#include <cstdint>
#include <cstdlib>
__attribute__((noinline)) double mul(double a, double b){ return a*b; }
__attribute__((noinline)) float mulf(float a, float b){ return a*b; }
int main(int argc, char** argv){
  double a = strtod("2.2250738585072014e-308", nullptr); float af = strtof("1.17549435e-38", nullptr);
  printf("arch arm64=%d fpcr=0x%llx\n", (int)
#ifdef __aarch64__
  1
#else
  0
#endif
  , (unsigned long long)__builtin_arm_rsr64("fpcr"));
  printf("FZ=0: double %a  float %a\n", mul(a,0.5), (double)mulf(af,0.5f));
  __builtin_arm_wsr64("fpcr", __builtin_arm_rsr64("fpcr") | (1ULL<<24));
  printf("FZ=1: double %a  float %a\n", mul(a,0.5), (double)mulf(af,0.5f));
  uname: ;
}
