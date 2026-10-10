#pragma once

#include <cstdio>
#include <cstdlib>
#include <format>
#include <string>
#include <utility>

namespace AdaptiveSound::log
{

    // Off-RT (control-plane) diagnostic logging ONLY — never call on the RT render path
    // (render/process/pullFloat). Replaces the scattered fprintf/NSLog calls that each needed a
    // `cppcoreguidelines-pro-type-vararg` suppression (Stage-2 suppression audit).
    //
    // Why this is suppression-free: `std::format_string<Args...>` is CONSTEVAL — the format string
    // is validated against the argument types at COMPILE TIME, so a bad specifier is a build error
    // (not a runtime std::format_error), which matters under -fno-exceptions. And `std::format` is a
    // VARIADIC TEMPLATE, not a C `...` ellipsis, so pro-type-vararg does not fire; `std::fwrite` is
    // non-variadic. Allocates a std::string — fine off-RT (on OOM under -fno-exceptions it
    // terminates rather than throws; the RT path never calls this).
    template <class... Args> void line(std::format_string<Args...> fmt, Args&&... args)
    {
        std::string msg = std::format(fmt, std::forward<Args>(args)...);
        msg.push_back('\n');
        std::fwrite(msg.data(), 1, msg.size(), stderr);
    }

    // Debug-level lines: printed only when ADAPTIVESOUND_DEBUG_LOG is set in the environment (read
    // once, thread-safely). For the per-publish control-plane trace (the [QW1] lines), which
    // floods the log during an EQ drag (amendment 6); errors and rejections stay on line().
    [[nodiscard]] inline bool debugEnabled() noexcept
    {
        static const bool enabled = std::getenv("ADAPTIVESOUND_DEBUG_LOG") != nullptr;
        return enabled;
    }

    template <class... Args> void debug(std::format_string<Args...> fmt, Args&&... args)
    {
        if (debugEnabled())
        {
            line(fmt, std::forward<Args>(args)...);
        }
    }

} // namespace AdaptiveSound::log
