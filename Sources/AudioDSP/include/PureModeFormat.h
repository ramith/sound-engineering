#pragma once

//
// PureModeFormat.h — bit-exact float -> device-native PCM conversion (Pure Mode).
//
// CoreAudio-FREE BY DESIGN, exactly like DeviceCapability.h: no CoreAudio / Obj-C headers, so the
// C++ test harness (which links neither) can unit-test the conversion. -fno-exceptions / -fno-rtti
// clean (no throw / dynamic_cast / typeid).
//
// The engine extracts the format flags from the AU's ACTUAL chosen AudioStreamBasicDescription and
// passes them here as plain booleans, so this stays a pure function with no AudioToolbox
// dependency.
//

#include <cstdint>

namespace AdaptiveSound
{

    // Convert `frames * channels` interleaved float samples in [-1, 1] to the device's native PCM
    // sample format, writing into `dst`. RT-SAFE: noexcept, no allocation, no locks. Out-of-range
    // inputs are saturated to the destination range (never wrapped). An unsupported flag
    // combination writes silence (all-zero bytes for the frame span) rather than invoking undefined
    // behaviour.
    //
    // Parameters mirror the decoded fields of an AudioStreamBasicDescription:
    //   bitsPerChannel : valid sample bits (16, 24 or 32 are handled)
    //   isFloat        : kAudioFormatFlagIsFloat            (float32 passthrough)
    //   isSignedInt    : kAudioFormatFlagIsSignedInteger    (integer PCM is signed)
    //   isPacked       : kAudioFormatFlagIsPacked           (no padding bits in the word)
    //   isAlignedHigh  : kAudioFormatFlagIsAlignedHigh      (sample left-justified in its word)
    //   isBigEndian    : kAudioFormatFlagIsBigEndian        (false == little-endian, the Mac norm)
    //
    // Container/width handling (the cases that actually occur on macOS output devices):
    //   * float32                              -> raw passthrough (bit-identical)
    //   * 16-bit signed packed                 -> int16 little/big-endian
    //   * 32-bit signed packed                 -> int32 little/big-endian
    //   * 24-bit signed in a 32-bit container  -> isAlignedHigh ? left-justified : low-justified
    //
    // The format is decided ONCE per call; the per-sample loop is branch-free on the format.
    void convertFloatToNative(const float* src,
                              void* dst,
                              uint32_t frames,
                              uint32_t channels,
                              uint32_t bitsPerChannel,
                              bool isFloat,
                              bool isSignedInt,
                              bool isPacked,
                              bool isAlignedHigh,
                              bool isBigEndian) noexcept;

} // namespace AdaptiveSound
