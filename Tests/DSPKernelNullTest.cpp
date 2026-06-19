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
// Build: ./scripts/build-null-test.sh
// Run:   ./Tests/DSPKernelNullTest
//
// Structure: ONE translation unit assembled by textual #include.
//   TestSupport.h    — shared infrastructure: includes, constants, logging,
//                      runner, and helpers used by two or more area files
//   DspBypassTests.inc    — bypass / identity-chain tests (tests 1-7)
//   LimiterTests.inc      — limiter tests + shared limiter helper bodies (tests 8-12)
//   LoudnessTests.inc     — loudness/BS.1770 tests + shared loudness helpers (tests 13-17)
//   EqTests.inc           — EQ audibility tests (tests 18-19)
//   MultichannelTests.inc — multichannel epic safety net, BS.1770 multichannel,
//                           large-buffer fence (tests 20-34)
//   SpatialTests.inc      — SpatialRenderKernel passthrough tests (test 35)
//   PureModeTests.inc     — Pure-Mode policy, format conversion, ToneSource,
//                           + C-ABI bridge (pureModeEvaluate) tests (tests 36-51)
//   FileDecodeTests.inc   — file-decode bit-exact + expanded B2b coverage + seek (tests 52-72)
//   GaplessTests.inc      — gapless DECODE-LAYER decode->concatenate contract (tests 73-77)
//   RoundTripTests.inc    — B5/L1 Pure-Mode software-chain bit-exact round-trip (tests 78-79)
//   PureGaplessTests.inc  — Pure-path gapless STAGE 2 (GaplessSource) seam contract (tests 80-83)
//
// The kTests registry array and main() are defined here, AFTER all includes.

// clang-format off
// Include order is LOAD-BEARING: TestSupport.h must precede the .inc fragments (they depend on its
// includes, TestConstants, helpers, and runner types). The .inc order below follows the test
// registration grouping; the actual run order is fixed by the kTests array, not by include order.
// Do not let clang-format alphabetize this block (it would move TestSupport.h last and break the build).
#include "TestSupport.h"
#include "DspBypassTests.inc"
#include "LimiterTests.inc"
#include "LoudnessTests.inc"
#include "EqTests.inc"
#include "MultichannelTests.inc"
#include "SpatialTests.inc"
#include "PureModeTests.inc"
#include "FileDecodeTests.inc"
#include "GaplessTests.inc"
#include "RoundTripTests.inc"
#include "PureGaplessTests.inc"
#include "RealizerTests.inc"
// clang-format on

// ---------------------------------------------------------------------------
// Test registry: EXACT current call order. parallelSafe=false on all 16 FileDecode_*
// and testFileDecode* tests (they mutate ADAPTIVESOUND_DECODER and share /tmp paths).
// ---------------------------------------------------------------------------

namespace
{
    // NOLINTBEGIN(cppcoreguidelines-avoid-non-const-globals)
    constexpr std::array<TestEntry, 84U> kTests = {{
        // Phase 0 bypass tests
        {"IntensityZero_BitExactPassthrough", testIntensityZeroIsBitExact, true},
        {"IntensityZero_MultiChunkBitExact", testIntensityZeroMultiChunk, true},
        // Identity-chain tests
        {"WhiteNoiseBypasses", testWhiteNoiseBypasses, true},
        {"ChirpSignalBypasses", testChirpBypasses, true},
        {"EQModuleIdentityAtZeroBiquads", testEQModuleIdentityAtZeroBiquads, true},
        {"ZeroInputProducesZeroOutput", testZeroInputProducesZeroOutput, true},
        {"MultiChunkStatePreservation", testMultiChunkStatePreservation, true},
        // Limiter tests (Sprint 4)
        {"Limiter_BypassIsIdentity", testLimiterBypassIsIdentity, true},
        {"Limiter_CeilingEnforcement", testLimiterCeilingEnforcement, true},
        {"Limiter_GRResponseWithin2ms", testLimiterGRResponseTime, true},
        {"Limiter_NearNyquistCeiling", testLimiterNearNyquistCeiling, true},
        {"Limiter_HotNoiseSoak", testLimiterHotNoiseSoak, true},
        // Loudness / BS.1770-5 tests (Sprint 4 — Milestone 2)
        {"Loudness_KWeightingLowCut", testLoudnessKWeightingLowCut, true},
        {"Loudness_IntegratedAccuracy", testLoudnessIntegratedAccuracy, true},
        {"Loudness_AbsoluteGate", testLoudnessAbsoluteGate, true},
        {"Loudness_RelativeGate", testLoudnessRelativeGate, true},
        {"Loudness_MakeupRoundTrip", testLoudnessMakeupRoundTrip, true},
        // EQ audibility tests (Sprint 5 — Milestone 2)
        {"EQ_FrequencyResponseAccuracy", testEQFrequencyResponseAccuracy, true},
        {"EQ_CoefficientSwapNoClick", testEQCoefficientSwapNoClick, true},
        // Multichannel epic safety net (Sprint 5b — S0-M1)
        {"GoldenMaster_StereoN2_v1", testGoldenMasterStereoN2, true},
        {"MultichannelView_Decode", testMultichannelViewDecode, true},
        {"PerChannelIndependence_N4_6_8", testPerChannelIndependence, true},
        {"EQ_FrequencyResponseAccuracy_N4", testEQFrequencyResponseAccuracyN4, true},
        {"EQ_CoefficientSwapNoClick_N4", testEQCoefficientSwapNoClickN4, true},
        {"Limiter_LinkedGainLockstep", testLimiterLinkedGainLockstep, true},
        {"Limiter_HotNoiseSoak_N8", testLimiterHotNoiseSoakN8, true},
        {"Reconfiguration_Stereo_5p1_Stereo", testReconfigurationContinuity, true},
        // S1-C2a: N-channel BS.1770-5 LUFS meter (Gate C)
        {"Loudness_Multichannel_BS1770_Weights", testLoudnessMultichannelBS1770Weights, true},
        // M1-1: ChannelLayout decoder (Gate D)
        {"ChannelLayout_Decode_GateD", testChannelLayoutDecodeGateD, true},
        // M1-2: decode→meter path (Gate E)
        {"Loudness_DecodedLayout_Weights", testLoudnessDecodedLayoutWeights, true},
        // Large-buffer regression fence
        {"Kernel_LargeBuffer_LimiterTailCorrect", testLargeBufferLimiterTailCorrect, true},
        {"Kernel_LargeBuffer_EQGainNoCutoff", testLargeBufferEQGainNoCutoff, true},
        {"Kernel_LargeBuffer_ConsecutiveBuffers", testLargeBufferConsecutiveBuffers, true},
        // SpatialRenderKernel (Sprint 5b, M3-1)
        {"SpatialRender_PassthroughRoute", testSpatialRenderPassthroughRoute, true},
        // Pure-Mode policy (Phase B — B1)
        {"PureMode_HdmiBitPerfect", testPureModeHdmiBitPerfect, true},
        {"PureMode_HdmiRateUnsupported", testPureModeHdmiRateUnsupported, true},
        {"PureMode_BluetoothLossy", testPureModeBluetoothLossy, true},
        {"PureMode_BuiltInRateMatchedFloat", testPureModeBuiltInRateMatchedFloat, true},
        {"PureMode_BuiltInRateUnsupported", testPureModeBuiltInRateUnsupported, true},
        {"PureMode_VirtualDevice", testPureModeVirtualDevice, true},
        {"PureMode_RateEpsilonAndMax", testPureModeRateEpsilonAndMax, true},
        // Pure-Mode format conversion (Phase B — B2a)
        {"Convert_Int16Saturation", testConvertInt16Saturation, true},
        {"Convert_Int32Saturation", testConvertInt32Saturation, true},
        {"Convert_24In32Alignment", testConvert24In32Alignment, true},
        {"Convert_FloatPassthrough", testConvertFloatPassthrough, true},
        {"Convert_UnsupportedWritesSilence", testConvertUnsupportedWritesSilence, true},
        {"ToneSource_FillsBuffer", testToneSourceFillsBuffer, true},
        // Pure-Mode C-ABI bridge (pureModeEvaluate) — PARALLEL-SAFE: pure functions, no env/tmp
        {"PureModeBridge_TranslatesAllDecisionBranches",
         testPureModeBridgeTranslatesAllDecisionBranches,
         true},
        {"PureModeBridge_NullArgsAreNoOp", testPureModeBridgeNullArgsAreNoOp, true},
        {"PureModeBridge_RateArrayCopiedFaithfully",
         testPureModeBridgeRateArrayCopiedFaithfully,
         true},
        // Pure-Mode file decode (Phase B — B2b) — SERIAL: mutate env + /tmp paths
        {"FileDecode_BitExact_Auto", testFileDecodeBitExactAuto, false},
        {"FileDecode_BitExact_Apple", testFileDecodeBitExactApple, false},
        // Expanded B2b coverage (FileDecodeTests.inc) — SERIAL: mutate env + /tmp paths
        {"FileDecode_OpenFailurePaths", testFileDecodeOpenFailurePaths, false},
        {"FileDecode_CloseIdempotent", testFileDecodeCloseIdempotent, false},
        {"FileDecode_FormatGetters", testFileDecodeFormatGetters, false},
        {"FileDecode_BitExact_24bit", testFileDecodeBitExact24bit, false},
        {"FileDecode_BitExact_Float32", testFileDecodeBitExactFloat32, false},
        {"FileDecode_NativeRates", testFileDecodeNativeRates, false},
        {"FileDecode_Mono_BitExact", testFileDecodeMonoBitExact, false},
        {"FileDecode_Multichannel_4ch", testFileDecodeMultichannel4ch, false},
        {"FileDecode_PullChannelMismatchSilence", testFileDecodePullChannelMismatchSilence, false},
        {"FileDecode_EofAndFinishedFlag", testFileDecodeEofAndFinishedFlag, false},
        {"FileDecode_FinishedFlagRingTail", testFileDecodeFinishedFlagRingTail, false},
        {"FileDecode_PullBeforeDecodeZeroPads", testFileDecodePullBeforeDecodeZeroPads, false},
        {"FileDecode_BackendEquivalence", testFileDecodeBackendEquivalence, false},
        {"FileDecode_RingWraparound", testFileDecodeRingWraparound, false},
        // Seek coverage (FileDecodeSource::seek) — SERIAL: mutate env + /tmp paths
        {"FileDecode_Seek_SampleAccurateWav16", testFileDecodeSeekSampleAccurateWav16, false},
        {"FileDecode_Seek_ToZeroReproducesFromOpen",
         testFileDecodeSeekToZeroReproducesFromOpen,
         false},
        {"FileDecode_Seek_PastEofLandsAtEnd", testFileDecodeSeekPastEofLandsAtEnd, false},
        {"FileDecode_Seek_BackendEquivalenceAfterSeek",
         testFileDecodeSeekBackendEquivalenceAfterSeek,
         false},
        {"FileDecode_Seek_RepeatedRapidNoStaleNoLeak",
         testFileDecodeSeekRepeatedRapidNoStaleNoLeak,
         false},
        {"FileDecode_Seek_MidStreamDistinctChannels",
         testFileDecodeSeekMidStreamDistinctChannels,
         false},
        // Gapless DECODE-LAYER decode->concatenate contract — SERIAL: write fixtures to test-data/.
        {"Gapless_SeamFrameAccuracy", testGaplessSeamFrameAccuracy, false},
        {"Gapless_TotalFrameCount_48kOnly", testGaplessTotalFrameCount48kOnly, false},
        {"Gapless_SampleRateMismatch_ProducesFrameCountForEach",
         testGaplessSampleRateMismatchProducesFrameCountForEach,
         false},
        {"Gapless_ShortFile_DrainCorrectly", testGaplessShortFileDrainCorrectly, false},
        {"Gapless_OpenFailure_SecondSource", testGaplessOpenFailureSecondSource, false},
        // B5 / L1: Pure-Mode software-chain bit-exact round-trip — SERIAL: mutate env + /tmp paths.
        {"RoundTrip_BitExact_16bit", testRoundTripBitExact16bit, false},
        {"RoundTrip_BitExact_24bit", testRoundTripBitExact24bit, false},
        // Pure-path gapless STAGE 2 (GaplessSource) — SERIAL: write fixtures to test-data/.
        {"PureGapless_SeamSampleAccurate", testPureGaplessSeamSampleAccurate, false},
        {"PureGapless_ExhaustedPredicate", testPureGaplessExhaustedPredicate, false},
        {"PureGapless_SameRateCompatible", testPureGaplessSameRateCompatible, false},
        {"PureGapless_PlaylistEndNoNext", testPureGaplessPlaylistEndNoNext, false},
        // S6 Tier-3 (3a) Realizer multi-surface RMW contract (parallel-safe: no env/tmp).
        {"Realizer_MultiSurfaceRMW_NoClobber_SeqMonotonic", testRealizerMultiSurfaceRMW, true},
    }};
    // NOLINTEND(cppcoreguidelines-avoid-non-const-globals)
} // namespace

// ---------------------------------------------------------------------------

auto main(int argc, const char* const* argv) -> int
{
    // ---------------------------------------------------------------------------
    // Argument parsing: --parallel[=N], --list, --filter=<name>
    // ---------------------------------------------------------------------------
    int parallelN = 1; // default: serial
    bool listOnly = false;
    const char* filterName = nullptr;

    for (int ai = 1; ai < argc; ++ai)
    {
        const std::string arg(argv[ai]);
        if (arg == "--parallel")
        {
            const int hwc = static_cast<int>(std::thread::hardware_concurrency());
            parallelN = std::max(2, hwc);
        }
        else if (arg.rfind("--parallel=", 0) == 0)
        {
            const int val = std::stoi(arg.substr(11U));
            parallelN = std::max(1, val);
        }
        else if (arg == "--list")
        {
            listOnly = true;
        }
        else if (arg.rfind("--filter=", 0) == 0)
        {
            filterName = argv[ai] + 9;
        }
        else
        {
            // Check environment variable ADAPTIVESOUND_PARALLEL=N.
        }
    }

    // Environment variable fallback for parallel degree.
    if (parallelN == 1)
    {
        const char* envPar = std::getenv("ADAPTIVESOUND_PARALLEL");
        if (envPar != nullptr)
        {
            const int val = std::atoi(envPar);
            if (val > 1)
            {
                parallelN = val;
            }
        }
    }

    // --list: print test names with classification and exit.
    if (listOnly)
    {
        for (const auto& entry : kTests)
        {
            std::string line = std::string(entry.name) + "  " +
                               (entry.parallelSafe ? "[parallel-safe]" : "[serial-only]") + "\n";
            std::fputs(line.c_str(), stdout);
        }
        return 0;
    }

    // --filter=<name>: run one named test for debugging.
    if (filterName != nullptr)
    {
        for (const auto& entry : kTests)
        {
            if (std::string(entry.name) == filterName)
            {
                std::fputs("=== DSPKernel Null Test Suite (--filter) ===\n\n", stdout);
                entry.fn();
                return printSummary();
            }
        }
        std::string errLine = std::string("error: no test named '") + filterName + "'\n";
        std::fputs(errLine.c_str(), stderr);
        return 1;
    }

    std::fputs("=== DSPKernel Null Test Suite ===\n\n", stdout);
    runAllTests(parallelN, kTests);
    return printSummary();
}
