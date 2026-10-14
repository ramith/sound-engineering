// P5b: fuzz aggregatePrivacyFromComposition + exhaustive deviceListVerdict against oracles written
// from AudioHardware.h (kAudioAggregateDeviceIsPrivateKey) / AudioHardwareBase.h (IsHidden).
#include "DeviceListPolicy.h"
#include <cmath>
#include <cstdio>
#include <random>
#include <string>
#include <vector>
using namespace AdaptiveSound;

static AggregatePrivacy oracle(CFDictionaryRef dict) {
    if (!dict) return AggregatePrivacy::Unknown;
    CFStringRef key = CFStringCreateWithCString(nullptr, "private", kCFStringEncodingUTF8); // a fresh, non-constant key
    const void* v = CFDictionaryGetValue(dict, key);
    CFRelease(key);
    if (!v) return AggregatePrivacy::Public; // "if this key is not present … published to the entire system"
    if (CFGetTypeID(v) == CFBooleanGetTypeID()) return CFBooleanGetValue((CFBooleanRef)v) ? AggregatePrivacy::Private : AggregatePrivacy::Public;
    if (CFGetTypeID(v) == CFNumberGetTypeID()) {
        CFNumberRef n = (CFNumberRef)v;
        if (!CFNumberIsFloatType(n)) {
            long long i = 0;
            CFNumberGetValue(n, kCFNumberLongLongType, &i);
            return i != 0 ? AggregatePrivacy::Private : AggregatePrivacy::Public;
        }
        double d = 0;
        CFNumberGetValue(n, kCFNumberDoubleType, &d);
        if (!std::isfinite(d) || std::floor(d) != d || d >= 9.223372036854775807e18 || d < -9.223372036854775808e18) return AggregatePrivacy::Unknown;
        return d != 0 ? AggregatePrivacy::Private : AggregatePrivacy::Public;
    }
    return AggregatePrivacy::Unknown;
}

static CFTypeRef randomValue(std::mt19937_64& g, std::string& desc) {
    switch (g() % 12) {
    case 0: desc = "true"; return CFRetain(kCFBooleanTrue);
    case 1: desc = "false"; return CFRetain(kCFBooleanFalse);
    case 2: { long long v = (long long)(g() % 5) - 2; desc = "int " + std::to_string(v); return CFNumberCreate(nullptr, kCFNumberLongLongType, &v); }
    case 3: { long long v = (g() & 1) ? INT64_MAX : INT64_MIN; desc = "int64 extreme"; return CFNumberCreate(nullptr, kCFNumberLongLongType, &v); }
    case 4: { double vs[] = {0.0, -0.0, 1.0, 0.5, -1.0, 1e19, 9.2233720368547758e18, NAN, INFINITY, -INFINITY, 2.0, 1e-300};
              double v = vs[g() % 12]; desc = "double " + std::to_string(v); return CFNumberCreate(nullptr, kCFNumberDoubleType, &v); }
    case 5: { float v = (g() & 1) ? 1.0f : 0.25f; desc = "float " + std::to_string(v); return CFNumberCreate(nullptr, kCFNumberFloatType, &v); }
    case 6: { char v = (char)(g() % 3); desc = "char " + std::to_string(v); return CFNumberCreate(nullptr, kCFNumberCharType, &v); }
    case 7: desc = "string \"1\""; return CFSTR("1");
    case 8: desc = "null"; return CFRetain(kCFNull);
    case 9: desc = "array"; return CFArrayCreate(nullptr, nullptr, 0, &kCFTypeArrayCallBacks);
    case 10: desc = "data"; return CFDataCreate(nullptr, (const UInt8*)"\1", 1);
    default: { short v = (short)((g() % 3) - 1); desc = "short " + std::to_string(v); return CFNumberCreate(nullptr, kCFNumberShortType, &v); }
    }
}

int main() {
    std::mt19937_64 g(96);
    int mismatches = 0, cases = 0;
    int counts[4] = {0, 0, 0, 0};
    if (aggregatePrivacyFromComposition(nullptr) != AggregatePrivacy::Unknown) { puts("null → not Unknown"); mismatches++; }
    for (int i = 0; i < 200000; ++i) {
        CFMutableDictionaryRef d = CFDictionaryCreateMutable(nullptr, 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
        std::string desc = "absent";
        // noise keys (real composition keys)
        const char* noise[] = {"uid", "name", "subdevices", "master", "stacked", "clock", "Private", "private "};
        for (int k = 0; k < (int)(g() % 4); ++k) {
            CFStringRef nk = CFStringCreateWithCString(nullptr, noise[g() % 8], kCFStringEncodingUTF8);
            std::string ignore; CFTypeRef nv = randomValue(g, ignore);
            CFDictionarySetValue(d, nk, nv); CFRelease(nk); CFRelease(nv);
        }
        if (g() % 6 != 0) {
            CFTypeRef v = randomValue(g, desc);
            CFDictionarySetValue(d, CFSTR("private"), v); CFRelease(v);
        }
        AggregatePrivacy got = aggregatePrivacyFromComposition(d), want = oracle(d);
        counts[(int)got]++; cases++;
        if (got != want) {
            if (mismatches < 12) printf("MISMATCH value=%s: got %s want %s\n", desc.c_str(), aggregatePrivacyString(got), aggregatePrivacyString(want));
            mismatches++;
        }
        CFRelease(d);
    }
    printf("composition decode: %d cases, %d mismatches; verdicts none/public/private/unknown = %d/%d/%d/%d\n", cases, mismatches, counts[0], counts[1], counts[2], counts[3]);

    // deviceListVerdict: exhaustive over the rule's inputs; oracle = the documented order.
    std::vector<std::string> ids = {"", "BuiltInSpeakerDevice", "CADefaultDeviceAggregate-1234-0", "cadefaultdeviceaggregate-1",
                                    "My CADefaultDeviceAggregate-", "CADefaultDeviceAggregate", "CADefaultDeviceAggregate-"};
    int vcases = 0, vmis = 0;
    for (std::uint32_t streams : {0u, 1u, 2u, 0xFFFFFFFFu})
        for (bool hidden : {false, true})
            for (int p = 0; p < 4; ++p)
                for (auto& uid : ids)
                    for (auto& name : ids) {
                        DeviceListFacts f; f.outputStreamCount = streams; f.isHidden = hidden; f.aggregatePrivacy = (AggregatePrivacy)p; f.uid = uid; f.name = name;
                        auto pre = [](const std::string& s) { return s.rfind("CADefaultDeviceAggregate-", 0) == 0; };
                        DeviceListVerdict want = streams == 0 ? DeviceListVerdict::NoOutputStream
                            : hidden ? DeviceListVerdict::Hidden
                            : (AggregatePrivacy)p == AggregatePrivacy::Private ? DeviceListVerdict::PrivateAggregate
                            : (pre(uid) || pre(name)) ? DeviceListVerdict::ProcessDefaultAggregate
                            : DeviceListVerdict::Listed;
                        vcases++;
                        if (deviceListVerdict(f) != want) vmis++;
                    }
    printf("deviceListVerdict: %d cases, %d mismatches\n", vcases, vmis);
    return (mismatches || vmis) ? 1 : 0;
}
