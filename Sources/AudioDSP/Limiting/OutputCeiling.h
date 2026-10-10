#pragma once

// OutputCeiling.h — the EQ-only path's true-peak ceiling for an output (Sprint EQ, EQ2; founder
// decision 29, amendments).
//
// At Intensity 0 with the EQ on, the chain is EQ → limiter with no normaliser. At the usual
// −1 dBTP the limiter worked hard on loud masters (> 1 dB of gain reduction up to 74 % of the
// time on a −9 LUFS master) and EQ On played up to 2.75 dB under Off. On an output whose link is
// LOCAL AND LOSSLESS the ceiling is −0.1 dBTP instead — no higher than the bit-perfect Off of the
// same masters already sends. A link that RE-ENCODES keeps −1 dBTP: lossy encoders need the
// margin (EBU R128's rationale). So does an output whose real link is unknown.

#include "../include/AudioConstants.h"
#include <CoreAudio/AudioHardwareBase.h> // kAudioDeviceTransportType* (header constants only)
#include <cstdint>

namespace AdaptiveSound
{
    // The EQ-only ceiling (linear) for an output's transport (kAudioDevicePropertyTransportType
    // FourCC; 0 = unknown):
    //   −0.1 dBTP  built-in, USB, FireWire, Thunderbolt, PCI, HDMI, DisplayPort, AVB
    //   −1 dBTP    Bluetooth, Bluetooth LE, AirPlay (re-encoded), and unknown, virtual or
    //              aggregate devices (the link behind them is not known)
    [[nodiscard]] constexpr float eqOnlyCeilingLinear(uint32_t transportType) noexcept
    {
        switch (transportType)
        {
            case kAudioDeviceTransportTypeBuiltIn:
            case kAudioDeviceTransportTypeUSB:
            case kAudioDeviceTransportTypeFireWire:
            case kAudioDeviceTransportTypeThunderbolt:
            case kAudioDeviceTransportTypePCI:
            case kAudioDeviceTransportTypeHDMI:
            case kAudioDeviceTransportTypeDisplayPort:
            case kAudioDeviceTransportTypeAVB:
                return kEqOnlyWiredCeilingLinear;
            default:
                return kTruePeakCeilingLinear;
        }
    }
} // namespace AdaptiveSound
