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
        double best = 0.0;
        for (const double rate : availableRates)
        {
            best = std::max(best, rate);
        }
        return best;
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
        }
        // Unreachable for a valid enumerator; keeps the function total without a throw.
        return "Unknown";
    }

    namespace
    {
        // Smallest advertised rate >= target (the soxr resample target hint for the Enhanced
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
    } // namespace

    PureModeEvaluation evaluatePureMode(const DeviceCapability& cap, const FileFormat& file)
    {
        PureModeEvaluation result;

        // 1. Virtual / aggregate devices have no real exclusive hardware path: never bit-perfect.
        if (cap.isVirtualOrAggregate)
        {
            result.decision = PureModeDecision::FallbackEnhanced;
            result.reason = PureModeReason::VirtualDevice;
            result.requiresHog = false;
            result.requiresRateChange = false;
            result.targetDeviceRate = 0.0;
            return result;
        }

        // 2. Lossy wireless transports (BT / BT-LE / AirPlay) re-encode below the HAL.
        if (cap.isLossyWireless)
        {
            result.decision = PureModeDecision::FallbackEnhanced;
            result.reason = PureModeReason::LossyWirelessCodec;
            result.requiresHog = false;
            result.requiresRateChange = false;
            result.targetDeviceRate = 0.0;
            return result;
        }

        // 3. Device cannot do the file's exact rate: hand off to the Enhanced (resampling) path.
        //    targetDeviceRate is the resample target hint (smallest advertised rate >= file rate,
        //    else the device maximum).
        if (!cap.supportsRate(file.sampleRate))
        {
            result.decision = PureModeDecision::FallbackEnhanced;
            result.reason = PureModeReason::RateUnsupportedResample;
            result.requiresHog = false;
            result.requiresRateChange = false;
            result.targetDeviceRate = smallestRateAtLeast(cap, file.sampleRate);
            return result;
        }

        // 4. Device supports the file's exact rate: seize it and drive at that rate.
        result.requiresHog = true;
        result.targetDeviceRate = file.sampleRate;
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

} // namespace AdaptiveSound
