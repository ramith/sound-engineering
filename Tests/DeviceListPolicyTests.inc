// DeviceListPolicyTests.inc
//
// Sprint G: the output-device menu rule (deviceListVerdict) and the aggregate-composition decode
// (aggregatePrivacyFromComposition). Pure: hand-built facts and CFDictionaries, no HAL, no
// hardware. #included into Tests/DSPKernelNullTest.cpp after TestSupport.h.
//
// The kept-device fixtures copy the devices measured on the founder's Mac on 2026-10-12 (a
// read-only probe: name, UID, transport, hidden, output streams); the excluded ones copy the
// menu bug seen live the same day (`CADefaultDeviceAggregate-17457-0` listed as an output).
//
// Tests: DeviceList_KeepsRealOutputs, DeviceList_KeepsVirtualAndUserAggregates,
//        DeviceList_HidesInternalDevices, DeviceList_RuleOrder,
//        DeviceList_CompositionDecode, DeviceList_VerdictStrings,
//        OutputDevice_Family, OutputDevice_Headphones (R1.1-A: the one output classifier).
// Helpers (area-local): makeOutputFacts, checkVerdict, createComposition.

#include "DeviceListPolicy.h"
#include <CoreAudio/AudioHardware.h> // kAudioAggregateDeviceIsPrivateKey (a string macro only)
#include <IOKit/audio/IOAudioTypes.h> // kIOAudioOutputPortSubType* — the data-source codes

namespace
{
    // A listed-shape device: one output stream, not hidden, not an aggregate.
    auto makeOutputFacts(const char* uid, const char* name) -> DeviceListFacts
    {
        DeviceListFacts facts;
        facts.outputStreamCount = 1;
        facts.uid = uid;
        facts.name = name;
        return facts;
    }

    // "" when deviceListVerdict(facts) == expected, else the mismatch with the device's name.
    auto checkVerdict(const DeviceListFacts& facts, DeviceListVerdict expected) -> std::string
    {
        const DeviceListVerdict actual = deviceListVerdict(facts);
        if (actual == expected)
        {
            return "";
        }
        return std::format("'{}': expected {}, got {}; ",
                           facts.name,
                           deviceListVerdictString(expected),
                           deviceListVerdictString(actual));
    }

    // A one-entry composition dictionary {"private": value} (an empty one when value is null).
    // The caller owns the result (the Create rule) and releases it.
    auto createComposition(CFTypeRef value) -> CFDictionaryRef
    {
        std::array<const void*, 1> keys{CFSTR(kAudioAggregateDeviceIsPrivateKey)};
        std::array<const void*, 1> values{value};
        return CFDictionaryCreate(kCFAllocatorDefault,
                                  keys.data(),
                                  values.data(),
                                  value == nullptr ? 0 : 1,
                                  &kCFTypeDictionaryKeyCallBacks,
                                  &kCFTypeDictionaryValueCallBacks);
    }
} // namespace

// Every real output on the founder's Mac, plus the hardware kinds the brief keeps (USB DAC,
// AirPlay), is listed.
static auto testDeviceListKeepsRealOutputs() -> void
{
    static const char* const kName = "DeviceList_KeepsRealOutputs";
    std::string err;
    err += checkVerdict(makeOutputFacts("BuiltInSpeakerDevice", "MacBook Pro Speakers"),
                        DeviceListVerdict::Listed);
    err += checkVerdict(makeOutputFacts("14-3F-A6-34-34-23:output", "WH-1000XM4"),
                        DeviceListVerdict::Listed);
    err += checkVerdict(makeOutputFacts("AppleUSBAudioEngine:Topping:E30:1:1", "E30"),
                        DeviceListVerdict::Listed);
    err += checkVerdict(makeOutputFacts("AirPlay:3C-22-FB-00-00-01", "Living Room"),
                        DeviceListVerdict::Listed);
    if (!err.empty())
    {
        logFail(kName, err);
        return;
    }
    logPass(kName);
}

// Virtual devices and the aggregates a user builds stay: Microsoft Teams Audio (measured: 'virt',
// not hidden, one output stream), BlackHole, a public Audio MIDI Setup aggregate, and an
// aggregate whose composition could not be read (a failed read never hides a user's device).
static auto testDeviceListKeepsVirtualAndUserAggregates() -> void
{
    static const char* const kName = "DeviceList_KeepsVirtualAndUserAggregates";
    std::string err;
    err += checkVerdict(makeOutputFacts("MSLoopbackDriverDevice_UID", "Microsoft Teams Audio"),
                        DeviceListVerdict::Listed);
    err += checkVerdict(makeOutputFacts("BlackHole2ch_UID", "BlackHole 2ch"),
                        DeviceListVerdict::Listed);

    DeviceListFacts userAggregate = makeOutputFacts("~:AMS2_Aggregate:0", "Aggregate Device");
    userAggregate.aggregatePrivacy = AggregatePrivacy::Public;
    err += checkVerdict(userAggregate, DeviceListVerdict::Listed);

    DeviceListFacts unreadAggregate = makeOutputFacts("~:AMS2_StackedOutput:0", "Multi-Output");
    unreadAggregate.aggregatePrivacy = AggregatePrivacy::Unknown;
    err += checkVerdict(unreadAggregate, DeviceListVerdict::Listed);

    // The backstop prefix matches only at the start: a name that merely contains it stays.
    err += checkVerdict(makeOutputFacts("Studio-CADefaultDeviceAggregate-1", "Studio Mix"),
                        DeviceListVerdict::Listed);
    err += checkVerdict(makeOutputFacts("CADefaultDeviceAggregateX", "CADefaultDeviceAggregateX"),
                        DeviceListVerdict::Listed);
    if (!err.empty())
    {
        logFail(kName, err);
        return;
    }
    logPass(kName);
}

// The internal devices never reach the menu: this app's own CADefaultDeviceAggregate (private,
// and caught by its name even when its flags say otherwise), any other process-private aggregate,
// hidden devices, and input-only devices (the measured mic and the BT headset's input half).
static auto testDeviceListHidesInternalDevices() -> void
{
    static const char* const kName = "DeviceList_HidesInternalDevices";
    std::string err;

    DeviceListFacts ownAggregate =
        makeOutputFacts("CADefaultDeviceAggregate-17457-0", "CADefaultDeviceAggregate-17457-0");
    ownAggregate.aggregatePrivacy = AggregatePrivacy::Private;
    err += checkVerdict(ownAggregate, DeviceListVerdict::PrivateAggregate);

    // The name backstop, for every way the private flag could fail to say "private".
    for (const AggregatePrivacy privacy :
         {AggregatePrivacy::Public, AggregatePrivacy::Unknown, AggregatePrivacy::NotAggregate})
    {
        ownAggregate.aggregatePrivacy = privacy;
        err += checkVerdict(ownAggregate, DeviceListVerdict::ProcessDefaultAggregate);
    }
    // ...and when only one of the UID or the name carries the prefix.
    const DeviceListFacts byUid = makeOutputFacts("CADefaultDeviceAggregate-4242-1", "Aggregate");
    err += checkVerdict(byUid, DeviceListVerdict::ProcessDefaultAggregate);
    const DeviceListFacts byName = makeOutputFacts("", "CADefaultDeviceAggregate-4242-2");
    err += checkVerdict(byName, DeviceListVerdict::ProcessDefaultAggregate);

    DeviceListFacts otherPrivate = makeOutputFacts("com.example.tap-aggregate", "Tap Aggregate");
    otherPrivate.aggregatePrivacy = AggregatePrivacy::Private;
    err += checkVerdict(otherPrivate, DeviceListVerdict::PrivateAggregate);

    DeviceListFacts hidden = makeOutputFacts("HiddenDriverDevice_UID", "Hidden Driver");
    hidden.isHidden = true;
    err += checkVerdict(hidden, DeviceListVerdict::Hidden);

    DeviceListFacts microphone = makeOutputFacts("BuiltInMicrophoneDevice", "MacBook Pro Mic");
    microphone.outputStreamCount = 0;
    err += checkVerdict(microphone, DeviceListVerdict::NoOutputStream);
    DeviceListFacts headsetInput = makeOutputFacts("14-3F-A6-34-34-23:input", "WH-1000XM4");
    headsetInput.outputStreamCount = 0;
    err += checkVerdict(headsetInput, DeviceListVerdict::NoOutputStream);
    if (!err.empty())
    {
        logFail(kName, err);
        return;
    }
    logPass(kName);
}

// One verdict per device, and the first rule wins: no output stream, then hidden, then private,
// then the name backstop. (The log line names the rule that fired, so the order is visible.)
static auto testDeviceListRuleOrder() -> void
{
    static const char* const kName = "DeviceList_RuleOrder";
    DeviceListFacts facts =
        makeOutputFacts("CADefaultDeviceAggregate-1-0", "CADefaultDeviceAggregate-1-0");
    facts.aggregatePrivacy = AggregatePrivacy::Private;
    facts.isHidden = true;
    facts.outputStreamCount = 0;

    std::string err;
    err += checkVerdict(facts, DeviceListVerdict::NoOutputStream);
    facts.outputStreamCount = 2;
    err += checkVerdict(facts, DeviceListVerdict::Hidden);
    facts.isHidden = false;
    err += checkVerdict(facts, DeviceListVerdict::PrivateAggregate);
    facts.aggregatePrivacy = AggregatePrivacy::Public;
    err += checkVerdict(facts, DeviceListVerdict::ProcessDefaultAggregate);
    facts.uid = "~:AMS2_Aggregate:1";
    facts.name = "Aggregate Device";
    err += checkVerdict(facts, DeviceListVerdict::Listed);
    if (!err.empty())
    {
        logFail(kName, err);
        return;
    }
    logPass(kName);
}

// The composition decode follows AudioHardware.h: "private" 1 → private, 0 → published, key
// absent → published; CFBoolean is honoured too; anything else (a string, a fractional number,
// no dictionary) is Unknown. It borrows the dictionary: the retain count is unchanged after.
static auto testDeviceListCompositionDecode() -> void
{
    static const char* const kName = "DeviceList_CompositionDecode";
    const int one = 1;
    const int zero = 0;
    const int two = 2;
    const double half = 0.5;
    const CFNumberRef numOne = CFNumberCreate(kCFAllocatorDefault, kCFNumberIntType, &one);
    const CFNumberRef numZero = CFNumberCreate(kCFAllocatorDefault, kCFNumberIntType, &zero);
    const CFNumberRef numTwo = CFNumberCreate(kCFAllocatorDefault, kCFNumberIntType, &two);
    const CFNumberRef numHalf = CFNumberCreate(kCFAllocatorDefault, kCFNumberDoubleType, &half);

    struct Case
    {
        const char* label;
        CFTypeRef value; // nullptr = the key is absent
        AggregatePrivacy expected;
    };
    const auto cases = std::to_array<Case>({
        {"private=1", numOne, AggregatePrivacy::Private},
        {"private=0", numZero, AggregatePrivacy::Public},
        {"private=2", numTwo, AggregatePrivacy::Private},
        {"private absent", nullptr, AggregatePrivacy::Public},
        {"private=true", kCFBooleanTrue, AggregatePrivacy::Private},
        {"private=false", kCFBooleanFalse, AggregatePrivacy::Public},
        {"private=\"1\"", CFSTR("1"), AggregatePrivacy::Unknown},
        {"private=0.5", numHalf, AggregatePrivacy::Unknown},
    });

    std::string err;
    for (const Case& testCase : cases)
    {
        const CFDictionaryRef composition = createComposition(testCase.value);
        const CFIndex retainsBefore = CFGetRetainCount(composition);
        const AggregatePrivacy actual = aggregatePrivacyFromComposition(composition);
        if (actual != testCase.expected)
        {
            err += std::format("{}: expected {}, got {}; ",
                               testCase.label,
                               aggregatePrivacyString(testCase.expected),
                               aggregatePrivacyString(actual));
        }
        if (CFGetRetainCount(composition) != retainsBefore)
        {
            err += std::format("{}: the decode changed the dictionary's retain count; ",
                               testCase.label);
        }
        CFRelease(composition);
    }
    if (aggregatePrivacyFromComposition(nullptr) != AggregatePrivacy::Unknown)
    {
        err += "null dictionary: expected unreadable; ";
    }

    CFRelease(numOne);
    CFRelease(numZero);
    CFRelease(numTwo);
    CFRelease(numHalf);
    if (!err.empty())
    {
        logFail(kName, err);
        return;
    }
    logPass(kName);
}

// The log names: every enumerator has its own non-empty string.
static auto testDeviceListVerdictStrings() -> void
{
    static const char* const kName = "DeviceList_VerdictStrings";
    const std::array<DeviceListVerdict, 5> verdicts{
        DeviceListVerdict::Listed,
        DeviceListVerdict::NoOutputStream,
        DeviceListVerdict::Hidden,
        DeviceListVerdict::PrivateAggregate,
        DeviceListVerdict::ProcessDefaultAggregate,
    };
    const std::array<AggregatePrivacy, 4> privacies{
        AggregatePrivacy::NotAggregate,
        AggregatePrivacy::Public,
        AggregatePrivacy::Private,
        AggregatePrivacy::Unknown,
    };
    std::vector<std::string_view> names;
    names.reserve(verdicts.size() + privacies.size());
    for (const DeviceListVerdict verdict : verdicts)
    {
        names.emplace_back(deviceListVerdictString(verdict));
    }
    for (const AggregatePrivacy privacy : privacies)
    {
        names.emplace_back(aggregatePrivacyString(privacy));
    }
    std::string err;
    for (size_t i = 0; i < names.size(); ++i)
    {
        if (names[i].empty())
        {
            err += std::format("name {} is empty; ", i);
        }
        for (size_t j = i + 1; j < names.size(); ++j)
        {
            if (names[i] == names[j])
            {
                err += std::format("names {} and {} are both '{}'; ", i, j, names[i]);
            }
        }
    }
    if (!err.empty())
    {
        logFail(kName, err);
        return;
    }
    logPass(kName);
}

// ---------------------------------------------------------------------------
// The one output classifier (R1.1-A; council C-30 / DUP-3, C-42, P2 D44, KI-DEV-01).
// ---------------------------------------------------------------------------
namespace
{
    struct ClassifierCase
    {
        const char* what;
        uint32_t transport;
        uint32_t dataSource;
        const char* name;
        OutputDeviceType type;
        bool headphones;
    };

    auto checkClassifier(const ClassifierCase& c, bool checkType, bool checkHeadphones) -> std::string
    {
        const OutputDeviceClass got =
            classifyOutputDevice({.transportType = c.transport, .dataSource = c.dataSource, .name = c.name});
        std::string fail;
        if (checkType && got.type != c.type)
        {
            fail += std::format("\n  {}: family {} (expected {})",
                                c.what,
                                static_cast<int>(got.type),
                                static_cast<int>(c.type));
        }
        if (checkHeadphones && got.headphones != c.headphones)
        {
            fail += std::format("\n  {}: headphones {} (expected {})", c.what, got.headphones, c.headphones);
        }
        return fail;
    }

    // The fixtures. Data sources are the SDK's codes (IOAudioTypes.h): 'hdpn' headphones, 'ispk'
    // the internal speaker, 'espk' an external speaker, 'line' a line out. The Mac's own speakers
    // read 'ispk' (probed read-only on the founder's MacBook Pro, 2026-10-15); a Bluetooth or
    // AirPlay device reports none (VLC's auhal headphone check, which keys on the same property).
    constexpr std::array<ClassifierCase, 17U> kClassifierCases = {
        {
            {
                .what = "the Mac's headphone jack",
                .transport = kAudioDeviceTransportTypeBuiltIn,
                .dataSource = kIOAudioOutputPortSubTypeHeadphones,
                .name = "External Headphones",
                .type = OutputDeviceType::Builtin,
                .headphones = true,
            },
            {
                .what = "the Mac's speakers",
                .transport = kAudioDeviceTransportTypeBuiltIn,
                .dataSource = kIOAudioOutputPortSubTypeInternalSpeaker,
                .name = "MacBook Pro Speakers",
                .type = OutputDeviceType::Builtin,
                .headphones = false,
            },
            {
                .what = "a built-in output with no data source",
                .transport = kAudioDeviceTransportTypeBuiltIn,
                .dataSource = 0U,
                .name = "Built-in Output",
                .type = OutputDeviceType::Builtin,
                .headphones = false,
            },
            {
                .what = "a built-in line out",
                .transport = kAudioDeviceTransportTypeBuiltIn,
                .dataSource = kIOAudioOutputPortSubTypeLine,
                .name = "Line Out",
                .type = OutputDeviceType::Builtin,
                .headphones = false,
            },
            {
                .what = "Bluetooth headphones",
                .transport = kAudioDeviceTransportTypeBluetooth,
                .dataSource = 0U,
                .name = "AirPods Pro",
                .type = OutputDeviceType::Wireless,
                .headphones = true,
            },
            {
                .what = "Bluetooth LE headphones",
                .transport = kAudioDeviceTransportTypeBluetoothLE,
                .dataSource = 0U,
                .name = "Buds",
                .type = OutputDeviceType::Wireless,
                .headphones = true,
            },
            {
                .what = "a Bluetooth speaker that says so",
                .transport = kAudioDeviceTransportTypeBluetooth,
                .dataSource = kIOAudioOutputPortSubTypeExternalSpeaker,
                .name = "Speaker",
                .type = OutputDeviceType::Wireless,
                .headphones = false,
            },
            {
                .what = "an AirPlay receiver",
                .transport = kAudioDeviceTransportTypeAirPlay,
                .dataSource = 0U,
                .name = "Living Room",
                .type = OutputDeviceType::Wireless,
                .headphones = false,
            },
            {
                .what = "a USB headphone DAC",
                .transport = kAudioDeviceTransportTypeUSB,
                .dataSource = 0U,
                .name = "Modi+",
                .type = OutputDeviceType::USB,
                .headphones = true,
            },
            {
                .what = "a USB DAC's line out",
                .transport = kAudioDeviceTransportTypeUSB,
                .dataSource = kIOAudioOutputPortSubTypeLine,
                .name = "DAC",
                .type = OutputDeviceType::USB,
                .headphones = true,
            },
            {
                .what = "a USB interface's speaker out",
                .transport = kAudioDeviceTransportTypeUSB,
                .dataSource = kIOAudioOutputPortSubTypeExternalSpeaker,
                .name = "Interface",
                .type = OutputDeviceType::USB,
                .headphones = false,
            },
            {
                .what = "a Thunderbolt interface's headphone out",
                .transport = kAudioDeviceTransportTypeThunderbolt,
                .dataSource = kIOAudioOutputPortSubTypeHeadphones,
                .name = "Apollo",
                .type = OutputDeviceType::Unknown,
                .headphones = true,
            },
            {
                .what = "a Thunderbolt interface",
                .transport = kAudioDeviceTransportTypeThunderbolt,
                .dataSource = 0U,
                .name = "Apollo",
                .type = OutputDeviceType::Unknown,
                .headphones = false,
            },
            {
                .what = "an HDMI display",
                .transport = kAudioDeviceTransportTypeHDMI,
                .dataSource = 0U,
                .name = "LG UltraFine",
                .type = OutputDeviceType::Unknown,
                .headphones = false,
            },
            {
                .what = "a virtual device",
                .transport = kAudioDeviceTransportTypeVirtual,
                .dataSource = 0U,
                .name = "Microsoft Teams Audio",
                .type = OutputDeviceType::Unknown,
                .headphones = false,
            },
            {
                .what = "an unknown transport, AirPods by name",
                .transport = 0U,
                .dataSource = 0U,
                .name = "Ramith's AirPods",
                .type = OutputDeviceType::Wireless,
                .headphones = true,
            },
            {
                .what = "an unknown transport, nothing known",
                .transport = 0U,
                .dataSource = 0U,
                .name = "Mystery",
                .type = OutputDeviceType::Unknown,
                .headphones = false,
            },
        },
    };
} // namespace

// The family (the menu's label and icon) is the transport, else the name — unchanged by R1.1-A,
// pinned because the rule moved here from CoreAudioDevice.
static auto testOutputDeviceFamily() -> void
{
    static const char* const kName = "OutputDevice_Family";
    std::string fail;
    for (const ClassifierCase& c : kClassifierCases)
    {
        fail += checkClassifier(c, true, false);
    }
    if (!fail.empty())
    {
        logFail(kName, "an output's family:" + fail);
        return;
    }
    logPass(kName);
}

// Headphones — where crossfeed plays. The output's data source says what is plugged in where it
// reports one ('hdpn' yes; 'ispk' / 'espk' no); a line or digital out could feed either, so the
// transport decides then. By transport: Bluetooth and USB are personal outputs (a Bluetooth
// speaker reads as headphones unless it says otherwise — crossfeed still plays only if the
// listener turned it on); AirPlay is a receiver (a HomePod, a TV, a speaker), never headphones.
// Before R1.1 the rule was "wireless or USB transport": wired headphones in the Mac's own jack
// (built-in transport) could not use crossfeed, and an AirPlay speaker could.
static auto testOutputDeviceHeadphones() -> void
{
    static const char* const kName = "OutputDevice_Headphones";
    std::string fail;
    for (const ClassifierCase& c : kClassifierCases)
    {
        fail += checkClassifier(c, false, true);
    }
    if (!fail.empty())
    {
        logFail(kName, "headphones or not:" + fail);
        return;
    }
    logPass(kName);
}
