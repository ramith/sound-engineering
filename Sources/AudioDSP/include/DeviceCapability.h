#pragma once

//
// DeviceCapability.h — Pure-Mode (bit-perfect HAL output) capability model + policy.
//
// CoreAudio-FREE BY DESIGN. This header includes NO CoreAudio / Objective-C headers so the
// Pure-Mode policy is a pure, unit-testable C++ function (the C++ test harness links neither
// CoreAudio nor Obj-C). The CoreAudio glue that *fills* a DeviceCapability lives in
// CoreAudioDevice.{h,mm}; this file only models the data and decides the policy.
//
// The policy is keyed off SEMANTIC booleans (isLossyWireless / isVirtualOrAggregate /
// integerCapable) + rate support — never off a device-type enum. (Note: there is a
// pre-existing encoding mismatch between AdaptiveSound::AudioDevice::Type in CoreAudioDevice.h
// and the documented encoding in DeviceBridge.h; this model deliberately does not depend on it.)
//

#include <cstdint>
#include <vector>

namespace AdaptiveSound
{

    // A decoded AudioStreamBasicDescription, reduced to the fields Pure Mode cares about.
    struct StreamFormatInfo
    {
        double sampleRate = 0;       // nominal sample rate of this stream format (Hz)
        uint32_t bitsPerChannel = 0; // sample bit depth (e.g. 16, 24, 32)
        uint32_t channels = 0;       // channels per frame
        bool isFloat = false;        // kAudioFormatFlagIsFloat
        bool isPCM = false;          // formatID == kAudioFormatLinearPCM
    };

    // Everything Pure Mode needs to know about one output device.
    struct DeviceCapability
    {
        uint32_t id = 0;            // CoreAudio AudioDeviceID (opaque here)
        uint32_t transportType = 0; // CoreAudio transport FourCC (opaque here; not interpreted)
        double currentRate = 0;     // current nominal sample rate (Hz)
        std::vector<double> availableRates;

        StreamFormatInfo virtualFormat;  // what the HAL exposes to us
        StreamFormatInfo physicalFormat; // what goes over the wire to the DAC

        bool integerCapable = false;   // physicalFormat.isPCM && !physicalFormat.isFloat
        bool exclusiveCapable = false; // plausibly hoggable (not virtual / aggregate)
        bool isLossyWireless =
            false; // BT / BT-LE / AirPlay — codec below the HAL, never bit-perfect
        bool isVirtualOrAggregate = false;

        // True if rateHz is within 1.0 Hz of any availableRates entry.
        [[nodiscard]] bool supportsRate(double rateHz) const;

        // Largest availableRates entry, or 0 if there are none.
        [[nodiscard]] double maxRate() const;
    };

    // The format of the source file we are about to play.
    struct FileFormat
    {
        double sampleRate = 0;
        uint32_t bitsPerChannel = 0;
        uint32_t channels = 0;
        bool isFloat = false;
    };

    // What Pure Mode decided to do for a (device, file) pair.
    enum class PureModeDecision : uint8_t
    {
        FullBitPerfect,   // integer PCM at the file's exact rate — true bit-perfect
        RateMatchedFloat, // float HAL render at the file's exact rate — no sample-rate conversion
        FallbackEnhanced  // hand off to the Enhanced (DSP) path; bit-perfect not achievable
    };

    // Why Pure Mode reached its decision (for logging / tests).
    enum class PureModeReason : uint8_t
    {
        BitPerfectInteger,      // device exposes integer PCM at the exact rate
        RateMatchedFloatNoSRC,  // exact rate supported, but only float — no SRC needed
        LossyWirelessCodec,     // BT / BT-LE / AirPlay codec sits below the HAL
        VirtualDevice,          // virtual / aggregate device — no real exclusive hardware path
        RateUnsupportedResample // device cannot do the file's rate — Enhanced path must resample
    };

    // The full result of evaluating Pure Mode.
    struct PureModeEvaluation
    {
        PureModeDecision decision = PureModeDecision::FallbackEnhanced;
        double targetDeviceRate = 0;     // rate to drive the device at (0 = leave as-is / N/A)
        bool requiresRateChange = false; // device nominal rate must change to targetDeviceRate
        bool requiresHog = false;        // exclusive (hog-mode) access is required
        PureModeReason reason = PureModeReason::VirtualDevice;
    };

    // Decide the Pure-Mode policy for one (device, file) pair. Pure function; no side effects.
    [[nodiscard]] PureModeEvaluation evaluatePureMode(const DeviceCapability& cap,
                                                      const FileFormat& file);

    // Human-readable name for a PureModeReason (logging / tests). Never returns nullptr.
    [[nodiscard]] const char* pureModeReasonString(PureModeReason reason);

} // namespace AdaptiveSound
