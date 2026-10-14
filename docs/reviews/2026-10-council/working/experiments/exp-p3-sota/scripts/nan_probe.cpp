#include "PureModeFormat.h"
#include <cstdio>
#include <cmath>
#include <cstdint>
using namespace AdaptiveSound;
int main() {
    float v[2] = {NAN, -NAN}; int16_t o16[2]; int32_t o24[2];
    convertFloatToNative(v, o16, 2, 1, 16, false, true, true, false, false);
    convertFloatToNative(v, o24, 2, 1, 24, false, true, false, true, false);
    std::printf("NaN -> int16 %d %d, 24in32 0x%08x 0x%08x\n", o16[0], o16[1], (unsigned)o24[0], (unsigned)o24[1]);
}
