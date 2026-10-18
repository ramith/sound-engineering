//
// HALOutputEngine.mm — bit-perfect HAL output engine (Pure Mode, Phase B — B2a).
//
// Obj-C++. Drives one output device via a kAudioUnitSubType_HALOutput AudioUnit. The CoreAudio
// query / mutate patterns (first output stream, hog acquire/release, nominal-rate set + poll,
// RAII restore) are lifted from scripts/hal-spike.mm; the render-callback float->native conversion
// is convertFloatToNative() into the NativePcmFormat the AU negotiated (PureModeFormat.h).
//
// SAFETY: device mutation (hog, nominal rate) happens only in configure()/stop() on the control
// thread. The original nominal rate is saved up front and ALWAYS restored on teardown; hog is
// released only if we acquired it. Teardown is idempotent and runs from the destructor, so an
// early return still restores the device.
//

#import <AudioToolbox/AudioToolbox.h>
#import <CoreAudio/CoreAudio.h>
#import <Foundation/Foundation.h>

#include "../include/AsLog.h"
#include "../include/HALOutputEngine.h"
#include "../include/PureModeFormat.h"
#include "../include/PureModeSource.h"
#include "../include/RenderGate.h"

#include <array>
#include <atomic>
#include <chrono>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <cstring>
#include <ctime>
#include <format>
#include <optional>
#include <span>
#include <unistd.h> // getpid
#include <vector>

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

    constexpr double kMsPerSec = 1000.0;
    constexpr double kNsPerMs = 1.0e6;

    // Upper bound on the number of available physical formats we will enumerate. HDMI / USB DACs
    // advertise on the order of a dozen; 256 is comfortably above any real device.
    constexpr uint32_t kMaxPhysicalFormats = 256U;

    // FourCC rendering: 4 ASCII chars + quotes + NUL fit comfortably in 16 bytes.
    constexpr size_t kFourCCBufferBytes = 16U;
    using FourCCBuffer = std::array<char, kFourCCBufferBytes>;

    // Printable-ASCII bounds for deciding whether a FourCC's bytes render as characters.
    constexpr unsigned char kAsciiSpace = 0x20U; // first printable ASCII
    constexpr unsigned char kAsciiTilde = 0x7EU; // last printable ASCII

    // Byte/word extraction constants for the FourCC decode.
    constexpr uint32_t kByteMask = 0xFFU;
    constexpr uint32_t kShiftByte0 = 0U;
    constexpr uint32_t kShiftByte1 = 8U;
    constexpr uint32_t kShiftByte2 = 16U;
    constexpr uint32_t kShiftByte3 = 24U;

    // Render a CoreAudio FourCC (OSStatus / OSType) into a printable 4-char string for logging.
    // Many CoreAudio codes are packed ASCII (e.g. 'nope', '!dat'); fall back to decimal otherwise.
    // (Ported from scripts/hal-spike.mm.) The caller owns the buffer.
    const char* fourcc(OSStatus code, FourCCBuffer& buf) noexcept
    {
        const auto value = static_cast<uint32_t>(code);
        const std::array<unsigned char, 4> bytes{
            static_cast<unsigned char>((value >> kShiftByte3) & kByteMask),
            static_cast<unsigned char>((value >> kShiftByte2) & kByteMask),
            static_cast<unsigned char>((value >> kShiftByte1) & kByteMask),
            static_cast<unsigned char>((value >> kShiftByte0) & kByteMask),
        };
        bool printable = true;
        for (const unsigned char byte : bytes)
        {
            if (byte < kAsciiSpace || byte > kAsciiTilde)
            {
                printable = false;
                break;
            }
        }
        if (printable)
        {
            const auto res =
                std::format_to_n(buf.data(), buf.size() - 1U, "'{}{}{}{}'",
                                 static_cast<char>(bytes[0]), static_cast<char>(bytes[1]),
                                 static_cast<char>(bytes[2]), static_cast<char>(bytes[3]));
            *res.out = '\0';
        }
        else
        {
            const auto res =
                std::format_to_n(buf.data(), buf.size() - 1U, "{}", static_cast<int>(code));
            *res.out = '\0';
        }
        return buf.data();
    }

    // Human label for an ASBD's sample type (flattened to avoid a nested ternary at the call site).
    const char* sampleTypeLabel(bool isPCM, bool isFloat) noexcept
    {
        if (!isPCM)
        {
            return "non-PCM";
        }
        return isFloat ? "float" : "int";
    }

    // Log the audio-relevant fields of an ASBD with format flags decoded into human terms. This is
    // the core diagnostic for the founder's HDMI run: it makes a format mismatch self-evident.
    void logASBD(const char* label, const AudioStreamBasicDescription& asbd) noexcept
    {
        const bool isPCM = (asbd.mFormatID == kAudioFormatLinearPCM);
        const bool isFloat = (asbd.mFormatFlags & kAudioFormatFlagIsFloat) != 0U;
        const bool isSignedInt = (asbd.mFormatFlags & kAudioFormatFlagIsSignedInteger) != 0U;
        const bool isPacked = (asbd.mFormatFlags & kAudioFormatFlagIsPacked) != 0U;
        const bool isAlignedHigh = (asbd.mFormatFlags & kAudioFormatFlagIsAlignedHigh) != 0U;
        const bool isBigEndian = (asbd.mFormatFlags & kAudioFormatFlagIsBigEndian) != 0U;
        FourCCBuffer fid{};
        AdaptiveSound::log::line(
            "[HALOutputEngine]   {}: id={} rate={:.1f} ch={} bits={} bytes/frame={} "
            "type={}{} packed={} alignedHigh={} endian={}",
            label, fourcc(static_cast<OSStatus>(asbd.mFormatID), fid), asbd.mSampleRate,
            asbd.mChannelsPerFrame, asbd.mBitsPerChannel, asbd.mBytesPerFrame,
            sampleTypeLabel(isPCM, isFloat), (isPCM && !isFloat && isSignedInt) ? " signed" : "",
            isPacked ? "yes" : "no", isAlignedHigh ? "yes" : "no", isBigEndian ? "big" : "little");
    }

    // First OUTPUT-scope stream of a device, used for physical/virtual format queries. Returns
    // kAudioObjectUnknown when the device has no output stream. (Mirrors the spike's helper.)
    AudioObjectID firstOutputStream(AudioDeviceID dev) noexcept
    {
        AudioObjectPropertyAddress addr{
            kAudioDevicePropertyStreams,
            kAudioObjectPropertyScopeOutput,
            kAudioObjectPropertyElementMain,
        };
        UInt32 size = 0;
        if (AudioObjectGetPropertyDataSize(dev, &addr, 0, nullptr, &size) != noErr || size == 0U)
        {
            return kAudioObjectUnknown;
        }
        const UInt32 count = size / sizeof(AudioObjectID);
        if (count == 0U)
        {
            return kAudioObjectUnknown;
        }
        std::vector<AudioObjectID> streams(count);
        if (AudioObjectGetPropertyData(dev, &addr, 0, nullptr, &size, streams.data()) != noErr)
        {
            return kAudioObjectUnknown;
        }
        return streams[0];
    }

    // Read the current physical format of an output stream. Returns false (and leaves out
    // untouched) on failure.
    bool getStreamPhysicalFormat(AudioObjectID stream, AudioStreamBasicDescription& out) noexcept
    {
        AudioObjectPropertyAddress addr{
            kAudioStreamPropertyPhysicalFormat,
            kAudioObjectPropertyScopeGlobal,
            kAudioObjectPropertyElementMain,
        };
        UInt32 size = sizeof(out);
        return AudioObjectGetPropertyData(stream, &addr, 0, nullptr, &size, &out) == noErr;
    }

    // Read the current virtual format of an output stream. Returns false on failure.
    bool getStreamVirtualFormat(AudioObjectID stream, AudioStreamBasicDescription& out) noexcept
    {
        AudioObjectPropertyAddress addr{
            kAudioStreamPropertyVirtualFormat,
            kAudioObjectPropertyScopeGlobal,
            kAudioObjectPropertyElementMain,
        };
        UInt32 size = sizeof(out);
        return AudioObjectGetPropertyData(stream, &addr, 0, nullptr, &size, &out) == noErr;
    }

    // Enumerate the available physical formats advertised by an output stream. Appends to out
    // (cleared first). Returns false on a CoreAudio failure (out is then empty).
    bool getAvailablePhysicalFormats(AudioObjectID stream,
                                     std::vector<AudioStreamBasicDescription>& out) noexcept
    {
        out.clear();
        AudioObjectPropertyAddress addr{
            kAudioStreamPropertyAvailablePhysicalFormats,
            kAudioObjectPropertyScopeGlobal,
            kAudioObjectPropertyElementMain,
        };
        UInt32 size = 0;
        if (AudioObjectGetPropertyDataSize(stream, &addr, 0, nullptr, &size) != noErr || size == 0U)
        {
            return false;
        }
        UInt32 count = size / static_cast<UInt32>(sizeof(AudioStreamRangedDescription));
        if (count == 0U)
        {
            return false;
        }
        if (count > kMaxPhysicalFormats)
        {
            count = kMaxPhysicalFormats;
            size = count * static_cast<UInt32>(sizeof(AudioStreamRangedDescription));
        }
        std::vector<AudioStreamRangedDescription> ranged(count);
        if (AudioObjectGetPropertyData(stream, &addr, 0, nullptr, &size, ranged.data()) != noErr)
        {
            return false;
        }
        const UInt32 got = size / static_cast<UInt32>(sizeof(AudioStreamRangedDescription));
        out.reserve(got);
        for (UInt32 idx = 0U; idx < got; ++idx)
        {
            out.push_back(ranged[idx].mFormat);
        }
        return !out.empty();
    }

    // Set an output stream's physical format. Returns true on success.
    bool setStreamPhysicalFormat(AudioObjectID stream,
                                 const AudioStreamBasicDescription& fmt) noexcept
    {
        AudioObjectPropertyAddress addr{
            kAudioStreamPropertyPhysicalFormat,
            kAudioObjectPropertyScopeGlobal,
            kAudioObjectPropertyElementMain,
        };
        return AudioObjectSetPropertyData(stream, &addr, 0, nullptr, sizeof(fmt), &fmt) == noErr;
    }

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
        AudioObjectPropertyAddress addr{
            kAudioDevicePropertyNominalSampleRate,
            kAudioObjectPropertyScopeGlobal,
            kAudioObjectPropertyElementMain,
        };
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
        AudioObjectPropertyAddress addr{
            kAudioDevicePropertyNominalSampleRate,
            kAudioObjectPropertyScopeGlobal,
            kAudioObjectPropertyElementMain,
        };
        Float64 rateValue = rateHz;
        return AudioObjectSetPropertyData(dev, &addr, 0, nullptr, sizeof(rateValue), &rateValue) ==
               noErr;
    }

    // Try to acquire hog mode (set owner pid to us). Returns true only if we now own it.
    bool acquireHog(AudioDeviceID dev) noexcept
    {
        AudioObjectPropertyAddress addr{
            kAudioDevicePropertyHogMode,
            kAudioObjectPropertyScopeGlobal,
            kAudioObjectPropertyElementMain,
        };
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
        AudioObjectPropertyAddress addr{
            kAudioDevicePropertyHogMode,
            kAudioObjectPropertyScopeGlobal,
            kAudioObjectPropertyElementMain,
        };
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
        declineReason_ = PureModeReason::DeviceWouldNotStart; // until a gate below names its own

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
                AdaptiveSound::log::line(
                    "[HALOutputEngine] hog mode denied (device {}); continuing in shared mode",
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
                AdaptiveSound::log::line("[HALOutputEngine] rate change to {:.1f} Hz did not take; "
                                         "continuing at {:.1f} Hz",
                                         eval.targetDeviceRate, getNominalRate(deviceID_));
            }
        }
        achieved_.achievedRate = getNominalRate(deviceID_);

        // 2b) Rate-match gate. Pure performs NO sample-rate conversion, so the device MUST actually
        // be running at the file's rate. If a required rate change did not take — most importantly
        // macOS LOCKS HDMI output to 48 kHz, so a 44.1 kHz file can never rate-match over HDMI —
        // decline Pure here and let the bridge fall back to the Enhanced path, which resamples
        // correctly (AVAudioConverter .max). Proceeding would render the file's samples at the wrong
        // device rate (wrong-speed playback). A file already at the device rate (no change required,
        // or the change succeeded) passes this gate; e.g. a 48 kHz file over HDMI still goes Pure.
        if (eval.requiresRateChange && eval.targetDeviceRate > 0.0)
        {
            const double rateDelta = achieved_.achievedRate - eval.targetDeviceRate;
            if (rateDelta > kRateEpsilonHz || rateDelta < -kRateEpsilonHz)
            {
                AdaptiveSound::log::line(
                    "[HALOutputEngine] device rate {:.1f} Hz != file rate {:.1f} Hz — rate-match "
                    "not achievable (e.g. HDMI 48 kHz lock); declining Pure so Enhanced resamples",
                    achieved_.achievedRate, eval.targetDeviceRate);
                teardown();
                declineReason_ = PureModeReason::RateUnsupportedResample;
                return false;
            }
        }

        // 3) Instantiate the AUHAL unit and bind it to the device.
        if (!createUnitAndBind())
        {
            teardown();
            return false;
        }

        // 4) Choose + apply the stream format (no AU-internal SRC). It fails when the AU's format
        // is not one the converter writes exactly (NativePcmFormat::fromAsbd) — Pure declines.
        if (!applyStreamFormat(eval))
        {
            teardown();
            return false;
        }

        // 4b) Channel-match gate. Pure maps no channels (evaluatePureMode), so the stream the AU
        // negotiated must carry exactly the file's channels: a mismatch would pull nothing and play
        // silence that never ends. The policy compared the device's first stream; this checks what
        // the render will really pull (e.g. a multi-stream device's AU spans every stream). Decline
        // so the bridge falls back to Enhanced, which maps any width.
        if (renderFormat_.channels != eval.targetChannels)
        {
            AdaptiveSound::log::line(
                "[HALOutputEngine] device stream carries {} channels, the file {} — Pure maps no "
                "channels; declining Pure so Enhanced plays it",
                renderFormat_.channels, eval.targetChannels);
            teardown();
            declineReason_ = PureModeReason::ChannelCountMismatch;
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
            AdaptiveSound::log::line("[HALOutputEngine] AudioUnitInitialize failed");
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
        gate_.open(); // a teardown closed it; a fresh session pulls again
        if (AudioOutputUnitStart(unit_) != noErr)
        {
            AdaptiveSound::log::line("[HALOutputEngine] AudioOutputUnitStart failed");
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

    bool holdRender()
    {
        if (!gate_.close(kHoldRenderTimeout))
        {
            AdaptiveSound::log::line("[HALOutputEngine] a render pass did not finish within {} ms",
                                     kHoldRenderTimeout.count());
            return false;
        }
        return true;
    }

    void releaseRender()
    {
        gate_.open();
    }

    [[nodiscard]] AchievedOutputState achievedState() const
    {
        return achieved_;
    }

    [[nodiscard]] PureModeReason configureDeclineReason() const
    {
        return declineReason_;
    }

    void setDither(bool reducesBits)
    {
        dithers_.store(reducesBits, std::memory_order_release);
    }

  private:
    // ---- format selection ----------------------------------------------------------------

    bool createUnitAndBind()
    {
        AudioComponentDescription desc{};
        desc.componentType = kHalOutputType;
        desc.componentSubType = kHalOutputSubType;
        desc.componentManufacturer = kAudioUnitManufacturer_Apple;

        AudioComponent comp = AudioComponentFindNext(nullptr, &desc);
        if (comp == nullptr)
        {
            AdaptiveSound::log::line("[HALOutputEngine] HAL output component not found");
            return false;
        }
        if (AudioComponentInstanceNew(comp, &unit_) != noErr || unit_ == nullptr)
        {
            AdaptiveSound::log::line("[HALOutputEngine] AudioComponentInstanceNew failed");
            return false;
        }

        AudioDeviceID dev = deviceID_;
        if (AudioUnitSetProperty(unit_, kAudioOutputUnitProperty_CurrentDevice,
                                 kAudioUnitScope_Global, 0, &dev, sizeof(dev)) != noErr)
        {
            AdaptiveSound::log::line("[HALOutputEngine] set CurrentDevice failed");
            return false;
        }
        return true;
    }

    // Top-level format negotiation. Two paths:
    //   FullBitPerfect (integer DAC, hog held): set the DEVICE's physical stream format to an
    //     advertised integer format, then match the AU input scope to the AU output scope the new
    //     physical format produced. This is the real bit-perfect route the spike proved.
    //   RateMatchedFloat (built-in / Bluetooth, shared): leave the physical format alone and use
    //     the AU's native (float) output format verbatim on both scopes. This path already works.
    bool applyStreamFormat(const PureModeEvaluation& eval)
    {
        if (eval.decision == PureModeDecision::FullBitPerfect)
        {
            return applyBitPerfectFormat(eval);
        }
        return applyFloatFormat();
    }

    // FullBitPerfect: enumerate -> choose -> set device physical format -> match AU input to the AU
    // output scope. Falls back to the device's current format (never silence) if no integer match.
    bool applyBitPerfectFormat(const PureModeEvaluation& eval)
    {
        const double targetRate =
            (achieved_.achievedRate > 0.0) ? achieved_.achievedRate : eval.targetDeviceRate;
        const uint32_t channels = eval.targetChannels;

        AudioObjectID stream = firstOutputStream(deviceID_);
        if (stream == kAudioObjectUnknown)
        {
            AdaptiveSound::log::line("[HALOutputEngine] FullBitPerfect: no output stream on device "
                                     "{}; falling back to the AU native (float) format",
                                     deviceID_);
            return applyFloatFormat();
        }

        // Diagnostics: current physical + virtual format, then every advertised physical format.
        AudioStreamBasicDescription currentPhys{};
        const bool haveCurrent = getStreamPhysicalFormat(stream, currentPhys);
        AudioStreamBasicDescription currentVirt{};
        const bool haveVirt = getStreamVirtualFormat(stream, currentVirt);
        AdaptiveSound::log::line(
            "[HALOutputEngine] FullBitPerfect on device {}, stream {}: targetRate={:.1f} Hz, "
            "channels={}",
            deviceID_, stream, targetRate, channels);
        if (haveCurrent)
        {
            logASBD("CURRENT physical", currentPhys);
        }
        if (haveVirt)
        {
            logASBD("CURRENT virtual ", currentVirt);
        }

        std::vector<AudioStreamBasicDescription> available;
        const bool haveList = getAvailablePhysicalFormats(stream, available);
        if (haveList)
        {
            AdaptiveSound::log::line("[HALOutputEngine]   available physical formats ({}):",
                                     available.size());
            for (const AudioStreamBasicDescription& fmt : available)
            {
                logASBD("  avail", fmt);
            }
        }
        else
        {
            AdaptiveSound::log::line(
                "[HALOutputEngine]   (could not enumerate available physical formats)");
        }

        // Choose the best integer physical format at the target rate that the converter writes
        // exactly (a packed-24 or 24-in-32 word, never a layout it would have to guess at).
        const std::optional<AudioStreamBasicDescription> picked =
            haveList ? pickIntegerPhysicalFormat(available, currentPhys, targetRate, channels)
                     : std::nullopt;
        if (!picked.has_value())
        {
            AdaptiveSound::log::line(
                "[HALOutputEngine]   no writable integer physical format matched (rate={:.1f} Hz, "
                "ch={}); graceful fallback to the AU native (float) format — device will still "
                "play, but NOT bit-perfect",
                targetRate, channels);
            return applyFloatFormat();
        }
        const AudioStreamBasicDescription chosen = *picked;
        logASBD("CHOSEN  physical", chosen);

        // Set the device's physical stream format (hog is held -> permitted).
        if (!setStreamPhysicalFormat(stream, chosen))
        {
            AdaptiveSound::log::line("[HALOutputEngine]   set physical format FAILED; graceful "
                                     "fallback to the AU native (float) format");
            return applyFloatFormat();
        }
        AdaptiveSound::log::line("[HALOutputEngine]   set physical format OK");

        // The AU's output-scope format now reflects the new physical format. Query it (do NOT set
        // it), then match the AU input scope to it exactly so the AU does zero internal conversion.
        AudioStreamBasicDescription auOut{};
        UInt32 size = sizeof(auOut);
        if (AudioUnitGetProperty(unit_, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 0,
                                 &auOut, &size) != noErr)
        {
            AdaptiveSound::log::line(
                "[HALOutputEngine]   query AU output StreamFormat FAILED after physical set");
            return false;
        }
        logASBD("AU output (post-set)", auOut);

        if (AudioUnitSetProperty(unit_, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 0,
                                 &auOut, sizeof(auOut)) != noErr)
        {
            AdaptiveSound::log::line(
                "[HALOutputEngine]   set AU input StreamFormat (= AU output) FAILED");
            return false;
        }
        AdaptiveSound::log::line(
            "[HALOutputEngine]   set AU input StreamFormat OK (matches output)");

        // Read back the ACTUAL negotiated input format and cache its decoded flags for the RT path.
        AudioStreamBasicDescription actual{};
        size = sizeof(actual);
        if (AudioUnitGetProperty(unit_, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 0,
                                 &actual, &size) != noErr)
        {
            AdaptiveSound::log::line("[HALOutputEngine]   read-back AU input StreamFormat FAILED");
            return false;
        }
        logASBD("AU input (cached)", actual);
        return adoptRenderFormat(actual);
    }

    // RateMatchedFloat (and the graceful fallback): use the AU's native output-scope format on both
    // scopes. No device physical-format mutation — the device keeps its current (float) format and
    // still plays. This is the proven-working path; do not regress it.
    bool applyFloatFormat()
    {
        // Query the AU's native output-scope format (reflects the device's current format).
        AudioStreamBasicDescription fmt{};
        UInt32 size = sizeof(fmt);
        if (AudioUnitGetProperty(unit_, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 0,
                                 &fmt, &size) != noErr)
        {
            AdaptiveSound::log::line("[HALOutputEngine] query AU native output StreamFormat failed");
            return false;
        }
        logASBD("AU native output", fmt);

        // Supply that same format on the input scope -> zero AU-internal conversion.
        if (AudioUnitSetProperty(unit_, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 0,
                                 &fmt, sizeof(fmt)) != noErr)
        {
            AdaptiveSound::log::line("[HALOutputEngine] set AU input StreamFormat (= native) failed");
            return false;
        }

        // Read back the ACTUAL negotiated input format and cache its decoded flags for the RT path.
        AudioStreamBasicDescription actual{};
        size = sizeof(actual);
        if (AudioUnitGetProperty(unit_, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 0,
                                 &actual, &size) != noErr)
        {
            AdaptiveSound::log::line("[HALOutputEngine] read-back AU input StreamFormat failed");
            return false;
        }
        logASBD("AU input (cached)", actual);
        return adoptRenderFormat(actual);
    }

    // Adopt the AU's negotiated input format as the RT render format — only when the converter
    // writes it exactly (interleaved, a known layout, a frame stride its bit depth explains).
    // Anything else declines Pure rather than render a guess. Configure path, render stopped.
    bool adoptRenderFormat(const AudioStreamBasicDescription& asbd)
    {
        const std::optional<NativePcmFormat> format = NativePcmFormat::fromAsbd(asbd);
        if (!format.has_value())
        {
            AdaptiveSound::log::line("[HALOutputEngine] the AU's format is not one Pure writes "
                                     "exactly; declining Pure");
            return false;
        }
        renderFormat_ = *format;

        achieved_.achievedBitsPerChannel = renderFormat_.validBits();
        achieved_.achievedIsFloat = renderFormat_.isFloat();

        // Pre-allocate the float scratch buffer OFF the RT thread (configure path). Sized to the
        // host frame ceiling × the stream's channels so pullFloat never needs more room.
        scratch_.assign(static_cast<size_t>(kMaxRenderFrames) * renderFormat_.channels, 0.0F);
        return true;
    }

    bool installRenderCallback()
    {
        AURenderCallbackStruct cb{};
        cb.inputProc = &Impl::renderTrampoline;
        cb.inputProcRefCon = this;
        if (AudioUnitSetProperty(unit_, kAudioUnitProperty_SetRenderCallback, kAudioUnitScope_Input,
                                 0, &cb, sizeof(cb)) != noErr)
        {
            AdaptiveSound::log::line("[HALOutputEngine] set render callback failed");
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

        const uint32_t channels = renderFormat_.channels; // >= 1: fromAsbd admits no 0-wide format
        const uint32_t frames = numberFrames;

        // Guard against an unexpectedly large request (scratch is sized to kMaxRenderFrames). If the
        // host ever asks for more, emit silence for this buffer rather than overflow the scratch.
        const size_t needed = static_cast<size_t>(frames) * channels;
        if (needed > scratch_.size())
        {
            zeroFill(ioData);
            return noErr;
        }

        // Pull interleaved float from the source (RT-safe), only inside the render gate: while the
        // control plane holds it (a seek moving the decoder, a teardown) render silence and leave
        // the source alone. A short/zero fill is zero-padded.
        if (!gate_.tryEnter())
        {
            zeroFill(ioData);
            return noErr;
        }
        PureModeSource* src = source_.load(std::memory_order_acquire);
        uint32_t produced = 0U;
        if (src != nullptr)
        {
            produced = src->pullFloat(scratch_.data(), frames, channels);
        }
        gate_.leave();
        if (produced < frames)
        {
            const size_t startSample = static_cast<size_t>(produced) * channels;
            const size_t tailSamples = (static_cast<size_t>(frames) * channels) - startSample;
            std::memset(scratch_.data() + startSample, 0, tailSamples * sizeof(float));
        }

        // The render format is interleaved (fromAsbd admits nothing else): one buffer. Convert
        // float -> native into it. The write is bounded by the buffer's OWN byte size and the
        // format's real frame stride (mBytesPerFrame: 3 bytes a sample packed, 4 in a 32-bit
        // word), never by a size implied by the bit depth; whatever is left is written silent.
        AudioBuffer& buf = ioData->mBuffers[0];
        if (buf.mData == nullptr)
        {
            return noErr;
        }
        // Where the device's word holds fewer bits than the source, the step adds TPDF dither (no
        // allocation, no lock: the generator is this engine's own state, touched only here);
        // otherwise it is the bit-exact plain conversion.
        const std::span<const float> samples(scratch_.data(), needed);
        const std::span<std::byte> bytes(static_cast<std::byte*>(buf.mData), buf.mDataByteSize);
        if (dithers_.load(std::memory_order_acquire))
        {
            convertFloatToNativeDithered(samples, bytes, renderFormat_, dither_);
        }
        else
        {
            convertFloatToNative(samples, bytes, renderFormat_);
        }
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
            const struct timespec step{.tv_sec = 0, .tv_nsec = kRatePollStepNs};
            nanosleep(&step, nullptr);
        }
        return std::fabs(getNominalRate(dev) - rateHz) < kRateEpsilonHz;
    }

    // ---- teardown (idempotent; restores device + releases hog) ---------------------------

    void teardown() noexcept
    {
        // The barrier for the source is the render gate, not the unit stop: closed to new passes
        // at once, and NEVER reopened here — a reopen would let a fresh pass start against a source
        // its owner is about to free (start() opens it for the next session). Then wait for the
        // one pass that may already be inside.
        const bool quiet = !gate_.requestClose() || gate_.awaitQuiet(kHoldRenderTimeout);
        if (!quiet)
        {
            AdaptiveSound::log::line(
                "[HALOutputEngine] teardown: a render pass is still inside after {} ms",
                kHoldRenderTimeout.count());
        }
        if (unit_ != nullptr)
        {
            if (started_)
            {
                const OSStatus stopped = AudioOutputUnitStop(unit_);
                if (stopped != noErr)
                {
                    AdaptiveSound::log::line(
                        "[HALOutputEngine] AudioOutputUnitStop failed ({}); disposing the unit",
                        static_cast<int>(stopped));
                }
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
            if (originalRate_ > 0.0 && !setNominalRate(deviceID_, originalRate_))
            {
                AdaptiveSound::log::line(
                    "[HALOutputEngine] WARNING: failed to restore nominal rate {:.1f} Hz",
                    originalRate_);
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

        // With the unit stopped and disposed, a pass still inside the gate is one the IO thread
        // never finished (a stopped process, a page fault mid-pull — not an RT render's normal
        // life). It holds pointers into this engine and the source: the owner must not free them
        // (renderMayStillRun(); the Pure session parks both).
        renderMayStillRun_ = !gate_.awaitQuiet(std::chrono::microseconds{0});
        if (renderMayStillRun_)
        {
            AdaptiveSound::log::line(
                "[HALOutputEngine] teardown: a render pass outlived the unit; its memory must stay");
        }
    }

  public:
    // Set by teardown() just above, read by the public shell (HALOutputEngine::renderMayStillRun).
    [[nodiscard]] bool renderMayStillRun() const noexcept
    {
        return renderMayStillRun_;
    }

  private:
    // ---- state ---------------------------------------------------------------------------

    AudioUnit unit_ = nullptr;
    AudioDeviceID deviceID_ = kAudioObjectUnknown;
    double originalRate_ = 0.0;
    bool weHogged_ = false;
    bool initialized_ = false;
    bool started_ = false;

    AchievedOutputState achieved_;

    // RT render format, read on the audio thread.
    //
    // Sole-accessor invariant: renderFormat_ (a non-atomic multi-word POD) is written ONLY by
    // adoptRenderFormat() on the configure/format path (while the engine is stopped, no render
    // callback installed/running) and read ONLY by render() on the RT thread. It is frozen for the
    // entire lifetime of a started session — start()/stop() bracket every mutation, so there is no
    // concurrent reader during a write and no torn read on the RT thread. If the format ever needed
    // to change mid-session it would have to be published atomically (e.g. behind
    // TripleBufferSnapshot<T>); today that path does not exist.
    std::atomic<PureModeSource*> source_{nullptr};
    // Render ⇄ control-plane handshake around every source access (RenderGate.h).
    RenderGate gate_;
    // How long holdRender() / teardown wait for a render pass already inside the gate.
    static constexpr std::chrono::milliseconds kHoldRenderTimeout{100};
    // The last teardown could not see the render go quiet (control plane only; see teardown()).
    bool renderMayStillRun_ = false;
    NativePcmFormat renderFormat_;

    // Why the last configure() declined (configureDeclineReason); reset at each configure().
    PureModeReason declineReason_ = PureModeReason::DeviceWouldNotStart;

    // TPDF dither where the device's word holds fewer bits than the source (setDither, before start).
    // The flag is read by the render; the generator is the render thread's alone.
    std::atomic<bool> dithers_{false};
    TpdfDither dither_;

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

bool HALOutputEngine::holdRender()
{
    return impl_->holdRender();
}

void HALOutputEngine::releaseRender()
{
    impl_->releaseRender();
}

bool HALOutputEngine::renderMayStillRun() const
{
    return impl_->renderMayStillRun();
}

AchievedOutputState HALOutputEngine::achievedState() const
{
    return impl_->achievedState();
}

PureModeReason HALOutputEngine::configureDeclineReason() const
{
    return impl_->configureDeclineReason();
}

void HALOutputEngine::setDither(bool reducesBits)
{
    impl_->setDither(reducesBits);
}
