#pragma once

//
// BoundedWait.h — the control plane waiting for something the render thread is a moment away from
// publishing: the render pass inside a RenderGate leaving it, a seam the render claimed in a
// GaplessSource being published. Yield a few times (it is usually a few instructions away), then
// sleep in small steps, until the condition holds or the timeout passes.
//
// Control plane only — never on the render thread, which stays wait-free. Header-only,
// CoreAudio-free; the condition is the caller's own acquire load, so ThreadSanitizer models the edge.
//

#include <chrono>
#include <thread>

namespace AdaptiveSound
{
    // A timeout meaning "no deadline".
    inline constexpr std::chrono::microseconds kWaitForever = std::chrono::microseconds::max();

    // Wait until `done()` holds. True once it does; false if `timeout` passed first.
    template <typename Done>
    [[nodiscard]] bool waitUntil(Done done, std::chrono::microseconds timeout) noexcept
    {
        constexpr int kYieldSpins = 64;
        constexpr std::chrono::microseconds kPollStep{50};
        const bool bounded = timeout != kWaitForever;
        const auto deadline = bounded ? std::chrono::steady_clock::now() + timeout
                                      : std::chrono::steady_clock::time_point::max();
        int spins = 0;
        while (!done())
        {
            if (bounded && std::chrono::steady_clock::now() >= deadline)
            {
                return false;
            }
            if (spins < kYieldSpins)
            {
                ++spins;
                std::this_thread::yield();
            }
            else
            {
                std::this_thread::sleep_for(kPollStep);
            }
        }
        return true;
    }
} // namespace AdaptiveSound
