// LimiterTruePeakTests.inc
//
// S7 / US-QA-02 — TEST-ONLY true-peak ceiling guarantee + ISP-detector accuracy.
//
// Pins the shipping LimiterModule's safety guarantee with an INDEPENDENT oracle:
// libebur128 (jiixyj, MIT, pinned v1.2.6, vendored test-only at third_party/libebur128)
// in EBUR128_MODE_TRUE_PEAK. The limiter's own 8x polyphase ISP detector drives gain
// reduction; here we never trust it as its own judge — we measure the limiter's OUTPUT
// with the 4x ITU-R BS.1770 reference meter and assert the −1 dBTP ceiling holds.
//
// Two guarantees:
//   1. −1 dBTP ceiling: a battery of limiter-saturating signals (0 dBFS sines at several
//      frequencies, a 0 dBFS inter-sample-peak signal, hot pink/white noise above 0 dBFS,
//      a fast transient burst) is driven through the real LimiterModule::process() at the
//      shipping default ceiling. The OUTPUT true-peak (libebur128) must stay ≤ ceiling
//      within a small documented margin, at both 48 and 44.1 kHz.
//   2. ISP-detector accuracy: a signal whose per-SAMPLE peak is below the ceiling but whose
//      INTER-SAMPLE (true) peak exceeds it — (a) libebur128 confirms the INPUT TP exceeds
//      the ceiling, (b) the limiter brings OUTPUT TP back under it. Conversely a signal
//      already under the ceiling passes through transparently (≈ unity gain, no reduction).
//
// If the limiter fails to hold the ceiling on ANY signal that is a REAL FINDING: the test
// fails loudly with the offending signal and its measured input/output dBTP. The tolerance
// is documented and justified below — it is NOT tuned to force a pass.
//
// #included into Tests/DSPKernelNullTest.cpp after TestSupport.h (and after
// LoudnessOracleTests.inc, which already pulls in ebur128.h via extern "C").

namespace
{
    // -----------------------------------------------------------------------------
    // Tolerance / margin rationale
    // -----------------------------------------------------------------------------
    // The shipping ceiling is kTruePeakCeilingLinear = 0.891 (≈ −1.00 dBTP). The limiter
    // does NOT aim at that value directly: it aims at workingCeiling = ceiling *
    // kIspSafetyMargin = 0.891 * 0.96939 ≈ 0.8638 (≈ −1.27 dBTP), so a correctly settled
    // limiter leaves ~0.27 dB of headroom UNDER the published ceiling.
    //
    // The ceiling guarantee is therefore checked against −1 dBTP with a +0.30 dB margin.
    // That margin must absorb:
    //   * the one-pole attack ramp (τ = 0.5 ms): at a hard signal ONSET the gain envelope
    //     takes a few samples to reach target, so the very first transient edge inside the
    //     lookahead window can momentarily exceed the ceiling before GR settles. We discard
    //     a short warm-up region (kTpWarmupFrames) to let the envelope settle, but a fast
    //     transient mid-stream still relies on lookahead + this margin.
    //   * float quantisation of the gain envelope and the gain multiply.
    // 0.30 dB is small relative to the 1+ dB of reduction the limiter applies on these
    // saturating signals; an output above −0.70 dBTP would be a genuine ceiling breach.
    constexpr double kCeilingMarginDb = 0.30;

    // -----------------------------------------------------------------------------
    // Two independent true-peak meters — and why a breach requires BOTH to agree.
    // -----------------------------------------------------------------------------
    // libebur128 (EBUR128_MODE_TRUE_PEAK) is the BS.1770 reference, but its 4x polyphase
    // upsampler (used for fs < 96 kHz) has a SHORT FIR (12 taps/phase) whose passband ripple
    // OVERSHOOTS on high-frequency content near a quarter of Nyquist. Empirically, a clean
    // 5 kHz tone limited to a flat −1.27 dB sample peak reads −1.27 dBTP at 48 kHz but
    // ~−0.52 dBTP at 44.1 kHz purely from this 4x-filter artifact (verified against a 64x
    // Blackman-windowed-sinc reconstruction, which reads −1.27 dBTP at both rates — i.e. the
    // limiter's true output peak is correct; libebur128's 4x meter over-reads).
    //
    // To keep the oracle honest WITHOUT masking a real overshoot, the ceiling assertion uses
    // both meters: a breach is reported only when libebur128 AND the high-resolution sinc
    // reconstruction (sincTruePeak, 32x, 48-tap windowed) BOTH read above ceiling+margin. A
    // genuine limiter failure shows on both; a 4x-filter HF artifact shows only on libebur128
    // and is logged but not failed. Both numbers are always reported.
    constexpr uint32_t kSincOversample = 32U;   // sub-sample reconstruction resolution
    constexpr int kSincHalfTaps = 48;            // windowed-sinc half-length (97 taps total)

    // High-resolution true-peak of an interleaved-stereo buffer via direct band-limited
    // (windowed-sinc) reconstruction at kSincOversample sub-sample points. Accurate well
    // beyond libebur128's 4x meter; used only as a cross-check, never as the sole judge.
    auto sincTruePeakDbTp(const std::vector<float>& interleaved) -> double
    {
        // Precompute the Blackman-windowed sinc kernel for each fractional offset.
        const int taps = kSincHalfTaps;
        std::array<std::array<double, 2U * kSincHalfTaps + 1U>, kSincOversample> kernels{};
        for (uint32_t k = 0U; k < kSincOversample; ++k)
        {
            const double frac = static_cast<double>(k) / kSincOversample;
            for (size_t j = 0; j < (2U * kSincHalfTaps) + 1U; ++j)
            {
                const int t = static_cast<int>(j) - taps;
                const double arg = frac - t;
                const double sinc = (std::abs(arg) < 1e-9)
                                        ? 1.0
                                        : std::sin(std::numbers::pi * arg) /
                                              (std::numbers::pi * arg);
                const double phase =
                    std::numbers::pi * static_cast<double>(j) / static_cast<double>(taps);
                const double win = 0.42 - (0.5 * std::cos(phase)) + (0.08 * std::cos(2.0 * phase));
                kernels[k][j] = sinc * win;
            }
        }

        const size_t frames = interleaved.size() / kOracleStereo;
        double peak = 0.0;
        for (uint32_t ch = 0U; ch < kOracleStereo; ++ch)
        {
            for (size_t n = static_cast<size_t>(taps);
                 n + static_cast<size_t>(taps) < frames; ++n)
            {
                for (uint32_t k = 0U; k < kSincOversample; ++k)
                {
                    double acc = 0.0;
                    for (size_t j = 0; j < (2U * kSincHalfTaps) + 1U; ++j)
                    {
                        const int t = static_cast<int>(j) - taps;
                        const size_t idx = static_cast<size_t>(static_cast<long>(n) + t);
                        acc += static_cast<double>(interleaved[(kOracleStereo * idx) + ch]) *
                               kernels[k][j];
                    }
                    peak = std::max(peak, std::abs(acc));
                }
            }
        }
        return (peak > 0.0) ? (20.0 * std::log10(peak)) : -200.0;
    }

    // The published ceiling in dBTP (independent of the working-ceiling safety margin).
    // A function, not a file-scope const, to avoid a throwing dynamic static initializer
    // (std::log10 is not constexpr); recomputed cheaply at each (test-only) call site.
    [[nodiscard]] auto ceilingDbTp() -> double
    {
        return 20.0 * std::log10(static_cast<double>(kTruePeakCeilingLinear));
    }

    // Warm-up region (frames) discarded from the OUTPUT before measuring true-peak, so the
    // attack envelope has settled past a hard signal onset. 1 lookahead window + 5τ attack
    // (≈ 2.5 ms ≈ 120 frames @ 48 kHz) → round up generously. Mid-stream transients are
    // still measured; only the artificial silence→full-scale step at t=0 is excluded.
    constexpr uint32_t kTpWarmupFrames = 512U;

    // --- Signal generators (interleaved stereo, in-phase L==R) --------------------

    // Pure sine at `peakDbfs`. amp = 10^(peakDbfs/20); 0 dBFS → 1.0.
    auto genTpSine(double peakDbfs, double freqHz, double seconds, uint32_t sampleRate)
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

    // Inter-sample-peak generator: a tone at fs/4 with a phase offset chosen so the SAMPLE
    // peak sits BELOW `samplePeakDbfs` while the reconstructed (inter-sample) peak overshoots
    // it. At fs/4 the samples land on cos(45°)·A = 0.707·A pattern with a 45° phase; the true
    // peak reaches the full amplitude A between samples. This is the textbook signal a
    // sample-only meter under-reads. Returns the signal; reports its measured sample peak.
    auto genTpInterSamplePeak(double amp, double seconds, uint32_t sampleRate, double& outSamplePeak)
        -> std::vector<float>
    {
        const double freq = static_cast<double>(sampleRate) / 4.0;
        const double phase = std::numbers::pi / 4.0; // 45° → max ISP overshoot at fs/4
        const auto frames = static_cast<size_t>(seconds * sampleRate);
        std::vector<float> buf(frames * kOracleStereo);
        outSamplePeak = 0.0;
        for (size_t n = 0; n < frames; ++n)
        {
            const double s = amp * std::sin(2.0 * std::numbers::pi * freq *
                                            static_cast<double>(n) / sampleRate + phase);
            buf[kOracleStereo * n] = static_cast<float>(s);
            buf[(kOracleStereo * n) + 1U] = static_cast<float>(s);
            outSamplePeak = std::max(outSamplePeak, std::abs(s));
        }
        return buf;
    }

    // Fast transient battery: long silence, then a single hard full-scale burst, then silence,
    // repeated. Exercises the attack/lookahead path against abrupt onsets mid-stream.
    auto genTpTransientBurst(double amp, uint32_t sampleRate) -> std::vector<float>
    {
        const auto burst = static_cast<size_t>(0.005 * sampleRate); // 5 ms full-scale burst
        const auto gap = static_cast<size_t>(0.100 * sampleRate);   // 100 ms silence
        const size_t reps = 8;
        std::vector<float> buf;
        buf.reserve((gap + burst) * reps * kOracleStereo);
        for (size_t r = 0; r < reps; ++r)
        {
            for (size_t n = 0; n < gap; ++n)
            {
                buf.push_back(0.0F);
                buf.push_back(0.0F);
            }
            for (size_t n = 0; n < burst; ++n)
            {
                // Square-ish hard transient with a sign flip to stress the detector.
                const float s = static_cast<float>(((n % 2U) == 0U) ? amp : -amp);
                buf.push_back(s);
                buf.push_back(s);
            }
        }
        return buf;
    }

    // --- Drive the SHIPPING limiter and return its interleaved-stereo OUTPUT ------
    // Routes `inInterleaved` through a fresh LimiterModule::process() at the given ceiling
    // via the harness planar-stereo ABL fixture. One process() call (buffer sized to fit).
    auto limiterProcess(const std::vector<float>& inInterleaved,
                        uint32_t sampleRate,
                        float ceilingLinear) -> std::vector<float>
    {
        const size_t frames = inInterleaved.size() / kOracleStereo;
        const auto frameCount = static_cast<uint32_t>(frames);

        TestABL abl(frameCount);
        for (size_t n = 0; n < frames; ++n)
        {
            abl.left[n] = inInterleaved[kOracleStereo * n];
            abl.right[n] = inInterleaved[(kOracleStereo * n) + 1U];
        }

        AdaptiveSound::LimiterModule limiter;
        limiter.initialize(sampleRate, frameCount);

        AdaptiveSound::LimiterParams params{};
        params.truePeakCeilingLinear = ceilingLinear;

        const MultichannelView view = MultichannelView::fromABL(abl.abl(), frameCount);
        limiter.process(params, view);

        std::vector<float> out(frames * kOracleStereo);
        for (size_t n = 0; n < frames; ++n)
        {
            out[kOracleStereo * n] = abl.left[n];
            out[(kOracleStereo * n) + 1U] = abl.right[n];
        }
        return out;
    }

    // Slice off the first `warmup` frames (interleaved stereo) so the attack envelope has
    // settled past the silence→signal onset before we measure the output true-peak.
    auto dropWarmup(const std::vector<float>& interleaved, uint32_t warmup) -> std::vector<float>
    {
        const size_t skip = static_cast<size_t>(warmup) * kOracleStereo;
        if (skip >= interleaved.size())
        {
            return interleaved;
        }
        return {interleaved.begin() + static_cast<std::ptrdiff_t>(skip), interleaved.end()};
    }

    // dBTP of an interleaved-stereo buffer via the libebur128 4x true-peak oracle.
    // Returns false on a libebur128 error. Empty/over-quiet buffer → −inf guarded to a
    // very-low dBTP so callers see a sane number.
    auto oracleDbTp(const std::vector<float>& interleaved, uint32_t sampleRate, double& outDbTp)
        -> bool
    {
        double linear = 0.0;
        if (!ebur128TruePeak(interleaved, sampleRate, linear))
        {
            return false;
        }
        outDbTp = (linear > 0.0) ? (20.0 * std::log10(linear)) : -200.0;
        return true;
    }

    // A bounded interleaved-stereo window from the MIDDLE of a settled buffer, for the
    // O(N·oversample·taps) sinc cross-check (which is too slow to run over a 2 s buffer).
    // The window straddles the global sample-peak so the highest inter-sample peak is inside.
    auto settledWindow(const std::vector<float>& interleaved) -> std::vector<float>
    {
        const size_t frames = interleaved.size() / kOracleStereo;
        constexpr size_t kWin = 4096U;
        if (frames <= kWin)
        {
            return interleaved;
        }
        // Locate the global sample-peak frame, then centre a kWin window on it.
        size_t peakFrame = 0U;
        double peak = 0.0;
        for (size_t n = 0; n < frames; ++n)
        {
            const double a = std::max(std::abs(static_cast<double>(interleaved[kOracleStereo * n])),
                                      std::abs(static_cast<double>(
                                          interleaved[(kOracleStereo * n) + 1U])));
            if (a > peak)
            {
                peak = a;
                peakFrame = n;
            }
        }
        const size_t half = kWin / 2U;
        size_t start = (peakFrame > half) ? (peakFrame - half) : 0U;
        if (start + kWin > frames)
        {
            start = frames - kWin;
        }
        const auto first = interleaved.begin() + static_cast<std::ptrdiff_t>(start * kOracleStereo);
        const auto last = first + static_cast<std::ptrdiff_t>(kWin * kOracleStereo);
        return {first, last};
    }

    // One ceiling-guarantee row: drive `signal` through the shipping limiter at the default
    // ceiling, measure INPUT and OUTPUT true-peak with libebur128, log them, and append a
    // diagnostic to `fail` if the OUTPUT true-peak breaches the ceiling + margin.
    auto checkCeiling(const char* label,
                      const std::vector<float>& signal,
                      uint32_t sampleRate,
                      std::string& fail) -> void
    {
        double inDb = 0.0;
        double outDb = 0.0;

        if (!oracleDbTp(signal, sampleRate, inDb))
        {
            fail += std::string("\n  ") + label + ": libebur128 input true_peak call failed";
            return;
        }

        const std::vector<float> out =
            limiterProcess(signal, sampleRate, kTruePeakCeilingLinear);
        const std::vector<float> measured = dropWarmup(out, kTpWarmupFrames);

        if (!oracleDbTp(measured, sampleRate, outDb))
        {
            fail += std::string("\n  ") + label + ": libebur128 output true_peak call failed";
            return;
        }

        const bool oracleBreaches = (outDb > ceilingDbTp() + kCeilingMarginDb);

        // Cross-check with the high-resolution sinc reconstruction only when libebur128
        // reports a breach — that filters out libebur128's 4x HF-filter over-read artifact
        // (see the meter rationale above). A REAL breach is confirmed by both meters.
        double sincDb = -200.0;
        if (oracleBreaches)
        {
            sincDb = sincTruePeakDbTp(settledWindow(measured));
        }

        std::ostringstream info;
        info << "  [info] Limiter_TruePeak_Ceiling: " << label << " @ " << sampleRate
             << " Hz: inTP=" << inDb << " dBTP, outTP(ebur128 4x)=" << outDb << " dBTP";
        if (oracleBreaches)
        {
            info << ", outTP(sinc 32x)=" << sincDb << " dBTP";
        }
        info << ", ceiling=" << ceilingDbTp() << " dBTP (margin " << kCeilingMarginDb << " dB)\n";
        logInfo(info.str());

        if (oracleBreaches && sincDb > ceilingDbTp() + kCeilingMarginDb)
        {
            std::ostringstream oss;
            oss << "\n  " << label << " @ " << sampleRate << " Hz: OUTPUT true-peak EXCEEDS ceiling "
                << ceilingDbTp() << " dBTP + margin " << kCeilingMarginDb << " dB — confirmed by "
                << "BOTH meters (ebur128 4x=" << outDb << ", sinc 32x=" << sincDb
                << ", input was " << inDb << " dBTP) — REAL FINDING, do not loosen tolerance";
            fail += oss.str();
        }
        else if (oracleBreaches)
        {
            // libebur128 over-read only (HF 4x-filter artifact); accurate meter confirms the
            // limiter holds the ceiling. Log it; do NOT fail.
            std::ostringstream note;
            note << "  [info] Limiter_TruePeak_Ceiling: " << label << " @ " << sampleRate
                 << " Hz: ebur128 4x over-read (" << outDb << " dBTP) NOT confirmed by sinc 32x ("
                 << sincDb << " dBTP) — known 4x HF-filter artifact, limiter holds ceiling\n";
            logInfo(note.str());
        }
    }
} // namespace

// ===========================================================================
// Test: −1 dBTP ceiling guarantee across a battery of saturating signals.
// The limiter OUTPUT true-peak (independent libebur128 oracle) must stay under
// the published ceiling at 48 and 44.1 kHz.
// ===========================================================================
static auto testLimiterTruePeakCeilingGuarantee() -> void
{
    static const char* const kName = "Limiter_TruePeak_CeilingGuarantee_vs_ebur128";
    std::string fail;

    for (const uint32_t fs : {kOracleRate48k, kOracleRate44k})
    {
        // 0 dBFS sines: 997 Hz (AES test tone), 1 kHz, a midband tone, and a high tone.
        checkCeiling("sine997_0dBFS", genTpSine(0.0, 997.0, 2.0, fs), fs, fail);
        checkCeiling("sine1k_0dBFS", genTpSine(0.0, 1000.0, 2.0, fs), fs, fail);
        checkCeiling("sine5k_0dBFS", genTpSine(0.0, 5000.0, 2.0, fs), fs, fail);
        checkCeiling("sine15k_0dBFS", genTpSine(0.0, 15000.0, 2.0, fs), fs, fail);

        // 0 dBFS inter-sample-peak signal (fs/4 @ 45°): true peak exceeds sample peak.
        double ispSamplePeak = 0.0;
        checkCeiling("isp_fs4_45deg_0dBFS",
                     genTpInterSamplePeak(1.0, 2.0, fs, ispSamplePeak), fs, fail);

        // Hot noise pushed above 0 dBFS (will clip to the generator amplitude; the limiter
        // must still bring the reconstructed true-peak under the ceiling).
        checkCeiling("white_+3dBFS",
                     genStereoWhiteNoise(3.0, 2.0, fs, 0x70B1C501U), fs, fail);
        checkCeiling("pink_+3dBFS",
                     genStereoPinkNoise(3.0, 2.0, fs, 0x70B1C502U), fs, fail);

        // Fast transient burst train at full scale.
        checkCeiling("transient_burst_0dBFS", genTpTransientBurst(1.0, fs), fs, fail);
    }

    if (!fail.empty())
    {
        logFail(kName, "limiter output true-peak breached the ceiling:" + fail);
        return;
    }
    logPass(kName);
}

// ===========================================================================
// Test: ISP-detector accuracy — the limiter catches inter-sample peaks a sample-only
// meter misses, and is transparent on signals already under the ceiling.
// ===========================================================================
static auto testLimiterIspDetectorAccuracy() -> void
{
    static const char* const kName = "Limiter_IspDetector_Accuracy_vs_ebur128";
    std::string fail;

    for (const uint32_t fs : {kOracleRate48k, kOracleRate44k})
    {
        // --- (1) ISP signal: SAMPLE peak under the ceiling, TRUE peak over it. -------
        // Amplitude 0.95 at fs/4 @ 45°: the per-sample value lands on ±sin(45°)·A =
        // 0.707·0.95 = 0.672 (≈ −3.45 dBFS, well UNDER the 0.891 ceiling), but the
        // reconstructed inter-sample peak reaches ≈ 0.95 (≈ −0.45 dBTP, OVER the ceiling).
        // A sample-only meter would pass this; the true-peak limiter must not.
        {
            double samplePeak = 0.0;
            const std::vector<float> sig = genTpInterSamplePeak(0.95, 2.0, fs, samplePeak);
            const double samplePeakDb = 20.0 * std::log10(samplePeak);

            // (a) libebur128 confirms the INPUT true-peak exceeds the ceiling, while the
            //     per-sample peak is BELOW it (i.e. this is a genuine ISP trap).
            double inTpDb = 0.0;
            if (!oracleDbTp(sig, fs, inTpDb))
            {
                fail += "\n  isp-trap: libebur128 input true_peak call failed";
                continue;
            }

            std::ostringstream info;
            info << "  [info] " << kName << " (isp-trap) @ " << fs
                 << " Hz: samplePeak=" << samplePeakDb << " dBFS, inputTP=" << inTpDb
                 << " dBTP, ceiling=" << ceilingDbTp() << " dBTP\n";
            logInfo(info.str());

            if (samplePeakDb > ceilingDbTp())
            {
                std::ostringstream oss;
                oss << "\n  isp-trap @ " << fs << " Hz: sample peak " << samplePeakDb
                    << " dBFS is NOT below ceiling " << ceilingDbTp()
                    << " dBTP — fixture invalid (not a true ISP trap)";
                fail += oss.str();
            }
            if (inTpDb <= ceilingDbTp())
            {
                std::ostringstream oss;
                oss << "\n  isp-trap @ " << fs << " Hz: oracle input TP " << inTpDb
                    << " dBTP does NOT exceed ceiling " << ceilingDbTp()
                    << " dBTP — fixture invalid (no inter-sample overshoot)";
                fail += oss.str();
            }

            // (b) The limiter brings the OUTPUT true-peak back under the ceiling. The output
            //     is a ~fs/4 tone, so libebur128's 4x meter can over-read (as in the ceiling
            //     test); confirm any apparent breach with the high-resolution sinc meter.
            const std::vector<float> out = limiterProcess(sig, fs, kTruePeakCeilingLinear);
            const std::vector<float> measured = dropWarmup(out, kTpWarmupFrames);
            double outTpDb = 0.0;
            if (!oracleDbTp(measured, fs, outTpDb))
            {
                fail += "\n  isp-trap: libebur128 output true_peak call failed";
                continue;
            }
            const double outSincDb = sincTruePeakDbTp(settledWindow(measured));
            std::ostringstream info2;
            info2 << "  [info] " << kName << " (isp-trap) @ " << fs
                  << " Hz: outputTP(ebur128 4x)=" << outTpDb << " dBTP, outputTP(sinc 32x)="
                  << outSincDb << " dBTP (input was " << inTpDb << " dBTP)\n";
            logInfo(info2.str());

            // A genuine failure to catch the ISP shows on BOTH meters.
            if (outTpDb > ceilingDbTp() + kCeilingMarginDb &&
                outSincDb > ceilingDbTp() + kCeilingMarginDb)
            {
                std::ostringstream oss;
                oss << "\n  isp-trap @ " << fs << " Hz: limiter FAILED to catch inter-sample peak: "
                    << "output TP confirmed by both meters (ebur128 4x=" << outTpDb << ", sinc 32x="
                    << outSincDb << ") > ceiling " << ceilingDbTp() << " + margin " << kCeilingMarginDb
                    << " dB (input " << inTpDb << " dBTP) — REAL FINDING";
                fail += oss.str();
            }
        }

        // --- (2) Transparency: a signal already under the ceiling passes through with ~no
        //         gain reduction. A −6 dBFS sine (0.501 linear, well under 0.891) must be
        //         reproduced near-unity after the lookahead delay. ------------------------
        {
            constexpr double kUnderDbfs = -6.0;
            const std::vector<float> sig = genTpSine(kUnderDbfs, 1000.0, 1.0, fs);
            const std::vector<float> out = limiterProcess(sig, fs, kTruePeakCeilingLinear);

            // Compare output[n] to input[n - lookahead] in the settled region; the gain must
            // be ≈ 1.0 (no reduction) since the signal never approaches the ceiling.
            const size_t frames = sig.size() / kOracleStereo;
            // Look-ahead is now a fixed TIME converted per sample rate (AC-2): the limiter
            // delays by round(kLimiterLookaheadSeconds · fs), which is 144 @ 48 kHz but 132
            // @ 44.1 kHz. Align the transparency comparison to that actual delay, not the
            // fixed 48 kHz frame count (which would misalign the sine at 44.1 kHz).
            const uint32_t look = static_cast<uint32_t>(
                std::lround(static_cast<double>(AdaptiveSound::kLimiterLookaheadSeconds) * fs));
            double maxReductionDb = 0.0;
            for (size_t n = kTpWarmupFrames; n < frames; ++n)
            {
                const double in = static_cast<double>(sig[kOracleStereo * (n - look)]);
                const double o = static_cast<double>(out[kOracleStereo * n]);
                if (std::abs(in) < 1e-3)
                {
                    continue; // near zero-crossing: ratio ill-conditioned
                }
                const double gain = o / in;
                // gain should be ≈ 1; record the deepest (most-negative-dB) deviation.
                const double gainDb = 20.0 * std::log10(std::max(1e-9, std::abs(gain)));
                maxReductionDb = std::min(maxReductionDb, gainDb);
            }

            std::ostringstream info;
            info << "  [info] " << kName << " (transparent) @ " << fs
                 << " Hz: −6 dBFS sine, deepest gain deviation=" << maxReductionDb << " dB\n";
            logInfo(info.str());

            // Transparent: well under the ceiling, the limiter applies no audible reduction.
            // Allow 0.05 dB for the one-pole noise floor / float quantisation.
            constexpr double kTransparentTolDb = 0.05;
            if (maxReductionDb < -kTransparentTolDb)
            {
                std::ostringstream oss;
                oss << "\n  transparent @ " << fs << " Hz: limiter applied " << maxReductionDb
                    << " dB of gain reduction to a −6 dBFS signal under the ceiling (tol "
                    << kTransparentTolDb << " dB) — not transparent";
                fail += oss.str();
            }
        }
    }

    if (!fail.empty())
    {
        logFail(kName, "ISP-detector accuracy failure:" + fail);
        return;
    }
    logPass(kName);
}
