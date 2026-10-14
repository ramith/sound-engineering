#pragma once
// The a206107 RenderGate ALGORITHM (one state word; close = CAS Open->Closed, polled) re-expressed
// in the fix branch's API so the fix's NEW tests can run against the OLD algorithm.
// requestClose() can only try once (the old gate had no pending-close state); awaitQuiet() keeps
// trying the CAS; kWaitForever = no deadline (avoids now()+max overflow).
#include <atomic>
#include <chrono>
#include <cstdint>
#include <thread>
namespace AdaptiveSound {
class RenderGate {
  public:
    static constexpr std::chrono::microseconds kWaitForever = std::chrono::microseconds::max();
    [[nodiscard]] bool tryEnter() noexcept { State e = State::Open; return s_.compare_exchange_strong(e, State::Rendering, std::memory_order_acquire, std::memory_order_relaxed); }
    void leave() noexcept { s_.store(State::Open, std::memory_order_release); }
    [[nodiscard]] bool requestClose() noexcept {
        State e = State::Open;
        if (s_.compare_exchange_strong(e, State::Closed, std::memory_order_acquire, std::memory_order_acquire)) return false;
        return e == State::Rendering;
    }
    [[nodiscard]] bool awaitQuiet(std::chrono::microseconds timeout) noexcept {
        const bool bounded = timeout != kWaitForever;
        const auto deadline = bounded ? std::chrono::steady_clock::now() + timeout : std::chrono::steady_clock::time_point::max();
        for (;;) {
            State e = State::Open;
            if (s_.compare_exchange_weak(e, State::Closed, std::memory_order_acquire, std::memory_order_acquire)) return true;
            if (e == State::Closed) return true;
            if (e == State::Open) continue;
            if (bounded && std::chrono::steady_clock::now() >= deadline) return false;
            std::this_thread::sleep_for(std::chrono::microseconds{50});
        }
    }
    [[nodiscard]] bool close(std::chrono::microseconds timeout) noexcept { return awaitQuiet(timeout); }
    void open() noexcept { State e = State::Closed; (void)s_.compare_exchange_strong(e, State::Open, std::memory_order_release, std::memory_order_relaxed); }
    [[nodiscard]] bool isClosed() const noexcept { return s_.load(std::memory_order_acquire) == State::Closed; }
  private:
    enum class State : uint8_t { Open, Rendering, Closed };
    std::atomic<State> s_{State::Open};
};
}
