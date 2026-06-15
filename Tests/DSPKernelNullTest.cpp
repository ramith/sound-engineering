// DSPKernelNullTest.cpp
//
// Null test: verifies DSPKernel::process() produces bit-identical output to input
// under two conditions:
//   (a) intensityLinear == 0  -> early-return bypass (Phase 0 requirement)
//   (b) identity EQ (numBiquads=0, masterGainLinear=1) -> full chain at unity
//
// This is the Phase 0 canary for the signal chain.  Every future module must pass
// this test (or a variant) before merging.
//
// Standalone executable; same pattern as EQModuleCoefficientsTests.cpp.
// Build: ./Scripts/build-null-test.sh
// Run:   ./Tests/DSPKernelNullTest

#include <array>
#include <AudioToolbox/AudioToolbox.h>
#include <cmath>
#include <cstring>
#include <numbers>
#include <random>
#include <sstream>
#include <string>
#include <vector>

#include "DSPKernel.h"
#include "TargetState.h"

using namespace AdaptiveSound;

// ---------------------------------------------------------------------------
// Named constants — no magic numbers per clang-tidy
// ---------------------------------------------------------------------------

namespace TestConstants
{
    constexpr uint32_t kSampleRate48k = 48000U;
    constexpr uint32_t kFrames512 = 512U;
    constexpr uint32_t kTotalFrames1s = 48000U; // 1 second at 48 kHz
    constexpr uint32_t kChunks3 = 3U;
    constexpr uint32_t kChunks10 = 10U;

    // RNG seeds: fixed for deterministic test sequences (intentional, not a security concern).
    // NOLINTBEGIN(cert-msc32-c,cert-msc51-cpp)
    constexpr uint32_t kSeedWhiteNoise = 42U;
    constexpr uint32_t kSeedMultiChunk = 99U;
    constexpr uint32_t kSeedBypassSingle = 0xDEADBEEFU;
    constexpr uint32_t kSeedBypassMulti = 0xCAFEBABEU;
    // NOLINTEND(cert-msc32-c,cert-msc51-cpp)

    constexpr float kNoiseHalf = 0.5F;   // noise amplitude +-0.5
    constexpr float kNoiseUnit = 1.0F;   // noise amplitude +-1.0
    constexpr float kConstantDC = 0.1F;  // DC level for identity test
    constexpr float kChirpF0 = 20.0F;    // chirp start frequency (Hz)
    constexpr float kChirpF1 = 20000.0F; // chirp end frequency (Hz)
    constexpr float kChirpAmpl = 0.5F;   // chirp amplitude
    constexpr float kChirpDuration = 1.0F;
} // namespace TestConstants

// ---------------------------------------------------------------------------
// Test result counter — struct avoids cppcoreguidelines-avoid-non-const-globals
// ---------------------------------------------------------------------------

namespace
{
    struct Results
    {
        int passed = 0;
        int failed = 0;
    };

    Results gResults; // NOLINT(cppcoreguidelines-avoid-non-const-globals)
} // namespace

// ---------------------------------------------------------------------------
// Logging helpers — std::fputs avoids cppcoreguidelines-pro-type-vararg
// ---------------------------------------------------------------------------

static auto logPass(const char* testName) -> void
{
    std::string line = std::string("[PASS] ") + testName + "\n";
    std::fputs(line.c_str(), stdout);
    ++gResults.passed;
}

static auto logFail(const char* testName, const std::string& reason) -> void
{
    std::string line = std::string("[FAIL] ") + testName + " -- " + reason + "\n";
    std::fputs(line.c_str(), stderr);
    ++gResults.failed;
}

// Build a mismatch message without snprintf.
static auto mismatchMsg(const char* side, uint32_t index, float expected, float actual)
    -> std::string
{
    std::ostringstream oss;
    oss << side << '[' << index << "]: expected " << expected << ", got " << actual << " (delta "
        << std::abs(actual - expected) << ')';
    return oss.str();
}

// ---------------------------------------------------------------------------
// AudioBufferList helpers
//
// AudioBufferList has a C flexible-array member: AudioBuffer mBuffers[1].
// Declaring a plain AudioBufferList only allocates one AudioBuffer slot, so
// accessing mBuffers[1] is undefined behaviour.
//
// The standard CoreAudio idiom for two non-interleaved channels is to declare
// a struct that embeds an AudioBufferList followed by a second AudioBuffer,
// giving the correct contiguous layout without any heap allocation.
// ---------------------------------------------------------------------------

// Two-channel (non-interleaved) AudioBufferList with statically correct storage.
struct AudioBufferList2
{
    AudioBufferList head; // mNumberBuffers + mBuffers[0]
    AudioBuffer extra;    // provides storage for mBuffers[1]

    AudioBufferList2() : head{}, extra{}
    {
        head.mNumberBuffers = 2U;
    }

    auto abl() -> AudioBufferList*
    {
        return &head;
    }
};

struct TestABL
{
    explicit TestABL(uint32_t numFrames)
        : frames(numFrames), left(numFrames, 0.0F), right(numFrames, 0.0F), storage()
    {
        storage.head.mBuffers[0].mNumberChannels = 1U;
        storage.head.mBuffers[0].mDataByteSize = numFrames * static_cast<uint32_t>(sizeof(float));
        storage.head.mBuffers[0].mData = left.data();
        storage.extra.mNumberChannels = 1U;
        storage.extra.mDataByteSize = numFrames * static_cast<uint32_t>(sizeof(float));
        storage.extra.mData = right.data();
    }

    auto setFrameCount(uint32_t n) -> void
    {
        storage.head.mBuffers[0].mDataByteSize = n * static_cast<uint32_t>(sizeof(float));
        storage.extra.mDataByteSize = n * static_cast<uint32_t>(sizeof(float));
    }

    auto abl() -> AudioBufferList*
    {
        return storage.abl();
    }

    uint32_t frames;
    std::vector<float> left;
    std::vector<float> right;
    AudioBufferList2 storage;
};

// Build an identity TargetState: EQ passthrough (numBiquads=0, masterGain=1),
// all other modules are stubs that pass through untouched.
static auto makeIdentityState() -> TargetState
{
    TargetState state{};
    state.intensityLinear = 1.0F; // documentary clarity; matches the struct default
    state.eq.numBiquads = 0U;
    state.eq.masterGainLinear = 1.0F;
    state.clarity.enabled = 0U;  // stub module -- no-op
    state.loudness.enabled = 0U; // stub module -- no-op
    return state;
}

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

// ---------------------------------------------------------------------------
// main
// ---------------------------------------------------------------------------

auto main() -> int
{
    std::fputs("=== DSPKernel Null Test Suite ===\n\n", stdout);

    // Phase 0 bypass tests -- run first (critical path)
    testIntensityZeroIsBitExact();
    testIntensityZeroMultiChunk();

    // Identity-chain tests -- validate the full chain at unity gain
    testWhiteNoiseBypasses();
    testChirpBypasses();
    testEQModuleIdentityAtZeroBiquads();
    testZeroInputProducesZeroOutput();
    testMultiChunkStatePreservation();

    std::ostringstream summary;
    summary << "\n=== Results: " << gResults.passed << " passed, " << gResults.failed
            << " failed ===\n";
    std::fputs(summary.str().c_str(), stdout);

    if (gResults.failed > 0)
    {
        std::ostringstream err;
        err << "\nNULL TEST FAILED: " << gResults.failed << " test(s) failed.\n"
            << "The identity/bypass path is broken -- do NOT merge this change.\n";
        std::fputs(err.str().c_str(), stderr);
        return 1;
    }

    std::fputs("All null tests passed. Identity and bypass paths are intact.\n", stdout);
    return 0;
}
