#pragma once

//
// DeviceBridge.h — Pure C header for Swift.
//
// This header is the AudioDSP module's one Swift-visible header (module.modulemap; Swift
// writes `import AudioDSP`) and MUST be valid ISO C11 (no C++ namespaces, no
// #include <cstdint>, no class declarations). It declares only the CDeviceInfo struct and
// the C-ABI device functions.
//

#include "CApiNoexcept.h"
#include <stdint.h>

// Re-export the pure-C AU registration surface so the module's single Swift-visible header
// (this file) also exposes registerAdaptiveAudioUnitSubclass() +
// adaptiveAudioUnitComponentDescription() to Swift. Pure C; safe for all includers.
#include "AudioUnitRegistrationBridge.h"

// Re-export the pure-C Pure-Mode bridge so the same single Swift-visible header
// (`import AudioDSP`) exposes pureModeQueryCapability /
// pureModeEngine* / pureModeEvaluate to Swift. Pure C11; #pragma once guards double-include.
#include "PureModeBridge.h"

// Re-export the pure-C metadata bridge (S8.3) so `import AudioDSP` (LibraryScan) exposes
// the opaque-handle FFmpeg-metadata API (ffmpegOpenMetadata / ffmpegCloseMetadata +
// the ffmpegMetadata* accessors) to Swift for the FFmpeg-fallback extractor.
// Pure C11; #pragma once guards double-include.
#include "MetadataBridge.h"

// Re-export the pure-C FFmpeg switch (R1.1-A, FD-3): "Use FFmpeg for other formats", off by
// default — ffmpegSetEnabled / ffmpegIsEnabled / ffmpegState. Pure C11; #pragma once guards.
#include "FFmpegBridge.h"

// Re-export the pure-C graphic-EQ designer (Sprint EQ, EQ1a) so `import AudioDSP` exposes
// asEqDesignerCreate / asEqDesign / asEqDesignerDestroy to the Swift EQDesigner wrapper.
// Pure C11; #pragma once guards double-include.
#include "EQDesignBridge.h"

// Re-export the pure-C track loudness profiler + loudness-change predictor (Sprint EQ, EQ1c) so
// `import AudioDSP` exposes the asLoudnessProfiler* / asLoudnessProfile* / asLoudnessPredictChangeDb
// API to the Swift TrackLoudnessAnalyzer. Pure C11; #pragma once guards double-include.
#include "TrackLoudnessBridge.h"

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
///
/// The device's UID and model UID are strings of unbounded length, so they are read per device
/// with copyOutputDeviceUIDC / copyOutputDeviceModelUIDC rather than carried here.
typedef struct
{
    uint32_t deviceID;        ///< Real CoreAudio AudioDeviceID
    uint32_t sampleRate;      ///< Nominal sample rate (Hz)
    uint32_t bufferFrameSize; ///< Hardware buffer frame size in frames
    uint32_t transportType;   ///< kAudioDevicePropertyTransportType FourCC (0 = unknown)
    uint8_t deviceType;       ///< 0=Unknown 1=Builtin 2=USB 3=Wireless
    uint8_t isHeadphones;     ///< 1 = headphones (where crossfeed plays; classifyOutputDevice)
    // Fixed-size C name buffer, for Swift (`import AudioDSP`). All four suppressed rules are
    // irreducible in THIS file, which must be valid ISO C11 (see the file header): the c-array
    // rules can't use std::array (not valid C / not Swift-bridgeable), and every way to NAME the
    // 256 bound trips a worse check under C11 — a macro fires macro-to-enum, and a plain enum
    // fires performance-enum-size (which wants a uint16_t base type, a C23 feature). So the bound
    // stays a literal and avoid-magic-numbers rides on the same already-required suppression.
    // NOLINTNEXTLINE(cppcoreguidelines-avoid-c-arrays,modernize-avoid-c-arrays,cppcoreguidelines-avoid-magic-numbers) PERMANENT reason="C11 ABI name buffer: std::array/named-bound unavailable in ISO C11 (see comment)"
    char name[256]; ///< Device name (UTF-8, null-terminated)
} CDeviceInfo;

// MARK: - CLoudnessReadout

/// Flat C struct: the latest BS.1770-5 loudness readout for the UI meters.
/// Values are LUFS except truePeakDb — inter-sample TRUE peak in dBTP (8× polyphase ISP,
/// the shared TruePeakKernel; was sample-peak before S10.8 PR E). Unmeasured = very negative.
typedef struct
{
    double integratedLufs;
    double shortTermLufs;
    double momentaryLufs;
    double truePeakDb;
} CLoudnessReadout;

// MARK: - C-ABI device functions

#ifdef __cplusplus
extern "C"
{
#endif

    // MARK: - C-ABI loudness meter (BS.1770-5 LufsMeter, fed from the playback tap)

    /// Create an opaque loudness-meter handle for the given sample rate.
    /// Returns NULL on allocation failure. Destroy with loudnessMeterDestroy().
    void* loudnessMeterCreate(double sampleRate) AUDIODSP_C_NOEXCEPT;

    /// Destroy a handle from loudnessMeterCreate(). NULL-safe.
    void loudnessMeterDestroy(void* meter) AUDIODSP_C_NOEXCEPT;

    /// Feed non-interleaved stereo frames (audio-tap thread; no allocation/lock).
    /// Pass right == left for mono.
    void loudnessMeterAddStereo(void* meter, const float* left, const float* right, uint32_t frames)
        AUDIODSP_C_NOEXCEPT;

    /// Read the latest measured loudness (any thread; lock-free).
    CLoudnessReadout loudnessMeterRead(void* meter) AUDIODSP_C_NOEXCEPT;

    /// The track `trackToken` became audible (any thread but the tap's; lock-free). "Integrated"
    /// measures the playing track: a different track starts a new measurement interval, the same
    /// one announced again (a resume, a seek) continues it, and 0 (an unknown track) always starts
    /// one. The tap applies it at its next buffer. NULL-safe.
    void loudnessMeterBeginTrack(void* meter, uint64_t trackToken) AUDIODSP_C_NOEXCEPT;

    /// Enumerate output devices and populate the caller-supplied array.
    ///
    /// @param outDevices  Caller-allocated array of CDeviceInfo; must fit maxCount entries.
    /// @param maxCount    Capacity of outDevices.
    /// @return            Number of entries written (0 on error or no devices found).
    uint32_t enumerateOutputDevicesC(CDeviceInfo* outDevices,
                                     uint32_t maxCount) AUDIODSP_C_NOEXCEPT;

    /// Copy a device's persistent UID (kAudioDevicePropertyDeviceUID) into `out` as UTF-8,
    /// NUL-terminated and truncated to fit `capacity` bytes. Returns the UID's full length in
    /// bytes (excluding the NUL), snprintf-style: a result >= capacity means `out` was too small
    /// and holds a truncated copy. Returns 0 when the device has no UID. `out` may be NULL only
    /// with capacity 0 (to ask for the length).
    uint32_t
    copyOutputDeviceUIDC(uint32_t deviceID, char* out, uint32_t capacity) AUDIODSP_C_NOEXCEPT;

    /// Same contract as copyOutputDeviceUIDC, for the model UID (kAudioDevicePropertyModelUID),
    /// which every unit of the same model shares. Returns 0 when the device reports none.
    uint32_t
    copyOutputDeviceModelUIDC(uint32_t deviceID, char* out, uint32_t capacity) AUDIODSP_C_NOEXCEPT;

    /// 1 when the output-device menu would list this device (the same rule as
    /// enumerateOutputDevicesC: an output stream, not hidden, not a process-private aggregate),
    /// else 0. A Bluetooth device mid-handshake has no output stream yet, so it reads 0.
    int isListedOutputDeviceC(uint32_t deviceID) AUDIODSP_C_NOEXCEPT;

    /// Return the default output device ID, or 0 if none is available.
    uint32_t getDefaultOutputDeviceID(void) AUDIODSP_C_NOEXCEPT;

    /// Verify that a device ID is valid and live; returns 1 on success, 0 on failure.
    /// Also used by selectOutputDeviceC to validate before queuing the change.
    int selectOutputDeviceC(uint32_t deviceID) AUDIODSP_C_NOEXCEPT;

#ifdef __cplusplus
} // extern "C"
#endif
