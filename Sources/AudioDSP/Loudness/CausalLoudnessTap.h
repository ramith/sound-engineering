#pragma once

// CausalLoudnessTap — the causal running estimate of a track's loudness profile (Sprint EQ, EQ1c;
// amendments item 3, engine-plan §4.3).
//
// When the track loudness analysis fails (the Swift analyzer could not decode the file), the
// loudness-neutral EQ gain falls back to THIS: a TrackLoudnessProfiler fed with the audio as it
// plays — the kernel's input, ahead of the EQ — whose profile of everything heard so far is handed
// to the Realizer after every second of audio. The Realizer turns each one into a gain and slews
// toward it (1 dB/s); a whole-track pre-analysis is better in every way, so this runs only for a
// track whose analysis failed.
//
//   RT process()  ──push(input)──▶  SpscRing  ──▶  worker jthread: TrackLoudnessProfiler
//                                                  └─ every 1 s of audio: snapshot() → sink
//
// The RT side mirrors LoudnessModule: it relays the channel count by atomic, interleaves into a
// pre-allocated scratch and pushes to a lock-free SPSC ring, DROPPING on full. When the tap is not
// running it costs one relaxed atomic load per block. The worker parks while no estimate runs, and
// once no audio has come for a while (WorkerParking), so a paused or idle tap wakes nobody. Everything else — the profiler, its FFTs, the
// profile's storage, the sink — runs on the worker, off-RT.
//
// CONTROL (off-RT, any one control thread at a time — the Realizer's queue): start(sink) begins a
// fresh estimate (the profiler restarts on the next audio), stop() ends it; the sink is held under
// a mutex the worker also takes to call it, so after stop() returns it is never called again.
// publishChannelLayout() sets the BS.1770-5 channel weights (a new estimate starts with them).

#include "../include/AudioConstants.h"
#include "../include/ChannelLayout.h"
#include "../include/MultichannelView.h"
#include "../include/SpscRing.h"
#include "../include/WorkerParking.h"
#include <array>
#include <atomic>
#include <chrono>
#include <cstddef>
#include <cstdint>
#include <functional>
#include <memory>
#include <mutex>
#include <stop_token>
#include <thread>
#include <vector>

namespace AdaptiveSound
{
    struct TrackLoudnessProfile;
    class TrackLoudnessProfiler;

    class CausalLoudnessTap
    {
      public:
        // Called on the worker with the profile of everything fed since start(), once per second
        // of audio. It must not block for long (the Realizer's dispatches to its queue).
        using Sink = std::function<void(std::shared_ptr<const TrackLoudnessProfile>)>;

        // One snapshot per second of fed audio.
        static constexpr double kSnapshotSeconds = 1.0;
        // The ring: ~680 ms of 8 channels at 48 kHz, so the worker may fall a block behind.
        static constexpr size_t kRingFrames = 32768U;
        static constexpr size_t kRingElems = kRingFrames * kMaxChannels;
        // The worker drains in chunks of this many frames.
        static constexpr size_t kChunkFrames = 2048U;
        // The worker's nap while an estimate runs and its ring is empty, and how long it finds
        // nothing before it parks until the next push (WorkerParking).
        static constexpr std::chrono::milliseconds kDrainNap{10};
        static constexpr std::chrono::milliseconds kParkAfter{200};

        CausalLoudnessTap() = default;
        ~CausalLoudnessTap(); // stops and joins the worker

        CausalLoudnessTap(const CausalLoudnessTap&) = delete;
        CausalLoudnessTap& operator=(const CausalLoudnessTap&) = delete;
        CausalLoudnessTap(CausalLoudnessTap&&) = delete;
        CausalLoudnessTap& operator=(CausalLoudnessTap&&) = delete;

        // Off-RT: size the scratch for `maxFrames` and start the (idle) worker. Once, before the
        // first push().
        void initialize(uint32_t sampleRate, uint32_t maxFrames) noexcept;

        // Off-RT control: begin a fresh running estimate delivered to `sink`; stop it.
        void start(Sink sink) noexcept;
        void stop() noexcept;

        // Off-RT control: the BS.1770-5 channel weights (LFE 0); used from the next estimate on.
        void publishChannelLayout(const ChannelLayout& layout) noexcept;

        // RT: hand the block to the worker while an estimate runs (drop on full). noexcept, no
        // allocation, no lock.
        void push(const MultichannelView& block) noexcept;

        // Diagnostics (any thread): frames the worker has fed to the current estimate (reset when
        // the worker begins a new one).
        [[nodiscard]] uint64_t fedFrames() const noexcept
        {
            return fedFrames_.load(std::memory_order_acquire);
        }

      private:
        // The worker's estimate in progress.
        struct Worker
        {
            std::unique_ptr<TrackLoudnessProfiler> profiler;
            uint64_t estimate = 0U; // the generation the profiler belongs to
            uint32_t channels = 0U;
            uint64_t sinceSnapshot = 0U; // frames since the last snapshot
        };

        void run(const std::stop_token& stopToken) noexcept;
        // Worker: drop everything in the ring.
        void discardRing() noexcept;
        // Worker: make the profiler match the current estimate and channel count; false while
        // there is none to run (no audio yet, or the profiler could not be made).
        [[nodiscard]] bool prepare(Worker& worker) noexcept;
        // Worker: feed one chunk from the ring (and emit a snapshot each second); false if empty.
        [[nodiscard]] bool drainOnce(Worker& worker) noexcept;
        // Worker: a profiler for `channels` at the stream rate with the current weights.
        [[nodiscard]] std::unique_ptr<TrackLoudnessProfiler>
        makeProfiler(uint32_t channels) noexcept;
        // Worker: deinterleave `frames` from chunk_ into planar_ and feed the profiler.
        void feed(TrackLoudnessProfiler& profiler, uint32_t channels, size_t frames) noexcept;
        // Worker: hand the profile so far to the sink (under sinkMutex_).
        void emit(const TrackLoudnessProfiler& profiler) noexcept;

        // RT → worker.
        SpscRing<float, kRingElems> ring_;
        std::vector<float> pushBuf_; // maxFrames × kMaxChannels, interleaved (RT-owned)
        std::atomic<uint32_t> channelCount_{0U};

        // Control → worker / RT.
        std::atomic<bool> running_{false};
        std::atomic<uint64_t> generation_{0U}; // bumped by start(): the worker restarts
        std::atomic<uint64_t> fedFrames_{0U};
        std::mutex sinkMutex_; // guards sink_ and weights_
        Sink sink_;
        std::array<double, kMaxChannels> weights_{1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0};

        // RT / control → worker wake-ups.
        WorkerParking parking_{kDrainNap, kParkAfter};

        // Worker-owned.
        std::vector<float> chunk_;  // kChunkFrames × kMaxChannels, interleaved
        std::vector<float> planar_; // kChunkFrames × kMaxChannels, channel-major
        uint32_t sampleRate_ = kDefaultSampleRate;
        uint32_t maxFrames_ = kDefaultMaxFrames;

        // MUST be the last member: destroyed first, so the worker stops before what it touches.
        std::jthread worker_;
    };
} // namespace AdaptiveSound
