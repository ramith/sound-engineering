//
// PureModeFormat.cpp — bit-exact float -> device-native PCM conversion.
//
// CoreAudio-FREE / Obj-C-FREE, -fno-exceptions / -fno-rtti clean. Compiled into both the AudioDSP
// target and the unit-test harness.
//
// RT-safety: convertFloatToNative is noexcept, allocation-free and lock-free. It runs inside the
// HAL render callback.
//

#include "PureModeFormat.h"

#include <bit>
#include <cstdint>
#include <cstring>

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

        constexpr uint32_t kBytesFloat32 = 4U;
        constexpr uint32_t kBytesInt16 = 2U;
        constexpr uint32_t kBytes32BitWord = 4U;

        constexpr uint32_t kBitsPerByte = 8U;
        constexpr uint32_t kShift16 = 16U;
        constexpr uint32_t kShift24 = 24U;
        constexpr uint32_t k24In32ShiftHigh = 8U;    // left-justify 24 bits in a 32-bit word
        constexpr uint32_t kByteMask = 0xFFU;        // low 8 bits
        constexpr uint32_t k24BitMask = 0x00FFFFFFU; // low 24 bits

        // Clamp a float sample to [-1, 1] before scaling.
        inline float clampUnit(float value) noexcept
        {
            if (value > 1.0F)
            {
                return 1.0F;
            }
            if (value < -1.0F)
            {
                return -1.0F;
            }
            return value;
        }

        inline int32_t toInt16(float value) noexcept
        {
            const auto scaled =
                static_cast<int32_t>(static_cast<double>(clampUnit(value)) * kInt16Scale);
            if (scaled > kInt16Max)
            {
                return kInt16Max;
            }
            if (scaled < kInt16Min)
            {
                return kInt16Min;
            }
            return scaled;
        }

        // 24-bit signed value, returned in the low 24 bits of an int32 (range [-2^23, 2^23-1]).
        inline int32_t toInt24(float value) noexcept
        {
            const auto scaled =
                static_cast<int32_t>(static_cast<double>(clampUnit(value)) * kInt24Scale);
            if (scaled > kInt24Max)
            {
                return kInt24Max;
            }
            if (scaled < kInt24Min)
            {
                return kInt24Min;
            }
            return scaled;
        }

        inline int32_t toInt32(float value) noexcept
        {
            const auto scaled =
                static_cast<int64_t>(static_cast<double>(clampUnit(value)) * kInt32Scale);
            if (scaled > kInt32Max)
            {
                return static_cast<int32_t>(kInt32Max);
            }
            if (scaled < kInt32Min)
            {
                return static_cast<int32_t>(kInt32Min);
            }
            return static_cast<int32_t>(scaled);
        }

        // Store a 16-bit pattern honouring endianness. dst points at the 2-byte slot.
        inline void store16(std::uint8_t* dst, uint16_t bits, bool bigEndian) noexcept
        {
            if (bigEndian)
            {
                dst[0] = static_cast<std::uint8_t>((bits >> kBitsPerByte) & kByteMask);
                dst[1] = static_cast<std::uint8_t>(bits & kByteMask);
            }
            else
            {
                dst[0] = static_cast<std::uint8_t>(bits & kByteMask);
                dst[1] = static_cast<std::uint8_t>((bits >> kBitsPerByte) & kByteMask);
            }
        }

        // Store a 32-bit pattern honouring endianness. dst points at the 4-byte slot.
        inline void store32(std::uint8_t* dst, uint32_t bits, bool bigEndian) noexcept
        {
            if (bigEndian)
            {
                dst[0] = static_cast<std::uint8_t>((bits >> kShift24) & kByteMask);
                dst[1] = static_cast<std::uint8_t>((bits >> kShift16) & kByteMask);
                dst[2] = static_cast<std::uint8_t>((bits >> kBitsPerByte) & kByteMask);
                dst[3] = static_cast<std::uint8_t>(bits & kByteMask);
            }
            else
            {
                dst[0] = static_cast<std::uint8_t>(bits & kByteMask);
                dst[1] = static_cast<std::uint8_t>((bits >> kBitsPerByte) & kByteMask);
                dst[2] = static_cast<std::uint8_t>((bits >> kShift16) & kByteMask);
                dst[3] = static_cast<std::uint8_t>((bits >> kShift24) & kByteMask);
            }
        }

        // ---- per-format store loops (factored out of convertFloatToNative so its branching
        //      stays within the clang-tidy cognitive-complexity budget). All RT-safe / noexcept.

        void
        storeFloat32(std::uint8_t* out, const float* src, uint32_t samples, bool bigEndian) noexcept
        {
            if (!bigEndian)
            {
                std::memcpy(out, src, static_cast<size_t>(samples) * kBytesFloat32);
                return;
            }
            // Float big-endian is essentially never the Mac output format; byte-swap rather than
            // risk a wrong-endian copy.
            for (uint32_t idx = 0U; idx < samples; ++idx)
            {
                const uint32_t bits = std::bit_cast<uint32_t>(src[idx]);
                store32(out + (static_cast<size_t>(idx) * kBytesFloat32), bits, /*bigEndian=*/true);
            }
        }

        void storeInt16Packed(std::uint8_t* out,
                              const float* src,
                              uint32_t samples,
                              bool bigEndian) noexcept
        {
            for (uint32_t idx = 0U; idx < samples; ++idx)
            {
                const auto bits = static_cast<uint16_t>(toInt16(src[idx]));
                store16(out + (static_cast<size_t>(idx) * kBytesInt16), bits, bigEndian);
            }
        }

        void storeInt32Packed(std::uint8_t* out,
                              const float* src,
                              uint32_t samples,
                              bool bigEndian) noexcept
        {
            for (uint32_t idx = 0U; idx < samples; ++idx)
            {
                const auto bits = static_cast<uint32_t>(toInt32(src[idx]));
                store32(out + (static_cast<size_t>(idx) * kBytes32BitWord), bits, bigEndian);
            }
        }

        // 24-bit signed in a 32-bit container (HDMI / USB-DAC case): the 24-bit sample sits either
        // left-justified (aligned-high: top 24 bits, low byte 0) or low-justified (bottom 24 bits).
        void store24In32(std::uint8_t* out,
                         const float* src,
                         uint32_t samples,
                         bool alignedHigh,
                         bool bigEndian) noexcept
        {
            for (uint32_t idx = 0U; idx < samples; ++idx)
            {
                uint32_t bits = static_cast<uint32_t>(toInt24(src[idx])) & k24BitMask;
                if (alignedHigh)
                {
                    bits <<= k24In32ShiftHigh; // left-justify into the 32-bit word
                }
                store32(out + (static_cast<size_t>(idx) * kBytes32BitWord), bits, bigEndian);
            }
        }
    } // namespace

    void convertFloatToNative(const float* src,
                              void* dst,
                              uint32_t frames,
                              uint32_t channels,
                              uint32_t bitsPerChannel,
                              bool isFloat,
                              bool isSignedInt,
                              bool isPacked,
                              bool isAlignedHigh,
                              bool isBigEndian) noexcept
    {
        if (src == nullptr || dst == nullptr || frames == 0U || channels == 0U)
        {
            return;
        }

        const uint32_t samples = frames * channels;
        auto* out = static_cast<std::uint8_t*>(dst);
        const bool intOk = !isFloat && isSignedInt; // from here only signed integer PCM is handled

        if (isFloat && bitsPerChannel == kBits32)
        {
            storeFloat32(out, src, samples, isBigEndian);
            return;
        }
        if (intOk && isPacked && bitsPerChannel == kBits16)
        {
            storeInt16Packed(out, src, samples, isBigEndian);
            return;
        }
        if (intOk && isPacked && bitsPerChannel == kBits32)
        {
            storeInt32Packed(out, src, samples, isBigEndian);
            return;
        }
        if (intOk && bitsPerChannel == kBits24)
        {
            store24In32(out, src, samples, isAlignedHigh, isBigEndian);
            return;
        }

        // Unsupported combination: write silence (safe), never UB. Destination byte span follows
        // the word size implied by the bit depth.
        const uint32_t bytesPerSample = (bitsPerChannel == kBits16) ? kBytesInt16 : kBytes32BitWord;
        std::memset(out, 0, static_cast<size_t>(samples) * bytesPerSample);
    }

} // namespace AdaptiveSound
