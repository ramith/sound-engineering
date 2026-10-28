#pragma once

// LfeStatistics — what the one analysis pass measures of a file's LFE against its mains, for the LFE rule
// to decide from at plan time (R1.1-B; the level-and-fold design, docs/design/level-and-fold/README.md §5;
// the verify pass's C2/C4: the 90th-percentile r²). It measures and decides nothing: the rule
// (Spatial/FoldLfeRule) reads AsLfeStats later, so its thresholds tune without a re-analysis.
//
// THE PORT. An exact port of the design's prototype, proto/p4_lfe_v2.py `band500` + `stats` (NumPy/SciPy;
// 117 of 117 fixture decisions), including its circular shifts (np.roll) and SciPy's Welch defaults, so a
// decision near a threshold lands as the prototype's does:
//   band       every channel → Butterworth high-pass (order 2, 20 Hz) → low-pass (order 4, 120 Hz), designed
//              by the prewarped bilinear transform (scipy.signal.butter), direct form II transposed in double
//              (sosfilt); then every round(fs / 500)-th sample from the first (y[::96] at 48 kHz). The LFE
//              is the sum of the LFE-role channels; the MAINS are every other channel; msum is their sum.
//   blocks     200 samples (400 ms) every 50 (100 ms); ACTIVE when 10·log10(mean LFE² + 1e-30) ≥ −50 dB.
//              Fewer than 50 active blocks: only activeBlocks is measured (the rest NaN).
//   lag        over ±100 samples (±200 ms), the normalised correlation of the masked LFE with the masked
//              msum circularly shifted by the lag; the first lag of the largest |r| (lagMs = 2·lag).
//   the fit    one 21-tap FIR per main (±10 samples, ±20 ms) centred on the lag: least squares over the
//              masked samples farther than 110 from either end. The prototype's np.linalg.lstsq (SVD) is
//              replaced by the normal equations with a 1e-12 relative ridge (Cholesky): the same prediction
//              wherever the mains carry energy; directions below 1e-12 of the mean eigenvalue — where only
//              rounding lives — are left out instead of fitted. The prediction covers every sample.
//   per block  r² = (y·p)² / (y·y · p·p + 1e-30) (scale-invariant); the unexplained LFE power
//              mean(y²)·(1 − r²) against Σ_main mean(main²): excess20 counts it ≥ −20 dB.
//   explainGain  max over the 25, 31.5, 40, 50 and 63 Hz third-octaves (edges fc·2^∓1/6) of the
//              prediction's power over msum's, both by Welch (Hann, 512 samples, 256 overlap, each segment's
//              mean removed) over the fitted samples; −99 dB when no band is filled.
//   coherentShare = share(r² ≥ 0.8); medianR2 and p90R2 = NumPy's linear-interpolated percentiles.
// A file with no LFE role, or nothing but an LFE, has no statistics (activeBlocks 0, the rest NaN).
//
// COST AND MEMORY. The band signals at 500 Hz are kept in double: 4 KB per second per channel (≈ 1 MB per
// 4-minute channel). The fit's normal matrix accumulates by BLAS dsyrk; the lag search and the prediction
// are vDSP dot products and multiply-adds. A 4-minute 7.1 file's statistics take well under a second.
//
// THREADS. One owner (the analysis job); allocates as the band signals grow; off the real-time path.

#include "../include/AudioConstants.h"
#include "../include/ChannelLayout.h"
#include "../include/TrackPlanBridge.h"
#include <array>
#include <cstddef>
#include <cstdint>
#include <span>
#include <vector>

namespace AdaptiveSound
{
    class LfeStatistics
    {
      public:
        // The band signals' rate (nominal: the prototype's FS2).
        static constexpr double kBandRateHz = 500.0;

        // Measure a stream at `sampleRate` whose channels have `roles`.
        LfeStatistics(double sampleRate, std::span<const ChannelRole> roles);

        // Whether there is anything to measure: at least one LFE channel and one main.
        [[nodiscard]] bool measures() const noexcept
        {
            return measures_;
        }

        // Band-limit and decimate `frames` more frames (one pointer per channel, in the roles' order).
        void process(std::span<const double* const> channels, size_t frames);

        // The statistics of everything processed.
        [[nodiscard]] AsLfeStats finish() const;

        // The statistics of band signals already at kBandRateHz (the prototype's `stats(mains, lfe)`):
        // `mains` holds one signal per main, each as long as `lfe`.
        [[nodiscard]] static AsLfeStats measure(std::span<const std::vector<double>> mains,
                                                std::span<const double> lfe);

      private:
        // One DF2T biquad in double (scipy.signal.sosfilt's form).
        struct Section
        {
            double b0 = 1.0;
            double b1 = 0.0;
            double b2 = 0.0;
            double a1 = 0.0;
            double a2 = 0.0;
            double z1 = 0.0;
            double z2 = 0.0;

            [[nodiscard]] double process(double input) noexcept
            {
                const double output = (b0 * input) + z1;
                z1 = (b1 * input) - (a1 * output) + z2;
                z2 = (b2 * input) - (a2 * output);
                return output;
            }
        };
        static constexpr size_t kSections =
            3U; // high-pass order 2, then low-pass order 4 (two sections)
        using Band = std::array<Section, kSections>;

        [[nodiscard]] static Band makeBand(double sampleRate) noexcept;
        [[nodiscard]] static double filter(Band& band, double input) noexcept;

        bool measures_ = false;
        uint32_t channels_ = 0U;
        std::array<int, kMaxChannels> mainOf_{}; // channel → main index, −1 for an LFE channel
        uint32_t decimation_ = 1U;
        uint32_t phase_ = 0U; // samples since the last kept one
        std::vector<Band> mainBands_;
        Band lfeBand_{};
        std::vector<std::vector<double>> mains_;
        std::vector<double> lfe_;
    };
} // namespace AdaptiveSound
