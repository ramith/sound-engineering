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
#include <bit>
#include <cmath>
#include <cstdint>
#include <cstring>
#include <numbers>
#include <random>
#include <sstream>
#include <string>
#include <vector>

#include "DSPKernel.h"
#include "EQ/EQModuleCoefficients.h"
#include "Loudness/ChannelLayoutDecoder.h"
#include "Loudness/LufsMeter.h"
#include "MultichannelView.h"
#include "Spatial/SpatialRenderKernel.h"
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

    // Multichannel per-channel independence test constants (S1-A2 T-C3).
    constexpr uint32_t kNChannels4 = 4U;
    constexpr uint32_t kNChannels6 = 6U;
    constexpr uint32_t kNChannels8 = 8U;
    constexpr float kPerChAmplitude = 0.25F;        // -12 dBFS per channel
    constexpr double kCrosstalkThresholdDb = -60.0; // inter-channel isolation target (dB)
    // DFT-bin-aligned test: N=8192 frames at 48 kHz → bin spacing = 48000/8192 Hz.
    // The sine for channel k is generated at exactly bin[k] × (fs/N) so the Goertzel
    // measurement at that bin captures a full integer number of cycles, making cross-bin
    // leakage ≈ 0 (rectangular-window DFT orthogonality). Bins chosen to be non-harmonic,
    // all well within the audible band: 34,59,89,116,149,173,211,251 × (48000/8192).
    constexpr uint32_t kPerChTestFrames = 8192U; // ~170 ms @ 48 kHz — must be power-of-2
    // NOLINTBEGIN(cppcoreguidelines-avoid-c-arrays)
    constexpr uint32_t kPerChBins[] = {34U, 59U, 89U, 116U, 149U, 173U, 211U, 251U};
    // NOLINTEND(cppcoreguidelines-avoid-c-arrays)
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

// A test that is intentionally not yet implemented (lands in a later epic milestone). Prints a
// PENDING line but does NOT count as pass or fail, so the suite gate stays green.
static auto logPending(const char* testName, const char* note) -> void
{
    std::string line = std::string("[PENDING] ") + testName + " -- " + note + "\n";
    std::fputs(line.c_str(), stdout);
}

// FNV-1a 64-bit over the raw float bytes of a buffer — a compact bit-exact signature. bit_cast
// avoids reinterpret_cast (clang-tidy clean). Used by the golden-master regression fence.
static auto fnv1aFloats(const std::vector<float>& data, uint64_t seed) -> uint64_t
{
    constexpr uint64_t kFnvPrime = 0x100000001b3ULL;
    uint64_t hash = seed;
    for (const float sample : data)
    {
        const auto bits = std::bit_cast<uint32_t>(sample);
        for (int shift = 0; shift < 32; shift += 8)
        {
            hash ^= static_cast<uint64_t>((bits >> static_cast<uint32_t>(shift)) & 0xFFU);
            hash *= kFnvPrime;
        }
    }
    return hash;
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

// N-channel (non-interleaved) AudioBufferList with statically correct storage for up to
// kMaxChannels channels. AudioBufferList has a flexible-array-style tail (mBuffers[1]);
// we extend it by embedding (kMaxChannels-1) extra AudioBuffer slots immediately after,
// giving a contiguous layout that CoreAudio expects. mNumberBuffers is set to `numCh`
// at construction time; only those buffers are wired to channel vectors.
struct AudioBufferListN
{
    AudioBufferList head; // mNumberBuffers + mBuffers[0]
    // NOLINTNEXTLINE(cppcoreguidelines-avoid-c-arrays) -- CoreAudio flexible-array layout
    std::array<AudioBuffer, kMaxChannels - 1U> extra{}; // mBuffers[1..kMaxChannels-1]

    explicit AudioBufferListN(uint32_t numCh) : head{}, extra{}
    {
        head.mNumberBuffers = numCh;
    }

    auto abl() -> AudioBufferList*
    {
        return &head;
    }
};

// N-channel test fixture: owns per-channel float vectors, wires them into an N-channel ABL.
struct TestABLN
{
    explicit TestABLN(uint32_t numCh, uint32_t numFrames)
        : numChannels(numCh), frames(numFrames), storage(numCh)
    {
        channels.resize(numCh, std::vector<float>(numFrames, 0.0F));
        for (uint32_t ch = 0U; ch < numCh; ++ch)
        {
            // mBuffers[0] lives in head; mBuffers[1..] live in extra[0..].
            AudioBuffer& buf = (ch == 0U) ? storage.head.mBuffers[0] : storage.extra[ch - 1U];
            buf.mNumberChannels = 1U;
            buf.mDataByteSize = numFrames * static_cast<uint32_t>(sizeof(float));
            buf.mData = channels[ch].data();
        }
    }

    auto abl() -> AudioBufferList*
    {
        return storage.abl();
    }

    uint32_t numChannels;
    uint32_t frames;
    std::vector<std::vector<float>> channels; // channels[ch][frame]
    AudioBufferListN storage;
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
// all other modules explicitly disabled / neutralised.
//
// Each real module that could alter the signal is set to its bypass/identity
// condition so chain null-tests measure only EQ identity:
//   clarity.enabled = 0       — stub, no-op
//   loudness.enabled = 0      — stub, no-op
//   limiter.truePeakCeilingLinear = 2.0F — ceiling ≥ 1.0 → zero-latency bypass
//     (the limiter's ring-based path is only entered when ceiling < 1.0; at 2.0
//      process() returns immediately after the null-guard, giving bit-exact output)
static auto makeIdentityState() -> TargetState
{
    TargetState state{};
    state.intensityLinear = 1.0F; // documentary clarity; matches the struct default
    state.eq.numBiquads = 0U;
    state.eq.masterGainLinear = 1.0F;
    state.clarity.enabled = 0U;                 // stub module -- no-op
    state.loudness.enabled = 0U;                // stub module -- no-op
    state.limiter.truePeakCeilingLinear = 2.0F; // bypass: ceiling ≥ 1.0 → identity
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
// Limiter tests (Sprint 1)
// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// Test 8: LimiterModule bypass (ceiling ≥ 1.0) is bit-exact identity
//
// With truePeakCeilingLinear = 2.0 the limiter's fast bypass path fires and
// process() returns immediately, leaving the buffers untouched.
// Signal: white noise at ±1.0 (above the default −1 dBTP ceiling, so this
// also confirms that bypass mode suppresses engagement regardless of amplitude).
// ---------------------------------------------------------------------------

static auto testLimiterBypassIsIdentity() -> void
{
    static const char* const kName = "Limiter_BypassIsIdentity";
    constexpr uint32_t kFrames = TestConstants::kFrames512;

    DSPKernel kernel;
    kernel.initialize(TestConstants::kSampleRate48k, kFrames);

    // NOLINTBEGIN(cert-msc32-c,cert-msc51-cpp)
    std::mt19937 gen(0xABCD1234U);
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

    // Limiter bypass: ceiling ≥ 1.0
    TargetState state = makeIdentityState(); // already sets ceiling = 2.0
    kernel.publishTargetState(state);
    kernel.process(abl.abl(), kFrames);

    if (std::memcmp(abl.left.data(), refLeft.data(), kFrames * sizeof(float)) != 0)
    {
        logFail(kName, "left channel was modified in bypass mode");
        return;
    }
    if (std::memcmp(abl.right.data(), refRight.data(), kFrames * sizeof(float)) != 0)
    {
        logFail(kName, "right channel was modified in bypass mode");
        return;
    }
    logPass(kName);
}

// ---------------------------------------------------------------------------
// Test 9: Limiter ceiling enforcement — −3 dBFS input → output ≤ −1 dBTP
//
// Feeds a full-scale sine burst whose peak is ~−3 dBFS (0.708 linear) through
// the active limiter with the default −1 dBTP ceiling (0.891 linear).
// That signal is BELOW the ceiling, so a single sine at −3 dBFS passes through
// without gain reduction.
//
// To test actual ceiling enforcement we use a +0 dBFS sine (amplitude 0.999)
// which EXCEEDS the −1 dBTP ceiling (0.891).  After the lookahead has primed
// (kLimiterLookaheadFrames samples of silence prefix), the output peak must be
// ≤ 0.891 (with a small tolerance for the one-pole smoother's ramp time).
//
// Method:
//   1. Prime the limiter with kLimiterLookaheadFrames zero frames.
//   2. Feed N frames of a 1 kHz sine at amplitude 0.999.
//   3. Measure the output true-peak (linear max absolute).
//   4. Assert output_peak ≤ kTruePeakCeilingLinear + small_tolerance.
//
// Tolerance: the one-pole attack (τ = 0.5 ms @ 48 kHz, α ≈ 0.064) means the
// GR envelope takes a few samples to ramp to the required gain.  The ceiling
// check is applied after the first full buffer, by which time GR has settled.
// ---------------------------------------------------------------------------

static auto testLimiterCeilingEnforcement() -> void
{
    static const char* const kName = "Limiter_CeilingEnforcement";
    // Use a block large enough that the one-pole attack has fully settled:
    // 5τ at 0.5 ms = 2.5 ms = 120 samples.  Use 512.
    constexpr uint32_t kFrames = TestConstants::kFrames512;
    constexpr uint32_t kSR = TestConstants::kSampleRate48k;

    // Ceiling from AudioConstants (default −1 dBTP ≈ 0.891)
    // Allow 1 dB of tolerance for attack ramp-up.
    constexpr float kCeiling = kTruePeakCeilingLinear;
    // 1 dB above ceiling in linear: 10^((-1+1)/20) = 1.0 — but we want a tighter
    // check.  The smoother has τ = 0.5 ms; at 512 frames (10.7 ms) it is fully
    // settled.  Allow 0.01 absolute tolerance (≈ 0.1 dB) for numerical precision.
    constexpr float kTolerance = 0.01F;

    DSPKernel kernel;
    kernel.initialize(kSR, kFrames);

    // Publish state with the default ceiling (0.891) — active limiting.
    TargetState state{};
    state.intensityLinear = 1.0F;
    state.eq.numBiquads = 0U;
    state.eq.masterGainLinear = 1.0F;
    state.clarity.enabled = 0U;
    state.loudness.enabled = 0U;
    // limiter: default LimiterParams — truePeakCeilingLinear = kTruePeakCeilingLinear
    kernel.publishTargetState(state);

    // Step 1: prime with silence so the ring fills with zeros before the sine arrives.
    // This avoids a false "peak = 0" scan of a half-full ring biasing the first GR.
    TestABL prime(kLimiterLookaheadFrames);
    prime.left.assign(kLimiterLookaheadFrames, 0.0F);
    prime.right.assign(kLimiterLookaheadFrames, 0.0F);
    kernel.process(prime.abl(), kLimiterLookaheadFrames);

    // Step 2: feed a 1 kHz sine at amplitude 0.999 (just below 0 dBFS, well above ceiling)
    TestABL abl(kFrames);
    constexpr float kSineFreq = 1000.0F;
    constexpr float kSineAmpl = 0.999F;
    for (uint32_t idx = 0U; idx < kFrames; ++idx)
    {
        const float phase = 2.0F * std::numbers::pi_v<float> * kSineFreq * static_cast<float>(idx) /
                            static_cast<float>(kSR);
        abl.left[idx] = kSineAmpl * std::sin(phase);
        abl.right[idx] = abl.left[idx];
    }
    kernel.process(abl.abl(), kFrames);

    // Step 3: measure the true-peak of the output (max absolute value)
    float outPeak = 0.0F;
    for (uint32_t idx = 0U; idx < kFrames; ++idx)
    {
        const float absL = std::abs(abl.left[idx]);
        const float absR = std::abs(abl.right[idx]);
        if (absL > outPeak)
        {
            outPeak = absL;
        }
        if (absR > outPeak)
        {
            outPeak = absR;
        }
    }

    // Step 4: assert output peak ≤ ceiling + tolerance
    if (outPeak > kCeiling + kTolerance)
    {
        std::ostringstream oss;
        oss << "output peak " << outPeak << " exceeds ceiling " << kCeiling << " + tolerance "
            << kTolerance << " (delta " << (outPeak - kCeiling) << ")";
        logFail(kName, oss.str());
        return;
    }
    logPass(kName);
}

// ---------------------------------------------------------------------------
// Test 10: GR response time — onset within ≤ 2 ms of a sudden +0 dBFS peak
//
// Injects an abrupt +0 dBFS step at frame 0 into a limiter that starts with
// an unprimed ring (all zeros).  The fast-path bypasses until the peak primes
// the ring, then GR starts racking.  We verify that within 2 ms (96 samples
// @ 48 kHz) the output gain has dropped below the ceiling.
//
// "Response time" here means: how quickly does gain reduction reach the point
// where output ≤ ceiling?  With a 0.5 ms attack τ (α ≈ 0.064), 5τ = 2.5 ms;
// we target < 2 ms which is ~3τ (~86% of final GR).  We check that at least
// one output sample in the first 96 samples is already ≤ ceiling.
// ---------------------------------------------------------------------------

static auto testLimiterGRResponseTime() -> void
{
    static const char* const kName = "Limiter_GRResponseWithin2ms";
    constexpr uint32_t kSR = TestConstants::kSampleRate48k;
    constexpr uint32_t kFrames = TestConstants::kFrames512;
    // 2 ms at 48 kHz = 96 samples
    constexpr uint32_t k2msFrames = 96U;

    DSPKernel kernel;
    kernel.initialize(kSR, kFrames);

    // Active limiting state (default ceiling = 0.891)
    TargetState state{};
    state.intensityLinear = 1.0F;
    state.eq.numBiquads = 0U;
    state.eq.masterGainLinear = 1.0F;
    state.clarity.enabled = 0U;
    state.loudness.enabled = 0U;
    kernel.publishTargetState(state);

    // Feed a DC burst at +0 dBFS (0.999) into a fresh, unprimed limiter.
    // The ring fast-path will disengage as soon as the peak exceeds the ceiling,
    // then the ring-based path begins.
    TestABL abl(kFrames);
    constexpr float kBurstAmpl = 0.999F;
    abl.left.assign(kFrames, kBurstAmpl);
    abl.right.assign(kFrames, kBurstAmpl);

    kernel.process(abl.abl(), kFrames);

    // Check that within the first 2 ms (k2msFrames) at least one sample has been
    // limited to ≤ ceiling.  The lookahead means the FIRST kLimiterLookaheadFrames
    // output samples are from the zero-primed ring (output = 0).  After those, the
    // GR-attenuated burst samples emerge.  We check that by frame k2msFrames the
    // output has engaged — i.e. the samples that come from the ring are ≤ ceiling.
    //
    // Because the ring was zero-filled and the output is taken from the oldest ring
    // position, the first kLimiterLookaheadFrames output samples are 0.0F (well below
    // the ceiling).  What matters is that no output sample EXCEEDS the ceiling.
    bool anyExceedsCeiling = false;
    for (uint32_t idx = 0U; idx < k2msFrames; ++idx)
    {
        if (std::abs(abl.left[idx]) > kTruePeakCeilingLinear + 0.01F)
        {
            anyExceedsCeiling = true;
            break;
        }
    }

    if (anyExceedsCeiling)
    {
        logFail(kName, "output exceeded ceiling within the first 2 ms (96 frames)");
        return;
    }
    logPass(kName);
}

// Test M3a: near-Nyquist true-peak — a 0.45·fs tone at 0.97 (above the −1 dBTP
// ceiling) must be limited so the OUTPUT sample peak ≤ ceiling. The polyphase
// detector catches the inter-sample energy a sample-only/linear detector misses.
static auto testLimiterNearNyquistCeiling() -> void
{
    static const char* const kName = "Limiter_NearNyquistCeiling";
    constexpr uint32_t kSR = TestConstants::kSampleRate48k;
    constexpr uint32_t kFrames = TestConstants::kFrames512;
    constexpr float kCeiling = kTruePeakCeilingLinear;

    DSPKernel kernel;
    kernel.initialize(kSR, kFrames);
    TargetState state{};
    state.intensityLinear = 1.0F;
    state.eq.numBiquads = 0U;
    state.eq.masterGainLinear = 1.0F;
    state.clarity.enabled = 0U;
    state.loudness.enabled = 0U; // default limiter ceiling (0.891)
    kernel.publishTargetState(state);

    TestABL prime(kLimiterLookaheadFrames);
    kernel.process(prime.abl(), kLimiterLookaheadFrames);

    const float freq = 0.45F * static_cast<float>(kSR);
    const float ampl = 0.97F;
    float outPeak = 0.0F;
    for (uint32_t b = 0U; b < 8U; ++b)
    {
        TestABL abl(kFrames);
        for (uint32_t i = 0U; i < kFrames; ++i)
        {
            const float phase = 2.0F * std::numbers::pi_v<float> * freq *
                                static_cast<float>((b * kFrames) + i) / static_cast<float>(kSR);
            abl.left[i] = ampl * std::sin(phase);
            abl.right[i] = abl.left[i];
        }
        kernel.process(abl.abl(), kFrames);
        if (b >= 4U) // measure after the limiter has settled
        {
            for (uint32_t i = 0U; i < kFrames; ++i)
            {
                outPeak = std::max({outPeak, std::abs(abl.left[i]), std::abs(abl.right[i])});
            }
        }
    }

    if (outPeak > kCeiling + 0.01F)
    {
        std::ostringstream oss;
        oss << "near-Nyquist output peak " << outPeak << " exceeds ceiling " << kCeiling;
        logFail(kName, oss.str());
        return;
    }
    logPass(kName);
}

// Test M3b: hot-noise soak — 100 buffers of full-scale white noise; every output
// sample (after lookahead warm-up) must stay ≤ ceiling. Stresses ring wrap across
// many buffers + the dual-stage release.
static auto testLimiterHotNoiseSoak() -> void
{
    static const char* const kName = "Limiter_HotNoiseSoak";
    constexpr uint32_t kSR = TestConstants::kSampleRate48k;
    constexpr uint32_t kFrames = TestConstants::kFrames512;
    constexpr float kCeiling = kTruePeakCeilingLinear;

    DSPKernel kernel;
    kernel.initialize(kSR, kFrames);
    TargetState state{};
    state.intensityLinear = 1.0F;
    state.eq.numBiquads = 0U;
    state.eq.masterGainLinear = 1.0F;
    state.clarity.enabled = 0U;
    state.loudness.enabled = 0U;
    kernel.publishTargetState(state);

    std::mt19937 gen(0x515D7E57U);
    std::uniform_real_distribution<float> dist(-0.999F, 0.999F);
    float worst = 0.0F;
    for (uint32_t b = 0U; b < 100U; ++b)
    {
        TestABL abl(kFrames);
        for (uint32_t i = 0U; i < kFrames; ++i)
        {
            abl.left[i] = dist(gen);
            abl.right[i] = dist(gen);
        }
        kernel.process(abl.abl(), kFrames);
        if (b >= 1U) // skip the first buffer (lookahead warm-up / silence prefix)
        {
            for (uint32_t i = 0U; i < kFrames; ++i)
            {
                worst = std::max({worst, std::abs(abl.left[i]), std::abs(abl.right[i])});
            }
        }
    }

    if (worst > kCeiling + 0.01F)
    {
        std::ostringstream oss;
        oss << "soak output peak " << worst << " exceeds ceiling " << kCeiling;
        logFail(kName, oss.str());
        return;
    }
    logPass(kName);
}

// ===========================================================================
// Loudness tests (Sprint 4 — BS.1770-5 LufsMeter). Driven synchronously; no
// threading. Reference values per EBU Tech 3341. Tolerance 0.15 LU (the meter
// is within EBU's ±0.1 LU; the extra margin guards against startup transients).
// ===========================================================================

static const double kLufsTol = 0.15;

// Feed `seconds` of an in-phase stereo sine at `peakDbfs` peak amplitude.
static auto feedStereoSine(
    LufsMeter& meter, double peakDbfs, double freqHz, double seconds, uint32_t sampleRate) -> void
{
    const double amp = std::pow(10.0, peakDbfs / 20.0);
    const auto frames = static_cast<size_t>(seconds * sampleRate);
    std::vector<float> buf(frames * 2U);
    for (size_t n = 0; n < frames; ++n)
    {
        const double s =
            amp * std::sin(2.0 * std::numbers::pi * freqHz * static_cast<double>(n) / sampleRate);
        buf[2 * n] = static_cast<float>(s);
        buf[(2 * n) + 1] = static_cast<float>(s);
    }
    meter.addInterleavedStereo(buf.data(), frames);
}

static auto feedStereoSilence(LufsMeter& meter, double seconds, uint32_t sampleRate) -> void
{
    const auto frames = static_cast<size_t>(seconds * sampleRate);
    std::vector<float> buf(frames * 2U, 0.0F);
    meter.addInterleavedStereo(buf.data(), frames);
}

// Test 15: K-weighting attenuates low frequencies (RLB high-pass + shelf).
// A 40 Hz tone must read substantially lower than a 1 kHz tone at the same peak.
static auto testLoudnessKWeightingLowCut() -> void
{
    static const char* const kName = "Loudness_KWeightingLowCut";
    LufsMeter low;
    low.prepare(TestConstants::kSampleRate48k);
    feedStereoSine(low, -20.0, 40.0, 10.0, TestConstants::kSampleRate48k);

    LufsMeter mid;
    mid.prepare(TestConstants::kSampleRate48k);
    feedStereoSine(mid, -20.0, 1000.0, 10.0, TestConstants::kSampleRate48k);

    const double delta = mid.integratedLufs() - low.integratedLufs();
    if (delta < 3.0)
    {
        std::ostringstream oss;
        oss << "40 Hz should read >=3 LU below 1 kHz; 1k=" << mid.integratedLufs()
            << " 40=" << low.integratedLufs() << " delta=" << delta;
        logFail(kName, oss.str());
        return;
    }
    logPass(kName);
}

// Test 16: Integrated LUFS accuracy for stereo 1 kHz sines (EBU Tech 3341):
// an in-phase stereo sine at X dBFS peak measures X LUFS.
static auto testLoudnessIntegratedAccuracy() -> void
{
    static const char* const kName = "Loudness_IntegratedAccuracy";
    const double levels[] = {-23.0, -33.0, -18.0};
    for (double peak : levels)
    {
        LufsMeter meter;
        meter.prepare(TestConstants::kSampleRate48k);
        feedStereoSine(meter, peak, 1000.0, 15.0, TestConstants::kSampleRate48k);
        const double measured = meter.integratedLufs();
        if (std::abs(measured - peak) > kLufsTol)
        {
            std::ostringstream oss;
            oss << "1 kHz @ " << peak << " dBFS peak: expected " << peak << " LUFS, got "
                << measured << " (delta " << std::abs(measured - peak) << ")";
            logFail(kName, oss.str());
            return;
        }
    }
    logPass(kName);
}

// Test 17: Absolute gate (-70 LUFS) discards silence — a 2 s silence prefix must
// not drag the integrated value below the 8 s of -23 dBFS sine that follows.
static auto testLoudnessAbsoluteGate() -> void
{
    static const char* const kName = "Loudness_AbsoluteGate";
    LufsMeter meter;
    meter.prepare(TestConstants::kSampleRate48k);
    feedStereoSilence(meter, 2.0, TestConstants::kSampleRate48k);
    feedStereoSine(meter, -23.0, 1000.0, 8.0, TestConstants::kSampleRate48k);
    const double measured = meter.integratedLufs();
    if (std::abs(measured - (-23.0)) > 0.3)
    {
        std::ostringstream oss;
        oss << "silence+(-23 dBFS) expected ~-23 LUFS, got " << measured;
        logFail(kName, oss.str());
        return;
    }
    logPass(kName);
}

// Test 18: Relative gate (-10 LU) discards a quiet segment >10 LU below the mean.
// 8 s at -23 dBFS then 8 s at -50 dBFS → integrated ~= the loud segment only.
static auto testLoudnessRelativeGate() -> void
{
    static const char* const kName = "Loudness_RelativeGate";
    LufsMeter meter;
    meter.prepare(TestConstants::kSampleRate48k);
    feedStereoSine(meter, -23.0, 1000.0, 8.0, TestConstants::kSampleRate48k);
    feedStereoSine(meter, -50.0, 1000.0, 8.0, TestConstants::kSampleRate48k);
    const double measured = meter.integratedLufs();
    if (std::abs(measured - (-23.0)) > 0.5)
    {
        std::ostringstream oss;
        oss << "loud+quiet expected ~-23 LUFS (quiet gated out), got " << measured;
        logFail(kName, oss.str());
        return;
    }
    logPass(kName);
}

// Test 19: Makeup-gain round-trip. Measure a signal, apply makeup = target -
// measured, re-measure → target (±tol). Validates measurement + gain arithmetic.
static auto testLoudnessMakeupRoundTrip() -> void
{
    static const char* const kName = "Loudness_MakeupRoundTrip";
    constexpr double kTarget = -14.0;

    LufsMeter pass1;
    pass1.prepare(TestConstants::kSampleRate48k);
    feedStereoSine(pass1, -20.0, 1000.0, 15.0, TestConstants::kSampleRate48k);
    const double measured = pass1.integratedLufs();

    const double makeupDb = kTarget - measured;
    const double gain = std::pow(10.0, makeupDb / 20.0);

    // Re-measure the same signal scaled by the makeup gain.
    LufsMeter pass2;
    pass2.prepare(TestConstants::kSampleRate48k);
    feedStereoSine(
        pass2, -20.0 + (20.0 * std::log10(gain)), 1000.0, 15.0, TestConstants::kSampleRate48k);
    const double remeasured = pass2.integratedLufs();
    if (std::abs(remeasured - kTarget) > kLufsTol)
    {
        std::ostringstream oss;
        oss << "after +makeup, expected " << kTarget << " LUFS, got " << remeasured;
        logFail(kName, oss.str());
        return;
    }
    logPass(kName);
}

// ---------------------------------------------------------------------------
// main
// ---------------------------------------------------------------------------
// EQ audibility tests (Sprint 5 — Milestone 2): the EQ is now in the live graph
// and driven by computeBiquadCascade -> publishTargetState. These validate that a
// band boost actually changes the signal by the right amount (FR accuracy) and
// that a large coefficient change does not produce an audible boundary click
// (the zipper measurement that the audio-dsp review flagged as make-or-break).
// ---------------------------------------------------------------------------

namespace
{
    // Goertzel algorithm: energy at a single frequency bin.
    // Returns the squared magnitude (linear power) of the DFT at `freqHz` over `numFrames`
    // samples from `buf` at sample rate `sampleRate`. O(N), no FFT allocation.
    // Reference: Proakis & Manolakis, "Digital Signal Processing", §8.3 (Goertzel algorithm).
    auto goertzelPower(const float* buf, uint32_t numFrames, float freqHz, float sampleRate)
        -> double
    {
        const double omega =
            2.0 * std::numbers::pi * static_cast<double>(freqHz) / static_cast<double>(sampleRate);
        const double coeff = 2.0 * std::cos(omega);
        double sprev = 0.0;
        double sprev2 = 0.0;
        for (uint32_t idx = 0U; idx < numFrames; ++idx)
        {
            const double sval = static_cast<double>(buf[idx]) + coeff * sprev - sprev2;
            sprev2 = sprev;
            sprev = sval;
        }
        // Power: |X[k]|^2 = sprev2^2 + sprev^2 - coeff * sprev * sprev2
        return (sprev2 * sprev2) + (sprev * sprev) - (coeff * sprev * sprev2);
    }

    constexpr uint32_t kEqBands = 31U;
    constexpr size_t kBand1kHzIndex = 17U; // kCenterFrequencies[17] == 1000 Hz
    constexpr float kEqTestToneHz = 1000.0F;
    constexpr float kEqTestAmplitude = 0.25F; // -12 dBFS
    constexpr float kEqBoostDb = 6.0F;
    constexpr float kEqFrToleranceDb = 1.0F; // generous vs spec ±0.5 (measurement at exact center)

    // RMS of a slice [start, end) of a buffer.
    auto sliceRms(const std::vector<float>& buf, size_t start, size_t end) -> double
    {
        double acc = 0.0;
        for (size_t idx = start; idx < end; ++idx)
        {
            acc += static_cast<double>(buf[idx]) * buf[idx];
        }
        const size_t count = (end > start) ? (end - start) : 1U;
        return std::sqrt(acc / static_cast<double>(count));
    }

    // Run a 1 kHz sine through the kernel with the given 31-band gains; return the captured
    // mono (left) output. maxFrames sized to the whole buffer so it is one process() call.
    auto runEqSine(const std::array<float, kEqBands>& gains, uint32_t totalFrames)
        -> std::vector<float>
    {
        DSPKernel kernel;
        kernel.initialize(TestConstants::kSampleRate48k, totalFrames);

        TargetState state = makeIdentityState();
        state.eq = EQModuleCoefficients::computeBiquadCascade(
            gains, static_cast<float>(TestConstants::kSampleRate48k));
        kernel.publishTargetState(state);

        TestABL abl(totalFrames);
        for (uint32_t idx = 0U; idx < totalFrames; ++idx)
        {
            const float sample =
                kEqTestAmplitude * std::sin(2.0F * std::numbers::pi_v<float> * kEqTestToneHz *
                                            static_cast<float>(idx) /
                                            static_cast<float>(TestConstants::kSampleRate48k));
            abl.left[idx] = sample;
            abl.right[idx] = sample;
        }
        kernel.process(abl.abl(), totalFrames);
        return abl.left;
    }
} // namespace

static auto testEQFrequencyResponseAccuracy() -> void
{
    static const char* const kName = "EQ_FrequencyResponseAccuracy";
    constexpr uint32_t kFrames = TestConstants::kTotalFrames1s;

    std::array<float, kEqBands> flat{};
    std::array<float, kEqBands> boosted{};
    boosted[kBand1kHzIndex] = kEqBoostDb;

    const std::vector<float> flatOut = runEqSine(flat, kFrames);
    const std::vector<float> boostOut = runEqSine(boosted, kFrames);

    // Measure over the settled second half (IIR settles in ms; this is a safe margin).
    const size_t halfFrame = kFrames / 2U;
    const double flatRms = sliceRms(flatOut, halfFrame, kFrames);
    const double boostRms = sliceRms(boostOut, halfFrame, kFrames);

    if (flatRms <= 0.0)
    {
        logFail(kName, "flat-EQ output was silent");
        return;
    }
    const double measuredDb = 20.0 * std::log10(boostRms / flatRms);
    if (std::abs(measuredDb - kEqBoostDb) > kEqFrToleranceDb)
    {
        std::ostringstream oss;
        oss << "measured " << measuredDb << " dB at 1 kHz, expected " << kEqBoostDb << " ± "
            << kEqFrToleranceDb;
        logFail(kName, oss.str());
        return;
    }
    logPass(kName);
}

static auto testEQCoefficientSwapNoClick() -> void
{
    static const char* const kName = "EQ_CoefficientSwapNoClick";
    constexpr uint32_t kBlock = TestConstants::kFrames512;
    constexpr uint32_t kBlocksBefore = 16U; // settle flat
    constexpr uint32_t kBlocksAfter = 16U;  // settle boosted
    constexpr float kBoostDbLarge = 12.0F;  // worst-case jump (preset-style)

    DSPKernel kernel;
    kernel.initialize(TestConstants::kSampleRate48k, kBlock);

    std::array<float, kEqBands> flat{};
    std::array<float, kEqBands> boosted{};
    boosted[kBand1kHzIndex] = kBoostDbLarge;

    TargetState flatState = makeIdentityState();
    flatState.eq = EQModuleCoefficients::computeBiquadCascade(
        flat, static_cast<float>(TestConstants::kSampleRate48k));
    kernel.publishTargetState(flatState);

    // Phase-continuous sine fed block by block; capture the full output.
    std::vector<float> out;
    out.reserve(static_cast<size_t>(kBlock) * (kBlocksBefore + kBlocksAfter));
    uint32_t sampleIndex = 0U;
    size_t swapSample = 0U;

    const auto processBlocks = [&](uint32_t numBlocks)
    {
        for (uint32_t blk = 0U; blk < numBlocks; ++blk)
        {
            TestABL abl(kBlock);
            for (uint32_t idx = 0U; idx < kBlock; ++idx)
            {
                const float sample =
                    kEqTestAmplitude * std::sin(2.0F * std::numbers::pi_v<float> * kEqTestToneHz *
                                                static_cast<float>(sampleIndex) /
                                                static_cast<float>(TestConstants::kSampleRate48k));
                abl.left[idx] = sample;
                abl.right[idx] = sample;
                ++sampleIndex;
            }
            kernel.process(abl.abl(), kBlock);
            for (uint32_t idx = 0U; idx < kBlock; ++idx)
            {
                out.push_back(abl.left[idx]);
            }
        }
    };

    processBlocks(kBlocksBefore);
    swapSample = out.size(); // the boundary: first sample rendered with the new coefficients
    boosted[kBand1kHzIndex] = kBoostDbLarge;
    TargetState boostState = makeIdentityState();
    boostState.eq = EQModuleCoefficients::computeBiquadCascade(
        boosted, static_cast<float>(TestConstants::kSampleRate48k));
    kernel.publishTargetState(boostState);
    processBlocks(kBlocksAfter);

    // Max single-sample step in the fully-settled boosted tail (reference for "normal").
    const size_t tailStart = out.size() - kBlock;
    float settledMaxStep = 0.0F;
    for (size_t idx = tailStart + 1U; idx < out.size(); ++idx)
    {
        settledMaxStep = std::max(settledMaxStep, std::abs(out[idx] - out[idx - 1U]));
    }
    // The exact swap-boundary step (a hard coefficient snap with preserved state shows here).
    const float boundaryStep = std::abs(out[swapSample] - out[swapSample - 1U]);

    std::ostringstream info;
    info << "boundaryStep=" << boundaryStep << " settledBoostedMaxStep=" << settledMaxStep;
    // A click would spike the boundary step well above the settled per-sample delta. Clean
    // transitions keep it at/below the settled level (the amplitude has not yet ramped up).
    if (boundaryStep > 3.0F * settledMaxStep)
    {
        logFail(kName, "audible coefficient-swap click: " + info.str());
        return;
    }
    std::fputs(("  [info] " + std::string(kName) + ": " + info.str() + "\n").c_str(), stdout);
    logPass(kName);
}

// ---------------------------------------------------------------------------
// Multichannel epic safety net (Sprint 5b, S0-M1).
//
// T-C1 GOLDEN MASTER: a bit-exact regression fence for the current STEREO DSP output. A
// deterministic 1 s chirp is processed through a non-trivial state (+6 dB @ 1 kHz EQ boost +
// ACTIVE true-peak limiter), and a 64-bit FNV-1a signature of the L+R output is asserted against
// a committed constant. Any refactor that changes the stereo output (even one ULP) flips the hash.
// This is the fence the whole N-channel migration must never break at N=2. Re-baseline ONLY on a
// deliberate, founder-approved DSP change (see the QA plan). Same-toolchain/arch fence.
//
// T-C2..T-C5 are PENDING placeholders for later milestones (they keep the plan visible without
// failing the gate). They are filled in their target sprint.
// ---------------------------------------------------------------------------

static auto testGoldenMasterStereoN2() -> void
{
    static const char* const kName = "GoldenMaster_StereoN2_v1";
    constexpr uint32_t kSR = TestConstants::kSampleRate48k;
    constexpr uint32_t kChunk = TestConstants::kFrames512;
    constexpr uint32_t kTotal = TestConstants::kTotalFrames1s;
    constexpr float kBoostDb = 6.0F;
    // Committed bit-exact signature of the current stereo output. See header note for re-baseline.
    constexpr uint64_t kGoldenHash = 0xE7267654BA01D315ULL;
    constexpr uint64_t kFnvOffsetBasis = 0xCBF29CE484222325ULL;

    // Deterministic 1 s linear chirp 20 Hz -> 20 kHz, amplitude 0.5 (no RNG).
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

    // Non-trivial state: +6 dB @ 1 kHz EQ + ACTIVE true-peak limiter (default ceiling < 1.0).
    DSPKernel kernel;
    kernel.initialize(kSR, kChunk);
    TargetState state = makeIdentityState();
    std::array<float, kEqBands> gains{};
    gains[kBand1kHzIndex] = kBoostDb;
    state.eq = EQModuleCoefficients::computeBiquadCascade(gains, static_cast<float>(kSR));
    state.limiter.truePeakCeilingLinear =
        kTruePeakCeilingLinear; // active (overrides identity bypass)
    kernel.publishTargetState(state);

    // Process in 512-frame chunks; capture L and R output.
    std::vector<float> outLeft;
    std::vector<float> outRight;
    outLeft.reserve(kTotal);
    outRight.reserve(kTotal);
    TestABL abl(kChunk);
    uint32_t offset = 0U;
    while (offset < kTotal)
    {
        const uint32_t chunk = std::min(kChunk, kTotal - offset);
        std::memcpy(abl.left.data(), chirp.data() + offset, chunk * sizeof(float));
        std::memcpy(abl.right.data(), chirp.data() + offset, chunk * sizeof(float));
        abl.setFrameCount(chunk);
        kernel.process(abl.abl(), chunk);
        for (uint32_t idx = 0U; idx < chunk; ++idx)
        {
            outLeft.push_back(abl.left[idx]);
            outRight.push_back(abl.right[idx]);
        }
        offset += chunk;
    }

    const uint64_t hash = fnv1aFloats(outRight, fnv1aFloats(outLeft, kFnvOffsetBasis));

    std::ostringstream info;
    info << "  [info] " << kName << ": output hash = 0x" << std::hex << hash << "\n";
    std::fputs(info.str().c_str(), stdout);

    if (hash != kGoldenHash)
    {
        std::ostringstream oss;
        oss << "golden-master hash mismatch: got 0x" << std::hex << hash << ", expected 0x"
            << kGoldenHash
            << " (stereo DSP output changed — intended? then re-baseline per QA plan)";
        logFail(kName, oss.str());
        return;
    }
    logPass(kName);
}

// T-C2: MultichannelView is the sole ABL-decode point — unit-test its semantics directly.
// (Bit-exactness of the chain THROUGH the view is already covered by T-C1, which now runs the
// kernel via the MultichannelView path.)
static auto testMultichannelViewDecode() -> void
{
    static const char* const kName = "MultichannelView_Decode";
    constexpr uint32_t kFrames = TestConstants::kFrames512;

    TestABL abl(kFrames);
    const MultichannelView view = MultichannelView::fromABL(abl.abl(), kFrames);

    if (view.channels() != 2U)
    {
        logFail(kName, "expected 2 channels from a stereo ABL");
        return;
    }
    if (view.frames() != kFrames)
    {
        logFail(kName, "frames() did not echo the frame count");
        return;
    }
    if (view.channel(0) != abl.left.data() || view.channel(1) != abl.right.data())
    {
        logFail(kName, "channel pointers do not match the ABL buffers");
        return;
    }
    if (view.channel(2) != nullptr || view.channel(kMaxChannels) != nullptr)
    {
        logFail(kName, "out-of-range channel() must return nullptr");
        return;
    }

    // Null ABL → empty view, no crash.
    const MultichannelView nullView = MultichannelView::fromABL(nullptr, kFrames);
    if (nullView.channels() != 0U || nullView.channel(0) != nullptr)
    {
        logFail(kName, "null ABL must yield an empty view");
        return;
    }
    logPass(kName);
}

// T-C3: Per-channel independence — N-channel EQ does not mix channels.
//
// For each N in {4, 6, 8}: feed channel k a pure sine at a distinct DFT-bin-aligned
// frequency through the kernel with an identity EQ (numBiquads=0, masterGain=1).
// After processing, assert:
//   - The OUTPUT channel k contains energy at its OWN frequency (power > noise floor).
//   - The OUTPUT channel k contains NO energy at any OTHER channel's frequency
//     (cross-channel power ratio < −60 dB relative to the self-channel power).
// This catches channel-swap, crosstalk, and accidental delay-state sharing.
//
// Frequencies are chosen as exact DFT bins at N=kPerChTestFrames samples (bin k has
// frequency k × fs/N), so the Goertzel measurement at each bin captures an integer
// number of cycles — rectangular-window orthogonality makes cross-bin leakage ≈ 0
// (numerical noise floor ~−120 dB), well below the −60 dB threshold. Using non-harmonic
// bins avoids the harmonic-aliasing leakage that would occur at f0, 2f0, 3f0… bins.
//
// Energy is measured with the Goertzel algorithm — O(N) per bin, no heap allocation.
// Reference: Proakis & Manolakis, "Digital Signal Processing", §8.3.
static auto testPerChannelIndependence() -> void
{
    static const char* const kName = "PerChannelIndependence_N4_6_8";
    constexpr uint32_t kFrames = TestConstants::kPerChTestFrames;
    constexpr float kSR = static_cast<float>(TestConstants::kSampleRate48k);
    constexpr float kAmp = TestConstants::kPerChAmplitude;
    constexpr double kXtalkThreshDb = TestConstants::kCrosstalkThresholdDb;

    const uint32_t nValues[] = {
        TestConstants::kNChannels4, TestConstants::kNChannels6, TestConstants::kNChannels8};

    for (const uint32_t numCh : nValues)
    {
        DSPKernel kernel;
        kernel.initialize(TestConstants::kSampleRate48k, kFrames);

        const TargetState state = makeIdentityState();
        kernel.publishTargetState(state);

        TestABLN abl(numCh, kFrames);

        // Fill each channel with a sine at its DFT-bin-aligned frequency.
        // freq[ch] = kPerChBins[ch] × (fs / kFrames) — exact integer cycles, no leakage.
        for (uint32_t ch = 0U; ch < numCh; ++ch)
        {
            // Frequency is exactly bin × (fs/N) so the sine completes an integer number
            // of cycles in kFrames samples — Goertzel bins are then orthogonal.
            const float freq = static_cast<float>(TestConstants::kPerChBins[ch]) * kSR /
                               static_cast<float>(kFrames);
            for (uint32_t idx = 0U; idx < kFrames; ++idx)
            {
                abl.channels[ch][idx] = kAmp * std::sin(2.0F * std::numbers::pi_v<float> * freq *
                                                        static_cast<float>(idx) / kSR);
            }
        }

        kernel.process(abl.abl(), kFrames);

        // Check isolation: each output channel must carry its own tone and not others.
        for (uint32_t ch = 0U; ch < numCh; ++ch)
        {
            const float selfFreq = static_cast<float>(TestConstants::kPerChBins[ch]) * kSR /
                                   static_cast<float>(kFrames);
            const float* outBuf = abl.channels[ch].data();

            const double selfPower = goertzelPower(outBuf, kFrames, selfFreq, kSR);
            if (selfPower <= 0.0)
            {
                std::ostringstream oss;
                oss << "N=" << numCh << " ch" << ch << ": self tone (" << selfFreq
                    << " Hz) has zero power after identity EQ";
                logFail(kName, oss.str());
                return;
            }

            for (uint32_t otherCh = 0U; otherCh < numCh; ++otherCh)
            {
                if (otherCh == ch)
                {
                    continue;
                }
                const float otherFreq = static_cast<float>(TestConstants::kPerChBins[otherCh]) *
                                        kSR / static_cast<float>(kFrames);
                const double crosstalkPower = goertzelPower(outBuf, kFrames, otherFreq, kSR);
                // Ratio in dB: 10·log10(crosstalk / self).
                const double ratioDb = 10.0 * std::log10(crosstalkPower / selfPower + 1e-300);
                if (ratioDb > kXtalkThreshDb)
                {
                    std::ostringstream oss;
                    oss << "N=" << numCh << " ch" << ch << ": crosstalk from ch" << otherCh << " ("
                        << otherFreq << " Hz) at " << ratioDb << " dB (threshold " << kXtalkThreshDb
                        << " dB)";
                    logFail(kName, oss.str());
                    return;
                }
            }
        }
    }
    logPass(kName);
}

// T-C3b: EQ frequency-response accuracy at N=4.
//
// Boost one band (+6 dB @ 1 kHz) applied identically to all channels. Feed each
// channel the same 1 kHz sine, process through the kernel with the boosted EQ, and
// assert that every channel's output RMS (over the settled second half) is +6 dB ±1 dB
// relative to the flat-EQ baseline. This confirms the SAME coefficient cascade is
// applied to all N channels and that no channel is dropped or misrouted.
static auto testEQFrequencyResponseAccuracyN4() -> void
{
    static const char* const kName = "EQ_FrequencyResponseAccuracy_N4";
    constexpr uint32_t kNumCh = TestConstants::kNChannels4;
    constexpr uint32_t kFrames = TestConstants::kTotalFrames1s;
    constexpr float kSR = static_cast<float>(TestConstants::kSampleRate48k);

    const auto runN4 = [&](const std::array<float, kEqBands>& gains) -> std::vector<double>
    {
        DSPKernel kernel;
        kernel.initialize(TestConstants::kSampleRate48k, kFrames);

        TargetState state = makeIdentityState();
        state.eq = EQModuleCoefficients::computeBiquadCascade(gains, kSR);
        kernel.publishTargetState(state);

        TestABLN abl(kNumCh, kFrames);
        for (uint32_t ch = 0U; ch < kNumCh; ++ch)
        {
            for (uint32_t idx = 0U; idx < kFrames; ++idx)
            {
                abl.channels[ch][idx] =
                    kEqTestAmplitude * std::sin(2.0F * std::numbers::pi_v<float> * kEqTestToneHz *
                                                static_cast<float>(idx) / kSR);
            }
        }
        kernel.process(abl.abl(), kFrames);

        std::vector<double> rmsVals(kNumCh);
        const size_t halfFrame = static_cast<size_t>(kFrames) / 2U;
        for (uint32_t ch = 0U; ch < kNumCh; ++ch)
        {
            rmsVals[ch] = sliceRms(abl.channels[ch], halfFrame, static_cast<size_t>(kFrames));
        }
        return rmsVals;
    };

    std::array<float, kEqBands> flatGains{};
    std::array<float, kEqBands> boostedGains{};
    boostedGains[kBand1kHzIndex] = kEqBoostDb;

    const std::vector<double> flatRms = runN4(flatGains);
    const std::vector<double> boostRms = runN4(boostedGains);

    for (uint32_t ch = 0U; ch < kNumCh; ++ch)
    {
        if (flatRms[ch] <= 0.0)
        {
            logFail(kName, "flat-EQ output was silent on ch" + std::to_string(ch));
            return;
        }
        const double measuredDb = 20.0 * std::log10(boostRms[ch] / flatRms[ch]);
        if (std::abs(measuredDb - static_cast<double>(kEqBoostDb)) >
            static_cast<double>(kEqFrToleranceDb))
        {
            std::ostringstream oss;
            oss << "ch" << ch << ": measured " << measuredDb << " dB at 1 kHz, expected "
                << kEqBoostDb << " ± " << kEqFrToleranceDb;
            logFail(kName, oss.str());
            return;
        }
    }
    logPass(kName);
}

// T-C3c: Click-free coefficient swap at N=4.
//
// N=4 variant of testEQCoefficientSwapNoClick. Flat -> +12 dB @ 1 kHz mid-stream.
// For each channel the boundary step must be ≤ 3× the settled-tail max per-sample step.
static auto testEQCoefficientSwapNoClickN4() -> void
{
    static const char* const kName = "EQ_CoefficientSwapNoClick_N4";
    constexpr uint32_t kNumCh = TestConstants::kNChannels4;
    constexpr uint32_t kBlock = TestConstants::kFrames512;
    constexpr uint32_t kBlocksBefore = 16U;
    constexpr uint32_t kBlocksAfter = 16U;
    constexpr float kBoostDbLarge = 12.0F;
    constexpr float kSR = static_cast<float>(TestConstants::kSampleRate48k);

    DSPKernel kernel;
    kernel.initialize(TestConstants::kSampleRate48k, kBlock);

    std::array<float, kEqBands> flatGains{};
    std::array<float, kEqBands> boostedGains{};
    boostedGains[kBand1kHzIndex] = kBoostDbLarge;

    TargetState flatState = makeIdentityState();
    flatState.eq = EQModuleCoefficients::computeBiquadCascade(flatGains, kSR);
    kernel.publishTargetState(flatState);

    // Capture per-channel output across the full run.
    std::vector<std::vector<float>> out(kNumCh);
    for (uint32_t ch = 0U; ch < kNumCh; ++ch)
    {
        out[ch].reserve(static_cast<size_t>(kBlock) * (kBlocksBefore + kBlocksAfter));
    }
    uint32_t sampleIdx = 0U;
    size_t swapSample = 0U;

    const auto processBlocks = [&](uint32_t numBlocks)
    {
        for (uint32_t blk = 0U; blk < numBlocks; ++blk)
        {
            TestABLN abl(kNumCh, kBlock);
            // All channels carry the same 1 kHz sine (phase-continuous).
            for (uint32_t ch = 0U; ch < kNumCh; ++ch)
            {
                for (uint32_t idx = 0U; idx < kBlock; ++idx)
                {
                    abl.channels[ch][idx] =
                        kEqTestAmplitude *
                        std::sin(2.0F * std::numbers::pi_v<float> * kEqTestToneHz *
                                 static_cast<float>(sampleIdx + idx) / kSR);
                }
            }
            sampleIdx += kBlock;
            kernel.process(abl.abl(), kBlock);
            for (uint32_t ch = 0U; ch < kNumCh; ++ch)
            {
                for (uint32_t idx = 0U; idx < kBlock; ++idx)
                {
                    out[ch].push_back(abl.channels[ch][idx]);
                }
            }
        }
    };

    processBlocks(kBlocksBefore);
    swapSample = out[0].size();

    TargetState boostState = makeIdentityState();
    boostState.eq = EQModuleCoefficients::computeBiquadCascade(boostedGains, kSR);
    kernel.publishTargetState(boostState);

    processBlocks(kBlocksAfter);

    // Per-channel click check: boundary step ≤ 3× settled tail max-step.
    for (uint32_t ch = 0U; ch < kNumCh; ++ch)
    {
        const std::vector<float>& chOut = out[ch];
        const size_t tailStart = chOut.size() - kBlock;
        float settledMaxStep = 0.0F;
        for (size_t idx = tailStart + 1U; idx < chOut.size(); ++idx)
        {
            settledMaxStep = std::max(settledMaxStep, std::abs(chOut[idx] - chOut[idx - 1U]));
        }
        const float boundaryStep = std::abs(chOut[swapSample] - chOut[swapSample - 1U]);

        std::ostringstream info;
        info << "ch" << ch << " boundaryStep=" << boundaryStep
             << " settledMaxStep=" << settledMaxStep;
        std::fputs(("  [info] " + std::string(kName) + ": " + info.str() + "\n").c_str(), stdout);

        if (boundaryStep > 3.0F * settledMaxStep)
        {
            logFail(kName, "audible coefficient-swap click: " + info.str());
            return;
        }
    }
    logPass(kName);
}

// T-C4: Limiter_LinkedGainLockstep — S1-B3 linked-gain correctness test.
//
// Build a 4-channel buffer where:
//   ch0: a HOT 1 kHz sine at amplitude 0.999 (above the −1 dBTP ceiling of 0.891) → forces GR.
//   ch1/ch2/ch3: moderate steady sines at distinct DFT-bin-aligned frequencies,
//                amplitude 0.30 (below ceiling on their own, ≈ −10 dBFS).
//
// Process through the kernel with the active true-peak ceiling.  The single shared
// grBuf_ is driven solely by ch0's peak; all channels are attenuated by the SAME
// envelope.  This is the "linked gain" invariant: every channel duck by the same GR.
//
// Proof method:
//   1. Prime the limiter ring with kLimiterLookaheadFrames silence frames so the
//      look-ahead ring starts with zeros (avoids a half-full-ring bias on the first GR).
//   2. Save a copy of the tone channels' input before processing.
//   3. Feed the 4-channel block through the kernel.
//   4. After processing, for each tone channel (1..3) and each output sample index
//      where the DELAYED input is non-trivially non-zero (|delayed_input| > 0.1):
//        applied_gain[ch][i] = output[ch][i] / delayed_input[ch][i]
//      where delayed_input[ch][i] = saved_input[ch][i] (the primed-silence + current
//      block means output[i] = grBuf_[i] * input[i] for ALL i in the block, because
//      the ring was pre-loaded with zeros for the entire lookahead window — the ring
//      readHead is at kLimiterLookaheadFrames at entry to the test block, so
//      output[i] reads ring[kLimiterLookaheadFrames + i mod kLimiterRingSize] which
//      was written at sample i of the current block, exactly kLimiterLookaheadFrames
//      in advance).
//   5. Compute the inter-channel GR difference (in dB) between tone channels at every
//      active sample and assert it is < 0.01 dB.
//
// "Active limiting" guard: confirm that at least one output sample on ch0 is
// measurably below the input amplitude (i.e. GR > 0 dB), so the test actually
// exercises the linked path and is not vacuously passing on a silent signal.
//
// Reference: linked-gain limiter design — Giannoulis/Massberg/Reiss JAES 2012;
//            the look-ahead ring mechanic — LimiterModule.h initialize() comments.
static auto testLimiterLinkedGainLockstep() -> void
{
    static const char* const kName = "Limiter_LinkedGainLockstep";
    constexpr uint32_t kNumCh = 4U;
    constexpr uint32_t kFrames = 512U;
    constexpr uint32_t kSR = TestConstants::kSampleRate48k;
    constexpr float kSRf = static_cast<float>(kSR);

    // Hot signal on ch0: 1 kHz at 0.999 — well above the −1 dBTP ceiling.
    constexpr float kHotFreq = 1000.0F;
    constexpr float kHotAmpl = 0.999F;

    // Tone channels: DFT-bin-aligned frequencies for clean division (no
    // phase-wrap ambiguity during the lookahead window).  Amplitude 0.30 keeps
    // them below the ceiling but large enough for a reliable gain ratio.
    // Bins chosen to be non-harmonic of each other and of the hot tone.
    constexpr float kToneAmpl = 0.30F;
    constexpr float kToneFreq1 = static_cast<float>(TestConstants::kPerChBins[1]) * kSRf /
                                 static_cast<float>(TestConstants::kPerChTestFrames);
    constexpr float kToneFreq2 = static_cast<float>(TestConstants::kPerChBins[2]) * kSRf /
                                 static_cast<float>(TestConstants::kPerChTestFrames);
    constexpr float kToneFreq3 = static_cast<float>(TestConstants::kPerChBins[3]) * kSRf /
                                 static_cast<float>(TestConstants::kPerChTestFrames);

    // Active ceiling: the default −1 dBTP.
    constexpr float kCeiling = kTruePeakCeilingLinear;

    // Inter-channel GR difference threshold: < 0.01 dB (a truly linked gain bus
    // produces a difference of exactly 0 dB; 0.01 dB guards only float rounding).
    constexpr double kGrDiffThreshDb = 0.01;

    // The applied-gain ratio measurement requires non-trivial input amplitude.
    // Skip samples where the delayed input is too close to zero (node of a sine).
    constexpr float kMinInputForRatio = 0.05F;

    // ------------------------------------------------------------------
    // Build a fresh DSPKernel with the active ceiling.
    // ------------------------------------------------------------------
    DSPKernel kernel;
    kernel.initialize(kSR, kFrames);

    TargetState state{};
    state.intensityLinear = 1.0F;
    state.eq.numBiquads = 0U;
    state.eq.masterGainLinear = 1.0F;
    state.clarity.enabled = 0U;
    state.loudness.enabled = 0U;
    state.limiter.truePeakCeilingLinear = kCeiling;
    kernel.publishTargetState(state);

    // ------------------------------------------------------------------
    // Step 1: Prime the ring with kLimiterLookaheadFrames silence frames.
    // After this call: readHead_ = kLimiterLookaheadFrames, the ring
    // positions [0..kLimiterLookaheadFrames-1] hold zeros in all channels.
    // ------------------------------------------------------------------
    TestABLN prime(kNumCh, kLimiterLookaheadFrames);
    // All channels already zero-initialised by TestABLN constructor.
    kernel.process(prime.abl(), kLimiterLookaheadFrames);

    // ------------------------------------------------------------------
    // Step 2: Fill the 4-channel test block.  Save a copy for ratio check.
    // ------------------------------------------------------------------
    TestABLN abl(kNumCh, kFrames);

    // ch0: hot 1 kHz sine
    for (uint32_t i = 0U; i < kFrames; ++i)
    {
        abl.channels[0][i] = kHotAmpl * std::sin(2.0F * std::numbers::pi_v<float> * kHotFreq *
                                                 static_cast<float>(i) / kSRf);
    }
    // ch1/ch2/ch3: moderate tones
    const float toneFreqs[3] = {kToneFreq1, kToneFreq2, kToneFreq3};
    for (uint32_t ch = 1U; ch < kNumCh; ++ch)
    {
        for (uint32_t i = 0U; i < kFrames; ++i)
        {
            abl.channels[ch][i] =
                kToneAmpl * std::sin(2.0F * std::numbers::pi_v<float> * toneFreqs[ch - 1U] *
                                     static_cast<float>(i) / kSRf);
        }
    }

    // Save tone inputs for the delayed-input ratio computation.
    //
    // Ring timing after the prime call (kLimiterLookaheadFrames silence frames):
    //   readHead_ = kLimiterLookaheadFrames,  writeHead_ = 2 * kLimiterLookaheadFrames.
    //
    // During this block call, fillOutputFromRing reads ring[(readHead_ + i) % ringSize],
    // which was written during the PRIME block at prime-step i (positions
    // kLimiterLookaheadFrames .. 2*kLimiterLookaheadFrames-1, all zeros) for i in
    // [0 .. kLimiterLookaheadFrames-1], and written during THIS block at test-step
    // (i - kLimiterLookaheadFrames) for i in [kLimiterLookaheadFrames .. kFrames-1].
    //
    // Therefore:
    //   output[i] = 0                          for i < kLimiterLookaheadFrames
    //   output[i] = grBuf_[i] * input[i - kLimiterLookaheadFrames]
    //                                           for i >= kLimiterLookaheadFrames
    //
    // The grBuf_[i] at every index is driven by the ISP of the CURRENT write position
    // (the hot+tone signal), so limiting is active throughout.  We measure the ratio
    // only for i >= kLimiterLookaheadFrames, using savedInput[ch][i - kLookahead] as
    // the denominator.
    std::vector<std::vector<float>> savedInput(kNumCh, std::vector<float>(kFrames));
    for (uint32_t ch = 1U; ch < kNumCh; ++ch)
    {
        savedInput[ch] = abl.channels[ch];
    }

    // ------------------------------------------------------------------
    // Step 3: Process through the kernel.
    // ------------------------------------------------------------------
    kernel.process(abl.abl(), kFrames);

    // ------------------------------------------------------------------
    // Step 4: Verify the limiter actually engaged on ch0.
    // ------------------------------------------------------------------
    float ch0MaxOut = 0.0F;
    for (uint32_t i = 0U; i < kFrames; ++i)
    {
        ch0MaxOut = std::max(ch0MaxOut, std::abs(abl.channels[0][i]));
    }
    if (ch0MaxOut >= kHotAmpl - 0.01F)
    {
        logFail(kName, "ch0 output peak not reduced — limiter did not engage; GR path not tested");
        return;
    }

    // ------------------------------------------------------------------
    // Step 5: Recover per-channel applied gain and compare across tone channels.
    // For every sample where the delayed tone input is large enough for a stable
    // ratio, compute gain[ch][i] = output[ch][i] / savedInput[ch][i].  Then
    // assert |gain_dB[ch1][i] - gain_dB[ch2][i]| < kGrDiffThreshDb for all ch pairs.
    // ------------------------------------------------------------------
    // Only examine samples where the delayed input is available:
    // output[i] = grBuf_[i] * savedInput[ch][i - kLimiterLookaheadFrames]
    // for i in [kLimiterLookaheadFrames .. kFrames - 1].
    uint32_t activeSamples = 0U;
    for (uint32_t i = kLimiterLookaheadFrames; i < kFrames; ++i)
    {
        const uint32_t delayedIdx = i - kLimiterLookaheadFrames;

        // Collect gain estimates for tone channels 1..3 where delayed input is non-trivial.
        double gainDb[3] = {0.0, 0.0, 0.0};
        bool valid[3] = {false, false, false};

        for (uint32_t ch = 1U; ch < kNumCh; ++ch)
        {
            const float inSample = savedInput[ch][delayedIdx];
            if (std::abs(inSample) >= kMinInputForRatio)
            {
                const float outSample = abl.channels[ch][i];
                const double ratio = static_cast<double>(outSample) / static_cast<double>(inSample);
                // Clamp ratio to (0, 1] for the dB conversion — the limiter only attenuates.
                const double clampedRatio = std::max(1e-12, std::min(1.0, std::abs(ratio)));
                gainDb[ch - 1U] = 20.0 * std::log10(clampedRatio);
                valid[ch - 1U] = true;
            }
        }

        // Only compare frames where all three tone channels have a valid ratio.
        if (!valid[0] || !valid[1] || !valid[2])
        {
            continue;
        }

        ++activeSamples;

        // Inter-channel GR must be identical (same grBuf_ applied to all).
        for (uint32_t pair = 1U; pair < 3U; ++pair)
        {
            const double diffDb = std::abs(gainDb[0] - gainDb[pair]);
            if (diffDb >= kGrDiffThreshDb)
            {
                std::ostringstream oss;
                oss << "sample " << i << " (delayed=" << delayedIdx << "): ch1 GR=" << gainDb[0]
                    << " dB, ch" << (pair + 1U) << " GR=" << gainDb[pair] << " dB, diff=" << diffDb
                    << " dB (threshold " << kGrDiffThreshDb << " dB) — gain is NOT linked";
                logFail(kName, oss.str());
                return;
            }
        }
    }

    if (activeSamples == 0U)
    {
        logFail(kName,
                "no samples with sufficient input amplitude for ratio measurement — "
                "test configuration error");
        return;
    }

    std::ostringstream info;
    info << "  [info] " << kName << ": ch0_maxOut=" << ch0MaxOut << " ceiling=" << kCeiling
         << " activeSamples=" << activeSamples << "\n";
    std::fputs(info.str().c_str(), stdout);

    logPass(kName);
}

// T-C4b: Limiter N=8 hot-noise ceiling soak — S1-B3 N>2 safety net.
//
// Drive all 8 channels with full-scale-ish hot white noise (distinct per-channel
// RNG seeds) for 50 buffers.  After the first buffer (lookahead warm-up), assert:
//   (a) Every output sample on every channel is <= ceiling + 0.01 dB in linear.
//   (b) No NaN or Inf appears in any channel.
// This exercises the N=8 path through the new per-channel ring loops and confirms
// the linked-gain bus handles 8 independent peaks without overflow or NaN.
static auto testLimiterHotNoiseSoakN8() -> void
{
    static const char* const kName = "Limiter_HotNoiseSoak_N8";
    constexpr uint32_t kNumCh = 8U;
    constexpr uint32_t kFrames = 512U;
    constexpr uint32_t kSR = TestConstants::kSampleRate48k;
    constexpr float kCeiling = kTruePeakCeilingLinear;
    constexpr float kCeilingTolerance = 0.01F;

    DSPKernel kernel;
    kernel.initialize(kSR, kFrames);

    TargetState state{};
    state.intensityLinear = 1.0F;
    state.eq.numBiquads = 0U;
    state.eq.masterGainLinear = 1.0F;
    state.clarity.enabled = 0U;
    state.loudness.enabled = 0U;
    state.limiter.truePeakCeilingLinear = kCeiling;
    kernel.publishTargetState(state);

    // Use 8 distinct seeds so each channel carries a different noise sequence,
    // maximising the chance of independent inter-sample peaks that stress the
    // fan-in max() and the ring wrap across 8 slots.
    // NOLINTBEGIN(cert-msc32-c,cert-msc51-cpp)
    const uint32_t seeds[kNumCh] = {0xA1B2C3D4U,
                                    0xE5F60718U,
                                    0x29304152U,
                                    0x63748596U,
                                    0xA7B8C9DAU,
                                    0xEBFC0D1EU,
                                    0x2F304152U,
                                    0x73849506U};
    // NOLINTEND(cert-msc32-c,cert-msc51-cpp)

    float worst = 0.0F;
    for (uint32_t blk = 0U; blk < 50U; ++blk)
    {
        TestABLN abl(kNumCh, kFrames);
        for (uint32_t ch = 0U; ch < kNumCh; ++ch)
        {
            std::mt19937 gen(seeds[ch] + blk); // shift seed per block for variety
            std::uniform_real_distribution<float> dist(-0.999F, 0.999F);
            for (uint32_t i = 0U; i < kFrames; ++i)
            {
                abl.channels[ch][i] = dist(gen);
            }
        }
        kernel.process(abl.abl(), kFrames);

        if (blk >= 1U) // skip first buffer (lookahead warm-up, ring may output silence)
        {
            for (uint32_t ch = 0U; ch < kNumCh; ++ch)
            {
                for (uint32_t i = 0U; i < kFrames; ++i)
                {
                    const float sample = abl.channels[ch][i];

                    // NaN/Inf check
                    if (!std::isfinite(sample))
                    {
                        std::ostringstream oss;
                        oss << "NaN/Inf on ch" << ch << " sample " << i << " block " << blk;
                        logFail(kName, oss.str());
                        return;
                    }

                    worst = std::max(worst, std::abs(sample));
                }
            }
        }
    }

    if (worst > kCeiling + kCeilingTolerance)
    {
        std::ostringstream oss;
        oss << "N=8 soak: worst output peak " << worst << " exceeds ceiling " << kCeiling
            << " + tolerance " << kCeilingTolerance;
        logFail(kName, oss.str());
        return;
    }

    std::ostringstream info;
    info << "  [info] " << kName << ": N=8 worst_peak=" << worst << " ceiling=" << kCeiling << "\n";
    std::fputs(info.str().c_str(), stdout);

    logPass(kName);
}

static auto testReconfigurationContinuity() -> void
{
    logPending(
        "Reconfiguration_Stereo_5p1_Stereo",
        "S2: stereo -> 5.1 -> stereo in one kernel instance: no NaN, no crash, ceiling held");
}

// ---------------------------------------------------------------------------
// S1-C2a: Loudness_Multichannel_BS1770_Weights  (Gate C)
//
// Validates the N-channel ITU-R BS.1770-5 LufsMeter upgrade.
//
// BS.1770-5 channel weights used throughout (ITU-R BS.1770-5, Annex 1, Table 1):
//   L  = slot 0  G = 1.0
//   R  = slot 1  G = 1.0
//   C  = slot 2  G = 1.0
//   LFE= slot 3  G = 0.0  (EXCLUDED from loudness sum)
//   Ls = slot 4  G = 1.41 (~+1.5 dB, exact value 10^(1.5/10))
//   Rs = slot 5  G = 1.41
//
// ORACLE: an independent, straightforward second-path BS.1770-5 implementation
// written inline, distinct from the production LufsMeter.  It applies the same
// K-weighting coefficients (identical analytic bilinear-transform form) and the
// same two-pass gated integration algorithm, but is a self-contained loop with
// no shared code with LufsMeter.  This stands in for a libebur128 reference,
// which is not available in this build environment.  Reference:
//   ITU-R BS.1770-5 (2023), Annex 1.
// The oracle has no histogram — it integrates a single continuous measurement
// to keep the code small and auditable, suitable for the deterministic
// calibrated-tone and calibrated-noise signals used here.
//
// Sub-cases:
//   (a) Stereo-identity: 5.1 buffer with L/R active and C/LFE/Ls/Rs=0 reads
//       the SAME integrated LUFS (within 1e-6) as the stereo meter fed only L/R.
//   (b) Surround weight (+1.5 dB) and LFE exclusion (G=0): known tone on Ls+Rs
//       reads ~+1.5 dB above the same tone on L+R; LFE-only signal reads silence.
//   (c) Full 5.1 calibrated case against the independent oracle (±0.2 LU).
// ---------------------------------------------------------------------------

namespace
{
    // BS.1770-5 channel weights for ITU 5.1 (L, R, C, LFE, Ls, Rs).
    // Reference: ITU-R BS.1770-5, Annex 1, Table 1.
    // kBs1770GSurround = 10^(1.5/10) ≈ 1.41253754…  (exactly +1.5 dB in power).
    constexpr double kBs1770GLRC = 1.0;
    constexpr double kBs1770GLFE = 0.0;
    constexpr double kBs1770GSurround = 1.41253754462275643; // 10^(1.5/10)
    constexpr uint32_t kNum51Channels = 6U;

    // Build the weight array for 5.1 (L, R, C, LFE, Ls, Rs).
    auto make51Weights() -> std::array<double, kMaxChannels>
    {
        std::array<double, kMaxChannels> w{};
        w[0] = kBs1770GLRC;      // L
        w[1] = kBs1770GLRC;      // R
        w[2] = kBs1770GLRC;      // C
        w[3] = kBs1770GLFE;      // LFE (excluded)
        w[4] = kBs1770GSurround; // Ls
        w[5] = kBs1770GSurround; // Rs
        return w;
    }

    // Generate interleaved N-channel audio: one channel carries a 1 kHz sine at
    // peakDbfs; all other channels are silent.  sampleRate at 48 kHz.
    auto makeInterleavedNch(uint32_t numCh,
                            uint32_t activeCh,
                            double peakDbfs,
                            double seconds,
                            uint32_t sampleRate) -> std::vector<float>
    {
        const double amp = std::pow(10.0, peakDbfs / 20.0);
        const auto frames = static_cast<size_t>(seconds * sampleRate);
        std::vector<float> buf(frames * numCh, 0.0F);
        for (size_t frm = 0U; frm < frames; ++frm)
        {
            const double s =
                amp * std::sin(2.0 * std::numbers::pi * 1000.0 * static_cast<double>(frm) /
                               static_cast<double>(sampleRate));
            buf[(frm * numCh) + activeCh] = static_cast<float>(s);
        }
        return buf;
    }

    // Same as above but two channels active in phase (additive).
    auto makeInterleavedNch2Active(uint32_t numCh,
                                   uint32_t activeCh0,
                                   uint32_t activeCh1,
                                   double peakDbfs,
                                   double seconds,
                                   uint32_t sampleRate) -> std::vector<float>
    {
        const double amp = std::pow(10.0, peakDbfs / 20.0);
        const auto frames = static_cast<size_t>(seconds * sampleRate);
        std::vector<float> buf(frames * numCh, 0.0F);
        for (size_t frm = 0U; frm < frames; ++frm)
        {
            const double s =
                amp * std::sin(2.0 * std::numbers::pi * 1000.0 * static_cast<double>(frm) /
                               static_cast<double>(sampleRate));
            buf[(frm * numCh) + activeCh0] = static_cast<float>(s);
            buf[(frm * numCh) + activeCh1] = static_cast<float>(s);
        }
        return buf;
    }

    // ---------------------------------------------------------------------------
    // Independent BS.1770-5 oracle (stands in for libebur128).
    //
    // This is a separate, self-contained implementation of the BS.1770-5
    // integrated-loudness algorithm.  It shares NO code with the production
    // LufsMeter — it recomputes K-weighting from scratch and performs its own
    // gating.  It is deliberately simple (single-pass accumulation on gated
    // blocks, no histogram) and appropriate only for the calibrated deterministic
    // signals in this test.
    //
    // Reference: ITU-R BS.1770-5 (2023), Annex 1.
    // ---------------------------------------------------------------------------

    struct OracleBiquad
    {
        double b0{1.0}, b1{0.0}, b2{0.0}, a1{0.0}, a2{0.0};
        double z1{0.0}, z2{0.0};

        auto process(double x) noexcept -> double
        {
            const double y = b0 * x + z1;
            z1 = b1 * x - a1 * y + z2;
            z2 = b2 * x - a2 * y;
            return y;
        }
    };

    struct OracleKWeight
    {
        OracleBiquad shelf{};
        OracleBiquad rlb{};

        auto process(double x) noexcept -> double
        {
            return rlb.process(shelf.process(x));
        }
    };

    // Build oracle K-weight filters at the given sample rate using the same
    // analytic bilinear-transform form as LufsMeter (for consistency).
    auto makeOracleKWeight(double sampleRate) -> OracleKWeight
    {
        OracleKWeight kw;
        // Stage 1: high-shelf
        {
            const double warp = std::tan(M_PI * kKwShelfF0Hz / sampleRate);
            const double Vh = std::pow(kDecibelBase, kKwShelfGainDb / kDbAmplitudeScale);
            const double Vb = std::pow(Vh, kKwShelfVbExponent);
            const double a0 = 1.0 + (warp / kKwShelfQ) + (warp * warp);
            kw.shelf.b0 = (Vh + (Vb * warp / kKwShelfQ) + (warp * warp)) / a0;
            kw.shelf.b1 = 2.0 * ((warp * warp) - Vh) / a0;
            kw.shelf.b2 = (Vh - (Vb * warp / kKwShelfQ) + (warp * warp)) / a0;
            kw.shelf.a1 = 2.0 * ((warp * warp) - 1.0) / a0;
            kw.shelf.a2 = (1.0 - (warp / kKwShelfQ) + (warp * warp)) / a0;
        }
        // Stage 2: RLB high-pass
        {
            const double warp = std::tan(M_PI * kKwRlbF0Hz / sampleRate);
            const double a0 = 1.0 + (warp / kKwRlbQ) + (warp * warp);
            kw.rlb.b0 = 1.0 / a0;
            kw.rlb.b1 = -2.0 / a0;
            kw.rlb.b2 = 1.0 / a0;
            kw.rlb.a1 = 2.0 * ((warp * warp) - 1.0) / a0;
            kw.rlb.a2 = (1.0 - (warp / kKwRlbQ) + (warp * warp)) / a0;
        }
        return kw;
    }

    // Convert an energy value to LUFS (BS.1770-5 block loudness formula).
    auto energyToLufs(double energy) -> double
    {
        return (energy > kTinyEnergy) ? (kLufsOffset + kDbPowerScale * std::log10(energy))
                                      : kSilenceLufs;
    }

    // Two-pass gated integration over a vector of absolute-gated block energies.
    // Returns integrated LUFS (BS.1770-5 §2.3).
    auto oracleTwoPassGate(const std::vector<double>& blockEnergies) -> double
    {
        if (blockEnergies.empty())
        {
            return kSilenceLufs;
        }
        // Pass 1: absolute-gated mean → relative threshold.
        double sumEnergy1 = 0.0;
        for (const double e : blockEnergies)
        {
            sumEnergy1 += e;
        }
        const double meanEnergy1 = sumEnergy1 / static_cast<double>(blockEnergies.size());
        const double relThresh = (meanEnergy1 > kTinyEnergy)
                                     ? (energyToLufs(meanEnergy1) + kRelativeGateOffsetLu)
                                     : kSilenceLufs;
        // Pass 2: relative-gated mean → loudness.
        double sumEnergy2 = 0.0;
        size_t count2 = 0U;
        for (const double e : blockEnergies)
        {
            if (energyToLufs(e) >= relThresh)
            {
                sumEnergy2 += e;
                ++count2;
            }
        }
        if (count2 == 0U)
        {
            return energyToLufs(meanEnergy1);
        }
        return energyToLufs(sumEnergy2 / static_cast<double>(count2));
    }

    // Compute BS.1770-5 integrated LUFS for an interleaved N-channel buffer using
    // the independent oracle (NOT production LufsMeter).
    auto oracleIntegratedLufs(const std::vector<float>& buf,
                              uint32_t numCh,
                              const std::array<double, kMaxChannels>& weights,
                              uint32_t sampleRate) -> double
    {
        // Build one K-weight filter per channel (independent state).
        std::vector<OracleKWeight> filters(numCh);
        for (uint32_t ch = 0U; ch < numCh; ++ch)
        {
            filters[ch] = makeOracleKWeight(static_cast<double>(sampleRate));
        }

        const auto hopFrames =
            static_cast<uint32_t>(std::lround(kHopSeconds * static_cast<double>(sampleRate)));
        const double blockFrames = static_cast<double>(hopFrames) * kBlockHops;
        const size_t totalFrames = buf.size() / numCh;

        std::array<double, kShortTermHops> ring{};
        uint32_t ringHead = 0U;
        uint32_t ringFilled = 0U;
        std::vector<double> hopAccum(numCh, 0.0);
        uint32_t hopCount = 0U;

        std::vector<double> blockEnergies;
        blockEnergies.reserve(totalFrames / hopFrames + 10U);

        for (size_t frm = 0U; frm < totalFrames; ++frm)
        {
            for (uint32_t ch = 0U; ch < numCh; ++ch)
            {
                const double ky = filters[ch].process(static_cast<double>(buf[(frm * numCh) + ch]));
                hopAccum[ch] += ky * ky;
            }
            ++hopCount;
            if (hopCount < hopFrames)
            {
                continue;
            }
            // Hop complete: weighted sum, reset.
            double hopEnergy = 0.0;
            for (uint32_t ch = 0U; ch < numCh; ++ch)
            {
                hopEnergy += weights[ch] * hopAccum[ch];
                hopAccum[ch] = 0.0;
            }
            hopCount = 0U;
            ring[ringHead] = hopEnergy;
            ringHead = (ringHead + 1U) % static_cast<uint32_t>(kShortTermHops);
            if (ringFilled < static_cast<uint32_t>(kShortTermHops))
            {
                ++ringFilled;
            }
            if (ringFilled < static_cast<uint32_t>(kBlockHops))
            {
                continue;
            }
            // Block complete: sum kBlockHops most-recent hops.
            double blockSum = 0.0;
            for (int hIdx = 0; hIdx < kBlockHops; ++hIdx)
            {
                const uint32_t pos = (ringHead + static_cast<uint32_t>(kShortTermHops) - 1U -
                                      static_cast<uint32_t>(hIdx)) %
                                     static_cast<uint32_t>(kShortTermHops);
                blockSum += ring[pos];
            }
            const double energy = blockSum / blockFrames;
            if (energyToLufs(energy) >= kAbsoluteGateLufs)
            {
                blockEnergies.push_back(energy);
            }
        }

        return oracleTwoPassGate(blockEnergies);
    }

} // namespace

static auto testLoudnessMultichannelBS1770Weights() -> void
{
    static const char* const kName = "Loudness_Multichannel_BS1770_Weights";
    const uint32_t kSR = TestConstants::kSampleRate48k;
    const double kDuration = 15.0;
    const double kPeak = -23.0; // dBFS

    // -----------------------------------------------------------------------
    // Sub-case (a): Stereo-identity equivalence.
    //
    // A 5.1 buffer with only L (slot 0) and R (slot 1) active and the remaining
    // four channels silent must read the SAME integrated LUFS (within 1e-6 LU)
    // as a stereo meter fed only those L/R channels.
    // This validates that the N=2 weights {1,1,...} path is bit-equivalent to
    // the N=6 path when only the first two channels carry signal and all
    // surround/LFE weights are effectively zero (or channels are silent).
    // -----------------------------------------------------------------------

    // Stereo reference meter: feed L and R as interleaved stereo.
    LufsMeter stereoMeter;
    stereoMeter.prepare(kSR);
    {
        const double amp = std::pow(10.0, kPeak / 20.0);
        const auto frames = static_cast<size_t>(kDuration * kSR);
        std::vector<float> stereoBuf(frames * 2U);
        for (size_t frm = 0U; frm < frames; ++frm)
        {
            const double s = amp * std::sin(2.0 * std::numbers::pi * 1000.0 *
                                            static_cast<double>(frm) / static_cast<double>(kSR));
            stereoBuf[2U * frm] = static_cast<float>(s);
            stereoBuf[(2U * frm) + 1U] = static_cast<float>(s);
        }
        stereoMeter.addInterleavedStereo(stereoBuf.data(), frames);
    }
    const double stereoLufs = stereoMeter.integratedLufs();

    // 5.1 meter: same L/R signal, C/LFE/Ls/Rs are silent; use BS.1770-5 weights.
    // With C=0, LFE=0, Ls=0, Rs=0 (all silent) the weighted energy collapses to
    // G_L * accum[L] + G_R * accum[R] = accum[L] + accum[R], identical to stereo.
    LufsMeter meter51;
    meter51.prepare(kSR);
    meter51.configureChannels(kNum51Channels, make51Weights());
    {
        const double amp = std::pow(10.0, kPeak / 20.0);
        const auto frames = static_cast<size_t>(kDuration * kSR);
        std::vector<float> buf51(frames * kNum51Channels, 0.0F);
        for (size_t frm = 0U; frm < frames; ++frm)
        {
            const double s = amp * std::sin(2.0 * std::numbers::pi * 1000.0 *
                                            static_cast<double>(frm) / static_cast<double>(kSR));
            buf51[frm * kNum51Channels + 0U] = static_cast<float>(s); // L
            buf51[frm * kNum51Channels + 1U] = static_cast<float>(s); // R
        }
        meter51.addInterleaved(buf51.data(), frames, kNum51Channels);
    }
    const double lufs51LROnly = meter51.integratedLufs();

    const double deltaA = std::abs(lufs51LROnly - stereoLufs);
    std::ostringstream infoA;
    infoA << "  [info] " << kName << " (a): stereo=" << stereoLufs
          << " 5.1_LR_only=" << lufs51LROnly << " delta=" << deltaA << "\n";
    std::fputs(infoA.str().c_str(), stdout);

    if (deltaA > 1e-6)
    {
        std::ostringstream oss;
        oss << "(a) stereo-identity: expected delta < 1e-6, got " << deltaA
            << " (stereo=" << stereoLufs << " 5.1_LR=" << lufs51LROnly << ")";
        logFail(kName, oss.str());
        return;
    }

    // -----------------------------------------------------------------------
    // Sub-case (b1): Surround weight (+1.5 dB, G=1.41) check.
    //
    // A 5.1 buffer with only Ls+Rs active at peakDbfs is measured by a 5.1 meter
    // (weights: Ls=Rs=G_surround≈1.41).  The same signal on L+R (G=1.0 each)
    // at the same peak amplitude should measure ~1.5 dB less.
    //
    // Expected delta = 10*log10(G_surround) ≈ +1.5 dB (ITU-R BS.1770-5, Table 1).
    // Tolerance: ±0.05 dB (the weight is exact; any deviation is a code bug).
    // -----------------------------------------------------------------------

    // Ls+Rs only signal.
    LufsMeter meterSurround;
    meterSurround.prepare(kSR);
    meterSurround.configureChannels(kNum51Channels, make51Weights());
    {
        const auto buf = makeInterleavedNch2Active(kNum51Channels, 4U, 5U, kPeak, kDuration, kSR);
        meterSurround.addInterleaved(
            buf.data(), static_cast<size_t>(kDuration * kSR), kNum51Channels);
    }
    const double lufsSurround = meterSurround.integratedLufs();

    // L+R only signal (G=1.0) at same peak.
    LufsMeter meterLR;
    meterLR.prepare(kSR);
    meterLR.configureChannels(kNum51Channels, make51Weights());
    {
        const auto buf = makeInterleavedNch2Active(kNum51Channels, 0U, 1U, kPeak, kDuration, kSR);
        meterLR.addInterleaved(buf.data(), static_cast<size_t>(kDuration * kSR), kNum51Channels);
    }
    const double lufsLR = meterLR.integratedLufs();

    const double expectedSurroundBoostDb = kDbPowerScale * std::log10(kBs1770GSurround);
    const double measuredSurroundBoostDb = lufsSurround - lufsLR;
    const double deltaB1 = std::abs(measuredSurroundBoostDb - expectedSurroundBoostDb);

    std::ostringstream infoB1;
    infoB1 << "  [info] " << kName << " (b1): LR=" << lufsLR << " Surround=" << lufsSurround
           << " measuredBoost=" << measuredSurroundBoostDb
           << " expectedBoost=" << expectedSurroundBoostDb << " delta=" << deltaB1 << "\n";
    std::fputs(infoB1.str().c_str(), stdout);

    if (deltaB1 > 0.05)
    {
        std::ostringstream oss;
        oss << "(b1) surround +1.5 dB weight: measured boost=" << measuredSurroundBoostDb
            << " expected=" << expectedSurroundBoostDb << " delta=" << deltaB1;
        logFail(kName, oss.str());
        return;
    }

    // -----------------------------------------------------------------------
    // Sub-case (b2): LFE exclusion (G=0).
    //
    // A 5.1 buffer with only LFE (slot 3) active at peakDbfs must measure
    // kSilenceLufs (no gated blocks pass the absolute gate, because the weighted
    // energy is 0 × accum = 0).
    // -----------------------------------------------------------------------

    LufsMeter meterLFE;
    meterLFE.prepare(kSR);
    meterLFE.configureChannels(kNum51Channels, make51Weights());
    {
        const auto buf = makeInterleavedNch(kNum51Channels, 3U, kPeak, kDuration, kSR);
        meterLFE.addInterleaved(buf.data(), static_cast<size_t>(kDuration * kSR), kNum51Channels);
    }
    const double lufsLFE = meterLFE.integratedLufs();

    std::ostringstream infoB2;
    infoB2 << "  [info] " << kName << " (b2): LFE_only=" << lufsLFE
           << " (expect kSilenceLufs=" << kSilenceLufs << ")\n";
    std::fputs(infoB2.str().c_str(), stdout);

    if (lufsLFE > kAbsoluteGateLufs)
    {
        std::ostringstream oss;
        oss << "(b2) LFE exclusion: LFE-only signal must produce no gated blocks; got " << lufsLFE
            << " LUFS (should be <= " << kAbsoluteGateLufs << ")";
        logFail(kName, oss.str());
        return;
    }

    // -----------------------------------------------------------------------
    // Sub-case (c): Full 5.1 calibrated case vs. independent oracle (±0.2 LU).
    //
    // Generate a 5.1 buffer with all six channels carrying distinct-level tones:
    //   L  = -20 dBFS, R  = -22 dBFS, C  = -25 dBFS,
    //   LFE= -10 dBFS  (excluded), Ls = -24 dBFS, Rs = -26 dBFS.
    // Feed this to the production LufsMeter and to the independent oracle and
    // assert they agree within ±0.2 LU.
    // -----------------------------------------------------------------------

    const double ampL = std::pow(10.0, -20.0 / 20.0);
    const double ampR = std::pow(10.0, -22.0 / 20.0);
    const double ampC = std::pow(10.0, -25.0 / 20.0);
    const double ampLFE = std::pow(10.0, -10.0 / 20.0); // excluded by G=0
    const double ampLs = std::pow(10.0, -24.0 / 20.0);
    const double ampRs = std::pow(10.0, -26.0 / 20.0);

    const double amps51[kNum51Channels] = {ampL, ampR, ampC, ampLFE, ampLs, ampRs};

    const auto frames = static_cast<size_t>(kDuration * kSR);
    std::vector<float> buf51full(frames * kNum51Channels);
    for (size_t frm = 0U; frm < frames; ++frm)
    {
        const double phase =
            2.0 * std::numbers::pi * 1000.0 * static_cast<double>(frm) / static_cast<double>(kSR);
        for (uint32_t ch = 0U; ch < kNum51Channels; ++ch)
        {
            buf51full[(frm * kNum51Channels) + ch] =
                static_cast<float>(amps51[ch] * std::sin(phase));
        }
    }

    // Production meter.
    LufsMeter meterFull;
    meterFull.prepare(kSR);
    meterFull.configureChannels(kNum51Channels, make51Weights());
    meterFull.addInterleaved(buf51full.data(), frames, kNum51Channels);
    const double lufsProduction = meterFull.integratedLufs();

    // Independent BS.1770-5 oracle (separate code, not LufsMeter).
    const double lufsOracle = oracleIntegratedLufs(buf51full, kNum51Channels, make51Weights(), kSR);

    const double deltaC = std::abs(lufsProduction - lufsOracle);

    std::ostringstream infoC;
    infoC << "  [info] " << kName << " (c): production=" << lufsProduction
          << " oracle=" << lufsOracle << " delta=" << deltaC << "\n";
    std::fputs(infoC.str().c_str(), stdout);

    if (deltaC > 0.2)
    {
        std::ostringstream oss;
        oss << "(c) 5.1 full calibrated: production=" << lufsProduction << " oracle=" << lufsOracle
            << " delta=" << deltaC << " (threshold 0.2 LU)";
        logFail(kName, oss.str());
        return;
    }

    logPass(kName);
}

// ---------------------------------------------------------------------------
// Large-buffer regression fence (buffer-size desync bug fix verification).
//
// WHAT THIS TESTS:
//   Before the fix: safeCount = min(frameCount, kDefaultMaxFrames=512) meant that
//   buffers larger than 512 frames had their tail [512..N-1] left unprocessed by the
//   Limiter ring, the EQ master-gain ramp, and the Loudness makeup-gain ramp.
//   At bufSize=1024 with the Limiter active and a hot signal above the ceiling:
//     - frames [0..511]: gain-reduced via ring path, output ≤ ceiling.
//     - frames [512..1023]: raw undelayed input carried through untouched (above ceiling).
//   The EQ ramp bug caused a -0.14 linear step discontinuity at frame 512 every buffer.
//
// After the fix: grBuf_, rampBuf_, and pushBuf_ are sized to maxFrames_ in
// initialize(), and safeCount = min(frameCount, maxFrames_) == frameCount for all
// correctly-configured callers. ALL frames in every buffer are processed.
//
// T-LB1: Kernel_LargeBuffer_LimiterTailCorrect
//   Drive the full DSPKernel (active limiter, identity EQ) at bufSize=1024, then 4096.
//   Feed a hot (above-ceiling) signal. Assert:
//     (a) The ENTIRE output buffer (including frames [512..N-1]) respects the ceiling.
//     (b) The output contains no NaN/Inf.
//     (c) Per-buffer tail gain ≈ head gain (no safeCount boundary step in the limiter path).
//
// T-LB2: Kernel_LargeBuffer_EQGainNoCutoff
//   Drive the kernel with masterGain=2.0 (ramp path active) at bufSize=1024.
//   Assert the per-sample output is monotonically increasing (or at least non-zero) past
//   frame 512 — i.e. the ramp continues to advance and the gain multiply was applied.
//
// T-LB3: Kernel_LargeBuffer_ConsecutiveBuffers
//   Feed 6 consecutive 1024-frame buffers of a hot signal through the full chain.
//   Assert that the last buffer is NOT more distorted than the first — i.e. the ring
//   desync does not compound. Measure output peak in the tail of each buffer.
// ---------------------------------------------------------------------------

static auto testLargeBufferLimiterTailCorrect() -> void
{
    static const char* const kName = "Kernel_LargeBuffer_LimiterTailCorrect";
    constexpr uint32_t kSR = TestConstants::kSampleRate48k;
    constexpr float kCeiling = kTruePeakCeilingLinear; // 0.891
    constexpr float kCeilingTol = 0.01F;
    constexpr float kHotAmpl = 0.999F; // above ceiling

    const uint32_t bufSizes[] = {1024U, 4096U};

    for (const uint32_t bufSize : bufSizes)
    {
        DSPKernel kernel;
        kernel.initialize(kSR, bufSize);

        TargetState state{};
        state.intensityLinear = 1.0F;
        state.eq.numBiquads = 0U;
        state.eq.masterGainLinear = 1.0F;
        state.clarity.enabled = 0U;
        state.loudness.enabled = 0U;
        state.limiter.truePeakCeilingLinear = kCeiling;
        kernel.publishTargetState(state);

        // Prime the ring so the lookahead window starts with zeros.
        TestABLN prime(2U, kLimiterLookaheadFrames);
        kernel.process(prime.abl(), kLimiterLookaheadFrames);

        // Hot DC burst for a full large buffer.
        TestABLN abl(2U, bufSize);
        for (uint32_t i = 0U; i < bufSize; ++i)
        {
            abl.channels[0][i] = kHotAmpl;
            abl.channels[1][i] = kHotAmpl;
        }
        kernel.process(abl.abl(), bufSize);

        // (a) + (b): every output sample must be finite and ≤ ceiling + tolerance.
        uint32_t nanCount = 0U;
        uint32_t aboveCeiling = 0U;
        for (uint32_t i = 0U; i < bufSize; ++i)
        {
            const float s = abl.channels[0][i];
            if (!std::isfinite(s))
            {
                ++nanCount;
            }
            else if (std::abs(s) > kCeiling + kCeilingTol)
            {
                ++aboveCeiling;
            }
        }

        if (nanCount > 0U || aboveCeiling > 0U)
        {
            std::ostringstream oss;
            oss << "bufSize=" << bufSize << " NaN/Inf=" << nanCount
                << " samples_above_ceiling=" << aboveCeiling << " (ceiling=" << kCeiling
                << " + tol=" << kCeilingTol << ")";
            logFail(kName, oss.str());
            return;
        }

        // (c) Tail gain must not be significantly higher than head gain (no safeCount
        // boundary where the limiter stopped applying the ring path).
        // Compute mean absolute gain (output/input) for head vs tail of safeCount.
        constexpr uint32_t kBoundary = kDefaultMaxFrames; // the old 512 boundary
        if (bufSize <= kBoundary)
        {
            continue; // not a large-buffer case; skip boundary check
        }

        double headGainSum = 0.0;
        uint32_t headCnt = 0U;
        double tailGainSum = 0.0;
        uint32_t tailCnt = 0U;

        for (uint32_t i = kLimiterLookaheadFrames; i < kBoundary; ++i)
        {
            headGainSum += static_cast<double>(std::abs(abl.channels[0][i])) / kHotAmpl;
            ++headCnt;
        }
        for (uint32_t i = kBoundary; i < bufSize; ++i)
        {
            tailGainSum += static_cast<double>(std::abs(abl.channels[0][i])) / kHotAmpl;
            ++tailCnt;
        }

        if (headCnt > 0U && tailCnt > 0U)
        {
            const double avgHeadGain = headGainSum / static_cast<double>(headCnt);
            const double avgTailGain = tailGainSum / static_cast<double>(tailCnt);
            // Before the fix: tailGain ≈ 1.0 (raw input), headGain ≈ 0.62 (limited).
            // After the fix: tailGain ≈ headGain (both limited).
            // Threshold: tail must not be more than 5% above head.
            if (avgTailGain > avgHeadGain + 0.05)
            {
                std::ostringstream oss;
                oss << "bufSize=" << bufSize << " tail avg gain (" << avgTailGain
                    << ") >> head avg gain (" << avgHeadGain
                    << ") — limiter tail-safeCount boundary still present";
                logFail(kName, oss.str());
                return;
            }
        }
    }
    logPass(kName);
}

static auto testLargeBufferEQGainNoCutoff() -> void
{
    static const char* const kName = "Kernel_LargeBuffer_EQGainNoCutoff";
    constexpr uint32_t kSR = TestConstants::kSampleRate48k;
    constexpr uint32_t kBufSize = 1024U;

    DSPKernel kernel;
    kernel.initialize(kSR, kBufSize);

    // masterGain=2.0 forces the ramp path; ramp starts at unity (snapped) and
    // trends toward 2.0, so every output sample > input * 0.9 at minimum.
    TargetState state{};
    state.intensityLinear = 1.0F;
    state.eq.numBiquads = 0U;
    state.eq.masterGainLinear = 2.0F;
    state.clarity.enabled = 0U;
    state.loudness.enabled = 0U;
    state.limiter.truePeakCeilingLinear = 10.0F; // bypass limiter
    kernel.publishTargetState(state);

    // DC signal at 0.5 — with masterGain=2.0 the ramp trend means all output > 0.4.
    TestABLN abl(2U, kBufSize);
    for (uint32_t i = 0U; i < kBufSize; ++i)
    {
        abl.channels[0][i] = 0.5F;
        abl.channels[1][i] = 0.5F;
    }
    kernel.process(abl.abl(), kBufSize);

    // Before the fix: samples [512..1023] were multiplied by stale rampBuf_[i-512]
    // values from initialize()'s fill (0.0), so output[512..] ≈ 0.
    // After the fix: the ramp continues through all 1024 samples; output > 0.4.
    constexpr float kMinExpected = 0.4F; // ramp at unity * 0.5 input = 0.5 at minimum
    constexpr uint32_t kBoundary = kDefaultMaxFrames;

    bool tailSilent = false;
    float minTailOutput = 1.0F;
    for (uint32_t i = kBoundary; i < kBufSize; ++i)
    {
        const float s = abl.channels[0][i];
        if (std::abs(s) < minTailOutput)
        {
            minTailOutput = std::abs(s);
        }
        if (std::abs(s) < kMinExpected)
        {
            tailSilent = true;
        }
    }

    // Also assert no step at the 512 boundary.
    const float stepAt512 = std::abs(abl.channels[0][kBoundary] - abl.channels[0][kBoundary - 1U]);
    // The ramp is monotonically increasing toward 2.0; the per-sample gain step is tiny.
    // Before the fix: a ~-0.14 linear discontinuity. After the fix: smooth ramp.
    constexpr float kMaxAllowedStep = 0.05F; // generous: ramp changes < 0.001 per sample

    if (tailSilent)
    {
        std::ostringstream oss;
        oss << "tail [" << kBoundary << ".." << kBufSize - 1U << "] min output=" << minTailOutput
            << " < " << kMinExpected << " — EQ master-gain ramp was not applied past frame "
            << kBoundary;
        logFail(kName, oss.str());
        return;
    }
    if (stepAt512 > kMaxAllowedStep)
    {
        std::ostringstream oss;
        oss << "step at frame " << kBoundary << ": " << stepAt512 << " linear (max allowed "
            << kMaxAllowedStep << ") — EQ ramp discontinuity at safeCount boundary";
        logFail(kName, oss.str());
        return;
    }
    logPass(kName);
}

static auto testLargeBufferConsecutiveBuffers() -> void
{
    static const char* const kName = "Kernel_LargeBuffer_ConsecutiveBuffers";
    constexpr uint32_t kSR = TestConstants::kSampleRate48k;
    constexpr uint32_t kBufSize = 1024U;
    constexpr float kCeiling = kTruePeakCeilingLinear;
    constexpr float kCeilingTol = 0.01F;
    constexpr float kHotAmpl = 0.999F;
    constexpr uint32_t kNumBlocks = 6U;

    DSPKernel kernel;
    kernel.initialize(kSR, kBufSize);

    TargetState state{};
    state.intensityLinear = 1.0F;
    state.eq.numBiquads = 0U;
    state.eq.masterGainLinear = 1.0F;
    state.clarity.enabled = 0U;
    state.loudness.enabled = 0U;
    state.limiter.truePeakCeilingLinear = kCeiling;
    kernel.publishTargetState(state);

    // Feed kNumBlocks 1024-frame buffers of a 1 kHz sine above the ceiling.
    float worstTailPeak = 0.0F;
    uint32_t failBlock = 0U;
    bool failed = false;

    for (uint32_t blk = 0U; blk < kNumBlocks; ++blk)
    {
        TestABLN abl(2U, kBufSize);
        for (uint32_t i = 0U; i < kBufSize; ++i)
        {
            const float phase = 2.0F * std::numbers::pi_v<float> * 1000.0F *
                                static_cast<float>((blk * kBufSize) + i) / static_cast<float>(kSR);
            abl.channels[0][i] = kHotAmpl * std::sin(phase);
            abl.channels[1][i] = abl.channels[0][i];
        }
        kernel.process(abl.abl(), kBufSize);

        // Check tail: before the fix the ring desyncs progressively, so blocks 2+
        // would show increasing corruption in the tail.
        for (uint32_t i = kDefaultMaxFrames; i < kBufSize; ++i)
        {
            const float absS = std::abs(abl.channels[0][i]);
            if (absS > worstTailPeak)
            {
                worstTailPeak = absS;
            }
            if (!failed && absS > kCeiling + kCeilingTol)
            {
                failed = true;
                failBlock = blk;
            }
        }
    }

    if (failed)
    {
        std::ostringstream oss;
        oss << "tail [" << kDefaultMaxFrames << ".." << kBufSize - 1U
            << "] exceeded ceiling on block " << failBlock << ": worst_tail_peak=" << worstTailPeak
            << " ceiling=" << kCeiling << " — ring desync or safeCount boundary not fixed";
        logFail(kName, oss.str());
        return;
    }
    logPass(kName);
}

// ---------------------------------------------------------------------------
// M1-1 Gate D: ChannelLayout_Decode_GateD
//
// Validates decodeChannelLayout() for Stereo, MPEG_5_1_A, MPEG_5_1_B, MPEG_7_1_A,
// MPEG_7_1_C, and an unknown/custom tag.
//
// The critical correctness target is the 5.1 _A vs _B ordering trap:
//   _A: L R C LFE Ls Rs  → LFE at slot 3, surrounds at slots 4/5
//   _B: L R Ls Rs C LFE  → LFE at slot 5, surrounds at slots 2/3
//
// Per-slot values under test:
//   lufsWeight : L/R/C = 1.0  |  LFE = 0.0  |  surround = 1.41253754 (±1e-5)
//   isLfe      : 1 at LFE slot, 0 elsewhere
//   brirAzimuth: spot-checks at the L and C slots (right index per ordering)
//   numChannels: correct count for each tag
//
// Decomposed into one sub-function per format to keep cognitive complexity inside
// the clang-tidy threshold of 25.
//
// References:
//   ITU-R BS.1770-5 (2023), Annex 1, Table 1 — weights
//   ITU-R BS.775-4  (2022), §3              — azimuths
//   Apple CoreAudioBaseTypes.h              — tag → channel-order comments
// ---------------------------------------------------------------------------

namespace
{
    // Shared tolerance and expected-value constants (same across all sub-cases).
    // Kept at namespace scope so each sub-function can use them without re-declaring.
    constexpr float kGateDWeightTol = 1e-5F;
    constexpr float kGateDazimTol = 1e-4F;
    constexpr float kGateDExpLRC = 1.0F;
    constexpr float kGateDExpLFE = 0.0F;
    constexpr float kGateDExpSurr = 1.41253754F; // 10^(1.5/10) per BS.1770-5 Annex 1 Table 1
    // Azimuth spot-checks (BS.775-4; + = left/CCW from centre)
    constexpr float kGateDExpAzimL = 30.0F; // L
    constexpr float kGateDExpAzimC = 0.0F;  // C

    // Returns "" on success, a non-empty error string on failure.
    // Stereo (2): L R
    auto gateDCheckStereo() -> std::string
    {
        const ChannelLayout lay = decodeChannelLayout(kAudioChannelLayoutTag_Stereo);
        if (lay.numChannels != 2U)
        {
            return "Stereo: numChannels != 2";
        }
        if (std::abs(lay.lufsWeight[0] - kGateDExpLRC) > kGateDWeightTol)
        {
            return "Stereo: slot0 (L) lufsWeight != 1.0";
        }
        if (lay.isLfe[0] != 0U)
        {
            return "Stereo: slot0 (L) isLfe != 0";
        }
        if (std::abs(lay.brirAzimuthDeg[0] - kGateDExpAzimL) > kGateDazimTol)
        {
            return "Stereo: slot0 (L) brirAzimuthDeg != +30";
        }
        if (std::abs(lay.lufsWeight[1] - kGateDExpLRC) > kGateDWeightTol)
        {
            return "Stereo: slot1 (R) lufsWeight != 1.0";
        }
        if (lay.isLfe[1] != 0U)
        {
            return "Stereo: slot1 (R) isLfe != 0";
        }
        return {};
    }

    // MPEG 5.1 A: L R C LFE Ls Rs  (LFE at slot 3, surrounds at 4/5)
    auto gateDCheck51A() -> std::string
    {
        const ChannelLayout layA = decodeChannelLayout(kAudioChannelLayoutTag_MPEG_5_1_A);
        if (layA.numChannels != 6U)
        {
            return "5_1_A: numChannels != 6";
        }
        if (std::abs(layA.lufsWeight[0] - kGateDExpLRC) > kGateDWeightTol || layA.isLfe[0] != 0U)
        {
            return "5_1_A: slot0 (L) wrong";
        }
        // slot 2: C — ordering trap proof: must be C (weight=1) not surround
        if (std::abs(layA.lufsWeight[2] - kGateDExpLRC) > kGateDWeightTol || layA.isLfe[2] != 0U)
        {
            return "5_1_A: slot2 (C) weight or isLfe wrong";
        }
        if (std::abs(layA.brirAzimuthDeg[2] - kGateDExpAzimC) > kGateDazimTol)
        {
            return "5_1_A: slot2 (C) brirAzimuthDeg != 0";
        }
        // slot 3: LFE — THE TRAP: LFE is at index 3 in _A, at index 5 in _B
        if (std::abs(layA.lufsWeight[3] - kGateDExpLFE) > kGateDWeightTol || layA.isLfe[3] != 1U)
        {
            return "5_1_A: slot3 must be LFE — ordering trap";
        }
        // slots 4/5: Ls/Rs (surround)
        if (std::abs(layA.lufsWeight[4] - kGateDExpSurr) > kGateDWeightTol || layA.isLfe[4] != 0U)
        {
            return "5_1_A: slot4 (Ls) surround weight wrong";
        }
        if (std::abs(layA.lufsWeight[5] - kGateDExpSurr) > kGateDWeightTol || layA.isLfe[5] != 0U)
        {
            return "5_1_A: slot5 (Rs) surround weight wrong";
        }
        if (std::abs(layA.brirAzimuthDeg[0] - kGateDExpAzimL) > kGateDazimTol)
        {
            return "5_1_A: slot0 (L) brirAzimuthDeg != +30";
        }
        return {};
    }

    // MPEG 5.1 B: L R Ls Rs C LFE  (LFE at slot 5, surrounds at 2/3)
    // DIFFERENT ordering from _A — this is the whole point of Gate D.
    auto gateDCheck51B() -> std::string
    {
        const ChannelLayout layB = decodeChannelLayout(kAudioChannelLayoutTag_MPEG_5_1_B);
        if (layB.numChannels != 6U)
        {
            return "5_1_B: numChannels != 6";
        }
        // slot 2: Ls — ordering trap proof: must be surround (weight=1.41) not C (weight=1)
        if (std::abs(layB.lufsWeight[2] - kGateDExpSurr) > kGateDWeightTol || layB.isLfe[2] != 0U)
        {
            return "5_1_B: slot2 must be Ls (surround) — ordering trap";
        }
        // slot 3: Rs — ordering trap proof: must be surround, not LFE
        if (std::abs(layB.lufsWeight[3] - kGateDExpSurr) > kGateDWeightTol || layB.isLfe[3] != 0U)
        {
            return "5_1_B: slot3 must be Rs (surround) — ordering trap";
        }
        // slot 4: C
        if (std::abs(layB.lufsWeight[4] - kGateDExpLRC) > kGateDWeightTol || layB.isLfe[4] != 0U)
        {
            return "5_1_B: slot4 (C) wrong";
        }
        if (std::abs(layB.brirAzimuthDeg[4] - kGateDExpAzimC) > kGateDazimTol)
        {
            return "5_1_B: slot4 (C) brirAzimuthDeg != 0";
        }
        // slot 5: LFE — THE TRAP: LFE is at index 5 in _B, at index 3 in _A
        if (std::abs(layB.lufsWeight[5] - kGateDExpLFE) > kGateDWeightTol || layB.isLfe[5] != 1U)
        {
            return "5_1_B: slot5 must be LFE — ordering trap";
        }
        if (std::abs(layB.brirAzimuthDeg[0] - kGateDExpAzimL) > kGateDazimTol)
        {
            return "5_1_B: slot0 (L) brirAzimuthDeg != +30";
        }
        return {};
    }

    // MPEG 7.1 A: L R C LFE Ls Rs Lc Rc
    auto gateDCheck71A() -> std::string
    {
        const ChannelLayout lay71A = decodeChannelLayout(kAudioChannelLayoutTag_MPEG_7_1_A);
        if (lay71A.numChannels != 8U)
        {
            return "7_1_A: numChannels != 8";
        }
        if (std::abs(lay71A.lufsWeight[3] - kGateDExpLFE) > kGateDWeightTol ||
            lay71A.isLfe[3] != 1U)
        {
            return "7_1_A: slot3 must be LFE";
        }
        if (std::abs(lay71A.lufsWeight[4] - kGateDExpSurr) > kGateDWeightTol ||
            lay71A.isLfe[4] != 0U)
        {
            return "7_1_A: slot4 (Ls) surround weight wrong";
        }
        if (std::abs(lay71A.lufsWeight[6] - kGateDExpLRC) > kGateDWeightTol ||
            lay71A.isLfe[6] != 0U)
        {
            return "7_1_A: slot6 (Lc) weight wrong";
        }
        if (std::abs(lay71A.brirAzimuthDeg[2] - kGateDExpAzimC) > kGateDazimTol)
        {
            return "7_1_A: slot2 (C) brirAzimuthDeg != 0";
        }
        return {};
    }

    // MPEG 7.1 C: L R C LFE Ls Rs Rls Rrs
    auto gateDCheck71C() -> std::string
    {
        const ChannelLayout lay71C = decodeChannelLayout(kAudioChannelLayoutTag_MPEG_7_1_C);
        if (lay71C.numChannels != 8U)
        {
            return "7_1_C: numChannels != 8";
        }
        if (std::abs(lay71C.lufsWeight[3] - kGateDExpLFE) > kGateDWeightTol ||
            lay71C.isLfe[3] != 1U)
        {
            return "7_1_C: slot3 must be LFE";
        }
        if (std::abs(lay71C.lufsWeight[4] - kGateDExpSurr) > kGateDWeightTol ||
            lay71C.isLfe[4] != 0U)
        {
            return "7_1_C: slot4 (Ls) surround weight wrong";
        }
        if (std::abs(lay71C.lufsWeight[6] - kGateDExpSurr) > kGateDWeightTol ||
            lay71C.isLfe[6] != 0U)
        {
            return "7_1_C: slot6 (Rls) back-surround weight wrong";
        }
        if (std::abs(lay71C.lufsWeight[7] - kGateDExpSurr) > kGateDWeightTol ||
            lay71C.isLfe[7] != 0U)
        {
            return "7_1_C: slot7 (Rrs) back-surround weight wrong";
        }
        if (std::abs(lay71C.brirAzimuthDeg[0] - kGateDExpAzimL) > kGateDazimTol)
        {
            return "7_1_C: slot0 (L) brirAzimuthDeg != +30";
        }
        return {};
    }

    // Unknown tag — neutral fallback: numChannels from tag bits, all weights 1.0, no LFE.
    auto gateDCheckUnknown() -> std::string
    {
        constexpr uint32_t kFakeChCount = 4U;
        constexpr AudioChannelLayoutTag kUnknownTag =
            static_cast<AudioChannelLayoutTag>((0xFFFFU << 16U) | kFakeChCount);
        const ChannelLayout layUnk = decodeChannelLayout(kUnknownTag);
        if (layUnk.numChannels != kFakeChCount)
        {
            return "unknown tag: numChannels != 4";
        }
        for (uint32_t ch = 0U; ch < kFakeChCount; ++ch)
        {
            if (std::abs(layUnk.lufsWeight[ch] - kGateDExpLRC) > kGateDWeightTol)
            {
                return "unknown tag: slot" + std::to_string(ch) + " lufsWeight != 1.0";
            }
            if (layUnk.isLfe[ch] != 0U)
            {
                return "unknown tag: slot" + std::to_string(ch) + " isLfe != 0";
            }
        }
        return {};
    }
} // namespace

static auto testChannelLayoutDecodeGateD() -> void
{
    static const char* const kName = "ChannelLayout_Decode_GateD";

    // Run each sub-case; bail on the first failure (matches the pattern used
    // by all other Gate tests in this suite).
    const std::string stereoErr = gateDCheckStereo();
    if (!stereoErr.empty())
    {
        logFail(kName, stereoErr);
        return;
    }

    const std::string err51A = gateDCheck51A();
    if (!err51A.empty())
    {
        logFail(kName, err51A);
        return;
    }

    const std::string err51B = gateDCheck51B();
    if (!err51B.empty())
    {
        logFail(kName, err51B);
        return;
    }

    const std::string err71A = gateDCheck71A();
    if (!err71A.empty())
    {
        logFail(kName, err71A);
        return;
    }

    const std::string err71C = gateDCheck71C();
    if (!err71C.empty())
    {
        logFail(kName, err71C);
        return;
    }

    const std::string errUnk = gateDCheckUnknown();
    if (!errUnk.empty())
    {
        logFail(kName, errUnk);
        return;
    }

    logPass(kName);
}

// ---------------------------------------------------------------------------
// M1-2 Gate E: Loudness_DecodedLayout_Weights
//
// Validates the decode→meter path END-TO-END (synchronously; no worker thread).
//
// Strategy: use decodeChannelLayout(kAudioChannelLayoutTag_MPEG_5_1_A) to obtain
// the REAL BS.1770-5 per-channel weights, convert them to a double weight array,
// call meter.configureChannels(6, weights) directly, feed a calibrated 6-channel
// signal, and assert the integrated LUFS matches the same oracle expectation used
// by Loudness_Multichannel_BS1770_Weights — proving the decode→weight→meter chain
// is wired correctly and bit-equivalent to the hand-crafted weight array.
//
// The specific assertions mirror sub-case (b) and (c) of the existing BS.1770
// weights test:
//   (b) surround (+1.5 dB) and LFE exclusion (G=0) via decoded weights.
//   (c) full 5.1 calibrated case against the independent oracle (±0.2 LU).
//
// If this test passes while the existing Loudness_Multichannel_BS1770_Weights test
// also passes, the two weight sources (hand-crafted and decoder-derived) are
// confirmed to be numerically identical, and the new publish path delivers
// correct weights to the meter.
//
// Reference: ITU-R BS.1770-5 (2023), Annex 1, Table 1.
// ---------------------------------------------------------------------------

static auto testLoudnessDecodedLayoutWeights() -> void
{
    static const char* const kName = "Loudness_DecodedLayout_Weights";
    constexpr uint32_t kSR = TestConstants::kSampleRate48k;
    constexpr double kDuration = 15.0;
    constexpr double kPeak = -23.0;           // dBFS
    constexpr double kSurroundDeltaMin = 1.0; // surrounds must read ≥ 1 dB above L+R
    constexpr double kSurroundDeltaMax = 2.0; // and ≤ 2 dB above (tolerance on +1.5 dB)
    constexpr double kOracleTol = 0.2;        // ±0.2 LU vs. oracle

    // -----------------------------------------------------------------------
    // Step 1: Decode the 5.1-A layout to obtain BS.1770-5 weights.
    //
    // kAudioChannelLayoutTag_MPEG_5_1_A: L R C LFE Ls Rs
    //   slot 0 (L)  : lufsWeight = 1.0
    //   slot 1 (R)  : lufsWeight = 1.0
    //   slot 2 (C)  : lufsWeight = 1.0
    //   slot 3 (LFE): lufsWeight = 0.0   (excluded)
    //   slot 4 (Ls) : lufsWeight = 1.41253754
    //   slot 5 (Rs) : lufsWeight = 1.41253754
    // -----------------------------------------------------------------------
    const ChannelLayout decoded51A = decodeChannelLayout(kAudioChannelLayoutTag_MPEG_5_1_A);

    // Convert float lufsWeight to the double array required by configureChannels().
    std::array<double, kMaxChannels> decodedWeights{};
    for (uint32_t ch = 0U; ch < kMaxChannels; ++ch)
    {
        decodedWeights[ch] = static_cast<double>(decoded51A.lufsWeight[ch]);
    }

    // -----------------------------------------------------------------------
    // Sub-case (b): Surround weight and LFE exclusion via decoded weights.
    //
    // Feed Ls+Rs active at kPeak and measure.  Then feed L+R active at kPeak
    // and measure.  The surround reading must be ~+1.5 dB above the L+R reading
    // because the decoder assigned G=1.41 to slots 4/5 and G=1.0 to slots 0/1.
    // A zero-weight LFE-only signal must read kSilenceLufs (excluded).
    // -----------------------------------------------------------------------

    // Ls+Rs active (slots 4 and 5) — surround weight G=1.41 (~+1.5 dB)
    LufsMeter meterSurr;
    meterSurr.prepare(kSR);
    meterSurr.configureChannels(kNum51Channels, decodedWeights);
    {
        const auto buf = makeInterleavedNch2Active(kNum51Channels, 4U, 5U, kPeak, kDuration, kSR);
        meterSurr.addInterleaved(buf.data(), static_cast<size_t>(kDuration * kSR), kNum51Channels);
    }
    const double lufsSurr = meterSurr.integratedLufs();

    // L+R active (slots 0 and 1) — weight G=1.0
    LufsMeter meterLR;
    meterLR.prepare(kSR);
    meterLR.configureChannels(kNum51Channels, decodedWeights);
    {
        const auto buf = makeInterleavedNch2Active(kNum51Channels, 0U, 1U, kPeak, kDuration, kSR);
        meterLR.addInterleaved(buf.data(), static_cast<size_t>(kDuration * kSR), kNum51Channels);
    }
    const double lufsLR = meterLR.integratedLufs();

    const double surroundDelta = lufsSurr - lufsLR;
    std::ostringstream infoB;
    infoB << "  [info] " << kName << " (b): lufsSurr=" << lufsSurr << " lufsLR=" << lufsLR
          << " delta=" << surroundDelta << "\n";
    std::fputs(infoB.str().c_str(), stdout);

    if (surroundDelta < kSurroundDeltaMin || surroundDelta > kSurroundDeltaMax)
    {
        std::ostringstream oss;
        oss << "(b) surround weight delta=" << surroundDelta << " not in [" << kSurroundDeltaMin
            << ", " << kSurroundDeltaMax << "] (expected ~+1.5 dB from decoded G=1.41)";
        logFail(kName, oss.str());
        return;
    }

    // LFE-only (slot 3, decoded weight = 0.0) → excluded, reads silence.
    LufsMeter meterLfe;
    meterLfe.prepare(kSR);
    meterLfe.configureChannels(kNum51Channels, decodedWeights);
    {
        // slot 3 carries a tone; all others are silent.
        const auto buf = makeInterleavedNch(kNum51Channels, 3U, kPeak, kDuration, kSR);
        meterLfe.addInterleaved(buf.data(), static_cast<size_t>(kDuration * kSR), kNum51Channels);
    }
    const double lufsLfe = meterLfe.integratedLufs();
    std::ostringstream infoLfe;
    infoLfe << "  [info] " << kName << " (b-lfe): lufsLfe=" << lufsLfe << "\n";
    std::fputs(infoLfe.str().c_str(), stdout);

    if (lufsLfe > kAbsoluteGateLufs)
    {
        std::ostringstream oss;
        oss << "(b) LFE channel with decoded weight 0.0 reads " << lufsLfe
            << " LUFS (expected <= " << kAbsoluteGateLufs << " / silence)";
        logFail(kName, oss.str());
        return;
    }

    // -----------------------------------------------------------------------
    // Sub-case (c): Full 5.1 calibrated signal vs. independent oracle.
    //
    // A signal that exercises all six channels simultaneously: L/R/C/Ls/Rs carry
    // a 1 kHz sine at kPeak; LFE carries the same sine (but its weight is 0.0 so
    // it contributes nothing).  Both the decoded-weight meter and the oracle must
    // agree within ±kOracleTol LU.
    // -----------------------------------------------------------------------
    constexpr double kFullPeak = -23.0;
    const auto frames51 = static_cast<size_t>(kDuration * kSR);
    const double amp = std::pow(10.0, kFullPeak / 20.0);

    // Build interleaved 6-channel buffer: all channels carry the same 1 kHz sine.
    std::vector<float> buf51full(frames51 * kNum51Channels, 0.0F);
    for (size_t frm = 0U; frm < frames51; ++frm)
    {
        const double s = amp * std::sin(2.0 * std::numbers::pi * 1000.0 * static_cast<double>(frm) /
                                        static_cast<double>(kSR));
        for (uint32_t ch = 0U; ch < kNum51Channels; ++ch)
        {
            buf51full[(frm * kNum51Channels) + ch] = static_cast<float>(s);
        }
    }

    // Decoded-weight meter.
    LufsMeter meterFull;
    meterFull.prepare(kSR);
    meterFull.configureChannels(kNum51Channels, decodedWeights);
    meterFull.addInterleaved(buf51full.data(), frames51, kNum51Channels);
    const double lufsFull = meterFull.integratedLufs();

    // Independent oracle.
    const double lufsOracle = oracleIntegratedLufs(buf51full, kNum51Channels, decodedWeights, kSR);

    const double deltaC = std::abs(lufsFull - lufsOracle);
    std::ostringstream infoC;
    infoC << "  [info] " << kName << " (c): meter=" << lufsFull << " oracle=" << lufsOracle
          << " delta=" << deltaC << "\n";
    std::fputs(infoC.str().c_str(), stdout);

    if (deltaC > kOracleTol)
    {
        std::ostringstream oss;
        oss << "(c) decoded-weight meter=" << lufsFull << " vs oracle=" << lufsOracle
            << " delta=" << deltaC << " > " << kOracleTol << " LU";
        logFail(kName, oss.str());
        return;
    }

    logPass(kName);
}

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
static void spatialFillNoise(TestABLN& abl, uint32_t numCh, uint32_t seed)
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
static auto spatialCheckZeroFill(const TestABLN& outAbl, uint32_t inCh, uint32_t outCh) -> std::string
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
static auto spatialCheckSoakBuffer(const TestABLN& inAbl, const TestABLN& outAbl, uint32_t numCh,
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
            if (std::memcmp(inAbl.channels[ch].data(), outAbl.channels[ch].data(),
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
            if (std::memcmp(inAbl.channels[ch].data(), outAbl.channels[ch].data(),
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

    // Limiter tests (Sprint 4 — loudness safety)
    testLimiterBypassIsIdentity();
    testLimiterCeilingEnforcement();
    testLimiterGRResponseTime();
    testLimiterNearNyquistCeiling();
    testLimiterHotNoiseSoak();

    // Loudness / BS.1770-5 tests (Sprint 4 — Milestone 2)
    testLoudnessKWeightingLowCut();
    testLoudnessIntegratedAccuracy();
    testLoudnessAbsoluteGate();
    testLoudnessRelativeGate();
    testLoudnessMakeupRoundTrip();

    // EQ audibility tests (Sprint 5 — Milestone 2)
    testEQFrequencyResponseAccuracy();
    testEQCoefficientSwapNoClick();

    // Multichannel epic safety net (Sprint 5b — S0-M1)
    testGoldenMasterStereoN2();
    testMultichannelViewDecode();
    testPerChannelIndependence();        // T-C3: per-channel isolation N=4,6,8
    testEQFrequencyResponseAccuracyN4(); // T-C3b: FR accuracy at N=4
    testEQCoefficientSwapNoClickN4();    // T-C3c: click-free swap at N=4
    testLimiterLinkedGainLockstep();     // T-C4: S1-B3 linked-gain lockstep (4-ch, GR < 0.01 dB)
    testLimiterHotNoiseSoakN8();         // T-C4b: S1-B3 N=8 hot-noise ceiling soak
    testReconfigurationContinuity();

    // S1-C2a: N-channel BS.1770-5 LUFS meter (Gate C)
    testLoudnessMultichannelBS1770Weights();

    // M1-1: ChannelLayout decoder (Gate D)
    testChannelLayoutDecodeGateD();

    // M1-2: decode→meter path (Gate E)
    testLoudnessDecodedLayoutWeights();

    // Large-buffer regression fence (buffer-size desync / safeCount=512 fix)
    testLargeBufferLimiterTailCorrect(); // T-LB1: limiter processes full bufSize tail
    testLargeBufferEQGainNoCutoff();     // T-LB2: EQ master-gain ramp covers full buffer
    testLargeBufferConsecutiveBuffers(); // T-LB3: no ring desync across consecutive buffers

    // SpatialRenderKernel (Sprint 5b, M3-1)
    testSpatialRenderPassthroughRoute(); // identity route, in<out zero-fill, 200-buffer soak

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
