#pragma once

//
// FFmpegLoader.h — whether FFmpeg may be loaded at all, and from where (R1.1-A, founder decision
// FD-3, council C-99).
//
// FFmpeg is an IN-PROCESS C PARSER for untrusted files: its demuxers read whatever a downloaded
// album holds. So it is an OPT-IN, OFF BY DEFAULT ("Use FFmpeg for other formats" in Settings),
// and while it is off nothing here ever calls dlopen — the decode fallback and the metadata scan
// use Apple's decoder only. One process-wide switch (setEnabled), set by the app from the
// listener's setting; the decode and metadata paths ask isEnabled() before every use.
//
// While it is on, a library loads only from a FIXED LIST OF ABSOLUTE DIRECTORIES (Homebrew on
// Apple Silicon, then on Intel) by its exact major-versioned name — never by a bare leaf name, a
// relative path, @loader_path or a DYLD search — and only when the file it resolves to (symlinks
// followed) is a regular file owned by root or by the user running the app, writable by no one
// else, in a directory writable by no one else (vetLibrary). It is opened by that resolved path,
// and the image dlopen returns must be that file (dladdr), so DYLD_LIBRARY_PATH or a swap
// between the check and the open can't substitute another. The major-version guard stays with
// the symbols (FileDecodeSource.cpp).
//
// What remains is listed in docs/product/known-issues.md (KI-SEC-01): a parser that runs in the
// app's own process, with the user's rights, on files the user did not make.
//
// CoreAudio-FREE: compiled into the C++ null test, which unit-tests the vetting rule and proves
// that "off" loads nothing (loadAttempts). -fno-exceptions / -fno-rtti clean. Control plane only.
//

#include <cstdint>
#include <span>
#include <string>
#include <string_view>

namespace AdaptiveSound::ffmpeg
{
    // The listener's switch. Off when the process starts. Cheap (an atomic); any thread.
    void setEnabled(bool enabled) noexcept;
    [[nodiscard]] bool isEnabled() noexcept;

    // What the file system reports about a library file — after its symlinks are resolved — and
    // about the directory that holds it.
    struct LibraryFileFacts
    {
        bool exists = false;
        bool isRegularFile = false;
        uint32_t ownerUID = 0;
        uint32_t mode = 0; // st_mode
        uint32_t directoryOwnerUID = 0;
        uint32_t directoryMode = 0; // st_mode of the directory holding the file
    };

    // Whether a library file may be loaded, or why not.
    enum class LibraryVerdict : uint8_t
    {
        Trusted,             // a regular file, owned by root or the user, writable by them alone
        Missing,             // nothing at the path
        NotARegularFile,     // a directory, device, socket …
        UntrustedOwner,      // owned by another user
        WritableByOthers,    // group- or world-writable
        DirectoryNotPrivate, // its directory is another user's, or group- or world-writable
        Substituted,         // dlopen handed back an image other than the vetted file
    };

    // The rule, pure: may a process running as `currentUID` load the file `facts` describe?
    [[nodiscard]] LibraryVerdict vetLibrary(const LibraryFileFacts& facts,
                                            uint32_t currentUID) noexcept;

    // The fixed absolute directories FFmpeg loads from, in order: Homebrew on Apple Silicon, then
    // Homebrew on Intel.
    [[nodiscard]] std::span<const std::string_view> libraryDirectories() noexcept;

    // "<directory>/<base>.<major>.dylib" — the one name a library is looked for by.
    [[nodiscard]] std::string
    libraryPath(std::string_view directory, std::string_view base, int major);

    // The facts for `path`: its symlinks resolved (realpath), then lstat of the file and stat of
    // its directory. `resolved` receives the resolved path ("" when it does not resolve).
    [[nodiscard]] LibraryFileFacts readFacts(const std::string& path,
                                             std::string& resolved) noexcept;

    // One library, opened.
    struct OpenedLibrary
    {
        void* handle = nullptr;                           // nullptr: not opened
        LibraryVerdict verdict = LibraryVerdict::Missing; // the best verdict among the candidates
    };

    // Open `base`.`major` from the fixed directories: the first candidate whose resolved file vets
    // Trusted, dlopened by its resolved path and checked to be that image (dladdr of
    // `probeSymbol`). Nothing is opened, and no dlopen is made, while FFmpeg is off.
    [[nodiscard]] OpenedLibrary
    openLibrary(std::string_view base, int major, const char* probeSymbol) noexcept;

    // How many dlopen calls this process has made for FFmpeg — the observable the null test uses
    // to prove that "off" loads nothing.
    [[nodiscard]] uint64_t loadAttempts() noexcept;

    // How the last load went (FileDecodeSource.cpp records it), for the Settings line.
    enum class LoadOutcome : uint8_t
    {
        NotTried,     // nothing has needed FFmpeg yet
        Loaded,       // every library loaded, trusted, with the majors this build was made for
        NotFound,     // no FFmpeg at the fixed directories (or this build has no FFmpeg support)
        Refused,      // a library was found, but another user could change it (vetLibrary)
        WrongVersion, // found, but not the major versions this build was made for (or incomplete)
    };
    void recordLoadOutcome(LoadOutcome outcome) noexcept;
    [[nodiscard]] LoadOutcome loadOutcome() noexcept;

} // namespace AdaptiveSound::ffmpeg
