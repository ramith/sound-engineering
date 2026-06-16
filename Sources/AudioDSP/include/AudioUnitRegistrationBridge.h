#pragma once

//
// AudioUnitRegistrationBridge.h — Pure-C bridging surface for Swift.
//
// Declares ONLY the two C-ABI functions Swift needs to register and describe the custom
// v3 AUAudioUnit (AdaptiveSoundAU) so it can be instantiated via AVAudioUnit.instantiate().
//
// Must stay valid ISO C: no C++ namespaces, no <cstdint>, no Obj-C. That is why these
// declarations live here and not in the C++ AudioUnitBridge.h (which cannot be a Swift
// bridging header). This header is #included from DeviceBridge.h (the single Swift bridging
// header) and from AUAudioUnit.mm (so the C++ definitions are checked against these prototypes).
//
// <AudioToolbox/AudioComponent.h> is the C (not Obj-C) home of AudioComponentDescription, so
// including it here is safe for every translation unit that pulls in DeviceBridge.h.
//

#include <AudioToolbox/AudioComponent.h>
#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C"
{
#endif

    /// Register the AdaptiveSoundAU subclass with the AudioComponent registry so it can be
    /// instantiated in-process via AVAudioUnit.instantiate(with:options:). Idempotent and
    /// thread-safe (guarded by dispatch_once). Call during engine setup before instantiating.
    void registerAdaptiveAudioUnitSubclass(void);

    /// The AudioComponentDescription the subclass is registered under. Stable for the process
    /// lifetime. Pass to AVAudioUnit.instantiate(with:options:).
    AudioComponentDescription adaptiveAudioUnitComponentDescription(void);

    /// Publish a full 31-band EQ gain vector (dB) to the live AdaptiveSoundAU (Sprint 5 M2).
    /// Off-RT control plane: computes the minimum-phase biquad cascade and atomically publishes
    /// an updated TargetState snapshot to the kernel. Does NOT touch the render thread. Must be
    /// called from a single control thread (the EQ view model on the main actor).
    ///
    /// @param auUnit       Borrowed (passUnretained) AUAudioUnit*; must be non-null.
    /// @param bandGainsDb  Pointer to `count` floats, gains in dB. Must be non-null.
    /// @param count        Must be exactly 31 (the ISO band count); any other value is rejected.
    /// @param sampleRate   Coefficient design sample rate in Hz (must be > 0).
    /// @return true if validated and published; false on any validation failure.
    bool publishEQBandGains(void* auUnit, const float* bandGainsDb, uint32_t count, double sampleRate);

#ifdef __cplusplus
} // extern "C"
#endif
