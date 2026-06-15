#include "EQModule.h"
#include <Accelerate/Accelerate.h>

namespace AdaptiveSound
{

// Pointer-width atomics must be lock-free for the RT setup swap to be wait-free.
static_assert(std::atomic<void*>::is_always_lock_free,
              "EQModule requires lock-free pointer atomics for RT-safe setup swaps");

namespace
{
    // Destroy a setup held in an atomic slot, if any (off-RT only).
    void destroySlot(std::atomic<void*>& slot) noexcept
    {
        void* setupPtr = slot.exchange(nullptr, std::memory_order_acq_rel);
        if (setupPtr != nullptr) {
            vDSP_biquad_DestroySetup(static_cast<vDSP_biquad_Setup>(setupPtr));
        }
    }
} // namespace

EQModule::~EQModule()
{
    // Destructor runs off-RT; drain every slot and free any live setup.
    destroySlot(activeSetup_);
    destroySlot(pendingSetup_);
    destroySlot(toReleaseSetup_);
}

void EQModule::initialize(uint32_t sampleRate, uint32_t maxFrames) noexcept
{
    sampleRate_ = sampleRate;
    maxFrames_ = maxFrames;

    // Reset per-channel delay state (issue #2).
    leftDelay_.fill(0.0F);
    rightDelay_.fill(0.0F);

    // Seed coefficients to an all-identity cascade (b0=1, rest 0 per section).
    cascadeCoeffs_.fill(0.0);
    for (size_t i = 0; i < static_cast<size_t>(kMaxBiquads); ++i) {
        cascadeCoeffs_[i * kCoeffsPerBiquad] = 1.0; // b0
    }

    // Create the initial (identity) setup once, off-RT. Until publishCoefficients()
    // supplies real coefficients, the cascade passes audio through unchanged.
    destroySlot(activeSetup_);
    vDSP_biquad_Setup setup =
        vDSP_biquad_CreateSetup(cascadeCoeffs_.data(), static_cast<vDSP_Length>(kMaxBiquads));
    activeSetup_.store(static_cast<void*>(setup), std::memory_order_release);
}

void EQModule::publishCoefficients(const EQParams& params) noexcept
{
    // OFF-RT ONLY. Pack the active sections, identity-pad the rest, build a new
    // fixed-size (kMaxBiquads) setup, and hand it to the RT thread via pendingSetup_.
    const size_t numActive =
        std::min(static_cast<size_t>(params.numBiquads), static_cast<size_t>(kMaxBiquads));

    for (size_t i = 0; i < numActive; ++i) {
        const auto& coeffs = params.biquads[i];
        const size_t offset = i * kCoeffsPerBiquad;
        cascadeCoeffs_[offset + 0] = static_cast<double>(coeffs.b0);
        cascadeCoeffs_[offset + 1] = static_cast<double>(coeffs.b1);
        cascadeCoeffs_[offset + 2] = static_cast<double>(coeffs.b2);
        cascadeCoeffs_[offset + 3] = static_cast<double>(coeffs.a1);
        cascadeCoeffs_[offset + 4] = static_cast<double>(coeffs.a2);
    }
    for (size_t i = numActive; i < static_cast<size_t>(kMaxBiquads); ++i) {
        const size_t offset = i * kCoeffsPerBiquad;
        cascadeCoeffs_[offset + 0] = 1.0; // identity: b0=1
        cascadeCoeffs_[offset + 1] = 0.0;
        cascadeCoeffs_[offset + 2] = 0.0;
        cascadeCoeffs_[offset + 3] = 0.0;
        cascadeCoeffs_[offset + 4] = 0.0;
    }

    vDSP_biquad_Setup newSetup =
        vDSP_biquad_CreateSetup(cascadeCoeffs_.data(), static_cast<vDSP_Length>(kMaxBiquads));
    if (newSetup == nullptr) {
        return; // Accelerate failure — keep the existing setup running.
    }

    // Publish. If a prior pending setup was never consumed by the RT thread
    // (two updates before one render), destroy the unclaimed one here (off-RT).
    void* unclaimed = pendingSetup_.exchange(static_cast<void*>(newSetup), std::memory_order_acq_rel);
    if (unclaimed != nullptr) {
        vDSP_biquad_DestroySetup(static_cast<vDSP_biquad_Setup>(unclaimed));
    }

    // Drain any setup the RT thread retired into toReleaseSetup_ and free it here.
    destroySlot(toReleaseSetup_);
}

void EQModule::process(const EQParams& params, AudioBufferList* ioData, uint32_t frameCount) noexcept
{
    if (ioData == nullptr || frameCount == 0) {
        return;
    }

    // RT-safe setup adoption: if a new setup was published, swap it in and retire the
    // old one for off-RT destruction. All operations are lock-free atomics — no alloc,
    // no free, no lock on the render thread.
    void* pending = pendingSetup_.exchange(nullptr, std::memory_order_acq_rel);
    if (pending != nullptr) {
        void* old = activeSetup_.exchange(pending, std::memory_order_acq_rel);
        void* orphan = toReleaseSetup_.exchange(old, std::memory_order_acq_rel);
        // Pathological only (off-RT severely behind): we cannot DestroySetup on the
        // RT thread, so intentionally leak the orphan rather than free/block here.
        (void)orphan;

        // Delay state is intentionally PRESERVED across swaps. The cascade is a fixed
        // kMaxBiquads topology, so the 2*kMaxBiquads+2 delay layout is invariant and the
        // existing state is valid input to the new coefficients — continuous filter
        // memory is click-free, whereas re-zeroing would inject a discontinuity on every
        // EQ change. (Confirmed by audio-dsp-agent + cpp-pro; obsoletes the #2 re-zero,
        // which only existed because the section count — and thus the layout — varied.)
    }

    vDSP_biquad_Setup setup = static_cast<vDSP_biquad_Setup>(activeSetup_.load(std::memory_order_acquire));
    if (setup == nullptr) {
        return;
    }

    // Only process the first 2 channels (stereo).
    uint32_t numChannels = ioData->mNumberBuffers > 2 ? 2 : ioData->mNumberBuffers;

    float* leftBuffer = nullptr;
    float* rightBuffer = nullptr;
    if (numChannels >= 1) {
        leftBuffer = static_cast<float*>(ioData->mBuffers[0].mData);
    }
    if (numChannels >= 2) {
        rightBuffer = static_cast<float*>(ioData->mBuffers[1].mData);
    }

    // Run each channel through the fixed kMaxBiquads-section cascade (identity-padded)
    // with its own independent delay state.
    if (leftBuffer != nullptr) {
        vDSP_biquad(setup, leftDelay_.data(), leftBuffer, 1, leftBuffer, 1,
                    static_cast<vDSP_Length>(frameCount));
    }
    if (rightBuffer != nullptr) {
        vDSP_biquad(setup, rightDelay_.data(), rightBuffer, 1, rightBuffer, 1,
                    static_cast<vDSP_Length>(frameCount));
    }

    // Apply master gain scaling (linear amplitude).
    if (params.masterGainLinear != 1.0F) {
        float gain = params.masterGainLinear;
        if (leftBuffer != nullptr) {
            vDSP_vsmul(leftBuffer, 1, &gain, leftBuffer, 1, static_cast<vDSP_Length>(frameCount));
        }
        if (rightBuffer != nullptr) {
            vDSP_vsmul(rightBuffer, 1, &gain, rightBuffer, 1, static_cast<vDSP_Length>(frameCount));
        }
    }
}

} // namespace AdaptiveSound
