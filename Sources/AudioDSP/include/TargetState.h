#ifndef ADAPTIVE_SOUND_TARGET_STATE_H
#define ADAPTIVE_SOUND_TARGET_STATE_H

#include <array>
#include <cstdint>
#include <type_traits>

namespace AdaptiveSound
{

    static constexpr int kMaxBiquads = 10;

    struct EQParams
    {
        struct BiquadCoeffs
        {
            float b0, b1, b2, a1, a2;
        };
        std::array<BiquadCoeffs, kMaxBiquads> biquads;
        uint8_t numBiquads = 0;
        float masterGainLinear = 1.0f;
        uint8_t _pad[3] = {};
    };

    struct ClarityParams
    {
        float thresholdLinear = 0.1f;
        float attackCoeff = 0.f;
        float releaseCoeff = 0.f;
        float ratioRecip = 0.5f;
        float kneeWidthLinear = 0.1f;
        uint8_t enabled = 1;
        uint8_t _pad[3] = {};
    };

    struct LoudnessParams
    {
        float makeupGainLinear = 1.0f;
        float lufsTarget = -16.f;
        uint8_t enabled = 1;
        uint8_t _pad[3] = {};
    };

    struct BRIRParams
    {
        uint8_t activeSlotIndex = 0;
        float azimuthDeg = 0.f;
        float elevationDeg = 0.f;
        float roomAmountLinear = 1.0f;
        uint8_t bassMonoGated = 1;
        uint8_t _pad[3] = {};
    };

    struct LimiterParams
    {
        float truePeakCeilingLinear = 0.891f;
        float lookaheadFrames = 48.f;
        float attackCoeff = 0.f;
        float releaseCoeff = 0.f;
    };

    struct alignas(64) TargetState
    {
        EQParams eq;
        ClarityParams clarity;
        LoudnessParams loudness;
        BRIRParams brir;
        LimiterParams limiter;
        float intensityLinear = 1.0f;
        uint64_t sequenceNumber = 0;
    };

    // Verify trivially copyable at compile time (C++11 compatible)
    static_assert(std::is_trivially_copyable<TargetState>::value,
                  "TargetState must be trivially copyable");
    static_assert(std::is_standard_layout<TargetState>::value,
                  "TargetState must have standard layout");

} // namespace AdaptiveSound

#endif
