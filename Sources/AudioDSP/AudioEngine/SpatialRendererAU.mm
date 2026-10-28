#import <AudioToolbox/AudioToolbox.h>
#import <AVFoundation/AVFoundation.h>
#include "../include/AudioUnitRegistrationBridge.h" // C prototypes for the registration funcs
#include "../include/MultichannelView.h"
#include "../include/SpatialBridge.h" // the fold's C-ABI (AsFoldState)
#include "../Spatial/SpatialRenderKernel.h"
#include "InProcessEffectAU.h" // the scaffold both in-process AUs share (C-87)
#include <cstddef>
#include <memory>
#include <vector>

using namespace AdaptiveSound;

namespace
{
    // The subtype the in-process spatial-renderer AU is registered under: the same effect type and
    // manufacturer as AdaptiveSoundAU (InProcessEffectScaffold adds them), a DISTINCT subtype so the
    // two custom v3 units have separate registry entries and component descriptions.
    constexpr OSType kComponentSubType = 0x6173707AU; // 'aspz' (Adaptive SPatialiZer)

    // The kernel's routing until the first allocate derives it from the negotiated busses: the
    // scaffold's stereo default.
    constexpr uint32_t kDefaultChannelCount = 2U;

    // channelCapabilities sentinel: -1 means "any number of channels". A {-1, -1} pair
    // (any in, any out) lets AVAudioEngine.connect(...:format:) drive BOTH the source and
    // device channel counts, which is exactly how the spike showed width is negotiated.
    constexpr NSInteger kAnyChannelCount = -1;

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

namespace
{
    // The device-boundary stage's render: NON-IN-PLACE. Pull the N-channel source into the
    // PREALLOCATED input scratch (sized N x maxFrames off-RT), then render N -> M into the
    // host-provided output. The kernel and the scratch are this object's own: the scaffold's render
    // block co-owns it for the AU's whole lifetime, and only allocate (off-RT, not rendering)
    // re-prepares them.
    class SpatialRender final : public InProcessEffectRender
    {
      public:
        SpatialRender() noexcept
        {
            kernel_.configure(kDefaultChannelCount, kDefaultChannelCount);
            kernel_.initialize(kDefaultSampleRate, kDefaultMaxFrames);
        }

        // Off-RT (allocate). Route N source channels to M device channels at the host's rate and
        // frame ceiling, and size the input scratch: N x maxFrames — its SOLE allocation site. False
        // on a degenerate request.
        [[nodiscard]] bool prepare(uint32_t inChannels,
                                   uint32_t outChannels,
                                   uint32_t sampleRate,
                                   uint32_t maxFrames) noexcept
        {
            kernel_.configure(inChannels, outChannels);
            kernel_.initialize(sampleRate, maxFrames);
            return scratch_.allocate(inChannels, maxFrames);
        }

        // Off-RT (deallocate). Free the scratch's storage; the next allocate sizes it again.
        void releaseScratch() noexcept
        {
            scratch_.clear();
        }

        // Any thread: what the fold plays now (atomics).
        [[nodiscard]] FoldReadout readout() const noexcept
        {
            return kernel_.readout();
        }

        AUAudioUnitStatus render(AudioUnitRenderActionFlags* flags,
                                 const AudioTimeStamp* timestamp,
                                 AUAudioFrameCount frames,
                                 AudioBufferList* output,
                                 __unsafe_unretained AURenderPullInputBlock pull) noexcept override
        {
            // Flush-to-zero is the kernel's, scoped to its process() (council C-50), never set over
            // the pull() below, which runs the upstream nodes on this thread.

            // Scratch not yet allocated: nothing valid to render.
            AudioBufferList* inputAbl = scratch_.abl();
            if (inputAbl == nullptr) { return kAudioUnitErr_Uninitialized; }

            // Reset the scratch byte sizes to this call's frame count first, so the pull writes
            // `frames` samples.
            scratch_.prepareForPull(frames);
            const OSStatus pullStatus = pull(flags, timestamp, frames, 0, inputAbl);
            if (pullStatus != noErr) { return pullStatus; }

            const MultichannelView inputView = MultichannelView::fromABL(inputAbl, frames);
            const MultichannelView outputView = MultichannelView::fromABL(output, frames);
            kernel_.process(inputView, outputView);
            return noErr;
        }

      private:
        SpatialRenderKernel kernel_;
        InputScratch scratch_; // the pulled input; read and written on the render thread only
    };
} // namespace

@interface SpatialRendererAU : AUAudioUnit {
    std::shared_ptr<SpatialRender> _render; // created ONCE in -init; co-owned by the render block
    // Busses, render block, rate and frame ceiling.
    InProcessEffectScaffold _scaffold;
}
@property (nonatomic, readonly) AUInternalRenderBlock internalRenderBlock;
// The render (kernel + scratch), for the C-ABI below: off the render thread only.
- (std::shared_ptr<SpatialRender>)spatialRender;
@end

@implementation SpatialRendererAU

- (instancetype)initWithComponentDescription:(AudioComponentDescription)componentDescription
                                     options:(AudioComponentInstantiationOptions)options
                                       error:(NSError**)outError {
    self = [super initWithComponentDescription:componentDescription options:options error:outError];
    if (self == nil) { return nil; }

    // The render (kernel + input scratch): created exactly ONCE, here; allocate re-prepares it and
    // deallocate frees its scratch, neither reconstructs it. (Apple v3 contract: internalRenderBlock
    // must be non-nil at attach — that is why this is in -init.) The connect-negotiated bus formats
    // drive the actual N (input) and M (output) widths, which may DIFFER.
    _render = std::make_shared<SpatialRender>();
    if (!_scaffold.setUp(self, _render)) { return nil; }
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

- (std::shared_ptr<SpatialRender>)spatialRender {
    return _render;
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

    // Adopt the host-negotiated rate + per-call frame ceiling, and DERIVE the routing from the
    // negotiated bus formats: input bus width = N source channels, output bus width = M device
    // channels (they may differ — that is the whole point of this device-boundary stage). The v3
    // contract guarantees allocate runs while not rendering, so re-preparing the render here never
    // races its render().
    _scaffold.adoptHostFormat(self);
    const AVAudioChannelCount inChannels = self.inputBusses[0].format.channelCount;
    const AVAudioChannelCount outChannels = self.outputBusses[0].format.channelCount;
    if (!_render->prepare(static_cast<uint32_t>(inChannels), static_cast<uint32_t>(outChannels),
                          _scaffold.sampleRate(), _scaffold.maxFrames())) {
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
    // Free the input scratch's heap (off-RT; deallocate runs while not rendering). The render
    // itself lives for the AU's whole lifetime, co-owned by the render block; re-allocation
    // re-prepares the SAME instance.
    _render->releaseScratch();
    [super deallocateRenderResources];
}

@end

// MARK: - C ABI (off-RT control plane). Signatures MUST match AudioUnitRegistrationBridge.h.

extern "C" {

AudioComponentDescription spatialRendererComponentDescription(void) AUDIODSP_C_NOEXCEPT {
    return InProcessEffectScaffold::description(kComponentSubType);
}

void registerSpatialRendererAUSubclass(void) AUDIODSP_C_NOEXCEPT {
    static dispatch_once_t onceToken;
    InProcessEffectScaffold::registerOnce(onceToken, [SpatialRendererAU class],
                                          spatialRendererComponentDescription(),
                                          CFSTR("AdaptiveSound: SpatialRendererAU"));
}

// MARK: The fold (SpatialBridge.h)

bool asSpatialFoldState(void* spatialAU, AsFoldState* out) AUDIODSP_C_NOEXCEPT {
    if (spatialAU == nullptr || out == nullptr) {
        return false;
    }
    SpatialRendererAU* audioUnit = (__bridge SpatialRendererAU*)spatialAU; // non-owning borrow
    const std::shared_ptr<SpatialRender> render = [audioUnit spatialRender];
    if (render == nullptr) {
        return false;
    }
    const FoldReadout state = render->readout();
    *out = AsFoldState{
        .sourceChannels = state.sourceChannels,
        .outputChannels = state.outputChannels,
        .folding = state.folding,
        .fromPlan = state.fromPlan,
        .trimDb = state.trimDb,
        .lfeGain = state.lfeGain,
        .backstopPeakGrDb = state.backstopPeakGrDb,
    };
    return true;
}

} // extern "C"
