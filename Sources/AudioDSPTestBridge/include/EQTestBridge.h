// EQTestBridge.h — Pure C header for Swift test bridging.
//
// MUST remain valid ISO C11 (no C++ namespaces, no class declarations, no <cstdint>). Imported by
// the Swift test target as its bridging header; implemented by EQTestBridge.cpp over the real
// production EQ: GraphicEQDesigner (the design) and EQModule (the real-time SVF cascade).

#pragma once

#include "CApiNoexcept.h"
#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C"
{
#endif

    // Design `points` (pointCount = 31 values in dB) at `sampleRate` and stream `frameCount`
    // samples of the mono signal in `ioBuffer` IN PLACE through ONE persistent production EQModule
    // (a stereo block with the signal on both channels; the left is returned), in 512-frame
    // blocks — the render-thread lifecycle. The design is adopted in the first block, so it plays
    // from the first sample (no glide). Returns false, leaving the buffer untouched, when the
    // design is rejected (wrong count, a non-finite point, a rate outside 44–768 kHz).
    bool eqStreamC(float* ioBuffer,
                   uint32_t frameCount,
                   const float* points,
                   uint32_t pointCount,
                   double sampleRate) AUDIODSP_C_NOEXCEPT;

    // The same design's played response (dB) at the 31 band centres, into `outCentreDb`
    // (31 floats). Returns false, writing nothing, when the design is rejected.
    bool eqPlayedCentresC(const float* points,
                          uint32_t pointCount,
                          double sampleRate,
                          float* outCentreDb) AUDIODSP_C_NOEXCEPT;

#ifdef __cplusplus
} // extern "C"
#endif
