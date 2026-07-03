#pragma once

#include <AudioToolbox/AudioToolbox.h>
#include <cstdint>

namespace AdaptiveSound
{

    // Forward declarations
    class AudioEngine;
    class DSPKernel;

    /// C++-exported AU parameter IDs.
    /// These correspond to AUAudioUnit parameter indexing.
    /// Base type is uint64_t to match the C-ABI paramID width in setAUParameter/
    /// getAUParameter (AudioUnitBridge.h); do not shrink it.
    // NOLINTNEXTLINE(performance-enum-size) PERMANENT reason="enum intentionally packed to uint8_t (ABI/layout)"
    enum class AUParameterID : uint64_t
    {
        MasterGain = 0, // EQ master gain (dB)
        Bypass = 1,     // Bypass flag (0 = process, 1 = bypass)
        Intensity = 2,  // Spatial/clarity intensity (0..1)
    };

} // namespace AdaptiveSound

/// C interface for Audio Unit creation and parameter control.
/// Exposed to Swift via module map or bridging header.
///
/// Device enumeration functions (CDeviceInfo, enumerateOutputDevicesC, etc.)
/// live in DeviceBridge.h — a pure-C header safe for Swift bridging.

#ifdef __cplusplus
extern "C"
{
#endif

    /// Create and initialize a custom AUAudioUnit v3 for Adaptive Sound.
    /// Attaches the AU to the given AVAudioEngine, sets up the render callback,
    /// and returns the AUAudioUnit instance (opaque pointer).
    ///
    /// @param audioEngine Pointer to initialized AVAudioEngine (C++ class pointer cast to void*)
    /// @param sampleRate   Target sample rate (typically 48000)
    /// @param bufferFrames Preferred buffer frame size (typically 512)
    /// @return Opaque pointer to AUAudioUnit on success, NULL on failure.
    ///
    /// **Ownership:** The caller (Swift/Obj-C) owns the lifetime; must pair with
    /// destroyAdaptiveAudioUnit() on shutdown.
    void* createAdaptiveAudioUnit(void* audioEngine, uint32_t sampleRate, uint32_t bufferFrames);

    /// Destroy and clean up an AUAudioUnit created by createAdaptiveAudioUnit().
    /// Releases render resources and frees internal state.
    ///
    /// @param auUnit Opaque pointer returned from createAdaptiveAudioUnit().
    void destroyAdaptiveAudioUnit(void* auUnit);

    /// DEAD STUB by design — kept only as part of the stable exported C-ABI (F6).
    /// It does NOT reach the RT kernel: it ignores paramID/value and returns false. The real
    /// control surfaces are the dedicated intent entry points routed through the Realizer —
    /// `publishIntensity()` (the single intensity surface) and `publishEQBandGains()` for EQ — so
    /// there are never two contradictory parameter paths. See the impl note in AUAudioUnit.mm.
    ///
    /// @param auUnit      Opaque pointer to AUAudioUnit.
    /// @param paramID     Ignored.
    /// @param value       Ignored.
    /// @return Always false (auUnit==NULL also returns false).
    bool setAUParameter(void* auUnit, uint64_t paramID, float value);

    /// DEAD STUB by design — kept only as part of the stable exported C-ABI (F6). There is no
    /// readable AU parameter store; the live values live in the Realizer's canonical TargetState.
    /// Always returns 0.0f. See `setAUParameter` / `publishIntensity` / `publishEQBandGains`.
    ///
    /// @param auUnit      Opaque pointer to AUAudioUnit.
    /// @param paramID     Ignored.
    /// @return Always 0.0f.
    float getAUParameter(void* auUnit, uint64_t paramID);

    /// Publish a new TargetState to the AU's render kernel.
    /// Called by the Realizer (off-RT) after computing new DSP parameters.
    /// This is the low-level control point; higher-level UI/logic publishes via
    /// slider callbacks that eventually call setAUParameter() for individual params.
    ///
    /// @param auUnit    Opaque pointer to AUAudioUnit.
    /// @param state     Pointer to TargetState struct (will be memcpy'd to double-buffer).
    /// @return True on success.
    bool publishTargetState(void* auUnit, const void* state);

    // publishIntensity(...) is declared in AudioUnitRegistrationBridge.h (sibling of
    // publishEQBandGains, the other control-plane intent entry point) — declared once.
    //
    // publishCrossfeed(...) likewise lives ONLY in AudioUnitRegistrationBridge.h (the same
    // control-plane intent surface) — declared once there, NOT here, to avoid a duplicate
    // declaration.

#ifdef __cplusplus
} // extern "C"
#endif
