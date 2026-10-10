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
