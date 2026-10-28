// DSPKernelNullTest.cpp
//
// Null test: verifies DSPKernel::process() produces bit-identical output to input
// under two conditions:
//   (a) intensityLinear == 0  -> early-return bypass (Phase 0 requirement)
//   (b) identity EQ (the default EQParams) -> full chain at unity
//
// This is the Phase 0 canary for the signal chain.  Every future module must pass
// this test (or a variant) before merging.
//
// Build + run: ./scripts/build-null-test.sh (its header lists the variants, tiers and flags)
// Run:         ./Tests/DSPKernelNullTest [--tier=…] [--gtest_filter=…] [--gtest_repeat=N] …
//
// Structure: ONE translation unit assembled by textual #include.
//   TestSupport.h    — shared infrastructure: includes, constants, the verdicts (logPass /
//                      logFail / logPending, GoogleTest results), the rig primitives (rig::
//                      waitUntil, rig::Rendezvous, the thread-CPU meter), and helpers used by two
//                      or more area files
//   NullTestRunner.h — the runner: GoogleTest registration of kTests, tiers, the per-test watchdog
//   DspBypassTests.inc    — bypass / identity-chain tests (tests 1-7)
//   LimiterTests.inc      — limiter tests + shared limiter helper bodies (tests 8-12)
//   LoudnessTests.inc     — loudness/BS.1770 tests + shared loudness helpers (tests 13-17)
//   EqTests.inc           — EQ audibility tests (tests 18-19)
//   MultichannelTests.inc — multichannel epic safety net, BS.1770 multichannel,
//                           large-buffer fence (tests 20-34)
//   SpatialTests.inc      — SpatialRenderKernel passthrough tests (test 35)
//   PureModeTests.inc     — Pure-Mode policy, format conversion,
//                           + C-ABI bridge (pureModeEvaluate) tests (tests 36-51)
//   FileDecodeTests.inc   — file-decode bit-exact + expanded B2b coverage + seek (tests 52-72)
//   FFmpegLoaderTests.inc — FFmpeg opt-in (off loads nothing), the hardened load's vetting rule,
//                           the fixed paths, and the probe's "needs FFmpeg" (R1.1-A, FD-3)
//   GaplessTests.inc      — gapless DECODE-LAYER decode->concatenate contract (tests 73-77)
//   RoundTripTests.inc    — B5/L1 Pure-Mode software-chain bit-exact round-trip (tests 78-79)
//   PureGaplessTests.inc  — Pure-path gapless STAGE 2 (GaplessSource) seam contract (tests 80-83)
//   GaplessContractTests.inc — S6 Tier-3 (3d) Pure gapless behavioral-contract conformance suite
//   GaplessArmContractTests.inc — council D41: the Pure arm contract (the old pick comes off,
//                           arming never replaces, the end is final, arming frees the retired slot,
//                           arming waits for a seam in flight)
//   LoudnessOracleTests.inc  — S7/US-QA-01 TEST-ONLY libebur128 conformance oracle (LUFS + TP)
//   LimiterTruePeakTests.inc — S7/US-QA-02 TEST-ONLY limiter −1 dBTP ceiling guarantee +
//                              ISP-detector accuracy vs the libebur128 true-peak oracle
//   EqFrequencyResponseSweepTests.inc — S7/US-QA-03 31-band FR sweep (±6/±12 dB, 48 &
//                              44.1 kHz) + near-Nyquist gain guard + flat bit-transparency
//   EqDesignerTests.inc   — Sprint EQ / EQ1a: the accurate 31-band graphic-EQ designer
//                           (GraphicEQDesigner + the asEqDesign C-ABI) vs the Python oracle
//   TrackLoudnessTests.inc — Sprint EQ / EQ1c: the track loudness profiler + the gated
//                           loudness-change predictor + their C-ABI vs the libebur128 oracle
//   EqTransitionTests.inc — Sprint EQ / EQ1b: time-domain curve transitions + the EQ's CPU
//   EqEngineTests.inc     — Sprint EQ / EQ1b: the RT EQ in the kernel — paths, guards, re-allocation
//   LoudnessNeutralTests.inc — Sprint EQ / EQ1c part 2: the loudness-neutral gain, live — the
//                           per-track rules, gapless seams, the causal fallback, On vs Off
//   EqEngineBreakItTests.inc — Sprint EQ engine break-it: red tests pinning defects the gate above
//                           misses (its measurement half: EqEngineBreakItMeasure.cpp, not gated)
//   EqEngineFixTests.inc  — Sprint EQ engine fix round (amendments 14–19): each fix's own gate
//   DeviceListPolicyTests.inc — Sprint G: the output-device menu rule (no hidden / private /
//                           process-default aggregate devices) + the aggregate-composition decode
//   RenderGateTests.inc   — Sprint G: the render gate a Pure seek holds instead of stopping the
//                           output unit (exclusion, close-waits, concurrent no-overlap under TSan)
//
// The kTests registry array and main() are defined here, AFTER all includes (NullTestRunner.h last).

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
#include "FFmpegLoaderTests.inc" // after FileDecodeTests.inc (BackendGuard, writeWav16)
#include "GaplessTests.inc"
#include "RoundTripTests.inc"
#include "PureGaplessTests.inc"
#include "GaplessContractTests.inc"
#include "GaplessArmContractTests.inc" // after PureGaplessTests.inc (openPureGaplessSource)
#include "RealizerTests.inc"
#include "IntensityTests.inc"
#include "CrossfeedTests.inc"
#include "LoudnessOracleTests.inc"
#include "LimiterTruePeakTests.inc"
#include "EqFrequencyResponseSweepTests.inc"
#include "EqDesignerTests.inc"
#include "TrackLoudnessTests.inc"
#include "SoakRtAllocTests.inc"
#include "PureDitherTests.inc" // after SoakRtAllocTests.inc (RtGuardScope) + PureModeTests.inc (makeFile)
#include "BreakItPureDepthTests.inc" // after PureModeTests.inc (the policy) — D-1, lossless source depth
#include "SnapshotConcurrencyTests.inc"
#include "EqTransitionTests.inc" // after EqDesignerTests.inc (its curves)
#include "EqEngineTests.inc"     // after SoakRtAllocTests.inc (its RT-alloc guard)
#include "LoudnessNeutralTests.inc" // after TrackLoudnessTests.inc + EqEngineTests.inc (helpers)
#include "EqEngineBreakItTests.inc" // after EqEngineTests.inc + EqTransitionTests.inc (helpers)
#include "EqEngineFixTests.inc"     // after EqEngineBreakItTests.inc (helpers)
#include "DeviceListPolicyTests.inc"
#include "RenderGateTests.inc"
#include "AnalyzerTests.inc"   // R1.1-B W4, lane 1
#include "LevelPlanTests.inc"  // R1.1-B W4, lane 1
#include "FoldTests.inc"       // R1.1-B W4, lane 2
#include "LfeRuleTests.inc"    // R1.1-B W4, lane 2
#include "NullTestRunner.h" // after every *.inc: the runner registers their bodies
// clang-format on

// ---------------------------------------------------------------------------
// Test registry, in run order (GoogleTest runs a tier's tests in this order; --gtest_shuffle
// shuffles them). Each entry: name (unchanged since the home runner), body, tier, flags — see
// NullTestRunner.h. kSerial marks the tests that write fixtures under test-data/ shared by name, or
// mutate ADAPTIVESOUND_DECODER: they run in the one serial process, never in a parallel shard.
// ---------------------------------------------------------------------------

namespace
{
    constexpr auto kTests = std::to_array<TestEntry>({
        // Phase 0 bypass tests
        {"IntensityZero_BitExactPassthrough", testIntensityZeroIsBitExact, Tier::Correctness},
        {"IntensityZero_MultiChunkBitExact", testIntensityZeroMultiChunk, Tier::Correctness},
        // Identity-chain tests
        {"WhiteNoiseBypasses", testWhiteNoiseBypasses, Tier::Correctness},
        {"ChirpSignalBypasses", testChirpBypasses, Tier::Correctness},
        {"EQModuleIdentityByDefault", testEQModuleIdentityByDefault, Tier::Correctness},
        {"ZeroInputProducesZeroOutput", testZeroInputProducesZeroOutput, Tier::Correctness},
        {"MultiChunkStatePreservation", testMultiChunkStatePreservation, Tier::Correctness},
        // Limiter tests (Sprint 4)
        {"Limiter_BypassIsIdentity", testLimiterBypassIsIdentity, Tier::Correctness},
        {"Limiter_CeilingEnforcement", testLimiterCeilingEnforcement, Tier::Correctness},
        {"Limiter_GRResponseWithin2ms", testLimiterGRResponseTime, Tier::Correctness},
        {"Limiter_NearNyquistCeiling", testLimiterNearNyquistCeiling, Tier::Correctness},
        {"Limiter_HotNoiseSoak", testLimiterHotNoiseSoak, Tier::Correctness},
        // R1.1-A (council C-39): the release is program-dependent — a transient is fast.
        {"Limiter_Release_TransientIsFast", testLimiterReleaseTransientIsFast, Tier::Correctness},
        {"Limiter_Release_SustainedIsSlow", testLimiterReleaseSustainedIsSlow, Tier::Correctness},
        // Loudness / BS.1770-5 tests (Sprint 4 — Milestone 2)
        {"Loudness_KWeightingLowCut", testLoudnessKWeightingLowCut, Tier::Correctness},
        {"Loudness_IntegratedAccuracy", testLoudnessIntegratedAccuracy, Tier::Correctness},
        {"Loudness_AbsoluteGate", testLoudnessAbsoluteGate, Tier::Correctness},
        {"Loudness_RelativeGate", testLoudnessRelativeGate, Tier::Correctness},
        {"Loudness_MakeupRoundTrip", testLoudnessMakeupRoundTrip, Tier::Correctness},
        {
            "Loudness_TruePeakKernel_InterSample",
            testLoudnessTruePeakKernelInterSample,
            Tier::Correctness,
        },
        {"Loudness_MeterBridge_TruePeak", testLoudnessMeterBridgeTruePeak, Tier::Correctness},
        // R1.1-A (council C-46, KI-UI-03): the analysis workers sleep while no audio reaches them.
        // It reads the workers' own parked state and wake counts (0fb9ddb), so any process.
        {"Loudness_WorkersSleepWhileIdle", testLoudnessWorkersSleepWhileIdle, Tier::Concurrent},
        // EQ audibility tests (Sprint 5 — Milestone 2)
        {"EQ_FrequencyResponseAccuracy", testEQFrequencyResponseAccuracy, Tier::Correctness},
        {"EQ_CoefficientSwapNoClick", testEQCoefficientSwapNoClick, Tier::Correctness},
        // Multichannel epic safety net (Sprint 5b — S0-M1)
        {"GoldenMaster_StereoN2_v1", testGoldenMasterStereoN2, Tier::Correctness},
        {"MultichannelView_Decode", testMultichannelViewDecode, Tier::Correctness},
        {"PerChannelIndependence_N4_6_8", testPerChannelIndependence, Tier::Correctness},
        {"EQ_FrequencyResponseAccuracy_N4", testEQFrequencyResponseAccuracyN4, Tier::Correctness},
        {"EQ_CoefficientSwapNoClick_N4", testEQCoefficientSwapNoClickN4, Tier::Correctness},
        {"Limiter_LinkedGainLockstep", testLimiterLinkedGainLockstep, Tier::Correctness},
        {"Limiter_HotNoiseSoak_N8", testLimiterHotNoiseSoakN8, Tier::Correctness},
        {"Reconfiguration_Stereo_5p1_Stereo", testReconfigurationContinuity, Tier::Correctness},
        // S1-C2a: N-channel BS.1770-5 LUFS meter (Gate C)
        {
            "Loudness_Multichannel_BS1770_Weights",
            testLoudnessMultichannelBS1770Weights,
            Tier::Correctness,
        },
        // M1-1: ChannelLayout decoder (Gate D)
        {"ChannelLayout_Decode_GateD", testChannelLayoutDecodeGateD, Tier::Correctness},
        // M1-2: decode→meter path (Gate E)
        {"Loudness_DecodedLayout_Weights", testLoudnessDecodedLayoutWeights, Tier::Correctness},
        // Large-buffer regression fence
        {
            "Kernel_LargeBuffer_LimiterTailCorrect",
            testLargeBufferLimiterTailCorrect,
            Tier::Correctness,
        },
        {"Kernel_LargeBuffer_EQGainNoCutoff", testLargeBufferEQGainNoCutoff, Tier::Correctness},
        {
            "Kernel_LargeBuffer_ConsecutiveBuffers",
            testLargeBufferConsecutiveBuffers,
            Tier::Correctness,
        },
        // SpatialRenderKernel (Sprint 5b, M3-1)
        {"SpatialRender_PassthroughRoute", testSpatialRenderPassthroughRoute, Tier::Correctness},
        // R1.1-A (council C-50): flush-to-zero is scoped to our render calls, then restored.
        {"Render_FlushToZero_Scoped", testRenderFlushToZeroScoped, Tier::Correctness},
        // Pure-Mode policy (Phase B — B1)
        {"PureMode_HdmiBitPerfect", testPureModeHdmiBitPerfect, Tier::Correctness},
        {"PureMode_HdmiRateUnsupported", testPureModeHdmiRateUnsupported, Tier::Correctness},
        {"PureMode_BluetoothLossy", testPureModeBluetoothLossy, Tier::Correctness},
        {
            "PureMode_BuiltInRateMatchedFloat",
            testPureModeBuiltInRateMatchedFloat,
            Tier::Correctness,
        },
        {"PureMode_BuiltInRateUnsupported", testPureModeBuiltInRateUnsupported, Tier::Correctness},
        {"PureMode_VirtualDevice", testPureModeVirtualDevice, Tier::Correctness},
        {"PureMode_RateEpsilonAndMax", testPureModeRateEpsilonAndMax, Tier::Correctness},
        {"PureMode_ChannelCountMismatch", testPureModeChannelCountMismatch, Tier::Correctness},
        {"PureMode_BitExactness_DepthRule", testPureModeBitExactnessDepthRule, Tier::Correctness},
        {
            "PureMode_ReasonCodes_BridgeOrder",
            testPureModeReasonCodesAreTheBridgeOrder,
            Tier::Correctness,
        },
        // TPDF dither where Pure reduces bits (R1.1-A, founder 2026-10-16). RtSafe arms the
        // thread-local allocation guard.
        {"PureDither_TpdfShape", testPureDitherTpdfShape, Tier::Correctness},
        {
            "PureDither_NoDcNoNoiseModulation",
            testPureDitherNoDcNoNoiseModulation,
            Tier::Correctness,
        },
        {
            "PureDither_QuietSineIsToneInNoise",
            testPureDitherQuietSineIsToneInNoise,
            Tier::Correctness,
        },
        {"PureDither_OnlyWhenReducing", testPureDitherOnlyWhenReducing, Tier::Correctness},
        {"PureDither_RtSafe", testPureDitherRtSafe, Tier::Correctness},
        {
            "BreakIt_PureDepth_LosslessSourceBits",
            testBreakItPureDepthLosslessSourceBits,
            Tier::Concurrent,
            kSerial,
        },
        // Pure-Mode format conversion (Phase B — B2a)
        {"Convert_Int16Saturation", testConvertInt16Saturation, Tier::Correctness},
        {"Convert_Int32Saturation", testConvertInt32Saturation, Tier::Correctness},
        {"Convert_24In32Alignment", testConvert24In32Alignment, Tier::Correctness},
        {"Convert_FloatPassthrough", testConvertFloatPassthrough, Tier::Correctness},
        {
            "PureFormat_FromAsbdOnlyExactLayouts",
            testPureFormatFromAsbdOnlyExactLayouts,
            Tier::Correctness,
        },
        {
            "PureFormat_PickerOnlyWritableFormats",
            testPureFormatPickerOnlyWritableFormats,
            Tier::Correctness,
        },
        {
            "Convert_Packed24_ExactBytesRoundTrip",
            testConvertPacked24ExactBytesRoundTrip,
            Tier::Correctness,
        },
        {
            "Convert_WriteBoundedByBufferBytes",
            testConvertWriteBoundedByBufferBytes,
            Tier::Correctness,
        },
        {
            "Convert_NonFiniteIsSilence_FiniteUntouched",
            testConvertNonFiniteIsSilenceFiniteUntouched,
            Tier::Correctness,
        },
        {
            "Convert_BitExact_Exhaustive16And24",
            testConvertBitExactExhaustive16And24,
            Tier::AccuracySweep,
        },
        // Pure-Mode C-ABI bridge (pureModeEvaluate) — PARALLEL-SAFE: pure functions, no env/tmp
        {
            "PureModeBridge_TranslatesAllDecisionBranches",
            testPureModeBridgeTranslatesAllDecisionBranches,
            Tier::Correctness,
        },
        {"PureModeBridge_NullArgsAreNoOp", testPureModeBridgeNullArgsAreNoOp, Tier::Correctness},
        {
            "PureModeBridge_RateArrayCopiedFaithfully",
            testPureModeBridgeRateArrayCopiedFaithfully,
            Tier::Correctness,
        },
        // Pure-Mode file decode (Phase B — B2b) — SERIAL: fixtures in test-data/ + the env
        {"FileDecode_BitExact_Auto", testFileDecodeBitExactAuto, Tier::Concurrent, kSerial},
        {"FileDecode_BitExact_Apple", testFileDecodeBitExactApple, Tier::Concurrent, kSerial},
        // Expanded B2b coverage (FileDecodeTests.inc) — SERIAL: fixtures in test-data/ + the env
        {"FileDecode_OpenFailurePaths", testFileDecodeOpenFailurePaths, Tier::Concurrent, kSerial},
        {"FileDecode_CloseIdempotent", testFileDecodeCloseIdempotent, Tier::Concurrent, kSerial},
        {"FileDecode_FormatGetters", testFileDecodeFormatGetters, Tier::Concurrent, kSerial},
        {
            "FileDecode_BitExact_24bit",
            testFileDecodeBitExact24bit,
            Tier::Concurrent,
            kSerial | kNeedsFfmpeg,
        },
        {
            "FileDecode_BitExact_Float32",
            testFileDecodeBitExactFloat32,
            Tier::Concurrent,
            kSerial | kNeedsFfmpeg,
        },
        {
            "FileDecode_NativeRates",
            testFileDecodeNativeRates,
            Tier::Concurrent,
            kSerial | kNeedsFfmpeg,
        },
        {
            "FileDecode_Mono_BitExact",
            testFileDecodeMonoBitExact,
            Tier::Concurrent,
            kSerial | kNeedsFfmpeg,
        },
        {
            "FileDecode_Multichannel_4ch",
            testFileDecodeMultichannel4ch,
            Tier::Concurrent,
            kSerial | kNeedsFfmpeg,
        },
        {
            "FileDecode_PullChannelMismatchSilence",
            testFileDecodePullChannelMismatchSilence,
            Tier::Concurrent,
            kSerial,
        },
        {
            "FileDecode_EofAndFinishedFlag",
            testFileDecodeEofAndFinishedFlag,
            Tier::Concurrent,
            kSerial,
        },
        {
            "FileDecode_FinishedFlagRingTail",
            testFileDecodeFinishedFlagRingTail,
            Tier::Concurrent,
            kSerial,
        },
        {
            "FileDecode_PullBeforeDecodeZeroPads",
            testFileDecodePullBeforeDecodeZeroPads,
            Tier::Concurrent,
            kSerial,
        },
        {
            "FileDecode_BackendEquivalence",
            testFileDecodeBackendEquivalence,
            Tier::Concurrent,
            kSerial | kNeedsFfmpeg,
        },
        {"FileDecode_RingWraparound", testFileDecodeRingWraparound, Tier::Concurrent, kSerial},
        // Seek coverage (FileDecodeSource::seek) — SERIAL: fixtures in test-data/ + the env
        {
            "FileDecode_Seek_SampleAccurateWav16",
            testFileDecodeSeekSampleAccurateWav16,
            Tier::Concurrent,
            kSerial | kNeedsFfmpeg,
        },
        {
            "FileDecode_Seek_ToZeroReproducesFromOpen",
            testFileDecodeSeekToZeroReproducesFromOpen,
            Tier::Concurrent,
            kSerial | kNeedsFfmpeg,
        },
        {
            "FileDecode_Seek_PastEofLandsAtEnd",
            testFileDecodeSeekPastEofLandsAtEnd,
            Tier::Concurrent,
            kSerial | kNeedsFfmpeg,
        },
        {
            "FileDecode_Seek_BackendEquivalenceAfterSeek",
            testFileDecodeSeekBackendEquivalenceAfterSeek,
            Tier::Concurrent,
            kSerial | kNeedsFfmpeg,
        },
        {
            "FileDecode_Seek_RepeatedRapidNoStaleNoLeak",
            testFileDecodeSeekRepeatedRapidNoStaleNoLeak,
            Tier::Concurrent,
            kSerial | kNeedsFfmpeg,
        },
        {
            "FileDecode_Seek_MidStreamDistinctChannels",
            testFileDecodeSeekMidStreamDistinctChannels,
            Tier::Concurrent,
            kSerial | kNeedsFfmpeg,
        },
        // C-35: the FFmpeg seek honours the stream start; a refused seek keeps the buffered audio.
        {
            "FileDecode_Seek_FFmpegHonoursStreamStart",
            testFileDecodeSeekFFmpegHonoursStreamStart,
            Tier::Concurrent,
            kSerial | kNeedsFfmpeg,
        },
        {
            "FileDecode_Seek_RefusedKeepsBufferedAudio",
            testFileDecodeSeekRefusedKeepsBufferedAudio,
            Tier::Concurrent,
            kSerial | kNeedsFfmpeg,
        },
        // FFmpeg as an opt-in, off by default, hardened load (R1.1-A, FD-3, C-99) — SERIAL: the
        // switch is process-wide.
        {
            "FFmpeg_OffByDefault_LoadsNothing",
            testFFmpegOffByDefaultLoadsNothing,
            Tier::Concurrent,
            kSerial | kNeedsFfmpeg,
        },
        {
            "FFmpeg_VetLibrary_Rules",
            testFFmpegVetLibraryRules,
            Tier::Correctness,
            kSerial | kNeedsFfmpeg,
        },
        {
            "FFmpeg_LibraryPaths_FixedAndAbsolute",
            testFFmpegLibraryPathsFixedAndAbsolute,
            Tier::Correctness,
            kSerial | kNeedsFfmpeg,
        },
        {
            "FFmpeg_ReadFacts_RealFiles",
            testFFmpegReadFactsRealFiles,
            Tier::Correctness,
            kSerial | kNeedsFfmpeg,
        },
        {
            "FFmpeg_OpenLibrary_RefusesWhatOthersCanChange",
            testFFmpegOpenLibraryRefusesWhatOthersCanChange,
            Tier::Correctness,
            kSerial | kNeedsFfmpeg,
        },
        {
            "FFmpeg_ProbeNamesWhyAFileWontOpen",
            testFFmpegProbeNamesWhyAFileWontOpen,
            Tier::Concurrent,
            kSerial | kNeedsFfmpeg,
        },
        // Gapless DECODE-LAYER decode->concatenate contract — SERIAL: write fixtures to test-data/.
        {"Gapless_SeamFrameAccuracy", testGaplessSeamFrameAccuracy, Tier::Concurrent, kSerial},
        {
            "Gapless_TotalFrameCount_48kOnly",
            testGaplessTotalFrameCount48kOnly,
            Tier::Concurrent,
            kSerial,
        },
        {
            "Gapless_SampleRateMismatch_ProducesFrameCountForEach",
            testGaplessSampleRateMismatchProducesFrameCountForEach,
            Tier::Concurrent,
            kSerial,
        },
        {
            "Gapless_ShortFile_DrainCorrectly",
            testGaplessShortFileDrainCorrectly,
            Tier::Concurrent,
            kSerial,
        },
        {
            "Gapless_OpenFailure_SecondSource",
            testGaplessOpenFailureSecondSource,
            Tier::Concurrent,
            kSerial,
        },
        // B5 / L1: Pure-Mode software-chain bit-exact round-trip — SERIAL: fixtures + the env.
        {"RoundTrip_BitExact_16bit", testRoundTripBitExact16bit, Tier::Concurrent, kSerial},
        {"RoundTrip_BitExact_24bit", testRoundTripBitExact24bit, Tier::Concurrent, kSerial},
        // Pure-path gapless STAGE 2 (GaplessSource) — SERIAL: write fixtures to test-data/.
        {
            "PureGapless_SeamSampleAccurate",
            testPureGaplessSeamSampleAccurate,
            Tier::Concurrent,
            kSerial,
        },
        {
            "PureGapless_ExhaustedPredicate",
            testPureGaplessExhaustedPredicate,
            Tier::Concurrent,
            kSerial,
        },
        {
            "PureGapless_SameRateCompatible",
            testPureGaplessSameRateCompatible,
            Tier::Concurrent,
            kSerial,
        },
        {
            "PureGapless_PlaylistEndNoNext",
            testPureGaplessPlaylistEndNoNext,
            Tier::Concurrent,
            kSerial,
        },
        {
            "PureGapless_ArmRefusesOtherWidth",
            testPureGaplessArmRefusesOtherWidth,
            Tier::Concurrent,
            kSerial,
        },
        // S6 Tier-3 (3d) Pure gapless behavioral-contract conformance — SERIAL: write fixtures.
        {
            "GaplessContract_TransitionCountPerSeam",
            testGaplessContractTransitionCountPerSeam,
            Tier::Concurrent,
            kSerial,
        },
        {
            "GaplessContract_ClearCancelsOnDeck",
            testGaplessContractClearCancelsOnDeck,
            Tier::Concurrent,
            kSerial,
        },
        {
            "GaplessContract_EndOfQueueSignals",
            testGaplessContractEndOfQueueSignals,
            Tier::Concurrent,
            kSerial,
        },
        {
            "GaplessContract_PositionRezeroesAtSeam",
            testGaplessContractPositionRezeroesAtSeam,
            Tier::Concurrent,
            kSerial,
        },
        {
            "GaplessContract_PollReapsRetiredSource",
            testGaplessContractPollReapsRetiredSource,
            Tier::Concurrent,
            kSerial,
        },
        // Council D41: the Pure arm contract — SERIAL: write fixtures to test-data/.
        {
            "ArmContract_RetractArmBeforeEnd",
            testArmContractRetractArmBeforeEnd,
            Tier::Concurrent,
            kSerial,
        },
        {"ArmContract_OccupiedRefuses", testArmContractOccupiedRefuses, Tier::Concurrent, kSerial},
        {"ArmContract_RetractEndArm", testArmContractRetractEndArm, Tier::Concurrent, kSerial},
        {"ArmContract_ArmBeforeReap", testArmContractArmBeforeReap, Tier::Concurrent, kSerial},
        {"ArmContract_ClearRacesSeam", testArmContractClearRacesSeam, Tier::Concurrent, kSerial},
        {"ArmContract_ArmRacesEnd", testArmContractArmRacesEnd, Tier::Concurrent, kSerial},
        {
            "ArmContract_ArmWhileSeamClaimed",
            testArmContractArmWhileSeamClaimed,
            Tier::Concurrent,
            kSerial,
        },
        {
            "ArmContract_ArmWhileSeamRetired",
            testArmContractArmWhileSeamRetired,
            Tier::Concurrent,
            kSerial,
        },
        {
            "ArmContract_SeamPublishBounded",
            testArmContractSeamPublishBounded,
            Tier::Concurrent,
            kSerial,
        },
        // S6 Tier-3 (3a) Realizer multi-surface RMW contract (parallel-safe: no env/tmp).
        {
            "Realizer_MultiSurfaceRMW_NoClobber_SeqMonotonic",
            testRealizerMultiSurfaceRMW,
            Tier::Concurrent,
        },
        // QW1 CF-11: the 4th Realizer surface — crossfeed RMW + clamp (parallel-safe).
        {"Realizer_Crossfeed_4SurfaceRMW_Clamp", testRealizerCrossfeedSurfaceRMW, Tier::Concurrent},
        // S6 Tier-3 (3b) steerable wet/dry intensity (parallel-safe: no env/tmp).
        {"Intensity_EndpointsBitExact_Settled", testIntensityEndpointsBitExact, Tier::Correctness},
        {
            "Intensity_SettledRampConvergesToHardBranch",
            testIntensitySettledRampConvergesToHardBranch,
            Tier::Correctness,
        },
        {"Intensity_EqualPowerAtHalf", testIntensityEqualPowerAtHalf, Tier::Correctness},
        {
            "Intensity_LevelPeakSafetyIntermediate",
            testIntensityLevelPeakSafetyIntermediate,
            Tier::AccuracySweep,
        },
        {"Intensity_NoNaNAndFastStepSettles", testIntensityNoNaNFastStepSettles, Tier::Correctness},
        // Crossfeed: bs2b conformance CF-1..CF-9 and its own kernel stage CF-13 / CF-14
        // (parallel-safe: pure DSP, no env/tmp).
        {
            "Crossfeed_Bypass_BitExact_GoldenMaster",
            testCrossfeedBypassBitExactGoldenMaster,
            Tier::Correctness,
        },
        {"Crossfeed_NonStereo_PassThrough", testCrossfeedNonStereoPassThrough, Tier::Correctness},
        {"Crossfeed_CentreFlat_vs_bs2b", testCrossfeedCentreFlatVsBs2b, Tier::Correctness},
        {"Crossfeed_ChannelSeparation", testCrossfeedChannelSeparation, Tier::Correctness},
        {"Crossfeed_LpfCharacteristic", testCrossfeedLpfCharacteristic, Tier::Correctness},
        {"Crossfeed_NoNaNInf", testCrossfeedNoNaNInf, Tier::Correctness},
        {
            "Crossfeed_ClickFreeEnableDisable",
            testCrossfeedClickFreeEnableDisable,
            Tier::Correctness,
        },
        {
            "Crossfeed_CoeffRecomputeAcrossRates",
            testCrossfeedCoeffRecomputeAcrossRates,
            Tier::Correctness,
        },
        {"Crossfeed_MatchesBs2bReference", testCrossfeedMatchesBs2bReference, Tier::Correctness},
        {"Crossfeed_PlaysAtAnyIntensity", testCrossfeedPlaysAtAnyIntensity, Tier::Correctness},
        {"Crossfeed_Off_BitExact", testCrossfeedOffBitExact, Tier::Correctness},
        // S7 / US-QA-01: TEST-ONLY libebur128 conformance oracle (parallel-safe: no env/tmp).
        {"Loudness_Oracle_Integrated_vs_ebur128", testLoudnessOracleIntegrated, Tier::Correctness},
        {"Loudness_Oracle_TruePeak_vs_ebur128", testLoudnessOracleTruePeak, Tier::Correctness},
        // QW1 CF-10: crossfeed ebur128 loudness-neutrality (real decorrelated stereo).
        {"Crossfeed_ebur128_LevelNeutral", testCrossfeedLoudnessNeutral, Tier::Concurrent},
        // R1.1-A (council C-46): the UI's Integrated is the track's, not the session's.
        {
            "Loudness_MeterBridge_IntegratedPerTrack",
            testLoudnessMeterBridgeIntegratedPerTrack,
            Tier::Correctness,
        },
        {
            "Loudness_MeterBridge_BeginTrack_Concurrent",
            testLoudnessMeterBridgeBeginTrackConcurrent,
            Tier::Concurrent,
        },
        // S7 / US-QA-02: TEST-ONLY limiter true-peak ceiling guarantee + ISP-detector accuracy
        // (parallel-safe: pure DSP, no env/tmp).
        {
            "Limiter_TruePeak_CeilingGuarantee_vs_ebur128",
            testLimiterTruePeakCeilingGuarantee,
            Tier::Correctness,
        },
        {
            "Limiter_IspDetector_Accuracy_vs_ebur128",
            testLimiterIspDetectorAccuracy,
            Tier::Correctness,
        },
        {
            "Limiter_TruePeak_CeilingWithCrossfeed",
            testLimiterTruePeakCeilingWithCrossfeed,
            Tier::Correctness,
        },
        // S7 / US-QA-03: 31-band EQ frequency-response sweep + bit-transparent bypass.
        // Parallel-safe: pure DSP, no env/tmp, fresh kernel per run.
        {"EQ_Sweep31Bands_48k", testEqSweep31Bands48k, Tier::AccuracySweep},
        {"EQ_Sweep31Bands_44k", testEqSweep31Bands44k, Tier::AccuracySweep},
        {"EQ_SweepExtremes_PlusMinus12", testEqSweepExtremesPlusMinus12, Tier::AccuracySweep},
        {"EQ_NearNyquistBandsApplyGain", testEqNearNyquistBandsApplyGain, Tier::Correctness},
        {
            "EQ_CombinedBands_CutRunAndMixedSign",
            testEqCombinedBandsCutRunAndMixedSign,
            Tier::Correctness,
        },
        {"EQ_FlatIsBitTransparentBypass", testEqFlatIsBitTransparentBypass, Tier::Correctness},
        // Sprint EQ / EQ1a: the graphic-EQ designer vs the Python oracle (parallel-safe: pure
        // DSP, no env/tmp) — Designer_Timing's budget is thread CPU time (the Timing tier).
        {"EQ_Bands_MatchKit", testEqBandsMatchKit, Tier::Correctness},
        {"EQ_Designer_MatchesOracle", testEqDesignerMatchesOracle, Tier::Correctness},
        {"EQ_ACGE_Presets_Tone_Smooth", testEqAcgePresetsToneSmooth, Tier::Correctness},
        {"EQ_ACGE_Ramo1000", testEqAcgeRamo1000, Tier::Correctness},
        {"EQ_ACGE_Hard", testEqAcgeHard, Tier::Correctness},
        {"EQ_ACGE_SingleBand", testEqAcgeSingleBand, Tier::Correctness},
        {"EQ_SvfBell_Exact", testEqSvfBellExact, Tier::Correctness},
        {"EQ_Ultrasonic_Property", testEqUltrasonicProperty, Tier::Correctness},
        {
            "EQ_Readback_MatchesIndependentEval",
            testEqReadbackMatchesIndependentEval,
            Tier::Correctness,
        },
        {"EQ_Design_FlatFinite", testEqDesignFlatFinite, Tier::Correctness},
        {"EQ_Design_Rejects_NonFinite", testEqDesignRejectsNonFinite, Tier::Correctness},
        {"Designer_TwoThreads", testDesignerTwoThreads, Tier::Concurrent},
        {"Designer_Timing", testDesignerTiming, Tier::Timing},
        // Sprint EQ / EQ1c: the track loudness profiler + predictor vs the libebur128 oracle
        // (parallel-safe: pure DSP, no env/tmp) — Profiler_Timing's budget is thread CPU time.
        {"Loudness_Profile_MatchesEbur128", testLoudnessProfileMatchesEbur128, Tier::Correctness},
        {"Loudness_Predictor_Pink", testLoudnessPredictorPink, Tier::Correctness},
        {"Loudness_Predictor_Tonal808", testLoudnessPredictorTonal808, Tier::Correctness},
        {"Loudness_Predictor_Orchestral", testLoudnessPredictorOrchestral, Tier::Correctness},
        {"Loudness_Predictor_LoudMaster", testLoudnessPredictorLoudMaster, Tier::Correctness},
        {
            "Loudness_Predictor_RatesAndLayouts",
            testLoudnessPredictorRatesAndLayouts,
            Tier::Correctness,
        },
        {
            "Loudness_Profile_NoWindow_ParsevalAndTonal",
            testLoudnessProfileNoWindow,
            Tier::Correctness,
        },
        {"Loudness_Profile_PrefixVsFull", testLoudnessProfilePrefixVsFull, Tier::AccuracySweep},
        {
            "Loudness_Profile_DecimationAndMemory",
            testLoudnessProfileDecimationAndMemory,
            Tier::Correctness,
        },
        {"Loudness_Predictor_Properties", testLoudnessPredictorProperties, Tier::Correctness},
        {
            "Loudness_Profiler_RejectsBadInput",
            testLoudnessProfilerRejectsBadInput,
            Tier::Correctness,
        },
        {"Loudness_Abi_LifecycleAndGuards", testLoudnessAbiLifecycleAndGuards, Tier::Correctness},
        {
            "Loudness_Profile_SharedAcrossThreads",
            testLoudnessProfileSharedAcrossThreads,
            Tier::Concurrent,
        },
        {"Profiler_Timing", testProfilerTiming, Tier::Timing},
        // Sprint EQ / EQ1b: the real-time EQ — transitions, paths, guards, re-allocation.
        // The CPU report is a Timing test (thread CPU time); the FZ/denormal tests own their
        // thread's FPCR; the normaliser tests wait until the meter has measured what they pushed.
        {"EQ_Transitions_Realistic", testEqTransitionsRealistic, Tier::AccuracySweep},
        {"EQ_Transitions_Adversarial", testEqTransitionsAdversarial, Tier::AccuracySweep},
        {"EQ_Cpu_7_1_192k", testEqCpu71At192k, Tier::Timing},
        {"EQ_ReadbackEqualsEngine", testEqReadbackEqualsEngine, Tier::Concurrent},
        {
            "EQ_ResponseIndependentOfIntensity",
            testEqResponseIndependentOfIntensity,
            Tier::Correctness,
        },
        {"EQ_Off_BitExact", testEqOffBitExact, Tier::Concurrent},
        {"EQ_BitPerfect_P0", testEqBitPerfectP0, Tier::Concurrent},
        {"Kernel_PathSwitch_NoGlitch", testKernelPathSwitchNoGlitch, Tier::Correctness},
        {
            "Path_Switch_AfterNormaliserAdapted",
            testPathSwitchAfterNormaliserAdapted,
            Tier::Concurrent,
        },
        {"EQ_PublishRejectsNonFinite", testEqPublishRejectsNonFinite, Tier::Concurrent},
        {"EQ_RT_IgnoresBadSnapshot", testEqRtIgnoresBadSnapshot, Tier::Correctness},
        {"EQ_NaNInput_Recovers", testEqNaNInputRecovers, Tier::Correctness},
        {"EQ_FZ_OnWhileRendering", testEqFzOnWhileRendering, Tier::Concurrent},
        {"EQ_NoSubnormalStates", testEqNoSubnormalStates, Tier::Concurrent},
        {
            "Soak_DSPKernel_ZeroRtAlloc_EqPaths",
            testSoakDspKernelZeroRtAllocEqPaths,
            Tier::Concurrent,
        },
        {"EQ_Reallocate_KeepsCurve", testEqReallocateKeepsCurve, Tier::Concurrent},
        {"EQ_Reallocate_NewRate", testEqReallocateNewRate, Tier::Concurrent},
        {"Crossfeed_RederivedOnRateChange", testCrossfeedRederivedOnRateChange, Tier::Concurrent},
        {"Realizer_ReinitDuringDrain", testRealizerReinitDuringDrain, Tier::Concurrent},
        // Sprint EQ / EQ1c part 2: the loudness-neutral gain, live (the cost bound is a Timing
        // test; the RT-alloc soak's guard is per thread).
        {"EQ_LoudnessNeutral_OnOff", testEqLoudnessNeutralOnOff, Tier::Concurrent},
        {"Loudness_ProfileLate", testLoudnessProfileLate, Tier::Concurrent},
        {"Loudness_GaplessSeamStep", testLoudnessGaplessSeamStep, Tier::Concurrent},
        {
            "Loudness_AnalysisFails_CausalFallback",
            testLoudnessAnalysisFailsCausalFallback,
            Tier::Concurrent,
        },
        {"Loudness_EditDebounce", testLoudnessEditDebounce, Tier::Concurrent},
        {"TrackLoudnessGain_Rules", testTrackLoudnessGainRules, Tier::Correctness},
        {
            "Soak_DSPKernel_ZeroRtAlloc_CausalTap",
            testSoakDspKernelZeroRtAllocCausalTap,
            Tier::Concurrent,
        },
        {"Realizer_LoudnessCost", testRealizerLoudnessCost, Tier::Timing},
        // Sprint EQ / EQ2: decision 29's EQ-only ceiling.
        {"Limiter_EqOnlyCeiling", testLimiterEqOnlyCeiling, Tier::Concurrent},
        // Sprint EQ break-it (engine): red tests pinning defects the gate above does not see.
        {"BreakIt_InfInput_KernelRecovers", testBreakItInfInputKernelRecovers, Tier::Concurrent},
        {
            "BreakIt_NonFiniteInput_NormaliserKeepsAdapting",
            testBreakItNonFiniteInputNormaliserKeepsAdapting,
            Tier::Concurrent,
        },
        {
            "BreakIt_Transitions_LowBandGestures",
            testBreakItTransitionsLowBandGestures,
            Tier::AccuracySweep,
        },
        {
            "BreakIt_TauRule_SinglePointIsNotJagged",
            testBreakItTauRuleSinglePointIsNotJagged,
            Tier::Correctness,
        },
        // Sprint EQ engine fix round (amendments 14–19): each fix's own gate.
        {
            "Kernel_NonFiniteInput_PlaysAsSilence",
            testKernelNonFiniteInputPlaysAsSilence,
            Tier::Correctness,
        },
        {
            "Limiter_NonFiniteInput_StaysFinite",
            testLimiterNonFiniteInputStaysFinite,
            Tier::Correctness,
        },
        {
            "LufsMeter_NonFiniteSample_IsSilence",
            testLufsMeterNonFiniteSampleIsSilence,
            Tier::Correctness,
        },
        {"EQ_Transitions_SinglePoints", testEqTransitionsSinglePoints, Tier::AccuracySweep},
        {"EQ_SinglePoint_SettlesFast", testEqSinglePointSettlesFast, Tier::Correctness},
        {"Intensity_Zero_LevelGlide", testIntensityZeroLevelGlide, Tier::Concurrent},
        {"Kernel_P0Switch_LoudMasterStep", testKernelP0SwitchLoudMasterStep, Tier::Concurrent},
        {"Kernel_P0Fade_KeepsPower", testKernelP0FadeKeepsPower, Tier::Correctness},
        {"EQ_Cpu_7_1_AboveSupportedRates", testEqCpu71AboveSupportedRates, Tier::Timing},
        {
            "Loudness_Predictor_PathologicalBounded",
            testLoudnessPredictorPathologicalBounded,
            Tier::Correctness,
        },
        // Sprint G: the output-device menu rule (parallel-safe: pure, no HAL, no env/tmp).
        {"DeviceList_KeepsRealOutputs", testDeviceListKeepsRealOutputs, Tier::Correctness},
        {
            "DeviceList_KeepsVirtualAndUserAggregates",
            testDeviceListKeepsVirtualAndUserAggregates,
            Tier::Correctness,
        },
        {"DeviceList_HidesInternalDevices", testDeviceListHidesInternalDevices, Tier::Correctness},
        {"DeviceList_RuleOrder", testDeviceListRuleOrder, Tier::Correctness},
        {"DeviceList_CompositionDecode", testDeviceListCompositionDecode, Tier::Correctness},
        {"DeviceList_VerdictStrings", testDeviceListVerdictStrings, Tier::Correctness},
        // R1.1-A: the one output classifier — family, and headphones (crossfeed's gate).
        {"OutputDevice_Family", testOutputDeviceFamily, Tier::Correctness},
        {"OutputDevice_Headphones", testOutputDeviceHeadphones, Tier::Correctness},
        // Sprint G: the Pure seek's render gate (parallel-safe: own threads, no HAL, no env/tmp).
        {
            "RenderGate_ClosedGateTurnsRenderAway",
            testRenderGateClosedGateTurnsRenderAway,
            Tier::Correctness,
        },
        {
            "RenderGate_CloseWaitsForRenderInside",
            testRenderGateCloseWaitsForRenderInside,
            Tier::Concurrent,
        },
        {
            "RenderGate_PendingCloseBarsReentry",
            testRenderGatePendingCloseBarsReentry,
            Tier::Correctness,
        },
        {
            "RenderGate_TeardownCloseNeverReopens",
            testRenderGateTeardownCloseNeverReopens,
            Tier::Correctness,
        },
        {
            "RenderGate_ConcurrentNeverOverlaps",
            testRenderGateConcurrentNeverOverlaps,
            Tier::Concurrent,
        },
        // S7 / US-QA-06 (automated half): RT-allocation-guard soak. These arm a process-wide
        // operator new/delete override scoped to the calling thread via a thread_local flag, so
        // other tests' allocations never trip it. The Gapless soak writes fixtures (serial).
        {
            "Soak_DSPKernel_ZeroRtAlloc_FullChain",
            testSoakDspKernelZeroRtAllocFullChain,
            Tier::Correctness,
        },
        {"Soak_DSPKernel_ZeroRtAlloc_Blend", testSoakDspKernelZeroRtAllocBlend, Tier::Correctness},
        // QW1 CF-12: crossfeed-on blend soak (rtAllocs==0).
        {
            "Soak_DSPKernel_ZeroRtAlloc_CrossfeedBlend",
            testSoakDspKernelZeroRtAllocCrossfeedBlend,
            Tier::Concurrent,
        },
        {
            "Soak_GaplessSource_ZeroRtAlloc_Pull",
            testSoakGaplessSourceZeroRtAllocPull,
            Tier::Concurrent,
            kSerial,
        },
        // S6 RACE-1: wait-free triple-buffer parameter snapshot — concurrent publish/read, no torn read
        // (realistic TargetState payload; gen-0 identity-seed handled — see the .inc header).
        {
            "Snapshot_Seqlock_ConcurrentNoTear_RACE1",
            testSnapshotSeqlockConcurrentNoTear,
            Tier::Concurrent,
        },
        // Hardening (2026-07-10): whole-payload, all-words-equal tear detector over multiple fresh
        // rounds — independent cross-check of the generic transport, no seed special-case.
        {
            "Snapshot_TripleBuffer_WholePayloadNoTear",
            testSnapshotTripleBufferWholePayloadNoTear,
            Tier::Concurrent,
        },
        // ---- AnalyzerTests.inc (R1.1-B W4, lane 1): rows below ----
        // ---- end AnalyzerTests.inc ----
        // ---- LevelPlanTests.inc (R1.1-B W4, lane 1): rows below ----
        {"LevelPlan_RoleNumbers_Fixed", testLevelPlanRoleNumbersFixed, Tier::Correctness},
        {"LevelPlan_FoldMatrix_Table", testLevelPlanFoldMatrixTable, Tier::Correctness},
        {
            "LevelPlan_FoldMatrix_WorstCaseTrim",
            testLevelPlanFoldMatrixWorstCaseTrim,
            Tier::Correctness,
        },
        {"LevelPlan_WorkingCeiling", testLevelPlanWorkingCeiling, Tier::Correctness},
        {"LevelPlan_LfeVariantGains", testLevelPlanLfeVariantGains, Tier::Correctness},
        {
            "Kernel_CrossfeedEngaged_FollowsWhatPlays",
            testKernelCrossfeedEngagedFollowsWhatPlays,
            Tier::Correctness,
        },
        // ---- end LevelPlanTests.inc ----
        // ---- FoldTests.inc (R1.1-B W4, lane 2): rows below ----
        // ---- end FoldTests.inc ----
        // ---- LfeRuleTests.inc (R1.1-B W4, lane 2): rows below ----
        // ---- end LfeRuleTests.inc ----
    });
} // namespace

// ---------------------------------------------------------------------------

auto main(int argc, char** argv) -> int
{
    return runNullTest(argc, argv, kTests);
}
