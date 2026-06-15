#import <AudioToolbox/AudioToolbox.h>
#import <AVFoundation/AVFoundation.h>
#include "../include/AudioConstants.h"
#include "../include/AudioUnitBridge.h" // enforce extern "C" signature agreement for AU functions
#include "../include/CoreAudioDevice.h"
#include "../include/DeviceBridge.h"   // enforce extern "C" signature agreement for device functions
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

    // Enable flush-to-zero on the calling thread (must be called at render-block entry).
    // See DSPKernel.mm::enableFlushToZero() for the full rationale.
    // FPCR is a per-thread register; this sets it on the render thread independently
    // of the control-thread call in DSPKernel::initialize().
    inline void setRenderThreadFTZ() noexcept
    {
#if defined(__aarch64__)
        uint64_t fpcr = 0;
        __asm__ volatile("mrs %0, fpcr" : "=r"(fpcr));
        fpcr |= (1ULL << 24U); // FZ bit
        __asm__ volatile("msr fpcr, %0" : : "r"(fpcr));
#endif
    }
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
        (void)busNum;   // required by AURenderBlock typedef; not used by this in-process AU
        (void)events;   // MIDI events deferred to Phase 2 MIDI implementation
        if (kernel == nullptr) { return kAudioUnitErr_Uninitialized; }

        // Set FPCR.FZ on this render thread so subnormals are flushed to zero.
        // Called once per render callback; the register write is ~1 cycle on M1.
        setRenderThreadFTZ();

        // Fix #11 + #4: pull input directly into the output buffers (in-place effect),
        // then process in place. This removes the stack-declared AudioBufferList (which
        // had storage for only one AudioBuffer — stack corruption for planar/multi-buffer
        // input, #11) and the memcpy that wrote input-sized bytes into possibly-smaller
        // output buffers (#4). Assumes the host (AVAudioEngine) provides non-null output
        // buffer pointers; the null-mData fallback for other hosts/auval belongs with the
        // deferred AU host integration (#6).
        OSStatus pullStatus = pull(flags, timestamp, frames, 0, out);
        if (pullStatus != noErr) { return pullStatus; }

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

// Helper: map C++ AudioDevice::Type to the uint8_t used in CDeviceInfo
static uint8_t deviceTypeToByte(AdaptiveSound::AudioDevice::Type t) {
    switch (t) {
    case AdaptiveSound::AudioDevice::Type::Builtin:  return 1U;
    case AdaptiveSound::AudioDevice::Type::USB:       return 2U;
    case AdaptiveSound::AudioDevice::Type::Wireless:  return 3U;
    default:                                           return 0U;
    }
}

extern "C" {

// MARK: Device enumeration

uint32_t enumerateOutputDevicesC(CDeviceInfo* outDevices, uint32_t maxCount) {
    if (outDevices == nullptr || maxCount == 0) {
        return 0;
    }

    auto devices = AdaptiveSound::CoreAudioDevice::enumerateOutputDevices();
    uint32_t written = 0;

    for (const auto& dev : devices) {
        if (written >= maxCount) { break; }

        CDeviceInfo& out = outDevices[written];
        out.deviceID        = dev.id;
        out.sampleRate      = dev.sampleRate;
        out.bufferFrameSize = dev.bufferFrameSize;
        out.deviceType      = deviceTypeToByte(dev.type);

        // Safe copy: ensure null-termination even if name is too long.
        constexpr size_t kNameBufSize = sizeof(out.name);
        std::strncpy(out.name, dev.name.c_str(), kNameBufSize - 1U);
        out.name[kNameBufSize - 1U] = '\0';

        ++written;
    }

    return written;
}

uint32_t getDefaultOutputDeviceID() {
    AudioDeviceID id = AdaptiveSound::CoreAudioDevice::getDefaultOutputDevice();
    // kAudioObjectUnknown == 0 on all Apple platforms; return 0 to signal "none".
    return (id == kAudioObjectUnknown) ? 0U : static_cast<uint32_t>(id);
}

int selectOutputDeviceC(uint32_t deviceID) {
    if (deviceID == 0) { return 0; }
    // Verify the device ID resolves to a real device before accepting it.
    std::string name = AdaptiveSound::CoreAudioDevice::getDeviceName(static_cast<AudioDeviceID>(deviceID));
    return (name != "Unknown Device" && !name.empty()) ? 1 : 0;
}

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
