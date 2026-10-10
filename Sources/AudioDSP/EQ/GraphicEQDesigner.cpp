// GraphicEQDesigner.cpp — the accurate 31-band graphic-EQ solve. See GraphicEQDesigner.h.

#include "GraphicEQDesigner.h"
#include "../include/AudioConstants.h"
#include <algorithm>
#include <cmath>
#include <cstddef>

namespace AdaptiveSound
{
    namespace
    {
        using GraphicEQ::kBandCount;

        constexpr auto kBands = static_cast<size_t>(kBandCount);
        constexpr size_t kPoints = (2 * kBands) - 1;

        // Design point p is band centre p / 2 when p is even, and the geometric midpoint of
        // centres p / 2 and p / 2 + 1 when p is odd.
        [[nodiscard]] constexpr bool isCentre(size_t point) noexcept
        {
            return point % 2U == 0U;
        }

        // The WLS weight² of a design point: centres 1, midpoints 0.5² = 0.25.
        [[nodiscard]] constexpr double weightSquared(size_t point) noexcept
        {
            return isCentre(point)
                       ? 1.0
                       : GraphicEQDesigner::kMidpointWeight * GraphicEQDesigner::kMidpointWeight;
        }

        // The prototype a refinement pass divides by: the previous gain, kept at least
        // kGuardGainDb from 0 (a 0 dB bell has no shape to divide out; engine-plan §2.1).
        [[nodiscard]] double guardedGainDb(double gainDb) noexcept
        {
            if (std::abs(gainDb) < GraphicEQDesigner::kGuardGainDb)
            {
                return (gainDb >= 0.0) ? GraphicEQDesigner::kGuardGainDb
                                       : -GraphicEQDesigner::kGuardGainDb;
            }
            return gainDb;
        }

        [[nodiscard]] bool allFinite(std::span<const double> values) noexcept
        {
            return std::ranges::all_of(values, [](double value) { return std::isfinite(value); });
        }
    } // namespace

    bool GraphicEQDesigner::prepareRate(double sampleRate) noexcept
    {
        if (sampleRate == rate_)
        {
            return true;
        }
        rate_ = 0.0; // empty until every table below is built

        std::array<double, kBands> centres{};
        for (size_t band = 0; band < kBands; ++band)
        {
            centres[band] = GraphicEQ::centreHz(static_cast<int>(band));
            svfG_[band] = GraphicEQ::prewarp(centres[band], sampleRate);
            inverseG2_[band] = 1.0 / (svfG_[band] * svfG_[band]);
            bellK0_[band] = GraphicEQ::bellK0(centres[band], sampleRate);
        }
        for (size_t point = 0; point < kPoints; ++point)
        {
            const size_t lower = point / 2U;
            const double pointHz =
                isCentre(point) ? centres[lower] : std::sqrt(centres[lower] * centres[lower + 1U]);
            const double prewarped = GraphicEQ::prewarp(pointHz, sampleRate);
            pointPrewarp2_[point] = prewarped * prewarped;
        }

        BandVector prototype{};
        prototype.fill(kPrototypeGainDb);
        buildBasis(prototype, prototypeBasis_);
        if (!factorNormalMatrix(prototypeBasis_, prototypeFactor_))
        {
            return false;
        }
        rate_ = sampleRate;
        return true;
    }

    void GraphicEQDesigner::buildBasis(const BandVector& prototypeDb, Basis& basis) const noexcept
    {
        for (size_t band = 0; band < kBands; ++band)
        {
            const GraphicEQ::SvfBell bell = GraphicEQ::svfBell(prototypeDb[band], bellK0_[band]);
            const double perDb = 1.0 / prototypeDb[band];
            double* row = basis.data() + (band * kPoints);
            for (size_t point = 0; point < kPoints; ++point)
            {
                row[point] =
                    GraphicEQ::bellDb(bell, pointPrewarp2_[point] * inverseG2_[band]) * perDb;
            }
        }
    }

    bool GraphicEQDesigner::factorNormalMatrix(const Basis& basis, BandMatrix& factor) noexcept
    {
        // Lower triangle of N = Bᵀ·W²·B (the basis is band-major, so rows are bands).
        for (size_t i = 0; i < kBands; ++i)
        {
            const double* rowI = basis.data() + (i * kPoints);
            for (size_t j = 0; j <= i; ++j)
            {
                const double* rowJ = basis.data() + (j * kPoints);
                double sum = 0.0;
                for (size_t point = 0; point < kPoints; ++point)
                {
                    sum += weightSquared(point) * rowI[point] * rowJ[point];
                }
                factor[(i * kBands) + j] = sum;
            }
        }
        // In-place Cholesky, column by column: N = L·Lᵀ, L lower-triangular.
        for (size_t j = 0; j < kBands; ++j)
        {
            double pivot = factor[(j * kBands) + j];
            for (size_t col = 0; col < j; ++col)
            {
                pivot -= factor[(j * kBands) + col] * factor[(j * kBands) + col];
            }
            // Not positive definite (or non-finite): no usable solve.
            if (!(pivot > 0.0) || !std::isfinite(pivot))
            {
                return false;
            }
            const double diagonal = std::sqrt(pivot);
            factor[(j * kBands) + j] = diagonal;
            for (size_t i = j + 1U; i < kBands; ++i)
            {
                double value = factor[(i * kBands) + j];
                for (size_t col = 0; col < j; ++col)
                {
                    value -= factor[(i * kBands) + col] * factor[(j * kBands) + col];
                }
                factor[(i * kBands) + j] = value / diagonal;
            }
        }
        return true;
    }

    void GraphicEQDesigner::solveFactored(const Basis& basis,
                                          const BandMatrix& factor,
                                          const PointVector& target,
                                          BandVector& gainsDb) noexcept
    {
        // Right-hand side Bᵀ·W²·t, then forward (L·y = b) and back (Lᵀ·g = y) substitution.
        BandVector forward{};
        for (size_t i = 0; i < kBands; ++i)
        {
            const double* row = basis.data() + (i * kPoints);
            double value = 0.0;
            for (size_t point = 0; point < kPoints; ++point)
            {
                value += weightSquared(point) * row[point] * target[point];
            }
            for (size_t col = 0; col < i; ++col)
            {
                value -= factor[(i * kBands) + col] * forward[col];
            }
            forward[i] = value / factor[(i * kBands) + i];
        }
        for (size_t step = 0; step < kBands; ++step)
        {
            const size_t i = kBands - 1U - step;
            double value = forward[i];
            for (size_t row = i + 1U; row < kBands; ++row)
            {
                value -= factor[(row * kBands) + i] * gainsDb[row];
            }
            gainsDb[i] = value / factor[(i * kBands) + i];
        }
    }

    bool GraphicEQDesigner::design(std::span<const float, GraphicEQ::kBandCount> pointsDb,
                                   double sampleRate,
                                   GraphicEQDesign& out) noexcept
    {
        if (!std::isfinite(sampleRate) || sampleRate < kMinSampleRateHz ||
            sampleRate > kMaxSampleRateHz)
        {
            return false;
        }
        constexpr auto kLimitDb = static_cast<double>(kEQMaxGainDb);
        BandVector clamped{};
        for (size_t band = 0; band < kBands; ++band)
        {
            const auto point = static_cast<double>(pointsDb[band]);
            if (!std::isfinite(point))
            {
                return false;
            }
            clamped[band] = std::clamp(point, -kLimitDb, kLimitDb);
        }
        if (!prepareRate(sampleRate))
        {
            return false;
        }

        // The 61-point target: the centres, and the straight line between them at the midpoints.
        PointVector target{};
        for (size_t point = 0; point < kPoints; ++point)
        {
            const size_t lower = point / 2U;
            target[point] =
                isCentre(point) ? clamped[lower] : (clamped[lower] + clamped[lower + 1U]) / 2.0;
        }

        BandVector gains{};
        solveFactored(prototypeBasis_, prototypeFactor_, target, gains);
        for (int pass = 0; pass < kRefinementPasses; ++pass)
        {
            BandVector prototype{};
            std::ranges::transform(gains, prototype.begin(), guardedGainDb);
            buildBasis(prototype, basis_);
            if (!factorNormalMatrix(basis_, factor_))
            {
                return false;
            }
            solveFactored(basis_, factor_, target, gains);
        }
        if (!allFinite(gains))
        {
            return false;
        }

        GraphicEQDesign result{};
        result.sampleRate = sampleRate;
        result.filterGainDb = gains;
        result.svfG = svfG_;
        for (size_t band = 0; band < kBands; ++band)
        {
            const GraphicEQ::SvfBell bell = GraphicEQ::svfBell(gains[band], bellK0_[band]);
            if (!std::isfinite(bell.k) || !std::isfinite(bell.m1))
            {
                return false;
            }
            result.bells[band] = bell;
        }
        out = result;
        return true;
    }

    double GraphicEQDesigner::playedDb(const GraphicEQDesign& design, double frequencyHz) noexcept
    {
        // Σ_m 10·log10|H_m|² = 10·log10 Π_m |H_m|²: one logarithm per frequency. Each factor is
        // 1 + (a cancellation-free excess). A band with m1 == 0 is an exact identity (as the
        // engine treats it) and is skipped, so a flat — or default-constructed — design reads
        // back exactly 0 dB.
        const double prewarped = GraphicEQ::prewarp(frequencyHz, design.sampleRate);
        double power = 1.0;
        for (size_t band = 0; band < kBands; ++band)
        {
            if (design.bells[band].m1 == 0.0)
            {
                continue;
            }
            const double omega = prewarped / design.svfG[band];
            power *= 1.0 + GraphicEQ::bellPowerExcess(design.bells[band], omega * omega);
        }
        return GraphicEQ::kPowerDbPerNeper * std::log(power);
    }

    bool GraphicEQDesigner::playedResponseDb(const GraphicEQDesign& design,
                                             std::span<const double> frequenciesHz,
                                             std::span<float> outDb) noexcept
    {
        if (frequenciesHz.size() != outDb.size())
        {
            return false;
        }
        const double nyquist = design.sampleRate / 2.0;
        const bool inBand = std::ranges::all_of(
            frequenciesHz,
            [nyquist](double frequency)
            { return std::isfinite(frequency) && frequency >= 0.0 && frequency < nyquist; });
        if (!inBand)
        {
            return false;
        }
        std::ranges::transform(frequenciesHz,
                               outDb.begin(),
                               [&design](double frequency)
                               { return static_cast<float>(playedDb(design, frequency)); });
        return true;
    }
} // namespace AdaptiveSound
