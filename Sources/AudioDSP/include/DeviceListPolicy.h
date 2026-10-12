#pragma once

//
// DeviceListPolicy.h — which CoreAudio devices the output-device menu may list (Sprint G).
//
// The pure half of device enumeration. CoreAudioDevice.cpp reads each device's properties into a
// DeviceListFacts (the only part that talks to the HAL); deviceListVerdict() decides from those
// facts alone whether a user may see and pick the device. Keeping the rule here, HAL-free, lets
// the C++ test harness check every case with hand-built facts and no real hardware.
//
// What is hidden: devices with no output stream; devices CoreAudio marks hidden; aggregates that
// are private to the process that built them — above all the `CADefaultDeviceAggregate-<pid>-<n>`
// CoreAudio builds around the default devices for this app's own I/O. What stays: every other
// output, including user-made aggregates (Audio MIDI Setup), virtual devices (BlackHole,
// Microsoft Teams Audio), USB DACs, Bluetooth and AirPlay.
//
// Off the audio thread: enumeration runs on the engine's control queue, never the render block.
//

#include <CoreFoundation/CoreFoundation.h>
#include <cstdint>
#include <string>

namespace AdaptiveSound
{

    // Whether an aggregate device is published to the whole system or private to the process
    // that created it: the kAudioAggregateDeviceIsPrivateKey entry of the device's
    // kAudioAggregateDevicePropertyComposition dictionary (CoreAudio/AudioHardware.h).
    enum class AggregatePrivacy : std::uint8_t
    {
        NotAggregate, // the device has no aggregate composition (a plain device)
        Public,       // published system-wide: the key is 0, or absent (AudioHardware.h)
        Private,      // private to the creating process: the key is non-zero
        Unknown,      // an aggregate whose composition could not be read or decoded
    };

    // The device properties the menu rule reads. Filled by CoreAudioDevice::readDeviceListFacts.
    struct DeviceListFacts
    {
        std::uint32_t outputStreamCount = 0; // buffers in kAudioDevicePropertyStreamConfiguration
        bool isHidden = false;               // kAudioDevicePropertyIsHidden is non-zero
        AggregatePrivacy aggregatePrivacy = AggregatePrivacy::NotAggregate;
        std::string uid;  // kAudioDevicePropertyDeviceUID
        std::string name; // kAudioObjectPropertyName
    };

    // Whether the menu lists a device, or the first rule that keeps it out.
    enum class DeviceListVerdict : std::uint8_t
    {
        Listed,                  // a user may see and pick it
        NoOutputStream,          // input-only, or an output not ready yet (BT mid-handshake)
        Hidden,                  // CoreAudio marks it hidden
        PrivateAggregate,        // an aggregate private to the process that built it
        ProcessDefaultAggregate, // CoreAudio's per-process default-device aggregate, by UID/name
    };

    // The menu rule: Listed exactly when a user may see and pick the device. Pure; no HAL calls.
    [[nodiscard]] DeviceListVerdict deviceListVerdict(const DeviceListFacts& facts);

    // Decode an aggregate's composition dictionary (kAudioAggregateDevicePropertyComposition) into
    // its privacy. Reads the dictionary only — the caller keeps ownership and releases it. A null
    // dictionary or a private value that is neither a CFNumber nor a CFBoolean is Unknown.
    [[nodiscard]] AggregatePrivacy aggregatePrivacyFromComposition(CFDictionaryRef composition);

    // Human-readable names for logging and tests. Never return nullptr.
    [[nodiscard]] const char* deviceListVerdictString(DeviceListVerdict verdict);
    [[nodiscard]] const char* aggregatePrivacyString(AggregatePrivacy privacy);

} // namespace AdaptiveSound
