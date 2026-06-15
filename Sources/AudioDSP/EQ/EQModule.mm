#include "EQModule.h"
#include <Accelerate/Accelerate.h>
#include <cstring>

namespace AdaptiveSound
{

EQModule::~EQModule()
{
    // Destroy the cascade setup if it exists
    if (cascadeSetup_ != nullptr) {
        vDSP_biquad_DestroySetup(static_cast<vDSP_biquad_Setup>(cascadeSetup_));
    }
}

void EQModule::initialize(uint32_t sampleRate, uint32_t maxFrames) noexcept
{
    sampleRate_ = sampleRate;
    maxFrames_ = maxFrames;

    // Reset per-channel delay state (also zero-initialized in the header; re-zero
    // here so a second initialize() — e.g. on sample-rate change — starts clean).
    leftDelay_.fill(0.0F);
    rightDelay_.fill(0.0F);
    cachedNumBiquads_ = 0;

    // Pre-allocate coefficient array for cascade (5 coeffs per stage)
    cascadeCoeffs_.resize(static_cast<size_t>(kMaxBiquads) * kCoeffsPerBiquad, 0.0);
}

void EQModule::process(const EQParams& params, AudioBufferList* ioData, uint32_t frameCount) noexcept
{
    if (ioData == nullptr || frameCount == 0 || params.numBiquads == 0) {
        return;
    }

    // Only process first 2 channels (stereo)
    uint32_t numChannels = ioData->mNumberBuffers > 2 ? 2 : ioData->mNumberBuffers;
    if (numChannels == 0) {
        return;
    }

    // Get pointers to audio data
    float* leftBuffer = nullptr;
    float* rightBuffer = nullptr;

    if (numChannels >= 1) {
        leftBuffer = static_cast<float*>(ioData->mBuffers[0].mData);
    }
    if (numChannels >= 2) {
        rightBuffer = static_cast<float*>(ioData->mBuffers[1].mData);
    }

    // If the cascade section count changed, the persisted delay state belongs to a
    // different cascade and is structurally mismatched — re-zero it to avoid a click.
    if (params.numBiquads != cachedNumBiquads_) {
        leftDelay_.fill(0.0F);
        rightDelay_.fill(0.0F);
        cachedNumBiquads_ = params.numBiquads;
    }

    // Pack coefficients for all active stages into cascadeCoeffs_
    // vDSP expects: [b0_0, b1_0, b2_0, a1_0, a2_0, b0_1, b1_1, ...]
    for (size_t i = 0; i < static_cast<size_t>(params.numBiquads) && i < static_cast<size_t>(kMaxBiquads); ++i) {
        const auto& coeffs = params.biquads[i];
        size_t offset = i * kCoeffsPerBiquad;
        cascadeCoeffs_[offset + 0] = coeffs.b0;
        cascadeCoeffs_[offset + 1] = coeffs.b1;
        cascadeCoeffs_[offset + 2] = coeffs.b2;
        cascadeCoeffs_[offset + 3] = coeffs.a1;
        cascadeCoeffs_[offset + 4] = coeffs.a2;
    }

    // Create or update cascade setup
    // Destroy old setup if coefficients changed
    // TODO(#3): vDSP setup create/destroy on RT thread (malloc/free); fix separately
    if (cascadeSetup_ != nullptr) {
        vDSP_biquad_DestroySetup(static_cast<vDSP_biquad_Setup>(cascadeSetup_));
        cascadeSetup_ = nullptr;
    }

    // Create new setup with all active cascade stages
    vDSP_biquad_Setup setup = vDSP_biquad_CreateSetup(cascadeCoeffs_.data(), static_cast<vDSP_Length>(params.numBiquads));
    if (setup == nullptr) {
        return;  // Setup creation failed, skip processing
    }
    cascadeSetup_ = setup;

    // Process each channel through the cascade with its own independent delay state.
    if (leftBuffer != nullptr) {
        vDSP_biquad(setup, leftDelay_.data(),
                    leftBuffer, 1,
                    leftBuffer, 1,
                    frameCount);
    }

    if (rightBuffer != nullptr) {
        vDSP_biquad(setup, rightDelay_.data(),
                    rightBuffer, 1,
                    rightBuffer, 1,
                    frameCount);
    }

    // Apply master gain scaling (linear amplitude)
    if (params.masterGainLinear != 1.0F) {
        float gain = params.masterGainLinear;

        if (leftBuffer != nullptr) {
            vDSP_vsmul(leftBuffer, 1, &gain, leftBuffer, 1, frameCount);
        }

        if (rightBuffer != nullptr) {
            vDSP_vsmul(rightBuffer, 1, &gain, rightBuffer, 1, frameCount);
        }
    }
}

} // namespace AdaptiveSound
