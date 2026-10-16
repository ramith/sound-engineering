// PureDitherTests.inc
//
// TPDF dither where Pure reduces bits (R1.1-A, founder decision 2026-10-16; council C-33): a source
// deeper than the device's integer word — a 24-bit file on a 16-bit DAC — used to be truncated. Now
// the float → integer step adds triangular (TPDF) dither of ±1 LSB of the output word and rounds to
// nearest, only when bits are reduced; at the exact depth the conversion stays bit-exact (the
// exhaustive 2^16 / 2^24 round trips in PureModeTests.inc).
// #included into Tests/DSPKernelNullTest.cpp after SoakRtAllocTests.inc (RtGuardScope).
//
// Tests: PureDither_TpdfShape, PureDither_NoDcNoNoiseModulation, PureDither_QuietSineIsToneInNoise,
//        PureDither_OnlyWhenReducing, PureDither_RtSafe.

namespace
{
    constexpr double kDitherLsb16 = 1.0 / 32768.0; // one int16 LSB, full scale ±1.0

    // Interleaved int16 little-endian bytes → the integer codes.
    auto int16Codes(std::span<const std::byte> bytes) -> std::vector<int32_t>
    {
        std::vector<int32_t> codes(bytes.size() / 2U);
        for (std::size_t idx = 0U; idx < codes.size(); ++idx)
        {
            const auto low = static_cast<uint32_t>(bytes[2U * idx]);
            const auto high = static_cast<uint32_t>(bytes[(2U * idx) + 1U]);
            codes[idx] = static_cast<int16_t>(static_cast<uint16_t>(low | (high << 8U)));
        }
        return codes;
    }

    // One mono int16 format (little-endian).
    auto mono16() -> NativePcmFormat
    {
        NativePcmFormat format;
        format.layout = NativeSampleLayout::Int16;
        format.channels = 1U;
        return format;
    }

    // Convert `samples` to mono int16, dithered (`dither`) or not, and return the codes.
    auto toInt16(const std::vector<float>& samples, TpdfDither* dither) -> std::vector<int32_t>
    {
        std::vector<std::byte> bytes(samples.size() * 2U);
        if (dither != nullptr)
        {
            (void)convertFloatToNativeDithered(samples, bytes, mono16(), *dither);
        }
        else
        {
            (void)convertFloatToNative(samples, bytes, mono16());
        }
        return int16Codes(bytes);
    }

    // The amplitude (dBFS, full scale 1.0) of the `freq` Hz component of int16 `codes` at `rate`: one
    // DFT bin, coherent (a whole number of cycles), so no window.
    auto componentDbfs(const std::vector<int32_t>& codes, double freq, double rate) -> double
    {
        double real = 0.0;
        double imag = 0.0;
        const double step = 2.0 * std::numbers::pi * freq / rate;
        for (std::size_t idx = 0U; idx < codes.size(); ++idx)
        {
            const double value = static_cast<double>(codes[idx]) * kDitherLsb16;
            real += value * std::cos(step * static_cast<double>(idx));
            imag -= value * std::sin(step * static_cast<double>(idx));
        }
        const double amplitude = 2.0 * std::hypot(real, imag) / static_cast<double>(codes.size());
        return amplitude > 0.0 ? 20.0 * std::log10(amplitude) : -400.0;
    }

    // A sine at `dbfs` (peak, full scale 1.0) and `freq` Hz, `count` samples at `rate`.
    auto sine(double dbfs, double freq, double rate, std::size_t count) -> std::vector<float>
    {
        const double amplitude = std::pow(10.0, dbfs / 20.0);
        std::vector<float> samples(count);
        for (std::size_t idx = 0U; idx < count; ++idx)
        {
            samples[idx] = static_cast<float>(
                amplitude * std::sin(2.0 * std::numbers::pi * freq * static_cast<double>(idx) / rate));
        }
        return samples;
    }
} // namespace

// The dither itself: triangular on (−1, +1) LSB — the difference of two independent uniform draws —
// zero-mean, variance 1/6 LSB², three quarters of it inside ±½ LSB, and the density 1 − |x|.
static auto testPureDitherTpdfShape() -> void
{
    static const char* const kName = "PureDither_TpdfShape";
    constexpr int kDraws = 1'000'000;
    constexpr int kBins = 20; // 0.1 LSB each, over (−1, 1)
    TpdfDither dither;
    double sum = 0.0;
    double sumSquares = 0.0;
    int inner = 0;
    std::array<int, kBins> histogram{};
    for (int draw = 0; draw < kDraws; ++draw)
    {
        const double value = dither.next();
        if (value <= -1.0 || value >= 1.0)
        {
            logFail(kName, std::format("a draw outside (−1, 1) LSB: {}", value));
            return;
        }
        sum += value;
        sumSquares += value * value;
        inner += (std::fabs(value) < 0.5) ? 1 : 0;
        histogram[static_cast<std::size_t>(std::clamp(static_cast<int>((value + 1.0) * 10.0), 0, kBins - 1))]++;
    }
    const double mean = sum / kDraws;
    const double variance = (sumSquares / kDraws) - (mean * mean);
    const double innerShare = static_cast<double>(inner) / kDraws;
    double worstBin = 0.0;
    for (int bin = 0; bin < kBins; ++bin)
    {
        const double centre = -0.95 + (0.1 * bin);
        const double expected = (1.0 - std::fabs(centre)) * 0.1; // the triangle's mass in the bin
        worstBin = std::max(worstBin,
                            std::fabs((static_cast<double>(histogram[static_cast<std::size_t>(bin)]) / kDraws) -
                                      expected));
    }
    logInfo(std::format("  [info] TPDF: mean {:.5f} LSB, variance {:.5f} LSB² (1/6 = {:.5f}), |d|<½: {:.4f}, "
                        "worst bin off the triangle by {:.5f}\n",
                        mean, variance, 1.0 / 6.0, innerShare, worstBin));
    if (std::fabs(mean) > 0.003 || std::fabs(variance - (1.0 / 6.0)) > 0.003 ||
        std::fabs(innerShare - 0.75) > 0.003 || worstBin > 0.002)
    {
        logFail(kName, "the dither is not triangular, zero-mean, ±1 LSB");
        return;
    }
    logPass(kName);
}

// No DC, no noise modulation: a constant input at any fraction of an LSB comes out right on average
// (truncation is off by the fraction), and the error's power is the same at every fraction — ¼ LSB²
// (the dither's 1/6 plus rounding's 1/12) — so the noise doesn't follow the signal.
static auto testPureDitherNoDcNoNoiseModulation() -> void
{
    static const char* const kName = "PureDither_NoDcNoNoiseModulation";
    constexpr std::size_t kSamples = 400'000;
    constexpr std::array<double, 5> kOffsets = {0.0, 0.25, 0.5, 0.75, -0.6}; // in LSB, around 10 LSB
    TpdfDither dither;
    std::string report;
    for (const double offset : kOffsets)
    {
        const double input = (10.0 + offset) * kDitherLsb16;
        const std::vector<float> samples(kSamples, static_cast<float>(input));
        const std::vector<int32_t> dithered = toInt16(samples, &dither);
        const std::vector<int32_t> truncated = toInt16(samples, nullptr);
        const double target = static_cast<double>(samples[0]) / kDitherLsb16;
        double sum = 0.0;
        double sumSquares = 0.0;
        for (const int32_t code : dithered)
        {
            const double error = static_cast<double>(code) - target;
            sum += error;
            sumSquares += error * error;
        }
        const double mean = sum / kSamples;
        const double power = sumSquares / kSamples;
        const double truncationError = static_cast<double>(truncated[0]) - target;
        report += std::format(" [{:+.2f} LSB: mean {:+.4f}, power {:.4f}; truncation {:+.2f}]", offset, mean, power,
                              truncationError);
        if (std::fabs(mean) > 0.01 || std::fabs(power - 0.25) > 0.01)
        {
            logFail(kName, "DC or noise modulation:" + report);
            return;
        }
    }
    logInfo("  [info] dither error vs input fraction:" + report + "\n");
    logPass(kName);
}

// A quiet tone survives as a tone in noise: at −100 dBFS (a third of an int16 LSB) truncation leaves
// nothing at all, dither keeps the 1 kHz tone at its level; at −80 dBFS (3.3 LSB) truncation's staircase
// makes odd harmonics, which dither turns into a flat floor.
static auto testPureDitherQuietSineIsToneInNoise() -> void
{
    static const char* const kName = "PureDither_QuietSineIsToneInNoise";
    constexpr double kRate = 48000.0;
    constexpr double kTone = 1000.0;
    constexpr std::size_t kSamples = 192'000; // 4 s: whole cycles of every harmonic measured
    TpdfDither dither;

    const std::vector<float> quietest = sine(-100.0, kTone, kRate, kSamples);
    const std::vector<int32_t> quietDithered = toInt16(quietest, &dither);
    const std::vector<int32_t> quietTruncated = toInt16(quietest, nullptr);
    const double quietDitheredDb = componentDbfs(quietDithered, kTone, kRate);
    const double quietTruncatedDb = componentDbfs(quietTruncated, kTone, kRate);

    const std::vector<float> quiet = sine(-80.0, kTone, kRate, kSamples);
    const std::vector<int32_t> dithered = toInt16(quiet, &dither);
    const std::vector<int32_t> truncated = toInt16(quiet, nullptr);
    const double fundamental = componentDbfs(dithered, kTone, kRate);
    const double third = componentDbfs(dithered, 3.0 * kTone, kRate);
    const double fifth = componentDbfs(dithered, 5.0 * kTone, kRate);
    const double thirdTruncated = componentDbfs(truncated, 3.0 * kTone, kRate);
    const double fifthTruncated = componentDbfs(truncated, 5.0 * kTone, kRate);

    logInfo(std::format("  [info] −100 dBFS 1 kHz → int16: dithered {:.1f} dBFS, truncated {:.1f} dBFS\n"
                        "  [info] −80 dBFS 1 kHz → int16: dithered fundamental {:.1f}, 3rd {:.1f}, 5th {:.1f} dBFS; "
                        "truncated 3rd {:.1f}, 5th {:.1f} dBFS\n",
                        quietDitheredDb, quietTruncatedDb, fundamental, third, fifth, thirdTruncated,
                        fifthTruncated));
    if (std::fabs(quietDitheredDb - (-100.0)) > 1.5)
    {
        logFail(kName, std::format("the −100 dBFS tone came out at {:.1f} dBFS", quietDitheredDb));
        return;
    }
    if (std::fabs(fundamental - (-80.0)) > 0.5 || std::max(third, fifth) > -125.0)
    {
        logFail(kName, std::format("−80 dBFS: fundamental {:.1f}, harmonics {:.1f} / {:.1f} dBFS", fundamental,
                                   third, fifth));
        return;
    }
    if (thirdTruncated - third < 25.0)
    {
        logFail(kName, std::format("dither suppressed the 3rd harmonic by only {:.1f} dB", thirdTruncated - third));
        return;
    }
    logPass(kName);
}

// Dither only where bits are reduced: the depth rule's "not bit-perfect" on an integer word narrower
// than 32 bits. At the exact depth, on a float device, or for a compressed source, the conversion is
// the plain one — bit-exact (PureModeTests' exhaustive round trips cover it). On a float32 layout the
// dithered converter writes exactly what the plain one does: there is no integer step to dither.
static auto testPureDitherOnlyWhenReducing() -> void
{
    static const char* const kName = "PureDither_OnlyWhenReducing";
    struct Case
    {
        const char* what;
        uint32_t fileBits;
        bool fileFloat;
        uint32_t outputBits;
        bool outputFloat;
        bool dithers;
    };
    constexpr auto kCases = std::to_array<Case>({
        {"24-bit file, 16-bit DAC", 24U, false, 16U, false, true},
        {"float32 file, 24-bit DAC", 32U, true, 24U, false, true},
        {"float32 file, 16-bit DAC", 32U, true, 16U, false, true},
        {"32-bit integer file, 24-bit DAC", 32U, false, 24U, false, true},
        {"16-bit file, 16-bit DAC", 16U, false, 16U, false, false},
        {"24-bit file, 24-bit DAC", 24U, false, 24U, false, false},
        {"16-bit file, 24-bit DAC", 16U, false, 24U, false, false},
        {"24-bit file, float output", 24U, false, 32U, true, false},
        {"32-bit integer file, 32-bit DAC (no reduction at the output step)", 32U, false, 32U, false, false},
        {"a compressed file, 16-bit DAC", 0U, false, 16U, false, false},
    });
    for (const Case& testCase : kCases)
    {
        FileFormat file = makeFile(TestConstants::kRate44k);
        file.bitsPerChannel = testCase.fileBits;
        file.isFloat = testCase.fileFloat;
        if (ditherWhenConverting(file, testCase.outputBits, testCase.outputFloat) != testCase.dithers)
        {
            logFail(kName, std::format("{}: dither {}, expected {}", testCase.what, !testCase.dithers,
                                       testCase.dithers));
            return;
        }
    }
    NativePcmFormat float32;
    float32.layout = NativeSampleLayout::Float32;
    float32.channels = 2U;
    const std::vector<float> samples = sine(-20.0, 997.0, 48000.0, 4096);
    std::vector<std::byte> plain(samples.size() * 4U);
    std::vector<std::byte> withDither(samples.size() * 4U);
    TpdfDither dither;
    (void)convertFloatToNative(samples, plain, float32);
    (void)convertFloatToNativeDithered(samples, withDither, float32, dither);
    if (plain != withDither)
    {
        logFail(kName, "a float32 output was dithered");
        return;
    }
    logPass(kName);
}

// Real-time safe: the dithered conversion is noexcept and allocates nothing on the IO thread (the
// generator is a 64-bit state in the engine, no lock, no system call).
static auto testPureDitherRtSafe() -> void
{
    static const char* const kName = "PureDither_RtSafe";
    static_assert(noexcept(convertFloatToNativeDithered(std::span<const float>(), std::span<std::byte>(),
                                                         std::declval<const NativePcmFormat&>(),
                                                         std::declval<TpdfDither&>())));
    static_assert(noexcept(std::declval<TpdfDither&>().next()));
    const std::vector<float> samples = sine(-10.0, 997.0, 48000.0, 8192);
    std::vector<std::byte> bytes(samples.size() * 4U);
    NativePcmFormat packed24;
    packed24.layout = NativeSampleLayout::Int24Packed;
    packed24.channels = 2U;
    TpdfDither dither;
    uint64_t allocations = 0U;
    {
        RtGuardScope guard;
        for (int block = 0; block < 64; ++block)
        {
            (void)convertFloatToNativeDithered(samples, bytes, mono16(), dither);
            (void)convertFloatToNativeDithered(samples, bytes, packed24, dither);
        }
        allocations = RtGuardScope::count();
    }
    if (allocations != 0U)
    {
        logFail(kName, std::format("{} allocation(s) on the conversion path", allocations));
        return;
    }
    logPass(kName);
}
