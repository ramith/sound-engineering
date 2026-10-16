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

        // Channels per frame of the device's output stream: the physical format's (what goes over
        // the wire), else the virtual format's; 0 when neither is known.
        [[nodiscard]] uint32_t streamChannels() const;
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
        FallbackEnhanced, // hand off to the Enhanced (DSP) path; bit-perfect not achievable
    };

    // Why Pure Mode is, or is not, playing bit-perfect — the ONE named reason (R1.1-A, council
    // C-34): it crosses the C boundary as its code (PureModeBridge.h documents the order; Swift's
    // PureModeReason mirrors it) and the UI names it. Codes are stable: append, never reorder.
    enum class PureModeReason : uint8_t
    {
        BitPerfectInteger,       // 0 device exposes integer PCM at the exact rate
        RateMatchedFloatNoSRC,   // 1 exact rate supported, but only float — no SRC needed
        LossyWirelessCodec,      // 2 BT / BT-LE / AirPlay codec sits below the HAL
        VirtualDevice,           // 3 virtual / aggregate device — no real exclusive hardware path
        RateUnsupportedResample, // 4 device cannot do the file's rate — Enhanced path must resample
        ChannelCountMismatch, // 5 the device stream's channel count is not the file's — Pure maps
                              //   no channels, so Enhanced plays it
        DeviceShallowerThanSource, // 6 Pure plays, but the output holds fewer bits than the source:
                                   //   NOT bit-perfect (council C-33; bitExactness)
        DeviceWouldNotStart,       // 7 the device would not take Pure's format, or would not start
        FileUnreadable,            // 8 no decoder that may run can read the file
        FileNeedsFFmpeg, // 9 Apple's decoder can't read the file, and FFmpeg is off (FD-3)
    };

    // The full result of evaluating Pure Mode.
    struct PureModeEvaluation
    {
        PureModeDecision decision = PureModeDecision::FallbackEnhanced;
        double targetDeviceRate = 0; // rate to drive the device at (0 = leave as-is / N/A)
        uint32_t targetChannels = 0; // channels the device stream must carry (the file's; 0 = N/A)
        bool requiresRateChange = false; // device nominal rate must change to targetDeviceRate
        bool requiresHog = false;        // exclusive (hog-mode) access is required
        PureModeReason reason = PureModeReason::VirtualDevice;
    };

    // Decide the Pure-Mode policy for one (device, file) pair. Pure function; no side effects.
    [[nodiscard]] PureModeEvaluation evaluatePureMode(const DeviceCapability& cap,
                                                      const FileFormat& file);

    // Human-readable name for a PureModeReason (logging / tests). Never returns nullptr.
    [[nodiscard]] const char* pureModeReasonString(PureModeReason reason);

    // Whether the output Pure achieved carries every bit of the source (council C-33): `engaged` —
    // the reason the session plays as (BitPerfectInteger / RateMatchedFloatNoSRC) — when it does,
    // else DeviceShallowerThanSource. Pure decodes through float32 (24 significant bits) and writes
    // the device's own format (`outputBits`, `outputIsFloat`), so an integer source is bit-perfect
    // only up to min(24, the device's bits); a float source only on a float device, at 32 bits or
    // fewer. A source with no stated depth (a compressed one: 0 bits) is taken as carried.
    [[nodiscard]] PureModeReason bitExactness(const FileFormat& file,
                                              uint32_t outputBits,
                                              bool outputIsFloat,
                                              PureModeReason engaged);

    // Whether Pure's float → integer step reduces bits the source has, and so is dithered (TPDF,
    // PureModeFormat.h — R1.1-A, founder decision 2026-10-16): the depth rule says "not bit-perfect"
    // (bitExactness) on an integer word narrower than 32 bits. A float output has no integer step; a
    // 32-bit word takes the decoded float32 exactly (what a 32-bit source lost, it lost in decoding);
    // at the exact depth nothing is reduced, and the conversion stays bit-exact.
    [[nodiscard]] bool
    ditherWhenConverting(const FileFormat& file, uint32_t outputBits, bool outputIsFloat);

} // namespace AdaptiveSound
