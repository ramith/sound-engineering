// CausalLoudnessTap.cpp — the causal running loudness estimate. See CausalLoudnessTap.h.

#include "CausalLoudnessTap.h"
#include "../include/FlushToZero.h"
#include "TrackLoudnessProfiler.h"
#include <algorithm>
#include <chrono>
#include <cmath>
#include <utility>

namespace AdaptiveSound
{
    namespace
    {
        // The worker's sleep with no estimate running, and with the ring empty while one runs.
        constexpr auto kIdleSleep = std::chrono::milliseconds(50);
        constexpr auto kDrainSleep = std::chrono::milliseconds(10);
    } // namespace

    CausalLoudnessTap::~CausalLoudnessTap()
    {
        stop();
        // worker_ (the last member) is destroyed first: request_stop() + join().
    }

    void CausalLoudnessTap::initialize(uint32_t sampleRate, uint32_t maxFrames) noexcept
    {
        sampleRate_ = sampleRate;
        maxFrames_ = maxFrames;
        pushBuf_.assign(static_cast<size_t>(maxFrames) * kMaxChannels, 0.0F);
        chunk_.assign(kChunkFrames * kMaxChannels, 0.0F);
        planar_.assign(kChunkFrames * kMaxChannels, 0.0F);
        // Start the worker LAST, after everything it touches exists.
        worker_ = std::jthread([this](const std::stop_token& stopToken) { run(stopToken); });
    }

    void CausalLoudnessTap::start(Sink sink) noexcept
    {
        {
            const std::scoped_lock lock(sinkMutex_);
            sink_ = std::move(sink);
        }
        generation_.fetch_add(1U, std::memory_order_acq_rel);
        running_.store(true, std::memory_order_release);
    }

    void CausalLoudnessTap::stop() noexcept
    {
        running_.store(false, std::memory_order_release);
        // The worker calls the sink only under this mutex, so once it is cleared here no call can
        // follow (and none is in flight once the lock is ours).
        const std::scoped_lock lock(sinkMutex_);
        sink_ = nullptr;
    }

    void CausalLoudnessTap::publishChannelLayout(const ChannelLayout& layout) noexcept
    {
        std::array<double, kMaxChannels> weights{};
        bool anyPositive = false;
        for (uint32_t ch = 0U; ch < kMaxChannels; ++ch)
        {
            const auto weight = static_cast<double>(layout.lufsWeight[ch]);
            weights[ch] = (std::isfinite(weight) && weight > 0.0) ? weight : 0.0;
            anyPositive = anyPositive || weights[ch] > 0.0;
        }
        if (!anyPositive)
        {
            weights.fill(1.0); // a layout with no weighted channel: the neutral fallback
        }
        const std::scoped_lock lock(sinkMutex_);
        weights_ = weights;
    }

    void CausalLoudnessTap::push(const MultichannelView& block) noexcept
    {
        if (!running_.load(std::memory_order_relaxed))
        {
            return;
        }
        const uint32_t channels = std::min(block.channels(), kMaxChannels);
        const uint32_t frames = std::min(block.frames(), maxFrames_);
        if (channels == 0U || frames == 0U)
        {
            return;
        }
        channelCount_.store(channels, std::memory_order_release);
        for (uint32_t ch = 0U; ch < channels; ++ch)
        {
            const float* src = block.channel(ch);
            for (uint32_t i = 0U; i < frames; ++i)
            {
                pushBuf_[(static_cast<size_t>(i) * channels) + ch] =
                    (src != nullptr) ? src[i] : 0.0F;
            }
        }
        // All or nothing, so the ring only ever holds whole frames and the worker's frame-aligned
        // reads stay aligned.
        if (!ring_.tryPushAll(pushBuf_.data(), static_cast<size_t>(frames) * channels))
        {
            droppedFrames_.fetch_add(frames, std::memory_order_relaxed);
        }
    }

    std::unique_ptr<TrackLoudnessProfiler>
    CausalLoudnessTap::makeProfiler(uint32_t channels) noexcept
    {
        TrackLoudnessProfiler::Format format{};
        format.sampleRate = static_cast<double>(sampleRate_);
        format.channelCount = channels;
        {
            const std::scoped_lock lock(sinkMutex_);
            format.channelWeights = weights_;
        }
        // A layout for more channels than this stream carries may weight every carried channel 0
        // (e.g. a stale LFE-only slot): fall back to neutral weights rather than no estimate.
        const bool anyPositive = std::any_of(format.channelWeights.begin(),
                                             format.channelWeights.begin() + channels,
                                             [](double weight) { return weight > 0.0; });
        if (!anyPositive)
        {
            format.channelWeights.fill(1.0);
        }
        return TrackLoudnessProfiler::create(format);
    }

    void CausalLoudnessTap::feed(TrackLoudnessProfiler& profiler,
                                 uint32_t channels,
                                 size_t frames) noexcept
    {
        std::array<const float*, kMaxChannels> pointers{};
        for (uint32_t ch = 0U; ch < channels; ++ch)
        {
            float* dst = planar_.data() + (static_cast<size_t>(ch) * kChunkFrames);
            for (size_t i = 0U; i < frames; ++i)
            {
                const float sample = chunk_[(i * channels) + ch];
                dst[i] =
                    std::isfinite(sample) ? sample : 0.0F; // the profiler rejects non-finite PCM
            }
            pointers[ch] = dst;
        }
        if (profiler.feed(std::span<const float* const>(pointers.data(), channels), frames))
        {
            fedFrames_.fetch_add(frames, std::memory_order_acq_rel);
        }
    }

    void CausalLoudnessTap::emit(const TrackLoudnessProfiler& profiler) noexcept
    {
        std::shared_ptr<const TrackLoudnessProfile> snapshot = profiler.snapshot();
        if (!snapshot)
        {
            return; // not one whole 400 ms block yet
        }
        const std::scoped_lock lock(sinkMutex_);
        if (sink_ && running_.load(std::memory_order_acquire))
        {
            sink_(std::move(snapshot));
        }
    }

    void CausalLoudnessTap::discardRing() noexcept
    {
        while (ring_.popBlock(chunk_.data(), chunk_.size()) > 0U)
        {
        }
    }

    bool CausalLoudnessTap::prepare(Worker& worker) noexcept
    {
        const uint64_t generation = generation_.load(std::memory_order_acquire);
        const uint32_t channels = channelCount_.load(std::memory_order_acquire);
        if (channels == 0U)
        {
            return false; // no audio has arrived yet
        }
        if (worker.profiler && generation == worker.estimate && channels == worker.channels)
        {
            return true;
        }
        // A new estimate restarts on the audio in the ring (pushed since start(); a restart while
        // running may carry a few ms of the previous track — harmless). A new channel count (only
        // at the stream's first push: a re-allocation rebuilds the tap) drops the ring, whose
        // frames have the old width.
        if (worker.channels != 0U && channels != worker.channels)
        {
            discardRing();
        }
        worker.profiler = makeProfiler(channels);
        worker.estimate = generation;
        worker.channels = channels;
        worker.sinceSnapshot = 0U;
        fedFrames_.store(0U, std::memory_order_release);
        return worker.profiler != nullptr;
    }

    bool CausalLoudnessTap::drainOnce(Worker& worker) noexcept
    {
        const size_t capacity = kChunkFrames * worker.channels;
        const size_t got = ring_.popBlock(chunk_.data(), capacity);
        if (got == 0U)
        {
            return false;
        }
        // The ring holds whole frames only (tryPushAll) and `capacity` is frame-aligned.
        const size_t frames = got / worker.channels;
        feed(*worker.profiler, worker.channels, frames);
        worker.sinceSnapshot += frames;
        const auto snapshotFrames =
            static_cast<uint64_t>(std::llround(kSnapshotSeconds * sampleRate_));
        if (worker.sinceSnapshot >= snapshotFrames)
        {
            worker.sinceSnapshot -= snapshotFrames;
            emit(*worker.profiler);
        }
        return true;
    }

    void CausalLoudnessTap::run(const std::stop_token& stopToken) noexcept
    {
        enableFlushToZero(); // the profiler's K-weighting biquads run here
        Worker worker;
        while (!stopToken.stop_requested())
        {
            if (!running_.load(std::memory_order_acquire))
            {
                // Idle: discard whatever the RT side pushed before it saw the stop, so the next
                // estimate starts with only its own audio in the ring.
                discardRing();
                worker.profiler.reset();
                std::this_thread::sleep_for(kIdleSleep);
                continue;
            }
            if (!prepare(worker) || !drainOnce(worker))
            {
                std::this_thread::sleep_for(kDrainSleep);
            }
        }
    }
} // namespace AdaptiveSound
