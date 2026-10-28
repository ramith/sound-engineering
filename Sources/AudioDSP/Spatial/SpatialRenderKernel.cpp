#include "SpatialRenderKernel.h"
#include "../include/FiniteSamples.h"
#include "../include/FlushToZero.h"
#include <Accelerate/Accelerate.h>
#include <algorithm>
#include <cmath>
#include <cstdint>

// SpatialRenderKernel — implementation (see the header for the routes and the fold's parameters).
//
// All real-time-safe (RT) code in process() satisfies the audio-thread contract:
//   - No malloc / free / new / delete: the backstop's rings and the meter's ring are sized in
//     initialize() (off-RT).
//   - No locks (the publish mutex is the producer's alone), no Obj-C runtime, no syscalls.
//   - vDSP_mmov / vDSP_vclr / vDSP_vsmul / vDSP_vsma are RT-safe (no internal allocation).

namespace AdaptiveSound
{

    // Flush-to-zero (FPCR.FZ, include/FlushToZero.h) is scoped to process(): set for the render
    // call, the caller's mode restored on return (council C-50).

    namespace
    {
        constexpr float kDbScale = 20.0F;
        constexpr float kDbBase = 10.0F;

        // The meter reads a sample's applied gain only where the limiter's input is above this
        // (−120 dBFS): below it the ratio of two tiny floats is noise, not a gain.
        constexpr float kMeterFloor = 1.0e-6F;

        // The two output rows of the fold: L′ and R′.
        constexpr uint32_t kFoldRows = 2U;

        [[nodiscard]] auto linearFromDb(float decibels) noexcept -> float
        {
            return std::pow(kDbBase, decibels / kDbScale);
        }

        // LimiterModule::initialize's look-ahead in frames at `sampleRate`, the same expression, so the
        // meter's delay is exactly the limiter's ring delay.
        [[nodiscard]] auto limiterLookaheadFrames(uint32_t sampleRate) noexcept -> uint32_t
        {
            const float fs = static_cast<float>(sampleRate);
            return std::min<uint32_t>(static_cast<uint32_t>(std::lround(
                                          static_cast<double>(kLimiterLookaheadSeconds) * fs)),
                                      kMaxLimiterLookaheadFrames);
        }

        // The backstop's ceiling: the fold's, held at −0.1 dBTP at most — at or above full scale the
        // limiter would bypass, and the fold never plays without its net — and −1 dBTP when the value
        // is not a usable gain.
        [[nodiscard]] auto backstopCeiling(float ceilingLinear) noexcept -> float
        {
            if (!std::isfinite(ceilingLinear) || ceilingLinear <= 0.0F)
            {
                return kTruePeakCeilingLinear;
            }
            return std::min(ceilingLinear, kEqOnlyWiredCeilingLinear);
        }

        [[nodiscard]] auto isFinite(const FoldParams& fold) noexcept -> bool
        {
            for (const auto& row : fold.rows)
            {
                if (!std::ranges::all_of(row, [](float gain) { return std::isfinite(gain); }))
                {
                    return false;
                }
            }
            return std::isfinite(fold.trimDb) && std::isfinite(fold.lfeGain) &&
                   std::isfinite(fold.glideSeconds);
        }

        // Copy `numIn` channels from `input` to `output` (vDSP_mmov, bit-exact), then zero-fill output
        // channels [numIn, numOut). The M >= N identity route.
        void routePassthrough(const MultichannelView& input,
                              const MultichannelView& output,
                              uint32_t numIn,
                              uint32_t numOut,
                              vDSP_Length vLen) noexcept
        {
            for (uint32_t ch = 0U; ch < numIn; ++ch)
            {
                const float* inPtr = input.channel(ch);
                float* outPtr = output.channel(ch);
                if (inPtr != nullptr && outPtr != nullptr)
                {
                    vDSP_mmov(inPtr, outPtr, vLen, 1, vLen, vLen);
                }
            }
            for (uint32_t ch = numIn; ch < numOut; ++ch)
            {
                float* outPtr = output.channel(ch);
                if (outPtr != nullptr)
                {
                    vDSP_vclr(outPtr, 1, vLen);
                }
            }
        }

        // Zero output channels [from, view's count).
        void
        zeroOutputChannels(const MultichannelView& output, uint32_t from, vDSP_Length vLen) noexcept
        {
            for (uint32_t ch = from; ch < output.channels(); ++ch)
            {
                float* outPtr = output.channel(ch);
                if (outPtr != nullptr)
                {
                    vDSP_vclr(outPtr, 1, vLen);
                }
            }
        }
    } // namespace

    // ---------------------------------------------------------------------------
    // Off-RT
    // ---------------------------------------------------------------------------

    auto SpatialRenderKernel::initialize(uint32_t sampleRate, uint32_t maxFramesToRender) noexcept
        -> void
    {
        sampleRate_ = sampleRate;
        maxFrames_ = maxFramesToRender;
        backstop_.initialize(sampleRate, maxFramesToRender);
        meterLookahead_ = limiterLookaheadFrames(sampleRate);
        for (auto& ring : meterRing_)
        {
            ring.assign(static_cast<size_t>(meterLookahead_) + maxFramesToRender, 0.0F);
        }
        meterHead_ = 0U;
        needsSnap_ = true;
    }

    auto SpatialRenderKernel::configure(uint32_t numInChannels, uint32_t numOutChannels) noexcept
        -> void
    {
        inChannels_ = std::min(numInChannels, kMaxChannels);
        outChannels_ = std::min(numOutChannels, kMaxChannels);
        needsSnap_ = true;
        readoutIn_.store(inChannels_, std::memory_order_relaxed);
        readoutOut_.store(outChannels_, std::memory_order_relaxed);
    }

    auto SpatialRenderKernel::publishFold(const FoldParams& fold) noexcept -> bool
    {
        if (!isFinite(fold))
        {
            return false;
        }
        const std::scoped_lock lock(publishMutex_);
        FoldParams numbered = fold;
        publishCount_ = (publishCount_ == UINT32_MAX) ? 1U : publishCount_ + 1U; // 0 means "none"
        numbered.generation = publishCount_;
        published_.publish(numbered);
        return true;
    }

    auto SpatialRenderKernel::readout() const noexcept -> FoldReadout
    {
        const uint32_t sourceChannels = readoutIn_.load(std::memory_order_relaxed);
        const uint32_t outputChannels = readoutOut_.load(std::memory_order_relaxed);
        return FoldReadout{
            .sourceChannels = sourceChannels,
            .outputChannels = outputChannels,
            .folding = outputChannels < sourceChannels && sourceChannels > 2U,
            .fromPlan = readoutFromPlan_.load(std::memory_order_relaxed),
            .trimDb = readoutTrimDb_.load(std::memory_order_relaxed),
            .lfeGain = readoutLfeGain_.load(std::memory_order_relaxed),
            .backstopPeakGrDb = readoutPeakGrDb_.load(std::memory_order_relaxed),
        };
    }

    // ---------------------------------------------------------------------------
    // RT: process  (NON-IN-PLACE; input and output are SEPARATE ABLs)
    // ---------------------------------------------------------------------------

    auto SpatialRenderKernel::process(const MultichannelView& input,
                                      const MultichannelView& output) noexcept -> void
    {
        const ScopedFlushToZero flushToZero;
        const uint32_t frames = input.frames();
        if (frames == 0U || frames != output.frames() || frames > maxFrames_)
        {
            return;
        }
        const uint32_t numIn = inChannels_;
        const uint32_t numOut = outChannels_;
        const auto vLen = static_cast<vDSP_Length>(frames);
        if (numIn == 0U || numOut == 0U)
        {
            zeroOutputChannels(output, 0U, vLen);
            return;
        }
        if (numOut >= numIn)
        {
            routePassthrough(input, output, numIn, numOut, vLen);
        }
        else if (numIn <= kFoldRows)
        {
            // A stereo source on a mono device: its first channel (today's behaviour; no fold).
            routePassthrough(input, output, numOut, numOut, vLen);
        }
        else
        {
            foldBlock(input, output, frames);
        }
    }

    // The fold: the newest published fold if it is for this N, adopted at a change; mix L′/R′ (gliding, then
    // steady), zero any further device channel, then the backstop.
    auto SpatialRenderKernel::foldBlock(const MultichannelView& input,
                                        const MultichannelView& output,
                                        uint32_t frames) noexcept -> void
    {
        published_.copySnapshot(latest_);
        const auto vLen = static_cast<vDSP_Length>(frames);
        if (latest_.generation == 0U || latest_.inChannels != inChannels_)
        {
            // No fold for this width yet: silence, never the first two channels.
            zeroOutputChannels(output, 0U, vLen);
            haveFold_ = false;
            return;
        }
        if (needsSnap_ || !haveFold_ || latest_.generation != appliedGeneration_)
        {
            adoptFold(latest_, needsSnap_ || !haveFold_);
            appliedGeneration_ = latest_.generation;
        }
        needsSnap_ = false;
        haveFold_ = true;

        const uint32_t glided = mixRamped(input, output, frames);
        mixSteady(input, output, glided, frames);
        zeroOutputChannels(output, kFoldRows, vLen);
        runBackstop(output, frames);
    }

    // Take `fold` as the fold in force: its coefficients (rows × trim) as the target, reached at once
    // (`snap`, or a zero glide) or by a linear per-sample glide; its ceiling for the backstop; and a
    // fresh gain-reduction peak for the read-out.
    auto SpatialRenderKernel::adoptFold(const FoldParams& fold, bool snap) noexcept
        -> void
    {
        const float trim = linearFromDb(std::min(fold.trimDb, 0.0F));
        for (uint32_t row = 0U; row < kFoldRows; ++row)
        {
            for (uint32_t ch = 0U; ch < kMaxChannels; ++ch)
            {
                target_[row][ch] = (ch < inChannels_) ? fold.rows[row][ch] * trim : 0.0F;
            }
        }
        const auto glide =
            snap ? 0U
                 : static_cast<uint32_t>(std::lround(
                       static_cast<double>(std::max(fold.glideSeconds, 0.0F)) * sampleRate_));
        if (glide == 0U)
        {
            coeff_ = target_;
            glideLeft_ = 0U;
        }
        else
        {
            for (uint32_t row = 0U; row < kFoldRows; ++row)
            {
                for (uint32_t ch = 0U; ch < kMaxChannels; ++ch)
                {
                    step_[row][ch] =
                        (target_[row][ch] - coeff_[row][ch]) / static_cast<float>(glide);
                }
            }
            glideLeft_ = glide;
        }
        backstopParams_.truePeakCeilingLinear = backstopCeiling(fold.ceilingLinear);
        peakGrDb_ = 0.0F;
        readoutPeakGrDb_.store(0.0F, std::memory_order_relaxed);
        readoutTrimDb_.store(fold.trimDb, std::memory_order_relaxed);
        readoutLfeGain_.store(fold.lfeGain, std::memory_order_relaxed);
        readoutFromPlan_.store(fold.fromPlan, std::memory_order_relaxed);
    }

    // The gliding part of the block, per sample: each output sample at the coefficients in force, which
    // then step toward the target; the glide's last sample lands on the target exactly. Returns the
    // frames it rendered (0 with no glide).
    auto SpatialRenderKernel::mixRamped(const MultichannelView& input,
                                        const MultichannelView& output,
                                        uint32_t frames) noexcept -> uint32_t
    {
        const uint32_t count = std::min(glideLeft_, frames);
        for (uint32_t i = 0U; i < count; ++i)
        {
            for (uint32_t row = 0U; row < kFoldRows; ++row)
            {
                float* out = output.channel(row);
                if (out == nullptr)
                {
                    continue;
                }
                float sum = 0.0F;
                for (uint32_t ch = 0U; ch < inChannels_; ++ch)
                {
                    const float* in = input.channel(ch);
                    sum += (in != nullptr) ? coeff_[row][ch] * in[i] : 0.0F;
                }
                out[i] = sum;
            }
            for (uint32_t row = 0U; row < kFoldRows; ++row)
            {
                for (uint32_t ch = 0U; ch < inChannels_; ++ch)
                {
                    coeff_[row][ch] += step_[row][ch];
                }
            }
        }
        glideLeft_ -= count;
        if (count > 0U && glideLeft_ == 0U)
        {
            coeff_ = target_;
        }
        return count;
    }

    // Frames [from, frames) at the steady coefficients: each row a scaled sum of its non-zero inputs.
    // A zero coefficient adds nothing (so a silent channel, or one the fold leaves out, is never
    // touched): a stereo source in a 5.1 container folds to exactly its own samples at trim 0.
    auto SpatialRenderKernel::mixSteady(const MultichannelView& input,
                                        const MultichannelView& output,
                                        uint32_t from,
                                        uint32_t frames) const noexcept -> void
    {
        if (from >= frames)
        {
            return;
        }
        const auto len = static_cast<vDSP_Length>(frames - from);
        for (uint32_t row = 0U; row < kFoldRows; ++row)
        {
            float* out = output.channel(row);
            if (out == nullptr)
            {
                continue;
            }
            out += from;
            bool written = false;
            for (uint32_t ch = 0U; ch < inChannels_; ++ch)
            {
                const float* in = input.channel(ch);
                const float gain = coeff_[row][ch];
                if (in == nullptr || gain == 0.0F)
                {
                    continue;
                }
                if (written)
                {
                    vDSP_vsma(in + from, 1, &gain, out, 1, out, 1, len);
                }
                else
                {
                    vDSP_vsmul(in + from, 1, &gain, out, 1, len);
                    written = true;
                }
            }
            if (!written)
            {
                vDSP_vclr(out, 1, len);
            }
        }
    }

    // The backstop: the limiter on L′/R′ in place, and its meter. The limiter delays by its look-ahead
    // and applies one linked gain, so the gain it applied to a sample is the output over the input
    // `meterLookahead_` frames earlier — read on the louder side, where the input is above the floor.
    auto SpatialRenderKernel::runBackstop(const MultichannelView& output, uint32_t frames) noexcept
        -> void
    {
        const auto size = static_cast<uint32_t>(meterRing_[0].size());
        if (size == 0U)
        {
            return;
        }
        for (uint32_t row = 0U; row < kFoldRows; ++row)
        {
            const float* out = output.channel(row);
            for (uint32_t i = 0U; i < frames; ++i)
            {
                meterRing_[row][(meterHead_ + i) % size] =
                    (out != nullptr) ? finiteOrSilence(out[i]) : 0.0F;
            }
        }
        backstop_.process(backstopParams_, output);

        float minGain = 1.0F;
        for (uint32_t i = 0U; i < frames; ++i)
        {
            const uint32_t delayed = (meterHead_ + i + size - meterLookahead_) % size;
            uint32_t louder = 0U;
            if (std::fabs(meterRing_[1][delayed]) > std::fabs(meterRing_[0][delayed]))
            {
                louder = 1U;
            }
            const float before = std::fabs(meterRing_[louder][delayed]);
            const float* out = output.channel(louder);
            if (out != nullptr && before > kMeterFloor)
            {
                minGain = std::min(minGain, std::fabs(out[i]) / before);
            }
        }
        meterHead_ = (meterHead_ + frames) % size;
        if (minGain < 1.0F)
        {
            const float reduction = -kDbScale * std::log10(std::max(minGain, 1.0e-12F));
            if (reduction > peakGrDb_)
            {
                peakGrDb_ = reduction;
                readoutPeakGrDb_.store(reduction, std::memory_order_relaxed);
            }
        }
    }

} // namespace AdaptiveSound
