#pragma once

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

        // Device listener callback type (called off-RT, safe for light work)
        using DeviceListenerCallback = void (*)(AudioDeviceID deviceID, void* context);

        // Add/remove device listeners
        static bool addDefaultDeviceListener(DeviceListenerCallback callback, void* context);
        static bool removeDefaultDeviceListener();

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

        // Static listener state
        static DeviceListenerCallback gListenerCallback;
        static void* gListenerContext;

        // Core Audio listener callback trampoline. The C-array parameter is
        // mandated by the Core Audio listener ABI and cannot be changed.
        // NOLINTBEGIN(cppcoreguidelines-avoid-c-arrays, modernize-avoid-c-arrays)
        static void listenerCallback(AudioObjectID objectID,
                                     UInt32 numberAddresses,
                                     const AudioObjectPropertyAddress inAddresses[],
                                     void* clientData);
        // NOLINTEND(cppcoreguidelines-avoid-c-arrays, modernize-avoid-c-arrays)

        // Non-instantiable
        CoreAudioDevice() = delete;
        ~CoreAudioDevice() = delete;
        CoreAudioDevice(const CoreAudioDevice&) = delete;
        CoreAudioDevice& operator=(const CoreAudioDevice&) = delete;
        CoreAudioDevice(CoreAudioDevice&&) = delete;
        CoreAudioDevice& operator=(CoreAudioDevice&&) = delete;
    };

} // namespace AdaptiveSound
