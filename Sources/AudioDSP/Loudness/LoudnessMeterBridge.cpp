// LoudnessMeterBridge.cpp
//
// C-ABI wrapper around the validated BS.1770-5 LufsMeter so the Swift playback
// tap can drive real loudness meters without reimplementing the DSP in Swift.
//
// Threading: loudnessMeterAddStereo() is called on the audio-tap thread — it runs
// the (allocation-free, lock-free) LufsMeter and snapshots results into atomics.
// loudnessMeterRead() reads those atomics from the UI thread. create/destroy are
// off-RT (engine init/teardown).

#include "../include/DeviceBridge.h"
#include "../include/TruePeakKernel.h"
#include "LufsMeter.h"
#include <algorithm>
#include <array>
#include <atomic>
#include <cmath>
#include <cstdint>
#include <new>

namespace
{
    constexpr float kPeakDecayPerBuffer = 0.85F; // ~150 ms visual decay at tap rate
    constexpr double kPeakFloorDb = -120.0;
    constexpr double kPeakFloorLinear = 1.0e-6;
    constexpr double kDbAmplitudeScale = 20.0;
    constexpr double kUnmeasuredLufs = -200.0;
    constexpr uint32_t kTruePeakChannels = 2U;

    struct LoudnessMeterHandle
    {
        AdaptiveSound::LufsMeter meter;
        std::atomic<double> integrated{kUnmeasuredLufs};
        std::atomic<double> shortTerm{kUnmeasuredLufs};
        std::atomic<double> momentary{kUnmeasuredLufs};
        std::atomic<double> truePeakDb{kPeakFloorDb};

        // True-peak state (S10.8 PR E — the meter path was SAMPLE-peak before; the UI's
        // "True peak" label is honest only because this is the same 8× polyphase ISP
        // kernel the limiter's ceiling runs). Tap-thread only.
        AdaptiveSound::TruePeakKernel::Coefficients ispCoeffs{};
        std::array<std::array<double, AdaptiveSound::TruePeakKernel::kNumTaps>, kTruePeakChannels>
            histories{}; // newest-first windows, shifted per sample
        double truePeakLinear = 0.0;
    };

    static_assert(std::atomic<double>::is_always_lock_free,
                  "Loudness readout requires lock-free double atomics");
} // namespace

void* loudnessMeterCreate(double sampleRate) AUDIODSP_C_NOEXCEPT
{
    auto* handle = new (std::nothrow) LoudnessMeterHandle();
    if (handle != nullptr)
    {
        handle->meter.prepare(sampleRate);
        AdaptiveSound::TruePeakKernel::computeCoefficients(handle->ispCoeffs);
    }
    return handle;
}

void loudnessMeterDestroy(void* meter) AUDIODSP_C_NOEXCEPT
{
    delete static_cast<LoudnessMeterHandle*>(meter);
}

void loudnessMeterAddStereo(void* meter, const float* left, const float* right, uint32_t frames)
    AUDIODSP_C_NOEXCEPT
{
    auto* handle = static_cast<LoudnessMeterHandle*>(meter);
    if (handle == nullptr || left == nullptr)
    {
        return;
    }
    const float* rightChannel = (right != nullptr) ? right : left;
    handle->meter.addNonInterleavedStereo(left, rightChannel, frames);

    // Inter-sample TRUE peak (8× polyphase ISP — the shared TruePeakKernel), with the
    // same per-buffer visual decay the old sample-peak readout used. Histories are
    // newest-first shift registers (24 doubles/channel; the shift is cheaper than the
    // 8×24 dot products that follow it). Mono runs ONE channel — the aliased right would
    // reproduce channel 0's dot products exactly (break-it finding 7).
    using AdaptiveSound::TruePeakKernel::kNumTaps;
    const uint32_t activeChannels = (right != nullptr) ? kTruePeakChannels : 1U;
    double peak = handle->truePeakLinear * kPeakDecayPerBuffer;
    for (uint32_t i = 0U; i < frames; ++i)
    {
        const std::array<double, kTruePeakChannels> samples{static_cast<double>(left[i]),
                                                            static_cast<double>(rightChannel[i])};
        for (uint32_t ch = 0U; ch < activeChannels; ++ch)
        {
            auto& hist = handle->histories[ch];
            for (uint32_t k = kNumTaps - 1U; k > 0U; --k)
            {
                hist[k] = hist[k - 1U];
            }
            hist[0] = samples[ch];
            peak =
                std::max(peak, AdaptiveSound::TruePeakKernel::phasePeak(hist, handle->ispCoeffs));
        }
    }
    handle->truePeakLinear = peak;
    const double truePeakDecibels =
        (peak > kPeakFloorLinear) ? (kDbAmplitudeScale * std::log10(peak)) : kPeakFloorDb;

    handle->integrated.store(handle->meter.integratedLufs(), std::memory_order_release);
    handle->shortTerm.store(handle->meter.shortTermLufs(), std::memory_order_release);
    handle->momentary.store(handle->meter.momentaryLufs(), std::memory_order_release);
    handle->truePeakDb.store(truePeakDecibels, std::memory_order_release);
}

CLoudnessReadout loudnessMeterRead(void* meter) AUDIODSP_C_NOEXCEPT
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
    out.truePeakDb = handle->truePeakDb.load(std::memory_order_acquire);
    return out;
}
