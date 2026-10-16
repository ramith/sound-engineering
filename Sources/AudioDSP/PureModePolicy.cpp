//
// PureModePolicy.cpp — pure C++ implementation of the Pure-Mode (bit-perfect) decision.
//
// CoreAudio-FREE / Obj-C-FREE: this file is compiled into the unit-test harness, which links
// neither CoreAudio nor Obj-C. It must also be -fno-exceptions / -fno-rtti clean (no throw,
// no dynamic_cast, no typeid).
//

#include "DeviceCapability.h"

#include <algorithm>
#include <cmath>
#include <limits>

namespace AdaptiveSound
{

    namespace
    {
        // A device "supports" a rate if it is within this many Hz of an advertised rate.
        // Nominal rates come back as floating-point from CoreAudio, so an exact == is unsafe.
        constexpr double kRateEpsilonHz = 1.0;
    } // namespace

    bool DeviceCapability::supportsRate(double rateHz) const
    {
        return std::ranges::any_of(availableRates,
                                   [rateHz](double rate)
                                   { return std::fabs(rate - rateHz) <= kRateEpsilonHz; });
    }

    double DeviceCapability::maxRate() const
    {
        // Sample rates are always positive, so the largest advertised rate IS the max; an empty
        // list has no rate and returns the 0 sentinel (see supportsRate() / the header contract).
        if (availableRates.empty())
        {
            return 0.0;
        }
        return std::ranges::max(availableRates);
    }

    uint32_t DeviceCapability::streamChannels() const
    {
        return (physicalFormat.channels > 0U) ? physicalFormat.channels : virtualFormat.channels;
    }

    const char* pureModeReasonString(PureModeReason reason)
    {
        switch (reason)
        {
            case PureModeReason::BitPerfectInteger:
                return "BitPerfectInteger";
            case PureModeReason::RateMatchedFloatNoSRC:
                return "RateMatchedFloatNoSRC";
            case PureModeReason::LossyWirelessCodec:
                return "LossyWirelessCodec";
            case PureModeReason::VirtualDevice:
                return "VirtualDevice";
            case PureModeReason::RateUnsupportedResample:
                return "RateUnsupportedResample";
            case PureModeReason::ChannelCountMismatch:
                return "ChannelCountMismatch";
            case PureModeReason::DeviceShallowerThanSource:
                return "DeviceShallowerThanSource";
            case PureModeReason::DeviceWouldNotStart:
                return "DeviceWouldNotStart";
            case PureModeReason::FileUnreadable:
                return "FileUnreadable";
            case PureModeReason::FileNeedsFFmpeg:
                return "FileNeedsFFmpeg";
        }
        // Unreachable for a valid enumerator; keeps the function total without a throw.
        return "Unknown";
    }

    namespace
    {
        // Smallest advertised rate >= target (the resample target rate hint for the Enhanced
        // path when the device cannot do the file's exact rate). If no advertised rate is
        // >= target, fall back to the device's maximum rate.
        double smallestRateAtLeast(const DeviceCapability& cap, double target)
        {
            double best = std::numeric_limits<double>::infinity();
            for (const double rate : cap.availableRates)
            {
                if (rate >= target && rate < best)
                {
                    best = rate;
                }
            }
            if (best == std::numeric_limits<double>::infinity())
            {
                return cap.maxRate();
            }
            return best;
        }

        // Hand the file to the Enhanced (DSP) path: no hog, no rate change, no stream format to
        // drive. `rateHint` is the Enhanced resample target where the device's rate decided it.
        PureModeEvaluation fallbackEnhanced(PureModeReason reason, double rateHint = 0.0)
        {
            PureModeEvaluation result;
            result.decision = PureModeDecision::FallbackEnhanced;
            result.reason = reason;
            result.targetDeviceRate = rateHint;
            return result;
        }
    } // namespace

    PureModeEvaluation evaluatePureMode(const DeviceCapability& cap, const FileFormat& file)
    {
        // 1. Virtual / aggregate devices have no real exclusive hardware path: never bit-perfect.
        if (cap.isVirtualOrAggregate)
        {
            return fallbackEnhanced(PureModeReason::VirtualDevice);
        }

        // 2. Lossy wireless transports (BT / BT-LE / AirPlay) re-encode below the HAL.
        if (cap.isLossyWireless)
        {
            return fallbackEnhanced(PureModeReason::LossyWirelessCodec);
        }

        // 3. Device cannot do the file's exact rate: hand off to the Enhanced (resampling) path.
        //    targetDeviceRate is the resample target hint (smallest advertised rate >= file rate,
        //    else the device maximum).
        if (!cap.supportsRate(file.sampleRate))
        {
            return fallbackEnhanced(PureModeReason::RateUnsupportedResample,
                                    smallestRateAtLeast(cap, file.sampleRate));
        }

        // 4. Pure plays the file's samples exactly as they are, channel for channel: the device
        //    stream must carry the file's channel count. A mono file on a stereo output, or a stereo
        //    file on a 4- or 8-channel interface, goes to Enhanced, which maps any width onto the
        //    device. (Rendering the mismatch would pull nothing: silence that never ends.) Mapping
        //    inside Pure (mono onto both speakers, still bit-exact per channel) would route through
        //    AUHAL's kAudioOutputUnitProperty_ChannelMap; not done yet.
        if (file.channels == 0U || file.channels != cap.streamChannels())
        {
            return fallbackEnhanced(PureModeReason::ChannelCountMismatch);
        }

        // 5. Device supports the file's exact rate and width: seize it and drive at that rate.
        PureModeEvaluation result;
        result.requiresHog = true;
        result.targetDeviceRate = file.sampleRate;
        result.targetChannels = file.channels;
        result.requiresRateChange = std::fabs(cap.currentRate - file.sampleRate) > kRateEpsilonHz;

        if (cap.integerCapable)
        {
            result.decision = PureModeDecision::FullBitPerfect;
            result.reason = PureModeReason::BitPerfectInteger;
        }
        else
        {
            result.decision = PureModeDecision::RateMatchedFloat;
            result.reason = PureModeReason::RateMatchedFloatNoSRC;
        }
        return result;
    }

    PureModeReason bitExactness(const FileFormat& file,
                                uint32_t outputBits,
                                bool outputIsFloat,
                                PureModeReason engaged)
    {
        // Pure decodes to float32: 24 significant bits reach the converter, whatever the device.
        constexpr uint32_t kFloat32SignificantBits = 24U;
        constexpr uint32_t kFloat32Bits = 32U;
        if (file.bitsPerChannel == 0U || outputBits == 0U)
        {
            return engaged; // no stated depth to compare (a compressed source, an unknown output)
        }
        if (file.isFloat)
        {
            const bool carried = outputIsFloat && file.bitsPerChannel <= kFloat32Bits;
            return carried ? engaged : PureModeReason::DeviceShallowerThanSource;
        }
        const uint32_t reaching =
            outputIsFloat ? kFloat32SignificantBits : std::min(outputBits, kFloat32SignificantBits);
        return (file.bitsPerChannel <= reaching) ? engaged
                                                 : PureModeReason::DeviceShallowerThanSource;
    }

} // namespace AdaptiveSound
