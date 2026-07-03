#import <AudioToolbox/AudioToolbox.h>
#import <AVFoundation/AVFoundation.h>
#include "../include/AudioConstants.h"
#include "../include/AudioUnitRegistrationBridge.h" // C prototypes for the registration funcs
#include "../include/MultichannelView.h"
#include "../Spatial/SpatialRenderKernel.h"
#include <cstddef>
#include <memory>
#include <vector>

using namespace AdaptiveSound;

namespace
{
    // AudioComponent identity the in-process spatial-renderer AU is registered under.
    // Same type + manufacturer as AdaptiveSoundAU; a DISTINCT subtype ('aspz') so the
    // two custom v3 units have separate registry entries and component descriptions.
    constexpr OSType kComponentType = kAudioUnitType_Effect;  // 'aufx'
    constexpr OSType kComponentSubType = 0x6173707AU;         // 'aspz' (Adaptive SPatialiZer)
    constexpr OSType kComponentManufacturer = 0x41647364U;    // 'Adsd' (matches AdaptiveSoundAU)
    constexpr uint32_t kComponentVersion = 0x00010000U;       // 1.0.0 (major.minor.patch)

    // Default published bus width before the engine's connect-driven format negotiation
    // re-widths the busses. Stereo is the safe baseline both AUAudioUnitBus inits accept.
    constexpr AVAudioChannelCount kDefaultChannelCount = 2U;

    // channelCapabilities sentinel: -1 means "any number of channels". A {-1, -1} pair
    // (any in, any out) lets AVAudioEngine.connect(...:format:) drive BOTH the source and
    // device channel counts, which is exactly how the spike showed width is negotiated.
    constexpr NSInteger kAnyChannelCount = -1;

    // FPCR flush-to-zero (FZ) bit on AArch64 (FPCR.FZ, bit 24 — ARM DDI 0487 §A1.4.3).
    constexpr uint64_t kFpcrFlushToZeroBit = 1ULL << 24U;

    // Enable flush-to-zero on the calling thread (must be called at render-block entry).
    // FPCR is a per-thread register; this sets it on the render thread independently of
    // the control-thread call in SpatialRenderKernel::initialize(). Mirrors AUAudioUnit.mm.
    inline void setRenderThreadFTZ() noexcept
    {
#ifdef __aarch64__
        uint64_t fpcr = 0U;
        __asm__ volatile("mrs %0, fpcr" : "=r"(fpcr));
        fpcr |= kFpcrFlushToZeroBit;
        __asm__ volatile("msr fpcr, %0" : : "r"(fpcr));
#endif
    }
} // namespace

// Non-interleaved float32 scratch buffer for the pulled input. Owns its storage via std::vector
// (rule of zero, C.20 — no hand-rolled new/delete/free): a flat planar sample block, plus a byte
// vector backing the flexible AudioBufferList whose mBuffers point into the sample block.
// (Re)sized ONCE per allocateRenderResources (off-RT); read/written only on the render thread.
// The vectors' capacity is the sole input allocation site; the render path never resizes them.
namespace
{
    class InputScratch
    {
      public:
        InputScratch() = default;

        // Off-RT ONLY. (Re)allocate to hold `channels` planar buffers of `frames` floats each.
        // Returns false on a degenerate request (leaves the object empty). This is the sole
        // allocation site for the input scratch; the render thread never reaches an allocator.
        [[nodiscard]] auto allocate(uint32_t channels, uint32_t frames) noexcept -> bool
        {
            channels_ = 0U;
            if (channels == 0U || frames == 0U)
            {
                return false;
            }

            const size_t frameCount = static_cast<size_t>(frames);
            const size_t totalSamples = static_cast<size_t>(channels) * frameCount;
            samples_.assign(totalSamples, 0.0F);

            // Flexible-array AudioBufferList: the base struct embeds one AudioBuffer, so reserve
            // (channels - 1) EXTRA trailing AudioBuffers' worth of bytes.
            const size_t ablBytes =
                sizeof(AudioBufferList) + (static_cast<size_t>(channels - 1U) * sizeof(AudioBuffer));
            ablStorage_.assign(ablBytes, std::byte{0});

            // sole ABL decode; the
            // byte vector is sized + aligned for AudioBufferList above (vectors are max-aligned).
            auto* abl = reinterpret_cast<AudioBufferList*>(ablStorage_.data());
            abl->mNumberBuffers = channels;
            const UInt32 bytesPerChannel = static_cast<UInt32>(frameCount * sizeof(float));
            for (uint32_t ch = 0U; ch < channels; ++ch)
            {
                // CoreAudio
                // flexible-array idiom: the ABL was sized for `channels` AudioBuffers above.
                AudioBuffer& buffer = abl->mBuffers[ch];
                buffer.mNumberChannels = 1U; // non-interleaved: one channel per buffer
                buffer.mDataByteSize = bytesPerChannel;
                buffer.mData = samples_.data() + (static_cast<size_t>(ch) * frameCount);
            }
            channels_ = channels;
            return true;
        }

        // Off-RT. Release the backing storage (used by deallocateRenderResources).
        void clear() noexcept
        {
            samples_.clear();
            samples_.shrink_to_fit();
            ablStorage_.clear();
            ablStorage_.shrink_to_fit();
            channels_ = 0U;
        }

        // RT-safe. Reset every buffer's mDataByteSize to the per-call frame count BEFORE pulling,
        // so the pull block writes the host's actual frame count (<= capacity) and the
        // MultichannelView reports the right width. No allocation; pure field writes.
        void prepareForPull(uint32_t frames) noexcept
        {
            if (channels_ == 0U)
            {
                return;
            }
            // see allocate()
            auto* abl = reinterpret_cast<AudioBufferList*>(ablStorage_.data());
            const UInt32 byteSize = static_cast<UInt32>(static_cast<size_t>(frames) * sizeof(float));
            for (uint32_t ch = 0U; ch < channels_; ++ch)
            {
                // sized above
                abl->mBuffers[ch].mDataByteSize = byteSize;
            }
        }

        // RT-safe. The backing ABL, or nullptr if not yet allocated.
        [[nodiscard]] auto abl() noexcept -> AudioBufferList*
        {
            if (channels_ == 0U)
            {
                return nullptr;
            }
            // see allocate()
            return reinterpret_cast<AudioBufferList*>(ablStorage_.data());
        }

      private:
        std::vector<float> samples_;        // flat channels_ * frames_ planar sample block
        std::vector<std::byte> ablStorage_; // backing bytes for the flexible-array ABL
        uint32_t channels_ = 0U;
    };
} // namespace

@interface SpatialRendererAU : AUAudioUnit {
    std::shared_ptr<SpatialRenderKernel> _kernel; // created ONCE in -init; never reset until -dealloc
    std::shared_ptr<InputScratch> _inputScratch;  // sole input-ABL owner; co-owned by render block
    AUInternalRenderBlock _renderBlock;           // created ONCE in -init; co-owns kernel + scratch
    AUAudioUnitBus* _inputBus;
    AUAudioUnitBus* _outputBus;
    AUAudioUnitBusArray* _inputBusArray;
    AUAudioUnitBusArray* _outputBusArray;
    uint32_t _sampleRate;   // single source of truth; re-synced in allocateRenderResources
    uint32_t _bufferFrames; // host max frames; applied in allocateRenderResources
}
@property (nonatomic, readonly) AUInternalRenderBlock internalRenderBlock;
@end

@implementation SpatialRendererAU

- (instancetype)initWithComponentDescription:(AudioComponentDescription)componentDescription
                                     options:(AudioComponentInstantiationOptions)options
                                       error:(NSError**)outError {
    self = [super initWithComponentDescription:componentDescription options:options error:outError];
    if (self == nil) { return nil; }

    _sampleRate = kDefaultSampleRate;
    _bufferFrames = kDefaultMaxFrames;

    // Kernel + input scratch: created exactly ONCE, here. allocate/deallocate only
    // re-initialize()/re-allocate() them; they never reconstruct. The render block (below)
    // co-owns both by value (shared_ptr copies) for the AU's whole lifetime, so neither can be
    // freed out from under a live render block nor freed on the RT thread. (Apple v3 contract:
    // internalRenderBlock must be non-nil at attach — that is why this is in -init.)
    _kernel = std::make_shared<SpatialRenderKernel>();
    _kernel->configure(kDefaultChannelCount, kDefaultChannelCount);
    _kernel->initialize(_sampleRate, _bufferFrames);
    _inputScratch = std::make_shared<InputScratch>();

    // Capture the kernel + scratch by value (shared_ptr copies) so the render block never touches
    // `self` nor promotes a __weak reference on the audio thread — no Obj-C runtime calls on the
    // RT path. These copies are the block's strong co-owners; copy/destroy happen off-RT (block
    // creation here / teardown in -dealloc), never during render. Both non-null for the block's
    // lifetime; the SCRATCH'S underlying ABL is non-null only after allocateRenderResources, which
    // the v3 contract guarantees runs before any render.
    std::shared_ptr<SpatialRenderKernel> kernel = _kernel;
    std::shared_ptr<InputScratch> inputScratch = _inputScratch;
    _renderBlock = ^AUAudioUnitStatus(AudioUnitRenderActionFlags* flags,
                                      const AudioTimeStamp* timestamp,
                                      AUAudioFrameCount frames,
                                      NSInteger busNum,
                                      AudioBufferList* outputData,
                                      const AURenderEvent* events,
                                      AURenderPullInputBlock pull) {
        (void)busNum; // single output bus; index unused by this in-process AU
        (void)events; // MIDI not used by this AU

        // Set FPCR.FZ on this render thread so subnormals are flushed to zero (~1 cycle on M1).
        setRenderThreadFTZ();

        // No upstream to pull, or scratch not yet allocated — nothing valid to render.
        if (pull == nullptr) { return kAudioUnitErr_NoConnection; }
        AudioBufferList* inputAbl = inputScratch->abl();
        if (inputAbl == nullptr) { return kAudioUnitErr_Uninitialized; }

        // NON-IN-PLACE: pull the N-channel source into the PREALLOCATED input scratch (sized
        // N x maxFrames off-RT), then render N -> M into the engine-provided output ABL. Reset the
        // scratch byte sizes to this call's frame count first so the pull writes `frames` samples.
        inputScratch->prepareForPull(frames);
        const OSStatus pullStatus = pull(flags, timestamp, frames, 0, inputAbl);
        if (pullStatus != noErr) { return pullStatus; }

        const MultichannelView inputView = MultichannelView::fromABL(inputAbl, frames);
        const MultichannelView outputView = MultichannelView::fromABL(outputData, frames);
        kernel->process(inputView, outputView);
        return noErr;
    };

    // Busses: one input + one output, each non-interleaved float32. The engine's
    // connect(...:format:) drives the actual N (input) and M (output) widths (which may DIFFER);
    // a v3 effect AU with no bus arrays fails engine.connect().
    if (![self setupBussesWithSampleRate:_sampleRate error:outError]) { return nil; }

    return self;
}

// Build the published input/output busses from a canonical non-interleaved float32 stereo format
// at `sampleRate`. The connect-driven negotiation re-widths them later; channelCapabilities
// advertises "any in / any out" so {2,6,8} on either side is accepted.
- (BOOL)setupBussesWithSampleRate:(uint32_t)sampleRate error:(NSError**)outError {
    AVAudioFormat* format =
        [[AVAudioFormat alloc] initStandardFormatWithSampleRate:static_cast<double>(sampleRate)
                                                       channels:kDefaultChannelCount];
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

// {-1, -1}: any input channel count, any output channel count. This lets AVAudioEngine's
// connect-driven format negotiation set both N and M freely (the spike confirmed connect, not
// channelCapabilities, drives width); returning a restrictive pair would make connect fail.
- (NSArray<NSNumber*>*)channelCapabilities {
    NSNumber* anyChannels = [NSNumber numberWithInteger:kAnyChannelCount];
    return @[ anyChannels, anyChannels ];
}

- (BOOL)allocateRenderResourcesAndReturnError:(NSError**)outError {
    if (![super allocateRenderResourcesAndReturnError:outError]) { return NO; }

    // Adopt the host-negotiated sample rate + per-call frame ceiling as the single source of
    // truth. DERIVE the routing from the negotiated bus formats: input bus width = N source
    // channels, output bus width = M device channels (they may differ — that is the whole point of
    // this device-boundary stage). The v3 contract guarantees allocate runs while not rendering,
    // so reconfiguring the kernel + reallocating the scratch here never races process().
    const double negotiatedSampleRate = self.outputBusses[0].format.sampleRate;
    if (negotiatedSampleRate > 0.0) {
        _sampleRate = static_cast<uint32_t>(negotiatedSampleRate);
    }
    const AUAudioFrameCount hostMaxFrames = self.maximumFramesToRender;
    if (hostMaxFrames > 0U) {
        _bufferFrames = static_cast<uint32_t>(hostMaxFrames);
    }

    const AVAudioChannelCount inChannels = self.inputBusses[0].format.channelCount;
    const AVAudioChannelCount outChannels = self.outputBusses[0].format.channelCount;

    _kernel->configure(static_cast<uint32_t>(inChannels), static_cast<uint32_t>(outChannels));
    _kernel->initialize(_sampleRate, _bufferFrames);

    // SOLE allocation site for the input scratch: N source channels x maxFrames. The render block
    // co-owns this same InputScratch instance, so reallocating its contents here is safe — the
    // block reads abl() fresh each call and never caches the pointer.
    if (!_inputScratch->allocate(static_cast<uint32_t>(inChannels), _bufferFrames)) {
        if (outError != nullptr) {
            *outError = [NSError errorWithDomain:NSOSStatusErrorDomain
                                            code:kAudioUnitErr_FailedInitialization
                                        userInfo:nil];
        }
        return NO;
    }
    return YES;
}

- (void)deallocateRenderResources {
    // Free the input scratch's heap (off-RT; deallocate runs while not rendering). Does NOT reset
    // _kernel / _inputScratch / _renderBlock object ownership: those live for the AU's whole
    // lifetime and are co-owned by the render block; re-allocation re-prepares the SAME instances.
    if (_inputScratch != nullptr) {
        _inputScratch->clear(); // frees the backing storage; leaves the shared object alive
    }
    [super deallocateRenderResources];
}

- (void)dealloc {
    // The single, off-RT teardown point (last reference drop via __bridge_transfer / ARC). Drop the
    // block first (releasing its captured shared_ptr copies), then the members — the
    // SpatialRenderKernel + InputScratch destructors run here, off-RT.
    _renderBlock = nil;
    _inputScratch.reset();
    _kernel.reset();
}

- (AUInternalRenderBlock)internalRenderBlock {
    return _renderBlock;
}

// Off-RT control plane. Stores the desired sample rate / buffer size applied on the next
// allocateRenderResources.
- (void)setRequestedSampleRate:(uint32_t)sampleRate bufferFrames:(uint32_t)bufferFrames {
    if (sampleRate != 0U) { _sampleRate = sampleRate; }
    if (bufferFrames != 0U) { _bufferFrames = bufferFrames; }
}

// Off-RT control plane. Explicit routing override for callers that do NOT drive width via the
// negotiated bus formats. Normally unnecessary — allocateRenderResources derives N/M from the
// connect-negotiated bus formats — but exposed for the C-ABI configureSpatialChannels().
- (void)configureInputChannels:(uint32_t)inChannels outputChannels:(uint32_t)outChannels {
    if (_kernel != nullptr) { _kernel->configure(inChannels, outChannels); }
}

@end

// MARK: - C ABI (off-RT control plane). Pure-C signatures mirror the AdaptiveSoundAU C-ABI.

extern "C" {

AudioComponentDescription spatialRendererComponentDescription(void) {
    AudioComponentDescription desc = {};
    desc.componentType = kComponentType;
    desc.componentSubType = kComponentSubType;
    desc.componentManufacturer = kComponentManufacturer;
    desc.componentFlags = 0;
    desc.componentFlagsMask = 0;
    return desc;
}

void registerSpatialRendererAUSubclass(void) {
    // registerSubclass: must run exactly once per process; dispatch_once guards against double
    // registration when engine setup repeats (e.g. device re-init).
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        [AUAudioUnit registerSubclass:[SpatialRendererAU class]
               asComponentDescription:spatialRendererComponentDescription()
                                 name:@"AdaptiveSound: SpatialRendererAU"
                              version:kComponentVersion];
    });
}

void configureSpatialChannels(void* auHandle, uint32_t inChannels, uint32_t outChannels) {
    if (auHandle == nullptr) { return; }
    SpatialRendererAU* audioUnit = (__bridge SpatialRendererAU*)auHandle; // non-owning borrow
    [audioUnit configureInputChannels:inChannels outputChannels:outChannels];
}

} // extern "C"
