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

        // Start / stop rendering. Control-plane only; safe to call stop() repeatedly.
        bool start();
        void stop();

        // The real achieved state (lock-free snapshot for the UI / B3).
        [[nodiscard]] AchievedOutputState achievedState() const;

      private:
        class Impl; // opaque; owns the AudioUnit + CoreAudio state (defined in the .mm)
        std::unique_ptr<Impl> impl_;
    };

} // namespace AdaptiveSound
