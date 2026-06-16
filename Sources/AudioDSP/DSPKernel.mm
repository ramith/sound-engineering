#include "include/DSPKernel.h"
#include "include/MultichannelView.h"
#include "EQ/EQModule.h"
#include "Clarity/ClarityModule.h"
#include "Loudness/LoudnessModule.h"
#include "Spatial/BRIRModule.h"
#include "Limiting/LimiterModule.h"
#include <cstring>

namespace AdaptiveSound {

DSPKernel::DSPKernel() = default;

DSPKernel::~DSPKernel() = default;

// Enable flush-to-zero on the calling thread.
//
// On AArch64 (Apple Silicon) there is a single FPCR.FZ flag (bit 24) that flushes
// both input and output subnormals to zero — equivalent to the combined x86
// FTZ + DAZ pair. The x86 MXCSR.DAZ (denormals-are-zero for inputs) has no
// separate counterpart in AArch64; FPCR.FZ covers both directions.
//
// This must be called on EVERY thread that runs DSP code (the render thread and any
// Audio-Workgroup worker threads), because FPCR is a per-thread register. The kernel
// initialize() call covers the control/init thread; the AU render block sets it on
// the render thread at entry (see AUAudioUnit.mm).
//
// Reference: ARM DDI 0487, §A1.4.3 (FPCR); Apple Silicon LLVM inline-asm guide.
static constexpr uint64_t kFpcrFlushToZeroBit = 1ULL << 24U; // FPCR.FZ
static void enableFlushToZero() noexcept
{
#ifdef __aarch64__
    uint64_t fpcr = 0;
    __asm__ volatile("mrs %0, fpcr" : "=r"(fpcr));
    fpcr |= kFpcrFlushToZeroBit; // flush subnormal inputs and outputs to zero
    __asm__ volatile("msr fpcr, %0" : : "r"(fpcr));
#endif
    // On x86_64 (CI / simulator) Accelerate/vDSP already sets FTZ/DAZ internally;
    // we leave MXCSR alone rather than depend on <xmmintrin.h> / _MM_SET_FLUSH_ZERO_MODE.
}

void DSPKernel::initialize(uint32_t sampleRate, uint32_t maxFrames) noexcept {
    sampleRate_ = sampleRate;
    maxFrames_ = maxFrames;

    // Enable flush-to-zero on the init/control thread. The render thread sets it
    // independently at the top of the AU render block (AUAudioUnit.mm).
    enableFlushToZero();

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

void DSPKernel::publishTargetState(const TargetState& newState) noexcept {
    // Off-RT control path. Build the EQ vDSP setup off-RT (issue #3) before publishing
    // the snapshot, so the RT thread adopts coefficients and setup together.
    //
    // PRECONDITION: single producer. publishCoefficients() below is not safe for
    // concurrent callers, so this method must be driven by a single control thread
    // (the Realizer/control path). A second publisher would require an off-RT mutex.
    if (eqModule_ != nullptr) {
        eqModule_->publishCoefficients(newState.eq);
    }
    targetStateSnapshot_.publish(newState);
}

void DSPKernel::process(AudioBufferList* ioData, uint32_t inNumberFrames) noexcept {
    // Acquire current parameter snapshot (one acquire-load, held for entire buffer)
    const TargetState& state = targetStateSnapshot_.acquireSnapshot();

    // INTENSITY BYPASS: intensityLinear == 0 → bit-exact passthrough (no processing).
    //
    // The AU render block (AUAudioUnit.mm) pulls input directly into the output
    // AudioBufferList (in-place effect), so ioData buffers already hold the input
    // samples by the time process() is called. When intensity is zero we simply
    // return — the output is already equal to the input, so no memcpy is needed.
    // This satisfies the MD5-bit-exact null-test requirement (architecture §null-test).
    //
    // NOTE: if this kernel is ever used outside the in-place AU context (e.g. the
    // Phase-2 process-tap path supplies separate input/output buffers), the caller
    // must ensure input has been copied to output before calling process(), or this
    // function's signature must be extended to accept a separate input ABL.
    if (state.intensityLinear == 0.0F) {
        return;
    }

    // Decode the AudioBufferList ONCE into a non-owning planar view (the single ABL-decode
    // point); every module operates on the MultichannelView and never touches the raw ABL.
    const MultichannelView block = MultichannelView::fromABL(ioData, inNumberFrames);

    // Signal chain: EQ → Clarity → BRIR → Loudness → Limiter
    eqModule_->process(state.eq, block);
    clarityModule_->process(state.clarity, block);
    brirModule_->process(state.brir, block);
    loudnessModule_->process(state.loudness, block);
    limiterModule_->process(state.limiter, block);
}

} // namespace AdaptiveSound
