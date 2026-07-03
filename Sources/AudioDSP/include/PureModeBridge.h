#pragma once

//
// PureModeBridge.h — Pure C header bridging the "Pure Mode" (bit-perfect HAL output) C++ layer
// to Swift.
//
// This header is included via the Swift bridging header and MUST be valid ISO C11 (no C++
// namespaces, no #include <cstdint>, no class declarations). It declares flat POD structs plus
// the C-ABI Pure-Mode policy + engine functions.
//
// Two implementation files back this surface:
//   * PureModeBridgePolicy.cpp — CoreAudio-FREE; implements ONLY pureModeEvaluate(). Compiles into
//     the C++ test harness (which links no CoreAudio).
//   * PureModeBridge.mm        — CoreAudio (Obj-C++) glue for capability querying + the engine.
//
// Opaque-handle convention (mirrors DeviceBridge.h): the engine is owned through a void* handle;
// the caller creates it with pureModeEngineCreate() and destroys it with pureModeEngineDestroy()
// (NULL-safe). All structs are plain-old-data; uint8_t stands in for bool to keep the ABI fixed.
//

#include <stdint.h>

// A noexcept-specifier for the extern "C" bridge functions under C++ (a C++ exception must
// never unwind across the C ABI into Swift — that is UB / std::terminate). Expands to nothing
// for the C compiler Swift's bridging uses, where `noexcept` is not a keyword.
#ifndef AUDIODSP_C_NOEXCEPT
#ifdef __cplusplus
#define AUDIODSP_C_NOEXCEPT noexcept
#else
#define AUDIODSP_C_NOEXCEPT
#endif
#endif

// MARK: - Flat POD structs

/// Flat mirror of AdaptiveSound::DeviceCapability's scalar fields (CoreAudio-free).
/// The available-rate list is passed separately as a (rates, count) pair so this struct stays POD.
typedef struct
{
    uint32_t deviceID;               ///< CoreAudio AudioDeviceID (opaque here)
    uint32_t transportType;          ///< CoreAudio transport FourCC (opaque; not interpreted)
    double currentRate;              ///< Current nominal sample rate (Hz)
    uint32_t physicalBitsPerChannel; ///< physicalFormat bit depth (e.g. 16, 24, 32)
    uint32_t physicalChannels;       ///< physicalFormat channels per frame
    uint8_t integerCapable;          ///< 1 if the physical format is integer PCM (bit-perfect path)
    uint8_t exclusiveCapable;        ///< 1 if plausibly hoggable (not virtual / aggregate)
    uint8_t isLossyWireless;         ///< 1 for BT / BT-LE / AirPlay (codec below the HAL)
    uint8_t isVirtualOrAggregate;    ///< 1 for virtual / aggregate devices
} CDeviceCapability;

/// Flat mirror of AdaptiveSound::FileFormat.
typedef struct
{
    double sampleRate;       ///< File native sample rate (Hz)
    uint32_t bitsPerChannel; ///< Source bit depth (e.g. 16, 24, 32)
    uint32_t channels;       ///< Source channel count
    uint8_t isFloat;         ///< 1 if the source samples are float
} CFileFormat;

/// Flat mirror of AdaptiveSound::PureModeEvaluation.
/// `decision` mirrors PureModeDecision order: 0 FullBitPerfect, 1 RateMatchedFloat,
/// 2 FallbackEnhanced. `reason` mirrors PureModeReason order: 0 BitPerfectInteger,
/// 1 RateMatchedFloatNoSRC, 2 LossyWirelessCodec, 3 VirtualDevice, 4 RateUnsupportedResample.
typedef struct
{
    uint8_t decision;           ///< 0 FullBitPerfect, 1 RateMatchedFloat, 2 FallbackEnhanced
    double targetDeviceRate;    ///< Rate to drive the device at (0 = leave as-is / N/A)
    uint8_t requiresRateChange; ///< 1 if the device nominal rate must change
    uint8_t requiresHog;        ///< 1 if exclusive (hog-mode) access is required
    uint8_t reason;             ///< Mirrors PureModeReason order (see above)
} CPureModeEvaluation;

/// Flat mirror of AdaptiveSound::AchievedOutputState, plus the decoder backend that was used.
typedef struct
{
    uint8_t decision;                ///< Mirrors PureModeDecision order
    uint8_t configured;              ///< 1 if configure() set up the AU far enough to render
    uint8_t didHog;                  ///< 1 if WE hold hog mode (and must release it on teardown)
    uint8_t rateChanged;             ///< 1 if we successfully changed the device nominal rate
    double achievedRate;             ///< Device nominal rate the engine is running at (Hz)
    uint32_t achievedBitsPerChannel; ///< AU output format bit depth actually negotiated
    uint8_t achievedIsFloat;         ///< 1 if the AU output format is float (vs integer PCM)
    uint8_t running;                 ///< 1 if start() succeeded and stop() has not been called
    uint8_t decoderBackend;          ///< 0 apple, 1 ffmpeg
} CAchievedOutputState;

// MARK: - C-ABI functions

#ifdef __cplusplus
extern "C"
{
#endif

    // MARK: CoreAudio-FREE policy (implemented in PureModeBridgePolicy.cpp)

    /// Evaluate the Pure-Mode policy for one (device, file) pair. Pure function; no side effects.
    ///
    /// @param cap            Flat device capability (scalar fields). Must be non-NULL.
    /// @param availableRates Caller-owned array of advertised nominal rates (Hz); may be NULL iff
    ///                       rateCount == 0.
    /// @param rateCount      Number of entries in availableRates.
    /// @param file           Flat file format. Must be non-NULL.
    /// @param out            Caller-allocated result. Must be non-NULL.
    void pureModeEvaluate(const CDeviceCapability* cap,
                          const double* availableRates,
                          uint32_t rateCount,
                          const CFileFormat* file,
                          CPureModeEvaluation* out) AUDIODSP_C_NOEXCEPT;

    // MARK: CoreAudio glue (implemented in PureModeBridge.mm)

    /// Query a device's Pure-Mode capability + its advertised sample rates.
    ///
    /// @param deviceID     CoreAudio AudioDeviceID to query.
    /// @param outCap       Caller-allocated capability (scalar fields). Must be non-NULL.
    /// @param outRates     Caller-allocated rate array; may be NULL iff maxRates == 0.
    /// @param maxRates     Capacity of outRates.
    /// @param outRateCount Receives the number of rates written (clamped to maxRates). Non-NULL.
    /// @return             1 on success, 0 on failure.
    int pureModeQueryCapability(uint32_t deviceID,
                                CDeviceCapability* outCap,
                                double* outRates,
                                uint32_t maxRates,
                                uint32_t* outRateCount) AUDIODSP_C_NOEXCEPT;

    /// Create an opaque Pure-Mode engine session handle. Returns NULL on allocation failure.
    /// Destroy with pureModeEngineDestroy().
    void* pureModeEngineCreate(void) AUDIODSP_C_NOEXCEPT;

    /// Open `filePath`, query+evaluate `deviceID`, configure and start bit-perfect render.
    /// Resets the position counters to 0. Returns 1 on success, 0 on failure.
    int
    pureModeEngineStart(void* engine, uint32_t deviceID, const char* filePath) AUDIODSP_C_NOEXCEPT;

    /// Stop render, seek the source to `seconds`, restart render. Returns 1 on success, 0 on
    /// failure (the seek precondition — pullFloat not running — is satisfied internally).
    int pureModeEngineSeek(void* engine, double seconds) AUDIODSP_C_NOEXCEPT;

    /// Stop the engine (control-plane). Idempotent; NULL-safe.
    void pureModeEngineStop(void* engine) AUDIODSP_C_NOEXCEPT;

    /// Tear down the engine and free the handle. Idempotent + NULL-safe.
    void pureModeEngineDestroy(void* engine) AUDIODSP_C_NOEXCEPT;

    /// Snapshot the state the engine actually achieved (lock-free). Returns a zeroed struct for a
    /// NULL handle.
    CAchievedOutputState pureModeEngineAchievedState(void* engine) AUDIODSP_C_NOEXCEPT;

    /// Current playback position in seconds: (active-track seekBase + active-track renderedFrames)
    /// / active-track rate. RESTARTS at 0 at each gapless seam (position is per-track). Jumps on
    /// seek. Returns 0 when there is no source or rate.
    double pureModeEnginePositionSeconds(void* engine) AUDIODSP_C_NOEXCEPT;

    // MARK: Pure-path gapless (Stage 2)

    /// Pre-open `filePath` off-RT and arm it as the next track for a gapless seam at the current
    /// track's true end-of-file. Same-rate only: the bridge runs sameRateGaplessCompatible() vs
    /// the ACTIVE track first.
    /// @return 2 = armed (compatible, gapless seam ready);
    ///         1 = format/rate mismatch (caller should reconfigure for the next track itself);
    ///         0 = error (unreadable/unsupported file, already armed, or NULL handle/path).
    int pureModeEngineSetNextTrack(void* engine, const char* filePath) AUDIODSP_C_NOEXCEPT;

    /// Clear any armed next track (e.g. the user cleared the on-deck queue). Joins the dropped
    /// source off-RT. Idempotent; NULL-safe.
    void pureModeEngineClearNextTrack(void* engine) AUDIODSP_C_NOEXCEPT;

    /// Monotonic count of completed gapless seams. The view model polls this; an increase means
    /// the armed next track became the active track. ALSO reaps a seam-retired source off-RT
    /// (joins its decode thread) — so poll this regularly. Returns 0 for a NULL handle.
    uint64_t pureModeEnginePollTrackAdvance(void* engine) AUDIODSP_C_NOEXCEPT;

    /// 1 once the active track ended with no armed next track (playlist exhausted), else 0.
    /// Returns 0 for a NULL handle.
    int pureModeEnginePlaybackEnded(void* engine) AUDIODSP_C_NOEXCEPT;

    /// Set the device's hardware master volume (kAudioDevicePropertyVolumeScalar, output scope,
    /// 0..1, clamped). Hardware/analog-domain, so the rendered stream stays bit-perfect — this
    /// gives Pure Mode a working volume control WITHOUT exclusive hog mode. Returns 1 on success, 0
    /// if the device has no settable master volume (the caller treats that as "volume on device").
    int pureModeSetDeviceVolume(uint32_t deviceID, float scalar) AUDIODSP_C_NOEXCEPT;

#ifdef __cplusplus
} // extern "C"
#endif
