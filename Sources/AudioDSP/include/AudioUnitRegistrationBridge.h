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
// <CoreAudioTypes/CoreAudioBaseTypes.h> is the C home of AudioChannelLayoutTag (a UInt32
// typedef) — likewise pure C and safe for every includer (Swift bridging included).
//

#include <AudioToolbox/AudioComponent.h>
#include <CoreAudioTypes/CoreAudioBaseTypes.h>
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

    /// Register the SpatialRendererAU subclass (the device-boundary N->M render stage, subtype
    /// 'aspz') with the AudioComponent registry so it can be instantiated in-process via
    /// AVAudioUnit.instantiate(with:options:). Idempotent and thread-safe (dispatch_once). Call
    /// during engine setup before instantiating. Separate registry entry from AdaptiveSoundAU.
    void registerSpatialRendererAUSubclass(void);

    /// The AudioComponentDescription the SpatialRendererAU subclass is registered under (subtype
    /// 'aspz', same manufacturer as AdaptiveSoundAU). Stable for the process lifetime. Pass to
    /// AVAudioUnit.instantiate(with:options:).
    AudioComponentDescription spatialRendererComponentDescription(void);

    /// Override the SpatialRendererAU's N->M channel routing explicitly (off-RT control plane).
    /// Normally UNNECESSARY: allocateRenderResources derives N (input) and M (output) from the
    /// connect-negotiated bus formats, so Swift just connects at the desired formats. Exposed for
    /// callers that do not drive width via the bus formats.
    ///
    /// @param auHandle    Borrowed (passUnretained) AUAudioUnit*; no-op if null.
    /// @param inChannels  Source channel count N (clamped to the DSP ceiling by the kernel).
    /// @param outChannels Device channel count M (clamped to the DSP ceiling by the kernel).
    void configureSpatialChannels(void* auHandle, uint32_t inChannels, uint32_t outChannels);

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
    bool
    publishEQBandGains(void* auUnit, const float* bandGainsDb, uint32_t count, double sampleRate);

    /// Publish the source file's channel layout tag to the live AdaptiveSoundAU (Sprint 5b M2).
    /// Off-RT control plane: decodes `tag` into the per-channel BS.1770-5 loudness weights and
    /// hands them to the kernel, which forwards them (lock-free) to the loudness worker. Does NOT
    /// touch the render thread. Must be called from a single control thread; a cheap decode plus a
    /// non-blocking publish (no allocation, no locks). No-op if `auHandle` is null.
    ///
    /// @param auHandle Borrowed (passUnretained) AUAudioUnit*; no-op if null.
    /// @param tag      CoreAudio AudioChannelLayoutTag describing the source layout; unrecognised
    ///                 tags decode to a neutral fallback (all weights 1.0).
    void publishChannelLayoutTag(void* auHandle, AudioChannelLayoutTag tag);

    /// Publish a new intensity value (the spatial/clarity coloration wet/dry mix) to the live
    /// AdaptiveSoundAU (S6 Tier-3 3a). This is the SINGLE intensity control surface (design
    /// §1.5): setAUParameter(Intensity, ...) is a dead stub. Off-RT control plane: sets the
    /// Realizer's pending-intensity slot (clamped to [0,1]) and posts a drain block on a
    /// clean->dirty transition; the canonical read-modify-write and the atomic publish happen
    /// off-main in the Realizer's serial queue. Must be called from a single control thread
    /// (the @MainActor). No-op if auUnit is null.
    ///
    /// @param auUnit    Borrowed (passUnretained) AUAudioUnit*; no-op if null.
    /// @param intensity Intensity in [0,1]; values outside the range are clamped.
    void publishIntensity(void* auUnit, float intensity);

    /// Publish a new crossfeed state (the wet-region headphone-soundstage stage) to the live
    /// AdaptiveSoundAU (QW1 §3). Off-RT control plane: sets the Realizer's pending-crossfeed slot
    /// (level clamped to [0,1], preset clamped to the valid enum range) and posts a drain block on
    /// a clean->dirty transition; the off-RT coefficient derivation (from {preset, level, fs}),
    /// the canonical read-modify-write, and the atomic publish all happen in the Realizer's serial
    /// queue. Crossfeed is a WET-region stage, so its audible depth is `crossfeed × intensity`
    /// (QW1 §4) — the Reimagine knob scales it. Must be called from a single control thread (the
    /// @MainActor). No-op if auUnit is null.
    ///
    /// @param auUnit   Borrowed (passUnretained) AUAudioUnit*; no-op if null.
    /// @param enabled  0 = bypass (bit-exact pass-through); non-zero = active.
    /// @param level    Crossfeed level in [0,1]; values outside the range are clamped.
    /// @param preset   CrossfeedPreset value (0 = Relaxed, 1 = Bauer/"Default", 2 = Strong);
    ///                 out-of-range values are clamped to the nearest valid preset.
    void publishCrossfeed(void* auUnit, uint32_t enabled, float level, uint32_t preset);

#ifdef __cplusplus
} // extern "C"
#endif
