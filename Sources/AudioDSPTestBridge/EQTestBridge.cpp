// EQTestBridge.cpp — C++ implementation of EQTestBridge.h, over the real production EQ.

#include "EQTestBridge.h"

// AudioDSP production code via the target's header search paths (../AudioDSP, ../AudioDSP/include).
#include "AudioConstants.h"
#include "EQ/EQModule.h"
#include "EQ/EQTargets.h"
#include "EQ/GraphicEQDesigner.h"
#include "MultichannelView.h"

#include <algorithm>
#include <array>
#include <AudioToolbox/AudioToolbox.h>
#include <memory>
#include <span>
#include <vector>

namespace
{
    constexpr uint32_t kBlockFrames = 512U;

    // Design `points` at `sampleRate`; false when the points or the rate are rejected.
    bool designFor(const float* points,
                   uint32_t pointCount,
                   double sampleRate,
                   AdaptiveSound::GraphicEQDesign& design)
    {
        if (points == nullptr || pointCount != static_cast<uint32_t>(AdaptiveSound::kEqBandCount))
        {
            return false;
        }
        auto designer = std::make_unique<AdaptiveSound::GraphicEQDesigner>();
        return designer->design(
            std::span<const float, AdaptiveSound::kEqBandCount>(points, pointCount),
            sampleRate,
            design);
    }
} // namespace

extern "C" bool eqStreamC(float* ioBuffer,
                          uint32_t frameCount,
                          const float* points,
                          uint32_t pointCount,
                          double sampleRate) AUDIODSP_C_NOEXCEPT
{
    AdaptiveSound::GraphicEQDesign design{};
    if (ioBuffer == nullptr || !designFor(points, pointCount, sampleRate, design))
    {
        return false;
    }
    const AdaptiveSound::EQParams params =
        AdaptiveSound::EQTargets::toParams(design, AdaptiveSound::kEqDefaultRampSeconds);

    auto module = std::make_unique<AdaptiveSound::EQModule>();
    module->initialize(static_cast<uint32_t>(sampleRate), kBlockFrames);

    // A two-channel non-interleaved AudioBufferList (the flexible-array idiom: head + one extra).
    struct ABL2
    {
        AudioBufferList head;
        AudioBuffer extra;
    } abl{};
    std::vector<float> right(kBlockFrames, 0.0F);
    for (uint32_t offset = 0U; offset < frameCount; offset += kBlockFrames)
    {
        const uint32_t frames = std::min(kBlockFrames, frameCount - offset);
        std::copy_n(ioBuffer + offset, frames, right.begin());
        abl.head.mNumberBuffers = 2U;
        abl.head.mBuffers[0].mNumberChannels = 1U;
        abl.head.mBuffers[0].mDataByteSize = frames * static_cast<uint32_t>(sizeof(float));
        abl.head.mBuffers[0].mData = ioBuffer + offset;
        abl.extra.mNumberChannels = 1U;
        abl.extra.mDataByteSize = frames * static_cast<uint32_t>(sizeof(float));
        abl.extra.mData = right.data();
        module->update(params);
        module->process(AdaptiveSound::MultichannelView::fromABL(&abl.head, frames));
    }
    return true;
}

extern "C" bool eqPlayedCentresC(const float* points,
                                 uint32_t pointCount,
                                 double sampleRate,
                                 float* outCentreDb) AUDIODSP_C_NOEXCEPT
{
    AdaptiveSound::GraphicEQDesign design{};
    if (outCentreDb == nullptr || !designFor(points, pointCount, sampleRate, design))
    {
        return false;
    }
    for (int band = 0; band < AdaptiveSound::kEqBandCount; ++band)
    {
        outCentreDb[band] = static_cast<float>(AdaptiveSound::GraphicEQDesigner::playedDb(
            design, AdaptiveSound::GraphicEQ::centreHz(band)));
    }
    return true;
}
