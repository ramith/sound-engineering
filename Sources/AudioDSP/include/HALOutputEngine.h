#pragma once

//
// HALOutputEngine.h — reusable bit-perfect HAL output engine (Pure Mode, Phase B — B2a).
//
// Drives ONE output device through a kAudioUnitSubType_HALOutput AudioUnit, pulling interleaved
// float PCM from a pluggable PureModeSource and converting it to the device's native sample format
// with no AVAudioEngine and no AU-internal sample-rate conversion.
//
// This header is CoreAudio-FREE on purpose (the AudioUnit + CoreAudio state live behind a pimpl in
// the .mm), so it composes cleanly with the CoreAudio-free B1 model. -fno-exceptions / -fno-rtti
// clean.
//
// SAFETY: configure()/start()/stop() are control-plane (never the audio thread). The original
// device nominal rate is saved at configure() and ALWAYS restored on stop()/destruction; hog mode
// is released only if WE acquired it. Teardown is idempotent and runs from the destructor too, so
// an early-return path still leaves the device in its original state.
//

#include "DeviceCapability.h"

#include <cstdint>
#include <memory>

namespace AdaptiveSound
{

    class PureModeSource;

    // The state the engine ACTUALLY achieved (may differ from what was requested — e.g. hog denied,
    // or a rate change that did not take). B3/UI should display this, not the PureModeEvaluation.
    struct AchievedOutputState
    {
        PureModeDecision decision = PureModeDecision::FallbackEnhanced;
        bool configured = false;             // configure() succeeded far enough to render
        bool didHog = false;                 // WE hold hog mode (and must release it on teardown)
        bool rateChanged = false;            // we successfully set the device nominal rate
        double achievedRate = 0;             // device nominal rate the engine is running at (Hz)
        uint32_t achievedBitsPerChannel = 0; // AU output format bit depth actually negotiated
        bool achievedIsFloat = false;        // AU output format is float (vs integer PCM)
        bool running = false;                // start() succeeded and stop() not yet called
    };

    class HALOutputEngine
    {
      public:
        HALOutputEngine();
        ~HALOutputEngine();

        HALOutputEngine(const HALOutputEngine&) = delete;
        HALOutputEngine& operator=(const HALOutputEngine&) = delete;
        HALOutputEngine(HALOutputEngine&&) = delete;
        HALOutputEngine& operator=(HALOutputEngine&&) = delete;

        // Configure the engine for one (device, evaluation) pair, pulling PCM from `source`.
        // Best-effort: hog/rate-change failures LOG and continue (shared mode / current rate)
        // rather than hard-failing. `source` is borrowed; it must outlive the engine (until
        // stop()). Returns true if the AU was set up far enough to render. Control-plane only.
        bool configure(const DeviceCapability& cap,
                       const PureModeEvaluation& eval,
                       PureModeSource* source);

        // Start / stop rendering. Control-plane only; safe to call stop() repeatedly. stop() TEARS
        // the session down (restores the rate, releases hog, disposes the unit): only configure()
        // can render again after it.
        bool start();
        void stop();

        // Hold the render: the callback outputs silence and leaves the source alone until
        // releaseRender(). Closed to new passes at once; returns once the one pass already inside
        // (if any) has left — never waits on a pass that starts later (RenderGate.h). No HAL call:
        // the device keeps running and the session stays configured. For a control-plane operation
        // on the source, e.g. a seek (FileDecodeSource::seek's precondition). False only if that
        // one pass is still inside after 100 ms (an RT render never is): nothing is held.
        // Control-plane only.
        [[nodiscard]] bool holdRender();
        void releaseRender();

        // True when the last stop() could not see the render go quiet: a pass was still inside
        // after the unit was stopped and disposed (an RT render essentially never is). That pass
        // holds pointers into this engine and its source, so neither may be freed — the owner
        // parks them (PureModeBridge.cpp). Control-plane only.
        [[nodiscard]] bool renderMayStillRun() const;

        // The real achieved state, copied. Not a lock-free snapshot: configure() writes it and the
        // Pure bridge reads it, both on the control plane (the app's engine queue) — never across
        // threads.
        [[nodiscard]] AchievedOutputState achievedState() const;

        // Why the last configure() declined (it returned false): the device would not run at the file's
        // rate (RateUnsupportedResample — e.g. HDMI's 48 kHz lock), its stream carries another channel
        // count than the file (ChannelCountMismatch), or anything else (DeviceWouldNotStart). Read
        // after a failed configure(), for the reason Pure names (C-34). Control-plane only.
        [[nodiscard]] PureModeReason configureDeclineReason() const;

        // Whether the float → native step reduces bits the source has, and so adds TPDF dither
        // (convertFloatToNativeDithered — R1.1-A, founder decision 2026-10-16). Off by default: the
        // plain conversion is bit-exact. Set after configure() and before start(), from the depth rule
        // (ditherWhenConverting); a session's format and source depth are fixed (a gapless seam
        // joins only tracks of one depth). Control-plane only.
        void setDither(bool reducesBits);

      private:
        class Impl; // opaque; owns the AudioUnit + CoreAudio state (defined in the .mm)
        std::unique_ptr<Impl> impl_;
    };

} // namespace AdaptiveSound
