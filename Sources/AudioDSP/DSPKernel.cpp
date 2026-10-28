#include "include/DSPKernel.h"
#include "Clarity/ClarityModule.h"
#include "EQ/EQModule.h"
#include "include/FiniteSamples.h"
#include "include/FlushToZero.h"
#include "include/MultichannelView.h"
#include "Limiting/LimiterModule.h"
#include "Loudness/CausalLoudnessTap.h"
#include "Loudness/LoudnessModule.h"
#include "Spatial/BRIRModule.h"
#include "Spatial/CrossfeedModule.h"
#include <Accelerate/Accelerate.h>
#include <algorithm>
#include <cassert>
#include <cmath>
#include <cstring>
#include <span>
#include <utility>

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
    // makeup·min(1, r/0.1)), and fades linearly to 0 dB below it …
    static constexpr float kLoudnessFadeIntensity = 0.1F;
    // … but in TIME it moves no faster than a full 0 ↔ 1 in this long (founder decision 33:
    // crossing Intensity 0 glides the level over ~2 s): the normaliser's makeup leaves (or joins)
    // the level as a slow fade, however fast Intensity itself moves.
    static constexpr float kLoudnessGlideSeconds = 2.0F;

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

        eqModule_ = std::make_unique<EQModule>();
        clarityModule_ = std::make_unique<ClarityModule>();
        brirModule_ = std::make_unique<BRIRModule>();
        crossfeedModule_ = std::make_unique<CrossfeedModule>();
        loudnessModule_ = std::make_unique<LoudnessModule>();
        limiterModule_ = std::make_unique<LimiterModule>();
        causalTap_ = std::make_unique<CausalLoudnessTap>();

        eqModule_->initialize(sampleRate, maxFrames);
        clarityModule_->initialize(sampleRate, maxFrames);
        brirModule_->initialize(sampleRate, maxFrames);
        crossfeedModule_->initialize(sampleRate, maxFrames);
        loudnessModule_->initialize(sampleRate, maxFrames);
        limiterModule_->initialize(sampleRate, maxFrames);
        causalTap_->initialize(sampleRate, maxFrames);

        // Pre-allocate every scratch off-RT, sized to the host's maximumFramesToRender.
        const auto planar = static_cast<size_t>(maxFrames_) * kMaxChannels;
        dryScratch_.assign(planar, 0.0F);
        bypassScratch_.assign(planar, 0.0F);
        wetGainBuf_.assign(maxFrames_, 0.0F);
        dryGainBuf_.assign(maxFrames_, 0.0F);
        loudnessWeightBuf_.assign(maxFrames_, 0.0F);

        // Snap the intensity ramp to whatever has been published so far (no launch fade-in).
        intensityRamp_.initialize(kIntensityRampTauSeconds, static_cast<float>(sampleRate));
        targetStateSnapshot_.copySnapshot(currentState_);
        intensityRamp_.target = currentState_.intensityLinear;
        intensityRamp_.snap();
        loudnessContribution_ = loudnessContributionAt(intensityRamp_.current);
        loudnessContributionStep_ =
            1.0F / std::max(1.0F, kLoudnessGlideSeconds * static_cast<float>(sampleRate));

        const auto fs = static_cast<double>(sampleRate);
        bypassMixStep_ = 1.0F / std::max(1.0F, kBypassCrossfadeSeconds * static_cast<float>(fs));
        bypassHoldFrames_ = static_cast<uint64_t>(std::llround(kBypassHoldSeconds * fs));
        identityHeldFrames_ = 0U;
        bypassMix_ = 0.0F;
        firstBlock_ = true;
        // A fresh crossfeed module plays nothing until its first block says otherwise (S2).
        crossfeedEngagedSeen_ = 0U;
        crossfeedEngaged_.store(0U, std::memory_order_relaxed);
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
        if (causalTap_ != nullptr)
        {
            causalTap_->publishChannelLayout(layout);
        }
    }

    void DSPKernel::startCausalLoudness(
        std::function<void(std::shared_ptr<const TrackLoudnessProfile>)> sink) noexcept
    {
        if (causalTap_ != nullptr)
        {
            causalTap_->start(std::move(sink));
        }
    }

    void DSPKernel::stopCausalLoudness() noexcept
    {
        if (causalTap_ != nullptr)
        {
            causalTap_->stop();
        }
    }

    uint64_t DSPKernel::causalLoudnessFedFrames() const noexcept
    {
        return (causalTap_ != nullptr) ? causalTap_->fedFrames() : 0U;
    }

    bool DSPKernel::analysisWorkersParked() const noexcept
    {
        return loudnessModule_ != nullptr && causalTap_ != nullptr &&
               loudnessModule_->workerParked() && causalTap_->workerParked();
    }

    bool DSPKernel::loudnessMeterCaughtUp() const noexcept
    {
        return loudnessModule_ == nullptr || loudnessModule_->meterCaughtUp();
    }

    uint64_t DSPKernel::analysisWorkerWakes() const noexcept
    {
        return (loudnessModule_ != nullptr ? loudnessModule_->workerWakes() : 0U) +
               (causalTap_ != nullptr ? causalTap_->workerWakes() : 0U);
    }

    void DSPKernel::process(AudioBufferList* ioData, uint32_t inNumberFrames) noexcept
    {
        // Subnormals flush to zero while the kernel renders, on whichever thread calls it, and the
        // caller's floating-point mode comes back on return (council C-50): structural for every
        // host of the kernel, and never left set on a thread Apple's own nodes share.
        const ScopedFlushToZero flushToZero;

        // Copy the snapshot ONCE into RT-owned storage (S6 RACE-1); wait-free.
        targetStateSnapshot_.copySnapshot(scratchState_);
        currentState_ = scratchState_;
        const TargetState& state = currentState_;
        const MultichannelView block = MultichannelView::fromABL(ioData, inNumberFrames);

        // A NaN or an infinity is not audio (amendment 14): it plays as silence on EVERY path, the
        // bit-perfect one included, so nothing downstream — a filter state, the normaliser, the
        // limiter, the device — ever meets one. A finite block is only read, never written.
        for (uint32_t ch = 0U; ch < block.channels(); ++ch)
        {
            if (float* samples = block.channel(ch); samples != nullptr)
            {
                scrubNonFinite(samples, block.frames());
            }
        }

        // The source, ahead of everything, for the causal loudness estimate (a no-op unless one
        // runs: the fallback for a track whose loudness analysis failed).
        causalTap_->push(block);

        // The EQ adopts its target on every path (even the bit-perfect one), so an EQ turned on
        // during the bypass is seen here.
        eqModule_->update(state.eq);

        intensityRamp_.target = state.intensityLinear;
        const bool settled =
            std::abs(intensityRamp_.current - intensityRamp_.target) < kIntensitySettledEpsilon;
        const bool endpoint = intensityRamp_.target == 0.0F || intensityRamp_.target == 1.0F;
        if (settled && endpoint)
        {
            intensityRamp_.current = intensityRamp_.target; // keep the endpoint bit-exact
        }
        // An endpoint's hard branch (P1 / P2) also waits for the normaliser's contribution to
        // finish its glide there (decision 33); until then the blend path runs at the endpoint.
        const bool atZero =
            settled && intensityRamp_.target == 0.0F && loudnessContribution_ == 0.0F;
        const bool atOne =
            settled && intensityRamp_.target == 1.0F && loudnessContribution_ == 1.0F;

        // P0 eligibility, with the 2 s hysteresis. The first block after initialize() has no
        // previous output to stay continuous with, so it snaps to its path. Crossfeed is an output
        // stage of its own: while it plays (or glides out) the kernel is off the bit-perfect path,
        // whatever Intensity is (founder decision 2026-10-14).
        const bool crossfeedBypassed =
            crossfeedModule_->isBypassed(state.crossfeed, block.channels());
        const bool identity = atZero && eqModule_->isIdentity() && crossfeedBypassed;
        publishCrossfeedEngaged(!crossfeedBypassed);
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

    void DSPKernel::publishCrossfeedEngaged(bool engaged) noexcept
    {
        const uint8_t value = engaged ? 1U : 0U;
        if (value != crossfeedEngagedSeen_)
        {
            crossfeedEngagedSeen_ = value;
            crossfeedEngaged_.store(value, std::memory_order_relaxed);
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
            // P1: EQ → Crossfeed → Limiter. No coloration, no normaliser; the limiter at the
            // EQ-only ceiling (decision 29: −0.1 dBTP on a wired output, so a loud master's EQ On
            // is not squashed under its bit-perfect Off). It only ever RAISES the ceiling, so a
            // bypassed limiter (ceiling ≥ 1) stays bypassed.
            LimiterParams eqOnly = state.limiter;
            eqOnly.truePeakCeilingLinear =
                std::max(state.limiter.truePeakCeilingLinear, state.limiter.eqOnlyCeilingLinear);
            renderOutput(state, block, eqOnly);
            return;
        }
        if (intensityAtOne)
        {
            // P2: the full chain in place.
            runColorationChain(state, block);
            loudnessModule_->process(state.loudness, block);
            renderOutput(state, block, state.limiter);
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
        //     +3 dB at r = 0.5, which the normaliser downstream absorbs. The normaliser's
        //     contribution glides toward min(1, r/0.1) at most 1 per kLoudnessGlideSeconds.
        for (uint32_t i = 0U; i < safeCount; ++i)
        {
            const float ramped = intensityRamp_.tick();
            wetGainBuf_[i] = std::sin(ramped * kHalfPi);
            dryGainBuf_[i] = std::cos(ramped * kHalfPi);
            const float goal = loudnessContributionAt(ramped);
            loudnessContribution_ =
                (goal > loudnessContribution_)
                    ? std::min(goal, loudnessContribution_ + loudnessContributionStep_)
                    : std::max(goal, loudnessContribution_ - loudnessContributionStep_);
            loudnessWeightBuf_[i] = loudnessContribution_;
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
        //     the normaliser-free EQ-only path with no level step (amendment 2), and slowly
        //     (decision 33); then the output stages.
        loudnessModule_->process(
            state.loudness, block, std::span<const float>(loudnessWeightBuf_.data(), safeCount));
        renderOutput(state, block, state.limiter);
    }

    // The output stages, on every processed path, after Intensity: the headphone crossfeed — an
    // output-rendering stage of its own, at its preset's full strength whatever Intensity is
    // (founder decision 2026-10-14), an exact pass-through when off — then the true-peak limiter,
    // last, because crossfeed can add level.
    void DSPKernel::renderOutput(const TargetState& state,
                                 const MultichannelView& block,
                                 const LimiterParams& limiter) noexcept
    {
        crossfeedModule_->process(state.crossfeed, block);
        limiterModule_->process(limiter, block);
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

    float DSPKernel::loudnessContributionAt(float intensity) noexcept
    {
        return std::min(1.0F, intensity / kLoudnessFadeIntensity);
    }

    float DSPKernel::streamCorrelation(const MultichannelView& block,
                                       uint32_t frames) const noexcept
    {
        double cross = 0.0;
        double processedEnergy = 0.0;
        double inputEnergy = 0.0;
        for (uint32_t ch = 0U; ch < block.channels(); ++ch)
        {
            const float* processed = block.channel(ch);
            if (processed == nullptr)
            {
                continue;
            }
            const float* input = bypassScratch_.data() + (static_cast<size_t>(ch) * maxFrames_);
            for (uint32_t i = 0U; i < frames; ++i)
            {
                cross += static_cast<double>(processed[i]) * input[i];
                processedEnergy += static_cast<double>(processed[i]) * processed[i];
                inputEnergy += static_cast<double>(input[i]) * input[i];
            }
        }
        const double norm = std::sqrt(processedEnergy * inputEnergy);
        // Anti-correlated streams are faded as uncorrelated ones: positive gains cannot keep their
        // power anyway, and the endpoints stay exact only for ρ ≥ 0.
        return (norm > 0.0) ? static_cast<float>(std::clamp(cross / norm, 0.0, 1.0)) : 0.0F;
    }

    void DSPKernel::crossfadeWithBypass(const MultichannelView& block, float toward) noexcept
    {
        // A constant-POWER cross-fade between the processed block and the undelayed input,
        // w gliding linearly toward `toward` over 5 ms (amendment 17). The two streams are the same
        // audio 3 ms apart (the limiter's look-ahead), so a fade beats the skip or repeat a hard
        // switch would make — but how alike they are depends on the content: broadband audio is
        // nearly uncorrelated 3 ms apart (an equal-GAIN fade dips it −3 dB mid-way), a low or
        // periodic tone nearly identical (an equal-POWER one would bump it +3 dB). So when a fade
        // starts it measures the streams' correlation ρ over the block (all channels), and holds
        //   input = sin(w·π/2),  processed = −ρ·input + √(1 − input²·(1 − ρ²)),
        // whose sum keeps the power for that ρ: equal-power at ρ = 0, equal-gain at ρ = 1, and a
        // constant envelope for a tone (ρ = cos of its phase shift). Limits: ρ comes from one render
        // block, so a low mono tone in a very small block can wander (up to +2.7 dB at 30 Hz with
        // 128 frames, ±0.5 dB at 512) for the ~2 ms mid-fade; content anti-correlated 3 ms apart
        // (a tone near 167 Hz, 500 Hz …) still dips there — no positive-gain fade avoids that.
        const uint32_t safeCount = std::min(block.frames(), maxFrames_);
        if ((bypassMix_ == 0.0F || bypassMix_ == 1.0F) && bypassMix_ != toward)
        {
            bypassCorrelation_ = streamCorrelation(block, safeCount);
        }
        const float rho = bypassCorrelation_;
        const float uncorrelated = 1.0F - (rho * rho);
        const float step = (toward > bypassMix_) ? bypassMixStep_ : -bypassMixStep_;
        for (uint32_t i = 0U; i < safeCount; ++i)
        {
            bypassMix_ = (step > 0.0F) ? std::min(toward, bypassMix_ + step)
                                       : std::max(toward, bypassMix_ + step);
            const float inputGain = (bypassMix_ >= 1.0F) ? 1.0F : std::sin(bypassMix_ * kHalfPi);
            wetGainBuf_[i] =
                (bypassMix_ >= 1.0F)
                    ? 0.0F
                    : (-rho * inputGain) + std::sqrt(1.0F - (inputGain * inputGain * uncorrelated));
            dryGainBuf_[i] = inputGain;
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
                out[i] = (wetGainBuf_[i] * out[i]) + (dryGainBuf_[i] * input[i]);
            }
        }
    }

    // Wet-region coloration chain, in place: Clarity → BRIR — what Intensity blends in. The EQ
    // runs ahead of it, before the dry tap; the crossfeed after the blend (renderOutput).
    void DSPKernel::runColorationChain(const TargetState& state,
                                       const MultichannelView& block) noexcept
    {
        clarityModule_->process(state.clarity, block);
        brirModule_->process(state.brir, block);
    }

} // namespace AdaptiveSound
