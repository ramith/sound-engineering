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
    // Which decode backend a FileDecodeSource selected at open(). Values match the
    // CAchievedOutputState.decoderBackend C-ABI convention (0 = Apple, 1 = FFmpeg) so the
    // signal-path UI can report the real decoder honestly.
    enum class DecoderKind : uint8_t
    {
        Apple = 0,
        FFmpeg = 1
    };

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

        // Off-RT control-plane: reposition decoding to `seconds` from the start (clamped to >= 0).
        // Joins the decode thread, repositions the backend SAMPLE-ACCURATELY, discards buffered
        // pre-seek audio, and restarts decoding. Returns false if the backend reposition failed
        // (playback still resumes from the prior position so the source is never left dead).
        //
        // PRECONDITION: pullFloat() MUST NOT run concurrently. The HAL engine satisfies this by
        // stopping render around a seek (control-plane). NOT RT-safe; never call from the audio
        // thread.
        [[nodiscard]] bool seek(double seconds);

        // RT thread: drain interleaved float from the ring, zero-padding any short fill. noexcept,
        // allocation-free, lock-free. `channels` MUST equal channels() — the engine renders at the
        // file's channel count; a mismatch yields silence rather than misaligned audio.
        uint32_t pullFloat(float* out, uint32_t frames, uint32_t channels) noexcept override;

        // Source format — valid after a successful open().
        [[nodiscard]] double sampleRate() const noexcept;
        [[nodiscard]] uint32_t channels() const noexcept;
        [[nodiscard]] uint32_t sourceBitsPerChannel() const noexcept;
        [[nodiscard]] bool sourceIsFloat() const noexcept;

        // Which decode backend was selected at open(). Valid after a successful open().
        [[nodiscard]] DecoderKind decoderKind() const noexcept;

        // True once the decoder has read the entire file. The ring may still hold a tail, so a
        // consumer should keep pulling until pullFloat() also returns 0 to know playback truly
        // ended.
        [[nodiscard]] bool decoderFinished() const noexcept;

        // True end-of-stream for the RT consumer: the decoder has finished AND the ring is drained
        // AND no partial frame is carried. This is the gapless seam's true-EOF predicate — when it
        // holds, this source will never produce another frame, so the gapless engine may swap to
        // the armed-next track. RT-safe: noexcept, allocation-free, lock-free; the carry count is
        // RT-thread-private (read race-free here on the RT thread). Distinguishing this from a
        // transient underrun (decoder still running, ring momentarily empty) is what keeps the
        // seam from triggering on a mid-stream buffer starve.
        [[nodiscard]] bool exhausted() const noexcept;

      private:
        class Impl;
        std::unique_ptr<Impl> impl_;
    };
} // namespace AdaptiveSound
