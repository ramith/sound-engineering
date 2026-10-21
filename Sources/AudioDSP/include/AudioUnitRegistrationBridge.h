#pragma once

//
// AudioUnitRegistrationBridge.h — Pure-C bridging surface for Swift.
//
// The C-ABI Swift reaches the two in-process v3 AUs through: their registration and component
// descriptions (so AVAudioUnit.instantiate() can make them), and the control-plane intents posted
// to the live AdaptiveSoundAU (EQ, intensity, crossfeed, track loudness, output transport, channel
// layout). Every function here has a caller in the app; the AUs' former direct-create, parameter
// and second-publish-plane entry points had none and were deleted (R1.1-A, council C-86).
//
// Must stay valid ISO C: no C++ namespaces, no <cstdint>, no Obj-C. This header is #included from
// DeviceBridge.h (the module's single Swift-visible header) and from both AU .mm files (so their
// definitions are checked against these prototypes).
//
// <AudioToolbox/AudioComponent.h> is the C (not Obj-C) home of AudioComponentDescription, so
// including it here is safe for every translation unit that pulls in DeviceBridge.h.
// <CoreAudioTypes/CoreAudioBaseTypes.h> is the C home of AudioChannelLayoutTag (a UInt32
// typedef) — likewise pure C and safe for every includer (Swift bridging included).
//

#include "CApiNoexcept.h"
#include "TrackLoudnessBridge.h" // AsLoudnessProfile (publishTrackLoudnessProfile)
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
    void registerAdaptiveAudioUnitSubclass(void) AUDIODSP_C_NOEXCEPT;

    /// The AudioComponentDescription the subclass is registered under. Stable for the process
    /// lifetime. Pass to AVAudioUnit.instantiate(with:options:).
    AudioComponentDescription adaptiveAudioUnitComponentDescription(void) AUDIODSP_C_NOEXCEPT;

    /// Register the SpatialRendererAU subclass (the device-boundary N->M render stage, subtype
    /// 'aspz') with the AudioComponent registry so it can be instantiated in-process via
    /// AVAudioUnit.instantiate(with:options:). Idempotent and thread-safe (dispatch_once). Call
    /// during engine setup before instantiating. Separate registry entry from AdaptiveSoundAU.
    void registerSpatialRendererAUSubclass(void) AUDIODSP_C_NOEXCEPT;

    /// The AudioComponentDescription the SpatialRendererAU subclass is registered under (subtype
    /// 'aspz', same manufacturer as AdaptiveSoundAU). Stable for the process lifetime. Pass to
    /// AVAudioUnit.instantiate(with:options:).
    AudioComponentDescription spatialRendererComponentDescription(void) AUDIODSP_C_NOEXCEPT;

    /// Publish the EQ to the live AdaptiveSoundAU (Sprint EQ, engine-plan §8): the 31 points the
    /// UI draws (dB) and On/Off. Off-RT control plane: the trust boundary validates, then the
    /// Realizer designs the cascade on its queue at the kernel's own sample rate and publishes
    /// the finished coefficients; the RT module glides to them. Off is a true bypass (the
    /// identity). Must be called from a single control thread (the main actor).
    ///
    /// @param auUnit    Borrowed (passUnretained) AUAudioUnit*; false if null.
    /// @param pointsDb  `count` points in dB; non-null.
    /// @param count     Must be exactly 31.
    /// @param isOn      false plays the identity (the points are kept for the next On).
    /// @return true if accepted; false — the last good EQ keeps playing — on a null pointer, a
    ///         wrong count or any non-finite point. Finite points are clamped to ±12 dB.
    bool
    publishEQ(void* auUnit, const float* pointsDb, uint32_t count, bool isOn) AUDIODSP_C_NOEXCEPT;

    /// The sample rate the EQ is designed at (the kernel's current rate), for the UI's read-back.
    /// Returns 0 if `auUnit` is null.
    double eqDesignSampleRate(void* auUnit) AUDIODSP_C_NOEXCEPT;

    /// Tell the live AdaptiveSoundAU which kind of output it plays on (Sprint EQ, EQ2; founder
    /// decision 29): the device's kAudioDevicePropertyTransportType FourCC, 0 when unknown. It
    /// sets the limiter ceiling of the EQ-only path (Intensity 0, EQ on): −0.1 dBTP on a wired or
    /// built-in output, −1 dBTP on Bluetooth, AirPlay or an unknown link. Every other path keeps
    /// −1 dBTP. Off-RT; called by the view model when the output changes. No-op if null.
    void publishOutputTransport(void* auUnit, uint32_t transportType) AUDIODSP_C_NOEXCEPT;

    /// Hand the live AdaptiveSoundAU a track's loudness profile (Sprint EQ, EQ1c): the analyzer's
    /// prefix, then its whole-track profile. The engine keeps its own reference (the blocks are
    /// shared, not copied), so the caller may release `profile` right after. The Realizer turns it
    /// into the loudness-neutral EQ gain once `trackToken` is the audible track. Off-RT; called by
    /// the track analyzer only (amendments item 3), from any one thread at a time.
    ///
    /// @param auUnit      Borrowed (passUnretained) AUAudioUnit*; false if null.
    /// @param trackToken  The track's identity token (non-zero; the same file → the same token).
    /// @param profile     From asLoudnessProfilerFinishPrefix / FinishFull; non-null.
    /// @return true if accepted; false on a null AU or profile, or a zero token.
    bool publishTrackLoudnessProfile(void* auUnit,
                                     uint64_t trackToken,
                                     const AsLoudnessProfile* profile) AUDIODSP_C_NOEXCEPT;

    /// Tell the live AdaptiveSoundAU that `trackToken` could not be analysed at all: its
    /// loudness-neutral gain falls back to the causal running estimate of the audio as it plays.
    /// Off-RT; called by the track analyzer only. No-op if `auUnit` is null or the token is 0.
    void reportTrackLoudnessFailure(void* auUnit, uint64_t trackToken) AUDIODSP_C_NOEXCEPT;

    /// Tell the live AdaptiveSoundAU which track is audible now: at a gapless seam
    /// (`gaplessSeam` true — the gain steps by at most 0.2 dB where the music is continuous) or by
    /// a fresh start. The same token again is a no-op. Off-RT; called by the playback bridge only
    /// (at the audible seam and at a fresh start — never when the next track is merely
    /// scheduled). No-op if `auUnit` is null.
    void setCurrentTrack(void* auUnit, uint64_t trackToken, bool gaplessSeam) AUDIODSP_C_NOEXCEPT;

    /// Publish the source file's channel layout tag to the live AdaptiveSoundAU (Sprint 5b M2).
    /// Off-RT control plane: decodes `tag` into the per-channel BS.1770-5 loudness weights and
    /// hands them to the kernel, which forwards them (lock-free) to the loudness worker. Does NOT
    /// touch the render thread. Must be called from a single control thread; a cheap decode plus a
    /// non-blocking publish (no allocation, no locks). No-op if `auHandle` is null.
    ///
    /// @param auHandle Borrowed (passUnretained) AUAudioUnit*; no-op if null.
    /// @param tag      CoreAudio AudioChannelLayoutTag describing the source layout; unrecognised
    ///                 tags decode to a neutral fallback (all weights 1.0).
    void publishChannelLayoutTag(void* auHandle, AudioChannelLayoutTag tag) AUDIODSP_C_NOEXCEPT;

    /// Publish a new intensity value (the spatial/clarity coloration wet/dry mix) to the live
    /// AdaptiveSoundAU (S6 Tier-3 3a). This is the SINGLE intensity control surface (design
    /// §1.5). Off-RT control plane: sets the
    /// Realizer's pending-intensity slot (clamped to [0,1]) and posts a drain block when none is
    /// pending; the canonical read-modify-write and the atomic publish happen
    /// off-main in the Realizer's serial queue. Must be called from a single control thread
    /// (the @MainActor). No-op if auUnit is null.
    ///
    /// @param auUnit    Borrowed (passUnretained) AUAudioUnit*; no-op if null.
    /// @param intensity Intensity in [0,1]; values outside the range are clamped.
    void publishIntensity(void* auUnit, float intensity) AUDIODSP_C_NOEXCEPT;

    /// Publish a new crossfeed state (the headphone crossfeed, bs2b) to the live AdaptiveSoundAU
    /// (QW1 §3; R1.1-A). Off-RT control plane: sets the Realizer's pending-crossfeed slot (preset
    /// clamped to the valid enum range) and posts a drain block when none is pending; the off-RT
    /// coefficient derivation (bs2b's, from {preset, fs}), the canonical read-modify-write and the
    /// atomic publish all happen in the Realizer's serial queue. Crossfeed is an output stage of
    /// its own, ahead of the limiter: it plays at the preset's full strength whatever Intensity is
    /// (founder decision 2026-10-14). Must be called from a single control thread (the
    /// @MainActor). No-op if auUnit is null.
    ///
    /// @param auUnit   Borrowed (passUnretained) AUAudioUnit*; no-op if null.
    /// @param enabled  0 = off (glides out, then a bit-exact pass-through); non-zero = on.
    /// @param preset   CrossfeedPreset value — bs2b's levels: 0 = Jmeier ("Relaxed"), 1 = Cmoy
    ///                 ("Default"), 2 = bs2b default ("Strong"); out of range clamps to the
    ///                 nearest.
    void publishCrossfeed(void* auUnit, uint32_t enabled, uint32_t preset) AUDIODSP_C_NOEXCEPT;

#ifdef __cplusplus
} // extern "C"
#endif
