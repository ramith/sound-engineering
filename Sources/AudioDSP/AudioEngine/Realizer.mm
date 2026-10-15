#import "Realizer.h"

#import <Foundation/Foundation.h> // Obj-C++ TU (dispatch); diagnostics go through AsLog

#include "../EQ/EQTargets.h" // design → EQParams, and the τ rule
#include "../Limiting/OutputCeiling.h" // decision 29: the EQ-only ceiling per transport
#include "../include/AsLog.h" // AdaptiveSound::log — off-RT control-plane logging seam

#include <algorithm> // std::clamp
#include <cmath>     // std::exp, std::isfinite
#include <optional>  // the queue-taken loudness copy
#include <utility>   // std::move

namespace AdaptiveSound
{

namespace
{
    // The crossfeed presets: bs2b's levels (libbs2b bs2b.h, BS2B_*_CLEVEL) — the cut frequency of
    // the cross-path low-pass and the feed, the low-frequency level of the cross path against the
    // direct path. Council P2-3 / C-42: the UI's three strengths are bs2b's own levels.
    struct Bs2bLevel
    {
        double fcutHz;
        double feedDb;
    };
    constexpr Bs2bLevel kBs2bJmeier = {.fcutHz = 650.0, .feedDb = 9.5};  // BS2B_JMEIER_CLEVEL
    constexpr Bs2bLevel kBs2bCmoy = {.fcutHz = 700.0, .feedDb = 6.0};    // BS2B_CMOY_CLEVEL
    constexpr Bs2bLevel kBs2bDefault = {.fcutHz = 700.0, .feedDb = 4.5}; // BS2B_DEFAULT_CLEVEL

    [[nodiscard]] auto bs2bLevel(uint32_t preset) -> Bs2bLevel
    {
        switch (static_cast<CrossfeedPreset>(static_cast<uint8_t>(preset)))
        {
        case CrossfeedPreset::Jmeier:
            return kBs2bJmeier;
        case CrossfeedPreset::Cmoy:
            return kBs2bCmoy;
        case CrossfeedPreset::Bs2bDefault:
            return kBs2bDefault;
        }
        return kBs2bCmoy; // unreachable (the preset is clamped at the surface)
    }

    // 20·log10: linear amplitude ↔ dB (bs2b's gains; the ceiling in its log line).
    constexpr double kAmplitudeDbScale = 20.0;
    constexpr double kTwoPi = 6.28318530717958647692;

    // The CrossfeedParams the module plays for {enabled, preset} at sampleRate: bs2b's init()
    // (libbs2b src/bs2b.c, MIT © 2005 Boris Mikhaylov; re-implemented from the published source,
    // not linked — OQ-17), in double precision, with its output gain folded into the numerators:
    //   GB_lo = −feed·5/6 − 3 dB, GB_hi = feed/6 − 3 dB     (so GB_lo − GB_hi = −feed)
    //   G_lo = 10^(GB_lo/20),  G_hi = 1 − 10^(GB_hi/20),  Fc_hi = Fc_lo·2^((GB_lo − 20·log10 G_hi)/12)
    //   low-pass (cross):  a0_lo = G_lo·(1 − x_lo), b1_lo = x_lo,        x_lo = e^(−2π·Fc_lo/fs)
    //   high-boost (direct): a0_hi = 1 − G_hi·(1 − x_hi), a1_hi = −x_hi, b1_hi = x_hi = e^(−2π·Fc_hi/fs)
    //   gain = 1 / (1 − G_hi + G_lo)   — a centred (L = R) signal at DC passes at exactly 0 dB.
    //
    // IMPORTANT (click-free DISABLE): the coefficients are ALWAYS derived, even when enabled == 0.
    // `enabled` drives only the module's glide target; the coefficients are the crossfeed it glides
    // out of. Zeroed coefficients would make the crossfed signal the input instantly — a snap — and
    // leave the glide nothing to fade. The DEFAULT CrossfeedParams{} (enabled = 0, the identity) is
    // what a never-enabled kernel plays (the golden master / CF-1 anchor).
    [[nodiscard]] auto deriveCrossfeedParams(uint32_t enabled, uint32_t preset, double sampleRate)
        -> CrossfeedParams
    {
        CrossfeedParams params{};
        params.enabled = (enabled != 0U) ? 1U : 0U;
        params.preset = static_cast<uint8_t>(preset);

        const Bs2bLevel level = bs2bLevel(preset);
        constexpr double kLowPassShare = -5.0 / 6.0;
        constexpr double kHighShelfShare = 1.0 / 6.0;
        constexpr double kGainOffsetDb = -3.0;
        constexpr double kSemitonesPerOctave = 12.0;
        const double gainLowDb = (level.feedDb * kLowPassShare) + kGainOffsetDb;
        const double gainHighDb = (level.feedDb * kHighShelfShare) + kGainOffsetDb;
        const double gainLow = std::pow(10.0, gainLowDb / kAmplitudeDbScale);
        const double gainHigh = 1.0 - std::pow(10.0, gainHighDb / kAmplitudeDbScale);
        const double cutHighHz =
            level.fcutHz *
            std::pow(2.0, (gainLowDb - (kAmplitudeDbScale * std::log10(gainHigh))) / kSemitonesPerOctave);
        const double gain = 1.0 / (1.0 - gainHigh + gainLow);

        const double poleLow = std::exp(-kTwoPi * level.fcutHz / sampleRate);
        const double poleHigh = std::exp(-kTwoPi * cutHighHz / sampleRate);
        params.crossB0 = static_cast<float>(gain * gainLow * (1.0 - poleLow));
        params.crossPole = static_cast<float>(poleLow);
        params.directB0 = static_cast<float>(gain * (1.0 - (gainHigh * (1.0 - poleHigh))));
        params.directB1 = static_cast<float>(-gain * poleHigh);
        params.directPole = static_cast<float>(poleHigh);
        return params;
    }
} // namespace

namespace
{
    // Marks the Realizer's own queue (dispatch_queue_set_specific), so shutdown() never
    // dispatch_syncs onto the queue it is running on.
    constexpr char kQueueKey = 0;

    // The idle debounce before an edit's gain is refreshed at full resolution (A6).
    constexpr int64_t kLoudnessRefreshDelayNs = 150 * static_cast<int64_t>(NSEC_PER_MSEC);

    // Run `work(Realizer&)` on `queue` if the Realizer still exists by then. A block captures a
    // C++ REFERENCE by reference, so the work and the weak reference move to the heap and the
    // block owns them until it runs. The Realizer is only ever locked ON the queue — never on the
    // caller's thread (the kernel's tap worker must never drop its last reference).
    template <typename Work>
    void postWeak(dispatch_queue_t queue, std::weak_ptr<Realizer> weak, Work work)
    {
        auto task = std::make_shared<Work>(std::move(work));
        auto target = std::make_shared<std::weak_ptr<Realizer>>(std::move(weak));
        dispatch_async(queue, ^{
            if (std::shared_ptr<Realizer> self = target->lock())
            {
                (*task)(*self);
            }
        });
    }
} // namespace

Realizer::Realizer(std::shared_ptr<DSPKernel> kernel, double sampleRate)
    : kernel_(std::move(kernel)), designer_(std::make_unique<GraphicEQDesigner>()),
      sampleRate_(sampleRate), designRate_(sampleRate), loudness_(sampleRate)
{
    // Serial, off-main queue. The control plane is not latency critical and must never run on
    // the RT/render thread.
    queue_ = dispatch_queue_create("com.adaptivesound.realizer", DISPATCH_QUEUE_SERIAL);
    dispatch_queue_set_specific(queue_, &kQueueKey, this, nullptr);
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
    // Draining barrier: a dispatch_sync on a SERIAL queue returns only after every
    // previously-enqueued block has finished, so no drain runs after the caller drops the
    // Realizer and releases the kernel. It also ends any causal loudness estimate, so the
    // kernel's tap never calls back into a Realizer that is going away. On the queue itself
    // (the last reference dropped by a block) there is nothing to wait for.
    Realizer* self = this;
    if (dispatch_get_specific(&kQueueKey) == this)
    {
        stopCausalEstimate();
    }
    else
    {
        dispatch_sync(queue_, ^{
            self->stopCausalEstimate();
        });
    }
    shutdown_ = true;
}

void Realizer::barrier()
{
    if (queue_ == nullptr)
    {
        return;
    }
    dispatch_sync(queue_, ^{
                  });
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

void Realizer::setPendingCrossfeed(uint32_t enabled, uint32_t preset)
{
    constexpr uint32_t kMaxPreset = static_cast<uint32_t>(CrossfeedPreset::Bs2bDefault);
    const CrossfeedIntent intent{
        .enabled = enabled,
        .preset = std::clamp(preset, 0U, kMaxPreset),
    };
    const bool post = writeSlot(pendingCrossfeed_, intent);
    AdaptiveSound::log::debug("[QW1] Realizer.setPendingCrossfeed enabled={} preset={} -> {}",
                              intent.enabled, intent.preset,
                              post ? "POST drain" : "coalesced (drain pending)");
    if (post)
    {
        postDrain();
    }
}

void Realizer::publishTrackLoudnessProfile(uint64_t token,
                                           std::shared_ptr<const TrackLoudnessProfile> profile)
{
    if (token == 0U || !profile)
    {
        return;
    }
    postWeak(queue_, weak_from_this(), [token, profile = std::move(profile)](Realizer& self) {
        if (const auto change = self.loudness_.onProfile(token, profile))
        {
            self.applyGainChange(*change);
        }
        self.syncCausalEstimate(false); // a profile ends a running estimate
    });
}

void Realizer::reportTrackLoudnessFailure(uint64_t token)
{
    if (token == 0U)
    {
        return;
    }
    postWeak(queue_, weak_from_this(), [token](Realizer& self) {
        self.loudness_.onFailure(token);
        self.syncCausalEstimate(false);
    });
}

void Realizer::setOutputTransport(uint32_t transportType)
{
    postWeak(queue_, weak_from_this(), [transportType](Realizer& self) {
        const float ceiling = eqOnlyCeilingLinear(transportType);
        if (ceiling == self.canonical_.limiter.eqOnlyCeilingLinear)
        {
            return;
        }
        self.canonical_.limiter.eqOnlyCeilingLinear = ceiling;
        self.canonical_.sequenceNumber += 1;
        AdaptiveSound::log::line("[EQ] output transport {:08x}: EQ-only ceiling {:+.1f} dBTP",
                                 transportType, kAmplitudeDbScale * std::log10(static_cast<double>(ceiling)));
        self.publishCanonical();
    });
}

void Realizer::setCurrentTrack(uint64_t token, bool gaplessSeam)
{
    postWeak(queue_, weak_from_this(), [token, gaplessSeam](Realizer& self) {
        const auto change = self.loudness_.onCurrentTrack(token, gaplessSeam);
        if (change)
        {
            self.applyGainChange(*change);
        }
        AdaptiveSound::log::line("[EQ] loudness: track {:016x} audible ({}) — gain {:+.2f} dB{}",
                                 static_cast<unsigned long long>(token),
                                 gaplessSeam ? "gapless seam" : "fresh start",
                                 self.loudness_.gainDb(),
                                 self.loudness_.sharesGroupGain() ? ", shared by the gapless group"
                                                                  : "");
        self.syncCausalEstimate(true); // a new track: any estimate starts over
    });
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
    loudness_.setOutputRate(sampleRate_);
    // Re-realise every rate-dependent intent at the new rate. The EQ module snaps to the first
    // target it adopts after initialize(), so the curve plays at once — no fade-in from flat.
    realizeEq();
    realizeCrossfeed();
    // initialize() rebuilt the kernel's causal tap: a running estimate starts again on it.
    causalRunning_ = false;
    syncCausalEstimate(false);
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
        scheduleLoudnessRefresh();
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
        publishedDesign_ = GraphicEQDesign{};
        (void)loudness_.onDesign(GraphicEQDesign(), false);
        return;
    }
    // Each band glides at its own τ, from what was last published (amendment 15).
    canonical_.eq = EQTargets::toParams(design, EQTargets::rampsFor(publishedDesign_, design));
    publishedDesign_ = design;
    // The loudness-neutral gain rides with the coefficients, at the rule's gain τ (decimated for a
    // long profile; the idle refresh completes it).
    canonical_.eq.outputGainDb = loudness_.onDesign(design, eq_.isOn);
}

void Realizer::realizeCrossfeed()
{
    canonical_.crossfeed = deriveCrossfeedParams(crossfeed_.enabled, crossfeed_.preset, sampleRate_);
}

template <typename Work> void Realizer::runOnQueue(const Work& work)
{
    if (queue_ == nullptr || dispatch_get_specific(&kQueueKey) == this)
    {
        work();
        return;
    }
    dispatch_sync(queue_, ^{
        work();
    });
}

TargetState Realizer::canonicalState()
{
    TargetState copy{};
    runOnQueue([this, &copy] { copy = canonical_; });
    return copy;
}

TrackLoudnessGain Realizer::loudnessGain()
{
    std::optional<TrackLoudnessGain> copy;
    runOnQueue([this, &copy] { copy.emplace(loudness_); });
    return *copy;
}

void Realizer::applyEq(const EqIntent& intent)
{
    runOnQueue([this, intent] {
        eq_ = intent;
        realizeEq();
        canonical_.sequenceNumber += 1;
        publishCanonical();
        scheduleLoudnessRefresh();
    });
}

void Realizer::applyIntensity(float value)
{
    runOnQueue([this, value] {
        canonical_.intensityLinear = value;
        canonical_.sequenceNumber += 1;
        publishCanonical();
    });
}

void Realizer::applyCrossfeed(const CrossfeedIntent& intent)
{
    runOnQueue([this, intent] {
        crossfeed_ = intent;
        realizeCrossfeed();
        canonical_.sequenceNumber += 1;
        publishCanonical();
    });
}

void Realizer::applyGainChange(const TrackLoudnessGain::Change& change)
{
    // A gain-only publish: the coefficients' targets are unchanged, so only the EQ module's
    // output gain glides, at this change's τ.
    canonical_.eq.outputGainDb = change.gainDb;
    canonical_.eq.gainRampSeconds = change.rampSeconds;
    canonical_.sequenceNumber += 1;
    AdaptiveSound::log::debug("[EQ] loudness: gain {:+.2f} dB over τ {:.3f} s", change.gainDb,
                              change.rampSeconds);
    publishCanonical();
}

void Realizer::stopCausalEstimate()
{
    if (causalRunning_ && kernel_ != nullptr)
    {
        kernel_->stopCausalLoudness();
    }
    causalRunning_ = false;
    causalGeneration_ += 1; // any snapshot still in flight is dropped
}

void Realizer::syncCausalEstimate(bool restart)
{
    const bool wanted = loudness_.wantsCausalEstimate();
    if (causalRunning_ && (restart || !wanted))
    {
        stopCausalEstimate();
    }
    if (!wanted || causalRunning_ || kernel_ == nullptr)
    {
        return;
    }
    // The tap's worker calls the sink, which only posts to the queue: the Realizer is never
    // locked on the tap's thread, so its last reference can never be dropped there.
    causalGeneration_ += 1;
    const uint64_t generation = causalGeneration_;
    kernel_->startCausalLoudness(
        [weak = weak_from_this(), queue = queue_, generation](
            std::shared_ptr<const TrackLoudnessProfile> profile) {
            postWeak(queue,
                     weak,
                     [generation, snapshot = std::move(profile)](Realizer& self) {
                         self.applyCausalSnapshot(generation, snapshot);
                     });
        });
    causalRunning_ = true;
    AdaptiveSound::log::line("[EQ] loudness: no track analysis — estimating from the audio as it plays");
}

void Realizer::applyCausalSnapshot(uint64_t generation,
                                   std::shared_ptr<const TrackLoudnessProfile> profile)
{
    if (generation != causalGeneration_ || !causalRunning_)
    {
        return; // from an estimate that has since ended
    }
    if (const auto change = loudness_.onCausalSnapshot(std::move(profile)))
    {
        applyGainChange(*change);
    }
}

void Realizer::scheduleLoudnessRefresh()
{
    if (!loudness_.needsRefresh())
    {
        return;
    }
    refreshGeneration_ += 1;
    const uint64_t generation = refreshGeneration_;
    std::weak_ptr<Realizer> weak = weak_from_this();
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, kLoudnessRefreshDelayNs), queue_, ^{
        std::shared_ptr<Realizer> self = weak.lock();
        if (self == nullptr || generation != self->refreshGeneration_)
        {
            return; // a later edit re-armed it
        }
        if (const auto change = self->loudness_.onRefresh())
        {
            self->applyGainChange(*change);
        }
    });
}

void Realizer::publishCanonical()
{
    // The SOLE publishTargetState call site. Per-publish detail is debug-level (amendment 6).
    AdaptiveSound::log::debug("[QW1] Realizer.publishCanonical seq={} intensity={:.4f} "
                              "crossfeed{{enabled={} preset={}}} eq{{fs={} gainRamp={:.3f}s}}",
                              static_cast<unsigned long long>(canonical_.sequenceNumber),
                              canonical_.intensityLinear, canonical_.crossfeed.enabled,
                              canonical_.crossfeed.preset, canonical_.eq.designSampleRate,
                              canonical_.eq.gainRampSeconds);
    if (kernel_ != nullptr)
    {
        kernel_->publishTargetState(canonical_);
    }
}

} // namespace AdaptiveSound
