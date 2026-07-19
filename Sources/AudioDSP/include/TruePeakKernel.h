#pragma once

// TruePeakKernel — the shared 8× polyphase windowed-sinc inter-sample-peak kernel
// (ITU-R BS.1770-5 Annex 2 posture; Kaiser β=8 ≈ −98 dB stopband).
//
// EXTRACTED from LimiterModule (S10.8 PR E) so the limiter's true-peak ceiling detector
// and the loudness meter's true-peak readout share ONE verified design: the libebur128
// conformance oracle (Tests/LoudnessOracleTests.inc) exercises this kernel through the
// limiter, and Loudness_TruePeakKernel_InterSample drives it directly.
//
// Pure, header-only, allocation-free: coefficient generation is off-RT; `phasePeak` is
// the per-sample hot path (8 × 24 dot products) both the limiter's render loop and the
// meter's tap thread run.
//
// References: ITU-R BS.1770-5 Annex 2; jiixyj/libebur128, x42/dpl.lv2 (oversampled
// true-peak detection); Kaiser & Schafer (I0 window).

#include <algorithm>
#include <array>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <numbers>

namespace AdaptiveSound::TruePeakKernel
{
    inline constexpr uint32_t kOversampling = 8U; // 8× polyphase upsample
    inline constexpr uint32_t kNumTaps = 24U;     // taps per phase (windowed sinc)
    inline constexpr uint32_t kPrototypeN = kOversampling * kNumTaps; // 192
    inline constexpr double kKaiserBeta = 8.0;         // Kaiser β (≈ −98 dB stopband)
    inline constexpr double kProtoCutoffNorm = 0.0625; // 0.5/L: pass base band, reject images
    inline constexpr uint32_t kI0MaxTerms = 25U;       // I0 Bessel series term cap
    inline constexpr double kI0ConvergeEps = 1.0e-16;  // I0 series termination

    /// Flat phase-major coefficient bank: coeffs[phase*kNumTaps + tap] = h[phase + tap*L].
    using Coefficients = std::array<double, kPrototypeN>;
    /// Newest-first sample history window for one channel.
    using History = std::array<double, kNumTaps>;

    /// Zeroth-order modified Bessel I0 (Kaiser window normalizer), series form.
    [[nodiscard]] inline auto kaiserI0(double xValue) noexcept -> double
    {
        const double half = xValue / 2.0;
        double term = 1.0;
        double sum = 1.0;
        for (uint32_t k = 1U; k <= kI0MaxTerms; ++k)
        {
            const double ratio = half / static_cast<double>(k);
            term *= ratio * ratio;
            sum += term;
            if (term < sum * kI0ConvergeEps)
            {
                break;
            }
        }
        return sum;
    }

    /// Build the 8×24 windowed-sinc polyphase upsampler (flat, phase-major).
    /// h[n] = L·(2·fc)·sinc(2·fc·(n−M))·kaiser(n,β),  M = (N−1)/2.  Off-RT.
    inline void computeCoefficients(Coefficients& coeffs) noexcept
    {
        const double center = static_cast<double>(kPrototypeN - 1U) / 2.0; // 95.5
        const double twoFc = 2.0 * kProtoCutoffNorm;                       // 0.125 = 1/L
        const double scale = static_cast<double>(kOversampling) * twoFc;   // = 1.0
        const double i0Beta = kaiserI0(kKaiserBeta);
        const double denom = static_cast<double>(kPrototypeN - 1U);

        for (uint32_t i = 0U; i < kPrototypeN; ++i)
        {
            // dist is half-integer (center = 95.5) → sincArg is never exactly 0.
            const double dist = static_cast<double>(i) - center;
            const double sincArg = twoFc * dist;
            const double sincVal =
                std::sin(std::numbers::pi * sincArg) / (std::numbers::pi * sincArg);
            const double ratio = (2.0 * dist) / denom;
            const double winArg = kKaiserBeta * std::sqrt(std::max(0.0, 1.0 - (ratio * ratio)));
            const double window = kaiserI0(winArg) / i0Beta;

            const uint32_t phase = i % kOversampling;
            const uint32_t tap = i / kOversampling;
            coeffs[(static_cast<size_t>(phase) * kNumTaps) + tap] = scale * sincVal * window;
        }
    }

    /// 8× polyphase inter-sample true peak of the NEWEST sample in `hist` (newest-first
    /// window): runs the 8 phase dot-products, returns max |·|. The caller maxes this
    /// over all active channels.
    [[nodiscard]] inline auto phasePeak(const History& hist, const Coefficients& coeffs) noexcept
        -> double
    {
        double maxPeak = 0.0;
        for (uint32_t phase = 0U; phase < kOversampling; ++phase)
        {
            const size_t base = static_cast<size_t>(phase) * kNumTaps;
            double dot = 0.0;
            for (uint32_t k = 0U; k < kNumTaps; ++k)
            {
                dot += coeffs[base + k] * hist[k];
            }
            maxPeak = std::max(maxPeak, std::abs(dot));
        }
        return maxPeak;
    }
} // namespace AdaptiveSound::TruePeakKernel
