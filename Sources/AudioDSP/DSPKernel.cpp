#include "include/DSPKernel.h"
#include "Clarity/ClarityModule.h"
#include "EQ/EQModule.h"
#include "include/FlushToZero.h"
#include "include/MultichannelView.h"
#include "Limiting/LimiterModule.h"
#include "Loudness/LoudnessModule.h"
#include "Spatial/BRIRModule.h"
#include "Spatial/CrossfeedModule.h"
#include <Accelerate/Accelerate.h>
#include <algorithm>
#include <cassert>
#include <cmath>
#include <cstring>
#include <span>

namespace AdaptiveSound
{

    // Intensity ramp time constant. Mirrors the EQ master-gain / loudness makeup smoothers
    // (32 ms one-pole) so a knob sweep is click-free; settles to ~98% in 5τ ≈ 160 ms.
    static constexpr float kIntensityRampTauSeconds = 0.032F;

    // "Settled" epsilon for the intensity ramp: once |current-target| < this AND the target is
    // an endpoint (0 or 1), process() routes to the bit-exact HARD branch instead of the
    // crossfade. Sized 1e-4 (≈0.0009 dB) — large enough to escape the float32 one-pole
    // stagnation floor, small enough to be inaudible. The ramp is SNAPPED to the endpoint when
    // the hard branch is taken.
    static constexpr float kIntensitySettledEpsilon = 1e-4F;

    // Half-pi for the equal-power crossfade gains: wetGain = sin(r·π/2), dryGain = cos(r·π/2).
    static constexpr float kHalfPi = 1.57079632679489661923F;

    // The normaliser's contribution reaches 100 % at this Intensity (amendment 2:
    // makeup·min(1, r/0.1)), and fades linearly to 0 dB below it.
    static constexpr float kLoudnessFadeIntensity = 0.1F;

    // The bit-perfect path: the cross-fade length between the undelayed input and the limiter's
    // delayed output, and the hysteresis before entering it (engine-plan §5.1).
    static constexpr float kBypassCrossfadeSeconds = 0.005F;
    static constexpr double kBypassHoldSeconds = 2.0;

    DSPKernel::DSPKernel() = default;

    DSPKernel::~DSPKernel() = default;

    void DSPKernel::initialize(uint32_t sampleRate, uint32_t maxFrames) noexcept
    {
        sampleRate_ = sampleRate;
        maxFrames_ = maxFrames;

        // Enable flush-to-zero on the init/control thread (process() sets it on the render thread).
        enableFlushToZero();

        eqModule_ = std::make_unique<EQModule>();
        clarityModule_ = std::make_unique<ClarityModule>();
        brirModule_ = std::make_unique<BRIRModule>();
        crossfeedModule_ = std::make_unique<CrossfeedModule>();
        loudnessModule_ = std::make_unique<LoudnessModule>();
        limiterModule_ = std::make_unique<LimiterModule>();

        eqModule_->initialize(sampleRate, maxFrames);
        clarityModule_->initialize(sampleRate, maxFrames);
        brirModule_->initialize(sampleRate, maxFrames);
        crossfeedModule_->initialize(sampleRate, maxFrames);
        loudnessModule_->initialize(sampleRate, maxFrames);
        limiterModule_->initialize(sampleRate, maxFrames);

        // Pre-allocate every scratch off-RT, sized to the host's maximumFramesToRender.
        const auto planar = static_cast<size_t>(maxFrames_) * kMaxChannels;
        dryScratch_.assign(planar, 0.0F);
        bypassScratch_.assign(planar, 0.0F);
        wetGainBuf_.assign(maxFrames_, 0.0F);
        dryGainBuf_.assign(maxFrames_, 0.0F);
        loudnessWeightBuf_.assign(maxFrames_, 0.0F);

        // Snap the intensity ramp to whatever has been published so far (no launch fade-in).
        intensityRamp_.initialize(kIntensityRampTauSeconds, static_cast<float>(sampleRate));
        (void)targetStateSnapshot_.tryCopySnapshot(currentState_);
        intensityRamp_.target = currentState_.intensityLinear;
        intensityRamp_.snap();

        const auto fs = static_cast<double>(sampleRate);
        bypassMixStep_ = 1.0F / std::max(1.0F, kBypassCrossfadeSeconds * static_cast<float>(fs));
        bypassHoldFrames_ = static_cast<uint64_t>(std::llround(kBypassHoldSeconds * fs));
        identityHeldFrames_ = 0U;
        bypassMix_ = 0.0F;
        firstBlock_ = true;
    }

    void DSPKernel::publishTargetState(const TargetState& newState) noexcept
    {
        // Off-RT control path, single producer (the Realizer). The EQ needs no off-RT setup: the
        // RT module adopts the finished coefficients straight from the snapshot.
        targetStateSnapshot_.publish(newState);
    }

    void DSPKernel::publishChannelLayout(const ChannelLayout& layout) noexcept
    {
        // Off-RT (control thread): forwarded lock-free to the loudness measurement worker.
        if (loudnessModule_ != nullptr)
        {
            loudnessModule_->publishChannelLayout(layout);
        }
    }

    void DSPKernel::process(AudioBufferList* ioData, uint32_t inNumberFrames) noexcept
    {
        // FPCR.FZ on whichever thread renders (the AU sets it too; this makes it structural for
        // every host of the kernel, so subnormal filter tails can never cost CPU).
        enableFlushToZero();

        // Copy the snapshot ONCE into RT-owned storage (S6 RACE-1); wait-free, always succeeds.
        (void)targetStateSnapshot_.tryCopySnapshot(scratchState_);
        currentState_ = scratchState_;
        const TargetState& state = currentState_;

        // The EQ adopts its target on every path (even the bit-perfect one), so an EQ turned on
        // during the bypass is seen here.
        eqModule_->update(state.eq);

        intensityRamp_.target = state.intensityLinear;
        const bool settled =
            std::abs(intensityRamp_.current - intensityRamp_.target) < kIntensitySettledEpsilon;
        const bool atZero = settled && intensityRamp_.target == 0.0F;
        const bool atOne = settled && intensityRamp_.target == 1.0F;
        if (atZero || atOne)
        {
            intensityRamp_.current = intensityRamp_.target; // keep the endpoint bit-exact
        }

        // P0 eligibility, with the 2 s hysteresis. The first block after initialize() has no
        // previous output to stay continuous with, so it snaps to its path.
        const MultichannelView block = MultichannelView::fromABL(ioData, inNumberFrames);
        const bool identity = atZero && eqModule_->isIdentity();
        identityHeldFrames_ = identity ? (identityHeldFrames_ + block.frames()) : 0U;
        if (firstBlock_ && identity)
        {
            identityHeldFrames_ = bypassHoldFrames_;
        }
        const bool wantBypass = identity && identityHeldFrames_ >= bypassHoldFrames_;
        if (firstBlock_)
        {
            bypassMix_ = wantBypass ? 1.0F : 0.0F;
            firstBlock_ = false;
        }

        // P0: bit-perfect. The AU pulls input straight into the output buffers (in-place), so the
        // block already holds the input; keep the limiter's ring current and return untouched.
        if (wantBypass && bypassMix_ >= 1.0F)
        {
            limiterModule_->prime(block);
            return;
        }

        assert(block.frames() <= maxFrames_);
        const bool crossfading = wantBypass || bypassMix_ > 0.0F;
        if (crossfading)
        {
            copyBlock(block, bypassScratch_); // the undelayed input
        }
        runProcessedPath(state, block, atZero, atOne);
        if (crossfading)
        {
            crossfadeWithBypass(block, wantBypass ? 1.0F : 0.0F);
        }
    }

    void DSPKernel::runProcessedPath(const TargetState& state,
                                     const MultichannelView& block,
                                     bool intensityAtZero,
                                     bool intensityAtOne) noexcept
    {
        eqModule_->process(block);
        if (intensityAtZero)
        {
            // P1: EQ → Limiter. No coloration, no normaliser.
            limiterModule_->process(state.limiter, block);
            return;
        }
        if (intensityAtOne)
        {
            // P2: the full chain in place.
            runColorationChain(state, block);
            loudnessModule_->process(state.loudness, block);
            limiterModule_->process(state.limiter, block);
            return;
        }
        runBlendPath(state, block);
    }

    void DSPKernel::runBlendPath(const TargetState& state, const MultichannelView& block) noexcept
    {
        const uint32_t numChannels = block.channels();
        const uint32_t safeCount = std::min(block.frames(), maxFrames_);

        // (a) The dry tap is the EQ'd signal (decision 25): the blend never undoes the EQ.
        copyBlock(block, dryScratch_);

        // (b) Coloration in place → the block now holds the wet signal.
        runColorationChain(state, block);

        // (c) Equal-power blend, the intensity ramp advanced per sample. Equal-POWER is the law for
        //     the decorrelating wet chain; on correlated (lightly processed) material it adds up to
        //     +3 dB at r = 0.5, which the normaliser downstream absorbs.
        for (uint32_t i = 0U; i < safeCount; ++i)
        {
            const float ramped = intensityRamp_.tick();
            wetGainBuf_[i] = std::sin(ramped * kHalfPi);
            dryGainBuf_[i] = std::cos(ramped * kHalfPi);
            loudnessWeightBuf_[i] = std::min(1.0F, ramped / kLoudnessFadeIntensity);
        }
        const auto len = static_cast<vDSP_Length>(safeCount);
        for (uint32_t ch = 0U; ch < numChannels; ++ch)
        {
            float* wet = block.channel(ch);
            if (wet != nullptr)
            {
                const float* dry = dryScratch_.data() + (static_cast<size_t>(ch) * maxFrames_);
                vDSP_vmul(wet, 1, wetGainBuf_.data(), 1, wet, 1, len);        // wet *= wetGain
                vDSP_vma(dry, 1, dryGainBuf_.data(), 1, wet, 1, wet, 1, len); // wet += dryGain·dry
            }
        }

        // (d) Loudness on the blend, its contribution faded toward 0 dB as r → 0 so this path meets
        //     the normaliser-free EQ-only path with no level step (amendment 2); then the limiter.
        loudnessModule_->process(
            state.loudness, block, std::span<const float>(loudnessWeightBuf_.data(), safeCount));
        limiterModule_->process(state.limiter, block);
    }

    void DSPKernel::copyBlock(const MultichannelView& block,
                              std::vector<float>& scratch) const noexcept
    {
        const uint32_t safeCount = std::min(block.frames(), maxFrames_);
        for (uint32_t ch = 0U; ch < block.channels(); ++ch)
        {
            const float* src = block.channel(ch);
            if (src != nullptr)
            {
                float* dst = scratch.data() + (static_cast<size_t>(ch) * maxFrames_);
                std::copy_n(src, safeCount, dst);
            }
        }
    }

    void DSPKernel::crossfadeWithBypass(const MultichannelView& block, float toward) noexcept
    {
        // Equal-gain cross-fade, out = (1 − w)·processed + w·input, w gliding linearly toward
        // `toward` over 5 ms. The two streams are the same audio 3 ms apart (the limiter's
        // look-ahead), so a fade beats the skip or repeat a hard switch would make.
        const uint32_t safeCount = std::min(block.frames(), maxFrames_);
        const float step = (toward > bypassMix_) ? bypassMixStep_ : -bypassMixStep_;
        for (uint32_t i = 0U; i < safeCount; ++i)
        {
            bypassMix_ = (step > 0.0F) ? std::min(toward, bypassMix_ + step)
                                       : std::max(toward, bypassMix_ + step);
            wetGainBuf_[i] = bypassMix_;
        }
        for (uint32_t ch = 0U; ch < block.channels(); ++ch)
        {
            float* out = block.channel(ch);
            if (out == nullptr)
            {
                continue;
            }
            const float* input = bypassScratch_.data() + (static_cast<size_t>(ch) * maxFrames_);
            for (uint32_t i = 0U; i < safeCount; ++i)
            {
                const float mix = wetGainBuf_[i];
                out[i] = ((1.0F - mix) * out[i]) + (mix * input[i]);
            }
        }
    }

    // Wet-region coloration chain, in place: Clarity → BRIR → Crossfeed (default-off crossfeed is a
    // bit-exact pass-through). The EQ runs ahead of it, before the dry tap.
    void DSPKernel::runColorationChain(const TargetState& state,
                                       const MultichannelView& block) noexcept
    {
        clarityModule_->process(state.clarity, block);
        brirModule_->process(state.brir, block);
        crossfeedModule_->process(state.crossfeed, block);
    }

} // namespace AdaptiveSound
