#import <AudioToolbox/AudioToolbox.h>
#import <AVFoundation/AVFoundation.h>
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
    if (![super allocateRenderResourcesAndReturnError:outError]) return NO;
    
    _kernel = std::make_unique<DSPKernel>();
    _kernel->initialize(48000, 512);

    __weak typeof(self) weakSelf = self;
    _renderBlock = ^AUAudioUnitStatus(AudioUnitRenderActionFlags* flags,
                                      const AudioTimeStamp* ts,
                                      AUAudioFrameCount frames,
                                      NSInteger busNum,
                                      AudioBufferList* out,
                                      const AURenderEvent* events,
                                      AURenderPullInputBlock pull) {
        typeof(self) self = weakSelf;
        if (!self || !self->_kernel) return kAudioUnitErr_Uninitialized;
        
        AudioBufferList input;
        if (pull(flags, ts, frames, 0, &input) == noErr) {
            for (UInt32 i = 0; i < out->mNumberBuffers && i < input.mNumberBuffers; ++i) {
                memcpy(out->mBuffers[i].mData, input.mBuffers[i].mData, 
                       input.mBuffers[i].mDataByteSize);
            }
        }
        self->_kernel->process(out, frames);
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
void setAUParameter(void* handle, uint32_t id, float val) { }
}
