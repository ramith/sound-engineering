#pragma once

//
// FileDecodeSource.h — Pure-Mode file decode source (Phase B — B2b).
//
// An ExtAudioFile-backed PureModeSource: decodes an audio file on a background thread into a
// lock-free SPSC ring and feeds interleaved float to the HAL render callback via pullFloat().
// Decoding is at the file's NATIVE sample rate (client rate == file rate => NO sample-rate
// conversion). Bit-exact for 16/24-bit and float sources.
//
// 32-bit-INTEGER caveat (intentional, deferred): the float client format holds 16/24-bit and float
// sources losslessly, but a true 32-bit-integer source loses its low 8 bits at the float boundary.
// A native-integer passthrough is a future follow-up; 32-bit-int PCM files are rare.
//
// Apple-native (AudioToolbox / ExtAudioFile) — no third-party dependency, nothing to bundle.
// FFmpeg is reserved for the exotic formats Apple cannot decode (DSD/Opus/Ogg), added later.
//
// pimpl: the AudioToolbox / threading / ring details stay out of this header so consumers (the
// engine bridge, the signal-path UI) need not pull in CoreAudio.
//

#include "PureModeSource.h"

#include <cstdint>
#include <memory>

namespace AdaptiveSound
{
    class FileDecodeSource final : public PureModeSource
    {
      public:
        FileDecodeSource();
        ~FileDecodeSource() override;

        FileDecodeSource(const FileDecodeSource&) = delete;
        FileDecodeSource& operator=(const FileDecodeSource&) = delete;
        FileDecodeSource(FileDecodeSource&&) = delete;
        FileDecodeSource& operator=(FileDecodeSource&&) = delete;

        // Off-RT: open `path`, read its native format, start the background decode thread.
        // Returns false on any failure (missing/unsupported file, bad format, > 8 channels).
        [[nodiscard]] bool open(const char* path);

        // Off-RT: stop + join the decode thread and close the file. Idempotent; called by the dtor.
        void close() noexcept;

        // RT thread: drain interleaved float from the ring, zero-padding any short fill. noexcept,
        // allocation-free, lock-free. `channels` MUST equal channels() — the engine renders at the
        // file's channel count; a mismatch yields silence rather than misaligned audio.
        uint32_t pullFloat(float* out, uint32_t frames, uint32_t channels) noexcept override;

        // Source format — valid after a successful open().
        [[nodiscard]] double sampleRate() const noexcept;
        [[nodiscard]] uint32_t channels() const noexcept;
        [[nodiscard]] uint32_t sourceBitsPerChannel() const noexcept;
        [[nodiscard]] bool sourceIsFloat() const noexcept;

        // True once the decoder has read the entire file. The ring may still hold a tail, so a
        // consumer should keep pulling until pullFloat() also returns 0 to know playback truly
        // ended.
        [[nodiscard]] bool decoderFinished() const noexcept;

      private:
        class Impl;
        std::unique_ptr<Impl> impl_;
    };
} // namespace AdaptiveSound
