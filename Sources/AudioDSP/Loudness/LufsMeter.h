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
//       z = Σ_i G_i · (Σ y_i² over 400 ms) / N_block          (G = 1 for L/R)
//       block loudness  l = −0.691 + 10·log10(z)
//   integrated (gated):
//       absolute gate: keep blocks with l ≥ −70 LUFS
//       relative gate: keep blocks with l ≥ (loudness of ungated mean) − 10 LU
//       I = −0.691 + 10·log10(mean z over relatively-gated blocks)
//   momentary  = block loudness over the last 400 ms (no gate)
//   short-term = block loudness over the last 3 s   (no gate)
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
//   - ITU-R BS.1770-5 (2023), Annex 1 (K-weighting + gating).
//   - EBU Tech 3341 (EBU Mode metering); EBU R128.
//   - jiixyj/libebur128 ebur128.c (coefficient derivation, double accumulation,
//     histogram gating) — verified.

#include <algorithm>
#include <array>
#include <cmath>
#include <cstddef>
#include <cstdint>

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
            return out;
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
        void prepare(double sampleRate) noexcept
        {
            sampleRate_ = sampleRate;
            hopFrames_ = static_cast<uint32_t>(std::lround(kHopSeconds * sampleRate));
            if (hopFrames_ == 0U)
            {
                hopFrames_ = 1U;
            }
            computeShelf();
            computeRlb();
            reset();
        }

        // Clear all measurement state (filters, accumulators, histogram).
        void reset() noexcept
        {
            leftK_.reset();
            rightK_.reset();
            accumLeft_ = 0.0;
            accumRight_ = 0.0;
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

        // Feed interleaved stereo samples (L0,R0,L1,R1,…). Updates all metrics.
        void addInterleavedStereo(const float* samples, size_t frames) noexcept
        {
            for (size_t i = 0U; i < frames; ++i)
            {
                const double left = leftK_.processSample(static_cast<double>(samples[2U * i]));
                const double right =
                    rightK_.processSample(static_cast<double>(samples[(2U * i) + 1U]));
                accumLeft_ += left * left;
                accumRight_ += right * right;
                if (++hopSampleCount_ >= hopFrames_)
                {
                    finishHop();
                }
            }
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
        // Block loudness from K-weighted mean-square energy z (stereo G = 1).
        [[nodiscard]] static auto blockLoudness(double energy) noexcept -> double
        {
            return (energy > kTinyEnergy) ? (kLufsOffset + (kDbPowerScale * std::log10(energy)))
                                          : kSilenceLufs;
        }

        // Sum of the most recent `count` per-hop sum-of-squares (across channels).
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

        // A 100 ms hop completed: roll it into the windows and update metrics.
        void finishHop() noexcept
        {
            const double hopEnergy = accumLeft_ + accumRight_; // G_L = G_R = 1
            accumLeft_ = 0.0;
            accumRight_ = 0.0;
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
            const int rawIdx = static_cast<int>(std::floor((loudness - kHistMinLufs) / kHistStepLu));
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
        void computeShelf() noexcept
        {
            const double warp = std::tan(M_PI * kKwShelfF0Hz / sampleRate_);
            const double Vh = std::pow(kDecibelBase, kKwShelfGainDb / kDbAmplitudeScale);
            const double Vb = std::pow(Vh, kKwShelfVbExponent);
            const double a0 = 1.0 + (warp / kKwShelfQ) + (warp * warp);
            leftK_.shelf.b0 = (Vh + (Vb * warp / kKwShelfQ) + (warp * warp)) / a0;
            leftK_.shelf.b1 = 2.0 * ((warp * warp) - Vh) / a0;
            leftK_.shelf.b2 = (Vh - (Vb * warp / kKwShelfQ) + (warp * warp)) / a0;
            leftK_.shelf.a1 = 2.0 * ((warp * warp) - 1.0) / a0;
            leftK_.shelf.a2 = (1.0 - (warp / kKwShelfQ) + (warp * warp)) / a0;
            rightK_.shelf = leftK_.shelf;
        }

        // Stage-2 RLB high-pass coefficients (bilinear + prewarp).
        void computeRlb() noexcept
        {
            const double warp = std::tan(M_PI * kKwRlbF0Hz / sampleRate_);
            const double a0 = 1.0 + (warp / kKwRlbQ) + (warp * warp);
            leftK_.rlb.b0 = 1.0 / a0;
            leftK_.rlb.b1 = -2.0 / a0;
            leftK_.rlb.b2 = 1.0 / a0;
            leftK_.rlb.a1 = 2.0 * ((warp * warp) - 1.0) / a0;
            leftK_.rlb.a2 = (1.0 - (warp / kKwRlbQ) + (warp * warp)) / a0;
            rightK_.rlb = leftK_.rlb;
        }

        // K-weighting filters (one cascade per channel).
        LufsKWeight leftK_{};
        LufsKWeight rightK_{};

        // 100 ms-hop accumulators (sum of squared K-weighted samples).
        double accumLeft_ = 0.0;
        double accumRight_ = 0.0;
        uint32_t hopSampleCount_ = 0U;

        // Ring of the last 30 per-hop energies (covers 400 ms and 3 s windows).
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
