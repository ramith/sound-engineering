#pragma once

//
// InProcessEffectAU.h — the scaffolding the app's two in-process v3 effect AUs share (R1.1-A, council
// C-87; DSP-14, DUP-15).
//
// AdaptiveSoundAU (the effects chain) and SpatialRendererAU (the device-boundary N -> M stage) are
// AUAudioUnit subclasses that differ only in WHAT they render and how they PREPARE for it. Everything
// else lives here, once, in an InProcessEffectScaffold each AU holds by value: the component identity
// and its one-time registration, the busses, the re-sync of the sample rate and frame ceiling at
// allocate, and the render block — whose first act is the guard both need: with nothing connected
// upstream (a nil pull block) there is nothing to render, so the AU answers
// kAudioUnitErr_NoConnection. (Written twice, the copies had diverged: the effects AU called the nil
// block.)
//
// The render block reaches the AU's work through one virtual call (InProcessEffectRender), not a
// wrapped Objective-C block: a block calling a captured block retains and releases it on every render
// (-O2), and the render thread makes no Objective-C runtime call.
//
// Objective-C++ only (AudioToolbox's AUAudioUnit types), but written in C++ syntax with no Foundation
// names, so the C++-only format check reads it as C++.
//

#include "../include/AudioConstants.h"
#include <AudioToolbox/AudioToolbox.h>
#include <cstdint>
#include <dispatch/dispatch.h>
#include <memory>

namespace AdaptiveSound
{

    // What an in-process effect AU renders, on the render thread: `frames` frames into `output`, its
    // input pulled through `pull` — never nil here (the scaffold's render block answers a missing
    // upstream first), and borrowed: the host keeps it alive for the call, so it is not retained
    // (ARC would retain and release it on every render). No allocation, lock or Objective-C message.
    class InProcessEffectRender
    {
      public:
        InProcessEffectRender() = default;
        virtual ~InProcessEffectRender() = default;
        InProcessEffectRender(const InProcessEffectRender&) = delete;
        InProcessEffectRender& operator=(const InProcessEffectRender&) = delete;
        InProcessEffectRender(InProcessEffectRender&&) = delete;
        InProcessEffectRender& operator=(InProcessEffectRender&&) = delete;

        virtual AUAudioUnitStatus
        render(AudioUnitRenderActionFlags* flags,
               const AudioTimeStamp* timestamp,
               AUAudioFrameCount frames,
               AudioBufferList* output,
               __unsafe_unretained AURenderPullInputBlock pull) noexcept = 0;
    };

    // The scaffold an in-process effect AU holds by value (see the file header). Called off the
    // render thread only; the render block it builds is the one part that runs on it.
    class InProcessEffectScaffold
    {
      public:
        // The description one of the app's in-process effect AUs is registered under: an effect
        // ('aufx') made by the app ('Adsd'), told apart by `subType`.
        [[nodiscard]] static AudioComponentDescription description(OSType subType) noexcept;

        // Register `auClass` under `description` as `name` (a CFSTR constant), once per process
        // (`token` is the caller's own static): engine setup repeats, on a device re-init.
        static void registerOnce(dispatch_once_t& token,
                                 Class auClass,
                                 AudioComponentDescription description,
                                 CFStringRef name) noexcept;

        // From the AU's -init (the v3 contract: internalRenderBlock is non-nil at attach): one
        // stereo input and one stereo output bus at the default rate — a host's connect re-widths
        // them — and the render block over `render`. False only if AVFoundation cannot make a
        // stereo bus.
        [[nodiscard]] bool setUp(AUAudioUnit* owner, std::shared_ptr<InProcessEffectRender> render);

        // From the AU's allocate (off the render thread; the v3 contract: not rendering): adopt the
        // host's negotiated output rate and per-call frame ceiling.
        void adoptHostFormat(AUAudioUnit* owner) noexcept;

        [[nodiscard]] AUAudioUnitBusArray* inputBusses() const noexcept;
        [[nodiscard]] AUAudioUnitBusArray* outputBusses() const noexcept;
        [[nodiscard]] AUInternalRenderBlock renderBlock() const noexcept;
        // The rate and per-call frame ceiling the AU renders at: the defaults until the first
        // allocate, then the host's.
        [[nodiscard]] uint32_t sampleRate() const noexcept;
        [[nodiscard]] uint32_t maxFrames() const noexcept;

      private:
        AUAudioUnitBusArray* inputBusses_ = nullptr;
        AUAudioUnitBusArray* outputBusses_ = nullptr;
        AUInternalRenderBlock renderBlock_ = nullptr; // co-owns the render (and its kernel)
        uint32_t sampleRate_ = kDefaultSampleRate;
        uint32_t maxFrames_ = kDefaultMaxFrames;
    };

} // namespace AdaptiveSound
