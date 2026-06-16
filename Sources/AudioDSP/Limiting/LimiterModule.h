#ifndef LIMITER_MODULE_H
#define LIMITER_MODULE_H

// LimiterModule — True-peak lookahead limiter
//
// Architecture
// ============
// This is the final stage of the signal chain (see DSPKernel.h):
//   EQ → Clarity → BRIR → Loudness → [Limiter] → Device Output
//
// The limiter enforces a true-peak ceiling (default −1 dBTP) using three
// mechanisms that together give transparent, zero-artifact peak control:
//
//   1. Lookahead delay (2 ms / 96 frames @ 48 kHz)
//      Input samples are written into a per-channel ring buffer of size
//      kLimiterRingSize = kLimiterLookaheadFrames + kDefaultMaxFrames.
//      The ring is large enough that writing a full block of new input never
//      overlaps the lookahead window of delayed output that is simultaneously
//      being read back.  The write head always stays kLimiterLookaheadFrames
//      ahead of the read head.
//
//      This gives the gain envelope time to ramp up BEFORE the transient peak
//      arrives at the output — all audible clipping is eliminated even on hard
//      transients.  At a 0.5 ms attack (5τ ≈ 2.5 ms) a 2 ms lookahead lets the
//      envelope reach ~98 % of target before the peak emerges.
//
//   2. Inter-sample (true-peak) detection with ≥4× oversampling
//      For each newly written sample the GR sidechain evaluates the 4×
//      upsampled (linear-interpolated) peak of the newest adjacent sample pair
//      and feeds it into a sliding-window maximum (see #3).
//      Reference: ITU-R BS.1770-5 §3 true-peak measurement.
//
//      NOTE (MVP): linear interpolation under-reads the true inter-sample peak
//      by up to ~0.5–0.8 dB vs a proper polyphase FIR upsampler.  To stay safe
//      we apply an additional −0.5 dB margin (kIspSafetyMargin) to the working
//      ceiling.  A polyphase FIR ISP detector is a planned follow-up.
//
//   3. Sliding-window peak + sample-accurate linear-gain smoothing
//      The peak driving gain reduction is the maximum 4×-ISP pair-peak over the
//      kLimiterLookaheadFrames-sample lookahead window.  It is maintained
//      incrementally with a monotonic deque (amortized O(1) per sample) instead
//      of rescanning the whole window every sample.  The per-sample gain is then
//      smoothed with an RC-exact one-pole (JOS §1.3.1) directly in the LINEAR
//      gain domain — no per-sample log10/exp — and applied via vDSP_vmul.  This
//      eliminates zipper noise on buffer boundaries and the per-sample
//      transcendentals of a dB-domain implementation.
//
// Ring Layout (per channel)
// ========================
//              [read head]                      [write head]
//              |                                |
//   ... old .. R .... kLimiterLookaheadFrames .. W ... new ...
//
//   writeHead = (readHead + kLimiterLookaheadFrames) % kLimiterRingSize
//
//   At initialize() the ring is zeroed and:
//     readHead_  = 0
//     writeHead_ = kLimiterLookaheadFrames   (pre-filled with zeros)
//
//   process() advances both heads by frameCount each call.
//
// RT-Safety
// =========
// process() is fully noexcept: no allocation, no free, no OS calls, no locks.
// All buffers (ring, GR ramp scratch, peak deque) are pre-allocated in
// initialize().  Attack and release coefficients are computed off-RT in
// initialize() and are never modified from the render thread.
//
// Parameters (from LimiterParams, published via DoubleBufferSnapshot)
// ===================================================================
//   truePeakCeilingLinear  — ceiling in linear scale; default 0.891 (−1 dBTP).
//                            Set to ≥ 1.0 to bypass gain reduction entirely.
//                            process() returns immediately for a zero-latency
//                            identity passthrough in that case.
//
// Math
// ====
// One-pole gain smoother (per sample, LINEAR gain domain):
//   ceiling_w   = truePeakCeilingLinear · kIspSafetyMargin       (−0.5 dB margin)
//   g_target[n] = (peak[n] > ceiling_w) ? ceiling_w / peak[n] : 1   (≤ 1)
//   if g_target < g[n-1]  (more reduction → attack):
//        g[n] = g[n-1] + α_a·(g_target − g[n-1])
//   else                  (release):
//        g[n] = g[n-1] + α_r·(g_target − g[n-1])
//
//   α = 1 − exp(−1 / (τ · fs))   (RC-exact discrete-time pole; JOS §1.3.1)
//   τ_attack  = 0.5 ms  → α_a ≈ 0.040 @ 48 kHz
//   τ_release = 100 ms  → α_r ≈ 0.000208 @ 48 kHz
//
// References
// ==========
// - Julius O. Smith III, "Introduction to Digital Filters", §1.3.1 (one-pole RC)
//   https://ccrma.stanford.edu/~jos/filters/
// - ITU-R BS.1770-5 §3 (true-peak / inter-sample peak measurement)
// - Reiss & McPherson, "Audio Effects: Theory, Implementation and Application",
//   ch. 4 (dynamics processing)
// - Zölzer (ed.), "DAFX: Digital Audio Effects", ch. 3 (limiting / companding)

#include "../include/AudioConstants.h"
#include "../include/TargetState.h"
#include <Accelerate/Accelerate.h>
#include <array>
#include <AudioToolbox/AudioToolbox.h>
#include <cmath>
#include <cstdint>

namespace AdaptiveSound
{

    // ---------------------------------------------------------------------------
    // Module-local constants
    // ---------------------------------------------------------------------------

    // Attack: 0.5 ms — fast enough to catch transients without audible pre-emphasis
    static constexpr float kLimiterAttackMs = 0.5F;
    // Release: 100 ms — slow enough for transparency, fast enough for recovery
    static constexpr float kLimiterReleaseMs = 100.0F;
    // Milliseconds → seconds (one-pole τ is specified in ms; fs is in Hz).
    static constexpr float kMillisToSeconds = 0.001F;

    // Inter-sample oversampling factor for peak detection (≥4 per spec).
    // We use 4×: insert (kISPOversamplingFactor − 1) linearly interpolated midpoints
    // between each pair of adjacent samples → fractions 0.25, 0.50, 0.75.
    static constexpr uint32_t kISPOversamplingFactor = 4U;

    // Extra headroom on the working ceiling to cover linear-interpolation ISP
    // underestimation (~0.5–0.8 dB worst case).  −0.5 dB = 10^(−0.5/20) ≈ 0.94406.
    // The user still sees/sets the nominal ceiling; this margin is applied internally.
    static constexpr float kIspSafetyMargin = 0.94406087F;

    // Maximum channels handled (stereo)
    static constexpr uint32_t kLimiterMaxChannels = 2U;

    // Ring size: must hold the lookahead window PLUS a full maximum-size block so
    // the write head never collides with the read head during a single process() call.
    //   kLimiterRingSize = kLimiterLookaheadFrames + kDefaultMaxFrames = 96 + 512 = 608
    static constexpr uint32_t kLimiterRingSize = kLimiterLookaheadFrames + kDefaultMaxFrames;

    // Monotonic-deque capacity for the sliding-window peak.  The window spans
    // kLimiterLookaheadFrames pair-peaks; the deque holds at most that many
    // entries, plus one transient slot needed between push-back and front-evict.
    static constexpr uint32_t kPeakDequeCapacity = kLimiterLookaheadFrames + 1U;

    class LimiterModule
    {
      public:
        LimiterModule() = default;
        ~LimiterModule() = default;

        // Non-copyable, non-movable (owns pre-allocated state arrays)
        LimiterModule(const LimiterModule&) = delete;
        LimiterModule& operator=(const LimiterModule&) = delete;
        LimiterModule(LimiterModule&&) = delete;
        LimiterModule& operator=(LimiterModule&&) = delete;

        // -----------------------------------------------------------------------
        // initialize() — call from the control thread before the first process()
        // call, and again whenever the sample rate changes.  Always off-RT.
        // -----------------------------------------------------------------------
        void initialize(uint32_t sampleRate, uint32_t maxFrames) noexcept
        {
            sampleRate_ = sampleRate;
            maxFrames_ = maxFrames;

            // RC-exact one-pole coefficients: α = 1 − exp(−1/(τ·fs))  (JOS §1.3.1)
            const float fs = static_cast<float>(sampleRate);
            attackCoeff_ = 1.0F - std::exp(-1.0F / ((kLimiterAttackMs * kMillisToSeconds) * fs));
            releaseCoeff_ = 1.0F - std::exp(-1.0F / ((kLimiterReleaseMs * kMillisToSeconds) * fs));

            // Zero ring buffers
            leftRing_.fill(0.0F);
            rightRing_.fill(0.0F);

            // Write head starts kLimiterLookaheadFrames ahead of read head.
            // The gap of kLimiterLookaheadFrames zero-filled samples acts as the
            // initial silence prefix — no separate prime step is needed.
            readHead_ = 0U;
            writeHead_ = kLimiterLookaheadFrames;

            // Reset gain state, scratch, and the sliding-window peak deque
            gainLinear_ = 1.0F;
            grBuf_.fill(0.0F);
            dequeHead_ = 0U;
            dequeCount_ = 0U;
            sampleCounter_ = 0U;
        }

        // -----------------------------------------------------------------------
        // process() — RT-safe; noexcept; no allocation.
        //
        // Processes the AudioBufferList in-place.  Expects non-interleaved stereo
        // (mBuffers[0] = left, mBuffers[1] = right); mono (mBuffers==1) works too.
        //
        // Bypass mode (truePeakCeilingLinear ≥ 1.0):
        //   Returns immediately — zero-latency bit-exact passthrough.
        //   Used by makeIdentityState() in the null tests (ceiling = 2.0).
        //
        // Active mode signal flow per call (safeCount = min(frameCount, kDefaultMaxFrames)):
        //   For each sample i in [0, safeCount):
        //     1. Write leftBuf[i] (and rightBuf[i]) into the ring at writeHead_
        //     2. Compute the 4×-ISP peak of the newest adjacent sample pair and
        //        push it into the monotonic deque; the deque front is the max over
        //        the kLimiterLookaheadFrames-sample lookahead window
        //     3. Compute linear gain target; advance one-pole smoother; store grBuf_[i]
        //     4. Advance writeHead_
        //   Then:
        //     5. Read safeCount delayed samples starting at readHead_ into the
        //        output buffers (one or two memcpy-style segments)
        //     6. Apply grBuf_ via vDSP_vmul
        //     7. Advance readHead_
        // -----------------------------------------------------------------------
        void
        process(const LimiterParams& params, AudioBufferList* ioData, uint32_t frameCount) noexcept
        {
            if (ioData == nullptr || frameCount == 0U)
            {
                return;
            }

            const uint32_t numChannels = ioData->mNumberBuffers >= kLimiterMaxChannels
                                             ? kLimiterMaxChannels
                                             : ioData->mNumberBuffers;
            if (numChannels == 0U)
            {
                return;
            }

            float* leftBuf = static_cast<float*>(ioData->mBuffers[0].mData);
            float* rightBuf =
                (numChannels >= 2U) ? static_cast<float*>(ioData->mBuffers[1].mData) : nullptr;
            if (leftBuf == nullptr)
            {
                return;
            }

            // Bypass: ceiling ≥ 1.0 → zero-latency identity.
            if (params.truePeakCeilingLinear >= 1.0F)
            {
                return;
            }

            // Safety clamp: never overrun the pre-allocated scratch/ring buffers.
            // kLimiterRingSize and grBuf_ are sized for kDefaultMaxFrames; enforce it.
            const uint32_t safeCount = std::min(frameCount, kDefaultMaxFrames);

            // Working ceiling with the inter-sample safety margin applied.
            const float workingCeiling = params.truePeakCeilingLinear * kIspSafetyMargin;

            // -----------------------------------------------------------------
            // Per-sample loop: write input, update sliding-window peak, smooth gain
            // -----------------------------------------------------------------
            for (uint32_t i = 0U; i < safeCount; ++i)
            {
                // 1. Write new input sample into ring
                leftRing_[writeHead_] = leftBuf[i];
                if (rightBuf != nullptr)
                {
                    rightRing_[writeHead_] = rightBuf[i];
                }

                // 2. 4×-ISP peak of the newest adjacent pair (current, previous),
                //    combined across channels, fed into the sliding-window max.
                const uint32_t prev = (writeHead_ + kLimiterRingSize - 1U) % kLimiterRingSize;
                float pairPeak = ispPairPeak(leftRing_[writeHead_], leftRing_[prev]);
                if (rightBuf != nullptr)
                {
                    pairPeak =
                        std::max(pairPeak, ispPairPeak(rightRing_[writeHead_], rightRing_[prev]));
                }
                const float peak = updatePeakDeque(pairPeak);

                // 3. Linear gain target + one-pole smoothing (attack when reducing).
                const float gainTarget = (peak > workingCeiling) ? (workingCeiling / peak) : 1.0F;
                const float coeff = (gainTarget < gainLinear_) ? attackCoeff_ : releaseCoeff_;
                gainLinear_ += coeff * (gainTarget - gainLinear_);
                grBuf_[i] = gainLinear_;

                // 4. Advance write head
                writeHead_ = (writeHead_ + 1U) % kLimiterRingSize;
            }

            // -----------------------------------------------------------------
            // 5. Extract delayed output from ring (at readHead_) and overwrite
            //    the input buffers.  readHead_ is kLimiterLookaheadFrames behind
            //    writeHead_ — those samples were written kLimiterLookaheadFrames
            //    frames ago and represent the audio to output NOW.
            // -----------------------------------------------------------------
            fillOutputFromRing(leftBuf, leftRing_.data(), safeCount);
            if (rightBuf != nullptr)
            {
                fillOutputFromRing(rightBuf, rightRing_.data(), safeCount);
            }

            // 6. Apply per-sample gain envelope
            const vDSP_Length count = static_cast<vDSP_Length>(safeCount);
            vDSP_vmul(leftBuf, 1, grBuf_.data(), 1, leftBuf, 1, count);
            if (rightBuf != nullptr)
            {
                vDSP_vmul(rightBuf, 1, grBuf_.data(), 1, rightBuf, 1, count);
            }

            // 7. Advance read head
            readHead_ = (readHead_ + safeCount) % kLimiterRingSize;
        }

      private:
        // -----------------------------------------------------------------------
        // ispPairPeak() — return the 4× ISP true-peak for a single adjacent
        // sample pair (sampleA, sampleB) using linear interpolation.
        //
        // Evaluates: |sampleA|, |sampleB|, and (kISPOversamplingFactor − 1) = 3
        // linearly interpolated midpoints at fractions 0.25/0.50/0.75.  Returns
        // the maximum absolute value found.  Pure function, no side effects.
        //
        // Reference: ITU-R BS.1770-5 Annex 1; Zölzer DAFX 3rd ed. §3.3.1.
        // -----------------------------------------------------------------------
        [[nodiscard]] static auto ispPairPeak(float sampleA, float sampleB) noexcept -> float
        {
            static constexpr float kStep = 1.0F / static_cast<float>(kISPOversamplingFactor);
            static constexpr uint32_t kNumMidpoints = kISPOversamplingFactor - 1U;

            const float diff = sampleB - sampleA;
            float peak = std::max(std::abs(sampleA), std::abs(sampleB));
            for (uint32_t k = 1U; k <= kNumMidpoints; ++k)
            {
                const float fraction = static_cast<float>(k) * kStep;
                peak = std::max(peak, std::abs(sampleA + (fraction * diff)));
            }
            return peak;
        }

        // -----------------------------------------------------------------------
        // updatePeakDeque() — push one pair-peak for the current sample and return
        // the maximum over the trailing kLimiterLookaheadFrames-sample window.
        //
        // Classic monotonic-deque sliding-window maximum: amortized O(1) per sample.
        // The deque holds (index, value) entries with strictly decreasing values;
        // the front is always the window maximum.  Backed by a fixed circular
        // array (kPeakDequeCapacity) — no allocation.
        //
        // Index arithmetic uses the additive form (front.index + window <= counter)
        // to avoid unsigned underflow during the warm-up phase.
        // -----------------------------------------------------------------------
        [[nodiscard]] auto updatePeakDeque(float value) noexcept -> float
        {
            // Evict smaller-or-equal entries from the back (maintain monotonicity).
            while (dequeCount_ > 0U)
            {
                const uint32_t backPos = (dequeHead_ + dequeCount_ - 1U) % kPeakDequeCapacity;
                if (peakDeque_[backPos].value <= value)
                {
                    --dequeCount_;
                }
                else
                {
                    break;
                }
            }

            // Push the new (index, value) at the back.
            const uint32_t pushPos = (dequeHead_ + dequeCount_) % kPeakDequeCapacity;
            peakDeque_[pushPos] = {.index = sampleCounter_, .value = value};
            ++dequeCount_;

            // Evict the front while it has fallen out of the trailing window.
            while (dequeCount_ > 0U &&
                   peakDeque_[dequeHead_].index + kLimiterLookaheadFrames <= sampleCounter_)
            {
                dequeHead_ = (dequeHead_ + 1U) % kPeakDequeCapacity;
                --dequeCount_;
            }

            const float windowMax = peakDeque_[dequeHead_].value;
            ++sampleCounter_;
            return windowMax;
        }

        // -----------------------------------------------------------------------
        // fillOutputFromRing() — copy safeCount samples from the ring starting at
        // readHead_ into dst[], overwriting it.  Splits into one or two segments
        // to handle the ring wrap without per-sample modular arithmetic.
        // -----------------------------------------------------------------------
        void fillOutputFromRing(float* dst, const float* ring, uint32_t safeCount) const noexcept
        {
            const uint32_t toEnd = kLimiterRingSize - readHead_;

            if (safeCount <= toEnd)
            {
                for (uint32_t i = 0U; i < safeCount; ++i)
                {
                    dst[i] = ring[readHead_ + i];
                }
            }
            else
            {
                for (uint32_t i = 0U; i < toEnd; ++i)
                {
                    dst[i] = ring[readHead_ + i];
                }
                const uint32_t remaining = safeCount - toEnd;
                for (uint32_t i = 0U; i < remaining; ++i)
                {
                    dst[toEnd + i] = ring[i];
                }
            }
        }

        // -----------------------------------------------------------------------
        // State — all pre-allocated; no heap in process()
        // -----------------------------------------------------------------------

        // Sliding-window peak deque entry: (sample index, ISP pair-peak value).
        struct PeakEntry
        {
            uint64_t index = 0U;
            float value = 0.0F;
        };

        // Ring buffers: lookahead window + one full max-size block.
        // kLimiterRingSize = kLimiterLookaheadFrames + kDefaultMaxFrames = 96 + 512 = 608.
        std::array<float, kLimiterRingSize> leftRing_{};
        std::array<float, kLimiterRingSize> rightRing_{};

        // Read head: position of the oldest sample to output (lags writeHead_ by
        // kLimiterLookaheadFrames).
        uint32_t readHead_ = 0U;
        // Write head: position where the next input sample will be written.
        uint32_t writeHead_ = kLimiterLookaheadFrames;

        // Running linear gain (≤ 1.0). Persists across calls. 1.0 = no reduction.
        float gainLinear_ = 1.0F;

        // One-pole smoother coefficients (computed in initialize(), never on RT thread)
        float attackCoeff_ = 0.0F;
        float releaseCoeff_ = 0.0F;

        // Per-sample gain envelope scratch (pre-allocated to kDefaultMaxFrames = 512)
        std::array<float, kDefaultMaxFrames> grBuf_{};

        // Monotonic-deque sliding-window peak state (circular buffer).
        std::array<PeakEntry, kPeakDequeCapacity> peakDeque_{};
        uint32_t dequeHead_ = 0U;     // index of the front entry
        uint32_t dequeCount_ = 0U;    // number of live entries
        uint64_t sampleCounter_ = 0U; // monotonically increasing sample index

        uint32_t sampleRate_ = kDefaultSampleRate;
        uint32_t maxFrames_ = kDefaultMaxFrames;
    };

} // namespace AdaptiveSound
#endif // LIMITER_MODULE_H
