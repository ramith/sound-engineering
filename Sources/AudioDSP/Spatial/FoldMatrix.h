#pragma once

// FoldMatrix.h — the BS.775 stereo fold's matrix, built from channel roles (R1.1-B; the
// level-and-fold design, docs/design/level-and-fold/README.md §S1b, §4 and §5).
//
// Pure and header-only: no state, no allocation, safe on any thread. The planner
// (Planning/TrackPlan) reads its worst-case row sum for the fallback trim; the analysis measures the
// fold through it (lane 1-B); the spatial unit plays it (lane 2). One table, so what is measured is
// what plays.
//
// THE TABLE (two output rows, L′ and R′):
//   L / R              1.0 into its own side                     BS.775-4 Table 2, p. 8
//   C, Mono            0.7071 to both                            Table 2; Annex 5 §1.1
//   one surround pair  0.7071 into its side (Ls/Rs, or Lb/Rb)    Table 2
//   side AND back      0.5 each into its side (7.1)              founder decision 5 (2026-10-26):
//                                                                derived from Note 5 and Table 2 —
//                                                                BS.775-4 has no 7.1 row
//   Cs                 0.5 to both                               derived
//   Lc / Rc, Lw / Rw   1.0 into its side                         judgment, unverified
//   Unknown            0.5 to both                               judgment
//   Lfe                the LFE variant's gain to both            BS.775-4 Annex 7, Fig. 5
//
// The LFE variants (per side): 0 (omitted), 0.5 (−6 dB, the music-disc convention), 1.0, and
// 10^(4/20) (+4 dB, the film convention). The include level is the founder's; every variant is
// measured by the analysis, so a choice needs no re-analysis.

#include "../include/AudioConstants.h"
#include "../include/ChannelLayout.h"
#include "../include/TrackPlanBridge.h"
#include <algorithm>
#include <array>
#include <cmath>
#include <cstdint>
#include <optional>
#include <span>

namespace AdaptiveSound
{
    // The per-side LFE gain of each variant (AsLfeVariant order). Persisted analyses carry one
    // folded loudness and peak per entry, so this table is in AS_TRACK_ANALYSIS_VERSION's list.
    inline constexpr std::array<float, AS_FOLD_LFE_VARIANTS> kFoldLfeVariantGains = {
        0.0F,        // Omit
        0.5F,        // Music: −6 dB per side
        1.0F,        // Full
        1.58489319F, // Film: +4 dB per side (10^(4/20))
    };

    inline constexpr float kFoldFrontGain = 1.0F;           // L, R; Lc/Rc, Lw/Rw
    inline constexpr float kFoldCentreGain = 0.70710678F;   // C, Mono: −3 dB to both
    inline constexpr float kFoldSurroundGain = 0.70710678F; // the one surround pair
    inline constexpr float kFoldSurround71Gain = 0.5F;      // side and back pairs both present
    inline constexpr float kFoldCentreSurroundGain = 0.5F;  // Cs, to both
    inline constexpr float kFoldUnknownGain = 0.5F;         // an unknown role, to both
    inline constexpr double kFoldDbAmplitudeScale = 20.0;   // 20·log10

    // The fold: two output rows (L′, R′) over the input's channels.
    struct FoldMatrix
    {
        uint32_t inChannels = 0U;
        std::array<std::array<float, kMaxChannels>, 2> gain{};

        // The larger row's Σ|gain| in dB: how far the fold can raise a peak shared by every input
        // (|Σ gᵢ·xᵢ| ≤ Σ|gᵢ|·max|xᵢ|, for sample and true peaks alike).
        [[nodiscard]] double worstRowGainDb() const noexcept
        {
            double worst = 0.0;
            for (const auto& row : gain)
            {
                double sum = 0.0;
                for (uint32_t ch = 0U; ch < inChannels; ++ch)
                {
                    sum += std::abs(static_cast<double>(row[ch]));
                }
                worst = std::max(worst, sum);
            }
            return (worst > 0.0) ? kFoldDbAmplitudeScale * std::log10(worst) : 0.0;
        }
    };

    // The per-side gain of LFE variant `variant` (0 for one out of range).
    [[nodiscard]] constexpr float foldLfeVariantGain(uint8_t variant) noexcept
    {
        return (variant < kFoldLfeVariantGains.size()) ? kFoldLfeVariantGains[variant] : 0.0F;
    }

    // The BS.775 fold of channels with `roles` (one per input), the LFE at `lfeVariant`. nullopt
    // for no channels or more than kMaxChannels.
    [[nodiscard]] inline std::optional<FoldMatrix> makeBs775Fold(std::span<const ChannelRole> roles,
                                                                 uint8_t lfeVariant) noexcept
    {
        if (roles.empty() || roles.size() > kMaxChannels)
        {
            return std::nullopt;
        }
        const auto has = [&roles](ChannelRole wanted)
        { return std::ranges::find(roles, wanted) != roles.end(); };
        const bool sidePair = has(ChannelRole::Ls) || has(ChannelRole::Rs);
        const bool backPair = has(ChannelRole::Lb) || has(ChannelRole::Rb);
        const float surround = (sidePair && backPair) ? kFoldSurround71Gain : kFoldSurroundGain;
        const float lfe = foldLfeVariantGain(lfeVariant);

        FoldMatrix matrix{};
        matrix.inChannels = static_cast<uint32_t>(roles.size());
        auto& left = matrix.gain[0];
        auto& right = matrix.gain[1];
        for (size_t ch = 0U; ch < roles.size(); ++ch)
        {
            switch (roles[ch])
            {
                case ChannelRole::L:
                case ChannelRole::Lc:
                case ChannelRole::Lw:
                    left[ch] = kFoldFrontGain;
                    break;
                case ChannelRole::R:
                case ChannelRole::Rc:
                case ChannelRole::Rw:
                    right[ch] = kFoldFrontGain;
                    break;
                case ChannelRole::C:
                case ChannelRole::Mono:
                    left[ch] = kFoldCentreGain;
                    right[ch] = kFoldCentreGain;
                    break;
                case ChannelRole::Ls:
                case ChannelRole::Lb:
                    left[ch] = surround;
                    break;
                case ChannelRole::Rs:
                case ChannelRole::Rb:
                    right[ch] = surround;
                    break;
                case ChannelRole::Cs:
                    left[ch] = kFoldCentreSurroundGain;
                    right[ch] = kFoldCentreSurroundGain;
                    break;
                case ChannelRole::Lfe:
                    left[ch] = lfe;
                    right[ch] = lfe;
                    break;
                case ChannelRole::Unknown:
                    left[ch] = kFoldUnknownGain;
                    right[ch] = kFoldUnknownGain;
                    break;
            }
        }
        return matrix;
    }

    // The same, from a decoded layout's roles (the design's form).
    [[nodiscard]] inline std::optional<FoldMatrix> makeBs775Fold(const ChannelLayout& layout,
                                                                 uint8_t lfeVariant) noexcept
    {
        const uint32_t channels = std::min(layout.numChannels, kMaxChannels);
        return makeBs775Fold(std::span<const ChannelRole>(layout.role.data(), channels),
                             lfeVariant);
    }

    // The fold's trim (dB, ≤ 0) for a working ceiling of `cWorkDb`: min(0, cWorkDb − tpDbtp), where
    // tpDbtp is the fold's measured true peak (after any gain the caller adds). A NaN tpDbtp — no
    // measurement — falls back to the matrix's worst case over a source at `sourcePeakDbtp`:
    // min(0, cWorkDb − (worstRowGainDb + sourcePeakDbtp)).
    [[nodiscard]] inline double foldTrimDb(double cWorkDb,
                                           double tpDbtp,
                                           const FoldMatrix& matrix,
                                           double sourcePeakDbtp = 0.0) noexcept
    {
        const double peak = std::isnan(tpDbtp) ? matrix.worstRowGainDb() + sourcePeakDbtp : tpDbtp;
        return std::min(0.0, cWorkDb - peak);
    }
} // namespace AdaptiveSound
