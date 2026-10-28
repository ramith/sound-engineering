// TestSupport.h
//
// Shared infrastructure for DSPKernelNullTest.cpp and all *Tests.inc area files.
// This header is #included at the top of DSPKernelNullTest.cpp (the single translation unit) and of
// the measurement harness EqEngineBreakItMeasure.cpp; NullTestRunner.h includes it too, so it reads
// on its own (#pragma once: one copy per TU).
//
// Contents: all system/project #includes, TestConstants, the verdict/logging layer (each verdict
// is a GoogleTest result; the runner itself is NullTestRunner.h), the test-rig primitives (rig::
// waitUntil, rig::Rendezvous, the thread-CPU meter, min-of-N timing), and any helpers that are
// used by two or more area files.

#pragma once

#include <algorithm>
#include <array>
#include <atomic>
#include <AudioToolbox/AudioToolbox.h>
#include <bit>
#include <chrono>
#include <cmath>
#include <complex>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <ctime>
#include <format>
#include <functional>
#include <limits>
#include <memory>
#include <mutex>
#include <numbers>
#include <optional>
#include <random>
#include <source_location>
#include <span>
#include <sstream>
#include <string>
#include <string_view>
#include <thread>
#include <tuple>
#include <utility>
#include <vector>

#include <csignal>
#include <dlfcn.h>
#include <fcntl.h>
#include <sys/stat.h>
#include <unistd.h>

// GoogleTest 1.18.0 (the third_party/googletest submodule, pinned in toolchain/toolchain.env) runs
// the null test: every test body's verdict below is a GoogleTest result.
#include <gtest/gtest.h>

#include "DeviceCapability.h"
#include "DSPKernel.h"
#include "EQ/EQModule.h"
#include "EQ/EQTargets.h"
#include "EQ/GraphicEQDesigner.h"
#include "EQDesignBridge.h"
#include "FFmpegBridge.h"
#include "FFmpegLoader.h"
#include "FileDecodeSource.h"
#include "FlushToZero.h"
#include "GaplessSource.h"
#include "Limiting/LimiterModule.h"
#include "Limiting/OutputCeiling.h"
#include "Loudness/ChannelLayoutDecoder.h"
#include "Loudness/LufsMeter.h"
#include "Loudness/TrackLoudnessProfile.h"
#include "Loudness/TrackLoudnessProfiler.h"
#include "MetadataBridge.h"
#include "MultichannelView.h"
#include "PureModeFormat.h"
#include "PureModeSource.h"
#include "Spatial/SpatialRenderKernel.h"
#include "TargetState.h"
#include "TrackLoudnessBridge.h"

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
#define ADAPTIVESOUND_TEST_DATA_DIR "test-data"
#endif

// ---------------------------------------------------------------------------
// Named constants — no magic numbers per clang-tidy
// ---------------------------------------------------------------------------

namespace TestConstants
{
    constexpr uint32_t kSampleRate48k = 48000U;
    constexpr uint32_t kSampleRate44k = 44100U; // CD rate; used by the EQ FR sweep (US-QA-03)
    constexpr uint32_t kFrames512 = 512U;
    constexpr uint32_t kTotalFrames1s = 48000U; // 1 second at 48 kHz
    constexpr uint32_t kChunks3 = 3U;
    constexpr uint32_t kChunks10 = 10U;

    // RNG seeds: fixed for deterministic test sequences (intentional, not a security concern).
    constexpr uint32_t kSeedWhiteNoise = 42U;
    constexpr uint32_t kSeedMultiChunk = 99U;
    constexpr uint32_t kSeedBypassSingle = 0xDEADBEEFU;
    constexpr uint32_t kSeedBypassMulti = 0xCAFEBABEU;

    constexpr float kNoiseHalf = 0.5F;   // noise amplitude +-0.5
    constexpr float kNoiseUnit = 1.0F;   // noise amplitude +-1.0
    constexpr float kConstantDC = 0.1F;  // DC level for identity test
    constexpr float kChirpF0 = 20.0F;    // chirp start frequency (Hz)
    constexpr float kChirpF1 = 20000.0F; // chirp end frequency (Hz)
    constexpr float kChirpAmpl = 0.5F;   // chirp amplitude
    constexpr float kChirpDuration = 1.0F;

    // The committed bit-exact signature of the stereo chain's output on the chirp above
    // (GoldenMaster_StereoN2_v1, and Crossfeed_Bypass_BitExact_GoldenMaster with crossfeed present
    // but off). Re-baseline ONLY on a deliberate DSP change — history in GoldenMaster_StereoN2_v1.
    constexpr uint64_t kGoldenMasterStereoN2Hash = 0xF0E1D4EF83763709ULL;
    // The shipping path's signature (R1.1-B, level-and-fold §7, architect N8): the same chirp at Intensity 0
    // (P1), the EQ Off, through the Realizer with a plan whose leveling gain is −7.07 dB (§4's worked example's
    // g) on a Bluetooth output (GoldenMaster_StereoN2_P1Leveled_v1). Re-baseline ONLY on a deliberate DSP change.
    constexpr uint64_t kGoldenMasterStereoP1LeveledHash = 0xE6D871E710A80759ULL;

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
    constexpr uint32_t kPerChBins[] = {34U, 59U, 89U, 116U, 149U, 173U, 211U, 251U};

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
// Verdicts — every test body ends in exactly one of logPass / logFail / logPending, and each is a
// GoogleTest result for the test that is running (NullTestRunner.h registers the bodies). std::fputs
// avoids cppcoreguidelines-pro-type-vararg.
// ---------------------------------------------------------------------------

namespace
{
    // Set by a verdict, cleared by the runner before each body: a body that returns without one
    // (a forgotten logPass on some path) fails instead of passing silently. Atomic: a verdict may
    // come from a thread the test started.
    std::atomic<bool> gVerdictGiven{false};
} // namespace

// The test passed. GoogleTest's "[       OK ]" line reports it, with the time it took. The name must
// be the running test's own (a copied kName would otherwise report a pass for the wrong test).
static auto logPass(const char* testName) -> void
{
    gVerdictGiven.store(true, std::memory_order_relaxed);
    const testing::TestInfo* running = testing::UnitTest::GetInstance()->current_test_info();
    if (running != nullptr && std::string_view(running->name()) != testName)
    {
        ADD_FAILURE() << "[FAIL] " << running->name() << " -- its body passed as '" << testName
                      << "'";
    }
}

// The test failed: a GoogleTest failure at the call site (file:line), naming the test and why. A
// test may fail more than once; any failure fails it.
static auto logFail(const char* testName,
                    std::string_view reason,
                    std::source_location where = std::source_location::current()) -> void
{
    gVerdictGiven.store(true, std::memory_order_relaxed);
    ADD_FAILURE_AT(where.file_name(), static_cast<int>(where.line()))
        << "[FAIL] " << testName << " -- " << reason;
}

// A test that is intentionally not yet implemented (lands in a later epic milestone): reported as
// SKIPPED, neither a pass nor a failure, so the suite gate stays green.
static auto logPending(const char* testName, const char* note) -> void
{
    gVerdictGiven.store(true, std::memory_order_relaxed);
    GTEST_SKIP() << "[PENDING] " << testName << " -- " << note;
}

// Emit an [info] line (stdout, line-buffered by the runner).
static auto logInfo(const std::string& line) -> void
{
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
    AudioBufferList head{}; // mNumberBuffers + mBuffers[0]
    AudioBuffer extra{};    // provides storage for mBuffers[1]

    AudioBufferList2()
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
    AudioBufferList head{};                             // mNumberBuffers + mBuffers[0]
    std::array<AudioBuffer, kMaxChannels - 1U> extra{}; // mBuffers[1..kMaxChannels-1]

    explicit AudioBufferListN(uint32_t numCh)
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

// Build an identity TargetState: EQ passthrough (the default EQParams: no design, every m1 = 0),
// all other modules explicitly disabled / neutralised.
//
// Each real module that could alter the signal is set to its bypass/identity
// condition so chain null-tests measure only EQ identity:
//   clarity.enabled = 0       — stub, no-op
//   limiter.truePeakCeilingLinear = 2.0F — ceiling ≥ 1.0 → zero-latency bypass
//     (the limiter's ring-based path is only entered when ceiling < 1.0; at 2.0
//      process() returns immediately after the null-guard, giving bit-exact output)
static auto makeIdentityState() -> TargetState
{
    TargetState state{};
    state.intensityLinear = 1.0F; // documentary clarity; matches the struct default
    state.eq = EQParams{};
    state.clarity.enabled = 0U;                 // stub module -- no-op
    state.limiter.truePeakCeilingLinear = 2.0F; // bypass: ceiling ≥ 1.0 → identity
    return state;
}

// The EQParams the Realizer publishes for `points` at `sampleRate`: the production
// GraphicEQDesigner's design as finished (k, m1), gliding over `rampSeconds`. The identity
// (EQParams{}) if the design is rejected.
static auto makeEqParams(const std::array<float, kEqBandCount>& points,
                         uint32_t sampleRate,
                         float rampSeconds = kEqDefaultRampSeconds) -> EQParams
{
    auto designer = std::make_unique<GraphicEQDesigner>();
    GraphicEQDesign design{};
    if (!designer->design(points, static_cast<double>(sampleRate), design))
    {
        return EQParams{};
    }
    return EQTargets::toParams(design, rampSeconds);
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
    constexpr size_t kBand1kHzIndex = 17U; // GraphicEQ::centreHz(17) == 1000 Hz
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
        state.eq = makeEqParams(gains, TestConstants::kSampleRate48k);
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
    flatState.eq = makeEqParams(flatGains, TestConstants::kSampleRate48k);
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
    boostState.eq = makeEqParams(boostedGains, TestConstants::kSampleRate48k);
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
// The test rig — the primitives every timing-sensitive test is built from (the four rules of the
// test-rig redesign, docs/development/testing.md):
//   1. Time only ever breaks hangs. A wait waits for a STATE (rig::waitUntil, rig::pumpUntil); its
//      generous cap fails the test, naming the state, and the caller returns — it never carries on
//      past a deadline. A thread held at a point is released by the test (rig::Rendezvous).
//   2. Measure the component, never the machine: the component's own counters, or the CPU time of
//      the thread doing the work (rig::threadCpuTime), the least of N runs (rig::minThreadCpu).
//      Wall time is a hang guard and an [info] figure, never a budget: steady_clock counts the
//      time a thread was descheduled, and on Apple platforms the time the Mac slept.
//   3. Each test owns its world.
//   4. Every run has a ceiling (NullTestRunner.h's watchdog) and reports everything.
// ---------------------------------------------------------------------------

namespace rig
{
    // The time the Mac has been AWAKE (CLOCK_UPTIME_RAW: it "does not increment while the system
    // is asleep"). The hang caps and the watchdog's ceilings use it: steady_clock on Apple
    // platforms counts sleep, so a laptop that slept through a run would trip them all on waking.
    struct AwakeClock
    {
        using duration = std::chrono::nanoseconds;
        using time_point = std::chrono::time_point<AwakeClock>;
        static auto now() noexcept -> time_point
        {
            return time_point{
                duration{static_cast<duration::rep>(clock_gettime_nsec_np(CLOCK_UPTIME_RAW))}};
        }
    };

    // What the running test is doing (a string literal, or a string that outlives the step: no
    // allocation, so a test may set it inside an RT-allocation guard). The watchdog prints it when
    // a test overruns its ceiling; the runner resets it before each test.
    inline std::atomic<const char*> gProgress{"started"};

    // Names what the test is doing until the scope ends, then restores the previous note.
    class Progress
    {
      public:
        explicit Progress(const char* note) noexcept
            : previous_(gProgress.exchange(note, std::memory_order_acq_rel))
        {
        }
        ~Progress()
        {
            gProgress.store(previous_, std::memory_order_release);
        }
        Progress(const Progress&) = delete;
        Progress(Progress&&) = delete;
        auto operator=(const Progress&) -> Progress& = delete;
        auto operator=(Progress&&) -> Progress& = delete;

      private:
        const char* previous_;
    };

    // How many times slower this build runs than a plain one: the sanitizers instrument every
    // memory access. Every time cap in the rig scales by it — this wait cap and the per-test
    // ceilings (NullTestRunner.h) — so a slow but passing run never reads as a hang.
#if __has_feature(thread_sanitizer)
    inline constexpr int kSanitizerSlowdown = 8;
#elif __has_feature(address_sanitizer)
    inline constexpr int kSanitizerSlowdown = 3;
#else
    inline constexpr int kSanitizerSlowdown = 1;
#endif

    // One wait's hang cap. Generous: a passing run never comes near it, so only a hang reaches it
    // (and under the per-test ceiling, so the wait names its state before the watchdog fires).
    inline constexpr std::chrono::seconds kHangCap{60 * kSanitizerSlowdown};

    // What one step of a pump did (rig::pumpUntil).
    enum class Pump : uint8_t
    {
        Done,       // the state is reached
        Progressed, // moved on (pulled frames): step again at once
        Idle,       // nothing to do yet (a decoder still filling): nap, then step again
    };

    // Step until `step()` says Pump::Done; true once it does, false if `cap` passed first. Naps
    // only after an Idle step. NOT reported: the caller reports and returns (an RT-allocation soak
    // calls this inside its guard, where a report would allocate). Prefer pumpUntil.
    template <typename Step>
    [[nodiscard]] auto pumped(const char* state, Step step, std::chrono::seconds cap = kHangCap)
        -> bool
    {
        using namespace std::chrono_literals;
        constexpr int kYieldSpins = 64;
        const Progress progress(state);
        const AwakeClock::time_point deadline = AwakeClock::now() + cap;
        int idleSpins = 0;
        for (;;)
        {
            const Pump result = step();
            if (result == Pump::Done)
            {
                return true;
            }
            if (AwakeClock::now() >= deadline)
            {
                return false;
            }
            if (result == Pump::Progressed)
            {
                idleSpins = 0;
            }
            else if (++idleSpins < kYieldSpins)
            {
                std::this_thread::yield();
            }
            else
            {
                std::this_thread::sleep_for(200us);
            }
        }
    }

    // Wait until `done()` holds (polled: yield, then short naps); true once it does, false if `cap`
    // passed first. NOT reported — prefer waitUntil.
    template <typename Done>
    [[nodiscard]] auto reached(const char* state, Done done, std::chrono::seconds cap = kHangCap)
        -> bool
    {
        return pumped(state, [&done] { return done() ? Pump::Done : Pump::Idle; }, cap);
    }

    // The failure for a state never reached: at the waiter's call site, naming the state.
    inline auto failNeverReached(const char* state,
                                 std::chrono::seconds cap,
                                 const std::source_location& where) -> void
    {
        gVerdictGiven.store(true, std::memory_order_relaxed); // a failure is a verdict
        ADD_FAILURE_AT(where.file_name(), static_cast<int>(where.line()))
            << "[FAIL] never reached: " << state << " (hang cap " << cap.count() << " s)";
    }

    // Wait until `done()` holds. If the cap passes first the test FAILS, naming `state`, and this
    // returns false: the caller returns (nodiscard) — it never carries on past the cap.
    template <typename Done>
    [[nodiscard]] auto waitUntil(const char* state,
                                 Done done,
                                 std::chrono::seconds cap = kHangCap,
                                 std::source_location where = std::source_location::current())
        -> bool
    {
        if (reached(state, std::move(done), cap))
        {
            return true;
        }
        failNeverReached(state, cap, where);
        return false;
    }

    // Step until `step()` says Pump::Done (a drain that pulls as it waits). If the cap passes first
    // the test FAILS, naming `state`, and this returns false.
    template <typename Step>
    [[nodiscard]] auto pumpUntil(const char* state,
                                 Step step,
                                 std::chrono::seconds cap = kHangCap,
                                 std::source_location where = std::source_location::current())
        -> bool
    {
        if (pumped(state, std::move(step), cap))
        {
            return true;
        }
        failNeverReached(state, cap, where);
        return false;
    }

    // A thread held at a point until the test lets it go — GaplessArmContract's seam pause,
    // generalised. The thread that reaches the point (from a product test hook) arrives and waits
    // for the release; the test waits for the arrival, acts while the thread is held, then releases.
    // Only the first arrival stops; later ones pass. Every wait is bounded and names the point, so a
    // regression fails the test instead of hanging the suite.
    class Rendezvous
    {
      public:
        explicit Rendezvous(std::string_view point)
            : arrivedState_(std::format("{}: the held thread arrived", point)),
              releasedState_(std::format("{}: the test released the held thread", point))
        {
        }

        // The held thread: the first arrival waits for release(). False if the release never came
        // (the test has failed); the thread then goes on.
        auto arriveAndWait() -> bool
        {
            if (arrived_.exchange(true, std::memory_order_acq_rel))
            {
                return true;
            }
            return waitUntil(releasedState_.c_str(),
                             [this] { return released_.load(std::memory_order_acquire); });
        }

        // The test: wait until the thread arrived — or `cannotArrive()` says it never will (it
        // finished without reaching the point), which fails the test at once.
        template <typename CannotArrive>
        [[nodiscard]] auto
        awaitArrival(CannotArrive cannotArrive,
                     std::source_location where = std::source_location::current()) -> bool
        {
            const bool settled = waitUntil(
                arrivedState_.c_str(),
                [&] { return arrived() || cannotArrive(); },
                kHangCap,
                where);
            if (settled && !arrived())
            {
                gVerdictGiven.store(true, std::memory_order_relaxed);
                ADD_FAILURE_AT(where.file_name(), static_cast<int>(where.line()))
                    << "[FAIL] " << arrivedState_ << " — no: it finished without reaching it";
                return false;
            }
            return settled;
        }

        // The test: let the held thread go (also a thread that has not arrived yet: it then passes).
        void release() noexcept
        {
            released_.store(true, std::memory_order_release);
        }

        [[nodiscard]] auto arrived() const noexcept -> bool
        {
            return arrived_.load(std::memory_order_acquire);
        }

      private:
        std::string arrivedState_;
        std::string releasedState_;
        std::atomic<bool> arrived_{false};
        std::atomic<bool> released_{false};
    };

    // The CPU time the CALLING thread has used (CLOCK_THREAD_CPUTIME_ID, as SRCQualityMeasure
    // measures). Unlike steady_clock it does not advance while the thread waits, is descheduled or
    // the Mac sleeps — so a busy machine cannot inflate it. Allocation-free.
    [[nodiscard]] inline auto threadCpuTime() noexcept -> std::chrono::nanoseconds
    {
        return std::chrono::nanoseconds{static_cast<std::chrono::nanoseconds::rep>(
            clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID))};
    }

    // The thread CPU time `run()` takes, the least of `runs` runs: noise (a cold cache, an
    // efficiency core, an interrupt) only ever adds time, so the minimum is the code's own cost.
    template <typename Run>
    [[nodiscard]] auto minThreadCpu(int runs, Run run) -> std::chrono::nanoseconds
    {
        auto best = std::chrono::nanoseconds::max();
        for (int index = 0; index < std::max(1, runs); ++index)
        {
            const std::chrono::nanoseconds before = threadCpuTime();
            run();
            best = std::min(best, threadCpuTime() - before);
        }
        return best;
    }

    // Which timing budgets this build enforces (rule 2). The real budgets hold for an optimised,
    // uninstrumented build: the -O2 timing run (scripts/build-null-test.sh --opt-run), on the least
    // of kTimingRuns runs of thread CPU time. A debug or sanitizer build only trips a catastrophic
    // regression, ≥ 10× above what that build measures, on one run.
#if defined(__OPTIMIZE__) && !__has_feature(address_sanitizer) && !__has_feature(thread_sanitizer)
    inline constexpr bool kStrictBudgets = true;
    inline constexpr const char* kBuild = "optimised";
#elif __has_feature(thread_sanitizer)
    inline constexpr bool kStrictBudgets = false;
    inline constexpr const char* kBuild = "tsan";
#elif __has_feature(address_sanitizer)
    inline constexpr bool kStrictBudgets = false;
    inline constexpr const char* kBuild = "asan";
#else
    inline constexpr bool kStrictBudgets = false;
    inline constexpr const char* kBuild = "debug -O0";
#endif
    inline constexpr int kTimingRuns = kStrictBudgets ? 5 : 1;

    // One timing budget: the real one, and each instrumented build's catastrophic tripwire.
    struct Budget
    {
        double strict;
        double debug;
        double asan;
        double tsan;
    };

    // The bound this build enforces for `budget`.
    [[nodiscard]] constexpr auto limit(const Budget& budget) noexcept -> double
    {
#if __has_feature(thread_sanitizer)
        return budget.tsan;
#elif __has_feature(address_sanitizer)
        return budget.asan;
#else
        return kStrictBudgets ? budget.strict : budget.debug;
#endif
    }
} // namespace rig
