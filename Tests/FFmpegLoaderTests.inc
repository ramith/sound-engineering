// FFmpegLoaderTests.inc
//
// FFmpeg as an opt-in, off by default, with a hardened load (R1.1-A, founder decision FD-3,
// council C-99, KI-SEC-01). #included into Tests/DSPKernelNullTest.cpp after TestSupport.h and
// FileDecodeTests.inc (BackendGuard, writeWav16, makeStereoRamp).
//
// Tests: FFmpeg_OffByDefault_LoadsNothing, FFmpeg_VetLibrary_Rules,
//        FFmpeg_LibraryPaths_FixedAndAbsolute, FFmpeg_ReadFacts_RealFiles,
//        FFmpeg_OpenLibrary_RefusesWhatOthersCanChange, FFmpeg_ProbeNamesWhyAFileWontOpen.
//
// FFmpeg's switch is process-wide, so every test here runs serially and leaves it as it found it.

#if __has_include(<libavutil/version.h>)
#include <libavutil/version.h> // the libavutil major this build was made for (test only)
#endif

namespace
{
    namespace ff = AdaptiveSound::ffmpeg;

    constexpr uint32_t kRootUID = 0U;
    constexpr uint32_t kMeUID = 501U;
    constexpr uint32_t kOtherUID = 502U;
    constexpr uint32_t kRegular0644 = S_IFREG | 0644U;
    constexpr uint32_t kRegular0444 = S_IFREG | 0444U;
    constexpr uint32_t kDir0755 = S_IFDIR | 0755U;

    // A trusted library: a regular file the user owns, read-only to others, in their own folder.
    auto trustedFacts() -> ff::LibraryFileFacts
    {
        ff::LibraryFileFacts facts;
        facts.exists = true;
        facts.isRegularFile = true;
        facts.ownerUID = kMeUID;
        facts.mode = kRegular0644;
        facts.directoryOwnerUID = kMeUID;
        facts.directoryMode = kDir0755;
        return facts;
    }

    // Turns FFmpeg on for a scope and restores the switch after.
    struct FFmpegSwitch
    {
        explicit FFmpegSwitch(bool enabled) : previous(ff::isEnabled())
        {
            ff::setEnabled(enabled);
        }
        ~FFmpegSwitch()
        {
            ff::setEnabled(previous);
        }
        FFmpegSwitch(const FFmpegSwitch&) = delete;
        FFmpegSwitch(FFmpegSwitch&&) = delete;
        auto operator=(const FFmpegSwitch&) -> FFmpegSwitch& = delete;
        auto operator=(FFmpegSwitch&&) -> FFmpegSwitch& = delete;
        bool previous;
    };

    // The checked-in FLAC fixture (Vorbis comments + a PICTURE): what FFmpeg's demuxer used to read
    // first in every scan.
    constexpr const char* kFlacFixture =
        ADAPTIVESOUND_TEST_DATA_DIR "/../Tests/Fixtures/artwork-audio/fixture.flac";
} // namespace

// Off is the default, and off loads nothing: no decode backend, no metadata read, no dlopen — even
// when a backend is forced (ADAPTIVESOUND_DECODER=ffmpeg) and even if FFmpeg was loaded earlier in
// the process. Red on d2b689a: FFmpeg opened the forced decode and the FLAC's tags.
static auto testFFmpegOffByDefaultLoadsNothing() -> void
{
    constexpr const char* kName = "FFmpeg_OffByDefault_LoadsNothing";
    constexpr const char* kPath = ADAPTIVESOUND_TEST_DATA_DIR "/ffmpeg-off.wav";
    if (ff::isEnabled() || ffmpegIsEnabled() != 0)
    {
        logFail(kName, "FFmpeg is on before anything turned it on");
        return;
    }
    if (ffmpegState() != 0U) // 0: off (FFmpegBridge.h)
    {
        logFail(kName, "the state is not Off while the switch is off");
        return;
    }
    if (!writeWav16(kPath, makeStereoRamp(64U), 2U, 48000.0))
    {
        logFail(kName, "could not write the WAV fixture");
        return;
    }
    const uint64_t attemptsBefore = ff::loadAttempts();
    bool forcedOpened = false;
    {
        BackendGuard forced(Backend::FFmpeg, /*enableFFmpeg=*/false);
        FileDecodeSource source;
        forcedOpened = source.open(kPath);
        source.close();
    }
    void* metadata = ffmpegOpenMetadata(kFlacFixture);
    const bool metadataRead = metadata != nullptr;
    ffmpegCloseMetadata(metadata);
    std::remove(kPath);

    if (forcedOpened)
    {
        logFail(kName, "a forced FFmpeg decode opened while FFmpeg is off");
        return;
    }
    if (metadataRead)
    {
        logFail(kName, "FFmpeg read the FLAC's tags while FFmpeg is off");
        return;
    }
    if (ff::loadAttempts() != attemptsBefore)
    {
        logFail(kName,
                std::format("{} dlopen call(s) while FFmpeg is off",
                            ff::loadAttempts() - attemptsBefore));
        return;
    }
    logPass(kName);
}

// The vetting rule, case by case: what the file system says about a library and its folder, and
// whether the app may load it.
static auto testFFmpegVetLibraryRules() -> void
{
    constexpr const char* kName = "FFmpeg_VetLibrary_Rules";
    struct Case
    {
        const char* what;
        ff::LibraryFileFacts facts;
        ff::LibraryVerdict expected;
    };
    std::vector<Case> cases;
    cases.push_back({"the user's own read-only file", trustedFacts(), ff::LibraryVerdict::Trusted});
    {
        ff::LibraryFileFacts facts = trustedFacts();
        facts.ownerUID = kRootUID;
        facts.mode = kRegular0444;
        facts.directoryOwnerUID = kRootUID;
        cases.push_back({"root's file in root's folder", facts, ff::LibraryVerdict::Trusted});
    }
    const ff::LibraryFileFacts nothing;
    cases.push_back({"nothing there", nothing, ff::LibraryVerdict::Missing});
    {
        ff::LibraryFileFacts facts = trustedFacts();
        facts.isRegularFile = false;
        facts.mode = kDir0755;
        cases.push_back({"a directory", facts, ff::LibraryVerdict::NotARegularFile});
    }
    {
        ff::LibraryFileFacts facts = trustedFacts();
        facts.ownerUID = kOtherUID;
        cases.push_back({"another user's file", facts, ff::LibraryVerdict::UntrustedOwner});
    }
    {
        ff::LibraryFileFacts facts = trustedFacts();
        facts.mode = S_IFREG | 0666U;
        cases.push_back({"a world-writable file", facts, ff::LibraryVerdict::WritableByOthers});
    }
    {
        ff::LibraryFileFacts facts = trustedFacts();
        facts.mode = S_IFREG | 0664U;
        cases.push_back({"a group-writable file", facts, ff::LibraryVerdict::WritableByOthers});
    }
    {
        ff::LibraryFileFacts facts = trustedFacts();
        facts.directoryMode = S_IFDIR | 0775U;
        cases.push_back(
            {"a group-writable folder", facts, ff::LibraryVerdict::DirectoryNotPrivate});
    }
    {
        ff::LibraryFileFacts facts = trustedFacts();
        facts.directoryMode = S_IFDIR | S_ISVTX | 0777U;
        cases.push_back(
            {"a sticky world-writable folder", facts, ff::LibraryVerdict::DirectoryNotPrivate});
    }
    {
        ff::LibraryFileFacts facts = trustedFacts();
        facts.directoryOwnerUID = kOtherUID;
        cases.push_back({"another user's folder", facts, ff::LibraryVerdict::DirectoryNotPrivate});
    }
    for (const Case& testCase : cases)
    {
        const ff::LibraryVerdict verdict = ff::vetLibrary(testCase.facts, kMeUID);
        if (verdict != testCase.expected)
        {
            logFail(kName,
                    std::format("{}: verdict {}, expected {}",
                                testCase.what,
                                static_cast<int>(verdict),
                                static_cast<int>(testCase.expected)));
            return;
        }
    }
    logPass(kName);
}

// FFmpeg is looked for by its exact versioned name in two fixed absolute folders, and nowhere else:
// no bare leaf name (a DYLD / current-directory search), no @loader_path.
static auto testFFmpegLibraryPathsFixedAndAbsolute() -> void
{
    constexpr const char* kName = "FFmpeg_LibraryPaths_FixedAndAbsolute";
    const std::span<const std::string_view> directories = ff::libraryDirectories();
    const std::vector<std::string_view> expected = {"/opt/homebrew/lib", "/usr/local/lib"};
    if (!std::ranges::equal(directories, expected))
    {
        logFail(kName,
                "the folders FFmpeg loads from are not exactly /opt/homebrew/lib, /usr/local/lib");
        return;
    }
    for (const std::string_view directory : directories)
    {
        const std::string path = ff::libraryPath(directory, "libavformat", 61);
        if (path != std::string(directory) + "/libavformat.61.dylib" || !path.starts_with('/') ||
            path.contains('@'))
        {
            logFail(kName, "not a fixed absolute path: " + path);
            return;
        }
    }
    logPass(kName);
}

// The facts come from the file the path resolves to (symlinks followed) and its folder.
static auto testFFmpegReadFactsRealFiles() -> void
{
    constexpr const char* kName = "FFmpeg_ReadFacts_RealFiles";
    const std::string folder = ADAPTIVESOUND_TEST_DATA_DIR "/ffmpeg-vet";
    const std::string file = folder + "/libfake.1.dylib";
    const std::string link = folder + "/liblink.1.dylib";
    std::remove(link.c_str());
    std::remove(file.c_str());
    ::rmdir(folder.c_str());
    if (::mkdir(folder.c_str(), 0755) != 0 || ::chmod(folder.c_str(), 0755) != 0)
    {
        logFail(kName, "could not make the folder");
        return;
    }
    std::FILE* out = std::fopen(file.c_str(), "wb");
    if (out == nullptr)
    {
        logFail(kName, "could not write the file");
        return;
    }
    std::fputs("not a library", out);
    std::fclose(out);
    const uint32_t me = static_cast<uint32_t>(::getuid());
    std::string failure;
    auto verdictFor = [&](const std::string& path, std::string& resolved) -> ff::LibraryVerdict
    { return ff::vetLibrary(ff::readFacts(path, resolved), me); };
    std::string resolved;

    ::chmod(file.c_str(), 0644);
    if (verdictFor(file, resolved) != ff::LibraryVerdict::Trusted)
    {
        failure = "the user's own 0644 file in a 0755 folder is not trusted";
    }
    ::chmod(file.c_str(), 0666);
    if (failure.empty() && verdictFor(file, resolved) != ff::LibraryVerdict::WritableByOthers)
    {
        failure = "a 0666 file is not refused as writable by others";
    }
    ::chmod(file.c_str(), 0664);
    if (failure.empty() && verdictFor(file, resolved) != ff::LibraryVerdict::WritableByOthers)
    {
        failure = "a 0664 file is not refused as writable by others";
    }
    ::chmod(file.c_str(), 0644);
    if (failure.empty() && ::symlink("libfake.1.dylib", link.c_str()) != 0)
    {
        failure = "could not make the symlink";
    }
    if (failure.empty() && (verdictFor(link, resolved) != ff::LibraryVerdict::Trusted ||
                            !resolved.ends_with("/ffmpeg-vet/libfake.1.dylib")))
    {
        failure = "a symlink is not judged by the file it resolves to (" + resolved + ")";
    }
    ::chmod(folder.c_str(), 0777);
    if (failure.empty() && verdictFor(file, resolved) != ff::LibraryVerdict::DirectoryNotPrivate)
    {
        failure = "a file in a 0777 folder is not refused";
    }
    ::chmod(folder.c_str(), 0755);
    if (failure.empty() &&
        verdictFor(folder + "/absent.dylib", resolved) != ff::LibraryVerdict::Missing)
    {
        failure = "a missing file is not Missing";
    }
    std::remove(link.c_str());
    std::remove(file.c_str());
    ::rmdir(folder.c_str());
    if (!failure.empty())
    {
        logFail(kName, failure);
        return;
    }
    logPass(kName);
}

// The fixed folders hold whatever Homebrew installed: when FFmpeg is there and on, every library
// it loads is the vetted file at a fixed path (dladdr), and the state reads Loaded. When FFmpeg is
// off, the same open makes no dlopen. Skipped (an [info] line) where FFmpeg is not installed.
static auto testFFmpegOpenLibraryRefusesWhatOthersCanChange() -> void
{
    constexpr const char* kName = "FFmpeg_OpenLibrary_RefusesWhatOthersCanChange";
#if __has_include(<libavutil/version.h>)
    constexpr int kMajor = LIBAVUTIL_VERSION_MAJOR;
    {
        FFmpegSwitch off(false);
        const uint64_t before = ff::loadAttempts();
        const ff::OpenedLibrary opened = ff::openLibrary("libavutil", kMajor, "avutil_version");
        if (opened.handle != nullptr || ff::loadAttempts() != before)
        {
            logFail(kName, "openLibrary called dlopen while FFmpeg is off");
            return;
        }
    }
    FFmpegSwitch on(true);
    const ff::OpenedLibrary opened = ff::openLibrary("libavutil", kMajor, "avutil_version");
    if (opened.handle == nullptr)
    {
        if (opened.verdict == ff::LibraryVerdict::Missing)
        {
            logInfo(
                "  [info] FFmpeg_OpenLibrary: FFmpeg not installed at the fixed paths — skipped\n");
            logPass(kName);
            return;
        }
        logInfo(
            std::format("  [info] FFmpeg_OpenLibrary: the installed libavutil was refused ({})\n",
                        static_cast<int>(opened.verdict)));
        logPass(kName);
        return;
    }
    Dl_info info{};
    void* symbol = dlsym(opened.handle, "avutil_version");
    if (symbol == nullptr || dladdr(symbol, &info) == 0 || info.dli_fname == nullptr)
    {
        logFail(kName, "the loaded libavutil has no avutil_version image");
        return;
    }
    const std::string image = info.dli_fname;
    const bool fromFixedFolder = std::ranges::any_of(
        ff::libraryDirectories(),
        [&](std::string_view directory)
        {
            std::string resolved;
            (void)ff::readFacts(ff::libraryPath(directory, "libavutil", kMajor), resolved);
            return !resolved.empty() && resolved == image;
        });
    if (!fromFixedFolder)
    {
        logFail(kName, "libavutil was loaded from " + image + ", not a vetted fixed path");
        return;
    }
    logPass(kName);
#else
    logInfo("  [info] FFmpeg_OpenLibrary: built without FFmpeg headers — skipped\n");
    logPass(kName);
#endif
}

// Why a file won't open for Pure: Apple can't read it and FFmpeg is off (a "needs FFmpeg" reason
// the UI can name), or no decoder can read it at all. A file Apple reads opens either way.
static auto testFFmpegProbeNamesWhyAFileWontOpen() -> void
{
    constexpr const char* kName = "FFmpeg_ProbeNamesWhyAFileWontOpen";
    constexpr const char* kGarbage = ADAPTIVESOUND_TEST_DATA_DIR "/ffmpeg-probe-garbage.flac";
    constexpr const char* kWav = ADAPTIVESOUND_TEST_DATA_DIR "/ffmpeg-probe.wav";
    std::FILE* out = std::fopen(kGarbage, "wb");
    if (out == nullptr || !writeWav16(kWav, makeStereoRamp(64U), 2U, 44100.0))
    {
        if (out != nullptr)
        {
            std::fclose(out);
        }
        logFail(kName, "could not write the fixtures");
        return;
    }
    std::fputs("fLaC but not really", out);
    std::fclose(out);

    using AdaptiveSound::FileProbe;
    std::string failure;
    {
        FFmpegSwitch off(false);
        const FileProbe garbage = FileDecodeSource::probe(kGarbage);
        const FileProbe wav = FileDecodeSource::probe(kWav);
        if (garbage.outcome != FileProbe::Outcome::NeedsFFmpeg)
        {
            failure = "an unreadable file with FFmpeg off is not 'needs FFmpeg'";
        }
        else if (wav.outcome != FileProbe::Outcome::Opened || wav.format.channels != 2U ||
                 std::fabs(wav.format.sampleRate - 44100.0) > 0.5)
        {
            failure = "a WAV did not probe as opened, stereo, 44.1 kHz";
        }
    }
    if (failure.empty())
    {
        FFmpegSwitch on(true);
        const FileProbe garbage = FileDecodeSource::probe(kGarbage);
        if (garbage.outcome != FileProbe::Outcome::Unreadable)
        {
            failure = "a file no decoder reads is not 'unreadable' with FFmpeg on";
        }
    }
    std::remove(kGarbage);
    std::remove(kWav);
    if (!failure.empty())
    {
        logFail(kName, failure);
        return;
    }
    logPass(kName);
}
