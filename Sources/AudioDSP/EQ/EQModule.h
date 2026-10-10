#pragma once

// EQModule — the graphic EQ's real-time stage (Sprint EQ, EQ1b; engine-plan §3, §6, §7).
//
// 31 bilinear bells (GraphicEQBands.h) per channel, run as Simper's trapezoidal state-variable
// filter in DOUBLE precision, two channels per NEON register (simd_double2 lanes = a channel pair).
// The module never designs: it runs the FINISHED per-band (k, m1) the Realizer's GraphicEQDesigner
// produced, and glides to a new set on one one-pole per sample ("S2"):
//
//   k ← k + α(k* − k),  m1 ← m1 + α(m1* − m1),  a1 = 1 / (1 + g(g + k)),  a2 = g·a1,  a3 = g·a2
//
// so every intermediate state is itself a stable bell (k stays a convex combination of positive
// values) and the transition never swells beyond the louder endpoint the way a dB-domain ramp of
// the solved gains does (engine-plan §3.1). The broadband output gain (EQ1c's loudness-neutral
// gain; 0 dB until then) rides the same one-pole in dB. α comes from EQParams::rampSeconds, the
// Realizer's τ rule (amendment 1: 10 / 40 / 160 ms).
//
// Settled: once every parameter is within a relative 1e-9 of its target it snaps and the per-
// sample smoothing stops. At the identity (every m1 == 0, 0 dB, settled) the cascade is skipped
// and its states are zeroed, so the module is a bit-exact pass-through — the kernel's bit-perfect
// path keys on isIdentity().
//
// Guards (engine-plan §7): a snapshot with a non-finite or non-positive coefficient is ignored (the
// last good target keeps playing); one designed for another sample rate is held off (identity if
// nothing else was ever adopted); states are checked every block and zeroed if non-finite, so a
// NaN input recovers within one block. The first target adopted after initialize() is applied
// without a ramp (no fade-in after a re-allocation, engine-plan §6).
//
// RT-safety: process() allocates nothing, takes no locks and calls no OS services. Every buffer is
// sized in initialize() (off-RT) to the host's maximum frame count.

#include "../include/AudioConstants.h"
#include "../include/MultichannelView.h"
#include "../include/TargetState.h"
#include <array>
#include <cstdint>
#include <simd/simd.h>
#include <vector>

namespace AdaptiveSound
{
    class EQModule
    {
      public:
        // Channel pairs processed per sample (one simd_double2 lane per channel).
        static constexpr uint32_t kChannelPairs = (kMaxChannels + 1U) / 2U;

        EQModule() = default;

        // Off-RT: per-rate tables, scratch sized to maxFrames, states zeroed, the identity as the
        // current target, and "snap the next adopted target" armed.
        void initialize(uint32_t sampleRate, uint32_t maxFrames) noexcept;

        // RT, once per render block on EVERY kernel path (even the bit-perfect bypass, so an EQ
        // turned on is seen there): adopt `params` if they changed since the last block. A target
        // adopted in the first block after initialize() snaps; any later one glides.
        void update(const EQParams& params) noexcept;

        // RT: run the cascade in place (a no-op at the identity).
        void process(const MultichannelView& block) noexcept;

        // RT (or between process() calls): settled at the identity — the cascade is skipped and the
        // module is a bit-exact pass-through.
        [[nodiscard]] bool isIdentity() const noexcept;

        // Between process() calls (tests/diagnostics): the coefficients the module runs right now.
        [[nodiscard]] const std::array<double, kEqBandCount>& currentK() const noexcept
        {
            return kCurrent_;
        }
        [[nodiscard]] const std::array<double, kEqBandCount>& currentM1() const noexcept
        {
            return m1Current_;
        }
        [[nodiscard]] double currentOutputGainDb() const noexcept
        {
            return gainDbCurrent_;
        }

        // Test hooks for the denormal gate (EQ_NoSubnormalStates): seed every filter state, and
        // ask whether any state is subnormal right now. Never used by production code.
        void seedStatesForTesting(double value) noexcept;
        [[nodiscard]] bool hasSubnormalState() const noexcept;

      private:
        using BandArray = std::array<double, kEqBandCount>;
        using PairStates = std::array<std::array<simd_double2, kEqBandCount>, kChannelPairs>;

        // RT: take `params` as the new target (or hold / ignore it; see the file header).
        void adopt(const EQParams& params) noexcept;
        void snapToTargets() noexcept;
        void zeroStates() noexcept;
        [[nodiscard]] double onePoleAlpha(float rampSeconds) const noexcept;

        // RT: run band `band` over the work buffer for `pairs` channel pairs, advancing its glide
        // when `ramping`. Dispatches to runBandPairs for the compile-time pair count.
        void runBand(size_t band, uint32_t frames, uint32_t pairs, bool ramping) noexcept;
        // RT: runBand for exactly `Pairs` channel pairs. The pair count and the glide are template
        // parameters so the states live in registers across the whole block (no store→load round
        // trip in the recurrence) and the per-sample coefficient glide is fused into the filter loop,
        // where its short dependency chain hides behind the filter's longer one.
        template <uint32_t Pairs, bool Ramping>
        void runBandPairs(size_t band, uint32_t frames) noexcept;
        // RT: apply the output gain (constant or ramping) to the work buffer.
        void applyOutputGain(uint32_t frames, uint32_t pairs) noexcept;
        // RT: snap the parameters that reached their targets; zero the states at the identity.
        void settleIfConverged() noexcept;
        // RT: the block into / out of the double work buffer; and the state finiteness check.
        void loadWork(const MultichannelView& block, uint32_t frames, uint32_t pairs) noexcept;
        void
        storeWork(const MultichannelView& block, uint32_t frames, uint32_t pairs) const noexcept;
        [[nodiscard]] bool statesFinite() const noexcept;

        uint32_t sampleRate_ = kDefaultSampleRate;
        uint32_t maxFrames_ = kDefaultMaxFrames;

        // Per-rate tables (initialize()).
        BandArray prewarp_{}; // g = tan(ω_m / 2)
        BandArray unityK_{};  // k0: the damping of a 0 dB bell (the identity's k)

        // Current and target coefficients, and the output gain (dB).
        BandArray kCurrent_{};
        BandArray m1Current_{};
        BandArray kTarget_{};
        BandArray m1Target_{};
        double gainDbCurrent_ = 0.0;
        double gainDbTarget_ = 0.0;
        double coefficientAlpha_ = 1.0; // one-pole α of the (k, m1) glide
        double gainAlpha_ = 1.0;        // one-pole α of the output-gain glide
        bool coefficientsRamping_ = false;
        bool gainRamping_ = false;
        bool snapNextAdopt_ = true;
        bool statesClear_ = true;

        // The last snapshot evaluated (adopt() runs only when it changes).
        EQParams seen_{};

        // Filter memory: per channel pair, per band, the two trapezoidal integrator states.
        PairStates ic1_{};
        PairStates ic2_{};

        // Scratch (initialize()): the block in double, sample-major / pair-minor; the output-gain
        // trajectory.
        std::vector<simd_double2> work_;
        std::vector<double> gainLinear_;
    };
} // namespace AdaptiveSound
