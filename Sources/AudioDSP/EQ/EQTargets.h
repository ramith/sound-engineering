#pragma once

// EQTargets.h — from a finished GraphicEQDesign to the RT module's EQParams, and the τ rule that
// decides how fast each band glides there (Sprint EQ, EQ1b; per band since the engine break-it's
// fix round, amendment 15). Header-only; used by the Realizer (on its queue) and by the C++ gate.
//
// THE τ RULE. The module glides every band's (k, m1) on its own one-pole (EQModule.h). How fast a
// band may move is set by the band itself:
//
//   1. Its ring time. A bell is a resonator that rings for T = 1 / (π·k·f) — about 1/(k·fs·g) in
//      the warped domain: 110 ms for a +18 dB bell at 20 Hz, 2 ms for the same bell at 1 kHz.
//      Re-tuning it much faster than that leaves a free ringing remainder that beats against the
//      programme (the low-band swells of the break-it's finding 6). A band glides at
//      τ = kRingTimes · T, T from the SHARPER of its two endpoints, scaled down for a small change
//      (the remainder grows with the size of the step: full weight from kFullChangeDb up).
//   2. Its neighbours. A graphic EQ's bells overlap, and a jagged curve is neighbours CANCELLING
//      each other (adjacent solved gains of ±30 dB for ±12 dB points). Such neighbours must stay in
//      step, or the cancellation comes undone mid-glide — while bells an octave apart are
//      independent. So the τ profile across the bands is the smallest one that covers every band's
//      own need and falls by no more than one band-spacing ratio (10^0.1, the 1/f of the ring
//      times) per band — less where adjacent bands oppose each other: by kOppositionDb / opposition
//      of that ratio's logarithm. Calm neighbours keep their own pace; fighting ones glide together.
//   3. kRampSeconds (10 ms) at the least — fast enough that any single point at 1 kHz and above
//      settles in ~25 ms — and kMaxRampSeconds at the most: the bottom octave's sharpest bells.
//
// The loudness-neutral output gain glides at the bands' τ weighted by how much each band changed,
// so the level follows the bands that move it.
//
// Measured (EQ_Transitions_*, BreakIt_*; EqEngineFixTests.inc): everyday changes, single points
// and bass gestures stay within +0.75 dB of their louder endpoint (local) and +0.5 dB of the
// curve's own maximum (peak); the breaker's jagged pairs within +1 dB.

#include "../include/TargetState.h"
#include "GraphicEQDesigner.h"
#include <algorithm>
#include <array>
#include <cmath>
#include <numbers>

namespace AdaptiveSound::EQTargets
{
    // The τ range (amendment 15): the floor every band may glide at, and the ceiling.
    constexpr float kRampSeconds = kEqDefaultRampSeconds; // 10 ms
    constexpr float kMaxRampSeconds = 0.300F;
    // τ = kRingTimes × the band's ring time (by measurement: the red bass gestures need ≥ 3).
    constexpr double kRingTimes = 3.5;
    // A change in solved gain of this size or more takes the full ring-time τ; smaller ones scale.
    constexpr double kFullChangeDb = 3.0;
    // Adjacent bands may differ in τ by the band spacing (10^0.1, the 1/f of the ring times) …
    constexpr double kNeighbourLogRatio = std::numbers::ln10 / 10.0;
    // … less where they oppose: an opposition (the smaller |gain| of two adjacent solved gains of
    // opposite sign, at either endpoint) above this many dB shrinks the allowed ratio's logarithm
    // by kOppositionDb / opposition.
    constexpr double kOppositionDb = 6.0;

    // How fast the RT module glides to a design: one τ per band, and the output gain's.
    struct Ramps
    {
        std::array<float, kEqBandCount> band = eqUniformRamp(kRampSeconds);
        float gain = kRampSeconds;
    };

    // The same τ for every band and the gain.
    [[nodiscard]] constexpr Ramps uniformRamps(float seconds) noexcept
    {
        return Ramps{.band = eqUniformRamp(seconds), .gain = seconds};
    }

    namespace detail
    {
        using BandValues = std::array<double, kEqBandCount>;

        // Rule 1: band m's own τ (0 when it does not change).
        [[nodiscard]] inline double
        ownTau(const GraphicEQDesign& from, const GraphicEQDesign& next, size_t band) noexcept
        {
            const GraphicEQ::SvfBell& before = from.bells[band];
            const GraphicEQ::SvfBell& after = next.bells[band];
            if (before.k == after.k && before.m1 == after.m1)
            {
                return 0.0;
            }
            // The sharper endpoint rings longer (a missing `from`, k 0, counts as `next`).
            const double sharpest = (before.k > 0.0) ? std::min(before.k, after.k) : after.k;
            const double ringSeconds = 1.0 / (sharpest * next.sampleRate * next.svfG[band]);
            const double change = std::abs(next.filterGainDb[band] - from.filterGainDb[band]);
            const double tau = kRingTimes * ringSeconds * std::min(1.0, change / kFullChangeDb);
            return std::isfinite(tau) ? tau : 0.0;
        }

        // Rule 2: the largest log-ratio of τ allowed between band m and band m + 1.
        [[nodiscard]] inline double allowedLogRatio(const GraphicEQDesign& from,
                                                    const GraphicEQDesign& next,
                                                    size_t band) noexcept
        {
            double opposition = 0.0;
            for (const GraphicEQDesign* design : {&from, &next})
            {
                const double lower = design->filterGainDb[band];
                const double upper = design->filterGainDb[band + 1U];
                if ((lower > 0.0) != (upper > 0.0))
                {
                    opposition = std::max(opposition, std::min(std::abs(lower), std::abs(upper)));
                }
            }
            return (opposition > kOppositionDb) ? kNeighbourLogRatio * (kOppositionDb / opposition)
                                                : kNeighbourLogRatio;
        }
    } // namespace detail

    // The τ rule (amendment 15; see the file header): each band's glide time from the published
    // design (`from`) to the new one (`next`), and the output gain's.
    [[nodiscard]] inline Ramps rampsFor(const GraphicEQDesign& from,
                                        const GraphicEQDesign& next) noexcept
    {
        constexpr size_t kBands = kEqBandCount;
        detail::BandValues tau{};
        detail::BandValues logRatio{};
        for (size_t band = 0; band < kBands; ++band)
        {
            tau[band] = detail::ownTau(from, next, band);
            if (band + 1U < kBands)
            {
                logRatio[band] = detail::allowedLogRatio(from, next, band);
            }
        }
        // The smallest profile that covers every band's need and falls no faster than allowed:
        // one sweep up the bands, one down.
        for (size_t band = 1U; band < kBands; ++band)
        {
            tau[band] = std::max(tau[band], tau[band - 1U] * std::exp(-logRatio[band - 1U]));
        }
        for (size_t band = kBands - 1U; band > 0U; --band)
        {
            tau[band - 1U] = std::max(tau[band - 1U], tau[band] * std::exp(-logRatio[band - 1U]));
        }
        Ramps ramps;
        double weightedTau = 0.0;
        double totalChange = 0.0;
        for (size_t band = 0; band < kBands; ++band)
        {
            const double clamped = std::clamp(
                tau[band], static_cast<double>(kRampSeconds), static_cast<double>(kMaxRampSeconds));
            ramps.band[band] = static_cast<float>(clamped);
            const double change = std::abs(next.filterGainDb[band] - from.filterGainDb[band]);
            weightedTau += change * clamped;
            totalChange += change;
        }
        // The output gain: the bands' τ, weighted by how much each one moves.
        ramps.gain =
            (totalChange > 0.0) ? static_cast<float>(weightedTau / totalChange) : kRampSeconds;
        return ramps;
    }

    // The RT module's target for a finished design, gliding at `ramps`.
    [[nodiscard]] inline EQParams toParams(const GraphicEQDesign& design,
                                           const Ramps& ramps) noexcept
    {
        EQParams params{};
        for (size_t band = 0; band < params.k.size(); ++band)
        {
            params.k[band] = design.bells[band].k;
            params.m1[band] = design.bells[band].m1;
        }
        params.designSampleRate = static_cast<float>(design.sampleRate);
        params.bandRampSeconds = ramps.band;
        params.gainRampSeconds = ramps.gain;
        return params;
    }

    // … gliding at one τ for every band (tests; and a first target, which snaps anyway).
    [[nodiscard]] inline EQParams toParams(const GraphicEQDesign& design, float seconds) noexcept
    {
        return toParams(design, uniformRamps(seconds));
    }
} // namespace AdaptiveSound::EQTargets
