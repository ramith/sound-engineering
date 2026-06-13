#pragma once

#include <CoreAudio/CoreAudio.h>
#include <string>
#include <vector>

namespace AdaptiveSound
{

    // Audio device information
    struct AudioDevice
    {
        AudioDeviceID id;
        std::string name;
        uint32_t sampleRate;
        uint32_t bufferFrameSize;

        enum Type
        {
            Builtin,
            USB,
            Wireless,
            Unknown
        };
        Type type;
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
    };

} // namespace AdaptiveSound
