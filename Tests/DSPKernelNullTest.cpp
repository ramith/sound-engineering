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
#include "SnapshotConcurrencyTests.inc"
#include "EqTransitionTests.inc" // after EqDesignerTests.inc (its curves)
#include "EqEngineTests.inc"     // after SoakRtAllocTests.inc (its RT-alloc guard)
#include "LoudnessNeutralTests.inc" // after TrackLoudnessTests.inc + EqEngineTests.inc (helpers)
#include "EqEngineBreakItTests.inc" // after EqEngineTests.inc + EqTransitionTests.inc (helpers)
#include "EqEngineFixTests.inc"     // after EqEngineBreakItTests.inc (helpers)
#include "DeviceListPolicyTests.inc"
#include "RenderGateTests.inc"
// clang-format on

// ---------------------------------------------------------------------------
// Test registry: EXACT current call order. parallelSafe=false on all 16 FileDecode_*
// and testFileDecode* tests (they mutate ADAPTIVESOUND_DECODER and share /tmp paths).
// ---------------------------------------------------------------------------

namespace
{
    constexpr auto kTests = std::to_array<TestEntry>({
        // Phase 0 bypass tests
        {"IntensityZero_BitExactPassthrough", testIntensityZeroIsBitExact, true},
        {"IntensityZero_MultiChunkBitExact", testIntensityZeroMultiChunk, true},
        // Identity-chain tests
        {"WhiteNoiseBypasses", testWhiteNoiseBypasses, true},
        {"ChirpSignalBypasses", testChirpBypasses, true},
        {"EQModuleIdentityByDefault", testEQModuleIdentityByDefault, true},
        {"ZeroInputProducesZeroOutput", testZeroInputProducesZeroOutput, true},
        {"MultiChunkStatePreservation", testMultiChunkStatePreservation, true},
        // Limiter tests (Sprint 4)
        {"Limiter_BypassIsIdentity", testLimiterBypassIsIdentity, true},
        {"Limiter_CeilingEnforcement", testLimiterCeilingEnforcement, true},
        {"Limiter_GRResponseWithin2ms", testLimiterGRResponseTime, true},
        {"Limiter_NearNyquistCeiling", testLimiterNearNyquistCeiling, true},
        {"Limiter_HotNoiseSoak", testLimiterHotNoiseSoak, true},
        // R1.1-A (council C-39): the release is program-dependent — a transient is fast.
        {"Limiter_Release_TransientIsFast", testLimiterReleaseTransientIsFast, true},
        {"Limiter_Release_SustainedIsSlow", testLimiterReleaseSustainedIsSlow, true},
        // Loudness / BS.1770-5 tests (Sprint 4 — Milestone 2)
        {"Loudness_KWeightingLowCut", testLoudnessKWeightingLowCut, true},
        {"Loudness_IntegratedAccuracy", testLoudnessIntegratedAccuracy, true},
        {"Loudness_AbsoluteGate", testLoudnessAbsoluteGate, true},
        {"Loudness_RelativeGate", testLoudnessRelativeGate, true},
        {"Loudness_MakeupRoundTrip", testLoudnessMakeupRoundTrip, true},
        {"Loudness_TruePeakKernel_InterSample", testLoudnessTruePeakKernelInterSample, true},
        {"Loudness_MeterBridge_TruePeak", testLoudnessMeterBridgeTruePeak, true},
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
        // R1.1-A (council C-50): flush-to-zero is scoped to our render calls, then restored.
        {"Render_FlushToZero_Scoped", testRenderFlushToZeroScoped, true},
        // Pure-Mode policy (Phase B — B1)
        {"PureMode_HdmiBitPerfect", testPureModeHdmiBitPerfect, true},
        {"PureMode_HdmiRateUnsupported", testPureModeHdmiRateUnsupported, true},
        {"PureMode_BluetoothLossy", testPureModeBluetoothLossy, true},
        {"PureMode_BuiltInRateMatchedFloat", testPureModeBuiltInRateMatchedFloat, true},
        {"PureMode_BuiltInRateUnsupported", testPureModeBuiltInRateUnsupported, true},
        {"PureMode_VirtualDevice", testPureModeVirtualDevice, true},
        {"PureMode_RateEpsilonAndMax", testPureModeRateEpsilonAndMax, true},
        {"PureMode_ChannelCountMismatch", testPureModeChannelCountMismatch, true},
        // Pure-Mode format conversion (Phase B — B2a)
        {"Convert_Int16Saturation", testConvertInt16Saturation, true},
        {"Convert_Int32Saturation", testConvertInt32Saturation, true},
        {"Convert_24In32Alignment", testConvert24In32Alignment, true},
        {"Convert_FloatPassthrough", testConvertFloatPassthrough, true},
        {"PureFormat_FromAsbdOnlyExactLayouts", testPureFormatFromAsbdOnlyExactLayouts, true},
        {"PureFormat_PickerOnlyWritableFormats", testPureFormatPickerOnlyWritableFormats, true},
        {"Convert_Packed24_ExactBytesRoundTrip", testConvertPacked24ExactBytesRoundTrip, true},
        {"Convert_WriteBoundedByBufferBytes", testConvertWriteBoundedByBufferBytes, true},
        {
            "Convert_NonFiniteIsSilence_FiniteUntouched",
            testConvertNonFiniteIsSilenceFiniteUntouched,
            true,
        },
        {"Convert_BitExact_Exhaustive16And24", testConvertBitExactExhaustive16And24, true},
        {"ToneSource_FillsBuffer", testToneSourceFillsBuffer, true},
        // Pure-Mode C-ABI bridge (pureModeEvaluate) — PARALLEL-SAFE: pure functions, no env/tmp
        {
            "PureModeBridge_TranslatesAllDecisionBranches",
            testPureModeBridgeTranslatesAllDecisionBranches,
            true,
        },
        {"PureModeBridge_NullArgsAreNoOp", testPureModeBridgeNullArgsAreNoOp, true},
        {
            "PureModeBridge_RateArrayCopiedFaithfully",
            testPureModeBridgeRateArrayCopiedFaithfully,
            true,
        },
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
        {
            "FileDecode_PullChannelMismatchSilence",
            testFileDecodePullChannelMismatchSilence,
            false,
        },
        {"FileDecode_EofAndFinishedFlag", testFileDecodeEofAndFinishedFlag, false},
        {"FileDecode_FinishedFlagRingTail", testFileDecodeFinishedFlagRingTail, false},
        {"FileDecode_PullBeforeDecodeZeroPads", testFileDecodePullBeforeDecodeZeroPads, false},
        {"FileDecode_BackendEquivalence", testFileDecodeBackendEquivalence, false},
        {"FileDecode_RingWraparound", testFileDecodeRingWraparound, false},
        // Seek coverage (FileDecodeSource::seek) — SERIAL: mutate env + /tmp paths
        {"FileDecode_Seek_SampleAccurateWav16", testFileDecodeSeekSampleAccurateWav16, false},
        {
            "FileDecode_Seek_ToZeroReproducesFromOpen",
            testFileDecodeSeekToZeroReproducesFromOpen,
            false,
        },
        {"FileDecode_Seek_PastEofLandsAtEnd", testFileDecodeSeekPastEofLandsAtEnd, false},
        {
            "FileDecode_Seek_BackendEquivalenceAfterSeek",
            testFileDecodeSeekBackendEquivalenceAfterSeek,
            false,
        },
        {
            "FileDecode_Seek_RepeatedRapidNoStaleNoLeak",
            testFileDecodeSeekRepeatedRapidNoStaleNoLeak,
            false,
        },
        {
            "FileDecode_Seek_MidStreamDistinctChannels",
            testFileDecodeSeekMidStreamDistinctChannels,
            false,
        },
        // C-35: the FFmpeg seek honours the stream start; a refused seek keeps the buffered audio.
        {
            "FileDecode_Seek_FFmpegHonoursStreamStart",
            testFileDecodeSeekFFmpegHonoursStreamStart,
            false,
        },
        {
            "FileDecode_Seek_RefusedKeepsBufferedAudio",
            testFileDecodeSeekRefusedKeepsBufferedAudio,
            false,
        },
        // FFmpeg as an opt-in, off by default, hardened load (R1.1-A, FD-3, C-99) — SERIAL: the
        // switch is process-wide.
        {"FFmpeg_OffByDefault_LoadsNothing", testFFmpegOffByDefaultLoadsNothing, false},
        {"FFmpeg_VetLibrary_Rules", testFFmpegVetLibraryRules, false},
        {"FFmpeg_LibraryPaths_FixedAndAbsolute", testFFmpegLibraryPathsFixedAndAbsolute, false},
        {"FFmpeg_ReadFacts_RealFiles", testFFmpegReadFactsRealFiles, false},
        {
            "FFmpeg_OpenLibrary_RefusesWhatOthersCanChange",
            testFFmpegOpenLibraryRefusesWhatOthersCanChange,
            false,
        },
        {"FFmpeg_ProbeNamesWhyAFileWontOpen", testFFmpegProbeNamesWhyAFileWontOpen, false},
        // Gapless DECODE-LAYER decode->concatenate contract — SERIAL: write fixtures to test-data/.
        {"Gapless_SeamFrameAccuracy", testGaplessSeamFrameAccuracy, false},
        {"Gapless_TotalFrameCount_48kOnly", testGaplessTotalFrameCount48kOnly, false},
        {
            "Gapless_SampleRateMismatch_ProducesFrameCountForEach",
            testGaplessSampleRateMismatchProducesFrameCountForEach,
            false,
        },
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
        {"PureGapless_ArmRefusesOtherWidth", testPureGaplessArmRefusesOtherWidth, false},
        // S6 Tier-3 (3d) Pure gapless behavioral-contract conformance — SERIAL: write fixtures.
        {
            "GaplessContract_TransitionCountPerSeam",
            testGaplessContractTransitionCountPerSeam,
            false,
        },
        {"GaplessContract_ClearCancelsOnDeck", testGaplessContractClearCancelsOnDeck, false},
        {"GaplessContract_EndOfQueueSignals", testGaplessContractEndOfQueueSignals, false},
        {
            "GaplessContract_PositionRezeroesAtSeam",
            testGaplessContractPositionRezeroesAtSeam,
            false,
        },
        {
            "GaplessContract_PollReapsRetiredSource",
            testGaplessContractPollReapsRetiredSource,
            false,
        },
        // Council D41: the Pure arm contract — SERIAL: write fixtures to test-data/.
        {"ArmContract_RetractArmBeforeEnd", testArmContractRetractArmBeforeEnd, false},
        {"ArmContract_OccupiedRefuses", testArmContractOccupiedRefuses, false},
        {"ArmContract_RetractEndArm", testArmContractRetractEndArm, false},
        {"ArmContract_ArmBeforeReap", testArmContractArmBeforeReap, false},
        {"ArmContract_ClearRacesSeam", testArmContractClearRacesSeam, false},
        {"ArmContract_ArmRacesEnd", testArmContractArmRacesEnd, false},
        {"ArmContract_ArmWhileSeamClaimed", testArmContractArmWhileSeamClaimed, false},
        {"ArmContract_ArmWhileSeamRetired", testArmContractArmWhileSeamRetired, false},
        {"ArmContract_SeamPublishBounded", testArmContractSeamPublishBounded, false},
        // S6 Tier-3 (3a) Realizer multi-surface RMW contract (parallel-safe: no env/tmp).
        {"Realizer_MultiSurfaceRMW_NoClobber_SeqMonotonic", testRealizerMultiSurfaceRMW, true},
        // QW1 CF-11: the 4th Realizer surface — crossfeed RMW + clamp (parallel-safe).
        {"Realizer_Crossfeed_4SurfaceRMW_Clamp", testRealizerCrossfeedSurfaceRMW, true},
        // S6 Tier-3 (3b) steerable wet/dry intensity (parallel-safe: no env/tmp).
        {"Intensity_EndpointsBitExact_Settled", testIntensityEndpointsBitExact, true},
        {
            "Intensity_SettledRampConvergesToHardBranch",
            testIntensitySettledRampConvergesToHardBranch,
            true,
        },
        {"Intensity_EqualPowerAtHalf", testIntensityEqualPowerAtHalf, true},
        {
            "Intensity_LevelPeakSafetyIntermediate",
            testIntensityLevelPeakSafetyIntermediate,
            true,
        },
        {"Intensity_NoNaNAndFastStepSettles", testIntensityNoNaNFastStepSettles, true},
        // Crossfeed: bs2b conformance CF-1..CF-9 and its own kernel stage CF-13 / CF-14
        // (parallel-safe: pure DSP, no env/tmp).
        {
            "Crossfeed_Bypass_BitExact_GoldenMaster",
            testCrossfeedBypassBitExactGoldenMaster,
            true,
        },
        {"Crossfeed_NonStereo_PassThrough", testCrossfeedNonStereoPassThrough, true},
        {"Crossfeed_CentreFlat_vs_bs2b", testCrossfeedCentreFlatVsBs2b, true},
        {"Crossfeed_ChannelSeparation", testCrossfeedChannelSeparation, true},
        {"Crossfeed_LpfCharacteristic", testCrossfeedLpfCharacteristic, true},
        {"Crossfeed_NoNaNInf", testCrossfeedNoNaNInf, true},
        {"Crossfeed_ClickFreeEnableDisable", testCrossfeedClickFreeEnableDisable, true},
        {"Crossfeed_CoeffRecomputeAcrossRates", testCrossfeedCoeffRecomputeAcrossRates, true},
        {"Crossfeed_MatchesBs2bReference", testCrossfeedMatchesBs2bReference, true},
        {"Crossfeed_PlaysAtAnyIntensity", testCrossfeedPlaysAtAnyIntensity, true},
        {"Crossfeed_Off_BitExact", testCrossfeedOffBitExact, true},
        // S7 / US-QA-01: TEST-ONLY libebur128 conformance oracle (parallel-safe: no env/tmp).
        {"Loudness_Oracle_Integrated_vs_ebur128", testLoudnessOracleIntegrated, true},
        {"Loudness_Oracle_TruePeak_vs_ebur128", testLoudnessOracleTruePeak, true},
        // QW1 CF-10: crossfeed ebur128 loudness-neutrality (real decorrelated stereo).
        {"Crossfeed_ebur128_LevelNeutral", testCrossfeedLoudnessNeutral, true},
        // R1.1-A (council C-46): the UI's Integrated is the track's, not the session's.
        {
            "Loudness_MeterBridge_IntegratedPerTrack",
            testLoudnessMeterBridgeIntegratedPerTrack,
            true,
        },
        {
            "Loudness_MeterBridge_BeginTrack_Concurrent",
            testLoudnessMeterBridgeBeginTrackConcurrent,
            true,
        },
        // S7 / US-QA-02: TEST-ONLY limiter true-peak ceiling guarantee + ISP-detector accuracy
        // (parallel-safe: pure DSP, no env/tmp).
        {
            "Limiter_TruePeak_CeilingGuarantee_vs_ebur128",
            testLimiterTruePeakCeilingGuarantee,
            true,
        },
        {"Limiter_IspDetector_Accuracy_vs_ebur128", testLimiterIspDetectorAccuracy, true},
        {"Limiter_TruePeak_CeilingWithCrossfeed", testLimiterTruePeakCeilingWithCrossfeed, true},
        // S7 / US-QA-03: 31-band EQ frequency-response sweep + bit-transparent bypass.
        // Parallel-safe: pure DSP, no env/tmp, fresh kernel per run.
        {"EQ_Sweep31Bands_48k", testEqSweep31Bands48k, true},
        {"EQ_Sweep31Bands_44k", testEqSweep31Bands44k, true},
        {"EQ_SweepExtremes_PlusMinus12", testEqSweepExtremesPlusMinus12, true},
        {"EQ_NearNyquistBandsApplyGain", testEqNearNyquistBandsApplyGain, true},
        {"EQ_CombinedBands_CutRunAndMixedSign", testEqCombinedBandsCutRunAndMixedSign, true},
        {"EQ_FlatIsBitTransparentBypass", testEqFlatIsBitTransparentBypass, true},
        // Sprint EQ / EQ1a: the graphic-EQ designer vs the Python oracle (parallel-safe: pure
        // DSP, no env/tmp) — except Designer_Timing, serial so the pool cannot skew its clock.
        {"EQ_Bands_MatchKit", testEqBandsMatchKit, true},
        {"EQ_Designer_MatchesOracle", testEqDesignerMatchesOracle, true},
        {"EQ_ACGE_Presets_Tone_Smooth", testEqAcgePresetsToneSmooth, true},
        {"EQ_ACGE_Ramo1000", testEqAcgeRamo1000, true},
        {"EQ_ACGE_Hard", testEqAcgeHard, true},
        {"EQ_ACGE_SingleBand", testEqAcgeSingleBand, true},
        {"EQ_SvfBell_Exact", testEqSvfBellExact, true},
        {"EQ_Ultrasonic_Property", testEqUltrasonicProperty, true},
        {"EQ_Readback_MatchesIndependentEval", testEqReadbackMatchesIndependentEval, true},
        {"EQ_Design_FlatFinite", testEqDesignFlatFinite, true},
        {"EQ_Design_Rejects_NonFinite", testEqDesignRejectsNonFinite, true},
        {"Designer_TwoThreads", testDesignerTwoThreads, true},
        {"Designer_Timing", testDesignerTiming, false},
        // Sprint EQ / EQ1c: the track loudness profiler + predictor vs the libebur128 oracle
        // (parallel-safe: pure DSP, no env/tmp) — except Profiler_Timing, serial for its clock.
        {"Loudness_Profile_MatchesEbur128", testLoudnessProfileMatchesEbur128, true},
        {"Loudness_Predictor_Pink", testLoudnessPredictorPink, true},
        {"Loudness_Predictor_Tonal808", testLoudnessPredictorTonal808, true},
        {"Loudness_Predictor_Orchestral", testLoudnessPredictorOrchestral, true},
        {"Loudness_Predictor_LoudMaster", testLoudnessPredictorLoudMaster, true},
        {"Loudness_Predictor_RatesAndLayouts", testLoudnessPredictorRatesAndLayouts, true},
        {
            "Loudness_Profile_NoWindow_ParsevalAndTonal",
            testLoudnessProfileNoWindow,
            true,
        },
        {"Loudness_Profile_PrefixVsFull", testLoudnessProfilePrefixVsFull, true},
        {
            "Loudness_Profile_DecimationAndMemory",
            testLoudnessProfileDecimationAndMemory,
            true,
        },
        {"Loudness_Predictor_Properties", testLoudnessPredictorProperties, true},
        {"Loudness_Profiler_RejectsBadInput", testLoudnessProfilerRejectsBadInput, true},
        {"Loudness_Abi_LifecycleAndGuards", testLoudnessAbiLifecycleAndGuards, true},
        {
            "Loudness_Profile_SharedAcrossThreads",
            testLoudnessProfileSharedAcrossThreads,
            true,
        },
        {"Profiler_Timing", testProfilerTiming, false},
        // Sprint EQ / EQ1b: the real-time EQ — transitions, paths, guards, re-allocation.
        // Serial: the CPU report, the FPCR-owning FZ/denormal tests, the paced normaliser
        // test and the soak (the pool would skew or race them).
        {"EQ_Transitions_Realistic", testEqTransitionsRealistic, true},
        {"EQ_Transitions_Adversarial", testEqTransitionsAdversarial, true},
        {"EQ_Cpu_7_1_192k", testEqCpu71At192k, false},
        {"EQ_ReadbackEqualsEngine", testEqReadbackEqualsEngine, true},
        {"EQ_ResponseIndependentOfIntensity", testEqResponseIndependentOfIntensity, true},
        {"EQ_Off_BitExact", testEqOffBitExact, true},
        {"EQ_BitPerfect_P0", testEqBitPerfectP0, true},
        {"Kernel_PathSwitch_NoGlitch", testKernelPathSwitchNoGlitch, true},
        {"Path_Switch_AfterNormaliserAdapted", testPathSwitchAfterNormaliserAdapted, false},
        {"EQ_PublishRejectsNonFinite", testEqPublishRejectsNonFinite, true},
        {"EQ_RT_IgnoresBadSnapshot", testEqRtIgnoresBadSnapshot, true},
        {"EQ_NaNInput_Recovers", testEqNaNInputRecovers, true},
        {"EQ_FZ_OnWhileRendering", testEqFzOnWhileRendering, false},
        {"EQ_NoSubnormalStates", testEqNoSubnormalStates, false},
        {"RtSwappableResource_Lifecycle", testRtSwappableResourceLifecycle, true},
        {"Soak_DSPKernel_ZeroRtAlloc_EqPaths", testSoakDspKernelZeroRtAllocEqPaths, false},
        {"EQ_Reallocate_KeepsCurve", testEqReallocateKeepsCurve, true},
        {"EQ_Reallocate_NewRate", testEqReallocateNewRate, true},
        {"Crossfeed_RederivedOnRateChange", testCrossfeedRederivedOnRateChange, true},
        {"Realizer_ReinitDuringDrain", testRealizerReinitDuringDrain, true},
        // Sprint EQ / EQ1c part 2: the loudness-neutral gain, live (the timing and the RT-alloc
        // soak are serial-only: the pool would skew the clock / the guard is process-wide).
        {"EQ_LoudnessNeutral_OnOff", testEqLoudnessNeutralOnOff, true},
        {"Loudness_ProfileLate", testLoudnessProfileLate, true},
        {"Loudness_GaplessSeamStep", testLoudnessGaplessSeamStep, true},
        {
            "Loudness_AnalysisFails_CausalFallback",
            testLoudnessAnalysisFailsCausalFallback,
            true,
        },
        {"Loudness_EditDebounce", testLoudnessEditDebounce, true},
        {"TrackLoudnessGain_Rules", testTrackLoudnessGainRules, true},
        {"Soak_DSPKernel_ZeroRtAlloc_CausalTap", testSoakDspKernelZeroRtAllocCausalTap, false},
        {"Realizer_LoudnessCost", testRealizerLoudnessCost, false},
        // Sprint EQ / EQ2: decision 29's EQ-only ceiling.
        {"Limiter_EqOnlyCeiling", testLimiterEqOnlyCeiling, true},
        // Sprint EQ break-it (engine): red tests pinning defects the gate above does not see.
        {"BreakIt_InfInput_KernelRecovers", testBreakItInfInputKernelRecovers, true},
        {
            "BreakIt_NonFiniteInput_NormaliserKeepsAdapting",
            testBreakItNonFiniteInputNormaliserKeepsAdapting,
            false,
        },
        {"BreakIt_Transitions_LowBandGestures", testBreakItTransitionsLowBandGestures, true},
        {"BreakIt_TauRule_SinglePointIsNotJagged", testBreakItTauRuleSinglePointIsNotJagged, true},
        // Sprint EQ engine fix round (amendments 14–19): each fix's own gate.
        {"Kernel_NonFiniteInput_PlaysAsSilence", testKernelNonFiniteInputPlaysAsSilence, true},
        {"Limiter_NonFiniteInput_StaysFinite", testLimiterNonFiniteInputStaysFinite, true},
        {"LufsMeter_NonFiniteSample_IsSilence", testLufsMeterNonFiniteSampleIsSilence, true},
        {"EQ_Transitions_SinglePoints", testEqTransitionsSinglePoints, true},
        {"EQ_SinglePoint_SettlesFast", testEqSinglePointSettlesFast, true},
        {"Intensity_Zero_LevelGlide", testIntensityZeroLevelGlide, false},
        {"Kernel_P0Switch_LoudMasterStep", testKernelP0SwitchLoudMasterStep, true},
        {"Kernel_P0Fade_KeepsPower", testKernelP0FadeKeepsPower, true},
        {"EQ_Cpu_7_1_AboveSupportedRates", testEqCpu71AboveSupportedRates, false},
        {
            "Loudness_Predictor_PathologicalBounded",
            testLoudnessPredictorPathologicalBounded,
            true,
        },
        // Sprint G: the output-device menu rule (parallel-safe: pure, no HAL, no env/tmp).
        {"DeviceList_KeepsRealOutputs", testDeviceListKeepsRealOutputs, true},
        {
            "DeviceList_KeepsVirtualAndUserAggregates",
            testDeviceListKeepsVirtualAndUserAggregates,
            true,
        },
        {"DeviceList_HidesInternalDevices", testDeviceListHidesInternalDevices, true},
        {"DeviceList_RuleOrder", testDeviceListRuleOrder, true},
        {"DeviceList_CompositionDecode", testDeviceListCompositionDecode, true},
        {"DeviceList_VerdictStrings", testDeviceListVerdictStrings, true},
        // R1.1-A: the one output classifier — family, and headphones (crossfeed's gate).
        {"OutputDevice_Family", testOutputDeviceFamily, true},
        {"OutputDevice_Headphones", testOutputDeviceHeadphones, true},
        // Sprint G: the Pure seek's render gate (parallel-safe: own threads, no HAL, no env/tmp).
        {"RenderGate_ClosedGateTurnsRenderAway", testRenderGateClosedGateTurnsRenderAway, true},
        {"RenderGate_CloseWaitsForRenderInside", testRenderGateCloseWaitsForRenderInside, true},
        {"RenderGate_PendingCloseBarsReentry", testRenderGatePendingCloseBarsReentry, true},
        {"RenderGate_TeardownCloseNeverReopens", testRenderGateTeardownCloseNeverReopens, true},
        {"RenderGate_ConcurrentNeverOverlaps", testRenderGateConcurrentNeverOverlaps, true},
        // S7 / US-QA-06 (automated half): RT-allocation-guard soak. SERIAL-ONLY — these arm a
        // process-wide operator new/delete override scoped to the calling thread via a thread_local
        // flag; running them in the parallel worker pool alongside other allocating tests is fine
        // for correctness (the flag is thread_local) but the Gapless soak spins on real decode
        // threads and the DSPKernel soaks are long, so keep them serial to avoid skewing the pool.
        {"Soak_DSPKernel_ZeroRtAlloc_FullChain", testSoakDspKernelZeroRtAllocFullChain, false},
        {"Soak_DSPKernel_ZeroRtAlloc_Blend", testSoakDspKernelZeroRtAllocBlend, false},
        // QW1 CF-12: crossfeed-on blend soak (rtAllocs==0).
        {
            "Soak_DSPKernel_ZeroRtAlloc_CrossfeedBlend",
            testSoakDspKernelZeroRtAllocCrossfeedBlend,
            false,
        },
        {"Soak_GaplessSource_ZeroRtAlloc_Pull", testSoakGaplessSourceZeroRtAllocPull, false},
        // S6 RACE-1: wait-free triple-buffer parameter snapshot — concurrent publish/read, no torn read
        // (realistic TargetState payload; gen-0 identity-seed handled — see the .inc header).
        {"Snapshot_Seqlock_ConcurrentNoTear_RACE1", testSnapshotSeqlockConcurrentNoTear, true},
        // Hardening (2026-07-10): whole-payload, all-words-equal tear detector over multiple fresh
        // rounds — independent cross-check of the generic transport, no seed special-case.
        {
            "Snapshot_TripleBuffer_WholePayloadNoTear",
            testSnapshotTripleBufferWholePayloadNoTear,
            true,
        },
    });
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
        else if (arg.starts_with("--parallel="))
        {
            const int val = std::stoi(arg.substr(11U));
            parallelN = std::max(1, val);
        }
        else if (arg == "--list")
        {
            listOnly = true;
        }
        else if (arg.starts_with("--filter="))
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
