#include "FoldLfeRule.h"
#include <cmath>

// FoldLfeRule — implementation (the rule and its reasons are in the header).

namespace AdaptiveSound
{
    namespace
    {
        [[nodiscard]] bool allFinite(const AsLfeStats& stats) noexcept
        {
            return std::isfinite(stats.lagMs) && std::isfinite(stats.lagPeak) &&
                   std::isfinite(stats.coherentShare) && std::isfinite(stats.medianR2) &&
                   std::isfinite(stats.p90R2) && std::isfinite(stats.excess20Share) &&
                   std::isfinite(stats.explainGainDb);
        }
    } // namespace

    AsLfeVerdict foldDecideLfe(const AsLfeStats& stats) noexcept
    {
        if (stats.activeBlocks < kLfeMinActiveBlocks || !allFinite(stats))
        {
            return AsLfeVerdictOmitUnknown;
        }
        const bool copyLike = stats.medianR2 >= kLfeCopyMedianR2 ||
                              stats.coherentShare >= kLfeCopyCoherentShare ||
                              stats.lagPeak >= kLfeCopyLagPeak;
        if (copyLike)
        {
            return stats.explainGainDb > kLfeRedirectExplainGainDb ? AsLfeVerdictIncludeRedirected
                                                                   : AsLfeVerdictOmitCopy;
        }
        if (stats.coherentShare < kLfeIndependentCoherentShare &&
            stats.excess20Share >= kLfeIndependentExcess20 && stats.p90R2 < kLfeIndependentP90R2)
        {
            return AsLfeVerdictIncludeIndependent;
        }
        return AsLfeVerdictOmitUncertain;
    }
} // namespace AdaptiveSound

extern "C"
{
    uint8_t asFoldDecideLfe(const AsLfeStats* stats) AUDIODSP_C_NOEXCEPT
    {
        if (stats == nullptr)
        {
            return AsLfeVerdictOmitUnknown;
        }
        return static_cast<uint8_t>(AdaptiveSound::foldDecideLfe(*stats));
    }

    bool asLfeVerdictIncludes(uint8_t verdict) AUDIODSP_C_NOEXCEPT
    {
        return AdaptiveSound::lfeVerdictIncludes(static_cast<AsLfeVerdict>(verdict));
    }

} // extern "C"
