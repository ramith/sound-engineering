// EQTestBridge.h — Pure C header for Swift test bridging.
//
// MUST remain valid ISO C11 (no C++ namespaces, no class declarations,
// no #include <cstdint>).  Imported by the Swift XCTest target via
// a module map; compiled by the Obj-C++ EQTestBridge.mm implementation.

#pragma once

#include <stdint.h>

#ifdef __cplusplus
extern "C"
{
#endif

    // ---------------------------------------------------------------------------
    // CEQBiquadCoeffs — flat C mirror of EQParams::BiquadCoeffs
    //
    // The Swift test calls computeEQCoefficients() and inspects individual biquad
    // sections without needing to know about the C++ EQParams struct layout.
    // ---------------------------------------------------------------------------
    typedef struct
    {
        float b0, b1, b2, a1, a2;
    } CEQBiquadCoeffs;

// ---------------------------------------------------------------------------
// CEQParams — flat C mirror of AdaptiveSound::EQParams
//
// kMaxBiquads == 10 (matches AdaptiveSound::kMaxBiquads in TargetState.h).
// ---------------------------------------------------------------------------
#define CEQ_MAX_BIQUADS 10

    typedef struct
    {
        CEQBiquadCoeffs biquads[CEQ_MAX_BIQUADS];
        uint8_t numBiquads;
        float masterGainLinear;
    } CEQParams;

    // ---------------------------------------------------------------------------
    // EQ Coefficient computation bridge
    //
    // @param bandGainsDb  31-element array of per-band gain values in dB.
    // @param sampleRate   Sample rate in Hz (e.g. 48000.0).
    // @param outParams    Caller-allocated CEQParams to receive results.
    // ---------------------------------------------------------------------------
    void computeEQCoefficientsC(const float* bandGainsDb, float sampleRate, CEQParams* outParams);

    // ---------------------------------------------------------------------------
    // EQModule process bridge
    //
    // Creates a temporary EQModule, initializes it, publishes the given coefficients
    // via publishCoefficients(), then calls process() once with the provided buffer.
    //
    // The buffer is processed in-place: input samples are overwritten with output.
    //
    // @param ioBuffer   Float buffer (mono), length numFrames.  Modified in-place.
    // @param params     Coefficient parameters to use (biquads + masterGainLinear).
    // @param numFrames  Number of frames to process.  Must be <= 512.
    // ---------------------------------------------------------------------------
    void eqModuleProcessC(float* ioBuffer, const CEQParams* params, uint32_t numFrames);

    // ---------------------------------------------------------------------------
    // EQModule STREAMING process bridge
    //
    // Runs the ENTIRE signal through ONE persistent EQModule (initialized once,
    // coefficients published once), processing in <=512-frame windows while
    // PRESERVING filter delay state and the master-gain ramp across windows — i.e.
    // it models the real render thread's long-lived module. This is different from
    // eqModuleProcessC, which rebuilds a fresh module every call (resetting filter
    // state and restarting the 32 ms master-gain ramp on each chunk).
    //
    // Use this for any measurement that depends on settled / steady-state output
    // (frequency response, per-band gain, master-gain settling). Measure the
    // SETTLED TAIL of the result — discard the leading transient.
    //
    // @param ioBuffer   Float buffer (mono), length numFrames.  Modified in-place.
    // @param params     Coefficient parameters (biquads + masterGainLinear).
    // @param numFrames  Total frames to process (any length; windowed internally).
    // ---------------------------------------------------------------------------
    void eqModuleProcessStreamC(float* ioBuffer, const CEQParams* params, uint32_t numFrames);

#ifdef __cplusplus
} // extern "C"
#endif
