#include <cstdio>
#include <cstdint>
static uint64_t rd(){ return __builtin_arm_rsr64("fpcr"); }
int main(){
  volatile double a = 1e-300, b = 1e-10; volatile float fa = 1e-30f, fb = 1e-10f;
  std::printf("fpcr at start = 0x%llx\n", (unsigned long long)rd());
  double d0 = a*b; float f0 = fa*fb;
  std::printf("before: double %g float %g\n", d0, (double)f0);
  uint64_t f = rd(); f |= (1ULL<<24); __builtin_arm_wsr64("fpcr", f);
  std::printf("fpcr after = 0x%llx\n", (unsigned long long)rd());
  double d1 = a*b; float f1 = fa*fb;
  volatile double sub = 1e-310; double d2 = sub * 1.0; double d3 = sub + 0.0;
  std::printf("after: double %g float %g ; subnormal input*1 = %g, +0 = %g\n", d1, (double)f1, d2, d3);
}
