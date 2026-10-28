#pragma once

// SpatialRenderKernel — host-agnostic C++ DSP core for SpatialRendererAU, the device-boundary stage.
//
// Topology:
//   The AdaptiveSoundAU / DSPKernel is the N->N effects unit (in place on the source channels). This
//   kernel is a SEPARATE device-boundary stage that maps the N source channels to the M device channels.
//   It is NOT in place: input and output are distinct buffer sets with (potentially) different channel
//   counts. The AU wrapper (SpatialRendererAU) and the graph wiring drive it.
//
// Routes (chosen per block from configure()'s N and M):
//   M >= N        — identity: source channel ch -> device channel ch for ch in [0, N), device channels
//                   [N, M) zero. vDSP_mmov per channel: BIT-EXACT. No fold, no backstop.
//   M < N, N > 2  — the interim fold (R1.1-B, level-and-fold §S1b/§S2/M1; architecture §7 "The fold"):
//                   L′/R′ = the per-track FoldParams' BS.775 rows (the LFE variant's gain included) × the
//                   per-track trim, ramped per sample at a change; then the BACKSTOP — a true-peak limiter
//                   (the effects chain's LimiterModule, reused unchanged: its own 3 ms look-ahead, the
//                   ceiling by scope, linked gain) that the trim keeps asleep; its gain reduction is
//                   metered. M is 2 by the device-width rule (deviceWidthFormat); any device channel past
//                   L′ and R′ is zero.
//   M < N, N <= 2 — a stereo source on a mono device: the first M channels (today's behaviour; no fold).
//
// The fold's parameters:
//   - `publishFold` (off-RT, any control thread; serialized by a producer-side mutex the render never
//     touches) hands a FoldParams to the render through a TripleBufferSnapshot, copied once per block: the
//     layout's fold when the graph is configured for a file (its matrix at the worst-case trim, NEVER trim
//     0 — M1), then the playing track's plan. The newest set plays; it is kept across an allocate
//     (keep-across-allocate, M1) and plays only at the width it was made for. With no set for this width
//     the fold plays silence: the device boundary never truncates.
//   - A change glides linearly over the set's `glideSeconds` (0: snap), per sample, from the coefficients
//     in force; a change of N or M (configure) snaps.
//
// RT-safety contract:
//   process() is REAL-TIME SAFE: no allocation, no lock, no syscall, no Obj-C runtime. All scratch,
//   the backstop's rings and the meter's ring are sized in initialize() (off-RT). Flush-to-zero is set
//   for the call only (ScopedFlushToZero).
//
// No Obj-C, no AVFoundation, no AudioUnit object — host-agnostic. (The reused LimiterModule includes the
// AudioToolbox C headers for its types, as DSPKernel does.)

#include "../include/AudioConstants.h"
#include "../include/MultichannelView.h"
#include "../include/TripleBufferSnapshot.h"
#include "../Limiting/LimiterModule.h"
#include <array>
#include <atomic>
#include <cstdint>
#include <mutex>
#include <vector>

namespace AdaptiveSound
{

    // The fold's per-track parameters (level-and-fold §8 M1): what the plan sends the spatial unit.
    // Trivially copyable and one cache line apart, like TargetState (it rides a TripleBufferSnapshot).
    struct alignas(kCacheLineBytes) FoldParams
    {
        // The source width this fold is for; 0 = none. A fold for another width is never played.
        uint32_t inChannels = 0U;
        // The two output rows (0 = L′, 1 = R′): a gain per source slot, the LFE variant's gain included.
        std::array<std::array<float, kMaxChannels>, 2> rows{};
        // The per-track trim, dB (≤ 0): min(0, C_work − TP_F[v]), or the matrix's worst case.
        float trimDb = 0.0F;
        // The LFE's gain per side in `rows` (0 = omitted), for the read-out.
        float lfeGain = 0.0F;
        // The backstop's ceiling by scope (linear): −0.1 dBTP lossless at the engine rate, else −1 dBTP.
        float ceilingLinear = kTruePeakCeilingLinear;
        // How long a change glides, in seconds (0: snap — a fresh start).
        float glideSeconds = 0.0F;
        // Numbered by publishFold (callers leave it 0): a new number is a new fold for the render.
        uint32_t generation = 0U;
        // The playing track's plan; false: the layout's fold at its worst-case trim (no plan yet).
        bool fromPlan = false;
    };

    // What the fold plays now, for the read-out (off-RT, any thread; from atomics).
    struct FoldReadout
    {
        uint32_t sourceChannels = 0U;
        uint32_t outputChannels = 0U;
        bool folding = false;  // M < N with N > 2
        bool fromPlan = false; // false: the layout's worst-case fold (no plan yet)
        float trimDb = 0.0F;
        float lfeGain = 0.0F;
        float backstopPeakGrDb =
            0.0F; // ≥ 0: the deepest backstop gain reduction since this fold began
    };

    class SpatialRenderKernel
    {
      public:
        SpatialRenderKernel() = default;
        ~SpatialRenderKernel() = default;

        SpatialRenderKernel(const SpatialRenderKernel&) = delete;
        auto operator=(const SpatialRenderKernel&) -> SpatialRenderKernel& = delete;
        SpatialRenderKernel(SpatialRenderKernel&&) = delete;
        auto operator=(SpatialRenderKernel&&) -> SpatialRenderKernel& = delete;

        // Off-RT: the rate and per-call frame ceiling. Sizes the backstop and its meter (the only
        // allocations). Safe to call again on a rate or buffer-size change; leaves FPCR alone.
        auto initialize(uint32_t sampleRate, uint32_t maxFramesToRender) noexcept -> void;

        // Off-RT: the routing — N source channels, M device channels (each clamped to kMaxChannels).
        // Call whenever the bus formats change (allocate). The published fold is kept; the next block
        // snaps to it if it is for this N.
        auto configure(uint32_t numInChannels, uint32_t numOutChannels) noexcept -> void;

        // Off-RT, any control thread: the fold for the next blocks (the layout's, or the plan's). False —
        // nothing changes — when any of its values is not finite.
        [[nodiscard]] auto publishFold(const FoldParams& fold) noexcept -> bool;

        // RT: process one block. NON-IN-PLACE: `input` (N channels) and `output` (M channels) must be
        // different buffer sets (vDSP_mmov is undefined for overlapping regions).
        // Preconditions checked by early return (RT-safe): equal non-zero frame counts within the
        // initialize() ceiling; a zero-channel route renders silence.
        auto process(const MultichannelView& input, const MultichannelView& output) noexcept
            -> void;

        // Off-RT, any thread: what the fold plays now.
        [[nodiscard]] auto readout() const noexcept -> FoldReadout;

        [[nodiscard]] auto inChannels() const noexcept -> uint32_t
        {
            return inChannels_;
        }
        [[nodiscard]] auto outChannels() const noexcept -> uint32_t
        {
            return outChannels_;
        }
        [[nodiscard]] auto maxFrames() const noexcept -> uint32_t
        {
            return maxFrames_;
        }

      private:
        // One fold's coefficients: rows × the trim's linear gain.
        using Coefficients = std::array<std::array<float, kMaxChannels>, 2>;

        auto foldBlock(const MultichannelView& input,
                       const MultichannelView& output,
                       uint32_t frames) noexcept -> void;
        auto adoptFold(const FoldParams& fold, bool snap) noexcept -> void;
        auto mixRamped(const MultichannelView& input,
                       const MultichannelView& output,
                       uint32_t frames) noexcept -> uint32_t;
        auto mixSteady(const MultichannelView& input,
                       const MultichannelView& output,
                       uint32_t from,
                       uint32_t frames) const noexcept -> void;
        auto runBackstop(const MultichannelView& output, uint32_t frames) noexcept -> void;

        // Ordered by alignment (the cache-line-aligned snapshot and fold first), so nothing pads.

        // The fold: published off-RT (producer mutex), copied once per block on-RT.
        TripleBufferSnapshot<FoldParams> published_;
        // RT: the last copied snapshot.
        FoldParams latest_{};

        // The backstop's meter: a copy of the limiter's input delayed by its look-ahead, so the gain it
        // applied is output ÷ delayed input.
        std::array<std::vector<float>, 2> meterRing_{};
        std::mutex publishMutex_; // producer side only: two control threads never publish at once
        // The backstop: the limiter on L′/R′.
        LimiterModule backstop_;

        // RT: the fold's coefficients in force this sample, where a glide ends, and its per-sample step.
        Coefficients coeff_{};
        Coefficients target_{};
        Coefficients step_{};
        LimiterParams backstopParams_{};

        // Routing — written off-RT by configure(), read on-RT (the v3 contract orders allocate before
        // render).
        uint32_t inChannels_ = 0U;
        uint32_t outChannels_ = 0U;
        uint32_t sampleRate_ = kDefaultSampleRate;
        uint32_t maxFrames_ = kDefaultMaxFrames;
        uint32_t publishCount_ = 0U;      // producer-owned, under publishMutex_
        uint32_t appliedGeneration_ = 0U; // RT: which publish is in force (0: none)
        uint32_t glideLeft_ = 0U;         // RT
        uint32_t meterLookahead_ = 0U;
        uint32_t meterHead_ = 0U; // RT
        float peakGrDb_ = 0.0F;   // RT-owned; mirrored into readoutPeakGrDb_

        // Read-out atomics (RT writes on change, any thread reads).
        std::atomic<float> readoutPeakGrDb_{0.0F};
        std::atomic<float> readoutTrimDb_{0.0F};
        std::atomic<float> readoutLfeGain_{0.0F};
        std::atomic<uint32_t> readoutIn_{0U};
        std::atomic<uint32_t> readoutOut_{0U};

        bool needsSnap_ = true; // set by configure(): the next fold snaps
        bool haveFold_ = false; // RT: a fold for this N is in force
        std::atomic<bool> readoutFromPlan_{false};
    };

} // namespace AdaptiveSound
