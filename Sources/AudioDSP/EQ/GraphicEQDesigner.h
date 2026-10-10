#pragma once

// GraphicEQDesigner.h — the accurate 31-band graphic-EQ designer (Sprint EQ, EQ1a).
//
// Turns 31 target points (dB, the values the UI draws and sends) into one bilinear bell per band
// whose CASCADE plays those points: the interaction between neighbouring bells is solved, so the
// played curve meets the targets at the centres: ≤ 0.084 dB on the built-in presets, ≤ 0.45 dB
// worst over 1000 Rämö-style ±12 dB commands (engine-plan §2.2).
//
// THE SOLVE (engine-plan §2.1; Välimäki & Liski 2017, the ACGE family):
//   - 61 design points: the 31 centres interleaved with the 30 geometric midpoints. A midpoint's
//     target is the mean of its two neighbours (a straight line between points on the log axis).
//   - Weighted least squares, weight 1 at the centres and 0.5 at the midpoints:
//     g = argmin Σ_p w_p² (Σ_m B[p][m]·g_m − t_p)², solved through the normal equations and a
//     31×31 Cholesky factorisation in double (the weighted basis has a condition number of 8–9).
//   - B[p][m] is band m's dB response at point p, per dB of its own gain. The first solve uses a
//     17 dB prototype for every band; then 5 refinement passes rebuild B from the previous
//     gains, so each band's shape matches the gain it will actually play at. A previous gain with
//     |g| < 1e-3 dB is replaced by ±1e-3 dB before dividing, so a flat band can never make 0/0.
//   - The bells' coefficients come from the ONE shared function in GraphicEQBands.h.
//
// THE READ-BACK. playedDb() evaluates the finished (g, k, m1) — exactly what the engine runs — in
// the cancellation-free complex form, never the expanded cos-polynomial (the C++ port rule).
//
// OWNERSHIP AND THREADS. A designer instance holds its own per-sample-rate tables and scratch
// (~47 KB) and NO shared or static mutable state. Each owner (the Realizer's queue, the UI) holds
// its own instance, so two designers never race; one instance is not thread-safe. design() and
// the read-back allocate nothing, take no locks and throw nothing, so the Realizer can call them
// on its queue between publishes. Construct instances on the heap (they are large).

#include "GraphicEQBands.h"
#include <array>
#include <span>
#include <type_traits>

namespace AdaptiveSound
{
    // A finished design: the solved gains and the per-band SVF coefficients the engine runs.
    // Trivially copyable, so it can travel inside a TargetState.
    struct GraphicEQDesign
    {
        double sampleRate = 0.0; // the rate the coefficients were designed for
        // The solved per-band bell gains (dB). NOT the targets: neighbouring bells overlap, so a
        // jagged curve needs gains beyond ±12 dB (up to ~±33 dB on adversarial commands).
        std::array<double, GraphicEQ::kBandCount> filterGainDb{};
        std::array<double, GraphicEQ::kBandCount> svfG{}; // prewarp tan(ω_m / 2) at sampleRate
        std::array<GraphicEQ::SvfBell, GraphicEQ::kBandCount> bells{}; // (k, m1) per band
    };
    static_assert(std::is_trivially_copyable_v<GraphicEQDesign>,
                  "GraphicEQDesign must stay trivially copyable (it is published by value)");

    class GraphicEQDesigner
    {
      public:
        static constexpr int kRefinementPasses = 5;
        static constexpr double kPrototypeGainDb = 17.0; // the first solve's bell gain
        static constexpr double kGuardGainDb = 1e-3;     // the |prototype gain| floor (no 0/0)
        static constexpr double kMidpointWeight = 0.5;   // WLS weight of a midpoint (centres: 1)
        // The design domain. Below ~44 kHz the top centre (19.95 kHz) is not safely below
        // Nyquist; 768 kHz bounds the tables' precision far beyond any device rate.
        static constexpr double kMinSampleRateHz = 44000.0;
        static constexpr double kMaxSampleRateHz = 768000.0;

        GraphicEQDesigner() noexcept = default;

        // Design the cascade that plays `pointsDb` at `sampleRate`. Points are clamped to
        // ±kEQMaxGainDb. Returns false, leaving `out` untouched, when any point is non-finite,
        // when the rate is non-finite or outside [kMinSampleRateHz, kMaxSampleRateHz], or when the
        // solve fails to produce finite coefficients — the caller then keeps its last good design.
        [[nodiscard]] bool design(std::span<const float, GraphicEQ::kBandCount> pointsDb,
                                  double sampleRate,
                                  GraphicEQDesign& out) noexcept;

        // The played response (dB) of a finished design at `frequencyHz` (0 ≤ f < sampleRate / 2):
        // the sum of the bells' dB, evaluated in the complex form. A band with m1 == 0 is an exact
        // identity, so a flat (or default-constructed) design returns exactly 0 dB.
        [[nodiscard]] static double playedDb(const GraphicEQDesign& design,
                                             double frequencyHz) noexcept;

        // playedDb at every frequency in `frequenciesHz` into `outDb` (same length; float, as the
        // UI draws it). Returns false, writing nothing, on a length mismatch or any frequency
        // that is non-finite or outside [0, sampleRate / 2).
        [[nodiscard]] static bool playedResponseDb(const GraphicEQDesign& design,
                                                   std::span<const double> frequenciesHz,
                                                   std::span<float> outDb) noexcept;

      private:
        static constexpr int kPointCount = (2 * GraphicEQ::kBandCount) - 1; // centres + midpoints
        using BandVector = std::array<double, GraphicEQ::kBandCount>;
        using PointVector = std::array<double, kPointCount>;
        // Band-major dB basis: basis[m * kPointCount + p] = band m's dB per dB of gain at point p.
        using Basis = std::array<double, static_cast<size_t>(GraphicEQ::kBandCount) * kPointCount>;
        // Row-major 31×31; holds the normal matrix's lower triangle, then its Cholesky factor.
        using BandMatrix =
            std::array<double, static_cast<size_t>(GraphicEQ::kBandCount) * GraphicEQ::kBandCount>;

        // Build the per-rate tables (prewarps, dampings, the 17 dB first-pass basis and factor)
        // unless `sampleRate` is the cached one. Leaves the cache empty on failure.
        [[nodiscard]] bool prepareRate(double sampleRate) noexcept;

        // basis[m][p] = bellDb(gain_m at point p) / gain_m, for the per-band prototype gains.
        void buildBasis(const BandVector& prototypeDb, Basis& basis) const noexcept;

        // Form Bᵀ·W²·B from `basis` into `factor` and factor it in place (L·Lᵀ). False when the
        // matrix is not numerically positive definite.
        [[nodiscard]] static bool factorNormalMatrix(const Basis& basis,
                                                     BandMatrix& factor) noexcept;

        // Solve (L·Lᵀ)·g = Bᵀ·W²·t.
        static void solveFactored(const Basis& basis,
                                  const BandMatrix& factor,
                                  const PointVector& target,
                                  BandVector& gainsDb) noexcept;

        // Per-rate tables (owner-local cache).
        double rate_ = 0.0;            // the cached rate; 0 = empty
        BandVector svfG_{};            // tan(ω_m / 2)
        BandVector inverseG2_{};       // 1 / g_m², so Ω² = tan²(πf/fs) / g_m²
        BandVector bellK0_{};          // unity-gain damping per band
        PointVector pointPrewarp2_{};  // tan²(π f_p / fs) at the 61 design points
        Basis prototypeBasis_{};       // the 17 dB first-pass basis
        BandMatrix prototypeFactor_{}; // its normal matrix's Cholesky factor

        // Refinement-pass scratch (no allocation in design()).
        Basis basis_{};
        BandMatrix factor_{};
    };
} // namespace AdaptiveSound
