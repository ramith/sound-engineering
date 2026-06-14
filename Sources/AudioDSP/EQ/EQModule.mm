#include "EQModule.h"
#include <cstring>
#include <iostream>

namespace AdaptiveSound {

// MARK: - EQModule Implementation

EQModule::EQModule() = default;

EQModule::~EQModule() = default;

void EQModule::initialize(uint32_t sampleRate, uint32_t maxFrameSize) noexcept {
    sampleRate_ = sampleRate;
    maxFrameSize_ = maxFrameSize;
    // Phase 1a: No state to initialize
    // Phase 1b: Allocate filter state arrays per channel
}

void EQModule::process(const EQParams& params [[maybe_unused]], AudioBufferList* ioData,
                       UInt32 frameCount) noexcept {
    // Phase 1a: Pass-through (no processing)
    // Input audio flows through unchanged
    // All module state (params, filter state) is captured but not applied
    //
    // Phase 1b: Will implement cascaded biquad processing:
    //   for each channel:
    //     for each frame:
    //       for each biquad in params.numBiquads:
    //         apply biquad filter
    //       apply master gain

    // Validate
    if (!ioData || frameCount == 0) {
        return;
    }

    // Currently: audio passes through unmodified
    // This satisfies Phase 1a pass-through mode requirement
}

}  // namespace AdaptiveSound
