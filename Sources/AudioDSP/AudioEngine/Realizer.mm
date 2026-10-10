#import "Realizer.h"

#import <Foundation/Foundation.h> // Obj-C++ TU (dispatch); diagnostics go through AsLog

#include "../EQ/EQTargets.h" // design → EQParams, and the τ rule
#include "../include/AsLog.h" // AdaptiveSound::log — off-RT control-plane logging seam

#include <algorithm> // std::clamp
#include <cmath>     // std::exp, std::isfinite

namespace AdaptiveSound
{

namespace
{
    // Preset → (fc, alpha) resolution table (QW1 §2/§5). The middle case is `Bauer`; the Swift
    // label stays "Default". These are bs2b-INSPIRED, not the bs2b coefficient sets: the DSP model
    // is a simplified Chu-Moy-style flat-direct + one-pole-LPF-cross (see CrossfeedModule), not
    // bs2b's complementary low/high-shelf topology, so the values approximate rather than reproduce
    // it. The cut frequencies match bs2b (650/700/700 Hz); the alphas are chosen to form a
    // MONOTONIC crossfeed-depth ladder Relaxed < Bauer < Strong (gCross = α/(1+α) is monotonic in
    // α). Off-RT only (called from the Realizer's serial queue / a test).
    //
    // Stage-1 review AC-3 (deferred, founder call): Bauer (0.355) sits only ~0.5 dB of gCross above
    // Relaxed (0.335), so the "Default" middle preset is barely distinct from Relaxed. The review
    // noted 0.355 doesn't match bs2b's Default 4.5 dB feed, but do NOT blindly set α=0.596 — that
    // exceeds Strong (0.501) and inverts the ladder. Any change here is a listening/UX decision
    // about how distinct the three rungs should be, not a mechanical coefficient correction.
    struct CrossfeedPresetCoeffs
    {
        float fcHz;
        float alpha;
    };

    // Labels are the UX depth rungs; the bs2b names are the design origins of each cut frequency.
    constexpr CrossfeedPresetCoeffs kCrossfeedRelaxed = {.fcHz = 650.0F, .alpha = 0.335F}; // ~Jmeier fc
    constexpr CrossfeedPresetCoeffs kCrossfeedBauer = {.fcHz = 700.0F, .alpha = 0.355F};   // ~Default fc
    constexpr CrossfeedPresetCoeffs kCrossfeedStrong = {.fcHz = 700.0F, .alpha = 0.501F};  // ~Cmoy fc

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

Realizer::Realizer(std::shared_ptr<DSPKernel> kernel, double sampleRate)
    : kernel_(std::move(kernel)), designer_(std::make_unique<GraphicEQDesigner>()),
      sampleRate_(sampleRate), designRate_(sampleRate)
{
    // Serial, off-main queue. The control plane is not latency critical and must never run on
    // the RT/render thread.
    queue_ = dispatch_queue_create("com.adaptivesound.realizer", DISPATCH_QUEUE_SERIAL);
}

Realizer::~Realizer()
{
    // Defensive: if the owner forgot to call shutdown(), drain now so no block outlives us.
    shutdown();
}

void Realizer::shutdown()
{
    if (queue_ == nullptr || shutdown_)
    {
        return;
    }
    // Draining barrier: a dispatch_sync of an empty block on a SERIAL queue returns only after
    // every previously-enqueued block has finished, so no drain runs after the caller drops the
    // Realizer and releases the kernel.
    dispatch_sync(queue_, ^{
                  });
    shutdown_ = true;
}

void Realizer::postDrain()
{
    std::shared_ptr<Realizer> self = shared_from_this();
    dispatch_async(queue_, ^{
        self->drain();
    });
}

template <typename T> bool Realizer::writeSlot(PendingSlot<T>& slot, const T& intent)
{
    const std::scoped_lock lock(slotMutex_);
    slot.write(intent);
    const bool post = !drainPosted_;
    drainPosted_ = true;
    return post;
}

bool Realizer::setPendingEq(const float* pointsDb, uint32_t count, bool isOn)
{
    if (pointsDb == nullptr || count != static_cast<uint32_t>(kEqBandCount))
    {
        return false;
    }
    EqIntent intent{};
    intent.isOn = isOn;
    for (size_t band = 0; band < intent.points.size(); ++band)
    {
        const float point = pointsDb[band];
        if (!std::isfinite(point))
        {
            AdaptiveSound::log::line("[EQ] Realizer.setPendingEq REJECT — point {} is not finite", band);
            return false;
        }
        intent.points[band] = std::clamp(point, -kEQMaxGainDb, kEQMaxGainDb);
    }

    const bool post = writeSlot(pendingEq_, intent);
    AdaptiveSound::log::debug("[QW1] Realizer.setPendingEq on={} -> {}", isOn,
                              post ? "POST drain" : "coalesced (drain pending)");
    if (post)
    {
        postDrain();
    }
    return true;
}

void Realizer::setPendingIntensity(float value)
{
    const IntensityIntent intent{.value = std::clamp(value, 0.0F, 1.0F)};
    const bool post = writeSlot(pendingIntensity_, intent);
    AdaptiveSound::log::debug("[QW1] Realizer.setPendingIntensity value={:.4f} -> {}", intent.value,
                              post ? "POST drain" : "coalesced (drain pending)");
    if (post)
    {
        postDrain();
    }
}

void Realizer::setPendingCrossfeed(uint32_t enabled, float level, uint32_t preset)
{
    constexpr uint32_t kMaxPreset = static_cast<uint32_t>(CrossfeedPreset::Strong);
    const CrossfeedIntent intent{
        .enabled = enabled,
        .level = std::clamp(level, 0.0F, 1.0F),
        .preset = std::clamp(preset, 0U, kMaxPreset),
    };
    const bool post = writeSlot(pendingCrossfeed_, intent);
    AdaptiveSound::log::debug("[QW1] Realizer.setPendingCrossfeed enabled={} level={:.4f} preset={} -> {}",
                              intent.enabled, intent.level, intent.preset,
                              post ? "POST drain" : "coalesced (drain pending)");
    if (post)
    {
        postDrain();
    }
}

void Realizer::reinitializeKernel(uint32_t sampleRate, uint32_t maxFrames)
{
    if (queue_ == nullptr || shutdown_)
    {
        reinitializeOnQueue(sampleRate, maxFrames); // no queue left to serialise with
        return;
    }
    // Serialise with every publish (the use-after-free race of architect F3). The Realizer never
    // waits on the allocating thread, so this cannot deadlock.
    Realizer* self = this;
    dispatch_sync(queue_, ^{
        self->reinitializeOnQueue(sampleRate, maxFrames);
    });
}

void Realizer::reinitializeOnQueue(uint32_t sampleRate, uint32_t maxFrames)
{
    if (kernel_ != nullptr)
    {
        kernel_->initialize(sampleRate, maxFrames);
    }
    sampleRate_ = static_cast<double>(sampleRate);
    designRate_.store(sampleRate_, std::memory_order_release);
    // Re-realise every rate-dependent intent at the new rate. The EQ module snaps to the first
    // target it adopts after initialize(), so the curve plays at once — no fade-in from flat.
    realizeEq();
    realizeCrossfeed();
    canonical_.sequenceNumber += 1;
    AdaptiveSound::log::line("[EQ] Realizer.reinitializeKernel {} Hz, {} frames — EQ re-solved",
                             sampleRate, maxFrames);
    publishCanonical();
}

void Realizer::drain()
{
    dispatch_assert_queue_debug(queue_);

    // Take the dirty slots and clear drainPosted_ under the lock, then realise and publish without
    // it. A write after the take finds no drain pending and posts a fresh one, so no intent is
    // lost — and at most one untaken drain is ever queued.
    EqIntent eq{};
    IntensityIntent intensity{};
    CrossfeedIntent crossfeed{};
    bool eqDirty = false;
    bool intensityDirty = false;
    bool crossfeedDirty = false;
    {
        const std::scoped_lock lock(slotMutex_);
        eqDirty = pendingEq_.take(eq);
        intensityDirty = pendingIntensity_.take(intensity);
        crossfeedDirty = pendingCrossfeed_.take(crossfeed);
        drainPosted_ = false;
    }
    if (!eqDirty && !intensityDirty && !crossfeedDirty)
    {
        return; // defensive: a posted drain always finds the slot whose write posted it
    }
    AdaptiveSound::log::debug("[QW1] Realizer.drain: eq={} intensity={} crossfeed={}",
                              static_cast<int>(eqDirty), static_cast<int>(intensityDirty),
                              static_cast<int>(crossfeedDirty));
    if (eqDirty)
    {
        eq_ = eq;
        realizeEq();
    }
    if (intensityDirty)
    {
        canonical_.intensityLinear = intensity.value;
    }
    if (crossfeedDirty)
    {
        crossfeed_ = crossfeed;
        realizeCrossfeed();
    }
    canonical_.sequenceNumber += 1;
    publishCanonical();
}

void Realizer::realizeEq()
{
    // Off is the flat design: k = k0 and m1 = 0 exactly — the RT module's identity.
    const std::array<float, kEqBandCount> flat{};
    const std::array<float, kEqBandCount>& points = eq_.isOn ? eq_.points : flat;
    GraphicEQDesign design{};
    if (!designer_->design(points, sampleRate_, design))
    {
        // Outside the design domain (a rate under 44 kHz): play the identity, never a curve
        // designed for another rate (engine-plan §6). Non-finite points never get here.
        AdaptiveSound::log::line("[EQ] Realizer: no EQ design at {} Hz — playing flat", sampleRate_);
        canonical_.eq = EQParams{};
        publishedGainsDb_.fill(0.0);
        return;
    }
    const float ramp = EQTargets::rampSeconds(publishedGainsDb_, design.filterGainDb);
    canonical_.eq = EQTargets::toParams(design, ramp);
    publishedGainsDb_ = design.filterGainDb;
}

void Realizer::realizeCrossfeed()
{
    canonical_.crossfeed =
        deriveCrossfeedParams(crossfeed_.enabled, crossfeed_.level, crossfeed_.preset, sampleRate_);
}

void Realizer::applyEq(const EqIntent& intent)
{
    eq_ = intent;
    realizeEq();
    canonical_.sequenceNumber += 1;
    publishCanonical();
}

void Realizer::applyIntensity(float value)
{
    canonical_.intensityLinear = value;
    canonical_.sequenceNumber += 1;
    publishCanonical();
}

void Realizer::applyCrossfeed(const CrossfeedIntent& intent)
{
    crossfeed_ = intent;
    realizeCrossfeed();
    canonical_.sequenceNumber += 1;
    publishCanonical();
}

void Realizer::publishCanonical()
{
    // The SOLE publishTargetState call site. Per-publish detail is debug-level (amendment 6).
    AdaptiveSound::log::debug("[QW1] Realizer.publishCanonical seq={} intensity={:.4f} "
                              "crossfeed{{enabled={} preset={}}} eq{{fs={} ramp={:.3f}s}}",
                              static_cast<unsigned long long>(canonical_.sequenceNumber),
                              canonical_.intensityLinear, canonical_.crossfeed.enabled,
                              canonical_.crossfeed.preset, canonical_.eq.designSampleRate,
                              canonical_.eq.rampSeconds);
    if (kernel_ != nullptr)
    {
        kernel_->publishTargetState(canonical_);
    }
}

} // namespace AdaptiveSound
