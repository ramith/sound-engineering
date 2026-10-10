// EQModule.cpp — the graphic EQ's real-time stage. See EQModule.h.

#include "EQModule.h"
#include "GraphicEQBands.h"
#include <algorithm>
#include <cassert>
#include <cmath>
#include <numbers>

namespace AdaptiveSound
{
    namespace
    {
        constexpr auto kBands = static_cast<size_t>(kEqBandCount);

        // A parameter within this RELATIVE distance of its target snaps to it and stops ramping.
        // Not 1e-12 (engine-plan §7): a double one-pole stalls one ulp/α short of its target, which
        // is ~1.3e-11 relative at τ 300 ms / 192 kHz, so a 1e-12 test would never settle. 1e-9
        // changes the response by ~1e-8 dB — inaudible — and settles at every supported τ and rate.
        constexpr double kSettleRelative = 1e-9;

        // The one-pole τ is held inside this range whatever the snapshot asks for.
        constexpr float kMinRampSeconds = 0.001F;
        constexpr float kMaxRampSeconds = 2.0F;

        constexpr double kGainDbToNeper = std::numbers::ln10 / 20.0;

        [[nodiscard]] bool closeTo(double value, double target, double scale) noexcept
        {
            return std::abs(value - target) <= kSettleRelative * scale;
        }
    } // namespace

    void EQModule::initialize(uint32_t sampleRate, uint32_t maxFrames) noexcept
    {
        sampleRate_ = sampleRate;
        maxFrames_ = maxFrames;
        const auto fs = static_cast<double>(sampleRate);
        for (size_t band = 0; band < kBands; ++band)
        {
            const double centre = GraphicEQ::centreHz(static_cast<int>(band));
            // A centre at or above Nyquist (rates under ~40 kHz) cannot host its bell: its prewarp
            // is meaningless. Such rates never adopt a design (the Realizer designs only within
            // 44–768 kHz), so the module stays at the identity; the tables just stay finite.
            const bool hostable = centre < (fs / 2.0);
            prewarp_[band] = hostable ? GraphicEQ::prewarp(centre, fs) : 1.0;
            unityK_[band] = hostable ? GraphicEQ::bellK0(centre, fs) : 1.0;
        }

        kTarget_ = unityK_;
        m1Target_.fill(0.0);
        gainDbTarget_ = 0.0;
        snapToTargets();
        bandAlpha_.fill(1.0);
        gainAlpha_ = 1.0;
        snapNextAdopt_ = true;
        seen_ = EQParams{};
        zeroStates();

        const size_t frames = maxFrames_;
        work_.assign(frames * kChannelPairs, simd_double2{0.0, 0.0});
        gainLinear_.assign(frames, 1.0);
    }

    double EQModule::onePoleAlpha(float rampSeconds) const noexcept
    {
        const float tau = std::isfinite(rampSeconds)
                              ? std::clamp(rampSeconds, kMinRampSeconds, kMaxRampSeconds)
                              : kEqDefaultRampSeconds;
        return 1.0 - std::exp(-1.0 / (static_cast<double>(tau) * static_cast<double>(sampleRate_)));
    }

    void EQModule::adopt(const EQParams& params) noexcept
    {
        const bool designed = params.designSampleRate != 0.0F;
        if (designed && params.designSampleRate != static_cast<float>(sampleRate_))
        {
            return; // designed for another rate: hold the last good target (engine-plan §6)
        }
        if (!std::isfinite(params.outputGainDb))
        {
            return;
        }
        if (designed)
        {
            for (size_t band = 0; band < kBands; ++band)
            {
                if (!std::isfinite(params.k[band]) || !(params.k[band] > 0.0) ||
                    !std::isfinite(params.m1[band]))
                {
                    return; // a bad snapshot is ignored; the last good target keeps playing
                }
            }
        }

        // An undesigned snapshot (the default EQParams) is the identity at this rate.
        const BandArray& damping = designed ? params.k : unityK_;
        BandArray mix{};
        if (designed)
        {
            mix = params.m1;
        }
        for (size_t band = 0; band < kBands; ++band)
        {
            // A band whose target moved glides there at ITS OWN τ (amendment 15). The others keep
            // going where they were going, at the pace they already had.
            if (damping[band] != kTarget_[band] || mix[band] != m1Target_[band])
            {
                kTarget_[band] = damping[band];
                m1Target_[band] = mix[band];
                bandAlpha_[band] = onePoleAlpha(params.bandRampSeconds[band]);
                bandRamping_[band] = true;
            }
        }
        if (params.outputGainDb != gainDbTarget_)
        {
            gainDbTarget_ = params.outputGainDb;
            gainAlpha_ = onePoleAlpha(params.gainRampSeconds);
            gainRamping_ = true;
        }
        if (snapNextAdopt_)
        {
            snapNextAdopt_ = false;
            snapToTargets();
            zeroStates();
        }
    }

    void EQModule::snapToTargets() noexcept
    {
        kCurrent_ = kTarget_;
        m1Current_ = m1Target_;
        gainDbCurrent_ = gainDbTarget_;
        bandRamping_.fill(false);
        gainRamping_ = false;
    }

    bool EQModule::anyBandRamping() const noexcept
    {
        return std::ranges::any_of(bandRamping_, [](bool ramping) { return ramping; });
    }

    void EQModule::zeroStates() noexcept
    {
        for (auto& pair : ic1_)
        {
            pair.fill(simd_double2{0.0, 0.0});
        }
        for (auto& pair : ic2_)
        {
            pair.fill(simd_double2{0.0, 0.0});
        }
        statesClear_ = true;
    }

    bool EQModule::isIdentity() const noexcept
    {
        if (gainRamping_ || gainDbCurrent_ != 0.0 || anyBandRamping())
        {
            return false;
        }
        return std::ranges::all_of(m1Current_, [](double mix) { return mix == 0.0; });
    }

    template <uint32_t Pairs, bool Ramping>
    void EQModule::runBandPairs(size_t band, uint32_t frames) noexcept
    {
        // Simper's trapezoidal SVF bell, per sample:
        //   v3 = v0 − ic2;  v1 = a1·ic1 + a2·v3;  v2 = ic2 + a2·ic1 + a3·v3
        //   ic1 = 2·v1 − ic1;  ic2 = 2·v2 − ic2;  out = v0 + m1·v1
        // The pairs are independent recurrences, interleaved per sample so the FMA latency of one
        // hides behind the others. The states are copied into locals for the block: with the pair
        // count a constant the loops unroll and they stay in registers.
        std::array<simd_double2, Pairs> ic1{};
        std::array<simd_double2, Pairs> ic2{};
        for (uint32_t pair = 0U; pair < Pairs; ++pair)
        {
            ic1[pair] = ic1_[pair][band];
            ic2[pair] = ic2_[pair][band];
        }
        const double prewarp = prewarp_[band];
        const double alpha = bandAlpha_[band];
        const double kGoal = kTarget_[band];
        const double mixGoal = m1Target_[band];
        double damping = kCurrent_[band];
        double mix = m1Current_[band];
        GraphicEQ::SvfDamping coefficients = GraphicEQ::svfDamping(prewarp, damping);
        simd_double2* frame = work_.data();
        for (uint32_t i = 0U; i < frames; ++i, frame += kChannelPairs)
        {
            if constexpr (Ramping)
            {
                // The S2 glide: one one-pole step per sample on (k, m1), then the finished a's.
                damping += alpha * (kGoal - damping);
                mix += alpha * (mixGoal - mix);
                coefficients = GraphicEQ::svfDamping(prewarp, damping);
            }
            for (uint32_t pair = 0U; pair < Pairs; ++pair)
            {
                const simd_double2 v0 = frame[pair];
                const simd_double2 v3 = v0 - ic2[pair];
                const simd_double2 v1 = (coefficients.a1 * ic1[pair]) + (coefficients.a2 * v3);
                const simd_double2 v2 =
                    ic2[pair] + (coefficients.a2 * ic1[pair]) + (coefficients.a3 * v3);
                ic1[pair] = (2.0 * v1) - ic1[pair];
                ic2[pair] = (2.0 * v2) - ic2[pair];
                frame[pair] = v0 + (mix * v1);
            }
        }
        for (uint32_t pair = 0U; pair < Pairs; ++pair)
        {
            ic1_[pair][band] = ic1[pair];
            ic2_[pair][band] = ic2[pair];
        }
        if constexpr (Ramping)
        {
            kCurrent_[band] = damping;
            m1Current_[band] = mix;
        }
    }

    void EQModule::runBand(size_t band, uint32_t frames, uint32_t pairs, bool ramping) noexcept
    {
        static_assert(kChannelPairs == 4U, "runBand dispatches one runBandPairs per pair count");
        switch (pairs)
        {
            case 1U:
                ramping ? runBandPairs<1U, true>(band, frames)
                        : runBandPairs<1U, false>(band, frames);
                break;
            case 2U:
                ramping ? runBandPairs<2U, true>(band, frames)
                        : runBandPairs<2U, false>(band, frames);
                break;
            case 3U:
                ramping ? runBandPairs<3U, true>(band, frames)
                        : runBandPairs<3U, false>(band, frames);
                break;
            default:
                ramping ? runBandPairs<4U, true>(band, frames)
                        : runBandPairs<4U, false>(band, frames);
                break;
        }
    }

    void EQModule::applyOutputGain(uint32_t frames, uint32_t pairs) noexcept
    {
        if (!gainRamping_ && gainDbCurrent_ == 0.0)
        {
            return;
        }
        if (gainRamping_)
        {
            double gainDb = gainDbCurrent_;
            for (uint32_t i = 0U; i < frames; ++i)
            {
                gainDb += gainAlpha_ * (gainDbTarget_ - gainDb);
                gainLinear_[i] = std::exp(gainDb * kGainDbToNeper);
            }
            gainDbCurrent_ = gainDb;
        }
        else
        {
            std::fill_n(gainLinear_.begin(), frames, std::exp(gainDbCurrent_ * kGainDbToNeper));
        }
        for (uint32_t i = 0U; i < frames; ++i)
        {
            simd_double2* frame = work_.data() + (static_cast<size_t>(i) * kChannelPairs);
            for (uint32_t pair = 0U; pair < pairs; ++pair)
            {
                frame[pair] = frame[pair] * gainLinear_[i];
            }
        }
    }

    void EQModule::settleIfConverged() noexcept
    {
        for (size_t band = 0; band < kBands; ++band)
        {
            const double scale = kTarget_[band] + std::abs(m1Target_[band]);
            if (bandRamping_[band] && closeTo(kCurrent_[band], kTarget_[band], scale) &&
                closeTo(m1Current_[band], m1Target_[band], scale))
            {
                kCurrent_[band] = kTarget_[band];
                m1Current_[band] = m1Target_[band];
                bandRamping_[band] = false;
            }
        }
        if (gainRamping_ && closeTo(gainDbCurrent_, gainDbTarget_, 1.0 + std::abs(gainDbTarget_)))
        {
            gainDbCurrent_ = gainDbTarget_;
            gainRamping_ = false;
        }
        if (isIdentity())
        {
            zeroStates(); // m1 == 0 everywhere: the states no longer reach the output
        }
    }

    void EQModule::update(const EQParams& params) noexcept
    {
        if (params != seen_)
        {
            seen_ = params;
            adopt(params);
        }
        // Audio is flowing from here on: a later target must glide, never snap.
        snapNextAdopt_ = false;
    }

    void EQModule::loadWork(const MultichannelView& block, uint32_t frames, uint32_t pairs) noexcept
    {
        // float → double, two channels per lane pair (a missing odd channel runs on zeros).
        for (uint32_t pair = 0U; pair < pairs; ++pair)
        {
            const float* left = block.channel(2U * pair);
            const float* right = block.channel((2U * pair) + 1U);
            for (uint32_t i = 0U; i < frames; ++i)
            {
                work_[(static_cast<size_t>(i) * kChannelPairs) + pair] = simd_double2{
                    (left != nullptr) ? static_cast<double>(left[i]) : 0.0,
                    (right != nullptr) ? static_cast<double>(right[i]) : 0.0,
                };
            }
        }
    }

    void EQModule::storeWork(const MultichannelView& block,
                             uint32_t frames,
                             uint32_t pairs) const noexcept
    {
        for (uint32_t pair = 0U; pair < pairs; ++pair)
        {
            float* left = block.channel(2U * pair);
            float* right = block.channel((2U * pair) + 1U);
            for (uint32_t i = 0U; i < frames; ++i)
            {
                const simd_double2 out = work_[(static_cast<size_t>(i) * kChannelPairs) + pair];
                if (left != nullptr)
                {
                    left[i] = static_cast<float>(out.x);
                }
                if (right != nullptr)
                {
                    right[i] = static_cast<float>(out.y);
                }
            }
        }
    }

    bool EQModule::statesFinite() const noexcept
    {
        const auto finite = [](const PairStates& states)
        {
            return std::ranges::all_of(
                states,
                [](const auto& pair)
                {
                    return std::ranges::all_of(
                        pair,
                        [](simd_double2 state)
                        { return std::isfinite(state.x) && std::isfinite(state.y); });
                });
        };
        return finite(ic1_) && finite(ic2_);
    }

    void EQModule::process(const MultichannelView& block) noexcept
    {
        if (isIdentity())
        {
            if (!statesClear_)
            {
                zeroStates();
            }
            return;
        }
        const uint32_t frameCount = block.frames();
        const uint32_t channels = block.channels();
        if (frameCount == 0U || channels == 0U)
        {
            return;
        }
        assert(frameCount <= maxFrames_);
        const uint32_t frames = std::min(frameCount, maxFrames_);
        const uint32_t pairs = (channels + 1U) / 2U;

        loadWork(block, frames, pairs);
        for (size_t band = 0; band < kBands; ++band)
        {
            runBand(band, frames, pairs, bandRamping_[band]);
        }
        statesClear_ = false;
        applyOutputGain(frames, pairs);
        storeWork(block, frames, pairs);

        // A non-finite input (or state) poisons the recursion: start the next block clean.
        if (!statesFinite())
        {
            zeroStates();
        }
        settleIfConverged();
    }

    void EQModule::seedStatesForTesting(double value) noexcept
    {
        for (auto& pair : ic1_)
        {
            pair.fill(simd_double2{value, value});
        }
        for (auto& pair : ic2_)
        {
            pair.fill(simd_double2{value, value});
        }
        statesClear_ = false;
    }

    bool EQModule::hasSubnormalState() const noexcept
    {
        const auto subnormal = [](const auto& pair)
        {
            return std::ranges::any_of(pair,
                                       [](simd_double2 state)
                                       {
                                           return std::fpclassify(state.x) == FP_SUBNORMAL ||
                                                  std::fpclassify(state.y) == FP_SUBNORMAL;
                                       });
        };
        return std::ranges::any_of(ic1_, subnormal) || std::ranges::any_of(ic2_, subnormal);
    }
} // namespace AdaptiveSound
