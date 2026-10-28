// TrackLoudnessBridge.cpp — the C-ABI over TrackLoudnessProfiler, the loudness-change predictor and the one
// analysis pass, TrackAnalyzer (see include/TrackLoudnessBridge.h).
//
// Pure C++ (no live CoreAudio), so the C++ null test compiles and exercises it directly. The ABI
// is the trust boundary: NULLs and wrong counts are rejected here; the profiler rejects
// non-finite PCM before consuming any of it, and the designer rejects non-finite points.

#include "../include/TrackLoudnessBridge.h"
#include "../EQ/EQDesignerHandle.h"
#include "../EQ/GraphicEQDesigner.h"
#include "ChannelLayoutDecoder.h"
#include "TrackAnalyzer.h"
#include "TrackLoudnessHandle.h"
#include "TrackLoudnessProfiler.h"
#include <array>
#include <cmath>
#include <cstddef>
#include <limits>
#include <memory>
#include <new>
#include <span>
#include <utility>
#include <vector>

struct AsLoudnessProfiler
{
    std::unique_ptr<AdaptiveSound::TrackLoudnessProfiler> profiler;
};

struct AsTrackAnalyzer
{
    std::unique_ptr<AdaptiveSound::TrackAnalyzer> analyzer;
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

// MARK: - The one analysis pass

AsTrackAnalyzer* asTrackAnalyzerCreate(double engineRateHz,
                                       uint32_t channels,
                                       const uint8_t* roles) AUDIODSP_C_NOEXCEPT
{
    if (roles == nullptr || channels == 0U || channels > AdaptiveSound::kMaxChannels)
    {
        return nullptr;
    }
    std::array<AdaptiveSound::ChannelRole, AdaptiveSound::kMaxChannels> decoded{};
    for (uint32_t ch = 0U; ch < channels; ++ch)
    {
        if (roles[ch] > static_cast<uint8_t>(AsChannelRoleMono))
        {
            return nullptr;
        }
        decoded[ch] = static_cast<AdaptiveSound::ChannelRole>(roles[ch]);
    }
    auto analyzer = AdaptiveSound::TrackAnalyzer::create(
        engineRateHz, std::span<const AdaptiveSound::ChannelRole>(decoded.data(), channels));
    if (!analyzer)
    {
        return nullptr;
    }
    auto* handle = new (std::nothrow) AsTrackAnalyzer();
    if (handle != nullptr)
    {
        handle->analyzer = std::move(analyzer);
    }
    return handle;
}

bool asTrackAnalyzerFeed(AsTrackAnalyzer* analyzer,
                         const float* const* channels,
                         uint32_t channelCount,
                         uint32_t frames) AUDIODSP_C_NOEXCEPT
{
    if (analyzer == nullptr || channels == nullptr)
    {
        return false;
    }
    return analyzer->analyzer->feed(std::span<const float* const>(channels, channelCount), frames);
}

bool asTrackAnalyzerFinish(AsTrackAnalyzer* analyzer, AsTrackAnalysis* out) AUDIODSP_C_NOEXCEPT
{
    if (analyzer == nullptr || out == nullptr)
    {
        return false;
    }
    return analyzer->analyzer->finish(*out);
}

uint32_t asTrackAnalyzerHistogram(const AsTrackAnalyzer* analyzer,
                                  uint8_t variant,
                                  AsLoudnessBin* out,
                                  uint32_t capacity) AUDIODSP_C_NOEXCEPT
{
    if (analyzer == nullptr)
    {
        return 0U;
    }
    const std::span<const AsLoudnessBin> bins = analyzer->analyzer->histogram(variant);
    const auto required = static_cast<uint32_t>(bins.size());
    if (out != nullptr && capacity >= required)
    {
        std::ranges::copy(bins, out);
    }
    return required;
}

uint32_t asTrackAnalyzerProfile(const AsTrackAnalyzer* analyzer,
                                uint8_t basis,
                                uint16_t* out,
                                uint32_t capacity) AUDIODSP_C_NOEXCEPT
{
    if (analyzer == nullptr)
    {
        return 0U;
    }
    const AdaptiveSound::TrackLoudnessProfile* profile = analyzer->analyzer->profile(basis);
    if (profile == nullptr)
    {
        return 0U;
    }
    const size_t required = profile->bandPower.size();
    if (out != nullptr && capacity >= required)
    {
        (void)AdaptiveSound::compactPowers(*profile, std::span<uint16_t>(out, required));
    }
    return static_cast<uint32_t>(required);
}

bool asTrackAnalyzerProfileInfo(const AsTrackAnalyzer* analyzer,
                                uint8_t basis,
                                AsCompactProfileInfo* info) AUDIODSP_C_NOEXCEPT
{
    if (analyzer == nullptr || info == nullptr)
    {
        return false;
    }
    const AdaptiveSound::TrackLoudnessProfile* profile = analyzer->analyzer->profile(basis);
    if (profile == nullptr)
    {
        return false;
    }
    AsCompactProfileInfo result{};
    result.sampleRate = profile->sampleRate;
    result.bandsPerOctave = profile->bandsPerOctave;
    result.bandCount = profile->bandCount;
    result.blockCount = profile->blockCount;
    result.blockStrideHops = profile->blockStrideHops;
    *info = result;
    return true;
}

void asTrackAnalyzerDestroy(AsTrackAnalyzer* analyzer) AUDIODSP_C_NOEXCEPT
{
    delete analyzer;
}

double asLoudnessPoolHistograms(const AsLoudnessBin* const* histograms,
                                const uint32_t* counts,
                                uint32_t members) AUDIODSP_C_NOEXCEPT
{
    if (histograms == nullptr || counts == nullptr)
    {
        return std::numeric_limits<double>::quiet_NaN();
    }
    std::vector<std::span<const AsLoudnessBin>> spans;
    spans.reserve(members);
    for (uint32_t member = 0U; member < members; ++member)
    {
        if (histograms[member] == nullptr && counts[member] > 0U)
        {
            return std::numeric_limits<double>::quiet_NaN();
        }
        spans.emplace_back(histograms[member], counts[member]);
    }
    return AdaptiveSound::poolHistogramsLufs(spans);
}

AsLoudnessProfile* asLoudnessProfileFromCompact(const AsCompactProfileInfo* info,
                                                const uint16_t* powers,
                                                uint32_t count) AUDIODSP_C_NOEXCEPT
{
    if (info == nullptr || (powers == nullptr && count > 0U))
    {
        return nullptr;
    }
    return wrap(AdaptiveSound::profileFromCompact(info->sampleRate,
                                                  info->bandsPerOctave,
                                                  info->bandCount,
                                                  info->blockCount,
                                                  info->blockStrideHops,
                                                  std::span<const uint16_t>(powers, count)));
}
