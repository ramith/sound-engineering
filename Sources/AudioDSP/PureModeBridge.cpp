//
// PureModeBridge.cpp — CoreAudio glue exposing the Pure-Mode engine to Swift (pure C++).
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

#include "include/PureModeBridge.h"
#include "include/AsLog.h"
#include "include/CoreAudioDevice.h"
#include "include/DeviceCapability.h"
#include "include/FileDecodeSource.h"
#include "include/GaplessSource.h"
#include "include/HALOutputEngine.h"
#include "include/PureModeSource.h"

#include <atomic>
#include <cassert>
#include <cmath>
#include <cstdint>
#include <memory>
#include <new>
#include <utility>
#include <vector>

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

    // Pure-gapless arm return codes (mirrored in PureModeBridge.h). Not armed (1, 3): the track
    // plays after a fresh start.
    constexpr int kNextTrackError = 0;            // null handle/decoder, no active track, occupied
    constexpr int kNextTrackNeedsReconfigure = 1; // format/rate mismatch
    constexpr int kNextTrackArmed = 2;            // compatible — armed for a gapless seam
    constexpr int kNextTrackEnded = 3;            // the current track already ended

    // The opaque engine session behind the void* handle. The GaplessSource IS the engine's single
    // PureModeSource; it owns the active + armed-next FileDecodeSources internally.
    struct PureModeSession
    {
        // gapless declared BEFORE engine so the engine — which holds a raw, non-owning source_
        // pointer into gapless — is destroyed FIRST (referrer before referent), making the
        // teardown ordering structural rather than relying on every path calling stop() first
        // (Stage-2 review OWN-3). Members destruct in reverse declaration order.
        std::unique_ptr<GaplessSource> gapless;
        std::unique_ptr<HALOutputEngine> engine;

        PureModeSession()
            : gapless(std::make_unique<GaplessSource>()),
              engine(std::make_unique<HALOutputEngine>())
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

    // Keep an engine and the source a render pass outlived (HALOutputEngine::renderMayStillRun)
    // reachable and never freed — that pass may still be reading them. The lists are never
    // destroyed (a static destructor at exit would free them too). Control plane only
    // (engineQueue). Empty in practice: it takes a render pass stuck inside the gate after its
    // output unit was stopped and disposed.
    void parkRender(std::unique_ptr<GaplessSource> gapless, std::unique_ptr<HALOutputEngine> engine)
    {
        static auto* parkedSources = new std::vector<std::unique_ptr<GaplessSource>>();
        static auto* parkedEngines = new std::vector<std::unique_ptr<HALOutputEngine>>();
        parkedSources->push_back(std::move(gapless));
        parkedEngines->push_back(std::move(engine));
    }

    // After session.engine->stop(): if a render pass outlived it, park the engine and the source it
    // reads instead of letting the session free them, and give the session fresh ones (DSP-06:
    // never free memory a running pass reads; no change on the real-time side).
    void parkIfRenderOutlivedStop(PureModeSession& session)
    {
        if (!session.engine->renderMayStillRun())
        {
            return;
        }
        AdaptiveSound::log::line(
            "[PureMode] a render pass outlived the output's teardown: "
            "parking its engine and source (kept, never freed)");
        parkRender(std::move(session.gapless), std::move(session.engine));
        session.gapless = std::make_unique<GaplessSource>();
        session.engine = std::make_unique<HALOutputEngine>();
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
        // ownership transfers to the C caller
        return new (std::nothrow) PureModeSession();
    }

    int pureModeEngineStart(void* engine,
                            uint32_t deviceID,
                            const char* filePath,
                            double startSeconds) AUDIODSP_C_NOEXCEPT
    {
        auto* session = static_cast<PureModeSession*>(engine);
        if (session == nullptr || filePath == nullptr)
        {
            return 0;
        }

        // Re-starting an already-running session: stop render first. setCurrent() below (with
        // render stopped) clears any prior active/armed source inside the GaplessSource.
        session->engine->stop();
        parkIfRenderOutlivedStop(*session);

        auto source = std::make_unique<FileDecodeSource>();
        if (!source->open(filePath))
        {
            return 0;
        }
        // Start at the requested place (a resume from Pause, a move to another device): position
        // the fresh source BEFORE it is installed and render starts — the seek precondition (no
        // pullFloat running) holds trivially, and nothing from 0:00 is heard first.
        const bool startsInside = startSeconds > 0.0 && std::isfinite(startSeconds);
        if (startsInside && !source->seek(startSeconds))
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
        // The policy gates the engine too: a session it declines never starts, and the caller
        // plays the file through Enhanced. The app checks the same policy first; this holds when
        // the decoder reports the file differently (e.g. its channel count).
        if (eval.decision == AdaptiveSound::PureModeDecision::FallbackEnhanced)
        {
            AdaptiveSound::log::line("[PureMode] declined for this file on device {}: {}",
                                     deviceID,
                                     AdaptiveSound::pureModeReasonString(eval.reason));
            return 0;
        }

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
        const double sourceRate = source->sampleRate();
        session->gapless->setCurrent(std::move(source));
        if (startsInside && sourceRate > 0.0)
        {
            // Report the position from the start place (setCurrent re-zeroed it).
            session->gapless->resetActiveBase(
                static_cast<uint64_t>(std::llround(startSeconds * sourceRate)));
        }

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
        // Hold the render FIRST. The FileDecodeSource::seek precondition is that pullFloat is not
        // running, and the render thread swaps the active track at a gapless seam inside pullFloat,
        // so even which source is active is only stable once no render is in flight. Holding is no
        // HAL call: the device keeps running (silence) and the session stays configured. This used
        // to be engine->stop() — teardown(), which disposed the unit, so the start() after it
        // failed and every Pure seek went silent (S10.8 G audit). A render that will not go quiet
        // refuses the seek: playback carries on where it was.
        if (!session->engine->holdRender())
        {
            return 0;
        }
        FileDecodeSource* active = session->gapless->activeSource();
        bool seekOk = false;
        // The ACTIVE track only; the armed next stays armed (a seek is not a transition).
        if (active != nullptr && active->seek(seconds))
        {
            seekOk = true;
            const double rate = active->sampleRate();
            const double clampedSeconds = (seconds > 0.0) ? seconds : 0.0;
            const uint64_t seekBaseFrames =
                (rate > 0.0) ? static_cast<uint64_t>(std::llround(clampedSeconds * rate)) : 0U;
            // Re-base the active track's position so display resumes from the seek target. A failed
            // reposition decodes on from where it was, so its position is NOT re-based.
            session->gapless->resetActiveBase(seekBaseFrames);
        }
        session->engine->releaseRender();
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
        parkIfRenderOutlivedStop(*session);
        // balances pureModeEngineCreate()
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
            (active != nullptr && active->decoderKind() == AdaptiveSound::DecoderKind::FFmpeg)
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

    void* pureModeOpenDecodeSource(const char* filePath) AUDIODSP_C_NOEXCEPT
    {
        if (filePath == nullptr)
        {
            return nullptr;
        }
        // Open OFF any caller lock — this is the potentially network-slow step (S3 F3). A failure
        // (unreadable / unsupported / > 8 channels) returns null; the unique_ptr dtor joins the
        // just-spawned (idle) decode thread here, still off-lock.
        auto next = std::make_unique<FileDecodeSource>();
        if (!next->open(filePath))
        {
            return nullptr;
        }
        return next.release();
    }

    int pureModeEngineArmOpenedNextTrack(void* engine, void* decoder) AUDIODSP_C_NOEXCEPT
    {
        // Adopt ownership of the pre-opened decoder for the whole call: on EVERY outcome it is
        // either moved into the gapless engine (armed) or destroyed when `next` leaves scope — so
        // the caller never frees it after this returns. The slow file open already ran off-lock in
        // pureModeOpenDecodeSource; only the fast compat check + pointer-swap arm run here.
        std::unique_ptr<FileDecodeSource> next(static_cast<FileDecodeSource*>(decoder));
        auto* session = static_cast<PureModeSession*>(engine);
        if (session == nullptr || next == nullptr)
        {
            return kNextTrackError;
        }
        const FileDecodeSource* active = session->gapless->activeSource();
        if (active == nullptr)
        {
            return kNextTrackError; // nothing playing to arm behind
        }
        // The end is final: the current track already ended with nothing armed, so the view model
        // starts this one fresh. `next` is dropped (dtor joins its decode thread).
        if (session->gapless->ended())
        {
            return kNextTrackEnded;
        }
        // Same-rate-only gapless: a rate/channel/float/bit-depth mismatch can't be straddled at the
        // seam. `next` is dropped (dtor joins its decode thread); the caller reconfigures instead.
        if (!AdaptiveSound::sameRateGaplessCompatible(*active, *next))
        {
            return kNextTrackNeedsReconfigure;
        }
        // Arm it. Ownership transfers into the engine only on success.
        if (session->gapless->armNext(std::move(next)))
        {
            return kNextTrackArmed;
        }
        // Refused: the end landed after the check above (final, as there) — or the slot was
        // occupied, which the caller rules out by taking the old pick off first, on the same queue
        // (arming never replaces).
        const bool ended = session->gapless->ended();
        assert(ended &&
               "pureModeEngineArmOpenedNextTrack: slot occupied — clear the old pick first");
        return ended ? kNextTrackEnded : kNextTrackError;
    }

    void pureModeDestroyDecodeSource(void* decoder) AUDIODSP_C_NOEXCEPT
    {
        // NULL-safe: `delete nullptr` is a no-op. The dtor joins the decode thread off-RT. Only for
        // a decoder that was opened but never armed (e.g. the engine was torn down before arming).
        delete static_cast<FileDecodeSource*>(decoder);
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
} // extern "C"
