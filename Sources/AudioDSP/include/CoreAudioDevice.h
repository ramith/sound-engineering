#pragma once

#include "DeviceCapability.h" // CoreAudio-free; safe to include here
#include "DeviceListPolicy.h" // HAL-free menu rule over DeviceListFacts
#include <CoreAudio/CoreAudio.h>
#include <cstdint>
#include <string>
#include <vector>

namespace AdaptiveSound
{

    // Audio device information
    struct AudioDevice
    {
        using Type = OutputDeviceType; // the family (DeviceListPolicy.h)

        AudioDeviceID id = 0;
        std::string name;
        uint32_t sampleRate = 0;
        uint32_t bufferFrameSize = 0;
        Type type = Type::Unknown;
        uint32_t transportType = 0; // kAudioDevicePropertyTransportType FourCC; 0 = unknown
        bool isHeadphones = false;  // where crossfeed plays (classifyOutputDevice)
    };

    // Core Audio device enumeration and management
    class CoreAudioDevice
    {
      public:
        // Enumerate the output devices a user may pick: every device deviceListVerdict() lists
        // (DeviceListPolicy.h) — no input-only, hidden or process-private devices.
        static std::vector<AudioDevice> enumerateOutputDevices();

        // Whether the menu would list this one device (the same deviceListVerdict). A Bluetooth
        // device mid-handshake is not listed yet: it has no output stream.
        static bool isListedOutput(AudioDeviceID deviceID);

        // Query properties of a specific device
        static AudioDevice queryDevice(AudioDeviceID deviceID);

        // Get default output device
        static AudioDeviceID getDefaultOutputDevice();

        // Get device name from ID
        static std::string getDeviceName(AudioDeviceID deviceID);

        // Get device sample rate
        static uint32_t getDeviceSampleRate(AudioDeviceID deviceID);

        // Get device buffer frame size
        static uint32_t getDeviceBufferFrameSize(AudioDeviceID deviceID);

        // Get the device's transport (kAudioDevicePropertyTransportType FourCC, e.g.
        // kAudioDeviceTransportTypeBluetooth); 0 when unavailable.
        static uint32_t getDeviceTransportType(AudioDeviceID deviceID);

        // Get the device's persistent UID (kAudioDevicePropertyDeviceUID): the same output across
        // reconnects and reboots, unlike its AudioDeviceID. Empty when unavailable.
        static std::string getDeviceUID(AudioDeviceID deviceID);

        // Get the device's model UID (kAudioDevicePropertyModelUID): shared by every unit of the
        // same model. Empty when the device reports none.
        static std::string getDeviceModelUID(AudioDeviceID deviceID);

        // The device's selected output data source (kAudioDevicePropertyDataSource, output
        // scope: an IOAudioTypes.h port code such as 'hdpn' or 'ispk'); 0 when it reports none.
        static uint32_t getDeviceDataSource(AudioDeviceID deviceID);

        // MARK: - Pure-Mode capability querying (Phase B — B1)

        // Discrete set of nominal sample rates the device advertises (Hz), output scope.
        // For a discrete range (mMinimum == mMaximum) the single rate is reported; for a
        // continuous range (mMinimum != mMaximum) both endpoints are reported.
        static std::vector<double> getAvailableSampleRates(AudioDeviceID deviceID);

        // Decode the first OUTPUT stream's virtual (physical == false) or physical
        // (physical == true) format into a StreamFormatInfo. Returns a zeroed struct on failure.
        static StreamFormatInfo getStreamFormat(AudioDeviceID deviceID, bool physical);

        // Fully populate a DeviceCapability for the given device (Pure-Mode model).
        static DeviceCapability queryCapability(AudioDeviceID deviceID);

      private:
        // Read the properties the device-list rule decides on (the HAL half of
        // deviceListVerdict). Off the audio thread; releases every CF object it copies.
        static DeviceListFacts readDeviceListFacts(AudioDeviceID deviceID);

        // Helper: Convert device ID to name
        static std::string deviceNameFromID(AudioDeviceID deviceID);

        // Helper: Get audio object property as string
        static std::string getStringProperty(AudioObjectID objectID,
                                             const AudioObjectPropertyAddress& address);

        // Helper: Get audio object property as uint32
        static uint32_t getUInt32Property(AudioObjectID objectID,
                                          const AudioObjectPropertyAddress& address,
                                          uint32_t defaultValue = 0);

        // Non-instantiable
        CoreAudioDevice() = delete;
        ~CoreAudioDevice() = delete;
        CoreAudioDevice(const CoreAudioDevice&) = delete;
        CoreAudioDevice& operator=(const CoreAudioDevice&) = delete;
        CoreAudioDevice(CoreAudioDevice&&) = delete;
        CoreAudioDevice& operator=(CoreAudioDevice&&) = delete;
    };

} // namespace AdaptiveSound
