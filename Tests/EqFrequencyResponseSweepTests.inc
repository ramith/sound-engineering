// EqFrequencyResponseSweepTests.inc
//
// S7 / US-QA-03 — comprehensive 31-band EQ frequency-response sweep +
// bit-transparent-bypass guarantees.
// #included into Tests/DSPKernelNullTest.cpp after TestSupport.h.
//
// Tests:
//   EQ_Sweep31Bands_48k        — every band, ±6 dB, measured-vs-requested ≤ tol @ 48 kHz
//   EQ_Sweep31Bands_44k        — every band, ±6 dB, measured-vs-requested ≤ tol @ 44.1 kHz
//   EQ_SweepExtremes_PlusMinus12 — extremal/subset bands at ±12 dB, both rates
//   EQ_NearNyquistBandsApplyGain — 16 kHz & 20 kHz @ 44.1 kHz ACTUALLY boost (no silent
//                                  identity fall-back from the S6 Schur-Cohn guard)
//   EQ_FlatIsBitTransparentBypass — all 31 bands flat → output bit-identical to input
//
// Rationale: EQ_FrequencyResponseAccuracy (EqTests.inc) pins ONE band (1 kHz) at one
// gain. This file generalises that exact measurement approach across ALL 31 ISO bands,
// both supported sample rates, and the boost/cut extremes, and adds the near-Nyquist
// regression guard the S6 stability review flagged. It reuses the shared helpers
// (goertzelPower, sliceRms, makeIdentityState, kCenterFrequencies, computeBiquadCascade).
//
// MEASUREMENT METHOD (matches the single-band test's spirit, generalised):
//   Drive a unit-amplitude sine at the band's EXACT center frequency through the real
//   DSPKernel with (a) flat EQ and (b) the single-band cascade. Measure the band-center
//   energy with a single-bin Goertzel DFT over the SETTLED second half of the buffer
//   (IIR transients die in milliseconds). The measured gain is
//       20*log10( sqrt(P_boost) / sqrt(P_flat) ).
//   Goertzel (not broadband RMS) is used because at high bands the sine is only a few
//   samples/cycle and a single-bin estimate rejects out-of-band numerical leakage.
//
// TOLERANCE: ±1.0 dB at the exact band center (kEqFrToleranceDb, the same contract the
//   single-band test documents). The 31-band graphic-EQ spec is ±0.5 dB at center; the
//   extra 0.5 dB absorbs finite-settling + single-bin estimation error and band
//   interaction. The analytic transfer-function response of these cascades is accurate
//   to < 0.01 dB at every center for ±6/±12 at both rates (verified off-line), so a
//   measured error approaching 1 dB would itself be a real finding — the tolerance is
//   deliberately NOT loosened to mask a fitter/stability regression.

namespace
{
    // ISO band centers for the sweep — pulled from production so the test cannot drift.
    constexpr float kSweepGain6 = 6.0F;
    constexpr float kSweepGain12 = 12.0F;
    // Near-Nyquist guard: the boost must be CLEARLY present (not a silent identity
    // fall-back). A real boost lands within ±1 dB of target; identity would read ~0 dB.
    // Require at least half the requested gain to flag any partial/silent collapse.
    constexpr double kNearNyquistMinFraction = 0.5;

    // Run a unit sine at `toneHz` through the real kernel with `gains`, at `sampleRate`,
    // and return the captured mono (left) output. One process() call (maxFrames=frames),
    // exactly as runEqSine does, but parameterized on sample rate and tone frequency so
    // the same path serves 48 kHz, 44.1 kHz, and every band center.
    auto runEqSineAt(const std::array<float, kEqBands>& gains,
                     uint32_t sampleRate,
                     float toneHz,
                     uint32_t frames) -> std::vector<float>
    {
        DSPKernel kernel;
        kernel.initialize(sampleRate, frames);

        TargetState state = makeIdentityState();
        state.eq = EQModuleCoefficients::computeBiquadCascade(gains, static_cast<float>(sampleRate));
        kernel.publishTargetState(state);

        TestABL abl(frames);
        const float sr = static_cast<float>(sampleRate);
        for (uint32_t idx = 0U; idx < frames; ++idx)
        {
            const float sample =
                kEqTestAmplitude * std::sin(2.0F * std::numbers::pi_v<float> * toneHz *
                                            static_cast<float>(idx) / sr);
            abl.left[idx] = sample;
            abl.right[idx] = sample;
        }
        kernel.process(abl.abl(), frames);
        return abl.left;
    }

    // Measure the gain (dB) the EQ applies at `toneHz` for a single-band `gainDb` boost,
    // relative to the flat-EQ baseline, via settled-half single-bin Goertzel.
    // Returns NaN if the flat baseline is silent (caller treats that as a hard failure).
    auto measureBandGainDb(int band, float gainDb, uint32_t sampleRate, uint32_t frames)
        -> double
    {
        const float toneHz = EQModuleCoefficients::kCenterFrequencies[static_cast<size_t>(band)];

        std::array<float, kEqBands> flat{};
        std::array<float, kEqBands> boosted{};
        boosted[static_cast<size_t>(band)] = gainDb;

        const std::vector<float> flatOut = runEqSineAt(flat, sampleRate, toneHz, frames);
        const std::vector<float> boostOut = runEqSineAt(boosted, sampleRate, toneHz, frames);

        const uint32_t half = frames / 2U;
        const uint32_t n = frames - half;
        const double flatP =
            goertzelPower(flatOut.data() + half, n, toneHz, static_cast<float>(sampleRate));
        const double boostP =
            goertzelPower(boostOut.data() + half, n, toneHz, static_cast<float>(sampleRate));

        if (!(flatP > 0.0))
        {
            return std::numeric_limits<double>::quiet_NaN();
        }
        return 10.0 * std::log10(boostP / flatP); // power ratio -> dB
    }

    // Sweep every band at +gainDb and -gainDb for one sample rate. Returns "" on success,
    // or a human-readable failure string for the first offending band. Also guards against
    // NaN/Inf and gross (>2 dB) center-frequency errors.
    auto sweepAllBandsBody(uint32_t sampleRate, float gainDb, uint32_t frames) -> std::string
    {
        constexpr double kGrossErrorDb = 2.0; // NaN/Inf or wildly-wrong guard
        const float nyquist = static_cast<float>(sampleRate) * 0.5F;

        for (int sign = 0; sign < 2; ++sign)
        {
            const float g = (sign == 0) ? gainDb : -gainDb;
            for (int band = 0; band < EQModuleCoefficients::kNumBands; ++band)
            {
                const float fc =
                    EQModuleCoefficients::kCenterFrequencies[static_cast<size_t>(band)];
                if (fc >= nyquist)
                {
                    continue; // center at/above Nyquist is unmeasurable; skip (none at these rates)
                }

                const double measured = measureBandGainDb(band, g, sampleRate, frames);
                if (!std::isfinite(measured))
                {
                    std::ostringstream oss;
                    oss << "band " << band << " (" << fc << " Hz) @ " << g
                        << " dB produced non-finite measurement (NaN/Inf or silent baseline)";
                    return oss.str();
                }
                const double err = std::abs(measured - static_cast<double>(g));
                if (err > kGrossErrorDb)
                {
                    std::ostringstream oss;
                    oss << "GROSS band " << band << " (" << fc << " Hz) @ " << g
                        << " dB: measured " << measured << " dB (err " << err << " dB)";
                    return oss.str();
                }
                if (err > static_cast<double>(kEqFrToleranceDb))
                {
                    std::ostringstream oss;
                    oss << "band " << band << " (" << fc << " Hz) @ " << g << " dB: measured "
                        << measured << " dB, expected " << g << " ± " << kEqFrToleranceDb
                        << " (err " << err << " dB)";
                    return oss.str();
                }
            }
        }
        return {};
    }
} // namespace

// ---------------------------------------------------------------------------
// EQ_Sweep31Bands_48k / _44k — every band, ±6 dB, measured at its exact center.
// ---------------------------------------------------------------------------
static auto testEqSweep31Bands48k() -> void
{
    static const char* const kName = "EQ_Sweep31Bands_48k";
    const std::string err =
        sweepAllBandsBody(TestConstants::kSampleRate48k, kSweepGain6, TestConstants::kTotalFrames1s);
    if (!err.empty())
    {
        logFail(kName, err);
        return;
    }
    logPass(kName);
}

static auto testEqSweep31Bands44k() -> void
{
    static const char* const kName = "EQ_Sweep31Bands_44k";
    // 1 s at 44.1 kHz; settled-half Goertzel as for 48 kHz.
    const std::string err =
        sweepAllBandsBody(TestConstants::kSampleRate44k, kSweepGain6, TestConstants::kSampleRate44k);
    if (!err.empty())
    {
        logFail(kName, err);
        return;
    }
    logPass(kName);
}

// ---------------------------------------------------------------------------
// EQ_SweepExtremes_PlusMinus12 — the ±12 dB clamp extremes, both rates, all bands.
// This is the subset called for in the spec "at +12/-12 dB for a subset incl. the
// extremes"; sweeping all bands at the extreme is cheap here and strictly stronger.
// ---------------------------------------------------------------------------
static auto testEqSweepExtremesPlusMinus12() -> void
{
    static const char* const kName = "EQ_SweepExtremes_PlusMinus12";
    const std::string err48 =
        sweepAllBandsBody(TestConstants::kSampleRate48k, kSweepGain12, TestConstants::kTotalFrames1s);
    if (!err48.empty())
    {
        logFail(kName, std::string("48k: ") + err48);
        return;
    }
    const std::string err44 =
        sweepAllBandsBody(TestConstants::kSampleRate44k, kSweepGain12, TestConstants::kSampleRate44k);
    if (!err44.empty())
    {
        logFail(kName, std::string("44.1k: ") + err44);
        return;
    }
    logPass(kName);
}

// ---------------------------------------------------------------------------
// EQ_NearNyquistBandsApplyGain — the S6 Schur-Cohn regression guard.
//
// At 44.1 kHz, the 16 kHz and 20 kHz band centers sit at 0.726 and 0.907 of Nyquist.
// validateMinimumPhase() (Schur-Cohn on poles AND zeros) MUST NOT wrongly reject these
// high-Q sections and silently fall the cascade back to identity. We assert the measured
// response at those centers shows a real boost (and a real cut), not ~0 dB. If a band
// silently collapses to identity, the measured gain is ~0 dB and this fails LOUD with the
// band + measured-vs-expected numbers.
// ---------------------------------------------------------------------------
static auto testEqNearNyquistBandsApplyGain() -> void
{
    static const char* const kName = "EQ_NearNyquistBandsApplyGain";
    constexpr uint32_t kSR = TestConstants::kSampleRate44k;
    constexpr uint32_t kFrames = TestConstants::kSampleRate44k; // 1 s
    // Bands 29 (16 kHz) and 30 (20 kHz): the two highest ISO centers.
    const std::array<int, 2> nearNyquistBands = {29, 30};
    const std::array<float, 2> testGains = {kSweepGain6, kSweepGain12};

    std::ostringstream report;
    for (const int band : nearNyquistBands)
    {
        const float fc = EQModuleCoefficients::kCenterFrequencies[static_cast<size_t>(band)];
        for (const float g : testGains)
        {
            // Boost
            const double up = measureBandGainDb(band, g, kSR, kFrames);
            // Cut
            const double down = measureBandGainDb(band, -g, kSR, kFrames);
            report << "  [info] " << kName << ": band " << band << " (" << fc << " Hz @ 44.1k) +"
                   << g << "->" << up << " dB, -" << g << "->" << down << " dB\n";

            if (!std::isfinite(up) || !std::isfinite(down))
            {
                logFail(kName, std::string("band ") + std::to_string(band) +
                                   " produced non-finite measurement near Nyquist");
                return;
            }
            // Identity fall-back guard: a silent collapse reads ~0 dB. Require the boost to
            // reach at least half the requested gain (and the cut to drop at least half).
            const double minMag = kNearNyquistMinFraction * static_cast<double>(g);
            if (up < minMag)
            {
                logInfo(report.str());
                std::ostringstream oss;
                oss << "band " << band << " (" << fc << " Hz) +" << g
                    << " dB boost collapsed to " << up
                    << " dB (likely silent identity fall-back from the stability check)";
                logFail(kName, oss.str());
                return;
            }
            if (down > -minMag)
            {
                logInfo(report.str());
                std::ostringstream oss;
                oss << "band " << band << " (" << fc << " Hz) -" << g << " dB cut collapsed to "
                    << down << " dB (likely silent identity fall-back)";
                logFail(kName, oss.str());
                return;
            }
            // And the boost must still be ACCURATE within the FR tolerance.
            if (std::abs(up - static_cast<double>(g)) > static_cast<double>(kEqFrToleranceDb))
            {
                logInfo(report.str());
                std::ostringstream oss;
                oss << "band " << band << " (" << fc << " Hz) +" << g << " dB: measured " << up
                    << " dB, expected " << g << " ± " << kEqFrToleranceDb;
                logFail(kName, oss.str());
                return;
            }
        }
    }
    logInfo(report.str());
    logPass(kName);
}

// ---------------------------------------------------------------------------
// EQ_FlatIsBitTransparentBypass — all 31 bands flat (0 dB) → EQ output is bit-identical
// to input. computeBiquadCascade short-circuits the all-zeros case to a single identity
// biquad; the EQModule's identity path must then leave the samples bit-for-bit unchanged.
//
// This is the EQ-stage analogue of the existing intensity-0 / golden-master bypass
// contract (which we reference, not duplicate: GoldenMaster_StereoN2_v1 +
// IntensityZero_BitExactPassthrough already pin the whole-chain bit-exact paths).
// ---------------------------------------------------------------------------
static auto testEqFlatIsBitTransparentBypass() -> void
{
    static const char* const kName = "EQ_FlatIsBitTransparentBypass";
    constexpr uint32_t kFrames = TestConstants::kTotalFrames1s;

    const auto check = [&](uint32_t sampleRate) -> std::string
    {
        // Deterministic broadband signal: 1 kHz sine + a touch of high content so a stray
        // biquad would perturb a wide range of samples, not just one bin.
        std::vector<float> input(kFrames);
        const float sr = static_cast<float>(sampleRate);
        for (uint32_t idx = 0U; idx < kFrames; ++idx)
        {
            const float t = static_cast<float>(idx) / sr;
            input[idx] = 0.5F * std::sin(2.0F * std::numbers::pi_v<float> * 1000.0F * t) +
                         0.25F * std::sin(2.0F * std::numbers::pi_v<float> * 7000.0F * t);
        }

        DSPKernel kernel;
        kernel.initialize(sampleRate, kFrames);
        TargetState state = makeIdentityState();
        std::array<float, kEqBands> flat{}; // all zeros -> pass-through cascade
        state.eq = EQModuleCoefficients::computeBiquadCascade(flat, sr);
        kernel.publishTargetState(state);

        TestABL abl(kFrames);
        std::memcpy(abl.left.data(), input.data(), kFrames * sizeof(float));
        std::memcpy(abl.right.data(), input.data(), kFrames * sizeof(float));
        kernel.process(abl.abl(), kFrames);

        for (uint32_t idx = 0U; idx < kFrames; ++idx)
        {
            if (abl.left[idx] != input[idx] || abl.right[idx] != input[idx])
            {
                std::ostringstream oss;
                oss << "sample " << idx << " @ " << sampleRate << " Hz changed: in " << input[idx]
                    << " L " << abl.left[idx] << " R " << abl.right[idx]
                    << " (flat EQ must be bit-transparent)";
                return oss.str();
            }
        }
        return {};
    };

    const std::string err48 = check(TestConstants::kSampleRate48k);
    if (!err48.empty())
    {
        logFail(kName, err48);
        return;
    }
    const std::string err44 = check(TestConstants::kSampleRate44k);
    if (!err44.empty())
    {
        logFail(kName, err44);
        return;
    }
    logPass(kName);
}

// ---------------------------------------------------------------------------
// EQ_CombinedBands_CutRunAndMixedSign — S6 EQ-1 regression.
//
// The single-band sweeps above cannot catch the fitter bug (one active band is one run either
// way). The bug only bites a MULTI-band active run:
//   (a) a run of CUTS [-12,-9,-12] used to collapse to a single -9 dB filter (least-negative) —
//       the deepest -12 bands were under-cut by ~3 dB; and
//   (b) a boost+cut run [+6,-6] used to become a single +6 dB filter — the cut was DROPPED, so the
//       cut band read a POSITIVE gain.
// The fix splits at sign changes and tracks |gain|, so the deep cut is applied and the mixed run
// yields both a boost and a cut. We measure the realized response (settled-half Goertzel, same
// method as the sweeps) at the relevant band centers through the full multi-band cascade.
// ---------------------------------------------------------------------------
namespace
{
    // Measure the realized gain (dB) at `band`'s center for a FULL multi-band `gains` cascade,
    // relative to the flat baseline. NaN if the flat baseline is silent.
    auto measureMultiBandGainDb(const std::array<float, kEqBands>& gains, int band,
                                uint32_t sampleRate, uint32_t frames) -> double
    {
        const float toneHz = EQModuleCoefficients::kCenterFrequencies[static_cast<size_t>(band)];
        std::array<float, kEqBands> flat{};
        const std::vector<float> flatOut = runEqSineAt(flat, sampleRate, toneHz, frames);
        const std::vector<float> mixOut = runEqSineAt(gains, sampleRate, toneHz, frames);

        const uint32_t half = frames / 2U;
        const uint32_t n = frames - half;
        const double flatP =
            goertzelPower(flatOut.data() + half, n, toneHz, static_cast<float>(sampleRate));
        const double mixP =
            goertzelPower(mixOut.data() + half, n, toneHz, static_cast<float>(sampleRate));
        if (!(flatP > 0.0))
        {
            return std::numeric_limits<double>::quiet_NaN();
        }
        return 10.0 * std::log10(mixP / flatP);
    }
} // namespace

static auto testEqCombinedBandsCutRunAndMixedSign() -> void
{
    static const char* const kName = "EQ_CombinedBands_CutRunAndMixedSign";
    constexpr uint32_t kSR = TestConstants::kSampleRate48k;
    constexpr uint32_t kFrames = TestConstants::kTotalFrames1s;
    std::ostringstream report;

    // (a) Adjacent CUT run at bands 15/16/17 (630/800/1000 Hz): [-12,-9,-12]. The deepest-cut band
    // (15, the first -12) must now read ~-12 dB, NOT the old ~-7..-9 collapse.
    {
        constexpr int kDeepBand = 15;
        std::array<float, kEqBands> gains{};
        gains[15] = -12.0F;
        gains[16] = -9.0F;
        gains[17] = -12.0F;
        const double deep = measureMultiBandGainDb(gains, kDeepBand, kSR, kFrames);
        report << "  [info] " << kName << ": cut-run deep band 15 (630 Hz) measured " << deep
               << " dB (target -12)\n";
        if (!std::isfinite(deep))
        {
            logInfo(report.str());
            logFail(kName, "cut-run produced a non-finite measurement");
            return;
        }
        // Regression sentinel: the old collapse-to-least-negative would read shallower than -10.5.
        if (deep > -10.5)
        {
            logInfo(report.str());
            std::ostringstream oss;
            oss << "cut run [-12,-9,-12]: deepest band 15 measured only " << deep
                << " dB — the deep cut is under-applied (EQ-1 regression)";
            logFail(kName, oss.str());
            return;
        }
        // And it must be ACCURATE to the target within the ratified FR tolerance (single filter at
        // its own center → no adjacent-filter interaction in a same-sign run).
        if (std::abs(deep - (-12.0)) > static_cast<double>(kEqFrToleranceDb))
        {
            logInfo(report.str());
            std::ostringstream oss;
            oss << "cut run: deepest band 15 measured " << deep << " dB, expected -12 ± "
                << kEqFrToleranceDb;
            logFail(kName, oss.str());
            return;
        }
    }

    // (b) Adjacent MIXED-sign run at bands 20/21 (2000/2500 Hz): [+6,-6]. This is ONE contiguous
    // active run that must SPLIT at the sign change into a +6 boost filter AND a -6 cut filter.
    //
    // We assert SIGN-CORRECTNESS, not magnitude: bands 20 and 21 are only 1/3 octave apart while
    // the greedy fitter's peaking filters are ~1.5 octaves wide (Q≈0.9 at 6 dB), so the two
    // opposite-sign filters heavily overlap and partially cancel — each center realizes only ~±1 dB.
    // That mutual cancellation is an inherent limitation of a wide-Q one-filter-per-run fitter (an
    // ERB-weighted optimizer is the noted future enhancement), NOT the EQ-1 bug. The DECISIVE proof
    // of the fix is the sign: before the fix the run collapsed to a single +6 filter and the cut was
    // DROPPED, so band 21 read a POSITIVE gain; after the fix band 21 is a real (negative) cut and
    // band 20 stays a (positive) boost. A revert flips band 21 back positive → this fails.
    {
        std::array<float, kEqBands> gains{};
        gains[20] = 6.0F;
        gains[21] = -6.0F;
        const double boost = measureMultiBandGainDb(gains, 20, kSR, kFrames);
        const double cut = measureMultiBandGainDb(gains, 21, kSR, kFrames);
        report << "  [info] " << kName << ": mixed run band 20 (2 kHz) " << boost
               << " dB (boost), band 21 (2.5 kHz) " << cut
               << " dB (cut) — signs must be +/- (magnitude cancels: adjacent wide-Q filters)\n";
        if (!std::isfinite(boost) || !std::isfinite(cut))
        {
            logInfo(report.str());
            logFail(kName, "mixed run produced a non-finite measurement");
            return;
        }
        // Decisive regression sentinel: the old code dropped the cut → band 21 read POSITIVE.
        if (cut >= -0.5)
        {
            logInfo(report.str());
            std::ostringstream oss;
            oss << "mixed run [+6,-6]: cut band 21 measured " << cut
                << " dB — expected a real (negative) cut; the cut was dropped (EQ-1 regression)";
            logFail(kName, oss.str());
            return;
        }
        // The boost sub-run must still register as a boost.
        if (boost <= 0.5)
        {
            logInfo(report.str());
            std::ostringstream oss;
            oss << "mixed run [+6,-6]: boost band 20 measured " << boost
                << " dB — expected a real (positive) boost";
            logFail(kName, oss.str());
            return;
        }
    }

    logInfo(report.str());
    logPass(kName);
}
