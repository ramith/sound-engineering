#include <cstdio>
#include <cstdlib>
#include <limits>
__attribute__((noinline)) double mul(double a, double b){ return a*b; }
int main(){
  double a = strtod("2.2250738585072014e-308", nullptr);
  printf("FZ=0 strtod-min*0.5=%a  limits-min*0.5=%a  equal-inputs=%d\n", mul(a,0.5), mul(std::numeric_limits<double>::min(),0.5), a==std::numeric_limits<double>::min());
}
