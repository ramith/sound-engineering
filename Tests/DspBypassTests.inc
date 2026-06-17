// DspBypassTests.inc
//
// DSP bypass / identity-chain tests (Phase 0, Tests 1–7).
// #included into Tests/DSPKernelNullTest.cpp after TestSupport.h.
//
// Tests: IntensityZero_BitExactPassthrough, IntensityZero_MultiChunkBitExact,
//        WhiteNoiseBypasses, ChirpSignalBypasses, EQModuleIdentityAtZeroBiquads,
//        ZeroInputProducesZeroOutput, MultiChunkStatePreservation.

// ---------------------------------------------------------------------------
// Test 1: intensityLinear == 0 -> bit-exact passthrough (Phase 0 bypass)
//
// With intensity == 0 the kernel executes an early return without touching the
// buffers.  The AU render block pulls input into the output ABL in-place before
// calling process(), so "not touching" == output bit-identical to input.
// This satisfies the MD5-bit-exact null-test requirement (architecture LD-11).
// ---------------------------------------------------------------------------

static auto testIntensityZeroIsBitExact() -> void
{
    static const char* const kName = "IntensityZero_BitExactPassthrough";
    constexpr uint32_t kFrames = TestConstants::kFrames512;

    DSPKernel kernel;
    kernel.initialize(TestConstants::kSampleRate48k, kFrames);

    // NOLINTBEGIN(cert-msc32-c,cert-msc51-cpp)
    std::mt19937 gen(TestConstants::kSeedBypassSingle);
    // NOLINTEND(cert-msc32-c,cert-msc51-cpp)
    std::uniform_real_distribution<float> dist(-TestConstants::kNoiseUnit,
                                               TestConstants::kNoiseUnit);

    TestABL abl(kFrames);
    for (uint32_t idx = 0U; idx < kFrames; ++idx)
    {
        abl.left[idx] = dist(gen);
        abl.right[idx] = dist(gen);
    }
    const std::vector<float> refLeft(abl.left);
    const std::vector<float> refRight(abl.right);

    TargetState state = makeIdentityState();
    state.intensityLinear = 0.0F;
    kernel.publishTargetState(state);
    kernel.process(abl.abl(), kFrames);

    if (std::memcmp(abl.left.data(), refLeft.data(), kFrames * sizeof(float)) != 0)
    {
        logFail(kName, "left channel was modified despite intensityLinear == 0");
        return;
    }
    if (std::memcmp(abl.right.data(), refRight.data(), kFrames * sizeof(float)) != 0)
    {
        logFail(kName, "right channel was modified despite intensityLinear == 0");
        return;
    }
    logPass(kName);
}

// ---------------------------------------------------------------------------
// Test 2: intensityLinear == 0 across multiple chunks
//
// Ten consecutive chunks with varying input content.  Confirms the bypass never
// accumulates state that bleeds into subsequent calls.
// ---------------------------------------------------------------------------

static auto testIntensityZeroMultiChunk() -> void
{
    static const char* const kName = "IntensityZero_MultiChunkBitExact";
    constexpr uint32_t kFrames = TestConstants::kFrames512;
    constexpr uint32_t kChunks = TestConstants::kChunks10;

    DSPKernel kernel;
    kernel.initialize(TestConstants::kSampleRate48k, kFrames);

    TargetState state = makeIdentityState();
    state.intensityLinear = 0.0F;
    kernel.publishTargetState(state);

    // NOLINTBEGIN(cert-msc32-c,cert-msc51-cpp)
    std::mt19937 gen(TestConstants::kSeedBypassMulti);
    // NOLINTEND(cert-msc32-c,cert-msc51-cpp)
    std::uniform_real_distribution<float> dist(-TestConstants::kNoiseUnit,
                                               TestConstants::kNoiseUnit);

    TestABL abl(kFrames);
    for (uint32_t chunk = 0U; chunk < kChunks; ++chunk)
    {
        for (uint32_t idx = 0U; idx < kFrames; ++idx)
        {
            abl.left[idx] = dist(gen);
            abl.right[idx] = dist(gen);
        }
        const std::vector<float> refLeft(abl.left);
        const std::vector<float> refRight(abl.right);

        kernel.process(abl.abl(), kFrames);

        if (std::memcmp(abl.left.data(), refLeft.data(), kFrames * sizeof(float)) != 0)
        {
            logFail(kName, "left modified on chunk " + std::to_string(chunk));
            return;
        }
        if (std::memcmp(abl.right.data(), refRight.data(), kFrames * sizeof(float)) != 0)
        {
            logFail(kName, "right modified on chunk " + std::to_string(chunk));
            return;
        }
    }
    logPass(kName);
}

// ---------------------------------------------------------------------------
// Test 3: White noise through identity EQ -> bit-exact passthrough
// ---------------------------------------------------------------------------

static auto testWhiteNoiseBypasses() -> void
{
    static const char* const kName = "WhiteNoiseBypasses";
    constexpr uint32_t kFrames = TestConstants::kFrames512;

    DSPKernel kernel;
    kernel.initialize(TestConstants::kSampleRate48k, kFrames);

    // NOLINTBEGIN(cert-msc32-c,cert-msc51-cpp)
    std::mt19937 gen(TestConstants::kSeedWhiteNoise);
    // NOLINTEND(cert-msc32-c,cert-msc51-cpp)
    std::uniform_real_distribution<float> dist(-TestConstants::kNoiseHalf,
                                               TestConstants::kNoiseHalf);

    TestABL abl(kFrames);
    for (uint32_t idx = 0U; idx < kFrames; ++idx)
    {
        abl.left[idx] = dist(gen);
        abl.right[idx] = dist(gen);
    }
    const std::vector<float> refLeft(abl.left);
    const std::vector<float> refRight(abl.right);

    const TargetState state = makeIdentityState();
    kernel.publishTargetState(state);
    kernel.process(abl.abl(), kFrames);

    for (uint32_t idx = 0U; idx < kFrames; ++idx)
    {
        if (abl.left[idx] != refLeft[idx])
        {
            logFail(kName, mismatchMsg("left", idx, refLeft[idx], abl.left[idx]));
            return;
        }
        if (abl.right[idx] != refRight[idx])
        {
            logFail(kName, mismatchMsg("right", idx, refRight[idx], abl.right[idx]));
            return;
        }
    }
    logPass(kName);
}

// ---------------------------------------------------------------------------
// Test 4: Chirp signal through identity EQ -> bit-exact passthrough
//
// A linear frequency sweep from 20 Hz to 20 kHz over 1 second, processed in
// 512-frame chunks.  Exercises the full audio band across persistent kernel state.
// ---------------------------------------------------------------------------

static auto testChirpBypasses() -> void
{
    static const char* const kName = "ChirpSignalBypasses";
    constexpr uint32_t kSR = TestConstants::kSampleRate48k;
    constexpr uint32_t kChunk = TestConstants::kFrames512;
    constexpr uint32_t kTotal = TestConstants::kTotalFrames1s;

    std::vector<float> chirp(kTotal);
    for (uint32_t idx = 0U; idx < kTotal; ++idx)
    {
        const float timeSec = static_cast<float>(idx) / static_cast<float>(kSR);
        const float freq =
            TestConstants::kChirpF0 + (TestConstants::kChirpF1 - TestConstants::kChirpF0) *
                                          (timeSec / TestConstants::kChirpDuration);
        chirp[idx] =
            std::sin(2.0F * std::numbers::pi_v<float> * freq * timeSec) * TestConstants::kChirpAmpl;
    }
    const std::vector<float> reference(chirp);

    DSPKernel kernel;
    kernel.initialize(kSR, kChunk);
    const TargetState state = makeIdentityState();
    kernel.publishTargetState(state);

    TestABL abl(kChunk);
    uint32_t offset = 0U;
    while (offset < kTotal)
    {
        const uint32_t chunk = std::min(kChunk, kTotal - offset);
        std::memcpy(abl.left.data(), chirp.data() + offset, chunk * sizeof(float));
        std::memcpy(abl.right.data(), chirp.data() + offset, chunk * sizeof(float));
        abl.setFrameCount(chunk);
        kernel.process(abl.abl(), chunk);
        std::memcpy(chirp.data() + offset, abl.left.data(), chunk * sizeof(float));
        offset += chunk;
    }

    for (uint32_t idx = 0U; idx < kTotal; ++idx)
    {
        if (chirp[idx] != reference[idx])
        {
            logFail(kName, mismatchMsg("frame", idx, reference[idx], chirp[idx]));
            return;
        }
    }
    logPass(kName);
}

// ---------------------------------------------------------------------------
// Test 5: EQ module identity at numBiquads=0 with unity masterGain
// ---------------------------------------------------------------------------

static auto testEQModuleIdentityAtZeroBiquads() -> void
{
    static const char* const kName = "EQModuleIdentityAtZeroBiquads";
    constexpr uint32_t kFrames = TestConstants::kFrames512;
    constexpr float kDC = TestConstants::kConstantDC;

    DSPKernel kernel;
    kernel.initialize(TestConstants::kSampleRate48k, kFrames);

    TestABL abl(kFrames);
    abl.left.assign(kFrames, kDC);
    abl.right.assign(kFrames, kDC);

    TargetState state = makeIdentityState();
    state.eq.numBiquads = 0U;
    state.eq.masterGainLinear = 1.0F;
    kernel.publishTargetState(state);
    kernel.process(abl.abl(), kFrames);

    for (uint32_t idx = 0U; idx < kFrames; ++idx)
    {
        if (abl.left[idx] != kDC)
        {
            logFail(kName, mismatchMsg("left", idx, kDC, abl.left[idx]));
            return;
        }
        if (abl.right[idx] != kDC)
        {
            logFail(kName, mismatchMsg("right", idx, kDC, abl.right[idx]));
            return;
        }
    }
    logPass(kName);
}

// ---------------------------------------------------------------------------
// Test 6: Zero input -> zero output (no DC injection from delay state init)
// ---------------------------------------------------------------------------

static auto testZeroInputProducesZeroOutput() -> void
{
    static const char* const kName = "ZeroInputProducesZeroOutput";
    constexpr uint32_t kFrames = TestConstants::kFrames512;

    DSPKernel kernel;
    kernel.initialize(TestConstants::kSampleRate48k, kFrames);

    TestABL abl(kFrames); // zero-initialised by std::vector default

    const TargetState state = makeIdentityState();
    kernel.publishTargetState(state);
    kernel.process(abl.abl(), kFrames);

    for (uint32_t idx = 0U; idx < kFrames; ++idx)
    {
        if (abl.left[idx] != 0.0F)
        {
            logFail(kName, mismatchMsg("left", idx, 0.0F, abl.left[idx]));
            return;
        }
        if (abl.right[idx] != 0.0F)
        {
            logFail(kName, mismatchMsg("right", idx, 0.0F, abl.right[idx]));
            return;
        }
    }
    logPass(kName);
}

// ---------------------------------------------------------------------------
// Test 7: Multi-chunk state preservation (identity EQ, 3 chunks)
// ---------------------------------------------------------------------------

static auto testMultiChunkStatePreservation() -> void
{
    static const char* const kName = "MultiChunkStatePreservation";
    constexpr uint32_t kFrames = TestConstants::kFrames512;
    constexpr uint32_t kChunks = TestConstants::kChunks3;

    DSPKernel kernel;
    kernel.initialize(TestConstants::kSampleRate48k, kFrames);

    // NOLINTBEGIN(cert-msc32-c,cert-msc51-cpp)
    std::mt19937 gen(TestConstants::kSeedMultiChunk);
    // NOLINTEND(cert-msc32-c,cert-msc51-cpp)
    std::uniform_real_distribution<float> dist(-TestConstants::kNoiseUnit,
                                               TestConstants::kNoiseUnit);

    const TargetState state = makeIdentityState();
    kernel.publishTargetState(state);

    TestABL abl(kFrames);
    for (uint32_t chunk = 0U; chunk < kChunks; ++chunk)
    {
        for (uint32_t idx = 0U; idx < kFrames; ++idx)
        {
            abl.left[idx] = dist(gen);
            abl.right[idx] = dist(gen);
        }
        const std::vector<float> refLeft(abl.left);
        const std::vector<float> refRight(abl.right);

        kernel.process(abl.abl(), kFrames);

        for (uint32_t idx = 0U; idx < kFrames; ++idx)
        {
            if (abl.left[idx] != refLeft[idx])
            {
                logFail(kName,
                        "chunk " + std::to_string(chunk) + " " +
                            mismatchMsg("left", idx, refLeft[idx], abl.left[idx]));
                return;
            }
            if (abl.right[idx] != refRight[idx])
            {
                logFail(kName,
                        "chunk " + std::to_string(chunk) + " " +
                            mismatchMsg("right", idx, refRight[idx], abl.right[idx]));
                return;
            }
        }
    }
    logPass(kName);
}
