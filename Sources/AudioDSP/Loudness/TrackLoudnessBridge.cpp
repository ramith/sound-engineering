// TrackLoudnessBridge.cpp — the C-ABI over TrackLoudnessProfiler and the loudness-change predictor
// (see include/TrackLoudnessBridge.h).
//
// Pure C++ (no live CoreAudio), so the C++ null test compiles and exercises it directly. The ABI
// is the trust boundary: NULLs and wrong counts are rejected here; the profiler rejects
// non-finite PCM before consuming any of it, and the designer rejects non-finite points.

#include "../include/TrackLoudnessBridge.h"
#include "../EQ/EQDesignerHandle.h"
#include "../EQ/GraphicEQDesigner.h"
#include "ChannelLayoutDecoder.h"
#include "TrackLoudnessHandle.h"
#include "TrackLoudnessProfiler.h"
#include <cstddef>
#include <memory>
#include <new>
#include <span>
#include <utility>

struct AsLoudnessProfiler
{
    std::unique_ptr<AdaptiveSound::TrackLoudnessProfiler> profiler;
};

namespace
{
    using AdaptiveSound::GraphicEQ::kBandCount;
    constexpr auto kBands = static_cast<size_t>(kBandCount);

    // The BS.1770-5 weights for `channelCount` channels: the decoded layout's when it describes
    // exactly that many channels, otherwise the neutral 1.0 for every channel.
    [[nodiscard]] AdaptiveSound::TrackLoudnessProfiler::Format
    formatFor(double sampleRate, uint32_t channelCount, AudioChannelLayoutTag layoutTag) noexcept
    {
        AdaptiveSound::TrackLoudnessProfiler::Format format;
        format.sampleRate = sampleRate;
        format.channelCount = channelCount;
        format.channelWeights.fill(1.0);
        const AdaptiveSound::ChannelLayout layout = AdaptiveSound::decodeChannelLayout(layoutTag);
        if (layout.numChannels == channelCount)
        {
            for (uint32_t ch = 0U; ch < channelCount; ++ch)
            {
                format.channelWeights[ch] = static_cast<double>(layout.lufsWeight[ch]);
            }
        }
        return format;
    }

    [[nodiscard]] AsLoudnessProfile*
    wrap(std::shared_ptr<const AdaptiveSound::TrackLoudnessProfile> profile) noexcept
    {
        if (!profile)
        {
            return nullptr;
        }
        auto* handle = new (std::nothrow) AsLoudnessProfile();
        if (handle != nullptr)
        {
            handle->profile = std::move(profile);
        }
        return handle;
    }
} // namespace

AsLoudnessProfiler* asLoudnessProfilerCreate(double sampleRate,
                                             uint32_t channelCount,
                                             AudioChannelLayoutTag layoutTag) AUDIODSP_C_NOEXCEPT
{
    auto profiler = AdaptiveSound::TrackLoudnessProfiler::create(
        formatFor(sampleRate, channelCount, layoutTag));
    if (!profiler)
    {
        return nullptr;
    }
    auto* handle = new (std::nothrow) AsLoudnessProfiler();
    if (handle != nullptr)
    {
        handle->profiler = std::move(profiler);
    }
    return handle;
}

bool asLoudnessProfilerFeed(AsLoudnessProfiler* profiler,
                            const float* const* channels,
                            uint32_t channelCount,
                            uint32_t frameCount) AUDIODSP_C_NOEXCEPT
{
    if (profiler == nullptr || channels == nullptr)
    {
        return false;
    }
    return profiler->profiler->feed(std::span<const float* const>(channels, channelCount),
                                    frameCount);
}

AsLoudnessProfile* asLoudnessProfilerFinishPrefix(AsLoudnessProfiler* profiler) AUDIODSP_C_NOEXCEPT
{
    if (profiler == nullptr)
    {
        return nullptr;
    }
    return wrap(profiler->profiler->snapshot());
}

AsLoudnessProfile* asLoudnessProfilerFinishFull(AsLoudnessProfiler* profiler) AUDIODSP_C_NOEXCEPT
{
    if (profiler == nullptr)
    {
        return nullptr;
    }
    return wrap(profiler->profiler->finish());
}

void asLoudnessProfilerDestroy(AsLoudnessProfiler* profiler) AUDIODSP_C_NOEXCEPT
{
    delete profiler;
}

void asLoudnessProfileDestroy(AsLoudnessProfile* profile) AUDIODSP_C_NOEXCEPT
{
    delete profile;
}

bool asLoudnessProfileGetInfo(const AsLoudnessProfile* profile,
                              AsLoudnessProfileInfo* info) AUDIODSP_C_NOEXCEPT
{
    if (profile == nullptr || info == nullptr)
    {
        return false;
    }
    const AdaptiveSound::TrackLoudnessProfile& value = *profile->profile;
    AsLoudnessProfileInfo result{};
    result.sampleRate = value.sampleRate;
    result.analysedSeconds = static_cast<double>(value.analysedFrames) / value.sampleRate;
    result.sourceLoudnessLufs = value.sourceLoudnessLufs;
    result.channelCount = value.channelCount;
    result.bandCount = value.bandCount;
    result.blockCount = value.blockCount;
    result.blockStrideHops = value.blockStrideHops;
    result.wholeTrack = value.wholeTrack;
    *info = result;
    return true;
}

bool asLoudnessPredictChangeDb(const AsLoudnessProfile* profile,
                               AsEqDesigner* designer,
                               const float* pointsDb,
                               uint32_t pointCount,
                               double outputSampleRate,
                               double* changeDb) AUDIODSP_C_NOEXCEPT
{
    if (profile == nullptr || designer == nullptr || pointsDb == nullptr || changeDb == nullptr ||
        pointCount != static_cast<uint32_t>(kBandCount))
    {
        return false;
    }
    AdaptiveSound::GraphicEQDesign design{};
    if (!designer->designer.design(
            std::span<const float, kBandCount>(pointsDb, kBands), outputSampleRate, design))
    {
        return false;
    }
    double change = 0.0;
    if (!AdaptiveSound::predictLoudnessChangeDb(*profile->profile, design, 1U, change))
    {
        return false;
    }
    *changeDb = change;
    return true;
}
