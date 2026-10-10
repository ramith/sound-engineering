#pragma once

// FiniteSamples.h — "a sample is a finite number" (Sprint EQ fix round, amendment 14).
//
// A NaN or an infinity is not audio. A corrupt 32-bit float file decodes to one, and a single such
// sample poisons every recursive state it reaches for good: an IIR's memory, a dB-domain gain
// envelope (−Inf + Inf = NaN), a loudness accumulator. Two layers keep that from happening:
//
//   1. the kernel scrubs its input once per block, on every path (DSPKernel::process);
//   2. each stage that owns long-lived state also refuses such a sample on its own (the limiter's
//      look-ahead ring, the loudness meter's K-weighting), so it recovers whatever feeds it.
//
// A non-finite sample plays as silence (0). Every finite sample passes untouched — a block of
// finite samples is only read, never written — so the bit-perfect path stays bit-perfect.
//
// Pure, header-only, RT-safe: no allocation, no locks, no OS calls.

#include <algorithm>
#include <bit>
#include <cmath>
#include <cstdint>

namespace AdaptiveSound
{
    // The sample itself, or silence when it is a NaN or an infinity.
    [[nodiscard]] inline float finiteOrSilence(float sample) noexcept
    {
        return std::isfinite(sample) ? sample : 0.0F;
    }

    // True when every one of `count` samples is finite. A float is non-finite exactly when its
    // exponent bits are all ones, so this is ONE integer max-reduction over the block: it
    // vectorises, where a floating-point test per sample would not.
    [[nodiscard]] inline bool allFinite(const float* samples, uint32_t count) noexcept
    {
        constexpr uint32_t kExponentMask = 0x7F800000U;
        uint32_t highestExponent = 0U;
        for (uint32_t i = 0U; i < count; ++i)
        {
            highestExponent =
                std::max(highestExponent, std::bit_cast<uint32_t>(samples[i]) & kExponentMask);
        }
        return highestExponent != kExponentMask;
    }

    // Replace every non-finite sample with silence, in place. A finite block is only read.
    inline void scrubNonFinite(float* samples, uint32_t count) noexcept
    {
        if (allFinite(samples, count))
        {
            return;
        }
        for (uint32_t i = 0U; i < count; ++i)
        {
            samples[i] = finiteOrSilence(samples[i]);
        }
    }
} // namespace AdaptiveSound
