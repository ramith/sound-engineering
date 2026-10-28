#pragma once

//
// TrackPlanBridge.h — Pure C header: the leveling plan's seam (R1.1-B; the level-and-fold design,
// docs/design/level-and-fold/README.md §1.3, §5 and §8 S1b / S3).
//
// What one track's leveling needs, end to end:
//   - the channel ROLES of a file, from its labels (never from its position), numbered once and
//     for all here: they are persisted with every analysis;
//   - the LFE VARIANTS the analysis measures the fold at, and their per-side gains;
//   - the LFE STATISTICS the analysis keeps, from which the LFE rule decides at plan time;
//   - the OUTPUT STATE the planner plans against: the transport (the view model's hand-over),
//     the engine's rate, the file's width N and roles, the output's width M;
//   - the DECISION (the app's, scope-resolved: measured numbers only) and the PLAN (what the
//     planner makes of it: the leveling gain g, the protected peak P, the working ceiling, the
//     fold's trim), and the PLANNER itself: one pure function, called once per audibility (B1),
//     whose one value goes to both audio units in the same turn.
//
// Must stay valid ISO C11 (no C++ namespaces, no <cstdint>, no class declarations): it is
// re-exported through AudioUnitRegistrationBridge.h and TrackLoudnessBridge.h, both reached from
// DeviceBridge.h, the module's single Swift-visible header. C++ code includes it too: the role
// numbers and the variant table are tied to their C++ forms by static_asserts (ChannelLayout.h,
// Spatial/FoldMatrix.h).
//
// THREADS. Every function here is pure (no state) and may be called from any thread.
//

#include "CApiNoexcept.h"
#include <CoreAudioTypes/CoreAudioBaseTypes.h> // AudioChannelLayout (pure C)
#include <stdbool.h>
#include <stdint.h>

// NOLINTBEGIN(cppcoreguidelines-use-enum-class,performance-enum-size,cppcoreguidelines-avoid-c-arrays,modernize-avoid-c-arrays) PERMANENT reason="ISO C11 ABI header, Swift-visible: C has no enum class, no sized enum and no std::array"

enum
{
    /// The plan's form (AsTrackPlan). Bump when a field's meaning changes.
    AS_TRACK_PLAN_VERSION = 1,
    /// The widest file the pipeline plays (7.1); every per-channel array here has this many slots.
    AS_MAX_CHANNELS = 8,
    /// The LFE variants the analysis measures the fold at, and the planner can choose from.
    AS_FOLD_LFE_VARIANTS = 4,
};

// MARK: - Channel roles (S1b, M3)

/// A channel's role, from its label. The numbers are FIXED: they are persisted with every analysis
/// (a change is an AS_TRACK_ANALYSIS_VERSION bump). Stored as uint8_t.
typedef enum
{
    AsChannelRoleUnknown = 0, ///< no label, or one the fold does not know
    AsChannelRoleL = 1,       ///< front left
    AsChannelRoleR = 2,       ///< front right
    AsChannelRoleC = 3,       ///< centre
    AsChannelRoleLfe = 4,     ///< low-frequency effects (".1")
    AsChannelRoleLs = 5,      ///< left surround (side)
    AsChannelRoleRs = 6,      ///< right surround (side)
    AsChannelRoleLb = 7,      ///< left back (rear surround: Rls, "back left")
    AsChannelRoleRb = 8,      ///< right back
    AsChannelRoleCs = 9,      ///< centre surround (back centre)
    AsChannelRoleLc = 10,     ///< left of centre
    AsChannelRoleRc = 11,     ///< right of centre
    AsChannelRoleLw = 12,     ///< left wide
    AsChannelRoleRw = 13,     ///< right wide
    AsChannelRoleMono = 14,   ///< a one-channel file's channel
} AsChannelRole;

// MARK: - The fold's LFE variants (§5)

/// The per-side LFE gains the fold is measured and played at (BS.775-4 Annex 7, Fig. 5): omitted;
/// the music-disc convention (−6 dB per side); full; the film convention (+4 dB per side). The
/// include level is the founder's choice; every variant is measured, so none needs a re-analysis.
typedef enum
{
    AsLfeVariantOmit = 0,  ///< 0
    AsLfeVariantMusic = 1, ///< 0.5 (−6 dB)
    AsLfeVariantFull = 2,  ///< 1.0
    AsLfeVariantFilm = 3,  ///< 10^(4/20) ≈ 1.585 (+4 dB)
} AsLfeVariant;

/// The LFE statistics the analysis keeps (§5; C2 adds the 90th-percentile r²). All on the LFE's
/// and the mains' 20–120 Hz band at 500 Hz, in 400 ms blocks with a 100 ms hop, over the ACTIVE
/// blocks (LFE band ≥ −50 dBFS). The LFE rule (lane 2's FoldLfeRule) decides from these at plan
/// time, so its thresholds tune without a re-analysis. A change to any definition here is an
/// AS_TRACK_ANALYSIS_VERSION bump.
typedef struct
{
    /// The active blocks; under 50 (5 s) the rule omits the LFE (unknown).
    uint32_t activeBlocks;
    /// The best lag of the LFE against the mains' sum, global normalised cross-correlation over
    /// ±200 ms (ms; positive: the LFE lags).
    float lagMs;
    /// |that correlation| at lagMs, 0…1.
    float lagPeak;
    /// The share of active blocks whose r² ≥ 0.8. r² is the squared correlation of the LFE with
    /// its least-squares prediction from the mains (one FIR per main, ±20 ms, centred on lagMs):
    /// scale-invariant, so automated sends and compressed copies still match.
    float coherentShare;
    /// The median r² over the active blocks.
    float medianR2;
    /// The 90th-percentile r² over the active blocks (separates a kick-stem copy down to a kick
    /// 6 dB under the bass — verify pass, C4).
    float p90R2;
    /// The share of active blocks whose unexplained LFE power P_LFE·(1 − r²) is ≥ the mains'
    /// low-band power − 20 dB.
    float excess20Share;
    /// Max over the 25–63 Hz third-octaves of the prediction's power over the mains' plain sum
    /// (dB): a copy stays near 0 dB whatever its filter or delay; a fit that must invert an
    /// authoring high-pass (bass moved into the LFE) reads +38 dB or more.
    float explainGainDb;
} AsLfeStats;

// MARK: - The output state (M2)

/// What the planner plans against — the one output state, assembled on the engine queue when the
/// graph is configured for a file and at every re-establish (lane 2), with the transport the view
/// model hands over as a value (`AudioPlaybackEngine.publishOutputTransport`).
typedef struct
{
    /// The output's kAudioDevicePropertyTransportType FourCC; 0 = unknown. It sets the ceiling:
    /// −0.1 dBTP on a local lossless link, −1 dBTP otherwise (Limiting/OutputCeiling.h).
    uint32_t transportType;
    /// The rate the effects kernel and its limiter run at (the graph's; 48 kHz). A true peak
    /// measured at another rate is not the limiter's (the planner treats it as unknown).
    double engineRateHz;
    /// N: the playing file's channel count (the effects unit's width), 1…8.
    uint32_t sourceChannels;
    /// M: the spatial unit's output width (the device boundary), 1…8. M < N with N > 2 folds to
    /// stereo (C1: never a truncation).
    uint32_t outputChannels;
    /// The playing file's channel roles (AsChannelRole, from asResolveChannelRoles); Unknown
    /// beyond N. The fold numbers of a decision are used only if its roles equal these.
    uint8_t sourceRoles[AS_MAX_CHANNELS];
} AsOutputState;

// MARK: - The decision (S3) and the plan (§1.3)

/// What the app decided for a track (TrackLevelingDecision's C mirror).
typedef enum
{
    AsLevelingModeOff = 0, ///< no leveling gain (g = 0); the fold's trim and the cap still apply
    AsLevelingModeLeveled = 1,    ///< level to −18 LUFS from the numbers
    AsLevelingModeUnknownCut = 2, ///< the loudness is unknown: the fixed −5 dB rule
} AsLevelingMode;

/// Where a decision's numbers came from (diagnostics; the planner reads the numbers, not this).
typedef enum
{
    AsLevelingSourceAnalysis = 0,
    AsLevelingSourceTags = 1,
    AsLevelingSourceUnknownCut = 2,
} AsLevelingSource;

/// The decision's numbers, already resolved to their scope by the app (the track's own, or its
/// group's or album's anchor and maxima — LevelingKit's job): measured numbers only, no ceiling
/// rule. NaN = unknown.
typedef struct
{
    uint8_t mode;   ///< AsLevelingMode
    uint8_t source; ///< AsLevelingSource
    uint8_t
        continuousWithPrevious; ///< 1: the one continuity judge says this track continues the last
    uint8_t lfeVariant;         ///< AsLfeVariant: the fold's LFE gain (a group shares one)
    uint8_t hasFolded;          ///< 1: foldedLufs / foldedTruePeakDbtp hold measurements
    uint8_t channelCount;       ///< the channels `roles` describes, 0…8
    uint8_t roles[AS_MAX_CHANNELS]; ///< the roles the numbers were measured with (AsChannelRole)
    /// The rate the true peaks were measured at (the analysis runs at the engine's rate); 0 when
    /// not known (a tag's peak).
    double peakRateHz;
    /// L: integrated loudness, BS.1770 Table 3 weights (LFE 0), as decoded (LUFS). A mono file's is
    /// as measured on its one channel: the planner adds +3.01 LU when it plays to ≥ 2 outputs.
    double loudnessLufs;
    /// TP_N: the true peak over all N channels, the LFE included (dBTP).
    double truePeakDbtp;
    /// L_F[v] and TP_F[v]: the same on the BS.775 stereo fold, one per LFE variant.
    double foldedLufs[AS_FOLD_LFE_VARIANTS];
    double foldedTruePeakDbtp[AS_FOLD_LFE_VARIANTS];
} AsTrackLeveling;

/// The plan for one track: what the level stage (the effects unit) and the fold (the spatial unit)
/// apply, frozen at audibility. One value; both units get it in the same turn.
typedef struct
{
    uint32_t version;   ///< AS_TRACK_PLAN_VERSION
    uint8_t mode;       ///< AsLevelingMode as planned (Off when there was no decision)
    uint8_t folds;      ///< 1: the spatial unit folds N → stereo (N > 2 and M < N)
    uint8_t lfeVariant; ///< AsLfeVariant the fold plays
    uint8_t
        foldFromAnalysis; ///< 1: the trim came from the measured fold; 0: the matrix's worst case
    /// g: the leveling gain the effects unit applies (dB). 0 when Off.
    double levelGainDb;
    /// P: the peak the level stage protects, before g (dBTP): max(TP_N, the fold's peak after the
    /// trim). Unknown true peaks count as 0 dBTP.
    double peakDbtp;
    /// C_work: the working ceiling the plan holds the peaks under (dBTP), from the transport.
    double workingCeilingDbtp;
    /// The fold's trim (dB, ≤ 0): 0 unless `folds`.
    double foldTrimDb;
    /// The fold's per-side LFE gain (linear) for `lfeVariant`.
    double lfeGainLinear;
    /// L as planned (LUFS): after the trim, +3.01 LU for mono on ≥ 2 outputs; NaN = unknown.
    double loudnessLufs;
} AsTrackPlan;

/// Why a plan is delivered — how the units move to it.
typedef enum
{
    AsPlanEventFreshStart = 0, ///< a new token became audible by a start: the gain snaps (N4)
    AsPlanEventGaplessSeam =
        1, ///< a new token (or the same one, Repeat One) became audible at a seam: 10 ms glide
    AsPlanEventModeChange = 2, ///< the listener changed the Leveling mode: 0.15 s glide
    AsPlanEventOutputChange =
        3, ///< the output changed at a re-establish: the protective re-plan (F5)
} AsPlanEvent;

// NOLINTEND(cppcoreguidelines-use-enum-class,performance-enum-size,cppcoreguidelines-avoid-c-arrays,modernize-avoid-c-arrays)

#ifdef __cplusplus
extern "C"
{
#endif

    /// The per-side gain (linear) of LFE variant `variant`; 0 for a variant out of range.
    float asLfeVariantGain(uint8_t variant) AUDIODSP_C_NOEXCEPT;

    /// Resolve the roles of a file's channels from its layout (S1b): from the labels — a tag's, a
    /// bitmap's or each channel description's — never from position; without labels, from the
    /// count (RFC 9639: 1 Mono; 2 L R; 3 L R C; 4 L R Lb Rb; 5 L R C Lb Rb; 6 L R C Lfe Lb Rb;
    /// 7 L R C Lfe Cs Ls Rs; 8 L R C Lfe Lb Rb Ls Rs — WAV order). Called once per file by the one
    /// Swift resolver (AudioFormatKit's ChannelRoles); its result goes by value to the analysis,
    /// the effects unit and the planner.
    ///
    /// Declared at lane 1's step 1; defined by lane 1-B (the resolver's step).
    ///
    /// @param layout    The file's AudioChannelLayout, or NULL (no layout: the count fallback).
    /// @param channels  The file's channel count, 1…8.
    /// @param roles     Receives `channels` AsChannelRole values.
    /// @return true when written; false — writing nothing — on a NULL `roles` or a count out of range.
    bool asResolveChannelRoles(const AudioChannelLayout* layout,
                               uint32_t channels,
                               uint8_t* roles) AUDIODSP_C_NOEXCEPT;

    /// The plan for one track (§1.3; B1): pure, called once per audibility by the playback bridge.
    ///
    ///   TP      = unknown, or measured at a rate other than the engine's → 0 dBTP (raised to a
    ///             known peak above full scale)
    ///   C_work  = 20·log10(ceiling × the limiter's ISP margin) − 0.01 dB, the ceiling from the
    ///             transport
    ///   fold    = N > 2 and M < N (mono: no fold; L += 3.01 LU when M ≥ 2)
    ///   trim    = fold ? min(0, C_work − TP_F[v]) : 0 — the measured fold when the decision's
    ///             roles equal the output's, else the matrix's worst case
    ///   P       = max(TP_N, fold ? TP_F[v] + trim : −∞)
    ///   L       = (fold ? L_F[v] : L_N) + trim
    ///   g       = Off → 0; unknown loudness → min(0, −5 − trim, C_work − P when TP is known);
    ///             else min(−18 − L, C_work − P, +12)
    ///
    /// @param decision  The track's decision; NULL = none at audibility (a bug state): Off with the
    ///                  matrix's worst-case trim.
    /// @param output    The output state; NULL plans against an unknown stereo output.
    /// @param frozen    NULL for a new play or a mode change. The playing plan for a protective
    ///                  re-plan at an output change (F5): g and the LFE variant are kept, and
    ///                  trim′ = min(0, C_work′ − (TP_F[v] + g)), P′ = max(TP_N, TP_F[v] + trim′).
    /// @return The plan (version AS_TRACK_PLAN_VERSION).
    AsTrackPlan asPlanTrack(const AsTrackLeveling* decision,
                            const AsOutputState* output,
                            const AsTrackPlan* frozen) AUDIODSP_C_NOEXCEPT;

#ifdef __cplusplus
} // extern "C"
#endif
