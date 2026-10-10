// EqDesignerTests.inc
//
// Sprint EQ, EQ1a — the pure 31-band graphic-EQ designer: GraphicEQDesigner
// (EQ/GraphicEQDesigner.h), its shared bell function (EQ/GraphicEQBands.h) and the asEqDesign
// C-ABI (EQDesignBridge.h). #included into Tests/DSPKernelNullTest.cpp after TestSupport.h.
// Pure DSP, no env/tmp: parallel-safe, except Designer_Timing (serial, so the pool cannot skew its
// clock).
//
// THE ORACLE is the Python reference research/eq-geq-poc/author/{geq.py, geq2.py}: design =
// solve_passes(t, fs, 5)[-1]. The port was cross-checked against it offline on 1345 curves (the
// presets, 100 Tone, 200 smooth, the 1000-command Rämö set, the 35 hard patterns and the guard
// cases) at all six rates: max |Δ solved gain| 1.3e-7 dB, identical centre errors to 6 digits.
// This gate pins six oracle gain vectors, the breaker's adversarial commands
// (research/eq-geq-poc/fixtures/worst_cmd_*.npy) and the accuracy bounds of engine-plan §9 / the
// EQ1a brief, at 44.1 / 48 / 88.2 / 96 / 176.4 / 192 kHz. The value in (…) is the oracle's.
//
// Tests:
//   EQ_Bands_MatchKit           — the designer's centres == EQEditKit's EQBands.centreHz, bit
//                                 for bit (the kit's BANDS-04 pins the same table)
//   EQ_Designer_MatchesOracle   — solved gains == pinned oracle gains (≤ 1e-6 dB), one curve
//                                 per rate
//   EQ_ACGE_Presets_Tone_Smooth — presets ≤ 0.084 dB (0.0282 re-voiced; 0.0837 before);
//                                 100 Tone ≤ 0.2 (0.081);
//                                 200 smooth ≤ 0.3 (0.157 on the oracle's draw; this seeded draw
//                                 holds a near-cliff at the top octave that plays 0.256 at 44.1 kHz
//                                 — the oracle gives the same 0.2564 on that curve)
//   EQ_ACGE_Ramo1000            — 500 binary {−12, 0, +12} + 500 integer commands ≤ 0.6 (0.440)
//   EQ_ACGE_Hard                — alternating, every-third ×6, cliffs ×16, singles, edge, ±all
//                                 and the 4 pinned breaker commands ≤ 0.6 (0.323)
//   EQ_ACGE_SingleBand          — every band at ±6 / ±12 ≤ 0.25 / 0.3 (0.15)
//   EQ_SvfBell_Exact            — the shared bell: exact centre gain, half-dB points exactly
//                                 0.40·ω apart, a cut = the inverse of the boost, SVF form ≡ the
//                                 RBJ biquad, 0 dB ≡ identity
//   EQ_Ultrasonic_Property      — named curves: max above 20.2 kHz ≤ in-band peak + 1.5 dB (1.42)
//   EQ_Readback_MatchesIndependentEval — playedDb == an independent complex-form RBJ-biquad
//                                 product (≤ 1e-6 dB) and == a time-domain SVF cascade measured by
//                                 correlation (≤ 0.01 dB); the C-ABI returns the C++ values
//   EQ_Design_FlatFinite        — flat → every gain and m1 exactly 0, played exactly 0 dB;
//                                 near-flat commands stay finite (the 1e-3 dB divide guard)
//   EQ_Design_Rejects_NonFinite — non-finite points/rates, out-of-domain rates, NULLs, wrong
//                                 counts, bad response frequencies → false, nothing written;
//                                 finite points beyond ±12 clamp to ±12
//   Designer_TwoThreads         — two owner-local designers on two threads, with rate churn ==
//                                 the serial results, bit-exact (the race check runs under tsan)
//   Designer_Timing             — µs per design and per read-back, reported; bounded

namespace
{
    using EqCurve = std::array<float, static_cast<size_t>(GraphicEQ::kBandCount)>;
    constexpr auto kDesignBands = static_cast<size_t>(GraphicEQ::kBandCount);
    constexpr std::array<double, 6> kEqGateRates = {
        44100.0,
        48000.0,
        88200.0,
        96000.0,
        176400.0,
        192000.0,
    };
    constexpr double kEqLimitDb = 12.0;

    // The built-in presets as the app ships them (decisions 30–32, the re-voice): each a Tone setting
    // over a flat base, through the Tone weights at the nominal ISO centres, rounded to 0.1 dB
    // (docs/design/eq-lens/plan/preset-revoice.md §1). Presence, Clarity, Warm, Bass & Treble (stored
    // id Loudness), Vocal, Bass Boost. These are the app's own points: EQEditKit's PRESET-06 pins
    // EQBuiltInPreset.points to this same table, so re-voicing a preset re-runs this gate.
    constexpr std::array<EqCurve, 6> kEqPresetCurves = {
        {
            // Presence
            {
                0.0F, 0.0F, 0.0F, 0.0F, 0.0F, 0.0F, 0.0F, 0.0F,
                0.0F, 0.0F, 0.0F, 0.0F, 0.0F, 0.0F, 0.0F, 0.0F,
                0.0F, 0.0F, 0.0F, 0.3F, 1.8F, 3.2F, 3.5F, 3.5F,
                3.2F, 2.0F, 1.0F, 1.0F, 1.0F, 1.0F, 1.0F,
            },
            // Clarity
            {
                0.0F, 0.0F, 0.0F, 0.0F, 0.0F, 0.0F, 0.0F, 0.0F,
                -0.3F, -1.3F, -2.0F, -2.0F, -2.0F, -1.8F, -1.0F, -0.1F,
                0.0F, 0.0F, 0.0F, 0.1F, 0.8F, 1.4F, 1.5F, 1.5F,
                1.7F, 2.4F, 3.0F, 3.0F, 3.0F, 3.0F, 3.0F,
            },
            // Warm
            {
                3.0F, 3.0F, 3.0F, 3.0F, 3.0F, 3.0F, 3.0F, 3.0F,
                2.9F, 2.4F, 2.0F, 2.0F, 2.0F, 1.8F, 1.0F, 0.1F,
                0.0F, 0.0F, 0.0F, -0.1F, -0.8F, -1.4F, -1.5F, -1.5F,
                -1.6F, -1.8F, -2.0F, -2.0F, -2.0F, -2.0F, -2.0F,
            },
            // Bass & Treble (id Loudness)
            {
                5.0F, 5.0F, 5.0F, 5.0F, 5.0F, 5.0F, 5.0F, 5.0F,
                4.3F, 1.8F, 0.1F, 0.0F, 0.0F, 0.0F, 0.0F, 0.0F,
                0.0F, 0.0F, 0.0F, 0.1F, 0.5F, 0.9F, 1.0F, 1.0F,
                1.3F, 2.5F, 3.5F, 3.5F, 3.5F, 3.5F, 3.5F,
            },
            // Vocal
            {
                -2.0F, -2.0F, -2.0F, -2.0F, -2.0F, -2.0F, -2.0F, -2.0F,
                -1.9F, -1.7F, -1.5F, -1.5F, -1.5F, -1.2F, 0.2F, 1.8F,
                2.0F, 2.0F, 2.0F, 2.1F, 2.5F, 2.9F, 3.0F, 3.0F,
                2.6F, 1.2F, 0.1F, 0.0F, 0.0F, 0.0F, 0.0F,
            },
            // Bass Boost
            {
                5.0F, 5.0F, 5.0F, 5.0F, 5.0F, 5.0F, 5.0F, 5.0F,
                4.5F, 2.4F, 1.1F, 1.0F, 1.0F, 0.9F, 0.5F, 0.1F,
                0.0F, 0.0F, 0.0F, 0.0F, 0.0F, 0.0F, 0.0F, 0.0F,
                0.0F, 0.0F, 0.0F, 0.0F, 0.0F, 0.0F, 0.0F,
            },
        },
    };
    constexpr size_t kEqPresetWarm = 2U;

    // EQEditKit's EQBands.centreHz (Swift: pow(10, 1.3 + 0.1·m)), printed %.17g. The kit's
    // BANDS-04 pins the Swift side to this same table, so the UI's bands and the designer's
    // bands can only change together.
    constexpr std::array<double, 31> kEqKitCentresHz = {
        19.952623149688797, 25.118864315095809,
        31.622776601683793, 39.810717055349734,
        50.118723362727252, 63.095734448019329,
        79.432823472428169, 100.0,
        125.89254117941675, 158.48931924611142,
        199.52623149688787, 251.18864315095823,
        316.22776601683796, 398.10717055349733,
        501.18723362727246, 630.957344480193,
        794.3282347242822,  1000.0,
        1258.9254117941675, 1584.893192461114,
        1995.2623149688789, 2511.8864315095821,
        3162.2776601683795, 3981.0717055349774,
        5011.8723362727251, 6309.5734448019302,
        7943.2823472428217, 10000.0,
        12589.254117941688, 15848.931924611141,
        19952.623149688789,
    };

    // The breaker's adversarial commands, pinned from research/eq-geq-poc/fixtures/ (float32).
    constexpr EqCurve kEqWorstCmdLong = {
        12.0F, 12.0F,  -12.0F,      12.0F,  -12.0F, 12.0F,  12.0F,       -12.0F,
        12.0F, -12.0F, 12.0F,       12.0F,  -12.0F, 12.0F,  12.0F,       -12.0F,
        12.0F, -12.0F, 0.0F,        -12.0F, 12.0F,  -12.0F, 10.7036247F, -12.0F,
        12.0F, 12.0F,  10.1254997F, -12.0F, 12.0F,  -12.0F, 12.0F,
    };
    constexpr EqCurve kEqWorstCmd44100 = {
        -12.0F, -12.0F, 12.0F,  -12.0F, -12.0F, 12.0F,  -12.0F, -12.0F, 12.0F,  -12.0F, 12.0F,
        -12.0F, 12.0F,  0.0F,   12.0F,  -12.0F, 12.0F,  -12.0F, -12.0F, -12.0F, 12.0F,  -12.0F,
        12.0F,  -12.0F, -12.0F, 12.0F,  -12.0F, -12.0F, -12.0F, 12.0F,  -12.0F,
    };
    constexpr EqCurve kEqWorstCmd48000 = {
        12.0F, 12.0F,  -12.0F, 12.0F, -12.0F, 12.0F,  12.0F,  -12.0F, 12.0F,  -12.0F, 12.0F,
        12.0F, -12.0F, 12.0F,  12.0F, -12.0F, 12.0F,  -12.0F, 0.0F,   -12.0F, 12.0F,  -12.0F,
        12.0F, -12.0F, 12.0F,  12.0F, 6.0F,   -12.0F, 12.0F,  -12.0F, 12.0F,
    };
    constexpr EqCurve kEqWorstCmd192000 = {
        -12.0F, 12.0F, -12.0F, -12.0F, 12.0F, -12.0F, -12.0F, -12.0F, 12.0F,  -12.0F, 12.0F,
        -12.0F, 12.0F, -12.0F, -12.0F, -6.0F, 12.0F,  -12.0F, 12.0F,  -12.0F, -12.0F, 12.0F,
        -12.0F, 12.0F, -12.0F, -12.0F, 12.0F, -12.0F, -12.0F, -6.0F,  12.0F,
    };

    // A designer on the heap: it is ~47 KB, and worker threads have small stacks.
    auto eqMakeDesigner() -> std::unique_ptr<GraphicEQDesigner>
    {
        return std::make_unique<GraphicEQDesigner>();
    }

    // +12 on even bands, −12 on odd: the hardest regular pattern.
    auto eqAlternatingCurve() -> EqCurve
    {
        EqCurve curve{};
        for (size_t band = 0; band < kDesignBands; ++band)
        {
            curve[band] = (band % 2U == 0U) ? 12.0F : -12.0F;
        }
        return curve;
    }

    auto eqFlatCurveWith(size_t band, float gainDb) -> EqCurve
    {
        EqCurve curve{};
        curve[band] = gainDb;
        return curve;
    }

    auto eqNegated(EqCurve curve) -> EqCurve
    {
        for (float& point : curve)
        {
            point = -point;
        }
        return curve;
    }

    // The UI's fixed response grid (EQPlayed.frequencies): 20·1000^(i/255), 256 points.
    auto eqUiGrid() -> std::vector<double>
    {
        std::vector<double> grid(256);
        for (size_t i = 0; i < grid.size(); ++i)
        {
            grid[i] = 20.0 * std::pow(1000.0, static_cast<double>(i) / 255.0);
        }
        return grid;
    }

    // `count` log-spaced frequencies over [lo, hi].
    auto eqLogGrid(double lo, double hi, size_t count) -> std::vector<double>
    {
        std::vector<double> grid(count);
        for (size_t i = 0; i < count; ++i)
        {
            const double t = static_cast<double>(i) / static_cast<double>(count - 1U);
            grid[i] = lo * std::pow(hi / lo, t);
        }
        return grid;
    }

    // The Tone macro (decision 24; geq.py tone_weights): a raised-cosine partition of unity over
    // log2 f with edges 150 / 500 / 2000 / 6000 Hz and 1-octave transitions, evaluated at the
    // exact centres; the sum is clamped to ±12.
    auto eqToneCurve(const std::array<double, 5>& tone) -> EqCurve
    {
        constexpr std::array<double, 4> kEdgesHz = {150.0, 500.0, 2000.0, 6000.0};
        const auto step = [](double octaves)
        {
            const double x = std::clamp(octaves, -0.5, 0.5);
            return 0.5 * (1.0 + std::sin(std::numbers::pi * x));
        };
        EqCurve curve{};
        for (size_t band = 0; band < kDesignBands; ++band)
        {
            const double x = std::log2(GraphicEQ::centreHz(static_cast<int>(band)));
            std::array<double, 4> s{};
            for (size_t e = 0; e < kEdgesHz.size(); ++e)
            {
                s[e] = step(x - std::log2(kEdgesHz[e]));
            }
            const std::array<double, 5> w = {
                1.0 - s[0],
                s[0] - s[1],
                s[1] - s[2],
                s[2] - s[3],
                s[3],
            };
            double sum = 0.0;
            for (size_t r = 0; r < w.size(); ++r)
            {
                sum += tone[r] * w[r];
            }
            curve[band] = static_cast<float>(std::clamp(sum, -kEqLimitDb, kEqLimitDb));
        }
        return curve;
    }

    // geq2.py tone_set: random Tone settings in ±12.
    auto eqToneSet(std::mt19937& rng, int count) -> std::vector<EqCurve>
    {
        std::uniform_real_distribution<double> dist(-12.0, 12.0);
        std::vector<EqCurve> curves;
        for (int i = 0; i < count; ++i)
        {
            std::array<double, 5> tone{};
            for (double& t : tone)
            {
                t = dist(rng);
            }
            curves.push_back(eqToneCurve(tone));
        }
        return curves;
    }

    // np.interp of `values` at `knots` (held flat outside the knots).
    auto eqInterpolate(const std::array<double, 6>& knots,
                       const std::array<double, 6>& values,
                       double x) -> double
    {
        if (x <= knots.front())
        {
            return values.front();
        }
        if (x >= knots.back())
        {
            return values.back();
        }
        size_t j = 1U;
        while (knots[j] < x)
        {
            ++j;
        }
        const double t = (x - knots[j - 1U]) / (knots[j] - knots[j - 1U]);
        return values[j - 1U] + (t * (values[j] - values[j - 1U]));
    }

    // geq2.py smooth_set: 6 random knots on the log2 axis, linear between them, values in ±12.
    auto eqSmoothSet(std::mt19937& rng, int count) -> std::vector<EqCurve>
    {
        const double lo = std::log2(GraphicEQ::centreHz(0));
        const double hi = std::log2(GraphicEQ::centreHz(GraphicEQ::kBandCount - 1));
        std::uniform_real_distribution<double> where(lo, hi);
        std::uniform_real_distribution<double> value(-12.0, 12.0);
        std::vector<EqCurve> curves;
        for (int i = 0; i < count; ++i)
        {
            std::array<double, 6> knots{};
            std::array<double, 6> values{};
            for (double& k : knots)
            {
                k = where(rng);
            }
            for (double& v : values)
            {
                v = value(rng);
            }
            std::ranges::sort(knots);
            EqCurve curve{};
            for (size_t band = 0; band < kDesignBands; ++band)
            {
                const double x = std::log2(GraphicEQ::centreHz(static_cast<int>(band)));
                curve[band] = static_cast<float>(eqInterpolate(knots, values, x));
            }
            curves.push_back(curve);
        }
        return curves;
    }

    // The Rämö et al. 2020 protocol (geq2.py ramo_set): half "extreme" {−12, 0, +12} commands,
    // half random integers in [−12, 12].
    auto eqRamoSet(std::mt19937& rng) -> std::vector<EqCurve>
    {
        constexpr int kHalf = 500;
        constexpr std::array<float, 3> kExtremes = {-12.0F, 0.0F, 12.0F};
        std::uniform_int_distribution<int> pick(0, 2);
        std::uniform_int_distribution<int> integer(-12, 12);
        std::vector<EqCurve> curves;
        for (int i = 0; i < kHalf; ++i)
        {
            EqCurve curve{};
            for (float& point : curve)
            {
                point = kExtremes[static_cast<size_t>(pick(rng))];
            }
            curves.push_back(curve);
        }
        for (int i = 0; i < kHalf; ++i)
        {
            EqCurve curve{};
            for (float& point : curve)
            {
                point = static_cast<float>(integer(rng));
            }
            curves.push_back(curve);
        }
        return curves;
    }

    // The hard patterns (geq2.py hard_set) plus the four pinned breaker commands: 35 curves.
    auto eqHardSet() -> std::vector<EqCurve>
    {
        std::vector<EqCurve> curves;
        const EqCurve alternating = eqAlternatingCurve();
        curves.push_back(alternating);
        curves.push_back(eqNegated(alternating));
        for (size_t phase = 0; phase < 3U; ++phase)
        {
            EqCurve everyThird{};
            for (size_t band = 0; band < kDesignBands; ++band)
            {
                everyThird[band] = (band % 3U == phase) ? -12.0F : 12.0F;
            }
            curves.push_back(everyThird);
            curves.push_back(eqNegated(everyThird));
        }
        for (const size_t edge : {5U, 10U, 15U, 20U, 25U, 28U, 29U, 30U})
        {
            EqCurve cliff{};
            for (size_t band = 0; band < kDesignBands; ++band)
            {
                cliff[band] = (band < edge) ? -12.0F : 12.0F;
            }
            curves.push_back(cliff);
            curves.push_back(eqNegated(cliff));
        }
        for (const size_t band : {0U, 1U, 29U, 30U})
        {
            curves.push_back(eqFlatCurveWith(band, 12.0F));
        }
        EqCurve edgePair{};
        edgePair[29] = -12.0F;
        edgePair[30] = 12.0F;
        curves.push_back(edgePair);
        EqCurve allUp{};
        allUp.fill(12.0F);
        curves.push_back(allUp);
        curves.push_back(eqNegated(allUp));
        curves.push_back(kEqWorstCmdLong);
        curves.push_back(kEqWorstCmd44100);
        curves.push_back(kEqWorstCmd48000);
        curves.push_back(kEqWorstCmd192000);
        return curves;
    }

    // Max |played − clamped target| over the 31 centres.
    auto eqCentreErrorDb(const GraphicEQDesign& design, const EqCurve& curve) -> double
    {
        double worst = 0.0;
        for (size_t band = 0; band < kDesignBands; ++band)
        {
            const double target =
                std::clamp(static_cast<double>(curve[band]), -kEqLimitDb, kEqLimitDb);
            const double played =
                GraphicEQDesigner::playedDb(design, GraphicEQ::centreHz(static_cast<int>(band)));
            worst = std::max(worst, std::abs(played - target));
        }
        return worst;
    }

    // Design every curve at `sampleRate`: the worst centre error and its curve, or a failure.
    struct EqSetResult
    {
        double worstDb = 0.0;
        size_t worstIndex = 0U;
        std::string failure;
    };

    auto eqWorstCentreError(GraphicEQDesigner& designer,
                            const std::vector<EqCurve>& curves,
                            double sampleRate) -> EqSetResult
    {
        EqSetResult result;
        GraphicEQDesign design{};
        for (size_t i = 0; i < curves.size(); ++i)
        {
            if (!designer.design(curves[i], sampleRate, design))
            {
                result.failure = std::format("curve {} failed to design at {} Hz", i, sampleRate);
                return result;
            }
            const double error = eqCentreErrorDb(design, curves[i]);
            if (!std::isfinite(error))
            {
                result.failure = std::format("curve {} plays a non-finite response", i);
                return result;
            }
            if (error > result.worstDb)
            {
                result.worstDb = error;
                result.worstIndex = i;
            }
        }
        return result;
    }

    // Check one named set against `boundDb` at every gate rate; "" on pass. Appends the per-rate
    // worst to `report`.
    auto eqCheckSetAtAllRates(const char* setName,
                              const std::vector<EqCurve>& curves,
                              double boundDb,
                              std::string& report) -> std::string
    {
        auto designer = eqMakeDesigner();
        double overall = 0.0;
        report +=
            std::format("[info]   {} ({} curves), bound {} dB:", setName, curves.size(), boundDb);
        for (const double rate : kEqGateRates)
        {
            const EqSetResult result = eqWorstCentreError(*designer, curves, rate);
            if (!result.failure.empty())
            {
                return std::format("{}: {}", setName, result.failure);
            }
            report += std::format(" {:.1f}k {:.4f}", rate / 1000.0, result.worstDb);
            overall = std::max(overall, result.worstDb);
            if (!(result.worstDb <= boundDb))
            {
                return std::format(
                    "{} @ {} Hz: curve {} plays {:.4f} dB off at a centre (bound {})",
                    setName,
                    rate,
                    result.worstIndex,
                    result.worstDb,
                    boundDb);
            }
        }
        report += std::format("  → worst {:.4f}\n", overall);
        return {};
    }

    // An independent bilinear bell: the RBJ Audio-EQ-Cookbook peaking biquad with alpha =
    // tan(B/2), B = 0.40·ω0, A = 10^(G/40), evaluated as the complex ratio B(z)/A(z) on the unit
    // circle (the port rule's "complex form"). Shares no code with GraphicEQBands.h.
    auto eqRbjBellDb(double centreHz, double gainDb, double sampleRate, double hz) -> double
    {
        const double w0 = 2.0 * std::numbers::pi * centreHz / sampleRate;
        const double alpha = std::tan(0.4 * w0 / 2.0);
        const double amp = std::pow(10.0, gainDb / 40.0);
        const double cosW0 = std::cos(w0);
        const std::complex<double> z1 = std::polar(1.0, -2.0 * std::numbers::pi * hz / sampleRate);
        const std::complex<double> num =
            (1.0 + (alpha * amp)) + (-2.0 * cosW0 * z1) + ((1.0 - (alpha * amp)) * z1 * z1);
        const std::complex<double> den =
            (1.0 + (alpha / amp)) + (-2.0 * cosW0 * z1) + ((1.0 - (alpha / amp)) * z1 * z1);
        return 20.0 * std::log10(std::abs(num / den));
    }

    // The design's response rebuilt independently from its solved gains alone.
    auto eqIndependentPlayedDb(const GraphicEQDesign& design, double hz) -> double
    {
        double sum = 0.0;
        for (size_t band = 0; band < kDesignBands; ++band)
        {
            const double centre = std::pow(10.0, 1.3 + (0.1 * static_cast<double>(band)));
            sum += eqRbjBellDb(centre, design.filterGainDb[band], design.sampleRate, hz);
        }
        return sum;
    }

    // One Simper trapezoidal SVF bell in time domain (the structure EQ1b's module runs).
    struct EqSvfBand
    {
        GraphicEQ::SvfDamping damping;
        double m1 = 0.0;
        double ic1 = 0.0;
        double ic2 = 0.0;

        auto tick(double in) -> double
        {
            const double v3 = in - ic2;
            const double v1 = (damping.a1 * ic1) + (damping.a2 * v3);
            const double v2 = ic2 + (damping.a2 * ic1) + (damping.a3 * v3);
            ic1 = (2.0 * v1) - ic1;
            ic2 = (2.0 * v2) - ic2;
            return in + (m1 * v1);
        }
    };

    // Run a sum of integer-Hz sines through a time-domain cascade of SVF bells built from the
    // design's (g, k, m1), settle for 2 s, then measure each tone's gain (dB) by correlation over
    // one second (an integer number of cycles of every tone, so the tones are orthogonal).
    auto eqTimeDomainGainsDb(const GraphicEQDesign& design, const std::vector<double>& tonesHz)
        -> std::vector<double>
    {
        constexpr double kToneAmplitude = 0.05;
        constexpr double kSettleSeconds = 2.0;
        const auto settle = static_cast<size_t>(kSettleSeconds * design.sampleRate);
        const auto window = static_cast<size_t>(design.sampleRate); // 1 s
        std::vector<EqSvfBand> bands(kDesignBands);
        for (size_t band = 0; band < kDesignBands; ++band)
        {
            bands[band].damping = GraphicEQ::svfDamping(design.svfG[band], design.bells[band].k);
            bands[band].m1 = design.bells[band].m1;
        }
        std::vector<double> inPhase(tonesHz.size(), 0.0);
        std::vector<double> quadrature(tonesHz.size(), 0.0);
        for (size_t n = 0; n < settle + window; ++n)
        {
            const double time = static_cast<double>(n) / design.sampleRate;
            double sample = 0.0;
            for (const double tone : tonesHz)
            {
                sample += kToneAmplitude * std::sin(2.0 * std::numbers::pi * tone * time);
            }
            for (EqSvfBand& band : bands)
            {
                sample = band.tick(sample);
            }
            for (size_t t = 0; n >= settle && t < tonesHz.size(); ++t)
            {
                const double phase = 2.0 * std::numbers::pi * tonesHz[t] * time;
                inPhase[t] += sample * std::sin(phase);
                quadrature[t] += sample * std::cos(phase);
            }
        }
        std::vector<double> gainsDb(tonesHz.size());
        for (size_t t = 0; t < tonesHz.size(); ++t)
        {
            const double amplitude =
                2.0 * std::hypot(inPhase[t], quadrature[t]) / static_cast<double>(window);
            gainsDb[t] = 20.0 * std::log10(amplitude / kToneAmplitude);
        }
        return gainsDb;
    }

    auto eqSameDesign(const GraphicEQDesign& lhs, const GraphicEQDesign& rhs) -> bool
    {
        static_assert(sizeof(GraphicEQDesign) == sizeof(double) * (1U + (4U * kDesignBands)),
                      "GraphicEQDesign must be padding-free for a bitwise compare");
        return std::memcmp(&lhs, &rhs, sizeof(GraphicEQDesign)) == 0;
    }

    // The worst exactness errors of the shared bell function (EQ_SvfBell_Exact).
    struct EqBellErrors
    {
        double centre = 0.0;
        double inverse = 0.0;
        double form = 0.0;
        double bandwidth = 0.0;
    };

    // The relative error of the bell's half-dB-gain bandwidth against 0.40·ω0, by bisection on ω
    // between DC, the centre and Nyquist.
    auto eqHalfGainBandwidthError(double centre, double gainDb, double rate) -> double
    {
        const double g = GraphicEQ::prewarp(centre, rate);
        const double k0 = GraphicEQ::bellK0(centre, rate);
        const GraphicEQ::SvfBell bell = GraphicEQ::svfBell(gainDb, k0);
        const auto excess = [&](double w)
        {
            const double omega = std::tan(w / 2.0) / g;
            return GraphicEQ::bellDb(bell, omega * omega) - (gainDb / 2.0);
        };
        const auto crossing = [&](double lo, double hi)
        {
            const bool loSign = excess(lo) < 0.0;
            for (int it = 0; it < 200; ++it)
            {
                const double mid = 0.5 * (lo + hi);
                ((excess(mid) < 0.0) == loSign ? lo : hi) = mid;
            }
            return 0.5 * (lo + hi);
        };
        const double w0 = 2.0 * std::numbers::pi * centre / rate;
        const double lower = crossing(1e-12, w0);
        const double upper = crossing(w0, std::numbers::pi * (1.0 - 1e-12));
        return std::abs((upper - lower) - (0.4 * w0)) / w0;
    }

    // Fold one band's exactness errors at `rate` into `errors`; "" unless 0 dB is not identity.
    auto eqBellBandErrors(double rate, int band, EqBellErrors& errors) -> std::string
    {
        const double centre = GraphicEQ::centreHz(band);
        const double g = GraphicEQ::prewarp(centre, rate);
        const double k0 = GraphicEQ::bellK0(centre, rate);
        const GraphicEQ::SvfBell unity = GraphicEQ::svfBell(0.0, k0);
        if (unity.m1 != 0.0 || unity.k != k0)
        {
            return std::format("band {} @ {} Hz: a 0 dB bell is not an identity", band, rate);
        }
        const auto bellDbAt = [&](double gainDb, double hz)
        {
            const double omega = GraphicEQ::prewarp(hz, rate) / g;
            return GraphicEQ::bellDb(GraphicEQ::svfBell(gainDb, k0), omega * omega);
        };
        const std::vector<double> sweep = eqLogGrid(10.0, 0.49 * rate, 64);
        for (const double gain : {-12.0, -6.0, -1e-3, 1e-3, 6.0, 12.0, 24.0})
        {
            // Exactly G at the centre (Ω = 1).
            const double atCentre = GraphicEQ::bellDb(GraphicEQ::svfBell(gain, k0), 1.0);
            errors.centre = std::max(errors.centre, std::abs(atCentre - gain));
            // A cut is the exact inverse of the boost; the SVF form ≡ the RBJ biquad.
            for (const double hz : sweep)
            {
                const double boost = bellDbAt(gain, hz);
                errors.inverse = std::max(errors.inverse, std::abs(boost + bellDbAt(-gain, hz)));
                errors.form =
                    std::max(errors.form, std::abs(boost - eqRbjBellDb(centre, gain, rate, hz)));
            }
            if (std::abs(gain) >= 1.0)
            {
                errors.bandwidth =
                    std::max(errors.bandwidth, eqHalfGainBandwidthError(centre, gain, rate));
            }
        }
        return {};
    }

    // The C-ABI hands back exactly the C++ design and read-back; "" when it does.
    auto eqAbiMatchesCpp(AsEqDesigner* abi,
                         const EqCurve& curve,
                         const GraphicEQDesign& design,
                         const std::vector<double>& grid) -> std::string
    {
        std::array<float, 31> centreDb{};
        std::vector<float> responseDb(grid.size());
        std::array<double, 31> gains{};
        std::array<double, 31> svfK{};
        std::array<double, 31> svfM1{};
        const AsEqDesignOutput output = {
            centreDb.data(),
            grid.data(),
            responseDb.data(),
            static_cast<uint32_t>(grid.size()),
            gains.data(),
            svfK.data(),
            svfM1.data(),
        };
        if (!asEqDesign(abi, curve.data(), 31U, design.sampleRate, &output))
        {
            return "asEqDesign returned false";
        }
        for (size_t band = 0; band < kDesignBands; ++band)
        {
            const auto centre = static_cast<float>(
                GraphicEQDesigner::playedDb(design, GraphicEQ::centreHz(static_cast<int>(band))));
            if (centreDb[band] != centre || gains[band] != design.filterGainDb[band] ||
                svfK[band] != design.bells[band].k || svfM1[band] != design.bells[band].m1)
            {
                return std::format("band {}: the C-ABI's centre/coefficients differ from C++",
                                   band);
            }
        }
        for (size_t i = 0; i < grid.size(); ++i)
        {
            if (responseDb[i] != static_cast<float>(GraphicEQDesigner::playedDb(design, grid[i])))
            {
                return std::format("response[{}]: the C-ABI differs from C++", i);
            }
        }
        return {};
    }

    // Flat (all 0 or all −0) designs as an exact identity at `rate`; "" when it does.
    auto eqFlatIsIdentity(GraphicEQDesigner& designer, const EqCurve& flat, double rate)
        -> std::string
    {
        GraphicEQDesign design{};
        if (!designer.design(flat, rate, design))
        {
            return std::format("flat failed to design at {} Hz", rate);
        }
        for (size_t band = 0; band < kDesignBands; ++band)
        {
            const double k0 = GraphicEQ::bellK0(GraphicEQ::centreHz(static_cast<int>(band)), rate);
            if (design.filterGainDb[band] != 0.0 || design.bells[band].m1 != 0.0 ||
                design.bells[band].k != k0)
            {
                return std::format("flat @ {} Hz band {}: gain {} m1 {} (want exactly 0)",
                                   rate,
                                   band,
                                   design.filterGainDb[band],
                                   design.bells[band].m1);
            }
        }
        for (const double hz : eqLogGrid(20.0, 20000.0, 256))
        {
            if (GraphicEQDesigner::playedDb(design, hz) != 0.0)
            {
                return std::format("flat @ {} Hz plays non-zero dB at {} Hz", rate, hz);
            }
        }
        return {};
    }

    // Max |playedDb − the independent complex-form RBJ product| over `grid`.
    auto eqWorstAnalyticDelta(const GraphicEQDesign& design, const std::vector<double>& grid)
        -> double
    {
        double worst = 0.0;
        for (const double hz : grid)
        {
            const double delta =
                GraphicEQDesigner::playedDb(design, hz) - eqIndependentPlayedDb(design, hz);
            worst = std::max(worst, std::abs(delta));
        }
        return worst;
    }

    // Max |what a time-domain SVF cascade plays − playedDb| at `tonesHz`.
    auto eqWorstTimeDomainDelta(const GraphicEQDesign& design, const std::vector<double>& tonesHz)
        -> double
    {
        const std::vector<double> measured = eqTimeDomainGainsDb(design, tonesHz);
        double worst = 0.0;
        for (size_t t = 0; t < tonesHz.size(); ++t)
        {
            worst = std::max(
                worst, std::abs(measured[t] - GraphicEQDesigner::playedDb(design, tonesHz[t])));
        }
        return worst;
    }

    // The asEqDesign trust boundary: every bad request returns false and leaves the caller's
    // buffers untouched; responseCount 0 needs no response buffers. "" on pass.
    auto eqAbiRejections(const EqCurve& valid) -> std::string
    {
        constexpr double kNan = std::numeric_limits<double>::quiet_NaN();
        constexpr float kUntouched = 777.0F;
        AsEqDesigner* abi = asEqDesignerCreate();
        if (abi == nullptr)
        {
            return "asEqDesignerCreate returned NULL";
        }
        std::array<float, 31> centreDb{};
        std::array<float, 2> responseDb{};
        std::array<double, 2> responseHz = {100.0, 1000.0};
        EqCurve nanPoint = valid;
        nanPoint[3] = std::numeric_limits<float>::quiet_NaN();
        struct Request
        {
            AsEqDesigner* designer = nullptr;
            const float* points = nullptr;
            uint32_t count = 31U;
            double rate = 48000.0;
            const double* hz = nullptr;
            float* response = nullptr;
            float* centres = nullptr;
        };
        Request valid48k;
        valid48k.designer = abi;
        valid48k.points = valid.data();
        valid48k.hz = responseHz.data();
        valid48k.response = responseDb.data();
        valid48k.centres = centreDb.data();
        // One invalid field per request.
        const auto with = [&valid48k](const auto& spoil)
        {
            Request request = valid48k;
            spoil(request);
            return request;
        };
        const std::array<std::pair<const char*, Request>, 10> requests = {
            {
                {"a NULL designer", with([](Request& r) { r.designer = nullptr; })},
                {"NULL points", with([](Request& r) { r.points = nullptr; })},
                {"a NULL centreDb", with([](Request& r) { r.centres = nullptr; })},
                {"pointCount 30", with([](Request& r) { r.count = 30U; })},
                {"pointCount 32", with([](Request& r) { r.count = 32U; })},
                {"a NULL responseHz", with([](Request& r) { r.hz = nullptr; })},
                {"a NULL responseDb", with([](Request& r) { r.response = nullptr; })},
                {"a NaN point", with([&nanPoint](Request& r) { r.points = nanPoint.data(); })},
                {"a NaN sample rate", with([](Request& r) { r.rate = kNan; })},
                {"a 32 kHz sample rate", with([](Request& r) { r.rate = 32000.0; })},
            },
        };
        const auto rejectedCleanly = [&](const Request& request)
        {
            centreDb.fill(kUntouched);
            responseDb.fill(kUntouched);
            const AsEqDesignOutput output = {
                request.centres,
                request.hz,
                request.response,
                2U,
                nullptr,
                nullptr,
                nullptr,
            };
            const bool accepted =
                asEqDesign(request.designer, request.points, request.count, request.rate, &output);
            return !accepted &&
                   std::ranges::all_of(centreDb, [](float v) { return v == kUntouched; }) &&
                   std::ranges::all_of(responseDb, [](float v) { return v == kUntouched; });
        };
        std::string failure;
        for (const auto& [what, request] : requests)
        {
            if (failure.empty() && !rejectedCleanly(request))
            {
                failure = std::format("C-ABI: {} was not rejected cleanly", what);
            }
        }
        for (const double badHz : {-1.0, kNan, std::numeric_limits<double>::infinity(), 24000.0})
        {
            responseHz[1] = badHz; // valid48k.hz points at responseHz
            if (failure.empty() && !rejectedCleanly(valid48k))
            {
                failure =
                    std::format("C-ABI: response frequency {} was not rejected cleanly", badHz);
            }
        }
        if (failure.empty() && asEqDesign(abi, valid.data(), 31U, 48000.0, nullptr))
        {
            failure = "C-ABI: a NULL output was accepted";
        }
        AsEqDesignOutput centresOnly{};
        centresOnly.centreDb = centreDb.data();
        if (failure.empty() && !asEqDesign(abi, valid.data(), 31U, 48000.0, &centresOnly))
        {
            failure = "C-ABI: responseCount 0 with NULL response buffers was rejected";
        }
        asEqDesignerDestroy(abi);
        asEqDesignerDestroy(nullptr); // NULL-safe
        return failure;
    }
} // namespace

// ---------------------------------------------------------------------------
// EQ_Bands_MatchKit — the C++ centres are the kit's (one source of truth, pinned on both sides).
// ---------------------------------------------------------------------------
static auto testEqBandsMatchKit() -> void
{
    static const char* const kName = "EQ_Bands_MatchKit";
    for (size_t band = 0; band < kDesignBands; ++band)
    {
        const double centre = GraphicEQ::centreHz(static_cast<int>(band));
        if (centre != kEqKitCentresHz[band])
        {
            logFail(kName,
                    std::format("band {}: C++ {:.17g} Hz vs EQBands.centreHz {:.17g} Hz",
                                band,
                                centre,
                                kEqKitCentresHz[band]));
            return;
        }
    }
    logPass(kName);
}

// ---------------------------------------------------------------------------
// EQ_Designer_MatchesOracle — the port reproduces the Python oracle's solved gains.
// ---------------------------------------------------------------------------
static auto testEqDesignerMatchesOracle() -> void
{
    static const char* const kName = "EQ_Designer_MatchesOracle";
    constexpr double kToleranceDb = 1e-6; // the oracle's own SOS-form noise is ≤ 1.3e-7 dB
    struct OracleCase
    {
        const char* name;
        EqCurve curve;
        double sampleRate;
        std::array<double, 31> gainsDb; // geq2.design(float32(curve), fs, 5)
    };
    const std::array<OracleCase, 6> cases = {
        {
            {
                "worst_cmd_44100",
                kEqWorstCmd44100,
                44100.0,
                {
                    -10.940743385456667, -17.614438489351066, 30.342204999882778,
                    -19.042444277051469, -19.121109642246676, 30.164497270062707,
                    -18.321911102736454, -17.67939700904272,  29.687825234236342,
                    -30.040965621049228, 28.006605349549933,  -31.18119650836498,
                    23.253244466435959,  -10.218715822711005, 22.6042561276426,
                    -31.658842271954263, 30.213238211916867,  -16.075385488525594,
                    -6.0092128216244296, -16.952470746767354, 28.807691188215962,
                    -32.080882631487825, 28.083576434636711,  -18.489815727635371,
                    -18.376232697750414, 30.831003204231568,  -17.969861552782103,
                    -7.1289761998440415, -17.456782259036586, 32.254408751571425,
                    -20.861215302532216,
                },
            },
            {
                "worst_cmd_48000",
                kEqWorstCmd48000,
                48000.0,
                {
                    9.5574685159206041,  16.268052917319686,  -29.273732390695823,
                    31.267867847085821,  -29.053848533554174, 17.072823304220091,
                    17.170114340271656,  -28.710442434084875, 31.971864306790557,
                    -28.222910207198272, 18.131590393346997,  17.839150527509027,
                    -31.076912278767775, 17.580056369650411,  17.330259965661419,
                    -29.262285344688131, 32.294527046168128,  -22.334752895216219,
                    10.256811832215678,  -23.26349921903412,  31.178270205783623,
                    -28.179136095729824, 29.686519530183183,  -30.34626179505976,
                    16.665038683639445,  9.3305640012075308,  8.8542565685903192,
                    -25.572037306565509, 30.772969663269343,  -33.343795715083175,
                    20.758418439728249,
                },
            },
            {
                "worst_cmd_long",
                kEqWorstCmdLong,
                88200.0,
                {
                    9.5574424336912518,  16.268022541447557,  -29.273774997328136,
                    31.267802222835584,  -29.053918901950745, 17.072700811895775,
                    17.169905720455478,  -28.710655476352535, 31.971684288725438,
                    -28.222712746313508, 18.132015411950224,  17.840344681126709,
                    -31.075004678321115, 17.580561921950725,  17.324917811228332,
                    -29.273834432121198, 32.276340221960972,  -22.345488804733801,
                    10.288816644344907,  -23.090150601841998, 31.506076397213874,
                    -27.713013297494363, 27.353344646473463,  -29.984389337434148,
                    16.861735072154016,  7.3169974969928493,  14.486942664733498,
                    -27.999776597153559, 31.072384183814183,  -30.450492664722745,
                    20.793600299723003,
                },
            },
            // The re-voiced Warm (decision 30), re-pinned from geq2.py: the same call reproduces the
            // previous Warm's pin bit for bit.
            {
                "Warm",
                kEqPresetCurves[kEqPresetWarm],
                96000.0,
                {
                    2.1112820360850755, 1.1807556370178052, 1.2969295683500204,
                    1.2438699258822663, 1.2464823560265261, 1.2430874855086256,
                    1.2487326600697561, 1.2774641553450503, 1.382609903905757,
                    0.9444165473510914, 0.6476204497087106, 0.8430921637625658,
                    0.9044386298866244, 1.0081312538928489, 0.464926508439896,
                    -0.33933914477935695, -0.03247344337033698, -0.008711819953769588,
                    0.03094858324795102, 0.2395791227158014, -0.38006872867212876,
                    -0.7995128928458828, -0.6607579286461239, -0.5822049455280038,
                    -0.6182486848132482, -0.7309574485949489, -0.9137383668472814,
                    -0.8067130335419808, -0.8500287502778613, -0.7462594727854691,
                    -1.4928734411676847,
                },
            },
            {
                "alternating",
                eqAlternatingCurve(),
                176400.0,
                {
                    20.526050790665483,  -30.535603321208196, 29.50632093325342,
                    -28.298438573407079, 29.465268227537155,  -28.87646282457013,
                    29.010243651733084,  -29.09013860640043,  28.971248128994528,
                    -29.053119976003,    29.019011032562435,  -29.021429217305165,
                    29.03212310194959,   -29.020192687018714, 29.029079689010818,
                    -29.022733415001184, 29.029474474910131,  -29.020160843943469,
                    29.032190343528498,  -29.02392445555018,  29.016387646263492,
                    -29.059744446968605, 28.971843569262749,  -29.087316216172475,
                    29.042018268864183,  -28.845600670790297, 29.523856333127011,
                    -28.32935958288143,  29.467639695309998,  -30.730704988794521,
                    20.611939820467843,
                },
            },
            {
                "worst_cmd_192000",
                kEqWorstCmd192000,
                192000.0,
                {
                    -22.718471940509726, 30.526540779002836,  -18.386552549719273,
                    -18.789982775520137, 30.260262679136286,  -18.188105000745008,
                    -7.1980084773362156, -17.115518878672376, 29.529545255006315,
                    -30.754961819629262, 27.128637223549397,  -30.35066877492152,
                    30.172193309173213,  -16.298767018619703, -8.7991461100561654,
                    -8.0890390863029911, 25.232444495656509,  -31.941196261046638,
                    29.437814659028952,  -16.612351153365996, -16.924823815212221,
                    28.852249210302386,  -31.882547144747708, 28.280816542367305,
                    -18.109891301977768, -17.89101981159645,  30.919305741145067,
                    -17.786544750113954, -9.5787833222161609, -10.079381366644515,
                    16.912975572267065,
                },
            },
        },
    };

    auto designer = eqMakeDesigner();
    double worst = 0.0;
    for (const OracleCase& oracle : cases)
    {
        GraphicEQDesign design{};
        if (!designer->design(oracle.curve, oracle.sampleRate, design))
        {
            logFail(kName,
                    std::format("{} failed to design at {} Hz", oracle.name, oracle.sampleRate));
            return;
        }
        for (size_t band = 0; band < kDesignBands; ++band)
        {
            const double delta = std::abs(design.filterGainDb[band] - oracle.gainsDb[band]);
            worst = std::max(worst, delta);
            if (!(delta <= kToleranceDb))
            {
                logFail(kName,
                        std::format("{} @ {} Hz band {}: C++ {:.12f} dB vs oracle {:.12f} dB",
                                    oracle.name,
                                    oracle.sampleRate,
                                    band,
                                    design.filterGainDb[band],
                                    oracle.gainsDb[band]));
                return;
            }
        }
    }
    logInfo(
        std::format("[info] {}: max |C++ − oracle| solved gain {:.2e} dB over the 6 pinned cases\n",
                    kName,
                    worst));
    logPass(kName);
}

// ---------------------------------------------------------------------------
// EQ_ACGE_Presets_Tone_Smooth / EQ_ACGE_Ramo1000 / EQ_ACGE_Hard — accuracy at the 31 centres,
// every gate rate.
// ---------------------------------------------------------------------------
static auto testEqAcgePresetsToneSmooth() -> void
{
    static const char* const kName = "EQ_ACGE_Presets_Tone_Smooth";
    constexpr uint32_t kSeed = 2020U;
    std::mt19937 rng(kSeed);
    const std::vector<EqCurve> presets(kEqPresetCurves.begin(), kEqPresetCurves.end());
    const std::vector<EqCurve> tone = eqToneSet(rng, 100);
    const std::vector<EqCurve> smooth = eqSmoothSet(rng, 200);
    std::string report =
        std::format("[info] {}: worst |played − target| at the centres (dB)\n", kName);
    const std::array<std::tuple<const char*, const std::vector<EqCurve>*, double>, 3> sets = {
        {
            {"presets", &presets, 0.084},
            {"tone", &tone, 0.2},
            {"smooth", &smooth, 0.3},
        },
    };
    for (const auto& [name, curves, bound] : sets)
    {
        const std::string err = eqCheckSetAtAllRates(name, *curves, bound, report);
        if (!err.empty())
        {
            logInfo(report);
            logFail(kName, err);
            return;
        }
    }
    logInfo(report);
    logPass(kName);
}

static auto testEqAcgeRamo1000() -> void
{
    static const char* const kName = "EQ_ACGE_Ramo1000";
    constexpr uint32_t kSeed = 1000U;
    std::mt19937 rng(kSeed);
    const std::vector<EqCurve> ramo = eqRamoSet(rng);
    std::string report =
        std::format("[info] {}: worst |played − target| at the centres (dB)\n", kName);
    const std::string err = eqCheckSetAtAllRates("ramo binary+integer", ramo, 0.6, report);
    logInfo(report);
    if (!err.empty())
    {
        logFail(kName, err);
        return;
    }
    logPass(kName);
}

static auto testEqAcgeHard() -> void
{
    static const char* const kName = "EQ_ACGE_Hard";
    const std::vector<EqCurve> hard = eqHardSet();
    std::string report =
        std::format("[info] {}: worst |played − target| at the centres (dB)\n", kName);
    const std::string err = eqCheckSetAtAllRates("hard + 4 breaker", hard, 0.6, report);
    logInfo(report);
    if (!err.empty())
    {
        logFail(kName, err);
        return;
    }
    logPass(kName);
}

// ---------------------------------------------------------------------------
// EQ_ACGE_SingleBand — one band at ±6 / ±12, every band, every gate rate.
// ---------------------------------------------------------------------------
static auto testEqAcgeSingleBand() -> void
{
    static const char* const kName = "EQ_ACGE_SingleBand";
    auto designer = eqMakeDesigner();
    double worst6 = 0.0;
    double worst12 = 0.0;
    for (const double rate : kEqGateRates)
    {
        for (size_t band = 0; band < kDesignBands; ++band)
        {
            for (const float gain : {6.0F, -6.0F, 12.0F, -12.0F})
            {
                const EqCurve curve = eqFlatCurveWith(band, gain);
                GraphicEQDesign design{};
                if (!designer->design(curve, rate, design))
                {
                    logFail(kName,
                            std::format("band {} @ {} dB failed at {} Hz", band, gain, rate));
                    return;
                }
                const double error = eqCentreErrorDb(design, curve);
                const bool twelve = std::abs(gain) > 6.0F;
                double& worst = twelve ? worst12 : worst6;
                worst = std::max(worst, error);
                const double bound = twelve ? 0.3 : 0.25;
                if (!(error <= bound))
                {
                    logFail(kName,
                            std::format("band {} @ {} dB, {} Hz: {:.4f} dB off (bound {})",
                                        band,
                                        gain,
                                        rate,
                                        error,
                                        bound));
                    return;
                }
            }
        }
    }
    logInfo(std::format(
        "[info] {}: worst ±6 {:.4f} dB (≤ 0.25), ±12 {:.4f} dB (≤ 0.3)\n", kName, worst6, worst12));
    logPass(kName);
}

// ---------------------------------------------------------------------------
// EQ_SvfBell_Exact — the shared bell function is the exact bilinear bell it claims to be.
// ---------------------------------------------------------------------------
static auto testEqSvfBellExact() -> void
{
    static const char* const kName = "EQ_SvfBell_Exact";
    constexpr double kExactDb = 1e-9;
    constexpr double kFormDb = 1e-7; // SVF form vs the RBJ complex form (the latter's noise)
    constexpr double kBandwidthRel = 1e-9;
    EqBellErrors errors;
    for (const double rate : kEqGateRates)
    {
        for (int band = 0; band < GraphicEQ::kBandCount; ++band)
        {
            const std::string failure = eqBellBandErrors(rate, band, errors);
            if (!failure.empty())
            {
                logFail(kName, failure);
                return;
            }
        }
    }
    logInfo(
        std::format("[info] {}: centre {:.1e} dB, cut+boost {:.1e} dB, SVF vs RBJ {:.1e} dB, "
                    "half-dB bandwidth rel {:.1e}\n",
                    kName,
                    errors.centre,
                    errors.inverse,
                    errors.form,
                    errors.bandwidth));
    if (!(errors.centre <= kExactDb) || !(errors.inverse <= kExactDb) ||
        !(errors.form <= kFormDb) || !(errors.bandwidth <= kBandwidthRel))
    {
        logFail(kName, "the shared bell is not exact (see the info line)");
        return;
    }
    logPass(kName);
}

// ---------------------------------------------------------------------------
// EQ_Ultrasonic_Property — above 20 kHz is a documented property (engine-plan §2.3): on the
// NAMED curves the response above 20.2 kHz stays ≤ the in-band peak + 1.5 dB (amendment 5:
// named curves only; an adversarial command exceeds it at +2.07 dB).
// ---------------------------------------------------------------------------
static auto testEqUltrasonicProperty() -> void
{
    static const char* const kName = "EQ_Ultrasonic_Property";
    constexpr double kMarginDb = 1.5;
    EqCurve edge{};
    edge[29] = -12.0F;
    edge[30] = 12.0F;
    EqCurve allUp{};
    allUp.fill(12.0F);
    const std::array<std::pair<const char*, EqCurve>, 5> named = {
        {
            {"+12 @ 20 kHz", eqFlatCurveWith(30U, 12.0F)},
            {"edge -12/+12 (16k/20k)", edge},
            {"all +12", allUp},
            {"alternating", eqAlternatingCurve()},
            {"Tone Air +12", eqToneCurve({0.0, 0.0, 0.0, 0.0, 12.0})},
        },
    };
    const std::vector<double> inBand = eqLogGrid(20.0, 20000.0, 4000);
    const auto peakOver = [](const GraphicEQDesign& design, const std::vector<double>& grid)
    {
        double peak = -std::numeric_limits<double>::infinity();
        for (const double hz : grid)
        {
            peak = std::max(peak, GraphicEQDesigner::playedDb(design, hz));
        }
        return peak;
    };
    auto designer = eqMakeDesigner();
    std::string report = std::format("[info] {}: max above 20.2 kHz vs in-band peak (dB)\n", kName);
    for (const double rate : kEqGateRates)
    {
        const std::vector<double> ultrasonic = eqLogGrid(20200.0, 0.999 * rate / 2.0, 2000);
        for (const auto& [name, curve] : named)
        {
            GraphicEQDesign design{};
            if (!designer->design(curve, rate, design))
            {
                logFail(kName, std::format("{} failed to design at {} Hz", name, rate));
                return;
            }
            const double inBandPeak = peakOver(design, inBand);
            const double above = peakOver(design, ultrasonic);
            if (rate == kEqGateRates.front())
            {
                report += std::format("[info]   44.1k {:24s} {:+.2f} vs {:+.2f} ({:+.2f})\n",
                                      name,
                                      above,
                                      inBandPeak,
                                      above - inBandPeak);
            }
            if (!(above <= inBandPeak + kMarginDb))
            {
                logInfo(report);
                logFail(kName,
                        std::format("{} @ {} Hz: {:+.2f} dB above 20.2 kHz vs in-band peak {:+.2f}",
                                    name,
                                    rate,
                                    above,
                                    inBandPeak));
                return;
            }
        }
    }
    logInfo(report);
    logPass(kName);
}

// ---------------------------------------------------------------------------
// EQ_Readback_MatchesIndependentEval — what the UI draws is what the coefficients play.
// ---------------------------------------------------------------------------
static auto testEqReadbackMatchesIndependentEval() -> void
{
    static const char* const kName = "EQ_Readback_MatchesIndependentEval";
    constexpr double kAnalyticDb = 1e-6;
    constexpr double kTimeDomainDb = 0.01;
    const std::array<std::pair<const char*, EqCurve>, 5> curves = {
        {
            {"Warm", kEqPresetCurves[kEqPresetWarm]},
            {"worst_cmd_44100", kEqWorstCmd44100},
            {"alternating", eqAlternatingCurve()},
            {"Tone B+6 Bo-3 P+4 A+6", eqToneCurve({6.0, -3.0, 0.0, 4.0, 6.0})},
            {"+12 @ 20 Hz", eqFlatCurveWith(0U, 12.0F)},
        },
    };
    // The time-domain check runs the first two curves at 48 and 96 kHz (it is the slow one).
    const std::vector<double> tones = {25.0, 100.0, 1000.0, 4000.0, 12500.0, 19000.0};
    const std::vector<double> uiGrid = eqUiGrid();
    auto designer = eqMakeDesigner();
    AsEqDesigner* abi = asEqDesignerCreate();
    if (abi == nullptr)
    {
        logFail(kName, "asEqDesignerCreate returned NULL");
        return;
    }
    double worstAnalytic = 0.0;
    double worstTimeDomain = 0.0;
    std::string failure;
    for (size_t r = 0; r < kEqGateRates.size() && failure.empty(); ++r)
    {
        const double rate = kEqGateRates[r];
        std::vector<double> grid = eqLogGrid(10.0, 0.49 * rate, 400);
        grid.insert(grid.end(), uiGrid.begin(), uiGrid.end());
        for (size_t c = 0; c < curves.size() && failure.empty(); ++c)
        {
            const auto& [name, curve] = curves[c];
            GraphicEQDesign design{};
            if (!designer->design(curve, rate, design))
            {
                failure = std::format("{} failed to design at {} Hz", name, rate);
                continue;
            }
            worstAnalytic = std::max(worstAnalytic, eqWorstAnalyticDelta(design, grid));
            if (const std::string abiFailure = eqAbiMatchesCpp(abi, curve, design, uiGrid);
                !abiFailure.empty())
            {
                failure = std::format("{} @ {} Hz: {}", name, rate, abiFailure);
            }
            if ((rate == 48000.0 || rate == 96000.0) && c < 2U)
            {
                worstTimeDomain = std::max(worstTimeDomain, eqWorstTimeDomainDelta(design, tones));
            }
        }
    }
    asEqDesignerDestroy(abi);
    if (!failure.empty())
    {
        logFail(kName, failure);
        return;
    }
    logInfo(
        std::format("[info] {}: vs complex RBJ product {:.1e} dB (≤ {:.0e}); vs time-domain "
                    "SVF {:.1e} dB (≤ {})\n",
                    kName,
                    worstAnalytic,
                    kAnalyticDb,
                    worstTimeDomain,
                    kTimeDomainDb));
    if (!(worstAnalytic <= kAnalyticDb) || !(worstTimeDomain <= kTimeDomainDb))
    {
        logFail(kName, "the read-back does not match what the coefficients play");
        return;
    }
    logPass(kName);
}

// ---------------------------------------------------------------------------
// EQ_Design_FlatFinite — flat is an exact identity; near-flat stays finite (the 1e-3 dB guard).
// ---------------------------------------------------------------------------
static auto testEqDesignFlatFinite() -> void
{
    static const char* const kName = "EQ_Design_FlatFinite";
    constexpr double kNearFlatBoundDb = 0.3; // +12/0 alternating plays 0.135 (the oracle's value)
    auto designer = eqMakeDesigner();
    EqCurve negativeZero{};
    negativeZero.fill(-0.0F);
    EqCurve oneZeroAmongSix{};
    oneZeroAmongSix.fill(6.0F);
    oneZeroAmongSix[15] = 0.0F;
    EqCurve tiny{};
    tiny.fill(1e-9F);
    EqCurve twelveAndZero{};
    for (size_t band = 0; band < kDesignBands; band += 2U)
    {
        twelveAndZero[band] = 12.0F;
    }
    const std::array<EqCurve, 4> nearFlat = {
        oneZeroAmongSix,
        tiny,
        twelveAndZero,
        eqFlatCurveWith(17U, 1e-4F),
    };
    // A default-constructed design (every m1 == 0) also reads back as the identity.
    const GraphicEQDesign defaultDesign;
    if (GraphicEQDesigner::playedDb(defaultDesign, 1000.0) != 0.0)
    {
        logFail(kName, "a default-constructed design does not read back 0 dB");
        return;
    }
    double worstNearFlat = 0.0;
    for (const double rate : kEqGateRates)
    {
        for (const EqCurve& flat : {EqCurve{}, negativeZero})
        {
            if (const std::string failure = eqFlatIsIdentity(*designer, flat, rate);
                !failure.empty())
            {
                logFail(kName, failure);
                return;
            }
        }
        const EqSetResult result = eqWorstCentreError(
            *designer, std::vector<EqCurve>(nearFlat.begin(), nearFlat.end()), rate);
        if (!result.failure.empty() || !(result.worstDb <= kNearFlatBoundDb))
        {
            logFail(kName,
                    std::format("near-flat @ {} Hz: {} (worst {:.4f} dB)",
                                rate,
                                result.failure,
                                result.worstDb));
            return;
        }
        worstNearFlat = std::max(worstNearFlat, result.worstDb);
    }
    logInfo(std::format("[info] {}: flat is exactly 0 dB at 6 rates; near-flat worst {:.4f} dB\n",
                        kName,
                        worstNearFlat));
    logPass(kName);
}

// ---------------------------------------------------------------------------
// EQ_Design_Rejects_NonFinite — the trust boundary (engine-plan §7, guard layers 1 and 2).
// ---------------------------------------------------------------------------
static auto testEqDesignRejectsNonFinite() -> void
{
    static const char* const kName = "EQ_Design_Rejects_NonFinite";
    constexpr double kNan = std::numeric_limits<double>::quiet_NaN();
    constexpr double kInf = std::numeric_limits<double>::infinity();
    auto designer = eqMakeDesigner();
    const EqCurve warm = kEqPresetCurves[kEqPresetWarm];

    // A rejected call leaves the caller's design untouched.
    GraphicEQDesign sentinel{};
    sentinel.sampleRate = 12345.0;
    sentinel.filterGainDb.fill(7.0);
    const auto rejects = [&](const EqCurve& curve, double rate)
    {
        GraphicEQDesign out = sentinel;
        return !designer->design(curve, rate, out) && eqSameDesign(out, sentinel);
    };
    for (const double bad : {kNan, kInf, -kInf})
    {
        for (const size_t band : {0U, 5U, 30U})
        {
            EqCurve curve = warm;
            curve[band] = static_cast<float>(bad);
            if (!rejects(curve, 48000.0))
            {
                logFail(kName, std::format("point {} = {} was not rejected cleanly", band, bad));
                return;
            }
        }
    }
    for (const double rate : {kNan, kInf, -kInf, 0.0, -48000.0, 43999.0, 768001.0, 1e9})
    {
        if (!rejects(warm, rate))
        {
            logFail(kName, std::format("sample rate {} was not rejected cleanly", rate));
            return;
        }
    }
    // The domain's ends design; after all the rejections the designer matches a fresh one.
    GraphicEQDesign edge{};
    GraphicEQDesign reused{};
    GraphicEQDesign fresh{};
    if (!designer->design(warm, GraphicEQDesigner::kMinSampleRateHz, edge) ||
        !designer->design(warm, GraphicEQDesigner::kMaxSampleRateHz, edge) ||
        !designer->design(warm, 48000.0, reused) ||
        !eqMakeDesigner()->design(warm, 48000.0, fresh) || !eqSameDesign(reused, fresh))
    {
        logFail(kName, "the domain's end rates failed, or a designer that rejected input drifted");
        return;
    }
    // Finite points beyond ±12 clamp to ±12 (not rejected).
    EqCurve beyond = warm;
    beyond[10] = 20.0F;
    beyond[20] = -30.0F;
    EqCurve clamped = warm;
    clamped[10] = 12.0F;
    clamped[20] = -12.0F;
    GraphicEQDesign beyondDesign{};
    GraphicEQDesign clampedDesign{};
    if (!designer->design(beyond, 48000.0, beyondDesign) ||
        !designer->design(clamped, 48000.0, clampedDesign) ||
        !eqSameDesign(beyondDesign, clampedDesign))
    {
        logFail(kName, "points beyond ±12 dB did not design as ±12 dB");
        return;
    }
    if (const std::string failure = eqAbiRejections(warm); !failure.empty())
    {
        logFail(kName, failure);
        return;
    }
    logPass(kName);
}

// ---------------------------------------------------------------------------
// Designer_TwoThreads — owner-local designers share nothing: two threads, each with its own
// designer and rate churn, reproduce the serial results bit-exactly (and race-free under tsan).
// ---------------------------------------------------------------------------
static auto testDesignerTwoThreads() -> void
{
    static const char* const kName = "Designer_TwoThreads";
    constexpr uint32_t kSeed = 77U;
    std::mt19937 rng(kSeed);
    const std::vector<EqCurve> setA = eqHardSet();
    const std::vector<EqCurve> setB = eqToneSet(rng, 40);
    const std::array<double, 2> ratesA = {48000.0, 44100.0};
    const std::array<double, 2> ratesB = {96000.0, 192000.0};
    const auto run = [](const std::vector<EqCurve>& curves,
                        const std::array<double, 2>& rates,
                        std::vector<GraphicEQDesign>& out)
    {
        auto designer = eqMakeDesigner();
        out.assign(curves.size(), GraphicEQDesign{});
        for (size_t i = 0; i < curves.size(); ++i)
        {
            if (!designer->design(curves[i], rates[i % rates.size()], out[i]))
            {
                out[i].sampleRate = -1.0; // marks a failure; never equals a real design
            }
        }
    };
    std::vector<GraphicEQDesign> serialA;
    std::vector<GraphicEQDesign> serialB;
    run(setA, ratesA, serialA);
    run(setB, ratesB, serialB);
    std::vector<GraphicEQDesign> threadA;
    std::vector<GraphicEQDesign> threadB;
    std::thread workerA([&] { run(setA, ratesA, threadA); });
    std::thread workerB([&] { run(setB, ratesB, threadB); });
    workerA.join();
    workerB.join();
    const auto matches =
        [](const std::vector<GraphicEQDesign>& serial, const std::vector<GraphicEQDesign>& threaded)
    {
        return std::ranges::equal(serial,
                                  threaded,
                                  [](const auto& lhs, const auto& rhs)
                                  { return lhs.sampleRate > 0.0 && eqSameDesign(lhs, rhs); });
    };
    if (!matches(serialA, threadA) || !matches(serialB, threadB))
    {
        logFail(kName, "a threaded design differs from the serial one (or failed)");
        return;
    }
    logPass(kName);
}

// ---------------------------------------------------------------------------
// Designer_Timing — one full design (5 refinement passes, warm per-rate cache) plus the UI's
// read-back (256 + 31 points). The plan measured ~95–135 µs per design in optimised C++; the M1
// budget is 0.25 ms (architect §2). The null test builds -O0 (and the sanitizers slow it
// further), so the 0.25 ms bound applies only to an optimised, uninstrumented build; the debug
// and sanitizer bounds only catch a gross regression. Serial-only: the pool would skew the clock.
// ---------------------------------------------------------------------------
static auto testDesignerTiming() -> void
{
    static const char* const kName = "Designer_Timing";
#if defined(__OPTIMIZE__) && !__has_feature(address_sanitizer) && !__has_feature(thread_sanitizer)
    constexpr double kBudgetMicros = 250.0;
    constexpr const char* kBuild = "optimised";
#elif __has_feature(address_sanitizer) || __has_feature(thread_sanitizer)
    constexpr double kBudgetMicros = 20000.0;
    constexpr const char* kBuild = "sanitizer";
#else
    constexpr double kBudgetMicros = 3000.0;
    constexpr const char* kBuild = "debug -O0";
#endif
    constexpr int kRounds = 200;
    const std::vector<EqCurve> curves = eqHardSet();
    const std::vector<double> uiGrid = eqUiGrid();
    std::vector<float> responseDb(uiGrid.size());
    auto designer = eqMakeDesigner();
    GraphicEQDesign design{};
    (void)designer->design(curves.front(), 48000.0, design); // warm the 48 kHz tables
    double sink = 0.0;
    const auto start = std::chrono::steady_clock::now();
    for (int round = 0; round < kRounds; ++round)
    {
        (void)designer->design(curves[static_cast<size_t>(round) % curves.size()], 48000.0, design);
        sink += design.filterGainDb[3];
    }
    const auto designed = std::chrono::steady_clock::now();
    for (int round = 0; round < kRounds; ++round)
    {
        (void)GraphicEQDesigner::playedResponseDb(design, uiGrid, responseDb);
        for (int band = 0; band < GraphicEQ::kBandCount; ++band)
        {
            sink += GraphicEQDesigner::playedDb(design, GraphicEQ::centreHz(band));
        }
    }
    const auto readBack = std::chrono::steady_clock::now();
    const double designMicros =
        std::chrono::duration<double, std::micro>(designed - start).count() / kRounds;
    const double readBackMicros =
        std::chrono::duration<double, std::micro>(readBack - designed).count() / kRounds;
    logInfo(
        std::format("[info] {} ({} build): design {:.1f} µs + read-back (256 + 31) {:.1f} µs "
                    "per call at 48 kHz (budget {:.0f} µs) [{:.1f}]\n",
                    kName,
                    kBuild,
                    designMicros,
                    readBackMicros,
                    kBudgetMicros,
                    sink));
    if (!(designMicros + readBackMicros <= kBudgetMicros))
    {
        logFail(kName,
                std::format("{:.1f} µs per design + read-back exceeds {:.0f} µs",
                            designMicros + readBackMicros,
                            kBudgetMicros));
        return;
    }
    logPass(kName);
}
