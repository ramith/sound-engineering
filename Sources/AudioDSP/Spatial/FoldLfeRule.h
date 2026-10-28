#pragma once

// FoldLfeRule — whether a track's LFE goes into the stereo fold (R1.1-B; the level-and-fold design,
// docs/design/level-and-fold/README.md §5 and §8½ C4).
//
// Decided at PLAN time from the statistics the one analysis pass stores (AsLfeStats, TrackPlanBridge.h), so
// the thresholds here tune without a re-analysis (they are not in AS_TRACK_ANALYSIS_VERSION). The include
// LEVEL is not this rule's: it is the LFE variant the founder chooses (the music convention, −6 dB per side,
// recommended); this rule says only whether the LFE plays.
//
// THE RULE (§5; rule 4's p90 gate is §8½ C4):
//   1. Fewer than 50 active blocks (5 s)                                → omit (unknown)
//   2. copy-like (medianR2 ≥ 0.5, or coherentShare ≥ 0.4, or lagPeak ≥ 0.8) and explainGain ≤ +15 dB
//                                                                      → omit (a copy of the mains' bass)
//   3. copy-like and explainGain > +15 dB                               → include (the mains' bass moved
//                                                                        into the LFE behind a high-pass)
//   4. coherentShare < 0.2 and excess20Share ≥ 0.5 and p90R2 < 0.3      → include (bass the mains lack)
//   5. otherwise                                                        → omit
//
// The asymmetry follows BS.775-4 Annex 7 ("at most, an enhancement"): a wrong include combs or doubles the
// bass (+6 dB below ~120 Hz for a full-level copy), a wrong omit loses an enhancement. A statistic that is
// not a number reads as unknown.
//
// Known limits (measured on the panel's and the verify pass's fixtures; lane 2's report):
//   - a stem copy (kick and bass panned alike) 10 dB or more under the bass reads like an independent layer
//     (p90 r² 0.19–0.29) and is included;
//   - bass redirected behind a gentle BW2 60 Hz high-pass reads explainGain +14.7 … +15.2 dB: on the +15 dB
//     line, so it may be omitted;
//   - a sub layer that sounds only part of the time (excess20Share ≈ 0.4) is omitted.
//
// Pure: no state, any thread.

#include "../include/SpatialBridge.h" // AsLfeVerdict
#include "../include/TrackPlanBridge.h"
#include <cstdint>

namespace AdaptiveSound
{
    inline constexpr uint32_t kLfeMinActiveBlocks = 50U;        // rule 1: 5 s at the 100 ms hop
    inline constexpr float kLfeCopyMedianR2 = 0.5F;             // rule 2: copy-like …
    inline constexpr float kLfeCopyCoherentShare = 0.4F;        // …
    inline constexpr float kLfeCopyLagPeak = 0.8F;              // …
    inline constexpr float kLfeRedirectExplainGainDb = 15.0F;   // rules 2 / 3
    inline constexpr float kLfeIndependentCoherentShare = 0.2F; // rule 4 …
    inline constexpr float kLfeIndependentExcess20 = 0.5F;      // …
    inline constexpr float kLfeIndependentP90R2 = 0.3F; // … C4: separates a stem copy down to −6 dB

    // The rule's verdict on `stats` (AsLfeVerdict).
    [[nodiscard]] AsLfeVerdict foldDecideLfe(const AsLfeStats& stats) noexcept;

    // Whether `verdict` puts the LFE in the fold.
    [[nodiscard]] constexpr bool lfeVerdictIncludes(AsLfeVerdict verdict) noexcept
    {
        return verdict == AsLfeVerdictIncludeRedirected ||
               verdict == AsLfeVerdictIncludeIndependent;
    }
} // namespace AdaptiveSound
