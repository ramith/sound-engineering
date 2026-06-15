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
//   1. Lookahead delay (1 ms / 48 frames @ 48 kHz)
//      Input samples are written into a per-channel ring buffer of size
//      kLimiterRingSize = kLimiterLookaheadFrames + kDefaultMaxFrames.
//      The ring is large enough that writing a full 512-frame block of new
//      input never overlaps the 48-frame window of delayed output that is
//      simultaneously being read back.  The write head always stays
//      kLimiterLookaheadFrames ahead of the read head.
//
//      This gives the gain-reduction envelope time to ramp up BEFORE the
//      transient peak arrives at the output — all audible clipping is
//      eliminated even on hard transients.
//
//   2. Inter-sample (true-peak) detection with ≥4× oversampling
//      After each new sample is written to the ring, the GR sidechain
//      scans a kLimiterLookaheadFrames-sample lookahead window ahead of
//      the write head at 4× upsampled resolution using linear interpolation
//      between adjacent samples (3 midpoints per pair).  This catches
//      inter-sample peaks that exceed the ceiling even though the sample
//      values themselves are below it.
//      Reference: ITU-R BS.1770-5 §3 true-peak measurement.
//
//   3. Sample-accurate gain reduction with one-pole attack/release smoothing
//      Gain reduction (GR) is maintained as a per-sample running value using
//      an RC-exact one-pole smoother (JOS §1.3.1).  The per-sample GR
//      envelope is materialized into grBuf_ then applied via vDSP_vmul.
//      This eliminates zipper noise on buffer boundaries and prevents the
//      "pumping/breathing" that a block-level gain scalar would cause.
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
// All buffers (ring, GR ramp scratch) are pre-allocated in initialize().
// Attack and release coefficients are computed off-RT in initialize() and are
// never modified from the render thread.
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
// One-pole GR smoother (per sample):
//   GR_target[n] = max(0, peakDbfs − ceilingDbfs)      [non-negative dB]
//   if GR_target > GR_current:  GR[n] = GR[n-1] + α_a·(GR_target − GR[n-1])
//   else:                        GR[n] = GR[n-1] + α_r·(GR_target − GR[n-1])
//
//   α = 1 − exp(−1 / (τ · fs))   (RC-exact discrete-time pole; JOS §1.3.1)
//   τ_attack  = 0.5 ms  → α_a ≈ 0.064 @ 48 kHz
//   τ_release = 100 ms  → α_r ≈ 0.000208 @ 48 kHz
//
// Output gain per sample:
//   gain[n] = 10^(−GR[n] / 20)  = exp(−GR[n] · ln(10)/20)
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

namespace AdaptiveSound
{

    // ---------------------------------------------------------------------------
    // Module-local constants
    // ---------------------------------------------------------------------------

    // Attack: 0.5 ms — fast enough to catch transients without audible pre-emphasis
    static constexpr float kLimiterAttackMs = 0.5F;
    // Release: 100 ms — slow enough for transparency, fast enough for recovery
    static constexpr float kLimiterReleaseMs = 100.0F;

    // Inter-sample oversampling factor for peak detection (≥4 per spec).
    // We use 4×: insert (kISPOversamplingFactor − 1) linearly interpolated midpoints
    // between each pair of adjacent samples in the lookahead window.
    // Fractions: k / kISPOversamplingFactor for k = 1…(factor-1) → 0.25, 0.50, 0.75
    static constexpr uint32_t kISPOversamplingFactor = 4U;

    // ln(10)/20 — used in the per-sample dB→linear conversion: gain = exp(−GR·kLn10Over20)
    static constexpr float kLn10Over20 = 0.11512925464970228F;

    // Maximum channels handled (stereo)
    static constexpr uint32_t kLimiterMaxChannels = 2U;

    // Ring size: must hold the lookahead window PLUS a full maximum-size block so
    // the write head never collides with the read head during a single process() call.
    //   kLimiterRingSize = kLimiterLookaheadFrames + kDefaultMaxFrames
    //                    = 48 + 512 = 560
    static constexpr uint32_t kLimiterRingSize = kLimiterLookaheadFrames + kDefaultMaxFrames;

    class LimiterModule
    {
      public:
        LimiterModule() = default;

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
            attackCoeff_ = 1.0F - std::exp(-1.0F / ((kLimiterAttackMs * 0.001F) * fs));
            releaseCoeff_ = 1.0F - std::exp(-1.0F / ((kLimiterReleaseMs * 0.001F) * fs));

            // Zero ring buffers
            leftRing_.fill(0.0F);
            rightRing_.fill(0.0F);

            // Write head starts kLimiterLookaheadFrames ahead of read head.
            // The gap of kLimiterLookaheadFrames zero-filled samples acts as the
            // initial silence prefix — no separate prime step is needed.
            readHead_ = 0U;
            writeHead_ = kLimiterLookaheadFrames;

            // Zero GR state and scratch
            gainReductionDb_ = 0.0F;
            grBuf_.fill(0.0F);
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
        //     2. Scan a kLimiterLookaheadFrames window starting at writeHead_+1
        //        (the lookahead window ahead of the current read position)
        //        at 4× ISP resolution (linear-interpolated midpoints)
        //     3. Compute GR target; advance one-pole smoother; store grBuf_[i]
        //     4. Advance writeHead_
        //   Then:
        //     5. Read safeCount delayed samples starting at readHead_ into the
        //        output buffers (one or two memcpy segments)
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

            // Safety clamp: never overrun the pre-allocated scratch buffer.
            // kLimiterRingSize is sized for kDefaultMaxFrames; enforce the same limit.
            const uint32_t safeCount = std::min(frameCount, kDefaultMaxFrames);

            // Pre-compute ceiling in dB once per buffer
            const float ceilingDb = 20.0F * std::log10(params.truePeakCeilingLinear + 1e-30F);

            // -----------------------------------------------------------------
            // Per-sample GR loop
            // -----------------------------------------------------------------
            for (uint32_t i = 0U; i < safeCount; ++i)
            {
                // 1. Write new input sample into ring
                leftRing_[writeHead_] = leftBuf[i];
                if (rightBuf != nullptr)
                {
                    rightRing_[writeHead_] = rightBuf[i];
                }

                // 2. Scan lookahead window for true-peak (4× ISP oversampled).
                //    The window is the kLimiterLookaheadFrames samples that were
                //    just written into the ring ahead of the current read position —
                //    i.e. positions [(writeHead_ - kLimiterLookaheadFrames + 1) ..
                //    writeHead_] (wrapping).  We scan writeHead_ as the newest and
                //    work kLimiterLookaheadFrames-1 steps back.
                const float peakLinear = scanLookahead(rightBuf != nullptr);

                // 3. Compute GR target and advance one-pole smoother
                {
                    const float peakDb = 20.0F * std::log10(peakLinear + 1e-30F);
                    const float grTarget = (peakDb > ceilingDb) ? (peakDb - ceilingDb) : 0.0F;
                    if (grTarget > gainReductionDb_)
                    {
                        gainReductionDb_ += attackCoeff_ * (grTarget - gainReductionDb_);
                    }
                    else
                    {
                        gainReductionDb_ += releaseCoeff_ * (grTarget - gainReductionDb_);
                    }
                }

                // 4. Convert GR (dB) to linear gain: gain = exp(−GR · ln(10)/20)
                grBuf_[i] = std::exp(-gainReductionDb_ * kLn10Over20);

                // 5. Advance write head
                writeHead_ = (writeHead_ + 1U) % kLimiterRingSize;
            }

            // -----------------------------------------------------------------
            // 6. Extract delayed output from ring (at readHead_) and overwrite
            //    the input buffers.  readHead_ is kLimiterLookaheadFrames behind
            //    writeHead_ — those samples were written kLimiterLookaheadFrames
            //    calls (frames) ago and represent the audio to output NOW.
            // -----------------------------------------------------------------
            fillOutputFromRing(leftBuf, leftRing_.data(), safeCount);
            if (rightBuf != nullptr)
            {
                fillOutputFromRing(rightBuf, rightRing_.data(), safeCount);
            }

            // 7. Apply per-sample gain envelope
            const vDSP_Length n = static_cast<vDSP_Length>(safeCount);
            vDSP_vmul(leftBuf, 1, grBuf_.data(), 1, leftBuf, 1, n);
            if (rightBuf != nullptr)
            {
                vDSP_vmul(rightBuf, 1, grBuf_.data(), 1, rightBuf, 1, n);
            }

            // 8. Advance read head
            readHead_ = (readHead_ + safeCount) % kLimiterRingSize;
        }

      private:
        // -----------------------------------------------------------------------
        // ispPairPeak() — return the 4× ISP true-peak for a single adjacent
        // sample pair (sampleA, sampleB) using linear interpolation.
        //
        // Evaluates: |sampleA|, |sampleB|, and (kISPOversamplingFactor − 1) = 3
        // linearly interpolated midpoints at fractions derived from kISPOversamplingFactor
        // (0.25, 0.50, 0.75 for 4×).  Returns the maximum absolute value found.
        //
        // Marked [[nodiscard]] and static — pure function, no side effects.
        // Extracted from scanLookahead() to reduce its cognitive complexity.
        //
        // Reference: ITU-R BS.1770-5 Annex 1; Zölzer DAFX 3rd ed. §3.3.1.
        // -----------------------------------------------------------------------
        [[nodiscard]] static auto ispPairPeak(float sampleA, float sampleB) noexcept -> float
        {
            // kISPOversamplingFactor = 4 → 3 interior midpoints at fractions 1/4, 2/4, 3/4.
            // Each fraction is k * kStep for k in [1, kISPOversamplingFactor − 1].
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
        // scanLookahead() — scan kLimiterLookaheadFrames samples ending at
        // writeHead_ (inclusive) at 4× ISP resolution.
        //
        // Window: positions [(writeHead_ - kLimiterLookaheadFrames + 1) .. writeHead_]
        // modulo kLimiterRingSize.  For each adjacent pair in the window,
        // ispPairPeak() is called for each active channel; the running max is returned.
        //
        // Cognitive complexity is kept low by delegating per-pair logic to ispPairPeak().
        // -----------------------------------------------------------------------
        [[nodiscard]] auto scanLookahead(bool hasStereo) const noexcept -> float
        {
            float peak = 0.0F;

            for (uint32_t k = 0U; k < kLimiterLookaheadFrames; ++k)
            {
                const uint32_t posA = (writeHead_ + kLimiterRingSize - k) % kLimiterRingSize;
                const uint32_t posB = (posA + kLimiterRingSize - 1U) % kLimiterRingSize;

                const float lp = ispPairPeak(leftRing_[posA], leftRing_[posB]);
                if (lp > peak)
                {
                    peak = lp;
                }

                if (hasStereo)
                {
                    const float rp = ispPairPeak(rightRing_[posA], rightRing_[posB]);
                    if (rp > peak)
                    {
                        peak = rp;
                    }
                }
            }

            return peak;
        }

        // -----------------------------------------------------------------------
        // fillOutputFromRing() — copy safeCount samples from the ring starting at
        // readHead_ into dst[], overwriting it.  Uses one or two memcpy segments
        // to handle the ring wrap without per-sample modular arithmetic.
        // -----------------------------------------------------------------------
        void fillOutputFromRing(float* dst, const float* ring, uint32_t safeCount) const noexcept
        {
            const uint32_t toEnd = kLimiterRingSize - readHead_;

            if (safeCount <= toEnd)
            {
                // Single segment — no wrap needed
                for (uint32_t i = 0U; i < safeCount; ++i)
                {
                    dst[i] = ring[readHead_ + i];
                }
            }
            else
            {
                // Two segments: tail of ring then head
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

        // Ring buffers: sized to hold lookahead window + one full max-size block.
        // kLimiterRingSize = kLimiterLookaheadFrames + kDefaultMaxFrames = 48 + 512 = 560.
        std::array<float, kLimiterRingSize> leftRing_{};
        std::array<float, kLimiterRingSize> rightRing_{};

        // Read head: position of the oldest sample to output (lags writeHead_ by
        // kLimiterLookaheadFrames).
        uint32_t readHead_ = 0U;
        // Write head: position where the next input sample will be written.
        uint32_t writeHead_ = kLimiterLookaheadFrames;

        // Running gain reduction state (dB, non-negative).  Persists across calls.
        float gainReductionDb_ = 0.0F;

        // One-pole smoother coefficients (computed in initialize(), never on RT thread)
        float attackCoeff_ = 0.0F;
        float releaseCoeff_ = 0.0F;

        // Per-sample gain envelope scratch (pre-allocated to kDefaultMaxFrames = 512)
        std::array<float, kDefaultMaxFrames> grBuf_{};

        uint32_t sampleRate_ = kDefaultSampleRate;
        uint32_t maxFrames_ = kDefaultMaxFrames;
    };

} // namespace AdaptiveSound
#endif // LIMITER_MODULE_H
