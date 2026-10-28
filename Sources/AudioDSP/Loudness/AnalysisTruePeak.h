#pragma once

// AnalysisTruePeak.h — the one analysis pass's true peak (R1.1-B; the level-and-fold design,
// docs/design/level-and-fold/README.md §0 P1 and §2). Analysis-only: the limiter's own kernel
// (include/TruePeakKernel.h) is untouched.
//
// THE READING. Per channel group, the maximum over the whole stream of:
//   - the SHIPPED kernel: 8× polyphase, 24 taps per phase (TruePeakKernel — the very coefficients the
//     effects limiter's detector runs), so the analysis never reads below what the limiter will see;
//   - an 8× kernel with 64 TAPS per phase, the same design (Kaiser β 8 windowed sinc, cut-off at the base
//     band's Nyquist) at 512 prototype taps: through Apple's converter it under-reads the reconstructed peak
//     by at most 0.09 dB where the shipped one under-reads by up to 1.01 dB (§2, challenger #4, measured);
//   - the samples themselves: a band-limited reconstruction passes through every sample, and both kernels'
//     phases sit 1/16 sample off the input grid, so the sample peak is a floor neither kernel guarantees.
// The stream is read from silence (zero history) and flushed with silence (kLongTaps − 1 zeros), as the
// limiter sees a track begin and end.
//
// THE EXACT PRUNING BOUND. |y_p[n]| ≤ max_k |x[n − k]| · ‖h_p‖₁ for every phase p (‖h_p‖₁ ≤ 2.18 for both
// kernels). A run of samples whose window maximum times the larger bound cannot exceed the group's running
// maximum cannot raise it, so it is skipped: the reading is exactly the unpruned one. A group (all N channels
// of a file; the two channels of a fold) shares one running maximum, because the reading is their maximum.
//
// COST. The phases of a run that is evaluated go through vDSP_convD (double precision; the summation order
// differs from TruePeakKernel::phasePeak by rounding only, ~1e-16 relative).
//
// THREADS. One owner (the analysis job); allocation only at construction.

#include "../include/AudioConstants.h"
#include "../include/TruePeakKernel.h"
#include <Accelerate/Accelerate.h>
#include <algorithm>
#include <array>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <numbers>
#include <span>
#include <vector>

namespace AdaptiveSound::AnalysisTruePeak
{
    inline constexpr uint32_t kOversampling = TruePeakKernel::kOversampling; // 8×
    inline constexpr uint32_t kShortTaps = TruePeakKernel::kNumTaps;         // the shipped 24
    inline constexpr uint32_t kLongTaps = 64U;                               // the analysis kernel
    inline constexpr uint32_t kLongPrototypeN = kOversampling * kLongTaps;   // 512
    inline constexpr uint32_t kHistory = kLongTaps - 1U; // samples kept across calls
    inline constexpr size_t kRun = 128U;                 // samples per pruning decision
    inline constexpr size_t kChunk = 2048U;              // samples per buffered pass

    // Phase-major, as TruePeakKernel: coeffs[phase · kLongTaps + tap] = h[phase + tap · 8].
    using LongCoefficients = std::array<double, kLongPrototypeN>;

    // The 8×64 design: TruePeakKernel::computeCoefficients's formula at 64 taps per phase.
    // h[n] = L·(2·fc)·sinc(2·fc·(n − M))·kaiser(n, β), M = (N − 1)/2, fc = 0.5/L (the base band's Nyquist).
    inline void computeLongCoefficients(LongCoefficients& coeffs) noexcept
    {
        const double centre = static_cast<double>(kLongPrototypeN - 1U) / 2.0; // 255.5
        const double twoFc = 2.0 * TruePeakKernel::kProtoCutoffNorm;           // 1/L
        const double scale = static_cast<double>(kOversampling) * twoFc;       // 1
        const double i0Beta = TruePeakKernel::kaiserI0(TruePeakKernel::kKaiserBeta);
        const double span = static_cast<double>(kLongPrototypeN - 1U);
        for (uint32_t index = 0U; index < kLongPrototypeN; ++index)
        {
            // The distance is half-integer, so the sinc's argument is never 0.
            const double distance = static_cast<double>(index) - centre;
            const double argument = twoFc * distance;
            const double sinc =
                std::sin(std::numbers::pi * argument) / (std::numbers::pi * argument);
            const double ratio = (2.0 * distance) / span;
            const double window =
                TruePeakKernel::kaiserI0(TruePeakKernel::kKaiserBeta *
                                         std::sqrt(std::max(0.0, 1.0 - (ratio * ratio)))) /
                i0Beta;
            const uint32_t phase = index % kOversampling;
            const uint32_t tap = index / kOversampling;
            coeffs[(static_cast<size_t>(phase) * kLongTaps) + tap] = scale * sinc * window;
        }
    }

    // max over phases of ‖h_p‖₁ for a phase-major bank of `taps` taps per phase.
    [[nodiscard]] inline double maxPhaseL1(std::span<const double> coeffs, uint32_t taps) noexcept
    {
        double worst = 0.0;
        for (uint32_t phase = 0U; phase < kOversampling; ++phase)
        {
            double sum = 0.0;
            for (uint32_t tap = 0U; tap < taps; ++tap)
            {
                sum += std::abs(coeffs[(static_cast<size_t>(phase) * taps) + tap]);
            }
            worst = std::max(worst, sum);
        }
        return worst;
    }

    // A group of channels read as one true peak (their maximum).
    class Detector
    {
      public:
        explicit Detector(uint32_t channels)
            : channels_(channels),
              buffers_(static_cast<size_t>(channels) * (kHistory + kChunk), 0.0),
              phaseOut_(kRun, 0.0)
        {
            TruePeakKernel::computeCoefficients(short_);
            computeLongCoefficients(long_);
            bound_ = std::max(maxPhaseL1(short_, kShortTaps), maxPhaseL1(long_, kLongTaps));
        }

        // Read `frames` more frames of each channel (one pointer per channel, `channels` of them).
        void process(std::span<const double* const> input, size_t frames) noexcept
        {
            size_t done = 0U;
            while (done < frames)
            {
                const size_t count = std::min(kChunk, frames - done);
                for (uint32_t ch = 0U; ch < channels_; ++ch)
                {
                    double* buffer = channelBuffer(ch);
                    std::copy_n(input[ch] + done, count, buffer + kHistory);
                    readChannel(buffer, count);
                    // Keep the newest kHistory samples as the next pass's history.
                    std::copy_n(buffer + count, kHistory, buffer);
                }
                done += count;
            }
        }

        // The stream has ended: read the reconstruction's tail, as the limiter does into silence.
        void flush() noexcept
        {
            for (uint32_t ch = 0U; ch < channels_; ++ch)
            {
                double* buffer = channelBuffer(ch);
                std::fill_n(buffer + kHistory, kHistory, 0.0);
                readChannel(buffer, kHistory);
                std::copy_n(buffer + kHistory, kHistory, buffer);
            }
        }

        // The group's true peak so far (linear, ≥ 0).
        [[nodiscard]] double peakLinear() const noexcept
        {
            return peak_;
        }

        // The runs the pruning bound let through (diagnostics: the cost's measure).
        [[nodiscard]] uint64_t evaluatedRuns() const noexcept
        {
            return evaluatedRuns_;
        }
        [[nodiscard]] uint64_t totalRuns() const noexcept
        {
            return totalRuns_;
        }

      private:
        [[nodiscard]] double* channelBuffer(uint32_t channel) noexcept
        {
            return buffers_.data() + (static_cast<size_t>(channel) * (kHistory + kChunk));
        }

        // `buffer` holds kHistory samples of history, then `count` new ones.
        void readChannel(const double* buffer, size_t count) noexcept
        {
            for (size_t start = 0U; start < count; start += kRun)
            {
                const size_t run = std::min(kRun, count - start);
                const double* newest = buffer + kHistory + start; // the run's first new sample
                ++totalRuns_;
                // The samples first: they are a floor, and they raise the running maximum early.
                double sampleMax = 0.0;
                vDSP_maxmgvD(newest, 1, &sampleMax, static_cast<vDSP_Length>(run));
                peak_ = std::max(peak_, sampleMax);
                // Every phase output in the run reads only the run and its kHistory predecessors.
                double windowMax = 0.0;
                vDSP_maxmgvD(
                    newest - kHistory, 1, &windowMax, static_cast<vDSP_Length>(run + kHistory));
                if (windowMax * bound_ <= peak_)
                {
                    continue;
                }
                ++evaluatedRuns_;
                readPhases(newest, run, short_, kShortTaps);
                readPhases(newest, run, long_, kLongTaps);
            }
        }

        // y_p[n] = Σ_k h_p[k]·x[n − k] for the run's n, every phase; the largest |y| raises the peak.
        void readPhases(const double* newest,
                        size_t run,
                        std::span<const double> coeffs,
                        uint32_t taps) noexcept
        {
            for (uint32_t phase = 0U; phase < kOversampling; ++phase)
            {
                // vDSP_convD with a negative filter stride convolves: the filter pointer is its last tap.
                const double* lastTap =
                    coeffs.data() + (static_cast<size_t>(phase) * taps) + (taps - 1U);
                vDSP_convD(newest - (taps - 1U),
                           1,
                           lastTap,
                           -1,
                           phaseOut_.data(),
                           1,
                           static_cast<vDSP_Length>(run),
                           static_cast<vDSP_Length>(taps));
                double phaseMax = 0.0;
                vDSP_maxmgvD(phaseOut_.data(), 1, &phaseMax, static_cast<vDSP_Length>(run));
                peak_ = std::max(peak_, phaseMax);
            }
        }

        uint32_t channels_ = 0U;
        TruePeakKernel::Coefficients short_{};
        LongCoefficients long_{};
        double bound_ = 0.0;
        std::vector<double>
            buffers_; // per channel: kHistory of history, then up to kChunk new samples
        std::vector<double> phaseOut_;
        double peak_ = 0.0;
        uint64_t evaluatedRuns_ = 0U;
        uint64_t totalRuns_ = 0U;
    };
} // namespace AdaptiveSound::AnalysisTruePeak
