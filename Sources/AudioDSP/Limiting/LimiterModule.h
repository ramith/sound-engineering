#pragma once

// LimiterModule — True-peak lookahead limiter (Sprint 4, Milestone 3 = state of the art)
//
// Architecture
// ============
// Final stage of the signal chain (see DSPKernel.h):
//   EQ → Clarity → BRIR → Loudness → [Limiter] → Device Output
//
// Enforces a true-peak ceiling (default −1 dBTP) transparently. Quality-first
// design (CPU/RAM assumed abundant — see docs/sprints/04-sprint-4-loudness-safety-plan.md):
//
//   1. Look-ahead delay — a fixed 3 ms (kLimiterLookaheadSeconds), converted to a
//      frame count per sample rate in initialize() (144 @ 48 kHz) via a per-channel
//      ring, so the gain envelope reaches target before the transient arrives at
//      EVERY rate. A fixed frame count would shrink the look-ahead TIME as fs rises
//      and let hi-res peaks slip the ceiling (Stage-1 review AC-2).
//
//   2. Inter-sample (true-peak) detection — **8× polyphase windowed-sinc FIR**
//      (Kaiser β=8, 24 taps/phase), sidechain-only. For each new input sample
//      the 8 polyphase phases reconstruct the 8 sub-sample magnitudes over the
//      last 24 samples; the per-sample ISP estimate = max(|those|). This replaces
//      the M1 4× linear interpolation (which under-read true peaks by ~0.5 dB):
//      verified worst-case under-read < 0.17 dB, so the working-ceiling margin is
//      −0.27 dB (was −0.5 dB). Audio path stays at base rate — only the detector
//      is oversampled (x42/zita-dpl1 model). Ref: ITU-R BS.1770 Annex 2; libebur128.
//
//   3. Sliding-window peak (monotonic deque, amortized O(1)) → gain reduction in
//      the **dB domain** with a **dual-stage release** (fast + slow, deeper wins)
//      and **LF hold-extension** (don't release between bass-spaced peaks). Ref:
//      Giannoulis/Massberg/Reiss, JAES 2012; x42 hold-extension. Gain applied via
//      vDSP_vmul. All sidechain math is double; only the final gain is float.
//
// Why NOT a K-weighted/HP sidechain (the withdrawn "B5"): a true-peak ceiling must
// catch low-frequency inter-sample peaks too — weighting the detector would make it
// blind to them. Bass pumping is solved by hold-extension, not by deafening the
// detector. (K-weighting belongs in the upstream LUFS module, which we have.)
//
// RT-Safety
// =========
// process() is noexcept: no allocation, free, OS call, or lock. All buffers and the
// polyphase coefficient table are pre-allocated/computed in initialize() (off-RT).
//
// Ring sizing
// ===========
// The look-ahead ring is sized ringSize_ = lookaheadFrames_ + maxFrames_, where
// lookaheadFrames_ = round(kLimiterLookaheadSeconds · fs) is computed in initialize()
// (so the look-ahead TIME is constant across rates — AC-2). Allocated as a heap vector
// per channel (so it scales with the host's maximumFramesToRender rather than being
// stuck at the compile-time kDefaultMaxFrames=512). At maxFrames_=512 / 48 kHz the
// geometry is identical to the former compile-time kLimiterRingSize = 144 + 512,
// preserving bit-exactness. grBuf_ is likewise a heap vector sized to maxFrames_.
//
// Parameters (LimiterParams, published via DoubleBufferSnapshot)
// =============================================================
//   truePeakCeilingLinear — linear ceiling; default 0.891 (−1 dBTP). ≥ 1.0 bypasses
//                           (zero-latency identity passthrough).
//
// References
// ==========
// - ITU-R BS.1770-4/-5 Annex 2 (true-peak / oversampled ISP measurement)
// - Giannoulis, Massberg & Reiss, "Digital Dynamic Range Compressor Design",
//   JAES 60(6), 2012 (dB-domain gain computer, dual-stage release)
// - Julius O. Smith III, "Introduction to Digital Filters" §1.3.1 (one-pole RC)
// - Oppenheim & Schafer §7.6 (Kaiser window); Schafer & Rabiner 1973 (polyphase)
// - jiixyj/libebur128, x42/dpl.lv2 (oversampled true-peak detection)

#include "../include/AudioConstants.h"
#include "../include/MultichannelView.h"
#include "../include/TargetState.h"
#include "../include/TruePeakKernel.h"
#include <Accelerate/Accelerate.h>
#include <algorithm>
#include <array>
#include <AudioToolbox/AudioToolbox.h>
#include <cassert>
#include <cmath>
#include <cstdint>
#include <vector>

namespace AdaptiveSound
{

    // --- Polyphase ISP detector (replaces M1 4× linear interpolation) -----------
    // The 8×24 windowed-sinc kernel itself lives in include/TruePeakKernel.h (S10.8 PR E
    // extraction) — shared with the loudness meter's true-peak readout so both run the
    // SAME oracle-verified design. Only the limiter-specific margin stays here.

    // Working-ceiling margin: polyphase worst-case under-read < 0.17 dB + 0.10 guard
    // → −0.27 dB = 10^(−0.27/20). (Was −0.5 dB / 0.94406 under M1 linear-interp.)
    inline constexpr double kIspSafetyMargin = 0.96939327;

    // --- Ballistics (dB domain, dual-stage release + LF hold) -------------------
    inline constexpr float kLimiterAttackMs = 0.5F;        // attack τ
    inline constexpr float kLimiterFastReleaseMs = 100.0F; // fast release τ
    inline constexpr float kLimiterSlowReleaseMs = 500.0F; // slow release τ (sustained)
    inline constexpr float kMillisToSeconds = 0.001F;
    inline constexpr double kLimiterDbScale = 20.0;   // 20·log10 (amplitude ↔ dB)
    inline constexpr double kLimiterDbBase = 10.0;    // base for dB → linear
    inline constexpr double kLfHoldThresholdDb = 0.5; // GR depth that arms LF hold
    inline constexpr float kLfHoldSeconds = 0.05F;    // hold span (≈ 2 periods @ 40 Hz)

    // Monotonic-deque capacity: window of look-ahead pair-peaks plus one transient slot
    // between push-back and front-evict. Sized to the MAX supported rate's look-ahead
    // (kMaxLimiterLookaheadFrames) so the fixed-capacity deque never overflows at any
    // sample rate; dequeCount_ is tracked explicitly, so a larger-than-needed capacity at
    // lower rates is harmless and does not change the window-max sequence (AC-2).
    inline constexpr uint32_t kPeakDequeCapacity = kMaxLimiterLookaheadFrames + 1U;

    class LimiterModule
    {
      public:
        LimiterModule() = default;
        ~LimiterModule() = default;

        LimiterModule(const LimiterModule&) = delete;
        LimiterModule& operator=(const LimiterModule&) = delete;
        LimiterModule(LimiterModule&&) = delete;
        LimiterModule& operator=(LimiterModule&&) = delete;

        // -----------------------------------------------------------------------
        // initialize() — control thread, off-RT. Computes ballistics + polyphase
        // coefficients; allocates ring buffers and grBuf_ to maxFrames_; call
        // again on sample-rate or maxFrames change.
        // -----------------------------------------------------------------------
        void initialize(uint32_t sampleRate, uint32_t maxFrames) noexcept
        {
            sampleRate_ = sampleRate;
            maxFrames_ = maxFrames;

            const float fs = static_cast<float>(sampleRate);

            // Look-ahead is a fixed TIME (kLimiterLookaheadSeconds); derive the frame count
            // from fs so the gain envelope always has enough attack time-constants to
            // converge before the transient arrives — the −1 dBTP ceiling then holds at
            // every rate, not just ≤48 kHz (Stage-1 review AC-2). At 48 kHz this is exactly
            // 144 (== kLimiterLookaheadFrames), so GoldenMaster_StereoN2_v1 stays bit-exact.
            // Clamped to the fixed-capacity deque's max-rate bound.
            lookaheadFrames_ =
                std::min<uint32_t>(static_cast<uint32_t>(std::lround(
                                       static_cast<double>(kLimiterLookaheadSeconds) * fs)),
                                   kMaxLimiterLookaheadFrames);

            // Ring size: lookahead window + one full host buffer. At maxFrames_=512 / 48 kHz
            // this equals the former kLimiterRingSize (656), preserving bit-exactness.
            ringSize_ = lookaheadFrames_ + maxFrames_;
            attackCoeff_ = onePoleCoeff(kLimiterAttackMs, fs);
            releaseFastCoeff_ = onePoleCoeff(kLimiterFastReleaseMs, fs);
            releaseSlowCoeff_ = onePoleCoeff(kLimiterSlowReleaseMs, fs);
            holdFrames_ = static_cast<uint32_t>(std::lround(kLfHoldSeconds * fs));

            // Allocate and zero each channel's ring. Do NOT call rings_.reset() here:
            // PerChannel<T>::reset() value-initialises slots, which for std::vector
            // would empty them (resize to zero). Instead resize+fill each slot directly.
            for (auto& ring : rings_)
            {
                ring.assign(ringSize_, 0.0F);
            }

            readHead_ = 0U;
            writeHead_ = lookaheadFrames_;

            envFastDb_ = 0.0;
            envSlowDb_ = 0.0;
            lfHoldCounter_ = 0U;

            // grBuf_: heap-allocated to maxFrames_ (off-RT, the only allocation site).
            grBuf_.assign(maxFrames_, 0.0F);

            dequeHead_ = 0U;
            dequeCount_ = 0U;
            sampleCounter_ = 0U;

            computePolyphaseCoeffs();
        }

        // -----------------------------------------------------------------------
        // process() — RT-safe; noexcept; no allocation. In-place on ioData.
        //   Bypass (ceiling ≥ 1.0): immediate zero-latency identity return.
        //   Active: per sample → write ring, polyphase ISP, deque window-max,
        //   dB-domain dual-stage gain, then read delayed output and apply gain.
        // -----------------------------------------------------------------------
        void process(const LimiterParams& params, const MultichannelView& block) noexcept
        {
            const uint32_t frameCount = block.frames();
            if (frameCount == 0U)
            {
                return;
            }
            const uint32_t numChannels = block.channels();
            if (numChannels == 0U)
            {
                return;
            }

            // Gather channel pointers once — RT-safe stack array, no heap.
            std::array<float*, kMaxChannels> bufs{};
            for (uint32_t ch = 0U; ch < numChannels; ++ch)
            {
                bufs[ch] = block.channel(ch);
            }
            if (bufs[0] == nullptr)
            {
                return;
            }

            // Bypass: ceiling ≥ 1.0 → zero-latency identity.
            if (params.truePeakCeilingLinear >= 1.0F)
            {
                return;
            }

            // frameCount must not exceed the buffer capacity established in initialize().
            assert(frameCount <= maxFrames_);

            // Process all frameCount samples — not just kDefaultMaxFrames.
            // grBuf_ and each ring are sized to maxFrames_ (and ringSize_ respectively)
            // so no bounds overrun is possible.
            const uint32_t safeCount = std::min(frameCount, maxFrames_);
            const double workingCeiling =
                static_cast<double>(params.truePeakCeilingLinear) * kIspSafetyMargin;
            const double ceilingDb = kLimiterDbScale * std::log10(workingCeiling);

            for (uint32_t i = 0U; i < safeCount; ++i)
            {
                // Write all active channels into their rings for this sample.
                for (uint32_t ch = 0U; ch < numChannels; ++ch)
                {
                    if (bufs[ch] != nullptr)
                    {
                        rings_[ch][writeHead_] = bufs[ch][i];
                    }
                }

                // Detection fan-in: the linked gain reacts to the loudest inter-sample
                // true peak across ALL active channels. max() over channels is
                // order-independent — at N=2 (ch=0 then ch=1, both non-null) this
                // reproduces the prior left-then-right order exactly, preserving
                // GoldenMaster_StereoN2_v1 bit-exactness.
                double isp = 0.0;
                for (uint32_t ch = 0U; ch < numChannels; ++ch)
                {
                    isp = std::max(isp, polyphaseIspPeak(ch, writeHead_));
                }
                const double peak = updatePeakDeque(isp);
                const double targetDb = targetGrDb(peak, workingCeiling, ceilingDb);
                const double grDb = advanceEnvelopeDb(targetDb);
                grBuf_[i] = static_cast<float>(std::pow(kLimiterDbBase, grDb / kLimiterDbScale));

                writeHead_ = (writeHead_ + 1U) % ringSize_;
            }

            // Copy lookahead-delayed samples from ring to output buffer, then apply
            // the shared gain envelope via vDSP_vmul. All channels receive the same
            // GR trajectory (linked gain).
            for (uint32_t ch = 0U; ch < numChannels; ++ch)
            {
                if (bufs[ch] != nullptr)
                {
                    fillOutputFromRing(bufs[ch], rings_[ch].data(), safeCount);
                }
            }
            const vDSP_Length count = static_cast<vDSP_Length>(safeCount);
            for (uint32_t ch = 0U; ch < numChannels; ++ch)
            {
                if (bufs[ch] != nullptr)
                {
                    vDSP_vmul(bufs[ch], 1, grBuf_.data(), 1, bufs[ch], 1, count);
                }
            }

            readHead_ = (readHead_ + safeCount) % ringSize_;
        }

      private:
        struct PeakEntry
        {
            uint64_t index = 0U;
            double value = 0.0;
        };

        // RC-exact one-pole coefficient: α = 1 − exp(−1/(τ·fs))  (JOS §1.3.1).
        [[nodiscard]] static auto onePoleCoeff(float timeConstantMs, float sampleRate) noexcept
            -> double
        {
            const double tauSeconds = static_cast<double>(timeConstantMs * kMillisToSeconds);
            return 1.0 - std::exp(-1.0 / (tauSeconds * static_cast<double>(sampleRate)));
        }

        // Modified Bessel I0(x) via series Σ ((x/2)^k / k!)² (libc++ lacks
        // std::cyl_bessel_i). Pure, off-RT.
        // Build the 8×24 windowed-sinc polyphase upsampler into ispCoeffs_. The kernel
        // math lives in TruePeakKernel (S10.8 PR E extraction — shared with the loudness
        // meter's true-peak readout). Off-RT.
        void computePolyphaseCoeffs() noexcept
        {
            TruePeakKernel::computeCoefficients(ispCoeffs_);
        }

        // 8× polyphase inter-sample true-peak of the sample just written at
        // `writePos`, for ONE channel. Reads that channel's 24-sample ring history
        // (handles wrap using ringSize_) into the kernel's newest-first window, then
        // runs the shared phase dot-products. The caller maxes this over all active
        // channels to drive the linked gain.
        [[nodiscard]] auto polyphaseIspPeak(uint32_t channel, uint32_t writePos) const noexcept
            -> double
        {
            TruePeakKernel::History hist{};
            for (uint32_t k = 0U; k < TruePeakKernel::kNumTaps; ++k)
            {
                const uint32_t idx = (writePos + ringSize_ - k) % ringSize_;
                hist[k] = static_cast<double>(rings_[channel][idx]);
            }
            return TruePeakKernel::phasePeak(hist, ispCoeffs_);
        }

        // Required gain reduction (dB, ≤ 0) to bring `peak` down to the working
        // ceiling. ceilingDb is precomputed once per buffer.
        [[nodiscard]] static auto
        targetGrDb(double peak, double workingCeiling, double ceilingDb) noexcept -> double
        {
            if (peak <= workingCeiling)
            {
                return 0.0;
            }
            return ceilingDb - (kLimiterDbScale * std::log10(peak));
        }

        // Advance the dual-stage dB envelope toward targetDb (≤ 0) with attack /
        // dual release + LF hold-extension; returns the deeper (more-reduced) of the
        // fast/slow branches in dB.
        [[nodiscard]] auto advanceEnvelopeDb(double targetDb) noexcept -> double
        {
            const double effDb = std::min(envFastDb_, envSlowDb_);
            if (targetDb < effDb)
            {
                // Attack: both branches track toward more reduction; arm LF hold.
                envFastDb_ += attackCoeff_ * (targetDb - envFastDb_);
                envSlowDb_ += attackCoeff_ * (targetDb - envSlowDb_);
                if (-targetDb >= kLfHoldThresholdDb)
                {
                    lfHoldCounter_ = holdFrames_;
                }
            }
            else if ((-effDb >= kLfHoldThresholdDb) && (lfHoldCounter_ > 0U))
            {
                // LF hold: freeze release between bass-spaced peaks.
                --lfHoldCounter_;
            }
            else
            {
                envFastDb_ += releaseFastCoeff_ * (targetDb - envFastDb_);
                envSlowDb_ += releaseSlowCoeff_ * (targetDb - envSlowDb_);
                if (lfHoldCounter_ > 0U)
                {
                    --lfHoldCounter_;
                }
            }
            return std::min(envFastDb_, envSlowDb_);
        }

        // Monotonic-deque sliding-window maximum over the lookahead window;
        // amortized O(1) per sample. Backed by a fixed circular array.
        [[nodiscard]] auto updatePeakDeque(double value) noexcept -> double
        {
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

            const uint32_t pushPos = (dequeHead_ + dequeCount_) % kPeakDequeCapacity;
            peakDeque_[pushPos] = {.index = sampleCounter_, .value = value};
            ++dequeCount_;

            while (dequeCount_ > 0U &&
                   peakDeque_[dequeHead_].index + lookaheadFrames_ <= sampleCounter_)
            {
                dequeHead_ = (dequeHead_ + 1U) % kPeakDequeCapacity;
                --dequeCount_;
            }

            const double windowMax = peakDeque_[dequeHead_].value;
            ++sampleCounter_;
            return windowMax;
        }

        // Copy safeCount delayed samples from the ring (at readHead_) into dst,
        // splitting at the wrap to avoid per-sample modular arithmetic.
        // Uses ringSize_ (runtime) for the wrap calculation.
        void fillOutputFromRing(float* dst, const float* ring, uint32_t count) const noexcept
        {
            const uint32_t toEnd = ringSize_ - readHead_;
            if (count <= toEnd)
            {
                for (uint32_t i = 0U; i < count; ++i)
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
                const uint32_t remaining = count - toEnd;
                for (uint32_t i = 0U; i < remaining; ++i)
                {
                    dst[toEnd + i] = ring[i];
                }
            }
        }

        // -----------------------------------------------------------------------
        // State
        // -----------------------------------------------------------------------

        // Polyphase coefficient table (flat phase-major; computed off-RT).
        TruePeakKernel::Coefficients ispCoeffs_{};

        // Look-ahead ring buffers: one std::vector<float> per channel, each sized to
        // ringSize_ = kLimiterLookaheadFrames + maxFrames_ in initialize(). Heap-allocated
        // off-RT so the ring scales with the host's maximumFramesToRender. process() never
        // allocates. Using a std::array of vectors (kMaxChannels slots) avoids the
        // PerChannel<T> reset() pitfall for vector elements (its reset() would empty them).
        std::array<std::vector<float>, kMaxChannels> rings_;

        // Per-sample gain envelope scratch: heap-allocated to maxFrames_ in initialize().
        std::vector<float> grBuf_;

        // Sliding-window peak deque (circular). Fixed capacity — depends only on the
        // lookahead window, not maxFrames_.
        std::array<PeakEntry, kPeakDequeCapacity> peakDeque_{};

        // dB-domain dual-stage envelope state (≤ 0 dB) and ballistics coefficients.
        double envFastDb_ = 0.0;
        double envSlowDb_ = 0.0;
        double attackCoeff_ = 0.0;
        double releaseFastCoeff_ = 0.0;
        double releaseSlowCoeff_ = 0.0;

        uint64_t sampleCounter_ = 0U; // monotonic sample index (deque window)

        uint32_t readHead_ = 0U;
        uint32_t writeHead_ = kLimiterLookaheadFrames;
        uint32_t dequeHead_ = 0U;
        uint32_t dequeCount_ = 0U;
        uint32_t lfHoldCounter_ = 0U; // frames remaining in LF hold-extension
        uint32_t holdFrames_ = 0U;    // LF hold span (computed in initialize())
        uint32_t sampleRate_ = kDefaultSampleRate;
        uint32_t maxFrames_ = kDefaultMaxFrames;
        // Look-ahead frame count, derived from kLimiterLookaheadSeconds · fs in initialize()
        // (AC-2). Defaults to the 48 kHz value; always ≤ kMaxLimiterLookaheadFrames.
        uint32_t lookaheadFrames_ = kLimiterLookaheadFrames;
        uint32_t ringSize_ = kLimiterLookaheadFrames + kDefaultMaxFrames; // set in initialize()
    };

} // namespace AdaptiveSound
