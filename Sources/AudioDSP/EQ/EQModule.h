#pragma once
#include "../include/AudioConstants.h"
#include "../include/MultichannelView.h"
#include "../include/ParameterRamp.h"
#include "../include/PerChannel.h"
#include "../include/RtSwappableResource.h"
#include "../include/TargetState.h"
#include <Accelerate/Accelerate.h>
#include <array>
#include <AudioToolbox/AudioToolbox.h>
#include <cassert>
#include <cmath>
#include <utility>
#include <vector>

namespace AdaptiveSound
{

    // ParameterRamp now lives in include/ParameterRamp.h (shared by EQ + Loudness).

    // Move-only RAII wrapper over the opaque vDSP_biquad_Setup handle. Owns exactly one
    // setup; the destructor calls vDSP_biquad_DestroySetup. Used as the T of the EQ's
    // RtSwappableResource: T's dtor frees the resource, so the swap template never has to
    // know about Accelerate. Rule of five (it owns a resource): copy deleted, move clears
    // the source, both move ops + dtor noexcept (no throw across the off-RT free).
    class VDSPBiquadSetup
    {
      public:
        VDSPBiquadSetup() = default;
        explicit VDSPBiquadSetup(vDSP_biquad_Setup setup) noexcept : setup_(setup)
        {
        }

        ~VDSPBiquadSetup()
        {
            if (setup_ != nullptr)
            {
                vDSP_biquad_DestroySetup(setup_);
            }
        }

        VDSPBiquadSetup(const VDSPBiquadSetup&) = delete;
        VDSPBiquadSetup& operator=(const VDSPBiquadSetup&) = delete;

        VDSPBiquadSetup(VDSPBiquadSetup&& other) noexcept
            : setup_(std::exchange(other.setup_, nullptr))
        {
        }
        VDSPBiquadSetup& operator=(VDSPBiquadSetup&& other) noexcept
        {
            if (this != &other)
            {
                if (setup_ != nullptr)
                {
                    vDSP_biquad_DestroySetup(setup_);
                }
                setup_ = std::exchange(other.setup_, nullptr);
            }
            return *this;
        }

        [[nodiscard]] vDSP_biquad_Setup get() const noexcept
        {
            return setup_;
        }

      private:
        vDSP_biquad_Setup setup_ = nullptr;
    };

    class EQModule
    {
      public:
        EQModule() = default;
        ~EQModule();

        EQModule(const EQModule&) = delete;
        EQModule& operator=(const EQModule&) = delete;
        EQModule(EQModule&&) = delete;
        EQModule& operator=(EQModule&&) = delete;

        void initialize(uint32_t sampleRate, uint32_t maxFrames) noexcept;

        // Off-RT: pack coefficients and build a new vDSP setup, published to the RT
        // thread via the lock-free setup double-buffer. Call when EQParams change.
        //
        // PRECONDITION (load-bearing): SINGLE producer. This must be called from exactly
        // one control thread (today: only DSPKernel::publishTargetState, driven by the
        // single Realizer/control path) and NEVER from the render thread. It is not
        // safe for concurrent callers: cascadeCoeffs_ and the publish handoff are
        // unsynchronized on the producer side. If a second publisher is ever introduced,
        // serialize this with an off-RT mutex around the pack+publish (off-RT only).
        // (issue #3)
        void publishCoefficients(const EQParams& params) noexcept;

        // RT: adopt any pending setup (atomic swap, no alloc) and run the cascade.
        void process(const EQParams& params, const MultichannelView& block) noexcept;

      private:
        // Per-channel delay state for the vDSP_biquad cascade (issue #2).
        // vDSP needs 2*M + 2 floats for an M-section cascade; the cascade is a fixed
        // kMaxBiquads sections (inactive sections are identity-padded), so size for that.
        // Independent, non-overlapping per channel; zero-initialized; persists across
        // process() calls (this IS the filter memory). std::array => no heap, RT-safe.
        static constexpr size_t kDelayStateSize = (2 * static_cast<size_t>(kMaxBiquads)) + 2;
        using EqDelay = std::array<float, kDelayStateSize>;
        PerChannel<EqDelay> delays_{};

        // RT-safe vDSP_biquad_Setup handoff (issue #3), factored into the generic
        // triple-atomic swap template (S6 Tier-3 §3):
        //  - publishCoefficients() (off-RT) builds a new setup and publish()es it.
        //  - process() (RT) adopt()s the pending setup; active() returns the live one.
        //  - publishCoefficients()/dtor (off-RT) reclaim()/free retired setups.
        // VDSPBiquadSetup's dtor calls vDSP_biquad_DestroySetup; the template owns the
        // lock-free pointer swap. EQ's per-channel delays_ filter-state preservation
        // across swaps stays HERE in process() — it is module-specific, not generic.
        RtSwappableResource<VDSPBiquadSetup> setup_;

        // Coefficient scratch (kCoeffsPerBiquad per section x kMaxBiquads).
        // Off-RT use only (initialize / publishCoefficients).
        static constexpr size_t kSetupCoeffCount =
            static_cast<size_t>(kMaxBiquads) * static_cast<size_t>(kCoeffsPerBiquad);
        std::array<double, kSetupCoeffCount> cascadeCoeffs_{};

        // Master-gain one-pole ramp (32 ms time constant). Pre-allocated, RT-safe.
        // process() writes rampBuf_[i] = masterGainRamp_.tick() then calls vDSP_vmul.
        ParameterRamp masterGainRamp_{};

        // Per-sample gain ramp scratch buffer. Heap-allocated in initialize() to
        // maxFrames_ capacity so process() never touches the heap. Only
        // [0, frameCount) is populated per call. frameCount <= maxFrames_ is
        // asserted at process() entry.
        std::vector<float> rampBuf_;

        uint32_t sampleRate_ = kDefaultSampleRate;
        uint32_t maxFrames_ = kDefaultMaxFrames;
    };

} // namespace AdaptiveSound
