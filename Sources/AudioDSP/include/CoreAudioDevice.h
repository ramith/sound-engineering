#pragma once

#include "DeviceCapability.h" // CoreAudio-free; safe to include here
#include <CoreAudio/CoreAudio.h>
#include <cstdint>
#include <string>
#include <vector>

namespace AdaptiveSound
{

    // Audio device information
    struct AudioDevice
    {
        enum class Type : std::uint8_t
        {
            Builtin,
            USB,
            Wireless,
            Unknown
        };

        AudioDeviceID id = 0;
        std::string name;
        uint32_t sampleRate = 0;
        uint32_t bufferFrameSize = 0;
        Type type = Type::Unknown;
    };

    // Core Audio device enumeration and management
    class CoreAudioDevice
    {
      public:
        // Enumerate all output devices
        static std::vector<AudioDevice> enumerateOutputDevices();

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

        // Determine device type (builtin, USB, wireless, etc.)
        static AudioDevice::Type getDeviceType(AudioDeviceID deviceID);

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
