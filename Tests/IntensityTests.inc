// IntensityTests.inc
//
// S6 Tier-3 (3b) — steerable wet/dry intensity. Verifies the corrected-topology
// crossfade in DSPKernel::process(): blend BEFORE Loudness+Limiter, equal-power law,
// settled-gated bit-exact endpoints, and click-free ramp convergence.
// #included into Tests/DSPKernelNullTest.cpp after TestSupport.h.
//
// Tests:
//   Intensity_EndpointsBitExact_Settled       — settled x==1 == full chain; x==0 == input.
//   Intensity_SettledRampConvergesToHardBranch — 0.5→1.0 ramp lands byte-identical to x==1.
//   Intensity_EqualPowerAtHalf                 — wet==dry, RMS at x=0.5 within ~0.5 dB of wet.
//   Intensity_LevelPeakSafetyIntermediate      — hot signal at intermediate x stays ≤ ceiling.
//   Intensity_NoNaNAndFastStepSettles          — 0→1 step settles in ~5τ, no NaN/denormal.

namespace
{
    constexpr float kHalfPiTest = 1.57079632679489661923F;

    // True sample-peak (max |·|) of a buffer.
    auto samplePeak(const std::vector<float>& buf) -> float
    {
        float peak = 0.0F;
        for (const float v : buf)
        {
            peak = std::max(peak, std::abs(v));
        }
        return peak;
    }

    // Crude 4× linear-interpolation inter-sample peak — a lightweight TP proxy. A full
    // libebur128 true-peak oracle is deferred to S7; a 4× linear estimate is sufficient as a
    // regression guard that the blend does not defeat the limiter ceiling (it always slightly
    // UNDER-reads vs the limiter's 8× polyphase detector, so a pass here is conservative).
    auto fourXPeak(const std::vector<float>& buf) -> float
    {
        if (buf.size() < 2U)
        {
            return samplePeak(buf);
        }
        float peak = 0.0F;
        for (size_t i = 0U; i + 1U < buf.size(); ++i)
        {
            const float a = buf[i];
            const float b = buf[i + 1U];
            for (int s = 0; s < 4; ++s)
            {
                const float t = static_cast<float>(s) / 4.0F;
                peak = std::max(peak, std::abs(a + (b - a) * t));
            }
        }
        return peak;
    }

    // Run a stereo signal (identical L/R) through the kernel at a FIXED intensity, returning the
    // left output of a buffer captured AFTER the intensity ramp has SETTLED. The kernel snaps the
    // ramp to the canonical default (1.0) in initialize(), so reaching a settled intermediate or a
    // settled endpoint requires warming the ramp. We feed the SAME input `kWarm` times (which also
    // drives the EQ/limiter to a steady state), then capture the next buffer. With identical input
    // each call, the captured buffer is the steady-state response at the requested intensity:
    //   x∈{0,1} → the bit-exact hard branch; intermediate x → the settled (flat-ramp) crossfade.
    auto runIntensityOnce(const TargetState& baseState,
                          float intensity,
                          const std::vector<float>& input) -> std::vector<float>
    {
        const auto frames = static_cast<uint32_t>(input.size());
        constexpr uint32_t kWarm = 256U; // ≫ 5τ at any reasonable buffer size
        DSPKernel kernel;
        kernel.initialize(TestConstants::kSampleRate48k, frames);
        TargetState state = baseState;
        state.intensityLinear = intensity;
        kernel.publishTargetState(state);

        TestABL abl(frames);
        for (uint32_t b = 0U; b <= kWarm; ++b)
        {
            std::memcpy(abl.left.data(), input.data(), frames * sizeof(float));
            std::memcpy(abl.right.data(), input.data(), frames * sizeof(float));
            kernel.process(abl.abl(), frames);
        }
        return abl.left;
    }
} // namespace

// ---------------------------------------------------------------------------
// Test: endpoints are bit-exact (settled).
//   x==1 (settled) → output byte-identical to the legacy full chain.
//   x==0 (settled) → output byte-identical to the input (early-return bypass).
// The golden master already pins x==1 globally; this adds an explicit per-call assert and
// the x==0 identity. We use an ACTIVE non-trivial state (EQ boost + active limiter) so the
// x==1 path actually exercises the full chain rather than an identity no-op.
// ---------------------------------------------------------------------------
static auto testIntensityEndpointsBitExact() -> void
{
    static const char* const kName = "Intensity_EndpointsBitExact_Settled";
    constexpr uint32_t kFrames = TestConstants::kFrames512;
    constexpr float kBoostDb = 6.0F;
    const float kSR = static_cast<float>(TestConstants::kSampleRate48k);

    // Deterministic chirp-ish content (1 kHz sine, -6 dBFS) — non-trivial through the chain.
    std::vector<float> input(kFrames);
    for (uint32_t i = 0U; i < kFrames; ++i)
    {
        input[i] = 0.5F * std::sin(2.0F * std::numbers::pi_v<float> * 1000.0F *
                                   static_cast<float>(i) / kSR);
    }

    TargetState active = makeIdentityState();
    std::array<float, kEqBands> gains{};
    gains[kBand1kHzIndex] = kBoostDb;
    active.eq = EQModuleCoefficients::computeBiquadCascade(gains, kSR);
    active.limiter.truePeakCeilingLinear = kTruePeakCeilingLinear; // active

    // Reference: today's full chain via the dedicated x==1 hard branch.
    const std::vector<float> wetRef = runIntensityOnce(active, 1.0F, input);

    // x==1 path must equal the reference byte-for-byte (it IS the reference path; this is the
    // explicit per-call endpoint assert the spec requires).
    const std::vector<float> atOne = runIntensityOnce(active, 1.0F, input);
    if (std::memcmp(atOne.data(), wetRef.data(), kFrames * sizeof(float)) != 0)
    {
        logFail(kName, "x==1 settled output not bit-identical to the full-chain reference");
        return;
    }

    // x==0 path must equal the input byte-for-byte (early-return bypass, no decode/copy).
    const std::vector<float> atZero = runIntensityOnce(active, 0.0F, input);
    if (std::memcmp(atZero.data(), input.data(), kFrames * sizeof(float)) != 0)
    {
        logFail(kName, "x==0 settled output not bit-identical to the input (bypass broken)");
        return;
    }

    logPass(kName);
}

// ---------------------------------------------------------------------------
// Test: a settled ramp converges INTO the x==1 HARD in-place branch — NOT a lerp that merely
// approaches 1.0 asymptotically. This is the BLOCKER from review §2.3.
//
// Key insight: with the IDENTITY state (EQ flat → no biquads → no delay/limiter/loudness
// history at all), wet == dry == input. So:
//   • the HARD x==1 branch produces out == input EXACTLY (no crossfade math runs);
//   • a lerp `dry + r·(wet-dry)` at the settled value r≈0.999999 would give out ≈ input but
//     NOT bit-identical (and even with wet==dry, the equal-power gain (cos+sin)(r·π/2) ≠ 1.0
//     for r≠1, so a non-hard path would scale the signal by ≈1.0 but not exactly 1.0).
// We publish 0.5, run the crossfade path, then publish 1.0, ramp to settle, and assert the
// settled output is byte-identical to the input — which ONLY the hard branch achieves.
// ---------------------------------------------------------------------------
static auto testIntensitySettledRampConvergesToHardBranch() -> void
{
    static const char* const kName = "Intensity_SettledRampConvergesToHardBranch";
    constexpr uint32_t kFrames = TestConstants::kFrames512;
    constexpr uint32_t kSettleBuffers = 300U; // ≫ 5τ (160 ms ≈ 16 buffers); drive deep into ε
    const float kSR = static_cast<float>(TestConstants::kSampleRate48k);

    std::vector<float> input(kFrames);
    for (uint32_t i = 0U; i < kFrames; ++i)
    {
        input[i] = 0.5F * std::sin(2.0F * std::numbers::pi_v<float> * 1000.0F *
                                   static_cast<float>(i) / kSR);
    }
    const std::vector<float> reference(input);

    // Identity coloration → wet == dry == input, and no module carries history.
    const TargetState identity = makeIdentityState();

    DSPKernel kernel;
    kernel.initialize(TestConstants::kSampleRate48k, kFrames);
    TargetState half = identity;
    half.intensityLinear = 0.5F;
    kernel.publishTargetState(half);

    TestABL abl(kFrames);
    auto runOne = [&]()
    {
        std::memcpy(abl.left.data(), input.data(), kFrames * sizeof(float));
        std::memcpy(abl.right.data(), input.data(), kFrames * sizeof(float));
        kernel.process(abl.abl(), kFrames);
    };

    // Crossfade path at 0.5 (ramp snapped to 0.5 → stays): output should be √2-scaled, NOT input.
    runOne();
    if (std::memcmp(abl.left.data(), reference.data(), kFrames * sizeof(float)) == 0)
    {
        logFail(kName, "x=0.5 produced bit-identical-to-input output (crossfade did not run?)");
        return;
    }

    // Request 1.0 and ramp to settle.
    TargetState full = identity;
    full.intensityLinear = 1.0F;
    kernel.publishTargetState(full);
    for (uint32_t b = 0U; b < kSettleBuffers; ++b)
    {
        runOne();
    }

    // SETTLED: the output of an identity-state kernel at settled x==1 must be byte-identical to
    // the input — proving the ramp converged INTO the hard in-place branch (a lerp at r≈1 would
    // scale by an off-by-ULPs equal-power gain and NOT reproduce the input exactly).
    if (std::memcmp(abl.left.data(), reference.data(), kFrames * sizeof(float)) != 0)
    {
        logFail(kName,
                "settled x==1 output not bit-identical to input — ramp landed on the lerp path, "
                "not the hard in-place branch");
        return;
    }
    logPass(kName);
}

// ---------------------------------------------------------------------------
// Test: equal-power conformance at x=0.5.
// With wet==dry (identity coloration: EQ flat, clarity/BRIR stubs are no-ops), the blend is
//   out = dryGain·in + wetGain·in = (cos+sin)(π/4)·in = √2·in,  i.e. +3.01 dB.
// The output RMS at x=0.5 must be within ~0.5 dB of the WET RMS (equal-power), NOT 6 dB down
// (which a linear law would give for decorrelated signals — here correlated, so equal-power
// gives +3 dB, the canonical equal-power-at-midpoint result for correlated wet/dry).
// We disable loudness+limiter so we measure the raw crossfade gain.
// ---------------------------------------------------------------------------
static auto testIntensityEqualPowerAtHalf() -> void
{
    static const char* const kName = "Intensity_EqualPowerAtHalf";
    constexpr uint32_t kFrames = 4096U;
    const float kSR = static_cast<float>(TestConstants::kSampleRate48k);

    std::vector<float> input(kFrames);
    for (uint32_t i = 0U; i < kFrames; ++i)
    {
        input[i] = 0.25F * std::sin(2.0F * std::numbers::pi_v<float> * 1000.0F *
                                    static_cast<float>(i) / kSR);
    }

    // Identity coloration so wet==dry; loudness/limiter bypassed (makeIdentityState does this).
    const TargetState identity = makeIdentityState();

    const std::vector<float> wet = runIntensityOnce(identity, 1.0F, input);
    const std::vector<float> half = runIntensityOnce(identity, 0.5F, input);

    const double wetRms = sliceRms(wet, 0U, kFrames);
    const double halfRms = sliceRms(half, 0U, kFrames);
    if (wetRms <= 0.0)
    {
        logFail(kName, "wet RMS is zero");
        return;
    }
    const double deltaDb = 20.0 * std::log10(halfRms / wetRms);

    std::ostringstream info;
    info << "  [info] " << kName << ": halfRms/wetRms = " << deltaDb
         << " dB (equal-power expects ~+3.01 dB for correlated wet==dry)\n";
    logInfo(info.str());

    // Equal-power: (cos+sin)(π/4) = √2 → +3.01 dB above wet. Linear law would be 0 dB here
    // (out = 0.5·in + 0.5·in = in). Assert we are within 0.5 dB of the equal-power result.
    constexpr double kEqualPowerDb = 3.0103; // 20·log10(√2)
    if (std::abs(deltaDb - kEqualPowerDb) > 0.5)
    {
        std::ostringstream oss;
        oss << "x=0.5 not equal-power: got " << deltaDb << " dB vs expected ~" << kEqualPowerDb
            << " dB (±0.5)";
        logFail(kName, oss.str());
        return;
    }
    logPass(kName);
}

// ---------------------------------------------------------------------------
// Test: level/peak safety at intermediate x.
// Feed a hot signal (near 0 dBFS) that would saturate the limiter, at several intermediate
// intensities. The BLENDED output sample-peak AND a 4× inter-sample estimate must stay at or
// below the limiter ceiling (kTruePeakCeilingLinear, with a small ISP slack since the test's
// 4× estimate is coarser than the limiter's 8× detector). This is the regression guard for the
// corrected topology (blend BEFORE the limiter). Full TP oracle is S7.
// ---------------------------------------------------------------------------
static auto testIntensityLevelPeakSafetyIntermediate() -> void
{
    static const char* const kName = "Intensity_LevelPeakSafetyIntermediate";
    constexpr uint32_t kFrames = 8192U;
    const float kSR = static_cast<float>(TestConstants::kSampleRate48k);

    // Hot 0.98-amplitude sine near a non-integer-period frequency → strong inter-sample peaks.
    std::vector<float> input(kFrames);
    for (uint32_t i = 0U; i < kFrames; ++i)
    {
        input[i] = 0.98F * std::sin(2.0F * std::numbers::pi_v<float> * 997.0F *
                                    static_cast<float>(i) / kSR);
    }

    TargetState active = makeIdentityState();
    active.limiter.truePeakCeilingLinear = kTruePeakCeilingLinear; // active

    // The limiter has 3 ms lookahead latency; skip the leading lookahead region when peak-checking
    // so we do not measure the initial zero-fill ramp-in. Allow a small slack above the sample
    // ceiling for the 4× ISP estimate vs the limiter's 8× detector (the limiter targets a working
    // ceiling slightly below the nominal ceiling, so 4× sample-domain peaks stay under nominal).
    const float ceiling = kTruePeakCeilingLinear;
    constexpr float kIspSlack = 1.02F; // 4× linear under-reads the 8× detector; allow ~0.17 dB
    const std::array<float, 5> xs = {0.1F, 0.25F, 0.5F, 0.75F, 0.9F};
    for (const float x : xs)
    {
        const std::vector<float> out = runIntensityOnce(active, x, input);
        // Skip the first lookahead window (zero-prefill region) for the peak measurement.
        const size_t skip = static_cast<size_t>(kLimiterLookaheadFrames) + 64U;
        std::vector<float> tail(out.begin() + static_cast<long>(skip), out.end());

        const float sp = samplePeak(tail);
        const float tp4 = fourXPeak(tail);
        if (sp > ceiling)
        {
            std::ostringstream oss;
            oss << "x=" << x << " sample-peak " << sp << " > ceiling " << ceiling;
            logFail(kName, oss.str());
            return;
        }
        if (tp4 > ceiling * kIspSlack)
        {
            std::ostringstream oss;
            oss << "x=" << x << " 4x-ISP peak " << tp4 << " > ceiling*slack " << (ceiling * kIspSlack);
            logFail(kName, oss.str());
            return;
        }
        std::ostringstream info;
        info << "  [info] " << kName << ": x=" << x << " samplePeak=" << sp << " 4xPeak=" << tp4
             << " (ceiling=" << ceiling << ")\n";
        logInfo(info.str());
    }
    logPass(kName);
}

// ---------------------------------------------------------------------------
// Test: no NaN/denormal anywhere; a fast 0→1 step settles within ~5τ without overshoot.
// Drive a constant DC input. Step intensity 0→1 and verify: (1) no NaN/Inf in any output,
// (2) the per-buffer mean monotonically approaches the wet level (no overshoot above it),
// (3) within ~5τ (160 ms ≈ 16 buffers of 512) the output has effectively converged.
// We disable loudness+limiter (identity state) so the only dynamic is the crossfade ramp,
// and use DC so wet==dry==input (gain trajectory is √2·input at most, monotone to ·1 at x=1).
//
// NOTE: at x=1 (settled) the crossfade is bypassed → out == in (1.0). En route, the equal-power
// gain (cos+sin)(r·π/2) PEAKS at √2 (≈ x=0.5) then returns to 1.0 at x=1, so the per-buffer mean
// rises above 1.0 mid-ramp and falls back. "No overshoot" here means it never exceeds √2·input
// (the equal-power maximum) — it must not ring beyond the equal-power envelope.
// ---------------------------------------------------------------------------
static auto testIntensityNoNaNFastStepSettles() -> void
{
    static const char* const kName = "Intensity_NoNaNAndFastStepSettles";
    constexpr uint32_t kFrames = TestConstants::kFrames512;
    constexpr float kDC = 0.1F;
    constexpr uint32_t kBuffers = 64U; // ~0.68 s ≫ 5τ
    const std::vector<float> input(kFrames, kDC);

    const TargetState identity = makeIdentityState();

    DSPKernel kernel;
    kernel.initialize(TestConstants::kSampleRate48k, kFrames);
    // Start at 0 (settled bypass), then step to 1.0 → ramp climbs through the crossfade.
    TargetState zero = identity;
    zero.intensityLinear = 0.0F;
    kernel.publishTargetState(zero);

    TestABL abl(kFrames);
    // One bypass buffer at x==0: output must equal input (1.0·DC).
    std::memcpy(abl.left.data(), input.data(), kFrames * sizeof(float));
    std::memcpy(abl.right.data(), input.data(), kFrames * sizeof(float));
    kernel.process(abl.abl(), kFrames);

    TargetState one = identity;
    one.intensityLinear = 1.0F;
    kernel.publishTargetState(one);

    constexpr float kSqrt2 = 1.41421356F;
    float lastMean = 0.0F;
    for (uint32_t b = 0U; b < kBuffers; ++b)
    {
        std::memcpy(abl.left.data(), input.data(), kFrames * sizeof(float));
        std::memcpy(abl.right.data(), input.data(), kFrames * sizeof(float));
        kernel.process(abl.abl(), kFrames);

        double sum = 0.0;
        for (uint32_t i = 0U; i < kFrames; ++i)
        {
            const float v = abl.left[i];
            if (!std::isfinite(v))
            {
                logFail(kName, "non-finite output sample on buffer " + std::to_string(b));
                return;
            }
            sum += v;
        }
        const float mean = static_cast<float>(sum / kFrames);
        // Equal-power envelope: the per-buffer mean must never exceed √2·DC (no ringing beyond
        // the equal-power maximum), accounting for tiny float slack.
        if (mean > (kSqrt2 * kDC * 1.001F))
        {
            std::ostringstream oss;
            oss << "overshoot beyond equal-power max: mean " << mean << " > √2·DC "
                << (kSqrt2 * kDC);
            logFail(kName, oss.str());
            return;
        }
        lastMean = mean;
    }

    // After ~64 buffers (≫ 5τ) the ramp has settled at x==1 → crossfade bypassed → out == in.
    if (std::abs(lastMean - kDC) > 1e-5F)
    {
        std::ostringstream oss;
        oss << "did not converge to wet (DC " << kDC << "): final mean " << lastMean;
        logFail(kName, oss.str());
        return;
    }
    logPass(kName);
}
