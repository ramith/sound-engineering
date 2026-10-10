// TrackLoudnessProfiler.cpp — the streaming BS.1770 block-spectral analysis. See
// TrackLoudnessProfiler.h.

#include "TrackLoudnessProfiler.h"
#include <algorithm>
#include <bit>
#include <cmath>
#include <new>
#include <utility>

namespace AdaptiveSound
{
    namespace
    {
        // The first growth step of the profile's storage: 30 s of blocks (a typical prefix).
        constexpr uint32_t kInitialBlockReserve = 300U;
        // vDSP's packed real-DFT output is twice the DFT; a one-sided interior bin carries
        // 2·|X_k|² = |out_k|² / 2, while DC and Nyquist carry |X|² = |out|² / 4 (half as much).
        constexpr float kEdgeBinShare = 0.5F;
        constexpr double kPackedPowerScale = 0.5;

        [[nodiscard]] bool validWeights(const TrackLoudnessProfiler::Format& format) noexcept
        {
            bool anyPositive = false;
            for (uint32_t ch = 0U; ch < format.channelCount; ++ch)
            {
                const double weight = format.channelWeights[ch];
                if (!std::isfinite(weight) || weight < 0.0)
                {
                    return false;
                }
                anyPositive = anyPositive || weight > 0.0;
            }
            return anyPositive;
        }

        [[nodiscard]] bool allFinite(const float* samples, size_t count) noexcept
        {
            return std::all_of(
                samples, samples + count, [](float sample) { return std::isfinite(sample); });
        }
    } // namespace

    std::unique_ptr<TrackLoudnessProfiler>
    TrackLoudnessProfiler::create(const Format& format, uint32_t maxBlocks) noexcept
    {
        if (TrackLoudness::bandCount(format.sampleRate) == 0U || format.channelCount == 0U ||
            format.channelCount > kMaxChannels || maxBlocks < kMinMaxBlocks ||
            maxBlocks % 2U != 0U || !validWeights(format))
        {
            return nullptr;
        }
        const auto hopFrames = static_cast<uint32_t>(std::lround(kHopSeconds * format.sampleRate));
        const uint32_t fftLength = std::bit_ceil(hopFrames * static_cast<uint32_t>(kBlockHops));
        DftSetup setup(vDSP_DFT_zrop_CreateSetup(nullptr, fftLength, vDSP_DFT_FORWARD));
        if (!setup)
        {
            return nullptr;
        }
        return std::unique_ptr<TrackLoudnessProfiler>(
            new (std::nothrow) TrackLoudnessProfiler(format, maxBlocks, std::move(setup)));
    }

    TrackLoudnessProfiler::TrackLoudnessProfiler(const Format& format,
                                                 uint32_t maxBlocks,
                                                 DftSetup setup) noexcept
        : format_(format),
          channelCount_(format.channelCount),
          hopFrames_(static_cast<uint32_t>(std::lround(kHopSeconds * format.sampleRate))),
          blockFrames_(hopFrames_ * static_cast<uint32_t>(kBlockHops)),
          fftLength_(std::bit_ceil(blockFrames_)),
          bandCount_(TrackLoudness::bandCount(format.sampleRate)),
          maxBlocks_(maxBlocks),
          setup_(std::move(setup)),
          ring_(static_cast<size_t>(channelCount_) * blockFrames_, 0.0F),
          fftInput_(fftLength_, 0.0F),
          splitReal_(fftLength_ / 2U),
          splitImag_(fftLength_ / 2U),
          spectrumReal_(fftLength_ / 2U),
          spectrumImag_(fftLength_ / 2U),
          binPower_(fftLength_ / 2U),
          bandFirstBin_(static_cast<size_t>(bandCount_) + 1U)
    {
        kWeight_.fill(makeKWeighting(format.sampleRate));
        // Band b ≥ 1 starts at the first bin at or above edge b − 1 (bin k sits at k·fs/N); band
        // 0 starts at DC; the last band ends after the Nyquist bin N/2.
        const uint32_t nyquistBin = fftLength_ / 2U;
        const double binHz = format.sampleRate / static_cast<double>(fftLength_);
        uint32_t bin = 0U;
        for (uint32_t band = 1U; band < bandCount_; ++band)
        {
            const double edge = TrackLoudness::edgeHz(band - 1U);
            while (bin <= nyquistBin && static_cast<double>(bin) * binHz < edge)
            {
                ++bin;
            }
            bandFirstBin_[band] = bin;
        }
        bandFirstBin_[bandCount_] = nyquistBin + 1U;
    }

    bool TrackLoudnessProfiler::feed(std::span<const float* const> channels,
                                     size_t frameCount) noexcept
    {
        if (finished_ || channels.size() != channelCount_)
        {
            return false;
        }
        // Validate the whole chunk before touching any state: a rejected chunk consumes nothing.
        const bool valid =
            std::ranges::all_of(channels,
                                [frameCount](const float* samples)
                                { return samples != nullptr && allFinite(samples, frameCount); });
        if (!valid)
        {
            return false;
        }
        size_t done = 0U;
        while (done < frameCount)
        {
            const size_t run = std::min<size_t>(frameCount - done, hopFrames_ - hopFill_);
            weightRun(channels, done, run);
            done += run;
            hopFill_ += static_cast<uint32_t>(run);
            if (hopFill_ == hopFrames_)
            {
                hopFill_ = 0U;
                ++hopsCompleted_;
                completeHop();
            }
        }
        framesFed_ += frameCount;
        return true;
    }

    void TrackLoudnessProfiler::weightRun(std::span<const float* const> channels,
                                          size_t offset,
                                          size_t frames) noexcept
    {
        for (uint32_t ch = 0U; ch < channelCount_; ++ch)
        {
            if (!(format_.channelWeights[ch] > 0.0))
            {
                continue; // an unweighted channel (LFE) never reaches a block
            }
            const float* source = channels[ch] + offset;
            float* ring = ring_.data() + (static_cast<size_t>(ch) * blockFrames_) + ringPosition_;
            LufsKWeight& filter = kWeight_[ch];
            for (size_t frame = 0U; frame < frames; ++frame)
            {
                ring[frame] =
                    static_cast<float>(filter.processSample(static_cast<double>(source[frame])));
            }
        }
        // A run never crosses a hop boundary, and the ring is exactly 4 hops long, so it can
        // only wrap at the end of a run.
        ringPosition_ += static_cast<uint32_t>(frames);
        if (ringPosition_ == blockFrames_)
        {
            ringPosition_ = 0U;
        }
    }

    void TrackLoudnessProfiler::completeHop()
    {
        const auto hopsPerBlock = static_cast<uint64_t>(kBlockHops);
        if (hopsCompleted_ < hopsPerBlock)
        {
            return;
        }
        // Block k covers hops [k, k + 4): it ends at the hop just completed.
        const uint64_t blockIndex = hopsCompleted_ - hopsPerBlock;
        if (blockIndex % strideHops_ != 0U)
        {
            return; // not kept: no FFT at all
        }
        if (blockCount_ == maxBlocks_)
        {
            decimate();
            if (blockIndex % strideHops_ != 0U)
            {
                return;
            }
        }
        analyseBlock();
    }

    void TrackLoudnessProfiler::analyseBlock()
    {
        const uint32_t half = fftLength_ / 2U;
        const auto halfLength = static_cast<vDSP_Length>(half);
        vDSP_vclr(binPower_.data(), 1, halfLength);
        float nyquistPower = 0.0F;
        const uint32_t olderFrames = blockFrames_ - ringPosition_;
        for (uint32_t ch = 0U; ch < channelCount_; ++ch)
        {
            const double weight = format_.channelWeights[ch];
            if (!(weight > 0.0))
            {
                continue;
            }
            // The block in time order (the ring's oldest sample sits at ringPosition_), scaled by
            // √G so the channel's bin powers come out weighted. NO window (the port rule).
            const auto rootWeight = static_cast<float>(std::sqrt(weight));
            const float* ring = ring_.data() + (static_cast<size_t>(ch) * blockFrames_);
            vDSP_vsmul(ring + ringPosition_,
                       1,
                       &rootWeight,
                       fftInput_.data(),
                       1,
                       static_cast<vDSP_Length>(olderFrames));
            vDSP_vsmul(ring,
                       1,
                       &rootWeight,
                       fftInput_.data() + olderFrames,
                       1,
                       static_cast<vDSP_Length>(ringPosition_));
            DSPSplitComplex packed{splitReal_.data(), splitImag_.data()};
            vDSP_ctoz(
                reinterpret_cast<const DSPComplex*>(fftInput_.data()), 2, &packed, 1, halfLength);
            vDSP_DFT_Execute(setup_.get(),
                             splitReal_.data(),
                             splitImag_.data(),
                             spectrumReal_.data(),
                             spectrumImag_.data());
            // vDSP packs the Nyquist term into imag[0]; take it out so bin 0 is DC alone.
            nyquistPower += spectrumImag_[0] * spectrumImag_[0];
            spectrumImag_[0] = 0.0F;
            DSPSplitComplex spectrum{spectrumReal_.data(), spectrumImag_.data()};
            vDSP_zvmgsa(&spectrum, 1, binPower_.data(), 1, binPower_.data(), 1, halfLength);
        }
        binPower_[0] *= kEdgeBinShare;
        nyquistPower *= kEdgeBinShare;

        // The block's row, growing the storage geometrically up to the cap (never beyond it).
        const size_t width = bandCount_;
        const size_t needed = (static_cast<size_t>(blockCount_) + 1U) * width;
        if (needed > blocks_.capacity())
        {
            const size_t grown = std::max(blocks_.capacity() * 2U, kInitialBlockReserve * width);
            blocks_.reserve(std::min(grown, static_cast<size_t>(maxBlocks_) * width));
        }
        blocks_.resize(needed);
        float* row = blocks_.data() + (static_cast<size_t>(blockCount_) * width);
        const auto scale =
            static_cast<float>(kPackedPowerScale / (static_cast<double>(blockFrames_) *
                                                    static_cast<double>(fftLength_)));
        for (uint32_t band = 0U; band < bandCount_; ++band)
        {
            const uint32_t first = bandFirstBin_[band];
            const uint32_t end = bandFirstBin_[band + 1U];
            const uint32_t packedEnd = std::min(end, half);
            float sum = 0.0F;
            if (packedEnd > first)
            {
                vDSP_sve(
                    binPower_.data() + first, 1, &sum, static_cast<vDSP_Length>(packedEnd - first));
            }
            if (end > half)
            {
                sum += nyquistPower; // the Nyquist bin N/2 closes the last band
            }
            row[band] = sum * scale;
        }
        ++blockCount_;
    }

    void TrackLoudnessProfiler::decimate() noexcept
    {
        // Keep kept-blocks 0, 2, 4, … (stride s → 2s). Block j moves to j / 2; the source always
        // lies ahead of the destination, so a forward copy is safe.
        const size_t width = bandCount_;
        const uint32_t kept = (blockCount_ + 1U) / 2U;
        for (uint32_t index = 1U; index < kept; ++index)
        {
            std::copy_n(blocks_.data() + (static_cast<size_t>(index) * 2U * width),
                        width,
                        blocks_.data() + (static_cast<size_t>(index) * width));
        }
        blockCount_ = kept;
        blocks_.resize(static_cast<size_t>(kept) * width);
        strideHops_ *= 2U;
    }

    std::shared_ptr<TrackLoudnessProfile> TrackLoudnessProfiler::makeProfile(bool wholeTrack) const
    {
        auto profile = std::make_shared<TrackLoudnessProfile>();
        profile->sampleRate = format_.sampleRate;
        profile->channelCount = channelCount_;
        profile->bandCount = bandCount_;
        profile->blockCount = blockCount_;
        profile->blockStrideHops = strideHops_;
        profile->analysedFrames = framesFed_;
        profile->wholeTrack = wholeTrack;
        return profile;
    }

    std::shared_ptr<const TrackLoudnessProfile> TrackLoudnessProfiler::snapshot() const
    {
        if (finished_ || blockCount_ == 0U)
        {
            return nullptr;
        }
        std::shared_ptr<TrackLoudnessProfile> profile = makeProfile(false);
        profile->bandPower.assign(blocks_.begin(), blocks_.end());
        profile->sourceLoudnessLufs = profileLoudnessLufs(*profile);
        return profile;
    }

    std::shared_ptr<const TrackLoudnessProfile> TrackLoudnessProfiler::finish()
    {
        if (finished_)
        {
            return nullptr;
        }
        finished_ = true;
        if (blockCount_ == 0U)
        {
            return nullptr;
        }
        std::shared_ptr<TrackLoudnessProfile> profile = makeProfile(true);
        profile->bandPower = std::move(blocks_);
        profile->bandPower.shrink_to_fit();
        blocks_ = {};
        profile->sourceLoudnessLufs = profileLoudnessLufs(*profile);
        return profile;
    }

    size_t TrackLoudnessProfiler::memoryBytes() const noexcept
    {
        const size_t floats = ring_.capacity() + fftInput_.capacity() + splitReal_.capacity() +
                              splitImag_.capacity() + spectrumReal_.capacity() +
                              spectrumImag_.capacity() + binPower_.capacity() + blocks_.capacity();
        return sizeof(TrackLoudnessProfiler) + (floats * sizeof(float)) +
               (bandFirstBin_.capacity() * sizeof(uint32_t));
    }
} // namespace AdaptiveSound
