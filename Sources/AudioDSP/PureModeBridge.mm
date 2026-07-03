//
// PureModeBridge.mm — CoreAudio (Obj-C++) glue exposing the Pure-Mode engine to Swift.
//
// Implements the capability-query + engine-session half of PureModeBridge.h. The CoreAudio-free
// policy (pureModeEvaluate) lives in PureModeBridgePolicy.cpp; this file is NOT compiled into the
// C++ test harness (it links CoreAudio).
//
// Ownership: the void* handle is a PureModeSession owned via RAII. The session owns the
// HALOutputEngine and a GaplessSource (the engine's single PureModeSource). The GaplessSource owns
// the current + an optionally pre-armed next FileDecodeSource and performs the sample-accurate
// RT-thread seam swap (Stage 2 gapless). Teardown is idempotent and runs from the destructor: the
// GaplessSource dtor frees both FileDecodeSources (each joins its decode thread); the
// HALOutputEngine dtor restores the device nominal rate and releases hog mode.
//
// -fno-exceptions / -fno-rtti clean.
//

#include "include/CoreAudioDevice.h"
#include "include/DeviceCapability.h"
#include "include/FileDecodeSource.h"
#include "include/GaplessSource.h"
#include "include/HALOutputEngine.h"
#include "include/PureModeBridge.h"
#include "include/PureModeSource.h"

#include <atomic>
#include <cmath>
#include <cstdint>
#include <memory>
#include <new>
#include <utility>

namespace
{
    using AdaptiveSound::AchievedOutputState;
    using AdaptiveSound::CoreAudioDevice;
    using AdaptiveSound::DeviceCapability;
    using AdaptiveSound::FileDecodeSource;
    using AdaptiveSound::FileFormat;
    using AdaptiveSound::GaplessSource;
    using AdaptiveSound::HALOutputEngine;
    using AdaptiveSound::PureModeEvaluation;

    // Decoder backend codes mirrored into CAchievedOutputState::decoderBackend.
    constexpr uint8_t kDecoderBackendApple = 0U;
    constexpr uint8_t kDecoderBackendFFmpeg = 1U;

    // pureModeEngineSetNextTrack return codes (mirrored in PureModeBridge.h).
    constexpr int kNextTrackError = 0;          // unreadable/unsupported/already-armed/null
    constexpr int kNextTrackNeedsReconfigure = 1; // format/rate mismatch — caller reconfigures
    constexpr int kNextTrackArmed = 2;            // compatible — armed for a gapless seam

    // The opaque engine session behind the void* handle. The GaplessSource IS the engine's single
    // PureModeSource; it owns the active + armed-next FileDecodeSources internally.
    struct PureModeSession
    {
        std::unique_ptr<HALOutputEngine> engine;
        std::unique_ptr<GaplessSource> gapless;

        PureModeSession()
            : engine(std::make_unique<HALOutputEngine>()),
              gapless(std::make_unique<GaplessSource>())
        {
        }
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
                                uint32_t* outRateCount) AUDIODSP_C_NOEXCEPT
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

    void* pureModeEngineCreate(void) AUDIODSP_C_NOEXCEPT
    {
        // NOLINTNEXTLINE(cppcoreguidelines-owning-memory): ownership transfers to the C caller.
        return new (std::nothrow) PureModeSession();
    }

    int pureModeEngineStart(void* engine, uint32_t deviceID, const char* filePath) AUDIODSP_C_NOEXCEPT
    {
        auto* session = static_cast<PureModeSession*>(engine);
        if (session == nullptr || filePath == nullptr)
        {
            return 0;
        }

        // Re-starting an already-running session: stop render first. setCurrent() below (with
        // render stopped) clears any prior active/armed source inside the GaplessSource.
        session->engine->stop();

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

        // Hog policy (refined after the HDMI smoke test):
        //   * FullBitPerfect (integer DAC — HDMI / USB): KEEP hog. Setting the device's INTEGER
        //     physical stream format requires EXCLUSIVE access; in shared mode the HAL refuses the
        //     format change ("set output StreamFormat failed") and the bit-perfect path can't start.
        //     On these devices the Mac's system volume doesn't drive the output anyway (the DAC / TV
        //     owns volume), so holding hog is the right, standard bit-perfect behaviour.
        //   * RateMatchedFloat (built-in / Bluetooth / other float devices): run SHARED (no hog) so
        //     the macOS system volume keeps working — these don't need an integer-format change, and
        //     locking the system volume on the built-in output was unacceptable (the earlier
        //     blanket no-hog fix). achievedState reports didHog honestly either way.
        if (eval.decision == AdaptiveSound::PureModeDecision::RateMatchedFloat)
        {
            eval.requiresHog = false;
        }

        // Install the active source into the GaplessSource (render is stopped → precondition met),
        // then point the engine at the GaplessSource (its single, stable PureModeSource).
        session->gapless->setCurrent(std::move(source));

        if (!session->engine->configure(cap, eval, session->gapless.get()))
        {
            return 0;
        }
        if (!session->engine->start())
        {
            session->engine->stop();
            return 0;
        }
        return 1;
    }

    int pureModeEngineSeek(void* engine, double seconds) AUDIODSP_C_NOEXCEPT
    {
        auto* session = static_cast<PureModeSession*>(engine);
        if (session == nullptr)
        {
            return 0;
        }
        FileDecodeSource* active = session->gapless->activeSource();
        if (active == nullptr)
        {
            return 0;
        }

        // Seek operates on the ACTIVE track ONLY and does NOT disturb the armed next (transitions_
        // must not increment on a seek). Satisfy the FileDecodeSource::seek precondition (pullFloat
        // must not run concurrently) by stopping render around the seek (control-plane).
        session->engine->stop();
        const bool seekOk = active->seek(seconds);

        const double rate = active->sampleRate();
        const double clampedSeconds = (seconds > 0.0) ? seconds : 0.0;
        const uint64_t seekBaseFrames =
            (rate > 0.0) ? static_cast<uint64_t>(std::llround(clampedSeconds * rate)) : 0U;
        // Re-base the active track's position so display resumes from the seek target.
        session->gapless->resetActiveBase(seekBaseFrames);

        session->engine->start();
        return seekOk ? 1 : 0;
    }

    void pureModeEngineStop(void* engine) AUDIODSP_C_NOEXCEPT
    {
        auto* session = static_cast<PureModeSession*>(engine);
        if (session == nullptr)
        {
            return;
        }
        session->engine->stop();
    }

    void pureModeEngineDestroy(void* engine) AUDIODSP_C_NOEXCEPT
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

    CAchievedOutputState pureModeEngineAchievedState(void* engine) AUDIODSP_C_NOEXCEPT
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

        // Report the decode backend the ACTIVE FileDecodeSource selected at open() (Apple
        // ExtAudioFile vs FFmpeg) so the signal-path UI is honest about which decoder is live.
        const FileDecodeSource* active = session->gapless->activeSource();
        out.decoderBackend =
            (active != nullptr &&
             active->decoderKind() == AdaptiveSound::DecoderKind::FFmpeg)
                ? kDecoderBackendFFmpeg
                : kDecoderBackendApple;
        return out;
    }

    double pureModeEnginePositionSeconds(void* engine) AUDIODSP_C_NOEXCEPT
    {
        auto* session = static_cast<PureModeSession*>(engine);
        if (session == nullptr)
        {
            return 0.0;
        }
        // Per-track position: (active seekBase + active renderedFrames) / active rate. Restarts at
        // 0 at each gapless seam (renderedFramesCurrent re-zeroes when the armed next becomes
        // active).
        const double rate = session->gapless->currentSampleRate();
        if (!(rate > 0.0))
        {
            return 0.0;
        }
        const uint64_t total = session->gapless->renderedFramesCurrent();
        return static_cast<double>(total) / rate;
    }

    int pureModeEngineSetNextTrack(void* engine, const char* filePath) AUDIODSP_C_NOEXCEPT
    {
        auto* session = static_cast<PureModeSession*>(engine);
        if (session == nullptr || filePath == nullptr)
        {
            return kNextTrackError;
        }
        const FileDecodeSource* active = session->gapless->activeSource();
        if (active == nullptr)
        {
            return kNextTrackError; // nothing playing to arm behind
        }

        // Pre-open the next source off-RT. A failure (unreadable / unsupported / > 8 channels)
        // leaves nothing armed and the RT path untouched.
        auto next = std::make_unique<FileDecodeSource>();
        if (!next->open(filePath))
        {
            return kNextTrackError;
        }

        // Same-rate-only gapless: a rate/channel/float/bit-depth mismatch can't be straddled at the
        // seam. Drop the source and tell the caller to reconfigure for the next track itself.
        if (!AdaptiveSound::sameRateGaplessCompatible(*active, *next))
        {
            return kNextTrackNeedsReconfigure; // `next` dtor joins its decode thread off-RT
        }

        // Arm it. A second arm (one already pending) is refused → treat as error so the caller
        // does not assume a gapless seam is queued. `next` ownership transfers only on success.
        if (!session->gapless->armNext(std::move(next)))
        {
            return kNextTrackError;
        }
        return kNextTrackArmed;
    }

    void pureModeEngineClearNextTrack(void* engine) AUDIODSP_C_NOEXCEPT
    {
        auto* session = static_cast<PureModeSession*>(engine);
        if (session == nullptr)
        {
            return;
        }
        session->gapless->clearNext();
    }

    uint64_t pureModeEnginePollTrackAdvance(void* engine) AUDIODSP_C_NOEXCEPT
    {
        auto* session = static_cast<PureModeSession*>(engine);
        if (session == nullptr)
        {
            return 0U;
        }
        // Reap a seam-retired source off-RT (joins its decode thread) before reporting the count.
        session->gapless->reapRetired();
        return session->gapless->transitionCount();
    }

    int pureModeEnginePlaybackEnded(void* engine) AUDIODSP_C_NOEXCEPT
    {
        auto* session = static_cast<PureModeSession*>(engine);
        if (session == nullptr)
        {
            return 0;
        }
        return session->gapless->ended() ? 1 : 0;
    }

    int pureModeSetDeviceVolume(uint32_t deviceID, float scalar) AUDIODSP_C_NOEXCEPT
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
