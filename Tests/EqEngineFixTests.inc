// EqEngineFixTests.inc
//
// Sprint EQ — the gates of the engine break-it's FIX ROUND (amendments 14–19). #included into
// Tests/DSPKernelNullTest.cpp after EqEngineBreakItTests.inc (it reuses the engine, transition and
// loudness-neutral helpers). The break-it's own four tests stay where they are; these pin each fix
// at the stage that owns it, so no fix can hide behind another.
//
// Amendment 14 — non-finite input:
//   Kernel_NonFiniteInput_PlaysAsSilence — a NaN / ±Inf sample plays as silence on all four paths:
//                                    the output is bit-identical to the same input with zeros
//                                    there, and finite in the very block that carried it
//   Limiter_NonFiniteInput_StaysFinite   — the limiter alone (process() and after prime())
//   LufsMeter_NonFiniteSample_IsSilence  — the meter alone: the readings equal a run with zeros
//
// Amendment 15 — each band glides at its own τ (EQTargets::rampsFor):
//   EQ_Transitions_SinglePoints  — one point to ±12 dB and back across the spectrum, and the bass
//                                    cuts: local ≤ +1.0 dB, peak ≤ +0.6 dB
//   EQ_SinglePoint_SettlesFast   — a single ±12 point (and a key step) at 1 kHz and up reaches 90 %
//                                    within ~30 ms (≤ 35); the lower bands' settle times are reported
//   (and EQ_Transitions_Adversarial's new duration bound: ≤ 60 ms above +3 dB)
//
// Amendment 16 — founder decision 33, crossing Intensity 0 glides the level over ~2 s:
//   Intensity_Zero_LevelGlide    — the normaliser's makeup leaves / rejoins the level as a ~2 s
//                                    glide (10–90 % ≥ 1 s; ≤ 0.5 dB in any 50 ms once Intensity
//                                    has ramped)
//
// Amendment 17 — entering and leaving bit-perfect (P0):
//   Kernel_P0Switch_LoudMasterStep — the level step entering P0 on the −9 LUFS loud master
//                                    ≤ 0.3 LU on a wired output (−0.1 dBTP); Bluetooth logged
//   Kernel_P0Fade_KeepsPower       — the 5 ms fade keeps the power: noise ±0.5 dB (equal-gain
//                                    dipped −2.5), tones' envelopes ±0.5 dB (equal-power would
//                                    bump an in-phase tone +3)
//
// Amendment 18 — rates above 192 kHz:
//   EQ_Cpu_7_1_AboveSupportedRates — the EQ at 384 and 768 kHz × 8 within its stated budget,
//                                    5 % × fs / 192 kHz (10 % / 20 % of one core)

namespace
{
    // The three non-finite floats.
    constexpr std::array<float, 3> kFixNonFinite = {
        std::numeric_limits<float>::quiet_NaN(),
        std::numeric_limits<float>::infinity(),
        -std::numeric_limits<float>::infinity(),
    };

    auto fixAllFinite(const std::vector<float>& samples) -> bool
    {
        return std::ranges::all_of(samples, [](float value) { return std::isfinite(value); });
    }

    // Bit-for-bit equality (a plain == would call two NaNs different and +0 / −0 the same).
    auto fixSameBits(const std::vector<float>& a, const std::vector<float>& b) -> bool
    {
        return a.size() == b.size() &&
               std::memcmp(a.data(), b.data(), a.size() * sizeof(float)) == 0;
    }

    // A stereo programme block: a 1 kHz sine on the left, a 700 Hz one on the right.
    auto fixProgrammeBlock(TestABL& abl, uint64_t start, double amplitude) -> void
    {
        for (uint32_t i = 0U; i < kEngineBlock; ++i)
        {
            const double time = static_cast<double>(start + i) / kEngineFs;
            abl.left[i] =
                static_cast<float>(amplitude * std::sin(2.0 * std::numbers::pi * 1000.0 * time));
            abl.right[i] =
                static_cast<float>(amplitude * std::sin(2.0 * std::numbers::pi * 700.0 * time));
        }
    }

    // Put the three non-finite values into block `block` of a run (both channels, spread out); or,
    // with `asSilence`, zeros in the same places.
    auto fixPoison(TestABL& abl, uint32_t block, bool asSilence) -> void
    {
        if (block != 3U && block != 4U)
        {
            return;
        }
        constexpr std::array<uint32_t, 3> kWhere = {7U, 400U, 511U}; // two inside the last 3 ms
        for (size_t i = 0; i < kWhere.size(); ++i)
        {
            const float value =
                asSilence ? 0.0F : kFixNonFinite[(i + block) % kFixNonFinite.size()];
            abl.left[kWhere[i]] = value;
            abl.right[(kWhere[i] + 31U) % kEngineBlock] = value;
        }
    }

    // A meter fed 5 s of a stereo 1 kHz tone at −6 dBFS, with `sample` at 1 s on the left and at
    // ~2 s on the right — interleaved or planar.
    auto fixMeteredTone(float sample, bool interleaved) -> std::unique_ptr<LufsMeter>
    {
        constexpr uint32_t kFs = 48000U;
        constexpr size_t kFrames = static_cast<size_t>(kFs) * 5U;
        std::vector<float> left(kFrames);
        for (size_t n = 0; n < kFrames; ++n)
        {
            left[n] = static_cast<float>(
                0.5 * std::sin(2.0 * std::numbers::pi * 1000.0 * static_cast<double>(n) / kFs));
        }
        std::vector<float> right = left;
        left[kFs] = sample;
        right[(kFs * 2U) + 17U] = sample;
        auto meter = std::make_unique<LufsMeter>();
        meter->prepare(static_cast<double>(kFs));
        if (!interleaved)
        {
            meter->addNonInterleavedStereo(left.data(), right.data(), kFrames);
            return meter;
        }
        std::vector<float> both(kFrames * 2U);
        for (size_t n = 0; n < kFrames; ++n)
        {
            both[2U * n] = left[n];
            both[(2U * n) + 1U] = right[n];
        }
        meter->addInterleavedStereo(both.data(), kFrames);
        return meter;
    }
} // namespace

// ---------------------------------------------------------------------------
// Kernel_NonFiniteInput_PlaysAsSilence — amendment 14, the kernel's input scrub. On every path
// (P0 bit-perfect, P1 EQ-only, P2 full, P3 blend) a run carrying NaN, +Inf and −Inf samples must
// produce, bit for bit, the output of the same run with zeros in their place — and no non-finite
// sample at all, not even in the block that carried them. (The normaliser is off here so the two
// runs are deterministic; its own recovery is BreakIt_NonFiniteInput_NormaliserKeepsAdapting.)
// ---------------------------------------------------------------------------
static auto testKernelNonFiniteInputPlaysAsSilence() -> void
{
    static const char* const kName = "Kernel_NonFiniteInput_PlaysAsSilence";
    const EQParams warm =
        makeEqParams(kEqPresetCurves[kEqPresetWarm], static_cast<uint32_t>(kEngineFs));
    struct Case
    {
        const char* name;
        float intensity;
        bool eqOn;
    };
    constexpr std::array<Case, 4> kCases = {
        {
            {"P0 (bit-perfect)", 0.0F, false},
            {"P1 (EQ-only)", 0.0F, true},
            {"P2 (full)", 1.0F, true},
            {"P3 (blend)", 0.5F, true},
        },
    };
    constexpr uint32_t kBlocks = 12U;
    for (const Case& c : kCases)
    {
        std::array<std::vector<float>, 2> outputs;
        for (size_t run = 0; run < outputs.size(); ++run)
        {
            TargetState state{}; // the limiter ON at −1 dBTP
            state.loudness.enabled = 0U;
            state.intensityLinear = c.intensity;
            state.eq = c.eqOn ? warm : EQParams{};
            DSPKernel kernel;
            kernel.publishTargetState(state);
            kernel.initialize(static_cast<uint32_t>(kEngineFs), kEngineBlock);
            TestABL abl(kEngineBlock);
            for (uint32_t block = 0U; block < kBlocks; ++block)
            {
                fixProgrammeBlock(abl, static_cast<uint64_t>(block) * kEngineBlock, 0.6);
                fixPoison(abl, block, run == 1U);
                kernel.process(abl.abl(), kEngineBlock);
                outputs[run].insert(outputs[run].end(), abl.left.begin(), abl.left.end());
                outputs[run].insert(outputs[run].end(), abl.right.begin(), abl.right.end());
            }
        }
        if (!fixAllFinite(outputs[0]))
        {
            logFail(kName, std::format("{}: a non-finite sample reached the output", c.name));
            return;
        }
        if (!fixSameBits(outputs[0], outputs[1]))
        {
            logFail(kName,
                    std::format("{}: the output differs from the same input with zeros in "
                                "place of the non-finite samples",
                                c.name));
            return;
        }
    }
    logPass(kName);
}

// ---------------------------------------------------------------------------
// Limiter_NonFiniteInput_StaysFinite — amendment 14, the limiter's own guard (no kernel scrub in
// front of it here). A NaN / ±Inf sample enters the look-ahead ring as silence: the output is
// finite, bit-identical to the run with zeros in place, and the gain envelope never goes to −Inf
// dB or NaN — on a loud programme (the limiter working) and a quiet one, through process() and
// through prime() followed by process().
// ---------------------------------------------------------------------------
static auto testLimiterNonFiniteInputStaysFinite() -> void
{
    static const char* const kName = "Limiter_NonFiniteInput_StaysFinite";
    constexpr uint32_t kBlocks = 12U;
    for (const double amplitude : {0.3, 1.4})
    {
        for (const bool primed : {false, true})
        {
            std::array<std::vector<float>, 2> outputs;
            for (size_t run = 0; run < outputs.size(); ++run)
            {
                LimiterModule limiter;
                limiter.initialize(static_cast<uint32_t>(kEngineFs), kEngineBlock);
                const LimiterParams params; // −1 dBTP
                TestABL abl(kEngineBlock);
                for (uint32_t block = 0U; block < kBlocks; ++block)
                {
                    fixProgrammeBlock(abl, static_cast<uint64_t>(block) * kEngineBlock, amplitude);
                    fixPoison(abl, block, run == 1U);
                    const MultichannelView view =
                        MultichannelView::fromABL(abl.abl(), kEngineBlock);
                    // `primed`: the poisoned blocks go by on the bit-perfect path (ring only).
                    if (primed && block <= 4U)
                    {
                        limiter.prime(view);
                        continue;
                    }
                    limiter.process(params, view);
                    outputs[run].insert(outputs[run].end(), abl.left.begin(), abl.left.end());
                    outputs[run].insert(outputs[run].end(), abl.right.begin(), abl.right.end());
                }
            }
            const std::string label = std::format(
                "amplitude {}, {}", amplitude, primed ? "prime() then process()" : "process()");
            if (!fixAllFinite(outputs[0]))
            {
                logFail(kName, std::format("{}: a non-finite sample left the limiter", label));
                return;
            }
            if (!fixSameBits(outputs[0], outputs[1]))
            {
                logFail(
                    kName,
                    std::format("{}: the output differs from the run with zeros in place", label));
                return;
            }
        }
    }
    logPass(kName);
}

// ---------------------------------------------------------------------------
// LufsMeter_NonFiniteSample_IsSilence — amendment 14, the meter's own guard: a NaN / ±Inf sample
// is measured as silence, so every reading equals (exactly) the reading of the same programme with
// zeros in place — and none of them is the −200 "silence" sentinel a poisoned K-weighting state
// used to leave behind for the rest of the session. Both feed layouts.
// ---------------------------------------------------------------------------
static auto testLufsMeterNonFiniteSampleIsSilence() -> void
{
    static const char* const kName = "LufsMeter_NonFiniteSample_IsSilence";
    for (const bool interleaved : {true, false})
    {
        for (const float poison : kFixNonFinite)
        {
            const std::unique_ptr<LufsMeter> poisoned = fixMeteredTone(poison, interleaved);
            const std::unique_ptr<LufsMeter> silenced = fixMeteredTone(0.0F, interleaved);
            const LufsMeter& bad = *poisoned;
            const LufsMeter& clean = *silenced;
            if (bad.integratedLufs() != clean.integratedLufs() ||
                bad.shortTermLufs() != clean.shortTermLufs() ||
                bad.momentaryLufs() != clean.momentaryLufs() || !(bad.integratedLufs() > -70.0) ||
                !(bad.shortTermLufs() > -70.0))
            {
                logFail(kName,
                        std::format("{} feed, a {} sample: integrated {:.3f} (clean {:.3f}), "
                                    "short-term {:.3f} (clean {:.3f}) LUFS",
                                    interleaved ? "interleaved" : "planar",
                                    poison,
                                    bad.integratedLufs(),
                                    clean.integratedLufs(),
                                    bad.shortTermLufs(),
                                    clean.shortTermLufs()));
                return;
            }
        }
    }
    logPass(kName);
}

// ---------------------------------------------------------------------------
// EQ_Transitions_SinglePoints — amendment 15, the everyday gesture the one-τ rule got wrong: one
// point pulled to ±12 dB (and back), at every third band from 20 Hz to 20 kHz, plus the bass cuts
// the break-it's red test does not cover (−6 / −8 dB at 20–63 Hz, both directions). Each band now
// glides at its own τ: local ≤ +1.0 dB (never a moment above +1 dB) and peak ≤ +0.6 dB. (The
// worst, +0.56 dB, is a −12 dB cut at 158 Hz: its flanking bells rise a little ahead of it, a
// few ms above the 0 dB around it. A ±12 dB point is the extreme gesture; the presets and Tone
// stay within EQ_Transitions_Realistic's +0.5 dB.)
// ---------------------------------------------------------------------------
static auto testEqTransitionsSinglePoints() -> void
{
    static const char* const kName = "EQ_Transitions_SinglePoints";
    constexpr double kFs = 48000.0;
    constexpr double kLocalBoundDb = 1.0;
    constexpr double kPeakBoundDb = 0.6;
    const auto switchFrame = static_cast<uint32_t>(0.5 * kFs);
    const auto totalFrames = static_cast<uint32_t>(1.3 * kFs);
    const std::vector<double> probes = tdProbes(2U);
    std::vector<std::pair<size_t, float>> points;
    for (size_t band = 0U; band < static_cast<size_t>(kEqBandCount); band += 3U)
    {
        points.emplace_back(band, 12.0F);
        points.emplace_back(band, -12.0F);
    }
    for (size_t band = 0U; band <= 5U; ++band)
    {
        points.emplace_back(band, -6.0F);
        points.emplace_back(band, -8.0F);
    }
    double worstLocal = -std::numeric_limits<double>::infinity();
    double worstPeak = -std::numeric_limits<double>::infinity();
    std::string worstName;
    std::string failures;
    std::string report;
    for (const auto& [band, gain] : points)
    {
        const EqCurve point = eqFlatCurveWith(band, gain);
        const double hz = GraphicEQ::centreHz(static_cast<int>(band));
        for (const bool release : {false, true})
        {
            const std::string name = release
                                         ? std::format("{:+.0f} dB @ {:.0f} Hz → Off", gain, hz)
                                         : std::format("Off → {:+.0f} dB @ {:.0f} Hz", gain, hz);
            const TdOvershoot result =
                tdOvershoot(release ? tdPairEvents(point, EqCurve{}, kFs, switchFrame)
                                    : tdPairEvents(EqCurve{}, point, kFs, switchFrame),
                            probes,
                            kFs,
                            switchFrame,
                            totalFrames);
            if (result.localDb > worstLocal)
            {
                worstLocal = result.localDb;
                worstName = std::format("{} @ {:.0f} Hz", name, result.localProbeHz);
            }
            worstPeak = std::max(worstPeak, result.peakDb);
            report += std::format("[info]   {:26s} local {:+5.2f} @ {:5.0f} Hz / peak {:+5.2f}\n",
                                  name,
                                  result.localDb,
                                  result.localProbeHz,
                                  result.peakDb);
            if (!(result.localDb <= kLocalBoundDb) || !(result.peakDb <= kPeakBoundDb))
            {
                failures += std::format(
                    "{}: local {:+.3f} dB @ {:.0f} Hz (≤ {}), peak {:+.3f} dB "
                    "(≤ {}); ",
                    name,
                    result.localDb,
                    result.localProbeHz,
                    kLocalBoundDb,
                    result.peakDb,
                    kPeakBoundDb);
            }
        }
    }
    if (!failures.empty())
    {
        logInfo(report);
        logFail(kName, failures);
        return;
    }
    logInfo(
        std::format("[info] {}: {} transitions, worst local {:+.3f} dB ({}), worst peak "
                    "{:+.3f} dB\n",
                    kName,
                    2U * points.size(),
                    worstLocal,
                    worstName,
                    worstPeak));
    logPass(kName);
}

namespace
{
    // How long (ms) after the switch a band's own centre tone takes to settle within 10 % (in
    // dB) of the change, gliding from `from` to `to` by the τ rule.
    auto fixSettleMs(const EqCurve& from, const EqCurve& to, size_t band, double fs) -> double
    {
        const auto switchFrame = static_cast<uint32_t>(0.25 * fs);
        const auto totalFrames = static_cast<uint32_t>(1.5 * fs);
        const double hz = GraphicEQ::centreHz(static_cast<int>(band));
        const GraphicEQDesign a = tdDesign(from, fs);
        const GraphicEQDesign b = tdDesign(to, fs);
        const double fromDb = GraphicEQDesigner::playedDb(a, hz);
        const double toDb = GraphicEQDesigner::playedDb(b, hz);
        const double tolerance = 0.1 * std::abs(toDb - fromDb);
        const std::vector<TdEvent> events = tdPairEvents(from, to, fs, switchFrame);
        auto module = std::make_unique<EQModule>();
        module->initialize(static_cast<uint32_t>(fs), kTdBlockFrames);
        TestABLN abl(2U, kTdBlockFrames);
        const std::vector<double> probe = {hz};
        size_t next = 0U;
        uint32_t lastOutside = switchFrame;
        for (uint32_t start = 0U; start < totalFrames; start += kTdBlockFrames)
        {
            const uint32_t frames = std::min(kTdBlockFrames, totalFrames - start);
            for (; next < events.size() && events[next].frame <= start; ++next)
            {
                module->update(events[next].params);
            }
            tdFillProbes(abl, probe, fs, start, frames);
            module->process(MultichannelView::fromABL(abl.abl(), frames));
            for (uint32_t i = 0U; i < frames; ++i)
            {
                const double envDb =
                    20.0 * std::log10(std::hypot(abl.channels[0][i], abl.channels[1][i]) /
                                      kTdProbeAmplitude);
                if (start + i >= switchFrame && std::abs(envDb - toDb) > tolerance)
                {
                    lastOutside = start + i;
                }
            }
        }
        return 1000.0 * static_cast<double>(lastOutside - switchFrame) / fs;
    }
} // namespace

// ---------------------------------------------------------------------------
// EQ_SinglePoint_SettlesFast — amendment 15: "a single ±12 point must settle in ≤ ~30 ms (today it
// takes 371 ms)". Measured on the band's own centre tone through the real module: Off → ±12 dB and
// the key step +11 → +12, at every band from 1 kHz up, reach 90 % of the change (in dB) within
// 35 ms — the 10 ms floor's own 90 % on the (k, m1) path is ~2.6 τ, plus the bell's ring and the
// probe's beat; measured 25–33 ms.
// Below 1 kHz a band glides at its own ring time (the physics, not a class): the settle times are
// reported down to 20 Hz.
// ---------------------------------------------------------------------------
static auto testEqSinglePointSettlesFast() -> void
{
    static const char* const kName = "EQ_SinglePoint_SettlesFast";
    constexpr double kFs = 48000.0;
    constexpr double kBoundMs = 35.0;       // amendment 15: "≤ ~30 ms"
    constexpr size_t kFirstBoundBand = 17U; // 1 kHz
    std::string report = std::format(
        "[info] {}: 90 % settle (ms) at the band's centre — "
        "Off → +12 / Off → −12 / +11 → +12\n",
        kName);
    for (size_t band = 0U; band < static_cast<size_t>(kEqBandCount); band += 2U)
    {
        const std::array<double, 3> settle = {
            fixSettleMs(EqCurve{}, eqFlatCurveWith(band, 12.0F), band, kFs),
            fixSettleMs(EqCurve{}, eqFlatCurveWith(band, -12.0F), band, kFs),
            fixSettleMs(eqFlatCurveWith(band, 11.0F), eqFlatCurveWith(band, 12.0F), band, kFs),
        };
        report += std::format("[info]   {:6.0f} Hz: {:6.1f} / {:6.1f} / {:6.1f}\n",
                              GraphicEQ::centreHz(static_cast<int>(band)),
                              settle[0],
                              settle[1],
                              settle[2]);
        if (band >= kFirstBoundBand && !(std::ranges::max(settle) <= kBoundMs))
        {
            logInfo(report);
            logFail(kName,
                    std::format("{:.0f} Hz takes {:.1f} ms to settle (≤ {})",
                                GraphicEQ::centreHz(static_cast<int>(band)),
                                std::ranges::max(settle),
                                kBoundMs));
            return;
        }
    }
    logInfo(report);
    logPass(kName);
}

namespace
{
    // The level (dB re the tone's own amplitude) in consecutive 5 ms windows of `out` from `from`.
    auto fixLevelTrace(const std::vector<float>& out, size_t from, double amplitude)
        -> std::vector<double>
    {
        constexpr size_t kWindow = 240U; // 5 ms at 48 kHz
        std::vector<double> levels;
        for (size_t n = from; n + kWindow <= out.size(); n += kWindow)
        {
            double energy = 0.0;
            for (size_t k = n; k < n + kWindow; ++k)
            {
                energy += static_cast<double>(out[k]) * out[k];
            }
            levels.push_back(10.0 * std::log10(std::max(energy / kWindow, 1e-20) /
                                               (amplitude * amplitude / 2.0)));
        }
        return levels;
    }

    struct FixGlide
    {
        double swingDb = 0.0;       // the level after − the level before
        double tenToNinetyMs = 0.0; // how long the middle 80 % of the swing takes
        double firstMoveDb = 0.0;   // the largest move from `before` while Intensity ramps
        double worst50MsDb = 0.0;   // the largest level change over any 50 ms after that
    };

    // The level glide in `levels` (5 ms windows), against the level just before it. The first
    // 200 ms are the Intensity ramp's own (τ 32 ms: the blend law moves the level there).
    auto fixGlide(const std::vector<double>& levels, double before) -> FixGlide
    {
        FixGlide glide;
        glide.swingDb = levels.back() - before;
        double t10 = -1.0;
        double t90 = -1.0;
        constexpr size_t kFiftyMs = 10U;
        constexpr size_t kRampWindows = 40U; // 200 ms
        for (size_t i = 0; i < levels.size(); ++i)
        {
            const double progress = (levels[i] - before) / glide.swingDb;
            const double ms = 5.0 * static_cast<double>(i);
            t10 = (t10 < 0.0 && progress >= 0.1) ? ms : t10;
            t90 = (t90 < 0.0 && progress >= 0.9) ? ms : t90;
            if (i < kRampWindows)
            {
                glide.firstMoveDb = std::max(glide.firstMoveDb, std::abs(levels[i] - before));
            }
            else
            {
                glide.worst50MsDb =
                    std::max(glide.worst50MsDb, std::abs(levels[i] - levels[i - kFiftyMs]));
            }
        }
        glide.tenToNinetyMs = t90 - t10;
        return glide;
    }

    // The equal-power blend's own level (dB) at Intensity r when wet == dry: cos + sin.
    auto fixBlendLawDb(double intensity) -> double
    {
        const double angle = intensity * std::numbers::pi / 2.0;
        return 20.0 * std::log10(std::cos(angle) + std::sin(angle));
    }
} // namespace

// ---------------------------------------------------------------------------
// Intensity_Zero_LevelGlide — founder decision 33 (amendment 16): crossing Intensity 0 glides the
// level over ~2 s. With the normaliser adapted to a loud (or quiet) tone at r = 0.3, r → 0 used
// to swing the whole makeup in ~0.1 s (+10 dB / −14.6 dB, 8.8 dB in the worst 50 ms; the
// break-it's finding 4), because the contribution followed r. Measured as level over time (5 ms
// windows), both ways across 0:
//   - the swing still happens (≥ 6 dB: the normaliser's makeup really leaves and rejoins);
//   - its middle 80 % takes ≥ 1 s (the blend law's quick move at the start shortens the ideal
//     linear glide's 1.6 s; the old behaviour took ~0.07 s);
//   - while Intensity itself ramps (the first 200 ms) the level moves by no more than the
//     equal-power blend's own change (wet == dry here: up to 2.6 dB for r 0.3) + 1.5 dB (the
//     glide's own share of those 200 ms is 0.1 × a makeup of up to 12 dB);
//   - after that, no 50 ms moves it by more than 0.5 dB (a 12 dB glide over 2 s is 0.3).
// Serial-only: paced so the measurement worker keeps up.
// ---------------------------------------------------------------------------
static auto testIntensityZeroLevelGlide() -> void
{
    static const char* const kName = "Intensity_Zero_LevelGlide";
    constexpr double kMinSwingDb = 6.0;
    constexpr double kMinGlideMs = 1000.0;
    constexpr double kRampAllowanceDb = 1.5;
    constexpr double kWorst50MsBoundDb = 0.5;
    constexpr float kStartIntensity = 0.3F;
    const double blendLawDb = fixBlendLawDb(kStartIntensity);
    std::string report = std::format(
        "[info] {}: swing / 10–90 % time / move while Intensity "
        "ramps (blend law {:.2f} dB) / worst 50 ms after\n",
        kName,
        blendLawDb);
    std::string failures;
    for (const double amplitude : {0.5, 0.02}) // loud: the normaliser cuts; quiet: it boosts
    {
        TargetState state{}; // normaliser ON (−16 LUFS), limiter ON
        state.clarity.enabled = 0U;
        state.intensityLinear = kStartIntensity;
        DSPKernel kernel;
        kernel.publishTargetState(state);
        kernel.initialize(static_cast<uint32_t>(kEngineFs), kEngineBlock);
        EngineSine sine;
        sine.amplitude = amplitude;
        std::vector<float> out;
        for (uint32_t b = 0U; b < engineBlocksFor(12.0); ++b)
        {
            engineRunSine(kernel, sine, 1U, out);
            std::this_thread::sleep_for(std::chrono::milliseconds(1));
        }
        for (const float to : {0.0F, kStartIntensity})
        {
            const size_t switchAt = out.size();
            const double before =
                fixLevelTrace(out, switchAt - (static_cast<size_t>(kEngineBlock) * 2U), amplitude)
                    .back();
            state.intensityLinear = to;
            kernel.publishTargetState(state);
            engineRunSine(kernel, sine, engineBlocksFor(3.5), out);
            const FixGlide glide = fixGlide(fixLevelTrace(out, switchAt, amplitude), before);
            const std::string name = std::format("tone {:.2f} FS, r → {:.1f}", amplitude, to);
            report +=
                std::format("[info]   {:22s} {:+6.2f} dB / {:6.0f} ms / {:.2f} dB / {:.2f} dB\n",
                            name,
                            glide.swingDb,
                            glide.tenToNinetyMs,
                            glide.firstMoveDb,
                            glide.worst50MsDb);
            const bool glided = std::abs(glide.swingDb) >= kMinSwingDb &&
                                glide.tenToNinetyMs >= kMinGlideMs &&
                                glide.firstMoveDb <= blendLawDb + kRampAllowanceDb &&
                                glide.worst50MsDb <= kWorst50MsBoundDb;
            if (!glided)
            {
                failures += std::format(
                    "{}: swing {:+.2f} dB (≥ {}), 10–90 % in {:.0f} ms (≥ {}), {:.2f} dB while "
                    "Intensity ramps (≤ {:.2f}), worst 50 ms after {:.2f} dB (≤ {}); ",
                    name,
                    glide.swingDb,
                    kMinSwingDb,
                    glide.tenToNinetyMs,
                    kMinGlideMs,
                    glide.firstMoveDb,
                    blendLawDb + kRampAllowanceDb,
                    glide.worst50MsDb,
                    kWorst50MsBoundDb);
            }
        }
    }
    logInfo(report);
    if (!failures.empty())
    {
        logFail(kName, failures);
        return;
    }
    logPass(kName);
}

namespace
{
    struct FixP0Step
    {
        double stepLu = 0.0;    // how much quieter the EQ-only path played than the source
        double p0Seconds = 0.0; // when the bit-perfect path took over (0: never)
    };

    // The gate's −9 LUFS loud master at Intensity 0 through the kernel: EQ Warm, then Off at 3 s,
    // on an output whose EQ-only ceiling is `eqOnlyCeiling`. Compares the 1.5 s before the
    // bit-perfect path takes over with the source there (libebur128): the level step entering P0.
    auto fixP0Step(float eqOnlyCeiling) -> FixP0Step
    {
        const TlProgramme& master = tlGateLoudMaster();
        const auto fs = static_cast<uint32_t>(master.sampleRate);
        TargetState state{}; // normaliser ON, limiter ON at −1 dBTP
        state.intensityLinear = 0.0F;
        state.limiter.eqOnlyCeilingLinear = eqOnlyCeiling;
        state.eq = makeEqParams(kEqPresetCurves[kEqPresetWarm], fs);
        DSPKernel kernel;
        kernel.publishTargetState(state);
        kernel.initialize(fs, kEngineBlock);
        TestABL abl(kEngineBlock);
        std::array<std::vector<float>, 2> out;
        const size_t total = std::min<size_t>(master.frames(), static_cast<size_t>(8U) * fs);
        const size_t offAt = static_cast<size_t>(3U) * fs;
        size_t p0 = 0U;
        for (size_t start = 0U; start + kEngineBlock <= total; start += kEngineBlock)
        {
            if (start <= offAt && offAt < start + kEngineBlock)
            {
                state.eq = makeEqParams(EqCurve{}, fs);
                kernel.publishTargetState(state);
            }
            const auto offset = static_cast<std::ptrdiff_t>(start);
            std::copy_n(master.channels[0].begin() + offset, kEngineBlock, abl.left.begin());
            std::copy_n(master.channels[1].begin() + offset, kEngineBlock, abl.right.begin());
            kernel.process(abl.abl(), kEngineBlock);
            const bool exact =
                std::equal(abl.left.begin(), abl.left.end(), master.channels[0].begin() + offset) &&
                std::equal(abl.right.begin(), abl.right.end(), master.channels[1].begin() + offset);
            if (p0 == 0U && start > offAt && exact)
            {
                p0 = start;
            }
            out[0].insert(out[0].end(), abl.left.begin(), abl.left.end());
            out[1].insert(out[1].end(), abl.right.begin(), abl.right.end());
        }
        if (p0 == 0U)
        {
            return {};
        }
        const auto span = static_cast<std::ptrdiff_t>(fs) + static_cast<std::ptrdiff_t>(fs / 2U);
        const auto end = static_cast<std::ptrdiff_t>(p0);
        const auto window = [&](const auto& channels)
        {
            return std::vector<std::vector<float>>{
                std::vector<float>(channels[0].begin() + end - span, channels[0].begin() + end),
                std::vector<float>(channels[1].begin() + end - span, channels[1].begin() + end),
            };
        };
        const double played = tlEbur128Lufs(window(out), master.sampleRate);
        const double source = tlEbur128Lufs(window(master.channels), master.sampleRate);
        return {
            .stepLu = source - played,
            .p0Seconds = static_cast<double>(p0) / master.sampleRate,
        };
    }
} // namespace

// ---------------------------------------------------------------------------
// Kernel_P0Switch_LoudMasterStep — amendment 17 (the break-it's finding 9): on a loud master at
// Intensity 0, an EQ turned Off (or a Compare held past 2 s) plays through the EQ-only limiter
// until the bit-perfect path takes over — and then the limiter's gain reduction lifts at once.
// That step was +0.74 LU at −1 dBTP. With decision 29's ceiling on a wired output (−0.1 dBTP) it
// must be ≤ 0.3 LU; a lossy wireless output keeps −1 dBTP (logged).
// ---------------------------------------------------------------------------
static auto testKernelP0SwitchLoudMasterStep() -> void
{
    static const char* const kName = "Kernel_P0Switch_LoudMasterStep";
    constexpr double kStepBoundLu = 0.3;
    const FixP0Step wired = fixP0Step(kEqOnlyWiredCeilingLinear);
    const FixP0Step wireless = fixP0Step(kTruePeakCeilingLinear);
    logInfo(
        std::format("[info] {}: level step entering bit-perfect on the −9 LUFS loud master — "
                    "wired (−0.1 dBTP) {:+.3f} LU at {:.2f} s, Bluetooth (−1 dBTP, logged) "
                    "{:+.3f} LU at {:.2f} s\n",
                    kName,
                    wired.stepLu,
                    wired.p0Seconds,
                    wireless.stepLu,
                    wireless.p0Seconds));
    if (wired.p0Seconds == 0.0 || wireless.p0Seconds == 0.0)
    {
        logFail(kName, "the bit-perfect path never took over");
        return;
    }
    if (!(std::abs(wired.stepLu) <= kStepBoundLu))
    {
        logFail(kName,
                std::format(
                    "a {:+.3f} LU step entering bit-perfect (≤ {})", wired.stepLu, kStepBoundLu));
        return;
    }
    logPass(kName);
}

namespace
{
    // Fills block `abl` with the signal from frame `first` on.
    using FixFill = std::function<void(TestABLN&, uint64_t)>;

    struct FixFade
    {
        double fadePowerDb = 0.0; // Σ out² / Σ in² over the middle 60 % of the P0 → P1 fades
        double lowestDb = 0.0;    // the envelope's extremes over the whole run (quadrature pairs)
        double highestDb = 0.0;
    };

    // Intensity 0, the normaliser off: three cycles of P0 → (EQ on: a −0.5 dB bell at 20 Hz, so
    // nearly flat) P1 → (EQ off; the 2 s hysteresis) P0 on `channels` channels of `fill`. The
    // P0 → P1 fade starts exactly with the block after the publish, so its power is read there;
    // for quadrature pairs (cos on channel 2p, sin on 2p + 1) the envelope |out| / |in| is exact
    // at every sample, so its extremes over the whole run cover both directions' fades.
    auto fixFade(uint32_t channels, const FixFill& fill) -> FixFade
    {
        const auto fs = static_cast<uint32_t>(kEngineFs);
        TargetState state{};
        state.loudness.enabled = 0U;
        state.intensityLinear = 0.0F;
        DSPKernel kernel;
        kernel.publishTargetState(state); // P0 from the first block
        kernel.initialize(fs, kEngineBlock);
        TestABLN abl(channels, kEngineBlock);
        const auto fadeFrames = static_cast<uint32_t>(0.005 * kEngineFs);
        uint64_t frame = 0U;
        double outEnergy = 0.0;
        double inEnergy = 0.0;
        FixFade fade{
            .lowestDb = std::numeric_limits<double>::infinity(),
            .highestDb = -std::numeric_limits<double>::infinity(),
        };
        std::vector<std::vector<float>> input(channels);
        const auto runBlock = [&](bool foldFade)
        {
            fill(abl, frame);
            for (uint32_t ch = 0U; ch < channels; ++ch)
            {
                input[ch] = abl.channels[ch];
            }
            kernel.process(abl.abl(), kEngineBlock);
            frame += kEngineBlock;
            for (uint32_t ch = 0U; ch < channels; ++ch)
            {
                for (uint32_t i = foldFade ? fadeFrames / 5U : kEngineBlock;
                     i < (4U * fadeFrames) / 5U;
                     ++i)
                {
                    outEnergy += static_cast<double>(abl.channels[ch][i]) * abl.channels[ch][i];
                    inEnergy += static_cast<double>(input[ch][i]) * input[ch][i];
                }
            }
            for (uint32_t pair = 0U; pair + 1U < channels; pair += 2U)
            {
                for (uint32_t i = 0U; i < kEngineBlock; ++i)
                {
                    const double ratio =
                        std::hypot(abl.channels[pair][i], abl.channels[pair + 1U][i]) /
                        std::hypot(input[pair][i], input[pair + 1U][i]);
                    fade.lowestDb = std::min(fade.lowestDb, 20.0 * std::log10(ratio));
                    fade.highestDb = std::max(fade.highestDb, 20.0 * std::log10(ratio));
                }
            }
        };
        for (uint32_t b = 0U; b < engineBlocksFor(0.1); ++b)
        {
            runBlock(false); // P0, its limiter ring primed: the fades below have both streams
        }
        for (int cycle = 0; cycle < 3; ++cycle)
        {
            state.eq = makeEqParams(eqFlatCurveWith(0U, -0.5F), fs);
            kernel.publishTargetState(state);
            runBlock(true); // P0 → P1 fades here
            for (uint32_t b = 0U; b < engineBlocksFor(0.3); ++b)
            {
                runBlock(false);
            }
            state.eq = makeEqParams(EqCurve{}, fs);
            kernel.publishTargetState(state);
            for (uint32_t b = 0U; b < engineBlocksFor(2.6); ++b) // P1 → P0 fades in here
            {
                runBlock(false);
            }
        }
        fade.fadePowerDb = 10.0 * std::log10(outEnergy / inEnergy);
        return fade;
    }

    // A quadrature tone at `hz` on every channel pair.
    auto fixQuadratureFill(double hz, double amplitude) -> FixFill
    {
        return [hz, amplitude](TestABLN& abl, uint64_t first)
        {
            const double omega = 2.0 * std::numbers::pi * hz / kEngineFs;
            for (uint32_t i = 0U; i < abl.frames; ++i)
            {
                const double phase = omega * static_cast<double>(first + i);
                for (uint32_t pair = 0U; pair + 1U < abl.numChannels; pair += 2U)
                {
                    abl.channels[pair][i] = static_cast<float>(amplitude * std::cos(phase));
                    abl.channels[pair + 1U][i] = static_cast<float>(amplitude * std::sin(phase));
                }
            }
        };
    }
} // namespace

// ---------------------------------------------------------------------------
// Kernel_P0Fade_KeepsPower — amendment 17: the 5 ms fade between the bit-perfect path and the
// processed one keeps the level. The two streams are the same audio 3 ms apart; the equal-GAIN
// fade dipped broadband audio −3.3 dB mid-way (the break-it's finding 9), and a plain equal-power
// one would bump a tone that lines up with itself (1 kHz: 3 whole periods) +3 dB. The fade now
// keeps each channel's power for the correlation it measures when it starts:
//   - white noise on 8 channels: the power over the middle of the P0 → P1 fades within ±0.5 dB of
//     the input's (equal-gain: −2.5 dB there);
//   - quadrature tones at 60 Hz (65° apart: a −1.5 dB dip at equal gain) and 1 kHz (in phase: a
//     +3 dB bump at equal power): the envelope within ±0.5 dB of the input's at every sample of
//     the run, both directions' fades included.
// ---------------------------------------------------------------------------
static auto testKernelP0FadeKeepsPower() -> void
{
    static const char* const kName = "Kernel_P0Fade_KeepsPower";
    constexpr double kNoiseBoundDb = 0.5;
    constexpr double kToneBoundDb = 0.5;
    constexpr uint32_t kNoiseChannels = 8U;
    std::mt19937 rng(17U);
    std::normal_distribution<float> gauss(0.0F, 0.05F);
    const FixFade noise =
        fixFade(kNoiseChannels,
                [&](TestABLN& abl, uint64_t /*first*/)
                {
                    for (auto& channel : abl.channels)
                    {
                        std::ranges::generate(channel, [&] { return gauss(rng); });
                    }
                });
    const FixFade low = fixFade(2U, fixQuadratureFill(60.0, 0.25));
    const FixFade mid = fixFade(2U, fixQuadratureFill(1000.0, 0.25));
    logInfo(
        std::format("[info] {}: white noise, fade power {:+.3f} dB; 60 Hz envelope "
                    "{:+.3f} … {:+.3f} dB; 1 kHz envelope {:+.3f} … {:+.3f} dB\n",
                    kName,
                    noise.fadePowerDb,
                    low.lowestDb,
                    low.highestDb,
                    mid.lowestDb,
                    mid.highestDb));
    const bool noiseKept = std::abs(noise.fadePowerDb) <= kNoiseBoundDb;
    const bool tonesKept = std::max({
                               std::abs(low.lowestDb),
                               std::abs(low.highestDb),
                               std::abs(mid.lowestDb),
                               std::abs(mid.highestDb),
                           }) <= kToneBoundDb;
    if (!noiseKept || !tonesKept)
    {
        logFail(kName,
                std::format("noise fade power {:+.3f} dB (±{}), tone envelopes 60 Hz {:+.3f} … "
                            "{:+.3f}, 1 kHz {:+.3f} … {:+.3f} dB (±{})",
                            noise.fadePowerDb,
                            kNoiseBoundDb,
                            low.lowestDb,
                            low.highestDb,
                            mid.lowestDb,
                            mid.highestDb,
                            kToneBoundDb));
        return;
    }
    logPass(kName);
}

// ---------------------------------------------------------------------------
// EQ_Cpu_7_1_AboveSupportedRates — amendment 18 (the break-it's finding 11): the designer, the
// Realizer and the module accept rates up to 768 kHz, above the pipeline's supported 192 kHz, and
// there the EQ cost 4.4–4.7 % (384 kHz × 8) and 8.7–9.4 % (768 kHz × 8) of one core — over the
// 192 kHz budget. The work per sample is the same at every rate (31 bells per channel), so the
// budget is stated per rate: 5 % × fs / 192 kHz — 10 % at 384 kHz, 20 % at 768 kHz (a margin for
// the M1 Pro floor's ×1.4–1.8). Holding the EQ off above a cap was rejected: the graph would no
// longer be what plays. Optimised builds only; -O0 and the sanitizers report. Serial-only.
// ---------------------------------------------------------------------------
static auto testEqCpu71AboveSupportedRates() -> void
{
    static const char* const kName = "EQ_Cpu_7_1_AboveSupportedRates";
    constexpr uint32_t kSeconds = 1U;
    std::string report =
        std::format("[info] {} ({} build): 8 ch, % of one core\n", kName, kTdCpuBuild);
    std::string failures;
    for (const uint32_t fs : {384000U, 768000U})
    {
        const double budget = tdEqCpuBudgetPercent(fs);
        const TdCpu cpu = tdEqCpuPercent(fs, kSeconds);
        report +=
            std::format("[info]   {:3d} kHz: settled {:.2f} %, gliding {:.2f} % (budget {} %)\n",
                        fs / 1000U,
                        cpu.settled,
                        cpu.gliding,
                        budget);
        if (!(std::max(cpu.settled, cpu.gliding) <= budget))
        {
            failures += std::format("{} kHz: {:.2f} % of one core exceeds {} %; ",
                                    fs / 1000U,
                                    std::max(cpu.settled, cpu.gliding),
                                    budget);
        }
    }
    logInfo(report);
    if (!failures.empty())
    {
        logFail(kName, failures);
        return;
    }
    logPass(kName);
}
