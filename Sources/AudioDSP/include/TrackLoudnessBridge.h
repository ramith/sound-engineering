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
// re-exported through DeviceBridge.h, the single Swift bridging header. Audio travels as
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

#ifdef __cplusplus
} // extern "C"
#endif
