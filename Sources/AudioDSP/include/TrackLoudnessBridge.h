#pragma once

//
// TrackLoudnessBridge.h — Pure C header: the track loudness profiler and the loudness-change
// predictor (Sprint EQ, EQ1c), for the Swift TrackLoudnessAnalyzer.
//
// The analyzer decodes a track a second time (AVAudioFile, off the RT path) and streams its PCM
// in; the profiler keeps the track's gated BS.1770 block spectra (Loudness/TrackLoudnessProfile.h).
// From a profile, the predictor returns how much louder (ΔL, dB) a 31-band EQ curve makes the
// track; the loudness-neutral EQ output gain is −ΔL (decision 26).
//
// LIFE CYCLE (one job per track):
//   p = asLoudnessProfilerCreate(rate, channels, layoutTag)
//   asLoudnessProfilerFeed(p, …) for the first ~20–30 s
//   prefix = asLoudnessProfilerFinishPrefix(p)   → publish; the stream continues
//   asLoudnessProfilerFeed(p, …) for the rest of the track
//   whole = asLoudnessProfilerFinishFull(p)      → publish; the stream has ended
//   asLoudnessProfilerDestroy(p)
// A profile handle is independent of its profiler (destroy either first) and immutable; it is
// released with asLoudnessProfileDestroy. The engine keeps its own reference to a published
// profile, so the caller may destroy its handle right after publishing.
//
// Must stay valid ISO C11 (no C++ namespaces, no <cstdint>, no class declarations): it is
// re-exported through DeviceBridge.h, the module's single Swift-visible header. Audio travels as
// (pointer, count) pairs in caller-owned buffers.
//
// THE TRUST BOUNDARY. Every call rejects NULL handles and pointers, wrong counts and non-finite
// input, returning false / NULL and writing nothing (a rejected feed consumes nothing).
//
// THREADS. A profiler is NOT thread-safe (one job owns it); every call is off the real-time thread.
// Profile handles may be read from any thread at once; asLoudnessPredictChangeDb also uses the
// caller's designer, which is single-owner (EQDesignBridge.h).
//

#include "CApiNoexcept.h"
#include "EQDesignBridge.h"
#include "TrackPlanBridge.h" // roles, the LFE variants, AsLfeStats (the analysis's seam, S1)
#include <CoreAudioTypes/CoreAudioBaseTypes.h>
#include <stdbool.h>
#include <stdint.h>

/// An opaque streaming profiler for one track. Create with asLoudnessProfilerCreate(); destroy
/// with asLoudnessProfilerDestroy().
typedef struct AsLoudnessProfiler AsLoudnessProfiler;

/// An opaque, immutable track loudness profile (a prefix or the whole track). Release with
/// asLoudnessProfileDestroy().
typedef struct AsLoudnessProfile AsLoudnessProfile;

/// A profile's metadata (asLoudnessProfileGetInfo).
typedef struct
{
    /// The decoded track's sample rate (Hz).
    double sampleRate;
    /// The audio fed before the profile was taken (seconds).
    double analysedSeconds;
    /// The source's own gated BS.1770 loudness over the profile's blocks (LUFS); −200 when no
    /// block passes the gates (silence).
    double sourceLoudnessLufs;
    uint32_t channelCount;
    /// 1/24-octave bands from DC to Nyquist (244 at 44.1 kHz, 295 at 192 kHz).
    uint32_t bandCount;
    /// The kept 400 ms blocks.
    uint32_t blockCount;
    /// 1 = a block every 100 ms; 2, 4, … once a long track was decimated to the 10-minute cap.
    uint32_t blockStrideHops;
    /// true for asLoudnessProfilerFinishFull's profile, false for a prefix.
    bool wholeTrack;
} AsLoudnessProfileInfo;

// MARK: - The one analysis pass (R1.1-B, level-and-fold §1.2 and §S1)
//
// Declared at lane 1's step 1 (the seam); defined by lane 1-B (the analyzer's step). The analysis is
// a separate object fed the ENGINE-RATE stream (after the engine's own Mastering converter, the
// file's own layout as its output format — F1), so every true peak is the one the limiter sees.
// It measures and decides nothing: the LFE rule and the plan read its numbers later.

// NOLINTBEGIN(cppcoreguidelines-use-enum-class,performance-enum-size,cppcoreguidelines-avoid-c-arrays,modernize-avoid-c-arrays) PERMANENT reason="ISO C11 ABI header, Swift-visible: C has no enum class, no sized enum and no std::array"

enum
{
    /// The analysis's form. Bump on: the fold coefficients, the LFE variant set, the LFE statistics'
    /// definition, the peak kernels or their rate, the SRC or its output format, K-weighting, the
    /// gates, the histogram or profile form, the role numbering, the role resolver, the count
    /// fallbacks. NOT on a decision threshold (those are the planner's and the LFE rule's).
    AS_TRACK_ANALYSIS_VERSION = 1,
    /// The bases a compact −ΔL profile is kept for: 0 = as decoded (N channels), 1 + v = the fold
    /// at LFE variant v.
    AS_PROFILE_BASES = 1 + AS_FOLD_LFE_VARIANTS,
};

/// An opaque analysis of one track. Create with asTrackAnalyzerCreate(); destroy with
/// asTrackAnalyzerDestroy().
typedef struct AsTrackAnalyzer AsTrackAnalyzer;

/// What the analysis measured. NaN = not measured (no gated block, or no fold).
typedef struct
{
    uint32_t version;               ///< AS_TRACK_ANALYSIS_VERSION
    uint32_t channelCount;          ///< N
    uint8_t roles[AS_MAX_CHANNELS]; ///< AsChannelRole per slot, as fed to asTrackAnalyzerCreate
    double sourceRateHz;            ///< the file's own rate
    double peakRateHz;              ///< the rate the true peaks were measured at (the engine's)
    double durationSeconds;
    /// L_N (BS.1770-5 gated, Table 3 weights, LFE 0) and TP_N (max over all N channels, the LFE
    /// included; max of the shipped 8×24 and an 8×64 kernel).
    double integratedLufs;
    double truePeakDbtp;
    /// The first and last whole 400 ms block (N-channel weights), for the continuity judge.
    double headBlockLufs;
    double tailBlockLufs;
    /// 1: N > 2 and the fold was measured (foldedLufs / foldedTruePeakDbtp below).
    uint8_t folds;
    double foldedLufs[AS_FOLD_LFE_VARIANTS];
    double foldedTruePeakDbtp[AS_FOLD_LFE_VARIANTS];
    AsLfeStats lfe;
} AsTrackAnalysis;

/// One non-empty bin of a gated-loudness histogram, in LufsMeter's form: 0.1 LU bins from
/// −70 LUFS (bin b's centre is −70 + 0.1·(b + 0.5) LUFS), each with its block count and the exact sum
/// of their energies.
typedef struct
{
    uint32_t bin;
    uint32_t count;
    double energy;
} AsLoudnessBin;

/// A compact −ΔL profile's shape (C2): 1/bandsPerOctave-octave bands from a 20 Hz first edge to
/// Nyquist at `sampleRate`, one row per kept 400 ms block, each band's K-weighted, channel-weighted
/// mean-square power as an IEEE-754 binary16 bit pattern, block-major (bandCount values per block).
typedef struct
{
    double sampleRate;       ///< the analysis's rate (the engine's)
    uint32_t bandsPerOctave; ///< 12
    uint32_t bandCount;
    uint32_t blockCount;
    uint32_t
        blockStrideHops; ///< kept block j starts at j·blockStrideHops·100 ms (4: non-overlapping)
} AsCompactProfileInfo;

// NOLINTEND(cppcoreguidelines-use-enum-class,performance-enum-size,cppcoreguidelines-avoid-c-arrays,modernize-avoid-c-arrays)

#ifdef __cplusplus
extern "C"
{
#endif

    /// Create a profiler for a decoded stream.
    ///
    /// @param sampleRate    The decoded rate (Hz): finite, within [8 kHz, 192 kHz].
    /// @param channelCount  1 … 8.
    /// @param layoutTag     The source's AudioChannelLayoutTag, for the BS.1770-5 channel weights
    ///                      (L/R/C 1.0, surrounds 1.41, LFE 0). A tag the decoder does not know, or
    ///                      one whose channel count differs from `channelCount`, weights every
    ///                      channel 1.0 (the neutral fallback).
    /// @return A profiler, or NULL on an invalid rate or channel count, or a failed setup.
    AsLoudnessProfiler*
    asLoudnessProfilerCreate(double sampleRate,
                             uint32_t channelCount,
                             AudioChannelLayoutTag layoutTag) AUDIODSP_C_NOEXCEPT;

    /// Feed the next chunk of PCM, planar float32 (AVAudioPCMBuffer.floatChannelData).
    ///
    /// @param channels      `channelCount` pointers, each to `frameCount` samples.
    /// @param channelCount  Must equal the profiler's channel count.
    /// @param frameCount    The frames in this chunk; 0 is a valid no-op.
    /// @return true when consumed. false — consuming nothing — on a NULL profiler, channels array
    ///         or channel pointer; a channel-count mismatch; any non-finite sample; or a stream
    ///         already ended by asLoudnessProfilerFinishFull.
    bool asLoudnessProfilerFeed(AsLoudnessProfiler* profiler,
                                const float* const* channels,
                                uint32_t channelCount,
                                uint32_t frameCount) AUDIODSP_C_NOEXCEPT;

    /// The prefix profile: the 400 ms blocks analysed so far. The stream continues.
    ///
    /// @return A new profile handle, or NULL on a NULL profiler, before the first whole 400 ms
    ///         block, or after asLoudnessProfilerFinishFull.
    AsLoudnessProfile*
    asLoudnessProfilerFinishPrefix(AsLoudnessProfiler* profiler) AUDIODSP_C_NOEXCEPT;

    /// The whole-track profile. Ends the stream: later feeds are rejected. A trailing part-block
    /// shorter than 400 ms is dropped, as BS.1770 does.
    ///
    /// @return A new profile handle, or NULL on a NULL profiler, a track with no whole 400 ms block,
    ///         or a second call.
    AsLoudnessProfile*
    asLoudnessProfilerFinishFull(AsLoudnessProfiler* profiler) AUDIODSP_C_NOEXCEPT;

    /// Destroy a profiler from asLoudnessProfilerCreate(). NULL-safe. Profiles it produced stay
    /// valid.
    void asLoudnessProfilerDestroy(AsLoudnessProfiler* profiler) AUDIODSP_C_NOEXCEPT;

    /// Release a profile handle. NULL-safe.
    void asLoudnessProfileDestroy(AsLoudnessProfile* profile) AUDIODSP_C_NOEXCEPT;

    /// Read a profile's metadata.
    ///
    /// @return true when written; false — writing nothing — on a NULL profile or info.
    bool asLoudnessProfileGetInfo(const AsLoudnessProfile* profile,
                                  AsLoudnessProfileInfo* info) AUDIODSP_C_NOEXCEPT;

    /// Predict the loudness change ΔL (dB) a 31-point EQ curve makes on the profiled track, as the
    /// engine would play it: the curve designed by `designer` at the OUTPUT rate, its played
    /// response read back on the profile's 1/24-octave grid (bands at or above the output's Nyquist
    /// are not played), and the real two-stage BS.1770 gating on the predicted blocks. The
    /// loudness-neutral EQ output gain is −ΔL.
    ///
    /// @param profile           From asLoudnessProfilerFinishPrefix / FinishFull.
    /// @param designer          The caller's designer (asEqDesignerCreate); its per-rate tables are
    ///                          reused.
    /// @param pointsDb          `pointCount` target points (dB); beyond ±12 dB they clamp to ±12.
    /// @param pointCount        Must be exactly 31.
    /// @param outputSampleRate  The rate the EQ plays at (Hz); within [44 kHz, 768 kHz].
    /// @param changeDb          Receives ΔL.
    /// @return true when written. false — writing nothing — on a NULL argument, a pointCount other
    ///         than 31, a non-finite point, an output rate outside the designer's domain, or a
    ///         profile in which nothing passes the BS.1770 gates (silence).
    bool asLoudnessPredictChangeDb(const AsLoudnessProfile* profile,
                                   AsEqDesigner* designer,
                                   const float* pointsDb,
                                   uint32_t pointCount,
                                   double outputSampleRate,
                                   double* changeDb) AUDIODSP_C_NOEXCEPT;

    // MARK: The one analysis pass (lane 1-B defines these)

    /// Create an analysis of a stream at the engine's rate.
    ///
    /// @param engineRateHz  The stream's rate (the engine's: 48 kHz).
    /// @param channels      N, 1…8.
    /// @param roles         `channels` AsChannelRole values (asResolveChannelRoles).
    /// @return An analysis, or NULL on an invalid rate, count or roles.
    AsTrackAnalyzer* asTrackAnalyzerCreate(double engineRateHz,
                                           uint32_t channels,
                                           const uint8_t* roles) AUDIODSP_C_NOEXCEPT;

    /// Feed the next chunk, planar float32, at the engine's rate.
    /// @return true when consumed; false — consuming nothing — on a NULL argument, a count
    ///         mismatch, a non-finite sample or a finished analysis.
    bool asTrackAnalyzerFeed(AsTrackAnalyzer* analyzer,
                             const float* const* channels,
                             uint32_t channelCount,
                             uint32_t frames) AUDIODSP_C_NOEXCEPT;

    /// End the stream and write what was measured. Measures; decides nothing.
    /// @return true when written; false — writing nothing — on a NULL argument or a second call.
    bool asTrackAnalyzerFinish(AsTrackAnalyzer* analyzer, AsTrackAnalysis* out) AUDIODSP_C_NOEXCEPT;

    /// The gated-loudness histogram of `variant` (0 = as decoded, 1 + v = the fold at v — the
    /// AS_PROFILE_BASES numbering), after asTrackAnalyzerFinish.
    /// @return The bins required. Nothing is written when `capacity` is short (architect N10).
    uint32_t asTrackAnalyzerHistogram(const AsTrackAnalyzer* analyzer,
                                      uint8_t variant,
                                      AsLoudnessBin* out,
                                      uint32_t capacity) AUDIODSP_C_NOEXCEPT;

    /// The compact −ΔL profile of `basis` (AS_PROFILE_BASES numbering), after asTrackAnalyzerFinish.
    /// @return The values required (blockCount × bandCount). Nothing is written when `capacity` is
    ///         short.
    uint32_t asTrackAnalyzerProfile(const AsTrackAnalyzer* analyzer,
                                    uint8_t basis,
                                    uint16_t* out,
                                    uint32_t capacity) AUDIODSP_C_NOEXCEPT;

    /// The shape of `basis`'s compact profile, after asTrackAnalyzerFinish.
    /// @return true when written.
    bool asTrackAnalyzerProfileInfo(const AsTrackAnalyzer* analyzer,
                                    uint8_t basis,
                                    AsCompactProfileInfo* info) AUDIODSP_C_NOEXCEPT;

    /// Destroy an analysis. NULL-safe.
    void asTrackAnalyzerDestroy(AsTrackAnalyzer* analyzer) AUDIODSP_C_NOEXCEPT;

    /// Pool `members` histograms into one BS.1770 gated loudness (the album's pooled anchor, P2):
    /// histogram i is `counts[i]` bins at `histograms[i]`. The gate math, once, in C++.
    /// @return The pooled loudness (LUFS); NaN when no block passes the gates or on a NULL argument.
    double asLoudnessPoolHistograms(const AsLoudnessBin* const* histograms,
                                    const uint32_t* counts,
                                    uint32_t members) AUDIODSP_C_NOEXCEPT;

    /// Rebuild a whole-track profile from a persisted compact one (C2: the saved −ΔL profile travels
    /// with the start or on-deck request, so a fresh start of an analysed track never glides).
    /// @return A new profile handle (release with asLoudnessProfileDestroy), or NULL on a NULL
    ///         argument, a `count` other than blockCount × bandCount, or a shape the predictor does
    ///         not support.
    AsLoudnessProfile* asLoudnessProfileFromCompact(const AsCompactProfileInfo* info,
                                                    const uint16_t* powers,
                                                    uint32_t count) AUDIODSP_C_NOEXCEPT;

#ifdef __cplusplus
} // extern "C"
#endif
