// FoldTests.inc
//
// The BS.775 fold in the spatial unit: the mix, the trim, the glide, keep-across-allocate, the backstop
// and its gain-reduction meter (level-and-fold §S1b, §S2, M1; US-R1F-08 items 1, 2 and 8).
// #included into Tests/DSPKernelNullTest.cpp after TestSupport.h, LoudnessOracleTests.inc (the libebur128
// true peak) and SoakRtAllocTests.inc (the render-thread allocation guard); its rows go in the kTests block
// marked "FoldTests.inc" there, so the two lanes never edit the same lines of the table.
//
// Every test drives the real SpatialRenderKernel. The 5.1 rows (`foldRows51`) are the design's BS.775-4
// Table 2 numbers written out as test data for the kernel's mechanics.

namespace
{
    constexpr uint32_t kFoldSR = 48000U;
    constexpr uint32_t kFoldBlock = 512U;
    constexpr uint32_t kFold51 = 6U;          // L R C LFE Ls Rs
    constexpr float kFoldSide = 0.70710678F;  // BS.775-4 Table 2: centre and one surround pair, −3.01 dB
    constexpr float kFoldToneHz = 997.0F;
    // The backstop's look-ahead at 48 kHz (LimiterModule: round(3 ms × fs)): the fold path's latency.
    constexpr uint32_t kFoldLatency = kLimiterLookaheadFrames;
    // dB per linear decade.
    constexpr double kFoldDb = 20.0;

    // The 5.1 fold's rows (L R C LFE Ls Rs), the LFE at `lfeGain` per side, at `trimDb`.
    auto foldRows51(float trimDb, float lfeGain = 0.0F) -> FoldParams
    {
        FoldParams fold;
        fold.inChannels = kFold51;
        fold.rows[0] = {1.0F, 0.0F, kFoldSide, lfeGain, kFoldSide, 0.0F, 0.0F, 0.0F};
        fold.rows[1] = {0.0F, 1.0F, kFoldSide, lfeGain, 0.0F, kFoldSide, 0.0F, 0.0F};
        fold.trimDb = trimDb;
        fold.lfeGain = lfeGain;
        fold.ceilingLinear = kTruePeakCeilingLinear;
        fold.fromPlan = true;
        return fold;
    }

    // A kernel at 48 kHz × 512, configured N → 2.
    auto makeFoldKernel(SpatialRenderKernel& kernel, uint32_t numIn) -> void
    {
        kernel.initialize(kFoldSR, kFoldBlock);
        kernel.configure(numIn, 2U);
    }

    // `blocks` blocks of `numIn` channels — channel ch, frame n (counted from the run's start) =
    // gen(ch, n) — through `kernel`; returns L′ and R′ concatenated.
    struct FoldOut
    {
        std::vector<float> left;
        std::vector<float> right;
    };
    auto runFold(SpatialRenderKernel& kernel,
                 uint32_t numIn,
                 uint32_t blocks,
                 const std::function<float(uint32_t, uint32_t)>& gen,
                 uint32_t startFrame = 0U) -> FoldOut
    {
        FoldOut out;
        TestABLN in(numIn, kFoldBlock);
        TestABLN outAbl(2U, kFoldBlock);
        for (uint32_t block = 0U; block < blocks; ++block)
        {
            for (uint32_t ch = 0U; ch < numIn; ++ch)
            {
                for (uint32_t i = 0U; i < kFoldBlock; ++i)
                {
                    in.channels[ch][i] = gen(ch, startFrame + (block * kFoldBlock) + i);
                }
            }
            kernel.process(MultichannelView::fromABL(in.abl(), kFoldBlock),
                           MultichannelView::fromABL(outAbl.abl(), kFoldBlock));
            out.left.insert(out.left.end(), outAbl.channels[0].begin(), outAbl.channels[0].end());
            out.right.insert(out.right.end(), outAbl.channels[1].begin(), outAbl.channels[1].end());
        }
        return out;
    }

    auto foldSine(float amplitude, uint32_t frame) -> float
    {
        return amplitude * std::sin(2.0F * std::numbers::pi_v<float> * kFoldToneHz * static_cast<float>(frame) /
                                    static_cast<float>(kFoldSR));
    }

    // RMS of `samples` from `from` on.
    auto foldRms(const std::vector<float>& samples, size_t from) -> double
    {
        double sum = 0.0;
        for (size_t i = from; i < samples.size(); ++i)
        {
            sum += static_cast<double>(samples[i]) * static_cast<double>(samples[i]);
        }
        return std::sqrt(sum / static_cast<double>(samples.size() - from));
    }

    auto foldDb(double ratio) -> double
    {
        return kFoldDb * std::log10(ratio);
    }

    // The output's true peak (libebur128, the oracle), dBTP.
    auto foldTruePeakDb(const FoldOut& out) -> double
    {
        std::vector<float> interleaved(out.left.size() * 2U);
        for (size_t i = 0U; i < out.left.size(); ++i)
        {
            interleaved[2U * i] = out.left[i];
            interleaved[(2U * i) + 1U] = out.right[i];
        }
        double linear = 0.0;
        if (!ebur128TruePeak(interleaved, kFoldSR, linear))
        {
            return std::numeric_limits<double>::quiet_NaN();
        }
        return foldDb(linear);
    }

    // C_work (design §1.1): 20·log10(ceiling × kIspSafetyMargin) − 0.01 dB.
    auto foldWorkingCeilingDb(float ceilingLinear) -> double
    {
        return foldDb(static_cast<double>(ceilingLinear) * kIspSafetyMargin) - 0.01;
    }
} // namespace

// ---------------------------------------------------------------------------
// Fold_Matrix_CentreAndInPhase — US-R1F-08 item 1: a centre-only sine folds to −3.0 dB per side; a sine
// at equal level and phase in L, R and C sums to +4.6 dB per side (1 + 0.7071). The backstop sleeps.
// ---------------------------------------------------------------------------
static auto testFoldMatrixCentreAndInPhase() -> void
{
    static const char* const kName = "Fold_Matrix_CentreAndInPhase";
    constexpr float kAmplitude = 0.1F;
    constexpr double kTolDb = 0.1;
    std::string fail;
    struct Case
    {
        const char* name;
        std::array<bool, kFold51> carries; // which of L R C LFE Ls Rs carry the sine
        double expectedDb;
    };
    const std::array cases{
        Case{.name = "centre only", .carries = {false, false, true, false, false, false}, .expectedDb = -3.0103},
        Case{.name = "L = R = C", .carries = {true, true, true, false, false, false}, .expectedDb = 4.6421},
    };
    for (const Case& each : cases)
    {
        SpatialRenderKernel kernel;
        makeFoldKernel(kernel, kFold51);
        (void)kernel.publishFold(foldRows51(0.0F));
        const FoldOut out = runFold(kernel, kFold51, 40U, [&](uint32_t ch, uint32_t n)
                                    { return each.carries[ch] ? foldSine(kAmplitude, n) : 0.0F; });
        const double inputRms = static_cast<double>(kAmplitude) / std::numbers::sqrt2;
        for (const auto* side : {&out.left, &out.right})
        {
            const double gotDb = foldDb(foldRms(*side, kFoldBlock) / inputRms);
            if (std::fabs(gotDb - each.expectedDb) > kTolDb)
            {
                fail += std::format("\n  {}: a side at {:.3f} dB, expected {:.3f} ±{}", each.name, gotDb,
                                    each.expectedDb, kTolDb);
            }
        }
        if (kernel.readout().backstopPeakGrDb > 0.0F)
        {
            fail += std::format("\n  {}: the backstop acted ({} dB)", each.name, kernel.readout().backstopPeakGrDb);
        }
    }
    if (!fail.empty())
    {
        logFail(kName, fail);
        return;
    }
    logPass(kName);
}

// ---------------------------------------------------------------------------
// Fold_StereoIn51_Null — US-R1F-08 item 1: a stereo programme in a 5.1 container (C, LFE, Ls, Rs silent)
// folds to EXACTLY its own L and R at trim 0 — the only change the backstop's look-ahead delay.
// ---------------------------------------------------------------------------
static auto testFoldStereoIn51Null() -> void
{
    static const char* const kName = "Fold_StereoIn51_Null";
    SpatialRenderKernel kernel;
    makeFoldKernel(kernel, kFold51);
    (void)kernel.publishFold(foldRows51(0.0F));
    std::mt19937 gen(0xF01DU);
    std::uniform_real_distribution<float> dist(-0.25F, 0.25F);
    constexpr uint32_t kBlocks = 20U;
    std::vector<std::array<float, 2>> program(static_cast<size_t>(kBlocks) * kFoldBlock);
    for (auto& frame : program)
    {
        frame = {dist(gen), dist(gen)};
    }
    const FoldOut out = runFold(kernel, kFold51, kBlocks,
                                [&](uint32_t ch, uint32_t n) { return ch < 2U ? program[n][ch] : 0.0F; });
    for (size_t i = 0U; i + kFoldLatency < out.left.size(); ++i)
    {
        if (out.left[i + kFoldLatency] != program[i][0] || out.right[i + kFoldLatency] != program[i][1])
        {
            logFail(kName, std::format("frame {}: ({}, {}) != the stereo input ({}, {})", i, out.left[i + kFoldLatency],
                                       out.right[i + kFoldLatency], program[i][0], program[i][1]));
            return;
        }
    }
    logPass(kName);
}

// ---------------------------------------------------------------------------
// Fold_Trim_Scales — US-R1F-08 item 2: the per-track trim scales the fold: a centre-only sine at trim
// −6 dB plays at −3.01 − 6 dB per side.
// ---------------------------------------------------------------------------
static auto testFoldTrimScales() -> void
{
    static const char* const kName = "Fold_Trim_Scales";
    constexpr float kAmplitude = 0.1F;
    constexpr float kTrimDb = -6.0F;
    SpatialRenderKernel kernel;
    makeFoldKernel(kernel, kFold51);
    (void)kernel.publishFold(foldRows51(kTrimDb));
    const FoldOut out = runFold(kernel, kFold51, 40U,
                                [&](uint32_t ch, uint32_t n) { return ch == 2U ? foldSine(kAmplitude, n) : 0.0F; });
    const double gotDb = foldDb(foldRms(out.left, kFoldBlock) / (static_cast<double>(kAmplitude) / std::numbers::sqrt2));
    const double expected = -3.0103 + static_cast<double>(kTrimDb);
    if (std::fabs(gotDb - expected) > 0.01)
    {
        logFail(kName, std::format("a side at {:.4f} dB, expected {:.4f}", gotDb, expected));
        return;
    }
    if (std::fabs(kernel.readout().trimDb - kTrimDb) > 0.0F)
    {
        logFail(kName, std::format("the read-out says trim {} dB", kernel.readout().trimDb));
        return;
    }
    logPass(kName);
}

// ---------------------------------------------------------------------------
// Fold_Glide_OnePoleThenExact — a change glides as the effects unit's gain does (NI-4; review N16): per
// sample, one one-pole step at τ = `glideSeconds` — the trim in dB, as EQModule moves its output gain —
// before the sample plays; settled, it lands exactly on the new fold; a set with no glide snaps. (Constant
// input: the output IS the coefficient.)
// ---------------------------------------------------------------------------
static auto testFoldGlideOnePoleThenExact() -> void
{
    static const char* const kName = "Fold_Glide_OnePoleThenExact";
    constexpr float kLevel = 0.1F;
    constexpr float kGlideSeconds = 0.01F; // τ = 480 frames
    constexpr double kTrimDb = -6.0;
    constexpr double kDbToNeper = 0.11512925464970228; // ln(10) / 20
    constexpr uint32_t kBlocks = 30U;                  // past the settle (~21 τ to 1e-9)
    SpatialRenderKernel kernel;
    makeFoldKernel(kernel, kFold51);
    (void)kernel.publishFold(foldRows51(0.0F));
    const auto centre = [&](uint32_t ch, uint32_t) { return ch == 2U ? kLevel : 0.0F; };
    (void)runFold(kernel, kFold51, 2U, centre);
    FoldParams lower = foldRows51(static_cast<float>(kTrimDb));
    lower.glideSeconds = kGlideSeconds;
    (void)kernel.publishFold(lower);
    const FoldOut out = runFold(kernel, kFold51, kBlocks, centre, 2U * kFoldBlock);

    // The coefficient is row × the trim's amplitude, and a sample plays as input × coefficient.
    const auto played = [&](double trimDb)
    {
        return kLevel * static_cast<float>(static_cast<double>(kFoldSide) * std::exp(trimDb * kDbToNeper));
    };
    const double alpha =
        1.0 - std::exp(-1.0 / (static_cast<double>(kGlideSeconds) * static_cast<double>(kFoldSR)));
    std::string fail;
    // The glide reaches the output kFoldLatency frames late (the backstop's look-ahead).
    double trimDb = 0.0;
    size_t landed = out.left.size();
    for (size_t i = kFoldLatency; i < out.left.size(); ++i)
    {
        trimDb += alpha * (kTrimDb - trimDb);
        const float expected = played(trimDb);
        if (std::fabs(out.left[i] - expected) > 1.0e-6F)
        {
            fail += std::format("\n  glide frame {}: {} expected {}", i - kFoldLatency, out.left[i], expected);
            break;
        }
        if (landed == out.left.size() && out.left[i] == played(kTrimDb))
        {
            landed = i;
        }
    }
    const float after = played(kTrimDb);
    if (landed - kFoldLatency < static_cast<size_t>(3.0 * static_cast<double>(kGlideSeconds) * kFoldSR))
    {
        fail += std::format("\n  landed after {} frames: not a one-pole at τ {} s", landed - kFoldLatency,
                            kGlideSeconds);
    }
    for (size_t i = out.left.size() - kFoldBlock; i < out.left.size(); ++i)
    {
        if (out.left[i] != after)
        {
            fail += std::format("\n  settled, frame {}: {} != {} exactly", i, out.left[i], after);
            break;
        }
    }
    // A set with no glide snaps: the very first delayed frame plays it.
    (void)kernel.publishFold(foldRows51(0.0F));
    const FoldOut snapped = runFold(kernel, kFold51, 1U, centre, (2U + kBlocks) * kFoldBlock);
    if (snapped.left[kFoldLatency] != played(0.0))
    {
        fail += std::format("\n  a snap played {} first, not {}", snapped.left[kFoldLatency], played(0.0));
    }
    if (!fail.empty())
    {
        logFail(kName, fail);
        return;
    }
    logPass(kName);
}

// ---------------------------------------------------------------------------
// Fold_KeepAcrossAllocate — M1: the unit keeps its last fold across an allocate at the same width; at a
// width it has no fold for it plays silence, never the first two channels; the layout's fold for the new
// width plays at its worst-case trim — never trim 0.
// ---------------------------------------------------------------------------
static auto testFoldKeepAcrossAllocate() -> void
{
    static const char* const kName = "Fold_KeepAcrossAllocate";
    constexpr float kLevel = 0.1F;
    std::string fail;
    SpatialRenderKernel kernel;
    makeFoldKernel(kernel, kFold51);
    (void)kernel.publishFold(foldRows51(-3.0F));
    const auto centre = [&](uint32_t ch, uint32_t) { return ch == 2U ? kLevel : 0.0F; };
    (void)runFold(kernel, kFold51, 2U, centre);

    kernel.configure(kFold51, 2U); // a re-allocation at the same width: no new set
    FoldOut out = runFold(kernel, kFold51, 2U, centre);
    const float planned = kLevel * (kFoldSide * std::pow(10.0F, -3.0F / 20.0F));
    if (std::fabs(out.left.back() - planned) > 1.0e-6F || !kernel.readout().fromPlan)
    {
        fail += std::format("\n  same width: {} (from plan: {}), expected the published {}", out.left.back(),
                            kernel.readout().fromPlan, planned);
    }

    // 8 channels now, and the fold in force is for 6: silence, not L and R.
    constexpr uint32_t kSeven1 = 8U;
    kernel.configure(kSeven1, 2U);
    out = runFold(kernel, kSeven1, 2U, [](uint32_t, uint32_t) { return 0.5F; });
    if (std::ranges::any_of(out.left, [](float sample) { return sample != 0.0F; }))
    {
        fail += "\n  a width with no fold played something, not silence";
    }

    // The layout's fold for the new width: its worst-case trim.
    constexpr float kWorstCaseTrimDb = -9.93F; // 7.1 at 0.5 surrounds on Bluetooth (design §4)
    FoldParams layout;
    layout.inChannels = kSeven1;
    layout.rows[0] = {1.0F, 0.0F, kFoldSide, 0.0F, 0.5F, 0.0F, 0.5F, 0.0F};
    layout.rows[1] = {0.0F, 1.0F, kFoldSide, 0.0F, 0.0F, 0.5F, 0.0F, 0.5F};
    layout.trimDb = kWorstCaseTrimDb;
    (void)kernel.publishFold(layout);
    out = runFold(kernel, kSeven1, 2U, centre);
    const float worstCase = kLevel * (kFoldSide * std::pow(10.0F, kWorstCaseTrimDb / 20.0F));
    if (std::fabs(out.left.back() - worstCase) > 1.0e-6F || kernel.readout().fromPlan)
    {
        fail += std::format("\n  the layout's fold: {} (from plan: {}), expected the worst-case {}", out.left.back(),
                            kernel.readout().fromPlan, worstCase);
    }
    if (!fail.empty())
    {
        logFail(kName, fail);
        return;
    }
    logPass(kName);
}

// ---------------------------------------------------------------------------
// Fold_Backstop_HoldsAndMeters — US-R1F-08 items 2 and 8: an in-phase 5.1 overload (every main at
// −6 dBFS: the fold reaches 0.5 × 2.414 = +1.64 dBFS) at trim 0 — the backstop holds the output under its
// ceiling (libebur128's true peak ≤ −1 dBTP + 0.1), and its meter reads the gain it applied (the steady
// output against the fold's 1.207 peak) within 0.05 dB. At the trim C_work − TP_F it sleeps: GR 0.
// ---------------------------------------------------------------------------
static auto testFoldBackstopHoldsAndMeters() -> void
{
    static const char* const kName = "Fold_Backstop_HoldsAndMeters";
    constexpr float kAmplitude = 0.5F;
    const auto mains = [&](uint32_t ch, uint32_t n) { return ch == 3U ? 0.0F : foldSine(kAmplitude, n); };
    std::string fail;

    SpatialRenderKernel hot;
    makeFoldKernel(hot, kFold51);
    (void)hot.publishFold(foldRows51(0.0F));
    const FoldOut limited = runFold(hot, kFold51, 200U, mains);
    const double tp = foldTruePeakDb(limited);
    if (!(tp <= -1.0 + 0.1))
    {
        fail += std::format("\n  trim 0: the output reaches {:.2f} dBTP over a −1 dBTP backstop", tp);
    }
    const double foldPeak = static_cast<double>(kAmplitude) * (1.0 + (2.0 * static_cast<double>(kFoldSide)));
    double steadyPeak = 0.0;
    for (size_t i = limited.left.size() / 2U; i < limited.left.size(); ++i)
    {
        steadyPeak = std::max(steadyPeak, static_cast<double>(std::fabs(limited.left[i])));
    }
    const double appliedDb = foldDb(foldPeak / steadyPeak);
    const auto metered = static_cast<double>(hot.readout().backstopPeakGrDb);
    if (std::fabs(metered - appliedDb) > 0.05)
    {
        fail += std::format("\n  the meter reads {:.3f} dB; the gain applied is {:.3f} dB", metered, appliedDb);
    }

    SpatialRenderKernel trimmed;
    makeFoldKernel(trimmed, kFold51);
    const double trimDb = std::min(0.0, foldWorkingCeilingDb(kTruePeakCeilingLinear) - foldDb(foldPeak));
    (void)trimmed.publishFold(foldRows51(static_cast<float>(trimDb)));
    const FoldOut asleep = runFold(trimmed, kFold51, 200U, mains);
    if (trimmed.readout().backstopPeakGrDb >= 0.01F)
    {
        fail += std::format("\n  at trim {:.2f} dB the backstop still reduced {} dB", trimDb,
                            trimmed.readout().backstopPeakGrDb);
    }
    logInfo(std::format("{}: trim 0 → output {:.2f} dBTP, metered GR {:.3f} dB (applied {:.3f}); trim {:.2f} dB → "
                        "GR {:.4f} dB, output {:.2f} dBTP",
                        kName, tp, metered, appliedDb, trimDb, trimmed.readout().backstopPeakGrDb,
                        foldTruePeakDb(asleep)));
    if (!fail.empty())
    {
        logFail(kName, fail);
        return;
    }
    logPass(kName);
}

// ---------------------------------------------------------------------------
// Fold_RejectsNonFinite — a fold with a NaN or an infinity is never published; the one in force plays on.
// ---------------------------------------------------------------------------
static auto testFoldRejectsNonFinite() -> void
{
    static const char* const kName = "Fold_RejectsNonFinite";
    SpatialRenderKernel kernel;
    makeFoldKernel(kernel, kFold51);
    std::string fail;
    if (!kernel.publishFold(foldRows51(-2.0F)))
    {
        fail += "\n  a finite fold was refused";
    }
    FoldParams bad = foldRows51(0.0F);
    bad.rows[0][2] = std::numeric_limits<float>::quiet_NaN();
    FoldParams badTrim = foldRows51(std::numeric_limits<float>::infinity());
    if (kernel.publishFold(bad) || kernel.publishFold(badTrim))
    {
        fail += "\n  a non-finite fold was accepted";
    }
    const FoldOut out = runFold(kernel, kFold51, 2U, [](uint32_t ch, uint32_t) { return ch == 2U ? 0.1F : 0.0F; });
    if (!std::ranges::all_of(out.left, [](float sample) { return std::isfinite(sample); }) ||
        std::fabs(kernel.readout().trimDb + 2.0F) > 0.0F)
    {
        fail += "\n  the fold in force did not play on";
    }
    if (!fail.empty())
    {
        logFail(kName, fail);
        return;
    }
    logPass(kName);
}

// ---------------------------------------------------------------------------
// Fold_NoRenderThreadAllocation — the fold path (a glide, the backstop at work, its meter) allocates
// nothing on the render thread.
// ---------------------------------------------------------------------------
static auto testFoldNoRenderThreadAllocation() -> void
{
    static const char* const kName = "Fold_NoRenderThreadAllocation";
    SpatialRenderKernel kernel;
    makeFoldKernel(kernel, kFold51);
    FoldParams fold = foldRows51(0.0F);
    fold.glideSeconds = 0.05F;
    (void)kernel.publishFold(fold);
    TestABLN in(kFold51, kFoldBlock);
    TestABLN out(2U, kFoldBlock);
    for (uint32_t ch = 0U; ch < kFold51; ++ch)
    {
        for (uint32_t i = 0U; i < kFoldBlock; ++i)
        {
            in.channels[ch][i] = foldSine(0.6F, i); // hot: the backstop works
        }
    }
    uint64_t allocations = 0U;
    {
        const RtGuardScope guard;
        for (uint32_t block = 0U; block < 200U; ++block)
        {
            kernel.process(MultichannelView::fromABL(in.abl(), kFoldBlock), MultichannelView::fromABL(out.abl(), kFoldBlock));
        }
        allocations = RtGuardScope::count();
    }
    if (allocations != 0U)
    {
        logFail(kName, std::format("{} allocation(s) on the render thread", allocations));
        return;
    }
    logPass(kName);
}

// ---------------------------------------------------------------------------
// Fold_ConcurrentPublish_NoTear — two control threads publish folds while the render runs: every block
// plays one whole published fold (each fold's rows and trim give a distinct steady level), never a mix.
// Under TSan (make tsan) this also proves the publish side serializes and the snapshot hands over cleanly.
// ---------------------------------------------------------------------------
static auto testFoldConcurrentPublishNoTear() -> void
{
    static const char* const kName = "Fold_ConcurrentPublish_NoTear";
    constexpr float kLevel = 0.1F;
    constexpr uint32_t kFolds = 8U;
    SpatialRenderKernel kernel;
    makeFoldKernel(kernel, kFold51);
    std::array<float, kFolds> levels{};
    for (uint32_t k = 0U; k < kFolds; ++k)
    {
        levels[k] = kFoldSide * kLevel * std::pow(10.0F, -static_cast<float>(k) / 20.0F);
    }
    (void)kernel.publishFold(foldRows51(0.0F));
    std::atomic<bool> stop{false};
    const auto publisher = [&](uint32_t offset)
    {
        uint32_t k = offset;
        while (!stop.load(std::memory_order_relaxed))
        {
            (void)kernel.publishFold(foldRows51(-static_cast<float>(k % kFolds)));
            k += 2U;
        }
    };
    std::thread first(publisher, 0U);
    std::thread second(publisher, 1U);
    TestABLN in(kFold51, kFoldBlock);
    TestABLN out(2U, kFoldBlock);
    in.channels[2].assign(kFoldBlock, kLevel);
    std::string fail;
    for (uint32_t block = 0U; block < 2000U && fail.empty(); ++block)
    {
        kernel.process(MultichannelView::fromABL(in.abl(), kFoldBlock), MultichannelView::fromABL(out.abl(), kFoldBlock));
        const float last = out.channels[0].back();
        const bool known =
            block == 0U || std::ranges::any_of(levels, [&](float level) { return std::fabs(level - last) < 1.0e-6F; });
        if (!known || !std::isfinite(last))
        {
            fail = std::format("block {}: a steady level {} that no published fold plays", block, last);
        }
    }
    stop.store(true, std::memory_order_relaxed);
    first.join();
    second.join();
    if (!fail.empty())
    {
        logFail(kName, fail);
        return;
    }
    logPass(kName);
}
