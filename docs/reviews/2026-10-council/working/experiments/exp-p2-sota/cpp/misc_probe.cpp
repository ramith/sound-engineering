#include "include/FlushToZero.h"
#include "include/ParameterRamp.h"
#include <cstdio>
#include <cmath>
#include <limits>
#include <cstring>
using namespace AdaptiveSound;
int main(int argc, char**){
  // (1) Does AArch64 FPCR.FZ flush DOUBLE subnormals? (LufsMeter.h:123-128 claims it does NOT.)
  volatile double tiny = std::numeric_limits<double>::min(); // smallest normal
  volatile double half = 0.5;
  double before = tiny*half; // subnormal result without FZ
  enableFlushToZero();
  double after = tiny*half;
  volatile float tf = std::numeric_limits<float>::min(); volatile float hf=0.5f; float fafter = tf*hf;
  printf("double min*0.5: before FZ=%g (subnormal=%d)  after FZ=%g (subnormal=%d); float after FZ=%g\n",
    before, std::fpclassify(before)==FP_SUBNORMAL, after, std::fpclassify(after)==FP_SUBNORMAL, (double)fafter);
  // (2) ParameterRamp float stagnation: makeup ramp (50 ms @ 48k) from 0.5 back to 1.0 — does it ever get within 1e-6?
  ParameterRamp r; r.initialize(0.050f, 48000.f); r.target=0.5f; r.snap(); r.target=1.0f;
  for (int i=0;i<48000*30;++i) r.tick();
  printf("makeup ramp after 30 s toward 1.0: current=%.9f  |diff|=%.3g  (LoudnessModule identity epsilon 1e-6)\n", r.current, std::fabs(r.current-1.0f));
  ParameterRamp r2; r2.initialize(0.050f, 48000.f); r2.target=2.0f; r2.snap(); r2.target=1.0f;
  for (int i=0;i<48000*30;++i) r2.tick();
  printf("makeup ramp from 2.0 down to 1.0: current=%.9f |diff|=%.3g\n", r2.current, std::fabs(r2.current-1.0f));
}
