#include "DeviceCapability.h"
#include <cstdio>
using namespace AdaptiveSound;
int main() {
    // getAvailableSampleRates() turns ONE continuous AudioValueRange [8000, 192000] into {8000, 192000}
    // (CoreAudioDevice.cpp:427-431). AudioHardwareBase.h: the ranges are "the valid ranges for the nominal
    // sample rate" — 44 100 Hz IS valid on such a device.
    DeviceCapability cap;
    cap.availableRates = {8000.0, 192000.0};
    cap.currentRate = 48000.0;
    cap.integerCapable = true;
    FileFormat file;
    file.sampleRate = 44100.0;
    PureModeEvaluation e = evaluatePureMode(cap, file);
    std::printf("continuous [8000-192000] device, 44.1 kHz file → %s (target %.0f Hz)\n", pureModeReasonString(e.reason), e.targetDeviceRate);
    return e.reason == PureModeReason::RateUnsupportedResample ? 1 : 0;
}
