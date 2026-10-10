#pragma once

// TrackLoudnessHandle.h — the definition behind the C-ABI's opaque AsLoudnessProfile
// (TrackLoudnessBridge.h).
//
// Internal to AudioDSP's bridges (never Swift-visible). A profile handle is one shared reference
// to an immutable profile, so publishing it to the engine (EQ1c part 2) copies the reference, not
// the blocks, and the Swift caller can release its handle independently.

#include "TrackLoudnessProfile.h"
#include <memory>

struct AsLoudnessProfile
{
    std::shared_ptr<const AdaptiveSound::TrackLoudnessProfile> profile;
};
