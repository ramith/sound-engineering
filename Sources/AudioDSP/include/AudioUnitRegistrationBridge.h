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

#ifdef __cplusplus
} // extern "C"
#endif
