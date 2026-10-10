#pragma once

// GraphicEQBands.h — the 31-band graphic EQ's bands and its ONE bell coefficient function.
//
// Header-only and allocation-free. Shared by the designer (GraphicEQDesigner), the read-back the
// UI draws, and the real-time module (EQ1b), so the coefficients the engine runs, the curve the
// designer fits and the curve the UI draws all come from the same code (architect F16).
//
// THE BAND FILTER (engine-plan §2.1). Band m (0…30) is a bilinear bell, written as Simper's
// trapezoidal state-variable filter:
//
//   H(s) = 1 + m1·s / (s² + k·s + 1),   s = (1 − z⁻¹) / ((1 + z⁻¹)·g),   g = tan(ω_m / 2)
//   A = 10^(G/40),   k = k0_m / A,   m1 = k·(A² − 1),   k0_m = 2·tan(0.2·ω_m) / sin(ω_m)
//
// It is the RBJ / Zölzer bilinear peaking filter with alpha = tan(0.2·ω_m): its half-dB-gain
// points (G/2 dB) lie exactly 0.40·ω_m apart, and a cut is the exact inverse of the boost of the
// same size. G = 0 gives m1 = 0 exactly, so a flat band is an exact identity.
//
// EVALUATION (the C++ port rule, SOTA review item 5). On the unit circle s = jΩ with
// Ω = tan(πf/fs) / g, so
//
//   |H|² = 1 + m1·(2k + m1)·Ω² / ((1 − Ω²)² + k²·Ω²)
//
// The excess over 1 is a single product (no difference of nearly equal terms) over a sum of
// squares, so it keeps full relative precision even at 20 Hz / 192 kHz or at a 1e-3 dB gain.
// NEVER evaluate |H|² as the expanded cos-polynomial of the biquad's coefficients — it is wrong by
// 0.63 dB at 20 Hz / 192 kHz (review-sota.md).
//
// References: V. Välimäki & J. Liski, "Accurate Cascade Graphic Equalizer," IEEE SPL 24(2), 2017;
// A. Simper (Cytomic), "Linear Trap Integrated SVF"; R. Bristow-Johnson, "Audio EQ Cookbook".

#include <cmath>
#include <numbers>

namespace AdaptiveSound::GraphicEQ
{
    // The number of bands, and the per-band array length everywhere in the EQ.
    constexpr int kBandCount = 31;

    // Exact base-10 third-octave centres f_m = 10^(1.3 + 0.1·m): 19.95 Hz … 19.95 kHz. The UI
    // labels them with the rounded ISO 266 names (20, 25, 31.5 … 20 k); the maths uses these.
    constexpr double kCentreBase = 10.0;
    constexpr double kFirstCentreLog10 = 1.3;
    constexpr double kCentreLog10Step = 0.1;

    // The bell's bandwidth between its half-dB-gain points, as a fraction of its centre's angular
    // frequency: B = 0.40·ω_m (the ACGE convention; engine-plan §2.1).
    constexpr double kBandwidthFraction = 0.4;

    // dB → amplitude exponents: A = 10^(G/40) is the square root of the linear gain 10^(G/20).
    constexpr double kAmplitudeDbDivisor = 40.0;
    constexpr double kGainDbDivisor = 20.0;
    // 10·log10(x) as a natural-log scale: 10 / ln 10.
    constexpr double kPowerDbPerNeper = 10.0 / std::numbers::ln10;

    // The centre frequency (Hz) of band `band` (0 … kBandCount − 1).
    [[nodiscard]] inline double centreHz(int band) noexcept
    {
        return std::pow(kCentreBase,
                        kFirstCentreLog10 + (kCentreLog10Step * static_cast<double>(band)));
    }

    // The bilinear prewarp tan(πf / fs). For a band centre this is the SVF's g; for any frequency
    // f, (tan(πf / fs) / g)² is the warped frequency ratio Ω² the response is evaluated at.
    // Requires 0 ≤ f < fs / 2.
    [[nodiscard]] inline double prewarp(double frequencyHz, double sampleRate) noexcept
    {
        return std::tan(std::numbers::pi * frequencyHz / sampleRate);
    }

    // The unity-gain damping k0 of a bell centred at `centreFrequencyHz`: 2·tan(0.2·ω) / sin(ω).
    // Requires the centre strictly inside (0, fs / 2).
    [[nodiscard]] inline double bellK0(double centreFrequencyHz, double sampleRate) noexcept
    {
        const double omega = 2.0 * std::numbers::pi * centreFrequencyHz / sampleRate;
        return 2.0 * std::tan(kBandwidthFraction * omega / 2.0) / std::sin(omega);
    }

    // A bell's finished SVF coefficients.
    struct SvfBell
    {
        double k = 0.0;  // damping
        double m1 = 0.0; // band-pass mix; exactly 0 for a 0 dB bell
    };

    // THE bell coefficient function: gain (dB) and unity-gain damping k0 → (k, m1). Uses expm1 so
    // m1 = k·(A² − 1) keeps full relative precision at tiny gains, and is exactly 0 at 0 dB.
    [[nodiscard]] inline SvfBell svfBell(double gainDb, double unityDamping) noexcept
    {
        const double amplitude = std::exp(gainDb * std::numbers::ln10 / kAmplitudeDbDivisor);
        const double damping = unityDamping / amplitude;
        return {damping, damping * std::expm1(gainDb * std::numbers::ln10 / kGainDbDivisor)};
    }

    // The SVF's per-sample tick coefficients for prewarp g and damping k (Simper):
    // a1 = 1 / (1 + g·(g + k)), a2 = g·a1, a3 = g·a2.
    struct SvfDamping
    {
        double a1 = 1.0;
        double a2 = 0.0;
        double a3 = 0.0;
    };

    [[nodiscard]] inline SvfDamping svfDamping(double prewarpG, double damping) noexcept
    {
        const double a1 = 1.0 / (1.0 + (prewarpG * (prewarpG + damping)));
        const double a2 = prewarpG * a1;
        return {a1, a2, prewarpG * a2};
    }

    // |H|² − 1 of one bell at the warped frequency ratio Ω² (see the file header). Exactly 0 when
    // m1 == 0; always > −1, so log1p of it is finite.
    [[nodiscard]] inline double bellPowerExcess(const SvfBell& bell, double omega2) noexcept
    {
        const double offResonance = 1.0 - omega2;
        const double denominator = (offResonance * offResonance) + (bell.k * bell.k * omega2);
        return bell.m1 * ((2.0 * bell.k) + bell.m1) * omega2 / denominator;
    }

    // The dB response of one bell at the warped frequency ratio Ω².
    [[nodiscard]] inline double bellDb(const SvfBell& bell, double omega2) noexcept
    {
        return kPowerDbPerNeper * std::log1p(bellPowerExcess(bell, omega2));
    }
} // namespace AdaptiveSound::GraphicEQ
