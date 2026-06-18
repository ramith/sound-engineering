// TestSupport.h
//
// Shared infrastructure for DSPKernelNullTest.cpp and all *Tests.inc area files.
// This header is #included ONCE at the top of DSPKernelNullTest.cpp (which is the
// single translation unit). It must not be included from anywhere else.
//
// Contents: all system/project #includes, TestConstants, the results/logging layer,
// the generic test runner (TestEntry/runOneTest/runAllTests/printSummary), and any
// helpers that are used by two or more area files.

#pragma once

#include <algorithm>
#include <array>
#include <atomic>
#include <AudioToolbox/AudioToolbox.h>
#include <bit>
#include <chrono>
#include <cmath>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <functional>
#include <mutex>
#include <numbers>
#include <random>
#include <sstream>
#include <string>
#include <thread>
#include <vector>

#include "DeviceCapability.h"
#include "DSPKernel.h"
#include "EQ/EQModuleCoefficients.h"
#include "FileDecodeSource.h"
#include "Loudness/ChannelLayoutDecoder.h"
#include "Loudness/LufsMeter.h"
#include "MultichannelView.h"
#include "PureModeFormat.h"
#include "PureModeSource.h"
#include "Spatial/SpatialRenderKernel.h"
#include "TargetState.h"

using namespace AdaptiveSound;

// ---------------------------------------------------------------------------
// Test-fixture directory. build-null-test.sh passes the absolute path of
// <repo>/test-data via -DADAPTIVESOUND_TEST_DATA_DIR; fixtures are written + read THERE
// (never /tmp). The fallback ("test-data", relative to the working dir) lets clang-tidy and
// other compiles that don't set the macro still resolve a path. Tests build fixture paths as
// `ADAPTIVESOUND_TEST_DATA_DIR "/<name>.wav"` (compile-time string-literal concatenation).
// ---------------------------------------------------------------------------
#ifndef ADAPTIVESOUND_TEST_DATA_DIR
// A macro (not a constexpr) is REQUIRED: fixture paths use compile-time string-literal
// concatenation — `ADAPTIVESOUND_TEST_DATA_DIR "/name.wav"` — which only works with literal tokens.
// NOLINTNEXTLINE(cppcoreguidelines-macro-usage)
#define ADAPTIVESOUND_TEST_DATA_DIR "test-data"
#endif

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

    // Pure-Mode policy (Phase B — B1). Sample rates measured on the founder's Mac.
    constexpr double kRate16k = 16000.0;
    constexpr double kRate32k = 32000.0;
    constexpr double kRate44k = 44100.0;
    constexpr double kRate48k = 48000.0;
    constexpr double kRate88k = 88200.0;
    constexpr double kRate96k = 96000.0;
    constexpr double kRate192k = 192000.0;
    constexpr double kRateEpsilonProbe = 44099.5; // within 1.0 Hz of 44100 → counts as supported

    // Transport-type FourCCs (documentary fidelity only — the policy ignores them and keys off the
    // semantic booleans). Values match kAudioDeviceTransportType* in
    // <CoreAudio/AudioHardwareBase.h>.
    constexpr uint32_t kTransportHDMI = 0x68646D69U;      // 'hdmi'
    constexpr uint32_t kTransportBluetooth = 0x626C7565U; // 'blue'
    constexpr uint32_t kTransportBuiltIn = 0x626C746EU;   // 'bltn'
    constexpr uint32_t kTransportVirtual = 0x76697274U;   // 'virt'

    // Common bit depths used when hand-building the device fixtures.
    constexpr uint32_t kBits24 = 24U;
    constexpr uint32_t kBits32 = 32U;
    constexpr uint32_t kStereo = 2U;
    constexpr uint32_t kMono = 1U;
} // namespace TestConstants

// ---------------------------------------------------------------------------
// Test result counter — struct avoids cppcoreguidelines-avoid-non-const-globals
// ---------------------------------------------------------------------------

namespace
{
    struct Results
    {
        std::atomic<int> passed{0};
        std::atomic<int> failed{0};
    };

    Results gResults; // NOLINT(cppcoreguidelines-avoid-non-const-globals)

    // Per-thread output buffer for parallel mode: each test accumulates its
    // stdout/stderr lines here, then flushes them atomically under gOutputMutex.
    // In serial mode this buffer is unused (logPass/logFail write directly).
    // NOLINTBEGIN(cppcoreguidelines-avoid-non-const-globals)
    thread_local std::string tlOutputBuf;
    thread_local bool tlTestPassed{true};
    // tlTestPending: set by logPending so runOneTest does not count the test as pass or fail.
    thread_local bool tlTestPending{false};
    // NOLINTEND(cppcoreguidelines-avoid-non-const-globals)

    std::mutex gOutputMutex; // NOLINT(cppcoreguidelines-avoid-non-const-globals)

    // When non-null, output goes to tlOutputBuf instead of directly to the stream.
    // NOLINTBEGIN(cppcoreguidelines-avoid-non-const-globals)
    thread_local bool tlBuffering{false};
    // NOLINTEND(cppcoreguidelines-avoid-non-const-globals)
} // namespace

// ---------------------------------------------------------------------------
// Logging helpers — std::fputs avoids cppcoreguidelines-pro-type-vararg
// ---------------------------------------------------------------------------

static auto logPass(const char* testName) -> void
{
    std::string line = std::string("[PASS] ") + testName + "\n";
    if (tlBuffering)
    {
        tlOutputBuf += line;
        tlTestPassed = true;
    }
    else
    {
        std::fputs(line.c_str(), stdout);
        ++gResults.passed;
    }
}

static auto logFail(const char* testName, const std::string& reason) -> void
{
    std::string line = std::string("[FAIL] ") + testName + " -- " + reason + "\n";
    if (tlBuffering)
    {
        tlOutputBuf += line;
        tlTestPassed = false;
    }
    else
    {
        std::fputs(line.c_str(), stderr);
        ++gResults.failed;
    }
}

// A test that is intentionally not yet implemented (lands in a later epic milestone). Prints a
// PENDING line but does NOT count as pass or fail, so the suite gate stays green.
static auto logPending(const char* testName, const char* note) -> void
{
    std::string line = std::string("[PENDING] ") + testName + " -- " + note + "\n";
    if (tlBuffering)
    {
        tlOutputBuf += line;
        tlTestPending = true; // signal runOneTest: do not count as pass or fail
    }
    else
    {
        std::fputs(line.c_str(), stdout);
    }
}

// Emit an [info] line. Goes to stdout (serial) or the thread buffer (parallel).
static auto logInfo(const std::string& line) -> void
{
    if (tlBuffering)
    {
        tlOutputBuf += line;
    }
    else
    {
        std::fputs(line.c_str(), stdout);
    }
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
// EQ test helpers shared between EqTests.inc and MultichannelTests.inc.
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

// ---------------------------------------------------------------------------
// Part C helpers — parameterized test bodies extracted to eliminate duplication.
// All helpers are pure functions: no static mutable local state.
// ---------------------------------------------------------------------------

// Shared body for EQ coefficient-swap no-click tests (N=2 stereo and N=4).
// Feeds a phase-continuous 1 kHz sine flat, then swaps to +12 dB @ 1 kHz mid-stream,
// and asserts no audible click at the swap boundary for every channel.
// N=2 uses the legacy info format (no per-channel prefix); N=4 includes "ch<k>" prefix.
// Returns "" on pass, a non-empty error string on failure.
// Drive `numBlocks` blocks of a phase-continuous 1 kHz sine at `kEqTestAmplitude`
// through `kernel`, appending per-channel output to `out`. `sampleIdx` tracks the
// running sample position for phase continuity across calls.
static auto eqSwapRunBlocks(DSPKernel& kernel,
                            uint32_t numCh,
                            uint32_t numBlocks,
                            float kSR,
                            std::vector<std::vector<float>>& out,
                            uint32_t& sampleIdx) -> void
{
    constexpr uint32_t kBlock = TestConstants::kFrames512;
    for (uint32_t blk = 0U; blk < numBlocks; ++blk)
    {
        TestABLN abl(numCh, kBlock);
        for (uint32_t ch = 0U; ch < numCh; ++ch)
        {
            for (uint32_t idx = 0U; idx < kBlock; ++idx)
            {
                abl.channels[ch][idx] =
                    kEqTestAmplitude * std::sin(2.0F * std::numbers::pi_v<float> * kEqTestToneHz *
                                                static_cast<float>(sampleIdx + idx) / kSR);
            }
        }
        sampleIdx += kBlock;
        kernel.process(abl.abl(), kBlock);
        for (uint32_t ch = 0U; ch < numCh; ++ch)
        {
            for (uint32_t idx = 0U; idx < kBlock; ++idx)
            {
                out[ch].push_back(abl.channels[ch][idx]);
            }
        }
    }
}

// Shared body for EQ coefficient-swap no-click tests (N=2 stereo and N=4).
// Feeds a phase-continuous 1 kHz sine flat, then swaps to +12 dB @ 1 kHz mid-stream,
// and asserts no audible click at the swap boundary for every channel.
// N=2 uses the legacy info format (no per-channel prefix); N=4 includes "ch<k>" prefix.
// Returns "" on pass, a non-empty error string on failure.
static auto eqSwapNoClickBody(uint32_t numCh, const char* kName) -> std::string
{
    constexpr uint32_t kBlock = TestConstants::kFrames512;
    constexpr uint32_t kBlocksBefore = 16U;
    constexpr uint32_t kBlocksAfter = 16U;
    constexpr float kBoostDbLarge = 12.0F;
    const float kSR = static_cast<float>(TestConstants::kSampleRate48k);

    DSPKernel kernel;
    kernel.initialize(TestConstants::kSampleRate48k, kBlock);

    std::array<float, kEqBands> flatGains{};
    std::array<float, kEqBands> boostedGains{};
    boostedGains[kBand1kHzIndex] = kBoostDbLarge;

    TargetState flatState = makeIdentityState();
    flatState.eq = EQModuleCoefficients::computeBiquadCascade(flatGains, kSR);
    kernel.publishTargetState(flatState);

    std::vector<std::vector<float>> out(numCh);
    for (uint32_t ch = 0U; ch < numCh; ++ch)
    {
        out[ch].reserve(static_cast<size_t>(kBlock) * (kBlocksBefore + kBlocksAfter));
    }
    uint32_t sampleIdx = 0U;
    eqSwapRunBlocks(kernel, numCh, kBlocksBefore, kSR, out, sampleIdx);
    const size_t swapSample = out[0].size();

    TargetState boostState = makeIdentityState();
    boostState.eq = EQModuleCoefficients::computeBiquadCascade(boostedGains, kSR);
    kernel.publishTargetState(boostState);
    eqSwapRunBlocks(kernel, numCh, kBlocksAfter, kSR, out, sampleIdx);

    // N=2 (stereo): check only the left channel (ch0) to match the legacy test which
    // captured only abl.left; N>=4: check all channels independently.
    const uint32_t kChToCheck = (numCh == 2U) ? 1U : numCh;

    for (uint32_t ch = 0U; ch < kChToCheck; ++ch)
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
        if (numCh == 2U)
        {
            // Stereo (N=2) format: no channel prefix, "settledBoostedMaxStep" label.
            info << "boundaryStep=" << boundaryStep << " settledBoostedMaxStep=" << settledMaxStep;
        }
        else
        {
            // Multichannel format: per-channel prefix, "settledMaxStep" label.
            info << "ch" << ch << " boundaryStep=" << boundaryStep
                 << " settledMaxStep=" << settledMaxStep;
        }

        if (boundaryStep > 3.0F * settledMaxStep)
        {
            return "audible coefficient-swap click: " + info.str();
        }
        logInfo("  [info] " + std::string(kName) + ": " + info.str() + "\n");
    }
    return {};
}

// ---------------------------------------------------------------------------
// Generic test runner
// ---------------------------------------------------------------------------

namespace
{
    struct TestEntry
    {
        const char* name;
        void (*fn)();
        bool parallelSafe;
    };
} // namespace

// Thread-safe test runner. In serial mode (parallelN<=1) each test writes directly.
// In parallel mode the test body writes to tlOutputBuf; runOneTest then flushes
// the buffer and updates the counters under gOutputMutex.
static auto runOneTest(const TestEntry& entry) -> void
{
    // Activate buffering so logPass/logFail/logPending/logInfo accumulate to tlOutputBuf.
    tlBuffering = true;
    tlOutputBuf.clear();
    tlTestPassed = true;   // may be overwritten by logFail
    tlTestPending = false; // may be set by logPending

    entry.fn();

    // Flush the accumulated output and update the global counters atomically.
    {
        const std::lock_guard<std::mutex> lock(gOutputMutex);
        if (tlTestPending)
        {
            // PENDING: not pass, not fail — print to stdout, no counter update.
            std::fputs(tlOutputBuf.c_str(), stdout);
        }
        else if (tlTestPassed)
        {
            std::fputs(tlOutputBuf.c_str(), stdout);
            ++gResults.passed;
        }
        else
        {
            // Write non-FAIL lines to stdout, FAIL lines to stderr.
            std::istringstream ss(tlOutputBuf);
            std::string ln;
            while (std::getline(ss, ln))
            {
                ln += '\n';
                if (ln.contains("[FAIL]"))
                {
                    std::fputs(ln.c_str(), stderr);
                }
                else
                {
                    std::fputs(ln.c_str(), stdout);
                }
            }
            ++gResults.failed;
        }
    }

    tlBuffering = false;
}

// Print the results summary and return the process exit code.
static auto printSummary() -> int
{
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

// Run all registered tests. parallelN<=1 → serial (default). parallelN>1 → parallel-safe
// entries run on a pool of parallelN workers (atomic work-stealing), then serial-only entries run
// sequentially in registration order.
static auto runAllTests(int parallelN, const std::array<TestEntry, 74U>& kTests) -> void
{
    if (parallelN <= 1)
    {
        // Serial path: run every test in registration order, writing directly to streams.
        for (const auto& entry : kTests)
        {
            entry.fn();
        }
        return;
    }

    // Parallel path: split into safe (parallelisable) and serial-only (env/tmp side-effects).
    // Run parallel-safe entries first on a worker pool, then serial-only in order.

    // Collect indices of parallel-safe and serial-only entries.
    std::vector<std::size_t> parallelIdx;
    std::vector<std::size_t> serialIdx;
    parallelIdx.reserve(kTests.size());
    serialIdx.reserve(kTests.size());
    for (std::size_t idx = 0U; idx < kTests.size(); ++idx)
    {
        if (kTests[idx].parallelSafe)
        {
            parallelIdx.push_back(idx);
        }
        else
        {
            serialIdx.push_back(idx);
        }
    }

    // Atomic work-steal index for the parallel pool.
    std::atomic<std::size_t> workIdx{0U};
    const auto workerBody = [&]()
    {
        for (;;)
        {
            const std::size_t myIdx = workIdx.fetch_add(1U, std::memory_order_relaxed);
            if (myIdx >= parallelIdx.size())
            {
                break;
            }
            runOneTest(kTests[parallelIdx[myIdx]]);
        }
    };

    // Cap to hardware concurrency (minimum 2).
    const int numWorkers = std::max(2, parallelN);
    std::vector<std::thread> workers;
    workers.reserve(static_cast<std::size_t>(numWorkers));
    for (int wk = 0; wk < numWorkers; ++wk)
    {
        workers.emplace_back(workerBody);
    }
    for (auto& thr : workers)
    {
        thr.join();
    }

    // Serial-only entries run in registration order after the parallel phase completes.
    for (const std::size_t idx : serialIdx)
    {
        kTests[idx].fn();
    }
}
