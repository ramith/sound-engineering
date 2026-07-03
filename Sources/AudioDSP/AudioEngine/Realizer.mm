#import "Realizer.h"

#import <Foundation/Foundation.h> // NSLog (control-plane diagnostics, off-RT only)

#include <algorithm> // std::clamp
#include <cmath>     // std::exp, M_PI
#include <cstring>   // std::memcpy

namespace AdaptiveSound
{

namespace
{
    // Preset → (fc, alpha) resolution table (QW1 §2/§5). The middle case is `Bauer`; the Swift
    // label stays "Default". Coefficients are the bs2b sets: Relaxed=Jmeier, Bauer=Default,
    // Strong=Cmoy. Off-RT only (called from the Realizer's serial queue / a test).
    struct CrossfeedPresetCoeffs
    {
        float fcHz;
        float alpha;
    };

    constexpr CrossfeedPresetCoeffs kCrossfeedRelaxed = {.fcHz = 650.0F, .alpha = 0.335F}; // Jmeier
    constexpr CrossfeedPresetCoeffs kCrossfeedBauer = {.fcHz = 700.0F, .alpha = 0.355F};   // Default
    constexpr CrossfeedPresetCoeffs kCrossfeedStrong = {.fcHz = 700.0F, .alpha = 0.501F};  // Cmoy

    // 2π for the exact-RC one-pole pole: p = exp(-2π·fc/fs).
    constexpr float kTwoPi = 6.28318530717958647692F;

    [[nodiscard]] auto resolveCrossfeedPreset(uint32_t preset) -> CrossfeedPresetCoeffs
    {
        const auto value = static_cast<CrossfeedPreset>(static_cast<uint8_t>(preset));
        switch (value)
        {
        case CrossfeedPreset::Strong:
            return kCrossfeedStrong;
        case CrossfeedPreset::Relaxed:
            return kCrossfeedRelaxed;
        case CrossfeedPreset::Bauer:
            return kCrossfeedBauer;
        }
        return kCrossfeedBauer; // unreachable (preset is clamped at the surface); safe default
    }

    // Derive the CrossfeedParams POD off-RT from the user intent {enabled, level, preset} and the
    // design sample rate. The cross-path attenuation alpha is SCALED by `level` (the crossfeed
    // depth control) so the audible amount tracks the UI level continuously; the gains stay
    // loudness-neutral (gDirect=1/(1+α), gCross=α/(1+α)).
    //
    // IMPORTANT (click-free DISABLE): the coefficients are ALWAYS computed, even when enabled==0.
    // `enabled` drives only the module's mix-ramp TARGET (1=fade in, 0=fade out); the coefficients
    // describe the crossfeed the module fades between. If a disable zeroed the coefficients, the
    // module's wet path would equal the dry path INSTANTLY (gCross=0) — a snap-cut click — and the
    // mix ramp would have nothing to fade. Carrying the last-active coefficients lets the module
    // glide the still-crossfed `wet` down to dry, then early-return bit-exact once the ramp settles
    // at 0 (which keeps the golden master / CF-1 anchor: the DEFAULT CrossfeedParams{} is enabled=0
    // with zero coefficients and a never-enabled module's mix stays at 0).
    [[nodiscard]] auto deriveCrossfeedParams(uint32_t enabled, float level, uint32_t preset,
                                             double sampleRate) -> CrossfeedParams
    {
        CrossfeedParams params{}; // all fields default to "off"
        params.enabled = (enabled != 0U) ? 1U : 0U;
        params.preset = static_cast<uint8_t>(preset);

        const CrossfeedPresetCoeffs coeffs = resolveCrossfeedPreset(preset);
        // Scale the cross attenuation by the depth level: level=0 → no cross (transparent),
        // level=1 → the preset's full alpha. Keeps enable/level a continuous, loudness-neutral
        // control (the module's per-sample mix ramp handles the click-free transition).
        const float alpha = coeffs.alpha * level;

        params.gDirect = 1.0F / (1.0F + alpha);
        params.gCross = alpha / (1.0F + alpha);

        // One-pole LPF (exact-RC form): p = exp(-2π·fc/fs); b0 = 1 - p; y[n]=b0·x[n]+p·y[n-1].
        const float fs = static_cast<float>(sampleRate);
        const float pole = std::exp(-(kTwoPi * coeffs.fcHz) / fs);
        params.lpfPole = pole;
        params.lpfB0 = 1.0F - pole;

        // ITD: delayFrames = round(0.0003178·fs). Clamped to the fixed line capacity (defensive;
        // 192 kHz worst case is 61 < 64, already asserted at compile time in CrossfeedModule.h).
        // roundToNearestInt (CrossfeedModule.h) avoids the bugprone-incorrect-roundings pattern.
        const int delayFrames =
            std::clamp(roundToNearestInt(kCrossfeedItdSeconds * sampleRate), 0,
                       kMaxCrossfeedDelayFrames - 1);
        params.delayFrames = delayFrames;
        return params;
    }
} // namespace

Realizer::Realizer(std::shared_ptr<DSPKernel> kernel) : kernel_(std::move(kernel))
{
    // Serial, off-main queue. Default QoS (utility-ish): the control plane is not latency
    // critical and must never run on the RT/render thread.
    queue_ = dispatch_queue_create("com.adaptivesound.realizer", DISPATCH_QUEUE_SERIAL);
}

Realizer::~Realizer()
{
    // Defensive: if the owner forgot to call shutdown(), drain now so no block outlives us.
    // shutdown() is idempotent.
    shutdown();
    // ARC manages dispatch_queue_t lifetime under -fobjc-arc; nothing to release manually.
}

void Realizer::shutdown()
{
    if (queue_ == nullptr || shutdown_)
    {
        return;
    }
    // Draining barrier (design §1, the review's BLOCKER): a dispatch_sync of an empty block
    // on a SERIAL queue does not return until every previously-enqueued block has finished.
    // dispatch_suspend would NOT be sufficient (it leaves enqueued blocks pending). After
    // this returns, no queued drain block can run, so the caller may safely drop its
    // shared_ptr<Realizer> and release the kernel.
    dispatch_sync(queue_, ^{
                  });
    shutdown_ = true;
}

bool Realizer::setPendingEqGains(const float* gainsDb, uint32_t count, double sampleRate)
{
    // Control-plane contract mirrors the old publishEQBandGains: 31-band ISO grid, valid SR,
    // non-null pointer. Reject mismatches rather than partially filling.
    if (gainsDb == nullptr)
    {
        return false;
    }
    if (count != static_cast<uint32_t>(EQModuleCoefficients::kNumBands))
    {
        return false;
    }
    if (!(sampleRate > 0.0)) // also rejects NaN
    {
        return false;
    }

    // Write the slot on the control thread. The cascade is NOT computed here; it is designed
    // off-main inside drain() (design §1.3 "EQ dirty -> computeBiquadCascade off-main, here").
    const bool wasClean = !pendingEqGains_.dirty;
    std::memcpy(pendingEqGains_.gainsDb.data(), gainsDb, sizeof(pendingEqGains_.gainsDb));
    pendingEqGains_.sampleRate = static_cast<float>(sampleRate);
    pendingEqGains_.dirty = true;

    // NOLINTNEXTLINE(cppcoreguidelines-pro-type-vararg) PERMANENT reason="NSLog is the platform logging API"
    NSLog(@"[QW1] Realizer.setPendingEqGains count=%u sampleRate=%.1f -> %s", count, sampleRate,
          wasClean ? "POST drain (clean->dirty)" : "coalesced (drain in flight)");

    // Post a drain ONLY on a clean->dirty transition. If a drain is already pending (slot was
    // still dirty), the in-flight drain will read the freshly-overwritten slot — true
    // "compute once per burst" coalescing.
    if (wasClean)
    {
        std::shared_ptr<Realizer> self = shared_from_this();
        dispatch_async(queue_, ^{
            self->drain();
        });
    }
    return true;
}

void Realizer::setPendingIntensity(float value)
{
    // Clamp to [0,1] at the surface (design §1.5: publishIntensity clamps).
    const float clamped = std::clamp(value, 0.0F, 1.0F);

    const bool wasClean = !pendingIntensity_.dirty;
    pendingIntensity_.value = clamped;
    pendingIntensity_.dirty = true;

    // NOLINTNEXTLINE(cppcoreguidelines-pro-type-vararg) PERMANENT reason="NSLog is the platform logging API"
    NSLog(@"[QW1] Realizer.setPendingIntensity value=%.4f (clamped=%.4f) -> %s", value, clamped,
          wasClean ? "POST drain (clean->dirty)" : "coalesced (drain in flight)");

    // Separate slot from EQ -> an interleaved intensity intent is never dropped by an EQ
    // burst. Post a drain only on a clean->dirty transition (coalesces intensity bursts).
    if (wasClean)
    {
        std::shared_ptr<Realizer> self = shared_from_this();
        dispatch_async(queue_, ^{
            self->drain();
        });
    }
}

bool Realizer::setPendingCrossfeed(uint32_t enabled, float level, uint32_t preset,
                                   double sampleRate)
{
    // Reject an invalid design sample rate rather than packing a NaN/garbage coefficient.
    if (!(sampleRate > 0.0)) // also rejects NaN
    {
        return false;
    }

    // Clamp at the surface (QW1 §3): level to [0,1], preset to the valid CrossfeedPreset range.
    // kStrong is the highest enum value (=2), so clamp the preset index to [0, kStrong].
    constexpr uint32_t kMaxPreset = static_cast<uint32_t>(CrossfeedPreset::Strong);
    const float clampedLevel = std::clamp(level, 0.0F, 1.0F);
    const uint32_t clampedPreset = std::clamp(preset, 0U, kMaxPreset);

    const bool wasClean = !pendingCrossfeed_.dirty;
    pendingCrossfeed_.enabled = enabled;
    pendingCrossfeed_.level = clampedLevel;
    pendingCrossfeed_.preset = clampedPreset;
    pendingCrossfeed_.sampleRate = static_cast<float>(sampleRate);
    pendingCrossfeed_.dirty = true;

    // NOLINTNEXTLINE(cppcoreguidelines-pro-type-vararg) PERMANENT reason="NSLog is the platform logging API"
    NSLog(@"[QW1] Realizer.setPendingCrossfeed enabled=%u level=%.4f preset=%u sampleRate=%.1f -> %s",
          enabled, clampedLevel, clampedPreset, sampleRate,
          wasClean ? "POST drain (clean->dirty)" : "coalesced (drain in flight)");

    // Separate slot from EQ/intensity → an interleaved crossfeed intent is never dropped by another
    // burst. Post a drain only on a clean->dirty transition (coalesces crossfeed bursts).
    if (wasClean)
    {
        std::shared_ptr<Realizer> self = shared_from_this();
        dispatch_async(queue_, ^{
            self->drain();
        });
    }
    return true;
}

void Realizer::drain()
{
    // Sole canonical-state mutation path. In debug, assert we are on the realizer queue so a
    // stray caller (or a future cross-thread bug) trips immediately.
    dispatch_assert_queue_debug(queue_);

    // Read-and-clear the dirty slots up front. A slot rewritten AFTER this read (by a
    // concurrent control-thread burst) flips dirty=true again and, because we cleared it,
    // looks "clean" to the next setPending* call -> that call posts a fresh drain. So no
    // intent is lost across the read/clear boundary.
    bool eqDirty = pendingEqGains_.dirty;
    std::array<float, static_cast<size_t>(EQModuleCoefficients::kNumBands)> eqGains{};
    float eqSampleRate = 0.0F;
    if (eqDirty)
    {
        eqGains = pendingEqGains_.gainsDb;
        eqSampleRate = pendingEqGains_.sampleRate;
        pendingEqGains_.dirty = false;
    }

    bool intensityDirty = pendingIntensity_.dirty;
    float intensityValue = 1.0F;
    if (intensityDirty)
    {
        intensityValue = pendingIntensity_.value;
        pendingIntensity_.dirty = false;
    }

    // Third per-intent read-and-clear block (QW1 §3). Same coalescing contract: a rewrite after
    // this read flips dirty=true again and posts a fresh drain, so no crossfeed intent is lost.
    bool crossfeedDirty = pendingCrossfeed_.dirty;
    PendingCrossfeed crossfeed{};
    if (crossfeedDirty)
    {
        crossfeed = pendingCrossfeed_;
        pendingCrossfeed_.dirty = false;
    }

    if (!eqDirty && !intensityDirty && !crossfeedDirty)
    {
        return; // spurious wake (slot already drained by an earlier coalesced block)
    }

    // NOLINTNEXTLINE(cppcoreguidelines-pro-type-vararg) PERMANENT reason="NSLog is the platform logging API"
    NSLog(@"[QW1] Realizer.drain applying dirty slots: eq=%d intensity=%d crossfeed=%d",
          static_cast<int>(eqDirty), static_cast<int>(intensityDirty),
          static_cast<int>(crossfeedDirty));

    // Recompute ONLY what changed, RMW the canonical state field-by-field (so the other
    // modules keep their last-set values), bump sequenceNumber ONCE, publish ONCE.
    if (eqDirty)
    {
        canonical_.eq = EQModuleCoefficients::computeBiquadCascade(eqGains, eqSampleRate);
    }
    if (intensityDirty)
    {
        canonical_.intensityLinear = intensityValue;
    }
    if (crossfeedDirty)
    {
        // Coefficients derived OFF-RT here (the Realizer's serial queue), from {preset, level, fs}.
        canonical_.crossfeed = deriveCrossfeedParams(
            crossfeed.enabled, crossfeed.level, crossfeed.preset,
            static_cast<double>(crossfeed.sampleRate));
    }
    canonical_.sequenceNumber += 1;
    publishCanonical();
}

void Realizer::applyEqGains(
    const std::array<float, static_cast<size_t>(EQModuleCoefficients::kNumBands)>& gains,
    float sampleRate)
{
    // Synchronously-callable RMW (testability, design §1.7). EQ design happens here, off the
    // RT thread. Bumps sequenceNumber and publishes once. Preserves all non-EQ fields.
    canonical_.eq = EQModuleCoefficients::computeBiquadCascade(gains, sampleRate);
    canonical_.sequenceNumber += 1;
    publishCanonical();
}

void Realizer::applyIntensity(float value)
{
    // Synchronously-callable RMW (testability, design §1.7). Preserves all non-intensity
    // fields. Caller is responsible for clamping (setPendingIntensity clamps at the surface).
    canonical_.intensityLinear = value;
    canonical_.sequenceNumber += 1;
    publishCanonical();
}

void Realizer::applyCrossfeed(uint32_t enabled, float level, uint32_t preset, double sampleRate)
{
    // Synchronously-callable RMW (testability, design §1.7). Derives the coefficients OFF-RT here,
    // RMW canonical_.crossfeed (preserving every other field). Caller is responsible for clamping
    // (setPendingCrossfeed clamps level/preset at the surface).
    canonical_.crossfeed = deriveCrossfeedParams(enabled, level, preset, sampleRate);
    canonical_.sequenceNumber += 1;
    publishCanonical();
}

void Realizer::publishCanonical()
{
    // The SOLE publishTargetState call site. Calls the kernel DIRECTLY (never captures the
    // ObjC AU). The kernel is guaranteed alive: blocks capture shared_from_this(), and
    // shutdown() drains before the owner releases the kernel.
    // NOLINTNEXTLINE(cppcoreguidelines-pro-type-vararg) PERMANENT reason="NSLog is the platform logging API"
    NSLog(@"[QW1] Realizer.publishCanonical seq=%llu intensity=%.4f crossfeed{enabled=%u preset=%u} "
          @"eq{numBiquads=%u}",
          static_cast<unsigned long long>(canonical_.sequenceNumber), canonical_.intensityLinear,
          canonical_.crossfeed.enabled, canonical_.crossfeed.preset,
          static_cast<unsigned>(canonical_.eq.numBiquads));
    if (kernel_ != nullptr)
    {
        kernel_->publishTargetState(canonical_);
    }
}

} // namespace AdaptiveSound
