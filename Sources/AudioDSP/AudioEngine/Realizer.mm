#import "Realizer.h"

#include <algorithm> // std::clamp
#include <cstring>   // std::memcpy

namespace AdaptiveSound
{

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

    if (!eqDirty && !intensityDirty)
    {
        return; // spurious wake (slot already drained by an earlier coalesced block)
    }

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

void Realizer::publishCanonical()
{
    // The SOLE publishTargetState call site. Calls the kernel DIRECTLY (never captures the
    // ObjC AU). The kernel is guaranteed alive: blocks capture shared_from_this(), and
    // shutdown() drains before the owner releases the kernel.
    if (kernel_ != nullptr)
    {
        kernel_->publishTargetState(canonical_);
    }
}

} // namespace AdaptiveSound
