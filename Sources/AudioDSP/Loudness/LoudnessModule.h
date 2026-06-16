#ifndef LOUDNESS_MODULE_H
#define LOUDNESS_MODULE_H

// LoudnessModule — ITU-R BS.1770-5 gated loudness measurement + auto makeup gain.
//
// Chain position (DSPKernel.h):  EQ → Clarity → BRIR → [Loudness] → Limiter.
//
// Unlike the other modules, Loudness runs a MEASUREMENT FEEDBACK LOOP that must
// stay off the render thread:
//
//   RT process()  ──push samples──▶  SpscRing  ──▶  measurement jthread (LufsMeter)
//   RT process()  ◀──atomic float──  makeupGainLinear_  ◀──  measurement jthread
//
// The RT thread NEVER measures and NEVER blocks: it relays lufsTarget/enabled to
// the worker via atomics, pushes post-BRIR samples into a lock-free SPSC ring
// (DROP on full — measurement degrades, audio never stalls), reads the atomic
// makeup-gain scalar, and applies it through a 50 ms one-pole ParameterRamp +
// vDSP_vmul (identical to the EQ master-gain / limiter pattern). All K-weighting,
// gating and integration run OFF-RT in double precision (see LufsMeter).
//
// Single-producer invariant: the measurement-derived makeup gain is a module-local
// std::atomic, NOT routed through DSPKernel::publishTargetState(). lufsTarget and
// enabled are relayed RT→worker via module-local atomics rather than having the
// worker read the TargetState snapshot — so the RT thread stays the snapshot's
// sole reader and publishTargetState() remains the single producer.
//
// References: ITU-R BS.1770-5; Timur Doumler (RT thread safety: scalars via atomic,
// streams via lock-free SPSC FIFO, RT side drops); rigtorp/SPSCQueue; JOS one-pole.

#include "../EQ/EQModule.h" // ParameterRamp
#include "../include/AudioConstants.h"
#include "../include/MultichannelView.h"
#include "../include/SpscRing.h"
#include "../include/TargetState.h"
#include "LufsMeter.h"
#include <array>
#include <atomic>
#include <AudioToolbox/AudioToolbox.h>
#include <cstdint>
#include <thread>

namespace AdaptiveSound
{

    // Makeup-gain control law (off-RT derivation).
    inline constexpr double kMakeupClampLoDb = -20.0;       // floor on applied makeup
    inline constexpr double kMakeupClampHiDb = 12.0;        // ceiling on applied makeup
    inline constexpr double kMakeupSlewDbPerBlock = 0.1;    // 1 dB/s at 100 ms gated blocks
    inline constexpr float kMakeupRampTauSeconds = 0.050F;  // RT-side one-pole smoother
    inline constexpr uint32_t kLoudnessMinGatedBlocks = 3U; // hold unity until ≥ this many

    // SPSC ring: per-channel frames buffered (~683 ms @ 48 k) so the worker can fall
    // a full integration block behind without forcing the RT side to drop. Power of
    // two. Stereo is pushed interleaved → backing element count is 2×.
    inline constexpr std::size_t kLoudnessRingFrames = 32768U;
    inline constexpr std::size_t kLoudnessRingElems = kLoudnessRingFrames * 2U;

    // Worker drain chunk (interleaved elements per popBlock).
    inline constexpr std::size_t kWorkerChunkFrames = 1024U;
    inline constexpr std::size_t kWorkerChunkElems = kWorkerChunkFrames * 2U;

    inline constexpr int kWorkerIdleSleepMs = 5; // off-RT sleep when ring empty
    inline constexpr float kUnityGainLinear = 1.0F;
    inline constexpr float kLoudnessUnmeasuredLufs = -200.0F; // telemetry sentinel

    // Member order is constrained by RAII: measurementThread_ MUST be declared last
    // so it is destroyed (request_stop()+join()) before the ring/meter it touches.
    // That ordering prevents the size-optimal layout, but there is a single
    // long-lived instance, so the padding is irrelevant.
    // NOLINTNEXTLINE(clang-analyzer-optin.performance.Padding)
    class LoudnessModule
    {
      public:
        LoudnessModule() = default;
        ~LoudnessModule(); // joins the measurement jthread (defined in .mm)

        // Owns a jthread + ring: non-copyable, non-movable (C.21, C.67).
        LoudnessModule(const LoudnessModule&) = delete;
        LoudnessModule& operator=(const LoudnessModule&) = delete;
        LoudnessModule(LoudnessModule&&) = delete;
        LoudnessModule& operator=(LoudnessModule&&) = delete;

        // Off-RT: configures the meter for `sampleRate`, snaps the makeup ramp to
        // unity, and STARTS the measurement worker. Call before the first process().
        void initialize(uint32_t sampleRate, uint32_t maxFrames) noexcept;

        // RT: noexcept, zero alloc/lock. Relays params to the worker, pushes samples
        // (drop on full), and applies the smoothed makeup gain in place.
        void process(const LoudnessParams& params, const MultichannelView& block) noexcept;

        // Lock-free telemetry getters (UI / Milestone 4); callable from any thread.
        [[nodiscard]] auto measuredLufsIntegrated() const noexcept -> float;
        [[nodiscard]] auto measuredLufsShortTerm() const noexcept -> float;
        [[nodiscard]] auto measuredLufsMomentary() const noexcept -> float;
        [[nodiscard]] auto currentMakeupGainLinear() const noexcept -> float;
        [[nodiscard]] auto droppedFrameCount() const noexcept -> uint64_t;

      private:
        // Off-RT worker (runs on measurementThread_).
        void runMeasurementLoop(const std::stop_token& stopToken) noexcept;
        void updateMakeupGain(uint32_t newGatedBlocks) noexcept;
        void publishTelemetry() noexcept;

        // --- Atomic hand-offs (asserted is_always_lock_free in the .mm) ---
        std::atomic<float> makeupGainLinear_{kUnityGainLinear};              // worker→RT (audible)
        std::atomic<float> targetLufs_{kDefaultLufsTarget};                  // RT→worker (control)
        std::atomic<uint8_t> enabled_{1U};                                   // RT→worker (control)
        std::atomic<float> measuredLufsIntegrated_{kLoudnessUnmeasuredLufs}; // worker→UI
        std::atomic<float> measuredLufsShortTerm_{kLoudnessUnmeasuredLufs};  // worker→UI
        std::atomic<float> measuredLufsMomentary_{kLoudnessUnmeasuredLufs};  // worker→UI
        std::atomic<uint64_t> droppedFrames_{0U};                            // RT→diagnostics

        // --- RT-owned state ---
        SpscRing<float, kLoudnessRingElems> sampleRing_;
        ParameterRamp makeupGainRamp_{};
        std::array<float, kDefaultMaxFrames> rampBuf_{}; // per-sample gain scratch
        std::array<float, static_cast<std::size_t>(kDefaultMaxFrames) * 2U>
            pushBuf_{}; // interleave scratch

        // --- Worker-owned state (touched only on measurementThread_) ---
        LufsMeter meter_;
        double currentMakeupDb_ = 0.0;
        uint32_t lastGatedBlocks_ = 0U;
        std::array<float, kWorkerChunkElems> workerChunk_{};

        uint32_t sampleRate_ = kDefaultSampleRate;
        uint32_t maxFrames_ = kDefaultMaxFrames;

        // MUST be the last member: destroyed FIRST, so request_stop()+join() run
        // before the ring/meter it touches are torn down (reverse declaration order).
        std::jthread measurementThread_;
    };

} // namespace AdaptiveSound
#endif // LOUDNESS_MODULE_H
