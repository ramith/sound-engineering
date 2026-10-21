// EqEngineBreakItTests.inc
//
// Sprint EQ — the adversarial break-it pass on the IMPLEMENTED EQ engine (EQ1a designer, EQ1b
// real-time module / Realizer / kernel paths, EQ1c profiler). #included into
// Tests/DSPKernelNullTest.cpp after EqEngineTests.inc (it reuses that file's and
// EqTransitionTests.inc's helpers). Each test here is RED on the branch it was written against: it
// pins a defect the builders' own gate does not see. The measurement half (durations, latencies,
// spectra) lives in research/eq-engine-break-it/.

#include "../Sources/AudioDSP/Loudness/LoudnessModule.h"

namespace
{
    // ---------------------------------------------------------------------------------------------
    // Shared break-it helpers.
    // ---------------------------------------------------------------------------------------------

    // max |solved gain| of a design (the τ rule's jaggedness measure).
    auto breakItMaxSolvedGainDb(const EqCurve& curve, double fs) -> double
    {
        const GraphicEQDesign design = tdDesign(curve, fs);
        double largest = 0.0;
        for (const double gain : design.filterGainDb)
        {
            largest = std::max(largest, std::abs(gain));
        }
        return largest;
    }

} // namespace

// ---------------------------------------------------------------------------
// BreakIt_InfInput_KernelRecovers — engine-plan §7 / EQ_NaNInput_Recovers claim "a bad input
// recovers within one block (module) / two (kernel)". A single +Inf sample (a corrupt 32-bit float
// file decodes to one) passes the EQ's state guard, but the limiter's true-peak detector reads
// |Inf| = Inf: the gain envelope goes to −Inf dB, then its release computes −Inf + Inf = NaN and
// stays NaN — every later block is NaN (or silence) until the kernel is re-initialised. Checked on
// the EQ-only path (P1), the full path (P2), and on leaving the bit-perfect path (P0) after an Inf
// went by there (the primed ring re-seeds the detector with it).
// ---------------------------------------------------------------------------
static auto testBreakItInfInputKernelRecovers() -> void
{
    static const char* const kName = "BreakIt_InfInput_KernelRecovers";
    const EQParams warm =
        makeEqParams(kEqPresetCurves[kEqPresetWarm], static_cast<uint32_t>(kEngineFs));
    struct Case
    {
        const char* name;
        float intensity;
        bool eqOnDuringInf;
        bool eqOnAfter;
        double secondsBefore; // < 2 s: the identity has not yet entered P0
        uint32_t infIndex;    // where in the block the +Inf lands
    };
    // (An EQ that is ON turns the Inf into NaN inside its cascade — v0 + m1·v1 with mixed-sign m1
    // gives Inf − Inf — and the limiter's std::max swallows a NaN, so those paths survive. The
    // identity EQ is skipped, so the Inf reaches the limiter as Inf.)
    constexpr std::array<Case, 5> kCases = {
        {
            {"P1, EQ Warm", 0.0F, true, true, 0.5, 200U},
            {"P2, EQ Warm", 1.0F, true, true, 0.5, 200U},
            {"P1, EQ off (inside the 2 s hysteresis)", 0.0F, false, false, 0.5, 200U},
            {"P2, EQ off", 1.0F, false, false, 0.5, 200U},
            {"P0 (bit-perfect), then EQ on", 0.0F, false, true, 3.0, 500U},
        },
    };
    std::string failures;
    for (const Case& c : kCases)
    {
        TargetState state{}; // normaliser and limiter ON (production defaults)
        state.intensityLinear = c.intensity;
        state.eq = c.eqOnDuringInf ? warm : EQParams{};
        DSPKernel kernel;
        kernel.publishTargetState(state);
        kernel.initialize(static_cast<uint32_t>(kEngineFs), kEngineBlock);
        EngineSine sine;
        sine.amplitude = 0.25;
        std::vector<float> out;
        engineRunSine(kernel, sine, engineBlocksFor(c.secondsBefore), out);
        // One block with a single +Inf sample in the left channel.
        TestABL abl(kEngineBlock);
        for (uint32_t i = 0U; i < kEngineBlock; ++i)
        {
            const double time = static_cast<double>(sine.sample + i) / kEngineFs;
            abl.left[i] = static_cast<float>(sine.amplitude *
                                             std::sin(2.0 * std::numbers::pi * sine.hz * time));
            abl.right[i] = abl.left[i];
        }
        abl.left[c.infIndex] = std::numeric_limits<float>::infinity();
        sine.sample += kEngineBlock;
        kernel.process(abl.abl(), kEngineBlock);
        if (!c.eqOnDuringInf && c.eqOnAfter)
        {
            state.eq = warm; // leave P0 now
            kernel.publishTargetState(state);
        }
        // One second of clean sine: from the third block on, every sample must be finite and the
        // level back near the clean level (the sine is far below the ceiling).
        out.clear();
        engineRunSine(kernel, sine, engineBlocksFor(1.0), out);
        size_t firstBad = out.size();
        for (size_t n = static_cast<size_t>(kEngineBlock) * 2U; n < out.size(); ++n)
        {
            if (!std::isfinite(out[n]))
            {
                firstBad = n;
                break;
            }
        }
        double tailPeak = 0.0;
        for (size_t n = out.size() - (static_cast<size_t>(kEngineBlock) * 10U); n < out.size(); ++n)
        {
            tailPeak = std::max(tailPeak, static_cast<double>(std::abs(out[n])));
        }
        logInfo(
            std::format("[info] {}: {}: first non-finite sample after the Inf block: {} "
                        "(of {}); last-100 ms peak {:.4f}\n",
                        kName,
                        c.name,
                        firstBad == out.size() ? std::string("none") : std::to_string(firstBad),
                        out.size(),
                        tailPeak));
        if (firstBad != out.size() || !(tailPeak > 0.05))
        {
            failures += std::format("{}: still {} 1 s after one +Inf sample; ",
                                    c.name,
                                    firstBad != out.size() ? "non-finite" : "silent");
        }
    }
    if (!failures.empty())
    {
        logFail(kName, failures);
        return;
    }
    logPass(kName);
}

namespace
{
    // Feed `seconds` of a loud 1 kHz tone (≈ −6 LUFS; the makeup slews toward −10 dB at 0.1 dB per
    // gated block) to `module`, the first block carrying `poison` (0: none) — and keep its meter up
    // by state: every kMeterCatchUpBlocks, and at the end, wait until it has measured what it was
    // handed. False if it never caught up (the hang cap failed the test).
    [[nodiscard]] auto bkFeedLoudTone(LoudnessModule& module,
                                      uint32_t fs,
                                      uint32_t blockFrames,
                                      uint64_t& n,
                                      double seconds,
                                      float poison) -> bool
    {
        TestABL abl(blockFrames);
        const auto blocks = static_cast<uint32_t>(seconds * fs / blockFrames);
        const LoudnessParams params; // production defaults: −16 LUFS, enabled
        const auto caughtUp = [&module]
        {
            return rig::waitUntil("the normaliser's meter measured every block it was handed",
                                  [&module] { return module.meterCaughtUp(); });
        };
        for (uint32_t b = 0U; b < blocks; ++b)
        {
            for (uint32_t i = 0U; i < blockFrames; ++i, ++n)
            {
                abl.left[i] = static_cast<float>(
                    0.5 * std::sin(2.0 * std::numbers::pi * 1000.0 * static_cast<double>(n) / fs));
                abl.right[i] = abl.left[i];
            }
            if (b == 0U && poison != 0.0F)
            {
                abl.left[100] = poison;
            }
            module.process(params, MultichannelView::fromABL(abl.abl(), blockFrames));
            if ((b % kMeterCatchUpBlocks) == kMeterCatchUpBlocks - 1U && !caughtUp())
            {
                return false;
            }
        }
        return caughtUp();
    }
} // namespace

// ---------------------------------------------------------------------------
// BreakIt_NonFiniteInput_NormaliserKeepsAdapting — the same guard claim, one stage later. The EQ
// zeroes its own states after a non-finite block, but that block's samples still reach the
// normaliser (P2 / P3). Its K-weighting biquads take the NaN into their state and never flush it:
// every later 100 ms hop is NaN, blockLoudness(NaN) reads as silence, nothing is gated in again,
// and the makeup gain FREEZES at whatever it was — for the rest of the session (until the AU
// re-allocates). One NaN or +Inf sample from a corrupt float file is enough.
// The meter keeps up by state: every 8 blocks the feed waits until it has measured what it was
// handed, and each reading follows a wait — no pacing sleeps, no fixed settles.
// ---------------------------------------------------------------------------
static auto testBreakItNonFiniteInputNormaliserKeepsAdapting() -> void
{
    static const char* const kName = "BreakIt_NonFiniteInput_NormaliserKeepsAdapting";
    constexpr uint32_t kFs = 48000U;
    constexpr uint32_t kBlock = 512U;
    const auto runSeconds = [](LoudnessModule& module, uint64_t& n, double seconds, float poison)
    { return bkFeedLoudTone(module, kFs, kBlock, n, seconds, poison); };
    std::string failures;
    for (const float poison :
         {std::numeric_limits<float>::quiet_NaN(), std::numeric_limits<float>::infinity()})
    {
        LoudnessModule module;
        module.initialize(kFs, kBlock);
        uint64_t n = 0U;
        if (!runSeconds(module, n, 3.0, 0.0F)) // adapting: the makeup is mid-slew here
        {
            return;
        }
        const double before = 20.0 * std::log10(module.currentMakeupGainLinear());
        if (!runSeconds(module, n, 0.02, poison) ||
            !runSeconds(module, n, 3.0, 0.0F)) // 3 s more of the same programme
        {
            return;
        }
        const double after = 20.0 * std::log10(module.currentMakeupGainLinear());
        const double shortTerm = module.measuredLufsShortTerm();
        logInfo(
            std::format("[info] {}: {} sample: makeup {:+.2f} dB before, {:+.2f} dB 3 s "
                        "after (still slewing toward ≈ −10 dB if healthy); short-term {:.1f} "
                        "LUFS\n",
                        kName,
                        std::isnan(poison) ? "NaN" : "+Inf",
                        before,
                        after,
                        shortTerm));
        // Healthy: 3 s of programme moves the makeup ≈ 2–3 dB further toward −10 dB, and the
        // short-term meter reads the tone (≈ −6 LUFS), not the −200 "silence" sentinel.
        if (!(after < before - 1.0) || !(shortTerm > -70.0))
        {
            failures += std::format(
                "{}: the normaliser froze (makeup {:+.2f} → {:+.2f} dB, "
                "short-term {:.1f} LUFS); ",
                std::isnan(poison) ? "NaN" : "+Inf",
                before,
                after,
                shortTerm);
        }
    }
    if (!failures.empty())
    {
        logFail(kName, failures);
        return;
    }
    logPass(kName);
}

// ---------------------------------------------------------------------------
// BreakIt_Transitions_LowBandGestures — EQ_Transitions_Realistic's own bound (local ≤ +0.75 dB,
// peak ≤ +0.5 dB at the rule's τ) on everyday BASS gestures its set does not contain: one point
// raised in the bottom octaves, switched in at once — what Compare's release (hold = Off,
// decision 28), the On toggle, choosing a My Preset or a click-to-place all do. The τ rule keys on
// the SIZE of the solved gains, but the overshoot comes from the ramp being fast against the
// low band's own time constant (a 20–63 Hz bell rings for 20–60 ms; τ is 10 ms): Off → +8 dB at
// 63 Hz swells the 50 Hz neighbourhood +2.5 dB for ~30 ms, and Off → +8 dB at 20 Hz breaks the
// PEAK bound too (+2.8 dB at 25 Hz, above the curve's own maximum, for ~80 ms) — while Off → +12
// dB at 1 kHz, sent to the 160 ms class, would have been clean at 10 ms (research/
// eq-engine-break-it, jagged-false-positives).
// ---------------------------------------------------------------------------
static auto testBreakItTransitionsLowBandGestures() -> void
{
    static const char* const kName = "BreakIt_Transitions_LowBandGestures";
    constexpr double kFs = 48000.0;
    constexpr double kLocalBoundDb = 0.75; // EQ_Transitions_Realistic's bound
    constexpr double kPeakBoundDb = 0.5;
    const auto switchFrame = static_cast<uint32_t>(0.5 * kFs);
    const auto totalFrames = static_cast<uint32_t>(1.1 * kFs);
    const std::vector<double> probes = tdProbes(1U);
    struct Case
    {
        std::string name;
        EqCurve from;
        EqCurve to;
    };
    std::vector<Case> cases;
    for (const size_t band : {0U, 1U, 2U, 3U, 4U, 5U}) // 20, 25, 32, 40, 50, 63 Hz
    {
        for (const float gain : {6.0F, 8.0F})
        {
            const EqCurve bump = eqFlatCurveWith(band, gain);
            const double hz = GraphicEQ::centreHz(static_cast<int>(band));
            cases.push_back(
                {std::format("Off → {:+.0f} dB @ {:.0f} Hz", gain, hz), EqCurve{}, bump});
            cases.push_back(
                {std::format("{:+.0f} dB @ {:.0f} Hz → Off", gain, hz), bump, EqCurve{}});
        }
    }
    std::string report =
        std::format("[info] {}: TD overshoot local / peak (dB), τ by the rule\n", kName);
    std::string failures;
    for (const Case& c : cases)
    {
        const std::vector<TdEvent> events = tdPairEvents(c.from, c.to, kFs, switchFrame);
        const TdOvershoot result = tdOvershoot(events, probes, kFs, switchFrame, totalFrames);
        report += std::format(
            "[info]   {:24s} τ ≤ {:3.0f} ms: local {:+5.2f} @ {:4.0f} Hz / peak {:+5.2f}\n",
            c.name,
            tdTauRangeMs(events.back().params).second,
            result.localDb,
            result.localProbeHz,
            result.peakDb);
        if (!(result.localDb <= kLocalBoundDb) || !(result.peakDb <= kPeakBoundDb))
        {
            failures +=
                std::format("{}: local {:+.2f} dB @ {:.0f} Hz (≤ {}), peak {:+.2f} (≤ {}); ",
                            c.name,
                            result.localDb,
                            result.localProbeHz,
                            kLocalBoundDb,
                            result.peakDb,
                            kPeakBoundDb);
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

// ---------------------------------------------------------------------------
// BreakIt_TauRule_SinglePointIsNotJagged — amendment 1 sends a transition to the 160 ms class
// when either endpoint's max |solved gain| exceeds 15 dB, meaning "a jagged curve" (adjacent bells
// fighting at ±30 dB). But ONE point at ±10.5 dB or more already solves past 15 dB (a single ±12
// point solves to ±17.8 dB), so the simplest gesture on the graph — pulling one point to the top
// or the bottom, by drag or by arrow key — is classed jagged and reaches the ear 15× slower: a
// +11 → +12 key step takes 371 ms to reach 90 % (vs 25 ms for +9 → +10). Measured at 10 ms, those
// single-point transitions are clean (≤ +0.53 dB local at 1 kHz and above; M13), so the slow
// class buys nothing there. Pins: a single point at ±12 dB, at 1 kHz and above, is not jagged.
// (Fix round, amendment 15: the τ rule is per band now, so this reads the dragged band's own τ, and
// "not jagged" is the amendment's own bound — the band reaches 90 % within ~30 ms: τ·ln 10 ≤ 30 ms.)
// ---------------------------------------------------------------------------
static auto testBreakItTauRuleSinglePointIsNotJagged() -> void
{
    static const char* const kName = "BreakIt_TauRule_SinglePointIsNotJagged";
    constexpr double kFs = 48000.0;
    constexpr double kNinetyPercentBoundSeconds = 0.030; // amendment 15: "settle in ≤ ~30 ms"
    std::string report = std::format("[info] {}: Off → one point, the rule's τ\n", kName);
    std::string failures;
    const GraphicEQDesign off = tdDesign(EqCurve{}, kFs);
    for (const size_t band : {17U, 20U, 24U, 27U})
    {
        for (const float gain : {12.0F, -12.0F})
        {
            const GraphicEQDesign point = tdDesign(eqFlatCurveWith(band, gain), kFs);
            const float ramp = EQTargets::rampsFor(off, point).band[band];
            const double hz = GraphicEQ::centreHz(static_cast<int>(band));
            report += std::format(
                "[info]   {:+.0f} dB @ {:5.0f} Hz: max |solved| {:.2f} dB → τ {:.0f} ms\n",
                gain,
                hz,
                breakItMaxSolvedGainDb(eqFlatCurveWith(band, gain), kFs),
                ramp * 1000.0F);
            if (!(static_cast<double>(ramp) * std::numbers::ln10 <= kNinetyPercentBoundSeconds))
            {
                failures += std::format(
                    "{:+.0f} dB @ {:.0f} Hz glides like a jagged curve "
                    "(τ {:.0f} ms); ",
                    gain,
                    hz,
                    ramp * 1000.0F);
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
