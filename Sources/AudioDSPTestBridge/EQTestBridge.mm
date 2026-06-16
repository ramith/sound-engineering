// EQTestBridge.mm — Obj-C++ implementation of EQTestBridge.h
//
// Calls the real AdaptiveSound::EQModule and AdaptiveSound::EQModuleCoefficients
// from within an XCTest target.  The pure-C header (EQTestBridge.h) is what
// Swift sees; this file contains all the C++ specifics.

#include "EQTestBridge.h"

// Pull in AudioDSP production code via its public header search path.
// The test target's headerSearchPath entries add Sources/AudioDSP and
// Sources/AudioDSP/include so these includes resolve correctly.
#include "EQ/EQModule.h"
#include "EQ/EQModuleCoefficients.h"
#include "AudioConstants.h" // from include/ search path

#include <AudioToolbox/AudioToolbox.h>
#include <array>
#include <cstring>
#include <algorithm>

// ---------------------------------------------------------------------------
// computeEQCoefficientsC — calls EQModuleCoefficients::computeBiquadCascade
// ---------------------------------------------------------------------------
extern "C" void computeEQCoefficientsC(const float* bandGainsDb,
                                        float sampleRate,
                                        CEQParams* outParams)
{
    if (bandGainsDb == nullptr || outParams == nullptr) {
        return;
    }

    std::array<float, 31> gains{};
    for (int i = 0; i < 31; ++i) {
        gains[static_cast<std::size_t>(i)] = bandGainsDb[i];
    }

    AdaptiveSound::EQParams result =
        AdaptiveSound::EQModuleCoefficients::computeBiquadCascade(gains, sampleRate);

    outParams->numBiquads      = result.numBiquads;
    outParams->masterGainLinear = result.masterGainLinear;

    const int count = std::min(static_cast<int>(result.numBiquads),
                               CEQ_MAX_BIQUADS);
    for (int i = 0; i < count; ++i) {
        outParams->biquads[i].b0 = result.biquads[static_cast<std::size_t>(i)].b0;
        outParams->biquads[i].b1 = result.biquads[static_cast<std::size_t>(i)].b1;
        outParams->biquads[i].b2 = result.biquads[static_cast<std::size_t>(i)].b2;
        outParams->biquads[i].a1 = result.biquads[static_cast<std::size_t>(i)].a1;
        outParams->biquads[i].a2 = result.biquads[static_cast<std::size_t>(i)].a2;
    }
}

// ---------------------------------------------------------------------------
// eqModuleProcessC — wraps a real EQModule lifecycle (init → publish → process)
//
// A two-channel AudioBufferList is constructed pointing at the caller's buffer
// for channel 0 (left) and a temporary zeroed buffer for channel 1 (right).
// Only the left channel is exposed to the Swift test, which is inherently mono.
//
// AudioBufferList layout: non-interleaved stereo (mNumberBuffers = 2).
// ---------------------------------------------------------------------------
extern "C" void eqModuleProcessC(float* ioBuffer,
                                  const CEQParams* params,
                                  uint32_t numFrames)
{
    if (ioBuffer == nullptr || params == nullptr || numFrames == 0U) {
        return;
    }

    // Clamp to EQModule's kMaxFramesCeil
    const uint32_t safeFrames = std::min(numFrames,
                                          AdaptiveSound::kDefaultMaxFrames);

    // Build production EQParams from the C mirror
    AdaptiveSound::EQParams eqParams{};
    eqParams.masterGainLinear = params->masterGainLinear;
    const uint8_t numBiquads =
        static_cast<uint8_t>(std::min(static_cast<int>(params->numBiquads),
                                       CEQ_MAX_BIQUADS));
    eqParams.numBiquads = numBiquads;
    for (int i = 0; i < static_cast<int>(numBiquads); ++i) {
        eqParams.biquads[static_cast<std::size_t>(i)].b0 = params->biquads[i].b0;
        eqParams.biquads[static_cast<std::size_t>(i)].b1 = params->biquads[i].b1;
        eqParams.biquads[static_cast<std::size_t>(i)].b2 = params->biquads[i].b2;
        eqParams.biquads[static_cast<std::size_t>(i)].a1 = params->biquads[i].a1;
        eqParams.biquads[static_cast<std::size_t>(i)].a2 = params->biquads[i].a2;
    }

    // Temporary right-channel scratch (zeroed)
    std::array<float, AdaptiveSound::kDefaultMaxFrames> rightScratch{};

    // Build a two-channel non-interleaved AudioBufferList.
    // AudioBufferList has a C flexible-array member mBuffers[1], so we need
    // contiguous storage for two AudioBuffer entries.  Use the same two-struct
    // pattern as DSPKernelNullTest.cpp (AudioBufferList2).
    struct ABL2 {
        AudioBufferList head;
        AudioBuffer     extra;
    } abl2{};

    abl2.head.mNumberBuffers              = 2U;
    abl2.head.mBuffers[0].mNumberChannels = 1U;
    abl2.head.mBuffers[0].mDataByteSize   = safeFrames * static_cast<uint32_t>(sizeof(float));
    abl2.head.mBuffers[0].mData           = ioBuffer;
    abl2.extra.mNumberChannels            = 1U;
    abl2.extra.mDataByteSize              = safeFrames * static_cast<uint32_t>(sizeof(float));
    abl2.extra.mData                      = rightScratch.data();

    // Create a real EQModule, initialize it, publish coefficients, then process.
    AdaptiveSound::EQModule module;
    module.initialize(AdaptiveSound::kDefaultSampleRate, AdaptiveSound::kDefaultMaxFrames);
    module.publishCoefficients(eqParams);

    // Give the RT thread a chance to adopt the pending setup.
    // process() performs the atomic swap internally on its first call.
    module.process(eqParams, AdaptiveSound::MultichannelView::fromABL(&abl2.head, safeFrames));
}
