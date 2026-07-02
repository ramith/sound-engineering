#ifndef LUFS_METER_H
#define LUFS_METER_H

// LufsMeter — ITU-R BS.1770-5 / EBU R128 gated loudness measurement.
//
// Pure, synchronous, header-only DSP — NO threading, NO atomics, NO Accelerate.
// This is the measurement core that LoudnessModule's off-RT worker drives, and
// that unit tests drive directly with a full buffer (deterministic, no thread).
//
// Pipeline (BS.1770-5 §2, EBU Tech 3341):
//   per channel:  x → [stage-1 high-shelf] → [stage-2 RLB high-pass] → y   (K-weighting)
//   per 100 ms hop:  accumulate Σ y²  per channel
//   per 400 ms block (every hop, 75 % overlap):
//       z = Σ_ch G_ch · (Σ y_ch² over 400 ms) / N_block
//       block loudness  l = −0.691 + 10·log10(z)
//   integrated (gated):
//       absolute gate: keep blocks with l ≥ −70 LUFS
//       relative gate: keep blocks with l ≥ (loudness of ungated mean) − 10 LU
//       I = −0.691 + 10·log10(mean z over relatively-gated blocks)
//   momentary  = block loudness over the last 400 ms (no gate)
//   short-term = block loudness over the last 3 s   (no gate)
//
// Multichannel channel weights G (ITU-R BS.1770-5, Annex 1, Table 1):
//   L, R, C        → G = 1.0
//   LFE            → G = 0.0  (excluded from sum)
//   Ls, Rs, Lss, Rss → G = 1.41 (+1.5 dB, i.e. 10^(1.5/10) ≈ 1.413)
// Weights are supplied by the caller via configureChannels(); the meter
// does not hard-code a channel-order assumption.  prepare() defaults to
// stereo (numChannels_=2, weights {1,1,...}) so existing call sites are
// unchanged.
//
// N=2 equivalence guarantee: with numChannels_=2 and weights {1,1,...},
// hopEnergy = accum_[0] + accum_[1] — bit-identical to the original
// accumLeft_ + accumRight_ path (same arithmetic, same IEEE-754 rounding).
//
// Precision: ALL measurement arithmetic is double (libebur128 does the same; the
// gating boundary near −70 LUFS loses bits in float). Coefficients are derived
// analytically per sample rate via the bilinear transform with pre-warp, so the
// meter is correct at 44.1 kHz as well as 48 kHz.
//
// Gating uses a bounded histogram of block loudness (libebur128's approach), so
// memory is O(bins), not O(program length).
//
// References:
//   - ITU-R BS.1770-5 (2023), Annex 1 (K-weighting + gating + channel weights).
//   - EBU Tech 3341 (EBU Mode metering); EBU R128.
//   - jiixyj/libebur128 ebur128.c (coefficient derivation, double accumulation,
//     histogram gating) — verified.

#include <algorithm>
#include <array>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <limits>

#include "../include/AudioConstants.h"

namespace AdaptiveSound
{

    // --- K-weighting analog prototypes (bilinear + prewarp per fs) ---------------
    inline constexpr double kKwShelfF0Hz = 1681.974450955533;        // stage-1 shelf midpoint
    inline constexpr double kKwShelfGainDb = 3.999843853973347;      // stage-1 shelf gain
    inline constexpr double kKwShelfQ = 0.7071752369554196;          // stage-1 Q
    inline constexpr double kKwShelfVbExponent = 0.4996667741545416; // libebur128 Vb power
    inline constexpr double kKwRlbF0Hz = 38.13547087602444;          // stage-2 high-pass cutoff
    inline constexpr double kKwRlbQ = 0.5003270373238773;            // stage-2 Q

    // --- dB / LUFS constants -----------------------------------------------------
    inline constexpr double kDecibelBase = 10.0;           // base for dB↔linear
    inline constexpr double kDbPowerScale = 10.0;          // 10·log10 (power → dB)
    inline constexpr double kDbAmplitudeScale = 20.0;      // 20·log10 (amplitude → dB)
    inline constexpr double kLufsOffset = -0.691;          // BS.1770 block-loudness offset
    inline constexpr double kAbsoluteGateLufs = -70.0;     // absolute silence gate
    inline constexpr double kRelativeGateOffsetLu = -10.0; // relative gate below ungated mean

    // --- Block / window structure (100 ms hop, 75 % overlap) ---------------------
    inline constexpr double kHopSeconds = 0.100; // 100 ms hop
    inline constexpr int kBlockHops = 4;         // 400 ms block = 4 hops
    inline constexpr int kShortTermHops = 30;    // 3 s short-term = 30 hops

    // --- Numerics ----------------------------------------------------------------
    inline constexpr double kSilenceLufs = -200.0; // sentinel for ~zero energy
    inline constexpr double kTinyEnergy = 1e-12;   // log10 floor (avoid -inf)

    // --- Gating histogram (bounded; libebur128-style) ----------------------------
    inline constexpr double kHistMinLufs = -70.0; // lowest binned loudness
    inline constexpr double kHistStepLu = 0.1;    // 0.1 LU resolution
    inline constexpr double kHistBinCenter = 0.5; // bin-center offset
    inline constexpr int kHistBins = 800;         // −70 … +10 LUFS

    // Defaults before prepare() is called (overwritten there).
    inline constexpr double kDefaultMeterSampleRate = 48000.0;
    inline constexpr uint32_t kDefaultMeterHopFrames = 4800U; // 100 ms @ 48 kHz

    // Default BS.1770-5 stereo weight (L and R).
    inline constexpr double kBs1770WeightLRC = 1.0;

    // ---------------------------------------------------------------------------
    // One TDF-II biquad in double precision (K-weighting stage).
    // ---------------------------------------------------------------------------
    struct LufsBiquad
    {
        double b0 = 1.0, b1 = 0.0, b2 = 0.0, a1 = 0.0, a2 = 0.0;
        double z1 = 0.0, z2 = 0.0;

        [[nodiscard]] auto processSample(double input) noexcept -> double
        {
            const double out = (b0 * input) + z1;
            z1 = (b1 * input) - (a1 * out) + z2;
            z2 = (b2 * input) - (a2 * out);
            // Denormal guard (S6 LOUD-1): fed exact-silence, this stable IIR's state decays
            // geometrically through the double subnormal range (< ~2.2e-308) before reaching 0.
            // Subnormal doubles are slow on some hardware, and — unlike single precision — AArch64
            // FPCR.FZ does NOT flush them, so a thread-level FTZ would not help; flush here
            // instead. Only true subnormals are zeroed, so no normal value (hence no LUFS reading)
            // changes.
            flushSubnormal(z1);
            flushSubnormal(z2);
            return out;
        }
        static void flushSubnormal(double& value) noexcept
        {
            if (std::abs(value) < std::numeric_limits<double>::min())
            {
                value = 0.0;
            }
        }
        void reset() noexcept
        {
            z1 = 0.0;
            z2 = 0.0;
        }
    };

    // K-weighting cascade for one channel: high-shelf → RLB high-pass.
    struct LufsKWeight
    {
        LufsBiquad shelf{};
        LufsBiquad rlb{};

        [[nodiscard]] auto processSample(double input) noexcept -> double
        {
            return rlb.processSample(shelf.processSample(input));
        }
        void reset() noexcept
        {
            shelf.reset();
            rlb.reset();
        }
    };

    class LufsMeter
    {
      public:
        LufsMeter() = default;

        // Off-RT setup. Derives K-weight coefficients for the given sample rate.
        // Defaults to stereo (numChannels_=2, weights {1,1,...}) so all existing
        // call sites are unaffected.  Call configureChannels() after prepare() to
        // override for N-channel operation.
        void prepare(double sampleRate) noexcept
        {
            sampleRate_ = sampleRate;
            hopFrames_ = static_cast<uint32_t>(std::lround(kHopSeconds * sampleRate));
            if (hopFrames_ == 0U)
            {
                hopFrames_ = 1U;
            }
            // Restore stereo defaults so prepare() is always a clean slate.
            numChannels_ = 2U;
            weights_.fill(kBs1770WeightLRC);
            computeShelf();
            computeRlb();
            reset();
        }

        // Configure N-channel measurement with per-channel BS.1770-5 weights.
        // Must be called after prepare().  Stores numChannels_ + weights_ and
        // calls reset() so filter state and accumulators are clean.
        //
        // Caller is responsible for computing weights_ from ChannelLayout.lufsWeight
        // (or the BS.1770-5 table: L/R/C = 1.0, LFE = 0.0, surround = 1.41).
        // The meter does NOT hard-code a channel-order assumption.
        //
        // Reference: ITU-R BS.1770-5 (2023), Annex 1, §1.1 (loudness model) and
        //            Table 1 (channel weighting coefficients).
        void configureChannels(uint32_t numChannels,
                               const std::array<double, kMaxChannels>& weights) noexcept
        {
            numChannels_ = (numChannels <= kMaxChannels) ? numChannels : kMaxChannels;
            weights_ = weights;
            reset();
        }

        // Clear all measurement state (filters, accumulators, histogram).
        void reset() noexcept
        {
            for (uint32_t ch = 0U; ch < kMaxChannels; ++ch)
            {
                chanK_[ch].reset();
            }
            accum_.fill(0.0);
            hopSampleCount_ = 0U;
            subBlocks_.fill(0.0);
            subHead_ = 0U;
            subFilled_ = 0U;
            histCount_.fill(0U);
            histSumEnergy_.fill(0.0);
            gatedBlockCount_ = 0U;
            momentaryLufs_ = kSilenceLufs;
            shortTermLufs_ = kSilenceLufs;
            integratedLufs_ = kSilenceLufs;
        }

        // Feed interleaved N-channel samples (ch0_fr0, ch1_fr0, …, ch0_fr1, …).
        // numChannels must match what was passed to configureChannels() (or 2 for
        // the default stereo case).  Updates all metrics.
        void addInterleaved(const float* samples, size_t frames, uint32_t numChannels) noexcept
        {
            for (size_t frm = 0U; frm < frames; ++frm)
            {
                for (uint32_t ch = 0U; ch < numChannels; ++ch)
                {
                    const double ky = chanK_[ch].processSample(
                        static_cast<double>(samples[(frm * numChannels) + ch]));
                    accum_[ch] += ky * ky;
                }
                if (++hopSampleCount_ >= hopFrames_)
                {
                    finishHop();
                }
            }
        }

        // Feed non-interleaved N-channel audio (planar; one pointer per channel).
        void addNonInterleaved(const float* const* channels,
                               size_t frames,
                               uint32_t numChannels) noexcept
        {
            for (size_t frm = 0U; frm < frames; ++frm)
            {
                for (uint32_t ch = 0U; ch < numChannels; ++ch)
                {
                    const double ky =
                        chanK_[ch].processSample(static_cast<double>(channels[ch][frm]));
                    accum_[ch] += ky * ky;
                }
                if (++hopSampleCount_ >= hopFrames_)
                {
                    finishHop();
                }
            }
        }

        // Feed interleaved stereo samples (L0,R0,L1,R1,…). Updates all metrics.
        // Kept for backward compatibility with existing call sites.  Equivalent to
        // addInterleaved(samples, frames, 2) when numChannels_==2 and
        // weights_=={1,1,...}, which is the default after prepare().
        void addInterleavedStereo(const float* samples, size_t frames) noexcept
        {
            addInterleaved(samples, frames, 2U);
        }

        // Feed non-interleaved stereo (separate L/R buffers — the AVAudioEngine tap
        // layout). Pass `right == left` for mono.
        // Kept for backward compatibility.  Equivalent to addNonInterleaved with
        // a two-element pointer array when numChannels_==2 and weights_=={1,1,...}.
        void addNonInterleavedStereo(const float* left, const float* right, size_t frames) noexcept
        {
            const std::array<const float*, 2U> ptrs{left, right};
            addNonInterleaved(ptrs.data(), frames, 2U);
        }

        [[nodiscard]] auto integratedLufs() const noexcept -> double
        {
            return integratedLufs_;
        }
        [[nodiscard]] auto momentaryLufs() const noexcept -> double
        {
            return momentaryLufs_;
        }
        [[nodiscard]] auto shortTermLufs() const noexcept -> double
        {
            return shortTermLufs_;
        }
        [[nodiscard]] auto gatedBlockCount() const noexcept -> uint32_t
        {
            return gatedBlockCount_;
        }

      private:
        // Block loudness from K-weighted mean-square energy z.
        [[nodiscard]] static auto blockLoudness(double energy) noexcept -> double
        {
            return (energy > kTinyEnergy) ? (kLufsOffset + (kDbPowerScale * std::log10(energy)))
                                          : kSilenceLufs;
        }

        // Sum of the most recent `count` per-hop weighted sum-of-squares.
        [[nodiscard]] auto sumRecentSubBlocks(int count) const noexcept -> double
        {
            double sum = 0.0;
            for (int i = 0; i < count; ++i)
            {
                const uint32_t idx = (subHead_ + static_cast<uint32_t>(kShortTermHops) - 1U -
                                      static_cast<uint32_t>(i)) %
                                     static_cast<uint32_t>(kShortTermHops);
                sum += subBlocks_[idx];
            }
            return sum;
        }

        // A 100 ms hop completed: apply channel weights, roll into windows, update metrics.
        //
        // BS.1770-5 Annex 1 block energy:
        //   z = Σ_ch G_ch · (accum_[ch] / N_block)
        // The N_block division is deferred to updateMomentaryAndIntegrated /
        // updateShortTerm (consistent with the original per-hop storage which also
        // stores raw sum-of-squares before dividing).  We store the WEIGHTED sum
        // here so sumRecentSubBlocks() only needs to divide once.
        void finishHop() noexcept
        {
            double hopEnergy = 0.0;
            for (uint32_t ch = 0U; ch < numChannels_; ++ch)
            {
                hopEnergy += weights_[ch] * accum_[ch];
                accum_[ch] = 0.0;
            }
            hopSampleCount_ = 0U;

            subBlocks_[subHead_] = hopEnergy;
            subHead_ = (subHead_ + 1U) % static_cast<uint32_t>(kShortTermHops);
            if (subFilled_ < static_cast<uint32_t>(kShortTermHops))
            {
                ++subFilled_;
            }

            updateMomentaryAndIntegrated();
            updateShortTerm();
        }

        void updateMomentaryAndIntegrated() noexcept
        {
            if (subFilled_ < static_cast<uint32_t>(kBlockHops))
            {
                return;
            }
            const double blockFrames = static_cast<double>(hopFrames_) * kBlockHops;
            const double energy = sumRecentSubBlocks(kBlockHops) / blockFrames;
            const double loudness = blockLoudness(energy);
            momentaryLufs_ = loudness;

            if (loudness >= kAbsoluteGateLufs)
            {
                addBlockToHistogram(loudness, energy);
                ++gatedBlockCount_;
                recomputeIntegrated();
            }
        }

        void updateShortTerm() noexcept
        {
            if (subFilled_ < static_cast<uint32_t>(kShortTermHops))
            {
                return;
            }
            const double frames = static_cast<double>(hopFrames_) * kShortTermHops;
            shortTermLufs_ = blockLoudness(sumRecentSubBlocks(kShortTermHops) / frames);
        }

        void addBlockToHistogram(double loudness, double energy) noexcept
        {
            const int rawIdx =
                static_cast<int>(std::floor((loudness - kHistMinLufs) / kHistStepLu));
            const int idx = std::clamp(rawIdx, 0, kHistBins - 1);
            const auto bin = static_cast<size_t>(idx);
            histCount_[bin] += 1U;
            histSumEnergy_[bin] += energy;
        }

        // Two-pass gated integrated loudness over the histogram (BS.1770-5 §2.3).
        void recomputeIntegrated() noexcept
        {
            uint64_t totalCount = 0U;
            double totalEnergy = 0.0;
            for (int i = 0; i < kHistBins; ++i)
            {
                totalCount += histCount_[static_cast<size_t>(i)];
                totalEnergy += histSumEnergy_[static_cast<size_t>(i)];
            }
            if (totalCount == 0U)
            {
                integratedLufs_ = kSilenceLufs;
                return;
            }
            const double absGatedMeanEnergy = totalEnergy / static_cast<double>(totalCount);
            const double relativeThreshold =
                blockLoudness(absGatedMeanEnergy) + kRelativeGateOffsetLu;

            uint64_t gatedCount = 0U;
            double gatedEnergy = 0.0;
            for (int i = 0; i < kHistBins; ++i)
            {
                const double binLoudness =
                    kHistMinLufs + ((static_cast<double>(i) + kHistBinCenter) * kHistStepLu);
                if (binLoudness >= relativeThreshold)
                {
                    gatedCount += histCount_[static_cast<size_t>(i)];
                    gatedEnergy += histSumEnergy_[static_cast<size_t>(i)];
                }
            }
            integratedLufs_ = (gatedCount == 0U)
                                  ? blockLoudness(absGatedMeanEnergy)
                                  : blockLoudness(gatedEnergy / static_cast<double>(gatedCount));
        }

        // Stage-1 high-shelf coefficients (bilinear + prewarp; libebur128 form).
        // Coefficients are computed once into chanK_[0] then copied to all other
        // channel slots — all channels share identical coefficients; only the delay
        // state (z1, z2) differs per channel.
        void computeShelf() noexcept
        {
            const double warp = std::tan(M_PI * kKwShelfF0Hz / sampleRate_);
            const double Vh = std::pow(kDecibelBase, kKwShelfGainDb / kDbAmplitudeScale);
            const double Vb = std::pow(Vh, kKwShelfVbExponent);
            const double a0 = 1.0 + (warp / kKwShelfQ) + (warp * warp);
            chanK_[0].shelf.b0 = (Vh + (Vb * warp / kKwShelfQ) + (warp * warp)) / a0;
            chanK_[0].shelf.b1 = 2.0 * ((warp * warp) - Vh) / a0;
            chanK_[0].shelf.b2 = (Vh - (Vb * warp / kKwShelfQ) + (warp * warp)) / a0;
            chanK_[0].shelf.a1 = 2.0 * ((warp * warp) - 1.0) / a0;
            chanK_[0].shelf.a2 = (1.0 - (warp / kKwShelfQ) + (warp * warp)) / a0;
            // Copy coefficients to all remaining channel slots (state resets independently).
            for (uint32_t ch = 1U; ch < kMaxChannels; ++ch)
            {
                chanK_[ch].shelf = chanK_[0].shelf;
            }
        }

        // Stage-2 RLB high-pass coefficients (bilinear + prewarp).
        // Same copy-broadcast pattern as computeShelf().
        void computeRlb() noexcept
        {
            const double warp = std::tan(M_PI * kKwRlbF0Hz / sampleRate_);
            const double a0 = 1.0 + (warp / kKwRlbQ) + (warp * warp);
            chanK_[0].rlb.b0 = 1.0 / a0;
            chanK_[0].rlb.b1 = -2.0 / a0;
            chanK_[0].rlb.b2 = 1.0 / a0;
            chanK_[0].rlb.a1 = 2.0 * ((warp * warp) - 1.0) / a0;
            chanK_[0].rlb.a2 = (1.0 - (warp / kKwRlbQ) + (warp * warp)) / a0;
            // Copy coefficients to all remaining channel slots.
            for (uint32_t ch = 1U; ch < kMaxChannels; ++ch)
            {
                chanK_[ch].rlb = chanK_[0].rlb;
            }
        }

        // K-weighting filter cascades — one per channel (kMaxChannels slots).
        // Coefficients are identical across slots; only z1/z2 delay state differs.
        std::array<LufsKWeight, kMaxChannels> chanK_{};

        // Per-channel 100 ms-hop accumulators (sum of squared K-weighted samples).
        std::array<double, kMaxChannels> accum_{};

        // Per-channel BS.1770-5 loudness weights (G_ch).
        // Default: all 1.0 (stereo).  Override via configureChannels().
        std::array<double, kMaxChannels> weights_{};

        // Active channel count (≤ kMaxChannels). Default: 2.
        uint32_t numChannels_ = 2U;

        uint32_t hopSampleCount_ = 0U;

        // Ring of the last 30 per-hop weighted energies (covers 400 ms and 3 s windows).
        std::array<double, kShortTermHops> subBlocks_{};
        uint32_t subHead_ = 0U;
        uint32_t subFilled_ = 0U;

        // Bounded gating histogram (loudness-binned block energy).
        std::array<uint64_t, kHistBins> histCount_{};
        std::array<double, kHistBins> histSumEnergy_{};
        uint32_t gatedBlockCount_ = 0U;

        double momentaryLufs_ = kSilenceLufs;
        double shortTermLufs_ = kSilenceLufs;
        double integratedLufs_ = kSilenceLufs;

        double sampleRate_ = kDefaultMeterSampleRate;
        uint32_t hopFrames_ = kDefaultMeterHopFrames;
    };

} // namespace AdaptiveSound
#endif // LUFS_METER_H
