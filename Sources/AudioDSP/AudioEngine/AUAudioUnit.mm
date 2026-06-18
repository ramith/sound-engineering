#import <AudioToolbox/AudioToolbox.h>
#import <AVFoundation/AVFoundation.h>
#include "../include/AudioConstants.h"
#include "../include/AudioUnitBridge.h" // enforce extern "C" signature agreement for AU functions
#include "../include/AudioUnitRegistrationBridge.h" // C prototypes for the registration funcs
#include "../include/CoreAudioDevice.h"
#include "../include/DeviceBridge.h"   // enforce extern "C" signature agreement for device functions
#include "../include/DSPKernel.h"
#include "../include/TargetState.h"
#include "../EQ/EQModuleCoefficients.h" // EQ Realizer (31 gains -> biquad cascade)
#include "../Loudness/ChannelLayoutDecoder.h" // OFF-RT AudioChannelLayoutTag -> ChannelLayout
#include <array>
#include <cstring>
#include <memory>

using namespace AdaptiveSound;

namespace
{
    // AudioComponent identity the in-process effect AU is registered under.
    constexpr OSType kComponentType = kAudioUnitType_Effect;  // 'aufx'
    constexpr OSType kComponentSubType = 0x61647364U;         // 'adsd' (AdaptiveSound)
    constexpr OSType kComponentManufacturer = 0x41647364U;    // 'Adsd'
    constexpr uint32_t kComponentVersion = 0x00010000U;       // 1.0.0 (major.minor.patch)

    constexpr AVAudioChannelCount kStereoChannelCount = 2U;

    // FPCR flush-to-zero (FZ) bit on AArch64.
    constexpr uint64_t kFpcrFlushToZeroBit = 1ULL << 24U;

    // Enable flush-to-zero on the calling thread (must be called at render-block entry).
    // See DSPKernel.mm::enableFlushToZero() for the full rationale.
    // FPCR is a per-thread register; this sets it on the render thread independently
    // of the control-thread call in DSPKernel::initialize().
    inline void setRenderThreadFTZ() noexcept
    {
#ifdef __aarch64__
        uint64_t fpcr = 0;
        __asm__ volatile("mrs %0, fpcr" : "=r"(fpcr));
        fpcr |= kFpcrFlushToZeroBit;
        __asm__ volatile("msr fpcr, %0" : : "r"(fpcr));
#endif
    }
} // namespace

@interface AdaptiveSoundAU : AUAudioUnit {
    std::shared_ptr<DSPKernel> _kernel; // created ONCE in -init; never reset until -dealloc
    AUInternalRenderBlock _renderBlock; // created ONCE in -init; co-owns _kernel by value
    AUAudioUnitBus* _inputBus;
    AUAudioUnitBus* _outputBus;
    AUAudioUnitBusArray* _inputBusArray;
    AUAudioUnitBusArray* _outputBusArray;
    uint32_t _sampleRate;   // single source of truth; re-synced in allocateRenderResources
    uint32_t _bufferFrames; // host max frames; applied in allocateRenderResources
    // Retained authoritative control-plane state. Control-thread-only (the EQ view model on the
    // main actor). EQ updates mutate only .eq and re-publish the whole state, so other modules
    // keep their last-set values rather than reverting to defaults on each slider move.
    TargetState _currentState;
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

    // Kernel: created exactly ONCE, here. allocate/deallocate only re-initialize() it; they
    // never construct or reset it. The render block (below) co-owns this same instance by
    // value for the AU's whole lifetime, so the kernel can never be freed out from under a
    // live render block, nor freed on the RT thread. (Apple v3 contract: internalRenderBlock
    // must be non-nil at attach — that is why this is in -init, not allocateRenderResources.)
    _kernel = std::make_shared<DSPKernel>();
    _kernel->initialize(_sampleRate, _bufferFrames);

    // Capture the kernel by value (shared_ptr copy) so the render block never touches `self`
    // nor promotes a __weak reference on the audio thread — i.e. no Obj-C runtime calls
    // (objc_loadWeakRetained) on the RT path (issue #7). The copy here is the block's strong
    // co-owner; the copy/destroy happen off-RT (block creation in -init / teardown in
    // -dealloc), never during render. `kernel` is non-null for the block's entire lifetime.
    std::shared_ptr<DSPKernel> kernel = _kernel;
    _renderBlock = ^AUAudioUnitStatus(AudioUnitRenderActionFlags* flags,
                                      const AudioTimeStamp* timestamp,
                                      AUAudioFrameCount frames,
                                      NSInteger busNum,
                                      AudioBufferList* out,
                                      const AURenderEvent* events,
                                      AURenderPullInputBlock pull) {
        (void)busNum;   // single output bus; index unused by this in-process AU
        (void)events;   // MIDI events deferred to Phase 2 MIDI implementation

        // Set FPCR.FZ on this render thread so subnormals are flushed to zero.
        // Called once per render callback; the register write is ~1 cycle on M1.
        setRenderThreadFTZ();

        // Fix #11 + #4: pull input directly into the output buffers (in-place effect),
        // then process in place. This removes the stack-declared AudioBufferList (which
        // had storage for only one AudioBuffer — stack corruption for planar/multi-buffer
        // input, #11) and the memcpy that wrote input-sized bytes into possibly-smaller
        // output buffers (#4). AVAudioEngine provides non-null output buffer pointers.
        OSStatus pullStatus = pull(flags, timestamp, frames, 0, out);
        if (pullStatus != noErr) { return pullStatus; }

        kernel->process(out, frames);
        return noErr;
    };

    // Busses: one stereo input + one stereo output so AVAudioEngine can connect upstream and
    // downstream nodes. A v3 effect AU with no bus arrays fails engine.connect() (Gap 2).
    if (![self setupBussesWithSampleRate:_sampleRate error:outError]) { return nil; }

    return self;
}

// Build the published input/output busses from a canonical non-interleaved float32 stereo
// format at `sampleRate`. The bus sample rate and DSPKernel both read `_sampleRate`, so there
// is a single source of truth keeping them consistent.
- (BOOL)setupBussesWithSampleRate:(uint32_t)sampleRate error:(NSError**)outError {
    AVAudioFormat* format =
        [[AVAudioFormat alloc] initStandardFormatWithSampleRate:static_cast<double>(sampleRate)
                                                       channels:kStereoChannelCount];
    if (format == nil) { return NO; }

    _inputBus = [[AUAudioUnitBus alloc] initWithFormat:format error:outError];
    if (_inputBus == nil) { return NO; }
    _outputBus = [[AUAudioUnitBus alloc] initWithFormat:format error:outError];
    if (_outputBus == nil) { return NO; }

    _inputBusArray = [[AUAudioUnitBusArray alloc] initWithAudioUnit:self
                                                            busType:AUAudioUnitBusTypeInput
                                                             busses:@[ _inputBus ]];
    _outputBusArray = [[AUAudioUnitBusArray alloc] initWithAudioUnit:self
                                                             busType:AUAudioUnitBusTypeOutput
                                                              busses:@[ _outputBus ]];
    return (_inputBusArray != nil && _outputBusArray != nil) ? YES : NO;
}

- (AUAudioUnitBusArray*)inputBusses {
    return _inputBusArray;
}

- (AUAudioUnitBusArray*)outputBusses {
    return _outputBusArray;
}

- (BOOL)allocateRenderResourcesAndReturnError:(NSError**)outError {
    if (![super allocateRenderResourcesAndReturnError:outError]) { return NO; }

    // Adopt the host-negotiated output sample rate (device SR can change since -init) and the
    // host's per-call frame ceiling as the single source of truth, then re-prepare the SAME
    // kernel. DSPKernel::initialize() rebuilds its modules in place (RAII frees the old ones)
    // and is noexcept; the v3 contract guarantees allocate runs while the AU is not rendering,
    // so this never races process(). The render block is untouched and stays valid because it
    // co-owns this same kernel instance.
    const double negotiatedSampleRate = self.outputBusses[0].format.sampleRate;
    if (negotiatedSampleRate > 0.0) {
        _sampleRate = static_cast<uint32_t>(negotiatedSampleRate);
    }
    const AUAudioFrameCount hostMaxFrames = self.maximumFramesToRender;
    if (hostMaxFrames > 0U) {
        _bufferFrames = static_cast<uint32_t>(hostMaxFrames);
    }
    _kernel->initialize(_sampleRate, _bufferFrames);
    return YES;
}

- (void)deallocateRenderResources {
    // Intentionally does NOT reset _kernel or _renderBlock. The kernel is owned for the AU's
    // whole lifetime (created in -init, released in -dealloc) and is co-owned by the render
    // block; resetting here would leave the block pointing at a dead kernel on the next
    // allocate (the block is never re-created) and risk freeing a kernel the engine could
    // still hold a render-block reference to. Re-allocation re-initialize()s this same kernel.
    [super deallocateRenderResources];
}

- (void)dealloc {
    // The single, off-RT teardown point (runs when the last reference drops via
    // __bridge_transfer in destroyAdaptiveAudioUnit / ARC). Drop the block first (releasing its
    // captured shared_ptr copy), then the member — the DSPKernel destructor runs here, off-RT.
    _renderBlock = nil;
    _kernel.reset();
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

// Off-RT control plane. Composes new EQ coefficients into the retained current state (so
// clarity/loudness/brir/limiter keep their last-set values) and re-publishes the whole state.
// Single-producer: control thread only, never the render thread.
- (void)publishEQParams:(const AdaptiveSound::EQParams&)eqParams {
    _currentState.eq = eqParams;
    _currentState.sequenceNumber += 1;
    [self publishState:_currentState];
}

// Off-RT control plane. Decodes the source layout tag (off-RT, allocation-free) and forwards the
// resulting per-channel BS.1770-5 weights to the kernel, which publishes them lock-free to the
// loudness worker. Single-producer: control thread only, never the render thread.
- (void)publishChannelLayoutTag:(AudioChannelLayoutTag)tag {
    if (_kernel != nullptr) {
        const ChannelLayout layout = decodeChannelLayout(tag);
        _kernel->publishChannelLayout(layout);
    }
}

@end

// MARK: - C ABI (off-RT control plane). Signatures MUST match AudioUnitBridge.h exactly.

// Helper: map C++ AudioDevice::Type to the uint8_t used in CDeviceInfo
static uint8_t deviceTypeToByte(AdaptiveSound::AudioDevice::Type type) {
    switch (type) {
    case AdaptiveSound::AudioDevice::Type::Builtin:  return 1U;
    case AdaptiveSound::AudioDevice::Type::USB:       return 2U;
    case AdaptiveSound::AudioDevice::Type::Wireless:  return 3U;
    default:                                           return 0U;
    }
}

extern "C" {

// MARK: AU registration (in-process v3 instantiation; off-RT, main-thread during setup)

AudioComponentDescription adaptiveAudioUnitComponentDescription(void) {
    AudioComponentDescription desc = {};
    desc.componentType = kComponentType;
    desc.componentSubType = kComponentSubType;
    desc.componentManufacturer = kComponentManufacturer;
    desc.componentFlags = 0;
    desc.componentFlagsMask = 0;
    return desc;
}

void registerAdaptiveAudioUnitSubclass(void) {
    // registerSubclass: must run exactly once per process; dispatch_once guards against
    // double registration when engine setup repeats (e.g. device re-init).
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        [AUAudioUnit registerSubclass:[AdaptiveSoundAU class]
               asComponentDescription:adaptiveAudioUnitComponentDescription()
                                 name:@"AdaptiveSound: AdaptiveSoundAU"
                              version:kComponentVersion];
    });
}

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
    if (name == "Unknown Device" || name.empty()) { return 0; }

    // "App-selected device is authoritative" (founder decision): make the picked device the macOS
    // default output. Pure targets currentDeviceID directly; the Enhanced AVAudioEngine follows the
    // system default — so setting the default here keeps BOTH paths on the device the user picked in
    // the app (fixes the "OS says Bluetooth, app plays on built-in" mismatch). Best-effort: a set
    // failure is logged but still returns success, since Pure uses currentDeviceID regardless.
    AudioObjectPropertyAddress addr{kAudioHardwarePropertyDefaultOutputDevice,
                                    kAudioObjectPropertyScopeGlobal,
                                    kAudioObjectPropertyElementMain};
    AudioDeviceID dev = static_cast<AudioDeviceID>(deviceID);
    const OSStatus status = AudioObjectSetPropertyData(
        kAudioObjectSystemObject, &addr, 0, nullptr, sizeof(dev), &dev);
    if (status != noErr) {
        // NOLINTNEXTLINE(cppcoreguidelines-pro-type-vararg) — NSLog is the platform logging API.
        NSLog(@"[selectOutputDeviceC] could not set default output device %u (status %d)", deviceID,
              static_cast<int>(status));
    }
    return 1;
}

void* createAdaptiveAudioUnit(void* audioEngine, uint32_t sampleRate, uint32_t bufferFrames) {
    // Attach into the AVAudioEngine graph is driven Swift-side via AVAudioUnit.instantiate()
    // using adaptiveAudioUnitComponentDescription(); this direct-alloc path remains for callers
    // that want the subclass instance directly.
    (void)audioEngine;
    registerAdaptiveAudioUnitSubclass();

    NSError* error = nil;
    AdaptiveSoundAU* audioUnit =
        [[AdaptiveSoundAU alloc] initWithComponentDescription:adaptiveAudioUnitComponentDescription()
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

bool publishEQBandGains(void* auUnit, const float* bandGainsDb, uint32_t count, double sampleRate) {
    // Control-plane contract: 31-band ISO grid, valid SR, non-null pointers. Reject mismatches
    // rather than partially filling (which would silently zero the missing bands).
    if (auUnit == nullptr || bandGainsDb == nullptr) { return false; }
    if (count != static_cast<uint32_t>(EQModuleCoefficients::kNumBands)) { return false; }
    if (!(sampleRate > 0.0)) { return false; } // also rejects NaN

    // Copy caller-owned floats into the value type the designer expects; bandGainsDb need not
    // outlive this call.
    std::array<float, EQModuleCoefficients::kNumBands> gains{};
    std::memcpy(gains.data(), bandGainsDb, sizeof(gains));

    // Off-RT minimum-phase cascade design, then compose into retained state + atomic publish.
    // computeBiquadCascade is allocation-free; the vDSP setup alloc happens inside
    // publishCoefficients, still off the render thread.
    const EQParams eqParams = EQModuleCoefficients::computeBiquadCascade(gains, static_cast<float>(sampleRate));
    AdaptiveSoundAU* audioUnit = (__bridge AdaptiveSoundAU*)auUnit; // non-owning borrow
    [audioUnit publishEQParams:eqParams];
    return true;
}

void publishChannelLayoutTag(void* auHandle, AudioChannelLayoutTag tag) {
    if (auHandle == nullptr) { return; }
    // Resolve the AU from the borrowed handle exactly as publishEQBandGains does (non-owning
    // __bridge borrow; no retain/release). The method decodes off-RT and publishes lock-free.
    AdaptiveSoundAU* audioUnit = (__bridge AdaptiveSoundAU*)auHandle;
    [audioUnit publishChannelLayoutTag:tag];
}

} // extern "C"
