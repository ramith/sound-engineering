//
// HALOutputEngine.mm — bit-perfect HAL output engine (Pure Mode, Phase B — B2a).
//
// Obj-C++. Drives one output device via a kAudioUnitSubType_HALOutput AudioUnit. The CoreAudio
// query / mutate patterns (first output stream, hog acquire/release, nominal-rate set + poll,
// RAII restore) are lifted from scripts/hal-spike.mm; the render-callback float->native conversion
// uses the CoreAudio-free convertFloatToNative().
//
// SAFETY: device mutation (hog, nominal rate) happens only in configure()/stop() on the control
// thread. The original nominal rate is saved up front and ALWAYS restored on teardown; hog is
// released only if we acquired it. Teardown is idempotent and runs from the destructor, so an
// early return still restores the device.
//

#import <AudioToolbox/AudioToolbox.h>
#import <CoreAudio/CoreAudio.h>
#import <Foundation/Foundation.h>

#include "../include/HALOutputEngine.h"
#include "../include/PureModeFormat.h"
#include "../include/PureModeSource.h"

#include <atomic>
#include <cmath>
#include <cstdint>
#include <cstring>
#include <ctime>
#include <unistd.h> // getpid
#include <vector>

// Control-plane logging only (configure/start/stop); never on the RT audio thread.
// NOLINTBEGIN(cppcoreguidelines-pro-type-vararg)

using namespace AdaptiveSound;

namespace
{
    // AUHAL component identity.
    constexpr OSType kHalOutputType = kAudioUnitType_Output;
    constexpr OSType kHalOutputSubType = kAudioUnitSubType_HALOutput;

    // Rate-change polling, mirrored from the spike: poll up to ~2 s in 10 ms steps.
    constexpr double kRateChangeTimeoutMs = 2000.0;
    constexpr long kRatePollStepNs = 10L * 1000L * 1000L; // 10 ms
    constexpr double kRateEpsilonHz = 1.0;

    constexpr uint32_t kMaxRenderFrames = 4096U; // scratch sizing ceiling (host frame cap)

    // Native integer / float sample bit depths used when building the AUHAL stream format.
    constexpr uint32_t kBitDepth16 = 16U;
    constexpr uint32_t kBitDepth32 = 32U;

    constexpr double kMsPerSec = 1000.0;
    constexpr double kNsPerMs = 1.0e6;

    double nowMs() noexcept
    {
        struct timespec ts
        {
        };
        clock_gettime(CLOCK_MONOTONIC, &ts);
        return (static_cast<double>(ts.tv_sec) * kMsPerSec) +
               (static_cast<double>(ts.tv_nsec) / kNsPerMs);
    }

    double getNominalRate(AudioDeviceID dev) noexcept
    {
        AudioObjectPropertyAddress addr{kAudioDevicePropertyNominalSampleRate,
                                        kAudioObjectPropertyScopeGlobal,
                                        kAudioObjectPropertyElementMain};
        Float64 rate = 0;
        UInt32 size = sizeof(rate);
        if (AudioObjectGetPropertyData(dev, &addr, 0, nullptr, &size, &rate) != noErr)
        {
            return 0.0;
        }
        return rate;
    }

    bool setNominalRate(AudioDeviceID dev, double rateHz) noexcept
    {
        AudioObjectPropertyAddress addr{kAudioDevicePropertyNominalSampleRate,
                                        kAudioObjectPropertyScopeGlobal,
                                        kAudioObjectPropertyElementMain};
        Float64 rateValue = rateHz;
        return AudioObjectSetPropertyData(dev, &addr, 0, nullptr, sizeof(rateValue), &rateValue) ==
               noErr;
    }

    // Try to acquire hog mode (set owner pid to us). Returns true only if we now own it.
    bool acquireHog(AudioDeviceID dev) noexcept
    {
        AudioObjectPropertyAddress addr{kAudioDevicePropertyHogMode, kAudioObjectPropertyScopeGlobal,
                                        kAudioObjectPropertyElementMain};
        pid_t want = getpid();
        if (AudioObjectSetPropertyData(dev, &addr, 0, nullptr, sizeof(want), &want) != noErr)
        {
            return false;
        }
        pid_t owner = -2;
        UInt32 size = sizeof(owner);
        if (AudioObjectGetPropertyData(dev, &addr, 0, nullptr, &size, &owner) != noErr)
        {
            return false;
        }
        return owner == getpid();
    }

    void releaseHog(AudioDeviceID dev) noexcept
    {
        AudioObjectPropertyAddress addr{kAudioDevicePropertyHogMode, kAudioObjectPropertyScopeGlobal,
                                        kAudioObjectPropertyElementMain};
        pid_t owner = -1; // -1 == release
        AudioObjectSetPropertyData(dev, &addr, 0, nullptr, sizeof(owner), &owner);
    }
} // namespace

// ===========================================================================
// HALOutputEngine::Impl
// ===========================================================================

class HALOutputEngine::Impl
{
  public:
    Impl() = default;

    ~Impl()
    {
        teardown(); // idempotent; restores device + releases hog even on an early-return path
    }

    Impl(const Impl&) = delete;
    Impl& operator=(const Impl&) = delete;
    Impl(Impl&&) = delete;
    Impl& operator=(Impl&&) = delete;

    bool configure(const DeviceCapability& cap, const PureModeEvaluation& eval,
                   PureModeSource* source)
    {
        // A reconfigure tears the previous session down first (restores rate / releases hog).
        teardown();

        deviceID_ = cap.id;
        source_.store(source, std::memory_order_release);
        achieved_ = AchievedOutputState{};
        achieved_.decision = eval.decision;

        // Save the original nominal rate up front so teardown can always restore it.
        originalRate_ = getNominalRate(deviceID_);

        // 1) Hog mode (best-effort). Failure -> log + continue shared. Never hard-fail.
        if (eval.requiresHog)
        {
            if (acquireHog(deviceID_))
            {
                weHogged_ = true;
                achieved_.didHog = true;
            }
            else
            {
                fprintf(stderr,
                        "[HALOutputEngine] hog mode denied (device %u); continuing in shared mode\n",
                        deviceID_);
            }
        }

        // 2) Nominal rate change (best-effort). Failure -> log + continue at current rate.
        if (eval.requiresRateChange && eval.targetDeviceRate > 0.0)
        {
            if (setRateAndWait(deviceID_, eval.targetDeviceRate))
            {
                achieved_.rateChanged = true;
            }
            else
            {
                fprintf(stderr,
                        "[HALOutputEngine] rate change to %.1f Hz did not take; continuing at %.1f "
                        "Hz\n",
                        eval.targetDeviceRate, getNominalRate(deviceID_));
            }
        }
        achieved_.achievedRate = getNominalRate(deviceID_);

        // 3) Instantiate the AUHAL unit and bind it to the device.
        if (!createUnitAndBind())
        {
            teardown();
            return false;
        }

        // 4) Choose + apply the stream format (no AU-internal SRC).
        if (!applyStreamFormat(cap, eval))
        {
            teardown();
            return false;
        }

        // 5) Install the RT render callback.
        if (!installRenderCallback())
        {
            teardown();
            return false;
        }

        // 6) Initialize the unit (allocates its render resources).
        if (AudioUnitInitialize(unit_) != noErr)
        {
            fprintf(stderr, "[HALOutputEngine] AudioUnitInitialize failed\n");
            teardown();
            return false;
        }
        initialized_ = true;
        achieved_.configured = true;
        return true;
    }

    bool start()
    {
        if (!initialized_ || unit_ == nullptr)
        {
            return false;
        }
        if (started_)
        {
            return true;
        }
        if (AudioOutputUnitStart(unit_) != noErr)
        {
            fprintf(stderr, "[HALOutputEngine] AudioOutputUnitStart failed\n");
            return false;
        }
        started_ = true;
        achieved_.running = true;
        return true;
    }

    void stop()
    {
        teardown();
    }

    [[nodiscard]] AchievedOutputState achievedState() const
    {
        return achieved_;
    }

  private:
    // ---- format selection ----------------------------------------------------------------

    // Build the integer/float ASBD the AU will render at, from the device physical/virtual format.
    AudioStreamBasicDescription chooseFormat(const DeviceCapability& cap,
                                             const PureModeEvaluation& eval) const
    {
        AudioStreamBasicDescription asbd{};
        asbd.mFormatID = kAudioFormatLinearPCM;
        asbd.mSampleRate = achieved_.achievedRate > 0.0 ? achieved_.achievedRate : eval.targetDeviceRate;
        asbd.mFramesPerPacket = 1;

        const StreamFormatInfo& phys = cap.physicalFormat;
        const StreamFormatInfo& virt = cap.virtualFormat;
        const uint32_t channels = (virt.channels > 0U) ? virt.channels : 2U;
        asbd.mChannelsPerFrame = channels;

        if (eval.decision == PureModeDecision::FullBitPerfect && phys.isPCM && !phys.isFloat)
        {
            // Integer PCM matching the physical (over-the-wire) format. Use a 32-bit container for
            // 24-bit (the universal Mac carrier) and pack 16/32.
            const uint32_t bits = phys.bitsPerChannel;
            asbd.mBitsPerChannel = bits;
            asbd.mFormatFlags = kAudioFormatFlagIsSignedInteger;
            uint32_t bytesPerChannel = 4U;
            if (bits == kBitDepth16)
            {
                bytesPerChannel = 2U;
                asbd.mFormatFlags |= kAudioFormatFlagIsPacked;
            }
            else if (bits == kBitDepth32)
            {
                bytesPerChannel = 4U;
                asbd.mFormatFlags |= kAudioFormatFlagIsPacked;
            }
            else
            {
                // 24-bit-in-32: low-justified, not packed. (See ambiguity note in the report.)
                bytesPerChannel = 4U;
            }
            asbd.mBytesPerFrame = bytesPerChannel * channels;
            asbd.mBytesPerPacket = asbd.mBytesPerFrame;
        }
        else
        {
            // RateMatchedFloat (or any non-integer fallback): canonical float32.
            asbd.mBitsPerChannel = kBitDepth32;
            asbd.mFormatFlags = kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked;
            asbd.mBytesPerFrame = 4U * channels;
            asbd.mBytesPerPacket = asbd.mBytesPerFrame;
        }
        return asbd;
    }

    bool createUnitAndBind()
    {
        AudioComponentDescription desc{};
        desc.componentType = kHalOutputType;
        desc.componentSubType = kHalOutputSubType;
        desc.componentManufacturer = kAudioUnitManufacturer_Apple;

        AudioComponent comp = AudioComponentFindNext(nullptr, &desc);
        if (comp == nullptr)
        {
            fprintf(stderr, "[HALOutputEngine] HAL output component not found\n");
            return false;
        }
        if (AudioComponentInstanceNew(comp, &unit_) != noErr || unit_ == nullptr)
        {
            fprintf(stderr, "[HALOutputEngine] AudioComponentInstanceNew failed\n");
            return false;
        }

        AudioDeviceID dev = deviceID_;
        if (AudioUnitSetProperty(unit_, kAudioOutputUnitProperty_CurrentDevice,
                                 kAudioUnitScope_Global, 0, &dev, sizeof(dev)) != noErr)
        {
            fprintf(stderr, "[HALOutputEngine] set CurrentDevice failed\n");
            return false;
        }
        return true;
    }

    bool applyStreamFormat(const DeviceCapability& cap, const PureModeEvaluation& eval)
    {
        const AudioStreamBasicDescription fmt = chooseFormat(cap, eval);

        // Output scope (device side) and input scope (our supply) get the SAME format, so the AU
        // does no internal sample-rate or format conversion.
        if (AudioUnitSetProperty(unit_, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 0,
                                 &fmt, sizeof(fmt)) != noErr)
        {
            fprintf(stderr, "[HALOutputEngine] set output StreamFormat failed\n");
            return false;
        }
        if (AudioUnitSetProperty(unit_, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 0,
                                 &fmt, sizeof(fmt)) != noErr)
        {
            fprintf(stderr, "[HALOutputEngine] set input StreamFormat failed\n");
            return false;
        }

        // Read back the ACTUAL negotiated input format and cache its decoded flags for the RT path.
        AudioStreamBasicDescription actual{};
        UInt32 size = sizeof(actual);
        if (AudioUnitGetProperty(unit_, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 0,
                                 &actual, &size) != noErr)
        {
            fprintf(stderr, "[HALOutputEngine] read-back StreamFormat failed\n");
            return false;
        }
        cacheRenderFormat(actual);
        return true;
    }

    void cacheRenderFormat(const AudioStreamBasicDescription& asbd) noexcept
    {
        rfChannels_ = asbd.mChannelsPerFrame;
        rfBits_ = asbd.mBitsPerChannel;
        rfIsFloat_ = (asbd.mFormatFlags & kAudioFormatFlagIsFloat) != 0;
        rfIsSignedInt_ = (asbd.mFormatFlags & kAudioFormatFlagIsSignedInteger) != 0;
        rfIsPacked_ = (asbd.mFormatFlags & kAudioFormatFlagIsPacked) != 0;
        rfIsAlignedHigh_ = (asbd.mFormatFlags & kAudioFormatFlagIsAlignedHigh) != 0;
        rfIsBigEndian_ = (asbd.mFormatFlags & kAudioFormatFlagIsBigEndian) != 0;

        achieved_.achievedBitsPerChannel = rfBits_;
        achieved_.achievedIsFloat = rfIsFloat_;

        // Pre-allocate the float scratch buffer OFF the RT thread (configure path). Sized to the
        // host frame ceiling × channel ceiling so pullFloat never needs more room.
        const uint32_t ch = (rfChannels_ > 0U) ? rfChannels_ : 1U;
        scratch_.assign(static_cast<size_t>(kMaxRenderFrames) * ch, 0.0F);
    }

    bool installRenderCallback()
    {
        AURenderCallbackStruct cb{};
        cb.inputProc = &Impl::renderTrampoline;
        cb.inputProcRefCon = this;
        if (AudioUnitSetProperty(unit_, kAudioUnitProperty_SetRenderCallback, kAudioUnitScope_Input,
                                 0, &cb, sizeof(cb)) != noErr)
        {
            fprintf(stderr, "[HALOutputEngine] set render callback failed\n");
            return false;
        }
        return true;
    }

    // ---- RT render path ------------------------------------------------------------------

    // Static trampoline -> instance render. RT thread; no Obj-C, no alloc, no lock, no throw.
    static OSStatus renderTrampoline(void* refCon, AudioUnitRenderActionFlags* /*flags*/,
                                     const AudioTimeStamp* /*ts*/, UInt32 /*busNumber*/,
                                     UInt32 numberFrames, AudioBufferList* ioData) noexcept
    {
        auto* self = static_cast<Impl*>(refCon);
        return self->render(numberFrames, ioData);
    }

    OSStatus render(UInt32 numberFrames, AudioBufferList* ioData) noexcept
    {
        if (ioData == nullptr || ioData->mNumberBuffers == 0U)
        {
            return noErr;
        }

        const uint32_t channels = (rfChannels_ > 0U) ? rfChannels_ : 1U;
        const uint32_t frames = numberFrames;

        // Guard against an unexpectedly large request (scratch is sized to kMaxRenderFrames). If the
        // host ever asks for more, emit silence for this buffer rather than overflow the scratch.
        const size_t needed = static_cast<size_t>(frames) * channels;
        if (needed > scratch_.size())
        {
            zeroFill(ioData);
            return noErr;
        }

        // Pull interleaved float from the source (RT-safe). A short/zero fill is zero-padded.
        PureModeSource* src = source_.load(std::memory_order_acquire);
        uint32_t produced = 0U;
        if (src != nullptr)
        {
            produced = src->pullFloat(scratch_.data(), frames, channels);
        }
        if (produced < frames)
        {
            const size_t startSample = static_cast<size_t>(produced) * channels;
            const size_t tailSamples = (static_cast<size_t>(frames) * channels) - startSample;
            std::memset(scratch_.data() + startSample, 0, tailSamples * sizeof(float));
        }

        // The AUHAL input format is interleaved (one buffer). Convert float -> native into it.
        AudioBuffer& buf = ioData->mBuffers[0];
        if (buf.mData == nullptr)
        {
            return noErr;
        }
        convertFloatToNative(scratch_.data(), buf.mData, frames, channels, rfBits_, rfIsFloat_,
                             rfIsSignedInt_, rfIsPacked_, rfIsAlignedHigh_, rfIsBigEndian_);
        return noErr;
    }

    static void zeroFill(AudioBufferList* ioData) noexcept
    {
        for (UInt32 i = 0U; i < ioData->mNumberBuffers; ++i)
        {
            AudioBuffer& b = ioData->mBuffers[i];
            if (b.mData != nullptr)
            {
                std::memset(b.mData, 0, b.mDataByteSize);
            }
        }
    }

    // ---- rate change with poll (spike pattern) -------------------------------------------

    static bool setRateAndWait(AudioDeviceID dev, double rateHz) noexcept
    {
        if (!setNominalRate(dev, rateHz))
        {
            return false;
        }
        const double deadline = nowMs() + kRateChangeTimeoutMs;
        while (nowMs() < deadline)
        {
            if (std::fabs(getNominalRate(dev) - rateHz) < kRateEpsilonHz)
            {
                return true;
            }
            const struct timespec step
            {
                0, kRatePollStepNs
            };
            nanosleep(&step, nullptr);
        }
        return std::fabs(getNominalRate(dev) - rateHz) < kRateEpsilonHz;
    }

    // ---- teardown (idempotent; restores device + releases hog) ---------------------------

    void teardown() noexcept
    {
        if (unit_ != nullptr)
        {
            if (started_)
            {
                AudioOutputUnitStop(unit_);
                started_ = false;
            }
            if (initialized_)
            {
                AudioUnitUninitialize(unit_);
                initialized_ = false;
            }
            AudioComponentInstanceDispose(unit_);
            unit_ = nullptr;
        }

        if (deviceID_ != kAudioObjectUnknown)
        {
            if (originalRate_ > 0.0)
            {
                if (!setNominalRate(deviceID_, originalRate_))
                {
                    fprintf(stderr, "[HALOutputEngine] WARNING: failed to restore nominal rate %.1f "
                                    "Hz\n",
                            originalRate_);
                }
            }
            if (weHogged_)
            {
                releaseHog(deviceID_);
                weHogged_ = false;
            }
        }

        // Make teardown a true no-op on repeat: a second call (dtor after stop()) must not re-touch
        // the device. configure() repopulates these before any further mutation.
        deviceID_ = kAudioObjectUnknown;
        originalRate_ = 0.0;

        achieved_.running = false;
        achieved_.didHog = false;
        source_.store(nullptr, std::memory_order_release);
    }

    // ---- state ---------------------------------------------------------------------------

    AudioUnit unit_ = nullptr;
    AudioDeviceID deviceID_ = kAudioObjectUnknown;
    double originalRate_ = 0.0;
    bool weHogged_ = false;
    bool initialized_ = false;
    bool started_ = false;

    AchievedOutputState achieved_;

    // RT render format (decoded ASBD flags), read on the audio thread.
    std::atomic<PureModeSource*> source_{nullptr};
    uint32_t rfChannels_ = 0U;
    uint32_t rfBits_ = 0U;
    bool rfIsFloat_ = false;
    bool rfIsSignedInt_ = false;
    bool rfIsPacked_ = false;
    bool rfIsAlignedHigh_ = false;
    bool rfIsBigEndian_ = false;

    // Pre-allocated interleaved-float scratch (sized in configure(); never resized on the RT path).
    std::vector<float> scratch_;
};

// ===========================================================================
// HALOutputEngine (public shell -> Impl)
// ===========================================================================

HALOutputEngine::HALOutputEngine() : impl_(std::make_unique<Impl>()) {}
HALOutputEngine::~HALOutputEngine() = default;

bool HALOutputEngine::configure(const DeviceCapability& cap, const PureModeEvaluation& eval,
                                PureModeSource* source)
{
    return impl_->configure(cap, eval, source);
}

bool HALOutputEngine::start()
{
    return impl_->start();
}

void HALOutputEngine::stop()
{
    impl_->stop();
}

AchievedOutputState HALOutputEngine::achievedState() const
{
    return impl_->achievedState();
}

// NOLINTEND(cppcoreguidelines-pro-type-vararg)
