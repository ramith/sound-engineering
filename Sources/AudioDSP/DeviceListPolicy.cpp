//
// DeviceListPolicy.cpp — the output-device menu rule and the output classifier (see
// DeviceListPolicy.h).
//
// HAL-FREE: no AudioObject* call lives here, so the C++ test harness compiles and links this file
// without CoreAudio.framework. CoreAudio's headers are included only for constants (the
// composition key's name, the transport FourCCs); CoreFoundation decodes the dictionary.
// -fno-exceptions / -fno-rtti clean.
//

#include "DeviceListPolicy.h"

#include <CoreAudio/AudioHardware.h>     // kAudioAggregateDeviceIsPrivateKey (a string macro only)
#include <CoreAudio/AudioHardwareBase.h> // kAudioDeviceTransportType* (constants only)
#include <IOKit/audio/IOAudioTypes.h> // kIOAudioOutputPortSubType* — data-source codes (constants)
#include <string_view>

namespace AdaptiveSound
{

    namespace
    {
        // LAST RESORT, kept on purpose. CoreAudio names the aggregate it builds around the default
        // devices for one process `CADefaultDeviceAggregate-<pid>-<n>`. Apple documents neither
        // the device nor its name, and a private aggregate is visible only to the process that
        // made it (AudioHardware.h), so its flags cannot be checked from outside the app. The
        // private-aggregate rule in deviceListVerdict is meant to catch it; this prefix catches it
        // if that rule ever does not. eqMac filters its output list on the same name
        // (Outputs.isDeviceAllowed), and EQOutputKey.isPinnable keys off the same prefix.
        constexpr std::string_view kProcessDefaultAggregatePrefix = "CADefaultDeviceAggregate-";

        bool isProcessDefaultAggregate(const DeviceListFacts& facts)
        {
            return facts.uid.starts_with(kProcessDefaultAggregatePrefix) ||
                   facts.name.starts_with(kProcessDefaultAggregatePrefix);
        }

        // Headphones — where crossfeed plays (council C-42 / P2 D44, KI-DEV-01). First what the
        // output says is plugged in, where it says: its data source (kAudioDevicePropertyDataSource,
        // the SDK's IOAudioTypes.h port codes) — 'hdpn' is headphones, the internal or an
        // external speaker is not (the Mac's headphone jack reads 'hdpn' on its built-in
        // transport; its speakers 'ispk'). A line or digital out could feed either, so then the
        // transport decides: Bluetooth (LE) and USB are personal outputs — a Bluetooth speaker
        // that reports nothing reads as headphones, and crossfeed still plays only if the listener
        // turned it on — and AirPlay is a receiver (a HomePod, a TV, a speaker), never
        // headphones. Everything else — the built-in transport without 'hdpn', HDMI, DisplayPort,
        // Thunderbolt / PCI / FireWire interfaces, virtual and aggregate devices — is not, unless
        // its data source says so. (VLC's auhal headphone check keys on the same 'hdpn'.)
        bool isHeadphoneOutput(const OutputDeviceFacts& facts, OutputDeviceType type)
        {
            switch (facts.dataSource)
            {
                case kIOAudioOutputPortSubTypeHeadphones:
                    return true;
                case kIOAudioOutputPortSubTypeInternalSpeaker:
                case kIOAudioOutputPortSubTypeExternalSpeaker:
                    return false;
                default:
                    break; // none, a line or digital out, or a code we don't know: the transport
            }
            if (facts.transportType == kAudioDeviceTransportTypeAirPlay)
            {
                return false;
            }
            return type == OutputDeviceType::Wireless || type == OutputDeviceType::USB;
        }
    } // namespace

    DeviceListVerdict deviceListVerdict(const DeviceListFacts& facts)
    {
        if (facts.outputStreamCount == 0)
        {
            return DeviceListVerdict::NoOutputStream;
        }
        // kAudioDevicePropertyIsHidden: "not included in the normal list of devices … nor can it
        // be the default device" (AudioHardwareBase.h). The HAL already leaves these out of
        // kAudioHardwarePropertyDevices; checked again so the menu never depends on that.
        if (facts.isHidden)
        {
            return DeviceListVerdict::Hidden;
        }
        // kAudioAggregateDeviceIsPrivateKey = 1: "private to the process that created it"
        // (AudioHardware.h). Never the user's to pick, and gone when that process exits. An
        // aggregate whose privacy could not be read stays listed: a failed read never hides a
        // device the user made.
        if (facts.aggregatePrivacy == AggregatePrivacy::Private)
        {
            return DeviceListVerdict::PrivateAggregate;
        }
        if (isProcessDefaultAggregate(facts))
        {
            return DeviceListVerdict::ProcessDefaultAggregate;
        }
        return DeviceListVerdict::Listed;
    }

    OutputDeviceClass classifyOutputDevice(const OutputDeviceFacts& facts)
    {
        OutputDeviceClass result;
        // The family: the authoritative transport (kAudioDevicePropertyTransportType); a USB DAC
        // named "SomeDAC" or a non-Apple Bluetooth headset would be misread by its name. The name
        // only when the transport is unknown or unrecognised.
        switch (facts.transportType)
        {
            case kAudioDeviceTransportTypeBluetooth:
            case kAudioDeviceTransportTypeBluetoothLE:
            case kAudioDeviceTransportTypeAirPlay:
                result.type = OutputDeviceType::Wireless;
                break;
            case kAudioDeviceTransportTypeUSB:
                result.type = OutputDeviceType::USB;
                break;
            case kAudioDeviceTransportTypeBuiltIn:
                result.type = OutputDeviceType::Builtin;
                break;
            default:
                if (facts.name.contains("AirPods") || facts.name.contains("Bluetooth") ||
                    facts.name.contains("wireless"))
                {
                    result.type = OutputDeviceType::Wireless;
                }
                else if (facts.name.contains("USB"))
                {
                    result.type = OutputDeviceType::USB;
                }
                else if (facts.name.contains("Built-in"))
                {
                    result.type = OutputDeviceType::Builtin;
                }
                break;
        }
        result.headphones = isHeadphoneOutput(facts, result.type);
        return result;
    }

    AggregatePrivacy aggregatePrivacyFromComposition(CFDictionaryRef composition)
    {
        if (composition == nullptr)
        {
            return AggregatePrivacy::Unknown;
        }
        // CFDictionaryGetValue follows the Get rule: the value is borrowed, never released here.
        const CFTypeRef value =
            CFDictionaryGetValue(composition, CFSTR(kAudioAggregateDeviceIsPrivateKey));
        if (value == nullptr)
        {
            // "if this key is not present, it implies that the AudioAggregateDevice is published
            // to the entire system" (AudioHardware.h).
            return AggregatePrivacy::Public;
        }
        const CFTypeID type = CFGetTypeID(value);
        if (type == CFBooleanGetTypeID())
        {
            return CFBooleanGetValue(static_cast<CFBooleanRef>(value)) != 0
                       ? AggregatePrivacy::Private
                       : AggregatePrivacy::Public;
        }
        if (type == CFNumberGetTypeID())
        {
            // The documented values are 0 (published) and 1 (private); any other whole number
            // counts as set. A value with a fractional part is not a flag CoreAudio writes.
            SInt64 flag = 0;
            if (CFNumberGetValue(static_cast<CFNumberRef>(value), kCFNumberSInt64Type, &flag) == 0)
            {
                return AggregatePrivacy::Unknown;
            }
            return flag != 0 ? AggregatePrivacy::Private : AggregatePrivacy::Public;
        }
        return AggregatePrivacy::Unknown;
    }

    const char* deviceListVerdictString(DeviceListVerdict verdict)
    {
        switch (verdict)
        {
            case DeviceListVerdict::Listed:
                return "listed";
            case DeviceListVerdict::NoOutputStream:
                return "EXCLUDED (no output stream)";
            case DeviceListVerdict::Hidden:
                return "EXCLUDED (hidden)";
            case DeviceListVerdict::PrivateAggregate:
                return "EXCLUDED (private aggregate)";
            case DeviceListVerdict::ProcessDefaultAggregate:
                return "EXCLUDED (process default-device aggregate, by name)";
        }
        // Unreachable for a valid enumerator; keeps the function total without a throw.
        return "unknown verdict";
    }

    const char* aggregatePrivacyString(AggregatePrivacy privacy)
    {
        switch (privacy)
        {
            case AggregatePrivacy::NotAggregate:
                return "none";
            case AggregatePrivacy::Public:
                return "public";
            case AggregatePrivacy::Private:
                return "private";
            case AggregatePrivacy::Unknown:
                return "unreadable";
        }
        // Unreachable for a valid enumerator; keeps the function total without a throw.
        return "unknown privacy";
    }

} // namespace AdaptiveSound
