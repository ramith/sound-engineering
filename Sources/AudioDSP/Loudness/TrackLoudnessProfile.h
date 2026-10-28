#pragma once

// TrackLoudnessProfile.h — a track's gated block spectra, and the loudness-change predictor that
// makes the EQ loudness-neutral (Sprint EQ, EQ1c; decision 26; engine-plan §4, amendments item 3).
//
// THE PROFILE. For every ITU-R BS.1770-5 gating block (400 ms, a new block every 100 ms, 75 %
// overlap) it keeps the K-weighted, channel-weighted mean-square power of the source in 1/24-octave
// bands from DC to Nyquist. A block's bands sum to its BS.1770 block energy z_j exactly (Parseval;
// the block FFT is rectangular — see TrackLoudnessProfiler.h, "the port rule"), so the profile
// carries the source's gated loudness AND, for any EQ curve, the EQ'd loudness:
//
//   z_j(H) = Σ_b P_j(b)·|H(f_b)|²        (f_b = band b's centre)
//   L(H)   = −0.691 + 10·log10(mean of z_j(H) over the blocks that pass BS.1770's gates)
//   ΔL     = L(H) − L(1)                 the loudness-neutral EQ output gain is −ΔL
//
// The gates are the real two-stage BS.1770 ones, applied to each predicted block set separately:
// absolute (l_j > −70 LUFS), then relative (l_j > the absolute-gated loudness − 10 LU). That is
// what makes the prediction exact for gating; an ungated long-term spectrum misses by up to 0.73 dB
// (review-sota §5). Measured: ≤ 0.112 dB against the BS.1770 change of the actually filtered track
// on the 7-track corpus (engine-plan §4.1, s4b).
//
// THE BAND GRID, a field of the profile (bandsPerOctave = B; R1.1-B §13.3). Band 0 is [0, 20 Hz). Band
// b ≥ 1 is [e_{b−1}, e_b) with edges e_i = 20·2^(i/B), every edge below Nyquist; the last band runs to
// Nyquist inclusive. The centre of band b is the geometric mean of its edges (the lower edge floored at
// 10 Hz): 14.1 Hz for band 0. The profiler's grid is 1/24 octave (B = 24): 244 bands at 44.1 kHz, 247 at
// 48 kHz, 295 at 192 kHz. (The Python oracle stops its edges at 20·2^(263/24) ≈ 39.8 kHz; above 88.2 kHz
// the grid here continues to Nyquist instead of lumping one wide top band.) A 1/12-octave grid (B = 12; 124
// bands at 48 kHz) is supported too, for a persisted profile at half the size; it is not used: on tonal
// programmes its band centres miss the curve by 0.05–0.10 dB of ΔL (lane 1-B's measurement). The analysis
// pass persists its profile on this 1/24 grid as binary16 (compactPowers / profileFromCompact below).
//
// THE LIMITS (amendment 19). The predictor reads each band's energy at the band's CENTRE, on a
// 1/24-octave grid whose low bands are narrower than the 400 ms block's 2.5 Hz FFT bins. Where a
// programme's energy sits in a few places at which the curve changes fast, the centre's response is
// not the one the energy meets — the break-it's finding 10, and EqEngineFixTests.inc's sweep:
//   - a sustained low sine (20–75 Hz) under a jagged ±12 curve or a ±12 bass point: up to 8.2 dB;
//   - DC and sub-20 Hz rumble (band 0 is all of 0–20 Hz) under a bass boost or cut: up to 2.8 dB;
//   - a tone near Nyquist (21.5 kHz at 44.1 kHz) under ±12 dB of Air: up to 1.1 dB.
// The errors are almost all UNDER-compensation: the gain moves the level the right way but not all
// of it (as an EQ without the gain would, only less). Where it goes PAST the true change, it goes
// at most 2.8 dB past (Loudness_Predictor_PathologicalBounded bounds that at 3 dB). Broadband music
// stays within 0.14 dB. And no prediction leaves the played curve's own range — the gain never
// compensates more than the curve changes anything, even where BS.1770's relative gate alone would
// carry the change past it (the predictor clamps to the response's [smallest, largest] gain).
//
// DECIMATION. A profile keeps every block up to the profiler's cap; above it the blocks are thinned
// to every 2nd, 4th, … (blockStrideHops). Kept blocks are always exact, whole 400 ms blocks, so the
// gating stays a fair sample (TrackLoudnessProfiler.h, "memory and cost").
//
// THREADS. A profile is an immutable value, shared as std::shared_ptr<const TrackLoudnessProfile>;
// any number of threads may predict from one profile at once. The predictor allocates nothing,
// takes no locks and throws nothing (it is meant for the Realizer's queue, never the RT thread).

#include "../include/AudioConstants.h"
#include <cstddef>
#include <cstdint>
#include <memory>
#include <span>
#include <vector>

namespace AdaptiveSound
{
    struct GraphicEQDesign;

    namespace TrackLoudness
    {
        // The band grids, from a 20 Hz first edge: 1/24 octave (the profiler's, and the persisted profile's);
        // 1/12 octave (supported, unused — see THE BAND GRID).
        constexpr uint32_t kBandsPerOctave = 24U;
        constexpr uint32_t kCoarseBandsPerOctave = 12U;
        constexpr double kFirstEdgeHz = 20.0;
        constexpr double kLowestCentreFloorHz = 10.0; // band 0's lower edge for its centre
        // The profiler's domain: any rate the decoders hand us up to 192 kHz.
        constexpr double kMinSampleRateHz = 8000.0;
        constexpr double kMaxSampleRateHz = static_cast<double>(kMaxSupportedSampleRate);
        // Bands at the highest rate (295 at 192 kHz), rounded up: sizes the predictor's stack
        // scratch, so a prediction never allocates.
        constexpr uint32_t kMaxBandCount = 300U;

        // Edge i of the 1/bandsPerOctave grid: 20·2^(i/bandsPerOctave) Hz.
        [[nodiscard]] double edgeHz(uint32_t edge,
                                    uint32_t bandsPerOctave = kBandsPerOctave) noexcept;

        // The number of bands at `sampleRate`: band 0 plus one band per edge below Nyquist. 0 for a
        // rate outside [kMinSampleRateHz, kMaxSampleRateHz] or non-finite, or a grid other than 1/12
        // or 1/24 octave.
        [[nodiscard]] uint32_t bandCount(double sampleRate,
                                         uint32_t bandsPerOctave = kBandsPerOctave) noexcept;

        // The centre (Hz) of `band` at `sampleRate`: √(max(lower edge, 10 Hz) · upper edge), the
        // last band's upper edge being Nyquist. Requires band < bandCount(sampleRate, bandsPerOctave).
        [[nodiscard]] double bandCentreHz(uint32_t band,
                                          double sampleRate,
                                          uint32_t bandsPerOctave = kBandsPerOctave) noexcept;

        // THE COMPACT FORM's storage (the persisted −ΔL profile, C2): each band power p is kept as the
        // IEEE-754 binary16 bit pattern of p·2^kCompactPowerScaleLog2, rounded to nearest. The fixed
        // scale puts binary16's range where band powers live: up to 64 (a band +18 dB over a full-scale
        // sine's 0.5; above it saturates at binary16's largest finite value), normal down to 6e-8
        // (−72 dB), subnormal down to 6e-11. binary16 alone (normal from 6e-5) would flush every band of
        // a quiet passage to zero.
        constexpr int kCompactPowerScaleLog2 = 10;
    } // namespace TrackLoudness

    // A track's (or a prefix's) gated block spectra. Built only by TrackLoudnessProfiler; read-only
    // once shared.
    struct TrackLoudnessProfile
    {
        double sampleRate = 0.0; // the decoded track's rate (sets the band grid)
        uint32_t bandsPerOctave = TrackLoudness::kBandsPerOctave; // the band grid (24 or 12)
        uint32_t channelCount = 0U;    // the decoded channels (≤ kMaxChannels)
        uint32_t bandCount = 0U;       // TrackLoudness::bandCount(sampleRate, bandsPerOctave)
        uint32_t blockCount = 0U;      // the kept blocks
        uint32_t blockStrideHops = 1U; // kept block j starts at j·blockStrideHops·100 ms
        uint64_t analysedFrames = 0U;  // the PCM frames fed before this profile was taken
        bool wholeTrack = false;       // true: the whole track; false: a prefix
        // The source's own gated loudness over the kept blocks (LUFS), from the band sums;
        // kSilenceLufs (−200) when no block passes the gates.
        double sourceLoudnessLufs = 0.0;
        // blockCount × bandCount floats, block-major: bandPower[j·bandCount + b] = P_j(b), the
        // K-weighted, channel-weighted mean-square power of block j in band b.
        std::vector<float> bandPower;

        // Block j's bands (j < blockCount).
        [[nodiscard]] std::span<const float> block(uint32_t index) const noexcept;
        // The bytes this profile holds (its band powers plus the value itself).
        [[nodiscard]] size_t memoryBytes() const noexcept;
    };

    // The gated-loudness change (dB) the EQ'd track would have: ΔL = L(H) − L(1), from the
    // profile's blocks and the PLAYED response on its band grid. The loudness-neutral EQ output
    // gain is −ΔL.
    //
    // `bandGainDb[b]` is the played response (dB) at TrackLoudness::bandCentreHz(b) for the first
    // bandGainDb.size() bands; bands at and above that index are treated as NOT PLAYED and leave
    // both sums (a track at a higher rate than the output loses them to the sample-rate converter).
    // `blockStep` ≥ 1 uses every blockStep-th kept block (a cheaper estimate, e.g. during a drag).
    // The result lies within the response's own range, [min, max] of bandGainDb (amendment 19).
    //
    // Returns false — leaving `changeDb` untouched — on an empty or oversized response, a
    // non-finite response value, a zero blockStep, a profile with no blocks, a block set in which
    // nothing passes the gates (with or without the curve), or a non-finite result.
    [[nodiscard]] bool predictLoudnessChangeDb(const TrackLoudnessProfile& profile,
                                               std::span<const double> bandGainDb,
                                               uint32_t blockStep,
                                               double& changeDb) noexcept;

    // The same for a finished 31-band design (GraphicEQDesigner): the played response is read
    // back at every band centre below the design's Nyquist (the output rate), in the designer's
    // cancellation-free form. Returns false, leaving `changeDb` untouched, on a design whose
    // sample rate is not finite and positive, or for any reason above.
    [[nodiscard]] bool predictLoudnessChangeDb(const TrackLoudnessProfile& profile,
                                               const GraphicEQDesign& design,
                                               uint32_t blockStep,
                                               double& changeDb) noexcept;

    // The gated loudness (LUFS) of a profile's blocks with no curve: the value stored as
    // sourceLoudnessLufs. kSilenceLufs (−200) when no block passes the gates.
    [[nodiscard]] double profileLoudnessLufs(const TrackLoudnessProfile& profile) noexcept;

    // The loudness (LUFS) of one block (j < blockCount): −0.691 + 10·log10 Σ_b P_j(b), ungated;
    // kSilenceLufs for a silent block or an index out of range. Used to tell a continuous gapless
    // seam (music on both sides) from one across silence.
    [[nodiscard]] double blockLoudnessLufs(const TrackLoudnessProfile& profile,
                                           uint32_t index) noexcept;

    // The compact form of `profile` (the persisted −ΔL profile, C2): its band powers as binary16 bit
    // patterns (TrackLoudness::kCompactPowerScaleLog2), block-major, into `out`. Returns the values
    // required (blockCount × bandCount); writes nothing when `out` is shorter.
    [[nodiscard]] size_t compactPowers(const TrackLoudnessProfile& profile,
                                       std::span<uint16_t> out) noexcept;

    // A whole-track profile rebuilt from a compact one: `powers` (blockCount × bandCount binary16 bit
    // patterns, block-major) on the 1/bandsPerOctave grid at `sampleRate`. nullptr for a rate outside
    // the grid's domain, a grid other than 1/12 or 1/24, a bandCount that is not that grid's at that
    // rate, a stride of 0, a count other than blockCount × bandCount, or a non-finite pattern.
    [[nodiscard]] std::shared_ptr<const TrackLoudnessProfile>
    profileFromCompact(double sampleRate,
                       uint32_t bandsPerOctave,
                       uint32_t bandCount,
                       uint32_t blockCount,
                       uint32_t blockStrideHops,
                       std::span<const uint16_t> powers);

    // The pink-noise prior (engine-plan §4.3): a one-block profile of K-weighted pink noise on the
    // band grid at `sampleRate`, at −23 LUFS. Pink noise has equal power per octave, so each
    // 1/24-octave band carries ln(upper/lower) of it (the lowest edge floored at 10 Hz), shaped
    // by the K-weighting's |K(f)|² at the band's centre. It stands in for a track whose profile
    // has not landed yet: −ΔL on it is within ~3.4 dB of the track's own (s4b). nullptr for a rate
    // outside the grid's domain.
    [[nodiscard]] std::shared_ptr<const TrackLoudnessProfile>
    makePinkPriorProfile(double sampleRate);
} // namespace AdaptiveSound
