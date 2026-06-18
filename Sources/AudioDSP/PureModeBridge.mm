//
// PureModeBridge.mm — CoreAudio (Obj-C++) glue exposing the Pure-Mode engine to Swift.
//
// Implements the capability-query + engine-session half of PureModeBridge.h. The CoreAudio-free
// policy (pureModeEvaluate) lives in PureModeBridgePolicy.cpp; this file is NOT compiled into the
// C++ test harness (it links CoreAudio).
//
// Ownership: the void* handle is a PureModeSession owned via RAII. The session owns the
// HALOutputEngine, the FileDecodeSource, and a tiny RT-safe adapter that forwards pullFloat() to
// the file source while counting rendered frames into an atomic. Teardown is idempotent and runs
// from the destructor: the FileDecodeSource dtor joins its decode thread; the HALOutputEngine dtor
// restores the device nominal rate and releases hog mode.
//
// -fno-exceptions / -fno-rtti clean.
//

#include "include/CoreAudioDevice.h"
#include "include/DeviceCapability.h"
#include "include/FileDecodeSource.h"
#include "include/HALOutputEngine.h"
#include "include/PureModeBridge.h"
#include "include/PureModeSource.h"

#include <atomic>
#include <cmath>
#include <cstdint>
#include <memory>
#include <new>

namespace
{
    using AdaptiveSound::AchievedOutputState;
    using AdaptiveSound::CoreAudioDevice;
    using AdaptiveSound::DeviceCapability;
    using AdaptiveSound::FileDecodeSource;
    using AdaptiveSound::FileFormat;
    using AdaptiveSound::HALOutputEngine;
    using AdaptiveSound::PureModeEvaluation;
    using AdaptiveSound::PureModeSource;

    // Decoder backend codes mirrored into CAchievedOutputState::decoderBackend.
    constexpr uint8_t kDecoderBackendApple = 0U;
    constexpr uint8_t kDecoderBackendFFmpeg = 1U;

    // RT-safe adapter: forwards pullFloat() to the wrapped FileDecodeSource and adds the produced
    // frame count to an atomic counter. No allocation, no lock, no throw on the render path
    // (memory_order_relaxed is sufficient — the counter is only read off-RT for position display).
    class CountingSource final : public PureModeSource
    {
      public:
        CountingSource(FileDecodeSource* source, std::atomic<uint64_t>* renderedFrames) noexcept
            : source_(source), renderedFrames_(renderedFrames)
        {
        }

        uint32_t pullFloat(float* out, uint32_t frames, uint32_t channels) noexcept override
        {
            const uint32_t produced = source_->pullFloat(out, frames, channels);
            renderedFrames_->fetch_add(produced, std::memory_order_relaxed);
            return produced;
        }

      private:
        FileDecodeSource* source_;            // borrowed; outlives this adapter (session-owned)
        std::atomic<uint64_t>* renderedFrames_; // borrowed; session-owned
    };

    // The opaque engine session behind the void* handle.
    struct PureModeSession
    {
        std::unique_ptr<HALOutputEngine> engine;
        std::unique_ptr<FileDecodeSource> source;
        std::unique_ptr<CountingSource> adapter;
        std::atomic<uint64_t> renderedFrames{0U};
        uint64_t seekBaseFrames = 0U;

        PureModeSession() : engine(std::make_unique<HALOutputEngine>()) {}
    };

    // Translate a C++ DeviceCapability into the flat C struct + rate array (clamped to maxRates).
    void copyCapabilityOut(const DeviceCapability& cap,
                           CDeviceCapability* outCap,
                           double* outRates,
                           uint32_t maxRates,
                           uint32_t* outRateCount) noexcept
    {
        outCap->deviceID = cap.id;
        outCap->transportType = cap.transportType;
        outCap->currentRate = cap.currentRate;
        outCap->physicalBitsPerChannel = cap.physicalFormat.bitsPerChannel;
        outCap->physicalChannels = cap.physicalFormat.channels;
        outCap->integerCapable = cap.integerCapable ? 1U : 0U;
        outCap->exclusiveCapable = cap.exclusiveCapable ? 1U : 0U;
        outCap->isLossyWireless = cap.isLossyWireless ? 1U : 0U;
        outCap->isVirtualOrAggregate = cap.isVirtualOrAggregate ? 1U : 0U;

        uint32_t written = 0U;
        if (outRates != nullptr)
        {
            for (const double rate : cap.availableRates)
            {
                if (written >= maxRates)
                {
                    break;
                }
                outRates[written] = rate;
                ++written;
            }
        }
        if (outRateCount != nullptr)
        {
            *outRateCount = written;
        }
    }
} // namespace

extern "C"
{
    int pureModeQueryCapability(uint32_t deviceID,
                                CDeviceCapability* outCap,
                                double* outRates,
                                uint32_t maxRates,
                                uint32_t* outRateCount)
    {
        if (outCap == nullptr)
        {
            return 0;
        }
        const DeviceCapability cap =
            CoreAudioDevice::queryCapability(static_cast<AudioDeviceID>(deviceID));
        copyCapabilityOut(cap, outCap, outRates, maxRates, outRateCount);
        return 1;
    }

    void* pureModeEngineCreate(void)
    {
        // NOLINTNEXTLINE(cppcoreguidelines-owning-memory): ownership transfers to the C caller.
        return new (std::nothrow) PureModeSession();
    }

    int pureModeEngineStart(void* engine, uint32_t deviceID, const char* filePath)
    {
        auto* session = static_cast<PureModeSession*>(engine);
        if (session == nullptr || filePath == nullptr)
        {
            return 0;
        }

        // Re-starting an already-running session: stop + tear down the prior source first.
        session->engine->stop();
        session->adapter.reset();
        session->source.reset();
        session->renderedFrames.store(0U, std::memory_order_relaxed);
        session->seekBaseFrames = 0U;

        auto source = std::make_unique<FileDecodeSource>();
        if (!source->open(filePath))
        {
            return 0;
        }

        FileFormat fileFormat;
        fileFormat.sampleRate = source->sampleRate();
        fileFormat.channels = source->channels();
        fileFormat.bitsPerChannel = source->sourceBitsPerChannel();
        fileFormat.isFloat = source->sourceIsFloat();

        const DeviceCapability cap =
            CoreAudioDevice::queryCapability(static_cast<AudioDeviceID>(deviceID));
        PureModeEvaluation eval = AdaptiveSound::evaluatePureMode(cap, fileFormat);

        // Founder decision (B3 hardware smoke test): do NOT acquire exclusive hog mode. Hog locks
        // out the macOS system volume control, which is unacceptable. We keep the rest of Pure's
        // purity — per-track nominal-rate match, native-format render, DSP bypassed — but run the
        // device SHARED so system volume keeps working. Bit-perfectness is therefore best-effort
        // (the HAL mixer may sit in the path) rather than exclusively guaranteed; achievedState
        // reports didHog == false honestly, and the signal-path UI reflects "shared". The policy
        // (evaluatePureMode) still computes requiresHog for documentation / unit tests; we override
        // only the engine action here.
        eval.requiresHog = false;

        auto adapter = std::make_unique<CountingSource>(source.get(), &session->renderedFrames);

        if (!session->engine->configure(cap, eval, adapter.get()))
        {
            return 0;
        }
        if (!session->engine->start())
        {
            session->engine->stop();
            return 0;
        }

        // Hand ownership to the session AFTER a successful start so a failed start leaves no
        // dangling source/adapter referenced by the engine.
        session->source = std::move(source);
        session->adapter = std::move(adapter);
        return 1;
    }

    int pureModeEngineSeek(void* engine, double seconds)
    {
        auto* session = static_cast<PureModeSession*>(engine);
        if (session == nullptr || session->source == nullptr)
        {
            return 0;
        }

        // Satisfy the FileDecodeSource::seek precondition (pullFloat must not run concurrently) by
        // stopping render around the seek (control-plane).
        session->engine->stop();
        const bool seekOk = session->source->seek(seconds);

        const double rate = session->source->sampleRate();
        const double clampedSeconds = (seconds > 0.0) ? seconds : 0.0;
        session->seekBaseFrames =
            (rate > 0.0) ? static_cast<uint64_t>(std::llround(clampedSeconds * rate)) : 0U;
        session->renderedFrames.store(0U, std::memory_order_relaxed);

        session->engine->start();
        return seekOk ? 1 : 0;
    }

    void pureModeEngineStop(void* engine)
    {
        auto* session = static_cast<PureModeSession*>(engine);
        if (session == nullptr)
        {
            return;
        }
        session->engine->stop();
    }

    void pureModeEngineDestroy(void* engine)
    {
        auto* session = static_cast<PureModeSession*>(engine);
        if (session == nullptr)
        {
            return;
        }
        // Stop render before tearing down members: the HALOutputEngine dtor restores the device
        // rate + releases hog; the FileDecodeSource dtor joins its decode thread.
        session->engine->stop();
        // NOLINTNEXTLINE(cppcoreguidelines-owning-memory): balances pureModeEngineCreate().
        delete session;
    }

    CAchievedOutputState pureModeEngineAchievedState(void* engine)
    {
        CAchievedOutputState out{};
        auto* session = static_cast<PureModeSession*>(engine);
        if (session == nullptr)
        {
            return out;
        }

        const AchievedOutputState state = session->engine->achievedState();
        out.decision = static_cast<uint8_t>(state.decision);
        out.configured = state.configured ? 1U : 0U;
        out.didHog = state.didHog ? 1U : 0U;
        out.rateChanged = state.rateChanged ? 1U : 0U;
        out.achievedRate = state.achievedRate;
        out.achievedBitsPerChannel = state.achievedBitsPerChannel;
        out.achievedIsFloat = state.achievedIsFloat ? 1U : 0U;
        out.running = state.running ? 1U : 0U;

        // Report the decode backend the FileDecodeSource actually selected at open() (Apple
        // ExtAudioFile vs FFmpeg) so the signal-path UI is honest about which decoder is live.
        out.decoderBackend =
            (session->source != nullptr &&
             session->source->decoderKind() == AdaptiveSound::DecoderKind::FFmpeg)
                ? kDecoderBackendFFmpeg
                : kDecoderBackendApple;
        return out;
    }

    double pureModeEnginePositionSeconds(void* engine)
    {
        auto* session = static_cast<PureModeSession*>(engine);
        if (session == nullptr || session->source == nullptr)
        {
            return 0.0;
        }
        const double rate = session->source->sampleRate();
        if (!(rate > 0.0))
        {
            return 0.0;
        }
        const uint64_t rendered = session->renderedFrames.load(std::memory_order_relaxed);
        const uint64_t total = session->seekBaseFrames + rendered;
        return static_cast<double>(total) / rate;
    }

    int pureModeSetDeviceVolume(uint32_t deviceID, float scalar)
    {
        if (deviceID == 0)
        {
            return 0;
        }
        Float32 clamped = scalar;
        if (clamped < 0.0F)
        {
            clamped = 0.0F;
        }
        else if (clamped > 1.0F)
        {
            clamped = 1.0F;
        }
        const AudioObjectPropertyAddress addr{kAudioDevicePropertyVolumeScalar,
                                              kAudioObjectPropertyScopeOutput,
                                              kAudioObjectPropertyElementMain};
        const auto dev = static_cast<AudioObjectID>(deviceID);
        if (AudioObjectHasProperty(dev, &addr) == 0)
        {
            return 0; // device has no master output volume scalar
        }
        Boolean settable = 0;
        if (AudioObjectIsPropertySettable(dev, &addr, &settable) != noErr || settable == 0)
        {
            return 0;
        }
        const OSStatus status =
            AudioObjectSetPropertyData(dev, &addr, 0, nullptr, sizeof(clamped), &clamped);
        return status == noErr ? 1 : 0;
    }
} // extern "C"
