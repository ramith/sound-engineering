#import <AudioToolbox/AudioToolbox.h>
#import <AVFoundation/AVFoundation.h>
#include "../include/AudioConstants.h"
#include "../include/DSPKernel.h"
#include <memory>

using namespace AdaptiveSound;

@interface AdaptiveSoundAU : AUAudioUnit {
    std::unique_ptr<DSPKernel> _kernel;
    AUInternalRenderBlock _renderBlock;
}
@property (nonatomic, readonly) AUInternalRenderBlock internalRenderBlock;
@end

@implementation AdaptiveSoundAU

- (BOOL)allocateRenderResourcesAndReturnError:(NSError**)outError {
    if (![super allocateRenderResourcesAndReturnError:outError]) { return NO; }

    _kernel = std::make_unique<DSPKernel>();
    _kernel->initialize(kDefaultSampleRate, kDefaultMaxFrames);

    AdaptiveSoundAU *__weak weakSelf = self;
    _renderBlock = ^AUAudioUnitStatus(AudioUnitRenderActionFlags* flags,
                                      const AudioTimeStamp* timestamp,
                                      AUAudioFrameCount frames,
                                      NSInteger busNum,
                                      AudioBufferList* out,
                                      const AURenderEvent* events,
                                      AURenderPullInputBlock pull) {
        AdaptiveSoundAU *strongSelf = weakSelf;
        if (strongSelf == nil || strongSelf->_kernel == nullptr) { return kAudioUnitErr_Uninitialized; }

        AudioBufferList input;
        if (pull(flags, timestamp, frames, 0, &input) == noErr) {
            // TODO(#4): memcpy uses input byte size into output buffer; clamp to min in fix
            for (UInt32 i = 0; i < out->mNumberBuffers && i < input.mNumberBuffers; ++i) {
                memcpy(out->mBuffers[i].mData, input.mBuffers[i].mData,
                       input.mBuffers[i].mDataByteSize);
            }
        }
        strongSelf->_kernel->process(out, frames);
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

@end

extern "C" {
void createAdaptiveAudioUnit(void* engine) { }
void destroyAdaptiveAudioUnit(void* handle) { }
void setAUParameter(void* handle, uint32_t parameterId, float val) { }
}
