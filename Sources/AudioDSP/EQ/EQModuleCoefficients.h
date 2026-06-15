#ifndef EQ_MODULE_COEFFICIENTS_H
#define EQ_MODULE_COEFFICIENTS_H

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
            return value < minVal ? minVal : (value > maxVal ? maxVal : value);
        }

      public:
        static constexpr int kNumBands = 31;
        static constexpr int kMaxBiquads = 10;

        // Standard 31-band ISO 3-octave center frequencies (Hz)
        static constexpr std::array<float, kNumBands> kCenterFrequencies = {
            20.f,   25.f,   31.5f,  40.f,    50.f,    63.f,    80.f,   100.f,
            125.f,  160.f,  200.f,  250.f,   315.f,   400.f,   500.f,  630.f,
            800.f,  1000.f, 1250.f, 1600.f,  2000.f,  2500.f,  3150.f, 4000.f,
            5000.f, 6300.f, 8000.f, 10000.f, 12500.f, 16000.f, 20000.f};

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
                if (std::abs(gains[i]) > 1e-6f)
                {
                    allZero = false;
                    break;
                }
            }

            if (allZero)
            {
                // Pass-through: single unity gain biquad
                result.biquads[0] = {1.0f, 0.0f, 0.0f, 0.0f, 0.0f};
                result.numBiquads = 1;
                result.masterGainLinear = 1.0f;
                return result;
            }

            // Realizer-style biquad fitting: fit 31-band response with cascade of up to 10 biquads
            // Phase 1b uses pre-computed coefficients; dynamic Realizer fitting deferred to Phase 2
            std::array<EQParams::BiquadCoeffs, kMaxBiquads> biquads;
            int numBiquads = fitBiquadCascade(gains, sampleRate, biquads);

            // Validate minimum-phase property (group delay check)
            if (!validateMinimumPhase(biquads, numBiquads, sampleRate))
            {
                // Fall back to identity if validation fails
                biquads[0] = {1.0f, 0.0f, 0.0f, 0.0f, 0.0f};
                numBiquads = 1;
            }

            // Copy to result
            result.numBiquads = std::min(numBiquads, kMaxBiquads);
            for (int i = 0; i < result.numBiquads; ++i)
            {
                result.biquads[i] = biquads[i];
            }
            result.masterGainLinear = 1.0f;

            return result;
        }

      private:
        // Fit 31-band gains to cascaded biquads
        // This uses a simplified fitting approach for Phase 1b:
        // - Group consecutive bands with similar gains
        // - Create peaking filters at center frequencies with proportional Q and gain
        // Returns number of biquads used (1 to kMaxBiquads)
        static int
        fitBiquadCascade(const std::array<float, kNumBands>& gains,
                         float sampleRate,
                         std::array<EQParams::BiquadCoeffs, kMaxBiquads>& outBiquads) noexcept
        {
            // Identify bands with significant gain change (≥ 0.5 dB threshold)
            std::array<bool, kNumBands> activeRegions{};
            int numActiveRegions = 0;

            for (int i = 0; i < kNumBands; ++i)
            {
                if (std::abs(gains[i]) > 0.5f)
                {
                    activeRegions[i] = true;
                    numActiveRegions++;
                }
            }

            if (numActiveRegions == 0)
            {
                // All gains below threshold: pass-through
                outBiquads[0] = {1.0f, 0.0f, 0.0f, 0.0f, 0.0f};
                return 1;
            }

            // Group consecutive active bands and create peaking filters
            int numBiquads = 0;
            int i = 0;

            while (i < kNumBands && numBiquads < kMaxBiquads)
            {
                if (activeRegions[i])
                {
                    // Find the peak of this gain region
                    int peakIdx = i;
                    float peakGain = gains[i];

                    // Extend region forward
                    while (i < kNumBands && activeRegions[i])
                    {
                        if (gains[i] > peakGain)
                        {
                            peakGain = gains[i];
                            peakIdx = i;
                        }
                        i++;
                    }

                    // Create peaking biquad at peak frequency with peak gain
                    float centerFreq = kCenterFrequencies[peakIdx];
                    float gainDb = peakGain;

                    // Clamp to safe range (±12 dB as per spec)
                    gainDb = clamp(gainDb, -12.0f, 12.0f);

                    // Create peaking filter
                    EQParams::BiquadCoeffs biquad =
                        designPeakingFilter(centerFreq, gainDb, sampleRate);
                    outBiquads[numBiquads++] = biquad;
                }
                else
                {
                    i++;
                }
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
            gainDb = clamp(gainDb, -12.0f, 12.0f);
            centerFreqHz = clamp(centerFreqHz, 20.0f, 20000.0f);

            if (std::abs(gainDb) < 0.001f)
            {
                // No gain: identity
                coeff.b0 = 1.0f;
                coeff.b1 = 0.0f;
                coeff.b2 = 0.0f;
                coeff.a1 = 0.0f;
                coeff.a2 = 0.0f;
                return coeff;
            }

            // RBJ peaking EQ filter (Audio EQ Cookbook)
            float A = std::pow(10.0f, gainDb / 40.0f); // Amplitude
            float w0 = 2.0f * std::numbers::pi_v<float> * centerFreqHz / sampleRate;
            float sinw0 = std::sin(w0);
            float cosw0 = std::cos(w0);

            // Q factor: wider for larger gains (simple Phase-1b heuristic; ~1.4 oct at
            // 6 dB, ~2.2 oct at 12 dB). Not Nyquist-aware — wide filters near 20 kHz at
            // 44.1 kHz skew their lower skirt into the audible band. Acceptable for the
            // greedy fitter; the Realizer's ERB-weighted L-M optimizer will supersede it.
            float Q = 1.0f / (0.5f + std::abs(gainDb) * 0.1f);

            float alpha = sinw0 / (2.0f * Q);

            // Peaking filter coefficients
            coeff.b0 = 1.0f + alpha * A;
            coeff.b1 = -2.0f * cosw0;
            coeff.b2 = 1.0f - alpha * A;
            coeff.a1 = -2.0f * cosw0;
            coeff.a2 = 1.0f - alpha / A; // RBJ peaking: a2 = 1 - alpha/A (matched with a0)

            // Normalize by a0
            float a0 = 1.0f + alpha / A;
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
                const auto& b = biquads[i];

                // Check stability: poles must be inside unit circle
                // For biquad: A(z) = 1 + a1*z^-1 + a2*z^-2
                // Poles are roots of A(z)
                // Simple check: |a2| < 1 and |a1| < 1 + a2

                if (std::abs(b.a2) >= 1.0f)
                {
                    return false; // Pole on or outside unit circle
                }

                if (std::abs(b.a1) > (1.0f + b.a2 + 1e-6f))
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
                if (std::abs(b.b0) < 1e-6f)
                {
                    return false; // degenerate numerator — cannot monic-normalize
                }
                const float nb1 = b.b1 / b.b0; // monic-normalized numerator coefficients
                const float nb2 = b.b2 / b.b0;
                if (std::abs(nb2) >= 1.0f)
                {
                    return false; // numerator zero on or outside unit circle
                }
                if (std::abs(nb1) > (1.0f + nb2 + 1e-6f))
                {
                    return false; // numerator zeros outside unit circle (Schur-Cohn on numerator)
                }
            }

            return true;
        }
    };

} // namespace AdaptiveSound

#endif // EQ_MODULE_COEFFICIENTS_H
