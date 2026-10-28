// LfeStatistics.cpp — the LFE statistics, ported from the design's proto/p4_lfe_v2.py. See LfeStatistics.h.
//
// Sources:
//   [1] docs/design/level-and-fold/README.md §5 (the statistics, the rule), §8½ C2/C4 (p90 r²).
//   [2] proto/p4_lfe_v2.py — `band500` and `stats`, the reference this file reproduces.
//   [3] SciPy 1.x: signal.butter (prewarped bilinear), signal.sosfilt (DF2T), signal.welch (defaults:
//       periodic Hann, nperseg 512, noverlap 256, detrend 'constant', one-sided density, mean).
//   [4] NumPy: np.roll, np.median, np.percentile (linear interpolation).

#include "LfeStatistics.h"
#include <Accelerate/Accelerate.h>
#include <algorithm>
#include <cmath>
#include <limits>
#include <numbers>
#include <numeric>
#include <vector>

namespace AdaptiveSound
{
    namespace
    {
        // [2] band500: high-pass order 2 at 20 Hz, low-pass order 4 at 120 Hz.
        constexpr double kHighPassHz = 20.0;
        constexpr double kLowPassHz = 120.0;
        // Butterworth pole pairs' Q: order 2 → 1/√2; order 4 → 1/(2·cos(π/8)), 1/(2·cos(3π/8)).
        constexpr double kButterworthQ2 = 0.70710678118654752;
        constexpr double kButterworthQ4First = 0.54119610014619698;
        constexpr double kButterworthQ4Second = 1.30656296487637652;

        // [2] stats: 400 ms blocks every 100 ms at 500 Hz; the activity floor; the ±200 ms lag; ±20 ms taps.
        constexpr size_t kBlockSamples = 200U;
        constexpr size_t kHopSamples = 50U;
        constexpr double kActiveFloorDb = -50.0;
        constexpr uint32_t kMinActiveBlocks = 50U;
        constexpr ptrdiff_t kMaxLag = 100;
        constexpr ptrdiff_t kHalfTaps = 10;
        constexpr size_t kTaps = (2U * static_cast<size_t>(kHalfTaps)) + 1U; // 21
        constexpr double kTiny = 1e-30;                                      // [2]'s guard
        constexpr double kCoherentR2 = 0.8;
        constexpr double kExcessFloorDb = -20.0;
        constexpr double kMedian = 0.5;
        constexpr double kNinetieth = 0.9;
        constexpr double kMsPerBandSample = 1000.0 / LfeStatistics::kBandRateHz;
        constexpr double kDbPower = 10.0;

        // The fit's ridge, relative to the normal matrix's mean eigenvalue (its trace / p).
        constexpr double kRelativeRidge = 1e-12;
        constexpr double kRidgeGrowth = 100.0;
        constexpr int kRidgeAttempts = 6;
        constexpr size_t kFitRowsPerChunk = 1024U;

        // [3] welch defaults at [2]'s nperseg.
        constexpr size_t kWelchSegment = 512U;
        constexpr size_t kWelchStep = kWelchSegment / 2U;
        constexpr std::array<double, 5U> kThirdOctaveCentresHz = {25.0, 31.5, 40.0, 50.0, 63.0};
        constexpr double kThirdOctaveHalfWidth = 1.0 / 6.0; // edges fc·2^∓1/6
        constexpr double kNoExplainDb = -99.0;
        constexpr double kOneSided = 2.0; // interior bins of a one-sided density
        constexpr double kHannHalf = 0.5;

        [[nodiscard]] float nanFloat() noexcept
        {
            return std::numeric_limits<float>::quiet_NaN();
        }

        [[nodiscard]] AsLfeStats unmeasured(uint32_t activeBlocks) noexcept
        {
            AsLfeStats stats{};
            stats.activeBlocks = activeBlocks;
            stats.lagMs = nanFloat();
            stats.lagPeak = nanFloat();
            stats.coherentShare = nanFloat();
            stats.medianR2 = nanFloat();
            stats.p90R2 = nanFloat();
            stats.excess20Share = nanFloat();
            stats.explainGainDb = nanFloat();
            return stats;
        }

        [[nodiscard]] double dot(const double* first, const double* second, size_t count) noexcept
        {
            double sum = 0.0;
            vDSP_dotprD(first, 1, second, 1, &sum, static_cast<vDSP_Length>(count));
            return sum;
        }

        // [4] np.roll: rolled[i] = x[(i − shift) mod n]; the shift reduced to [0, n).
        [[nodiscard]] size_t rollShift(ptrdiff_t shift, size_t length) noexcept
        {
            const auto period = static_cast<ptrdiff_t>(length);
            return static_cast<size_t>(((shift % period) + period) % period);
        }

        // Σ_i a[i]·roll(b, shift)[i].
        [[nodiscard]] double rolledDot(std::span<const double> first,
                                       std::span<const double> second,
                                       ptrdiff_t shift) noexcept
        {
            const size_t length = first.size();
            const size_t offset = rollShift(shift, length);
            return dot(first.data() + offset, second.data(), length - offset) +
                   dot(first.data(), second.data() + (length - offset), offset);
        }

        // out[i] += scale · roll(x, shift)[i].
        void addRolled(std::span<double> out,
                       std::span<const double> source,
                       ptrdiff_t shift,
                       double scale) noexcept
        {
            const size_t length = out.size();
            const size_t offset = rollShift(shift, length);
            vDSP_vsmaD(source.data(),
                       1,
                       &scale,
                       out.data() + offset,
                       1,
                       out.data() + offset,
                       1,
                       static_cast<vDSP_Length>(length - offset));
            vDSP_vsmaD(source.data() + (length - offset),
                       1,
                       &scale,
                       out.data(),
                       1,
                       out.data(),
                       1,
                       static_cast<vDSP_Length>(offset));
        }

        // [4] np.percentile(values, 100·q), linear interpolation (values sorted ascending).
        [[nodiscard]] double percentile(std::span<const double> sorted, double quantile) noexcept
        {
            const double position = quantile * static_cast<double>(sorted.size() - 1U);
            const auto lower = static_cast<size_t>(std::floor(position));
            const size_t upper = std::min(lower + 1U, sorted.size() - 1U);
            const double fraction = position - static_cast<double>(lower);
            return sorted[lower] + (fraction * (sorted[upper] - sorted[lower]));
        }

        // The lower-triangular L with L·Lᵀ = G + λI (G symmetric, p × p, its upper triangle filled). False
        // when a pivot is not positive.
        [[nodiscard]] bool choleskyFactor(std::span<const double> gram,
                                          size_t size,
                                          double ridge,
                                          std::span<double> factor) noexcept
        {
            for (size_t col = 0U; col < size; ++col)
            {
                for (size_t row = col; row < size; ++row)
                {
                    double sum = gram[(col * size) + row] + ((row == col) ? ridge : 0.0);
                    for (size_t inner = 0U; inner < col; ++inner)
                    {
                        sum -= factor[(row * size) + inner] * factor[(col * size) + inner];
                    }
                    if (row != col)
                    {
                        factor[(row * size) + col] = sum / factor[(col * size) + col];
                    }
                    else if (sum > 0.0)
                    {
                        factor[(col * size) + col] = std::sqrt(sum);
                    }
                    else
                    {
                        return false;
                    }
                }
            }
            return true;
        }

        // L·z = c, then Lᵀ·w = z.
        void choleskySolve(std::span<const double> factor,
                           std::span<const double> rhs,
                           std::span<double> out)
        {
            const size_t size = rhs.size();
            std::vector<double> forward(size, 0.0);
            for (size_t row = 0U; row < size; ++row)
            {
                double sum = rhs[row];
                for (size_t inner = 0U; inner < row; ++inner)
                {
                    sum -= factor[(row * size) + inner] * forward[inner];
                }
                forward[row] = sum / factor[(row * size) + row];
            }
            for (size_t row = size; row-- > 0U;)
            {
                double sum = forward[row];
                for (size_t inner = row + 1U; inner < size; ++inner)
                {
                    sum -= factor[(inner * size) + row] * out[inner];
                }
                out[row] = sum / factor[(row * size) + row];
            }
        }

        // Solve (G + λI)·w = c, λ grown from kRelativeRidge of G's mean eigenvalue until the factorisation
        // holds. False (w untouched): G is all zero, or no ridge made it positive definite.
        [[nodiscard]] bool
        solveRidge(std::span<const double> gram, std::span<const double> rhs, std::span<double> out)
        {
            const size_t size = rhs.size();
            double trace = 0.0;
            for (size_t row = 0U; row < size; ++row)
            {
                trace += gram[(row * size) + row];
            }
            if (!(trace > 0.0))
            {
                return false;
            }
            std::vector<double> factor(size * size, 0.0);
            double ridge = kRelativeRidge * trace / static_cast<double>(size);
            for (int attempt = 0; attempt < kRidgeAttempts; ++attempt, ridge *= kRidgeGrowth)
            {
                if (choleskyFactor(gram, size, ridge, factor))
                {
                    choleskySolve(factor, rhs, out);
                    return true;
                }
            }
            return false;
        }

        // [3] welch's in-band power, summed over the bins in [lowHz, highHz): Σ_segments Σ_bins of the
        // one-sided density, divided by the segment count. Needs ≥ one whole segment.
        struct WelchBands
        {
            std::vector<double> cosTable;
            std::vector<double> sinTable;
            std::vector<double> window;
            double densityScale = 0.0;

            WelchBands() : cosTable(kWelchSegment), sinTable(kWelchSegment), window(kWelchSegment)
            {
                double windowEnergy = 0.0;
                for (size_t index = 0U; index < kWelchSegment; ++index)
                {
                    const double angle = 2.0 * std::numbers::pi * static_cast<double>(index) /
                                         static_cast<double>(kWelchSegment);
                    cosTable[index] = std::cos(angle);
                    sinTable[index] = std::sin(angle);
                    window[index] = kHannHalf - (kHannHalf * std::cos(angle)); // periodic Hann
                    windowEnergy += window[index] * window[index];
                }
                densityScale = kOneSided / (LfeStatistics::kBandRateHz * windowEnergy);
            }

            // One value per third-octave band of kThirdOctaveCentresHz.
            [[nodiscard]] std::array<double, kThirdOctaveCentresHz.size()>
            power(std::span<const double> signal) const
            {
                std::array<double, kThirdOctaveCentresHz.size()> bands{};
                const size_t segments = ((signal.size() - kWelchSegment) / kWelchStep) + 1U;
                const double binHz =
                    LfeStatistics::kBandRateHz / static_cast<double>(kWelchSegment);
                std::vector<double> windowed(kWelchSegment);
                for (size_t segment = 0U; segment < segments; ++segment)
                {
                    const double* start = signal.data() + (segment * kWelchStep);
                    double mean = 0.0;
                    vDSP_meanvD(start, 1, &mean, static_cast<vDSP_Length>(kWelchSegment));
                    for (size_t index = 0U; index < kWelchSegment; ++index)
                    {
                        windowed[index] = (start[index] - mean) * window[index];
                    }
                    for (size_t band = 0U; band < kThirdOctaveCentresHz.size(); ++band)
                    {
                        const double centre = kThirdOctaveCentresHz[band];
                        const double lowHz = centre / std::exp2(kThirdOctaveHalfWidth);
                        const double highHz = centre * std::exp2(kThirdOctaveHalfWidth);
                        for (size_t bin = 1U; bin < kWelchSegment / 2U; ++bin)
                        {
                            const double frequency = static_cast<double>(bin) * binHz;
                            if (frequency < lowHz || !(frequency < highHz))
                            {
                                continue;
                            }
                            double real = 0.0;
                            double imaginary = 0.0;
                            for (size_t index = 0U; index < kWelchSegment; ++index)
                            {
                                const size_t turn = (bin * index) % kWelchSegment;
                                real += windowed[index] * cosTable[turn];
                                imaginary -= windowed[index] * sinTable[turn];
                            }
                            bands[band] += ((real * real) + (imaginary * imaginary)) * densityScale;
                        }
                    }
                }
                const auto count = static_cast<double>(segments);
                std::ranges::transform(
                    bands, bands.begin(), [count](double band) { return band / count; });
                return bands;
            }
        };
    } // namespace

    LfeStatistics::Band LfeStatistics::makeBand(double sampleRate) noexcept
    {
        // [3] butter: the analog prototype prewarped by K = tan(π·f/fs), then the bilinear transform.
        const auto lowPass = [sampleRate](double cutoffHz, double quality)
        {
            const double warp = std::tan(std::numbers::pi * cutoffHz / sampleRate);
            const double norm = 1.0 + (warp / quality) + (warp * warp);
            Section section;
            section.b0 = (warp * warp) / norm;
            section.b1 = 2.0 * section.b0;
            section.b2 = section.b0;
            section.a1 = 2.0 * ((warp * warp) - 1.0) / norm;
            section.a2 = (1.0 - (warp / quality) + (warp * warp)) / norm;
            return section;
        };
        const auto highPass = [sampleRate](double cutoffHz, double quality)
        {
            const double warp = std::tan(std::numbers::pi * cutoffHz / sampleRate);
            const double norm = 1.0 + (warp / quality) + (warp * warp);
            Section section;
            section.b0 = 1.0 / norm;
            section.b1 = -2.0 / norm;
            section.b2 = section.b0;
            section.a1 = 2.0 * ((warp * warp) - 1.0) / norm;
            section.a2 = (1.0 - (warp / quality) + (warp * warp)) / norm;
            return section;
        };
        return Band{
            highPass(kHighPassHz, kButterworthQ2),
            lowPass(kLowPassHz, kButterworthQ4First),
            lowPass(kLowPassHz, kButterworthQ4Second),
        };
    }

    double LfeStatistics::filter(Band& band, double input) noexcept
    {
        double value = input;
        for (Section& section : band)
        {
            value = section.process(value);
        }
        return value;
    }

    LfeStatistics::LfeStatistics(double sampleRate, std::span<const ChannelRole> roles)
        : channels_(static_cast<uint32_t>(std::min<size_t>(roles.size(), kMaxChannels))),
          decimation_(static_cast<uint32_t>(std::max(1L, std::lround(sampleRate / kBandRateHz))))
    {
        uint32_t lfeChannels = 0U;
        uint32_t mainChannels = 0U;
        for (uint32_t ch = 0U; ch < channels_; ++ch)
        {
            if (roles[ch] == ChannelRole::Lfe)
            {
                mainOf_[ch] = -1;
                ++lfeChannels;
            }
            else
            {
                mainOf_[ch] = static_cast<int>(mainChannels);
                ++mainChannels;
            }
        }
        measures_ = lfeChannels > 0U && mainChannels > 0U;
        if (measures_)
        {
            mainBands_.assign(mainChannels, makeBand(sampleRate));
            lfeBand_ = makeBand(sampleRate);
            mains_.resize(mainChannels);
        }
    }

    void LfeStatistics::process(std::span<const double* const> channels, size_t frames)
    {
        if (!measures_)
        {
            return;
        }
        for (size_t frame = 0U; frame < frames; ++frame)
        {
            const bool keep = phase_ == 0U;
            double lfeInput = 0.0;
            for (uint32_t ch = 0U; ch < channels_; ++ch)
            {
                const double sample = channels[ch][frame];
                const int main = mainOf_[ch];
                if (main < 0)
                {
                    lfeInput += sample;
                    continue;
                }
                const auto index = static_cast<size_t>(main);
                const double banded = filter(mainBands_[index], sample);
                if (keep)
                {
                    mains_[index].push_back(banded);
                }
            }
            const double lfeBanded = filter(lfeBand_, lfeInput);
            if (keep)
            {
                lfe_.push_back(lfeBanded);
            }
            phase_ = (phase_ + 1U == decimation_) ? 0U : phase_ + 1U;
        }
    }

    AsLfeStats LfeStatistics::finish() const
    {
        if (!measures_)
        {
            return unmeasured(0U);
        }
        return measure(mains_, lfe_);
    }

    namespace
    {
        // The starts of the active blocks: the LFE band's mean square at or above −50 dB.
        [[nodiscard]] std::vector<size_t> activeStarts(std::span<const double> lfe)
        {
            std::vector<size_t> active;
            for (size_t start = 0U; start + kBlockSamples <= lfe.size(); start += kHopSamples)
            {
                const double meanSquare =
                    dot(lfe.data() + start, lfe.data() + start, kBlockSamples) /
                    static_cast<double>(kBlockSamples);
                if (kDbPower * std::log10(meanSquare + kTiny) >= kActiveFloorDb)
                {
                    active.push_back(start);
                }
            }
            return active;
        }

        // The global lag: the normalised correlation of the masked LFE with the masked, rolled mains'
        // sum over ±kMaxLag; the first lag of the largest |r|.
        struct Lag
        {
            ptrdiff_t samples = 0;
            double correlation = 0.0;
        };

        [[nodiscard]] Lag globalLag(std::span<const double> lfe,
                                    std::span<const double> mainSum,
                                    std::span<const uint8_t> mask)
        {
            const size_t length = lfe.size();
            std::vector<double> maskedLfe(length, 0.0);
            std::vector<double> maskedSum(length, 0.0);
            for (size_t index = 0U; index < length; ++index)
            {
                if (mask[index] != 0U)
                {
                    maskedLfe[index] = lfe[index];
                    maskedSum[index] = mainSum[index];
                }
            }
            const double norm = std::sqrt((dot(maskedLfe.data(), maskedLfe.data(), length) *
                                           dot(maskedSum.data(), maskedSum.data(), length)) +
                                          kTiny);
            Lag best;
            for (ptrdiff_t lag = -kMaxLag; lag <= kMaxLag; ++lag)
            {
                const double correlation = rolledDot(maskedLfe, maskedSum, lag) / norm;
                if (std::abs(correlation) > std::abs(best.correlation))
                {
                    best = Lag{lag, correlation};
                }
            }
            return best;
        }

        // The fit: one 21-tap FIR per main centred on the lag (column (main, tap) is the main rolled by
        // lag + tap − 10), least squares over the masked rows farther than kMaxLag + kHalfTaps from
        // either end; returns the prediction over every sample (zero when the mains are silent).
        [[nodiscard]] std::vector<double> fitPrediction(std::span<const std::vector<double>> mains,
                                                        std::span<const double> lfe,
                                                        std::span<const size_t> rows,
                                                        ptrdiff_t lag)
        {
            const size_t length = lfe.size();
            const size_t mainCount = mains.size();
            const size_t columns = mainCount * kTaps;
            const auto shiftOf = [lag](size_t tap) -> ptrdiff_t
            { return lag + static_cast<ptrdiff_t>(tap) - kHalfTaps; };
            std::vector<double> gram(columns * columns, 0.0);
            std::vector<double> crossed(columns, 0.0);
            std::vector<double> design(kFitRowsPerChunk * columns, 0.0);
            std::vector<double> target(kFitRowsPerChunk, 0.0);
            for (size_t first = 0U; first < rows.size(); first += kFitRowsPerChunk)
            {
                const size_t count = std::min(kFitRowsPerChunk, rows.size() - first);
                for (size_t row = 0U; row < count; ++row)
                {
                    const size_t index = rows[first + row];
                    target[row] = lfe[index];
                    for (size_t column = 0U; column < columns; ++column)
                    {
                        const size_t shift = rollShift(shiftOf(column % kTaps), length);
                        design[(row * columns) + column] =
                            mains[column / kTaps][(index + length - shift) % length];
                    }
                }
                cblas_dsyrk(CblasRowMajor,
                            CblasUpper,
                            CblasTrans,
                            static_cast<__LAPACK_int>(columns),
                            static_cast<__LAPACK_int>(count),
                            1.0,
                            design.data(),
                            static_cast<__LAPACK_int>(columns),
                            1.0,
                            gram.data(),
                            static_cast<__LAPACK_int>(columns));
                cblas_dgemv(CblasRowMajor,
                            CblasTrans,
                            static_cast<__LAPACK_int>(count),
                            static_cast<__LAPACK_int>(columns),
                            1.0,
                            design.data(),
                            static_cast<__LAPACK_int>(columns),
                            target.data(),
                            1,
                            1.0,
                            crossed.data(),
                            1);
            }
            std::vector<double> weights(columns, 0.0);
            std::vector<double> prediction(length, 0.0);
            if (solveRidge(gram, crossed, weights))
            {
                for (size_t column = 0U; column < columns; ++column)
                {
                    addRolled(prediction,
                              mains[column / kTaps],
                              shiftOf(column % kTaps),
                              weights[column]);
                }
            }
            return prediction;
        }

        // Per active block: the shape match r² (scale-invariant) and the unexplained LFE power against the
        // mains' low-band power; the shares and percentiles over the active blocks.
        struct BlockShares
        {
            double coherent = 0.0;
            double excess20 = 0.0;
            double medianR2 = 0.0;
            double p90R2 = 0.0;
        };

        [[nodiscard]] BlockShares blockShares(std::span<const std::vector<double>> mains,
                                              std::span<const double> lfe,
                                              std::span<const double> prediction,
                                              std::span<const size_t> active)
        {
            std::vector<double> rSquared;
            rSquared.reserve(active.size());
            size_t coherent = 0U;
            size_t excess = 0U;
            const auto blockLength = static_cast<double>(kBlockSamples);
            for (const size_t start : active)
            {
                const double* lfeBlock = lfe.data() + start;
                const double* predicted = prediction.data() + start;
                const double lfeEnergy = dot(lfeBlock, lfeBlock, kBlockSamples);
                const double correlation =
                    dot(lfeBlock, predicted, kBlockSamples) /
                    std::sqrt((lfeEnergy * dot(predicted, predicted, kBlockSamples)) + kTiny);
                const double r2 = correlation * correlation;
                rSquared.push_back(r2);
                coherent += (r2 >= kCoherentR2) ? 1U : 0U;
                const double mainPower = std::accumulate(
                    mains.begin(),
                    mains.end(),
                    0.0,
                    [start, blockLength](double sum, const std::vector<double>& main)
                    {
                        return sum + (dot(main.data() + start, main.data() + start, kBlockSamples) /
                                      blockLength);
                    });
                const double unexplained = (lfeEnergy / blockLength) * (1.0 - r2);
                const double excessDb =
                    kDbPower * std::log10((unexplained / (mainPower + kTiny)) + kTiny);
                excess += (excessDb >= kExcessFloorDb) ? 1U : 0U;
            }
            std::ranges::sort(rSquared);
            const auto activeCount = static_cast<double>(active.size());
            return BlockShares{
                static_cast<double>(coherent) / activeCount,
                static_cast<double>(excess) / activeCount,
                percentile(rSquared, kMedian),
                percentile(rSquared, kNinetieth),
            };
        }

        // The explaining gain: max over the 25–63 Hz third-octaves of the prediction's Welch power over the
        // mains' sum's, both over the fitted rows. NaN with fewer rows than one Welch segment.
        [[nodiscard]] double explainGainDb(std::span<const double> prediction,
                                           std::span<const double> mainSum,
                                           std::span<const size_t> rows)
        {
            if (rows.size() < kWelchSegment)
            {
                return std::numeric_limits<double>::quiet_NaN();
            }
            std::vector<double> fittedPrediction(rows.size());
            std::vector<double> fittedSum(rows.size());
            for (size_t row = 0U; row < rows.size(); ++row)
            {
                fittedPrediction[row] = prediction[rows[row]];
                fittedSum[row] = mainSum[rows[row]];
            }
            const WelchBands welch;
            const auto predictedBands = welch.power(fittedPrediction);
            const auto sumBands = welch.power(fittedSum);
            double explain = kNoExplainDb;
            for (size_t band = 0U; band < predictedBands.size(); ++band)
            {
                explain = std::max(
                    explain,
                    kDbPower *
                        std::log10((predictedBands[band] / (sumBands[band] + kTiny)) + kTiny));
            }
            return explain;
        }
    } // namespace

    AsLfeStats LfeStatistics::measure(std::span<const std::vector<double>> mains,
                                      std::span<const double> lfe)
    {
        const size_t length = lfe.size();
        const bool aligned = std::ranges::all_of(
            mains, [length](const std::vector<double>& main) { return main.size() == length; });
        if (mains.empty() || length < kBlockSamples || !aligned)
        {
            return unmeasured(0U);
        }
        const std::vector<size_t> active = activeStarts(lfe);
        AsLfeStats stats = unmeasured(static_cast<uint32_t>(active.size()));
        if (active.size() < kMinActiveBlocks)
        {
            return stats;
        }
        std::vector<uint8_t> mask(length, 0U);
        for (const size_t start : active)
        {
            std::fill_n(mask.begin() + static_cast<ptrdiff_t>(start), kBlockSamples, uint8_t{1U});
        }
        std::vector<double> mainSum(length, 0.0);
        for (const std::vector<double>& main : mains)
        {
            vDSP_vaddD(mainSum.data(),
                       1,
                       main.data(),
                       1,
                       mainSum.data(),
                       1,
                       static_cast<vDSP_Length>(length));
        }
        const Lag lag = globalLag(lfe, mainSum, mask);
        stats.lagMs = static_cast<float>(static_cast<double>(lag.samples) * kMsPerBandSample);
        stats.lagPeak = static_cast<float>(std::abs(lag.correlation));

        std::vector<size_t> rows;
        const auto margin = static_cast<size_t>(kMaxLag + kHalfTaps);
        for (size_t index = margin + 1U; index + margin < length; ++index)
        {
            if (mask[index] != 0U)
            {
                rows.push_back(index);
            }
        }
        const std::vector<double> prediction = fitPrediction(mains, lfe, rows, lag.samples);
        const BlockShares shares = blockShares(mains, lfe, prediction, active);
        stats.coherentShare = static_cast<float>(shares.coherent);
        stats.excess20Share = static_cast<float>(shares.excess20);
        stats.medianR2 = static_cast<float>(shares.medianR2);
        stats.p90R2 = static_cast<float>(shares.p90R2);
        stats.explainGainDb = static_cast<float>(explainGainDb(prediction, mainSum, rows));
        return stats;
    }
} // namespace AdaptiveSound
