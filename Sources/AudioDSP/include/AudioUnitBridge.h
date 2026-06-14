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
    enum class AUParameterID : uint64_t
    {
        MasterGain = 0, // EQ master gain (dB)
        Bypass = 1,     // Bypass flag (0 = process, 1 = bypass)
        Intensity = 2,  // Spatial/clarity intensity (0..1)
    };

} // namespace AdaptiveSound

/// C interface for Audio Unit creation and parameter control.
/// Exposed to Swift via module map or bridging header.

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

    /// Set a parameter on the AU (off-RT safe).
    /// Changes are published to the RT kernel via the DoubleBufferSnapshot.
    ///
    /// @param auUnit      Opaque pointer to AUAudioUnit.
    /// @param paramID     Parameter ID (see AUParameterID enum).
    /// @param value       Parameter value (semantics depend on paramID).
    /// @return True on success, false if paramID is invalid or auUnit is NULL.
    bool setAUParameter(void* auUnit, uint64_t paramID, float value);

    /// Get the current value of a parameter from the AU.
    /// Reads from the last published TargetState snapshot.
    ///
    /// @param auUnit      Opaque pointer to AUAudioUnit.
    /// @param paramID     Parameter ID.
    /// @return Parameter value, or 0.0f if paramID is invalid or auUnit is NULL.
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

#ifdef __cplusplus
} // extern "C"
#endif
