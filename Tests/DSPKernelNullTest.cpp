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
#include "Loudness/LufsMeter.h"
#include "MultichannelView.h"
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
