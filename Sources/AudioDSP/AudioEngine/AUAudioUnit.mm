#import <AudioToolbox/AudioToolbox.h>
#include "../include/DSPKernel.h"
#include "../include/TargetState.h"
#include <memory>

using namespace AdaptiveSound;

// ============================================================================
// Objective-C++ AUAudioUnit Implementation
// ============================================================================

@interface AdaptiveSoundAU : AUAudioUnit {
    std::unique_ptr<DSPKernel> _kernel;
    AUInternalRenderBlock _renderBlock;
}
@property (nonatomic, readonly) AUInternalRenderBlock internalRenderBlock;
@end

@implementation AdaptiveSoundAU

- (instancetype)initWithComponentDescription:(AudioComponentDescription)componentDescription
                                      options:(AudioComponentInstantiationOptions)options
                                        error:(NSError**)outError {
    self = [super initWithComponentDescription:componentDescription options:options error:outError];
    if (self == nil) {
        return nil;
    }
    return self;
}

- (BOOL)allocateRenderResourcesAndReturnError:(NSError**)outError {
    if ([super allocateRenderResourcesAndReturnError:outError] == NO) {
        return NO;
    }

    // Create DSP kernel
    _kernel = std::make_unique<DSPKernel>();
    
    // Initialize with current sample rate and buffer frame size
    uint32_t sampleRate = static_cast<uint32_t>(self.outputBus.format.sampleRate);
    uint32_t maxFrames = self.maximumFramesToRender;
    if (maxFrames == 0) { maxFrames = 4096; }
    
    _kernel->initialize(sampleRate, maxFrames);

    // Store the render block in our ivar (internalRenderBlock is readonly)
    __weak typeof(self) weakSelf = self;
    _renderBlock = ^AUAudioUnitStatus(AudioUnitRenderActionFlags* actionFlags,
                                      const AudioTimeStamp* timestamp,
                                      AVAudioFrameCount frameCount,
                                      NSInteger outputBusNumber,
                                      AudioBufferList* outputData,
                                      const AURenderEvent* realtimeEventListHead,
                                      AURenderPullInputBlock pullInputBlock) {
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf || !strongSelf->_kernel) {
            return kAudioUnitErr_Uninitialized;
        }
        
        // Get input audio
        AudioBufferList* inputData = nullptr;
        AUAudioUnitStatus status = pullInputBlock(actionFlags, timestamp, frameCount, 0, &inputData);
        if (status != noErr || !inputData) {
            // Silence output on input failure
            for (UInt32 i = 0; i < outputData->mNumberBuffers; ++i) {
                memset(outputData->mBuffers[i].mData, 0, outputData->mBuffers[i].mDataByteSize);
            }
            return noErr;
        }

        // Copy input to output (for now; DSP kernel will process in-place)
        for (UInt32 i = 0; i < outputData->mNumberBuffers; ++i) {
            if (i < inputData->mNumberBuffers) {
                memcpy(outputData->mBuffers[i].mData,
                       inputData->mBuffers[i].mData,
                       inputData->mBuffers[i].mDataByteSize);
            }
        }

        // Process audio through DSP kernel
        strongSelf->_kernel->process(outputData, frameCount);
        
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

// ============================================================================
// C Bridge for Swift Integration
// ============================================================================

extern "C" {

typedef void* AudioUnitHandle;

AudioUnitHandle createAdaptiveAudioUnit(void* avAudioEngine) {
    if (!avAudioEngine) return nullptr;
    
    AVAudioEngine* engine = (__bridge AVAudioEngine*)avAudioEngine;
    
    AudioComponentDescription desc = {
        .componentType = kAudioUnitType_Effect,
        .componentSubType = 'adpt',
        .componentManufacturer = 'ASND',
        .componentFlags = 0,
        .componentFlagsMask = 0
    };

    NSError* error = nil;
    AVAudioUnit* audioUnit = nil;
    
    [AVAudioUnit instantiateWithComponentDescription:desc
                                              options:0
                                    completionHandler:^(AVAudioUnit* unit, NSError* err) {
        audioUnit = unit;
        error = err;
    }];

    if (error || !audioUnit) {
        return nullptr;
    }

    // Attach to engine (but don't connect; Swift layer handles graph routing)
    [engine attachNode:audioUnit];
    
    return (__bridge_retained void*)audioUnit;
}

void destroyAdaptiveAudioUnit(AudioUnitHandle handle) {
    if (!handle) return;
    AVAudioUnit* unit = (__bridge_transfer AVAudioUnit*)handle;
    // AUAudioUnit teardown is automatic on dealloc
    unit = nil;
}

void setAUParameter(AudioUnitHandle handle, uint32_t parameterID, float value) {
    if (!handle) return;
    AVAudioUnit* unit = (__bridge AVAudioUnit*)handle;
    
    // For Phase 1a, this is a placeholder; full parameter tree comes in Phase 1b
    // Currently supports Master Gain (ID 0)
    if (parameterID == 0) {
        unit.auAudioUnit.outputBusses[0].volume = value;
    }
}

float getAUParameter(AudioUnitHandle handle, uint32_t parameterID) {
    if (!handle) return 0.0f;
    AVAudioUnit* unit = (__bridge AVAudioUnit*)handle;
    
    if (parameterID == 0) {
        return unit.auAudioUnit.outputBusses[0].volume;
    }
    return 0.0f;
}

void publishTargetState(AudioUnitHandle handle, const TargetState* state) {
    if (!handle || !state) return;
    // Placeholder for Phase 1b: will wire to kernel->publishTargetState()
}

}
