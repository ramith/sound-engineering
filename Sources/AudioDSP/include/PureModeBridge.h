#pragma once

//
// PureModeBridge.h — Pure C header bridging the "Pure Mode" (bit-perfect HAL output) C++ layer
// to Swift.
//
// This header reaches Swift through DeviceBridge.h (`import AudioDSP`) and MUST be valid
// ISO C11 (no C++ namespaces, no #include <cstdint>, no class declarations). It declares flat
// POD structs plus the C-ABI Pure-Mode policy + engine functions.
//
// Two implementation files back this surface:
//   * PureModeBridgePolicy.cpp — CoreAudio-FREE; implements ONLY pureModeEvaluate(). Compiles into
//     the C++ test harness (which links no CoreAudio).
//   * PureModeBridge.cpp       — CoreAudio glue for capability querying + the engine.
//
// Opaque-handle convention (mirrors DeviceBridge.h): the engine is owned through a void* handle;
// the caller creates it with pureModeEngineCreate() and destroys it with pureModeEngineDestroy()
// (NULL-safe). All structs are plain-old-data; uint8_t stands in for bool to keep the ABI fixed.
//

#include "CApiNoexcept.h"
#include <stdint.h>

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
/// 2 FallbackEnhanced.
///
/// THE REASON CODES (AdaptiveSound::PureModeReason, the one named reason — council C-34; Swift's
/// PureModeReason decodes the same numbers; append, never reorder):
///   0 BitPerfectInteger        Pure plays, integer PCM at the file's rate
///   1 RateMatchedFloatNoSRC    Pure plays, float at the file's rate (no SRC)
///   2 LossyWirelessCodec       declined: Bluetooth / AirPlay re-encode below the HAL
///   3 VirtualDevice            declined: a virtual or aggregate device
///   4 RateUnsupportedResample  declined: the device can't run at the file's rate
///   5 ChannelCountMismatch     declined: the device stream's channel count is not the file's
///   6 DeviceShallowerThanSource Pure plays, NOT bit-perfect: the output holds fewer bits (C-33)
///   7 DeviceWouldNotStart      declined: the device would not take Pure's format, or start
///   8 FileUnreadable           declined: no decoder that may run can read the file
///   9 FileNeedsFFmpeg          declined: Apple's decoder can't read it, and FFmpeg is off
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
    uint8_t reason;                  ///< 0, 1 or 6 (the reason codes above): bit-perfect, or not
    uint32_t sourceBitsPerChannel;   ///< the active track's source depth (0: compressed / unknown)
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

    /// Evaluate the Pure-Mode policy for `filePath` on `deviceID` as a start would: the file read
    /// by Pure's own decoder (Apple first; FFmpeg only when it is on — FileDecodeSource::probe),
    /// without starting a decode, and the device's capability queried. A file no decoder may read
    /// comes back FallbackEnhanced with reason 8 or 9. Returns 1 when `out` is filled, 0 on NULL
    /// arguments. Control plane (it opens the file and queries the HAL).
    int pureModeEvaluateFile(uint32_t deviceID,
                             const char* filePath,
                             CPureModeEvaluation* out) AUDIODSP_C_NOEXCEPT;

    /// Create an opaque Pure-Mode engine session handle. Returns NULL on allocation failure.
    /// Destroy with pureModeEngineDestroy().
    void* pureModeEngineCreate(void) AUDIODSP_C_NOEXCEPT;

    /// Open `filePath`, query+evaluate `deviceID`, configure and start bit-perfect render from
    /// `startSeconds` into the file (0 = the top): the source is positioned BEFORE render starts, so
    /// a resume is never a play-from-0-then-seek. The position counters report from there. Returns
    /// 1 on success, 0 on failure. `outReason` (may be NULL) receives the reason code: on failure
    /// why it declined (2–5, 7–9), on success the reason it plays as (0 or 1; the achieved state
    /// refines it to 6 when the device holds fewer bits than the file).
    int pureModeEngineStart(void* engine,
                            uint32_t deviceID,
                            const char* filePath,
                            double startSeconds,
                            uint8_t* outReason) AUDIODSP_C_NOEXCEPT;

    /// Hold render (silence; the device keeps running), seek the active track to `seconds`,
    /// release render. Returns 1 on success; 0 when the decoder could not reposition, or the
    /// render would not go quiet (then nothing moved and playback carries on where it was).
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

    /// Open `filePath` into a decode source OFF any caller lock — this is the potentially slow /
    /// network file open (S3 F3: it no longer runs under the engine's leaf lock). Returns an opaque
    /// decoder handle to hand to pureModeEngineArmOpenedNextTrack, or NULL on open failure
    /// (unreadable / unsupported / NULL path). If it is never armed, free it with
    /// pureModeDestroyDecodeSource.
    void* pureModeOpenDecodeSource(const char* filePath) AUDIODSP_C_NOEXCEPT;

    /// Arm a PRE-OPENED decoder (from pureModeOpenDecodeSource) as the next track for a gapless seam
    /// at the current track's true end-of-file. TAKES OWNERSHIP of `decoder` on every outcome — it is
    /// either moved into the engine (armed) or destroyed here — so the caller must NOT free it
    /// afterwards. Only the fast checks + pointer-swap arm run here (the open already ran outside
    /// any lock). NULL-safe.
    ///
    /// Arming never replaces: the caller takes the old pick off first (pureModeEngineClearNextTrack,
    /// on the same serial queue), so the slot is empty here. The end is final: once the current
    /// track ended with nothing armed, nothing arms behind it. Same-rate only: runs
    /// sameRateGaplessCompatible() vs the ACTIVE track.
    /// @return 2 = armed (compatible, gapless seam ready);
    ///         1 = format/rate mismatch (not armed: the track plays after a fresh start);
    ///         3 = the current track already ended (not armed: it plays after a fresh start);
    ///         0 = error (NULL handle/decoder, no active track, a seam the render claimed and did
    ///             not publish in time, or the slot was occupied — a caller bug, asserted in DEBUG).
    int pureModeEngineArmOpenedNextTrack(void* engine, void* decoder) AUDIODSP_C_NOEXCEPT;

    /// Destroy a decoder from pureModeOpenDecodeSource that was NEVER handed to
    /// pureModeEngineArmOpenedNextTrack (e.g. the engine was torn down before arming). Joins the
    /// decode thread off-RT. Idempotent; NULL-safe. Do NOT call after a successful arm.
    void pureModeDestroyDecodeSource(void* decoder) AUDIODSP_C_NOEXCEPT;

    /// Take any armed next track off the slot (the user changed or cleared the pick). An exactly-once
    /// exchange with the render's seam claim: the armed track either already became current or never
    /// will. Joins the dropped source off-RT. Idempotent; NULL-safe.
    void pureModeEngineClearNextTrack(void* engine) AUDIODSP_C_NOEXCEPT;

    /// Monotonic count of completed gapless seams. The view model polls this; an increase means
    /// the armed next track became the active track. ALSO reaps a seam-retired source off-RT
    /// (joins its decode thread) — so poll this regularly. Returns 0 for a NULL handle.
    uint64_t pureModeEnginePollTrackAdvance(void* engine) AUDIODSP_C_NOEXCEPT;

    /// 1 once the active track ended with no armed next track (playlist exhausted), else 0.
    /// Returns 0 for a NULL handle.
    int pureModeEnginePlaybackEnded(void* engine) AUDIODSP_C_NOEXCEPT;

#ifdef __cplusplus
} // extern "C"
#endif
