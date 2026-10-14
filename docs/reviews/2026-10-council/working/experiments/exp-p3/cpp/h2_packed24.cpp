// H2: a 24-bit PACKED (3-byte) device format through the REAL convertFloatToNative, with the buffer
// sized the way the HAL sizes it (frames * channels * 3 bytes) and the HAL render clamp
// writableFrames = mDataByteSize / (ceil(24/8) * ch) reproduced from HALOutputEngine.mm:866-874.
#include "PureModeFormat.h"
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <vector>
using namespace AdaptiveSound;
int main(int argc, char**) {
    const uint32_t frames = 512, ch = 2, bits = 24;
    std::vector<float> src(frames * ch, 0.25f);
    const uint32_t mDataByteSize = frames * ch * 3;            // 3-byte packed 24-bit: mBytesPerFrame = 6
    const uint32_t bytesPerSample = (bits + 7U) / 8U;           // HALOutputEngine render(): 3
    const uint32_t writable = std::min(frames, mDataByteSize / (bytesPerSample * ch));
    std::printf("HAL clamp lets %u of %u frames through; the converter will write %u bytes into %u\n",
                writable, frames, writable * ch * 4, mDataByteSize);
    if (argc > 1) {   // NaN probe (UBSan float-cast-overflow)
        std::vector<float> nanv(2, std::nanf(""));
        std::vector<uint8_t> o(8);
        convertFloatToNative(nanv.data(), o.data(), 1, 2, 16, false, true, true, false, false);
        std::printf("NaN -> int16 bytes %02x%02x\n", o[1], o[0]);
        return 0;
    }
    uint8_t* buf = static_cast<uint8_t*>(std::malloc(mDataByteSize));   // exactly the HAL's buffer
    convertFloatToNative(src.data(), buf, writable, ch, bits, /*isFloat*/ false, /*signed*/ true,
                         /*packed*/ true, /*alignedHigh*/ false, /*bigEndian*/ false);
    // If we got here without ASan: show the stream is not 3-byte packed either.
    std::printf("bytes 0..11: ");
    for (int i = 0; i < 12; ++i) std::printf("%02x ", buf[i]);
    std::printf("\n(3-byte packed 0.25 would read 00 00 20 00 00 20 ...)\n");
    std::free(buf);
    return 0;
}
