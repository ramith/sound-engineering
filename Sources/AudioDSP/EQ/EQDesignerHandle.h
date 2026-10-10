#pragma once

// EQDesignerHandle.h — the definition behind the C-ABI's opaque AsEqDesigner (EQDesignBridge.h).
//
// Internal to AudioDSP's bridges (never Swift-visible): the EQ design bridge creates and designs
// with it, and the track-loudness bridge (TrackLoudnessBridge.cpp) predicts with the caller's own
// designer, so one owner-local designer serves both calls.

#include "GraphicEQDesigner.h"

struct AsEqDesigner
{
    AdaptiveSound::GraphicEQDesigner designer;
};
