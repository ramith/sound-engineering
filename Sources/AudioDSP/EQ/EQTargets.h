#pragma once

// EQTargets.h — from a finished GraphicEQDesign to the RT module's EQParams, and the ramp-time
// rule that decides how fast the module glides there (Sprint EQ, EQ1b). Header-only; used by the
// Realizer (on its queue) and by the C++ gate.

#include "../include/TargetState.h"
#include "GraphicEQDesigner.h"
#include <algorithm>
#include <array>
#include <cmath>

namespace AdaptiveSound::EQTargets
{
    // The three glide times (engine-plan §3.2 + amendment 1).
    constexpr float kRampSeconds = kEqDefaultRampSeconds; // presets, Tone, drags, Off toggles
    constexpr float kLargeChangeRampSeconds = 0.040F;     // a big jump between two calm curves
    constexpr float kJaggedRampSeconds = 0.160F;          // either endpoint is a jagged curve

    // The largest per-band change in SOLVED gain that still glides at 10 ms.
    constexpr double kLargeChangeDb = 12.0;
    // A solved gain beyond this marks a jagged endpoint (adjacent bells fighting at ±30 dB). The
    // transient swell comes from the endpoints being jagged, not from the size of the change, so
    // such transitions take 160 ms whatever changed (breaker verify §2.1: +4.51 / +2.42 dB → ≤ 1 dB).
    constexpr double kJaggedGainDb = 15.0;

    using SolvedGains = std::array<double, kEqBandCount>;

    // The τ rule (amendment 1): pick the glide time from the published (`from`) and the new (`next`)
    // solved gains.
    [[nodiscard]] inline float rampSeconds(const SolvedGains& from,
                                           const SolvedGains& next) noexcept
    {
        double largestGain = 0.0;
        double largestChange = 0.0;
        for (size_t band = 0; band < from.size(); ++band)
        {
            largestGain = std::max({largestGain, std::abs(from[band]), std::abs(next[band])});
            largestChange = std::max(largestChange, std::abs(next[band] - from[band]));
        }
        if (largestGain > kJaggedGainDb)
        {
            return kJaggedRampSeconds;
        }
        return (largestChange <= kLargeChangeDb) ? kRampSeconds : kLargeChangeRampSeconds;
    }

    // The RT module's target for a finished design, gliding over `ramp` seconds.
    [[nodiscard]] inline EQParams toParams(const GraphicEQDesign& design, float ramp) noexcept
    {
        EQParams params{};
        for (size_t band = 0; band < params.k.size(); ++band)
        {
            params.k[band] = design.bells[band].k;
            params.m1[band] = design.bells[band].m1;
        }
        params.designSampleRate = static_cast<float>(design.sampleRate);
        params.rampSeconds = ramp;
        return params;
    }
} // namespace AdaptiveSound::EQTargets
