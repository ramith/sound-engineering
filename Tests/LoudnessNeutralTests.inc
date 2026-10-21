// LoudnessNeutralTests.inc
//
// Sprint EQ, EQ1c part 2 — the loudness-neutral EQ gain, live: TrackLoudnessGain (the per-track
// state machine), the Realizer's loudness plumbing, the kernel's causal estimate
// (CausalLoudnessTap) and the whole chain against libebur128. #included into
// Tests/DSPKernelNullTest.cpp AFTER TrackLoudnessTests.inc (the programmes, profiles, curves and
// the libebur128 oracle) and EqEngineTests.inc (the engine helpers).
//
// Tests:
//   EQ_LoudnessNeutral_OnOff            — the full kernel at Intensity 0 with the track's profile:
//                                         EQ On vs Off integrated loudness (libebur128) on five
//                                         programme spectra × 8 curves: ≤ 0.15 dB (the pure
//                                         sub-bass 808 ≤ 0.25 dB: 400 ms blocks, part 1)
//   Loudness_ProfileLate                — the prior plays until the profile lands, then the gain
//                                         glides (τ 500 ms) to the track's own: no step
//   Loudness_GaplessSeamStep            — a continuous gapless seam steps ≤ 0.2 dB (a bigger
//                                         difference shares the group's gain); across silence
//                                         each track keeps its own; a late profile at a seam
//   Loudness_AnalysisFails_CausalFallback
//                                       — a failed analysis runs the causal estimate: the prior
//                                         for 3 s, then ≤ 1 dB/s toward the track's gain, and a
//                                         late profile ends it
//   Loudness_EditDebounce               — an edit publishes a decimated gain with the
//                                         coefficients; 150 ms idle later, the full one
//   TrackLoudnessGain_Rules             — the state machine's rules, unit by unit
//   Soak_DSPKernel_ZeroRtAlloc_CausalTap
//                                       — the causal tap allocates nothing on the RT thread
//   Realizer_LoudnessCost               — the worst profile (192 kHz, 6000 blocks): an edit's
//                                         gain and the full refresh against budgets (serial)
//   Limiter_EqOnlyCeiling               — EQ2, founder decision 29: the EQ-only path's ceiling is
//                                         −0.1 dBTP on wired/built-in outputs, −1 dBTP on
//                                         Bluetooth or an unknown link, −1 dBTP on every other
//                                         path; the output never above its ceiling

namespace
{
    constexpr uint64_t kLnTrackA = 0xA11CE5EEDULL;
    constexpr uint64_t kLnTrackB = 0xB0B5EEDULL;
    constexpr double kLnOnOffBoundDb = 0.15;
    constexpr double kLnSubBassBoundDb = 0.25;
    constexpr double kLnSeamStepDb = TrackLoudnessGain::kSeamStepDb;
    // A programme the On/Off gate logs but does not bound: the −9 LUFS loud master, whose EQ On
    // meets the EQ-only path's limiter (decision 29 accepted p90 0.57 / max 2.07 dB there).
    constexpr double kLnLoggedOnly = std::numeric_limits<double>::infinity();

    // A kernel + Realizer at the engine rate, Intensity 0 (P1: EQ → limiter, no normaliser), with
    // `curve` published On.
    struct LnEngine
    {
        std::shared_ptr<DSPKernel> kernel = std::make_shared<DSPKernel>();
        std::shared_ptr<AdaptiveSound::Realizer> realizer;

        // A wired (built-in) output unless told otherwise: the EQ-only ceiling is decision 29's.
        explicit LnEngine(const EqCurve& curve,
                          bool isOn = true,
                          uint32_t transport = kAudioDeviceTransportTypeBuiltIn)
        {
            kernel->initialize(static_cast<uint32_t>(kEngineFs), kEngineBlock);
            realizer = std::make_shared<AdaptiveSound::Realizer>(kernel, kEngineFs);
            realizer->setOutputTransport(transport);
            realizer->applyIntensity(0.0F);
            realizer->applyEq(engineEqIntent(curve, isOn));
            // Start rendering AT Intensity 0, as the app does (the AU allocates after the launch
            // publish): a move to 0 while rendering would glide the normaliser out over 2 s first
            // (decision 33).
            realizer->reinitializeKernel(static_cast<uint32_t>(kEngineFs), kEngineBlock);
        }
        ~LnEngine()
        {
            realizer->shutdown();
        }
        LnEngine(const LnEngine&) = delete;
        LnEngine(LnEngine&&) = delete;
        auto operator=(const LnEngine&) -> LnEngine& = delete;
        auto operator=(LnEngine&&) -> LnEngine& = delete;

        // The gain the EQ module applies right now (dB).
        [[nodiscard]] auto appliedGainDb() const -> double
        {
            return (kernel->eqModule() != nullptr) ? kernel->eqModule()->currentOutputGainDb()
                                                   : 0.0;
        }
    };

    // Render frames [start, start + frames) of `programme` through `kernel` in engine blocks,
    // calling `perBlock(firstFrame)` before each block. Returns the planar output.
    auto lnRender(DSPKernel& kernel,
                  const TlProgramme& programme,
                  size_t start,
                  size_t frames,
                  const std::function<void(size_t)>& perBlock = {}) -> TlChannels
    {
        const auto channels = static_cast<uint32_t>(programme.channels.size());
        TestABLN abl(channels, kEngineBlock);
        TlChannels output(channels, std::vector<float>(frames));
        for (size_t done = 0U; done < frames; done += kEngineBlock)
        {
            const auto block = static_cast<uint32_t>(std::min<size_t>(kEngineBlock, frames - done));
            if (perBlock)
            {
                perBlock(start + done);
            }
            for (uint32_t ch = 0U; ch < channels; ++ch)
            {
                const float* src = programme.channels[ch].data() + start + done;
                std::copy_n(src, block, abl.channels[ch].begin());
            }
            kernel.process(abl.abl(), block);
            for (uint32_t ch = 0U; ch < channels; ++ch)
            {
                std::copy_n(abl.channels[ch].begin(),
                            block,
                            output[ch].begin() + static_cast<std::ptrdiff_t>(done));
            }
        }
        return output;
    }

    // An RBJ 2nd-order Butterworth low-pass (Q = 1/√2), for the bass-heavy noise programmes.
    auto lnLowPass(double cutoffHz, double sampleRate) -> TlBiquad
    {
        const double w0 = 2.0 * std::numbers::pi * cutoffHz / sampleRate;
        const double alpha = std::sin(w0) / std::numbers::sqrt2;
        const double cosW0 = std::cos(w0);
        const double a0 = 1.0 + alpha;
        TlBiquad filter;
        filter.b0 = (1.0 - cosW0) / 2.0 / a0;
        filter.b1 = (1.0 - cosW0) / a0;
        filter.b2 = filter.b0;
        filter.a1 = -2.0 * cosW0 / a0;
        filter.a2 = (1.0 - alpha) / a0;
        return filter;
    }

    // Continuous stereo noise (pink, or pink low-passed at `lowPassHz` when > 0) at `lufs`, with
    // `silentTailSeconds` of digital silence at the end.
    auto lnNoiseProgramme(double seconds,
                          uint32_t seed,
                          double lowPassHz,
                          double lufs,
                          double silentTailSeconds = 0.0) -> TlProgramme
    {
        std::mt19937 rng(seed);
        const auto frames = static_cast<size_t>(seconds * kEngineFs);
        TlProgramme programme{kEngineFs, TlChannels(2U, std::vector<float>(frames))};
        for (std::vector<float>& channel : programme.channels)
        {
            std::vector<double> noise = tlPinkNoise(frames, rng);
            if (lowPassHz > 0.0)
            {
                TlBiquad first = lnLowPass(lowPassHz, kEngineFs);
                TlBiquad second = lnLowPass(lowPassHz, kEngineFs);
                for (double& sample : noise)
                {
                    sample = second.process(first.process(sample));
                }
            }
            std::ranges::transform(
                noise, channel.begin(), [](double sample) { return static_cast<float>(sample); });
        }
        tlNormalise(programme, lufs);
        const auto silent = static_cast<size_t>(silentTailSeconds * kEngineFs);
        for (std::vector<float>& channel : programme.channels)
        {
            std::fill(channel.end() - static_cast<std::ptrdiff_t>(std::min(silent, frames)),
                      channel.end(),
                      0.0F);
        }
        return programme;
    }

    // Bright programme: white noise in level sections (both gates act), −20 LUFS.
    auto lnBrightProgramme() -> const TlProgramme&
    {
        static const TlProgramme programme = []
        {
            constexpr std::array<double, 5> kLevelsDb = {0.0, -8.0, -3.0, -40.0, -1.0};
            std::mt19937 rng(21U);
            const auto frames = static_cast<size_t>(kTlGateSeconds * kEngineFs);
            std::normal_distribution<double> white(0.0, 1.0);
            const std::vector<double> envelope =
                tlSectionEnvelope(frames, kEngineFs, rng, kLevelsDb);
            TlProgramme bright{kEngineFs, TlChannels(2U, std::vector<float>(frames))};
            for (std::vector<float>& channel : bright.channels)
            {
                for (size_t frame = 0U; frame < frames; ++frame)
                {
                    channel[frame] = static_cast<float>(white(rng) * envelope[frame]);
                }
            }
            tlNormalise(bright, -20.0);
            return bright;
        }();
        return programme;
    }

    // Mixed programme: the pink, 808 and orchestral programmes summed (unclipped), −20 LUFS.
    auto lnMixProgramme() -> const TlProgramme&
    {
        static const TlProgramme programme = []
        {
            const TlProgramme& pink = tlGatePink();
            const TlProgramme& bass = tlGate808();
            const TlProgramme& strings = tlGateOrchestral();
            TlProgramme mix{kEngineFs, TlChannels(2U, std::vector<float>(pink.frames()))};
            for (size_t ch = 0U; ch < 2U; ++ch)
            {
                for (size_t frame = 0U; frame < pink.frames(); ++frame)
                {
                    mix.channels[ch][frame] = pink.channels[ch][frame] + bass.channels[ch][frame] +
                                              strings.channels[ch][frame];
                }
            }
            tlNormalise(mix, -20.0);
            return mix;
        }();
        return programme;
    }

    // The first `seconds` of `programme` (the On/Off gate's window, so it stays cheap under the
    // sanitizers).
    auto lnHead(const TlProgramme& programme, double seconds) -> TlProgramme
    {
        const auto frames =
            std::min(programme.frames(), static_cast<size_t>(seconds * programme.sampleRate));
        TlProgramme head{programme.sampleRate, {}};
        for (const std::vector<float>& channel : programme.channels)
        {
            head.channels.emplace_back(channel.begin(),
                                       channel.begin() + static_cast<std::ptrdiff_t>(frames));
        }
        return head;
    }

    // −ΔL of `profile` under `curve` designed at the engine rate (the Realizer's own answer).
    auto lnOwnGainDb(const TrackLoudnessProfile& profile,
                     const EqCurve& curve,
                     uint32_t blockStep = 1U) -> double
    {
        double change = 0.0;
        (void)predictLoudnessChangeDb(profile, engineDesign(curve, kEngineFs), blockStep, change);
        return -change;
    }

    // A profile at `rate` with `blocks` blocks of seeded random band powers (timing only).
    auto lnRandomProfile(double rate, uint32_t blocks, uint32_t seed)
        -> std::shared_ptr<TrackLoudnessProfile>
    {
        auto profile = std::make_shared<TrackLoudnessProfile>();
        profile->sampleRate = rate;
        profile->channelCount = 2U;
        profile->bandCount = TrackLoudness::bandCount(rate);
        profile->blockCount = blocks;
        profile->wholeTrack = true;
        profile->analysedFrames =
            static_cast<uint64_t>(blocks) * static_cast<uint64_t>(rate / 10.0);
        profile->bandPower.resize(static_cast<size_t>(blocks) * profile->bandCount);
        std::minstd_rand cheap(seed);
        std::uniform_real_distribution<float> power(1e-6F, 1e-2F);
        for (float& value : profile->bandPower)
        {
            value = power(cheap);
        }
        return profile;
    }
} // namespace

// ---------------------------------------------------------------------------
// EQ_LoudnessNeutral_OnOff — decision 26: with the track's profile in, EQ On plays at the same
// integrated loudness as Off (engine-plan §9). The whole chain at Intensity 0 (EQ → limiter) on a
// built-in output (decision 29's −0.1 dBTP ceiling); Off is the bit-perfect path, i.e. the
// programme itself. The −9 LUFS loud master is logged, not bounded: there the limiter takes back
// some of EQ On's peaks, which decision 29 accepted (p90 0.57 / max 2.07 dB).
// ---------------------------------------------------------------------------
static auto testEqLoudnessNeutralOnOff() -> void
{
    static const char* const kName = "EQ_LoudnessNeutral_OnOff";
    struct Case
    {
        const char* label;
        const TlProgramme* programme;
        double boundDb;
    };
    const std::array<Case, 6> cases = {
        {
            {"pink", &tlGatePink(), kLnOnOffBoundDb},
            {"tonal 808", &tlGate808(), kLnSubBassBoundDb},
            {"orchestral", &tlGateOrchestral(), kLnOnOffBoundDb},
            {"bright", &lnBrightProgramme(), kLnOnOffBoundDb},
            {"mix", &lnMixProgramme(), kLnOnOffBoundDb},
            {"loud master", &tlGateLoudMaster(), kLnLoggedOnly},
        },
    };
    constexpr double kWindowSeconds = 10.0;
    const std::vector<TlCurve> curves = tlGateCurves();
    std::string report = std::format(
        "[info] {}: |On − Off| integrated over {:.0f} s (dB), libebur128\n", kName, kWindowSeconds);
    std::string failure;
    for (const Case& test : cases)
    {
        const TlProgramme programme = lnHead(*test.programme, kWindowSeconds);
        const std::shared_ptr<const TrackLoudnessProfile> profile =
            tlProfile(programme, tlStereoWeights()).whole;
        const double offLufs = tlEbur128Lufs(programme.channels, programme.sampleRate);
        double worst = 0.0;
        std::string worstCurve;
        for (const TlCurve& curve : curves)
        {
            LnEngine engine(curve.points);
            engine.realizer->publishTrackLoudnessProfile(kLnTrackA, profile);
            engine.realizer->setCurrentTrack(kLnTrackA, false);
            engine.realizer->barrier();
            const TlChannels on = lnRender(*engine.kernel, programme, 0U, programme.frames());
            const double error = std::abs(tlEbur128Lufs(on, programme.sampleRate) - offLufs);
            if (!(error <= worst))
            {
                worst = error;
                worstCurve = curve.name;
            }
        }
        report += std::isinf(test.boundDb)
                      ? std::format("  {:<11} worst {:.3f} dB ({}), logged (decision 29)\n",
                                    test.label,
                                    worst,
                                    worstCurve)
                      : std::format("  {:<11} worst {:.3f} dB ({}), bound {:.2f}\n",
                                    test.label,
                                    worst,
                                    worstCurve,
                                    test.boundDb);
        if (!(worst <= test.boundDb) && failure.empty())
        {
            failure = std::format("{}: On vs Off {:.3f} dB with {} (> {:.2f})",
                                  test.label,
                                  worst,
                                  worstCurve,
                                  test.boundDb);
        }
    }
    logInfo(report);
    if (!failure.empty())
    {
        logFail(kName, failure);
        return;
    }
    logPass(kName);
}

// ---------------------------------------------------------------------------
// Loudness_ProfileLate — before a track's profile lands the pink prior plays; when it lands (here
// after 3 s) the gain glides to the track's own over τ 500 ms: no block-to-block step bigger than
// the glide allows, and it arrives (engine-plan §4.3, amendments item 3).
// ---------------------------------------------------------------------------
static auto testLoudnessProfileLate() -> void
{
    static const char* const kName = "Loudness_ProfileLate";
    constexpr double kLateSeconds = 3.0;
    constexpr double kAfterSeconds = 4.0;
    // The τ 500 ms glide moves 1 − e^(−10.7 ms / 500 ms) ≈ 2.1 % of the way per block, no more.
    const double glidePerBlock =
        1.0 - std::exp(-(static_cast<double>(kEngineBlock) / kEngineFs) /
                       static_cast<double>(TrackLoudnessGain::kArrivalRampSeconds));
    constexpr double kArrivedDb = 0.01;
    const EqCurve curve = eqFlatCurveWith(7U, 12.0F); // +12 dB at 100 Hz: a big ΔL on the 808
    const TlProgramme& programme = tlGate808();
    const std::shared_ptr<const TrackLoudnessProfile> profile =
        tlProfile(programme, tlStereoWeights()).whole;
    const double priorGain = lnOwnGainDb(*makePinkPriorProfile(kEngineFs), curve);
    const double ownGain = lnOwnGainDb(*profile, curve);
    const double maxBlockStepDb = 1.02 * glidePerBlock * std::abs(ownGain - priorGain);

    LnEngine engine(curve);
    engine.realizer->setCurrentTrack(kLnTrackA, false);
    engine.realizer->barrier();
    const double beforeGain = engine.realizer->loudnessGain().gainDb();
    const auto lateFrame = static_cast<size_t>(kLateSeconds * kEngineFs);
    (void)lnRender(*engine.kernel, programme, 0U, lateFrame);
    const double playedBefore = engine.appliedGainDb();

    engine.realizer->publishTrackLoudnessProfile(kLnTrackA, profile);
    engine.realizer->barrier();
    double previous = engine.appliedGainDb();
    double worstStep = 0.0;
    (void)lnRender(*engine.kernel,
                   programme,
                   lateFrame,
                   static_cast<size_t>(kAfterSeconds * kEngineFs),
                   [&](size_t)
                   {
                       const double now = engine.appliedGainDb();
                       worstStep = std::max(worstStep, std::abs(now - previous));
                       previous = now;
                   });
    const double finalGain = engine.appliedGainDb();
    logInfo(std::format(
        "[info] {}: prior {:+.3f} dB (played {:+.3f}), own {:+.3f} dB, reached {:+.3f}; "
        "worst block step {:.4f} dB (≤ {:.4f}, the glide's)\n",
        kName,
        priorGain,
        playedBefore,
        ownGain,
        finalGain,
        worstStep,
        maxBlockStepDb));
    if (std::abs(beforeGain - priorGain) > 1e-9 || std::abs(playedBefore - priorGain) > 1e-6)
    {
        logFail(kName, "the pink prior did not play before the profile landed");
        return;
    }
    if (std::abs(ownGain - priorGain) < 0.5)
    {
        logFail(kName, "vacuous: the profile barely moves the gain");
        return;
    }
    if (!(worstStep <= maxBlockStepDb) || !(std::abs(finalGain - ownGain) <= kArrivedDb))
    {
        logFail(kName, "the late profile stepped the level or never arrived");
        return;
    }
    logPass(kName);
}

namespace
{
    struct LnSeamResult
    {
        double before = 0.0;  // the applied gain just before the seam
        double after = 0.0;   // 100 ms after it
        double ownNext = 0.0; // the next track's own gain
        bool shared = false;  // the group kept one gain
    };

    // Play `a` for 2 s with its profile in, then a gapless seam to `b` (profile published before
    // the seam unless `bLate`, then 1 s later); report the gain around the seam.
    auto lnSeam(const TlProgramme& a, const TlProgramme& b, const EqCurve& curve, bool bLate)
        -> LnSeamResult
    {
        LnSeamResult result;
        const std::shared_ptr<const TrackLoudnessProfile> profileA =
            tlProfile(a, tlStereoWeights()).whole;
        const std::shared_ptr<const TrackLoudnessProfile> profileB =
            tlProfile(b, tlStereoWeights()).whole;
        result.ownNext = lnOwnGainDb(*profileB, curve);
        LnEngine engine(curve);
        engine.realizer->publishTrackLoudnessProfile(kLnTrackA, profileA);
        engine.realizer->setCurrentTrack(kLnTrackA, false);
        if (!bLate)
        {
            engine.realizer->publishTrackLoudnessProfile(kLnTrackB, profileB);
        }
        engine.realizer->barrier();
        const auto tail = static_cast<size_t>(2.0 * kEngineFs);
        (void)lnRender(*engine.kernel, a, a.frames() - tail, tail);
        result.before = engine.appliedGainDb();
        engine.realizer->setCurrentTrack(kLnTrackB, true);
        engine.realizer->barrier();
        (void)lnRender(*engine.kernel, b, 0U, static_cast<size_t>(0.1 * kEngineFs));
        result.after = engine.appliedGainDb();
        if (bLate)
        {
            (void)lnRender(*engine.kernel,
                           b,
                           static_cast<size_t>(0.1 * kEngineFs),
                           static_cast<size_t>(0.9 * kEngineFs));
            engine.realizer->publishTrackLoudnessProfile(kLnTrackB, profileB);
            engine.realizer->barrier();
            (void)lnRender(*engine.kernel,
                           b,
                           static_cast<size_t>(kEngineFs),
                           static_cast<size_t>(2.0 * kEngineFs));
            result.after = engine.appliedGainDb();
        }
        result.shared = engine.realizer->loudnessGain().sharesGroupGain();
        return result;
    }
} // namespace

// ---------------------------------------------------------------------------
// Loudness_GaplessSeamStep — amendments item 3: at a gapless seam where the music is continuous
// the level steps by ≤ 0.2 dB; a bigger difference makes the group share one gain. Across
// silence each track keeps its own (a step there is inaudible). A late profile at a seam holds the
// gain, then decides the same way.
// ---------------------------------------------------------------------------
static auto testLoudnessGaplessSeamStep() -> void
{
    static const char* const kName = "Loudness_GaplessSeamStep";
    const EqCurve curve = eqFlatCurveWith(7U, 12.0F);
    const TlProgramme pink = lnNoiseProgramme(8.0, 31U, 0.0, -18.0);
    const TlProgramme pinkTwin = lnNoiseProgramme(8.0, 32U, 0.0, -18.0);
    const TlProgramme bass = lnNoiseProgramme(8.0, 33U, 150.0, -18.0);
    const TlProgramme pinkThenSilence = lnNoiseProgramme(8.0, 34U, 0.0, -18.0, 1.0);

    const LnSeamResult continuous = lnSeam(pink, bass, curve, false);
    const LnSeamResult similar = lnSeam(pink, pinkTwin, curve, false);
    const LnSeamResult silent = lnSeam(pinkThenSilence, bass, curve, false);
    const LnSeamResult late = lnSeam(pink, bass, curve, true);
    logInfo(std::format(
        "[info] {}: continuous pink → bass: {:+.3f} → {:+.3f} dB (own {:+.3f}, shared {}); "
        "similar: {:+.3f} → {:+.3f}; across silence: {:+.3f} → {:+.3f} (own {:+.3f}); late "
        "profile: {:+.3f} → {:+.3f} (shared {})\n",
        kName,
        continuous.before,
        continuous.after,
        continuous.ownNext,
        continuous.shared,
        similar.before,
        similar.after,
        silent.before,
        silent.after,
        silent.ownNext,
        late.before,
        late.after,
        late.shared));
    if (std::abs(continuous.ownNext - continuous.before) <= kLnSeamStepDb)
    {
        logFail(kName, "vacuous: the two tracks' gains are within 0.2 dB");
        return;
    }
    const bool continuousOk =
        std::abs(continuous.after - continuous.before) <= kLnSeamStepDb && continuous.shared;
    const bool similarOk = std::abs(similar.after - similar.before) <= kLnSeamStepDb &&
                           !similar.shared && std::abs(similar.after - similar.ownNext) <= 0.01;
    const bool silentOk = !silent.shared && std::abs(silent.after - silent.ownNext) <= 0.01;
    const bool lateOk = std::abs(late.after - late.before) <= kLnSeamStepDb && late.shared;
    if (!continuousOk || !similarOk || !silentOk || !lateOk)
    {
        logFail(kName,
                std::format("continuous {} similar {} silent {} late {}",
                            continuousOk,
                            similarOk,
                            silentOk,
                            lateOk));
        return;
    }
    logPass(kName);
}

// ---------------------------------------------------------------------------
// Loudness_AnalysisFails_CausalFallback — amendments item 3: a track whose analysis failed falls
// back to the causal running estimate of the audio as it plays (not the pink prior): the prior for
// the first 3 s, then at most 1 dB per second toward the estimate's gain; a profile that lands
// later ends the estimate.
// ---------------------------------------------------------------------------
static auto testLoudnessAnalysisFailsCausalFallback() -> void
{
    static const char* const kName = "Loudness_AnalysisFails_CausalFallback";
    constexpr double kSeconds = 30.0;
    constexpr double kConvergedDb = 0.5;
    constexpr double kSlewDb = TrackLoudnessGain::kCausalSlewDbPerSnapshot + 1e-9;
    const EqCurve curve = eqFlatCurveWith(7U, 12.0F);
    const TlProgramme programme = tl808Programme(kEngineFs, kSeconds, 41U);
    const std::shared_ptr<const TrackLoudnessProfile> whole =
        tlProfile(programme, tlStereoWeights()).whole;
    const double ownGain = lnOwnGainDb(*whole, curve);
    const double priorGain = lnOwnGainDb(*makePinkPriorProfile(kEngineFs), curve);

    LnEngine engine(curve);
    engine.realizer->setCurrentTrack(kLnTrackA, false);
    engine.realizer->reportTrackLoudnessFailure(kLnTrackA);
    engine.realizer->barrier();
    const bool running = engine.realizer->loudnessGain().wantsCausalEstimate();

    // Render a second at a time, then wait until that second's snapshot has reached the
    // Realizer (the tap's worker and the queue run on their own threads). The ring holds 2.7 s, so
    // nothing rendered is ever dropped, and the estimate reaches every second — a cap that passes
    // fails the test (never a gain read off a half-analysed second).
    std::vector<double> perSecond;
    const auto second = static_cast<size_t>(kEngineFs);
    for (size_t start = 0U; start + second <= programme.frames(); start += second)
    {
        (void)lnRender(*engine.kernel, programme, start, second);
        const double covered = static_cast<double>(start + second) / kEngineFs;
        if (!rig::waitUntil("the causal estimate's snapshot covered the second just rendered",
                            [&] {
                                return engine.realizer->loudnessGain().causalSeconds() >=
                                       covered - 1e-6;
                            }))
        {
            return;
        }
        perSecond.push_back(engine.realizer->loudnessGain().gainDb());
    }
    double worstSlew = 0.0;
    double previous = priorGain;
    for (const double gain : perSecond)
    {
        worstSlew = std::max(worstSlew, std::abs(gain - previous));
        previous = gain;
    }
    const bool warmup =
        std::abs(perSecond[0] - priorGain) < 1e-9 && std::abs(perSecond[1] - priorGain) < 1e-9;
    const double causalFinal = perSecond.back();

    engine.realizer->publishTrackLoudnessProfile(kLnTrackA, whole);
    engine.realizer->barrier();
    const bool ended = !engine.realizer->loudnessGain().wantsCausalEstimate();
    const double afterProfile = engine.realizer->loudnessGain().gainDb();
    logInfo(
        std::format("[info] {}: prior {:+.3f} dB, own {:+.3f} dB; running estimate after {:.0f} s "
                    "{:+.3f} dB; worst per-second move {:.3f} dB; fed {} frames\n",
                    kName,
                    priorGain,
                    ownGain,
                    kSeconds,
                    causalFinal,
                    worstSlew,
                    engine.kernel->causalLoudnessFedFrames()));
    if (!running || !warmup)
    {
        logFail(kName, "the causal estimate did not start, or left the prior before 3 s");
        return;
    }
    if (!(worstSlew <= kSlewDb) || !(std::abs(causalFinal - ownGain) <= kConvergedDb))
    {
        logFail(kName, "the running estimate slewed faster than 1 dB/s or did not converge");
        return;
    }
    if (!ended || std::abs(afterProfile - ownGain) > 1e-9)
    {
        logFail(kName, "a profile that landed later did not end the estimate");
        return;
    }
    logPass(kName);
}

// ---------------------------------------------------------------------------
// Loudness_EditDebounce — amendments item 4 (A6): an edit carries a decimated gain with its
// coefficients; after ~150 ms with no further edit the Realizer publishes the full-resolution gain.
// ---------------------------------------------------------------------------
static auto testLoudnessEditDebounce() -> void
{
    static const char* const kName = "Loudness_EditDebounce";
    const TlProgramme programme = lnNoiseProgramme(70.0, 51U, 0.0, -18.0); // ~700 blocks
    const std::shared_ptr<const TrackLoudnessProfile> profile =
        tlProfile(programme, tlStereoWeights()).whole;
    LnEngine engine(kEqPresetCurves[kEqPresetWarm]);
    engine.realizer->publishTrackLoudnessProfile(kLnTrackA, profile);
    engine.realizer->setCurrentTrack(kLnTrackA, false);
    engine.realizer->barrier();
    // A burst of edits (a drag), each with its decimated gain; then idle.
    const std::array<EqCurve, 3> drag = {
        eqFlatCurveWith(10U, 6.0F),
        eqFlatCurveWith(10U, 9.0F),
        eqFlatCurveWith(10U, 12.0F),
    };
    for (const EqCurve& curve : drag)
    {
        engine.realizer->applyEq(engineEqIntent(curve, true));
    }
    const double decimated = engine.realizer->canonicalState().eq.outputGainDb;
    const bool pending = engine.realizer->loudnessGain().needsRefresh();
    // The idle refresh: the Realizer's own 150 ms debounce fires it (dispatch_after on its queue).
    // Wait for its effect — the refresh no longer pending, read on the queue — not a fixed 400 ms:
    // a starved queue only delays it, and a refresh that never comes fails at the cap.
    if (pending && !rig::waitUntil("the idle refresh ran (needsRefresh() false)",
                                   [&] { return !engine.realizer->loudnessGain().needsRefresh(); }))
    {
        return; // waitUntil failed the test, naming the state
    }
    const double refreshed = engine.realizer->canonicalState().eq.outputGainDb;
    const double full = lnOwnGainDb(*profile, drag.back());
    const uint32_t step = (profile->blockCount + TrackLoudnessGain::kEditBlockBudget - 1U) /
                          TrackLoudnessGain::kEditBlockBudget;
    const double expectedDecimated = lnOwnGainDb(*profile, drag.back(), step);
    logInfo(std::format(
        "[info] {}: {} blocks; edit gain {:+.4f} dB (every {} blocks), refreshed {:+.4f} dB, "
        "full {:+.4f} dB\n",
        kName,
        profile->blockCount,
        decimated,
        step,
        refreshed,
        full));
    if (!pending || step < 2U || std::abs(decimated - expectedDecimated) > 1e-9)
    {
        logFail(kName, "the edit did not publish the decimated gain or arm the refresh");
        return;
    }
    if (std::abs(refreshed - full) > TrackLoudnessGain::kMinChangeDb ||
        engine.realizer->loudnessGain().needsRefresh())
    {
        logFail(kName, "the idle refresh did not publish the full-resolution gain");
        return;
    }
    logPass(kName);
}

// ---------------------------------------------------------------------------
// TrackLoudnessGain_Rules — the state machine, rule by rule (TrackLoudnessGain.h).
// ---------------------------------------------------------------------------
static auto testTrackLoudnessGainRules() -> void
{
    static const char* const kName = "TrackLoudnessGain_Rules";
    const EqCurve curve = kEqPresetCurves[kEqPresetWarm];
    const GraphicEQDesign design = engineDesign(curve, kEngineFs);
    const TlProgramme programme =
        lnNoiseProgramme(30.0, 61U, 150.0, -18.0); // bass: far from the prior
    const TlProfiles profiles =
        tlProfile(programme, tlStereoWeights(), static_cast<size_t>(10.0 * kEngineFs));
    std::string failure;
    const auto expect = [&failure](bool condition, const char* what)
    {
        if (!condition && failure.empty())
        {
            failure = what;
        }
    };

    TrackLoudnessGain gain(kEngineFs);
    expect(gain.onDesign(design, false) == 0.0, "EQ Off plays 0 dB exactly");
    expect(gain.onDesign(engineDesign(EqCurve{}, kEngineFs), true) == 0.0,
           "a flat EQ plays 0 dB exactly");
    const double prior = gain.onDesign(design, true);
    expect(prior == lnOwnGainDb(*makePinkPriorProfile(kEngineFs), curve), "no track: the prior");
    const double own = lnOwnGainDb(*profiles.whole, curve);
    expect(std::abs(own - prior) > 1.0, "vacuous: the bass programme's gain is near the prior's");

    expect(!gain.onProfile(0U, profiles.prefix).has_value(), "token 0 is ignored");
    expect(!gain.onProfile(kLnTrackA, nullptr).has_value(), "a null profile is ignored");
    expect(!gain.onProfile(kLnTrackA, profiles.prefix).has_value(),
           "a non-current track's profile waits");
    const auto start = gain.onCurrentTrack(kLnTrackA, false);
    expect(start.has_value() && start->rampSeconds == TrackLoudnessGain::kTrackChangeRampSeconds,
           "a fresh start moves at once (10 ms)");
    expect(!gain.onCurrentTrack(kLnTrackA, false).has_value(), "the same track again is a no-op");
    const auto refine = gain.onProfile(kLnTrackA, profiles.whole);
    expect(!refine.has_value() || refine->rampSeconds == TrackLoudnessGain::kRefineRampSeconds,
           "prefix → whole refines over 2 s");
    expect(std::abs(gain.gainDb() - own) < TrackLoudnessGain::kMinChangeDb,
           "the whole track's own gain");
    expect(!gain.onProfile(kLnTrackA, profiles.whole).has_value(),
           "the same whole profile again (the analyzer re-publishing its cache) changes nothing");
    expect(!gain.onProfile(kLnTrackA, profiles.prefix).has_value(),
           "a late prefix never replaces the whole track");

    // The current track is never evicted, whatever else arrives.
    for (uint64_t token = 100U; token < 110U; ++token)
    {
        (void)gain.onProfile(token, profiles.prefix);
    }
    expect(std::abs(gain.onDesign(design, true) - own) < 1e-9,
           "the current track's profile is kept");

    // Failure → the causal estimate: the prior through its warm-up, then ≤ 1 dB per snapshot; a
    // profile ends it.
    (void)gain.onCurrentTrack(kLnTrackB, false);
    expect(std::abs(gain.gainDb() - prior) < 1e-9, "a new track without a profile plays the prior");
    gain.onFailure(kLnTrackB);
    expect(gain.wantsCausalEstimate(), "a failed current track wants the causal estimate");
    auto young = std::make_shared<TrackLoudnessProfile>(*profiles.prefix);
    young->analysedFrames = static_cast<uint64_t>(2.0 * kEngineFs);
    expect(!gain.onCausalSnapshot(young).has_value(), "the prior holds through the 3 s warm-up");
    const auto slewed = gain.onCausalSnapshot(profiles.whole);
    expect(slewed.has_value() &&
               std::abs(slewed->gainDb - prior) <=
                   TrackLoudnessGain::kCausalSlewDbPerSnapshot + 1e-9 &&
               slewed->rampSeconds == TrackLoudnessGain::kCausalRampSeconds,
           "the causal estimate moves ≤ 1 dB per snapshot, at 1 s");
    const auto landed = gain.onProfile(kLnTrackB, profiles.whole);
    expect(
        !gain.wantsCausalEstimate() &&
            std::abs(gain.gainDb() - own) < TrackLoudnessGain::kMinChangeDb &&
            (!landed.has_value() || landed->rampSeconds == TrackLoudnessGain::kArrivalRampSeconds),
        "a profile ends the estimate and lands over 500 ms");
    logInfo(
        std::format("[info] {}: prior {:+.3f} dB, own {:+.3f} dB\n", kName, prior, gain.gainDb()));
    if (!failure.empty())
    {
        logFail(kName, failure);
        return;
    }
    logPass(kName);
}

// ---------------------------------------------------------------------------
// Soak_DSPKernel_ZeroRtAlloc_CausalTap — with a causal estimate running, the kernel's render
// path (the tap's interleave and ring push) allocates nothing on the RT thread. SERIAL-ONLY (the
// process-wide allocation guard).
// ---------------------------------------------------------------------------
static auto testSoakDspKernelZeroRtAllocCausalTap() -> void
{
    static const char* const kName = "Soak_DSPKernel_ZeroRtAlloc_CausalTap";
    constexpr uint32_t kChannels = 8U;
    constexpr uint32_t kBlocks = 2000U; // ~21 s at 48 kHz
    DSPKernel kernel;
    kernel.initialize(static_cast<uint32_t>(kEngineFs), kEngineBlock);
    std::atomic<uint64_t> snapshots{0U};
    kernel.startCausalLoudness([&snapshots](const std::shared_ptr<const TrackLoudnessProfile>&)
                               { snapshots.fetch_add(1U, std::memory_order_relaxed); });
    TestABLN abl(kChannels, kEngineBlock);
    std::minstd_rand cheap(71U);
    std::uniform_real_distribution<float> noise(-0.2F, 0.2F);
    std::vector<std::vector<float>> source(kChannels, std::vector<float>(kEngineBlock));
    for (auto& channel : source)
    {
        std::ranges::generate(channel, [&] { return noise(cheap); });
    }
    uint64_t allocs = 0U;
    {
        const RtGuardScope guard;
        for (uint32_t block = 0U; block < kBlocks; ++block)
        {
            for (uint32_t ch = 0U; ch < kChannels; ++ch)
            {
                std::ranges::copy(source[ch], abl.channels[ch].begin());
            }
            kernel.process(abl.abl(), kEngineBlock);
        }
        allocs = RtGuardScope::count();
    }
    // The witness that the tap path ran: its worker fed the profiler. (The render outpaces the
    // worker on purpose — 21 s pushed at full speed — so the ring may drop; what reached it is
    // analysed. A cap that passes fails the test, never a verdict on a tap that fed nothing yet.)
    const bool fed = rig::waitUntil("the causal tap's worker fed the profiler",
                                    [&] { return kernel.causalLoudnessFedFrames() > 0U; });
    kernel.stopCausalLoudness();
    if (!fed)
    {
        return;
    }
    logInfo(std::format("[info] {}: rtAllocs={} fed {} frames, {} snapshots\n",
                        kName,
                        allocs,
                        kernel.causalLoudnessFedFrames(),
                        snapshots.load()));
    if (allocs != 0U || kernel.causalLoudnessFedFrames() == 0U)
    {
        logFail(kName, "the RT path allocated, or the tap fed nothing");
        return;
    }
    logPass(kName);
}

// ---------------------------------------------------------------------------
// Realizer_LoudnessCost — the cost bound (amendments item 3): the worst profile the Realizer can
// hold — a 10-minute-capped track at 192 kHz, 6000 blocks × 295 bands, 7.1 MB — under a design at
// 192 kHz. An edit pays the design plus a decimated gain (≤ 300 blocks); the idle refresh pays the
// full prediction. Budgets, with the M1 Pro floor in hand: edit ≤ 1 ms, refresh ≤ 5 ms — as the
// working thread's own CPU time, the least of rig::kTimingRuns runs, in the -O2 timing run; the
// debug and sanitizer builds only trip a catastrophic regression (≥ 10× what they measure — debug:
// 1.4 and 12 ms here, 2.0 and 16.3 ms wall on CI). The Realizer keeps at most kTrackSlots profiles
// (≤ 4 × 7.1 MB).
// ---------------------------------------------------------------------------
static auto testRealizerLoudnessCost() -> void
{
    static const char* const kName = "Realizer_LoudnessCost";
    // Tripwires ≥ 10× each build's measurement (2026-10-21: edit debug 1.8, ASan 5.7, TSan 18 ms;
    // refresh debug 14, ASan 54, TSan 332 ms).
    constexpr rig::Budget kEditBudgetMs{
        .strict = 1.0,
        .debug = 25.0,
        .asan = 75.0,
        .tsan = 250.0,
    };
    constexpr rig::Budget kRefreshBudgetMs{
        .strict = 5.0,
        .debug = 200.0,
        .asan = 600.0,
        .tsan = 4000.0,
    };
    constexpr double kRate = 192000.0;
    constexpr int kRounds = 20;
    const std::shared_ptr<TrackLoudnessProfile> profile =
        lnRandomProfile(kRate, TrackLoudnessProfiler::kDefaultMaxBlocks, 81U);
    TrackLoudnessGain gain(kRate);
    (void)gain.onProfile(kLnTrackA, profile);
    (void)gain.onCurrentTrack(kLnTrackA, false);
    auto designer = eqMakeDesigner();
    std::array<GraphicEQDesign, 2> designs{};
    (void)designer->design(kEqPresetCurves[kEqPresetWarm], kRate, designs[0]);
    (void)designer->design(kEqPresetCurves[kEqPresetVocal], kRate, designs[1]);
    double sink = 0.0;
    const std::chrono::nanoseconds editCpu = rig::minThreadCpu(
        rig::kTimingRuns,
        [&]
        {
            for (int round = 0; round < kRounds; ++round)
            {
                GraphicEQDesign design{};
                (void)designer->design(
                    kEqPresetCurves[static_cast<size_t>(round) % kEqPresetCurves.size()],
                    kRate,
                    design);
                sink += gain.onDesign(design, true);
            }
        });
    const std::chrono::nanoseconds editAndRefreshCpu = rig::minThreadCpu(
        rig::kTimingRuns,
        [&]
        {
            for (int round = 0; round < kRounds; ++round)
            {
                (void)gain.onDesign(designs[static_cast<size_t>(round) % 2U], true);
                if (const auto change = gain.onRefresh())
                {
                    sink += change->gainDb;
                }
            }
        });
    const double editMs = std::chrono::duration<double, std::milli>(editCpu).count() / kRounds;
    // The refresh loop also paid an edit per round: take it back out.
    const double refreshMs =
        (std::chrono::duration<double, std::milli>(editAndRefreshCpu).count() / kRounds) - editMs;
    const double editBound = rig::limit(kEditBudgetMs);
    const double refreshBound = rig::limit(kRefreshBudgetMs);
    const double profileMb = static_cast<double>(profile->memoryBytes()) / 1e6;
    logInfo(std::format(
        "[info] {} ({} build, thread CPU, least of {}): 6000 × {} bands at 192 kHz ({:.1f} MB; "
        "≤ {} kept): edit (design + decimated gain) {:.3f} ms (bound {:.1f}), full refresh "
        "{:.3f} ms (bound {:.1f}) [{:.1f}]\n",
        kName,
        rig::kBuild,
        rig::kTimingRuns,
        profile->bandCount,
        profileMb,
        TrackLoudnessGain::kTrackSlots,
        editMs,
        editBound,
        std::max(0.0, refreshMs),
        refreshBound,
        sink));
    if (!(editMs <= editBound) || !(refreshMs <= refreshBound))
    {
        logFail(kName,
                std::format("over budget: edit {:.3f} ms (≤ {:.1f}), refresh {:.3f} ms (≤ {:.1f})",
                            editMs,
                            editBound,
                            refreshMs,
                            refreshBound));
        return;
    }
    logPass(kName);
}

// ---------------------------------------------------------------------------
// Limiter_EqOnlyCeiling — founder decision 29 (EQ2). With Intensity 0 and the EQ on, the chain is
// EQ → limiter, and its true-peak ceiling follows the output: −0.1 dBTP on a wired or built-in
// output (no higher than the bit-perfect Off of the same master already sends), −1 dBTP on
// Bluetooth or an unknown link (a lossy encoder needs the margin). Every other path keeps
// −1 dBTP. A loud master (−9 LUFS) with a deep bass cut (the neutral gain lifts the rest) drives
// the limiter; the output's true
// peak (libebur128, cross-checked by the 32× sinc meter exactly as LimiterTruePeakTests.inc does)
// must stay under its ceiling, and on a wired output it must actually USE the higher one.
// ---------------------------------------------------------------------------
static auto testLimiterEqOnlyCeiling() -> void
{
    static const char* const kName = "Limiter_EqOnlyCeiling";
    constexpr double kWindowSeconds = 6.0;
    constexpr double kSettleSeconds = 0.5;
    constexpr double kWiredDbTp = -0.1;
    constexpr double kLossyDbTp = -1.0;
    constexpr double kUsesWiredCeilingDbTp =
        -0.9; // above the old −1 dBTP by more than the meter's slack
    struct Case
    {
        const char* label;
        uint32_t transport;
        float intensity;
        double ceilingDbTp;
    };
    const std::array<Case, 5> cases = {
        {
            {"built-in, EQ-only", kAudioDeviceTransportTypeBuiltIn, 0.0F, kWiredDbTp},
            {"USB, EQ-only", kAudioDeviceTransportTypeUSB, 0.0F, kWiredDbTp},
            {"Bluetooth, EQ-only", kAudioDeviceTransportTypeBluetooth, 0.0F, kLossyDbTp},
            {"unknown, EQ-only", 0U, 0.0F, kLossyDbTp},
            {"built-in, Intensity 0.5", kAudioDeviceTransportTypeBuiltIn, 0.5F, kLossyDbTp},
        },
    };
    const TlProgramme master = lnHead(tlGateLoudMaster(), kWindowSeconds);
    const std::shared_ptr<const TrackLoudnessProfile> profile =
        tlProfile(master, tlStereoWeights()).whole;
    // A deep bass cut: the loudness-neutral gain then lifts everything else by several dB, so the
    // EQ'd master's peaks press on the limiter (the scenario decision 29 is about).
    EqCurve curve{};
    std::fill(curve.begin(), curve.begin() + 11, -12.0F);
    std::string report =
        std::format("[info] {}: output true peak (libebur128 / sinc dBTP)\n", kName);
    std::string failure;
    // The transport table itself (Limiting/OutputCeiling.h): local lossless links get −0.1 dBTP;
    // re-encoding links and links the device does not name keep −1 dBTP.
    for (const uint32_t wired : {
             kAudioDeviceTransportTypeBuiltIn,
             kAudioDeviceTransportTypeUSB,
             kAudioDeviceTransportTypeFireWire,
             kAudioDeviceTransportTypeThunderbolt,
             kAudioDeviceTransportTypePCI,
             kAudioDeviceTransportTypeHDMI,
             kAudioDeviceTransportTypeDisplayPort,
             kAudioDeviceTransportTypeAVB,
         })
    {
        if (eqOnlyCeilingLinear(wired) != kEqOnlyWiredCeilingLinear)
        {
            failure = std::format("transport {:08x} should get −0.1 dBTP", wired);
        }
    }
    for (const uint32_t lossy : {
             kAudioDeviceTransportTypeBluetooth,
             kAudioDeviceTransportTypeBluetoothLE,
             kAudioDeviceTransportTypeAirPlay,
             kAudioDeviceTransportTypeVirtual,
             kAudioDeviceTransportTypeAggregate,
             kAudioDeviceTransportTypeUnknown,
         })
    {
        if (eqOnlyCeilingLinear(lossy) != kTruePeakCeilingLinear)
        {
            failure = std::format("transport {:08x} should keep −1 dBTP", lossy);
        }
    }
    for (const Case& test : cases)
    {
        LnEngine engine(curve, true, test.transport);
        engine.realizer->applyIntensity(test.intensity);
        engine.realizer->publishTrackLoudnessProfile(kLnTrackA, profile);
        engine.realizer->setCurrentTrack(kLnTrackA, false);
        engine.realizer->barrier();
        const TlChannels out = lnRender(*engine.kernel, master, 0U, master.frames());
        const auto settle = static_cast<size_t>(kSettleSeconds * kEngineFs);
        std::vector<float> interleaved;
        interleaved.reserve((out[0].size() - settle) * kOracleStereo);
        for (size_t frame = settle; frame < out[0].size(); ++frame)
        {
            interleaved.push_back(out[0][frame]);
            interleaved.push_back(out[1][frame]);
        }
        double oracle = 0.0;
        if (!oracleDbTp(interleaved, static_cast<uint32_t>(kEngineFs), oracle))
        {
            failure = "libebur128 failed";
            break;
        }
        const double sinc = sincTruePeakDbTp(settledWindow(interleaved));
        report += std::format("  {:<24} {:+.2f} / {:+.2f} dBTP (ceiling {:+.1f})\n",
                              test.label,
                              oracle,
                              sinc,
                              test.ceilingDbTp);
        const bool breach = oracle > test.ceilingDbTp + kCeilingMarginDb &&
                            sinc > test.ceilingDbTp + kCeilingMarginDb;
        if (breach && failure.empty())
        {
            failure = std::format("{}: {:+.2f} dBTP over its {:+.1f} dBTP ceiling",
                                  test.label,
                                  oracle,
                                  test.ceilingDbTp);
        }
        if (test.ceilingDbTp == kWiredDbTp && !(oracle > kUsesWiredCeilingDbTp) && failure.empty())
        {
            failure = std::format(
                "{}: {:+.2f} dBTP — the wired ceiling was not used", test.label, oracle);
        }
        if (test.ceilingDbTp == kLossyDbTp && !(sinc <= kLossyDbTp + kCeilingMarginDb) &&
            failure.empty())
        {
            failure = std::format("{}: {:+.2f} dBTP — not held at −1 dBTP", test.label, sinc);
        }
    }
    logInfo(report);
    if (!failure.empty())
    {
        logFail(kName, failure);
        return;
    }
    logPass(kName);
}
