#pragma once

//
// DeviceBridge.h — Pure C header for Swift bridging.
//
// This header is included via the Swift bridging header and MUST be valid
// ISO C11 (no C++ namespaces, no #include <cstdint>, no class declarations).
// It declares only the CDeviceInfo struct and the C-ABI device functions.
//

#include <stdint.h>

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
    char name[256];           ///< Device name (UTF-8, null-terminated)
} CDeviceInfo;

// MARK: - C-ABI device functions

#ifdef __cplusplus
extern "C"
{
#endif

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
