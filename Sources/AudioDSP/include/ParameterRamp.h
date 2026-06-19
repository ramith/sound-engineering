#ifndef ADAPTIVE_SOUND_PARAMETER_RAMP_H
#define ADAPTIVE_SOUND_PARAMETER_RAMP_H

#include <cmath>

namespace AdaptiveSound
{

    // ---------------------------------------------------------------------------
    // ParameterRamp — one-pole IIR smoother for zipper-noise-free gain changes.
    //
    // Model: y[n] = α·target + (1-α)·y[n-1]   (one-pole low-pass on the target)
    //
    // Coefficient: α = 1 - exp(-1 / (τ · fs))
    //   where τ is the 1/e time constant (seconds) and fs is the sample rate.
    //   This follows directly from the bilinear approximation of the RC circuit,
    //   but uses the exact discrete-time solution (Julius O. Smith, CCRMA,
    //   "Introduction to Digital Filters", §1.3.1).
    //   At 32 ms / 48 kHz: α ≈ 0.000648, giving ~98% of the step in 5τ ≈ 160 ms.
    //
    // RT-safety: tick() is noexcept with no allocation; target is written off-RT
    // before process() is called (no concurrent write during tick()).
    //
    // Shared DSP infrastructure: used by both the EQ and Loudness modules; it lives
    // here (not under EQ/) so Loudness need not depend on the EQ header (P2-G).
    // ---------------------------------------------------------------------------
    struct ParameterRamp
    {
        float target = 0.0F;
        float current = 0.0F;
        float alpha = 0.0F; // (1-α) pole coefficient; α = 1 - alpha

        // Off-RT: compute coefficient for the given time constant and sample rate.
        auto initialize(float timeConstantSeconds, float sampleRate) noexcept -> void
        {
            // Exact discrete-time RC: α = 1 - exp(-1/(τ·fs))
            // (1-α) is the pole; stored as 'alpha' to avoid repeated subtraction.
            alpha = 1.0F - std::exp(-1.0F / (timeConstantSeconds * sampleRate));
        }

        // RT: advance one sample toward target; returns current smoothed value.
        auto tick() noexcept -> float
        {
            current += alpha * (target - current);
            return current;
        }

        // RT: set current = target immediately (used at initialization so the
        // first buffer does not ramp up from zero).
        auto snap() noexcept -> void
        {
            current = target;
        }
    };

} // namespace AdaptiveSound

#endif // ADAPTIVE_SOUND_PARAMETER_RAMP_H
