#include "CoreAudioDevice.h"
#include "AsLog.h" // off-RT control-plane logging seam (AdaptiveSound::log::line)
#include "AudioConstants.h"
#include <CoreFoundation/CoreFoundation.h>
#include <cstddef>

namespace AdaptiveSound
{

    // control-plane logging only (init/shutdown/device-change); never on the RT audio thread.
    // Diagnostics use AdaptiveSound::log::line (AsLog.h) — no vararg suppression needed.

    // MARK: - Helper Functions

    static std::string cfStringToStdString(CFStringRef cfStr)
    {
        if (cfStr == nullptr)
        {
            return "";
        }
        const char* cStr = CFStringGetCStringPtr(cfStr, kCFStringEncodingUTF8);
        if (cStr != nullptr)
        {
            return std::string(cStr);
        }

        // Size by the MAX UTF-8 byte length for this string, not its UTF-16 code-unit count
        // (CFStringGetLength): a multi-byte name would otherwise be silently truncated (Stage-2 OWN-6).
        const CFIndex length = CFStringGetLength(cfStr);
        const CFIndex maxBytes =
            CFStringGetMaximumSizeForEncoding(length, kCFStringEncodingUTF8) + 1;
        std::vector<char> buffer(static_cast<size_t>(maxBytes));
        CFStringGetCString(cfStr, buffer.data(), maxBytes, kCFStringEncodingUTF8);
        return std::string(buffer.data());
    }

    // NOTE (Stage-2 review OWN-1): a C++ default-output-device listener API used to live here
    // (addDefaultDeviceListener / removeDefaultDeviceListener / a static callback trampoline). It had
    // ZERO callers — the Swift layer (AudioEngineBridge+OutputDeviceMonitor) does its own
    // correctly-balanced AudioObjectAdd/RemovePropertyListenerBlock — and it was defective (the block
    // was registered but never removed, its "can't remove block listeners" comment was false, and the
    // single-listener statics raced on the concurrent dispatch queue). Deleted rather than fixed.

    // MARK: - CoreAudioDevice Implementation

    std::vector<AudioDevice> CoreAudioDevice::enumerateOutputDevices()
    {
        std::vector<AudioDevice> devices;

        AudioObjectPropertyAddress devicesPropertyAddr{
            kAudioHardwarePropertyDevices,
            kAudioObjectPropertyScopeGlobal,
            kAudioObjectPropertyElementMain,
        };

        UInt32 devicesDataSize = 0;
        OSStatus status = AudioObjectGetPropertyDataSize(
            kAudioObjectSystemObject, &devicesPropertyAddr, 0, nullptr, &devicesDataSize);

        if (status != noErr || devicesDataSize == 0)
        {
            AdaptiveSound::log::line("[CoreAudioDevice] Failed to get device list size");
            return devices;
        }

        uint32_t deviceCount = devicesDataSize / sizeof(AudioDeviceID);
        std::vector<AudioDeviceID> deviceIDs(deviceCount);

        status = AudioObjectGetPropertyData(kAudioObjectSystemObject,
                                            &devicesPropertyAddr,
                                            0,
                                            nullptr,
                                            &devicesDataSize,
                                            deviceIDs.data());

        if (status != noErr)
        {
            AdaptiveSound::log::line("[CoreAudioDevice] Failed to get device IDs");
            return devices;
        }

        // Keep the devices a user may pick; the rule itself is deviceListVerdict (DeviceListPolicy).
        for (AudioDeviceID deviceID : deviceIDs)
        {
            const DeviceListFacts facts = readDeviceListFacts(deviceID);
            const DeviceListVerdict verdict = deviceListVerdict(facts);
            if (verdict == DeviceListVerdict::Listed)
            {
                devices.push_back(queryDevice(deviceID));
            }

            // DIAGNOSTIC: every raw device in the CoreAudio set, the facts the menu rule read and
            // its verdict. Tells a device ABSENT from CoreAudio's set apart from one PRESENT but
            // excluded, and why — e.g. a BT device mid-A2DP-handshake reports zero output streams;
            // this app's own CADefaultDeviceAggregate is a private aggregate.
            AdaptiveSound::log::line(
                "[CoreAudioDevice] candidate id={} '{}' uid='{}' outputStreams={} hidden={} "
                "aggregate={} -> {}",
                static_cast<unsigned int>(deviceID),
                facts.name,
                facts.uid,
                facts.outputStreamCount,
                facts.isHidden,
                aggregatePrivacyString(facts.aggregatePrivacy),
                deviceListVerdictString(verdict));
        }

        AdaptiveSound::log::line("[CoreAudioDevice] Enumerated {} output devices", devices.size());
        return devices;
    }

    AudioDevice CoreAudioDevice::queryDevice(AudioDeviceID deviceID)
    {
        AudioDevice device;
        device.id = deviceID;
        device.name = getDeviceName(deviceID);
        device.sampleRate = getDeviceSampleRate(deviceID);
        device.bufferFrameSize = getDeviceBufferFrameSize(deviceID);
        device.transportType = getDeviceTransportType(deviceID);
        device.type = classifyDeviceType(device.transportType, device.name);
        return device;
    }

    // MARK: - Device-list facts (the HAL reads behind deviceListVerdict)

    // Buffers in the device's OUTPUT stream configuration: 0 for an input-only device, or for an
    // output that isn't ready yet (a BT device mid-A2DP-handshake reports none).
    static uint32_t outputStreamCount(AudioDeviceID deviceID)
    {
        const AudioObjectPropertyAddress configAddr{
            kAudioDevicePropertyStreamConfiguration,
            kAudioObjectPropertyScopeOutput,
            kAudioObjectPropertyElementMain,
        };

        UInt32 dataSize = 0;
        OSStatus status =
            AudioObjectGetPropertyDataSize(deviceID, &configAddr, 0, nullptr, &dataSize);
        if (status != noErr || dataSize < sizeof(AudioBufferList::mNumberBuffers))
        {
            return 0;
        }

        // RAII-owned storage for the AudioBufferList (control-plane; size from API).
        std::vector<std::byte> storage(dataSize);
        auto* bufferList = reinterpret_cast<AudioBufferList*>(storage.data());
        status =
            AudioObjectGetPropertyData(deviceID, &configAddr, 0, nullptr, &dataSize, bufferList);
        return status == noErr ? bufferList->mNumberBuffers : 0U;
    }

    // An aggregate's privacy, from its composition dictionary. Plain devices have no composition.
    static AggregatePrivacy readAggregatePrivacy(AudioDeviceID deviceID)
    {
        const AudioObjectPropertyAddress compositionAddr{
            kAudioAggregateDevicePropertyComposition,
            kAudioObjectPropertyScopeGlobal,
            kAudioObjectPropertyElementMain,
        };
        if (AudioObjectHasProperty(deviceID, &compositionAddr) == 0)
        {
            return AggregatePrivacy::NotAggregate;
        }

        CFDictionaryRef composition = nullptr;
        UInt32 dataSize = sizeof(CFDictionaryRef);
        const OSStatus status = AudioObjectGetPropertyData(
            deviceID, &compositionAddr, 0, nullptr, &dataSize, static_cast<void*>(&composition));
        if (status != noErr || composition == nullptr)
        {
            return AggregatePrivacy::Unknown;
        }

        const AggregatePrivacy privacy = aggregatePrivacyFromComposition(composition);
        // "The caller is responsible for releasing the returned CFObject" (AudioHardware.h).
        CFRelease(composition);
        return privacy;
    }

    DeviceListFacts CoreAudioDevice::readDeviceListFacts(AudioDeviceID deviceID)
    {
        DeviceListFacts facts;
        facts.outputStreamCount = outputStreamCount(deviceID);
        facts.isHidden = getUInt32Property(deviceID,
                                           {
                                               kAudioDevicePropertyIsHidden,
                                               kAudioObjectPropertyScopeGlobal,
                                               kAudioObjectPropertyElementMain,
                                           }) != 0;
        facts.aggregatePrivacy = readAggregatePrivacy(deviceID);
        facts.uid = getDeviceUID(deviceID);
        facts.name = getDeviceName(deviceID);
        return facts;
    }

    AudioDeviceID CoreAudioDevice::getDefaultOutputDevice()
    {
        AudioObjectPropertyAddress devicePropertyAddr{
            kAudioHardwarePropertyDefaultOutputDevice,
            kAudioObjectPropertyScopeGlobal,
            kAudioObjectPropertyElementMain,
        };

        AudioDeviceID deviceID = kAudioObjectUnknown;
        UInt32 dataSize = sizeof(deviceID);

        OSStatus status = AudioObjectGetPropertyData(
            kAudioObjectSystemObject, &devicePropertyAddr, 0, nullptr, &dataSize, &deviceID);

        if (status != noErr)
        {
            AdaptiveSound::log::line("[CoreAudioDevice] Failed to get default output device");
            return kAudioObjectUnknown;
        }

        return deviceID;
    }

    std::string CoreAudioDevice::getDeviceName(AudioDeviceID deviceID)
    {
        AudioObjectPropertyAddress namePropertyAddr{
            kAudioObjectPropertyName,
            kAudioObjectPropertyScopeOutput,
            kAudioObjectPropertyElementMain,
        };

        CFStringRef deviceName = nullptr;
        UInt32 dataSize = sizeof(CFStringRef);

        OSStatus status = AudioObjectGetPropertyData(
            deviceID, &namePropertyAddr, 0, nullptr, &dataSize, static_cast<void*>(&deviceName));

        if (status != noErr || deviceName == nullptr)
        {
            return "Unknown Device";
        }

        std::string name = cfStringToStdString(deviceName);
        CFRelease(deviceName);
        return name;
    }

    uint32_t CoreAudioDevice::getDeviceSampleRate(AudioDeviceID deviceID)
    {
        AudioObjectPropertyAddress nominalSampleRateAddr{
            kAudioDevicePropertyNominalSampleRate,
            kAudioObjectPropertyScopeOutput,
            kAudioObjectPropertyElementMain,
        };

        Float64 sampleRate = static_cast<Float64>(kDefaultSampleRate);
        UInt32 dataSize = sizeof(sampleRate);

        OSStatus status = AudioObjectGetPropertyData(
            deviceID, &nominalSampleRateAddr, 0, nullptr, &dataSize, &sampleRate);

        if (status != noErr)
        {
            AdaptiveSound::log::line(
                "[CoreAudioDevice] Failed to get sample rate, using default 48 kHz");
            return kDefaultSampleRate;
        }

        return static_cast<uint32_t>(sampleRate);
    }

    uint32_t CoreAudioDevice::getDeviceBufferFrameSize(AudioDeviceID deviceID)
    {
        AudioObjectPropertyAddress bufferSizeAddr{
            kAudioDevicePropertyBufferFrameSize,
            kAudioObjectPropertyScopeOutput,
            kAudioObjectPropertyElementMain,
        };

        UInt32 bufferSize = kDefaultMaxFrames;
        UInt32 dataSize = sizeof(bufferSize);

        OSStatus status = AudioObjectGetPropertyData(
            deviceID, &bufferSizeAddr, 0, nullptr, &dataSize, &bufferSize);

        if (status != noErr)
        {
            AdaptiveSound::log::line(
                "[CoreAudioDevice] Failed to get buffer size, using default 512 frames");
            return kDefaultMaxFrames;
        }

        return bufferSize;
    }

    uint32_t CoreAudioDevice::getDeviceTransportType(AudioDeviceID deviceID)
    {
        return getUInt32Property(deviceID,
                                 {
                                     kAudioDevicePropertyTransportType,
                                     kAudioObjectPropertyScopeGlobal,
                                     kAudioObjectPropertyElementMain,
                                 });
    }

    std::string CoreAudioDevice::getDeviceUID(AudioDeviceID deviceID)
    {
        return getStringProperty(deviceID,
                                 {
                                     kAudioDevicePropertyDeviceUID,
                                     kAudioObjectPropertyScopeGlobal,
                                     kAudioObjectPropertyElementMain,
                                 });
    }

    std::string CoreAudioDevice::getDeviceModelUID(AudioDeviceID deviceID)
    {
        return getStringProperty(deviceID,
                                 {
                                     kAudioDevicePropertyModelUID,
                                     kAudioObjectPropertyScopeGlobal,
                                     kAudioObjectPropertyElementMain,
                                 });
    }

    AudioDevice::Type CoreAudioDevice::classifyDeviceType(uint32_t transportType,
                                                          const std::string& name)
    {
        // Prefer the authoritative CoreAudio transport type (kAudioDevicePropertyTransportType);
        // a USB DAC named "SomeDAC" or a non-Apple BT headset would be misclassified by a name
        // heuristic. Fall back to the name only when the transport type is unavailable/unrecognized.
        switch (transportType)
        {
            case kAudioDeviceTransportTypeBluetooth:
            case kAudioDeviceTransportTypeBluetoothLE:
            case kAudioDeviceTransportTypeAirPlay:
                return AudioDevice::Type::Wireless;
            case kAudioDeviceTransportTypeUSB:
                return AudioDevice::Type::USB;
            case kAudioDeviceTransportTypeBuiltIn:
                return AudioDevice::Type::Builtin;
            default:
                break; // unknown (0) or unrecognized transport — fall through to the name heuristic
        }

        // Fallback heuristic when the transport type is unknown.
        if (name.contains("AirPods") || name.contains("Bluetooth") || name.contains("wireless"))
        {
            return AudioDevice::Type::Wireless;
        }
        if (name.contains("USB"))
        {
            return AudioDevice::Type::USB;
        }
        if (name.contains("Built-in"))
        {
            return AudioDevice::Type::Builtin;
        }
        return AudioDevice::Type::Unknown;
    }

    // MARK: - Pure-Mode capability querying (Phase B — B1)

    // Local helper: first OUTPUT-scope stream of a device (for stream-format queries).
    // Returns kAudioObjectUnknown when the device has no output stream.
    static AudioObjectID firstOutputStream(AudioDeviceID deviceID)
    {
        AudioObjectPropertyAddress streamsAddr{
            kAudioDevicePropertyStreams,
            kAudioObjectPropertyScopeOutput,
            kAudioObjectPropertyElementMain,
        };

        UInt32 dataSize = 0;
        OSStatus status =
            AudioObjectGetPropertyDataSize(deviceID, &streamsAddr, 0, nullptr, &dataSize);
        if (status != noErr || dataSize == 0)
        {
            return kAudioObjectUnknown;
        }

        const uint32_t streamCount = dataSize / sizeof(AudioObjectID);
        std::vector<AudioObjectID> streams(streamCount);
        status = AudioObjectGetPropertyData(
            deviceID, &streamsAddr, 0, nullptr, &dataSize, streams.data());
        if (status != noErr || streams.empty())
        {
            return kAudioObjectUnknown;
        }
        return streams[0];
    }

    std::vector<double> CoreAudioDevice::getAvailableSampleRates(AudioDeviceID deviceID)
    {
        std::vector<double> rates;

        AudioObjectPropertyAddress ratesAddr{
            kAudioDevicePropertyAvailableNominalSampleRates,
            kAudioObjectPropertyScopeOutput,
            kAudioObjectPropertyElementMain,
        };

        UInt32 dataSize = 0;
        OSStatus status =
            AudioObjectGetPropertyDataSize(deviceID, &ratesAddr, 0, nullptr, &dataSize);
        if (status != noErr || dataSize == 0)
        {
            AdaptiveSound::log::line(
                "[CoreAudioDevice] Failed to get available sample-rate ranges size");
            return rates;
        }

        const uint32_t rangeCount = dataSize / sizeof(AudioValueRange);
        std::vector<AudioValueRange> ranges(rangeCount);
        status =
            AudioObjectGetPropertyData(deviceID, &ratesAddr, 0, nullptr, &dataSize, ranges.data());
        if (status != noErr)
        {
            AdaptiveSound::log::line(
                "[CoreAudioDevice] Failed to get available sample-rate ranges");
            return rates;
        }

        rates.reserve(ranges.size() * 2U);
        for (const AudioValueRange& range : ranges)
        {
            if (range.mMinimum == range.mMaximum)
            {
                // Discrete rate.
                rates.push_back(range.mMinimum);
            }
            else
            {
                // Continuous range — report both endpoints.
                rates.push_back(range.mMinimum);
                rates.push_back(range.mMaximum);
            }
        }
        return rates;
    }

    StreamFormatInfo CoreAudioDevice::getStreamFormat(AudioDeviceID deviceID, bool physical)
    {
        StreamFormatInfo info;

        AudioObjectID stream = firstOutputStream(deviceID);
        if (stream == kAudioObjectUnknown)
        {
            AdaptiveSound::log::line(
                "[CoreAudioDevice] No output stream; cannot read stream format");
            return info;
        }

        AudioObjectPropertyAddress formatAddr{
            physical ? kAudioStreamPropertyPhysicalFormat : kAudioStreamPropertyVirtualFormat,
            kAudioObjectPropertyScopeGlobal,
            kAudioObjectPropertyElementMain,
        };

        AudioStreamBasicDescription asbd{};
        UInt32 dataSize = sizeof(asbd);
        OSStatus status =
            AudioObjectGetPropertyData(stream, &formatAddr, 0, nullptr, &dataSize, &asbd);
        if (status != noErr)
        {
            AdaptiveSound::log::line("[CoreAudioDevice] Failed to get {} stream format",
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

    DeviceCapability CoreAudioDevice::queryCapability(AudioDeviceID deviceID)
    {
        DeviceCapability cap;
        cap.id = deviceID;

        // Transport type (authoritative; the same query device enumeration classifies with).
        const uint32_t transportType = getDeviceTransportType(deviceID);
        if (transportType == 0)
        {
            AdaptiveSound::log::line(
                "[CoreAudioDevice] No transport type for capability (unavailable or unknown)");
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

    std::string CoreAudioDevice::deviceNameFromID(AudioDeviceID deviceID)
    {
        return getDeviceName(deviceID);
    }

    std::string CoreAudioDevice::getStringProperty(AudioObjectID objectID,
                                                   const AudioObjectPropertyAddress& address)
    {
        CFStringRef stringValue = nullptr;
        UInt32 dataSize = sizeof(CFStringRef);

        OSStatus status = AudioObjectGetPropertyData(
            objectID, &address, 0, nullptr, &dataSize, static_cast<void*>(&stringValue));

        if (status != noErr || stringValue == nullptr)
        {
            return "";
        }

        std::string result = cfStringToStdString(stringValue);
        CFRelease(stringValue);
        return result;
    }

    uint32_t CoreAudioDevice::getUInt32Property(AudioObjectID objectID,
                                                const AudioObjectPropertyAddress& address,
                                                uint32_t defaultValue)
    {
        uint32_t value = defaultValue;
        UInt32 dataSize = sizeof(value);

        OSStatus status =
            AudioObjectGetPropertyData(objectID, &address, 0, nullptr, &dataSize, &value);

        if (status != noErr)
        {
            return defaultValue;
        }

        return value;
    }

} // namespace AdaptiveSound
