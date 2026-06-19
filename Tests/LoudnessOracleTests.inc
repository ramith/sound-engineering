// LoudnessOracleTests.inc
//
// S7 / US-QA-01 — TEST-ONLY conformance oracle.
//
// Cross-checks OUR loudness DSP against the reference implementation libebur128
// (jiixyj, MIT, pinned v1.2.6, vendored as a git submodule at third_party/libebur128).
// libebur128 is compiled — AS C — into the test binary ONLY (build-null-test.sh); it
// never enters Package.swift, the AudioDSP target, or the shipping app.
//
// Two oracles, same signal battery:
//   * Integrated LUFS:  AdaptiveSound::LufsMeter  vs  ebur128 EBUR128_MODE_I.
//   * True peak:        AdaptiveSound::LimiterModule's 8x polyphase ISP detector
//                        (recovered behaviourally from the applied gain reduction)
//                        vs  ebur128 EBUR128_MODE_TRUE_PEAK (4x default).
//
// Tolerances are NOT tuned to force a pass: a disagreement beyond them is a real
// finding about our DSP, and the test fails loudly with the measured numbers.
//
// #included into Tests/DSPKernelNullTest.cpp after TestSupport.h.

// ebur128.h self-guards with extern "C"; wrap defensively per the task contract.
extern "C"
{
#include "ebur128.h"
}

// QW1 CF-10 needs the crossfeed module + the Realizer derivation path.
#include "../Sources/AudioDSP/AudioEngine/Realizer.h"
#include "../Sources/AudioDSP/Spatial/CrossfeedModule.h"

namespace
{
    // Integrated-LUFS agreement budget. Our meter is within EBU's ±0.1 LU and so is
    // libebur128; ±0.2 LU covers the histogram-bin quantisation difference between the
    // two gating implementations without masking a genuine algorithmic divergence.
    constexpr double kOracleLufsTolLu = 0.2;

    // True-peak agreement budget. Our detector oversamples 8x; libebur128 oversamples
    // 4x for fs < 96 kHz, so it can read slightly LOWER on a worst-case inter-sample
    // peak. 0.3 dB covers that interpolator gap. We additionally require that NEITHER
    // meter under-reads the sample peak (a true-peak meter must be >= sample peak).
    constexpr double kOracleTpTolDb = 0.3;

    constexpr uint32_t kOracleRate48k = 48000U;
    constexpr uint32_t kOracleRate44k = 44100U;
    constexpr uint32_t kOracleStereo = 2U;

    // --- Signal generators (interleaved stereo, in-phase L==R) --------------------

    auto genStereoSine(double peakDbfs, double freqHz, double seconds, uint32_t sampleRate)
        -> std::vector<float>
    {
        const double amp = std::pow(10.0, peakDbfs / 20.0);
        const auto frames = static_cast<size_t>(seconds * sampleRate);
        std::vector<float> buf(frames * kOracleStereo);
        for (size_t n = 0; n < frames; ++n)
        {
            const double s = amp * std::sin(2.0 * std::numbers::pi * freqHz *
                                            static_cast<double>(n) / sampleRate);
            buf[kOracleStereo * n] = static_cast<float>(s);
            buf[(kOracleStereo * n) + 1U] = static_cast<float>(s);
        }
        return buf;
    }

    // White noise, peak-normalised to peakDbfs (deterministic seed).
    auto genStereoWhiteNoise(double peakDbfs, double seconds, uint32_t sampleRate, uint32_t seed)
        -> std::vector<float>
    {
        const double amp = std::pow(10.0, peakDbfs / 20.0);
        const auto frames = static_cast<size_t>(seconds * sampleRate);
        std::vector<float> buf(frames * kOracleStereo);
        // NOLINTBEGIN(cert-msc32-c,cert-msc51-cpp)
        std::mt19937 gen(seed);
        // NOLINTEND(cert-msc32-c,cert-msc51-cpp)
        std::uniform_real_distribution<double> dist(-amp, amp);
        for (size_t n = 0; n < frames; ++n)
        {
            const auto s = static_cast<float>(dist(gen));
            buf[kOracleStereo * n] = s;
            buf[(kOracleStereo * n) + 1U] = s; // in-phase stereo (correlated)
        }
        return buf;
    }

    // Pink noise via the Voss-McCartney algorithm, RMS-then-peak-normalised to peakDbfs.
    auto genStereoPinkNoise(double peakDbfs, double seconds, uint32_t sampleRate, uint32_t seed)
        -> std::vector<float>
    {
        const auto frames = static_cast<size_t>(seconds * sampleRate);
        std::vector<float> mono(frames);
        // NOLINTBEGIN(cert-msc32-c,cert-msc51-cpp)
        std::mt19937 gen(seed);
        // NOLINTEND(cert-msc32-c,cert-msc51-cpp)
        std::uniform_real_distribution<double> dist(-1.0, 1.0);
        constexpr int kRows = 16;
        std::array<double, kRows> rows{};
        double running = 0.0;
        for (auto& r : rows)
        {
            r = dist(gen);
            running += r;
        }
        double peak = 0.0;
        for (size_t n = 0; n < frames; ++n)
        {
            // Update one row per step: row index = number of trailing zero bits of n.
            const auto idx = (n == 0) ? 0 : std::countr_zero(n);
            if (idx < kRows)
            {
                running -= rows[static_cast<size_t>(idx)];
                rows[static_cast<size_t>(idx)] = dist(gen);
                running += rows[static_cast<size_t>(idx)];
            }
            const double s = (running + dist(gen)) / (kRows + 1);
            mono[n] = static_cast<float>(s);
            peak = std::max(peak, std::abs(s));
        }
        const double target = std::pow(10.0, peakDbfs / 20.0);
        const double scale = (peak > 0.0) ? (target / peak) : 1.0;
        std::vector<float> buf(frames * kOracleStereo);
        for (size_t n = 0; n < frames; ++n)
        {
            const auto s = static_cast<float>(static_cast<double>(mono[n]) * scale);
            buf[kOracleStereo * n] = s;
            buf[(kOracleStereo * n) + 1U] = s;
        }
        return buf;
    }

    // Gated battery: loud -23 dBFS tone / near-silent -65 dBFS / loud tone again.
    // Exercises both the absolute (-70 LUFS) and relative (-10 LU) gates: the integrated
    // value of both meters should reflect the loud segments only, ~ -23 LUFS.
    auto genStereoGated(uint32_t sampleRate) -> std::vector<float>
    {
        auto loud = genStereoSine(-23.0, 1000.0, 5.0, sampleRate);
        auto quiet = genStereoSine(-65.0, 1000.0, 4.0, sampleRate);
        std::vector<float> out;
        out.reserve(loud.size() * 2U + quiet.size());
        out.insert(out.end(), loud.begin(), loud.end());
        out.insert(out.end(), quiet.begin(), quiet.end());
        out.insert(out.end(), loud.begin(), loud.end());
        return out;
    }

    // --- Reference (libebur128) integrated LUFS -----------------------------------
    // Returns false on any libebur128 error.
    auto ebur128Integrated(const std::vector<float>& interleavedStereo,
                           uint32_t sampleRate,
                           double& outLufs) -> bool
    {
        ebur128_state* st = ebur128_init(kOracleStereo, sampleRate, EBUR128_MODE_I);
        if (st == nullptr)
        {
            return false;
        }
        const size_t frames = interleavedStereo.size() / kOracleStereo;
        bool ok =
            ebur128_add_frames_float(st, interleavedStereo.data(), frames) == EBUR128_SUCCESS;
        if (ok)
        {
            ok = ebur128_loudness_global(st, &outLufs) == EBUR128_SUCCESS;
        }
        ebur128_destroy(&st);
        return ok;
    }

    // --- Reference (libebur128) max true peak across both channels ----------------
    auto ebur128TruePeak(const std::vector<float>& interleavedStereo,
                         uint32_t sampleRate,
                         double& outLinear) -> bool
    {
        ebur128_state* st = ebur128_init(kOracleStereo, sampleRate, EBUR128_MODE_TRUE_PEAK);
        if (st == nullptr)
        {
            return false;
        }
        const size_t frames = interleavedStereo.size() / kOracleStereo;
        bool ok =
            ebur128_add_frames_float(st, interleavedStereo.data(), frames) == EBUR128_SUCCESS;
        outLinear = 0.0;
        for (uint32_t ch = 0U; ok && ch < kOracleStereo; ++ch)
        {
            double tp = 0.0;
            ok = ebur128_true_peak(st, ch, &tp) == EBUR128_SUCCESS;
            outLinear = std::max(outLinear, tp);
        }
        ebur128_destroy(&st);
        return ok;
    }

    // --- OUR integrated LUFS via LufsMeter ----------------------------------------
    auto ourIntegrated(const std::vector<float>& interleavedStereo, uint32_t sampleRate) -> double
    {
        LufsMeter meter;
        meter.prepare(sampleRate);
        const size_t frames = interleavedStereo.size() / kOracleStereo;
        meter.addInterleavedStereo(interleavedStereo.data(), frames);
        return meter.integratedLufs();
    }

    // --- OUR true peak via the shipping LimiterModule 8x polyphase ISP detector ----
    //
    // The detector (LimiterModule::polyphaseIspPeak) is private and ring-coupled, so we
    // recover its reading BEHAVIOURALLY — exactly the value that drives the limiter — by
    // running the real LimiterModule and inverting the linked gain reduction:
    //
    //   The limiter computes  gain = workingCeiling / detectedPeak  whenever the detected
    //   inter-sample peak exceeds workingCeiling = ceiling * kIspSafetyMargin. For a steady
    //   periodic tone the sliding-window max equals the per-sample ISP, so once the gain
    //   envelope has settled:   out = in * (workingCeiling / detectedPeak).
    //   Hence  detectedPeak = workingCeiling * (in / out)  measured at the same delayed
    //   input sample (account for the lookahead). We divide out kIspSafetyMargin to expose
    //   the detector's raw ISP estimate (what an ISP meter would report).
    //
    // This drives the SAME 8x polyphase FIR our shipping limiter uses; it is the closest
    // thing we have to a standalone true-peak meter without adding shipping API.
    auto ourTruePeakLinear(const std::vector<float>& interleavedStereo,
                           uint32_t sampleRate) -> double
    {
        constexpr float kCeiling = 0.5F; // well below the ISP we feed, so the limiter engages
        const double workingCeiling =
            static_cast<double>(kCeiling) * AdaptiveSound::kIspSafetyMargin;

        const size_t frames = interleavedStereo.size() / kOracleStereo;
        const auto frameCount = static_cast<uint32_t>(frames);

        // Drive the real LimiterModule via the harness's planar stereo ABL fixture.
        TestABL abl(frameCount);
        std::vector<float> leftIn(frames); // pristine input reference (pre-limiter)
        for (size_t n = 0; n < frames; ++n)
        {
            abl.left[n] = interleavedStereo[kOracleStereo * n];
            abl.right[n] = interleavedStereo[(kOracleStereo * n) + 1U];
            leftIn[n] = abl.left[n];
        }

        AdaptiveSound::LimiterModule limiter;
        limiter.initialize(sampleRate, frameCount);

        AdaptiveSound::LimiterParams params{};
        params.truePeakCeilingLinear = kCeiling;

        const MultichannelView view = MultichannelView::fromABL(abl.abl(), frameCount);
        limiter.process(params, view);

        // Recover the deepest detected ISP from the settled region (after lookahead),
        // matching each output sample to its delayed input.
        const uint32_t look = AdaptiveSound::kLimiterLookaheadFrames;
        double maxDetected = 0.0;
        for (size_t i = look; i < frames; ++i)
        {
            const double in = std::abs(static_cast<double>(leftIn[i - look]));
            const double out = std::abs(static_cast<double>(abl.left[i]));
            if (in < 1e-4 || out < 1e-9)
            {
                continue; // ratio undefined / no signal
            }
            const double gain = out / in;
            if (gain >= 0.999) // sample not gain-reduced here -> detector at/below ceiling
            {
                continue;
            }
            const double detected = workingCeiling / gain;
            maxDetected = std::max(maxDetected, detected);
        }
        // Undo the safety margin to expose the raw ISP estimate.
        return maxDetected / AdaptiveSound::kIspSafetyMargin;
    }

    // One integrated-LUFS comparison row. Appends a diagnostic to `fail` on mismatch.
    auto compareIntegrated(const char* label,
                           const std::vector<float>& signal,
                           uint32_t sampleRate,
                           std::string& fail) -> void
    {
        double ref = 0.0;
        if (!ebur128Integrated(signal, sampleRate, ref))
        {
            fail += std::string("\n  ") + label + ": libebur128 integrated call failed";
            return;
        }
        const double ours = ourIntegrated(signal, sampleRate);
        const double delta = std::abs(ours - ref);
        std::ostringstream info;
        info << "  [info] Loudness_Oracle_Integrated: " << label << " @ " << sampleRate
             << " Hz: ours=" << ours << " LUFS, ebur128=" << ref << " LUFS, delta=" << delta
             << " LU\n";
        logInfo(info.str());
        if (delta > kOracleLufsTolLu)
        {
            std::ostringstream oss;
            oss << "\n  " << label << " @ " << sampleRate << " Hz: ours=" << ours
                << " ebur128=" << ref << " delta=" << delta << " LU (tol " << kOracleLufsTolLu
                << ")";
            fail += oss.str();
        }
    }
} // namespace

// ===========================================================================
// Test: integrated-LUFS conformance against libebur128 across the signal battery.
// ===========================================================================
static auto testLoudnessOracleIntegrated() -> void
{
    static const char* const kName = "Loudness_Oracle_Integrated_vs_ebur128";
    std::string fail;

    for (const uint32_t fs : {kOracleRate48k, kOracleRate44k})
    {
        compareIntegrated("sine1k_-23dBFS", genStereoSine(-23.0, 1000.0, 12.0, fs), fs, fail);
        compareIntegrated("sine1k_-16dBFS", genStereoSine(-16.0, 1000.0, 12.0, fs), fs, fail);
        compareIntegrated("sine1k_-6dBFS", genStereoSine(-6.0, 1000.0, 12.0, fs), fs, fail);
        compareIntegrated("white_-20dBFS", genStereoWhiteNoise(-20.0, 12.0, fs, 0x5EED01U), fs,
                          fail);
        compareIntegrated("pink_-20dBFS", genStereoPinkNoise(-20.0, 12.0, fs, 0x5EED02U), fs, fail);
        compareIntegrated("gated_tone+silence", genStereoGated(fs), fs, fail);
    }

    if (!fail.empty())
    {
        logFail(kName, "integrated LUFS disagreement beyond +-0.2 LU:" + fail);
        return;
    }
    logPass(kName);
}

// ===========================================================================
// Test: true-peak conformance against libebur128 on a known inter-sample-peak signal.
// ===========================================================================
static auto testLoudnessOracleTruePeak() -> void
{
    static const char* const kName = "Loudness_Oracle_TruePeak_vs_ebur128";
    std::string fail;

    // Classic inter-sample-peak generator: a tone near fs/4 with a 45-degree phase offset
    // has a sample peak well BELOW its true (reconstructed) peak — the textbook case a
    // sample-only meter under-reads. Amplitude 0.9 leaves ISP headroom under full scale.
    for (const uint32_t fs : {kOracleRate48k, kOracleRate44k})
    {
        const double amp = 0.9;
        const double freq = static_cast<double>(fs) / 4.0;
        const double phase = std::numbers::pi / 4.0; // 45 deg: maximises ISP overshoot at fs/4
        const auto frames = static_cast<size_t>(2.0 * fs);
        std::vector<float> sig(frames * kOracleStereo);
        double samplePeak = 0.0;
        for (size_t n = 0; n < frames; ++n)
        {
            const double s =
                amp * std::sin(2.0 * std::numbers::pi * freq * static_cast<double>(n) / fs + phase);
            sig[kOracleStereo * n] = static_cast<float>(s);
            sig[(kOracleStereo * n) + 1U] = static_cast<float>(s);
            samplePeak = std::max(samplePeak, std::abs(s));
        }

        double refTp = 0.0;
        if (!ebur128TruePeak(sig, fs, refTp))
        {
            fail += "\n  libebur128 true_peak call failed";
            continue;
        }
        const double ourTp = ourTruePeakLinear(sig, fs);

        const double refDb = 20.0 * std::log10(refTp);
        const double ourDb = 20.0 * std::log10(ourTp);
        const double samplePeakDb = 20.0 * std::log10(samplePeak);
        const double deltaDb = std::abs(ourDb - refDb);

        std::ostringstream info;
        info << "  [info] " << kName << " @ " << fs << " Hz: samplePeak=" << samplePeakDb
             << " dBFS, ours(8x)=" << ourDb << " dBTP, ebur128(4x)=" << refDb
             << " dBTP, delta=" << deltaDb << " dB\n";
        logInfo(info.str());

        // Neither meter may UNDER-read the sample peak (a true-peak reading >= sample peak).
        // Small numerical slack (0.02 dB).
        if (ourDb < samplePeakDb - 0.02)
        {
            std::ostringstream oss;
            oss << "\n  ours under-reads sample peak @ " << fs << " Hz: ours=" << ourDb
                << " dBTP < samplePeak=" << samplePeakDb << " dBFS";
            fail += oss.str();
        }
        if (refDb < samplePeakDb - 0.02)
        {
            std::ostringstream oss;
            oss << "\n  ebur128 under-reads sample peak @ " << fs << " Hz: ebur128=" << refDb
                << " dBTP < samplePeak=" << samplePeakDb << " dBFS";
            fail += oss.str();
        }
        // The two meters must agree within ~0.3 dB (8x vs 4x interpolator gap).
        if (deltaDb > kOracleTpTolDb)
        {
            std::ostringstream oss;
            oss << "\n  TP disagreement @ " << fs << " Hz: ours=" << ourDb
                << " dBTP ebur128=" << refDb << " dBTP delta=" << deltaDb << " dB (tol "
                << kOracleTpTolDb << ")";
            fail += oss.str();
        }
    }

    if (!fail.empty())
    {
        logFail(kName, "true-peak conformance failure:" + fail);
        return;
    }
    logPass(kName);
}

// ===========================================================================
// CF-10 (QW1 §6): crossfeed is loudness-neutral, measured by the libebur128 integrated-LUFS
// oracle on REAL stereo content where the design's neutrality claim is operative. The gain-neutral
// design (gDirect=1/(1+α), gCross=α/(1+α)) makes the summed magnitude unity AT DC and near-unity
// through the cross-path LPF passband — i.e. for CENTRED, BASS/LOW-MID content (the content
// crossfeed is designed to preserve). Above fc the LPF deliberately attenuates the cross path (the
// inherent, benign coloration QW1 §2 flags; the downstream LoudnessModule absorbs that residual).
//
// So we measure on a correlated bass stereo bed (a sustained chord, 60-180 Hz, well within the
// cross-path LPF passband) through the Bauer ("Default", the safe default) preset: crossfeed ON vs
// OFF must agree within 0.3 LUFS via the ebur128 oracle. (The broader broadband residual on
// HF-dominant content is by-design and not a neutrality bug -- see CF-3 / CF-5.)
// ===========================================================================
static auto testCrossfeedLoudnessNeutral() -> void
{
    static const char* const kName = "Crossfeed_ebur128_LevelNeutral";
    constexpr double kCfLufsTolLu = 0.3;
    constexpr uint32_t kCfBauerPreset = 1U; // CrossfeedPreset::Bauer ("Default", safe default)

    // Derive the Bauer-preset POD via the shipping Realizer path.
    AdaptiveSound::CrossfeedParams params{};
    {
        auto kernel = std::make_shared<DSPKernel>();
        kernel->initialize(kOracleRate48k, 512U);
        auto realizer = std::make_shared<AdaptiveSound::Realizer>(kernel);
        realizer->applyCrossfeed(1U, 1.0F, kCfBauerPreset,
                                 static_cast<double>(kOracleRate48k));
        params = realizer->canonicalState().crossfeed;
        realizer->shutdown();
    }

    // Correlated (centred) bass bed: a sustained chord spanning 60-180 Hz, well within the
    // cross-path LPF passband, where crossfeed keeps loudness neutral by design.
    const uint32_t fs = kOracleRate48k;
    const auto frames = static_cast<size_t>(8.0 * fs);
    std::vector<float> inL(frames);
    std::vector<float> inR(frames);
    const std::array<double, 4U> chordHz = {60.0, 90.0, 120.0, 180.0};
    for (size_t n = 0; n < frames; ++n)
    {
        const auto t = static_cast<double>(n) / fs;
        double s = 0.0;
        for (const double f : chordHz)
        {
            s += std::sin(2.0 * std::numbers::pi * f * t);
        }
        s = 0.2 * s / static_cast<double>(chordHz.size());
        inL[n] = static_cast<float>(s); // centred (correlated) bed
        inR[n] = static_cast<float>(s);
    }

    // Interleave the DRY signal for the oracle.
    const auto interleave = [&](const std::vector<float>& l,
                                const std::vector<float>& r) -> std::vector<float>
    {
        std::vector<float> out(frames * kOracleStereo);
        for (size_t n = 0; n < frames; ++n)
        {
            out[kOracleStereo * n] = l[n];
            out[(kOracleStereo * n) + 1U] = r[n];
        }
        return out;
    };

    double offLufs = 0.0;
    if (!ebur128Integrated(interleave(inL, inR), fs, offLufs))
    {
        logFail(kName, "libebur128 integrated call failed (crossfeed OFF)");
        return;
    }

    // Process the SAME input through the crossfeed module (warm the mix ramp first, then process
    // the whole buffer as one block so the LUFS is measured on the settled steady state).
    std::vector<float> wetL = inL;
    std::vector<float> wetR = inR;
    {
        CrossfeedModule module;
        module.initialize(fs, static_cast<uint32_t>(frames));

        // Warm-up the mix ramp (process a short prefix repeatedly does NOT reset state, so instead
        // we run the full buffer twice: pass 1 warms the ramp + delay line, pass 2 is the measured
        // steady state. The input is restored before pass 2.)
        TestABL warm(static_cast<uint32_t>(frames));
        std::memcpy(warm.left.data(), inL.data(), frames * sizeof(float));
        std::memcpy(warm.right.data(), inR.data(), frames * sizeof(float));
        const MultichannelView warmView =
            MultichannelView::fromABL(warm.abl(), static_cast<uint32_t>(frames));
        module.process(params, warmView);

        TestABL meas(static_cast<uint32_t>(frames));
        std::memcpy(meas.left.data(), inL.data(), frames * sizeof(float));
        std::memcpy(meas.right.data(), inR.data(), frames * sizeof(float));
        const MultichannelView measView =
            MultichannelView::fromABL(meas.abl(), static_cast<uint32_t>(frames));
        module.process(params, measView);
        wetL = meas.left;
        wetR = meas.right;
    }

    double onLufs = 0.0;
    if (!ebur128Integrated(interleave(wetL, wetR), fs, onLufs))
    {
        logFail(kName, "libebur128 integrated call failed (crossfeed ON)");
        return;
    }

    const double delta = std::abs(onLufs - offLufs);
    std::ostringstream info;
    info << "  [info] " << kName << ": off=" << offLufs << " LUFS, on=" << onLufs
         << " LUFS, delta=" << delta << " LU (tol " << kCfLufsTolLu << ")\n";
    logInfo(info.str());

    if (delta > kCfLufsTolLu)
    {
        std::ostringstream oss;
        oss << "crossfeed not loudness-neutral: on=" << onLufs << " off=" << offLufs
            << " delta=" << delta << " LU (> " << kCfLufsTolLu << ")";
        logFail(kName, oss.str());
        return;
    }
    logPass(kName);
}
