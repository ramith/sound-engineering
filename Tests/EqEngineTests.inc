// EqEngineTests.inc
//
// Sprint EQ, EQ1b — the real-time graphic EQ inside the engine: the EQModule, the kernel's four
// paths (decision 25), the Realizer's design + re-allocation, and the RT guards (engine-plan §5–§7,
// §9; amendment 2). #included into Tests/DSPKernelNullTest.cpp after EqDesignerTests.inc (it reuses
// that file's curves) and SoakRtAllocTests.inc (its allocation guard). Parallel-safe except the
// soak, the FZ/denormal tests (they own their thread's FPCR) and the paced normaliser test.
//
// Tests:
//   EQ_ReadbackEqualsEngine        — the settled RT (k, m1) == the Realizer's design, bit-exact; the
//                                    kernel's measured tones == the designer's read-back (≤ 0.05 dB)
//   EQ_ResponseIndependentOfIntensity — EQ on / EQ off at r ∈ {0, 0.2, 0.5, 1} == the read-back
//                                    (≤ 0.05 dB): the graph is honest at every Intensity
//   EQ_Off_BitExact                — an EQ turned Off (or flat) settles into a bit-exact pass-through
//   EQ_BitPerfect_P0               — Intensity 0 + EQ off is bit-perfect even with the limiter and
//                                    the normaliser active; leaving it is immediate, re-entering
//                                    waits the 2 s hysteresis
//   Kernel_PathSwitch_NoGlitch     — P0 ↔ P1 (EQ toggles at Intensity 0) and P0/P1 ↔ P3 (Intensity
//                                    0 ↔ 0.2): no sample step > 1.2× the endpoints' own max step
//   Path_Switch_AfterNormaliserAdapted — 12 s of a loud tone at r = 0.3 (the normaliser adapts to
//                                    ~−11 dB), then r → 0 and back: no level step > 0.5 dB
//                                    (amendment 2; 13–15 dB before the fade)
//   EQ_PublishRejectsNonFinite     — the Realizer's trust boundary
//   EQ_RT_IgnoresBadSnapshot       — non-finite / non-positive coefficients and a design for
//                                    another rate are ignored; the last good target keeps playing
//   EQ_NaNInput_Recovers           — a NaN input recovers in one block (module) / two (kernel)
//   EQ_FZ_Set_OnRenderThread       — the kernel sets FPCR.FZ on whatever thread renders
//   EQ_NoSubnormalStates           — seeded states decaying in silence: subnormal without FZ (the
//                                    test CAN fail), none with it
//   RtSwappableResource_Lifecycle  — the swap template's publish/adopt/reclaim contract (F17)
//   Soak_DSPKernel_ZeroRtAlloc_EqPaths — 8 ch, a new EQ target every ~10 ms across all 4 paths:
//                                    zero RT allocations
//   EQ_Reallocate_KeepsCurve / EQ_Reallocate_NewRate / Crossfeed_RederivedOnRateChange /
//   Realizer_ReinitDuringDrain     — re-allocation (engine-plan §6)

#include <thread> // std::thread (FZ/denormal tests, the reinit race)

namespace
{
    constexpr double kEngineFs = 48000.0;
    constexpr uint32_t kEngineBlock = TestConstants::kFrames512;

    // The Vocal preset (a busy, mid-heavy curve).
    constexpr size_t kEqPresetVocal = 4U;

    // Feed equal-amplitude integer-Hz tones (identical L/R) through `kernel` for `settleSeconds`
    // + one second, and return each tone's gain (dB) over that last second, by quadrature
    // correlation (an integer number of cycles of every tone, so the tones are orthogonal).
    auto engineToneGainsDb(DSPKernel& kernel,
                           const std::vector<double>& tonesHz,
                           double amplitude,
                           double settleSeconds) -> std::vector<double>
    {
        const auto settle = static_cast<uint32_t>(settleSeconds * kEngineFs);
        const auto window = static_cast<uint32_t>(kEngineFs);
        std::vector<double> inPhase(tonesHz.size(), 0.0);
        std::vector<double> quadrature(tonesHz.size(), 0.0);
        TestABL abl(kEngineBlock);
        for (uint32_t start = 0U; start < settle + window; start += kEngineBlock)
        {
            const uint32_t frames = std::min(kEngineBlock, settle + window - start);
            for (uint32_t i = 0U; i < frames; ++i)
            {
                const double time = static_cast<double>(start + i) / kEngineFs;
                double sample = 0.0;
                for (const double tone : tonesHz)
                {
                    sample += amplitude * std::sin(2.0 * std::numbers::pi * tone * time);
                }
                abl.left[i] = static_cast<float>(sample);
                abl.right[i] = static_cast<float>(sample);
            }
            abl.setFrameCount(frames);
            kernel.process(abl.abl(), frames);
            const uint32_t first = (start >= settle) ? 0U : std::min(frames, settle - start);
            for (uint32_t i = first; i < frames; ++i)
            {
                const double time = static_cast<double>(start + i) / kEngineFs;
                for (size_t t = 0; t < tonesHz.size(); ++t)
                {
                    const double phase = 2.0 * std::numbers::pi * tonesHz[t] * time;
                    inPhase[t] += abl.left[i] * std::sin(phase);
                    quadrature[t] += abl.left[i] * std::cos(phase);
                }
            }
        }
        std::vector<double> gains(tonesHz.size());
        for (size_t t = 0; t < tonesHz.size(); ++t)
        {
            const double measured = 2.0 * std::hypot(inPhase[t], quadrature[t]) / window;
            gains[t] = 20.0 * std::log10(measured / amplitude);
        }
        return gains;
    }

    auto engineDesign(const EqCurve& curve, double fs) -> GraphicEQDesign
    {
        auto designer = eqMakeDesigner();
        GraphicEQDesign design{};
        (void)designer->design(curve, fs, design);
        return design;
    }

    // An EQ intent for the Realizer.
    auto engineEqIntent(const EqCurve& points, bool isOn) -> AdaptiveSound::Realizer::EqIntent
    {
        AdaptiveSound::Realizer::EqIntent intent{};
        intent.points = points;
        intent.isOn = isOn;
        return intent;
    }

    // Run `blocks` blocks of a continuous sine through `kernel`, appending the left output.
    struct EngineSine
    {
        double hz = 1000.0;
        double amplitude = 0.5;
        uint64_t sample = 0U;
    };

    auto engineRunSine(DSPKernel& kernel,
                       EngineSine& sine,
                       uint32_t blocks,
                       std::vector<float>& outLeft,
                       std::vector<float>* inLeft = nullptr) -> void
    {
        TestABL abl(kEngineBlock);
        for (uint32_t b = 0U; b < blocks; ++b)
        {
            for (uint32_t i = 0U; i < kEngineBlock; ++i)
            {
                const double time = static_cast<double>(sine.sample + i) / kEngineFs;
                const auto value = static_cast<float>(
                    sine.amplitude * std::sin(2.0 * std::numbers::pi * sine.hz * time));
                abl.left[i] = value;
                abl.right[i] = value;
                if (inLeft != nullptr)
                {
                    inLeft->push_back(value);
                }
            }
            sine.sample += kEngineBlock;
            kernel.process(abl.abl(), kEngineBlock);
            outLeft.insert(outLeft.end(), abl.left.begin(), abl.left.end());
        }
    }

    auto engineBlocksFor(double seconds) -> uint32_t
    {
        return static_cast<uint32_t>(std::ceil(seconds * kEngineFs / kEngineBlock));
    }

    // The largest |y[n] − y[n−1]| over [begin, end).
    auto engineMaxStep(const std::vector<float>& y, size_t begin, size_t end) -> double
    {
        double step = 0.0;
        for (size_t n = std::max<size_t>(begin, 1U); n < end && n < y.size(); ++n)
        {
            step = std::max(step, static_cast<double>(std::abs(y[n] - y[n - 1U])));
        }
        return step;
    }
} // namespace

// ---------------------------------------------------------------------------
// EQ_ReadbackEqualsEngine — what the UI reads back is what the engine plays (engine-plan §9).
// ---------------------------------------------------------------------------
static auto testEqReadbackEqualsEngine() -> void
{
    static const char* const kName = "EQ_ReadbackEqualsEngine";
    constexpr double kToleranceDb = 0.05;
    const EqCurve warm = kEqPresetCurves[kEqPresetWarm];
    auto kernel = std::make_shared<DSPKernel>();
    kernel->initialize(static_cast<uint32_t>(kEngineFs), kEngineBlock);
    auto realizer = std::make_shared<AdaptiveSound::Realizer>(kernel, kEngineFs);
    realizer->applyIntensity(0.0F); // P1: EQ → limiter (no normaliser, no coloration)
    realizer->applyEq(engineEqIntent(warm, true));

    const std::vector<double> tones = {50.0, 200.0, 1000.0, 4000.0, 12000.0};
    const std::vector<double> measured = engineToneGainsDb(*kernel, tones, 0.02, 1.5);
    const TargetState& canonical = realizer->canonicalState();
    const EQModule* module = kernel->eqModule();
    if (module == nullptr || module->currentK() != canonical.eq.k ||
        module->currentM1() != canonical.eq.m1)
    {
        logFail(kName, "the settled RT coefficients differ from the Realizer's design");
        return;
    }
    const GraphicEQDesign design = engineDesign(warm, kEngineFs);
    double worst = 0.0;
    std::string perTone;
    for (size_t t = 0; t < tones.size(); ++t)
    {
        const double readBack = GraphicEQDesigner::playedDb(design, tones[t]);
        worst = std::max(worst, std::abs(measured[t] - readBack));
        perTone += std::format(" {:.0f} Hz {:+.4f}/{:+.4f}", tones[t], measured[t], readBack);
    }
    realizer->shutdown();
    logInfo(
        std::format("[info] {}: RT (k, m1) == design bit-exact; kernel vs read-back {:.4f} dB "
                    "(measured/read-back:{})\n",
                    kName,
                    worst,
                    perTone));
    if (!(worst <= kToleranceDb))
    {
        logFail(kName,
                std::format(
                    "the kernel plays {:.4f} dB off the read-back (≤ {})", worst, kToleranceDb));
        return;
    }
    logPass(kName);
}

// ---------------------------------------------------------------------------
// EQ_ResponseIndependentOfIntensity — decision 25: the EQ is ahead of the blend, so its shape is
// the read-back at every Intensity (engine-plan §5.2).
// ---------------------------------------------------------------------------
static auto testEqResponseIndependentOfIntensity() -> void
{
    static const char* const kName = "EQ_ResponseIndependentOfIntensity";
    constexpr double kToleranceDb = 0.05;
    const EqCurve vocal = kEqPresetCurves[kEqPresetVocal];
    const GraphicEQDesign design = engineDesign(vocal, kEngineFs);
    const std::vector<double> tones = {100.0, 700.0, 2500.0, 6000.0};
    double worst = 0.0;
    for (const float intensity : {0.0F, 0.2F, 0.5F, 1.0F})
    {
        std::array<std::vector<double>, 2> gains{};
        for (size_t on = 0; on < 2U; ++on)
        {
            TargetState state = makeIdentityState();
            state.intensityLinear = intensity;
            state.eq =
                (on == 1U) ? makeEqParams(vocal, static_cast<uint32_t>(kEngineFs)) : EQParams{};
            DSPKernel kernel;
            kernel.publishTargetState(state); // before initialize: the ramp starts at `intensity`
            kernel.initialize(static_cast<uint32_t>(kEngineFs), kEngineBlock);
            gains[on] = engineToneGainsDb(kernel, tones, 0.05, 1.0);
        }
        for (size_t t = 0; t < tones.size(); ++t)
        {
            const double shape = gains[1][t] - gains[0][t];
            const double delta = std::abs(shape - GraphicEQDesigner::playedDb(design, tones[t]));
            worst = std::max(worst, delta);
            if (!(delta <= kToleranceDb))
            {
                logFail(
                    kName,
                    std::format("r = {}: {:.0f} Hz plays {:+.4f} dB, the read-back says {:+.4f}",
                                intensity,
                                tones[t],
                                shape,
                                GraphicEQDesigner::playedDb(design, tones[t])));
                return;
            }
        }
    }
    logInfo(
        std::format("[info] {}: EQ shape vs read-back at r = 0 / 0.2 / 0.5 / 1: worst {:.4f} dB\n",
                    kName,
                    worst));
    logPass(kName);
}

// ---------------------------------------------------------------------------
// EQ_Off_BitExact — Off (and a flat curve) settle into a bit-exact pass-through.
// ---------------------------------------------------------------------------
static auto testEqOffBitExact() -> void
{
    static const char* const kName = "EQ_Off_BitExact";
    for (const bool flatDesign : {true, false})
    {
        DSPKernel kernel;
        kernel.initialize(static_cast<uint32_t>(kEngineFs), kEngineBlock);
        TargetState state = makeIdentityState(); // normaliser off, limiter bypassed
        state.eq =
            makeEqParams(eqFlatCurveWith(kBand1kHzIndex, 6.0F), static_cast<uint32_t>(kEngineFs));
        kernel.publishTargetState(state);
        EngineSine sine;
        std::vector<float> out;
        engineRunSine(kernel, sine, 10U, out);
        // Off: the Realizer publishes the flat design; a default EQParams is the same identity.
        state.eq =
            flatDesign ? makeEqParams(EqCurve{}, static_cast<uint32_t>(kEngineFs)) : EQParams{};
        kernel.publishTargetState(state);
        engineRunSine(kernel, sine, engineBlocksFor(0.4), out); // 10 ms τ: settled long before
        std::vector<float> in;
        out.clear();
        engineRunSine(kernel, sine, 4U, out, &in);
        if (out != in || kernel.eqModule() == nullptr || !kernel.eqModule()->isIdentity())
        {
            logFail(kName,
                    std::format("{} did not settle into a bit-exact pass-through",
                                flatDesign ? "the flat design" : "EQParams{}"));
            return;
        }
    }
    logPass(kName);
}

// ---------------------------------------------------------------------------
// EQ_BitPerfect_P0 — engine-plan §5.1: P0 only with Intensity 0 AND the EQ identity-settled for
// 2 s; bit-perfect even though the limiter and the normaliser are active.
// ---------------------------------------------------------------------------
static auto testEqBitPerfectP0() -> void
{
    static const char* const kName = "EQ_BitPerfect_P0";
    TargetState state{}; // normaliser ON, limiter ON at −1 dBTP
    state.intensityLinear = 0.0F;
    DSPKernel kernel;
    kernel.publishTargetState(state);
    kernel.initialize(static_cast<uint32_t>(kEngineFs), kEngineBlock);
    EngineSine sine;
    sine.amplitude = 0.99; // above the −1 dBTP ceiling: anything but P0 would limit it
    std::vector<float> in;
    std::vector<float> out;
    engineRunSine(kernel, sine, engineBlocksFor(1.0), out, &in);
    if (out != in)
    {
        logFail(kName, "Intensity 0 + EQ off is not bit-perfect from the first block");
        return;
    }
    // EQ on: leave P0 at once.
    state.eq =
        makeEqParams(eqFlatCurveWith(kBand1kHzIndex, -6.0F), static_cast<uint32_t>(kEngineFs));
    kernel.publishTargetState(state);
    in.clear();
    out.clear();
    engineRunSine(kernel, sine, 2U, out, &in);
    if (out == in)
    {
        logFail(kName, "turning the EQ on did not leave the bit-perfect path");
        return;
    }
    engineRunSine(kernel, sine, engineBlocksFor(0.5), out, &in);
    // EQ off: the EQ settles to its identity in ~0.2 s, then P0 waits 2 s, then a 5 ms fade.
    state.eq = makeEqParams(EqCurve{}, static_cast<uint32_t>(kEngineFs));
    kernel.publishTargetState(state);
    in.clear();
    out.clear();
    engineRunSine(kernel, sine, engineBlocksFor(3.0), out, &in);
    size_t firstExact = out.size();
    for (size_t start = 0; start + kEngineBlock <= out.size(); start += kEngineBlock)
    {
        if (std::equal(out.begin() + static_cast<std::ptrdiff_t>(start),
                       out.begin() + static_cast<std::ptrdiff_t>(start + kEngineBlock),
                       in.begin() + static_cast<std::ptrdiff_t>(start)))
        {
            firstExact = start;
            break;
        }
    }
    const double firstExactSeconds = static_cast<double>(firstExact) / kEngineFs;
    const auto tailFrames = static_cast<std::ptrdiff_t>(kEngineBlock) * 20;
    const bool tailExact = std::equal(out.end() - tailFrames, out.end(), in.end() - tailFrames);
    logInfo(std::format("[info] {}: bit-perfect again {:.3f} s after the EQ was turned off\n",
                        kName,
                        firstExactSeconds));
    if (firstExactSeconds < 2.0 || firstExactSeconds > 2.6 || !tailExact)
    {
        logFail(
            kName,
            std::format("P0 resumed at {:.3f} s (want the 2 s hysteresis + the identity settle)",
                        firstExactSeconds));
        return;
    }
    logPass(kName);
}

// ---------------------------------------------------------------------------
// Kernel_PathSwitch_NoGlitch — engine-plan §5.1: path switches neither skip nor repeat audio.
// Each switch's largest sample step must stay within 1.2× the larger of its two endpoints' own
// steady maximum step (a 3 ms skip of a 1 kHz sine would be ~15×).
// ---------------------------------------------------------------------------
static auto testKernelPathSwitchNoGlitch() -> void
{
    static const char* const kName = "Kernel_PathSwitch_NoGlitch";
    constexpr double kBound = 1.2;
    TargetState state = makeIdentityState();
    state.limiter = LimiterParams{}; // the limiter ON: its 3 ms look-ahead is what P0 skips
    state.intensityLinear = 0.0F;
    DSPKernel kernel;
    kernel.publishTargetState(state);
    kernel.initialize(static_cast<uint32_t>(kEngineFs), kEngineBlock);
    EngineSine sine;
    std::vector<float> out;
    struct Switch
    {
        const char* name;
        size_t at;
        size_t end;
    };
    std::vector<Switch> switches;
    const auto segment = [&](const char* name, double seconds)
    {
        kernel.publishTargetState(state);
        const size_t at = out.size();
        engineRunSine(kernel, sine, engineBlocksFor(seconds), out);
        switches.push_back({name, at, out.size()});
    };
    engineRunSine(kernel, sine, engineBlocksFor(0.5), out); // P0
    state.eq =
        makeEqParams(eqFlatCurveWith(kBand1kHzIndex, -6.0F), static_cast<uint32_t>(kEngineFs));
    segment("P0 → P1 (EQ on)", 0.5);
    state.eq = makeEqParams(EqCurve{}, static_cast<uint32_t>(kEngineFs));
    segment("P1 → P0 (EQ off)", 2.8);
    state.intensityLinear = 0.2F;
    segment("P0 → P3 (Intensity 0 → 0.2)", 0.5);
    state.intensityLinear = 0.0F;
    segment("P3 → P1 → P0 (Intensity 0.2 → 0)", 2.8);

    const auto window = static_cast<size_t>(0.02 * kEngineFs);
    std::string report = std::format("[info] {}: max step / bound per switch\n", kName);
    for (const Switch& s : switches)
    {
        const double before = engineMaxStep(out, s.at - window, s.at);
        const double after = engineMaxStep(out, s.end - window, s.end);
        const double during = engineMaxStep(out, s.at, s.end);
        const double bound = kBound * std::max(before, after);
        report += std::format("[info]   {:34s} {:.5f} / {:.5f}\n", s.name, during, bound);
        if (!(during <= bound))
        {
            logInfo(report);
            logFail(kName,
                    std::format("{}: a sample step of {:.5f} > {:.5f}", s.name, during, bound));
            return;
        }
    }
    logInfo(report);
    logPass(kName);
}

// ---------------------------------------------------------------------------
// Path_Switch_AfterNormaliserAdapted — amendment 2. After ≥ 10 s of a loud programme the
// normaliser holds a large cut; leaving the blend for the normaliser-free EQ-only path (and coming
// back) must glide, not step. The breaker measured +13.4 / −15.5 dB in one block before the fade.
// Level steps are read per sample from the tone's exact amplitude (y[n], y[n−1] of a known ω).
// Serial-only: paced so the measurement worker keeps up.
// ---------------------------------------------------------------------------
static auto testPathSwitchAfterNormaliserAdapted() -> void
{
    static const char* const kName = "Path_Switch_AfterNormaliserAdapted";
    constexpr double kStepBoundDb = 0.5;
    constexpr double kMinAdaptedCutDb = 6.0;
    TargetState state{}; // normaliser ON (−16 LUFS), limiter ON
    state.clarity.enabled = 0U;
    state.intensityLinear = 0.3F;
    DSPKernel kernel;
    kernel.publishTargetState(state);
    kernel.initialize(static_cast<uint32_t>(kEngineFs), kEngineBlock);
    EngineSine sine; // 1 kHz at −6 dBFS: ≈ −4 LUFS through the r = 0.3 blend
    std::vector<float> out;
    // ≥ 10 s of programme, paced (the worker drains its ring between blocks).
    for (uint32_t b = 0U; b < engineBlocksFor(12.0); ++b)
    {
        engineRunSine(kernel, sine, 1U, out);
        std::this_thread::sleep_for(std::chrono::milliseconds(1));
    }
    const auto amplitudeAt = [&](size_t n)
    {
        const double omega = 2.0 * std::numbers::pi * sine.hz / kEngineFs;
        const double cosPart = ((out[n] * std::cos(omega)) - out[n - 1U]) / std::sin(omega);
        return std::hypot(static_cast<double>(out[n]), cosPart);
    };
    const double adaptedDb = 20.0 * std::log10(amplitudeAt(out.size() - 1U) / sine.amplitude);
    const double blendDb =
        20.0 * std::log10(std::cos(0.15 * std::numbers::pi) + std::sin(0.15 * std::numbers::pi));
    const double cutDb = blendDb - adaptedDb;
    if (!(cutDb >= kMinAdaptedCutDb))
    {
        logFail(kName,
                std::format(
                    "the normaliser did not adapt (cut {:.2f} dB < {})", cutDb, kMinAdaptedCutDb));
        return;
    }
    const size_t switchAt = out.size();
    state.intensityLinear = 0.0F;
    kernel.publishTargetState(state);
    engineRunSine(kernel, sine, engineBlocksFor(3.0), out); // P3 → P1 → (2 s) → P0
    state.intensityLinear = 0.3F;
    kernel.publishTargetState(state);
    engineRunSine(kernel, sine, engineBlocksFor(1.0), out); // P0 → P3
    double worstStep = 0.0;
    for (size_t n = switchAt; n < out.size(); ++n)
    {
        worstStep =
            std::max(worstStep, std::abs(20.0 * std::log10(amplitudeAt(n) / amplitudeAt(n - 1U))));
    }
    logInfo(
        std::format("[info] {}: normaliser cut {:.2f} dB; worst per-sample level step across "
                    "r 0.3 → 0 → 0.3 {:.4f} dB (≤ {})\n",
                    kName,
                    cutDb,
                    worstStep,
                    kStepBoundDb));
    if (!(worstStep <= kStepBoundDb))
    {
        logFail(kName, std::format("a {:.3f} dB level step at a path switch", worstStep));
        return;
    }
    logPass(kName);
}

// ---------------------------------------------------------------------------
// EQ_PublishRejectsNonFinite — the Realizer's trust boundary (engine-plan §7, guard layer 1).
// ---------------------------------------------------------------------------
static auto testEqPublishRejectsNonFinite() -> void
{
    static const char* const kName = "EQ_PublishRejectsNonFinite";
    auto kernel = std::make_shared<DSPKernel>();
    kernel->initialize(static_cast<uint32_t>(kEngineFs), kEngineBlock);
    auto realizer = std::make_shared<AdaptiveSound::Realizer>(kernel, kEngineFs);
    const EqCurve warm = kEqPresetCurves[kEqPresetWarm];
    realizer->applyEq(engineEqIntent(warm, true));
    const EQParams good = realizer->canonicalState().eq;

    std::string failure;
    for (const float bad : {
             std::numeric_limits<float>::quiet_NaN(),
             std::numeric_limits<float>::infinity(),
             -std::numeric_limits<float>::infinity(),
         })
    {
        EqCurve curve = warm;
        curve[12] = bad;
        if (realizer->setPendingEq(curve.data(), 31U, true))
        {
            failure = std::format("a point of {} was accepted", bad);
        }
    }
    if (realizer->setPendingEq(nullptr, 31U, true) ||
        realizer->setPendingEq(warm.data(), 30U, true) ||
        realizer->setPendingEq(warm.data(), 32U, true))
    {
        failure = "a NULL pointer or a wrong count was accepted";
    }
    realizer->shutdown(); // flush: nothing may have been published
    if (failure.empty() &&
        std::memcmp(&realizer->canonicalState().eq, &good, sizeof(EQParams)) != 0)
    {
        failure = "a rejected publish changed the published EQ";
    }
    // Finite points beyond ±12 dB are clamped, not rejected.
    auto clampKernel = std::make_shared<DSPKernel>();
    clampKernel->initialize(static_cast<uint32_t>(kEngineFs), kEngineBlock);
    auto clamping = std::make_shared<AdaptiveSound::Realizer>(clampKernel, kEngineFs);
    EqCurve beyond = warm;
    beyond[3] = 40.0F;
    beyond[20] = -40.0F;
    EqCurve clamped = warm;
    clamped[3] = 12.0F;
    clamped[20] = -12.0F;
    if (failure.empty() && !clamping->setPendingEq(beyond.data(), 31U, true))
    {
        failure = "finite points beyond ±12 dB were rejected instead of clamped";
    }
    clamping->shutdown();
    const EQParams expected = makeEqParams(clamped, static_cast<uint32_t>(kEngineFs));
    if (failure.empty() && (clamping->canonicalState().eq.k != expected.k ||
                            clamping->canonicalState().eq.m1 != expected.m1))
    {
        failure = "points beyond ±12 dB did not design as ±12 dB";
    }
    if (!failure.empty())
    {
        logFail(kName, failure);
        return;
    }
    logPass(kName);
}

// ---------------------------------------------------------------------------
// EQ_RT_IgnoresBadSnapshot — engine-plan §7, guard layer 4; §6 (the fs guard).
// ---------------------------------------------------------------------------
static auto testEqRtIgnoresBadSnapshot() -> void
{
    static const char* const kName = "EQ_RT_IgnoresBadSnapshot";
    const EQParams good =
        makeEqParams(kEqPresetCurves[kEqPresetWarm], static_cast<uint32_t>(kEngineFs));
    struct Bad
    {
        const char* what;
        EQParams params;
    };
    std::vector<Bad> bads;
    bads.push_back({"a NaN k", good});
    bads.back().params.k[3] = std::numeric_limits<double>::quiet_NaN();
    bads.push_back({"a negative k", good});
    bads.back().params.k[7] = -0.5;
    bads.push_back({"an infinite m1", good});
    bads.back().params.m1[2] = std::numeric_limits<double>::infinity();
    bads.push_back({"a NaN output gain", good});
    bads.back().params.outputGainDb = std::numeric_limits<double>::quiet_NaN();
    bads.push_back(
        {"a design for 44.1 kHz", makeEqParams(kEqPresetCurves[0], TestConstants::kSampleRate44k)});
    for (const Bad& bad : bads)
    {
        EQModule module;
        module.initialize(static_cast<uint32_t>(kEngineFs), kEngineBlock);
        TestABL abl(kEngineBlock);
        abl.left.assign(kEngineBlock, 0.1F);
        abl.right.assign(kEngineBlock, 0.1F);
        module.update(good);
        module.process(MultichannelView::fromABL(abl.abl(), kEngineBlock));
        const auto k = module.currentK();
        const auto m1 = module.currentM1();
        module.update(bad.params);
        module.process(MultichannelView::fromABL(abl.abl(), kEngineBlock));
        const bool finite = std::ranges::all_of(abl.left, [](float v) { return std::isfinite(v); });
        if (module.currentK() != k || module.currentM1() != m1 || !finite)
        {
            logFail(kName, std::format("{} was adopted (or broke the output)", bad.what));
            return;
        }
    }
    logPass(kName);
}

// ---------------------------------------------------------------------------
// EQ_NaNInput_Recovers — engine-plan §7: a NaN in the input poisons one block, not the stream.
// ---------------------------------------------------------------------------
static auto testEqNaNInputRecovers() -> void
{
    static const char* const kName = "EQ_NaNInput_Recovers";
    const EQParams warm =
        makeEqParams(kEqPresetCurves[kEqPresetWarm], static_cast<uint32_t>(kEngineFs));
    const auto blockWithNaN = [](TestABL& abl, bool poison)
    {
        for (uint32_t i = 0U; i < kEngineBlock; ++i)
        {
            abl.left[i] = 0.1F * std::sin(0.05F * static_cast<float>(i));
            abl.right[i] = abl.left[i];
        }
        if (poison)
        {
            abl.left[100] = std::numeric_limits<float>::quiet_NaN();
        }
    };
    // The module alone: the very next block is clean.
    EQModule module;
    module.initialize(static_cast<uint32_t>(kEngineFs), kEngineBlock);
    TestABL abl(kEngineBlock);
    module.update(warm);
    blockWithNaN(abl, true);
    module.process(MultichannelView::fromABL(abl.abl(), kEngineBlock));
    blockWithNaN(abl, false);
    module.process(MultichannelView::fromABL(abl.abl(), kEngineBlock));
    if (!std::ranges::all_of(abl.left, [](float v) { return std::isfinite(v); }))
    {
        logFail(kName, "the EQ module did not recover in the next block");
        return;
    }
    // The kernel: the limiter's 3 ms look-ahead still holds the NaN for one more block.
    TargetState state = makeIdentityState();
    state.limiter = LimiterParams{};
    state.eq = warm;
    DSPKernel kernel;
    kernel.publishTargetState(state);
    kernel.initialize(static_cast<uint32_t>(kEngineFs), kEngineBlock);
    blockWithNaN(abl, true);
    kernel.process(abl.abl(), kEngineBlock);
    for (int b = 0; b < 2; ++b)
    {
        blockWithNaN(abl, false);
        kernel.process(abl.abl(), kEngineBlock);
    }
    if (!std::ranges::all_of(abl.left, [](float v) { return std::isfinite(v); }))
    {
        logFail(kName, "the kernel did not recover within two blocks");
        return;
    }
    logPass(kName);
}

// ---------------------------------------------------------------------------
// EQ_FZ_Set_OnRenderThread — engine-plan §7: FPCR.FZ is on wherever the kernel renders.
// ---------------------------------------------------------------------------
static auto testEqFzSetOnRenderThread() -> void
{
    static const char* const kName = "EQ_FZ_Set_OnRenderThread";
#ifdef __aarch64__
    constexpr uint64_t kFz = 1ULL << 24U;
    DSPKernel kernel;
    kernel.initialize(static_cast<uint32_t>(kEngineFs), kEngineBlock);
    uint64_t before = 0U;
    uint64_t after = 0U;
    std::thread render(
        [&]
        {
            // A fresh thread: FZ off until something on it turns it on.
            before = __builtin_arm_rsr64("fpcr") & kFz;
            TestABL abl(kEngineBlock);
            kernel.process(abl.abl(), kEngineBlock);
            after = __builtin_arm_rsr64("fpcr") & kFz;
        });
    render.join();
    if (before != 0U || after == 0U)
    {
        logFail(kName, std::format("FPCR.FZ before {} after {} (want 0 then set)", before, after));
        return;
    }
    logPass(kName);
#else
    logPending(kName, "AArch64 only (FPCR.FZ)");
#endif
}

// ---------------------------------------------------------------------------
// EQ_NoSubnormalStates — engine-plan §7 (the breaker's m7): a denormal test that CAN fail.
// States seeded at 1e-300 decay in silence through the subnormal range; without FZ some state is
// subnormal at some block (proving the probe works), with FZ none ever is.
// ---------------------------------------------------------------------------
static auto testEqNoSubnormalStates() -> void
{
    static const char* const kName = "EQ_NoSubnormalStates";
#ifdef __aarch64__
    constexpr uint32_t kFs = 192000U;
    constexpr uint32_t kFrames = 64U;
    constexpr uint32_t kBlocks = 4000U;
    const EQParams params =
        makeEqParams(eqFlatCurveWith(0U, 12.0F), kFs); // the slowest band, 20 Hz
    const auto countSubnormalBlocks = [&](bool flushToZero)
    {
        uint32_t count = 0U;
        std::thread worker(
            [&]
            {
                if (flushToZero)
                {
                    enableFlushToZero();
                }
                EQModule module;
                module.initialize(kFs, kFrames);
                module.update(params);
                module.seedStatesForTesting(1e-300);
                TestABL abl(kFrames);
                for (uint32_t b = 0U; b < kBlocks; ++b)
                {
                    abl.left.assign(kFrames, 0.0F);
                    abl.right.assign(kFrames, 0.0F);
                    module.process(MultichannelView::fromABL(abl.abl(), kFrames));
                    count += module.hasSubnormalState() ? 1U : 0U;
                }
            });
        worker.join();
        return count;
    };
    const uint32_t withoutFz = countSubnormalBlocks(false);
    const uint32_t withFz = countSubnormalBlocks(true);
    logInfo(std::format("[info] {}: blocks with a subnormal state — without FZ {}, with FZ {}\n",
                        kName,
                        withoutFz,
                        withFz));
    if (withoutFz == 0U)
    {
        logFail(kName, "the probe never saw a subnormal without FZ: the test cannot fail");
        return;
    }
    if (withFz != 0U)
    {
        logFail(kName, std::format("{} block(s) held a subnormal state with FZ on", withFz));
        return;
    }
    logPass(kName);
#else
    logPending(kName, "AArch64 only (FPCR.FZ)");
#endif
}

// ---------------------------------------------------------------------------
// RtSwappableResource_Lifecycle — F17: the swap template (kept for BRIR's IR swaps) keeps its
// contract: adopt sees the newest publish, a never-adopted publish is freed by the next, retired
// resources are freed by reclaim, and the destructor frees the rest — every construction balanced.
// ---------------------------------------------------------------------------
namespace
{
    std::atomic<int> gSwapLive{0};

    struct SwapProbe
    {
        explicit SwapProbe(int tag) noexcept : value(tag)
        {
            gSwapLive.fetch_add(1);
        }
        ~SwapProbe()
        {
            gSwapLive.fetch_sub(1);
        }
        SwapProbe(const SwapProbe&) = delete;
        SwapProbe& operator=(const SwapProbe&) = delete;
        SwapProbe(SwapProbe&&) = delete;
        SwapProbe& operator=(SwapProbe&&) = delete;
        int value;
    };
} // namespace

static auto testRtSwappableResourceLifecycle() -> void
{
    static const char* const kName = "RtSwappableResource_Lifecycle";
    std::string failure;
    {
        RtSwappableResource<SwapProbe> resource;
        if (resource.adopt() != nullptr)
        {
            failure = "an empty swap adopted something";
        }
        resource.publish(std::make_unique<SwapProbe>(1));
        const SwapProbe* first = resource.adopt();
        if (failure.empty() &&
            (first == nullptr || first->value != 1 || resource.active() != first))
        {
            failure = "adopt did not return the published resource";
        }
        resource.publish(std::make_unique<SwapProbe>(2)); // never adopted…
        resource.publish(std::make_unique<SwapProbe>(3)); // …so this frees it
        if (failure.empty() && gSwapLive.load() != 2)
        {
            failure = std::format("a displaced, never-adopted resource was not freed ({} live)",
                                  gSwapLive.load());
        }
        const SwapProbe* third = resource.adopt(); // retires 1 into toRelease
        if (failure.empty() && (third == nullptr || third->value != 3))
        {
            failure = "adopt did not return the newest publish";
        }
        resource.reclaim(); // frees 1
        if (failure.empty() && gSwapLive.load() != 1)
        {
            failure = std::format("reclaim did not free the retired resource ({} live)",
                                  gSwapLive.load());
        }
        // Two threads: the producer publishes only after the consumer adopted the last one (the
        // single-pending contract), so nothing is orphaned; the race checks run under tsan.
        std::atomic<int> adopted{3};
        std::thread consumer(
            [&]
            {
                while (adopted.load(std::memory_order_acquire) < 200)
                {
                    const SwapProbe* probe = resource.adopt();
                    if (probe != nullptr && probe->value > adopted.load(std::memory_order_relaxed))
                    {
                        adopted.store(probe->value, std::memory_order_release);
                    }
                }
            });
        for (int tag = 4; tag <= 200; ++tag)
        {
            resource.publish(std::make_unique<SwapProbe>(tag));
            while (adopted.load(std::memory_order_acquire) < tag)
            {
                std::this_thread::yield();
            }
        }
        consumer.join();
        resource.reclaim();
        if (failure.empty() && gSwapLive.load() != 1)
        {
            failure =
                std::format("{} resources live after the threaded run (want only the active one)",
                            gSwapLive.load());
        }
    } // the destructor frees the active one
    if (failure.empty() && gSwapLive.load() != 0)
    {
        failure = std::format("{} resource(s) leaked past the destructor", gSwapLive.load());
    }
    if (!failure.empty())
    {
        logFail(kName, failure);
        return;
    }
    logPass(kName);
}

// ---------------------------------------------------------------------------
// Soak_DSPKernel_ZeroRtAlloc_EqPaths — engine-plan §9: 8 channels, a new EQ target every ~10 ms,
// Intensity and the EQ cycled through all four paths (P0 bypass, P1, P2, P3), zero allocations.
// The targets are designed BEFORE the guard is armed (the Realizer designs off the render thread).
// ---------------------------------------------------------------------------
static auto testSoakDspKernelZeroRtAllocEqPaths() -> void
{
    static const char* const kName = "Soak_DSPKernel_ZeroRtAlloc_EqPaths";
    constexpr uint32_t kChannels = 8U;
    std::mt19937 rng(9U);
    std::uniform_real_distribution<float> point(-12.0F, 12.0F);
    // The schedule: per Intensity, 24 random EQ targets one block (~10.7 ms) each, every sixth the
    // identity; after each Intensity-0 group, 2.2 s of EQ off so the kernel enters P0.
    std::vector<std::pair<TargetState, uint32_t>> schedule;
    for (const float intensity : {1.0F, 0.0F, 0.3F, 0.0F})
    {
        for (int i = 0; i < 24; ++i)
        {
            TargetState state{};
            state.intensityLinear = intensity;
            EqCurve curve{};
            for (float& value : curve)
            {
                value = point(rng);
            }
            state.eq =
                (i % 6 == 5) ? EQParams{} : makeEqParams(curve, static_cast<uint32_t>(kEngineFs));
            schedule.emplace_back(state, 1U);
        }
        if (intensity == 0.0F)
        {
            TargetState idle{};
            idle.intensityLinear = 0.0F;
            schedule.emplace_back(idle, engineBlocksFor(2.2));
        }
    }
    DSPKernel kernel;
    kernel.initialize(static_cast<uint32_t>(kEngineFs), kEngineBlock);
    TestABLN abl(kChannels, kEngineBlock);
    std::vector<std::vector<float>> source(kChannels, std::vector<float>(kEngineBlock));
    for (auto& channel : source)
    {
        std::ranges::generate(channel, [&] { return 0.1F * point(rng) / 12.0F; });
    }
    const auto refill = [&]
    {
        for (uint32_t ch = 0U; ch < kChannels; ++ch)
        {
            std::ranges::copy(source[ch], abl.channels[ch].begin());
        }
    };
    for (int warm = 0; warm < 64; ++warm)
    {
        refill();
        kernel.publishTargetState(schedule.front().first);
        kernel.process(abl.abl(), kEngineBlock);
    }
    uint64_t blocks = 0U;
    {
        const RtGuardScope guard;
        for (const auto& [target, count] : schedule)
        {
            for (uint32_t b = 0U; b < count; ++b)
            {
                refill();
                kernel.publishTargetState(target);
                kernel.process(abl.abl(), kEngineBlock);
                ++blocks;
            }
        }
    }
    const uint64_t allocs = RtGuardScope::count();
    logInfo(std::format("[info] {}: {} targets / {} blocks across P0–P3, 8 ch, rtAllocs = {}\n",
                        kName,
                        schedule.size(),
                        blocks,
                        allocs));
    if (allocs != 0U)
    {
        logFail(kName, std::format("the RT path allocated {} time(s)", allocs));
        return;
    }
    logPass(kName);
}

// ---------------------------------------------------------------------------
// Re-allocation (engine-plan §6).
// ---------------------------------------------------------------------------
static auto testEqReallocateKeepsCurve() -> void
{
    static const char* const kName = "EQ_Reallocate_KeepsCurve";
    constexpr double kToleranceDb = 0.1;
    const EqCurve warm = kEqPresetCurves[kEqPresetWarm];
    auto kernel = std::make_shared<DSPKernel>();
    kernel->initialize(static_cast<uint32_t>(kEngineFs), kEngineBlock);
    auto realizer = std::make_shared<AdaptiveSound::Realizer>(kernel, kEngineFs);
    realizer->applyIntensity(0.0F);
    realizer->applyEq(engineEqIntent(warm, true));
    const std::vector<double> tones = {60.0, 400.0, 3000.0};
    const std::vector<double> before = engineToneGainsDb(*kernel, tones, 0.02, 1.0);
    // The host re-allocates (a channel-layout change at the same rate): the curve must survive,
    // from the very first block — the module snaps to the re-solved target (no fade from flat).
    realizer->reinitializeKernel(static_cast<uint32_t>(kEngineFs), 1024U);
    TestABL abl(kEngineBlock);
    kernel->process(abl.abl(), kEngineBlock);
    const EQModule* module = kernel->eqModule();
    const bool snapped = module != nullptr &&
                         module->currentK() == realizer->canonicalState().eq.k &&
                         module->currentM1() == realizer->canonicalState().eq.m1;
    const std::vector<double> after = engineToneGainsDb(*kernel, tones, 0.02, 1.0);
    realizer->shutdown();
    double worst = 0.0;
    for (size_t t = 0; t < tones.size(); ++t)
    {
        worst = std::max(worst, std::abs(after[t] - before[t]));
    }
    if (!snapped || !(worst <= kToleranceDb))
    {
        logFail(kName,
                std::format("after re-allocation: snapped {} , played change {:.4f} dB (≤ {})",
                            snapped,
                            worst,
                            kToleranceDb));
        return;
    }
    logPass(kName);
}

static auto testEqReallocateNewRate() -> void
{
    static const char* const kName = "EQ_Reallocate_NewRate";
    const EqCurve air = eqToneCurve({0.0, 0.0, 0.0, 0.0, 12.0});
    auto kernel = std::make_shared<DSPKernel>();
    kernel->initialize(static_cast<uint32_t>(kEngineFs), kEngineBlock);
    auto realizer = std::make_shared<AdaptiveSound::Realizer>(kernel, kEngineFs);
    realizer->applyEq(engineEqIntent(air, true));
    TestABL abl(kEngineBlock);
    kernel->process(abl.abl(), kEngineBlock);
    // The device moves to 44.1 kHz: the Realizer re-solves there; the module never runs the
    // 48 kHz coefficients at 44.1 kHz (they would be 1.4–2.9 dB off, the breaker's M3).
    realizer->reinitializeKernel(TestConstants::kSampleRate44k, kEngineBlock);
    kernel->process(abl.abl(), kEngineBlock);
    const EQParams expected = makeEqParams(air, TestConstants::kSampleRate44k);
    const EQModule* module = kernel->eqModule();
    const bool resolved = realizer->eqDesignSampleRate() == TestConstants::kRate44k &&
                          realizer->canonicalState().eq.designSampleRate == 44100.0F &&
                          module != nullptr && module->currentK() == expected.k &&
                          module->currentM1() == expected.m1;
    // A rate the EQ cannot host (32 kHz: the top bands are above Nyquist) plays the identity.
    realizer->reinitializeKernel(32000U, kEngineBlock);
    kernel->process(abl.abl(), kEngineBlock);
    const bool identityAt32k = kernel->eqModule() != nullptr && kernel->eqModule()->isIdentity();
    realizer->shutdown();
    if (!resolved || !identityAt32k)
    {
        logFail(kName,
                std::format(
                    "re-solved at 44.1 kHz: {}; identity at 32 kHz: {}", resolved, identityAt32k));
        return;
    }
    logPass(kName);
}

static auto testCrossfeedRederivedOnRateChange() -> void
{
    static const char* const kName = "Crossfeed_RederivedOnRateChange";
    auto kernel = std::make_shared<DSPKernel>();
    kernel->initialize(static_cast<uint32_t>(kEngineFs), kEngineBlock);
    auto realizer = std::make_shared<AdaptiveSound::Realizer>(kernel, kEngineFs);
    constexpr AdaptiveSound::Realizer::CrossfeedIntent kStrong{
        .enabled = 1U,
        .level = 1.0F,
        .preset = 2U,
    };
    realizer->applyCrossfeed(kStrong);
    const CrossfeedParams at48k = realizer->canonicalState().crossfeed;
    realizer->reinitializeKernel(96000U, kEngineBlock);
    const CrossfeedParams at96k = realizer->canonicalState().crossfeed;
    // The reference: a Realizer that was at 96 kHz from the start.
    auto reference = std::make_shared<AdaptiveSound::Realizer>(kernel, 96000.0);
    reference->applyCrossfeed(kStrong);
    const CrossfeedParams fresh96k = reference->canonicalState().crossfeed;
    realizer->shutdown();
    reference->shutdown();
    if (at96k.delayFrames == at48k.delayFrames || at96k.lpfPole != fresh96k.lpfPole ||
        at96k.delayFrames != fresh96k.delayFrames || at96k.enabled != 1U)
    {
        logFail(kName,
                std::format("crossfeed after 48 → 96 kHz: delay {} (fresh {}), pole {} (fresh {})",
                            at96k.delayFrames,
                            fresh96k.delayFrames,
                            at96k.lpfPole,
                            fresh96k.lpfPole));
        return;
    }
    logPass(kName);
}

// Realizer_ReinitDuringDrain — architect F3: re-allocation and a burst of intents race through the
// Realizer's queue without a data race (run under tsan), the last intent wins, and a
// re-allocation never waits behind a growing queue. The bound is relative to an idle
// re-allocation, so it holds at -O0, -O2 and under the sanitizers: with at most one untaken drain
// queued, a re-allocation waits for at most one drain (one design) plus its own work, about 2×
// idle. Per-slot drain posting let every real drain re-arm all three slots, so the queue grew for
// as long as the burst lasted — 2–9 s per re-allocation before the fix.
static auto testRealizerReinitDuringDrain() -> void
{
    static const char* const kName = "Realizer_ReinitDuringDrain";
    constexpr int kRounds = 40;
    constexpr int kIdleRounds = 4;
    constexpr double kBoundFactor = 4.0; // ~2× expected; headroom for scheduler noise
    constexpr double kBoundSlackMs = 10.0;
    auto kernel = std::make_shared<DSPKernel>();
    kernel->initialize(static_cast<uint32_t>(kEngineFs), kEngineBlock);
    auto realizer = std::make_shared<AdaptiveSound::Realizer>(kernel, kEngineFs);
    const auto timedReinit = [&](int round) -> double
    {
        const auto started = std::chrono::steady_clock::now();
        realizer->reinitializeKernel((round % 2 == 0) ? TestConstants::kSampleRate44k : 48000U,
                                     kEngineBlock);
        return std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - started)
            .count();
    };
    double idleWorstMs = 0.0;
    for (int round = 0; round < kIdleRounds; ++round)
    {
        idleWorstMs = std::max(idleWorstMs, timedReinit(round));
    }
    std::atomic<bool> stop{false};
    std::thread control(
        [&]
        {
            uint32_t i = 0U;
            while (!stop.load(std::memory_order_relaxed))
            {
                EqCurve curve{};
                curve[i % 31U] = static_cast<float>((i % 25U)) - 12.0F;
                (void)realizer->setPendingEq(curve.data(), 31U, true);
                realizer->setPendingIntensity(static_cast<float>(i % 10U) / 10.0F);
                realizer->setPendingCrossfeed(i % 2U, 0.5F, i % 3U);
                ++i;
                std::this_thread::sleep_for(std::chrono::microseconds(50)); // a fast UI, not a spin
            }
        });
    double burstWorstMs = 0.0;
    double burstTotalMs = 0.0;
    for (int round = 0; round < kRounds; ++round)
    {
        const double ms = timedReinit(round);
        burstWorstMs = std::max(burstWorstMs, ms);
        burstTotalMs += ms;
    }
    stop.store(true, std::memory_order_relaxed);
    control.join();
    const double boundMs = (kBoundFactor * idleWorstMs) + kBoundSlackMs;
    logInfo(std::format(
        "[info] {}: re-allocation idle worst {:.2f} ms; under an intent burst mean {:.2f} ms, "
        "worst {:.2f} ms (bound {:.2f} ms)\n",
        kName,
        idleWorstMs,
        burstTotalMs / kRounds,
        burstWorstMs,
        boundMs));
    if (burstWorstMs > boundMs)
    {
        logFail(kName,
                std::format(
                    "a re-allocation waited {:.2f} ms behind the intent burst (bound {:.2f} ms) — "
                    "the drain queue is growing",
                    burstWorstMs,
                    boundMs));
        return;
    }
    // The last intents win once the queue drains.
    const EqCurve last = eqFlatCurveWith(17U, 6.0F);
    (void)realizer->setPendingEq(last.data(), 31U, true);
    realizer->setPendingIntensity(0.25F);
    realizer->shutdown();
    const TargetState& state = realizer->canonicalState();
    const EQParams expected = makeEqParams(last, 48000U);
    if (state.intensityLinear != 0.25F || state.eq.k != expected.k || state.eq.m1 != expected.m1)
    {
        logFail(kName, "the last intents did not win after the race");
        return;
    }
    logPass(kName);
}
