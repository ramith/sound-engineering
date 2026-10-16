#pragma once

//
// PureModeFormat.h — the device-native PCM format Pure Mode renders into, and the bit-exact
// float -> native conversion.
//
// CoreAudio TYPES only: CoreAudioBaseTypes.h supplies AudioStreamBasicDescription and the format
// flag constants (header declarations, nothing linked), so the C++ test harness unit-tests the
// format rules with the very descriptions a device reports. No HAL / AudioUnit / Obj-C here.
// -fno-exceptions / -fno-rtti clean (no throw / dynamic_cast / typeid).
//
// The HAL engine (HALOutputEngine.mm) builds a NativePcmFormat from the AU's ACTUAL negotiated
// input format at configure time. A format the converter cannot write exactly yields no value, and
// the engine declines Pure (the bridge then plays the file through Enhanced) rather than guess.
//

#include <CoreAudioTypes/CoreAudioBaseTypes.h> // AudioStreamBasicDescription + flags (types only)

#include <cstddef>
#include <cstdint>
#include <optional>
#include <span>

namespace AdaptiveSound
{

    // How the device stores one sample. Each is a layout convertFloatToNative writes exactly.
    enum class NativeSampleLayout : uint8_t
    {
        Float32,       // IEEE 754 single precision, 4 bytes (raw passthrough)
        Int16,         // signed 16-bit, 2 bytes
        Int24Packed,   // signed 24-bit, 3 bytes (no padding; common on USB DACs)
        Int24In32High, // signed 24-bit in a 4-byte word, left-justified (low byte 0)
        Int24In32Low,  // signed 24-bit in a 4-byte word, right-justified (top byte 0)
        Int32,         // signed 32-bit, 4 bytes
    };

    // The device-native PCM format Pure renders into: interleaved frames of `channels` samples of
    // one layout, in ONE buffer. The frame stride is derived from the layout, so it cannot
    // disagree with what the converter writes; fromAsbd only yields a format whose description
    // states that same stride (mBytesPerFrame).
    struct NativePcmFormat
    {
        NativeSampleLayout layout = NativeSampleLayout::Float32;
        uint32_t channels = 0;
        bool bigEndian = false;

        // The format a description states, when the converter writes it EXACTLY: linear PCM,
        // interleaved, one of the layouts above, and mBytesPerFrame == channels x the layout's
        // sample size. Anything else — non-interleaved, unsigned or 8/20-bit integers, float64,
        // a byte size the bit depth does not explain — yields std::nullopt (Pure declines).
        [[nodiscard]] static std::optional<NativePcmFormat>
        fromAsbd(const AudioStreamBasicDescription& asbd) noexcept;

        [[nodiscard]] uint32_t bytesPerSample() const noexcept;
        [[nodiscard]] uint32_t bytesPerFrame() const noexcept;
        [[nodiscard]] uint32_t validBits() const noexcept; // significant bits per sample
        [[nodiscard]] bool isFloat() const noexcept;
    };

    // The integer (bit-perfect) physical format to set on a device: among `available`, the linear
    // PCM integer formats at `rateHz` (±1 Hz) with `channels` that NativePcmFormat::fromAsbd
    // accepts (so whatever the AU then hands the render is one the converter writes exactly).
    // Preference: the highest bit depth, then a format whose flags equal `current`'s (the device's
    // own packing / alignment / endianness). std::nullopt when none qualifies.
    [[nodiscard]] std::optional<AudioStreamBasicDescription>
    pickIntegerPhysicalFormat(std::span<const AudioStreamBasicDescription> available,
                              const AudioStreamBasicDescription& current,
                              double rateHz,
                              uint32_t channels) noexcept;

    // Convert interleaved float samples (whole frames of format.channels, nominally in [-1, 1]) to
    // the device-native bytes `dst`. RT-SAFE: noexcept, no allocation, no locks.
    //
    //   * Writes min(frames in src, whole frames dst holds) frames, then zero-fills the rest of
    //     `dst` (room beyond src, a partial trailing frame): every byte of dst is defined and
    //     nothing past dst.size() is touched. Returns the frames converted.
    //   * A sample that is not a finite number (NaN, ±Inf) converts to silence — the rule the
    //     Enhanced kernel applies (FiniteSamples.h). Every finite sample converts exactly as it
    //     would alone, and a finite float32 block is copied bit for bit, so bit-perfect stays
    //     bit-perfect.
    //   * Integers: scale by 2^(N-1) and clamp (the CoreAudio / libsndfile convention), so every
    //     16- and 24-bit source code round-trips exactly; out-of-range input saturates, never wraps.
    std::size_t convertFloatToNative(std::span<const float> src,
                                     std::span<std::byte> dst,
                                     const NativePcmFormat& format) noexcept;

    // TPDF dither for a float → integer step that drops bits (R1.1-A, founder decision 2026-10-16;
    // council C-33): each sample gets the difference of two independent uniform draws — triangular
    // on (−1, +1) LSB of the output word, zero-mean, variance 1/6 LSB² — so the quantization error is
    // signal-independent noise (no distortion, no DC, no noise modulation) rather than truncation's
    // staircase. RT-SAFE: the generator is a 64-bit xorshift* state held here — no allocation, no
    // lock, no system call. One per render thread (it is not thread-safe, and need not be).
    class TpdfDither
    {
      public:
        static constexpr uint64_t kDefaultSeed = 0x9E3779B97F4A7C15ULL;

        explicit TpdfDither(uint64_t seed = kDefaultSeed) noexcept;

        // One dither value, in LSB of the output word: (−1, +1), triangular.
        [[nodiscard]] double next() noexcept;

      private:
        [[nodiscard]] double uniform() noexcept; // [0, 1)
        uint64_t state_;
    };

    // convertFloatToNative for a word that holds fewer bits than the source: each integer sample is
    // the float scaled to the word, plus `dither`, rounded to nearest and clamped. A float32 layout
    // has no integer step and is written exactly as convertFloatToNative writes it. Same bounds,
    // zero-fill and non-finite rules. RT-SAFE: noexcept, no allocation, no locks. Use it only where
    // bits are reduced (ditherWhenConverting): at the exact depth the plain conversion is bit-exact.
    std::size_t convertFloatToNativeDithered(std::span<const float> src,
                                             std::span<std::byte> dst,
                                             const NativePcmFormat& format,
                                             TpdfDither& dither) noexcept;

} // namespace AdaptiveSound
