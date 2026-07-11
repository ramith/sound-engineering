#pragma once

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

#include "../include/AudioConstants.h"
#include "../include/ChannelLayout.h"
#include "../include/MultichannelView.h"
#include "../include/ParameterRamp.h" // ParameterRamp (shared EQ/Loudness infra)
#include "../include/SpscRing.h"
#include "../include/TargetState.h"
#include "LufsMeter.h"
#include <array>
#include <atomic>
#include <AudioToolbox/AudioToolbox.h>
#include <cassert>
#include <cstdint>
#include <thread>
#include <vector>

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
    // two. Element count is frames × kMaxChannels so the same ring holds up to 7.1.
    inline constexpr std::size_t kLoudnessRingFrames = 32768U;
    inline constexpr std::size_t kLoudnessRingElems = kLoudnessRingFrames * kMaxChannels;

    // Worker drain chunk (interleaved elements per popBlock).
    inline constexpr std::size_t kWorkerChunkFrames = 1024U;
    inline constexpr std::size_t kWorkerChunkElems = kWorkerChunkFrames * kMaxChannels;

    inline constexpr int kWorkerIdleSleepMs = 5; // off-RT sleep when ring empty
    inline constexpr float kUnityGainLinear = 1.0F;
    inline constexpr float kLoudnessUnmeasuredLufs = -200.0F; // telemetry sentinel

    // Member order is constrained by RAII: measurementThread_ MUST be declared last
    // so it is destroyed (request_stop()+join()) before the ring/meter it touches.
    // That ordering prevents the size-optimal layout, but there is a single
    // long-lived instance, so the padding is irrelevant.
    // NOLINTNEXTLINE(clang-analyzer-optin.performance.Padding) PERMANENT reason="deliberate RT struct layout"
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

        // Off-RT (control thread only): publish per-channel BS.1770-5 weights decoded
        // from a ChannelLayout.  Lock-free; single producer.  The measurement worker
        // picks up the new weights on the next reconfigure check.  Safe to call before
        // or after initialize(); the worker ignores zero-gen until it first runs.
        void publishChannelLayout(const ChannelLayout& layout) noexcept;

        // RT: noexcept, zero alloc/lock. Relays params to the worker, pushes samples
        // (drop on full), and applies the smoothed makeup gain in place.
        void process(const LoudnessParams& params, const MultichannelView& block) noexcept;

        // Lock-free telemetry getters (UI / Milestone 4); callable from any thread.
        [[nodiscard]] float measuredLufsIntegrated() const noexcept;
        [[nodiscard]] float measuredLufsShortTerm() const noexcept;
        [[nodiscard]] float measuredLufsMomentary() const noexcept;
        [[nodiscard]] float currentMakeupGainLinear() const noexcept;
        [[nodiscard]] uint64_t droppedFrameCount() const noexcept;

      private:
        // Off-RT worker (runs on measurementThread_).
        void runMeasurementLoop(const std::stop_token& stopToken) noexcept;
        void updateMakeupGain(uint32_t newGatedBlocks) noexcept;
        void publishTelemetry() noexcept;

        // --- Atomic hand-offs (asserted is_always_lock_free in the .mm) ---
        std::atomic<float> makeupGainLinear_{kUnityGainLinear}; // worker→RT (audible)
        std::atomic<float> targetLufs_{kDefaultLufsTarget};     // RT→worker (control)
        std::atomic<uint8_t> enabled_{1U};                      // RT→worker (control)
        std::atomic<uint32_t> channelCount_{2U};                // RT→worker (channel N)
        std::atomic<float> measuredLufsIntegrated_{kLoudnessUnmeasuredLufs}; // worker→UI
        std::atomic<float> measuredLufsShortTerm_{kLoudnessUnmeasuredLufs};  // worker→UI
        std::atomic<float> measuredLufsMomentary_{kLoudnessUnmeasuredLufs};  // worker→UI
        std::atomic<uint64_t> droppedFrames_{0U};                            // RT→diagnostics

        // --- Generation-parity double buffer for BS.1770-5 per-channel weights ---
        //
        // Single-producer (control thread via publishChannelLayout), single-consumer
        // (measurement worker via runMeasurementLoop).  Protocol:
        //   publish: write into layoutWeights_[(gen+1) & 1], then release-store gen+1.
        //   consume: acquire-load gen; read from layoutWeights_[gen & 1].
        // The parity ensures the consumer always reads from the buffer that is NOT
        // being written: the producer increments gen AFTER the write is complete
        // (release), so the consumer only sees the new gen after the write has
        // propagated (acquire).  No torn double-slot reads are possible because there
        // is exactly one producer and one consumer.
        std::atomic<uint32_t> layoutGen_{0U};                              // control→worker
        std::array<std::array<double, kMaxChannels>, 2U> layoutWeights_{}; // double buffer

        // --- RT-owned state ---
        SpscRing<float, kLoudnessRingElems> sampleRing_;
        ParameterRamp makeupGainRamp_{};
        // Per-sample gain scratch and interleave scratch: heap-allocated to
        // maxFrames_ (and maxFrames_*kMaxChannels) in initialize() so they scale
        // with the host's maximumFramesToRender. process() asserts frameCount <=
        // maxFrames_ and never allocates. The SPSC ring and workerChunk_ are sized
        // independently of maxFrames_ and are not affected by this change.
        std::vector<float> rampBuf_; // maxFrames_ elements, heap-allocated in initialize()
        std::vector<float>
            pushBuf_; // maxFrames_ * kMaxChannels elements, heap-allocated in initialize()

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
