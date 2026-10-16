//
// FFmpegLoader.cpp — FFmpeg's opt-in switch and its hardened load (R1.1-A, founder decision FD-3,
// council C-99). See FFmpegLoader.h for the rules; FFmpegBridge.h for the C surface Swift uses.
//
// CoreAudio-FREE (POSIX + dyld only): compiled into the C++ null test. -fno-exceptions /
// -fno-rtti clean. Control plane only — never the audio thread.
//

#include "include/FFmpegLoader.h"

#include "include/AsLog.h"
#include "include/FFmpegBridge.h"

#include <array>
#include <atomic>
#include <climits>
#include <cstdint>
#include <cstdlib>
#include <dlfcn.h>
#include <format>
#include <span>
#include <string>
#include <string_view>
#include <sys/stat.h>
#include <unistd.h>

namespace AdaptiveSound::ffmpeg
{
    namespace
    {
        // The switch: off when the process starts (FD-3).
        std::atomic<bool>& enabledFlag() noexcept
        {
            static std::atomic<bool> flag{false};
            return flag;
        }

        // Every dlopen this process made for FFmpeg.
        std::atomic<uint64_t>& loadAttemptCount() noexcept
        {
            static std::atomic<uint64_t> count{0U};
            return count;
        }

        // How the last load went (LoadOutcome).
        std::atomic<LoadOutcome>& lastOutcome() noexcept
        {
            static std::atomic<LoadOutcome> outcome{LoadOutcome::NotTried};
            return outcome;
        }

        // Homebrew's library folders: Apple Silicon, then Intel. Absolute, and nothing else.
        constexpr std::array<std::string_view, 2> kDirectories = {
            "/opt/homebrew/lib",
            "/usr/local/lib",
        };

        // A permission another user could change the file (or its folder's entries) with.
        constexpr uint32_t kWritableByOthers = S_IWGRP | S_IWOTH;

        // The superuser.
        constexpr uint32_t kRootUID = 0U;

        // Root, or the user the app runs as: the only owners a library may have.
        [[nodiscard]] bool trustedOwner(uint32_t owner, uint32_t currentUID) noexcept
        {
            return owner == kRootUID || owner == currentUID;
        }

        // The path a file resolves to (symlinks followed), or "".
        [[nodiscard]] std::string resolvedPath(const char* path) noexcept
        {
            std::array<char, PATH_MAX> buffer{};
            if (path == nullptr || ::realpath(path, buffer.data()) == nullptr)
            {
                return {};
            }
            return {buffer.data()};
        }

        // Whether `handle` is the image of the file at `resolved`: dlopen honours DYLD_LIBRARY_PATH
        // even for an absolute path in a process that isn't hardened, and the file could be swapped
        // between the check and the open — so where the probe symbol really lives is what counts.
        [[nodiscard]] bool
        isImageOf(void* handle, const char* probeSymbol, const std::string& resolved) noexcept
        {
            void* symbol = (probeSymbol != nullptr) ? ::dlsym(handle, probeSymbol) : nullptr;
            Dl_info info{};
            if (symbol == nullptr || ::dladdr(symbol, &info) == 0 || info.dli_fname == nullptr)
            {
                return false;
            }
            return resolvedPath(info.dli_fname) == resolved;
        }
    } // namespace

    void setEnabled(bool enabled) noexcept
    {
        enabledFlag().store(enabled, std::memory_order_release);
    }

    bool isEnabled() noexcept
    {
        return enabledFlag().load(std::memory_order_acquire);
    }

    LibraryVerdict vetLibrary(const LibraryFileFacts& facts, uint32_t currentUID) noexcept
    {
        if (!facts.exists)
        {
            return LibraryVerdict::Missing;
        }
        if (!facts.isRegularFile)
        {
            return LibraryVerdict::NotARegularFile;
        }
        if (!trustedOwner(facts.ownerUID, currentUID))
        {
            return LibraryVerdict::UntrustedOwner;
        }
        if ((facts.mode & kWritableByOthers) != 0U)
        {
            return LibraryVerdict::WritableByOthers;
        }
        // Another user who can write the folder can replace the file in it (a sticky bit only
        // stops them renaming over a file they don't own, not planting one first).
        if (!trustedOwner(facts.directoryOwnerUID, currentUID) ||
            (facts.directoryMode & kWritableByOthers) != 0U)
        {
            return LibraryVerdict::DirectoryNotPrivate;
        }
        return LibraryVerdict::Trusted;
    }

    std::span<const std::string_view> libraryDirectories() noexcept
    {
        return kDirectories;
    }

    std::string libraryPath(std::string_view directory, std::string_view base, int major)
    {
        return std::format("{}/{}.{}.dylib", directory, base, major);
    }

    LibraryFileFacts readFacts(const std::string& path, std::string& resolved) noexcept
    {
        LibraryFileFacts facts;
        resolved = resolvedPath(path.c_str());
        struct stat file{};
        if (resolved.empty() || ::lstat(resolved.c_str(), &file) != 0)
        {
            return facts;
        }
        facts.exists = true;
        facts.isRegularFile = S_ISREG(file.st_mode);
        facts.ownerUID = static_cast<uint32_t>(file.st_uid);
        facts.mode = static_cast<uint32_t>(file.st_mode);

        const std::size_t slash = resolved.rfind('/');
        const std::string directory = (slash == 0U) ? std::string("/") : resolved.substr(0U, slash);
        struct stat folder{};
        if (::stat(directory.c_str(), &folder) == 0)
        {
            facts.directoryOwnerUID = static_cast<uint32_t>(folder.st_uid);
            facts.directoryMode = static_cast<uint32_t>(folder.st_mode);
        }
        else
        {
            facts.directoryOwnerUID = UINT32_MAX; // unknown: not private
        }
        return facts;
    }

    OpenedLibrary openLibrary(std::string_view base, int major, const char* probeSymbol) noexcept
    {
        OpenedLibrary result;
        if (!isEnabled())
        {
            return result; // off: no dlopen, ever
        }
        const auto currentUID = static_cast<uint32_t>(::getuid());
        for (const std::string_view directory : kDirectories)
        {
            const std::string candidate = libraryPath(directory, base, major);
            std::string resolved;
            const LibraryVerdict verdict = vetLibrary(readFacts(candidate, resolved), currentUID);
            if (verdict != LibraryVerdict::Trusted)
            {
                if (verdict != LibraryVerdict::Missing)
                {
                    result.verdict = verdict;
                    log::line("[FFmpeg] refused {} ({}): another user could change it (verdict {})",
                              candidate,
                              resolved,
                              static_cast<int>(verdict));
                }
                continue;
            }
            loadAttemptCount().fetch_add(1U, std::memory_order_relaxed);
            void* handle = ::dlopen(resolved.c_str(), RTLD_NOW | RTLD_LOCAL);
            if (handle == nullptr)
            {
                const char* error = ::dlerror();
                log::line(
                    "[FFmpeg] dlopen {} failed: {}", resolved, (error != nullptr) ? error : "?");
                continue;
            }
            if (!isImageOf(handle, probeSymbol, resolved))
            {
                log::line("[FFmpeg] refused {}: the loaded image is not the vetted file", resolved);
                ::dlclose(handle);
                result.verdict = LibraryVerdict::Substituted;
                continue;
            }
            result.handle = handle;
            result.verdict = LibraryVerdict::Trusted;
            return result;
        }
        return result;
    }

    uint64_t loadAttempts() noexcept
    {
        return loadAttemptCount().load(std::memory_order_relaxed);
    }

    void recordLoadOutcome(LoadOutcome outcome) noexcept
    {
        lastOutcome().store(outcome, std::memory_order_release);
    }

    LoadOutcome loadOutcome() noexcept
    {
        return lastOutcome().load(std::memory_order_acquire);
    }

} // namespace AdaptiveSound::ffmpeg

// ===========================================================================
// C-ABI (FFmpegBridge.h)
// ===========================================================================

extern "C" void ffmpegSetEnabled(int enabled) AUDIODSP_C_NOEXCEPT
{
    AdaptiveSound::ffmpeg::setEnabled(enabled != 0);
}

extern "C" int ffmpegIsEnabled(void) AUDIODSP_C_NOEXCEPT
{
    return AdaptiveSound::ffmpeg::isEnabled() ? 1 : 0;
}

extern "C" uint8_t ffmpegState(void) AUDIODSP_C_NOEXCEPT
{
    // The codes FFmpegBridge.h documents, in its order.
    constexpr uint8_t kOff = 0U;
    constexpr uint8_t kStandby = 1U;
    constexpr uint8_t kLoaded = 2U;
    constexpr uint8_t kNotFound = 3U;
    constexpr uint8_t kRefused = 4U;
    constexpr uint8_t kWrongVersion = 5U;
    using AdaptiveSound::ffmpeg::LoadOutcome;
    if (!AdaptiveSound::ffmpeg::isEnabled())
    {
        return kOff;
    }
    switch (AdaptiveSound::ffmpeg::loadOutcome())
    {
        case LoadOutcome::NotTried:
            return kStandby;
        case LoadOutcome::Loaded:
            return kLoaded;
        case LoadOutcome::NotFound:
            return kNotFound;
        case LoadOutcome::Refused:
            return kRefused;
        case LoadOutcome::WrongVersion:
            return kWrongVersion;
    }
    return kNotFound; // unreachable for a valid enumerator; keeps the function total
}
