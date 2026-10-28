#pragma once

//
// SpatialBridge.h — Pure C header: the stereo fold's surface for Swift (R1.1-B, the level-and-fold
// design, docs/design/level-and-fold/README.md, §S2 and §9).
//
// The spatial unit (SpatialRendererAU, Spatial/SpatialRenderKernel) is the device-boundary stage: the
// identity route when the device takes every channel; the BS.775 stereo fold and its backstop when a
// multichannel file meets a narrower device. This header is its control and read-out surface.
//
// Must stay valid ISO C11 (no C++ namespaces, no <cstdint>, no class declarations): it is
// re-exported through DeviceBridge.h, the module's single Swift-visible header.
//
// THREADS. Every function here takes the AU as a borrowed (passUnretained) AUAudioUnit* — the bridge's
// `withSpatialAU` borrow — and is safe from any thread, the main thread included: the read-out is
// atomics only, never AVFAudio.
//

#include "CApiNoexcept.h"
#include <stdbool.h>
#include <stdint.h>

/// What the spatial unit plays now (S2): the badge's "5.1 → stereo", and the backstop's meter.
typedef struct
{
    /// N: the source channels the unit takes (its input bus).
    uint32_t sourceChannels;
    /// M: the channels it renders (the device boundary).
    uint32_t outputChannels;
    /// The BS.775 stereo fold plays: N > 2 and M < N.
    bool folding;
    /// The fold is the playing track's plan; false: the layout's fold at its worst-case trim (no plan
    /// yet for this width).
    bool fromPlan;
    /// The fold's trim (dB, ≤ 0).
    float trimDb;
    /// The LFE's gain per side in the fold (linear; 0 = omitted).
    float lfeGain;
    /// The deepest gain reduction the backstop applied since this fold began (dB, ≥ 0). The trim keeps
    /// it at 0; anything above 0.01 dB says the fold overloaded past its trim.
    float backstopPeakGrDb;
} AsFoldState;

#ifdef __cplusplus
extern "C"
{
#endif

    /// Read what the spatial unit plays now.
    ///
    /// @param spatialAU  Borrowed SpatialRendererAU*; false if null.
    /// @param out        Receives the state; non-null (false, nothing written, if null).
    /// @return true when written.
    bool asSpatialFoldState(void* spatialAU, AsFoldState* out) AUDIODSP_C_NOEXCEPT;

#ifdef __cplusplus
} // extern "C"
#endif
