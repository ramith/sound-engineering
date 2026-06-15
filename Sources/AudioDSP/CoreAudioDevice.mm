#include "CoreAudioDevice.h"
#include "AudioConstants.h"
#include <CoreFoundation/CoreFoundation.h>
#include <cstddef>

namespace AdaptiveSound {

// control-plane logging only (init/shutdown/device-change); never on the RT audio
// thread; fprintf varargs acceptable here. RT TUs keep the check.
// NOLINTBEGIN(cppcoreguidelines-pro-type-vararg)

// MARK: - Helper Functions

static std::string cfStringToStdString(CFStringRef cfStr) {
    if (cfStr == nullptr) {
        return "";
    }
    const char* cStr = CFStringGetCStringPtr(cfStr, kCFStringEncodingUTF8);
    if (cStr != nullptr) {
        return std::string(cStr);
    }

    CFIndex length = CFStringGetLength(cfStr);
    std::vector<char> buffer(static_cast<size_t>(length) + 1);
    CFStringGetCString(cfStr, buffer.data(), static_cast<CFIndex>(buffer.size()), kCFStringEncodingUTF8);
    return std::string(buffer.data());
}

// MARK: - Static Listener State

CoreAudioDevice::DeviceListenerCallback CoreAudioDevice::gListenerCallback = nullptr;
void* CoreAudioDevice::gListenerContext = nullptr;

// MARK: - Device Listener Implementation

// The C-array parameter is mandated by the Core Audio listener ABI.
void CoreAudioDevice::listenerCallback(
    AudioObjectID objectID [[maybe_unused]],
    UInt32 numberAddresses,
    const AudioObjectPropertyAddress inAddresses[], // NOLINT(cppcoreguidelines-avoid-c-arrays, modernize-avoid-c-arrays)
    void* clientData [[maybe_unused]]) {
    // Verify callback is registered
    if (gListenerCallback == nullptr) {
        return;
    }

    // Check if this is a default output device change
    for (UInt32 i = 0; i < numberAddresses; ++i) {
        if (inAddresses[i].mSelector == kAudioHardwarePropertyDefaultOutputDevice) {
            AudioDeviceID newDeviceID = getDefaultOutputDevice();
            if (newDeviceID != kAudioObjectUnknown && gListenerCallback != nullptr) {
                gListenerCallback(newDeviceID, gListenerContext);
            }
            break;
        }
    }
}

bool CoreAudioDevice::addDefaultDeviceListener(DeviceListenerCallback callback, void* context) {
    if (callback == nullptr) {
        return false;
    }

    // Store callback and context
    gListenerCallback = callback;
    gListenerContext = context;

    // Register listener for default output device changes
    AudioObjectPropertyAddress defaultDeviceAddr{
        kAudioHardwarePropertyDefaultOutputDevice,
        kAudioObjectPropertyScopeGlobal,
        kAudioObjectPropertyElementMain};

    OSStatus status = AudioObjectAddPropertyListenerBlock(
        kAudioObjectSystemObject,
        &defaultDeviceAddr,
        dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0),
        // Core Audio listener block ABI mandates the C-array parameter.
        ^(UInt32 inNumberAddresses, const AudioObjectPropertyAddress inAddresses[]) { // NOLINT(cppcoreguidelines-avoid-c-arrays, modernize-avoid-c-arrays)
          listenerCallback(kAudioObjectSystemObject, inNumberAddresses, inAddresses, context);
        });

    if (status != noErr) {
        fprintf(stderr, "[CoreAudioDevice] Failed to add device listener: %d\n", status);
        gListenerCallback = nullptr;
        gListenerContext = nullptr;
        return false;
    }

    fprintf(stderr, "[CoreAudioDevice] Device listener registered\n");
    return true;
}

bool CoreAudioDevice::removeDefaultDeviceListener() {
    if (gListenerCallback == nullptr) {
        return true;  // Already removed
    }

    // Note: We can't remove a block-based listener directly via Core Audio API,
    // but we can disable the callback by clearing the function pointer
    gListenerCallback = nullptr;
    gListenerContext = nullptr;

    fprintf(stderr, "[CoreAudioDevice] Device listener disabled\n");
    return true;
}

// MARK: - CoreAudioDevice Implementation

std::vector<AudioDevice> CoreAudioDevice::enumerateOutputDevices() {
    std::vector<AudioDevice> devices;

    AudioObjectPropertyAddress devicesPropertyAddr{
        kAudioHardwarePropertyDevices,
        kAudioObjectPropertyScopeGlobal,
        kAudioObjectPropertyElementMain};

    UInt32 devicesDataSize = 0;
    OSStatus status = AudioObjectGetPropertyDataSize(
        kAudioObjectSystemObject,
        &devicesPropertyAddr,
        0,
        nullptr,
        &devicesDataSize);

    if (status != noErr || devicesDataSize == 0) {
        fprintf(stderr, "[CoreAudioDevice] Failed to get device list size\n");
        return devices;
    }

    uint32_t deviceCount = devicesDataSize / sizeof(AudioDeviceID);
    std::vector<AudioDeviceID> deviceIDs(deviceCount);

    status = AudioObjectGetPropertyData(
        kAudioObjectSystemObject,
        &devicesPropertyAddr,
        0,
        nullptr,
        &devicesDataSize,
        deviceIDs.data());

    if (status != noErr) {
        fprintf(stderr, "[CoreAudioDevice] Failed to get device IDs\n");
        return devices;
    }

    // Filter for output-capable devices
    for (AudioDeviceID deviceID : deviceIDs) {
        // Check if device has output channels
        AudioObjectPropertyAddress outputChannelsAddr{
            kAudioDevicePropertyStreamConfiguration,
            kAudioObjectPropertyScopeOutput,
            kAudioObjectPropertyElementMain};

        UInt32 bufferListSize = 0;

        status = AudioObjectGetPropertyDataSize(
            deviceID,
            &outputChannelsAddr,
            0,
            nullptr,
            &bufferListSize);

        if (status == noErr && bufferListSize > 0) {
            // RAII-owned storage for the AudioBufferList (control-plane; size from API).
            std::vector<std::byte> bufferStorage(bufferListSize);
            auto* bufferList = reinterpret_cast<AudioBufferList*>(bufferStorage.data());
            status = AudioObjectGetPropertyData(
                deviceID,
                &outputChannelsAddr,
                0,
                nullptr,
                &bufferListSize,
                bufferList);

            if (status == noErr && bufferList->mNumberBuffers > 0) {
                AudioDevice device = queryDevice(deviceID);
                devices.push_back(device);
            }
        }
    }

    fprintf(stderr, "[CoreAudioDevice] Enumerated %zu output devices\n", devices.size());
    return devices;
}

AudioDevice CoreAudioDevice::queryDevice(AudioDeviceID deviceID) {
    AudioDevice device;
    device.id = deviceID;
    device.name = getDeviceName(deviceID);
    device.sampleRate = getDeviceSampleRate(deviceID);
    device.bufferFrameSize = getDeviceBufferFrameSize(deviceID);
    device.type = getDeviceType(deviceID);
    return device;
}

AudioDeviceID CoreAudioDevice::getDefaultOutputDevice() {
    AudioObjectPropertyAddress devicePropertyAddr{
        kAudioHardwarePropertyDefaultOutputDevice,
        kAudioObjectPropertyScopeGlobal,
        kAudioObjectPropertyElementMain};

    AudioDeviceID deviceID = kAudioObjectUnknown;
    UInt32 dataSize = sizeof(deviceID);

    OSStatus status = AudioObjectGetPropertyData(
        kAudioObjectSystemObject,
        &devicePropertyAddr,
        0,
        nullptr,
        &dataSize,
        &deviceID);

    if (status != noErr) {
        fprintf(stderr, "[CoreAudioDevice] Failed to get default output device\n");
        return kAudioObjectUnknown;
    }

    return deviceID;
}

std::string CoreAudioDevice::getDeviceName(AudioDeviceID deviceID) {
    AudioObjectPropertyAddress namePropertyAddr{
        kAudioObjectPropertyName,
        kAudioObjectPropertyScopeOutput,
        kAudioObjectPropertyElementMain};

    CFStringRef deviceName = nullptr;
    UInt32 dataSize = sizeof(CFStringRef);

    OSStatus status = AudioObjectGetPropertyData(
        deviceID,
        &namePropertyAddr,
        0,
        nullptr,
        &dataSize,
        static_cast<void*>(&deviceName));

    if (status != noErr || deviceName == nullptr) {
        return "Unknown Device";
    }

    std::string name = cfStringToStdString(deviceName);
    CFRelease(deviceName);
    return name;
}

uint32_t CoreAudioDevice::getDeviceSampleRate(AudioDeviceID deviceID) {
    AudioObjectPropertyAddress nominalSampleRateAddr{
        kAudioDevicePropertyNominalSampleRate,
        kAudioObjectPropertyScopeOutput,
        kAudioObjectPropertyElementMain};

    Float64 sampleRate = static_cast<Float64>(kDefaultSampleRate);
    UInt32 dataSize = sizeof(sampleRate);

    OSStatus status = AudioObjectGetPropertyData(
        deviceID,
        &nominalSampleRateAddr,
        0,
        nullptr,
        &dataSize,
        &sampleRate);

    if (status != noErr) {
        fprintf(stderr, "[CoreAudioDevice] Failed to get sample rate, using default 48 kHz\n");
        return kDefaultSampleRate;
    }

    return static_cast<uint32_t>(sampleRate);
}

uint32_t CoreAudioDevice::getDeviceBufferFrameSize(AudioDeviceID deviceID) {
    AudioObjectPropertyAddress bufferSizeAddr{
        kAudioDevicePropertyBufferFrameSize,
        kAudioObjectPropertyScopeOutput,
        kAudioObjectPropertyElementMain};

    UInt32 bufferSize = kDefaultMaxFrames;
    UInt32 dataSize = sizeof(bufferSize);

    OSStatus status = AudioObjectGetPropertyData(
        deviceID,
        &bufferSizeAddr,
        0,
        nullptr,
        &dataSize,
        &bufferSize);

    if (status != noErr) {
        fprintf(stderr, "[CoreAudioDevice] Failed to get buffer size, using default 512 frames\n");
        return kDefaultMaxFrames;
    }

    return bufferSize;
}

AudioDevice::Type CoreAudioDevice::getDeviceType(AudioDeviceID deviceID) {
    std::string deviceName = getDeviceName(deviceID);

    // Simple heuristic based on device name
    if (deviceName.contains("AirPods") ||
        deviceName.contains("Bluetooth") ||
        deviceName.contains("wireless")) {
        return AudioDevice::Type::Wireless;
    }

    if (deviceName.contains("USB")) {
        return AudioDevice::Type::USB;
    }

    if (deviceName.contains("Built-in")) {
        return AudioDevice::Type::Builtin;
    }

    return AudioDevice::Type::Unknown;
}

std::string CoreAudioDevice::deviceNameFromID(AudioDeviceID deviceID) {
    return getDeviceName(deviceID);
}

std::string CoreAudioDevice::getStringProperty(
    AudioObjectID objectID,
    const AudioObjectPropertyAddress& address) {
    CFStringRef stringValue = nullptr;
    UInt32 dataSize = sizeof(CFStringRef);

    OSStatus status = AudioObjectGetPropertyData(
        objectID,
        &address,
        0,
        nullptr,
        &dataSize,
        static_cast<void*>(&stringValue));

    if (status != noErr || stringValue == nullptr) {
        return "";
    }

    std::string result = cfStringToStdString(stringValue);
    CFRelease(stringValue);
    return result;
}

uint32_t CoreAudioDevice::getUInt32Property(
    AudioObjectID objectID,
    const AudioObjectPropertyAddress& address,
    uint32_t defaultValue) {
    uint32_t value = defaultValue;
    UInt32 dataSize = sizeof(value);

    OSStatus status = AudioObjectGetPropertyData(
        objectID,
        &address,
        0,
        nullptr,
        &dataSize,
        &value);

    if (status != noErr) {
        return defaultValue;
    }

    return value;
}

// NOLINTEND(cppcoreguidelines-pro-type-vararg)

}  // namespace AdaptiveSound
