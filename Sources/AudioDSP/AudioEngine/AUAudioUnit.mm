#import <AudioToolbox/AudioToolbox.h>
#import <AVFoundation/AVFoundation.h>
#include "../include/AudioConstants.h"
#include "../include/AudioUnitBridge.h" // enforce extern "C" signature agreement
#include "../include/DSPKernel.h"
#include "../include/TargetState.h"
#include <cstring>
#include <memory>

using namespace AdaptiveSound;

namespace
{
    // Placeholder AudioComponent identifiers for the (not-yet-registered) in-process AU.
    constexpr OSType kComponentSubType = 0x61647364U;      // 'adsd' (AdaptiveSound)
    constexpr OSType kComponentManufacturer = 0x41647364U; // 'Adsd'
} // namespace

@interface AdaptiveSoundAU : AUAudioUnit {
    std::shared_ptr<DSPKernel> _kernel;
    AUInternalRenderBlock _renderBlock;
    uint32_t _sampleRate;   // captured at creation, applied in initialize
    uint32_t _bufferFrames; // captured at creation, applied in initialize
}
@property (nonatomic, readonly) AUInternalRenderBlock internalRenderBlock;
@end

@implementation AdaptiveSoundAU

- (instancetype)initWithComponentDescription:(AudioComponentDescription)componentDescription
                                     options:(AudioComponentInstantiationOptions)options
                                       error:(NSError**)outError {
    self = [super initWithComponentDescription:componentDescription options:options error:outError];
    if (self == nil) { return nil; }
    _sampleRate = kDefaultSampleRate;
    _bufferFrames = kDefaultMaxFrames;
    return self;
}

- (BOOL)allocateRenderResourcesAndReturnError:(NSError**)outError {
    if (![super allocateRenderResourcesAndReturnError:outError]) { return NO; }

    _kernel = std::make_shared<DSPKernel>();
    _kernel->initialize(_sampleRate, _bufferFrames);

    // Capture the kernel by value (shared_ptr copy) so the render block never touches
    // `self` nor promotes a __weak reference on the audio thread — i.e. no Obj-C runtime
    // calls (objc_loadWeakRetained) on the RT path (issue #7). The block co-owns the
    // kernel, so it stays alive for the block's lifetime; the shared_ptr copy and destroy
    // happen off-RT (at block creation / teardown), never during render.
    std::shared_ptr<DSPKernel> kernel = _kernel;
    _renderBlock = ^AUAudioUnitStatus(AudioUnitRenderActionFlags* flags,
                                      const AudioTimeStamp* timestamp,
                                      AUAudioFrameCount frames,
                                      NSInteger busNum,
                                      AudioBufferList* out,
                                      const AURenderEvent* events,
                                      AURenderPullInputBlock pull) {
        if (kernel == nullptr) { return kAudioUnitErr_Uninitialized; }

        AudioBufferList input;
        if (pull(flags, timestamp, frames, 0, &input) == noErr) {
            // TODO(#4): memcpy uses input byte size into output buffer; clamp to min in fix
            for (UInt32 i = 0; i < out->mNumberBuffers && i < input.mNumberBuffers; ++i) {
                memcpy(out->mBuffers[i].mData, input.mBuffers[i].mData,
                       input.mBuffers[i].mDataByteSize);
            }
        }
        kernel->process(out, frames);
        return noErr;
    };
    return YES;
}

- (void)deallocateRenderResources {
    _kernel.reset();
    _renderBlock = nullptr;
    [super deallocateRenderResources];
}

- (AUInternalRenderBlock)internalRenderBlock {
    return _renderBlock;
}

// Off-RT control plane. Stores the desired sample rate / buffer size that will be
// applied the next time render resources are allocated.
- (void)setRequestedSampleRate:(uint32_t)sampleRate bufferFrames:(uint32_t)bufferFrames {
    if (sampleRate != 0) { _sampleRate = sampleRate; }
    if (bufferFrames != 0) { _bufferFrames = bufferFrames; }
}

// Off-RT control plane. Forwards a fully-formed TargetState to the RT kernel via the
// lock-free double-buffer (SPSC producer side; never called on the render thread).
- (void)publishState:(const TargetState&)state {
    if (_kernel != nullptr) { _kernel->publishTargetState(state); }
}

@end

// MARK: - C ABI (off-RT control plane). Signatures MUST match AudioUnitBridge.h exactly.

extern "C" {

void* createAdaptiveAudioUnit(void* audioEngine, uint32_t sampleRate, uint32_t bufferFrames) {
    // TODO(future sprint): attach to the provided AVAudioEngine graph (bus/format
    // negotiation). The pointer is accepted but not yet wired into a live engine.
    (void)audioEngine;

    AudioComponentDescription desc = {};
    desc.componentType = kAudioUnitType_Effect;
    desc.componentSubType = kComponentSubType;
    desc.componentManufacturer = kComponentManufacturer;
    desc.componentFlags = 0;
    desc.componentFlagsMask = 0;

    NSError* error = nil;
    AdaptiveSoundAU* audioUnit = [[AdaptiveSoundAU alloc] initWithComponentDescription:desc
                                                                              options:0
                                                                                error:&error];
    if (audioUnit == nil) { return nullptr; }

    [audioUnit setRequestedSampleRate:sampleRate bufferFrames:bufferFrames];

    // Transfer an owning (+1) reference to the C caller. Balanced by
    // destroyAdaptiveAudioUnit() via __bridge_transfer.
    return (__bridge_retained void*)audioUnit;
}

void destroyAdaptiveAudioUnit(void* auUnit) {
    if (auUnit == nullptr) { return; }
    // Reclaim the +1 reference handed out by createAdaptiveAudioUnit(); ARC releases
    // when this transferred reference goes out of scope.
    AdaptiveSoundAU* audioUnit = (__bridge_transfer AdaptiveSoundAU*)auUnit;
    [audioUnit deallocateRenderResources];
    audioUnit = nil;
}

bool setAUParameter(void* auUnit, uint64_t paramID, float value) {
    if (auUnit == nullptr) { return false; }
    (void)paramID;
    (void)value;
    // TODO(future sprint): no parameter store / param->TargetState mapping exists yet.
    // The kernel is driven by whole-TargetState publication (publishTargetState); per-
    // parameter control belongs with the Realizer/param model. Returning false rather
    // than caching values that would never reach the kernel.
    return false;
}

float getAUParameter(void* auUnit, uint64_t paramID) {
    if (auUnit == nullptr) { return 0.0F; }
    (void)paramID;
    // TODO(future sprint): see setAUParameter — no readable parameter store yet.
    return 0.0F;
}

bool publishTargetState(void* auUnit, const void* state) {
    if (auUnit == nullptr || state == nullptr) { return false; }
    AdaptiveSoundAU* audioUnit = (__bridge AdaptiveSoundAU*)auUnit; // non-owning borrow
    const TargetState* targetState = static_cast<const TargetState*>(state);
    [audioUnit publishState:*targetState];
    return true;
}

} // extern "C"
