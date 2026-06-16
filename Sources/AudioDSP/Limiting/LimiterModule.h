#ifndef LIMITER_MODULE_H
#define LIMITER_MODULE_H

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
//   1. Look-ahead delay (3 ms / 144 frames @ 48 kHz) via a per-channel ring,
//      so the gain envelope reaches target before the transient arrives.
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
#include "../include/PerChannel.h"
#include "../include/TargetState.h"
#include <Accelerate/Accelerate.h>
#include <algorithm>
#include <array>
#include <AudioToolbox/AudioToolbox.h>
#include <cmath>
#include <cstdint>
#include <numbers>

namespace AdaptiveSound
{

    // --- Polyphase ISP detector (replaces M1 4× linear interpolation) -----------
    static constexpr uint32_t kIspOversampling = 8U; // 8× polyphase upsample
    static constexpr uint32_t kIspNumTaps = 24U;     // taps per phase (windowed sinc)
    static constexpr uint32_t kIspPrototypeN = kIspOversampling * kIspNumTaps; // 192
    static constexpr double kIspKaiserBeta = 8.0;         // Kaiser β (≈ −98 dB stopband)
    static constexpr double kIspProtoCutoffNorm = 0.0625; // 0.5/L: pass base band, reject images
    static constexpr uint32_t kI0MaxTerms = 25U;          // I0 Bessel series term cap
    static constexpr double kI0ConvergeEps = 1.0e-16;     // I0 series termination

    // Working-ceiling margin: polyphase worst-case under-read < 0.17 dB + 0.10 guard
    // → −0.27 dB = 10^(−0.27/20). (Was −0.5 dB / 0.94406 under M1 linear-interp.)
    static constexpr double kIspSafetyMargin = 0.96939327;

    // --- Ballistics (dB domain, dual-stage release + LF hold) -------------------
    static constexpr float kLimiterAttackMs = 0.5F;        // attack τ
    static constexpr float kLimiterFastReleaseMs = 100.0F; // fast release τ
    static constexpr float kLimiterSlowReleaseMs = 500.0F; // slow release τ (sustained)
    static constexpr float kMillisToSeconds = 0.001F;
    static constexpr double kLimiterDbScale = 20.0;   // 20·log10 (amplitude ↔ dB)
    static constexpr double kLimiterDbBase = 10.0;    // base for dB → linear
    static constexpr double kLfHoldThresholdDb = 0.5; // GR depth that arms LF hold
    static constexpr float kLfHoldSeconds = 0.05F;    // hold span (≈ 2 periods @ 40 Hz)

    // Maximum channels handled (stereo)
    static constexpr uint32_t kLimiterMaxChannels = 2U;

    // Ring: lookahead window + one full max-size block (96/144 + 512). Power-of-two
    // not required (we use explicit modulo). kLimiterRingSize = 144 + 512 = 656.
    static constexpr uint32_t kLimiterRingSize = kLimiterLookaheadFrames + kDefaultMaxFrames;

    // Monotonic-deque capacity: window of kLimiterLookaheadFrames pair-peaks plus one
    // transient slot between push-back and front-evict.
    static constexpr uint32_t kPeakDequeCapacity = kLimiterLookaheadFrames + 1U;

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
        // coefficients; call again on sample-rate change.
        // -----------------------------------------------------------------------
        void initialize(uint32_t sampleRate, uint32_t maxFrames) noexcept
        {
            sampleRate_ = sampleRate;
            maxFrames_ = maxFrames;

            const float fs = static_cast<float>(sampleRate);
            attackCoeff_ = onePoleCoeff(kLimiterAttackMs, fs);
            releaseFastCoeff_ = onePoleCoeff(kLimiterFastReleaseMs, fs);
            releaseSlowCoeff_ = onePoleCoeff(kLimiterSlowReleaseMs, fs);
            holdFrames_ = static_cast<uint32_t>(std::lround(kLfHoldSeconds * fs));

            rings_.reset();
            readHead_ = 0U;
            writeHead_ = kLimiterLookaheadFrames;

            envFastDb_ = 0.0;
            envSlowDb_ = 0.0;
            lfHoldCounter_ = 0U;
            grBuf_.fill(0.0F);
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
            // Stereo today (N-channel linked-gain generalization lands in S1).
            const uint32_t numChannels =
                block.channels() >= kLimiterMaxChannels ? kLimiterMaxChannels : block.channels();
            if (numChannels == 0U)
            {
                return;
            }
            float* leftBuf = block.channel(0);
            float* rightBuf = (numChannels >= 2U) ? block.channel(1) : nullptr;
            if (leftBuf == nullptr)
            {
                return;
            }

            // Bypass: ceiling ≥ 1.0 → zero-latency identity.
            if (params.truePeakCeilingLinear >= 1.0F)
            {
                return;
            }

            const uint32_t safeCount = std::min(frameCount, kDefaultMaxFrames);
            const double workingCeiling =
                static_cast<double>(params.truePeakCeilingLinear) * kIspSafetyMargin;
            const double ceilingDb = kLimiterDbScale * std::log10(workingCeiling);

            for (uint32_t i = 0U; i < safeCount; ++i)
            {
                rings_[0][writeHead_] = leftBuf[i];
                if (rightBuf != nullptr)
                {
                    rings_[1][writeHead_] = rightBuf[i];
                }

                const double isp = polyphaseIspPeak(writeHead_);
                const double peak = updatePeakDeque(isp);
                const double targetDb = targetGrDb(peak, workingCeiling, ceilingDb);
                const double grDb = advanceEnvelopeDb(targetDb);
                grBuf_[i] = static_cast<float>(std::pow(kLimiterDbBase, grDb / kLimiterDbScale));

                writeHead_ = (writeHead_ + 1U) % kLimiterRingSize;
            }

            fillOutputFromRing(leftBuf, rings_[0].data(), safeCount);
            if (rightBuf != nullptr)
            {
                fillOutputFromRing(rightBuf, rings_[1].data(), safeCount);
            }

            const vDSP_Length count = static_cast<vDSP_Length>(safeCount);
            vDSP_vmul(leftBuf, 1, grBuf_.data(), 1, leftBuf, 1, count);
            if (rightBuf != nullptr)
            {
                vDSP_vmul(rightBuf, 1, grBuf_.data(), 1, rightBuf, 1, count);
            }

            readHead_ = (readHead_ + safeCount) % kLimiterRingSize;
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
        [[nodiscard]] static auto kaiserI0(double xValue) noexcept -> double
        {
            const double half = xValue / 2.0;
            double term = 1.0;
            double sum = 1.0;
            for (uint32_t k = 1U; k <= kI0MaxTerms; ++k)
            {
                const double ratio = half / static_cast<double>(k);
                term *= ratio * ratio;
                sum += term;
                if (term < sum * kI0ConvergeEps)
                {
                    break;
                }
            }
            return sum;
        }

        // Build the 8×24 windowed-sinc polyphase upsampler into ispCoeffs_ (flat,
        // phase-major: ispCoeffs_[phase*kIspNumTaps + tap] = h[phase + tap*L]).
        // h[n] = L·(2·fc)·sinc(2·fc·(n−M))·kaiser(n,β),  M = (N−1)/2.  Off-RT.
        void computePolyphaseCoeffs() noexcept
        {
            const double center = static_cast<double>(kIspPrototypeN - 1U) / 2.0; // 95.5
            const double twoFc = 2.0 * kIspProtoCutoffNorm;                       // 0.125 = 1/L
            const double scale = static_cast<double>(kIspOversampling) * twoFc;   // = 1.0
            const double i0Beta = kaiserI0(kIspKaiserBeta);
            const double denom = static_cast<double>(kIspPrototypeN - 1U);

            for (uint32_t i = 0U; i < kIspPrototypeN; ++i)
            {
                // dist is half-integer (center = 95.5) → sincArg is never exactly 0.
                const double dist = static_cast<double>(i) - center;
                const double sincArg = twoFc * dist;
                const double sincVal =
                    std::sin(std::numbers::pi * sincArg) / (std::numbers::pi * sincArg);
                const double ratio = (2.0 * dist) / denom;
                const double winArg =
                    kIspKaiserBeta * std::sqrt(std::max(0.0, 1.0 - (ratio * ratio)));
                const double window = kaiserI0(winArg) / i0Beta;

                const uint32_t phase = i % kIspOversampling;
                const uint32_t tap = i / kIspOversampling;
                ispCoeffs_[(static_cast<size_t>(phase) * kIspNumTaps) + tap] =
                    scale * sincVal * window;
            }
        }

        // 8× polyphase inter-sample true-peak of the sample just written at
        // `writePos`, across both channels. Reads the 24-sample ring history
        // (handles wrap), runs 8 dot-products, returns max |·| (double).
        [[nodiscard]] auto polyphaseIspPeak(uint32_t writePos) const noexcept -> double
        {
            std::array<double, kIspNumTaps> histLeft{};
            std::array<double, kIspNumTaps> histRight{};
            for (uint32_t k = 0U; k < kIspNumTaps; ++k)
            {
                const uint32_t idx = (writePos + kLimiterRingSize - k) % kLimiterRingSize;
                histLeft[k] = static_cast<double>(rings_[0][idx]);
                histRight[k] = static_cast<double>(rings_[1][idx]);
            }

            double maxPeak = 0.0;
            for (uint32_t phase = 0U; phase < kIspOversampling; ++phase)
            {
                const size_t base = static_cast<size_t>(phase) * kIspNumTaps;
                double dotLeft = 0.0;
                double dotRight = 0.0;
                for (uint32_t k = 0U; k < kIspNumTaps; ++k)
                {
                    const double coeff = ispCoeffs_[base + k];
                    dotLeft += coeff * histLeft[k];
                    dotRight += coeff * histRight[k];
                }
                maxPeak = std::max({maxPeak, std::abs(dotLeft), std::abs(dotRight)});
            }
            return maxPeak;
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
                   peakDeque_[dequeHead_].index + kLimiterLookaheadFrames <= sampleCounter_)
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
        // State — all pre-allocated; no heap in process(). Ordered by descending
        // alignment to keep the layout padding-clean.
        // -----------------------------------------------------------------------

        // Polyphase coefficient table (flat phase-major; computed off-RT).
        std::array<double, static_cast<size_t>(kIspOversampling) * kIspNumTaps> ispCoeffs_{};

        // Look-ahead ring buffers (96/144 + 512 = 656), one per channel.
        using LimiterRing = std::array<float, kLimiterRingSize>;
        PerChannel<LimiterRing> rings_{};

        // Per-sample gain envelope scratch (kDefaultMaxFrames = 512).
        std::array<float, kDefaultMaxFrames> grBuf_{};

        // Sliding-window peak deque (circular).
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
    };

} // namespace AdaptiveSound
#endif // LIMITER_MODULE_H
