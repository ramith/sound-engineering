#ifndef EQ_MODULE_COEFFICIENTS_H
#define EQ_MODULE_COEFFICIENTS_H

#include "../include/AudioConstants.h"
#include "../include/TargetState.h"
#include <algorithm> // std::min / std::max
#include <array>
#include <cmath>
#include <cstring>
#include <limits>
#include <numbers>

namespace AdaptiveSound
{

    // EQ coefficient calculation and validation
    // Maps 31-band user gains to biquad cascade coefficients (minimum-phase)
    class EQModuleCoefficients
    {
      private:
        // Helper: clamp value to range [min, max]
        static constexpr float clamp(float value, float minVal, float maxVal) noexcept
        {
            if (value < minVal)
            {
                return minVal;
            }
            if (value > maxVal)
            {
                return maxVal;
            }
            return value;
        }

      public:
        static constexpr int kNumBands = 31;
        static constexpr int kMaxBiquads = 10;

        // Standard 31-band ISO 3-octave center frequencies (Hz)
        static constexpr std::array<float, kNumBands> kCenterFrequencies = {
            20.F,   25.F,   31.5F,  40.F,    50.F,    63.F,    80.F,   100.F,
            125.F,  160.F,  200.F,  250.F,   315.F,   400.F,   500.F,  630.F,
            800.F,  1000.F, 1250.F, 1600.F,  2000.F,  2500.F,  3150.F, 4000.F,
            5000.F, 6300.F, 8000.F, 10000.F, 12500.F, 16000.F, 20000.F};

        // Compute biquad cascade from 31-band gains
        // @param gains: 31-element array of gain in dB (typically ±12 dB range)
        // @param sampleRate: sample rate in Hz
        // @returns: EQParams with computed biquads and numBiquads set
        static EQParams computeBiquadCascade(const std::array<float, kNumBands>& gains,
                                             float sampleRate) noexcept
        {
            EQParams result{};

            // Check for all-zeros (pass-through) case
            bool allZero = true;
            for (int i = 0; i < kNumBands; ++i)
            {
                if (std::abs(gains[static_cast<size_t>(i)]) > kFlatGainThresholdDb)
                {
                    allZero = false;
                    break;
                }
            }

            if (allZero)
            {
                // Pass-through: single unity gain biquad
                result.biquads[0] = kIdentityBiquad;
                result.numBiquads = 1;
                result.masterGainLinear = 1.0F;
                return result;
            }

            // Greedy biquad fitting: fit 31-band response with cascade of up to 10 biquads.
            // Coefficients are pre-computed off-RT; ML-based dynamic fitting is a future
            // enhancement.
            std::array<EQParams::BiquadCoeffs, kMaxBiquads> biquads{};
            int numBiquads = fitBiquadCascade(gains, sampleRate, biquads);

            // Validate minimum-phase property (group delay check)
            if (!validateMinimumPhase(biquads, numBiquads, sampleRate))
            {
                // Fall back to identity if validation fails
                biquads[0] = kIdentityBiquad;
                numBiquads = 1;
            }

            // Copy to result
            result.numBiquads = static_cast<uint8_t>(std::min(numBiquads, kMaxBiquads));
            for (int i = 0; i < result.numBiquads; ++i)
            {
                result.biquads[static_cast<size_t>(i)] = biquads[static_cast<size_t>(i)];
            }
            result.masterGainLinear = 1.0F;

            return result;
        }

      private:
        // RBJ Audio EQ Cookbook coefficient-design constants (peaking-filter details).
        static constexpr EQParams::BiquadCoeffs kIdentityBiquad = {1.0F, 0.0F, 0.0F, 0.0F, 0.0F};
        static constexpr float kDecibelBase = 10.0F; // dB->linear base for pow(10, ...)
        // RBJ peaking EQ: A = 10^(gainDb / 40) for peaking filters
        // (Different from shelving: A = 10^(gainDb / 6))
        static constexpr float kRbjAmplitudeExp = 40.0F;
        static constexpr float kQHeuristicBase =
            0.5F; // Q = 1/(kQHeuristicBase + |gainDb|*kQHeuristicSlope)
        static constexpr float kQHeuristicSlope = 0.1F;
        static constexpr float kPeakingFilterGainThresholdDb =
            0.001F; // |gainDb| below this -> identity
        static constexpr float kActiveRegionThresholdDb =
            0.5F; // band participates in the fit above this
        static constexpr float kFlatGainThresholdDb =
            1e-6F; // below this |gain|, the whole curve is treated as flat (pass-through)
        // Schur-Cohn stability tolerance. Reused for the |b0|<tol degenerate-numerator
        // guard too; the two roles are distinct (pole/zero stability margin vs.
        // monic-normalize safety) but share the same small epsilon.
        static constexpr float kSchurCohnTolerance = 1e-6F;

        // Fit 31-band gains to cascaded biquads.
        // Approach: split the active bands into MAXIMAL SAME-SIGN runs and place ONE peaking
        // filter per run at the run's extremum-by-MAGNITUDE (deepest cut / highest boost).
        //
        // Splitting at sign changes + tracking |gain| (not the raw maximum) is the S6 EQ-1 fix.
        // The previous version grouped every contiguous active run and tracked only the maximum
        // gain, which (a) collapsed a run of CUTS to its least-negative band — e.g. [-12,-9,-12]
        // became a single -9 dB filter, under-applying the cut — and (b) dropped the cut in a
        // boost+cut run entirely — e.g. [+6,-6] became a single +6 dB filter. A boost-only run is
        // unaffected (its extremum-by-magnitude IS its maximum), so pure-boost cascades — including
        // the golden-master +6 dB @ 1 kHz — are byte-identical to before.
        //
        // Returns number of biquads used (1 to kMaxBiquads).
        static int
        fitBiquadCascade(const std::array<float, kNumBands>& gains,
                         float sampleRate,
                         std::array<EQParams::BiquadCoeffs, kMaxBiquads>& outBiquads) noexcept
        {
            // Identify bands with significant gain (≥ 0.5 dB threshold).
            std::array<bool, kNumBands> activeRegions{};
            int numActiveRegions = 0;

            for (int i = 0; i < kNumBands; ++i)
            {
                if (std::abs(gains[static_cast<size_t>(i)]) > kActiveRegionThresholdDb)
                {
                    activeRegions[static_cast<size_t>(i)] = true;
                    numActiveRegions++;
                }
            }

            if (numActiveRegions == 0)
            {
                // All gains below threshold: pass-through
                outBiquads[0] = kIdentityBiquad;
                return 1;
            }

            int numBiquads = 0;
            int i = 0;

            while (i < kNumBands && numBiquads < kMaxBiquads)
            {
                if (!activeRegions[static_cast<size_t>(i)])
                {
                    i++;
                    continue;
                }

                // Start a run at band i; it extends only while bands stay active AND keep the same
                // sign. Active bands have |gain| > 0.5, so the sign is unambiguous (never zero).
                const bool positive = gains[static_cast<size_t>(i)] > 0.0F;
                int extremeIdx = i;
                float extremeGain = gains[static_cast<size_t>(i)];

                while (i < kNumBands && activeRegions[static_cast<size_t>(i)] &&
                       (gains[static_cast<size_t>(i)] > 0.0F) == positive)
                {
                    if (std::abs(gains[static_cast<size_t>(i)]) > std::abs(extremeGain))
                    {
                        extremeGain = gains[static_cast<size_t>(i)];
                        extremeIdx = i;
                    }
                    i++;
                }

                // Create a peaking biquad at the run's extremum band, with its (clamped) gain.
                const float centerFreq = kCenterFrequencies[static_cast<size_t>(extremeIdx)];
                const float gainDb = clamp(extremeGain, -kEQMaxGainDb, kEQMaxGainDb);
                outBiquads[static_cast<size_t>(numBiquads++)] =
                    designPeakingFilter(centerFreq, gainDb, sampleRate);
            }

            return std::max(1, numBiquads);
        }

        // Design a peaking (bell) filter using standard RBJ audio EQ cookbook formulas
        // Minimum-phase by default (simple peaking without group delay constraint)
        static EQParams::BiquadCoeffs
        designPeakingFilter(float centerFreqHz, float gainDb, float sampleRate) noexcept
        {
            EQParams::BiquadCoeffs coeff{};

            // Clamp to safe range
            gainDb = clamp(gainDb, -kEQMaxGainDb, kEQMaxGainDb);
            centerFreqHz = clamp(centerFreqHz, kAudibleBandMinHz, kAudibleBandMaxHz);

            if (std::abs(gainDb) < kPeakingFilterGainThresholdDb)
            {
                // No gain: identity
                coeff = kIdentityBiquad;
                return coeff;
            }

            // RBJ peaking EQ filter (Audio EQ Cookbook)
            float A = std::pow(kDecibelBase, gainDb / kRbjAmplitudeExp); // Amplitude
            float w0 = (2.0F * std::numbers::pi_v<float> * centerFreqHz) / sampleRate;
            float sinw0 = std::sin(w0);
            float cosw0 = std::cos(w0);

            // Q factor: wider for larger gains (simple heuristic; ~1.4 oct at
            // 6 dB, ~2.2 oct at 12 dB). Not Nyquist-aware — wide filters near 20 kHz at
            // 44.1 kHz skew their lower skirt into the audible band. Acceptable for the
            // greedy fitter; an ERB-weighted L-M optimizer is a possible future enhancement.
            float Q = 1.0F / (kQHeuristicBase + (std::abs(gainDb) * kQHeuristicSlope));

            float alpha = sinw0 / (2.0F * Q);

            // Peaking filter coefficients
            coeff.b0 = 1.0F + (alpha * A);
            coeff.b1 = -2.0F * cosw0;
            coeff.b2 = 1.0F - (alpha * A);
            coeff.a1 = -2.0F * cosw0;
            coeff.a2 = 1.0F - (alpha / A); // RBJ peaking: a2 = 1 - alpha/A (matched with a0)

            // Normalize by a0
            float a0 = 1.0F + (alpha / A);
            coeff.b0 /= a0;
            coeff.b1 /= a0;
            coeff.b2 /= a0;
            coeff.a1 /= a0;
            coeff.a2 /= a0;

            return coeff;
        }

        // Validate the minimum-phase property.
        // Minimum-phase: both poles AND zeros must be strictly inside the open unit circle.
        // Poles: roots of A(z) = 1 + a1*z^-1 + a2*z^-2.  Schur-Cohn: |a2|<1 and |a1|<1+a2.
        // Zeros: roots of B(z) = b0 + b1*z^-1 + b2*z^-2.  Monic-normalize by b0, then
        //        Schur-Cohn: |b2/b0|<1 and |b1/b0|<1+(b2/b0).
        // A correctly computed RBJ peaking filter always passes; a failure indicates
        // numerical precision degradation (extreme Q near Nyquist or very high gain).
        static bool
        validateMinimumPhase(const std::array<EQParams::BiquadCoeffs, kMaxBiquads>& biquads,
                             int numBiquads,
                             float /* sampleRate */) noexcept
        {
            for (int i = 0; i < numBiquads; ++i)
            {
                const auto& b = biquads[static_cast<size_t>(i)];

                // Check stability: both poles must lie strictly inside the unit circle.
                // For biquad: A(z) = 1 + a1*z^-1 + a2*z^-2 (poles are roots of A(z)).
                // The stability triangle (necessary AND sufficient for both roots strictly
                // inside the unit circle) reduces to exactly two inequalities:
                //   |a2| < 1   AND   |a1| < 1 + a2.
                // The second already encodes both edges of the triangle (a2 > a1 - 1 and
                // a2 > -a1 - 1 combine to a2 > |a1| - 1). There is no separate "lower
                // triangle" term for this 1+a1 z^-1+a2 z^-2 convention.
                if (std::abs(b.a2) >= 1.0F)
                {
                    return false; // Pole on or outside unit circle
                }

                if (std::abs(b.a1) > (1.0F + b.a2 + kSchurCohnTolerance))
                {
                    return false; // Poles outside unit circle (Schur-Cohn condition)
                }

                // Check for NaN/Inf
                if (!std::isfinite(b.b0) || !std::isfinite(b.b1) || !std::isfinite(b.b2) ||
                    !std::isfinite(b.a1) || !std::isfinite(b.a2))
                {
                    return false;
                }

                // Minimum-phase: numerator zeros must also be inside the unit circle.
                // Apply Schur-Cohn to monic B(z): divide by b0, test |b2/b0|<1 and
                // |b1/b0|<1+(b2/b0). A correctly designed RBJ peaking filter always
                // satisfies this in exact arithmetic; failure indicates float precision
                // degradation (extreme Q near Nyquist or high gain).
                if (std::abs(b.b0) < kSchurCohnTolerance)
                {
                    return false; // degenerate numerator — cannot monic-normalize
                }
                const float nb1 = b.b1 / b.b0; // monic-normalized numerator coefficients
                const float nb2 = b.b2 / b.b0;
                if (std::abs(nb2) >= 1.0F)
                {
                    return false; // numerator zero on or outside unit circle
                }
                if (std::abs(nb1) > (1.0F + nb2 + kSchurCohnTolerance))
                {
                    return false; // numerator zeros outside unit circle (Schur-Cohn on numerator)
                }
            }

            return true;
        }
    };

} // namespace AdaptiveSound

#endif // EQ_MODULE_COEFFICIENTS_H
