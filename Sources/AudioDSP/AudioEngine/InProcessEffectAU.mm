//
// InProcessEffectAU.mm — the scaffolding the app's two in-process v3 effect AUs share (see the
// header). Off the render thread except the render block's body.
//

#import <AVFoundation/AVFoundation.h>
#import <AudioToolbox/AudioToolbox.h>
#include "InProcessEffectAU.h"
#include <utility>

namespace
{
    // The AudioComponent identity shared by the app's in-process effect AUs; each AU adds a subtype.
    constexpr OSType kComponentType = kAudioUnitType_Effect; // 'aufx'
    constexpr OSType kComponentManufacturer = 0x41647364U;   // 'Adsd' (AdaptiveSound)
    constexpr uint32_t kComponentVersion = 0x00010000U;      // 1.0.0 (major.minor.patch)

    // The busses' width until a host's connect re-widths them: stereo, which both bus inits accept.
    constexpr AVAudioChannelCount kStereoChannelCount = 2U;
} // namespace

namespace AdaptiveSound
{

    AudioComponentDescription InProcessEffectScaffold::description(OSType subType) noexcept
    {
        AudioComponentDescription desc = {};
        desc.componentType = kComponentType;
        desc.componentSubType = subType;
        desc.componentManufacturer = kComponentManufacturer;
        desc.componentFlags = 0;
        desc.componentFlagsMask = 0;
        return desc;
    }

    void InProcessEffectScaffold::registerOnce(dispatch_once_t& token,
                                               Class auClass,
                                               AudioComponentDescription description,
                                               CFStringRef name) noexcept
    {
        dispatch_once(&token, ^{
          [AUAudioUnit registerSubclass:auClass
                 asComponentDescription:description
                                   name:(__bridge NSString*)name
                                version:kComponentVersion];
        });
    }

    bool InProcessEffectScaffold::setUp(AUAudioUnit* owner,
                                        std::shared_ptr<InProcessEffectRender> render)
    {
        // Busses: one input + one output, so AVAudioEngine can connect upstream and downstream
        // nodes (a v3 effect AU with no bus arrays fails engine.connect()).
        AVAudioFormat* format =
            [[AVAudioFormat alloc] initStandardFormatWithSampleRate:static_cast<double>(sampleRate_)
                                                           channels:kStereoChannelCount];
        if (format == nil) { return false; }
        AUAudioUnitBus* input = [[AUAudioUnitBus alloc] initWithFormat:format error:nil];
        AUAudioUnitBus* output = [[AUAudioUnitBus alloc] initWithFormat:format error:nil];
        if (input == nil || output == nil) { return false; }
        inputBusses_ = [[AUAudioUnitBusArray alloc] initWithAudioUnit:owner
                                                              busType:AUAudioUnitBusTypeInput
                                                               busses:@[ input ]];
        outputBusses_ = [[AUAudioUnitBusArray alloc] initWithAudioUnit:owner
                                                               busType:AUAudioUnitBusTypeOutput
                                                                busses:@[ output ]];

        // The render block owns the render (`render` is a sink, moved into the local the block
        // copies), so it never touches the AU nor promotes a __weak reference on the render thread
        // (issue #7); the copy and its release happen off it (here, and when the AU is freed). The
        // render — and the kernel it holds — lives as long as the block, so it can never be freed
        // under a live render.
        std::shared_ptr<InProcessEffectRender> held = std::move(render);
        renderBlock_ = ^AUAudioUnitStatus(AudioUnitRenderActionFlags* flags,
                                          const AudioTimeStamp* timestamp,
                                          AUAudioFrameCount frames,
                                          NSInteger busNumber,
                                          AudioBufferList* outputData,
                                          const AURenderEvent* events,
                                          AURenderPullInputBlock pull) {
          (void)busNumber; // one output bus
          (void)events;    // no MIDI, no parameter events
          // Nothing connected upstream: nothing to render (council C-87).
          if (pull == nullptr) { return kAudioUnitErr_NoConnection; }
          return held->render(flags, timestamp, frames, outputData, pull);
        };
        return inputBusses_ != nil && outputBusses_ != nil;
    }

    void InProcessEffectScaffold::adoptHostFormat(AUAudioUnit* owner) noexcept
    {
        // The device's rate can change after -init; the host sets its per-call ceiling before
        // allocate.
        const double negotiatedSampleRate = owner.outputBusses[0].format.sampleRate;
        if (negotiatedSampleRate > 0.0) {
            sampleRate_ = static_cast<uint32_t>(negotiatedSampleRate);
        }
        const AUAudioFrameCount hostMaxFrames = owner.maximumFramesToRender;
        if (hostMaxFrames > 0U) {
            maxFrames_ = static_cast<uint32_t>(hostMaxFrames);
        }
    }

    AUAudioUnitBusArray* InProcessEffectScaffold::inputBusses() const noexcept
    {
        return inputBusses_;
    }

    AUAudioUnitBusArray* InProcessEffectScaffold::outputBusses() const noexcept
    {
        return outputBusses_;
    }

    AUInternalRenderBlock InProcessEffectScaffold::renderBlock() const noexcept
    {
        return renderBlock_;
    }

    uint32_t InProcessEffectScaffold::sampleRate() const noexcept
    {
        return sampleRate_;
    }

    uint32_t InProcessEffectScaffold::maxFrames() const noexcept
    {
        return maxFrames_;
    }

} // namespace AdaptiveSound
