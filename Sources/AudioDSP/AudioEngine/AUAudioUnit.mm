#import <AudioToolbox/AudioToolbox.h>
#import <AVFoundation/AVFoundation.h>
#include "../include/AsLog.h" // AdaptiveSound::log::line — off-RT control-plane logging seam
#include "../include/AudioUnitRegistrationBridge.h" // C prototypes for the registration funcs
#include "../include/CoreAudioDevice.h"
#include "../include/DeviceBridge.h"   // enforce extern "C" signature agreement for device functions
#include "../include/DSPKernel.h"
#include "InProcessEffectAU.h"                // the scaffold both in-process AUs share (C-87)
#include "Realizer.h"                         // off-main single-producer control owner (S6 Tier-3 3a)
#include "../Loudness/ChannelLayoutDecoder.h" // OFF-RT AudioChannelLayoutTag -> ChannelLayout
#include "../Loudness/TrackLoudnessHandle.h"  // AsLoudnessProfile: one shared profile reference
#include <algorithm>
#include <array>
#include <cstring>
#include <memory>
#include <span>
#include <utility>

using namespace AdaptiveSound;

namespace
{
    // The subtype the in-process effect AU is registered under (InProcessEffectScaffold adds the
    // app's effect type and manufacturer).
    constexpr OSType kComponentSubType = 0x61647364U; // 'adsd' (AdaptiveSound)

    // The effects chain's render: an in-place effect. Pull the input straight into the output
    // buffers, then process them in place (fix #11 + #4: no stack AudioBufferList with room for one
    // buffer — corruption for planar input — and no memcpy of input-sized bytes into smaller
    // output buffers). AVAudioEngine provides non-null output buffer pointers.
    class EffectsRender final : public InProcessEffectRender
    {
      public:
        explicit EffectsRender(std::shared_ptr<DSPKernel> kernel) noexcept
            : kernel_(std::move(kernel)) {}

        AUAudioUnitStatus render(AudioUnitRenderActionFlags* flags,
                                 const AudioTimeStamp* timestamp,
                                 AUAudioFrameCount frames,
                                 AudioBufferList* output,
                                 __unsafe_unretained AURenderPullInputBlock pull) noexcept override
        {
            // Flush-to-zero is the kernel's, scoped to its process() (council C-50): set here, before
            // pull(), it would also run Apple's upstream nodes — which render inside pull() on this
            // thread — in a floating-point mode that is not theirs.
            const OSStatus pullStatus = pull(flags, timestamp, frames, 0, output);
            if (pullStatus != noErr) { return pullStatus; }
            kernel_->process(output, frames);
            return noErr;
        }

      private:
        std::shared_ptr<DSPKernel> kernel_; // non-null for the render's whole lifetime
    };

} // namespace

@interface AdaptiveSoundAU : AUAudioUnit {
    std::shared_ptr<DSPKernel> _kernel; // created ONCE in -init; never reset until -dealloc
    // The off-main single-producer control owner (S6 Tier-3 3a). It OWNS the canonical
    // TargetState (formerly the `_currentState` ivar here) and is the sole caller of
    // DSPKernel::publishTargetState. Moving the canonical state into the Realizer makes
    // "only the Realizer touches it" STRUCTURAL, not conventional. Held by shared_ptr so
    // queued drain blocks (capturing shared_from_this) keep it + the kernel alive until the
    // queue is drained in -dealloc. Created ONCE in -init alongside _kernel.
    std::shared_ptr<AdaptiveSound::Realizer> _realizer;
    // Busses, render block (co-owning the kernel through EffectsRender), rate and frame ceiling.
    InProcessEffectScaffold _scaffold;
}
@property (nonatomic, readonly) AUInternalRenderBlock internalRenderBlock;
// Borrow the off-main control owner (used by the C-ABI to post EQ/intensity intents).
- (std::shared_ptr<AdaptiveSound::Realizer>)realizer;
// S2: the kernel's crossfeed status (one relaxed atomic load).
- (bool)kernelCrossfeedEngaged;
@end

@implementation AdaptiveSoundAU

- (instancetype)initWithComponentDescription:(AudioComponentDescription)componentDescription
                                     options:(AudioComponentInstantiationOptions)options
                                       error:(NSError**)outError {
    self = [super initWithComponentDescription:componentDescription options:options error:outError];
    if (self == nil) { return nil; }

    // Kernel: created exactly ONCE, here. allocate/deallocate only re-initialize() it; they
    // never construct or reset it. The render block co-owns this same instance for the AU's whole
    // lifetime, so the kernel can never be freed out from under a live render block, nor freed on
    // the RT thread. (Apple v3 contract: internalRenderBlock must be non-nil at attach — that is
    // why this is in -init, not allocateRenderResources.)
    _kernel = std::make_shared<DSPKernel>();
    _kernel->initialize(_scaffold.sampleRate(), _scaffold.maxFrames());

    // Realizer: created ONCE here, around the same kernel. It owns the canonical TargetState
    // and is the sole producer of feed-forward control through publishTargetState. It holds
    // a shared_ptr<DSPKernel> copy, so the kernel cannot be freed while a drain is in flight;
    // -dealloc drains the Realizer's queue BEFORE releasing the kernel (see below).
    _realizer = std::make_shared<AdaptiveSound::Realizer>(_kernel,
                                                          static_cast<double>(_scaffold.sampleRate()));

    if (!_scaffold.setUp(self, std::make_shared<EffectsRender>(_kernel))) { return nil; }
    return self;
}

- (AUAudioUnitBusArray*)inputBusses {
    return _scaffold.inputBusses();
}

- (AUAudioUnitBusArray*)outputBusses {
    return _scaffold.outputBusses();
}

- (AUInternalRenderBlock)internalRenderBlock {
    return _scaffold.renderBlock();
}

- (BOOL)allocateRenderResourcesAndReturnError:(NSError**)outError {
    if (![super allocateRenderResourcesAndReturnError:outError]) { return NO; }

    // Adopt the host-negotiated output rate and per-call frame ceiling, then re-prepare the SAME
    // kernel THROUGH THE REALIZER (engine-plan §6): reinitializeKernel() runs on the Realizer's
    // queue (dispatch_sync), so the re-initialisation is serialised with every publish, and it
    // re-solves the EQ and re-derives the crossfeed at the new rate before rendering resumes —
    // a rate or channel change never plays flat. The v3 contract guarantees allocate runs while
    // the AU is not rendering; the render block co-owns this same kernel instance. (Deallocation
    // resets nothing: the kernel lives as long as the AU, and re-allocation re-initializes it.)
    _scaffold.adoptHostFormat(self);
    _realizer->reinitializeKernel(_scaffold.sampleRate(), _scaffold.maxFrames());
    return YES;
}

- (void)dealloc {
    // The single, off-RT teardown point (runs when the engine releases the AU's last reference).
    //
    // Teardown ORDER is load-bearing (the review's BLOCKER, design §1): drain the Realizer's serial
    // queue via a dispatch_sync barrier BEFORE any kernel owner lets go, so no queued drain block
    // runs after the kernel is gone. shutdown() returns only once every enqueued block has
    // finished; queued blocks capture shared_from_this, so the Realizer + its kernel co-owner stay
    // alive through the last publish. Then the Realizer, our kernel member and (after this body)
    // the scaffold's render block let go — the DSPKernel destructor runs off-RT, after the last
    // publisher has quiesced.
    if (_realizer != nullptr) { _realizer->shutdown(); }
    _realizer.reset();
    _kernel.reset();
}

// Off-RT control plane. Borrow the Realizer (the shared_ptr<Realizer> owner). All
// feed-forward control now flows through it; the canonical TargetState lives inside it.
- (std::shared_ptr<AdaptiveSound::Realizer>)realizer {
    return _realizer;
}

- (bool)kernelCrossfeedEngaged {
    return _kernel != nullptr && _kernel->crossfeedEngaged();
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

// MARK: - C ABI (off-RT control plane). Signatures MUST match AudioUnitRegistrationBridge.h and
// DeviceBridge.h exactly (both are included above, so a mismatch fails to compile).

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
    return InProcessEffectScaffold::description(kComponentSubType);
}

void registerAdaptiveAudioUnitSubclass(void) AUDIODSP_C_NOEXCEPT {
    static dispatch_once_t onceToken;
    InProcessEffectScaffold::registerOnce(onceToken, [AdaptiveSoundAU class],
                                          adaptiveAudioUnitComponentDescription(),
                                          CFSTR("AdaptiveSound: AdaptiveSoundAU"));
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

bool publishEQ(void* auUnit, const float* pointsDb, uint32_t count, bool isOn) AUDIODSP_C_NOEXCEPT {
    return publishEQIntent(auUnit, pointsDb, count, isOn, false);
}

bool publishEQIntent(void* auUnit, const float* pointsDb, uint32_t count, bool isOn,
                     bool comparing) AUDIODSP_C_NOEXCEPT {
    // Sprint EQ (engine-plan §8): the points the UI draws + On/Off. The Realizer validates (the
    // trust boundary), designs on its queue at the kernel's rate and publishes; the RT module
    // glides to the finished coefficients. While Compare is held the curve's identity plays at the
    // level the curve plays at (R1.1-B, §7).
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
    AdaptiveSound::log::debug("[QW1] C-ABI publishEQ count={} on={} comparing={}", count, isOn, comparing);
    return realizer->setPendingEq(pointsDb, count, isOn, comparing);
}

double eqDesignSampleRate(void* auUnit) AUDIODSP_C_NOEXCEPT {
    if (auUnit == nullptr) {
        return 0.0;
    }
    AdaptiveSoundAU* audioUnit = (__bridge AdaptiveSoundAU*)auUnit; // non-owning borrow
    std::shared_ptr<AdaptiveSound::Realizer> realizer = [audioUnit realizer];
    return (realizer != nullptr) ? realizer->eqDesignSampleRate() : 0.0;
}

bool crossfeedEngaged(void* auUnit) AUDIODSP_C_NOEXCEPT {
    // R1.1-B, S2: one relaxed load of the kernel's status — no queue, no lock.
    if (auUnit == nullptr) {
        return false;
    }
    AdaptiveSoundAU* audioUnit = (__bridge AdaptiveSoundAU*)auUnit; // non-owning borrow
    return [audioUnit kernelCrossfeedEngaged];
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

// C2's rebuild of a saved compact profile is lane 1-B's (TrackLoudnessBridge.h declares it; its definition lands
// with the analysis pass, R1.1-B W4). Until that definition joins the link, this WEAK one answers "cannot be
// rebuilt", so the bridge falls back to analysing the track as it plays — today's path. A strong definition
// replaces it at link time without a clash. To be deleted at the combine, once lane 1-B's is in.
extern "C" __attribute__((weak)) AsLoudnessProfile*
asLoudnessProfileFromCompact(const AsCompactProfileInfo* /*info*/, const uint16_t* /*powers*/,
                             uint32_t /*count*/) AUDIODSP_C_NOEXCEPT {
    return nullptr;
}

bool publishSavedLoudnessProfile(void* auUnit, uint64_t trackToken,
                                 const AsLoudnessProfile* profile) AUDIODSP_C_NOEXCEPT {
    // R1.1-B, C2: the persisted profile, final — the shared reference is copied, not the blocks.
    std::shared_ptr<AdaptiveSound::Realizer> realizer = borrowRealizer(auUnit);
    if (realizer == nullptr || profile == nullptr || trackToken == 0U || !profile->profile) {
        return false;
    }
    realizer->publishTrackLoudnessProfile(trackToken, profile->profile, true);
    return true;
}

void applyTrackPlan(void* auUnit, uint64_t trackToken, uint8_t event, const AsTrackPlan* plan,
                    bool continuousWithPrevious) AUDIODSP_C_NOEXCEPT {
    if (plan == nullptr || event > static_cast<uint8_t>(AsPlanEventOutputChange)) {
        return;
    }
    if (std::shared_ptr<AdaptiveSound::Realizer> realizer = borrowRealizer(auUnit)) {
        realizer->applyTrackPlan(trackToken, static_cast<AsPlanEvent>(event), *plan, continuousWithPrevious);
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
