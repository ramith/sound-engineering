// EqEngineBreakItMeasurements.inc
//
// Sprint EQ — the MEASUREMENT half of the EQ-engine break-it pass (the red tests are in
// EqEngineBreakItTests.inc). Not part of `make gate`: #included only by
// Tests/EqEngineBreakItMeasure.cpp, built by research/eq-engine-break-it/build-measure.sh, and run
// by name. Every figure in the break-it report comes from one of these; the run that produced
// them is research/eq-engine-break-it/out-measurements.txt.
//
//   tau-classes            which curves the τ rule sends to 10 / 40 / 160 ms
//   tau-from-published     a jagged curve then two calm ones Δ ms apart (the rule's "from" is the
//                          published target, not where the module is)
//   local-swells           the adversarial pairs' "local" excursions: level, length, frequency
//   drag-latency           publish → 50 % / 90 % of a band's change, at the rule's τ
//   jagged-false-positives single points the rule calls jagged, and low bands it calls calm, at
//                          a forced 10 / 40 ms vs the rule
//   calm-pair-search       a TD search over pairs the rule sends to 10 / 40 ms
//   cpu                    the EQ module's cost by rate × channels × block, settled / gliding
//   app-safety-clamp-gap   graph vs played while AudioEngineBridge still sends EQSafetyClamp
//   normaliser-poison      one NaN / +Inf sample into the loudness normaliser
//   p0-switch              the P1 → P0 level step on a loud master; the 5 ms fade's dip
//   intensity-zero-swing   the Intensity-0 boundary as a level-vs-time trace
//   designer-accuracy      extra rates, fresh Rämö seeds, a hill-climb
//   predictor-adversarial  the EQ1c predictor on tonal / DC / ultrasonic / silent programmes
//   storm                  render + intent storm + re-allocations: RT allocations, finiteness
//   rt-vs-readback         the settled RT module vs the read-back: low bands at 192 / 768 kHz,
//                          the top band near Nyquist at 44.1 kHz

#include "../Sources/AudioDSP/Loudness/LoudnessModule.h"

namespace
{
    constexpr double kBkFs = 48000.0;

    auto bkLine(const std::string& text) -> void
    {
        logInfo(text + "\n");
    }

    auto bkCurveText(const EqCurve& curve) -> std::string
    {
        std::string text;
        for (const float point : curve)
        {
            text += std::format(" {:+.1f}", point);
        }
        return text;
    }

    // ---------------------------------------------------------------------------------------------
    // The sequence runner: the REAL Realizer's published EQParams through a bare EQModule, with
    // quadrature probes (exact envelopes) against the ANALYTIC response of every endpoint.
    // ---------------------------------------------------------------------------------------------

    // The EQParams the Realizer publishes for `curves`, in order (Realizer::applyEq: the production
    // τ rule and its "from" bookkeeping).
    auto bkRealizerParams(const std::vector<EqCurve>& curves, double fs) -> std::vector<EQParams>
    {
        auto kernel = std::make_shared<DSPKernel>();
        kernel->initialize(static_cast<uint32_t>(fs), kTdBlockFrames);
        auto realizer = std::make_shared<AdaptiveSound::Realizer>(kernel, fs);
        std::vector<EQParams> published;
        for (const EqCurve& curve : curves)
        {
            AdaptiveSound::Realizer::EqIntent intent{};
            intent.points = curve;
            intent.isOn = true;
            realizer->applyEq(intent);
            published.push_back(realizer->canonicalState().eq);
            // The shape only: since EQ1c part 2 the Realizer publishes the loudness-neutral gain
            // with the coefficients, and every reference here is the designer's shape read-back.
            published.back().outputGainDb = 0.0;
        }
        realizer->shutdown();
        return published;
    }

    struct BkProbe
    {
        double hz = 0.0;
        double referenceDb = 0.0; // max over the endpoints of the analytic |H(f)| (dB)
        double maxEnvelopeDb = -std::numeric_limits<double>::infinity();
        double msAbove1Db = 0.0; // time spent > reference + 1 dB
        double msAbove3Db = 0.0; // … > reference + 3 dB
        double peakAtMs = 0.0;   // when the maximum happened, after the first switch
    };

    struct BkSequence
    {
        std::vector<TdEvent> events;
        std::vector<GraphicEQDesign> endpoints;
    };

    struct BkResult
    {
        std::vector<BkProbe> probes;
        double localDb = -std::numeric_limits<double>::infinity(); // worst probe vs its own ref
        double localHz = 0.0;
        double peakDb = -std::numeric_limits<double>::infinity(); // loudest env vs loudest ref
    };

    struct BkTimedCurve
    {
        double atSeconds = 0.0;
        EqCurve curve{};
    };

    // `steps` published through the Realizer at their times, as module events + endpoint designs.
    auto bkRealizerSequence(const std::vector<BkTimedCurve>& steps, double fs) -> BkSequence
    {
        std::vector<EqCurve> curves;
        curves.reserve(steps.size());
        for (const BkTimedCurve& step : steps)
        {
            curves.push_back(step.curve);
        }
        const std::vector<EQParams> published = bkRealizerParams(curves, fs);
        BkSequence sequence;
        for (size_t i = 0; i < steps.size(); ++i)
        {
            const auto frame = static_cast<uint32_t>(std::llround(steps[i].atSeconds * fs));
            sequence.events.push_back({frame, published[i]});
            sequence.endpoints.push_back(tdDesign(steps[i].curve, fs));
        }
        return sequence;
    }

    // The same events with the designs given explicitly (a forced τ).
    auto bkForcedPair(const EqCurve& from, const EqCurve& to, float tau, double atSeconds)
        -> BkSequence
    {
        const GraphicEQDesign a = tdDesign(from, kBkFs);
        const GraphicEQDesign b = tdDesign(to, kBkFs);
        BkSequence sequence;
        sequence.events = {
            TdEvent{0U, EQTargets::toParams(a, EQTargets::kRampSeconds)},
            TdEvent{static_cast<uint32_t>(atSeconds * kBkFs), EQTargets::toParams(b, tau)},
        };
        sequence.endpoints = {a, b};
        return sequence;
    }

    struct BkWindow
    {
        uint32_t analysisStart = 0U;
        uint32_t firstSwitch = 0U;
        double fs = 0.0;
    };

    // Fold one processed block of probe envelopes into the per-probe statistics.
    auto bkAccumulate(const TestABLN& abl,
                      const BkWindow& window,
                      uint32_t start,
                      uint32_t frames,
                      std::vector<BkProbe>& stats) -> void
    {
        const double msPerSample = 1000.0 / window.fs;
        for (size_t p = 0; p < stats.size(); ++p)
        {
            BkProbe& probe = stats[p];
            for (uint32_t i = 0U; i < frames; ++i)
            {
                const uint32_t n = start + i;
                if (n < window.analysisStart)
                {
                    continue;
                }
                const double env =
                    std::hypot(abl.channels[2U * p][i], abl.channels[(2U * p) + 1U][i]) /
                    kTdProbeAmplitude;
                const double envDb = 20.0 * std::log10(std::max(env, 1e-12));
                if (envDb > probe.maxEnvelopeDb)
                {
                    probe.maxEnvelopeDb = envDb;
                    probe.peakAtMs = (static_cast<double>(n) - window.firstSwitch) * msPerSample;
                }
                probe.msAbove1Db += (envDb > probe.referenceDb + 1.0) ? msPerSample : 0.0;
                probe.msAbove3Db += (envDb > probe.referenceDb + 3.0) ? msPerSample : 0.0;
            }
        }
    }

    // Up to four probes through a fresh module over the sequence's events.
    auto bkRunProbes(const BkSequence& sequence,
                     const std::vector<double>& probesHz,
                     const BkWindow& window,
                     uint32_t totalFrames) -> std::vector<BkProbe>
    {
        std::vector<BkProbe> stats(probesHz.size());
        for (size_t p = 0; p < probesHz.size(); ++p)
        {
            stats[p].hz = probesHz[p];
            double ref = -std::numeric_limits<double>::infinity();
            for (const GraphicEQDesign& design : sequence.endpoints)
            {
                ref = std::max(ref, GraphicEQDesigner::playedDb(design, probesHz[p]));
            }
            stats[p].referenceDb = ref;
        }
        auto module = std::make_unique<EQModule>();
        module->initialize(static_cast<uint32_t>(window.fs), kTdBlockFrames);
        TestABLN abl(static_cast<uint32_t>(2U * probesHz.size()), kTdBlockFrames);
        size_t next = 0U;
        for (uint32_t start = 0U; start < totalFrames; start += kTdBlockFrames)
        {
            const uint32_t frames = std::min(kTdBlockFrames, totalFrames - start);
            for (; next < sequence.events.size() && sequence.events[next].frame <= start; ++next)
            {
                module->update(sequence.events[next].params);
            }
            tdFillProbes(abl, probesHz, window.fs, start, frames);
            module->process(MultichannelView::fromABL(abl.abl(), frames));
            bkAccumulate(abl, window, start, frames, stats);
        }
        return stats;
    }

    // local = how far a probe's envelope rises above the loudest endpoint AT THAT FREQUENCY;
    // peak = the loudest envelope anywhere vs the loudest endpoint anywhere (the builders'
    // "peak"). Analysis starts 20 ms before the first event after frame 0.
    auto bkRun(const BkSequence& sequence,
               const std::vector<double>& probesHz,
               double fs,
               uint32_t totalFrames) -> BkResult
    {
        BkWindow window{.fs = fs};
        window.firstSwitch = totalFrames;
        for (const TdEvent& event : sequence.events)
        {
            if (event.frame > 0U)
            {
                window.firstSwitch = std::min(window.firstSwitch, event.frame);
            }
        }
        window.analysisStart = window.firstSwitch - static_cast<uint32_t>(0.02 * fs);
        BkResult result;
        for (size_t first = 0; first < probesHz.size(); first += kTdProbesPerRun)
        {
            const size_t count = std::min(kTdProbesPerRun, probesHz.size() - first);
            const std::vector<double> run(probesHz.begin() + static_cast<std::ptrdiff_t>(first),
                                          probesHz.begin() +
                                              static_cast<std::ptrdiff_t>(first + count));
            for (const BkProbe& probe : bkRunProbes(sequence, run, window, totalFrames))
            {
                result.probes.push_back(probe);
            }
        }
        double loudestRef = -std::numeric_limits<double>::infinity();
        double loudestEnv = -std::numeric_limits<double>::infinity();
        for (const BkProbe& probe : result.probes)
        {
            loudestRef = std::max(loudestRef, probe.referenceDb);
            loudestEnv = std::max(loudestEnv, probe.maxEnvelopeDb);
            if (probe.maxEnvelopeDb - probe.referenceDb > result.localDb)
            {
                result.localDb = probe.maxEnvelopeDb - probe.referenceDb;
                result.localHz = probe.hz;
            }
        }
        result.peakDb = loudestEnv - loudestRef;
        return result;
    }

    auto bkReport(const std::string& label, const BkResult& result, bool perProbe) -> void
    {
        double longest1 = 0.0;
        double longest3 = 0.0;
        double loudestRef = -std::numeric_limits<double>::infinity();
        for (const BkProbe& probe : result.probes)
        {
            longest1 = std::max(longest1, probe.msAbove1Db);
            longest3 = std::max(longest3, probe.msAbove3Db);
            loudestRef = std::max(loudestRef, probe.referenceDb);
        }
        bkLine(
            std::format("  {:58s} local {:+6.2f} dB @ {:6.0f} Hz  peak {:+5.2f} dB  longest "
                        ">+1dB {:6.1f} ms  >+3dB {:6.1f} ms",
                        label,
                        result.localDb,
                        result.localHz,
                        result.peakDb,
                        longest1,
                        longest3));
        if (!perProbe)
        {
            return;
        }
        for (const BkProbe& probe : result.probes)
        {
            if (probe.maxEnvelopeDb - probe.referenceDb > 0.5)
            {
                bkLine(
                    std::format("      {:7.0f} Hz  ref {:+6.2f} dB ({:+6.2f} vs curve max)  max "
                                "{:+6.2f}  local {:+5.2f}  >+1dB {:5.1f} ms  >+3dB {:5.1f} ms  "
                                "peak at +{:5.1f} ms",
                                probe.hz,
                                probe.referenceDb,
                                probe.referenceDb - loudestRef,
                                probe.maxEnvelopeDb,
                                probe.maxEnvelopeDb - probe.referenceDb,
                                probe.msAbove1Db,
                                probe.msAbove3Db,
                                probe.peakAtMs));
            }
        }
    }

    // The slowest band τ of a published target (s). Since the fix round (amendment 15) each band
    // has its own; the reports print the slowest one.
    auto bkSlowestTau(const EQParams& params) -> float
    {
        return std::ranges::max(params.bandRampSeconds);
    }

    auto bkRuleTau(const EqCurve& from, const EqCurve& to) -> float
    {
        return std::ranges::max(
            EQTargets::rampsFor(tdDesign(from, kBkFs), tdDesign(to, kBkFs)).band);
    }

    // ---------------------------------------------------------------------------------------------
    // M1 tau-classes
    // ---------------------------------------------------------------------------------------------

    auto bkNamedPresets() -> std::vector<std::pair<std::string, EqCurve>>
    {
        constexpr std::array<const char*, 6> kNames = {
            "Presence",
            "Clarity",
            "Warm",
            "Loudness",
            "Vocal",
            "Studio",
        };
        std::vector<std::pair<std::string, EqCurve>> curves;
        curves.reserve(kEqPresetCurves.size());
        for (size_t i = 0; i < kEqPresetCurves.size(); ++i)
        {
            curves.emplace_back(kNames[i], kEqPresetCurves[i]);
        }
        return curves;
    }

    auto bkShapeCurves() -> std::vector<std::pair<std::string, EqCurve>>
    {
        std::vector<std::pair<std::string, EqCurve>> curves;
        EqCurve pair{};
        pair[17] = 12.0F;
        pair[18] = 12.0F;
        curves.emplace_back("two adjacent +12 (1k, 1.25k)", pair);
        EqCurve cliff{};
        cliff[17] = 12.0F;
        cliff[18] = -12.0F;
        curves.emplace_back("cliff +12/-12 (1k/1.25k)", cliff);
        EqCurve step{};
        std::fill(step.begin() + 17, step.end(), 12.0F);
        curves.emplace_back("step 0 -> +12 at 1 kHz", step);
        EqCurve shelf{};
        std::fill(shelf.begin(), shelf.begin() + 8, 12.0F);
        curves.emplace_back("bass +12 up to 100 Hz, hard edge", shelf);
        EqCurve notch{};
        notch[16] = -6.0F;
        notch[17] = -12.0F;
        notch[18] = -6.0F;
        curves.emplace_back("3-band notch -6/-12/-6", notch);
        EqCurve dragUp = kEqPresetCurves[kEqPresetWarm];
        dragUp[8] = 12.0F;
        curves.emplace_back("Warm, 125 Hz dragged to +12", dragUp);
        EqCurve dragDown = kEqPresetCurves[kEqPresetWarm];
        dragDown[8] = -12.0F;
        curves.emplace_back("Warm, 125 Hz pulled to -12 (one point)", dragDown);
        return curves;
    }

    auto measureTauClasses() -> void
    {
        std::vector<std::pair<std::string, EqCurve>> curves = bkNamedPresets();
        for (const size_t band : {3U, 10U, 17U, 24U, 27U, 30U})
        {
            for (const float gain : {6.0F, 9.0F, 12.0F, -12.0F})
            {
                curves.emplace_back(std::format("single band {} ({:.0f} Hz) {:+.0f}",
                                                band,
                                                GraphicEQ::centreHz(static_cast<int>(band)),
                                                gain),
                                    eqFlatCurveWith(band, gain));
            }
        }
        for (auto& named : bkShapeCurves())
        {
            curves.push_back(std::move(named));
        }
        const std::vector<std::array<double, 5>> tones = {
            {12, 0, 0, 0, 0},
            {0, 0, 12, 0, 0},
            {0, 0, 0, 0, 12},
            {12, 0, -12, 0, 12},
            {12, -12, 12, -12, 12},
        };
        for (const auto& tone : tones)
        {
            curves.emplace_back(std::format("Tone {:+.0f} {:+.0f} {:+.0f} {:+.0f} {:+.0f}",
                                            tone[0],
                                            tone[1],
                                            tone[2],
                                            tone[3],
                                            tone[4]),
                                eqToneCurve(tone));
        }
        for (const auto& [name, curve] : curves)
        {
            bkLine(std::format("  {:44s} max|solved| {:6.2f} dB  Off->it tau {:3.0f} ms",
                               name,
                               breakItMaxSolvedGainDb(curve, kBkFs),
                               bkRuleTau(EqCurve{}, curve) * 1000.0F));
        }
    }

    // ---------------------------------------------------------------------------------------------
    // M2 tau-from-published
    // ---------------------------------------------------------------------------------------------

    struct BkCalmHop
    {
        std::string name;
        EqCurve via;
        EqCurve to;
    };

    auto bkJaggedThenCalm(const std::string& jaggedName,
                          const EqCurve& jagged,
                          const BkCalmHop& hop) -> void
    {
        const auto totalFrames = static_cast<uint32_t>(3.2 * kBkFs);
        const std::vector<double> probes = tdProbes(1U);
        const BkSequence direct = bkRealizerSequence({{0.0, jagged}, {1.0, hop.to}}, kBkFs);
        bkReport(std::format("{} -> {}'s end (direct, tau {:.0f} ms)",
                             jaggedName,
                             hop.name,
                             bkSlowestTau(direct.events[1].params) * 1000.0F),
                 bkRun(direct, probes, kBkFs, totalFrames),
                 false);
        for (const double deltaMs : {10.0, 30.0, 60.0, 120.0, 250.0})
        {
            const BkSequence hopped = bkRealizerSequence(
                {{0.0, jagged}, {1.0, hop.via}, {1.0 + (deltaMs / 1000.0), hop.to}}, kBkFs);
            bkReport(std::format("{} -> [{}] +{:.0f} ms (tau {:.0f}/{:.0f})",
                                 jaggedName,
                                 hop.name,
                                 deltaMs,
                                 bkSlowestTau(hopped.events[1].params) * 1000.0F,
                                 bkSlowestTau(hopped.events[2].params) * 1000.0F),
                     bkRun(hopped, probes, kBkFs, totalFrames),
                     false);
        }
    }

    auto measureTauFromPublished() -> void
    {
        const EqCurve warm = kEqPresetCurves[kEqPresetWarm];
        const EqCurve presence = kEqPresetCurves[0];
        EqCurve warmNotch = warm;
        warmNotch[8] = -12.0F;
        const std::vector<std::pair<std::string, EqCurve>> jagged = {
            {"alternating", eqAlternatingCurve()},
            {"v3_worst_tau40[A]", kTdWorstTau40[0]},
            {"single +12 @ 1 kHz", eqFlatCurveWith(17U, 12.0F)},
            {"Warm w/ 125 Hz at -12", warmNotch},
        };
        const std::vector<BkCalmHop> hops = {
            {"Off -> Warm", EqCurve{}, warm},
            {"Warm -> Presence", warm, presence},
            {"Presence -> Off", presence, EqCurve{}},
        };
        for (const auto& [name, curve] : jagged)
        {
            for (const BkCalmHop& hop : hops)
            {
                bkJaggedThenCalm(name, curve, hop);
            }
        }
    }

    // ---------------------------------------------------------------------------------------------
    // M3 local-swells
    // ---------------------------------------------------------------------------------------------

    auto measureLocalSwells() -> void
    {
        const auto totalFrames = static_cast<uint32_t>(3.8 * kBkFs);
        const std::vector<double> probes = tdProbes(1U);
        const std::vector<std::pair<const char*, const std::array<EqCurve, 2>*>> pairs = {
            {"adv_pair_S2", &kTdAdvPairS2},
            {"v3_worst_tau40", &kTdWorstTau40},
            {"worst_pair", &kTdWorstPair},
        };
        for (const auto& [name, pair] : pairs)
        {
            const BkSequence sequence =
                bkRealizerSequence({{0.0, (*pair)[0]}, {1.5, (*pair)[1]}}, kBkFs);
            bkReport(std::format("{} (tau {:.0f} ms)",
                                 name,
                                 bkSlowestTau(sequence.events[1].params) * 1000.0F),
                     bkRun(sequence, probes, kBkFs, totalFrames),
                     true);
        }
    }

    // ---------------------------------------------------------------------------------------------
    // M4 drag-latency
    // ---------------------------------------------------------------------------------------------

    struct BkStep
    {
        std::string name;
        EqCurve from{};
        EqCurve to{};
        double probeHz = 0.0;
    };

    struct BkLatency
    {
        double t50Ms = -1.0;
        double t90Ms = -1.0;
    };

    // Publish → 50 % / 90 % of the change (in dB) at the probe, one probe through the module.
    auto bkLatency(const BkSequence& sequence, double probeHz) -> BkLatency
    {
        const auto totalFrames = static_cast<uint32_t>(2.0 * kBkFs);
        const double fromDb = GraphicEQDesigner::playedDb(sequence.endpoints[0], probeHz);
        const double toDb = GraphicEQDesigner::playedDb(sequence.endpoints[1], probeHz);
        auto module = std::make_unique<EQModule>();
        module->initialize(static_cast<uint32_t>(kBkFs), kTdBlockFrames);
        TestABLN abl(2U, kTdBlockFrames);
        size_t next = 0U;
        BkLatency latency;
        const uint32_t switchFrame = sequence.events[1].frame;
        for (uint32_t start = 0U; start < totalFrames; start += kTdBlockFrames)
        {
            for (; next < sequence.events.size() && sequence.events[next].frame <= start; ++next)
            {
                module->update(sequence.events[next].params);
            }
            tdFillProbes(abl, {probeHz}, kBkFs, start, kTdBlockFrames);
            module->process(MultichannelView::fromABL(abl.abl(), kTdBlockFrames));
            for (uint32_t i = 0U; i < kTdBlockFrames && start + i >= switchFrame; ++i)
            {
                const double envDb =
                    20.0 * std::log10(std::hypot(abl.channels[0][i], abl.channels[1][i]) /
                                      kTdProbeAmplitude);
                const double progress = (envDb - fromDb) / (toDb - fromDb);
                const double ms = 1000.0 * static_cast<double>(start + i - switchFrame) / kBkFs;
                latency.t50Ms = (latency.t50Ms < 0.0 && progress >= 0.5) ? ms : latency.t50Ms;
                latency.t90Ms = (latency.t90Ms < 0.0 && progress >= 0.9) ? ms : latency.t90Ms;
            }
        }
        return latency;
    }

    auto measureDragLatency() -> void
    {
        const auto single = [](float a, float b)
        { return std::pair{eqFlatCurveWith(17U, a), eqFlatCurveWith(17U, b)}; };
        std::vector<BkStep> steps;
        for (const auto& [a, b] : {std::pair{11.0F, 12.0F}, {9.0F, 10.0F}, {5.0F, 6.0F}})
        {
            const auto [from, to] = single(a, b);
            steps.push_back(
                {std::format("key step 1 kHz {:+.0f} -> {:+.0f}", a, b), from, to, 1000.0});
        }
        EqCurve warmNotch = kEqPresetCurves[kEqPresetWarm];
        warmNotch[8] = -10.0F;
        EqCurve warmNotchDeeper = warmNotch;
        warmNotchDeeper[8] = -12.0F;
        steps.push_back({"Warm, 125 Hz -10 -> -12", warmNotch, warmNotchDeeper, 125.89});
        EqCurve alternatingEdit = eqAlternatingCurve();
        alternatingEdit[17] = 6.0F;
        steps.push_back(
            {"alternating, 1 kHz +12 -> +6", eqAlternatingCurve(), alternatingEdit, 1000.0});
        for (const BkStep& step : steps)
        {
            const BkSequence sequence =
                bkRealizerSequence({{0.0, step.from}, {0.5, step.to}}, kBkFs);
            const BkLatency latency = bkLatency(sequence, step.probeHz);
            bkLine(
                std::format("  {:34s} tau {:3.0f} ms: {:+6.2f} -> {:+6.2f} dB at {:.0f} Hz; 50% "
                            "at {:6.1f} ms, 90% at {:6.1f} ms",
                            step.name,
                            bkSlowestTau(sequence.events[1].params) * 1000.0F,
                            GraphicEQDesigner::playedDb(sequence.endpoints[0], step.probeHz),
                            GraphicEQDesigner::playedDb(sequence.endpoints[1], step.probeHz),
                            step.probeHz,
                            latency.t50Ms,
                            latency.t90Ms));
        }
    }

    // ---------------------------------------------------------------------------------------------
    // M13 jagged-false-positives
    // ---------------------------------------------------------------------------------------------

    auto bkStep(std::string name, const EqCurve& from, const EqCurve& to, double probeHz) -> BkStep
    {
        BkStep step;
        step.name = std::move(name);
        step.from = from;
        step.to = to;
        step.probeHz = probeHz;
        return step;
    }

    // Off → one point at each gain, for each band.
    auto bkOffToPoint(const std::vector<size_t>& bands, const std::vector<float>& gains)
        -> std::vector<BkStep>
    {
        std::vector<BkStep> cases;
        cases.reserve(bands.size() * gains.size());
        for (const size_t band : bands)
        {
            const double hz = GraphicEQ::centreHz(static_cast<int>(band));
            for (const float gain : gains)
            {
                cases.push_back(bkStep(std::format("Off -> {:+.0f} @ {:.0f} Hz", gain, hz),
                                       EqCurve{},
                                       eqFlatCurveWith(band, gain),
                                       hz));
            }
        }
        return cases;
    }

    auto bkSinglePointCases() -> std::vector<BkStep>
    {
        std::vector<BkStep> cases = bkOffToPoint({3U, 10U, 17U, 24U, 27U}, {12.0F, -12.0F});
        const EqCurve at1k = eqFlatCurveWith(17U, 12.0F);
        cases.push_back(
            bkStep("key step +11 -> +12 @ 1 kHz", eqFlatCurveWith(17U, 11.0F), at1k, 1000.0));
        cases.push_back(bkStep(
            "+12 @ 1 kHz -> +12 @ 1.26 kHz (move)", at1k, eqFlatCurveWith(18U, 12.0F), 1000.0));
        cases.push_back(bkStep(
            "+12 @ 1 kHz -> -12 @ 1 kHz (flip)", at1k, eqFlatCurveWith(17U, -12.0F), 1000.0));
        EqCurve warmNotch = kEqPresetCurves[kEqPresetWarm];
        warmNotch[8] = -12.0F;
        cases.push_back(bkStep(
            "Warm -> Warm w/ 125 Hz at -12", kEqPresetCurves[kEqPresetWarm], warmNotch, 125.89));
        // Calm by the rule (τ 10 / 40 ms): the low bands at moderate gain.
        for (BkStep& low : bkOffToPoint({0U, 1U, 2U, 3U, 4U, 5U}, {6.0F, 8.0F, 10.0F}))
        {
            cases.push_back(std::move(low));
        }
        return cases;
    }

    auto measureJaggedFalsePositives() -> void
    {
        const auto totalFrames = static_cast<uint32_t>(2.2 * kBkFs);
        const std::vector<double> probes = tdProbes(1U);
        for (const BkStep& step : bkSinglePointCases())
        {
            const float rule = bkRuleTau(step.from, step.to);
            for (const float tau : {0.010F, 0.040F, rule})
            {
                bkReport(
                    std::format("{} @ tau {:.0f}{}",
                                step.name,
                                tau * 1000.0F,
                                (tau == rule) ? " (rule)" : ""),
                    bkRun(bkForcedPair(step.from, step.to, tau, 0.6), probes, kBkFs, totalFrames),
                    false);
            }
        }
    }

    // ---------------------------------------------------------------------------------------------
    // M12 calm-pair-search
    // ---------------------------------------------------------------------------------------------

    auto bkRandomCalm(std::mt19937& rng) -> EqCurve
    {
        std::uniform_int_distribution<int> kind(0, 3);
        std::uniform_real_distribution<double> tone(-12.0, 12.0);
        std::uniform_int_distribution<size_t> band(0U, 30U);
        std::uniform_real_distribution<float> level(-12.0F, 12.0F);
        const int chosen = kind(rng);
        if (chosen == 0)
        {
            return eqToneCurve({tone(rng), tone(rng), tone(rng), tone(rng), tone(rng)});
        }
        if (chosen == 1)
        {
            EqCurve curve = kEqPresetCurves[band(rng) % kEqPresetCurves.size()];
            curve[band(rng)] = level(rng);
            return curve;
        }
        if (chosen == 2)
        {
            EqCurve curve{};
            const size_t first = std::min<size_t>(band(rng), 29U);
            curve[first] = level(rng);
            curve[first + 1U] = level(rng);
            return curve;
        }
        EqCurve curve = eqToneCurve({tone(rng), tone(rng), tone(rng), tone(rng), tone(rng)});
        curve[band(rng)] = level(rng);
        curve[band(rng)] = level(rng);
        return curve;
    }

    struct BkPair
    {
        EqCurve a{};
        EqCurve b{};
        double localDb = -std::numeric_limits<double>::infinity();
        double peakDb = -std::numeric_limits<double>::infinity();
    };

    auto bkScorePair(const EqCurve& a, const EqCurve& b) -> BkResult
    {
        const auto totalFrames = static_cast<uint32_t>(1.6 * kBkFs);
        return bkRun(
            bkRealizerSequence({{0.0, a}, {0.8, b}}, kBkFs), tdProbes(2U), kBkFs, totalFrames);
    }

    // "Calm" is the pre-fix-round rule's own class: no solved gain beyond 15 dB (the rule sent
    // anything else to 160 ms). The search still covers exactly that class.
    auto bkCalm(const EqCurve& curve) -> bool
    {
        constexpr double kCalmSolvedGainDb = 15.0;
        return breakItMaxSolvedGainDb(curve, kBkFs) <= kCalmSolvedGainDb;
    }

    auto bkHillClimb(BkPair start, std::mt19937& rng) -> BkPair
    {
        std::uniform_int_distribution<size_t> band(0U, 30U);
        std::uniform_real_distribution<float> level(-12.0F, 12.0F);
        std::uniform_int_distribution<int> which(0, 1);
        BkPair best = start;
        for (int iter = 0; iter < 300; ++iter)
        {
            BkPair trial = best;
            EqCurve& edited = (which(rng) == 0) ? trial.a : trial.b;
            edited[band(rng)] = std::round(level(rng));
            if (!bkCalm(trial.a) || !bkCalm(trial.b))
            {
                continue;
            }
            const BkResult result = bkScorePair(trial.a, trial.b);
            if (result.localDb > best.localDb)
            {
                trial.localDb = result.localDb;
                trial.peakDb = result.peakDb;
                best = trial;
            }
        }
        return best;
    }

    auto measureCalmPairSearch() -> void
    {
        std::mt19937 rng(77U);
        BkPair worstLocal;
        double worstPeak = -std::numeric_limits<double>::infinity();
        int tried = 0;
        while (tried < 400)
        {
            const EqCurve a = bkRandomCalm(rng);
            const EqCurve b = bkRandomCalm(rng);
            if (!bkCalm(a) || !bkCalm(b))
            {
                continue;
            }
            ++tried;
            const BkResult result = bkScorePair(a, b);
            worstPeak = std::max(worstPeak, result.peakDb);
            if (result.localDb > worstLocal.localDb)
            {
                worstLocal = {a, b, result.localDb, result.peakDb};
            }
        }
        bkLine(
            std::format("  random calm pairs ({}): worst peak {:+.3f} dB, worst local {:+.3f} dB",
                        tried,
                        worstPeak,
                        worstLocal.localDb));
        const BkPair climbed = bkHillClimb(worstLocal, rng);
        bkReport(std::format("hill-climbed calm pair (tau {:.0f} ms)",
                             bkRuleTau(climbed.a, climbed.b) * 1000.0F),
                 bkScorePair(climbed.a, climbed.b),
                 true);
        bkLine("    A:" + bkCurveText(climbed.a));
        bkLine("    B:" + bkCurveText(climbed.b));
        bkLine(std::format("    max|solved| A {:.2f}, B {:.2f}",
                           breakItMaxSolvedGainDb(climbed.a, kBkFs),
                           breakItMaxSolvedGainDb(climbed.b, kBkFs)));
    }

    // ---------------------------------------------------------------------------------------------
    // M5 cpu
    // ---------------------------------------------------------------------------------------------

    struct BkCpuRun
    {
        uint32_t fs = 0U;
        uint32_t channels = 0U;
        uint32_t block = 0U;
        bool gliding = false;
    };

    auto bkEqCpuPercent(const BkCpuRun& run) -> double
    {
        auto module = std::make_unique<EQModule>();
        module->initialize(run.fs, run.block);
        TestABLN abl(run.channels, run.block);
        std::vector<std::vector<float>> source(run.channels, std::vector<float>(run.block));
        std::mt19937 rng(7U);
        std::uniform_real_distribution<float> noise(-0.25F, 0.25F);
        for (auto& channel : source)
        {
            std::ranges::generate(channel, [&] { return noise(rng); });
        }
        const auto fill = [&]
        {
            for (uint32_t ch = 0U; ch < run.channels; ++ch)
            {
                std::ranges::copy(source[ch], abl.channels[ch].begin());
            }
        };
        const EQParams warm = makeEqParams(kEqPresetCurves[kEqPresetWarm], run.fs);
        const EQParams vocal = makeEqParams(kEqPresetCurves[4], run.fs, 1.0F);
        const EQParams back = makeEqParams(kEqPresetCurves[kEqPresetWarm], run.fs, 1.0F);
        module->update(warm);
        for (uint64_t done = 0U; done < run.fs; done += run.block) // 1 s to settle
        {
            fill();
            module->process(MultichannelView::fromABL(abl.abl(), run.block));
        }
        const uint64_t retargetEvery = std::max<uint64_t>(1U, run.fs / 2U / run.block);
        uint64_t blocks = 0U;
        const auto start = std::chrono::steady_clock::now();
        for (uint64_t done = 0U; done < run.fs; done += run.block, ++blocks)
        {
            if (run.gliding && blocks % retargetEvery == 0U)
            {
                module->update(((blocks / retargetEvery) % 2U == 0U) ? vocal : back);
            }
            fill();
            module->process(MultichannelView::fromABL(abl.abl(), run.block));
        }
        return 100.0 *
               std::chrono::duration<double>(std::chrono::steady_clock::now() - start).count();
    }

    auto measureCpu() -> void
    {
#ifdef __OPTIMIZE__
        bkLine("  (optimised build)");
#else
        bkLine("  (UNOPTIMISED build — not the claim's numbers)");
#endif
        for (const uint32_t fs : {48000U, 192000U, 384000U, 768000U})
        {
            for (const uint32_t channels : {2U, 8U})
            {
                for (const uint32_t block : {16U, 64U, 512U, 4096U})
                {
                    bkLine(std::format(
                        "  {:6} Hz x {} ch, block {:4}: settled {:6.2f} %, gliding {:6.2f} %",
                        fs,
                        channels,
                        block,
                        bkEqCpuPercent({fs, channels, block, false}),
                        bkEqCpuPercent({fs, channels, block, true})));
                }
            }
        }
    }

    // ---------------------------------------------------------------------------------------------
    // M6 app-safety-clamp-gap
    // ---------------------------------------------------------------------------------------------

    // A mirror of EQSafetyClamp.clamped (Sources/AdaptiveSound/EQSafetyClamp.swift): signed sum
    // above 12 dB → every band scaled by 12 / sum.
    auto bkSafetyClamped(EqCurve points) -> EqCurve
    {
        float total = 0.0F;
        for (const float point : points)
        {
            total += point;
        }
        if (total > 12.0F)
        {
            const float scale = 12.0F / total;
            for (float& point : points)
            {
                point *= scale;
            }
        }
        return points;
    }

    auto measureAppSafetyClampGap() -> void
    {
        std::vector<std::pair<std::string, EqCurve>> curves = bkNamedPresets();
        curves.emplace_back("Tone Bass +6", eqToneCurve({6, 0, 0, 0, 0}));
        curves.emplace_back("Tone Air +6", eqToneCurve({0, 0, 0, 0, 6}));
        curves.emplace_back("Tone Bass +12 Air +12", eqToneCurve({12, 0, 0, 0, 12}));
        curves.emplace_back("single +12 @ 1 kHz", eqFlatCurveWith(17U, 12.0F));
        EqCurve allUp{};
        allUp.fill(12.0F);
        curves.emplace_back("all +12", allUp);
        const std::vector<double> grid = eqUiGrid();
        for (const auto& [name, curve] : curves)
        {
            const GraphicEQDesign drawn = tdDesign(curve, kBkFs);
            const GraphicEQDesign played = tdDesign(bkSafetyClamped(curve), kBkFs);
            double worst = 0.0;
            double worstHz = 0.0;
            double peakDrawn = -std::numeric_limits<double>::infinity();
            double peakPlayed = -std::numeric_limits<double>::infinity();
            for (const double hz : grid)
            {
                const double a = GraphicEQDesigner::playedDb(drawn, hz);
                const double b = GraphicEQDesigner::playedDb(played, hz);
                peakDrawn = std::max(peakDrawn, a);
                peakPlayed = std::max(peakPlayed, b);
                worstHz = (std::abs(a - b) > worst) ? hz : worstHz;
                worst = std::max(worst, std::abs(a - b));
            }
            float total = 0.0F;
            for (const float point : curve)
            {
                total += point;
            }
            bkLine(
                std::format("  {:24s} signed sum {:+7.2f} dB  graph peak {:+6.2f} dB, plays "
                            "{:+6.2f} dB; worst gap {:5.2f} dB @ {:6.0f} Hz",
                            name,
                            total,
                            peakDrawn,
                            peakPlayed,
                            worst,
                            worstHz));
        }
    }

    // ---------------------------------------------------------------------------------------------
    // M7 normaliser-poison
    // ---------------------------------------------------------------------------------------------

    auto bkFeedTone(LoudnessModule& module, uint64_t& n, double seconds, float poison) -> TestABL
    {
        constexpr uint32_t kBlock = 512U;
        TestABL abl(kBlock);
        const auto blocks = static_cast<uint32_t>(seconds * kBkFs / kBlock);
        const LoudnessParams params;
        for (uint32_t b = 0U; b < blocks; ++b)
        {
            for (uint32_t i = 0U; i < kBlock; ++i, ++n)
            {
                abl.left[i] = static_cast<float>(0.5 * std::sin(2.0 * std::numbers::pi * 1000.0 *
                                                                static_cast<double>(n) / kBkFs));
                abl.right[i] = abl.left[i];
            }
            abl.left[100] = (b == 0U && poison != 0.0F) ? poison : abl.left[100];
            module.process(params, MultichannelView::fromABL(abl.abl(), kBlock));
            std::this_thread::sleep_for(std::chrono::microseconds(500));
        }
        return abl;
    }

    auto measureNormaliserPoison() -> void
    {
        for (const float bad :
             {std::numeric_limits<float>::infinity(), std::numeric_limits<float>::quiet_NaN()})
        {
            LoudnessModule module;
            module.initialize(static_cast<uint32_t>(kBkFs), 512U);
            uint64_t n = 0U;
            (void)bkFeedTone(module, n, 6.0, 0.0F);
            const float makeupBefore = module.currentMakeupGainLinear();
            const float lufsBefore = module.measuredLufsIntegrated();
            (void)bkFeedTone(module, n, 0.02, bad);
            const TestABL last = bkFeedTone(module, n, 6.0, 0.0F);
            const bool finite =
                std::ranges::all_of(last.left, [](float v) { return std::isfinite(v); });
            bkLine(
                std::format("  {}: before: makeup {:.4f} ({:.2f} dB), integrated {:.2f} LUFS | 6 s "
                            "after: makeup {:.4f}, integrated {:.2f} LUFS, short-term {:.2f}, "
                            "output finite={}",
                            std::isinf(bad) ? "+Inf" : "NaN",
                            makeupBefore,
                            20.0 * std::log10(makeupBefore),
                            lufsBefore,
                            module.currentMakeupGainLinear(),
                            module.measuredLufsIntegrated(),
                            module.measuredLufsShortTerm(),
                            finite));
        }
    }

    // ---------------------------------------------------------------------------------------------
    // M10 p0-switch
    // ---------------------------------------------------------------------------------------------

    struct BkStereo
    {
        std::vector<float> left;
        std::vector<float> right;
    };

    // The loud master through the kernel at Intensity 0: EQ Warm, then Off at 3 s.
    auto bkLoudMasterWarmThenOff(const TlProgramme& master, float ceilingDbtp) -> BkStereo
    {
        constexpr uint32_t kBlock = 512U;
        const auto fs = static_cast<uint32_t>(master.sampleRate);
        TargetState state{};
        state.limiter.truePeakCeilingLinear = std::pow(10.0F, ceilingDbtp / 20.0F);
        state.intensityLinear = 0.0F;
        state.eq = makeEqParams(kEqPresetCurves[kEqPresetWarm], fs);
        DSPKernel kernel;
        kernel.publishTargetState(state);
        kernel.initialize(fs, kBlock);
        TestABL abl(kBlock);
        BkStereo out;
        const size_t total = std::min<size_t>(master.frames(), static_cast<size_t>(8U) * fs);
        const size_t offBlock = (static_cast<size_t>(3U) * fs) / kBlock;
        for (size_t block = 0U; (block + 1U) * kBlock <= total; ++block)
        {
            if (block == offBlock)
            {
                state.eq = makeEqParams(EqCurve{}, fs);
                kernel.publishTargetState(state);
            }
            const auto offset = static_cast<std::ptrdiff_t>(block * kBlock);
            std::copy_n(master.channels[0].begin() + offset, kBlock, abl.left.begin());
            std::copy_n(master.channels[1].begin() + offset, kBlock, abl.right.begin());
            kernel.process(abl.abl(), kBlock);
            out.left.insert(out.left.end(), abl.left.begin(), abl.left.end());
            out.right.insert(out.right.end(), abl.right.begin(), abl.right.end());
        }
        return out;
    }

    auto bkWindowLufsAndPeak(const BkStereo& audio, size_t from, size_t to, double fs)
        -> std::pair<double, double>
    {
        std::vector<std::vector<float>> channels = {
            std::vector<float>(audio.left.begin() + static_cast<std::ptrdiff_t>(from),
                               audio.left.begin() + static_cast<std::ptrdiff_t>(to)),
            std::vector<float>(audio.right.begin() + static_cast<std::ptrdiff_t>(from),
                               audio.right.begin() + static_cast<std::ptrdiff_t>(to)),
        };
        float peak = 0.0F;
        for (const auto& channel : channels)
        {
            for (const float v : channel)
            {
                peak = std::max(peak, std::abs(v));
            }
        }
        return {tlEbur128Lufs(channels, fs), 20.0 * std::log10(peak)};
    }

    auto bkP0StepAt(float ceilingDbtp) -> void
    {
        const TlProgramme& master = tlGateLoudMaster(); // −9 LUFS, soft-clipped, 48 kHz stereo
        const double fs = master.sampleRate;
        const BkStereo out = bkLoudMasterWarmThenOff(master, ceilingDbtp);
        const BkStereo source{master.channels[0], master.channels[1]};
        size_t p0 = out.left.size();
        for (size_t s = static_cast<size_t>(3.0 * fs); s + 512U <= out.left.size(); s += 512U)
        {
            if (std::equal(out.left.begin() + static_cast<std::ptrdiff_t>(s),
                           out.left.begin() + static_cast<std::ptrdiff_t>(s + 512U),
                           master.channels[0].begin() + static_cast<std::ptrdiff_t>(s)))
            {
                p0 = s;
                break;
            }
        }
        const auto span = static_cast<size_t>(1.5 * fs);
        const auto [lufsBefore, peakBefore] = bkWindowLufsAndPeak(out, p0 - span, p0, fs);
        const auto [lufsAfter, peakAfter] = bkWindowLufsAndPeak(out, p0, p0 + span, fs);
        const auto [srcBefore, srcPeakBefore] = bkWindowLufsAndPeak(source, p0 - span, p0, fs);
        bkLine(
            std::format("  ceiling {:.1f} dBTP: Intensity 0, EQ Warm -> Off at 3.0 s; "
                        "bit-perfect from {:.3f} s",
                        ceilingDbtp,
                        static_cast<double>(p0) / fs));
        bkLine(
            std::format("    1.5 s before P0 (P1: the limiter on a flat EQ): {:.2f} LUFS, sample "
                        "peak {:+.2f} dBFS (the source there: {:.2f} LUFS, {:+.2f} dBFS)",
                        lufsBefore,
                        peakBefore,
                        srcBefore,
                        srcPeakBefore));
        bkLine(
            std::format("    1.5 s after P0 (bit-perfect): {:.2f} LUFS, sample peak {:+.2f} dBFS",
                        lufsAfter,
                        peakAfter));
    }

    // The P1 → P0 equal-gain fade on white noise: the worst 1 ms energy vs the input.
    auto bkFadeDip() -> void
    {
        constexpr uint32_t kBlock = 512U;
        TargetState state{};
        state.intensityLinear = 0.0F;
        DSPKernel kernel;
        kernel.publishTargetState(state);
        kernel.initialize(static_cast<uint32_t>(kBkFs), kBlock);
        state.eq = makeEqParams(eqFlatCurveWith(0U, -0.5F), static_cast<uint32_t>(kBkFs));
        kernel.publishTargetState(state);
        std::mt19937 rng(5U);
        std::normal_distribution<float> gauss(0.0F, 0.1F);
        TestABL abl(kBlock);
        std::vector<float> in;
        std::vector<float> out;
        for (int b = 0; b < 400; ++b)
        {
            if (b == 50)
            {
                state.eq = makeEqParams(EqCurve{}, static_cast<uint32_t>(kBkFs));
                kernel.publishTargetState(state);
            }
            std::ranges::generate(abl.left, [&] { return gauss(rng); });
            abl.right = abl.left;
            in.insert(in.end(), abl.left.begin(), abl.left.end());
            kernel.process(abl.abl(), kBlock);
            out.insert(out.end(), abl.left.begin(), abl.left.end());
        }
        size_t exact = out.size();
        for (size_t n = static_cast<size_t>(50U) * kBlock; n + 64U < out.size(); ++n)
        {
            if (std::equal(out.begin() + static_cast<std::ptrdiff_t>(n),
                           out.begin() + static_cast<std::ptrdiff_t>(n + 64U),
                           in.begin() + static_cast<std::ptrdiff_t>(n)))
            {
                exact = n;
                break;
            }
        }
        double worstDb = 0.0;
        for (size_t n = exact - 480U; n <= exact; n += 12U) // 1 ms windows over the last 10 ms
        {
            double energyOut = 0.0;
            double energyIn = 0.0;
            for (size_t k = n; k < n + 48U; ++k)
            {
                energyOut += static_cast<double>(out[k]) * out[k];
                energyIn += static_cast<double>(in[k]) * in[k];
            }
            worstDb = std::min(worstDb, 10.0 * std::log10(energyOut / energyIn));
        }
        bkLine(
            std::format("  P1 -> P0 fade on white noise: worst 1 ms energy vs the input {:.2f} dB "
                        "(bit-perfect from {:.3f} s)",
                        worstDb,
                        static_cast<double>(exact) / kBkFs));
    }

    auto measureP0Switch() -> void
    {
        bkP0StepAt(-1.0F);
        bkP0StepAt(-0.1F); // decision 29's EQ-only ceiling (EQ2)
        bkFadeDip();
    }

    // ---------------------------------------------------------------------------------------------
    // M14 intensity-zero-swing
    // ---------------------------------------------------------------------------------------------

    auto bkSwing(double amplitude) -> void
    {
        TargetState state{};
        state.clarity.enabled = 0U;
        state.intensityLinear = 0.3F;
        DSPKernel kernel;
        kernel.publishTargetState(state);
        kernel.initialize(static_cast<uint32_t>(kBkFs), kEngineBlock);
        EngineSine sine;
        sine.amplitude = amplitude;
        std::vector<float> out;
        for (uint32_t b = 0U; b < engineBlocksFor(14.0); ++b) // paced: the worker keeps up
        {
            engineRunSine(kernel, sine, 1U, out);
            std::this_thread::sleep_for(std::chrono::microseconds(700));
        }
        const size_t switchAt = out.size();
        state.intensityLinear = 0.0F;
        kernel.publishTargetState(state);
        engineRunSine(kernel, sine, engineBlocksFor(0.6), out);
        constexpr size_t kWindow = 240U; // 5 ms
        const auto levelDb = [&](size_t from)
        {
            double energy = 0.0;
            for (size_t n = from; n < from + kWindow; ++n)
            {
                energy += static_cast<double>(out[n]) * out[n];
            }
            return 10.0 * std::log10((energy / kWindow) / (amplitude * amplitude / 2.0));
        };
        std::vector<double> levels;
        for (size_t n = switchAt; n + kWindow <= out.size(); n += kWindow)
        {
            levels.push_back(levelDb(n));
        }
        const double before = levelDb(switchAt - kWindow);
        const double after = levels.back();
        double t10 = -1.0;
        double t90 = -1.0;
        double worst50Ms = 0.0;
        for (size_t i = 0; i < levels.size(); ++i)
        {
            const double progress = (levels[i] - before) / (after - before);
            const double ms = 5.0 * static_cast<double>(i);
            t10 = (t10 < 0.0 && progress >= 0.1) ? ms : t10;
            t90 = (t90 < 0.0 && progress >= 0.9) ? ms : t90;
            worst50Ms =
                (i >= 10U) ? std::max(worst50Ms, std::abs(levels[i] - levels[i - 10U])) : worst50Ms;
        }
        bkLine(
            std::format("  tone {:.2f} FS, r 0.3 (normaliser adapted) -> r 0: level {:+.2f} -> "
                        "{:+.2f} dB (swing {:+.2f}); 10%..90% of it between {:.0f} and {:.0f} "
                        "ms; worst change in any 50 ms {:.2f} dB",
                        amplitude,
                        before,
                        after,
                        after - before,
                        t10,
                        t90,
                        worst50Ms));
    }

    auto measureIntensityZeroSwing() -> void
    {
        bkSwing(0.5);  // loud: the normaliser cuts
        bkSwing(0.02); // quiet: the normaliser boosts (to its +12 dB clamp)
    }

    // ---------------------------------------------------------------------------------------------
    // M15 rt-vs-readback — the settled RT module against the designer's read-back where numerics
    // are hardest: the lowest bands at 192 / 768 kHz (g ≈ 3e-4 / 8e-5) and the top band near
    // Nyquist at 44.1 kHz, on a smooth and a jagged curve.
    // ---------------------------------------------------------------------------------------------

    // The settled module's gain (dB) at `hz`, by quadrature over a whole number of cycles.
    auto bkSettledGainDb(EQModule& module, double fs, double hz) -> double
    {
        constexpr uint32_t kBlock = 4096U;
        const auto settle = static_cast<uint32_t>(2.0 * fs);
        const auto cycles = std::max(20.0, std::floor(0.5 * hz)); // ≥ 0.5 s of whole cycles
        const auto window = static_cast<uint32_t>(std::llround(cycles * fs / hz));
        TestABLN abl(2U, kBlock);
        double inPhase = 0.0;
        double quadrature = 0.0;
        for (uint32_t start = 0U; start < settle + window; start += kBlock)
        {
            const uint32_t frames = std::min(kBlock, settle + window - start);
            tdFillProbes(abl, {hz}, fs, start, frames);
            module.process(MultichannelView::fromABL(abl.abl(), frames));
            for (uint32_t i = 0U; i < frames; ++i)
            {
                if (start + i >= settle)
                {
                    const double phase =
                        2.0 * std::numbers::pi * hz * static_cast<double>(start + i) / fs;
                    inPhase += abl.channels[0][i] * std::cos(phase);
                    quadrature += abl.channels[0][i] * std::sin(phase);
                }
            }
        }
        const double amplitude = 2.0 * std::hypot(inPhase, quadrature) / window;
        return 20.0 * std::log10(amplitude / kTdProbeAmplitude);
    }

    auto measureRtVsReadback() -> void
    {
        const std::vector<std::pair<std::string, EqCurve>> curves = {
            {"Warm", kEqPresetCurves[kEqPresetWarm]},
            {"alternating", eqAlternatingCurve()},
            {"+12 @ 20 kHz", eqFlatCurveWith(30U, 12.0F)},
        };
        const std::vector<std::pair<double, std::vector<double>>> cases = {
            {44100.0, {20.0, 31.6228, 19952.6, 20500.0, 21500.0}},
            {192000.0, {20.0, 25.1189, 31.6228, 40.0, 19952.6}},
            {768000.0, {20.0, 25.1189, 31.6228, 40.0, 19952.6}},
        };
        for (const auto& [fs, tones] : cases)
        {
            for (const auto& [name, curve] : curves)
            {
                const GraphicEQDesign design = tdDesign(curve, fs);
                double worst = 0.0;
                std::string detail;
                for (const double hz : tones)
                {
                    auto module = std::make_unique<EQModule>();
                    module->initialize(static_cast<uint32_t>(fs), 4096U);
                    module->update(EQTargets::toParams(design, EQTargets::kRampSeconds));
                    const double played = bkSettledGainDb(*module, fs, hz);
                    const double readBack = GraphicEQDesigner::playedDb(design, hz);
                    worst = std::max(worst, std::abs(played - readBack));
                    detail += std::format(" {:.0f} Hz {:+.4f}/{:+.4f}", hz, played, readBack);
                }
                bkLine(std::format("  {:6.0f} Hz {:14s} worst |RT − read-back| {:.5f} dB:{}",
                                   fs,
                                   name,
                                   worst,
                                   detail));
            }
        }
    }

    // ---------------------------------------------------------------------------------------------
    // M11 designer-accuracy
    // ---------------------------------------------------------------------------------------------

    struct BkWorst
    {
        double errorDb = 0.0;
        EqCurve curve{};
    };

    auto bkWorstCentreError(GraphicEQDesigner& designer, const std::vector<EqCurve>& set, double fs)
        -> BkWorst
    {
        BkWorst worst;
        for (const EqCurve& curve : set)
        {
            GraphicEQDesign design{};
            if (!designer.design(curve, fs, design))
            {
                return {std::numeric_limits<double>::infinity(), curve};
            }
            const double error = eqCentreErrorDb(design, curve);
            if (error > worst.errorDb)
            {
                worst = {error, curve};
            }
        }
        return worst;
    }

    auto bkClimbWorstCommand(GraphicEQDesigner& designer, BkWorst start) -> BkWorst
    {
        std::mt19937 rng(42U);
        std::uniform_int_distribution<size_t> band(0U, 30U);
        std::uniform_int_distribution<size_t> level(0U, 4U);
        constexpr std::array<float, 5> kLevels = {-12.0F, -6.0F, 0.0F, 6.0F, 12.0F};
        BkWorst best = start;
        for (int iter = 0; iter < 30000; ++iter)
        {
            EqCurve trial = best.curve;
            trial[band(rng)] = kLevels[level(rng)];
            if (iter % 3 == 0)
            {
                trial[band(rng)] = kLevels[level(rng)];
            }
            GraphicEQDesign design{};
            if (designer.design(trial, kBkFs, design) &&
                eqCentreErrorDb(design, trial) >= best.errorDb)
            {
                best = {eqCentreErrorDb(design, trial), trial};
            }
        }
        return best;
    }

    auto measureDesignerAccuracy() -> void
    {
        auto designer = eqMakeDesigner();
        const std::vector<EqCurve> presets(kEqPresetCurves.begin(), kEqPresetCurves.end());
        const std::vector<EqCurve> hard = eqHardSet();
        std::mt19937 gateSeed(1000U);
        const std::vector<EqCurve> ramo = eqRamoSet(gateSeed);
        for (const double fs : {44000.0, 44100.0, 192000.0, 352800.0, 384000.0, 705600.0, 768000.0})
        {
            bkLine(
                std::format("  {:7.0f} Hz: presets {:.3f}  hard {:.3f}  ramo(seed 1000) {:.3f} dB",
                            fs,
                            bkWorstCentreError(*designer, presets, fs).errorDb,
                            bkWorstCentreError(*designer, hard, fs).errorDb,
                            bkWorstCentreError(*designer, ramo, fs).errorDb));
        }
        double worstFresh = 0.0;
        for (uint32_t seed = 1U; seed <= 8U; ++seed)
        {
            std::mt19937 rng(seed * 7919U);
            const std::vector<EqCurve> set = eqRamoSet(rng);
            for (const double fs : {44100.0, 48000.0, 192000.0})
            {
                worstFresh = std::max(worstFresh, bkWorstCentreError(*designer, set, fs).errorDb);
            }
        }
        bkLine(
            std::format("  Rämö-style, 8 fresh seeds x 1000 commands x {{44.1, 48, 192}} k: "
                        "worst {:.3f} dB (claim 0.44, gate 0.6)",
                        worstFresh));
        const BkWorst climbed =
            bkClimbWorstCommand(*designer, bkWorstCentreError(*designer, hard, kBkFs));
        bkLine(
            std::format("  hill-climb (30000 designs, 48 k): worst centre error {:.3f} dB; "
                        "command:{}",
                        climbed.errorDb,
                        bkCurveText(climbed.curve)));
        for (const double fs : {44100.0, 96000.0, 192000.0})
        {
            GraphicEQDesign design{};
            (void)designer->design(climbed.curve, fs, design);
            bkLine(std::format("    the same command at {:6.0f} Hz: {:.3f} dB",
                               fs,
                               eqCentreErrorDb(design, climbed.curve)));
        }
    }

    // ---------------------------------------------------------------------------------------------
    // M8 predictor-adversarial
    // ---------------------------------------------------------------------------------------------

    struct BkTone
    {
        double hz = 0.0;
        double dbfs = 0.0;
    };

    struct BkProgrammeSpec
    {
        double fs = kBkFs;
        double seconds = 20.0;
        std::vector<BkTone> tones;
        double pinkDb = -40.0;
        double dc = 0.0;
        bool leftOnly = false;
    };

    auto bkProgramme(const BkProgrammeSpec& spec) -> TlProgramme
    {
        const auto frames = static_cast<size_t>(spec.seconds * spec.fs);
        std::mt19937 rng(11U);
        const std::vector<double> pink = tlPinkNoise(frames, rng);
        TlProgramme programme{spec.fs, TlChannels(2U, std::vector<float>(frames))};
        const double pinkGain = std::pow(10.0, spec.pinkDb / 20.0);
        for (size_t n = 0; n < frames; ++n)
        {
            double sample = spec.dc + (pinkGain * pink[n]);
            for (const BkTone& tone : spec.tones)
            {
                sample +=
                    std::pow(10.0, tone.dbfs / 20.0) *
                    std::sin(2.0 * std::numbers::pi * tone.hz * static_cast<double>(n) / spec.fs);
            }
            programme.channels[0][n] = static_cast<float>(sample);
            programme.channels[1][n] = spec.leftOnly ? 0.0F : static_cast<float>(sample);
        }
        return programme;
    }

    // 95 % digital silence: a 0.5 s pink burst every 10 s.
    auto bkSilenceHeavy() -> TlProgramme
    {
        TlProgramme programme = bkProgramme({.seconds = 40.0, .pinkDb = -10.0});
        const auto period = static_cast<size_t>(10.0 * kBkFs);
        const auto burst = static_cast<size_t>(0.5 * kBkFs);
        for (auto& channel : programme.channels)
        {
            for (size_t n = 0; n < channel.size(); ++n)
            {
                channel[n] = ((n % period) >= burst) ? 0.0F : channel[n];
            }
        }
        return programme;
    }

    auto bkPredictorCurves() -> std::vector<TlCurve>
    {
        EqCurve cliff{};
        cliff[17] = 12.0F;
        cliff[18] = -12.0F;
        return {
            {"Warm", kEqPresetCurves[kEqPresetWarm]},
            {"alternating +-12", eqAlternatingCurve()},
            {"alternating, negated", eqNegated(eqAlternatingCurve())},
            {"-12 @ 31.6 Hz", eqFlatCurveWith(2U, -12.0F)},
            {"+12 @ 100 Hz", eqFlatCurveWith(7U, 12.0F)},
            {"cliff +12/-12 1k/1.26k", cliff},
            {"Tone Air +12", eqToneCurve({0, 0, 0, 0, 12})},
            {"+12 @ 20 kHz", eqFlatCurveWith(30U, 12.0F)},
        };
    }

    auto bkBassCutCurves() -> std::vector<TlCurve>
    {
        std::vector<TlCurve> cuts;
        for (const size_t band : {3U, 4U, 5U, 6U, 7U})
        {
            const double hz = GraphicEQ::centreHz(static_cast<int>(band));
            cuts.push_back({std::format("-12 @ {:.0f} Hz", hz), eqFlatCurveWith(band, -12.0F)});
            cuts.push_back({std::format("-6 @ {:.0f} Hz", hz), eqFlatCurveWith(band, -6.0F)});
        }
        cuts.push_back({"Tone Bass -12", eqToneCurve({-12, 0, 0, 0, 0})});
        cuts.push_back({"Warm, negated (bass cut)", eqNegated(kEqPresetCurves[kEqPresetWarm])});
        return cuts;
    }

    auto bkPredictorRow(const std::string& name,
                        const TlProgramme& programme,
                        const std::vector<TlCurve>& curves) -> void
    {
        const TlProfiles profiles = tlProfile(programme, tlStereoWeights());
        if (!profiles.whole)
        {
            bkLine(std::format("  {}: NO PROFILE", name));
            return;
        }
        const TlAccuracy accuracy = tlAccuracy(programme, *profiles.whole, curves);
        bkLine(
            std::format("  {:40s} source {:.2f} LUFS (profile off by {:+.4f} LU); worst |error| "
                        "{:.3f} dB {}",
                        name,
                        accuracy.sourceLufs,
                        accuracy.sourceDeltaLu,
                        accuracy.worstDb,
                        accuracy.failure));
        logInfo(accuracy.table);
    }

    auto measurePredictorAdversarial() -> void
    {
        // The gate's own realistic programmes with BASS CUTS (the gate only boosts the bass).
        const std::vector<TlCurve> cuts = bkBassCutCurves();
        bkPredictorRow("gate 808 (bass cuts)", tlGate808(), cuts);
        bkPredictorRow("gate loud master (bass cuts)", tlGateLoudMaster(), cuts);
        bkPredictorRow("gate orchestral (bass cuts)", tlGateOrchestral(), cuts);
        const std::vector<TlCurve> curves = bkPredictorCurves();
        bkPredictorRow(
            "31.6 Hz sine -12 dBFS + pink -40", bkProgramme({.tones = {{31.6228, -12.0}}}), curves);
        bkPredictorRow(
            "25 Hz sine -12 dBFS + pink -40", bkProgramme({.tones = {{25.0, -12.0}}}), curves);
        bkPredictorRow(
            "1000 Hz sine -12 + pink -40", bkProgramme({.tones = {{1000.0, -12.0}}}), curves);
        bkPredictorRow("1122 Hz sine (cliff slope) + pink -40",
                       bkProgramme({.tones = {{1122.0, -12.0}}}),
                       curves);
        bkPredictorRow("DC 0.3 + 12 Hz rumble + pink -20",
                       bkProgramme({.tones = {{12.0, -10.0}}, .pinkDb = -20.0, .dc = 0.3}),
                       curves);
        bkPredictorRow(
            "left-only pink -20", bkProgramme({.pinkDb = -20.0, .leftOnly = true}), curves);
        bkPredictorRow("95% silence, pink bursts", bkSilenceHeavy(), curves);
        bkPredictorRow("44.1k: 21.5 kHz tone -20 + pink -30",
                       bkProgramme({.fs = 44100.0, .tones = {{21500.0, -20.0}}, .pinkDb = -30.0}),
                       curves);
        bkPredictorRow("44.1k: 21.9 kHz tone -20 + pink -30",
                       bkProgramme({.fs = 44100.0, .tones = {{21900.0, -20.0}}, .pinkDb = -30.0}),
                       curves);
    }

    // ---------------------------------------------------------------------------------------------
    // M9 storm
    // ---------------------------------------------------------------------------------------------

    struct BkStormShared
    {
        std::atomic<bool> stop{false};
        std::atomic<bool> pauseRequested{false};
        std::atomic<bool> paused{false};
        std::atomic<uint32_t> maxFrames{512U};
        std::atomic<uint64_t> allocations{0U};
        std::atomic<uint64_t> nonFinite{0U};
        std::atomic<uint64_t> blocks{0U};
        std::atomic<uint32_t> peakBits{0U};
    };

    // The render thread's loop: 8 ch of noise, the RT-alloc guard armed around process().
    auto bkStormRender(DSPKernel& kernel, BkStormShared& shared) -> void
    {
        TestABLN abl(8U, 1024U);
        std::mt19937 rng(3U);
        std::uniform_real_distribution<float> noise(-0.5F, 0.5F);
        float peak = 0.0F;
        while (!shared.stop.load(std::memory_order_acquire))
        {
            if (shared.pauseRequested.load(std::memory_order_acquire))
            {
                shared.paused.store(true, std::memory_order_release);
                while (shared.pauseRequested.load(std::memory_order_acquire))
                {
                    std::this_thread::yield();
                }
                shared.paused.store(false, std::memory_order_release);
                continue;
            }
            const uint32_t frames =
                std::min(shared.maxFrames.load(std::memory_order_acquire), 512U);
            for (auto& channel : abl.channels)
            {
                std::generate_n(channel.begin(), frames, [&] { return noise(rng); });
            }
            {
                const RtGuardScope guard;
                kernel.process(abl.abl(), frames);
                shared.allocations.fetch_add(RtGuardScope::count(), std::memory_order_relaxed);
            }
            for (const auto& channel : abl.channels)
            {
                for (uint32_t i = 0U; i < frames; ++i)
                {
                    const bool finite = std::isfinite(channel[i]);
                    shared.nonFinite.fetch_add(finite ? 0U : 1U, std::memory_order_relaxed);
                    peak = finite ? std::max(peak, std::abs(channel[i])) : peak;
                }
            }
            shared.blocks.fetch_add(1U, std::memory_order_relaxed);
        }
        shared.peakBits.store(std::bit_cast<uint32_t>(peak));
    }

    // One random intent: an EQ (jagged, preset-edit or random, sometimes Off), an Intensity or a
    // crossfeed.
    auto bkStormIntent(AdaptiveSound::Realizer& realizer, std::mt19937& rng) -> void
    {
        std::uniform_int_distribution<int> pick(0, 99);
        std::uniform_real_distribution<float> level(-12.0F, 12.0F);
        const int r = pick(rng);
        if (r >= 85)
        {
            realizer.setPendingCrossfeed(static_cast<uint32_t>(r % 2), static_cast<uint32_t>(r % 3));
            return;
        }
        if (r >= 60)
        {
            constexpr std::array<float, 5> kIntensities = {0.0F, 0.05F, 0.2F, 1.0F, 0.0F};
            realizer.setPendingIntensity(
                kIntensities[static_cast<size_t>(r) % kIntensities.size()]);
            return;
        }
        EqCurve curve{};
        if (r < 20)
        {
            curve = (r % 2 == 0) ? eqAlternatingCurve() : eqNegated(eqAlternatingCurve());
        }
        else if (r < 40)
        {
            curve = kEqPresetCurves[static_cast<size_t>(r) % kEqPresetCurves.size()];
            curve[static_cast<size_t>(r) % curve.size()] = level(rng);
        }
        else
        {
            std::ranges::generate(curve, [&] { return level(rng); });
        }
        (void)realizer.setPendingEq(
            curve.data(), static_cast<uint32_t>(curve.size()), (r % 7) != 0);
    }

    // A "re-allocation" as the AU contract has it: the render thread paused, then reinitialize.
    auto bkStormReallocate(AdaptiveSound::Realizer& realizer, BkStormShared& shared, uint32_t round)
        -> void
    {
        constexpr std::array<uint32_t, 3> kRates = {44100U, 48000U, 96000U};
        constexpr std::array<uint32_t, 3> kFrames = {256U, 512U, 1024U};
        shared.pauseRequested.store(true, std::memory_order_release);
        while (!shared.paused.load(std::memory_order_acquire))
        {
            std::this_thread::yield();
        }
        const uint32_t frames = kFrames[round % kFrames.size()];
        realizer.reinitializeKernel(kRates[(round / 3U) % kRates.size()], frames);
        shared.maxFrames.store(frames, std::memory_order_release);
        shared.pauseRequested.store(false, std::memory_order_release);
    }

    auto measureStorm() -> void
    {
        auto kernel = std::make_shared<DSPKernel>();
        kernel->initialize(48000U, 512U);
        auto realizer = std::make_shared<AdaptiveSound::Realizer>(kernel, kBkFs);
        realizer->reinitializeKernel(48000U, 512U);
        BkStormShared shared;
        std::thread render([&] { bkStormRender(*kernel, shared); });
        std::mt19937 rng(9U);
        const auto started = std::chrono::steady_clock::now();
        auto lastRealloc = started;
        uint32_t intents = 0U;
        uint32_t reallocations = 0U;
        while (std::chrono::steady_clock::now() - started < std::chrono::seconds(6))
        {
            bkStormIntent(*realizer, rng);
            ++intents;
            std::this_thread::sleep_for(std::chrono::microseconds(200));
            if (std::chrono::steady_clock::now() - lastRealloc > std::chrono::milliseconds(150))
            {
                bkStormReallocate(*realizer, shared, reallocations++);
                lastRealloc = std::chrono::steady_clock::now();
            }
        }
        shared.stop.store(true, std::memory_order_release);
        render.join();
        realizer->shutdown();
        bkLine(std::format("  control: {} intents, {} re-allocations", intents, reallocations));
        bkLine(
            std::format("  render: {} blocks, RT allocations {}, non-finite samples {}, peak |x| "
                        "{:.3f} (input peak 0.5)",
                        shared.blocks.load(),
                        shared.allocations.load(),
                        shared.nonFinite.load(),
                        std::bit_cast<float>(shared.peakBits.load())));
    }

    // ---------------------------------------------------------------------------------------------

    using BkMeasurement = std::pair<const char*, void (*)()>;
    const std::array<BkMeasurement, 15> kBkMeasurements = {
        {
            {"tau-classes", measureTauClasses},
            {"tau-from-published", measureTauFromPublished},
            {"local-swells", measureLocalSwells},
            {"drag-latency", measureDragLatency},
            {"jagged-false-positives", measureJaggedFalsePositives},
            {"calm-pair-search", measureCalmPairSearch},
            {"cpu", measureCpu},
            {"app-safety-clamp-gap", measureAppSafetyClampGap},
            {"normaliser-poison", measureNormaliserPoison},
            {"p0-switch", measureP0Switch},
            {"intensity-zero-swing", measureIntensityZeroSwing},
            {"designer-accuracy", measureDesignerAccuracy},
            {"predictor-adversarial", measurePredictorAdversarial},
            {"storm", measureStorm},
            {"rt-vs-readback", measureRtVsReadback},
        },
    };
} // namespace
