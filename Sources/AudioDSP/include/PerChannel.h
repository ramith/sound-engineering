#ifndef ADAPTIVE_SOUND_PER_CHANNEL_H
#define ADAPTIVE_SOUND_PER_CHANNEL_H

#include "AudioConstants.h"
#include <array>
#include <cstdint>

namespace AdaptiveSound
{

    // kMaxChannels copies of a small per-channel DSP state (e.g. a biquad delay line or a
    // limiter ring), indexed by channel. Fixed `std::array` storage — no heap, RT-safe. Names
    // the intent ("this state is replicated independently per channel") in the type system,
    // replacing ad-hoc `leftFoo_`/`rightFoo_` pairs. Rule of zero. Used from Sprint 5b S1.
    template <typename State> struct PerChannel
    {
        std::array<State, kMaxChannels> slots{};

        [[nodiscard]] auto operator[](uint32_t index) noexcept -> State&
        {
            return slots[index];
        }
        [[nodiscard]] auto operator[](uint32_t index) const noexcept -> const State&
        {
            return slots[index];
        }

        // Off-RT: value-initialise every channel's state (call from initialize()).
        auto reset() noexcept -> void
        {
            for (auto& slot : slots)
            {
                slot = State{};
            }
        }
    };

} // namespace AdaptiveSound

#endif // ADAPTIVE_SOUND_PER_CHANNEL_H
