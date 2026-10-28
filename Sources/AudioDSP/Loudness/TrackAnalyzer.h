#pragma once

// TrackAnalyzer — the one analysis pass (R1.1-B; the level-and-fold design,
// docs/design/level-and-fold/README.md §1.2, §2, §3, §5 and §S1). Its C form is asTrackAnalyzer*
// (TrackLoudnessBridge.h); the Swift pipeline (TrackLoudnessKit) feeds it.
//
// WHAT IT IS FED: the ENGINE-RATE stream, after the engine's own Mastering converter with the file's own
// layout as its output format (F1), so every true peak is the one the limiter will see.
//
// WHAT IT MEASURES (it decides nothing):
//   bases        0 = as decoded (N channels); 1 + v = the BS.775 stereo fold at LFE variant v (N > 2 only),
//                through Spatial/FoldMatrix.h's makeBs775Fold — the one table the spatial unit plays.
//   loudness     per basis, ITU-R BS.1770-5: K-weighting (LufsMeter's makeKWeighting), the channel weights
//                by role (ChannelRoles.h bs1770Weights: LFE 0) or 1.0 for the fold's two channels, 400 ms
//                blocks every 100 ms; EVERY block's energy is kept and the integrated loudness is the exact
//                two-stage gate (absolute l > −70 LUFS, relative > the absolute-gated mean − 10 LU).
//   histograms   per basis, LufsMeter's form (0.1 LU bins from −70 LUFS, count + exact energy sum) of the
//                blocks above the absolute gate, for the album's pooled anchor (asLoudnessPoolHistograms).
//   head, tail   the first and the last whole block's loudness (basis 0), for the continuity judge.
//   true peaks   AnalysisTruePeak (max of the shipped 8×24 kernel, an 8×64 kernel and the samples) over all
//                N channels, the LFE included, and over each fold's two channels.
//   LFE          LfeStatistics (§5; the p90 r²).
//   profiles     per basis, the persisted −ΔL profile (C2): TrackLoudnessProfiler on today's 1/24-octave grid,
//                capped at kCompactMaxBlocks blocks — every block up to 2 minutes, then every 2nd, 4th, … (the
//                profiler's decimation) — returned as binary16 (TrackLoudnessProfile.h). Measured against the
//                full profile over 5 programmes × 8 curves × 20/120/240 s: ≤ 0.014 dB (the design's 1/12-octave
//                form on non-overlapping blocks erred up to 0.22 dB on tonal programmes: its grid alone 0.05–0.10).
// A fold with no LFE channel is the same at every variant: it is measured once and reported for all four.
//
// THREADS. One owner; not thread-safe; off the real-time path (it allocates as the track grows).

#include "../include/AudioConstants.h"
#include "../include/ChannelLayout.h"
#include "../include/TrackLoudnessBridge.h"
#include "../Spatial/FoldMatrix.h"
#include "AnalysisTruePeak.h"
#include "LfeStatistics.h"
#include "TrackLoudnessProfile.h"
#include "TrackLoudnessProfiler.h"
#include <array>
#include <cstddef>
#include <cstdint>
#include <memory>
#include <optional>
#include <span>
#include <vector>

namespace AdaptiveSound
{
    // BS.1770-5's integrated loudness of a programme's block energies (the exact two-stage gate). NaN when
    // no block passes the absolute gate.
    [[nodiscard]] double gatedLoudnessLufs(std::span<const double> blockEnergies) noexcept;

    // Pool gated-loudness histograms (LufsMeter's form) into one BS.1770 integrated loudness: the counts and
    // energies summed per bin, the relative gate by bin centre (as LufsMeter gates). NaN when no block is
    // binned, or for a bin index past the histogram's last or a non-finite or negative energy.
    [[nodiscard]] double
    poolHistogramsLufs(std::span<const std::span<const AsLoudnessBin>> members) noexcept;

    // One programme's BS.1770 blocks: per-channel K-weighting and weights; every block's energy is kept.
    class GatedBlockMeter
    {
      public:
        GatedBlockMeter(double sampleRate,
                        uint32_t channels,
                        const std::array<double, kMaxChannels>& weights);

        void process(std::span<const double* const> channels, size_t frames);

        [[nodiscard]] size_t blockCount() const noexcept
        {
            return blocks_.size();
        }
        // Block `index`'s loudness, ungated (LufsMeter's −200 LUFS floor for silence).
        [[nodiscard]] double blockLufs(size_t index) const noexcept;
        [[nodiscard]] double integratedLufs() const noexcept
        {
            return gatedLoudnessLufs(blocks_);
        }
        // The non-empty bins of the blocks above the absolute gate, in bin order.
        [[nodiscard]] std::vector<AsLoudnessBin> histogram() const;

      private:
        uint32_t channels_ = 0U;
        std::array<double, kMaxChannels> weights_{};
        std::array<LufsKWeight, kMaxChannels> kWeight_{};
        std::array<double, kMaxChannels> hopSum_{};
        uint32_t hopFrames_ = 0U;
        uint32_t hopFill_ = 0U;
        std::array<double, static_cast<size_t>(kBlockHops)> hopEnergy_{}; // the last 4 hops, a ring
        uint64_t hops_ = 0U;
        std::vector<double> blocks_;
    };

    class TrackAnalyzer
    {
      public:
        static constexpr uint8_t kBases = AS_PROFILE_BASES;
        // The persisted profile's cap: 2 minutes of blocks; a longer track keeps every 2nd, 4th, … block.
        static constexpr uint32_t kCompactMaxBlocks = 1200U;

        // An analysis of a stream at `engineRateHz` (the profiler's domain) whose channels have `roles`
        // (1 … kMaxChannels of them). nullptr otherwise.
        [[nodiscard]] static std::unique_ptr<TrackAnalyzer>
        create(double engineRateHz, std::span<const ChannelRole> roles);

        // Feed `frames` frames, planar (one pointer per channel). False — consuming NOTHING — on a wrong
        // channel count, a NULL channel, any non-finite sample, or after finish().
        [[nodiscard]] bool feed(std::span<const float* const> channels, size_t frames);

        // End the stream and write what was measured. False — writing nothing — on a second call.
        [[nodiscard]] bool finish(AsTrackAnalysis& out);

        [[nodiscard]] bool isFinished() const noexcept
        {
            return finished_;
        }
        [[nodiscard]] uint32_t channelCount() const noexcept
        {
            return channels_;
        }

        // After finish(): basis `basis`'s histogram (empty for a basis the file does not have).
        [[nodiscard]] std::span<const AsLoudnessBin> histogram(uint8_t basis) const noexcept;
        // After finish(): basis `basis`'s compact profile (nullptr for a basis the file does not have, or a
        // stream shorter than one block).
        [[nodiscard]] const TrackLoudnessProfile* profile(uint8_t basis) const noexcept;

        ~TrackAnalyzer() = default;
        TrackAnalyzer(const TrackAnalyzer&) = delete;
        TrackAnalyzer& operator=(const TrackAnalyzer&) = delete;
        TrackAnalyzer(TrackAnalyzer&&) = delete;
        TrackAnalyzer& operator=(TrackAnalyzer&&) = delete;

      private:
        static constexpr size_t kChunkFrames = 4096U;

        TrackAnalyzer(double engineRateHz, std::span<const ChannelRole> roles);

        // The basis a fold variant's measurements live in (all four share variant 0's without an LFE).
        [[nodiscard]] uint8_t measuredVariant(uint8_t variant) const noexcept
        {
            return hasLfe_ ? variant : 0U;
        }
        void processChunk(std::span<const float* const> channels, size_t offset, size_t frames);

        double rate_ = 0.0;
        uint32_t channels_ = 0U;
        std::array<ChannelRole, kMaxChannels> roles_{};
        bool folds_ = false;
        bool hasLfe_ = false;
        uint8_t foldVariants_ =
            0U; // the variants measured: 4 with an LFE, 1 without, 0 without a fold
        uint64_t frames_ = 0U;
        bool finished_ = false;

        // Basis 0.
        std::unique_ptr<GatedBlockMeter> decodedMeter_;
        std::unique_ptr<AnalysisTruePeak::Detector> decodedPeak_;
        std::unique_ptr<TrackLoudnessProfiler> decodedProfiler_;
        // The folds, one per measured variant.
        std::array<FoldMatrix, AS_FOLD_LFE_VARIANTS> foldMatrix_{};
        std::array<std::unique_ptr<GatedBlockMeter>, AS_FOLD_LFE_VARIANTS> foldMeter_;
        std::array<std::unique_ptr<AnalysisTruePeak::Detector>, AS_FOLD_LFE_VARIANTS> foldPeak_;
        std::array<std::unique_ptr<TrackLoudnessProfiler>, AS_FOLD_LFE_VARIANTS> foldProfiler_;
        LfeStatistics lfe_;

        // Scratch: the chunk in double; each measured fold's two channels in double and in float.
        std::vector<double> input_;
        std::vector<double> foldDouble_;
        std::vector<float> foldFloat_;

        // The results.
        std::array<std::vector<AsLoudnessBin>, kBases> histograms_{};
        std::array<std::shared_ptr<const TrackLoudnessProfile>, kBases> profiles_{};
    };
} // namespace AdaptiveSound
