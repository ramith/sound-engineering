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
        // DIAGNOSTIC: name every raw device in the CoreAudio set and log whether it passes the
        // output-stream filter. Debugging "connected BT headphone doesn't appear in the picker" —
        // this distinguishes the device being ABSENT from CoreAudio's device set entirely vs.
        // PRESENT but excluded (its output stream isn't negotiated/ready yet, e.g. a BT device
        // mid-A2DP-handshake reports zero output streams).
        const std::string candidateName = getDeviceName(deviceID);

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

        bool included = false;
        UInt32 outputStreams = 0;
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

            if (status == noErr) {
                outputStreams = bufferList->mNumberBuffers;
                if (outputStreams > 0) {
                    AudioDevice device = queryDevice(deviceID);
                    devices.push_back(device);
                    included = true;
                }
            }
        }

        fprintf(stderr, "[CoreAudioDevice] candidate id=%u '%s' outputStreams=%u -> %s\n",
                static_cast<unsigned int>(deviceID), candidateName.c_str(),
                static_cast<unsigned int>(outputStreams),
                included ? "included" : "EXCLUDED (no output stream)");
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
    // Prefer the authoritative CoreAudio transport type (kAudioDevicePropertyTransportType);
    // a USB DAC named "SomeDAC" or a non-Apple BT headset would be misclassified by a name
    // heuristic. Fall back to the name only when the transport type is unavailable/unrecognized.
    AudioObjectPropertyAddress transportAddr{
        kAudioDevicePropertyTransportType,
        kAudioObjectPropertyScopeGlobal,
        kAudioObjectPropertyElementMain};

    UInt32 transportType = 0;
    UInt32 dataSize = sizeof(transportType);
    OSStatus status = AudioObjectGetPropertyData(
        deviceID, &transportAddr, 0, nullptr, &dataSize, &transportType);

    if (status == noErr) {
        switch (transportType) {
            case kAudioDeviceTransportTypeBluetooth:
            case kAudioDeviceTransportTypeBluetoothLE:
            case kAudioDeviceTransportTypeAirPlay:
                return AudioDevice::Type::Wireless;
            case kAudioDeviceTransportTypeUSB:
                return AudioDevice::Type::USB;
            case kAudioDeviceTransportTypeBuiltIn:
                return AudioDevice::Type::Builtin;
            default:
                break;  // unrecognized transport — fall through to the name heuristic
        }
    }

    // Fallback heuristic when the transport type is unknown.
    std::string deviceName = getDeviceName(deviceID);
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

// MARK: - Pure-Mode capability querying (Phase B — B1)

// Local helper: first OUTPUT-scope stream of a device (for stream-format queries).
// Returns kAudioObjectUnknown when the device has no output stream.
static AudioObjectID firstOutputStream(AudioDeviceID deviceID) {
    AudioObjectPropertyAddress streamsAddr{
        kAudioDevicePropertyStreams,
        kAudioObjectPropertyScopeOutput,
        kAudioObjectPropertyElementMain};

    UInt32 dataSize = 0;
    OSStatus status = AudioObjectGetPropertyDataSize(deviceID, &streamsAddr, 0, nullptr, &dataSize);
    if (status != noErr || dataSize == 0) {
        return kAudioObjectUnknown;
    }

    const uint32_t streamCount = dataSize / sizeof(AudioObjectID);
    std::vector<AudioObjectID> streams(streamCount);
    status =
        AudioObjectGetPropertyData(deviceID, &streamsAddr, 0, nullptr, &dataSize, streams.data());
    if (status != noErr || streams.empty()) {
        return kAudioObjectUnknown;
    }
    return streams[0];
}

std::vector<double> CoreAudioDevice::getAvailableSampleRates(AudioDeviceID deviceID) {
    std::vector<double> rates;

    AudioObjectPropertyAddress ratesAddr{
        kAudioDevicePropertyAvailableNominalSampleRates,
        kAudioObjectPropertyScopeOutput,
        kAudioObjectPropertyElementMain};

    UInt32 dataSize = 0;
    OSStatus status = AudioObjectGetPropertyDataSize(deviceID, &ratesAddr, 0, nullptr, &dataSize);
    if (status != noErr || dataSize == 0) {
        fprintf(stderr, "[CoreAudioDevice] Failed to get available sample-rate ranges size\n");
        return rates;
    }

    const uint32_t rangeCount = dataSize / sizeof(AudioValueRange);
    std::vector<AudioValueRange> ranges(rangeCount);
    status = AudioObjectGetPropertyData(deviceID, &ratesAddr, 0, nullptr, &dataSize, ranges.data());
    if (status != noErr) {
        fprintf(stderr, "[CoreAudioDevice] Failed to get available sample-rate ranges\n");
        return rates;
    }

    rates.reserve(ranges.size() * 2U);
    for (const AudioValueRange& range : ranges) {
        if (range.mMinimum == range.mMaximum) {
            // Discrete rate.
            rates.push_back(range.mMinimum);
        } else {
            // Continuous range — report both endpoints.
            rates.push_back(range.mMinimum);
            rates.push_back(range.mMaximum);
        }
    }
    return rates;
}

StreamFormatInfo CoreAudioDevice::getStreamFormat(AudioDeviceID deviceID, bool physical) {
    StreamFormatInfo info;

    AudioObjectID stream = firstOutputStream(deviceID);
    if (stream == kAudioObjectUnknown) {
        fprintf(stderr, "[CoreAudioDevice] No output stream; cannot read stream format\n");
        return info;
    }

    AudioObjectPropertyAddress formatAddr{
        physical ? kAudioStreamPropertyPhysicalFormat : kAudioStreamPropertyVirtualFormat,
        kAudioObjectPropertyScopeGlobal,
        kAudioObjectPropertyElementMain};

    AudioStreamBasicDescription asbd{};
    UInt32 dataSize = sizeof(asbd);
    OSStatus status =
        AudioObjectGetPropertyData(stream, &formatAddr, 0, nullptr, &dataSize, &asbd);
    if (status != noErr) {
        fprintf(stderr, "[CoreAudioDevice] Failed to get %s stream format\n",
                physical ? "physical" : "virtual");
        return info;
    }

    info.sampleRate = asbd.mSampleRate;
    info.bitsPerChannel = asbd.mBitsPerChannel;
    info.channels = asbd.mChannelsPerFrame;
    info.isPCM = (asbd.mFormatID == kAudioFormatLinearPCM);
    info.isFloat = (asbd.mFormatFlags & kAudioFormatFlagIsFloat) != 0;
    return info;
}

DeviceCapability CoreAudioDevice::queryCapability(AudioDeviceID deviceID) {
    DeviceCapability cap;
    cap.id = deviceID;

    // Transport type (authoritative; same selector as getDeviceType()).
    AudioObjectPropertyAddress transportAddr{
        kAudioDevicePropertyTransportType,
        kAudioObjectPropertyScopeGlobal,
        kAudioObjectPropertyElementMain};
    UInt32 transportType = 0;
    UInt32 dataSize = sizeof(transportType);
    OSStatus status = AudioObjectGetPropertyData(
        deviceID, &transportAddr, 0, nullptr, &dataSize, &transportType);
    if (status != noErr) {
        fprintf(stderr, "[CoreAudioDevice] Failed to get transport type for capability\n");
        transportType = 0;
    }
    cap.transportType = transportType;

    // Current nominal rate (reuse the existing getter; it returns an integer Hz).
    cap.currentRate = static_cast<double>(getDeviceSampleRate(deviceID));

    // Advertised rates + stream formats.
    cap.availableRates = getAvailableSampleRates(deviceID);
    cap.virtualFormat = getStreamFormat(deviceID, /*physical=*/false);
    cap.physicalFormat = getStreamFormat(deviceID, /*physical=*/true);

    // Semantic capability flags (the policy keys off these, not off any device-type enum).
    cap.integerCapable = cap.physicalFormat.isPCM && !cap.physicalFormat.isFloat;

    cap.isLossyWireless = (transportType == kAudioDeviceTransportTypeBluetooth) ||
                          (transportType == kAudioDeviceTransportTypeBluetoothLE) ||
                          (transportType == kAudioDeviceTransportTypeAirPlay);

    cap.isVirtualOrAggregate = (transportType == kAudioDeviceTransportTypeVirtual) ||
                               (transportType == kAudioDeviceTransportTypeAggregate) ||
                               (transportType == kAudioDeviceTransportTypeAutoAggregate);

    cap.exclusiveCapable = !cap.isVirtualOrAggregate;

    return cap;
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
