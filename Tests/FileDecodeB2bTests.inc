// ============================================================================
// FileDecodeB2bTests.inc
//
// Pure-Mode file decode (Phase B — B2b): expanded harness coverage (QA audit).
//
// This file is #included into Tests/DSPKernelNullTest.cpp AFTER the existing B2b
// block (so it can use writeKnownWav, kWavBits16, FileDecodeSource, logPass/
// logFail, TestConstants, etc.) and immediately BEFORE main(). It defines new
// FileDecode_* test functions only; main() calls them (see the registration block
// in DSPKernelNullTest.cpp).
//
// Coverage added: open-failure paths, close() idempotency, format getters across
// bit depths, 24-bit + float32 + mono + 4-channel bit-exactness, channel-mismatch
// silence, EOF/finished-flag semantics, finished-flag-vs-ring-tail, underrun
// zero-pad, FFmpeg<->Apple equivalence, and ring wraparound.
//
// Backend forcing: ADAPTIVESOUND_DECODER=apple|ffmpeg. Tests that must run on
// "both" backends run the body once forced-Apple and once forced-FFmpeg; the
// FFmpeg leg is skipped gracefully (no failure, an [info] note) when FFmpeg is
// absent (open fails after forcing ffmpeg).
// ============================================================================

namespace
{
    // Named constants — no magic numbers (clang-tidy).
    constexpr uint32_t kB2bBits24 = 24U;
    constexpr uint32_t kB2bBits32 = 32U;
    constexpr uint32_t kB2bChannels1 = 1U;
    constexpr uint32_t kB2bChannels2 = 2U;
    constexpr uint32_t kB2bChannels4 = 4U;
    constexpr double kB2bRate48k = 48000.0;
    constexpr double kB2bRate44k = 44100.0;
    constexpr double kB2bRate96k = 96000.0;
    constexpr double kB2bRateTol = 1.0; // ±1 Hz on the reported sample rate
    constexpr double kB2bI16Scale = 32768.0;
    constexpr double kB2bI24Scale = 8388608.0; // 2^23
    constexpr float kB2bTol16 = 1.0F / 32768.0F;
    constexpr float kB2bTol24 = 1.0F / 8388608.0F;
    constexpr int kB2bMaxPollAttempts = 100;
    constexpr int kB2bPollNapMs = 2;
    constexpr int kB2bFinishedPollAttempts = 60; // ~120 ms at 2 ms naps
    constexpr uint32_t kBytesPerSample24 = 3U;
    constexpr uint32_t kWavHeaderBytes = 44U;
    constexpr uint32_t kPullChunk32 = 32U; // small pull for mismatch tests
    constexpr uint32_t kChannelsTooFew = 1U;
    constexpr uint32_t kChannelsTooMany = 3U;

    // The decode ring holds 2^18 floats (one slot reserved). 131071 stereo frames fit; a file
    // that fully fits the ring exercises the "finished flag set, tail still in the ring" path.
    constexpr uint32_t kRingFitFrames = 16384U;     // well under the 131071-frame stereo capacity
    constexpr uint32_t kWraparoundFrames = 300000U; // ~2.3x the stereo ring → forces wrap
    constexpr uint32_t kWraparoundChunk = 4096U;
    constexpr uint32_t kRingBoundaryFrame = 131072U; // first frame past the stereo ring boundary
    constexpr uint32_t kI16Period = 32768U;          // deterministic ramp period for patterns
    constexpr int kI16Bias = 16384;                  // centres the ramp around 0 within int16 range

    // Forced-backend selection for the "both backends" tests.
    enum class Backend : uint8_t
    {
        Apple,
        FFmpeg
    };

    auto forceBackend(Backend backend) -> void
    {
        setenv("ADAPTIVESOUND_DECODER", (backend == Backend::Apple) ? "apple" : "ffmpeg", 1);
    }

    auto clearBackend() -> void { unsetenv("ADAPTIVESOUND_DECODER"); }

    // BackendGuard: RAII wrapper that forces a backend on construction and clears it on
    // destruction. Copy and move are deleted so an early return cannot leave the env set.
    struct BackendGuard
    {
        explicit BackendGuard(Backend backend) { forceBackend(backend); }
        ~BackendGuard() { clearBackend(); }
        BackendGuard(const BackendGuard&) = delete;
        BackendGuard(BackendGuard&&) = delete;
        auto operator=(const BackendGuard&) -> BackendGuard& = delete;
        auto operator=(BackendGuard&&) -> BackendGuard& = delete;
    };

    // Write `interleaved` int16 samples as a 16-bit PCM WAV at `path` via ExtAudioFile.
    // Wraps the existing writeKnownWav (which takes a non-const ref but does not mutate content).
    auto writeWav16(const char* path,
                    const std::vector<int16_t>& interleaved,
                    uint32_t channels,
                    double rate) -> bool
    {
        std::vector<int16_t> mutableCopy(interleaved);
        return writeKnownWav(path, mutableCopy, channels, rate);
    }

    // Write `interleaved` float samples as a 32-bit float PCM WAV at `path` via ExtAudioFile.
    auto writeWavFloat32(const char* path,
                         const std::vector<float>& interleaved,
                         uint32_t channels,
                         double rate) -> bool
    {
        AudioStreamBasicDescription fmt{};
        fmt.mFormatID = kAudioFormatLinearPCM;
        fmt.mFormatFlags = kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked;
        fmt.mSampleRate = rate;
        fmt.mChannelsPerFrame = channels;
        fmt.mBitsPerChannel = kB2bBits32;
        fmt.mFramesPerPacket = 1U;
        fmt.mBytesPerFrame = static_cast<UInt32>(sizeof(float)) * channels;
        fmt.mBytesPerPacket = fmt.mBytesPerFrame;

        CFURLRef url =
            CFURLCreateFromFileSystemRepresentation(nullptr,
                                                    reinterpret_cast<const UInt8*>(path),
                                                    static_cast<CFIndex>(std::strlen(path)),
                                                    static_cast<Boolean>(false));
        if (url == nullptr)
        {
            return false;
        }
        ExtAudioFileRef out = nullptr;
        OSStatus status = ExtAudioFileCreateWithURL(
            url, kAudioFileWAVEType, &fmt, nullptr, kAudioFileFlags_EraseFile, &out);
        CFRelease(url);
        if (status != noErr || out == nullptr)
        {
            return false;
        }
        status =
            ExtAudioFileSetProperty(out, kExtAudioFileProperty_ClientDataFormat, sizeof(fmt), &fmt);
        if (status == noErr)
        {
            std::vector<float> mutableCopy(interleaved); // ExtAudioFileWrite needs a non-const buffer
            AudioBufferList abl{};
            abl.mNumberBuffers = 1U;
            abl.mBuffers[0].mNumberChannels = channels;
            abl.mBuffers[0].mDataByteSize = static_cast<UInt32>(mutableCopy.size() * sizeof(float));
            abl.mBuffers[0].mData = mutableCopy.data();
            const UInt32 frames = static_cast<UInt32>(mutableCopy.size()) / channels;
            status = ExtAudioFileWrite(out, frames, &abl);
        }
        ExtAudioFileDispose(out);
        return status == noErr;
    }

    // Append one little-endian uint32 word to a byte vector.
    auto appendLeWord32(std::vector<uint8_t>& bytes, uint32_t value) -> void
    {
        bytes.push_back(static_cast<uint8_t>(value & 0xFFU));
        bytes.push_back(static_cast<uint8_t>((value >> 8U) & 0xFFU));
        bytes.push_back(static_cast<uint8_t>((value >> 16U) & 0xFFU));
        bytes.push_back(static_cast<uint8_t>((value >> 24U) & 0xFFU));
    }

    // Append one little-endian uint16 half-word to a byte vector.
    auto appendLeWord16(std::vector<uint8_t>& bytes, uint16_t value) -> void
    {
        bytes.push_back(static_cast<uint8_t>(value & 0xFFU));
        bytes.push_back(static_cast<uint8_t>((value >> 8U) & 0xFFU));
    }

    // Hand-write a canonical 44-byte RIFF/WAV header + packed 24-bit signed little-endian PCM.
    // ExtAudioFile is unreliable for 24-bit fixtures, so this builds the bytes directly with
    // C stdio — also exercising the real-world 24-bit parsing path in the decoder backends.
    // `samples` are signed 24-bit values held in int32 (range −2^23 .. 2^23−1).
    auto writeWav24(const char* path,
                    const std::vector<int32_t>& samples,
                    uint32_t channels,
                    double rate) -> bool
    {
        const auto numSamples = static_cast<uint32_t>(samples.size());
        const uint32_t dataBytes = numSamples * kBytesPerSample24;
        const uint32_t byteRate = static_cast<uint32_t>(rate) * channels * kBytesPerSample24;
        const auto blockAlign = static_cast<uint16_t>(channels * kBytesPerSample24);

        std::vector<uint8_t> bytes;
        bytes.reserve(kWavHeaderBytes + dataBytes);

        // RIFF chunk descriptor.
        bytes.push_back(static_cast<uint8_t>('R'));
        bytes.push_back(static_cast<uint8_t>('I'));
        bytes.push_back(static_cast<uint8_t>('F'));
        bytes.push_back(static_cast<uint8_t>('F'));
        constexpr uint32_t kRiffMinusHeader = 8U;
        appendLeWord32(bytes, (kWavHeaderBytes - kRiffMinusHeader) + dataBytes); // ChunkSize
        bytes.push_back(static_cast<uint8_t>('W'));
        bytes.push_back(static_cast<uint8_t>('A'));
        bytes.push_back(static_cast<uint8_t>('V'));
        bytes.push_back(static_cast<uint8_t>('E'));

        // fmt subchunk.
        bytes.push_back(static_cast<uint8_t>('f'));
        bytes.push_back(static_cast<uint8_t>('m'));
        bytes.push_back(static_cast<uint8_t>('t'));
        bytes.push_back(static_cast<uint8_t>(' '));
        constexpr uint32_t kFmtSubchunkSize = 16U;
        constexpr uint16_t kAudioFormatPcm = 1U;
        appendLeWord32(bytes, kFmtSubchunkSize);
        appendLeWord16(bytes, kAudioFormatPcm);
        appendLeWord16(bytes, static_cast<uint16_t>(channels));
        appendLeWord32(bytes, static_cast<uint32_t>(rate));
        appendLeWord32(bytes, byteRate);
        appendLeWord16(bytes, blockAlign);
        appendLeWord16(bytes, static_cast<uint16_t>(kB2bBits24));

        // data subchunk.
        bytes.push_back(static_cast<uint8_t>('d'));
        bytes.push_back(static_cast<uint8_t>('a'));
        bytes.push_back(static_cast<uint8_t>('t'));
        bytes.push_back(static_cast<uint8_t>('a'));
        appendLeWord32(bytes, dataBytes);
        for (const int32_t sample : samples)
        {
            const auto packed = static_cast<uint32_t>(sample);
            bytes.push_back(static_cast<uint8_t>(packed & 0xFFU));
            bytes.push_back(static_cast<uint8_t>((packed >> 8U) & 0xFFU));
            bytes.push_back(static_cast<uint8_t>((packed >> 16U) & 0xFFU));
        }

        // NOLINTNEXTLINE(cppcoreguidelines-owning-memory) -- balanced fopen/fclose, no leak.
        std::FILE* handle = std::fopen(path, "wb");
        if (handle == nullptr)
        {
            return false;
        }
        const std::size_t written = std::fwrite(bytes.data(), 1U, bytes.size(), handle);
        const int closed = std::fclose(handle);
        return (written == bytes.size()) && (closed == 0);
    }

    // Drain `frameCount` frames into `out` (sized frameCount*channels), polling the background
    // decoder. Returns the total frames produced. Shared collect helper (keeps each test's
    // cognitive complexity low; mirrors the existing decodeBitExactCase poll-drain loop).
    auto drainFrames(FileDecodeSource& src,
                     std::vector<float>& out,
                     uint32_t frameCount,
                     uint32_t channels) -> uint32_t
    {
        uint32_t total = 0U;
        for (int attempt = 0; attempt < kB2bMaxPollAttempts && total < frameCount; ++attempt)
        {
            const uint32_t produced =
                src.pullFloat(out.data() + (static_cast<std::size_t>(total) * channels),
                              frameCount - total,
                              channels);
            total += produced;
            if (produced == 0U)
            {
                std::this_thread::sleep_for(std::chrono::milliseconds(kB2bPollNapMs));
            }
        }
        return total;
    }

    // Poll decoderFinished() up to ~120 ms. Returns true once the decode thread sets the flag.
    auto pollFinished(FileDecodeSource& src) -> bool
    {
        for (int attempt = 0; attempt < kB2bFinishedPollAttempts; ++attempt)
        {
            if (src.decoderFinished())
            {
                return true;
            }
            std::this_thread::sleep_for(std::chrono::milliseconds(kB2bPollNapMs));
        }
        return src.decoderFinished();
    }

    // True if forcing FFmpeg fails to open this fixture (FFmpeg absent / not loadable). Used by
    // the "both backends" tests to skip the FFmpeg leg gracefully.
    auto ffmpegLegUnavailable(const char* path) -> bool
    {
        BackendGuard guard(Backend::FFmpeg);
        FileDecodeSource probe;
        const bool opened = probe.open(path);
        probe.close();
        return !opened;
    }

    // Build a deterministic interleaved stereo int16 ramp: value = (frame % period) - bias on both
    // channels.
    auto makeStereoRamp(uint32_t frameCount) -> std::vector<int16_t>
    {
        std::vector<int16_t> interleaved(static_cast<std::size_t>(frameCount) * kB2bChannels2);
        for (uint32_t frame = 0U; frame < frameCount; ++frame)
        {
            const auto value =
                static_cast<int16_t>(static_cast<int>(frame % kI16Period) - kI16Bias);
            interleaved[static_cast<std::size_t>(frame) * kB2bChannels2] = value;
            interleaved[(static_cast<std::size_t>(frame) * kB2bChannels2) + 1U] = value;
        }
        return interleaved;
    }

    // Unique fixture paths per test (avoids cross-test collisions; removed after each use).
    constexpr const char* kPathFmtGetters = "/tmp/adaptivesound_b2b_fmtgetters.wav";
    constexpr const char* kPathBitExact24 = "/tmp/adaptivesound_b2b_bitexact24.wav";
    constexpr const char* kPathBitExactF32 = "/tmp/adaptivesound_b2b_bitexactf32.wav";
    constexpr const char* kPathNativeRate = "/tmp/adaptivesound_b2b_nativerate.wav";
    constexpr const char* kPathMono = "/tmp/adaptivesound_b2b_mono.wav";
    constexpr const char* kPath4ch = "/tmp/adaptivesound_b2b_4ch.wav";
    // Each test that previously shared kPathMismatch now has its own unique path
    // to prevent cross-test collisions if tests are ever reordered.
    constexpr const char* kPathOpenFailure  = "/tmp/adaptivesound_b2b_openfailure.wav";
    constexpr const char* kPathCloseIdemp   = "/tmp/adaptivesound_b2b_closeidemp.wav";
    constexpr const char* kPathChanMismatch = "/tmp/adaptivesound_b2b_chanmismatch.wav";
    constexpr const char* kPathEof = "/tmp/adaptivesound_b2b_eof.wav";
    constexpr const char* kPathRingTail = "/tmp/adaptivesound_b2b_ringtail.wav";
    constexpr const char* kPathUnderrun = "/tmp/adaptivesound_b2b_underrun.wav";
    constexpr const char* kPathEquiv = "/tmp/adaptivesound_b2b_equiv.wav";
    constexpr const char* kPathWrap = "/tmp/adaptivesound_b2b_wrap.wav";
    constexpr const char* kPathGarbage = "/tmp/adaptivesound_b2b_garbage.bin";
} // namespace

// Spec 1: open-failure paths. nullptr, missing file, garbage bytes, and a double-open all
// return false; close() after each must not crash.
static auto testFileDecodeOpenFailurePaths() -> void
{
    static const char* const kName = "FileDecode_OpenFailurePaths";

    // (a) nullptr path.
    {
        FileDecodeSource src;
        if (src.open(nullptr))
        {
            logFail(kName, "open(nullptr) returned true");
            return;
        }
        src.close();
    }

    // (b) missing file.
    {
        FileDecodeSource src;
        if (src.open("/tmp/adaptivesound_b2b_does_not_exist.wav"))
        {
            logFail(kName, "open(missing file) returned true");
            return;
        }
        src.close();
    }

    // (c) random non-audio bytes.
    {
        constexpr uint32_t kGarbageBytes = 256U;
        // NOLINTBEGIN(cert-msc32-c,cert-msc51-cpp)
        std::mt19937 gen(0x6A726B73U);
        // NOLINTEND(cert-msc32-c,cert-msc51-cpp)
        std::uniform_int_distribution<int> dist(0, 0xFF);
        std::vector<uint8_t> garbage;
        garbage.reserve(kGarbageBytes);
        for (uint32_t idx = 0U; idx < kGarbageBytes; ++idx)
        {
            garbage.push_back(static_cast<uint8_t>(dist(gen)));
        }
        // NOLINTNEXTLINE(cppcoreguidelines-owning-memory)
        std::FILE* handle = std::fopen(kPathGarbage, "wb");
        if (handle == nullptr)
        {
            logFail(kName, "could not write the garbage fixture");
            return;
        }
        std::fwrite(garbage.data(), 1U, garbage.size(), handle);
        std::fclose(handle);

        FileDecodeSource src;
        const bool opened = src.open(kPathGarbage);
        src.close();
        std::remove(kPathGarbage);
        if (opened)
        {
            logFail(kName, "open(garbage bytes) returned true");
            return;
        }
    }

    // (d) double-open: a valid WAV opens; a second open() without close() must fail.
    {
        const std::vector<int16_t> known = {0, 0, 4096, -4096};
        if (!writeWav16(kPathOpenFailure, known, kB2bChannels2, kB2bRate48k))
        {
            logFail(kName, "could not write the double-open fixture");
            return;
        }
        FileDecodeSource src;
        if (!src.open(kPathOpenFailure))
        {
            src.close();
            std::remove(kPathOpenFailure);
            logFail(kName, "first open() of a valid WAV failed");
            return;
        }
        const bool secondOpen = src.open(kPathOpenFailure);
        src.close();
        std::remove(kPathOpenFailure);
        if (secondOpen)
        {
            logFail(kName, "second open() without close() returned true");
            return;
        }
    }

    logPass(kName);
}

// Spec 2: close() idempotency — never-opened, open-then-double-close, default-construct + dtor.
static auto testFileDecodeCloseIdempotent() -> void
{
    static const char* const kName = "FileDecode_CloseIdempotent";

    // (a) close() on a never-opened source.
    {
        FileDecodeSource src;
        src.close();
    }

    // (b) open valid, then close() twice.
    {
        const std::vector<int16_t> known = {0, 0, 8192, -8192};
        if (!writeWav16(kPathCloseIdemp, known, kB2bChannels2, kB2bRate48k))
        {
            logFail(kName, "could not write the idempotency fixture");
            return;
        }
        FileDecodeSource src;
        if (!src.open(kPathCloseIdemp))
        {
            src.close();
            std::remove(kPathCloseIdemp);
            logFail(kName, "open() failed");
            return;
        }
        src.close();
        src.close();
        std::remove(kPathCloseIdemp);
    }

    // (c) default-construct + let the dtor run (scope exit).
    {
        FileDecodeSource src;
        static_cast<void>(src.channels());
    }

    logPass(kName);
}

// Format-getter sub-check on one open fixture. Returns "" on success, an error string otherwise.
static auto checkGetters(const char* path, uint32_t expectedBits, bool expectedFloat)
    -> std::string
{
    FileDecodeSource src;
    if (!src.open(path))
    {
        src.close();
        return "open() failed";
    }
    const bool bitsOk = (src.sourceBitsPerChannel() == expectedBits);
    const bool floatOk = (src.sourceIsFloat() == expectedFloat);
    const bool rateOk = (std::abs(src.sampleRate() - kB2bRate48k) <= kB2bRateTol);
    const bool chanOk = (src.channels() == kB2bChannels2);
    src.close();
    if (!bitsOk || !floatOk || !rateOk || !chanOk)
    {
        std::ostringstream oss;
        oss << "getters mismatch (bits ok=" << bitsOk << " float ok=" << floatOk
            << " rate ok=" << rateOk << " chan ok=" << chanOk << ")";
        return oss.str();
    }
    return {};
}

// Spec 3: format getters across 16/24/32-float (stereo 48k). After open (no pull): assert the
// reported bit depth, float flag, sample rate, and channel count.
static auto testFileDecodeFormatGetters() -> void
{
    static const char* const kName = "FileDecode_FormatGetters";

    const std::vector<int16_t> samples16 = {0, 0, 4096, -4096, 8192, -8192};
    const std::vector<int32_t> samples24 = {0, 0, 1048576, -1048576, 2097152, -2097152};
    const std::vector<float> samplesF32 = {0.0F, 0.0F, 0.25F, -0.25F, 0.5F, -0.5F};

    if (!writeWav16(kPathFmtGetters, samples16, kB2bChannels2, kB2bRate48k))
    {
        logFail(kName, "could not write 16-bit fixture");
        return;
    }
    const std::string err16 = checkGetters(kPathFmtGetters, kWavBits16, /*expectedFloat=*/false);
    std::remove(kPathFmtGetters);
    if (!err16.empty())
    {
        logFail(kName, "16-bit: " + err16);
        return;
    }

    if (!writeWav24(kPathFmtGetters, samples24, kB2bChannels2, kB2bRate48k))
    {
        logFail(kName, "could not write 24-bit fixture");
        return;
    }
    const std::string err24 = checkGetters(kPathFmtGetters, kB2bBits24, /*expectedFloat=*/false);
    std::remove(kPathFmtGetters);
    if (!err24.empty())
    {
        logFail(kName, "24-bit: " + err24);
        return;
    }

    if (!writeWavFloat32(kPathFmtGetters, samplesF32, kB2bChannels2, kB2bRate48k))
    {
        logFail(kName, "could not write 32-bit-float fixture");
        return;
    }
    const std::string errF32 = checkGetters(kPathFmtGetters, kB2bBits32, /*expectedFloat=*/true);
    std::remove(kPathFmtGetters);
    if (!errF32.empty())
    {
        logFail(kName, "32-bit-float: " + errF32);
        return;
    }

    logPass(kName);
}

// Body for the 24-bit bit-exact case on one forced backend. Returns "" on success, a non-empty
// error string on a real failure.
static auto bitExact24Body(const std::vector<int32_t>& samples) -> std::string
{
    FileDecodeSource src;
    if (!src.open(kPathBitExact24))
    {
        src.close();
        return "open() of 24-bit fixture failed";
    }
    if (src.sourceBitsPerChannel() != kB2bBits24 || src.sourceIsFloat() ||
        src.channels() != kB2bChannels2 || std::abs(src.sampleRate() - kB2bRate48k) > kB2bRateTol)
    {
        src.close();
        return "24-bit getters mismatch before decode";
    }

    const auto frameCount = static_cast<uint32_t>(samples.size()) / kB2bChannels2;
    std::vector<float> got(static_cast<std::size_t>(frameCount) * kB2bChannels2, 0.0F);
    const uint32_t total = drainFrames(src, got, frameCount, kB2bChannels2);
    src.close();

    if (total != frameCount)
    {
        std::ostringstream oss;
        oss << "decoded " << total << " of " << frameCount << " frames";
        return oss.str();
    }
    for (std::size_t idx = 0U; idx < samples.size(); ++idx)
    {
        const float expected = static_cast<float>(samples[idx]) / static_cast<float>(kB2bI24Scale);
        if (std::abs(got[idx] - expected) > kB2bTol24)
        {
            std::ostringstream oss;
            oss << "sample " << idx << ": expected " << expected << ", got " << got[idx];
            return oss.str();
        }
    }
    return {};
}

// Spec 4: 24-bit bit-exact (both backends). Known mid-range 24-bit samples; per-sample within
// 1/2^23.
static auto testFileDecodeBitExact24bit() -> void
{
    static const char* const kName = "FileDecode_BitExact_24bit";

    // Mid-range 24-bit signed values (avoid full scale for normalization robustness).
    const std::vector<int32_t> samples = {0,
                                          0,
                                          4194304,  // +0.5
                                          -4194304, // -0.5
                                          2097152,  // +0.25
                                          -2097152,
                                          1234567,
                                          -1234567,
                                          100,
                                          -100,
                                          8388607, // near +full scale
                                          -8388608};

    if (!writeWav24(kPathBitExact24, samples, kB2bChannels2, kB2bRate48k))
    {
        logFail(kName, "could not write the 24-bit fixture");
        return;
    }

    {
        BackendGuard appleGuard(Backend::Apple);
        const std::string appleErr = bitExact24Body(samples);
        if (!appleErr.empty())
        {
            std::remove(kPathBitExact24);
            logFail(kName, "Apple: " + appleErr);
            return;
        }
    }

    const bool skipFfmpeg = ffmpegLegUnavailable(kPathBitExact24);
    if (!skipFfmpeg)
    {
        BackendGuard ffmpegGuard(Backend::FFmpeg);
        const std::string ffmpegErr = bitExact24Body(samples);
        if (!ffmpegErr.empty())
        {
            std::remove(kPathBitExact24);
            logFail(kName, "FFmpeg: " + ffmpegErr);
            return;
        }
    }
    std::remove(kPathBitExact24);

    if (skipFfmpeg)
    {
        logInfo("  [info] FileDecode_BitExact_24bit: FFmpeg not present (Apple leg only)\n");
    }
    logPass(kName);
}

// Body for the 32-bit-float bit-exact case on one forced backend. Float client format means no
// conversion, so the decoded floats should be byte-identical to the source (std::memcmp).
static auto bitExactFloat32Body(const std::vector<float>& samples) -> std::string
{
    FileDecodeSource src;
    if (!src.open(kPathBitExactF32))
    {
        src.close();
        return "open() of 32-bit-float fixture failed";
    }
    if (!src.sourceIsFloat() || src.channels() != kB2bChannels2)
    {
        src.close();
        return "expected sourceIsFloat() == true and 2 channels";
    }
    const auto frameCount = static_cast<uint32_t>(samples.size()) / kB2bChannels2;
    std::vector<float> got(static_cast<std::size_t>(frameCount) * kB2bChannels2, 0.0F);
    const uint32_t total = drainFrames(src, got, frameCount, kB2bChannels2);
    src.close();
    if (total != frameCount)
    {
        std::ostringstream oss;
        oss << "decoded " << total << " of " << frameCount << " frames";
        return oss.str();
    }
    if (std::memcmp(got.data(), samples.data(), samples.size() * sizeof(float)) != 0)
    {
        return "decoded floats are not bit-identical to the source";
    }
    return {};
}

// Spec 5: 32-bit float bit-exact (both backends). Exact memcmp (no conversion at the float
// client boundary).
static auto testFileDecodeBitExactFloat32() -> void
{
    static const char* const kName = "FileDecode_BitExact_Float32";

    const std::vector<float> samples = {
        0.0F, 0.0F, 0.5F, -0.5F, 0.25F, -0.25F, 0.123456F, -0.123456F, 0.999F, -0.999F};

    if (!writeWavFloat32(kPathBitExactF32, samples, kB2bChannels2, kB2bRate48k))
    {
        logFail(kName, "could not write the 32-bit-float fixture");
        return;
    }

    {
        BackendGuard appleGuard(Backend::Apple);
        const std::string appleErr = bitExactFloat32Body(samples);
        if (!appleErr.empty())
        {
            std::remove(kPathBitExactF32);
            logFail(kName, "Apple: " + appleErr);
            return;
        }
    }

    const bool skipFfmpeg = ffmpegLegUnavailable(kPathBitExactF32);
    if (!skipFfmpeg)
    {
        BackendGuard ffmpegGuard(Backend::FFmpeg);
        const std::string ffmpegErr = bitExactFloat32Body(samples);
        if (!ffmpegErr.empty())
        {
            std::remove(kPathBitExactF32);
            logFail(kName, "FFmpeg: " + ffmpegErr);
            return;
        }
    }
    std::remove(kPathBitExactF32);

    if (skipFfmpeg)
    {
        logInfo("  [info] FileDecode_BitExact_Float32: FFmpeg not present (Apple leg only)\n");
    }
    logPass(kName);
}

// Body for the native-rate case on one forced backend. Asserts the reported rate and an exact
// frame count for a 64-frame fixture (client rate == file rate, so no sample-rate conversion).
static auto nativeRateBody(double rate, uint32_t frameCount) -> std::string
{
    FileDecodeSource src;
    if (!src.open(kPathNativeRate))
    {
        src.close();
        return "open() failed";
    }
    if (std::abs(src.sampleRate() - rate) > kB2bRateTol)
    {
        std::ostringstream oss;
        oss << "sampleRate() " << src.sampleRate() << " != " << rate;
        src.close();
        return oss.str();
    }
    std::vector<float> got(static_cast<std::size_t>(frameCount) * kB2bChannels2, 0.0F);
    const uint32_t total = drainFrames(src, got, frameCount, kB2bChannels2);
    src.close();
    if (total != frameCount)
    {
        std::ostringstream oss;
        oss << "decoded " << total << " of " << frameCount << " frames (no-SRC expected)";
        return oss.str();
    }
    return {};
}

// Spec 6: native rates / no-SRC (both backends). For 44100 and 96000: a 64-frame 16-bit stereo
// fixture reports the file rate (±1 Hz) and decodes exactly 64 frames.
static auto testFileDecodeNativeRates() -> void
{
    static const char* const kName = "FileDecode_NativeRates";
    constexpr uint32_t kFrames64 = 64U;

    const std::array<double, 2> rates = {kB2bRate44k, kB2bRate96k};
    for (const double rate : rates)
    {
        constexpr int kRampStep = 256;
        constexpr int kRampBias = 8192;
        std::vector<int16_t> interleaved(static_cast<std::size_t>(kFrames64) * kB2bChannels2);
        for (uint32_t frame = 0U; frame < kFrames64; ++frame)
        {
            const auto value =
                static_cast<int16_t>((static_cast<int>(frame) * kRampStep) - kRampBias);
            interleaved[static_cast<std::size_t>(frame) * kB2bChannels2] = value;
            interleaved[(static_cast<std::size_t>(frame) * kB2bChannels2) + 1U] =
                static_cast<int16_t>(-value);
        }
        if (!writeWav16(kPathNativeRate, interleaved, kB2bChannels2, rate))
        {
            logFail(kName, "could not write the native-rate fixture");
            return;
        }

        {
            BackendGuard appleGuard(Backend::Apple);
            const std::string appleErr = nativeRateBody(rate, kFrames64);
            if (!appleErr.empty())
            {
                std::remove(kPathNativeRate);
                logFail(kName, "Apple: " + appleErr);
                return;
            }
        }

        const bool skipFfmpeg = ffmpegLegUnavailable(kPathNativeRate);
        if (!skipFfmpeg)
        {
            BackendGuard ffmpegGuard(Backend::FFmpeg);
            const std::string ffmpegErr = nativeRateBody(rate, kFrames64);
            if (!ffmpegErr.empty())
            {
                std::remove(kPathNativeRate);
                logFail(kName, "FFmpeg: " + ffmpegErr);
                return;
            }
        }
        std::remove(kPathNativeRate);
    }
    logPass(kName);
}

// Body for the mono bit-exact case on one forced backend.
static auto monoBody(const std::vector<int16_t>& samples) -> std::string
{
    FileDecodeSource src;
    if (!src.open(kPathMono))
    {
        src.close();
        return "open() failed";
    }
    if (src.channels() != kB2bChannels1)
    {
        std::ostringstream oss;
        oss << "channels() " << src.channels() << " != 1";
        src.close();
        return oss.str();
    }
    const auto frameCount = static_cast<uint32_t>(samples.size());
    std::vector<float> got(frameCount, 0.0F);
    const uint32_t total = drainFrames(src, got, frameCount, kB2bChannels1);
    src.close();
    if (total != frameCount)
    {
        std::ostringstream oss;
        oss << "decoded " << total << " of " << frameCount << " frames";
        return oss.str();
    }
    for (std::size_t idx = 0U; idx < samples.size(); ++idx)
    {
        const float expected = static_cast<float>(samples[idx]) / static_cast<float>(kB2bI16Scale);
        if (std::abs(got[idx] - expected) > kB2bTol16)
        {
            std::ostringstream oss;
            oss << "sample " << idx << ": expected " << expected << ", got " << got[idx];
            return oss.str();
        }
    }
    return {};
}

// Spec 7: mono bit-exact (both backends). 1-channel 48k 16-bit; channels()==1, frame count,
// per-sample within 1/32768.
static auto testFileDecodeMonoBitExact() -> void
{
    static const char* const kName = "FileDecode_Mono_BitExact";
    const std::vector<int16_t> samples = {0, 4096, -4096, 8192, -8192, 12345, -12345, 100};

    if (!writeWav16(kPathMono, samples, kB2bChannels1, kB2bRate48k))
    {
        logFail(kName, "could not write the mono fixture");
        return;
    }

    {
        BackendGuard appleGuard(Backend::Apple);
        const std::string appleErr = monoBody(samples);
        if (!appleErr.empty())
        {
            std::remove(kPathMono);
            logFail(kName, "Apple: " + appleErr);
            return;
        }
    }

    const bool skipFfmpeg = ffmpegLegUnavailable(kPathMono);
    if (!skipFfmpeg)
    {
        BackendGuard ffmpegGuard(Backend::FFmpeg);
        const std::string ffmpegErr = monoBody(samples);
        if (!ffmpegErr.empty())
        {
            std::remove(kPathMono);
            logFail(kName, "FFmpeg: " + ffmpegErr);
            return;
        }
    }
    std::remove(kPathMono);
    logPass(kName);
}

// Body for the 4-channel case on one forced backend. Each channel carries a DISTINCT pattern so an
// interleave error or channel swap shows up; per-sample within 1/32768.
static auto multichannel4Body(const std::vector<int16_t>& interleaved, uint32_t frameCount)
    -> std::string
{
    FileDecodeSource src;
    if (!src.open(kPath4ch))
    {
        src.close();
        return "open() failed";
    }
    if (src.channels() != kB2bChannels4)
    {
        std::ostringstream oss;
        oss << "channels() " << src.channels() << " != 4";
        src.close();
        return oss.str();
    }
    std::vector<float> got(static_cast<std::size_t>(frameCount) * kB2bChannels4, 0.0F);
    const uint32_t total = drainFrames(src, got, frameCount, kB2bChannels4);
    src.close();
    if (total != frameCount)
    {
        std::ostringstream oss;
        oss << "decoded " << total << " of " << frameCount << " frames";
        return oss.str();
    }
    for (std::size_t idx = 0U; idx < interleaved.size(); ++idx)
    {
        const float expected =
            static_cast<float>(interleaved[idx]) / static_cast<float>(kB2bI16Scale);
        if (std::abs(got[idx] - expected) > kB2bTol16)
        {
            std::ostringstream oss;
            oss << "interleaved sample " << idx << " (ch " << (idx % kB2bChannels4)
                << "): expected " << expected << ", got " << got[idx];
            return oss.str();
        }
    }
    return {};
}

// Spec 8: 4-channel bit-exact (both backends). Distinct per-channel patterns catch interleave /
// swap bugs.
static auto testFileDecodeMultichannel4ch() -> void
{
    static const char* const kName = "FileDecode_Multichannel_4ch";
    constexpr uint32_t kFrames = 32U;
    // Distinct per-channel base + step so every channel is unique at every frame.
    constexpr std::array<int16_t, kB2bChannels4> kChBase = {1000, -1000, 5000, -5000};
    constexpr std::array<int16_t, kB2bChannels4> kChStep = {16, -16, 32, -32};

    std::vector<int16_t> interleaved(static_cast<std::size_t>(kFrames) * kB2bChannels4);
    for (uint32_t frame = 0U; frame < kFrames; ++frame)
    {
        for (uint32_t chan = 0U; chan < kB2bChannels4; ++chan)
        {
            const int value = static_cast<int>(kChBase[chan]) +
                              (static_cast<int>(frame) * static_cast<int>(kChStep[chan]));
            interleaved[(static_cast<std::size_t>(frame) * kB2bChannels4) + chan] =
                static_cast<int16_t>(value);
        }
    }

    if (!writeWav16(kPath4ch, interleaved, kB2bChannels4, kB2bRate48k))
    {
        logFail(kName, "could not write the 4-channel fixture");
        return;
    }

    {
        BackendGuard appleGuard(Backend::Apple);
        const std::string appleErr = multichannel4Body(interleaved, kFrames);
        if (!appleErr.empty())
        {
            std::remove(kPath4ch);
            logFail(kName, "Apple: " + appleErr);
            return;
        }
    }

    const bool skipFfmpeg = ffmpegLegUnavailable(kPath4ch);
    if (!skipFfmpeg)
    {
        BackendGuard ffmpegGuard(Backend::FFmpeg);
        const std::string ffmpegErr = multichannel4Body(interleaved, kFrames);
        if (!ffmpegErr.empty())
        {
            std::remove(kPath4ch);
            logFail(kName, "FFmpeg: " + ffmpegErr);
            return;
        }
    }
    std::remove(kPath4ch);
    logPass(kName);
}

// Spec 9: channel mismatch → silence. open stereo; pullFloat with channels=1 and channels=3 must
// return 0 and zero the buffer; then a correct channels=2 pull still works (ring intact).
static auto testFileDecodePullChannelMismatchSilence() -> void
{
    static const char* const kName = "FileDecode_PullChannelMismatchSilence";
    const std::vector<int16_t> samples = {4096, -4096, 8192, -8192, 12345, -12345, 100, -100};

    if (!writeWav16(kPathChanMismatch, samples, kB2bChannels2, kB2bRate48k))
    {
        logFail(kName, "could not write the mismatch fixture");
        return;
    }
    FileDecodeSource src;
    if (!src.open(kPathChanMismatch))
    {
        src.close();
        std::remove(kPathChanMismatch);
        logFail(kName, "open() failed");
        return;
    }

    // A pull with the wrong channel count must return 0 and zero-fill the destination.
    const auto checkSilenceReturn = [&](uint32_t channels) -> std::string
    {
        std::vector<float> buf(static_cast<std::size_t>(kPullChunk32) * channels, -999.0F);
        const uint32_t produced = src.pullFloat(buf.data(), kPullChunk32, channels);
        if (produced != 0U)
        {
            std::ostringstream oss;
            oss << "channels=" << channels << " pull returned " << produced << ", expected 0";
            return oss.str();
        }
        for (const float sample : buf)
        {
            if (sample != 0.0F)
            {
                std::ostringstream oss;
                oss << "channels=" << channels << " pull did not zero the buffer";
                return oss.str();
            }
        }
        return {};
    };

    const std::string errTooFew = checkSilenceReturn(kChannelsTooFew);
    if (!errTooFew.empty())
    {
        src.close();
        std::remove(kPathChanMismatch);
        logFail(kName, errTooFew);
        return;
    }
    const std::string errTooMany = checkSilenceReturn(kChannelsTooMany);
    if (!errTooMany.empty())
    {
        src.close();
        std::remove(kPathChanMismatch);
        logFail(kName, errTooMany);
        return;
    }

    // A correct channels=2 pull must still work — the ring was not disturbed by the mismatches.
    const auto frameCount = static_cast<uint32_t>(samples.size()) / kB2bChannels2;
    std::vector<float> got(static_cast<std::size_t>(frameCount) * kB2bChannels2, 0.0F);
    const uint32_t total = drainFrames(src, got, frameCount, kB2bChannels2);
    src.close();
    std::remove(kPathChanMismatch);
    if (total != frameCount)
    {
        std::ostringstream oss;
        oss << "after mismatches, correct pull decoded " << total << " of " << frameCount;
        logFail(kName, oss.str());
        return;
    }
    logPass(kName);
}

// Spec 10: EOF + decoderFinished. Drain a 64-frame file fully; decoderFinished() becomes true
// within ~100 ms; one more pullFloat returns 0 and zero-fills.
static auto testFileDecodeEofAndFinishedFlag() -> void
{
    static const char* const kName = "FileDecode_EofAndFinishedFlag";
    constexpr uint32_t kFrames64 = 64U;

    const std::vector<int16_t> interleaved = makeStereoRamp(kFrames64);
    if (!writeWav16(kPathEof, interleaved, kB2bChannels2, kB2bRate48k))
    {
        logFail(kName, "could not write the EOF fixture");
        return;
    }
    FileDecodeSource src;
    if (!src.open(kPathEof))
    {
        src.close();
        std::remove(kPathEof);
        logFail(kName, "open() failed");
        return;
    }

    std::vector<float> got(static_cast<std::size_t>(kFrames64) * kB2bChannels2, 0.0F);
    const uint32_t total = drainFrames(src, got, kFrames64, kB2bChannels2);
    if (total != kFrames64)
    {
        src.close();
        std::remove(kPathEof);
        std::ostringstream oss;
        oss << "decoded " << total << " of " << kFrames64 << " frames";
        logFail(kName, oss.str());
        return;
    }

    if (!pollFinished(src))
    {
        src.close();
        std::remove(kPathEof);
        logFail(kName, "decoderFinished() not true within ~120 ms after full drain");
        return;
    }

    // One more pull: ring is empty → returns 0 and zero-fills.
    std::vector<float> extra(static_cast<std::size_t>(kPullChunk32) * kB2bChannels2, -999.0F);
    const uint32_t produced = src.pullFloat(extra.data(), kPullChunk32, kB2bChannels2);
    bool zeroed = true;
    for (const float sample : extra)
    {
        if (sample != 0.0F)
        {
            zeroed = false;
            break;
        }
    }
    src.close();
    std::remove(kPathEof);
    if (produced != 0U || !zeroed)
    {
        std::ostringstream oss;
        oss << "post-EOF pull returned " << produced << " (expected 0) zeroed=" << zeroed;
        logFail(kName, oss.str());
        return;
    }
    logPass(kName);
}

// Spec 11: finished flag != ring empty. A file that fully fits the ring; poll decoderFinished()
// true; then a single big pullFloat still returns ALL frames (the push happens-before the flag).
static auto testFileDecodeFinishedFlagRingTail() -> void
{
    static const char* const kName = "FileDecode_FinishedFlagRingTail";

    const std::vector<int16_t> interleaved = makeStereoRamp(kRingFitFrames);
    if (!writeWav16(kPathRingTail, interleaved, kB2bChannels2, kB2bRate48k))
    {
        logFail(kName, "could not write the ring-tail fixture");
        return;
    }
    FileDecodeSource src;
    if (!src.open(kPathRingTail))
    {
        src.close();
        std::remove(kPathRingTail);
        logFail(kName, "open() failed");
        return;
    }

    // Wait for the decoder to finish WITHOUT pulling (the whole file fits the ring).
    if (!pollFinished(src))
    {
        src.close();
        std::remove(kPathRingTail);
        logFail(kName, "decoderFinished() not true within ~120 ms");
        return;
    }

    // Even though finished == true, the ring still holds the whole file: one big pull returns all.
    std::vector<float> got(static_cast<std::size_t>(kRingFitFrames) * kB2bChannels2, 0.0F);
    const uint32_t produced = src.pullFloat(got.data(), kRingFitFrames, kB2bChannels2);
    src.close();
    std::remove(kPathRingTail);
    if (produced != kRingFitFrames)
    {
        std::ostringstream oss;
        oss << "after finished==true, single pull returned " << produced << " of "
            << kRingFitFrames << " (ring tail lost — push not happens-before the flag)";
        logFail(kName, oss.str());
        return;
    }
    logPass(kName);
}

// Spec 12: underrun zero-pad. Open a 64-frame file; pull immediately (no sleep): returned <= 64,
// samples beyond returned*channels are 0.0F; then drain the rest — total == 64.
static auto testFileDecodePullBeforeDecodeZeroPads() -> void
{
    static const char* const kName = "FileDecode_PullBeforeDecodeZeroPads";
    constexpr uint32_t kFrames64 = 64U;

    const std::vector<int16_t> interleaved = makeStereoRamp(kFrames64);
    if (!writeWav16(kPathUnderrun, interleaved, kB2bChannels2, kB2bRate48k))
    {
        logFail(kName, "could not write the underrun fixture");
        return;
    }
    FileDecodeSource src;
    if (!src.open(kPathUnderrun))
    {
        src.close();
        std::remove(kPathUnderrun);
        logFail(kName, "open() failed");
        return;
    }

    // Immediate pull (no sleep): the background decoder may not have filled the ring yet.
    std::vector<float> first(static_cast<std::size_t>(kFrames64) * kB2bChannels2, -999.0F);
    const uint32_t firstProduced = src.pullFloat(first.data(), kFrames64, kB2bChannels2);
    if (firstProduced > kFrames64)
    {
        src.close();
        std::remove(kPathUnderrun);
        std::ostringstream oss;
        oss << "first pull returned " << firstProduced << " > " << kFrames64;
        logFail(kName, oss.str());
        return;
    }
    // Samples beyond firstProduced*channels must be zero-padded.
    for (std::size_t idx = static_cast<std::size_t>(firstProduced) * kB2bChannels2;
         idx < first.size();
         ++idx)
    {
        if (first[idx] != 0.0F)
        {
            src.close();
            std::remove(kPathUnderrun);
            std::ostringstream oss;
            oss << "underrun tail not zero-padded at index " << idx << " (got " << first[idx]
                << ")";
            logFail(kName, oss.str());
            return;
        }
    }

    // Drain the remainder; total must reach 64.
    uint32_t total = firstProduced;
    std::vector<float> rest(static_cast<std::size_t>(kFrames64) * kB2bChannels2, 0.0F);
    const uint32_t remaining = (kFrames64 > total) ? (kFrames64 - total) : 0U;
    if (remaining > 0U)
    {
        total += drainFrames(src, rest, remaining, kB2bChannels2);
    }
    src.close();
    std::remove(kPathUnderrun);
    if (total != kFrames64)
    {
        std::ostringstream oss;
        oss << "total decoded " << total << " != " << kFrames64;
        logFail(kName, oss.str());
        return;
    }
    logPass(kName);
}

// Spec 13: FFmpeg<->Apple equivalence. 512-frame 16-bit stereo decoded forced-Apple (vecA) and
// forced-FFmpeg (vecB); element-wise within 1/32768. Skips gracefully if FFmpeg is absent.
static auto testFileDecodeBackendEquivalence() -> void
{
    static const char* const kName = "FileDecode_BackendEquivalence";
    constexpr uint32_t kFrames = 512U;
    constexpr int kRightBase = 8192;
    constexpr uint32_t kRightPeriod = 4096U;

    std::vector<int16_t> interleaved(static_cast<std::size_t>(kFrames) * kB2bChannels2);
    for (uint32_t frame = 0U; frame < kFrames; ++frame)
    {
        const auto left = static_cast<int16_t>(static_cast<int>(frame % kI16Period) - kI16Bias);
        const auto right = static_cast<int16_t>(kRightBase - static_cast<int>(frame % kRightPeriod));
        interleaved[static_cast<std::size_t>(frame) * kB2bChannels2] = left;
        interleaved[(static_cast<std::size_t>(frame) * kB2bChannels2) + 1U] = right;
    }
    if (!writeWav16(kPathEquiv, interleaved, kB2bChannels2, kB2bRate48k))
    {
        logFail(kName, "could not write the equivalence fixture");
        return;
    }

    // Apple leg.
    std::vector<float> vecA(static_cast<std::size_t>(kFrames) * kB2bChannels2, 0.0F);
    uint32_t totalA = 0U;
    {
        BackendGuard appleGuard(Backend::Apple);
        FileDecodeSource src;
        if (!src.open(kPathEquiv))
        {
            src.close();
            std::remove(kPathEquiv);
            logFail(kName, "Apple open() failed");
            return;
        }
        totalA = drainFrames(src, vecA, kFrames, kB2bChannels2);
        src.close();
    }
    if (totalA != kFrames)
    {
        std::remove(kPathEquiv);
        std::ostringstream oss;
        oss << "Apple decoded " << totalA << " of " << kFrames;
        logFail(kName, oss.str());
        return;
    }

    if (ffmpegLegUnavailable(kPathEquiv))
    {
        std::remove(kPathEquiv);
        logInfo("  [info] FileDecode_BackendEquivalence: FFmpeg not present\n");
        logPass(kName);
        return;
    }

    // FFmpeg leg.
    std::vector<float> vecB(static_cast<std::size_t>(kFrames) * kB2bChannels2, 0.0F);
    uint32_t totalB = 0U;
    {
        BackendGuard ffmpegGuard(Backend::FFmpeg);
        FileDecodeSource src;
        if (!src.open(kPathEquiv))
        {
            src.close();
            std::remove(kPathEquiv);
            logFail(kName, "FFmpeg open() failed unexpectedly");
            return;
        }
        totalB = drainFrames(src, vecB, kFrames, kB2bChannels2);
        src.close();
    }
    std::remove(kPathEquiv);
    if (totalB != kFrames)
    {
        std::ostringstream oss;
        oss << "FFmpeg decoded " << totalB << " of " << kFrames;
        logFail(kName, oss.str());
        return;
    }

    for (std::size_t idx = 0U; idx < vecA.size(); ++idx)
    {
        if (std::abs(vecA[idx] - vecB[idx]) > kB2bTol16)
        {
            std::ostringstream oss;
            oss << "backend mismatch at index " << idx << ": Apple " << vecA[idx] << " vs FFmpeg "
                << vecB[idx];
            logFail(kName, oss.str());
            return;
        }
    }
    logPass(kName);
}

// Spec 14: ring wraparound. Write ~300000 stereo frames (> 2x the 131071-frame ring) with a
// deterministic pattern (frameIdx % 32768 → int16), drain all in 4096-frame chunks, assert the
// total and spot-check a sample just past the ring boundary and near the end (1/32768).
static auto testFileDecodeRingWraparound() -> void
{
    static const char* const kName = "FileDecode_RingWraparound";

    // Build the fixture via batched ExtAudioFileWrite (one big interleaved buffer).
    const std::vector<int16_t> interleaved = makeStereoRamp(kWraparoundFrames);
    if (!writeWav16(kPathWrap, interleaved, kB2bChannels2, kB2bRate48k))
    {
        logFail(kName, "could not write the wraparound fixture");
        return;
    }

    FileDecodeSource src;
    if (!src.open(kPathWrap))
    {
        src.close();
        std::remove(kPathWrap);
        logFail(kName, "open() failed");
        return;
    }

    // Drain all frames in 4096-frame chunks (concurrent drain prevents permanent ring-full stall).
    std::vector<float> got(static_cast<std::size_t>(kWraparoundFrames) * kB2bChannels2, 0.0F);
    uint32_t total = 0U;
    constexpr int kWrapMaxAttempts = 4000; // generous bound for the large drain
    for (int attempt = 0; attempt < kWrapMaxAttempts && total < kWraparoundFrames; ++attempt)
    {
        const uint32_t want = std::min(kWraparoundChunk, kWraparoundFrames - total);
        const uint32_t produced = src.pullFloat(
            got.data() + (static_cast<std::size_t>(total) * kB2bChannels2), want, kB2bChannels2);
        total += produced;
        if (produced == 0U)
        {
            std::this_thread::sleep_for(std::chrono::milliseconds(kB2bPollNapMs));
        }
    }
    src.close();
    std::remove(kPathWrap);

    if (total != kWraparoundFrames)
    {
        std::ostringstream oss;
        oss << "decoded " << total << " of " << kWraparoundFrames << " frames (wrap drain stalled)";
        logFail(kName, oss.str());
        return;
    }

    // Spot-check a sample just past the ring boundary and one near the end.
    const std::array<uint32_t, 2> probeFrames = {kRingBoundaryFrame, kWraparoundFrames - 1U};
    for (const uint32_t frame : probeFrames)
    {
        const auto expectedI16 =
            static_cast<int16_t>(static_cast<int>(frame % kI16Period) - kI16Bias);
        const float expected = static_cast<float>(expectedI16) / static_cast<float>(kB2bI16Scale);
        const float actual = got[static_cast<std::size_t>(frame) * kB2bChannels2];
        if (std::abs(actual - expected) > kB2bTol16)
        {
            std::ostringstream oss;
            oss << "wrap spot-check frame " << frame << ": expected " << expected << ", got "
                << actual;
            logFail(kName, oss.str());
            return;
        }
    }
    logPass(kName);
}
