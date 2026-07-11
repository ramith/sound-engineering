#include "EQModule.h"
#include <Accelerate/Accelerate.h>
#include <cassert>
#include <format>
#include <iostream>

namespace AdaptiveSound
{

    EQModule::~EQModule() = default;
    // The RtSwappableResource<VDSPBiquadSetup> member's dtor (off-RT) frees every live setup
    // via VDSPBiquadSetup -> vDSP_biquad_DestroySetup. Precondition: the RT thread is quiesced.

    void EQModule::initialize(uint32_t sampleRate, uint32_t maxFrames) noexcept
    {
        sampleRate_ = sampleRate;
        maxFrames_ = maxFrames;

        // Reset per-channel delay state (issue #2).
        delays_.reset();

        // Seed coefficients to an all-identity cascade (b0=1, rest 0 per section).
        cascadeCoeffs_.fill(0.0);
        for (size_t i = 0; i < static_cast<size_t>(kMaxBiquads); ++i)
        {
            cascadeCoeffs_[i * kCoeffsPerBiquad] = 1.0; // b0
        }

        // Create the initial (identity) setup once, off-RT. Until publishCoefficients()
        // supplies real coefficients, the cascade passes audio through unchanged.
        // publish() into pending_; the first process() adopt()s it into active_. (Before any
        // adopt, active() is null and process() returns early, exactly as before initialize.)
        vDSP_biquad_Setup setup =
            vDSP_biquad_CreateSetup(cascadeCoeffs_.data(), static_cast<vDSP_Length>(kMaxBiquads));
        setup_.publish(std::make_unique<VDSPBiquadSetup>(setup));

        // Initialize the master-gain ramp with a 32 ms time constant and snap it to
        // unity so the first buffer plays at full gain rather than ramping up from 0.
        constexpr float kMasterGainRampSeconds = 0.032F; // 32 ms one-pole smoothing
        masterGainRamp_.initialize(kMasterGainRampSeconds, static_cast<float>(sampleRate));
        masterGainRamp_.target = 1.0F;
        masterGainRamp_.snap();

        // Size the ramp scratch buffer to maxFrames_ (off-RT; the only allocation site).
        // process() asserts frameCount <= maxFrames_ so this is the tight upper bound.
        rampBuf_.assign(maxFrames_, 0.0F);
    }

    void EQModule::publishCoefficients(const EQParams& params) noexcept
    {
        // OFF-RT ONLY. Pack the active sections, identity-pad the rest, build a new
        // fixed-size (kMaxBiquads) setup, and hand it to the RT thread via setup_.publish().
        const size_t numActive =
            std::min(static_cast<size_t>(params.numBiquads), static_cast<size_t>(kMaxBiquads));

        for (size_t i = 0; i < numActive; ++i)
        {
            const auto& coeffs = params.biquads[i];
            const size_t offset = i * kCoeffsPerBiquad;
            cascadeCoeffs_[offset + 0] = static_cast<double>(coeffs.b0);
            cascadeCoeffs_[offset + 1] = static_cast<double>(coeffs.b1);
            cascadeCoeffs_[offset + 2] = static_cast<double>(coeffs.b2);
            cascadeCoeffs_[offset + 3] = static_cast<double>(coeffs.a1);
            cascadeCoeffs_[offset + 4] = static_cast<double>(coeffs.a2);
        }
        for (size_t i = numActive; i < static_cast<size_t>(kMaxBiquads); ++i)
        {
            const size_t offset = i * kCoeffsPerBiquad;
            cascadeCoeffs_[offset + 0] = 1.0; // identity: b0=1
            cascadeCoeffs_[offset + 1] = 0.0;
            cascadeCoeffs_[offset + 2] = 0.0;
            cascadeCoeffs_[offset + 3] = 0.0;
            cascadeCoeffs_[offset + 4] = 0.0;
        }

        vDSP_biquad_Setup newSetup =
            vDSP_biquad_CreateSetup(cascadeCoeffs_.data(), static_cast<vDSP_Length>(kMaxBiquads));
        if (newSetup == nullptr)
        {
            std::cerr << std::format(
                "[EQModule] WARNING: vDSP_biquad_CreateSetup failed for {} biquads; "
                "keeping existing setup running\n",
                static_cast<uint32_t>(numActive));
            return;
        }

        // Publish to the RT thread. publish() first reclaim()s anything the RT thread retired,
        // then release-stores the new setup into pending_. If a prior pending was never adopted
        // (two updates before one render), publish() frees that displaced setup here (off-RT) —
        // single-pending. The Realizer's coalescing guarantees the producer never outruns the RT
        // adopt (S6 Tier-3 §3.2 ↔ §3a).
        setup_.publish(std::make_unique<VDSPBiquadSetup>(newSetup));
    }

    void EQModule::process(const EQParams& params, const MultichannelView& block) noexcept
    {
        const uint32_t frameCount = block.frames();
        if (frameCount == 0)
        {
            return;
        }
        // frameCount must never exceed the buffer capacity established in initialize().
        // Violating this would overrun rampBuf_ (sized to maxFrames_ off-RT).
        assert(frameCount <= maxFrames_);

        // RT-safe setup adoption: adopt() swaps any pending setup into active, retires the old
        // one for off-RT reclaim, and returns the live resource. All lock-free atomics — no
        // alloc, no free, no lock on the render thread.
        //
        // Delay state (delays_) is intentionally PRESERVED across swaps and stays HERE in
        // EQModule — it is module-specific filter memory, NOT part of the generic swap template
        // (S6 Tier-3 §3). The cascade is a fixed kMaxBiquads topology, so the 2*kMaxBiquads+2
        // delay layout is invariant and the existing state is valid input to the new
        // coefficients — continuous filter memory is click-free, whereas re-zeroing would inject
        // a discontinuity on every EQ change. (Confirmed by audio-dsp-agent + cpp-pro; obsoletes
        // the #2 re-zero, which only existed because the section count — and thus the layout —
        // varied.) The template swaps the resource; delays_ are never touched by adopt().
        VDSPBiquadSetup* adopted = setup_.adopt();
        if (adopted == nullptr || adopted->get() == nullptr)
        {
            return;
        }
        vDSP_biquad_Setup setup = adopted->get();

        // Run every channel through the fixed kMaxBiquads-section cascade (identity-padded).
        // Each channel has its own independent delay state in delays_[ch]; the SAME setup
        // (coefficient cascade) is applied to all channels — identical tonal curve, independent
        // filter memory. delays_ is sized kMaxChannels; block.channels() ≤ kMaxChannels (enforced
        // by MultichannelView::fromABL). No alloc, no lock — RT-safe.
        const uint32_t numChannels = block.channels();
        const vDSP_Length vDspFrames = static_cast<vDSP_Length>(frameCount);
        for (uint32_t ch = 0U; ch < numChannels; ++ch)
        {
            float* buf = block.channel(ch);
            if (buf != nullptr)
            {
                vDSP_biquad(setup, delays_[ch].data(), buf, 1, buf, 1, vDspFrames);
            }
        }

        // Apply master gain with per-sample ramping to eliminate zipper noise.
        //
        // Update the ramp target from the current params. The target is set here (on the
        // RT thread) immediately before tick() — this is safe because publishTargetState()
        // (the sole off-RT writer of params.masterGainLinear) completes its store before
        // the render thread reads the TargetState snapshot, so there is no concurrent write
        // to params.masterGainLinear while process() runs.
        //
        // Fast path: if the ramp has fully settled at unity, skip the multiply entirely.
        // The settled check uses an epsilon so floating-point drift does not prevent exit.
        masterGainRamp_.target = params.masterGainLinear;
        const bool settled = (std::abs(masterGainRamp_.current - masterGainRamp_.target) < 1e-6F);

        if (!settled || params.masterGainLinear != 1.0F)
        {
            // Generate the per-sample gain envelope into rampBuf_ ONCE (shared across all
            // channels — one ramp for all; the envelope is channel-independent).
            // tick() advances current toward target by α each sample — this IS the
            // one-pole smoother; no secondary vDSP_vramp interpolation needed.
            //
            // rampBuf_ is sized to maxFrames_ in initialize(). The assert above
            // guarantees frameCount <= maxFrames_, so the full frameCount is safe.
            const uint32_t safeCount = std::min(frameCount, maxFrames_);
            const vDSP_Length len = static_cast<vDSP_Length>(safeCount);
            for (uint32_t i = 0U; i < safeCount; ++i)
            {
                rampBuf_[i] = masterGainRamp_.tick();
            }

            // vDSP_vmul: element-wise multiply (signal × per-sample gain), per channel.
            for (uint32_t ch = 0U; ch < numChannels; ++ch)
            {
                float* buf = block.channel(ch);
                if (buf != nullptr)
                {
                    vDSP_vmul(buf, 1, rampBuf_.data(), 1, buf, 1, len);
                }
            }
        }
    }

} // namespace AdaptiveSound
