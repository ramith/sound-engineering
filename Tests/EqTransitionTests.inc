// EqTransitionTests.inc
//
// Sprint EQ, EQ1b — what a CHANGE of EQ curve sounds like in the real-time module (engine-plan
// §3; amendment 1). #included into Tests/DSPKernelNullTest.cpp after EqDesignerTests.inc (it
// reuses that file's curves). Pure DSP, no env/tmp: parallel-safe, except EQ_Cpu_7_1_192k
// (serial, so the pool cannot skew its clock).
//
// THE METRIC is the research's time-domain overshoot (research/eq-geq-poc/author/trans_td.py):
// sine probes through the production EQModule while it glides from curve A to curve B. Each
// probe runs as a cos/sin PAIR on two channels, so |y_cos + j·y_sin| is the exact envelope of the
// (time-varying, linear) filter's response to e^{jωn} — no Hilbert transform needed. Per probe:
//   local = 20·log10(max envelope after the switch / max(steady A, steady B)),
//   peak  = 20·log10(max over probes of the post-switch maximum / max over probes of the louder
//           steady endpoint) — the transition is never louder than the louder endpoint;
//   and how LONG a probe spends above its louder endpoint: > +1 dB and > +3 dB (ms, the longest
//   total over the probes; amendment 15 bounds the swell's duration as well as its height).
// The glide times are the Realizer's τ rule (EQTargets::rampsFor) on the designs of A and B: one
// τ per band (amendment 15).
// There is no output gain yet (EQ1c's loudness-neutral gain): both endpoints play at their own
// level, as the module plays them today.
//
// Tests:
//   EQ_Transitions_Realistic   — the 42 ordered pairs of {Off, 6 presets}, Off → Tone, Off → all +12
//                                and a 120 Hz drag of Warm's 125 Hz band to +12: local ≤ +0.75 dB,
//                                peak ≤ +0.5 dB (engine-plan §3.2)
//   EQ_Transitions_Adversarial — the breaker's TD-searched jagged pairs (fixtures v3_worst_tau40,
//                                v3_worst_tau10) at the rule's τ: peak ≤ +1.0 dB (amendment 1);
//                                the earlier pinned pairs (worst_pair, adv_pair_S1/S2, the
//                                alternating flip): peak ≤ +2.0 dB; every pair, both directions,
//                                spends ≤ 60 ms above +3 dB (amendment 15: adv_pair_S2 spent
//                                211 ms there under the one-τ rule); local and > +1 dB logged
//   EQ_Cpu_7_1_192k            — % of one core for 8 channels at 192 kHz, settled and gliding

namespace
{
    constexpr double kTdProbeAmplitude = 0.25;
    constexpr uint32_t kTdBlockFrames = 512U;
    constexpr size_t kTdProbesPerRun = EQModule::kChannelPairs; // one cos/sin pair per probe

    // The research's 48 log-spaced probes, 25 Hz … 18 kHz.
    auto tdProbes(size_t stride) -> std::vector<double>
    {
        std::vector<double> probes;
        constexpr size_t kCount = 48U;
        for (size_t i = 0; i < kCount; i += stride)
        {
            const double t = static_cast<double>(i) / static_cast<double>(kCount - 1U);
            probes.push_back(25.0 * std::pow(18000.0 / 25.0, t));
        }
        return probes;
    }

    // One target change: at `frame`, the module is handed `params`.
    struct TdEvent
    {
        uint32_t frame = 0U;
        EQParams params{};
    };

    // The design of `curve` at `fs` (the production designer).
    auto tdDesign(const EqCurve& curve, double fs) -> GraphicEQDesign
    {
        auto designer = eqMakeDesigner();
        GraphicEQDesign design{};
        (void)designer->design(curve, fs, design);
        return design;
    }

    // A → B as the Realizer would publish them: A first (snapped), B at `switchFrame` gliding by
    // the τ rule.
    auto tdPairEvents(const EqCurve& from, const EqCurve& to, double fs, uint32_t switchFrame)
        -> std::vector<TdEvent>
    {
        const GraphicEQDesign a = tdDesign(from, fs);
        const GraphicEQDesign b = tdDesign(to, fs);
        return {
            TdEvent{0U, EQTargets::toParams(a, EQTargets::kRampSeconds)},
            TdEvent{switchFrame, EQTargets::toParams(b, EQTargets::rampsFor(a, b))},
        };
    }

    // The slowest and the fastest band τ of a published target (ms), for the reports.
    auto tdTauRangeMs(const EQParams& params) -> std::pair<double, double>
    {
        const auto [fastest, slowest] = std::ranges::minmax(params.bandRampSeconds);
        return {1000.0 * static_cast<double>(fastest), 1000.0 * static_cast<double>(slowest)};
    }

    struct TdProbeResult
    {
        double steadyA = 0.0;
        double steadyB = 0.0;
        double maxAfter = 0.0;
        std::vector<float> after; // the envelope from the switch to the end of steady B
    };

    // One run's analysis windows (frame indices; see tdRun) and per-probe accumulators.
    struct TdWindows
    {
        uint32_t aStart = 0U;
        uint32_t aEnd = 0U;
        uint32_t bStart = 0U;
        uint32_t bEnd = 0U;
        uint32_t switchFrame = 0U;
    };

    struct TdAccumulator
    {
        double sumA = 0.0;
        double sumB = 0.0;
        double maxAfter = 0.0;
        std::vector<float> after;
    };

    // The quadrature probes for frames [start, start + frames): probe p's cos on channel 2p, its
    // sin on 2p + 1, so the output envelope is exact without any smoothing.
    void tdFillProbes(TestABLN& abl,
                      const std::vector<double>& probes,
                      double fs,
                      uint32_t start,
                      uint32_t frames)
    {
        for (size_t p = 0; p < probes.size(); ++p)
        {
            const double omega = 2.0 * std::numbers::pi * probes[p] / fs;
            for (uint32_t i = 0U; i < frames; ++i)
            {
                const double phase = omega * static_cast<double>(start + i);
                abl.channels[2U * p][i] = static_cast<float>(kTdProbeAmplitude * std::cos(phase));
                abl.channels[(2U * p) + 1U][i] =
                    static_cast<float>(kTdProbeAmplitude * std::sin(phase));
            }
        }
    }

    // Fold one processed block's envelopes into the steady sums and the post-switch maxima.
    void tdAccumulate(const TestABLN& abl,
                      const TdWindows& windows,
                      uint32_t start,
                      uint32_t frames,
                      std::vector<TdAccumulator>& accumulators)
    {
        for (size_t p = 0; p < accumulators.size(); ++p)
        {
            TdAccumulator& acc = accumulators[p];
            for (uint32_t i = 0U; i < frames; ++i)
            {
                const uint32_t n = start + i;
                const double env =
                    std::hypot(abl.channels[2U * p][i], abl.channels[(2U * p) + 1U][i]) /
                    kTdProbeAmplitude;
                acc.sumA += (n >= windows.aStart && n < windows.aEnd) ? env : 0.0;
                acc.sumB += (n >= windows.bStart && n < windows.bEnd) ? env : 0.0;
                if (n >= windows.switchFrame && n < windows.bEnd)
                {
                    acc.maxAfter = std::max(acc.maxAfter, env);
                    acc.after.push_back(static_cast<float>(env));
                }
            }
        }
    }

    // Run up to four probes through a fresh EQModule over `events`. Steady A is the mean envelope
    // over [switch − 80 ms, switch − 10 ms]; steady B over the last [−100 ms, −30 ms]; the
    // post-switch maximum over [switch, end − 30 ms].
    auto tdRun(const std::vector<TdEvent>& events,
               const std::vector<double>& probes,
               double fs,
               uint32_t switchFrame,
               uint32_t totalFrames) -> std::vector<TdProbeResult>
    {
        auto module = std::make_unique<EQModule>();
        module->initialize(static_cast<uint32_t>(fs), kTdBlockFrames);
        const auto channels = static_cast<uint32_t>(2U * probes.size());
        TestABLN abl(channels, kTdBlockFrames);
        const auto ms = [fs](double millis) { return static_cast<uint32_t>(millis * fs / 1000.0); };
        const TdWindows windows{
            .aStart = switchFrame - ms(80.0),
            .aEnd = switchFrame - ms(10.0),
            .bStart = totalFrames - ms(100.0),
            .bEnd = totalFrames - ms(30.0),
            .switchFrame = switchFrame,
        };
        std::vector<TdAccumulator> accumulators(probes.size());
        size_t nextEvent = 0U;
        for (uint32_t start = 0U; start < totalFrames; start += kTdBlockFrames)
        {
            const uint32_t frames = std::min(kTdBlockFrames, totalFrames - start);
            for (; nextEvent < events.size() && events[nextEvent].frame <= start; ++nextEvent)
            {
                module->update(events[nextEvent].params);
            }
            tdFillProbes(abl, probes, fs, start, frames);
            module->process(MultichannelView::fromABL(abl.abl(), frames));
            tdAccumulate(abl, windows, start, frames, accumulators);
        }
        std::vector<TdProbeResult> results(probes.size());
        for (size_t p = 0; p < probes.size(); ++p)
        {
            results[p].steadyA =
                accumulators[p].sumA / static_cast<double>(windows.aEnd - windows.aStart);
            results[p].steadyB =
                accumulators[p].sumB / static_cast<double>(windows.bEnd - windows.bStart);
            results[p].maxAfter = accumulators[p].maxAfter;
            results[p].after = std::move(accumulators[p].after);
        }
        return results;
    }

    struct TdOvershoot
    {
        double localDb = -std::numeric_limits<double>::infinity();
        double localProbeHz = 0.0;
        double peakDb = 0.0;
        double msAbove1Db = 0.0; // the longest any probe spends > +1 dB over its louder endpoint
        double msAbove3Db = 0.0; // … > +3 dB
    };

    // How long (ms) the envelope after the switch spends above `steady` raised by `marginDb`.
    auto tdMsAbove(const std::vector<float>& after, double steady, double marginDb, double fs)
        -> double
    {
        const double threshold = steady * std::pow(10.0, marginDb / 20.0);
        const auto count = std::ranges::count_if(
            after, [threshold](float env) { return static_cast<double>(env) > threshold; });
        return 1000.0 * static_cast<double>(count) / fs;
    }

    // The overshoot of one transition over every probe (four per run).
    auto tdOvershoot(const std::vector<TdEvent>& events,
                     const std::vector<double>& probes,
                     double fs,
                     uint32_t switchFrame,
                     uint32_t totalFrames) -> TdOvershoot
    {
        TdOvershoot result;
        double loudestAfter = 0.0;
        double loudestSteady = 0.0;
        for (size_t first = 0; first < probes.size(); first += kTdProbesPerRun)
        {
            const size_t count = std::min(kTdProbesPerRun, probes.size() - first);
            const std::vector<double> run(probes.begin() + static_cast<std::ptrdiff_t>(first),
                                          probes.begin() +
                                              static_cast<std::ptrdiff_t>(first + count));
            const std::vector<TdProbeResult> stats =
                tdRun(events, run, fs, switchFrame, totalFrames);
            for (size_t p = 0; p < count; ++p)
            {
                const double steady = std::max(stats[p].steadyA, stats[p].steadyB);
                const double local = 20.0 * std::log10(stats[p].maxAfter / steady);
                if (local > result.localDb)
                {
                    result.localDb = local;
                    result.localProbeHz = run[p];
                }
                loudestAfter = std::max(loudestAfter, stats[p].maxAfter);
                loudestSteady = std::max(loudestSteady, steady);
                result.msAbove1Db =
                    std::max(result.msAbove1Db, tdMsAbove(stats[p].after, steady, 1.0, fs));
                result.msAbove3Db =
                    std::max(result.msAbove3Db, tdMsAbove(stats[p].after, steady, 3.0, fs));
            }
        }
        result.peakDb = 20.0 * std::log10(loudestAfter / loudestSteady);
        return result;
    }

    // The breaker's TD-searched pairs (amendment 1), pinned from research/eq-geq-poc/fixtures/.
    constexpr std::array<EqCurve, 2> kTdWorstTau40 = {
        {
            {
                0.0F,   12.0F,  0.0F,   12.0F,  -12.0F, -12.0F, -12.0F, -12.0F, 0.0F, 12.0F, 0.0F,
                12.0F,  -12.0F, 0.0F,   12.0F,  0.0F,   12.0F,  0.0F,   -12.0F, 0.0F, 12.0F, -12.0F,
                -12.0F, 0.0F,   -12.0F, -12.0F, 12.0F,  12.0F,  12.0F,  0.0F,   0.0F,
            },
            {
                -12.0F, 0.0F,   -12.0F, 12.0F, 12.0F, 0.0F,   0.0F,   12.0F, 12.0F,  -12.0F, -12.0F,
                12.0F,  0.0F,   0.0F,   12.0F, 0.0F,  0.0F,   12.0F,  12.0F, 12.0F,  -12.0F, -12.0F,
                0.0F,   -12.0F, 12.0F,  6.0F,  12.0F, -12.0F, -12.0F, 0.0F,  -12.0F,
            },
        },
    };
    constexpr std::array<EqCurve, 2> kTdWorstTau10 = {
        {
            {
                -12.0F, -12.0F, -6.0F, 0.0F,  0.0F,  12.0F, -6.0F,  12.0F,  -12.0F, 12.0F, 6.0F,
                12.0F,  -6.0F,  6.0F,  12.0F, -6.0F, 0.0F,  12.0F,  -12.0F, 6.0F,   6.0F,  -12.0F,
                -12.0F, 12.0F,  0.0F,  0.0F,  0.0F,  -6.0F, -12.0F, -6.0F,  12.0F,
            },
            {
                -12.0F, -12.0F, 0.0F, 0.0F,  0.0F,  12.0F, -12.0F, 12.0F,  -6.0F, 12.0F, 6.0F,
                12.0F,  -6.0F,  6.0F, 12.0F, -6.0F, 0.0F,  12.0F,  -12.0F, 6.0F,  6.0F,  -12.0F,
                -12.0F, 12.0F,  0.0F, 0.0F,  0.0F,  -6.0F, -12.0F, -6.0F,  12.0F,
            },
        },
    };
    // The earlier pinned pairs (engine-plan §9): the breaker's M1 pair and the plan author's two
    // adversarial pairs (research/eq-geq-poc/fixtures/worst_pair.npy, author/results/adv_pair_*).
    constexpr std::array<EqCurve, 2> kTdWorstPair = {
        {
            {
                -6.0F, -12.0F, 0.0F,   -12.0F, 12.0F,  6.0F,   12.0F, -12.0F, 6.0F,  -12.0F, -6.0F,
                12.0F, -12.0F, 12.0F,  12.0F,  -12.0F, 12.0F,  12.0F, 0.0F,   12.0F, 12.0F,  -6.0F,
                12.0F, 12.0F,  -12.0F, 12.0F,  12.0F,  -12.0F, 12.0F, 6.0F,   0.0F,
            },
            {
                -12.0F, -6.0F, -6.0F, 6.0F,   12.0F, 0.0F,  6.0F,   6.0F, 6.0F,   6.0F,  -12.0F,
                12.0F,  6.0F,  12.0F, -12.0F, 12.0F, 12.0F, 12.0F,  6.0F, -12.0F, 12.0F, 12.0F,
                -12.0F, 12.0F, 0.0F,  -12.0F, 12.0F, 6.0F,  -12.0F, 0.0F, -12.0F,
            },
        },
    };
    constexpr std::array<EqCurve, 2> kTdAdvPairS1 = {
        {
            {
                6.0F,   6.0F,   0.0F,   -12.0F, 0.0F,   0.0F,   -12.0F, 12.0F,
                6.0F,   -12.0F, 12.0F,  12.0F,  -12.0F, 12.0F,  12.0F,  -12.0F,
                12.0F,  12.0F,  -12.0F, 12.0F,  12.0F,  -12.0F, 12.0F,  12.0F,
                -12.0F, 12.0F,  12.0F,  -12.0F, 6.0F,   -12.0F, 6.0F,
            },
            {
                -6.0F,  0.0F,  -6.0F, 0.0F,   12.0F, 0.0F,  6.0F,   12.0F, -12.0F, 6.0F,  -12.0F,
                12.0F,  6.0F,  12.0F, -12.0F, 12.0F, 12.0F, 12.0F,  12.0F, -12.0F, 12.0F, 12.0F,
                -12.0F, 12.0F, 0.0F,  -12.0F, 12.0F, 12.0F, -12.0F, 12.0F, 6.0F,
            },
        },
    };
    constexpr std::array<EqCurve, 2> kTdAdvPairS2 = {
        {
            {
                6.0F,   -12.0F, 12.0F,  6.0F,   0.0F,   0.0F,   -12.0F, 0.0F,
                12.0F,  0.0F,   -12.0F, -6.0F,  -12.0F, 12.0F,  12.0F,  -12.0F,
                12.0F,  12.0F,  -12.0F, -12.0F, 12.0F,  -12.0F, -12.0F, 12.0F,
                -12.0F, 6.0F,   12.0F,  -12.0F, 6.0F,   6.0F,   -12.0F,
            },
            {
                -12.0F, -12.0F, -6.0F, 12.0F,  12.0F, 6.0F,  6.0F,   -6.0F, 12.0F,  -12.0F, 6.0F,
                12.0F,  0.0F,   12.0F, -12.0F, 12.0F, 12.0F, -12.0F, 12.0F, -12.0F, -12.0F, 12.0F,
                -12.0F, -12.0F, 6.0F,  -12.0F, 12.0F, 6.0F,  -12.0F, 0.0F,  -12.0F,
            },
        },
    };

    // The EQ's CPU (EQ_Cpu_*): % of one core for 8 channels at `fs`, settled on Warm and then
    // gliding to Vocal, over `seconds` of audio each. A fresh noise block every time — copied (a
    // 16 KB copy, inside the timing, so the figure errs high), not re-generated (the RNG stays out
    // of it). Processing the same buffer in place would compound the curve block after block until
    // the samples overflow, and time arithmetic on infinities rather than music.
    struct TdCpu
    {
        double settled = 0.0;
        double gliding = 0.0;
    };

    auto tdEqCpuPercent(uint32_t fs, uint32_t seconds) -> TdCpu
    {
        constexpr uint32_t kChannels = 8U;
        auto module = std::make_unique<EQModule>();
        module->initialize(fs, kTdBlockFrames);
        TestABLN abl(kChannels, kTdBlockFrames);
        std::vector<std::vector<float>> source(kChannels, std::vector<float>(kTdBlockFrames));
        std::mt19937 rng(7U);
        std::uniform_real_distribution<float> noise(-0.25F, 0.25F);
        for (auto& channel : source)
        {
            for (float& sample : channel)
            {
                sample = noise(rng);
            }
        }
        const auto fill = [&]
        {
            for (uint32_t ch = 0U; ch < kChannels; ++ch)
            {
                std::ranges::copy(source[ch], abl.channels[ch].begin());
            }
        };
        const EQParams warmParams = makeEqParams(kEqPresetCurves[kEqPresetWarm], fs);
        // A glide slow enough (τ 0.64 s) to keep every band's coefficients moving for the run.
        constexpr float kGlideSeconds = 0.64F;
        const EQParams vocalParams = makeEqParams(kEqPresetCurves[4], fs, kGlideSeconds);
        const auto run = [&](const EQParams& target)
        {
            module->update(target);
            const auto start = std::chrono::steady_clock::now();
            for (uint32_t done = 0U; done < fs * seconds; done += kTdBlockFrames)
            {
                fill();
                module->process(MultichannelView::fromABL(abl.abl(), kTdBlockFrames));
            }
            const auto elapsed = std::chrono::steady_clock::now() - start;
            return 100.0 * std::chrono::duration<double>(elapsed).count() /
                   static_cast<double>(seconds);
        };
        (void)run(warmParams); // snap to Warm, then settle
        TdCpu cpu;
        cpu.settled = run(warmParams);
        cpu.gliding = run(vocalParams);
        return cpu;
    }

    // The EQ's CPU budget at `fs` (% of one core, 8 channels; engine-plan §7, amendment 18): 5 % at
    // the pipeline's worst supported format, 192 kHz — and above it, where the EQ still plays (its
    // designer goes to 768 kHz) but the pipeline's supported range ends, the same work per sample:
    // 5 % × fs / 192 kHz. The bound applies to an optimised, uninstrumented build; -O0 and the
    // sanitizers get only a catastrophic-regression tripwire, scaled the same way.
#if defined(__OPTIMIZE__) && !__has_feature(address_sanitizer) && !__has_feature(thread_sanitizer)
    constexpr const char* kTdCpuBuild = "optimised";
    auto tdEqCpuBudgetPercent(uint32_t fs) -> double
    {
        constexpr double kBudgetAt192kPercent = 5.0;
        return kBudgetAt192kPercent *
               std::max(1.0,
                        static_cast<double>(fs) / static_cast<double>(kMaxSupportedSampleRate));
    }
#else
    constexpr const char* kTdCpuBuild = "unoptimised";
    // -O0 and the sanitizers run 10–100× slower, so they get no budget, only a tripwire for a
    // catastrophic regression. It scales per rate like the real budget (the same work per
    // sample): a fixed 1000 % was crossed by TSan at 768 kHz under ordinary machine load.
    auto tdEqCpuBudgetPercent(uint32_t fs) -> double
    {
        constexpr double kTripwireAt192kPercent = 1000.0;
        return kTripwireAt192kPercent *
               std::max(1.0,
                        static_cast<double>(fs) / static_cast<double>(kMaxSupportedSampleRate));
    }
#endif

    // The research's realistic drag (trans_td3.py): Warm's 125 Hz band (index 8) raised to +12 in
    // 0.5 dB steps at 120 Hz, the neighbours following by the stroke-start rule (±1: 75 %,
    // ±2: 25 %).
    auto tdWarmDragEvents(double fs, uint32_t switchFrame) -> std::vector<TdEvent>
    {
        const EqCurve start = kEqPresetCurves[kEqPresetWarm];
        constexpr size_t kBand = 8U;
        std::vector<TdEvent> events;
        GraphicEQDesign previous = tdDesign(start, fs);
        events.push_back({0U, EQTargets::toParams(previous, EQTargets::kRampSeconds)});
        const auto stepFrames = static_cast<uint32_t>(fs / 120.0);
        uint32_t frame = switchFrame;
        constexpr float kStepDb = 0.5F;
        const auto steps = static_cast<int>((12.01F - start[kBand]) / kStepDb);
        for (int step = 1; step <= steps; ++step)
        {
            const float value = start[kBand] + (kStepDb * static_cast<float>(step));
            EqCurve curve = start;
            curve[kBand] = value;
            for (const auto& [offset, weight] : {std::pair{1, 0.75F}, std::pair{2, 0.25F}})
            {
                for (const int sign : {-1, 1})
                {
                    const int neighbour = static_cast<int>(kBand) + (offset * sign);
                    const auto band = static_cast<size_t>(neighbour);
                    curve[band] =
                        std::clamp(start[band] + ((value - start[band]) * weight), -12.0F, 12.0F);
                }
            }
            const GraphicEQDesign next = tdDesign(curve, fs);
            events.push_back(
                {frame, EQTargets::toParams(next, EQTargets::rampsFor(previous, next))});
            previous = next;
            frame += stepFrames;
        }
        return events;
    }
} // namespace

// ---------------------------------------------------------------------------
// EQ_Transitions_Realistic — every-day curve changes never swell (engine-plan §3.2).
// ---------------------------------------------------------------------------
static auto testEqTransitionsRealistic() -> void
{
    static const char* const kName = "EQ_Transitions_Realistic";
    constexpr double kFs = 48000.0;
    constexpr double kLocalBoundDb = 0.75;
    constexpr double kPeakBoundDb = 0.5;
    const auto switchFrame = static_cast<uint32_t>(0.5 * kFs);
    const auto totalFrames = static_cast<uint32_t>(1.1 * kFs);
    const std::vector<double> probes = tdProbes(2U); // 24 probes

    std::vector<std::pair<std::string, std::vector<TdEvent>>> transitions;
    std::vector<std::pair<std::string, EqCurve>> curves = {{"Off", EqCurve{}}};
    constexpr std::array<const char*, 6> kPresetNames = {
        "Presence",
        "Clarity",
        "Warm",
        "Bass & Treble",
        "Vocal",
        "Bass Boost",
    };
    for (size_t i = 0; i < kEqPresetCurves.size(); ++i)
    {
        curves.emplace_back(kPresetNames[i], kEqPresetCurves[i]);
    }
    for (const auto& [fromName, from] : curves)
    {
        for (const auto& [toName, to] : curves)
        {
            if (fromName != toName)
            {
                transitions.emplace_back(std::format("{} → {}", fromName, toName),
                                         tdPairEvents(from, to, kFs, switchFrame));
            }
        }
    }
    EqCurve allUp{};
    allUp.fill(12.0F);
    transitions.emplace_back(
        "Off → Tone B+6 Bo-3 P+4 A+6",
        tdPairEvents(EqCurve{}, eqToneCurve({6.0, -3.0, 0.0, 4.0, 6.0}), kFs, switchFrame));
    transitions.emplace_back("Off → all +12", tdPairEvents(EqCurve{}, allUp, kFs, switchFrame));
    transitions.emplace_back("drag Warm 125 Hz → +12", tdWarmDragEvents(kFs, switchFrame));

    double worstLocal = -std::numeric_limits<double>::infinity();
    double worstPeak = -std::numeric_limits<double>::infinity();
    double longestAbove1Db = 0.0;
    std::string worstLocalName;
    for (const auto& [name, events] : transitions)
    {
        const TdOvershoot result = tdOvershoot(events, probes, kFs, switchFrame, totalFrames);
        if (result.localDb > worstLocal)
        {
            worstLocal = result.localDb;
            worstLocalName = std::format("{} @ {:.0f} Hz", name, result.localProbeHz);
        }
        worstPeak = std::max(worstPeak, result.peakDb);
        longestAbove1Db = std::max(longestAbove1Db, result.msAbove1Db);
        if (!(result.localDb <= kLocalBoundDb) || !(result.peakDb <= kPeakBoundDb))
        {
            logFail(kName,
                    std::format("{}: local {:+.3f} dB @ {:.0f} Hz (≤ {}), peak {:+.3f} dB (≤ {})",
                                name,
                                result.localDb,
                                result.localProbeHz,
                                kLocalBoundDb,
                                result.peakDb,
                                kPeakBoundDb));
            return;
        }
    }
    logInfo(
        std::format("[info] {}: {} transitions, worst local {:+.3f} dB ({}), worst peak "
                    "{:+.3f} dB, longest above +1 dB {:.1f} ms\n",
                    kName,
                    transitions.size(),
                    worstLocal,
                    worstLocalName,
                    worstPeak,
                    longestAbove1Db));
    logPass(kName);
}

// ---------------------------------------------------------------------------
// EQ_Transitions_Adversarial — jagged ↔ jagged switches stay within +1 dB (amendment 1).
// ---------------------------------------------------------------------------
static auto testEqTransitionsAdversarial() -> void
{
    static const char* const kName = "EQ_Transitions_Adversarial";
    constexpr double kFs = 48000.0;
    const auto switchFrame = static_cast<uint32_t>(1.5 * kFs);
    const auto totalFrames = static_cast<uint32_t>(3.8 * kFs); // 2.3 s ≈ 14 τ at 160 ms
    struct Case
    {
        const char* name;
        const std::array<EqCurve, 2>* pair;
        double peakBoundDb;
        size_t probeStride;
    };
    const EqCurve alternating = eqAlternatingCurve();
    const std::array<EqCurve, 2> altFlip = {alternating, eqNegated(alternating)};
    const std::array<Case, 6> cases = {
        {
            {"v3_worst_tau40", &kTdWorstTau40, 1.0, 1U},
            {"v3_worst_tau10", &kTdWorstTau10, 1.0, 1U},
            {"worst_pair", &kTdWorstPair, 2.0, 2U},
            {"adv_pair_S1", &kTdAdvPairS1, 2.0, 2U},
            {"adv_pair_S2", &kTdAdvPairS2, 2.0, 2U},
            {"alternating flip", &altFlip, 2.0, 2U},
        },
    };
    constexpr double kAbove3DbBoundMs = 60.0;
    std::string report = std::format(
        "[info] {}: TD overshoot local / peak (dB) and the time "
        "above +1 / +3 dB (ms), τ by the rule\n",
        kName);
    for (const Case& c : cases)
    {
        for (const bool reversed : {false, true})
        {
            const auto& [first, second] = *c.pair;
            const EqCurve& from = reversed ? second : first;
            const EqCurve& to = reversed ? first : second;
            const std::vector<TdEvent> events = tdPairEvents(from, to, kFs, switchFrame);
            const auto [fastestMs, slowestMs] = tdTauRangeMs(events.back().params);
            const TdOvershoot result =
                tdOvershoot(events, tdProbes(c.probeStride), kFs, switchFrame, totalFrames);
            const std::string name = std::format("{}{}", c.name, reversed ? " (back)" : "");
            report += std::format(
                "[info]   {:25s} τ {:3.0f}–{:3.0f} ms: local {:+6.2f} @ {:5.0f} "
                "Hz / peak {:+5.2f} (≤ {}) / > +1 dB {:5.1f}, > +3 dB {:5.1f} "
                "(≤ {})\n",
                name,
                fastestMs,
                slowestMs,
                result.localDb,
                result.localProbeHz,
                result.peakDb,
                c.peakBoundDb,
                result.msAbove1Db,
                result.msAbove3Db,
                kAbove3DbBoundMs);
            if (!(result.peakDb <= c.peakBoundDb) || !(result.msAbove3Db <= kAbove3DbBoundMs))
            {
                logInfo(report);
                logFail(kName,
                        std::format("{}: peak {:+.3f} dB (≤ {}), {:.1f} ms above +3 dB (≤ {})",
                                    name,
                                    result.peakDb,
                                    c.peakBoundDb,
                                    result.msAbove3Db,
                                    kAbove3DbBoundMs));
                return;
            }
        }
    }
    logInfo(report);
    logPass(kName);
}

// ---------------------------------------------------------------------------
// EQ_Cpu_7_1_192k — the EQ's real-time cost at the worst supported format (engine-plan §7: the
// SOTA review measured 2.66 % gliding / 2.00 % settled of one core at 192 kHz × 8). The bound
// (≤ 5 %) applies to an optimised, uninstrumented build; -O0 and the sanitizers only report.
// Serial-only: the pool would skew the clock.
// ---------------------------------------------------------------------------
static auto testEqCpu71At192k() -> void
{
    static const char* const kName = "EQ_Cpu_7_1_192k";
    constexpr uint32_t kFs = 192000U;
    constexpr uint32_t kSeconds = 2U;
    const double budget = tdEqCpuBudgetPercent(kFs);
    const TdCpu cpu = tdEqCpuPercent(kFs, kSeconds);
    logInfo(std::format(
        "[info] {} ({} build): 8 ch @ 192 kHz — settled {:.2f} %, gliding {:.2f} % of one "
        "core (budget {} %)\n",
        kName,
        kTdCpuBuild,
        cpu.settled,
        cpu.gliding,
        budget));
    if (!(std::max(cpu.settled, cpu.gliding) <= budget))
    {
        logFail(kName,
                std::format("{:.2f} % of one core exceeds {} %",
                            std::max(cpu.settled, cpu.gliding),
                            budget));
        return;
    }
    logPass(kName);
}
