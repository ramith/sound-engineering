#include "BRIRModule.h"
#include <cstring>
#include <iostream>

namespace AdaptiveSound {

// MARK: - BRIRModule Implementation

BRIRModule::BRIRModule() = default;

BRIRModule::~BRIRModule() = default;

void BRIRModule::initialize(uint32_t sampleRate, uint32_t maxFrameSize) noexcept {
    sampleRate_ = sampleRate;
    maxFrameSize_ = maxFrameSize;
    // Phase 1a: No state to initialize
    // Phase 1b: Allocate convolver state, FFT buffers, IR slot storage
}

void BRIRModule::process(const BRIRParams& params [[maybe_unused]], AudioBufferList* ioData,
                         UInt32 frameCount) noexcept {
    // Phase 1a: Pass-through (no processing)
    // Input audio flows through unchanged
    // All module state (params, convolver state, IR slots) is captured but not applied
    //
    // Phase 1b: Will implement fast convolution with atomic slot-switching:
    //   1. Check if activeSlotIndex has changed (atomic load)
    //      - If so, switch convolver to new IR slot
    //   2. Apply fast convolution (overlap-add FFT) to current IR slot
    //   3. Ramp roomAmountLinear and blend: output = dry*roomAmt + convolved*(1-roomAmt)
    //   4. If bassMonoGated: reduce bass to mono below ~80 Hz
    //   5. Ramp spatial parameters (azimuth, elevation) for HRTF morphing (future)

    // Validate
    if (!ioData || frameCount == 0) {
        return;
    }

    // Currently: audio passes through unmodified
    // This satisfies Phase 1a pass-through mode requirement
}

}  // namespace AdaptiveSound
