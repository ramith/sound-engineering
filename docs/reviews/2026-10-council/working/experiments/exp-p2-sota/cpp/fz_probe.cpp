#include <cstdio>
#include <cstdint>
#include <cmath>
#include <limits>
__attribute__((noinline)) double mul(double a, double b){ return a*b; }
__attribute__((noinline)) float mulf(float a, float b){ return a*b; }
static uint64_t rd(){ return __builtin_arm_rsr64("fpcr"); }
int main(){
  uint64_t f0=rd();
  double d0=mul(std::numeric_limits<double>::min(),0.5); float x0=mulf(std::numeric_limits<float>::min(),0.5f);
  __builtin_arm_wsr64("fpcr", f0 | (1ULL<<24));
  uint64_t f1=rd();
  double d1=mul(std::numeric_limits<double>::min(),0.5); float x1=mulf(std::numeric_limits<float>::min(),0.5f);
  // also: subnormal INPUT treated as zero?
  double sub = std::numeric_limits<double>::denorm_min()*4; // compile-time subnormal constant
  double d2=mul(sub, 1.0);
  printf("FPCR before=0x%llx FZ=%d: double=%a(sub=%d) float=%g(sub=%d)\n",(unsigned long long)f0,(int)((f0>>24)&1),d0,std::fpclassify(d0)==FP_SUBNORMAL,(double)x0,std::fpclassify(x0)==FP_SUBNORMAL);
  printf("FPCR after =0x%llx FZ=%d: double=%a(sub=%d) float=%g(sub=%d); subnormal input*1 = %g\n",(unsigned long long)f1,(int)((f1>>24)&1),d1,std::fpclassify(d1)==FP_SUBNORMAL,(double)x1,std::fpclassify(x1)==FP_SUBNORMAL,d2);
}
