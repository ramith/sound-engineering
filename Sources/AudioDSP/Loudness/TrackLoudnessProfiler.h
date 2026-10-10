#pragma once

// TrackLoudnessProfiler.h — builds a TrackLoudnessProfile from a track's decoded PCM, off the
// real-time path (Sprint EQ, EQ1c; amendments item 3, engine-plan §4.2).
//
// THE PIPELINE, per BS.1770-5:
//   per channel: x → K-weighting (makeKWeighting: shelf + RLB high-pass, double) → ring (float)
//   every 100 ms hop, once 4 hops (400 ms) are in: one block, if it is kept (see below):
//     per channel with weight G_ch > 0: √G_ch · the block, zero-padded to the next power of two
//     N, through ONE real FFT with NO window; Σ_ch |X_k|² into one-sided bin powers S_k
//     per 1/24-octave band: P(b) = Σ_{k ∈ band b} S_k / (L·N)
//   so Σ_b P(b) = (1/L)·Σ_ch G_ch·Σ_{n ∈ block} y_ch[n]² — the block's BS.1770 energy z_j, exactly.
//
// THE PORT RULE: the block FFT uses NO window (amendments item 3). Only the rectangular window keeps
// Parseval exact for the 400 ms block, so the band powers add up to the block's own energy. Hann
// re-weights the samples inside each block and errs −0.36 dB on a tonal 808 track with +12 dB at
// 100 Hz, Blackman-Harris −0.59 dB (verify-breaker M2). Profile_NoWindow_ParsevalAndTonal pins it.
//
// CHANNELS. Up to kMaxChannels, with the caller's BS.1770-5 weights (L/R/C 1.0, surrounds 1.41,
// LFE 0 — the ChannelLayoutDecoder table). A channel weighted 0 costs no FFT.
//
// PREFIX FIRST (amendments item 3). snapshot() takes the blocks analysed so far as a prefix
// profile (e.g. after the first ~20–30 s) without ending the stream; feeding on and finish() then
// refines it to the whole track. A prefix's blocks are the whole-track profile's first blocks,
// bit for bit, while the track is under the decimation cap.
//
// MEMORY AND COST, bounded by duration with decimation above a cap. The profile holds at most
// `maxBlocks` blocks (default 6000 = 10 minutes of 100 ms blocks: ≤ 5.9 MB at 44.1 kHz, ≤ 7.1 MB at
// 192 kHz). When a longer track reaches the cap, every second kept block is dropped and the stride
// doubles (blocks every 200 ms, then 400 ms, …); a block that will not be kept costs no FFT. So
// memory is O(maxBlocks), and the FFT count grows only logarithmically past the cap
// (maxBlocks + (maxBlocks / 2)·log2(duration / cap)). The working set besides the profile is fixed at
// creation: per channel one 400 ms float ring, plus one N-point FFT's buffers (≤ 4.5 MB at 192 kHz
// × 8 channels). Nothing is allocated per block except the profile's own storage, which grows
// geometrically up to the cap.
//
// THREADS. One owner (the Swift TrackLoudnessAnalyzer's job); not thread-safe. Off the RT path:
// feed() runs vDSP FFTs and may grow the profile's storage. The profiles it returns are immutable
// and may be shared across threads.

#include "../include/AudioConstants.h"
#include "LufsMeter.h"
#include "TrackLoudnessProfile.h"
#include <Accelerate/Accelerate.h>
#include <array>
#include <cstddef>
#include <cstdint>
#include <memory>
#include <span>
#include <vector>

namespace AdaptiveSound
{
    class TrackLoudnessProfiler
    {
      public:
        // The decoded stream: its rate, channel count and per-channel BS.1770-5 weights.
        struct Format
        {
            double sampleRate = 0.0;
            uint32_t channelCount = 0U;
            std::array<double, kMaxChannels> channelWeights{}; // the first channelCount are used
        };

        // The decimation cap: 6000 blocks = 10 minutes at the 100 ms block rate.
        static constexpr uint32_t kDefaultMaxBlocks = 6000U;
        // Decimation halves the kept blocks, so the cap must be even and at least 2.
        static constexpr uint32_t kMinMaxBlocks = 2U;

        // A profiler for `format`, or nullptr when the format is invalid: a rate outside
        // [TrackLoudness::kMinSampleRateHz, kMaxSampleRateHz] or non-finite; 0 or more than
        // kMaxChannels channels; a used weight that is negative or non-finite, or no positive
        // weight at all; an odd `maxBlocks` or one below kMinMaxBlocks; or a failed FFT setup.
        [[nodiscard]] static std::unique_ptr<TrackLoudnessProfiler>
        create(const Format& format, uint32_t maxBlocks = kDefaultMaxBlocks) noexcept;

        ~TrackLoudnessProfiler() = default;
        TrackLoudnessProfiler(const TrackLoudnessProfiler&) = delete;
        TrackLoudnessProfiler& operator=(const TrackLoudnessProfiler&) = delete;
        TrackLoudnessProfiler(TrackLoudnessProfiler&&) = delete;
        TrackLoudnessProfiler& operator=(TrackLoudnessProfiler&&) = delete;

        // Feed the next `frameCount` frames, planar (one pointer per channel; exactly
        // channelCount pointers). Returns false — consuming NOTHING, so the stream is unchanged —
        // on a wrong channel count, a NULL channel pointer, any non-finite sample, or after
        // finish(). Zero frames is a valid no-op.
        [[nodiscard]] bool feed(std::span<const float* const> channels, size_t frameCount) noexcept;

        // The prefix: a profile of the blocks analysed so far (wholeTrack = false); the stream
        // continues. nullptr when no whole 400 ms block has been analysed yet, or after finish().
        [[nodiscard]] std::shared_ptr<const TrackLoudnessProfile> snapshot() const;

        // The whole track: ends the stream (a trailing part-block shorter than 400 ms is dropped,
        // as BS.1770 does) and returns the profile (wholeTrack = true). nullptr when the track
        // held no whole block, or when the stream had already been finished.
        [[nodiscard]] std::shared_ptr<const TrackLoudnessProfile> finish();

        [[nodiscard]] bool isFinished() const noexcept
        {
            return finished_;
        }
        [[nodiscard]] uint64_t analysedFrames() const noexcept
        {
            return framesFed_;
        }
        [[nodiscard]] const Format& format() const noexcept
        {
            return format_;
        }
        // The fixed working set plus the profile storage reserved so far (bytes).
        [[nodiscard]] size_t memoryBytes() const noexcept;

      private:
        // vDSP's DFT setup, destroyed with its own function.
        struct DftSetupDeleter
        {
            void operator()(vDSP_DFT_SetupStruct* setup) const noexcept
            {
                vDSP_DFT_DestroySetup(setup);
            }
        };
        using DftSetup = std::unique_ptr<vDSP_DFT_SetupStruct, DftSetupDeleter>;

        TrackLoudnessProfiler(const Format& format, uint32_t maxBlocks, DftSetup setup) noexcept;

        // K-weight `frames` frames of every channel (starting at `offset` in the caller's
        // buffers) into the rings; the run never crosses a hop boundary.
        void
        weightRun(std::span<const float* const> channels, size_t offset, size_t frames) noexcept;
        // A hop just completed: analyse the block that ends here if it is kept.
        void completeHop();
        // The newest 400 ms block's band powers, appended to the profile storage.
        void analyseBlock();
        // Drop every second kept block and double the stride (the decimation cap).
        void decimate() noexcept;
        [[nodiscard]] std::shared_ptr<TrackLoudnessProfile> makeProfile(bool wholeTrack) const;

        Format format_;
        uint32_t channelCount_ = 0U;
        uint32_t hopFrames_ = 0U;   // lround(0.1·fs), as LufsMeter and libebur128
        uint32_t blockFrames_ = 0U; // 4 hops
        uint32_t fftLength_ = 0U;   // the next power of two ≥ blockFrames_
        uint32_t bandCount_ = 0U;
        uint32_t maxBlocks_ = 0U;
        DftSetup setup_;

        std::array<LufsKWeight, kMaxChannels> kWeight_{};
        std::vector<float> ring_;         // channelCount × blockFrames_ K-weighted samples
        std::vector<float> fftInput_;     // fftLength_; [blockFrames_, fftLength_) stays zero
        std::vector<float> splitReal_;    // fftLength_ / 2: the even samples, packed
        std::vector<float> splitImag_;    // fftLength_ / 2: the odd samples, packed
        std::vector<float> spectrumReal_; // fftLength_ / 2: vDSP's packed output
        std::vector<float> spectrumImag_;
        std::vector<float> binPower_; // fftLength_ / 2 channel-weighted bin powers (0 … N/2 − 1)
        std::vector<uint32_t> bandFirstBin_; // bandCount_ + 1: band b = [first[b], first[b + 1])

        uint32_t ringPosition_ = 0U; // the next write index (the oldest sample once full)
        uint32_t hopFill_ = 0U;      // frames into the current hop
        uint64_t hopsCompleted_ = 0U;
        uint64_t framesFed_ = 0U;
        uint32_t strideHops_ = 1U;
        uint32_t blockCount_ = 0U;
        std::vector<float> blocks_; // blockCount_ × bandCount_, block-major
        bool finished_ = false;
    };
} // namespace AdaptiveSound
