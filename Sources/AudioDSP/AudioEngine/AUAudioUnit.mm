#import <AudioToolbox/AudioToolbox.h>
#import <AVFoundation/AVFoundation.h>
#include "../include/AsLog.h" // AdaptiveSound::log::line — off-RT control-plane logging seam
#include "../include/AudioConstants.h"
#include "../include/AudioUnitBridge.h" // enforce extern "C" signature agreement for AU functions
#include "../include/AudioUnitRegistrationBridge.h" // C prototypes for the registration funcs
#include "../include/CoreAudioDevice.h"
#include "../include/DeviceBridge.h"   // enforce extern "C" signature agreement for device functions
#include "../include/DSPKernel.h"
#include "../include/TargetState.h"
#include "Realizer.h"                         // off-main single-producer control owner (S6 Tier-3 3a)
#include "../Loudness/ChannelLayoutDecoder.h" // OFF-RT AudioChannelLayoutTag -> ChannelLayout
#include "../Loudness/TrackLoudnessHandle.h"  // AsLoudnessProfile: one shared profile reference
#include <algorithm>
#include <array>
#include <cstring>
#include <memory>
#include <span>

using namespace AdaptiveSound;

namespace
{
    // AudioComponent identity the in-process effect AU is registered under.
    constexpr OSType kComponentType = kAudioUnitType_Effect;  // 'aufx'
    constexpr OSType kComponentSubType = 0x61647364U;         // 'adsd' (AdaptiveSound)
    constexpr OSType kComponentManufacturer = 0x41647364U;    // 'Adsd'
    constexpr uint32_t kComponentVersion = 0x00010000U;       // 1.0.0 (major.minor.patch)

    constexpr AVAudioChannelCount kStereoChannelCount = 2U;

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
    // The off-main single-producer control owner (S6 Tier-3 3a). It OWNS the canonical
    // TargetState (formerly the `_currentState` ivar here) and is the sole caller of
    // DSPKernel::publishTargetState. Moving the canonical state into the Realizer makes
    // "only the Realizer touches it" STRUCTURAL, not conventional. Held by shared_ptr so
    // queued drain blocks (capturing shared_from_this) keep it + the kernel alive until the
    // queue is drained in -dealloc. Created ONCE in -init alongside _kernel.
    std::shared_ptr<AdaptiveSound::Realizer> _realizer;
}
@property (nonatomic, readonly) AUInternalRenderBlock internalRenderBlock;
// Borrow the off-main control owner (used by the C-ABI to post EQ/intensity intents).
- (std::shared_ptr<AdaptiveSound::Realizer>)realizer;
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

    // Realizer: created ONCE here, around the same kernel. It owns the canonical TargetState
    // and is the sole producer of feed-forward control through publishTargetState. It holds
    // a shared_ptr<DSPKernel> copy, so the kernel cannot be freed while a drain is in flight;
    // -dealloc drains the Realizer's queue BEFORE releasing the kernel (see below).
    _realizer = std::make_shared<AdaptiveSound::Realizer>(_kernel, static_cast<double>(_sampleRate));

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
        (void)events;   // MIDI not used by this AU

        // Flush-to-zero is the kernel's, scoped to its process() (council C-50): set here, before
        // pull(), it would also run Apple's upstream nodes — which render inside pull() on this
        // thread — in a floating-point mode that is not theirs.

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
    // kernel THROUGH THE REALIZER (engine-plan §6): reinitializeKernel() runs on the Realizer's
    // queue (dispatch_sync), so the re-initialisation is serialised with every publish, and it
    // re-solves the EQ and re-derives the crossfeed at the new rate before rendering resumes —
    // a rate or channel change never plays flat. The v3 contract guarantees allocate runs while
    // the AU is not rendering; the render block co-owns this same kernel instance.
    const double negotiatedSampleRate = self.outputBusses[0].format.sampleRate;
    if (negotiatedSampleRate > 0.0) {
        _sampleRate = static_cast<uint32_t>(negotiatedSampleRate);
    }
    const AUAudioFrameCount hostMaxFrames = self.maximumFramesToRender;
    if (hostMaxFrames > 0U) {
        _bufferFrames = static_cast<uint32_t>(hostMaxFrames);
    }
    _realizer->reinitializeKernel(_sampleRate, _bufferFrames);
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
    // __bridge_transfer in destroyAdaptiveAudioUnit / ARC).
    //
    // Teardown ORDER is load-bearing (the review's BLOCKER, design §1):
    //  1. Drain the Realizer's serial queue via a dispatch_sync barrier, so no queued drain
    //     block runs after we release the kernel. shutdown() returns only once every enqueued
    //     block has finished; queued blocks capture shared_from_this, so the Realizer + its
    //     kernel co-owner stay alive through the last publish.
    //  2. Drop the Realizer (releases its kernel co-owner copy).
    //  3. Drop the render block (releases its kernel co-owner copy).
    //  4. Drop our kernel member — the DSPKernel destructor runs here, off-RT, only after the
    //     last publisher has quiesced (drain before releasing kernel).
    if (_realizer != nullptr) { _realizer->shutdown(); }
    _realizer.reset();
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

// Off-RT control plane. Borrow the Realizer (the shared_ptr<Realizer> owner). All
// feed-forward control now flows through it; the canonical TargetState lives inside it.
- (std::shared_ptr<AdaptiveSound::Realizer>)realizer {
    return _realizer;
}

// Off-RT control plane. Forwards a fully-formed TargetState directly to the RT kernel via the
// lock-free double-buffer (SPSC producer side; never called on the render thread). Retained
// only for the publishTargetState C-ABI (tests). NOTE: this is a SECOND publish plane parallel
// to the Realizer; the two are unordered w.r.t. each other (design §1.4). Production control
// flows through the Realizer (publishEQ/publishIntensity/publishCrossfeed), not this.
- (void)publishState:(const TargetState&)state {
    if (_kernel != nullptr) { _kernel->publishTargetState(state); }
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

// Helper: the copyOutputDevice*C string contract — copy `value` into the caller's buffer
// (NUL-terminated, truncated to fit) and return its full length, snprintf-style.
static uint32_t copyDeviceString(const std::string& value, char* out, uint32_t capacity) {
    if (out != nullptr && capacity > 0U) {
        const std::span<char> buffer(out, capacity);
        const size_t copied = std::min(value.size(), buffer.size() - 1U);
        std::copy_n(value.begin(), copied, buffer.begin());
        buffer[copied] = '\0';
    }
    return static_cast<uint32_t>(value.size());
}

extern "C" {

// MARK: AU registration (in-process v3 instantiation; off-RT, main-thread during setup)

AudioComponentDescription adaptiveAudioUnitComponentDescription(void) AUDIODSP_C_NOEXCEPT {
    AudioComponentDescription desc = {};
    desc.componentType = kComponentType;
    desc.componentSubType = kComponentSubType;
    desc.componentManufacturer = kComponentManufacturer;
    desc.componentFlags = 0;
    desc.componentFlagsMask = 0;
    return desc;
}

void registerAdaptiveAudioUnitSubclass(void) AUDIODSP_C_NOEXCEPT {
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

uint32_t enumerateOutputDevicesC(CDeviceInfo* outDevices, uint32_t maxCount) AUDIODSP_C_NOEXCEPT {
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
        out.transportType   = dev.transportType;
        out.deviceType      = deviceTypeToByte(dev.type);
        out.isHeadphones    = dev.isHeadphones ? 1U : 0U;

        // Safe copy: ensure null-termination even if name is too long.
        constexpr size_t kNameBufSize = sizeof(out.name);
        std::strncpy(out.name, dev.name.c_str(), kNameBufSize - 1U);
        out.name[kNameBufSize - 1U] = '\0';

        ++written;
    }

    return written;
}

uint32_t copyOutputDeviceUIDC(uint32_t deviceID, char* out, uint32_t capacity) AUDIODSP_C_NOEXCEPT {
    const auto device = static_cast<AudioDeviceID>(deviceID);
    return copyDeviceString(AdaptiveSound::CoreAudioDevice::getDeviceUID(device), out, capacity);
}

uint32_t copyOutputDeviceModelUIDC(uint32_t deviceID, char* out, uint32_t capacity) AUDIODSP_C_NOEXCEPT {
    const auto device = static_cast<AudioDeviceID>(deviceID);
    return copyDeviceString(AdaptiveSound::CoreAudioDevice::getDeviceModelUID(device), out, capacity);
}

int isListedOutputDeviceC(uint32_t deviceID) AUDIODSP_C_NOEXCEPT {
    if (deviceID == 0) { return 0; }
    return AdaptiveSound::CoreAudioDevice::isListedOutput(static_cast<AudioDeviceID>(deviceID)) ? 1 : 0;
}

uint32_t getDefaultOutputDeviceID() AUDIODSP_C_NOEXCEPT {
    AudioDeviceID id = AdaptiveSound::CoreAudioDevice::getDefaultOutputDevice();
    // kAudioObjectUnknown == 0 on all Apple platforms; return 0 to signal "none".
    return (id == kAudioObjectUnknown) ? 0U : static_cast<uint32_t>(id);
}

int selectOutputDeviceC(uint32_t deviceID) AUDIODSP_C_NOEXCEPT {
    if (deviceID == 0) { return 0; }
    // Verify the device ID resolves to a real device before accepting it.
    std::string name = AdaptiveSound::CoreAudioDevice::getDeviceName(static_cast<AudioDeviceID>(deviceID));
    if (name == "Unknown Device" || name.empty()) { return 0; }

    // "App-selected device is authoritative" (founder decision): make the picked device the macOS
    // default output. Pure targets currentDeviceID directly; the Enhanced AVAudioEngine follows the
    // system default — so setting the default here keeps BOTH paths on the device the user picked in
    // the app (fixes the "OS says Bluetooth, app plays on built-in" mismatch). Best-effort: a set
    // failure is logged but still returns success, since Pure uses currentDeviceID regardless.
    AudioObjectPropertyAddress addr{
        kAudioHardwarePropertyDefaultOutputDevice,
        kAudioObjectPropertyScopeGlobal,
        kAudioObjectPropertyElementMain,
    };
    AudioDeviceID dev = static_cast<AudioDeviceID>(deviceID);
    const OSStatus status = AudioObjectSetPropertyData(
        kAudioObjectSystemObject, &addr, 0, nullptr, sizeof(dev), &dev);
    if (status != noErr) {
        AdaptiveSound::log::line(
            "[selectOutputDeviceC] could not set default output device {} (status {})", deviceID,
            static_cast<int>(status));
    }
    return 1;
}

void* createAdaptiveAudioUnit(void* audioEngine, uint32_t sampleRate, uint32_t bufferFrames) AUDIODSP_C_NOEXCEPT {
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

void destroyAdaptiveAudioUnit(void* auUnit) AUDIODSP_C_NOEXCEPT {
    if (auUnit == nullptr) { return; }
    // Reclaim the +1 reference handed out by createAdaptiveAudioUnit(); ARC releases
    // when this transferred reference goes out of scope.
    AdaptiveSoundAU* audioUnit = (__bridge_transfer AdaptiveSoundAU*)auUnit;
    [audioUnit deallocateRenderResources];
    audioUnit = nil;
}

bool setAUParameter(void* auUnit, uint64_t paramID, float value) AUDIODSP_C_NOEXCEPT {
    if (auUnit == nullptr) { return false; }
    (void)paramID;
    (void)value;
    // Intentionally a dead stub returning false. The intensity surface (AUParameterID::Intensity)
    // is routed through the dedicated publishIntensity() C-ABI (design §1.5) — the single
    // intensity surface that posts to the Realizer's pending-intensity slot. We deliberately do
    // NOT also accept it here, to avoid two contradictory surfaces. EQ likewise drives the kernel
    // via publishEQ -> the Realizer, not an AU parameter tree. This stub stays part of
    // the stable exported C-ABI; it returns false rather than caching values that never reach the
    // kernel. See publishIntensity().
    return false;
}

float getAUParameter(void* auUnit, uint64_t paramID) AUDIODSP_C_NOEXCEPT {
    if (auUnit == nullptr) { return 0.0F; }
    (void)paramID;
    // No readable parameter store yet — see setAUParameter. Part of the stable
    // exported C-ABI surface.
    return 0.0F;
}

bool publishTargetState(void* auUnit, const void* state) AUDIODSP_C_NOEXCEPT {
    if (auUnit == nullptr || state == nullptr) { return false; }
    AdaptiveSoundAU* audioUnit = (__bridge AdaptiveSoundAU*)auUnit; // non-owning borrow
    const TargetState* targetState = static_cast<const TargetState*>(state);
    [audioUnit publishState:*targetState];
    return true;
}

bool publishEQ(void* auUnit, const float* pointsDb, uint32_t count, bool isOn) AUDIODSP_C_NOEXCEPT {
    // Sprint EQ (engine-plan §8): the points the UI draws + On/Off. The Realizer validates (the
    // trust boundary), designs on its queue at the kernel's rate and publishes; the RT module
    // glides to the finished coefficients.
    if (auUnit == nullptr) {
        AdaptiveSound::log::line("[EQ] C-ABI publishEQ SKIP — auUnit == nullptr");
        return false;
    }
    AdaptiveSoundAU* audioUnit = (__bridge AdaptiveSoundAU*)auUnit; // non-owning borrow
    std::shared_ptr<AdaptiveSound::Realizer> realizer = [audioUnit realizer];
    if (realizer == nullptr) {
        AdaptiveSound::log::line("[EQ] C-ABI publishEQ SKIP — realizer == nil");
        return false;
    }
    AdaptiveSound::log::debug("[QW1] C-ABI publishEQ count={} on={}", count, isOn);
    return realizer->setPendingEq(pointsDb, count, isOn);
}

double eqDesignSampleRate(void* auUnit) AUDIODSP_C_NOEXCEPT {
    if (auUnit == nullptr) {
        return 0.0;
    }
    AdaptiveSoundAU* audioUnit = (__bridge AdaptiveSoundAU*)auUnit; // non-owning borrow
    std::shared_ptr<AdaptiveSound::Realizer> realizer = [audioUnit realizer];
    return (realizer != nullptr) ? realizer->eqDesignSampleRate() : 0.0;
}

// The live AU's Realizer, borrowed for one C-ABI call (nullptr when there is none).
static std::shared_ptr<AdaptiveSound::Realizer> borrowRealizer(void* auUnit) noexcept {
    if (auUnit == nullptr) {
        return nullptr;
    }
    AdaptiveSoundAU* audioUnit = (__bridge AdaptiveSoundAU*)auUnit; // non-owning borrow
    return [audioUnit realizer];
}

bool publishTrackLoudnessProfile(void* auUnit, uint64_t trackToken, const AsLoudnessProfile* profile) AUDIODSP_C_NOEXCEPT {
    // Sprint EQ, EQ1c: the analyzer's profile. The handle's shared reference is copied — the
    // blocks are not — so the engine's copy outlives the caller's handle.
    std::shared_ptr<AdaptiveSound::Realizer> realizer = borrowRealizer(auUnit);
    if (realizer == nullptr || profile == nullptr || trackToken == 0U || !profile->profile) {
        return false;
    }
    realizer->publishTrackLoudnessProfile(trackToken, profile->profile);
    return true;
}

void reportTrackLoudnessFailure(void* auUnit, uint64_t trackToken) AUDIODSP_C_NOEXCEPT {
    if (std::shared_ptr<AdaptiveSound::Realizer> realizer = borrowRealizer(auUnit)) {
        realizer->reportTrackLoudnessFailure(trackToken);
    }
}

void setCurrentTrack(void* auUnit, uint64_t trackToken, bool gaplessSeam) AUDIODSP_C_NOEXCEPT {
    if (std::shared_ptr<AdaptiveSound::Realizer> realizer = borrowRealizer(auUnit)) {
        realizer->setCurrentTrack(trackToken, gaplessSeam);
    }
}

void publishOutputTransport(void* auUnit, uint32_t transportType) AUDIODSP_C_NOEXCEPT {
    // Sprint EQ, EQ2 (decision 29): the EQ-only path's limiter ceiling follows the output.
    if (std::shared_ptr<AdaptiveSound::Realizer> realizer = borrowRealizer(auUnit)) {
        realizer->setOutputTransport(transportType);
    }
}

void publishIntensity(void* auUnit, float intensity) AUDIODSP_C_NOEXCEPT {
    // S6 Tier-3 (3a): the single intensity control surface (design §1.5). Clamps to [0,1]
    // inside the Realizer, sets the pending-intensity slot, and posts a drain when none is
    // pending. The intensity slot is SEPARATE from the EQ slot, so an
    // interleaved intensity intent is never dropped by an EQ burst. Off-RT; no-op if null.
    AdaptiveSound::log::debug("[QW1] C-ABI publishIntensity intensity={:.4f}", intensity);
    if (auUnit == nullptr) {
        AdaptiveSound::log::line("[QW1] C-ABI publishIntensity SKIP — auUnit == nullptr");
        return;
    }
    AdaptiveSoundAU* audioUnit = (__bridge AdaptiveSoundAU*)auUnit; // non-owning borrow
    std::shared_ptr<AdaptiveSound::Realizer> realizer = [audioUnit realizer];
    if (realizer != nullptr) {
        realizer->setPendingIntensity(intensity);
    } else {
        AdaptiveSound::log::line("[QW1] C-ABI publishIntensity SKIP — realizer == nil");
    }
}

void publishCrossfeed(void* auUnit, uint32_t enabled, uint32_t preset) AUDIODSP_C_NOEXCEPT {
    // QW1 §3: the single crossfeed control surface. Sets the Realizer's pending-crossfeed slot
    // (preset clamped to the valid enum range) and posts a drain when none is pending; the off-RT
    // coefficient derivation, the canonical read-modify-write, and the atomic publish happen
    // off-main in the Realizer's serial queue. The crossfeed slot is SEPARATE from the
    // EQ/intensity slots, so an interleaved crossfeed intent is never dropped. The Realizer
    // derives the coefficients at the rate it owns. Off-RT; no-op if null.
    AdaptiveSound::log::debug("[QW1] C-ABI publishCrossfeed enabled={} preset={}", enabled, preset);
    if (auUnit == nullptr) {
        AdaptiveSound::log::line("[QW1] C-ABI publishCrossfeed SKIP — auUnit == nullptr");
        return;
    }
    AdaptiveSoundAU* audioUnit = (__bridge AdaptiveSoundAU*)auUnit; // non-owning borrow
    std::shared_ptr<AdaptiveSound::Realizer> realizer = [audioUnit realizer];
    if (realizer != nullptr) {
        realizer->setPendingCrossfeed(enabled, preset);
    } else {
        AdaptiveSound::log::line("[QW1] C-ABI publishCrossfeed SKIP — realizer == nil");
    }
}

void publishChannelLayoutTag(void* auHandle, AudioChannelLayoutTag tag) AUDIODSP_C_NOEXCEPT {
    if (auHandle == nullptr) { return; }
    // Resolve the AU from the borrowed handle exactly as publishEQ does (non-owning
    // __bridge borrow; no retain/release). The method decodes off-RT and publishes lock-free.
    AdaptiveSoundAU* audioUnit = (__bridge AdaptiveSoundAU*)auHandle;
    [audioUnit publishChannelLayoutTag:tag];
}

} // extern "C"
