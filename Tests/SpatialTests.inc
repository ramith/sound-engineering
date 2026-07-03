// SpatialTests.inc
//
// SpatialRenderKernel tests (Sprint 5b, M3-1).
// #included into Tests/DSPKernelNullTest.cpp after TestSupport.h.
//
// Tests: SpatialRender_PassthroughRoute.
// Helpers (area-local): spatialFillNoise, spatialCheckZeroFill, spatialCheckSoakBuffer,
//   spatialCheckIdentityRoute, spatialCheckNarrowerSourceRoute, spatialCheckIdentitySoak.

// ===========================================================================
// SpatialRenderKernel tests (Sprint 5b, M3-1)
//
// These tests exercise SpatialRenderKernel independently of DSPKernel.
// The golden-master stereo test (GoldenMaster_StereoN2_v1) is unaffected
// because SpatialRenderKernel has no shared state with DSPKernel.
//
// Test naming: SpatialRender_*
// ===========================================================================

namespace
{
    // Named constants for the spatial tests — no magic numbers (clang-tidy).
    constexpr uint32_t kSpatialSR = 48000U;
    constexpr uint32_t kSpatialMaxFrames = 512U;
    constexpr uint32_t kSpatialSoakBuffers = 200U;
    constexpr float kSpatialNoiseAmpl = 0.5F;
    // NOLINTBEGIN(cert-msc32-c,cert-msc51-cpp)
    constexpr uint32_t kSpatialSoakSeedBase = 0xBEEF1234U;
    // NOLINTEND(cert-msc32-c,cert-msc51-cpp)
} // namespace

// ---------------------------------------------------------------------------
// SpatialRender_PassthroughRoute
//
// Three sub-tests:
//   (A) in == out (N in {2, 6, 8}): every output channel is bit-exact copy
//       of the corresponding input channel.
//   (B) in < out (2->6, 6->8): first `in` channels copied bit-exact; extra
//       output channels are exactly 0.0f.
//   (C) soak: 200 buffers at N=6 and N=8 configured as identity routes
//       (in == out).  All output samples must be finite, non-NaN, and
//       bit-exact copies of the input.
// ---------------------------------------------------------------------------

// Fill `numCh` channels of `abl` with deterministic per-channel noise.
static auto spatialFillNoise(TestABLN& abl, uint32_t numCh, uint32_t seed) -> void
{
    // NOLINTBEGIN(cert-msc32-c,cert-msc51-cpp)
    std::mt19937 gen(seed);
    // NOLINTEND(cert-msc32-c,cert-msc51-cpp)
    std::uniform_real_distribution<float> dist(-kSpatialNoiseAmpl, kSpatialNoiseAmpl);
    for (uint32_t ch = 0U; ch < numCh; ++ch)
    {
        for (uint32_t frm = 0U; frm < kSpatialMaxFrames; ++frm)
        {
            abl.channels[ch][frm] = dist(gen);
        }
    }
}

// Assert output channels [inCh, outCh) are all exactly 0.0f (zero-fill). "" on pass.
static auto spatialCheckZeroFill(const TestABLN& outAbl, uint32_t inCh, uint32_t outCh)
    -> std::string
{
    for (uint32_t ch = inCh; ch < outCh; ++ch)
    {
        for (uint32_t frm = 0U; frm < kSpatialMaxFrames; ++frm)
        {
            if (outAbl.channels[ch][frm] != 0.0F)
            {
                std::ostringstream oss;
                oss << "(B) in=" << inCh << "->out=" << outCh << " extra ch" << ch << " frm" << frm
                    << ": expected 0.0 (zero-fill), got " << outAbl.channels[ch][frm];
                return oss.str();
            }
        }
    }
    return {};
}

// Assert every sample of an identity-route output buffer is finite + bit-exact. "" on pass.
static auto spatialCheckSoakBuffer(const TestABLN& inAbl,
                                   const TestABLN& outAbl,
                                   uint32_t numCh,
                                   uint32_t bufIdx) -> std::string
{
    for (uint32_t ch = 0U; ch < numCh; ++ch)
    {
        for (uint32_t frm = 0U; frm < kSpatialMaxFrames; ++frm)
        {
            const float outSample = outAbl.channels[ch][frm];
            const float inSample = inAbl.channels[ch][frm];
            if (!std::isfinite(outSample))
            {
                std::ostringstream oss;
                oss << "(C) N=" << numCh << " buf=" << bufIdx << " ch=" << ch << " frm=" << frm
                    << ": NaN or Inf in output";
                return oss.str();
            }
            if (outSample != inSample)
            {
                std::ostringstream oss;
                oss << "(C) N=" << numCh << " buf=" << bufIdx << " ch=" << ch << " frm=" << frm
                    << ": output " << outSample << " != input " << inSample
                    << " (identity route broken)";
                return oss.str();
            }
        }
    }
    return {};
}

// Sub-test A: in == out identity route (N in {2,6,8}) — bit-exact copy per channel.
static auto spatialCheckIdentityRoute() -> std::string
{
    const uint32_t identityCounts[] = {2U, 6U, 8U};
    for (const uint32_t numCh : identityCounts)
    {
        SpatialRenderKernel kernel;
        kernel.initialize(kSpatialSR, kSpatialMaxFrames);
        kernel.configure(numCh, numCh);

        TestABLN inAbl(numCh, kSpatialMaxFrames);
        TestABLN outAbl(numCh, kSpatialMaxFrames);
        spatialFillNoise(inAbl, numCh, kSpatialSoakSeedBase ^ numCh);

        const MultichannelView inView = MultichannelView::fromABL(inAbl.abl(), kSpatialMaxFrames);
        const MultichannelView outView = MultichannelView::fromABL(outAbl.abl(), kSpatialMaxFrames);
        kernel.process(inView, outView);

        for (uint32_t ch = 0U; ch < numCh; ++ch)
        {
            if (std::memcmp(inAbl.channels[ch].data(),
                            outAbl.channels[ch].data(),
                            kSpatialMaxFrames * sizeof(float)) != 0)
            {
                std::ostringstream oss;
                oss << "(A) N=" << numCh << " ch" << ch
                    << ": output is not a bit-exact copy of input (in==out route)";
                return oss.str();
            }
        }
    }
    return {};
}

// Sub-test B: in < out (2->6, 6->8) — first `in` channels copied bit-exact; extra zeroed.
static auto spatialCheckNarrowerSourceRoute() -> std::string
{
    struct RouteCase
    {
        uint32_t inCh;
        uint32_t outCh;
    };
    const RouteCase routeCases[] = {{.inCh = 2U, .outCh = 6U}, {.inCh = 6U, .outCh = 8U}};

    for (const auto& rc : routeCases)
    {
        SpatialRenderKernel kernel;
        kernel.initialize(kSpatialSR, kSpatialMaxFrames);
        kernel.configure(rc.inCh, rc.outCh);

        TestABLN inAbl(rc.inCh, kSpatialMaxFrames);
        TestABLN outAbl(rc.outCh, kSpatialMaxFrames);
        spatialFillNoise(inAbl, rc.inCh, kSpatialSoakSeedBase ^ (rc.inCh * 31U) ^ rc.outCh);

        // Pre-fill output with a sentinel so partial writes are caught.
        constexpr float kSentinel = -999.0F;
        for (uint32_t ch = 0U; ch < rc.outCh; ++ch)
        {
            outAbl.channels[ch].assign(kSpatialMaxFrames, kSentinel);
        }

        const MultichannelView inView = MultichannelView::fromABL(inAbl.abl(), kSpatialMaxFrames);
        const MultichannelView outView = MultichannelView::fromABL(outAbl.abl(), kSpatialMaxFrames);
        kernel.process(inView, outView);

        for (uint32_t ch = 0U; ch < rc.inCh; ++ch)
        {
            if (std::memcmp(inAbl.channels[ch].data(),
                            outAbl.channels[ch].data(),
                            kSpatialMaxFrames * sizeof(float)) != 0)
            {
                std::ostringstream oss;
                oss << "(B) in=" << rc.inCh << "->out=" << rc.outCh << " ch" << ch
                    << ": copied channel is not bit-exact";
                return oss.str();
            }
        }
        const std::string zeroErr = spatialCheckZeroFill(outAbl, rc.inCh, rc.outCh);
        if (!zeroErr.empty())
        {
            return zeroErr;
        }
    }
    return {};
}

// Sub-test C: multi-buffer soak — 200 buffers, N=6 and N=8, identity route.
static auto spatialCheckIdentitySoak() -> std::string
{
    const uint32_t soakCounts[] = {6U, 8U};
    for (const uint32_t numCh : soakCounts)
    {
        SpatialRenderKernel kernel;
        kernel.initialize(kSpatialSR, kSpatialMaxFrames);
        kernel.configure(numCh, numCh);

        for (uint32_t buf = 0U; buf < kSpatialSoakBuffers; ++buf)
        {
            TestABLN inAbl(numCh, kSpatialMaxFrames);
            TestABLN outAbl(numCh, kSpatialMaxFrames);
            spatialFillNoise(inAbl, numCh, (kSpatialSoakSeedBase + (numCh * 131U)) ^ buf);

            const MultichannelView inView =
                MultichannelView::fromABL(inAbl.abl(), kSpatialMaxFrames);
            const MultichannelView outView =
                MultichannelView::fromABL(outAbl.abl(), kSpatialMaxFrames);
            kernel.process(inView, outView);

            const std::string err = spatialCheckSoakBuffer(inAbl, outAbl, numCh, buf);
            if (!err.empty())
            {
                return err;
            }
        }
    }
    return {};
}

static auto testSpatialRenderPassthroughRoute() -> void
{
    static const char* const kName = "SpatialRender_PassthroughRoute";
    std::string err = spatialCheckIdentityRoute();
    if (err.empty())
    {
        err = spatialCheckNarrowerSourceRoute();
    }
    if (err.empty())
    {
        err = spatialCheckIdentitySoak();
    }
    if (!err.empty())
    {
        logFail(kName, err);
        return;
    }
    logPass(kName);
}
