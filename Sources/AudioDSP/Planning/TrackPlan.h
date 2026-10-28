#pragma once

// TrackPlan.h — the leveling planner (R1.1-B; the level-and-fold design,
// docs/design/level-and-fold/README.md §1.3, §4, §6 and §8 S3; B1).
//
// One pure function computes a track's plan ONCE, as the track becomes audible, and the playback
// bridge sends the same value to both audio units in the same turn: the effects unit applies the
// leveling gain g under the cap, the spatial unit folds at the plan's trim and LFE variant. The C
// form (asPlanTrack, TrackPlanBridge.h) is what the bridge calls; this header is the C++ surface the
// null test, the Realizer and the backstop share.
//
// THE WORKING CEILING (§1.1). C_work = 20·log10(ceiling × kIspSafetyMargin) − 0.01 dB, the ceiling
// being the processed path's: −0.1 dBTP on a local lossless link, −1 dBTP otherwise. The limiter
// acts only when a peak exceeds ceiling × kIspSafetyMargin, so a peak held at C_work never wakes
// it; the 0.01 dB guards rounding. The backstop computes its working ceiling the same way, from the
// same float.

#include "../include/TrackPlanBridge.h"
#include <cstdint>

namespace AdaptiveSound
{
    // L_T: the loudness every leveled track is brought to (the sound plan, 2026-10-23).
    inline constexpr double kLevelingTargetLufs = -18.0;
    // The margin under the limiter's working ceiling (rounding; §1.1).
    inline constexpr double kWorkingCeilingGuardDb = 0.01;

    // The processed path's true-peak ceiling (linear) on an output of `transportType`: the higher of
    // the default ceiling and the EQ-only path's (decision 29), as the kernel's P1 plays it.
    [[nodiscard]] float outputCeilingLinear(uint32_t transportType) noexcept;

    // C_work (dBTP) for a ceiling of `ceilingLinear`: 20·log10(ceiling × kIspSafetyMargin) − 0.01.
    [[nodiscard]] double workingCeilingDbtp(float ceilingLinear) noexcept;

    // The plan (TrackPlanBridge.h, asPlanTrack): pure, any thread.
    [[nodiscard]] AsTrackPlan planTrack(const AsTrackLeveling* decision,
                                        const AsOutputState* output,
                                        const AsTrackPlan* frozen) noexcept;
} // namespace AdaptiveSound
