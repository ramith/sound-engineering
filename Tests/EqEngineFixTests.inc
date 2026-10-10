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
