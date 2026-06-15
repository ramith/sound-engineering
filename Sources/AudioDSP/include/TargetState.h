#ifndef ADAPTIVE_SOUND_TARGET_STATE_H
#define ADAPTIVE_SOUND_TARGET_STATE_H

#include "AudioConstants.h"
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
        std::array<BiquadCoeffs, kMaxBiquads> biquads{};
        uint8_t numBiquads = 0;
        float masterGainLinear = 1.0F;
        std::array<uint8_t, 3> _pad = {};
    };

    struct ClarityParams
    {
        float thresholdLinear = kClarityDefaultThresholdLinear;
        float attackCoeff = 0.F;
        float releaseCoeff = 0.F;
        float ratioRecip = kClarityDefaultRatioRecip;
        float kneeWidthLinear = kClarityDefaultKneeWidthLinear;
        uint8_t enabled = 1;
        std::array<uint8_t, 3> _pad = {};
    };

    struct LoudnessParams
    {
        float makeupGainLinear = 1.0F;
        float lufsTarget = kDefaultLufsTarget;
        uint8_t enabled = 1;
        std::array<uint8_t, 3> _pad = {};
    };

    struct BRIRParams
    {
        uint8_t activeSlotIndex = 0;
        float azimuthDeg = 0.F;
        float elevationDeg = 0.F;
        float roomAmountLinear = 1.0F;
        uint8_t bassMonoGated = 1;
        std::array<uint8_t, 3> _pad = {};
    };

    struct LimiterParams
    {
        float truePeakCeilingLinear = kTruePeakCeilingLinear;
        uint32_t lookaheadFrames = kLimiterLookaheadFrames; // frame count (integer)
        float attackCoeff = 0.F;
        float releaseCoeff = 0.F;
    };

    struct alignas(kCacheLineBytes) TargetState
    {
        EQParams eq;
        ClarityParams clarity;
        LoudnessParams loudness;
        BRIRParams brir;
        LimiterParams limiter;
        float intensityLinear = 1.0F;
        uint64_t sequenceNumber = 0;
    };

    // Verify trivially copyable at compile time (C++11 compatible)
    static_assert(std::is_trivially_copyable<TargetState>::value,
                  "TargetState must be trivially copyable");
    static_assert(std::is_standard_layout<TargetState>::value,
                  "TargetState must have standard layout");

} // namespace AdaptiveSound

#endif
