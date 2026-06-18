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

#include <array>
#include <atomic>
#include <cmath>
#include <cstdint>
#include <cstdio>
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

    constexpr double kMsPerSec = 1000.0;
    constexpr double kNsPerMs = 1.0e6;

    // Rate match tolerance when comparing a candidate physical format's sample rate to the target.
    constexpr double kFormatRateEpsilonHz = 1.0;

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
            // NOLINTNEXTLINE(cppcoreguidelines-pro-type-vararg) — control-plane logging helper.
            std::snprintf(buf.data(), buf.size(), "'%c%c%c%c'", bytes[0], bytes[1], bytes[2],
                          bytes[3]);
        }
        else
        {
            // NOLINTNEXTLINE(cppcoreguidelines-pro-type-vararg) — control-plane logging helper.
            std::snprintf(buf.data(), buf.size(), "%d", static_cast<int>(code));
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
        fprintf(stderr,
                "[HALOutputEngine]   %s: id=%s rate=%.1f ch=%u bits=%u bytes/frame=%u "
                "type=%s%s packed=%s alignedHigh=%s endian=%s\n",
                label, fourcc(static_cast<OSStatus>(asbd.mFormatID), fid), asbd.mSampleRate,
                asbd.mChannelsPerFrame, asbd.mBitsPerChannel, asbd.mBytesPerFrame,
                sampleTypeLabel(isPCM, isFloat), (isPCM && !isFloat && isSignedInt) ? " signed" : "",
                isPacked ? "yes" : "no", isAlignedHigh ? "yes" : "no", isBigEndian ? "big" : "little");
    }

    // First OUTPUT-scope stream of a device, used for physical/virtual format queries. Returns
    // kAudioObjectUnknown when the device has no output stream. (Mirrors the spike's helper.)
    AudioObjectID firstOutputStream(AudioDeviceID dev) noexcept
    {
        AudioObjectPropertyAddress addr{kAudioDevicePropertyStreams,
                                        kAudioObjectPropertyScopeOutput,
                                        kAudioObjectPropertyElementMain};
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
        AudioObjectPropertyAddress addr{kAudioStreamPropertyPhysicalFormat,
                                        kAudioObjectPropertyScopeGlobal,
                                        kAudioObjectPropertyElementMain};
        UInt32 size = sizeof(out);
        return AudioObjectGetPropertyData(stream, &addr, 0, nullptr, &size, &out) == noErr;
    }

    // Read the current virtual format of an output stream. Returns false on failure.
    bool getStreamVirtualFormat(AudioObjectID stream, AudioStreamBasicDescription& out) noexcept
    {
        AudioObjectPropertyAddress addr{kAudioStreamPropertyVirtualFormat,
                                        kAudioObjectPropertyScopeGlobal,
                                        kAudioObjectPropertyElementMain};
        UInt32 size = sizeof(out);
        return AudioObjectGetPropertyData(stream, &addr, 0, nullptr, &size, &out) == noErr;
    }

    // Enumerate the available physical formats advertised by an output stream. Appends to out
    // (cleared first). Returns false on a CoreAudio failure (out is then empty).
    bool getAvailablePhysicalFormats(AudioObjectID stream,
                                     std::vector<AudioStreamBasicDescription>& out) noexcept
    {
        out.clear();
        AudioObjectPropertyAddress addr{kAudioStreamPropertyAvailablePhysicalFormats,
                                        kAudioObjectPropertyScopeGlobal,
                                        kAudioObjectPropertyElementMain};
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
        AudioObjectPropertyAddress addr{kAudioStreamPropertyPhysicalFormat,
                                        kAudioObjectPropertyScopeGlobal,
                                        kAudioObjectPropertyElementMain};
        return AudioObjectSetPropertyData(stream, &addr, 0, nullptr, sizeof(fmt), &fmt) == noErr;
    }

    // Predicate: integer (non-float) linear-PCM ASBD at the target rate with the target channel
    // count. The integer (bit-perfect) physical-format candidates we are willing to select.
    bool isIntegerMatch(const AudioStreamBasicDescription& fmt, double targetRate,
                        uint32_t targetChannels) noexcept
    {
        if (fmt.mFormatID != kAudioFormatLinearPCM)
        {
            return false;
        }
        if ((fmt.mFormatFlags & kAudioFormatFlagIsFloat) != 0U)
        {
            return false;
        }
        if (std::fabs(fmt.mSampleRate - targetRate) > kFormatRateEpsilonHz)
        {
            return false;
        }
        return fmt.mChannelsPerFrame == targetChannels;
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
                fprintf(stderr,
                        "[HALOutputEngine] device rate %.1f Hz != file rate %.1f Hz — rate-match not "
                        "achievable (e.g. HDMI 48 kHz lock); declining Pure so Enhanced resamples\n",
                        achieved_.achievedRate, eval.targetDeviceRate);
                teardown();
                return false;
            }
        }

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

    // From a list of advertised physical formats, pick the best integer (bit-perfect) candidate at
    // the target rate with the target channel count. Preference: highest bit depth (e.g. 24-in-32
    // over 16), then the format whose layout most closely matches the device's CURRENT physical
    // format (so we don't fight the driver's preferred packing / endianness). Returns false if no
    // integer format matches at the target rate.
    static bool pickIntegerPhysicalFormat(const std::vector<AudioStreamBasicDescription>& formats,
                                          const AudioStreamBasicDescription& current,
                                          double targetRate, uint32_t targetChannels,
                                          AudioStreamBasicDescription& out) noexcept
    {
        bool found = false;
        AudioStreamBasicDescription best{};
        for (const AudioStreamBasicDescription& fmt : formats)
        {
            if (!isIntegerMatch(fmt, targetRate, targetChannels))
            {
                continue;
            }
            if (!found)
            {
                best = fmt;
                found = true;
                continue;
            }
            // Prefer the higher valid bit depth.
            if (fmt.mBitsPerChannel > best.mBitsPerChannel)
            {
                best = fmt;
                continue;
            }
            if (fmt.mBitsPerChannel == best.mBitsPerChannel)
            {
                // Tie-break: prefer the candidate whose flags match the device's current physical
                // format (its own preferred packing / alignment / endianness).
                const bool fmtMatchesCurrent = (fmt.mFormatFlags == current.mFormatFlags);
                const bool bestMatchesCurrent = (best.mFormatFlags == current.mFormatFlags);
                if (fmtMatchesCurrent && !bestMatchesCurrent)
                {
                    best = fmt;
                }
            }
        }
        if (found)
        {
            out = best;
        }
        return found;
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

    // Top-level format negotiation. Two paths:
    //   FullBitPerfect (integer DAC, hog held): set the DEVICE's physical stream format to an
    //     advertised integer format, then match the AU input scope to the AU output scope the new
    //     physical format produced. This is the real bit-perfect route the spike proved.
    //   RateMatchedFloat (built-in / Bluetooth, shared): leave the physical format alone and use
    //     the AU's native (float) output format verbatim on both scopes. This path already works.
    bool applyStreamFormat(const DeviceCapability& cap, const PureModeEvaluation& eval)
    {
        if (eval.decision == PureModeDecision::FullBitPerfect)
        {
            return applyBitPerfectFormat(cap, eval);
        }
        return applyFloatFormat();
    }

    // FullBitPerfect: enumerate -> choose -> set device physical format -> match AU input to the AU
    // output scope. Falls back to the device's current format (never silence) if no integer match.
    bool applyBitPerfectFormat(const DeviceCapability& cap, const PureModeEvaluation& eval)
    {
        const double targetRate =
            (achieved_.achievedRate > 0.0) ? achieved_.achievedRate : eval.targetDeviceRate;
        const uint32_t channels = deviceChannelCount(cap);

        AudioObjectID stream = firstOutputStream(deviceID_);
        if (stream == kAudioObjectUnknown)
        {
            fprintf(stderr, "[HALOutputEngine] FullBitPerfect: no output stream on device %u; "
                            "falling back to the AU native (float) format\n",
                    deviceID_);
            return applyFloatFormat();
        }

        // Diagnostics: current physical + virtual format, then every advertised physical format.
        AudioStreamBasicDescription currentPhys{};
        const bool haveCurrent = getStreamPhysicalFormat(stream, currentPhys);
        AudioStreamBasicDescription currentVirt{};
        const bool haveVirt = getStreamVirtualFormat(stream, currentVirt);
        fprintf(stderr,
                "[HALOutputEngine] FullBitPerfect on device %u, stream %u: targetRate=%.1f Hz, "
                "channels=%u\n",
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
            fprintf(stderr, "[HALOutputEngine]   available physical formats (%zu):\n",
                    available.size());
            for (const AudioStreamBasicDescription& fmt : available)
            {
                logASBD("  avail", fmt);
            }
        }
        else
        {
            fprintf(stderr, "[HALOutputEngine]   (could not enumerate available physical "
                            "formats)\n");
        }

        // Choose the best integer physical format at the target rate.
        AudioStreamBasicDescription chosen{};
        const bool picked =
            haveList && pickIntegerPhysicalFormat(available, currentPhys, targetRate, channels,
                                                  chosen);
        if (!picked)
        {
            fprintf(stderr,
                    "[HALOutputEngine]   no integer physical format matched (rate=%.1f Hz, ch=%u); "
                    "graceful fallback to the AU native (float) format — device will still play, "
                    "but NOT bit-perfect\n",
                    targetRate, channels);
            return applyFloatFormat();
        }
        logASBD("CHOSEN  physical", chosen);

        // Set the device's physical stream format (hog is held -> permitted).
        if (!setStreamPhysicalFormat(stream, chosen))
        {
            fprintf(stderr, "[HALOutputEngine]   set physical format FAILED; graceful fallback to "
                            "the AU native (float) format\n");
            return applyFloatFormat();
        }
        fprintf(stderr, "[HALOutputEngine]   set physical format OK\n");

        // The AU's output-scope format now reflects the new physical format. Query it (do NOT set
        // it), then match the AU input scope to it exactly so the AU does zero internal conversion.
        AudioStreamBasicDescription auOut{};
        UInt32 size = sizeof(auOut);
        if (AudioUnitGetProperty(unit_, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 0,
                                 &auOut, &size) != noErr)
        {
            fprintf(stderr, "[HALOutputEngine]   query AU output StreamFormat FAILED after physical "
                            "set\n");
            return false;
        }
        logASBD("AU output (post-set)", auOut);

        if (AudioUnitSetProperty(unit_, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 0,
                                 &auOut, sizeof(auOut)) != noErr)
        {
            fprintf(stderr, "[HALOutputEngine]   set AU input StreamFormat (= AU output) FAILED\n");
            return false;
        }
        fprintf(stderr, "[HALOutputEngine]   set AU input StreamFormat OK (matches output)\n");

        // Read back the ACTUAL negotiated input format and cache its decoded flags for the RT path.
        AudioStreamBasicDescription actual{};
        size = sizeof(actual);
        if (AudioUnitGetProperty(unit_, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 0,
                                 &actual, &size) != noErr)
        {
            fprintf(stderr, "[HALOutputEngine]   read-back AU input StreamFormat FAILED\n");
            return false;
        }
        logASBD("AU input (cached)", actual);
        cacheRenderFormat(actual);
        return true;
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
            fprintf(stderr, "[HALOutputEngine] query AU native output StreamFormat failed\n");
            return false;
        }
        logASBD("AU native output", fmt);

        // Supply that same format on the input scope -> zero AU-internal conversion.
        if (AudioUnitSetProperty(unit_, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 0,
                                 &fmt, sizeof(fmt)) != noErr)
        {
            fprintf(stderr, "[HALOutputEngine] set AU input StreamFormat (= native) failed\n");
            return false;
        }

        // Read back the ACTUAL negotiated input format and cache its decoded flags for the RT path.
        AudioStreamBasicDescription actual{};
        size = sizeof(actual);
        if (AudioUnitGetProperty(unit_, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 0,
                                 &actual, &size) != noErr)
        {
            fprintf(stderr, "[HALOutputEngine] read-back AU input StreamFormat failed\n");
            return false;
        }
        logASBD("AU input (cached)", actual);
        cacheRenderFormat(actual);
        return true;
    }

    // Channels the device expects for the bit-perfect path: prefer the physical format's channel
    // count (it is what goes over the wire), then virtual, then a stereo default.
    static uint32_t deviceChannelCount(const DeviceCapability& cap) noexcept
    {
        if (cap.physicalFormat.channels > 0U)
        {
            return cap.physicalFormat.channels;
        }
        if (cap.virtualFormat.channels > 0U)
        {
            return cap.virtualFormat.channels;
        }
        return 2U;
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
