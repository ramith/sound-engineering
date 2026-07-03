// LoudnessMeterBridge.mm
//
// C-ABI wrapper around the validated BS.1770-5 LufsMeter so the Swift playback
// tap can drive real loudness meters without reimplementing the DSP in Swift.
//
// Threading: loudnessMeterAddStereo() is called on the audio-tap thread — it runs
// the (allocation-free, lock-free) LufsMeter and snapshots results into atomics.
// loudnessMeterRead() reads those atomics from the UI thread. create/destroy are
// off-RT (engine init/teardown).

#include "../include/DeviceBridge.h"
#include "LufsMeter.h"
#include <algorithm>
#include <atomic>
#include <cmath>
#include <new>

namespace
{
    constexpr float kPeakDecayPerBuffer = 0.85F; // ~150 ms visual decay at tap rate
    constexpr double kPeakFloorDb = -120.0;
    constexpr float kPeakFloorLinear = 1.0e-6F;
    constexpr double kDbAmplitudeScale = 20.0;
    constexpr double kUnmeasuredLufs = -200.0;

    struct LoudnessMeterHandle
    {
        AdaptiveSound::LufsMeter meter;
        std::atomic<double> integrated{kUnmeasuredLufs};
        std::atomic<double> shortTerm{kUnmeasuredLufs};
        std::atomic<double> momentary{kUnmeasuredLufs};
        std::atomic<double> peakDb{kPeakFloorDb};
        float peakLinear = 0.0F; // tap-thread only
    };

    static_assert(std::atomic<double>::is_always_lock_free,
                  "Loudness readout requires lock-free double atomics");
} // namespace

void* loudnessMeterCreate(double sampleRate)
{
    auto* handle = new (std::nothrow) LoudnessMeterHandle();
    if (handle != nullptr)
    {
        handle->meter.prepare(sampleRate);
    }
    return handle;
}

void loudnessMeterDestroy(void* meter)
{
    delete static_cast<LoudnessMeterHandle*>(meter);
}

void loudnessMeterAddStereo(void* meter, const float* left, const float* right, uint32_t frames)
{
    auto* handle = static_cast<LoudnessMeterHandle*>(meter);
    if (handle == nullptr || left == nullptr)
    {
        return;
    }
    const float* rightChannel = (right != nullptr) ? right : left;
    handle->meter.addNonInterleavedStereo(left, rightChannel, frames);

    // Sample-peak with per-buffer decay (the true-peak limiter is not in this path).
    float peak = handle->peakLinear * kPeakDecayPerBuffer;
    for (uint32_t i = 0U; i < frames; ++i)
    {
        peak = std::max({peak, std::abs(left[i]), std::abs(rightChannel[i])});
    }
    handle->peakLinear = peak;
    const double peakDecibels =
        (peak > kPeakFloorLinear) ? (kDbAmplitudeScale * std::log10(peak)) : kPeakFloorDb;

    handle->integrated.store(handle->meter.integratedLufs(), std::memory_order_release);
    handle->shortTerm.store(handle->meter.shortTermLufs(), std::memory_order_release);
    handle->momentary.store(handle->meter.momentaryLufs(), std::memory_order_release);
    handle->peakDb.store(peakDecibels, std::memory_order_release);
}

CLoudnessReadout loudnessMeterRead(void* meter)
{
    CLoudnessReadout out{kUnmeasuredLufs, kUnmeasuredLufs, kUnmeasuredLufs, kPeakFloorDb};
    auto* handle = static_cast<LoudnessMeterHandle*>(meter);
    if (handle == nullptr)
    {
        return out;
    }
    out.integratedLufs = handle->integrated.load(std::memory_order_acquire);
    out.shortTermLufs = handle->shortTerm.load(std::memory_order_acquire);
    out.momentaryLufs = handle->momentary.load(std::memory_order_acquire);
    out.peakDb = handle->peakDb.load(std::memory_order_acquire);
    return out;
}
