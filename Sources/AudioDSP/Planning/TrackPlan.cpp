// TrackPlan.cpp — the leveling planner. See TrackPlan.h.

#include "TrackPlan.h"
#include "../include/AudioConstants.h"
#include "../Limiting/LimiterModule.h" // kIspSafetyMargin: the limiter acts above ceiling × it
#include "../Limiting/OutputCeiling.h" // the EQ-only ceiling per transport (decision 29)
#include "../Spatial/FoldMatrix.h"     // the LFE variants' gains
#include <algorithm>
#include <cmath>
#include <limits>
#include <span>

namespace AdaptiveSound
{
    namespace
    {
        constexpr double kNaN = std::numeric_limits<double>::quiet_NaN();
    } // namespace

    float outputCeilingLinear(uint32_t transportType) noexcept
    {
        return std::max(kTruePeakCeilingLinear, eqOnlyCeilingLinear(transportType));
    }

    double workingCeilingDbtp(float ceilingLinear) noexcept
    {
        return (kFoldDbAmplitudeScale *
                std::log10(static_cast<double>(ceilingLinear) * kIspSafetyMargin)) -
               kWorkingCeilingGuardDb;
    }

    namespace
    {
        // Under this a measured loudness is no loudness (F4; BS.1770's absolute gate).
        constexpr double kSilentLufs = -70.0;
        // The fixed cut for a track whose loudness is unknown (founder decision 6, 2026-10-26).
        constexpr double kUnknownCutDb = -5.0;
        // A leveling gain never exceeds −ΔL's own clamp (F4): a −60 dBTP hiss would otherwise get +58.7 dB.
        constexpr double kMaxLevelGainDb = 12.0;
        // A mono file plays on both sides at 0 dB (F8, the founder's XM4 listen): dual mono, 10·log10(2) LU above
        // its one-channel measure (libebur128's EBUR128_DUAL_MONO).
        constexpr double kDualMonoLu = 3.010299956639812;
        constexpr double kEngineRateHz = static_cast<double>(kDefaultSampleRate);

        // The output before the graph says otherwise: the engine's rate, stereo in and out, transport unknown.
        [[nodiscard]] AsOutputState unknownStereoOutput() noexcept
        {
            AsOutputState output{};
            output.engineRateHz = kEngineRateHz;
            output.sourceChannels = 2U;
            output.outputChannels = 2U;
            output.sourceRoles[0] = static_cast<uint8_t>(ChannelRole::L);
            output.sourceRoles[1] = static_cast<uint8_t>(ChannelRole::R);
            return output;
        }

        // The decision's numbers as the planner reads them.
        struct Measured
        {
            const AsTrackLeveling* decision = nullptr;
            bool peakAtEngineRate = false;

            // A true peak the limiter would see (§6, architect N6): unknown → 0 dBTP; measured at another
            // rate than the engine's (a tag's peak) → 0 dBTP, raised to it only above full scale.
            [[nodiscard]] double limiterPeak(double truePeakDbtp) const noexcept
            {
                if (!std::isfinite(truePeakDbtp))
                {
                    return 0.0;
                }
                return peakAtEngineRate ? truePeakDbtp : std::max(0.0, truePeakDbtp);
            }

            // The decision's roles are the playing file's (its fold numbers apply).
            [[nodiscard]] bool rolesMatch(const AsOutputState& output,
                                          uint32_t channels) const noexcept
            {
                if (decision == nullptr || decision->channelCount != channels)
                {
                    return false;
                }
                for (uint32_t ch = 0U; ch < channels; ++ch)
                {
                    if (decision->roles[ch] != output.sourceRoles[ch])
                    {
                        return false;
                    }
                }
                return true;
            }
        };

        [[nodiscard]] uint8_t validVariant(uint8_t variant) noexcept
        {
            return (variant < static_cast<uint8_t>(AS_FOLD_LFE_VARIANTS))
                       ? variant
                       : static_cast<uint8_t>(AsLfeVariantOmit);
        }

        // The fold's LFE variant: kept by a protective re-plan, else the decision's (a group shares one), else
        // omitted.
        [[nodiscard]] uint8_t planVariant(const AsTrackLeveling* decision,
                                          const AsTrackPlan* frozen) noexcept
        {
            if (frozen != nullptr)
            {
                return validVariant(frozen->lfeVariant);
            }
            return validVariant((decision != nullptr) ? decision->lfeVariant
                                                      : static_cast<uint8_t>(AsLfeVariantOmit));
        }

        // The leveling gain g (§1.3; F4, NI-7) for a plan whose fold, peak and loudness are settled.
        [[nodiscard]] double levelGainDb(const AsTrackPlan& plan,
                                         const AsTrackPlan* frozen,
                                         double measuredLoudness,
                                         double plannedLoudness) noexcept
        {
            if (frozen != nullptr)
            {
                return frozen->levelGainDb; // frozen at audibility (F5)
            }
            if (plan.mode == static_cast<uint8_t>(AsLevelingModeOff))
            {
                return 0.0;
            }
            const double peakRoom = plan.workingCeilingDbtp - plan.peakDbtp;
            const bool loudnessKnown =
                std::isfinite(measuredLoudness) && measuredLoudness > kSilentLufs;
            if (plan.mode == static_cast<uint8_t>(AsLevelingModeUnknownCut) || !loudnessKnown)
            {
                // −5 dB, not stacked on a fold's trim that already cuts more, and never above the peak cap: an
                // unknown peak counts as 0 dBTP, a known hot one (a short +5 dBTP sting) cuts further (NI-7).
                return std::min({0.0, kUnknownCutDb - plan.foldTrimDb, peakRoom});
            }
            return std::min({kLevelingTargetLufs - plannedLoudness, peakRoom, kMaxLevelGainDb});
        }

        [[nodiscard]] uint8_t validMode(const AsTrackLeveling* decision) noexcept
        {
            if (decision == nullptr ||
                decision->mode > static_cast<uint8_t>(AsLevelingModeUnknownCut))
            {
                return static_cast<uint8_t>(AsLevelingModeOff);
            }
            return decision->mode;
        }

        // The fold's peak before the trim: the measured TP_F[v], or — with no measurement, or one made with
        // other roles — the matrix's worst row over the N-channel peak (|Σ gᵢ·xᵢ| ≤ Σ|gᵢ|·max|xᵢ|).
        [[nodiscard]] double foldPeakDbtp(const Measured& measured,
                                          const AsOutputState& output,
                                          uint32_t channels,
                                          uint8_t variant,
                                          bool fromAnalysis,
                                          double peakN) noexcept
        {
            if (fromAnalysis)
            {
                return measured.limiterPeak(measured.decision->foldedTruePeakDbtp[variant]);
            }
            std::array<ChannelRole, kMaxChannels> roles{};
            for (uint32_t ch = 0U; ch < channels; ++ch)
            {
                roles.at(ch) = static_cast<ChannelRole>(output.sourceRoles[ch]);
            }
            const auto matrix =
                makeBs775Fold(std::span<const ChannelRole>(roles.data(), channels), variant);
            return (matrix ? matrix->worstRowGainDb() : 0.0) + peakN;
        }
    } // namespace

    AsTrackPlan planTrack(const AsTrackLeveling* decision,
                          const AsOutputState* outputOrNull,
                          const AsTrackPlan* frozen) noexcept
    {
        const AsOutputState output =
            (outputOrNull != nullptr) ? *outputOrNull : unknownStereoOutput();
        const uint32_t channels = std::clamp(output.sourceChannels, 1U, kMaxChannels);
        const uint32_t outputs = std::max(output.outputChannels, 1U);
        const Measured measured{
            .decision = decision,
            .peakAtEngineRate = decision != nullptr && decision->peakRateHz > 0.0 &&
                                decision->peakRateHz == output.engineRateHz,
        };

        AsTrackPlan plan{};
        plan.version = static_cast<uint32_t>(AS_TRACK_PLAN_VERSION);
        plan.mode = validMode(decision);
        plan.lfeVariant = planVariant(decision, frozen);
        plan.lfeGainLinear = static_cast<double>(foldLfeVariantGain(plan.lfeVariant));
        const double cWork = workingCeilingDbtp(outputCeilingLinear(output.transportType));
        plan.workingCeilingDbtp = cWork;

        // The N-channel peak and loudness (the decision's, or unknown).
        const double peakN =
            (decision != nullptr) ? measured.limiterPeak(decision->truePeakDbtp) : 0.0;
        const double loudnessN = (decision != nullptr) ? decision->loudnessLufs : kNaN;
        // With the gain frozen (F5), the trim must make room for it too: the fold's peak after g.
        const double frozenGainDb = (frozen != nullptr) ? frozen->levelGainDb : 0.0;

        // The fold (C1: N > 2 played on fewer outputs folds to stereo, never truncates).
        plan.folds = (channels > 2U && outputs < channels) ? 1U : 0U;
        double measuredLoudness = loudnessN;
        double plannedLoudness = loudnessN;
        if (plan.folds != 0U)
        {
            const bool fromAnalysis = decision != nullptr && decision->hasFolded != 0U &&
                                      measured.rolesMatch(output, channels) &&
                                      std::isfinite(decision->foldedTruePeakDbtp[plan.lfeVariant]);
            plan.foldFromAnalysis = fromAnalysis ? 1U : 0U;
            const double peakF =
                foldPeakDbtp(measured, output, channels, plan.lfeVariant, fromAnalysis, peakN);
            plan.foldTrimDb = std::min(0.0, cWork - (peakF + frozenGainDb));
            plan.peakDbtp = std::max(peakN, peakF + plan.foldTrimDb);
            measuredLoudness = fromAnalysis ? decision->foldedLufs[plan.lfeVariant] : loudnessN;
            plannedLoudness = measuredLoudness + plan.foldTrimDb;
        }
        else
        {
            plan.peakDbtp = peakN;
            if (channels == 1U && outputs >= 2U)
            {
                plannedLoudness += kDualMonoLu;
            }
        }
        plan.loudnessLufs = plannedLoudness;

        plan.levelGainDb = levelGainDb(plan, frozen, measuredLoudness, plannedLoudness);
        return plan;
    }
} // namespace AdaptiveSound

extern "C"
{
    float asLfeVariantGain(uint8_t variant) AUDIODSP_C_NOEXCEPT
    {
        return AdaptiveSound::foldLfeVariantGain(variant);
    }

    AsTrackPlan asPlanTrack(const AsTrackLeveling* decision,
                            const AsOutputState* output,
                            const AsTrackPlan* frozen) AUDIODSP_C_NOEXCEPT
    {
        return AdaptiveSound::planTrack(decision, output, frozen);
    }
} // extern "C"
