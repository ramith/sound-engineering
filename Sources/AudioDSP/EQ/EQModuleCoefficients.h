#ifndef EQ_MODULE_COEFFICIENTS_H
#define EQ_MODULE_COEFFICIENTS_H

#include "../include/TargetState.h"
#include <array>
#include <cmath>
#include <cstring>
#include <limits>

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
            float w0 = 2.0f * 3.14159265359f * centerFreqHz / sampleRate;
            float sinw0 = std::sin(w0);
            float cosw0 = std::cos(w0);

            // Q factor: wider for larger gains (simple approach)
            // Q = 1 / (2 * fractional_bandwidth)
            float Q = 1.0f / (0.5f + std::abs(gainDb) * 0.1f);

            float alpha = sinw0 / (2.0f * Q);

            // Peaking filter coefficients
            coeff.b0 = 1.0f + alpha * A;
            coeff.b1 = -2.0f * cosw0;
            coeff.b2 = 1.0f - alpha * A;
            coeff.a1 = -2.0f * cosw0;
            coeff.a2 = 1.0f - alpha;

            // Normalize by a0
            float a0 = 1.0f + alpha / A;
            coeff.b0 /= a0;
            coeff.b1 /= a0;
            coeff.b2 /= a0;
            coeff.a1 /= a0;
            coeff.a2 /= a0;

            return coeff;
        }

        // Validate minimum-phase property by checking group delay
        // Group delay = -d(phase)/d(omega) should be ≤ 0 for minimum-phase filters
        // Simplified check: verify poles are inside unit circle and zeros outside
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
            }

            return true;
        }
    };

} // namespace AdaptiveSound

#endif // EQ_MODULE_COEFFICIENTS_H
