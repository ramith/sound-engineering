//
// PureModeSource.cpp — ToneSource implementation (RT-safe sine generator).
//
// CoreAudio-FREE / Obj-C-FREE, -fno-exceptions / -fno-rtti clean. Compiled into both the AudioDSP
// target and the unit-test harness.
//

#include "PureModeSource.h"

#include <cmath>
#include <cstddef>
#include <numbers>

namespace AdaptiveSound
{

    namespace
    {
        constexpr double kTwoPi = 2.0 * std::numbers::pi;
    } // namespace

    ToneSource::ToneSource(double freqHz, float amplitude, double sampleRate) noexcept
        : amplitude_(amplitude)
    {
        if (sampleRate > 0.0)
        {
            phaseInc_ = kTwoPi * freqHz / sampleRate;
        }
    }

    uint32_t ToneSource::pullFloat(float* out, uint32_t frames, uint32_t channels) noexcept
    {
        if (out == nullptr || frames == 0U || channels == 0U)
        {
            return 0U;
        }

        for (uint32_t frame = 0U; frame < frames; ++frame)
        {
            const auto sample =
                static_cast<float>(static_cast<double>(amplitude_) * std::sin(phase_));
            phase_ += phaseInc_;
            if (phase_ >= kTwoPi)
            {
                phase_ -= kTwoPi;
            }
            float* frameStart = out + (static_cast<size_t>(frame) * channels);
            for (uint32_t chan = 0U; chan < channels; ++chan)
            {
                frameStart[chan] = sample;
            }
        }
        return frames;
    }

} // namespace AdaptiveSound
