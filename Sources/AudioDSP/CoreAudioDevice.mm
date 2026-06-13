#include "CoreAudioDevice.h"
#include <CoreFoundation/CoreFoundation.h>
#include <cstring>

namespace AdaptiveSound {

// MARK: - Helper Functions

static std::string cfStringToStdString(CFStringRef cfStr) {
    if (!cfStr) {
        return "";
    }
    const char* cStr = CFStringGetCStringPtr(cfStr, kCFStringEncodingUTF8);
    if (cStr) {
        return std::string(cStr);
    }

    CFIndex length = CFStringGetLength(cfStr);
    std::vector<char> buffer(static_cast<size_t>(length) + 1);
    CFStringGetCString(cfStr, buffer.data(), static_cast<CFIndex>(buffer.size()), kCFStringEncodingUTF8);
    return std::string(buffer.data());
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

        AudioBufferList* bufferList = nullptr;
        UInt32 bufferListSize = 0;

        status = AudioObjectGetPropertyDataSize(
            deviceID,
            &outputChannelsAddr,
            0,
            nullptr,
            &bufferListSize);

        if (status == noErr && bufferListSize > 0) {
            bufferList = static_cast<AudioBufferList*>(malloc(bufferListSize));
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

            free(bufferList);
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
    UInt32 dataSize = sizeof(deviceName);

    OSStatus status = AudioObjectGetPropertyData(
        deviceID,
        &namePropertyAddr,
        0,
        nullptr,
        &dataSize,
        &deviceName);

    if (status != noErr || !deviceName) {
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

    Float64 sampleRate = 48000.0;
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
        return 48000;
    }

    return static_cast<uint32_t>(sampleRate);
}

uint32_t CoreAudioDevice::getDeviceBufferFrameSize(AudioDeviceID deviceID) {
    AudioObjectPropertyAddress bufferSizeAddr{
        kAudioDevicePropertyBufferFrameSize,
        kAudioObjectPropertyScopeOutput,
        kAudioObjectPropertyElementMain};

    UInt32 bufferSize = 512;
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
        return 512;
    }

    return bufferSize;
}

AudioDevice::Type CoreAudioDevice::getDeviceType(AudioDeviceID deviceID) {
    std::string deviceName = getDeviceName(deviceID);

    // Simple heuristic based on device name
    if (deviceName.find("AirPods") != std::string::npos ||
        deviceName.find("Bluetooth") != std::string::npos ||
        deviceName.find("wireless") != std::string::npos) {
        return AudioDevice::Wireless;
    }

    if (deviceName.find("USB") != std::string::npos) {
        return AudioDevice::USB;
    }

    if (deviceName.find("Built-in") != std::string::npos) {
        return AudioDevice::Builtin;
    }

    return AudioDevice::Unknown;
}

std::string CoreAudioDevice::deviceNameFromID(AudioDeviceID deviceID) {
    return getDeviceName(deviceID);
}

std::string CoreAudioDevice::getStringProperty(
    AudioObjectID objectID,
    const AudioObjectPropertyAddress& address) {
    CFStringRef stringValue = nullptr;
    UInt32 dataSize = sizeof(stringValue);

    OSStatus status = AudioObjectGetPropertyData(
        objectID,
        &address,
        0,
        nullptr,
        &dataSize,
        &stringValue);

    if (status != noErr || !stringValue) {
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

}  // namespace AdaptiveSound
