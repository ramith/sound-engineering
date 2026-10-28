// TrackPlan.cpp — the leveling planner. See TrackPlan.h.

#include "TrackPlan.h"
#include "../include/AudioConstants.h"
#include "../Limiting/LimiterModule.h" // kIspSafetyMargin: the limiter acts above ceiling × it
#include "../Limiting/OutputCeiling.h" // the EQ-only ceiling per transport (decision 29)
#include "../Spatial/FoldMatrix.h"     // the LFE variants' gains
#include <algorithm>
#include <cmath>
#include <limits>

namespace AdaptiveSound
{
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

    // Step-1 stub (R1.1-B W4, lane 1): the plan's shape only — Off, no fold. The body lands at
    // lane 1's step 4.
    AsTrackPlan planTrack(const AsTrackLeveling* /*decision*/,
                          const AsOutputState* output,
                          const AsTrackPlan* /*frozen*/) noexcept
    {
        AsTrackPlan plan{};
        plan.version = static_cast<uint32_t>(AS_TRACK_PLAN_VERSION);
        plan.mode = AsLevelingModeOff;
        plan.lfeVariant = AsLfeVariantOmit;
        plan.workingCeilingDbtp = workingCeilingDbtp(
            outputCeilingLinear((output != nullptr) ? output->transportType : 0U));
        plan.loudnessLufs = std::numeric_limits<double>::quiet_NaN();
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
