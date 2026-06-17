//
// PureModeBridgePolicy.cpp — C-ABI wrapper for the CoreAudio-FREE Pure-Mode policy.
//
// Implements ONLY pureModeEvaluate(): it marshals the flat C structs into the C++ model, calls
// AdaptiveSound::evaluatePureMode(), and copies the result back out. CoreAudio-FREE / Obj-C-FREE,
// so it compiles into the C++ unit-test harness (which links neither). -fno-exceptions / -fno-rtti
// clean.
//
// The CoreAudio engine glue lives in PureModeBridge.mm; it is NOT part of this translation unit.
//

#include "DeviceCapability.h"
#include "PureModeBridge.h"

#include <cstdint>

extern "C"
{
    void pureModeEvaluate(const CDeviceCapability* cap,
                          const double* availableRates,
                          uint32_t rateCount,
                          const CFileFormat* file,
                          CPureModeEvaluation* out)
    {
        if (cap == nullptr || file == nullptr || out == nullptr)
        {
            return;
        }

        AdaptiveSound::DeviceCapability deviceCap;
        deviceCap.id = cap->deviceID;
        deviceCap.transportType = cap->transportType;
        deviceCap.currentRate = cap->currentRate;
        deviceCap.integerCapable = cap->integerCapable != 0U;
        deviceCap.exclusiveCapable = cap->exclusiveCapable != 0U;
        deviceCap.isLossyWireless = cap->isLossyWireless != 0U;
        deviceCap.isVirtualOrAggregate = cap->isVirtualOrAggregate != 0U;

        // The physical format carries the bit depth / channels the policy reasons about; isPCM is
        // implied by integerCapable (which the C++ model derives as isPCM && !isFloat) and the
        // float flag is the complement of integerCapable for a PCM device.
        deviceCap.physicalFormat.sampleRate = cap->currentRate;
        deviceCap.physicalFormat.bitsPerChannel = cap->physicalBitsPerChannel;
        deviceCap.physicalFormat.channels = cap->physicalChannels;
        deviceCap.physicalFormat.isFloat = cap->integerCapable == 0U;
        deviceCap.physicalFormat.isPCM = true;

        // The virtual (HAL) format is what we render into; mirror the physical fields for it.
        deviceCap.virtualFormat = deviceCap.physicalFormat;

        if (availableRates != nullptr)
        {
            deviceCap.availableRates.reserve(rateCount);
            for (uint32_t i = 0U; i < rateCount; ++i)
            {
                deviceCap.availableRates.push_back(availableRates[i]);
            }
        }

        AdaptiveSound::FileFormat fileFormat;
        fileFormat.sampleRate = file->sampleRate;
        fileFormat.bitsPerChannel = file->bitsPerChannel;
        fileFormat.channels = file->channels;
        fileFormat.isFloat = file->isFloat != 0U;

        const AdaptiveSound::PureModeEvaluation eval =
            AdaptiveSound::evaluatePureMode(deviceCap, fileFormat);

        out->decision = static_cast<uint8_t>(eval.decision);
        out->targetDeviceRate = eval.targetDeviceRate;
        out->requiresRateChange = eval.requiresRateChange ? 1U : 0U;
        out->requiresHog = eval.requiresHog ? 1U : 0U;
        out->reason = static_cast<uint8_t>(eval.reason);
    }
} // extern "C"
