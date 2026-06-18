// RoundTripTests.inc
//
// B5 / L1 verification: the Pure-Mode SOFTWARE chain is sample-exact end-to-end.
// #included into Tests/DSPKernelNullTest.cpp AFTER FileDecodeTests.inc (it reuses that file's
// helpers: writeWav16, writeWav24, BackendGuard/Backend, ffmpegLegUnavailable, drainFrames; and
// PureModeTests.inc's readLeInt16 / readLeWord32). It mirrors the real device-boundary conversion
// performed in production: decode (ExtAudioFile / FFmpeg) -> convertFloatToNative() with the exact
// AudioStreamBasicDescription a real output device of that depth advertises.
//
// What is proven (L1): the chain decode -> convertFloatToNative is BYTE-IDENTICAL to the source
// integers for 16- and 24-bit stereo @ 48 kHz, with patterns that hit the format edges:
//   full-scale + (+0x7FFF / +0x7FFFFF), full-scale - (-0x8000 / -0x800000, the -1.0 -> -2^(N-1)
//   edge), mid (+-0.5*FS), and a short ramp. Zero tolerance.
//
// What is NOT proven here (L2): the CoreAudio HAL render-callback handoff of those native bytes to
// the hardware. The HAL handoff is hardware-only (no device in the harness) and is the founder's
// on-device bit-perfect check.
//
// Bit-exactness rationale: every 16-/24-bit integer is exactly representable in float32's 24-bit
// mantissa, and the int<->float convention is symmetric powers-of-two (int->float divides by
// 2^(N-1); convertFloatToNative multiplies by 2^(N-1) then clamps). So the int->float (decode) and
// the float->int (convert) compose to the identity on the in-range source integers used here.
// The single asymmetric edge (+full-scale int -> just under +1.0 in float, NOT +1.0) round-trips
// because the chosen +FS value is the largest in-range integer (e.g. +0x7FFF), whose float image
// (0x7FFF / 0x8000) maps straight back to +0x7FFF.

namespace
{
    // Native output-device descriptors used by the round-trip (the SAME ASBD flags a real device of
    // that depth presents to convertFloatToNative). 16-bit: packed signed LE. 24-bit: 24-in-32
    // container, low-justified signed LE (the founder's HDMI / USB-DAC case).
    constexpr uint32_t kRtRate48k = 48000U;
    constexpr uint32_t kRtChannels2 = 2U;

    constexpr uint32_t kRtBitsPerChannel16 = 16U; // 16-bit PCM depth passed to convertFloatToNative
    constexpr uint32_t kRtBitsPerChannel24 = 24U; // 24-bit PCM depth passed to convertFloatToNative

    constexpr uint32_t kRtBytesInt16 = 2U;   // packed 16-bit word
    constexpr uint32_t kRtBytes24In32 = 4U;  // 24-bit sits in a 32-bit container

    // /tmp fixture paths for the 16- and 24-bit round-trip WAV files.
    constexpr const char* kRtPath16 = ADAPTIVESOUND_TEST_DATA_DIR "/adaptivesound_b5_roundtrip16.wav";
    constexpr const char* kRtPath24 = ADAPTIVESOUND_TEST_DATA_DIR "/adaptivesound_b5_roundtrip24.wav";

    constexpr int32_t kRtI24PosFull = 8388607;  // 0x7FFFFF, 24-bit +full scale
    constexpr int32_t kRtI24NegFull = -8388608; // -0x800000, 24-bit -full scale (the -1.0 edge)
    constexpr int32_t kRtI24Half = 4194304;     // +0x400000, +0.5 * FS
    constexpr uint32_t kRt24BitMask = 0x00FFFFFFU;
    constexpr uint32_t kRt24SignBit = 0x00800000U; // set => negative 24-bit value
    constexpr uint32_t kRt24SignExtend = 0xFF000000U;

    // Decode the signed 24-bit value held in the low 24 bits of a 32-bit little-endian word at
    // sample index `i` (the low-justified 24-in-32 layout convertFloatToNative writes). Sign-extends
    // the top byte so the result is a correct negative int32 for samples with the 24-bit sign set.
    auto readLe24In32(const std::vector<uint8_t>& bytes, size_t i) -> int32_t
    {
        const uint32_t word = readLeWord32(bytes, i) & kRt24BitMask;
        const uint32_t extended = ((word & kRt24SignBit) != 0U) ? (word | kRt24SignExtend) : word;
        return static_cast<int32_t>(extended);
    }

    // Drain the whole file through FileDecodeSource into interleaved floats. Returns "" on success,
    // or a non-empty error string (format mismatch / short decode). On success `outFloats` holds
    // frameCount*channels decoded floats.
    auto decodeWholeFile(const char* path,
                         uint32_t channels,
                         uint32_t frameCount,
                         std::vector<float>& outFloats) -> std::string
    {
        FileDecodeSource src;
        if (!src.open(path))
        {
            src.close();
            return "open() failed";
        }
        if (std::abs(src.sampleRate() - static_cast<double>(kRtRate48k)) > 1.0 ||
            src.channels() != channels)
        {
            std::ostringstream oss;
            oss << "format mismatch: rate " << src.sampleRate() << " ch " << src.channels();
            src.close();
            return oss.str();
        }
        outFloats.assign(static_cast<std::size_t>(frameCount) * channels, 0.0F);
        const uint32_t total = drainFrames(src, outFloats, frameCount, channels);
        src.close();
        if (total != frameCount)
        {
            std::ostringstream oss;
            oss << "decoded " << total << " of " << frameCount << " frames";
            return oss.str();
        }
        return {};
    }
} // namespace

// 16-bit round-trip on one forced backend: decode -> convertFloatToNative(16-bit packed signed LE)
// -> decode native bytes -> assert byte-identical to the source int16 (zero tolerance).
static auto roundTrip16Body(const std::vector<int16_t>& source) -> std::string
{
    const auto frameCount = static_cast<uint32_t>(source.size()) / kRtChannels2;

    std::vector<float> decoded;
    std::string err = decodeWholeFile(kRtPath16, kRtChannels2, frameCount, decoded);
    if (!err.empty())
    {
        return err;
    }

    // Float -> native int16 packed signed LE (the EXACT descriptor a 16-bit device advertises).
    std::vector<uint8_t> native(source.size() * kRtBytesInt16, 0xAAU); // poison to catch gaps
    convertFloatToNative(decoded.data(),
                         native.data(),
                         frameCount,
                         kRtChannels2,
                         /*bitsPerChannel=*/kRtBitsPerChannel16,
                         /*isFloat=*/false,
                         /*isSignedInt=*/true,
                         /*isPacked=*/true,
                         /*isAlignedHigh=*/false,
                         /*isBigEndian=*/false);

    for (std::size_t idx = 0U; idx < source.size(); ++idx)
    {
        const int16_t got = readLeInt16(native, idx);
        if (got != source[idx])
        {
            std::ostringstream oss;
            oss << "sample " << idx << " (ch " << (idx % kRtChannels2) << "): expected "
                << source[idx] << ", got " << got;
            return oss.str();
        }
    }
    return {};
}

// 24-bit round-trip on one forced backend: decode -> convertFloatToNative(24-in-32 low-justified
// signed LE) -> decode the low 24 bits of each word -> assert byte-identical to the source 24-bit
// values (zero tolerance).
static auto roundTrip24Body(const std::vector<int32_t>& source) -> std::string
{
    const auto frameCount = static_cast<uint32_t>(source.size()) / kRtChannels2;

    std::vector<float> decoded;
    std::string err = decodeWholeFile(kRtPath24, kRtChannels2, frameCount, decoded);
    if (!err.empty())
    {
        return err;
    }

    // Float -> native 24-in-32 low-justified signed LE (the EXACT descriptor the founder's HDMI /
    // USB-DAC presents: 24 valid bits in a 32-bit word, bottom-justified, packed=false).
    std::vector<uint8_t> native(source.size() * kRtBytes24In32, 0xAAU);
    convertFloatToNative(decoded.data(),
                         native.data(),
                         frameCount,
                         kRtChannels2,
                         /*bitsPerChannel=*/kRtBitsPerChannel24,
                         /*isFloat=*/false,
                         /*isSignedInt=*/true,
                         /*isPacked=*/false,
                         /*isAlignedHigh=*/false,
                         /*isBigEndian=*/false);

    for (std::size_t idx = 0U; idx < source.size(); ++idx)
    {
        const int32_t got = readLe24In32(native, idx);
        if (got != source[idx])
        {
            std::ostringstream oss;
            oss << "sample " << idx << " (ch " << (idx % kRtChannels2) << "): expected "
                << source[idx] << ", got " << got;
            return oss.str();
        }
    }
    return {};
}

// Run one round-trip body forced-Apple (always) and forced-FFmpeg (when present), reporting per-leg.
// `runLeg` does the decode->convert->decode round-trip for the active backend. Returns true on
// pass (and logs PASS); on failure logs FAIL and returns false. Caller removes the fixture.
static auto runRoundTripLegs(const char* kName,
                             const char* path,
                             const std::function<std::string()>& runLeg) -> bool
{
    {
        BackendGuard appleGuard(Backend::Apple);
        const std::string appleErr = runLeg();
        if (!appleErr.empty())
        {
            std::remove(path);
            logFail(kName, "Apple: " + appleErr);
            return false;
        }
    }

    const bool skipFfmpeg = ffmpegLegUnavailable(path);
    if (!skipFfmpeg)
    {
        BackendGuard ffmpegGuard(Backend::FFmpeg);
        const std::string ffmpegErr = runLeg();
        if (!ffmpegErr.empty())
        {
            std::remove(path);
            logFail(kName, "FFmpeg: " + ffmpegErr);
            return false;
        }
    }
    std::remove(path);

    logInfo("  [info] " + std::string(kName) + ": L1 software chain (decode -> "
            "convertFloatToNative) is byte-exact; the HAL handoff (L2) is the on-device check.\n");
    if (skipFfmpeg)
    {
        logInfo("  [info] " + std::string(kName) + ": FFmpeg not present (Apple leg only)\n");
    }
    return true;
}

// RoundTrip_BitExact_16bit: known int16 stereo @ 48 kHz with edge patterns round-trips byte-exact
// through decode -> convertFloatToNative(16-bit packed signed LE) on both backends.
static auto testRoundTripBitExact16bit() -> void
{
    static const char* const kName = "RoundTrip_BitExact_16bit";

    // Edge-hitting interleaved stereo int16: +FS, -FS (the -1.0 edge), +-0.5*FS, mid values, and a
    // short ramp. Right channel mirrors left with a distinct offset so a channel swap is caught.
    constexpr int16_t kPosFull = 0x7FFF;  // +32767
    constexpr int16_t kNegFull = -0x8000; // -32768, the -1.0 -> -2^15 edge
    constexpr int16_t kPosHalf = 16384;   // +0.5 * FS
    constexpr int16_t kNegHalf = -16384;  // -0.5 * FS
    const std::vector<int16_t> source = {
        kPosFull, kNegFull, // frame 0: edges on both channels
        kNegFull, kPosFull, // frame 1: swapped edges
        kPosHalf, kNegHalf, // frame 2: +-0.5 FS
        kNegHalf, kPosHalf, // frame 3
        0,        0,        // frame 4: silence
        1,        -1,       // frame 5: 1 LSB either side of 0
        100,      200,      // frame 6: ramp
        300,      400,      // frame 7: ramp
    };

    if (!writeWav16(kRtPath16, source, kRtChannels2, static_cast<double>(kRtRate48k)))
    {
        logFail(kName, "could not write the 16-bit fixture");
        return;
    }
    const auto leg = [&source]() -> std::string { return roundTrip16Body(source); };
    if (runRoundTripLegs(kName, kRtPath16, leg))
    {
        logPass(kName);
    }
}

// RoundTrip_BitExact_24bit: known 24-bit stereo @ 48 kHz with edge patterns round-trips byte-exact
// through decode -> convertFloatToNative(24-in-32 low-justified signed LE) on both backends.
static auto testRoundTripBitExact24bit() -> void
{
    static const char* const kName = "RoundTrip_BitExact_24bit";

    // Edge-hitting interleaved stereo 24-bit (held in int32, range [-2^23, 2^23-1]).
    const std::vector<int32_t> source = {
        kRtI24PosFull, kRtI24NegFull, // frame 0: edges (+0x7FFFFF / -0x800000)
        kRtI24NegFull, kRtI24PosFull, // frame 1: swapped edges
        kRtI24Half,    -kRtI24Half,   // frame 2: +-0.5 FS
        -kRtI24Half,   kRtI24Half,    // frame 3
        0,             0,             // frame 4: silence
        1,             -1,            // frame 5: 1 LSB either side of 0
        123456,        -123456,       // frame 6: ramp / arbitrary
        654321,        -654321,       // frame 7: ramp / arbitrary
    };

    if (!writeWav24(kRtPath24, source, kRtChannels2, static_cast<double>(kRtRate48k)))
    {
        logFail(kName, "could not write the 24-bit fixture");
        return;
    }
    const auto leg = [&source]() -> std::string { return roundTrip24Body(source); };
    if (runRoundTripLegs(kName, kRtPath24, leg))
    {
        logPass(kName);
    }
}
