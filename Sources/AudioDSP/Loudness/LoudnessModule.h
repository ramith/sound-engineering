#pragma once

// LoudnessModule — ITU-R BS.1770-5 gated loudness measurement + auto makeup gain.
//
// Chain position (DSPKernel.h):  EQ → Clarity → BRIR → Intensity blend → [Loudness] → Crossfeed
// → Limiter.
//
// Unlike the other modules, Loudness runs a MEASUREMENT FEEDBACK LOOP that must
// stay off the render thread:
//
//   RT process()  ──push samples──▶  SpscRing  ──▶  measurement jthread (LufsMeter)
//   RT process()  ◀──atomic float──  makeupGainLinear_  ◀──  measurement jthread
//
// The worker naps while audio flows and parks once none has come for a while (WorkerParking): while
// paused, with leveling off and on the bit-perfect path it wakes nobody (KI-UI-03).
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
#include "../include/WorkerParking.h"
#include "LufsMeter.h"
#include <array>
#include <atomic>
#include <AudioToolbox/AudioToolbox.h>
#include <cassert>
#include <chrono>
#include <cstdint>
#include <span>
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

    // The worker's nap while audio flows (its ring empties between render blocks), and how long it
    // finds nothing before it parks until the next block (WorkerParking: paused, leveling off, P0).
    inline constexpr std::chrono::milliseconds kWorkerNap{5};
    inline constexpr std::chrono::milliseconds kWorkerParkAfter{200};
    inline constexpr float kUnityGainLinear = 1.0F;
    inline constexpr float kLoudnessUnmeasuredLufs = -200.0F; // telemetry sentinel

    class LoudnessModule
    {
      public:
        LoudnessModule() = default;
        ~LoudnessModule(); // joins the measurement jthread (defined in the .cpp)

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
        //
        // `contribution` (optional, one weight in [0, 1] per frame) scales the makeup gain's
        // CONTRIBUTION in dB: the applied gain is makeup^w, so w = 1 is the full makeup and w = 0
        // is 0 dB. The kernel fades it with the Intensity blend (amendment 2: makeup·min(1, r/0.1)),
        // so the normalised blend and the normaliser-free EQ-only path meet at r = 0 with no step.
        void process(const LoudnessParams& params,
                     const MultichannelView& block,
                     std::span<const float> contribution = {}) noexcept;

        // Lock-free telemetry getters, callable from any thread. The null test's measurements read
        // them; the app does not (its loudness readout is the mixer tap's meter).
        [[nodiscard]] float measuredLufsIntegrated() const noexcept;
        [[nodiscard]] float measuredLufsShortTerm() const noexcept;
        [[nodiscard]] float measuredLufsMomentary() const noexcept;
        [[nodiscard]] float currentMakeupGainLinear() const noexcept;

      private:
        // RT: apply the smoothed (and optionally contribution-weighted) makeup gain in place.
        void applyMakeup(const MultichannelView& block,
                         uint32_t safeCount,
                         std::span<const float> contribution) noexcept;

        // Off-RT worker (runs on measurementThread_).
        void runMeasurementLoop(const std::stop_token& stopToken) noexcept;
        void updateMakeupGain(uint32_t newGatedBlocks) noexcept;
        void publishTelemetry() noexcept;

        // Data members are ordered by DESCENDING alignment (largest first) so the struct
        // packs with minimal padding (clang-analyzer optin.performance.Padding), with two
        // hard constraints that override pure size-optimality:
        //   1. sampleRing_ is first — SpscRing is cache-line aligned (alignas(64), false-
        //      sharing avoidance), so it drives the struct's 64-byte alignment; placing it
        //      at offset 0 wastes the least.
        //   2. measurementThread_ is LAST — it must be destroyed FIRST (request_stop()+join())
        //      so the worker stops before the ring/meter it touches are torn down (reverse
        //      declaration order). Role annotations are kept per-member below.

        // --- RT-owned lock-free ring (SPSC: RT producer → measurement worker consumer) ---
        SpscRing<float, kLoudnessRingElems> sampleRing_;

        // --- 8-byte-aligned members ---
        double currentMakeupDb_ = 0.0; // worker-owned (measurementThread_ only)
        WorkerParking parking_{kWorkerNap, kWorkerParkAfter}; // RT/control → worker wake-ups
        // Per-sample gain scratch and interleave scratch: heap-allocated to maxFrames_ (and
        // maxFrames_*kMaxChannels) in initialize() so they scale with the host's
        // maximumFramesToRender. process() asserts frameCount <= maxFrames_ and never
        // allocates. The SPSC ring and workerChunk_ are sized independently of maxFrames_.
        std::vector<float> rampBuf_; // maxFrames_ elements, heap-allocated in initialize()
        std::vector<float> pushBuf_; // maxFrames_ * kMaxChannels elements, ditto
        // Generation-parity double buffer for BS.1770-5 per-channel weights. Single-producer
        // (control thread via publishChannelLayout), single-consumer (measurement worker):
        //   publish: write into layoutWeights_[(gen+1) & 1], then release-store gen+1.
        //   consume: acquire-load gen; read from layoutWeights_[gen & 1].
        // The parity ensures the consumer always reads the buffer NOT being written (producer
        // increments gen with release AFTER the write; consumer sees the new gen with acquire).
        // No torn double-slot reads: exactly one producer and one consumer.
        std::array<std::array<double, kMaxChannels>, 2U> layoutWeights_{}; // double buffer
        LufsMeter meter_; // worker-owned (measurementThread_ only)

        // --- 4-byte-aligned members ---
        // Atomic hand-offs (asserted is_always_lock_free in the .cpp).
        std::atomic<float> makeupGainLinear_{kUnityGainLinear}; // worker→RT (audible)
        std::atomic<float> targetLufs_{kDefaultLufsTarget};     // RT→worker (control)
        std::atomic<uint32_t> channelCount_{2U};                // RT→worker (channel N)
        std::atomic<float> measuredLufsIntegrated_{kLoudnessUnmeasuredLufs}; // worker→UI
        std::atomic<float> measuredLufsShortTerm_{kLoudnessUnmeasuredLufs};  // worker→UI
        std::atomic<float> measuredLufsMomentary_{kLoudnessUnmeasuredLufs};  // worker→UI
        std::atomic<uint32_t> layoutGen_{0U};                                // control→worker
        uint32_t lastGatedBlocks_ = 0U;                                      // worker-owned
        uint32_t sampleRate_ = kDefaultSampleRate;
        uint32_t maxFrames_ = kDefaultMaxFrames;
        ParameterRamp makeupGainRamp_{};                     // RT-owned (3 floats)
        std::array<float, kWorkerChunkElems> workerChunk_{}; // worker-owned drain scratch

        // --- 1-byte-aligned member ---
        std::atomic<uint8_t> enabled_{1U}; // RT→worker (control)

        // --- RAII: MUST be the last member (destroyed first; see constraint 2 above) ---
        std::jthread measurementThread_;
    };

} // namespace AdaptiveSound
