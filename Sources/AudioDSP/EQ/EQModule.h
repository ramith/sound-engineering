#ifndef EQ_MODULE_H
#define EQ_MODULE_H
#include "../include/AudioConstants.h"
#include "../include/TargetState.h"
#include <array>
#include <atomic>
#include <AudioToolbox/AudioToolbox.h>

namespace AdaptiveSound
{

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
        void process(const EQParams& params, AudioBufferList* ioData, uint32_t frameCount) noexcept;

      private:
        // Per-channel delay state for the vDSP_biquad cascade (issue #2).
        // vDSP needs 2*M + 2 floats for an M-section cascade; the cascade is a fixed
        // kMaxBiquads sections (inactive sections are identity-padded), so size for that.
        // Independent, non-overlapping per channel; zero-initialized; persists across
        // process() calls (this IS the filter memory). std::array => no heap, RT-safe.
        static constexpr size_t kDelayStateSize = (2 * static_cast<size_t>(kMaxBiquads)) + 2;
        std::array<float, kDelayStateSize> leftDelay_{};
        std::array<float, kDelayStateSize> rightDelay_{};

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

        uint32_t sampleRate_ = kDefaultSampleRate;
        uint32_t maxFrames_ = kDefaultMaxFrames;
    };

} // namespace AdaptiveSound
#endif
