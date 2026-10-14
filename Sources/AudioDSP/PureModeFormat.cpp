//
// PureModeFormat.cpp — the device-native PCM format Pure renders into (NativePcmFormat), the
// integer physical-format pick, and the bit-exact float -> native conversion.
//
// CoreAudio TYPES only (no HAL / AudioUnit / Obj-C), -fno-exceptions / -fno-rtti clean. Compiled
// into both the AudioDSP target and the unit-test harness.
//
// RT-safety: convertFloatToNative is noexcept, allocation-free and lock-free. It runs inside the
// HAL render callback. fromAsbd and pickIntegerPhysicalFormat run on the control plane (configure).
//

#include "PureModeFormat.h"

#include "FiniteSamples.h"

#include <algorithm>
#include <bit>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <cstring>
#include <limits>
#include <optional>
#include <span>

namespace AdaptiveSound
{

    namespace
    {
        // Bit-perfect float<->int convention (matches CoreAudio / libsndfile): int->float divides
        // by 2^(N-1), so the inverse multiplies by 2^(N-1) and clamps into [min, max]. This makes
        // -1.0f reach the true negative full scale (e.g. -0x8000) so an int16 source round-trips
        // exactly; +1.0f maps to 2^(N-1), which clamps down to the positive max (e.g. 0x7FFF).
        constexpr int32_t kInt16Max = 32767;    // 0x7FFF
        constexpr int32_t kInt16Min = -32768;   // -0x8000
        constexpr double kInt16Scale = 32768.0; // 2^15

        // 24-bit signed range.
        constexpr int32_t kInt24Max = 8388607;    // 0x7FFFFF
        constexpr int32_t kInt24Min = -8388608;   // -0x800000
        constexpr double kInt24Scale = 8388608.0; // 2^23

        // 32-bit signed range. Scale is held as a double; 2147483648.0 is representable.
        constexpr int64_t kInt32Max = 2147483647;    // 0x7FFFFFFF
        constexpr int64_t kInt32Min = -2147483648LL; // -0x80000000
        constexpr double kInt32Scale = 2147483648.0; // 2^31

        constexpr uint32_t kBits16 = 16U;
        constexpr uint32_t kBits24 = 24U;
        constexpr uint32_t kBits32 = 32U;

        constexpr uint32_t kBytesInt16 = 2U;
        constexpr uint32_t kBytesInt24Packed = 3U;
        constexpr uint32_t kBytes32BitWord = 4U; // float32, int32, 24-in-32

        constexpr uint32_t kBitsPerByte = 8U;
        constexpr uint32_t k24In32ShiftHigh = 8U;    // left-justify 24 bits in a 32-bit word
        constexpr uint32_t kByteMask = 0xFFU;        // low 8 bits
        constexpr uint32_t k24BitMask = 0x00FFFFFFU; // low 24 bits

        // A candidate physical format's rate matches the target within this many Hz.
        constexpr double kFormatRateEpsilonHz = 1.0;

        [[nodiscard]] bool hasFlag(AudioFormatFlags flags, AudioFormatFlags flag) noexcept
        {
            return (flags & flag) != 0U;
        }

        // The sample as a finite value in [-1, 1]. A NaN or an infinity is silence — the rule the
        // Enhanced kernel applies (FiniteSamples.h): it is not audio, and converting it to an
        // integer would be undefined behaviour. An out-of-range value saturates.
        [[nodiscard]] float unitSample(float value) noexcept
        {
            return std::clamp(finiteOrSilence(value), -1.0F, 1.0F);
        }

        [[nodiscard]] int32_t toInt16(float value) noexcept
        {
            const auto scaled =
                static_cast<int32_t>(static_cast<double>(unitSample(value)) * kInt16Scale);
            return std::clamp(scaled, kInt16Min, kInt16Max);
        }

        // 24-bit signed value, returned in an int32 (range [-2^23, 2^23-1]).
        [[nodiscard]] int32_t toInt24(float value) noexcept
        {
            const auto scaled =
                static_cast<int32_t>(static_cast<double>(unitSample(value)) * kInt24Scale);
            return std::clamp(scaled, kInt24Min, kInt24Max);
        }

        [[nodiscard]] int32_t toInt32(float value) noexcept
        {
            const auto scaled =
                static_cast<int64_t>(static_cast<double>(unitSample(value)) * kInt32Scale);
            return static_cast<int32_t>(std::clamp(scaled, kInt32Min, kInt32Max));
        }

        // The device word for one sample, per layout (the bits; storeWord lays out the bytes).
        [[nodiscard]] uint32_t float32Word(float sample) noexcept
        {
            return std::bit_cast<uint32_t>(finiteOrSilence(sample));
        }

        [[nodiscard]] uint32_t int16Word(float sample) noexcept
        {
            return static_cast<uint32_t>(toInt16(sample));
        }

        // The 24-bit value in the low 24 bits (packed, and 24-in-32 low-justified: top byte 0).
        [[nodiscard]] uint32_t int24Word(float sample) noexcept
        {
            return static_cast<uint32_t>(toInt24(sample)) & k24BitMask;
        }

        // The 24-bit value left-justified in a 32-bit word (low byte 0).
        [[nodiscard]] uint32_t int24HighWord(float sample) noexcept
        {
            return int24Word(sample) << k24In32ShiftHigh;
        }

        [[nodiscard]] uint32_t int32Word(float sample) noexcept
        {
            return static_cast<uint32_t>(toInt32(sample));
        }

        // Store the low `width` bytes of `bits` at dst: least significant first (little-endian, the
        // Mac norm) or most significant first. `width` is 2, 3 or 4.
        void storeWord(std::byte* dst, uint32_t bits, uint32_t width, bool bigEndian) noexcept
        {
            for (uint32_t idx = 0U; idx < width; ++idx)
            {
                const uint32_t byteIndex = bigEndian ? (width - 1U - idx) : idx;
                dst[idx] = static_cast<std::byte>((bits >> (byteIndex * kBitsPerByte)) & kByteMask);
            }
        }

        // One `width`-byte word per sample, its bits from `word` (one of the *Word functions).
        void storeEach(std::span<const float> samples,
                       std::byte* out,
                       uint32_t width,
                       bool bigEndian,
                       uint32_t (*word)(float) noexcept) noexcept
        {
            for (const float sample : samples)
            {
                storeWord(out, word(sample), width, bigEndian);
                out += width;
            }
        }

        void storeFloat32(std::span<const float> samples, std::byte* out, bool bigEndian) noexcept
        {
            // The common case — a little-endian float device and a block of finite samples — is a
            // copy: bit for bit what the source decoded, out-of-range values included.
            if (!bigEndian && samples.size() <= std::numeric_limits<uint32_t>::max() &&
                allFinite(samples.data(), static_cast<uint32_t>(samples.size())))
            {
                std::memcpy(out, samples.data(), samples.size_bytes());
                return;
            }
            storeEach(samples, out, kBytes32BitWord, bigEndian, float32Word);
        }

        // The layout a linear-PCM description's flags, bit depth and sample size state — only
        // when the converter writes it exactly.
        [[nodiscard]] std::optional<NativeSampleLayout>
        sampleLayout(AudioFormatFlags flags, uint32_t bits, uint32_t bytes) noexcept
        {
            // "Packed" promises the bits fill the sample's bytes; a description that says so while
            // leaving bits over contradicts itself, and Pure does not guess which half is true.
            if (hasFlag(flags, kAudioFormatFlagIsPacked) && bits != bytes * kBitsPerByte)
            {
                return std::nullopt;
            }
            if (hasFlag(flags, kAudioFormatFlagIsFloat))
            {
                if (bits == kBits32 && bytes == kBytes32BitWord)
                {
                    return NativeSampleLayout::Float32;
                }
                return std::nullopt; // float64 and the like
            }
            if (!hasFlag(flags, kAudioFormatFlagIsSignedInteger))
            {
                return std::nullopt; // unsigned integer PCM
            }
            if (bits == kBits16 && bytes == kBytesInt16)
            {
                return NativeSampleLayout::Int16;
            }
            if (bits == kBits32 && bytes == kBytes32BitWord)
            {
                return NativeSampleLayout::Int32;
            }
            if (bits == kBits24 && bytes == kBytesInt24Packed)
            {
                return NativeSampleLayout::Int24Packed;
            }
            if (bits == kBits24 && bytes == kBytes32BitWord)
            {
                return hasFlag(flags, kAudioFormatFlagIsAlignedHigh)
                           ? NativeSampleLayout::Int24In32High
                           : NativeSampleLayout::Int24In32Low;
            }
            return std::nullopt; // 8- / 20-bit, 16-in-32, and every other container
        }

        // An integer format at the rate and width Pure drives, that the converter writes exactly.
        [[nodiscard]] bool isWritableIntegerMatch(const AudioStreamBasicDescription& fmt,
                                                  double rateHz,
                                                  uint32_t channels) noexcept
        {
            const std::optional<NativePcmFormat> native = NativePcmFormat::fromAsbd(fmt);
            return native.has_value() && !native->isFloat() && native->channels == channels &&
                   std::fabs(fmt.mSampleRate - rateHz) <= kFormatRateEpsilonHz;
        }

        // `candidate` over `incumbent`: the higher bit depth, then (at equal depth) the format
        // whose flags are the device's current ones (its own packing / alignment / endianness).
        [[nodiscard]] bool preferred(const AudioStreamBasicDescription& candidate,
                                     const AudioStreamBasicDescription& incumbent,
                                     const AudioStreamBasicDescription& current) noexcept
        {
            if (candidate.mBitsPerChannel != incumbent.mBitsPerChannel)
            {
                return candidate.mBitsPerChannel > incumbent.mBitsPerChannel;
            }
            return candidate.mFormatFlags == current.mFormatFlags &&
                   incumbent.mFormatFlags != current.mFormatFlags;
        }
    } // namespace

    std::optional<NativePcmFormat>
    NativePcmFormat::fromAsbd(const AudioStreamBasicDescription& asbd) noexcept
    {
        const uint32_t channels = asbd.mChannelsPerFrame;
        // Pure writes ONE interleaved buffer of whole samples; anything else is not a layout the
        // converter knows.
        if (asbd.mFormatID != kAudioFormatLinearPCM ||
            hasFlag(asbd.mFormatFlags, kAudioFormatFlagIsNonInterleaved) || channels == 0U ||
            asbd.mBytesPerFrame % channels != 0U)
        {
            return std::nullopt;
        }
        const std::optional<NativeSampleLayout> layout =
            sampleLayout(asbd.mFormatFlags, asbd.mBitsPerChannel, asbd.mBytesPerFrame / channels);
        if (!layout.has_value())
        {
            return std::nullopt;
        }
        NativePcmFormat format;
        format.layout = *layout;
        format.channels = channels;
        format.bigEndian = hasFlag(asbd.mFormatFlags, kAudioFormatFlagIsBigEndian);
        return format;
    }

    uint32_t NativePcmFormat::bytesPerSample() const noexcept
    {
        switch (layout)
        {
            case NativeSampleLayout::Int16:
                return kBytesInt16;
            case NativeSampleLayout::Int24Packed:
                return kBytesInt24Packed;
            case NativeSampleLayout::Float32:
            case NativeSampleLayout::Int24In32High:
            case NativeSampleLayout::Int24In32Low:
            case NativeSampleLayout::Int32:
                return kBytes32BitWord;
        }
        return kBytes32BitWord; // unreachable for a valid enumerator; keeps the function total
    }

    uint32_t NativePcmFormat::bytesPerFrame() const noexcept
    {
        return channels * bytesPerSample();
    }

    uint32_t NativePcmFormat::validBits() const noexcept
    {
        switch (layout)
        {
            case NativeSampleLayout::Int16:
                return kBits16;
            case NativeSampleLayout::Int24Packed:
            case NativeSampleLayout::Int24In32High:
            case NativeSampleLayout::Int24In32Low:
                return kBits24;
            case NativeSampleLayout::Float32:
            case NativeSampleLayout::Int32:
                return kBits32;
        }
        return kBits32; // unreachable for a valid enumerator; keeps the function total
    }

    bool NativePcmFormat::isFloat() const noexcept
    {
        return layout == NativeSampleLayout::Float32;
    }

    std::optional<AudioStreamBasicDescription>
    pickIntegerPhysicalFormat(std::span<const AudioStreamBasicDescription> available,
                              const AudioStreamBasicDescription& current,
                              double rateHz,
                              uint32_t channels) noexcept
    {
        std::optional<AudioStreamBasicDescription> best;
        for (const AudioStreamBasicDescription& fmt : available)
        {
            if (isWritableIntegerMatch(fmt, rateHz, channels) &&
                (!best.has_value() || preferred(fmt, *best, current)))
            {
                best = fmt;
            }
        }
        return best;
    }

    std::size_t convertFloatToNative(std::span<const float> src,
                                     std::span<std::byte> dst,
                                     const NativePcmFormat& format) noexcept
    {
        // The frame stride comes from the format, never from the bit depth: a 24-bit sample is 3
        // bytes packed and 4 in a 32-bit word, and the buffer's own byte size bounds the write.
        const std::size_t bytesPerFrame =
            static_cast<std::size_t>(format.channels) * format.bytesPerSample(); // no 32-bit wrap
        const std::size_t frames = (bytesPerFrame == 0U) ? 0U
                                                         : std::min(src.size() / format.channels,
                                                                    dst.size() / bytesPerFrame);
        if (frames > 0U)
        {
            const std::span<const float> samples = src.first(frames * format.channels);
            std::byte* const out = dst.data();
            const bool bigEndian = format.bigEndian;
            switch (format.layout)
            {
                case NativeSampleLayout::Float32:
                    storeFloat32(samples, out, bigEndian);
                    break;
                case NativeSampleLayout::Int16:
                    storeEach(samples, out, kBytesInt16, bigEndian, int16Word);
                    break;
                case NativeSampleLayout::Int24Packed:
                    storeEach(samples, out, kBytesInt24Packed, bigEndian, int24Word);
                    break;
                case NativeSampleLayout::Int24In32High:
                    storeEach(samples, out, kBytes32BitWord, bigEndian, int24HighWord);
                    break;
                case NativeSampleLayout::Int24In32Low:
                    storeEach(samples, out, kBytes32BitWord, bigEndian, int24Word);
                    break;
                case NativeSampleLayout::Int32:
                    storeEach(samples, out, kBytes32BitWord, bigEndian, int32Word);
                    break;
            }
        }
        // Whatever no converted frame covers (room beyond src, a partial trailing frame) is
        // silence, so the device never plays stale bytes.
        std::ranges::fill(dst.subspan(frames * bytesPerFrame), std::byte{0});
        return frames;
    }

} // namespace AdaptiveSound
