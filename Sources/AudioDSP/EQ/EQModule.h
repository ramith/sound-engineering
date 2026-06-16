#ifndef EQ_MODULE_H
#define EQ_MODULE_H
#include "../include/AudioConstants.h"
#include "../include/MultichannelView.h"
#include "../include/PerChannel.h"
#include "../include/TargetState.h"
#include <array>
#include <atomic>
#include <AudioToolbox/AudioToolbox.h>
#include <cmath>

namespace AdaptiveSound
{

    // ---------------------------------------------------------------------------
    // ParameterRamp — one-pole IIR smoother for zipper-noise-free gain changes.
    //
    // Model: y[n] = α·target + (1-α)·y[n-1]   (one-pole low-pass on the target)
    //
    // Coefficient: α = 1 - exp(-1 / (τ · fs))
    //   where τ is the 1/e time constant (seconds) and fs is the sample rate.
    //   This follows directly from the bilinear approximation of the RC circuit,
    //   but uses the exact discrete-time solution (Julius O. Smith, CCRMA,
    //   "Introduction to Digital Filters", §1.3.1).
    //   At 32 ms / 48 kHz: α ≈ 0.000648, giving ~98% of the step in 5τ ≈ 160 ms.
    //
    // RT-safety: tick() is noexcept with no allocation; target is written off-RT
    // before process() is called (no concurrent write during tick()).
    // ---------------------------------------------------------------------------
    struct ParameterRamp
    {
        float target = 0.0F;
        float current = 0.0F;
        float alpha = 0.0F; // (1-α) pole coefficient; α = 1 - alpha

        // Off-RT: compute coefficient for the given time constant and sample rate.
        auto initialize(float timeConstantSeconds, float sampleRate) noexcept -> void
        {
            // Exact discrete-time RC: α = 1 - exp(-1/(τ·fs))
            // (1-α) is the pole; stored as 'alpha' to avoid repeated subtraction.
            alpha = 1.0F - std::exp(-1.0F / (timeConstantSeconds * sampleRate));
        }

        // RT: advance one sample toward target; returns current smoothed value.
        auto tick() noexcept -> float
        {
            current += alpha * (target - current);
            return current;
        }

        // RT: set current = target immediately (used at initialization so the
        // first buffer does not ramp up from zero).
        auto snap() noexcept -> void
        {
            current = target;
        }
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

        // Double-buffered vDSP_biquad_Setup (opaque void*) for RT-safe coefficient
        // updates without create/destroy on the audio thread (issue #3):
        //  - publishCoefficients() (off-RT) creates a new setup into pendingSetup_.
        //  - process() (RT) atomically swaps pendingSetup_ -> activeSetup_ and deposits
        //    the displaced setup into toReleaseSetup_ (no free on the RT thread).
        //  - publishCoefficients() / the destructor (off-RT) destroy released setups.
        // Pointer-width atomics are lock-free on arm64 (asserted in the .mm).
        std::atomic<void*> activeSetup_{nullptr};    // RT runs this
        std::atomic<void*> pendingSetup_{nullptr};   // off-RT publishes, RT adopts
        std::atomic<void*> toReleaseSetup_{nullptr}; // RT deposits old, off-RT destroys

        // Coefficient scratch (kCoeffsPerBiquad per section x kMaxBiquads).
        // Off-RT use only (initialize / publishCoefficients).
        static constexpr size_t kSetupCoeffCount =
            static_cast<size_t>(kMaxBiquads) * static_cast<size_t>(kCoeffsPerBiquad);
        std::array<double, kSetupCoeffCount> cascadeCoeffs_{};

        // Master-gain one-pole ramp (32 ms time constant). Pre-allocated, RT-safe.
        // process() writes rampBuf_[i] = masterGainRamp_.tick() then calls vDSP_vmul.
        ParameterRamp masterGainRamp_{};

        // Per-sample gain ramp scratch buffer. Pre-allocated in initialize() to
        // maxFrames_ capacity so process() never touches the heap. RT-safe std::array
        // sized to the compile-time ceiling; only [0, frameCount) is populated per call.
        static constexpr uint32_t kMaxFramesCeil = kDefaultMaxFrames; // 512 frames
        std::array<float, kMaxFramesCeil> rampBuf_{};

        uint32_t sampleRate_ = kDefaultSampleRate;
        uint32_t maxFrames_ = kDefaultMaxFrames;
    };

} // namespace AdaptiveSound
#endif
