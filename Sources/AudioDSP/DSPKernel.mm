#include "include/DSPKernel.h"
#include "EQ/EQModule.h"
#include "Clarity/ClarityModule.h"
#include "Loudness/LoudnessModule.h"
#include "Spatial/BRIRModule.h"
#include "Limiting/LimiterModule.h"

namespace AdaptiveSound {

DSPKernel::DSPKernel() = default;

DSPKernel::~DSPKernel() = default;

void DSPKernel::initialize(uint32_t sampleRate, uint32_t maxFrames) noexcept {
    sampleRate_ = sampleRate;
    maxFrames_ = maxFrames;

    // Create all 5 DSP modules
    eqModule_ = std::make_unique<EQModule>();
    clarityModule_ = std::make_unique<ClarityModule>();
    brirModule_ = std::make_unique<BRIRModule>();
    loudnessModule_ = std::make_unique<LoudnessModule>();
    limiterModule_ = std::make_unique<LimiterModule>();

    // Initialize each module with sample rate and max frame count
    eqModule_->initialize(sampleRate, maxFrames);
    clarityModule_->initialize(sampleRate, maxFrames);
    brirModule_->initialize(sampleRate, maxFrames);
    loudnessModule_->initialize(sampleRate, maxFrames);
    limiterModule_->initialize(sampleRate, maxFrames);
}

void DSPKernel::process(AudioBufferList* ioData, uint32_t inNumberFrames) noexcept {
    // Acquire current parameter snapshot (one acquire-load, held for entire buffer)
    const TargetState& state = targetStateSnapshot_.acquireSnapshot();

    // Signal chain: EQ → Clarity → BRIR → Loudness → Limiter
    eqModule_->process(state.eq, ioData, inNumberFrames);
    clarityModule_->process(state.clarity, ioData, inNumberFrames);
    brirModule_->process(state.brir, ioData, inNumberFrames);
    loudnessModule_->process(state.loudness, ioData, inNumberFrames);
    limiterModule_->process(state.limiter, ioData, inNumberFrames);
}

} // namespace AdaptiveSound
