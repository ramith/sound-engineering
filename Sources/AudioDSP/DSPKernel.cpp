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
#include <cassert>
#include <cmath>
#include <cstring>

namespace AdaptiveSound
{

    // Intensity ramp time constant. Mirrors the EQ master-gain / loudness makeup smoothers
    // (32 ms one-pole) so a knob sweep is click-free; settles to ~98% in 5τ ≈ 160 ms.
    static constexpr float kIntensityRampTauSeconds = 0.032F;

    // "Settled" epsilon for the intensity ramp: once |current-target| < this AND the target is
    // an endpoint (0 or 1), process() routes to the bit-exact HARD branch (early-return / pure
    // in-place chain) instead of the crossfade.
    //
    // Sized 1e-4 (≈0.0009 dB) — large enough to escape the float32 one-pole stagnation floor
    // (a one-pole smoother cannot asymptotically reach within 1e-6 of a ~1.0 target in float32:
    // alpha·(target-current) underflows the mantissa near unity), small enough to be inaudible.
    // When the hard branch is taken the ramp is SNAPPED to the endpoint (current = target) so the
    // branch is bit-exact and stays settled; the residual ≤1e-4 gain step is click-free.
    static constexpr float kIntensitySettledEpsilon = 1e-4F;

    // Half-pi for the equal-power crossfade gains: wetGain = sin(r·π/2), dryGain = cos(r·π/2).
    static constexpr float kHalfPi = 1.57079632679489661923F;

    DSPKernel::DSPKernel() = default;

    DSPKernel::~DSPKernel() = default;

    // Flush-to-zero (FPCR.FZ) lives in include/FlushToZero.h — one definition shared by every
    // DSP thread (control/init here, the AU + spatial render threads, the loudness worker).

    void DSPKernel::initialize(uint32_t sampleRate, uint32_t maxFrames) noexcept
    {
        sampleRate_ = sampleRate;
        maxFrames_ = maxFrames;

        // Enable flush-to-zero on the init/control thread. The render thread sets it
        // independently at the top of the AU render block (AUAudioUnit.mm).
        enableFlushToZero();

        // Create all DSP modules (Crossfeed is wet-region, adjacent to BRIR's slot — QW1 §2).
        eqModule_ = std::make_unique<EQModule>();
        clarityModule_ = std::make_unique<ClarityModule>();
        brirModule_ = std::make_unique<BRIRModule>();
        crossfeedModule_ = std::make_unique<CrossfeedModule>();
        loudnessModule_ = std::make_unique<LoudnessModule>();
        limiterModule_ = std::make_unique<LimiterModule>();

        // Initialize each module with sample rate and max frame count
        eqModule_->initialize(sampleRate, maxFrames);
        clarityModule_->initialize(sampleRate, maxFrames);
        brirModule_->initialize(sampleRate, maxFrames);
        crossfeedModule_->initialize(sampleRate, maxFrames);
        loudnessModule_->initialize(sampleRate, maxFrames);
        limiterModule_->initialize(sampleRate, maxFrames);

        // --- Steerable wet/dry intensity (S6 Tier-3 §3b) ---
        // Pre-allocate the planar dry-scratch and the per-sample crossfade-gain buffers off-RT,
        // sized to the host's maximumFramesToRender. process() asserts frames ≤ maxFrames_ and
        // never allocates. The dry-scratch holds kMaxChannels lanes of maxFrames_ each; channel
        // ch lives at dryScratch_.data() + ch*maxFrames_.
        dryScratch_.assign(static_cast<size_t>(maxFrames_) * kMaxChannels, 0.0F);
        wetGainBuf_.assign(maxFrames_, 0.0F);
        dryGainBuf_.assign(maxFrames_, 0.0F);

        // Configure the intensity ramp AFTER the modules so it inherits the same sample rate,
        // then SNAP it to the canonical default intensity so the first buffer does not fade in
        // from silence (review DSP-Issue 5). The snapshot's default intensityLinear is 1.0.
        intensityRamp_.initialize(kIntensityRampTauSeconds, static_cast<float>(sampleRate));
        // Seed the RT-owned snapshot from whatever has been published so far (default identity state if
        // nothing yet). The triple-buffer reader is wait-free and always succeeds — on the pre-publish
        // last-good path it hands back the default identity T the transport was seeded with.
        (void)targetStateSnapshot_.tryCopySnapshot(currentState_);
        intensityRamp_.target = currentState_.intensityLinear;
        intensityRamp_.snap();
    }

    void DSPKernel::publishTargetState(const TargetState& newState) noexcept
    {
        // Off-RT control path. Build the EQ vDSP setup off-RT (issue #3) before publishing
        // the snapshot, so the RT thread adopts coefficients and setup together.
        //
        // PRECONDITION: single producer. publishCoefficients() below is not safe for
        // concurrent callers, so this method must be driven by a single control thread
        // (the Realizer/control path). A second publisher would require an off-RT mutex.
        if (eqModule_ != nullptr)
        {
            eqModule_->publishCoefficients(newState.eq);
        }
        targetStateSnapshot_.publish(newState);
    }

    void DSPKernel::publishChannelLayout(const ChannelLayout& layout) noexcept
    {
        // Off-RT (control thread) entry point for M1-2.  S2 will call this when the
        // source file's AudioChannelLayoutTag changes.  Forwarded lock-free to the
        // loudness measurement worker via the generation-parity double buffer in
        // LoudnessModule.  Harmless no-op if loudnessModule_ has not been initialised
        // (i.e. initialize() has not been called yet — the worker does not exist).
        if (loudnessModule_ != nullptr)
        {
            loudnessModule_->publishChannelLayout(layout);
        }
    }

    void DSPKernel::process(AudioBufferList* ioData, uint32_t inNumberFrames) noexcept
    {
        // Copy the current parameter snapshot ONCE into RT-owned storage and use that stable copy for
        // the whole block (S6 RACE-1: never hold a reference into the transport across the block — two
        // off-RT publishes could otherwise overwrite the referenced slot mid-block → torn read). The
        // triple-buffer reader is wait-free (bounded, constant-step, retry-free) and always returns a
        // consistent snapshot — the newest generation, or the last good one when nothing new was
        // published; parameters are ramped so a one-block-stale value is inaudible.
        if (targetStateSnapshot_.tryCopySnapshot(scratchState_))
        {
            currentState_ = scratchState_;
        }
        const TargetState& state = currentState_;

        // --- Steerable wet/dry intensity (S6 Tier-3 §3b) -----------------------------------
        //
        // The blend sits BEFORE Loudness+Limiter (corrected topology): intensity scales the
        // coloration stages (EQ→Clarity→BRIR = "wet"); Loudness normalization + true-peak
        // Limiter always apply whenever not fully bypassed, so the limiter guards the final
        // output and loudness measures what the listener hears.
        //
        // A ramped intensity only approaches 0/1 ASYMPTOTICALLY, and `dry + 1·(wet-dry)` is
        // NOT bit-equal to `wet`. So the bit-exact endpoints take HARD branches gated on
        // "settled" (ramp within ε of target AND target ∈ {0,1}); the crossfade math is never
        // run at a settled endpoint. We never early-return mid-ramp (that would click).
        intensityRamp_.target = state.intensityLinear;
        const bool settled =
            std::abs(intensityRamp_.current - intensityRamp_.target) < kIntensitySettledEpsilon;

        // BRANCH 1 — settled at 0: bit-exact passthrough (today's bypass; golden master path).
        //
        // The AU render block (AUAudioUnit.mm) pulls input directly into the output
        // AudioBufferList (in-place effect), so ioData already holds the input samples by the
        // time process() is called. When intensity is settled at zero we return without
        // touching the buffers — the output is already equal to the input.
        //
        // NOTE: if this kernel is ever used outside the in-place AU context (e.g. a process-tap
        // supplying separate input/output buffers), the caller must copy input to output before
        // calling process(), or this signature must take a separate input ABL.
        if (settled && intensityRamp_.target == 0.0F)
        {
            // Snap so the ramp is exactly at the endpoint: keeps this branch bit-exact and prevents
            // the float32 one-pole stall from leaving current a hair off 0 forever.
            intensityRamp_.current = 0.0F;
            return;
        }

        // Decode the AudioBufferList ONCE into a non-owning planar view (the single ABL-decode
        // point); every module operates on the MultichannelView and never touches the raw ABL.
        const MultichannelView block = MultichannelView::fromABL(ioData, inNumberFrames);

        const uint32_t frameCount = block.frames();
        const uint32_t numChannels = block.channels();
        // frameCount must not exceed the capacity established in initialize() — the dry-scratch
        // and gain buffers are sized to maxFrames_, so this guards against an RT-path overrun.
        assert(frameCount <= maxFrames_);
        const uint32_t safeCount = std::min(frameCount, maxFrames_);

        // BRANCH 2 — settled at 1: run the chain fully in-place EXACTLY as before, with NO blend
        // code path, so the output stays byte-identical to the legacy full chain (golden master).
        if (settled && intensityRamp_.target == 1.0F)
        {
            // Snap to exactly 1.0 (see the x==0 branch): keeps the in-place chain bit-exact and the
            // ramp genuinely settled despite the float32 one-pole asymptote.
            intensityRamp_.current = 1.0F;
            // Full chain in place, byte-identical to the legacy path (golden master). Crossfeed
            // (in the coloration chain, after BRIR) is default-off → bit-exact pass-through.
            runColorationChain(state, block);
            runSafetyChain(state, block);
            return;
        }

        // BRANCH 3 — intermediate or mid-ramp (incl. descent toward 0 / ascent toward 1):
        // the equal-power crossfade path. We never early-return here even when heading to an
        // endpoint, because the ramp is still in flight (cutting it short would click).
        //
        // (a) Snapshot the DRY input per-channel into the planar scratch BEFORE any module
        //     mutates the block in place. Buffers are non-interleaved, so copy per channel.
        for (uint32_t ch = 0U; ch < numChannels; ++ch)
        {
            const float* src = block.channel(ch);
            if (src != nullptr)
            {
                float* dry = dryScratch_.data() + (static_cast<size_t>(ch) * maxFrames_);
                cblas_scopy(static_cast<int>(safeCount), src, 1, dry, 1);
            }
        }

        // (b) Run the coloration chain in place → the block now holds the "wet" signal. Crossfeed is
        //     part of the wet region (after BRIR), so the equal-power blend below scales it by the
        //     Reimagine intensity — at 0% (bypass) crossfeed is off too (QW1 §2).
        runColorationChain(state, block);

        // (c) Equal-power crossfade BEFORE Loudness+Limiter. The intensity ramp is advanced
        //     PER SAMPLE (one tick per frame) into a smoothed value r[i]; the gains are derived
        //     per sample as wetGain[i]=sin(r[i]·π/2), dryGain[i]=cos(r[i]·π/2). Per-sample (vs
        //     per-block constant) is chosen for click-free correctness — a per-block gain would
        //     step at block boundaries during a sweep, and resources are abundant (founder:
        //     quality first). One ramp drives all channels (intensity is channel-independent).
        //
        //     LAW CHOICE (Stage-1 AC-5): equal-POWER (sin/cos) is the correct law for
        //     UNCORRELATED signals; a dry/wet pair is correlated for lightly-processed material,
        //     where equal-power adds up to +3 dB at the r=0.5 midpoint. That is intentional and
        //     acceptable here: the wet chain (BRIR spatialization + crossfeed) decorrelates toward
        //     the equal-power regime, and the downstream Loudness stage normalizes to the LUFS
        //     target, absorbing any residual midpoint bump before output.
        const vDSP_Length len = static_cast<vDSP_Length>(safeCount);
        for (uint32_t i = 0U; i < safeCount; ++i)
        {
            const float ramped = intensityRamp_.tick();
            wetGainBuf_[i] = std::sin(ramped * kHalfPi);
            dryGainBuf_[i] = std::cos(ramped * kHalfPi);
        }
        for (uint32_t ch = 0U; ch < numChannels; ++ch)
        {
            float* wet = block.channel(ch);
            if (wet != nullptr)
            {
                const float* dry = dryScratch_.data() + (static_cast<size_t>(ch) * maxFrames_);
                // out = dryGain·dry + wetGain·wet  (two-op form: scale wet in place by wetGain,
                // then multiply-add dryGain·dry). vDSP permits the in-place wet operand; dry is a
                // distinct, non-aliasing buffer.
                vDSP_vmul(wet, 1, wetGainBuf_.data(), 1, wet, 1, len);        // wet *= wetGain
                vDSP_vma(dry, 1, dryGainBuf_.data(), 1, wet, 1, wet, 1, len); // wet += dryGain·dry
            }
        }

        // (d) Loudness then Limiter on the BLENDED signal: loudness makeup converges on the
        //     actual output, and the true-peak limiter guards the final blended output so the
        //     −1 dBTP ceiling always holds at intermediate intensities.
        runSafetyChain(state, block);
    }

    // Wet-region coloration chain, in place: EQ → Clarity → BRIR → Crossfeed. Crossfeed sits in
    // the wet region after BRIR (QW1 §2); default-off → bit-exact pass-through (the module
    // early-returns on enabled==0). Shared by the settled-at-1 and mid-ramp branches so the chain
    // order lives in ONE place (Stage-1 review AR-4).
    void DSPKernel::runColorationChain(const TargetState& state,
                                       const MultichannelView& block) noexcept
    {
        eqModule_->process(state.eq, block);
        clarityModule_->process(state.clarity, block);
        brirModule_->process(state.brir, block);
        crossfeedModule_->process(state.crossfeed, block);
    }

    // Safety chain, in place: Loudness normalization → true-peak Limiter. Always applied whenever
    // the kernel is not fully bypassed, so the limiter guards the final output and loudness
    // measures what the listener hears.
    void DSPKernel::runSafetyChain(const TargetState& state, const MultichannelView& block) noexcept
    {
        loudnessModule_->process(state.loudness, block);
        limiterModule_->process(state.limiter, block);
    }

} // namespace AdaptiveSound
