// Tests/HandleLeakHarness.mm
//
// Headless leak-DETECTION harness for the C-ABI opaque handles (audit hole #2).
//
// WHY THIS EXISTS: macOS / Apple-Silicon AddressSanitizer ships NO LeakSanitizer, so
// `make sanitize` / `make tsan` / `make sanitize-library-store` catch use-after-free,
// heap overruns and data races but are BLIND to plain memory leaks. This harness closes
// that hole by exercising the opaque-handle create/destroy lifecycles under
// `xcrun leaks --atExit` (see scripts/build-leak-check.sh) — `leaks` does a conservative
// heap-reachability scan at process exit and reports any allocation no live pointer
// reaches. Reachable-but-never-freed globals (CoreAudio HAL singletons, dlopen'd libav,
// the Obj-C runtime) are NOT reported, so this is a targeted net for OUR handle lifecycles.
//
// It is a STANDALONE main() (never linked into the app / SwiftPM). It drives ONLY the
// C-ABI surface the Swift side calls, with NO live audio device and NO network, so it runs
// headless in CI without hanging. Each leg loops ~64x: `leaks` needs only a single leaked
// iteration to fire, but the loop shakes out any PER-ITERATION leak a one-shot would miss.
//
// Legs (calling the C-ABI / C++ classes directly):
//   1. LoudnessMeter    — loudnessMeterCreate / AddStereo / Read / Destroy (headless DSP,
//                         no device, no ffmpeg). This is the PLANTABLE leg (see below).
//   2. FileDecodeSource — open() the m4a fixture via Apple ExtAudioFile, pull a few blocks,
//                         dtor joins the decode thread + frees the pimpl (no device, no ffmpeg).
//   3. PureModeSession  — create → start(deviceID=0 → the policy declines, returns 0) → destroy.
//                         With deviceID 0 there is no device access and no hang; the
//                         FileDecodeSource the start opened is freed on that declined return,
//                         and the session (GaplessSource + engine) on destroy.
//   4. FFmpeg metadata  — ffmpegOpenMetadata / scalar+tag+art accessors / Close over the flac
//                         fixture (ffmpeg-gated on <libavformat/avformat.h>).
//   5. EQ designer      — asEqDesignerCreate / asEqDesign (two rates) / asEqDesignerDestroy
//                         (headless DSP, no device).
//   6. Track loudness   — asLoudnessProfilerCreate / Feed (one chunk rejected as non-finite) /
//                         FinishPrefix / FinishFull / GetInfo / PredictChangeDb, the profiler
//                         destroyed BEFORE its two profile handles (they outlive it), then
//                         asLoudnessProfileDestroy (headless DSP, no device).
//
// PLANT-A-LEAK: with -DADAPTIVE_PLANT_LEAK=1 the LAST loudness iteration deliberately SKIPS
// loudnessMeterDestroy, leaking exactly one handle. scripts/build-leak-check.sh builds that
// second binary and asserts `leaks` catches it (inverted exit) — proving this gate is not a
// no-op. loudness is the plantable leg on purpose: its leaked block's allocation stack carries
// `loudnessMeterCreate`, an easy, unambiguous string for the build script to grep for.

#import <Foundation/Foundation.h>

// DeviceBridge.h: loudnessMeter* + CLoudnessReadout; re-exports PureModeBridge.h, MetadataBridge.h,
// EQDesignBridge.h and TrackLoudnessBridge.h.
#include "DeviceBridge.h"
#include "FileDecodeSource.h" // AdaptiveSound::FileDecodeSource (C++ class)

#include <cmath>
#include <cstdint>
#include <cstdio>
#include <limits>
#include <numbers>

// The fixtures directory (Tests/Fixtures/artwork-audio) is injected as a quoted string
// literal by the build script, exactly like build-null-test.sh's ADAPTIVESOUND_TEST_DATA_DIR.
#ifndef ADAPTIVE_FIXTURES_DIR
#error "ADAPTIVE_FIXTURES_DIR must be defined at compile time (see scripts/build-leak-check.sh)"
#endif

// Plant-a-leak toggle (default OFF). The build script compiles a SECOND binary with
// -DADAPTIVE_PLANT_LEAK=1 to verify the leak step actually catches a leak.
#ifndef ADAPTIVE_PLANT_LEAK
// NOLINTNEXTLINE(cppcoreguidelines-macro-usage) PERMANENT reason="compile-flag gate for the plant-a-leak self-test; must be a preprocessor macro because it drives #if ADAPTIVE_PLANT_LEAK"
#define ADAPTIVE_PLANT_LEAK 0
#endif

namespace
{
    constexpr int kIterations = 64;         // per-leg loop count (1 suffices for `leaks`)
    constexpr uint32_t kBlockFrames = 512U; // frames per synthetic block
    constexpr uint32_t kMaxChannels = 8U;   // FileDecodeSource rejects > 8 channels at open()

    const char* const kM4aPath = ADAPTIVE_FIXTURES_DIR "/fixture.m4a";
    const char* const kFlacPath = ADAPTIVE_FIXTURES_DIR "/fixture.flac";

    // Leg 1 — LoudnessMeter. Feed one block of synthetic non-interleaved stereo, read the
    // meter, then destroy the handle. On the final iteration under ADAPTIVE_PLANT_LEAK the
    // destroy is skipped ON PURPOSE (leak exactly one handle).
    void runLoudnessLeg(bool plantLeakThisIteration)
    {
        void* meter = loudnessMeterCreate(48000.0);
        if (meter == nullptr)
        {
            return;
        }

        float left[kBlockFrames];
        float right[kBlockFrames];
        for (uint32_t i = 0U; i < kBlockFrames; ++i)
        {
            // A quiet deterministic ramp — content is irrelevant to the leak scan; we only
            // need the meter's addStereo path to run its allocation-free math.
            const float phase = static_cast<float>(i) / static_cast<float>(kBlockFrames);
            left[i] = (0.25F * phase) - 0.125F;
            right[i] = 0.125F - (0.25F * phase);
        }
        loudnessMeterAddStereo(meter, left, right, kBlockFrames);
        const CLoudnessReadout readout = loudnessMeterRead(meter);
        (void)readout;

#if ADAPTIVE_PLANT_LEAK == 1
        if (plantLeakThisIteration)
        {
            // PLANT-A-LEAK: deliberately DO NOT destroy — leak this handle so `leaks`
            // (inverted in build-leak-check.sh) has something to catch; the leaked block's
            // allocation stack carries loudnessMeterCreate, which the script greps.
            (void)meter;
        }
        else
        {
            loudnessMeterDestroy(meter);
        }
#else
        (void)plantLeakThisIteration; // only meaningful in the planted build
        loudnessMeterDestroy(meter);
#endif
    }

    // Leg 2 — FileDecodeSource (Apple ExtAudioFile decode of the m4a fixture; no device, no
    // ffmpeg). Constructing on the stack + letting it fall out of scope runs the dtor, which
    // close()s the file, joins the background decode thread and frees the pimpl/ring.
    void runFileDecodeLeg()
    {
        AdaptiveSound::FileDecodeSource source;
        if (!source.open(kM4aPath))
        {
            return;
        }
        const uint32_t channels = source.channels();
        if (channels == 0U || channels > kMaxChannels)
        {
            return; // cannot happen post-open (open() rejects > 8ch); defensive.
        }
        float buffer[kBlockFrames * kMaxChannels];
        for (int block = 0; block < 4; ++block)
        {
            (void)source.pullFloat(buffer, kBlockFrames, channels);
        }
        // source dtor here: close() joins the decode thread + frees the ring/pimpl.
    }

    // Leg 3 — PureModeSession create/destroy + failed start. deviceID 0 has no capability (no
    // rates, no stream), so the Pure policy declines before any device access (no hang);
    // pureModeEngineStart returns 0 and frees the FileDecodeSource it opened, and
    // pureModeEngineDestroy frees the session.
    void runPureModeLeg()
    {
        void* engine = pureModeEngineCreate();
        if (engine == nullptr)
        {
            return;
        }
        uint8_t reason = 0U;
        (void)pureModeEngineStart(engine, /*deviceID=*/0U, kM4aPath, /*startSeconds=*/0.0, &reason);
        CPureModeEvaluation evaluation{};
        (void)pureModeEvaluateFile(/*deviceID=*/0U, kM4aPath, &evaluation);
        pureModeEngineDestroy(engine);
    }

#if __has_include(<libavformat/avformat.h>)
    // Leg 4 — FFmpeg metadata over the flac fixture (ffmpeg-gated). Exercises the opaque
    // metadata-handle lifecycle: open → scalars → per-tag borrowed strings → art → close. A
    // NULL handle (ffmpeg dylib unresolved at runtime) is fine — every accessor is NULL-safe.
    void runFfmpegMetadataLeg()
    {
        // FFmpeg is an opt-in, off by default (R1.1-A, FD-3): turn it on for this leg, as the
        // listener's setting would, and back off after.
        ffmpegSetEnabled(1);
        void* handle = ffmpegOpenMetadata(kFlacPath);
        ffmpegSetEnabled(0);
        if (handle == nullptr)
        {
            return;
        }
        CFileMetadataScalars scalars{};
        ffmpegMetadataScalars(handle, &scalars);
        for (uint32_t i = 0U; i < scalars.tagCount; ++i)
        {
            (void)ffmpegMetadataTagKey(handle, i);
            (void)ffmpegMetadataTagValue(handle, i);
        }
        (void)ffmpegMetadataArtBytes(handle);
        (void)ffmpegMetadataArtMime(handle);
        ffmpegCloseMetadata(handle);
    }
#endif

    // Leg 5 — the graphic-EQ designer (Sprint EQ, EQ1a): create → design + read back at two
    // rates (so the per-rate tables are rebuilt) → destroy. Pure DSP, no device.
    void runEqDesignerLeg()
    {
        AsEqDesigner* designer = asEqDesignerCreate();
        if (designer == nullptr)
        {
            return;
        }
        constexpr uint32_t kBands = 31U;
        float points[kBands] = {};
        points[17] = 6.0F; // +6 dB at 1 kHz
        float centreDb[kBands] = {};
        const double responseHz[2] = {100.0, 1000.0};
        float responseDb[2] = {};
        AsEqDesignOutput output{};
        output.centreDb = centreDb;
        output.responseHz = responseHz;
        output.responseDb = responseDb;
        output.responseCount = 2U;
        (void)asEqDesign(designer, points, kBands, 48000.0, &output);
        (void)asEqDesign(designer, points, kBands, 44100.0, &output);
        asEqDesignerDestroy(designer);
    }

    // Leg 6 — the track loudness profiler (Sprint EQ, EQ1c): create → feed 0.5 s of a 1 kHz
    // stereo tone in 100 ms chunks (one extra chunk rejected as non-finite) → a prefix → the whole
    // track → info + a prediction → destroy the profiler, then the profiles it left behind.
    void runTrackLoudnessLeg()
    {
        constexpr double kRate = 48000.0;
        constexpr uint32_t kChunkFrames = 4800U; // 100 ms
        constexpr int kChunks = 5;
        AsLoudnessProfiler* profiler =
            asLoudnessProfilerCreate(kRate, 2U, kAudioChannelLayoutTag_Stereo);
        AsEqDesigner* designer = asEqDesignerCreate();
        if (profiler == nullptr || designer == nullptr)
        {
            asLoudnessProfilerDestroy(profiler);
            asEqDesignerDestroy(designer);
            return;
        }
        float tone[kChunkFrames] = {};
        for (uint32_t frame = 0U; frame < kChunkFrames; ++frame)
        {
            tone[frame] = 0.25F * std::sin(2.0F * std::numbers::pi_v<float> * 1000.0F *
                                           static_cast<float>(frame) / static_cast<float>(kRate));
        }
        const float* channels[2] = {tone, tone};
        AsLoudnessProfile* prefix = nullptr;
        for (int chunk = 0; chunk < kChunks; ++chunk)
        {
            (void)asLoudnessProfilerFeed(profiler, channels, 2U, kChunkFrames);
            if (chunk == kChunks - 2)
            {
                prefix = asLoudnessProfilerFinishPrefix(profiler);
            }
        }
        float poisoned[kChunkFrames] = {};
        poisoned[0] = std::numeric_limits<float>::quiet_NaN();
        const float* bad[2] = {tone, poisoned};
        (void)asLoudnessProfilerFeed(profiler, bad, 2U, kChunkFrames); // rejected, consumes nothing
        AsLoudnessProfile* whole = asLoudnessProfilerFinishFull(profiler);
        asLoudnessProfilerDestroy(profiler);
        AsLoudnessProfileInfo info{};
        (void)asLoudnessProfileGetInfo(whole, &info);
        constexpr uint32_t kBands = 31U;
        float points[kBands] = {};
        points[7] = 12.0F; // +12 dB at 100 Hz
        double change = 0.0;
        (void)asLoudnessPredictChangeDb(whole, designer, points, kBands, kRate, &change);
        asLoudnessProfileDestroy(prefix);
        asLoudnessProfileDestroy(whole);
        asEqDesignerDestroy(designer);
    }
} // namespace

int main()
{
    @autoreleasepool
    {
        for (int i = 0; i < kIterations; ++i)
        {
            const bool lastIteration = (i == (kIterations - 1));
            runLoudnessLeg(lastIteration);
            runFileDecodeLeg();
            runPureModeLeg();
            runEqDesignerLeg();
            runTrackLoudnessLeg();
#if __has_include(<libavformat/avformat.h>)
            runFfmpegMetadataLeg();
#endif
        }
    }

#if !__has_include(<libavformat/avformat.h>)
    std::printf("SKIP: ffmpeg metadata leg (no libavformat headers)\n");
#endif

#if ADAPTIVE_PLANT_LEAK == 1
    std::printf("HandleLeakHarness: ran %d iterations (PLANT-A-LEAK: one loudness handle leaked "
                "on purpose).\n",
                kIterations);
#else
    std::printf("HandleLeakHarness: ran %d iterations; all handles balanced.\n", kIterations);
#endif
    return 0;
}
