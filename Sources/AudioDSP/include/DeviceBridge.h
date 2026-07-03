#pragma once

//
// DeviceBridge.h — Pure C header for Swift bridging.
//
// This header is included via the Swift bridging header and MUST be valid
// ISO C11 (no C++ namespaces, no #include <cstdint>, no class declarations).
// It declares only the CDeviceInfo struct and the C-ABI device functions.
//

#include <stdint.h>

// Re-export the pure-C AU registration surface so the single Swift bridging header
// (this file) also exposes registerAdaptiveAudioUnitSubclass() +
// adaptiveAudioUnitComponentDescription() to Swift. Pure C; safe for all includers.
#include "AudioUnitRegistrationBridge.h"

// Re-export the pure-C Pure-Mode bridge so the same single SwiftPM bridging header
// (Package.swift uses -import-objc-header DeviceBridge.h) exposes pureModeQueryCapability /
// pureModeEngine* / pureModeEvaluate to Swift. Pure C11; #pragma once guards double-include.
#include "PureModeBridge.h"

// Re-export the pure-C metadata bridge (S8.3) so `import AudioDSP` (LibraryScan) exposes
// the opaque-handle FFmpeg-metadata API (ffmpegOpenMetadata / ffmpegCloseMetadata +
// the ffmpegMetadata* accessors) to Swift for the FFmpeg-fallback extractor.
// Pure C11; #pragma once guards double-include.
#include "MetadataBridge.h"

// MARK: - CDeviceInfo

/// Flat C struct representing one audio output device.
/// Populated by enumerateOutputDevicesC() for Swift consumption.
/// All fields are plain-old-data — safe to zero-initialize.
///
/// deviceType encoding (matches AdaptiveSound::AudioDevice::Type):
///   0 = Unknown
///   1 = Builtin
///   2 = USB
///   3 = Wireless
typedef struct
{
    uint32_t deviceID;        ///< Real CoreAudio AudioDeviceID
    uint32_t sampleRate;      ///< Nominal sample rate (Hz)
    uint32_t bufferFrameSize; ///< Hardware buffer frame size in frames
    uint8_t deviceType;       ///< 0=Unknown 1=Builtin 2=USB 3=Wireless
    // C-ABI fixed-size name buffer: a plain C array is required for Swift bridging
    // and the C ABI (std::array is neither C-compatible nor bridgeable here).
    // NOLINTNEXTLINE(cppcoreguidelines-avoid-c-arrays,modernize-avoid-c-arrays,hicpp-avoid-c-arrays,cppcoreguidelines-avoid-magic-numbers,readability-magic-numbers)
    char name[256]; ///< Device name (UTF-8, null-terminated)
} CDeviceInfo;

// MARK: - CLoudnessReadout

/// Flat C struct: the latest BS.1770-5 loudness readout for the UI meters.
/// Values are LUFS except peakDb (sample-peak dBFS). Unmeasured = very negative.
typedef struct
{
    double integratedLufs;
    double shortTermLufs;
    double momentaryLufs;
    double peakDb;
} CLoudnessReadout;

// MARK: - C-ABI device functions

#ifdef __cplusplus
extern "C"
{
#endif

    // MARK: - C-ABI loudness meter (BS.1770-5 LufsMeter, fed from the playback tap)

    /// Create an opaque loudness-meter handle for the given sample rate.
    /// Returns NULL on allocation failure. Destroy with loudnessMeterDestroy().
    void* loudnessMeterCreate(double sampleRate);

    /// Destroy a handle from loudnessMeterCreate(). NULL-safe.
    void loudnessMeterDestroy(void* meter);

    /// Feed non-interleaved stereo frames (audio-tap thread; no allocation/lock).
    /// Pass right == left for mono.
    void
    loudnessMeterAddStereo(void* meter, const float* left, const float* right, uint32_t frames);

    /// Read the latest measured loudness (any thread; lock-free).
    CLoudnessReadout loudnessMeterRead(void* meter);

    /// Enumerate output devices and populate the caller-supplied array.
    ///
    /// @param outDevices  Caller-allocated array of CDeviceInfo; must fit maxCount entries.
    /// @param maxCount    Capacity of outDevices.
    /// @return            Number of entries written (0 on error or no devices found).
    uint32_t enumerateOutputDevicesC(CDeviceInfo* outDevices, uint32_t maxCount);

    /// Return the default output device ID, or 0 if none is available.
    uint32_t getDefaultOutputDeviceID(void);

    /// Verify that a device ID is valid and live; returns 1 on success, 0 on failure.
    /// Also used by selectOutputDeviceC to validate before queuing the change.
    int selectOutputDeviceC(uint32_t deviceID);

#ifdef __cplusplus
} // extern "C"
#endif
