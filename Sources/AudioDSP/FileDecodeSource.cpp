//
// FileDecodeSource.cpp — Pure-Mode file decode source (Phase B — B2b).
//
// Decodes on a background std::thread into an SpscRing<float>; the RT render thread drains the ring
// via pullFloat(). Decoding goes through a pluggable DecodeBackend selected at open():
//
//   open() decoder policy (FALLBACK-ONLY): Apple first, FFmpeg only if Apple can't open the file.
//     ADAPTIVESOUND_DECODER=apple|ffmpeg forces exactly one backend (diagnostics/tests).
//     AppleDecodeBackend   — ExtAudioFile (AudioToolbox). Always available; the DEFAULT + the
//                            bit/timing-exactness reference (trims lossy encoder delay via the
//                            file's edit list, keeping common formats gapless + Apple-identical).
//     FFmpegDecodeBackend  — FFmpeg via dlopen/dlsym (no link-time dependency, nothing to bundle).
//                            FALLBACK only, for formats Apple's decoder cannot open (e.g. Opus).
//                            Compiled only where FFmpeg headers are present (__has_include) and used
//                            only when a runtime FFmpeg whose MAJOR versions match the ones baked into
//                            this binary is found (FFmpeg guarantees ABI only within a major).
//
// Either backend decodes to interleaved float at the file's NATIVE sample rate (no SRC) — bit-exact
// for 16/24-bit + float sources. A true 32-bit-integer source loses its low 8 bits at the float
// boundary (rare; native-int passthrough is a deferred follow-up).
//
// RT-safety: pullFloat() is noexcept and only touches the lock-free ring + a memset. All decoder
// work + allocation live on the decode thread or the control-plane open()/close() path.
//

#include <AudioToolbox/AudioToolbox.h>
#include <CoreFoundation/CoreFoundation.h>

#include "../include/AsLog.h" // AdaptiveSound::log::line — off-RT control-plane logging seam
#include "../include/FileDecodeSource.h"
#include "../include/MetadataBridge.h"
#include "../include/SpscRing.h"

#include <array>
#include <atomic>
#include <chrono>
#include <cmath>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <memory>
#include <string>
#include <thread>
#include <vector>

#if __has_include(<libavformat/avformat.h>)
#include <dlfcn.h>
// FFmpeg's C headers do not satisfy the AudioDSP target's strict warnings; quarantine them.
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wconversion"
#pragma clang diagnostic ignored "-Wsign-conversion"
#pragma clang diagnostic ignored "-Wold-style-cast"
#pragma clang diagnostic ignored "-Wpedantic"
#pragma clang diagnostic ignored "-Wdocumentation"
#pragma clang diagnostic ignored "-Wcomma"
#include <libavcodec/avcodec.h>
#include <libavformat/avformat.h>
#include <libavutil/avutil.h>
#include <libavutil/channel_layout.h>
#include <libavutil/dict.h>
#include <libavutil/samplefmt.h>
#include <libswresample/swresample.h>
#pragma clang diagnostic pop
#endif

// S8.3 metadata handle (MetadataBridge.h's opaque `void*`): the C++ side OWNS the
// extracted storage via std::vector/std::string (no manual malloc, no cross-ABI free).
// Filled by ffmpegOpenMetadata, read via the accessors, released by ffmpegCloseMetadata.
struct CFileMetadataHandle
{
    std::vector<std::string> keys;
    std::vector<std::string> values;
    std::vector<uint8_t> art;
    std::string artMime;
    double durationSeconds = 0.0;
    uint32_t sampleRate = 0U;
    uint32_t channels = 0U;
    uint32_t bitsPerRawSample = 0U;
};

// Control-plane logging only (open/close/decode thread); never on the RT pull path.
// Diagnostics go through AdaptiveSound::log::line (AsLog.h) — no vararg suppression needed.

namespace AdaptiveSound
{
    namespace
    {
        // Ring capacity (interleaved floats; power of two for SpscRing). 2^18 = 262144 floats ≈
        // 1.4 s of 48 kHz stereo / 0.17 s of 192 kHz 8-channel.
        constexpr std::size_t kRingCapacity = 1U << 18U;

        // Frames pulled from the decoder per read on the decode thread.
        constexpr UInt32 kDecodeReadFrames = 4096U;

        // Upper bound on channels (matches the engine's 7.1/8 ceiling).
        constexpr uint32_t kMaxSourceChannels = 8U;

        // Float client format is 32-bit.
        constexpr uint32_t kClientFloatBits = 32U;

        // Bytes -> bits when reporting source bit depth; used only in the FFmpeg decode path,
        // so [[maybe_unused]] keeps the no-FFmpeg build (__has_include false) clean under -Werror.
        [[maybe_unused]] constexpr uint32_t kBitsPerByte = 8U;

        // Backpressure nap when the ring is momentarily full (off-RT only).
        constexpr int kRingFullNapMs = 2;

        // -------------------------------------------------------------------
        // DecodeBackend — pluggable file decoder producing interleaved float at the file's native
        // sample rate. open()/readChunk()/close() run off the RT thread; readChunk() may allocate.
        // -------------------------------------------------------------------
        class DecodeBackend
        {
          public:
            enum class Status : uint8_t
            {
                Ok,
                Eof,
                Error
            };

            DecodeBackend() = default;
            virtual ~DecodeBackend() = default;
            DecodeBackend(const DecodeBackend&) = delete;
            DecodeBackend& operator=(const DecodeBackend&) = delete;
            DecodeBackend(DecodeBackend&&) = delete;
            DecodeBackend& operator=(DecodeBackend&&) = delete;

            virtual bool open(const char* path) = 0;
            virtual void close() noexcept = 0;

            // Off-RT: reposition decoding to absolute file-frame `frame` (sample-accurate).
            // The decode thread MUST be joined before this is called (no concurrent readChunk).
            // Returns false if the underlying reposition failed.
            virtual bool seekToFrame(int64_t frame) noexcept = 0;

            // Decode the next chunk into `out` (resized to framesOut*channels interleaved floats).
            // framesOut == 0 with Status::Eof signals end of stream.
            virtual Status readChunk(std::vector<float>& out, uint32_t& framesOut) = 0;

            [[nodiscard]] virtual double sampleRate() const noexcept = 0;
            [[nodiscard]] virtual uint32_t channels() const noexcept = 0;
            [[nodiscard]] virtual uint32_t sourceBitsPerChannel() const noexcept = 0;
            [[nodiscard]] virtual bool sourceIsFloat() const noexcept = 0;
            [[nodiscard]] virtual DecoderKind kind() const noexcept = 0;
        };

        // -------------------------------------------------------------------
        // AppleDecodeBackend — ExtAudioFile (AudioToolbox). Always available; the fallback decoder.
        // -------------------------------------------------------------------
        class AppleDecodeBackend final : public DecodeBackend
        {
          public:
            AppleDecodeBackend() = default;
            ~AppleDecodeBackend() override
            {
                close();
            }
            AppleDecodeBackend(const AppleDecodeBackend&) = delete;
            AppleDecodeBackend& operator=(const AppleDecodeBackend&) = delete;
            AppleDecodeBackend(AppleDecodeBackend&&) = delete;
            AppleDecodeBackend& operator=(AppleDecodeBackend&&) = delete;

            bool open(const char* path) override
            {
                if (path == nullptr || file_ != nullptr)
                {
                    return false;
                }
                CFURLRef url =
                    CFURLCreateFromFileSystemRepresentation(nullptr,
                                                            reinterpret_cast<const UInt8*>(path),
                                                            static_cast<CFIndex>(std::strlen(path)),
                                                            static_cast<Boolean>(false));
                if (url == nullptr)
                {
                    return false;
                }
                const OSStatus openStatus = ExtAudioFileOpenURL(url, &file_);
                CFRelease(url);
                if (openStatus != noErr || file_ == nullptr)
                {
                    AdaptiveSound::log::line("[FileDecodeSource] ExtAudioFileOpenURL failed ({})",
                                             static_cast<int>(openStatus));
                    file_ = nullptr;
                    return false;
                }
                if (!readFileFormat() || !setClientFloatFormat())
                {
                    close();
                    return false;
                }
                return true;
            }

            void close() noexcept override
            {
                if (file_ != nullptr)
                {
                    ExtAudioFileDispose(file_);
                    file_ = nullptr;
                }
            }

            // The client (float) data rate equals the file data rate (no SRC), so client-frame
            // indices and file-frame indices coincide => ExtAudioFileSeek is sample-accurate here.
            bool seekToFrame(int64_t frame) noexcept override
            {
                if (file_ == nullptr)
                {
                    return false;
                }
                const OSStatus status = ExtAudioFileSeek(file_, static_cast<SInt64>(frame));
                if (status != noErr)
                {
                    AdaptiveSound::log::line("[FileDecodeSource] ExtAudioFileSeek failed ({})",
                                             static_cast<int>(status));
                }
                return status == noErr;
            }

            Status readChunk(std::vector<float>& out, uint32_t& framesOut) override
            {
                framesOut = 0U;
                out.assign(static_cast<std::size_t>(kDecodeReadFrames) * channels_, 0.0F);

                AudioBufferList abl{};
                abl.mNumberBuffers = 1U;
                abl.mBuffers[0].mNumberChannels = channels_;
                abl.mBuffers[0].mDataByteSize = static_cast<UInt32>(out.size() * sizeof(float));
                abl.mBuffers[0].mData = out.data();

                UInt32 framesRead = kDecodeReadFrames;
                const OSStatus status = ExtAudioFileRead(file_, &framesRead, &abl);
                if (status != noErr)
                {
                    AdaptiveSound::log::line("[FileDecodeSource] ExtAudioFileRead failed ({})",
                                             static_cast<int>(status));
                    return Status::Error;
                }
                framesOut = framesRead;
                return framesRead == 0U ? Status::Eof : Status::Ok;
            }

            [[nodiscard]] double sampleRate() const noexcept override
            {
                return sampleRate_;
            }
            [[nodiscard]] uint32_t channels() const noexcept override
            {
                return channels_;
            }
            [[nodiscard]] uint32_t sourceBitsPerChannel() const noexcept override
            {
                return sourceBits_;
            }
            [[nodiscard]] bool sourceIsFloat() const noexcept override
            {
                return sourceIsFloat_;
            }
            [[nodiscard]] DecoderKind kind() const noexcept override
            {
                return DecoderKind::Apple;
            }

          private:
            bool readFileFormat()
            {
                AudioStreamBasicDescription fileFmt{};
                UInt32 size = sizeof(fileFmt);
                const OSStatus status = ExtAudioFileGetProperty(
                    file_, kExtAudioFileProperty_FileDataFormat, &size, &fileFmt);
                if (status != noErr)
                {
                    AdaptiveSound::log::line("[FileDecodeSource] read FileDataFormat failed ({})",
                                             static_cast<int>(status));
                    return false;
                }
                sampleRate_ = fileFmt.mSampleRate;
                channels_ = fileFmt.mChannelsPerFrame;
                sourceBits_ = fileFmt.mBitsPerChannel; // 0 for compressed sources (informational)
                sourceIsFloat_ = (fileFmt.mFormatID == kAudioFormatLinearPCM) &&
                                 ((fileFmt.mFormatFlags & kAudioFormatFlagIsFloat) != 0U);
                if (sampleRate_ <= 0.0 || channels_ == 0U || channels_ > kMaxSourceChannels)
                {
                    AdaptiveSound::log::line(
                        "[FileDecodeSource] unsupported format (rate {:.1f}, ch {})",
                        sampleRate_,
                        channels_);
                    return false;
                }
                return true;
            }

            bool setClientFloatFormat()
            {
                const UInt32 bytesPerFrame = static_cast<UInt32>(sizeof(float)) * channels_;
                AudioStreamBasicDescription client{};
                client.mFormatID = kAudioFormatLinearPCM;
                client.mFormatFlags = kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked;
                client.mSampleRate = sampleRate_; // == file rate => no sample-rate conversion
                client.mChannelsPerFrame = channels_;
                client.mBitsPerChannel = kClientFloatBits;
                client.mFramesPerPacket = 1U;
                client.mBytesPerFrame = bytesPerFrame;
                client.mBytesPerPacket = bytesPerFrame;

                const OSStatus status = ExtAudioFileSetProperty(
                    file_, kExtAudioFileProperty_ClientDataFormat, sizeof(client), &client);
                if (status != noErr)
                {
                    AdaptiveSound::log::line("[FileDecodeSource] set ClientDataFormat failed ({})",
                                             static_cast<int>(status));
                    return false;
                }
                return true;
            }

            ExtAudioFileRef file_ = nullptr;
            double sampleRate_ = 0.0;
            uint32_t channels_ = 0U;
            uint32_t sourceBits_ = 0U;
            bool sourceIsFloat_ = false;
        };

#if __has_include(<libavformat/avformat.h>)
        // ===================================================================
        // FFmpeg runtime backend. libav* functions are resolved via dlopen/dlsym (no link-time
        // dependency); the headers provide the types. The compatible library MAJOR versions are
        // BAKED into this binary at compile time (kBuilt*Major); at load we verify the runtime
        // library majors match and otherwise refuse FFmpeg, falling back to Apple.
        // ===================================================================

        // Baked compatibility: the FFmpeg library majors this binary was COMPILED against. FFmpeg
        // guarantees ABI stability only within a major version, so a runtime major mismatch is unsafe.
        constexpr int kBuiltAvformatMajor = LIBAVFORMAT_VERSION_MAJOR;
        constexpr int kBuiltAvcodecMajor = LIBAVCODEC_VERSION_MAJOR;
        constexpr int kBuiltAvutilMajor = LIBAVUTIL_VERSION_MAJOR;
        constexpr int kBuiltSwresampleMajor = LIBSWRESAMPLE_VERSION_MAJOR;

        constexpr int kFindStreamAuto = -1; // av_find_best_stream: any / no related stream
        constexpr int kNoFlags = 0;

        // Sentinel for "no usable timestamp / no pending seek discard" (targetFrame_).
        constexpr int64_t kUnknownFrame = -1;

        // Resolved libav* entry points (types from the headers, addresses from dlsym).
        struct FFmpegApi
        {
            bool loaded = false;
            decltype(&::avformat_open_input) avformat_open_input = nullptr;
            decltype(&::avformat_find_stream_info) avformat_find_stream_info = nullptr;
            decltype(&::avformat_close_input) avformat_close_input = nullptr;
            decltype(&::av_read_frame) av_read_frame = nullptr;
            decltype(&::av_find_best_stream) av_find_best_stream = nullptr;
            decltype(&::av_seek_frame) av_seek_frame = nullptr;
            decltype(&::avformat_version) avformat_version = nullptr;
            decltype(&::avcodec_alloc_context3) avcodec_alloc_context3 = nullptr;
            decltype(&::avcodec_parameters_to_context) avcodec_parameters_to_context = nullptr;
            decltype(&::avcodec_open2) avcodec_open2 = nullptr;
            decltype(&::avcodec_send_packet) avcodec_send_packet = nullptr;
            decltype(&::avcodec_receive_frame) avcodec_receive_frame = nullptr;
            decltype(&::avcodec_flush_buffers) avcodec_flush_buffers = nullptr;
            decltype(&::avcodec_free_context) avcodec_free_context = nullptr;
            decltype(&::avcodec_version) avcodec_version = nullptr;
            decltype(&::av_packet_alloc) av_packet_alloc = nullptr;
            decltype(&::av_packet_free) av_packet_free = nullptr;
            decltype(&::av_packet_unref) av_packet_unref = nullptr;
            decltype(&::av_frame_alloc) av_frame_alloc = nullptr;
            decltype(&::av_frame_free) av_frame_free = nullptr;
            decltype(&::av_frame_unref) av_frame_unref = nullptr;
            decltype(&::av_get_bytes_per_sample) av_get_bytes_per_sample = nullptr;
            decltype(&::av_dict_get) av_dict_get = nullptr; // S8.3 metadata read
            decltype(&::avutil_version) avutil_version = nullptr;
            decltype(&::swr_alloc_set_opts2) swr_alloc_set_opts2 = nullptr;
            decltype(&::swr_init) swr_init = nullptr;
            decltype(&::swr_convert) swr_convert = nullptr;
            decltype(&::swr_free) swr_free = nullptr;
            decltype(&::swresample_version) swresample_version = nullptr;
        };

        // dlopen a versioned libav* dylib by its exact MAJOR soname, across Homebrew (AS/Intel), an
        // in-bundle Frameworks dir, and the default dyld search path.
        void* openVersionedLib(const char* base, int major) noexcept
        {
            const std::array<const char*, 4> prefixes = {
                "/opt/homebrew/lib/", "/usr/local/lib/", "@loader_path/../Frameworks/", ""};
            for (const char* prefix : prefixes)
            {
                const std::string soname = std::format("{}{}.{}.dylib", prefix, base, major);
                void* handle = dlopen(soname.c_str(), RTLD_NOW | RTLD_LOCAL);
                if (handle != nullptr)
                {
                    return handle;
                }
            }
            return nullptr;
        }

        template <typename Fn> bool resolveSym(void* handle, const char* symbol, Fn& outFn) noexcept
        {
            outFn = reinterpret_cast<Fn>(dlsym(handle, symbol));
            return outFn != nullptr;
        }

        FFmpegApi loadFFmpegApi() noexcept
        {
            FFmpegApi api;
            void* hutil = openVersionedLib("libavutil", kBuiltAvutilMajor);
            void* hswr = openVersionedLib("libswresample", kBuiltSwresampleMajor);
            void* hcodec = openVersionedLib("libavcodec", kBuiltAvcodecMajor);
            void* hfmt = openVersionedLib("libavformat", kBuiltAvformatMajor);
            if (hutil == nullptr || hswr == nullptr || hcodec == nullptr || hfmt == nullptr)
            {
                return api; // FFmpeg not present at the expected major; Apple decoder will be used.
            }

            // A single && sequence (not 27 statements) keeps cognitive complexity low; resolveSym
            // short-circuits on the first missing symbol.
            const bool ok =
                resolveSym(hfmt, "avformat_open_input", api.avformat_open_input) &&
                resolveSym(hfmt, "avformat_find_stream_info", api.avformat_find_stream_info) &&
                resolveSym(hfmt, "avformat_close_input", api.avformat_close_input) &&
                resolveSym(hfmt, "av_read_frame", api.av_read_frame) &&
                resolveSym(hfmt, "av_find_best_stream", api.av_find_best_stream) &&
                resolveSym(hfmt, "av_seek_frame", api.av_seek_frame) &&
                resolveSym(hfmt, "avformat_version", api.avformat_version) &&
                resolveSym(hcodec, "avcodec_alloc_context3", api.avcodec_alloc_context3) &&
                resolveSym(
                    hcodec, "avcodec_parameters_to_context", api.avcodec_parameters_to_context) &&
                resolveSym(hcodec, "avcodec_open2", api.avcodec_open2) &&
                resolveSym(hcodec, "avcodec_send_packet", api.avcodec_send_packet) &&
                resolveSym(hcodec, "avcodec_receive_frame", api.avcodec_receive_frame) &&
                resolveSym(hcodec, "avcodec_flush_buffers", api.avcodec_flush_buffers) &&
                resolveSym(hcodec, "avcodec_free_context", api.avcodec_free_context) &&
                resolveSym(hcodec, "avcodec_version", api.avcodec_version) &&
                resolveSym(hcodec, "av_packet_alloc", api.av_packet_alloc) &&
                resolveSym(hcodec, "av_packet_free", api.av_packet_free) &&
                resolveSym(hcodec, "av_packet_unref", api.av_packet_unref) &&
                resolveSym(hutil, "av_frame_alloc", api.av_frame_alloc) &&
                resolveSym(hutil, "av_frame_free", api.av_frame_free) &&
                resolveSym(hutil, "av_frame_unref", api.av_frame_unref) &&
                resolveSym(hutil, "av_get_bytes_per_sample", api.av_get_bytes_per_sample) &&
                resolveSym(hutil, "av_dict_get", api.av_dict_get) &&
                resolveSym(hutil, "avutil_version", api.avutil_version) &&
                resolveSym(hswr, "swr_alloc_set_opts2", api.swr_alloc_set_opts2) &&
                resolveSym(hswr, "swr_init", api.swr_init) &&
                resolveSym(hswr, "swr_convert", api.swr_convert) &&
                resolveSym(hswr, "swr_free", api.swr_free) &&
                resolveSym(hswr, "swresample_version", api.swresample_version);
            if (!ok)
            {
                AdaptiveSound::log::line(
                    "[FileDecodeSource] FFmpeg symbol resolution failed; Apple decoder");
                return api;
            }

            // Version guard: runtime library majors must match the baked compile-time majors.
            const int fmtMajor = static_cast<int>(AV_VERSION_MAJOR(api.avformat_version()));
            const int codecMajor = static_cast<int>(AV_VERSION_MAJOR(api.avcodec_version()));
            const int utilMajor = static_cast<int>(AV_VERSION_MAJOR(api.avutil_version()));
            const int swrMajor = static_cast<int>(AV_VERSION_MAJOR(api.swresample_version()));
            if (fmtMajor != kBuiltAvformatMajor || codecMajor != kBuiltAvcodecMajor ||
                utilMajor != kBuiltAvutilMajor || swrMajor != kBuiltSwresampleMajor)
            {
                AdaptiveSound::log::line(
                    "[FileDecodeSource] FFmpeg ABI mismatch (built libavformat {}, found {}); "
                    "using Apple decoder",
                    kBuiltAvformatMajor,
                    fmtMajor);
                return api;
            }
            api.loaded = true;
            return api;
        }

        const FFmpegApi& ffmpegApi() noexcept
        {
            static const FFmpegApi api = loadFFmpegApi(); // resolved once, process lifetime
            return api;
        }

        bool ffmpegAvailable() noexcept
        {
            return ffmpegApi().loaded;
        }

        // FFmpeg decode backend: av_read_frame -> avcodec_send/receive -> swr_convert to interleaved
        // float at the file's NATIVE rate (out-rate == in-rate, so no sample-rate conversion).
        //
        // INVARIANT: ffmpegApi().loaded is true ONLY after every entry point resolved non-null
        // (loadFFmpegApi returns early otherwise), and open()/seekToFrame() bail when !loaded — so
        // every api.*() call below runs through a non-null function pointer. close() is safe under
        // !loaded too: it guards each owned pointer (frame_/pkt_/…), all of which stay null unless a
        // prior open() succeeded (which itself requires loaded).
        class FFmpegDecodeBackend final : public DecodeBackend
        {
          public:
            FFmpegDecodeBackend() = default;
            ~FFmpegDecodeBackend() override
            {
                close();
            }
            FFmpegDecodeBackend(const FFmpegDecodeBackend&) = delete;
            FFmpegDecodeBackend& operator=(const FFmpegDecodeBackend&) = delete;
            FFmpegDecodeBackend(FFmpegDecodeBackend&&) = delete;
            FFmpegDecodeBackend& operator=(FFmpegDecodeBackend&&) = delete;

            bool open(const char* path) override
            {
                const FFmpegApi& api = ffmpegApi();
                if (!api.loaded || path == nullptr || fmt_ != nullptr)
                {
                    return false;
                }
                if (api.avformat_open_input(&fmt_, path, nullptr, nullptr) < 0)
                {
                    AdaptiveSound::log::line("[FileDecodeSource] avformat_open_input failed");
                    fmt_ = nullptr;
                    return false;
                }
                if (api.avformat_find_stream_info(fmt_, nullptr) < 0)
                {
                    close();
                    return false;
                }
                const AVCodec* codec = nullptr;
                const int idx = api.av_find_best_stream(
                    fmt_, AVMEDIA_TYPE_AUDIO, kFindStreamAuto, kFindStreamAuto, &codec, kNoFlags);
                if (idx < 0 || codec == nullptr)
                {
                    close();
                    return false;
                }
                audioStream_ = idx;
                codecCtx_ = api.avcodec_alloc_context3(codec);
                if (codecCtx_ == nullptr)
                {
                    close();
                    return false;
                }
                if (api.avcodec_parameters_to_context(codecCtx_, fmt_->streams[idx]->codecpar) <
                        0 ||
                    api.avcodec_open2(codecCtx_, codec, nullptr) < 0)
                {
                    close();
                    return false;
                }

                sampleRate_ = static_cast<double>(codecCtx_->sample_rate);
                channels_ = static_cast<uint32_t>(codecCtx_->ch_layout.nb_channels);
                const AVSampleFormat sfmt = codecCtx_->sample_fmt;
                // Report the SOURCE bit depth (e.g. 24 for a 24-bit file), not the decoded
                // sample-format width: FFmpeg decodes 24-bit PCM into S32, so bits_per_raw_sample
                // carries the true source depth and matches the Apple backend.
                const int rawBits = codecCtx_->bits_per_raw_sample;
                sourceBits_ =
                    (rawBits > 0)
                        ? static_cast<uint32_t>(rawBits)
                        : static_cast<uint32_t>(api.av_get_bytes_per_sample(sfmt)) * kBitsPerByte;
                sourceIsFloat_ = (sfmt == AV_SAMPLE_FMT_FLT || sfmt == AV_SAMPLE_FMT_FLTP ||
                                  sfmt == AV_SAMPLE_FMT_DBL || sfmt == AV_SAMPLE_FMT_DBLP);
                if (sampleRate_ <= 0.0 || channels_ == 0U || channels_ > kMaxSourceChannels)
                {
                    close();
                    return false;
                }

                // Output: interleaved float at the SAME rate + layout => no resample, no remap.
                if (api.swr_alloc_set_opts2(&swr_,
                                            &codecCtx_->ch_layout,
                                            AV_SAMPLE_FMT_FLT,
                                            codecCtx_->sample_rate,
                                            &codecCtx_->ch_layout,
                                            sfmt,
                                            codecCtx_->sample_rate,
                                            kNoFlags,
                                            nullptr) < 0 ||
                    api.swr_init(swr_) < 0)
                {
                    close();
                    return false;
                }
                pkt_ = api.av_packet_alloc();
                frame_ = api.av_frame_alloc();
                if (pkt_ == nullptr || frame_ == nullptr)
                {
                    close();
                    return false;
                }
                return true;
            }

            void close() noexcept override
            {
                const FFmpegApi& api = ffmpegApi();
                if (frame_ != nullptr)
                {
                    api.av_frame_free(&frame_);
                }
                if (pkt_ != nullptr)
                {
                    api.av_packet_free(&pkt_);
                }
                if (swr_ != nullptr)
                {
                    api.swr_free(&swr_);
                }
                if (codecCtx_ != nullptr)
                {
                    api.avcodec_free_context(&codecCtx_);
                }
                if (fmt_ != nullptr)
                {
                    api.avformat_close_input(&fmt_);
                }
                drained_ = false;
                swrFlushed_ = false;
            }

            // Reposition to absolute file-frame `frame`, sample-accurately. av_seek_frame with
            // AVSEEK_FLAG_BACKWARD lands at or before `frame` (typically a packet/keyframe
            // boundary); the readChunk discard logic then drops the surplus head samples so the
            // first frame handed to the ring starts exactly at `frame`.
            bool seekToFrame(int64_t frame) noexcept override
            {
                const FFmpegApi& api = ffmpegApi();
                if (!api.loaded || fmt_ == nullptr || codecCtx_ == nullptr || swr_ == nullptr ||
                    audioStream_ < 0)
                {
                    return false;
                }
                const AVStream* stream = fmt_->streams[audioStream_];
                const double timeBase = av_q2d(stream->time_base);
                int64_t ts = 0;
                if (timeBase > 0.0)
                {
                    ts = std::llround(static_cast<double>(frame) / sampleRate_ / timeBase);
                }
                if (api.av_seek_frame(fmt_, audioStream_, ts, AVSEEK_FLAG_BACKWARD) < 0)
                {
                    AdaptiveSound::log::line("[FileDecodeSource] av_seek_frame failed");
                    return false;
                }
                // Discard decoder + swresample state carried over from the pre-seek position.
                api.avcodec_flush_buffers(codecCtx_);
                drainSwr(api);
                // The stream is no longer at EOF after a backward/forward seek.
                drained_ = false;
                swrFlushed_ = false;
                // Drive sample-accurate front-drop of the surplus head samples in readChunk.
                targetFrame_ = frame;
                needDiscard_ = true;
                return true;
            }

            Status readChunk(std::vector<float>& out, uint32_t& framesOut) override
            {
                framesOut = 0U;
                const FFmpegApi& api = ffmpegApi();
                for (;;)
                {
                    const int ret = api.avcodec_receive_frame(codecCtx_, frame_);
                    if (ret == 0)
                    {
                        if (frame_->nb_samples <= 0)
                        {
                            api.av_frame_unref(frame_);
                            continue;
                        }
                        // Sample-accurate seek discard: skip frames wholly before the target, and
                        // compute the per-frame front-drop for the frame that straddles it.
                        uint32_t frontDrop = 0U;
                        const bool wasDiscarding = needDiscard_;
                        if (wasDiscarding && !computeSeekDiscard(frontDrop))
                        {
                            api.av_frame_unref(frame_);
                            continue; // whole frame precedes target — skip (NOT framesOut==0).
                        }
                        const Status convStatus = convertFrame(api, out, framesOut, frontDrop);
                        // If the front-drop consumed the entire converted output, keep decoding:
                        // returning framesOut==0 here would make decodeLoop stop mid-seek.
                        if (convStatus == Status::Ok && framesOut == 0U && wasDiscarding)
                        {
                            continue;
                        }
                        return convStatus;
                    }
                    if (ret == AVERROR_EOF)
                    {
                        return flushSwr(api, out, framesOut);
                    }
                    if (ret != AVERROR(EAGAIN))
                    {
                        return Status::Error;
                    }
                    if (drained_)
                    {
                        return Status::Eof;
                    }
                    if (api.av_read_frame(fmt_, pkt_) < 0)
                    {
                        api.avcodec_send_packet(codecCtx_, nullptr); // flush
                        drained_ = true;
                        continue;
                    }
                    if (pkt_->stream_index == audioStream_)
                    {
                        api.avcodec_send_packet(codecCtx_, pkt_);
                    }
                    api.av_packet_unref(pkt_);
                }
            }

            [[nodiscard]] double sampleRate() const noexcept override
            {
                return sampleRate_;
            }
            [[nodiscard]] uint32_t channels() const noexcept override
            {
                return channels_;
            }
            [[nodiscard]] uint32_t sourceBitsPerChannel() const noexcept override
            {
                return sourceBits_;
            }
            [[nodiscard]] bool sourceIsFloat() const noexcept override
            {
                return sourceIsFloat_;
            }
            [[nodiscard]] DecoderKind kind() const noexcept override
            {
                return DecoderKind::FFmpeg;
            }

          private:
            // Empty swresample's internal buffer (feed null input until it yields nothing) so no
            // pre-seek tail leaks into the post-seek output. Called from seekToFrame, off-RT
            // (allocation permitted); never on the RT pull path.
            void drainSwr(const FFmpegApi& api)
            {
                std::vector<float> discard(static_cast<std::size_t>(kDecodeReadFrames) * channels_,
                                           0.0F);
                auto* discardPtr = reinterpret_cast<uint8_t*>(discard.data());
                for (;;)
                {
                    const int converted = api.swr_convert(
                        swr_, &discardPtr, static_cast<int>(kDecodeReadFrames), nullptr, 0);
                    if (converted <= 0)
                    {
                        break;
                    }
                }
            }

            // For a pending seek, derive this frame's front-drop from its presentation timestamp.
            // Returns false when the WHOLE frame precedes targetFrame_ (caller skips the frame).
            // Returns true (with frontDrop set, and needDiscard_ cleared) otherwise; an unusable
            // timestamp abandons precise discard (frontDrop 0) rather than mis-trimming.
            bool computeSeekDiscard(uint32_t& frontDrop) noexcept
            {
                frontDrop = 0U;
                int64_t pts = frame_->best_effort_timestamp;
                if (pts == AV_NOPTS_VALUE)
                {
                    pts = frame_->pts;
                }
                if (pts == AV_NOPTS_VALUE)
                {
                    needDiscard_ = false; // no timestamp — give up on precise discard
                    return true;
                }
                const AVStream* stream = fmt_->streams[audioStream_];
                const double timeBase = av_q2d(stream->time_base);
                const int64_t startFrame =
                    std::llround(static_cast<double>(pts) * timeBase * sampleRate_);
                const int64_t frameEnd = startFrame + frame_->nb_samples;
                if (frameEnd <= targetFrame_)
                {
                    return false; // entire frame is before the target — skip it
                }
                // BACKWARD lands at/before the target; front-drop the surplus head. If the demuxer
                // overshot (startFrame > targetFrame_), there is nothing to drop (clamp to 0).
                if (startFrame < targetFrame_)
                {
                    frontDrop = static_cast<uint32_t>(targetFrame_ - startFrame);
                }
                needDiscard_ = false;
                return true;
            }

            // Drain samples buffered inside swresample once the decoder reaches EOF (swr can hold a
            // small delay even at a matched rate). Returns the flushed frames once, then Eof.
            Status flushSwr(const FFmpegApi& api, std::vector<float>& out, uint32_t& framesOut)
            {
                if (swrFlushed_)
                {
                    return Status::Eof;
                }
                swrFlushed_ = true;
                out.assign(static_cast<std::size_t>(kDecodeReadFrames) * channels_, 0.0F);
                auto* outPtr = reinterpret_cast<uint8_t*>(out.data());
                const int converted =
                    api.swr_convert(swr_, &outPtr, static_cast<int>(kDecodeReadFrames), nullptr, 0);
                if (converted <= 0)
                {
                    return Status::Eof;
                }
                framesOut = static_cast<uint32_t>(converted);
                return Status::Ok;
            }

            Status convertFrame(const FFmpegApi& api,
                                std::vector<float>& out,
                                uint32_t& framesOut,
                                uint32_t frontDrop)
            {
                const int inSamples = frame_->nb_samples;
                out.assign(static_cast<std::size_t>(inSamples) * channels_, 0.0F);
                auto* outPtr = reinterpret_cast<uint8_t*>(out.data());
                // Gather input plane pointers (planar); packed audio uses only plane 0, the rest stay
                // null. Implicit add-const on assignment avoids a cast-away-qualifiers on extended_data.
                std::array<const uint8_t*, kMaxSourceChannels> inPlanes{};
                for (uint32_t ch = 0U; ch < channels_; ++ch)
                {
                    inPlanes[ch] = frame_->extended_data[ch];
                }
                const int converted =
                    api.swr_convert(swr_, &outPtr, inSamples, inPlanes.data(), inSamples);
                api.av_frame_unref(frame_);
                if (converted < 0)
                {
                    return Status::Error;
                }
                uint32_t producedFrames = static_cast<uint32_t>(converted);
                // Sample-accurate seek: front-drop the surplus head samples so the first frame
                // handed to the ring starts exactly at the seek target. Clamp to what we produced.
                if (frontDrop > 0U && producedFrames > 0U)
                {
                    const uint32_t drop = frontDrop < producedFrames ? frontDrop : producedFrames;
                    const uint32_t keptFrames = producedFrames - drop;
                    if (keptFrames > 0U)
                    {
                        const std::size_t dropFloats = static_cast<std::size_t>(drop) * channels_;
                        const std::size_t keptFloats =
                            static_cast<std::size_t>(keptFrames) * channels_;
                        std::memmove(
                            out.data(), out.data() + dropFloats, keptFloats * sizeof(float));
                    }
                    producedFrames = keptFrames;
                }
                framesOut = producedFrames;
                return Status::Ok;
            }

            AVFormatContext* fmt_ = nullptr;
            AVCodecContext* codecCtx_ = nullptr;
            SwrContext* swr_ = nullptr;
            AVPacket* pkt_ = nullptr;
            AVFrame* frame_ = nullptr;
            double sampleRate_ = 0.0;
            int64_t targetFrame_ = kUnknownFrame; // absolute target file-frame of a pending seek
            int audioStream_ = -1;
            uint32_t channels_ = 0U;
            uint32_t sourceBits_ = 0U;
            bool drained_ = false;
            bool swrFlushed_ = false;
            bool sourceIsFloat_ = false;
            bool needDiscard_ = false; // a seek is pending sample-accurate front-drop
        };
#endif // __has_include(<libavformat/avformat.h>)

        // Explicit backend constructors. Apple (ExtAudioFile) is always available and is the
        // bit/timing-exactness reference (it trims lossy encoder delay via the file's edit list).
        // FFmpeg is optional (loaded via dlopen) and may be unavailable — returns nullptr then.
        std::unique_ptr<DecodeBackend> makeAppleBackend()
        {
            return std::make_unique<AppleDecodeBackend>();
        }
        std::unique_ptr<DecodeBackend> makeFFmpegBackend()
        {
#if __has_include(<libavformat/avformat.h>)
            if (ffmpegAvailable())
            {
                return std::make_unique<FFmpegDecodeBackend>();
            }
#endif
            return nullptr;
        }
    } // namespace

    // =======================================================================
    // FileDecodeSource::Impl
    // =======================================================================
    class FileDecodeSource::Impl
    {
      public:
        Impl() = default;
        ~Impl()
        {
            close();
        }

        Impl(const Impl&) = delete;
        Impl& operator=(const Impl&) = delete;
        Impl(Impl&&) = delete;
        Impl& operator=(Impl&&) = delete;

        bool open(const char* path)
        {
            if (backend_ != nullptr)
            {
                return false;
            }

            // Decoder policy (FALLBACK-ONLY): Apple's ExtAudioFile is the DEFAULT and the
            // bit/timing-exactness reference (it trims lossy encoder delay via the file's edit
            // list, so common formats stay gapless + Apple-identical). FFmpeg is a FALLBACK,
            // tried only when Apple cannot open the file (a format Apple doesn't support, e.g.
            // Opus). This prevents FFmpeg from silently becoming the decoder for Apple-decodable
            // formats (which would change the sound + tick lossy gapless seams).
            // ADAPTIVESOUND_DECODER=apple|ffmpeg forces exactly one backend (diagnostics/tests).
            const char* forced = std::getenv("ADAPTIVESOUND_DECODER");
            const bool forceApple = (forced != nullptr) && (std::strcmp(forced, "apple") == 0);
            const bool forceFFmpeg = (forced != nullptr) && (std::strcmp(forced, "ffmpeg") == 0);

            // Open each candidate at most ONCE; the first that opens `path` wins and is retained.
            auto tryOpen = [&](std::unique_ptr<DecodeBackend> candidate) -> bool
            {
                if (candidate == nullptr || !candidate->open(path))
                {
                    return false;
                }
                backend_ = std::move(candidate);
                return true;
            };

            bool opened = false;
            if (forceFFmpeg)
            {
                opened = tryOpen(makeFFmpegBackend());
            }
            else if (forceApple)
            {
                opened = tryOpen(makeAppleBackend());
            }
            else
            {
                // Default: Apple first (bit-exact reference); FFmpeg only if Apple can't open it.
                opened = tryOpen(makeAppleBackend()) || tryOpen(makeFFmpegBackend());
            }
            if (!opened)
            {
                backend_.reset();
                return false;
            }
            // Cache the format so the RT pull path and getters never call the backend.
            sampleRate_ = backend_->sampleRate();
            channels_ = backend_->channels();
            sourceBits_ = backend_->sourceBitsPerChannel();
            sourceIsFloat_ = backend_->sourceIsFloat();
            decoderKind_ = backend_->kind();

            carryCount_ = 0U; // reset the consumer-side frame-carry for this session
            startDecodeThread();
            return true;
        }

        void close() noexcept
        {
            joinDecodeThread();
            if (backend_ != nullptr)
            {
                backend_->close();
                backend_.reset();
            }
        }

        // Off-RT control plane. PRECONDITION: pullFloat() (the RT consumer) is NOT running — the
        // HAL engine stops render around a seek. We then quiesce the producer (join the decode
        // thread), reposition the backend, discard the buffered pre-seek audio while we are the
        // ring's sole accessor, and restart decoding from the new position.
        bool seek(double seconds) noexcept
        {
            if (backend_ == nullptr)
            {
                return false;
            }
            const double clamped = seconds > 0.0 ? seconds : 0.0;
            const int64_t targetFrame = std::llround(clamped * sampleRate_);
            joinDecodeThread(); // producer quiesced; consumer absent by precondition
            const bool ok = backend_->seekToFrame(targetFrame);
            ring_.reset();    // sole owner: discard buffered pre-seek audio
            carryCount_ = 0U; // consumer-side straggler reset (consumer stopped)
            startDecodeThread();
            return ok;
        }

        uint32_t pullFloat(float* out, uint32_t frames, uint32_t channels) noexcept
        {
            if (out == nullptr || frames == 0U || channels == 0U)
            {
                return 0U;
            }
            const std::size_t want = static_cast<std::size_t>(frames) * channels;
            // Channel count must match what the ring holds; otherwise emit silence.
            if (channels != channels_)
            {
                std::memset(out, 0, want * sizeof(float));
                return 0U;
            }

            // Prepend any partial frame carried from the previous pull. The producer pushes whole
            // frames, but tryPushBlock fills float-by-float, so the RT consumer can observe a
            // mid-push (non-frame-aligned) `available` count and pop a partial frame; carrying its
            // straggler samples across pulls avoids dropping them (sample-loss).
            std::size_t filled = 0U;
            if (carryCount_ > 0U)
            {
                std::memcpy(out, carry_.data(), carryCount_ * sizeof(float));
                filled = carryCount_;
                carryCount_ = 0U;
            }
            filled += ring_.popBlock(out + filled, want - filled);

            // Keep only whole frames; stash any trailing partial frame for the next pull.
            const std::size_t wholeFloats = (filled / channels) * channels;
            const std::size_t remainder = filled - wholeFloats;
            if (remainder > 0U)
            {
                std::memcpy(carry_.data(), out + wholeFloats, remainder * sizeof(float));
                carryCount_ = static_cast<uint32_t>(remainder);
            }
            if (wholeFloats < want)
            {
                std::memset(out + wholeFloats, 0, (want - wholeFloats) * sizeof(float));
            }
            return static_cast<uint32_t>(wholeFloats / channels);
        }

        [[nodiscard]] double sampleRate() const noexcept
        {
            return sampleRate_;
        }
        [[nodiscard]] uint32_t channels() const noexcept
        {
            return channels_;
        }
        [[nodiscard]] uint32_t sourceBitsPerChannel() const noexcept
        {
            return sourceBits_;
        }
        [[nodiscard]] bool sourceIsFloat() const noexcept
        {
            return sourceIsFloat_;
        }
        [[nodiscard]] DecoderKind decoderKind() const noexcept
        {
            return decoderKind_;
        }

        [[nodiscard]] bool decoderFinished() const noexcept
        {
            return finished_.load(std::memory_order_acquire);
        }

        // True end-of-stream for the RT consumer: decoder finished AND ring drained AND no carry.
        // finished_ flips (release) only AFTER the decode thread's final pushAll, so observing it
        // true together with an empty ring + zero carry means no further frame can ever arrive.
        // carryCount_ is mutated only by pullFloat (RT) — reading it here on the RT thread is
        // race-free. RT-safe: noexcept, allocation-free, lock-free.
        [[nodiscard]] bool exhausted() const noexcept
        {
            return finished_.load(std::memory_order_acquire) && ring_.isEmpty() &&
                   carryCount_ == 0U;
        }

      private:
        // Spawn the background producer. Caller guarantees no decode thread is currently running
        // (open() after construction, or seek() right after joinDecodeThread()).
        void startDecodeThread() noexcept
        {
            stop_.store(false, std::memory_order_release);
            finished_.store(false, std::memory_order_release);
            // std::thread's ctor throws std::system_error on OS thread-exhaustion; in this noexcept
            // context that calls std::terminate. That is the INTENDED stance (Stage-2 review OWN-4):
            // failing to spawn the decoder is unrecoverable for playback, and the AudioDSP TU is
            // built -fno-exceptions, so there is no meaningful recovery path to surface either way.
            decodeThread_ = std::thread([this] { decodeLoop(); });
        }

        // Signal stop and join the producer if running. Idempotent.
        void joinDecodeThread() noexcept
        {
            stop_.store(true, std::memory_order_release);
            if (decodeThread_.joinable())
            {
                decodeThread_.join();
            }
        }

        void decodeLoop() noexcept
        {
            std::vector<float> scratch;
            while (!stop_.load(std::memory_order_acquire))
            {
                uint32_t framesOut = 0U;
                const DecodeBackend::Status status = backend_->readChunk(scratch, framesOut);
                if (status == DecodeBackend::Status::Error ||
                    status == DecodeBackend::Status::Eof || framesOut == 0U)
                {
                    break;
                }
                pushAll(scratch.data(), static_cast<std::size_t>(framesOut) * channels_);
            }
            finished_.store(true, std::memory_order_release);
        }

        // Push every float into the ring, napping when full (off-RT; never drops).
        void pushAll(const float* data, std::size_t total) noexcept
        {
            std::size_t pushed = 0U;
            while (pushed < total && !stop_.load(std::memory_order_acquire))
            {
                pushed += ring_.tryPushBlock(data + pushed, total - pushed);
                if (pushed < total)
                {
                    std::this_thread::sleep_for(std::chrono::milliseconds(kRingFullNapMs));
                }
            }
        }

        // Field order minimizes padding (SpscRing is cache-line-aligned — keep it first).
        SpscRing<float, kRingCapacity> ring_;
        std::unique_ptr<DecodeBackend> backend_;
        std::thread decodeThread_;
        double sampleRate_ = 0.0;
        std::array<float, kMaxSourceChannels>
            carry_{}; // trailing partial frame (< channels floats)
        uint32_t channels_ = 0U;
        uint32_t sourceBits_ = 0U;
        uint32_t carryCount_ = 0U;
        std::atomic<bool> stop_{false};
        std::atomic<bool> finished_{false};
        bool sourceIsFloat_ = false;
        DecoderKind decoderKind_ = DecoderKind::Apple; // backend selected at open()
    };

    // =======================================================================
    // FileDecodeSource (public shell -> Impl)
    // =======================================================================
    FileDecodeSource::FileDecodeSource() : impl_(std::make_unique<Impl>())
    {
    }
    FileDecodeSource::~FileDecodeSource() = default;

    bool FileDecodeSource::open(const char* path)
    {
        return impl_->open(path);
    }
    void FileDecodeSource::close() noexcept
    {
        impl_->close();
    }
    bool FileDecodeSource::seek(double seconds)
    {
        return impl_->seek(seconds);
    }

    uint32_t FileDecodeSource::pullFloat(float* out, uint32_t frames, uint32_t channels) noexcept
    {
        return impl_->pullFloat(out, frames, channels);
    }

    double FileDecodeSource::sampleRate() const noexcept
    {
        return impl_->sampleRate();
    }
    uint32_t FileDecodeSource::channels() const noexcept
    {
        return impl_->channels();
    }
    uint32_t FileDecodeSource::sourceBitsPerChannel() const noexcept
    {
        return impl_->sourceBitsPerChannel();
    }
    bool FileDecodeSource::sourceIsFloat() const noexcept
    {
        return impl_->sourceIsFloat();
    }
    DecoderKind FileDecodeSource::decoderKind() const noexcept
    {
        return impl_->decoderKind();
    }
    bool FileDecodeSource::decoderFinished() const noexcept
    {
        return impl_->decoderFinished();
    }
    bool FileDecodeSource::exhausted() const noexcept
    {
        return impl_->exhausted();
    }

#if __has_include(<libavformat/avformat.h>)
    // =======================================================================
    // S8.3 metadata read — reuses the resolved ffmpegApi() backend above and fills
    // an OWNED CFileMetadataHandle (std::vector/std::string — no manual malloc, no
    // cross-ABI free): ffmpegOpenMetadata news it, ffmpegCloseMetadata deletes it.
    // =======================================================================

    static const char* artMimeForCodecID(int codecID)
    {
        if (codecID == AV_CODEC_ID_MJPEG)
        {
            return "image/jpeg";
        }
        if (codecID == AV_CODEC_ID_PNG)
        {
            return "image/png";
        }
        return nullptr;
    }

    // Append every entry of `dict` to the handle's key/value vectors, lowercasing keys.
    static void
    appendDictTags(const AVDictionary* dict, const FFmpegApi& api, CFileMetadataHandle* handle)
    {
        if (dict == nullptr)
        {
            return;
        }
        const AVDictionaryEntry* entry = nullptr;
        while ((entry = api.av_dict_get(dict, "", entry, AV_DICT_IGNORE_SUFFIX)) != nullptr)
        {
            std::string key = entry->key != nullptr ? entry->key : "";
            for (char& character : key)
            {
                if (character >= 'A' && character <= 'Z')
                {
                    character = static_cast<char>(character - 'A' + 'a');
                }
            }
            handle->keys.push_back(std::move(key));
            handle->values.emplace_back(entry->value != nullptr ? entry->value : "");
        }
    }

    // Copy the first attached-picture stream's bytes + MIME into the handle.
    static void readAttachedArt(AVFormatContext* fmt, CFileMetadataHandle* handle)
    {
        for (unsigned index = 0U; index < fmt->nb_streams; ++index)
        {
            AVStream* stream = fmt->streams[index];
            const bool isPic = (stream->disposition & AV_DISPOSITION_ATTACHED_PIC) != 0;
            if (isPic && stream->attached_pic.size > 0)
            {
                const std::size_t bytes = static_cast<std::size_t>(stream->attached_pic.size);
                handle->art.assign(stream->attached_pic.data, stream->attached_pic.data + bytes);
                const char* mime = artMimeForCodecID(stream->codecpar->codec_id);
                if (mime != nullptr)
                {
                    handle->artMime = mime;
                }
                return;
            }
        }
    }

    // Open `path` and fill a NEW owned handle, or nullptr on failure (caller frees).
    static CFileMetadataHandle* openFFmpegMetadataImpl(const char* path)
    {
        const FFmpegApi& api = ffmpegApi();
        if (!api.loaded)
        {
            return nullptr;
        }
        AVFormatContext* fmt = nullptr;
        if (api.avformat_open_input(&fmt, path, nullptr, nullptr) < 0 || fmt == nullptr)
        {
            return nullptr;
        }
        if (api.avformat_find_stream_info(fmt, nullptr) < 0)
        {
            api.avformat_close_input(&fmt);
            return nullptr;
        }
        // ownership transfers to the C caller
        auto* handle = new (std::nothrow) CFileMetadataHandle();
        if (handle == nullptr)
        {
            api.avformat_close_input(&fmt);
            return nullptr;
        }

        const int audioIndex = api.av_find_best_stream(
            fmt, AVMEDIA_TYPE_AUDIO, kFindStreamAuto, kFindStreamAuto, nullptr, kNoFlags);
        if (audioIndex >= 0)
        {
            const AVCodecParameters* params = fmt->streams[audioIndex]->codecpar;
            if (params->sample_rate > 0)
            {
                handle->sampleRate = static_cast<uint32_t>(params->sample_rate);
            }
            if (params->ch_layout.nb_channels > 0)
            {
                handle->channels = static_cast<uint32_t>(params->ch_layout.nb_channels);
            }
            if (params->bits_per_raw_sample > 0)
            {
                handle->bitsPerRawSample = static_cast<uint32_t>(params->bits_per_raw_sample);
            }
        }
        if (fmt->duration > 0)
        {
            handle->durationSeconds =
                static_cast<double>(fmt->duration) / static_cast<double>(AV_TIME_BASE);
        }

        appendDictTags(fmt->metadata, api, handle);
        if (audioIndex >= 0)
        {
            appendDictTags(fmt->streams[audioIndex]->metadata, api, handle);
        }
        readAttachedArt(fmt, handle);

        api.avformat_close_input(&fmt);
        return handle;
    }
#endif // __has_include(<libavformat/avformat.h>)

} // namespace AdaptiveSound

// ===========================================================================
// C-ABI metadata bridge (S8.3, MetadataBridge.h) — an opaque OWNED handle (mirrors
// PureModeBridge). Real open when FFmpeg headers are present; otherwise nullptr so
// MetadataExtractor degrades to AVFoundation-only. No malloc: the handle owns its
// std::vector/std::string storage and is released by ffmpegCloseMetadata.
// ===========================================================================
extern "C" void* ffmpegOpenMetadata(const char* path) AUDIODSP_C_NOEXCEPT
{
    if (path == nullptr)
    {
        return nullptr;
    }
#if __has_include(<libavformat/avformat.h>)
    return AdaptiveSound::openFFmpegMetadataImpl(path);
#else
    return nullptr;
#endif
}

extern "C" void ffmpegCloseMetadata(void* handle) AUDIODSP_C_NOEXCEPT
{
    // balances ffmpegOpenMetadata()
    delete static_cast<CFileMetadataHandle*>(handle);
}

extern "C" void ffmpegMetadataScalars(const void* handle,
                                      CFileMetadataScalars* out) AUDIODSP_C_NOEXCEPT
{
    if (handle == nullptr || out == nullptr)
    {
        return;
    }
    const auto* meta = static_cast<const CFileMetadataHandle*>(handle);
    out->durationSeconds = meta->durationSeconds;
    out->sampleRate = meta->sampleRate;
    out->channels = meta->channels;
    out->bitsPerRawSample = meta->bitsPerRawSample;
    out->tagCount = static_cast<uint32_t>(meta->keys.size());
    out->artLength = static_cast<uint32_t>(meta->art.size());
}

extern "C" const char* ffmpegMetadataTagKey(const void* handle, uint32_t index) AUDIODSP_C_NOEXCEPT
{
    if (handle == nullptr)
    {
        return nullptr;
    }
    const auto* meta = static_cast<const CFileMetadataHandle*>(handle);
    return index < meta->keys.size() ? meta->keys[index].c_str() : nullptr;
}

extern "C" const char* ffmpegMetadataTagValue(const void* handle,
                                              uint32_t index) AUDIODSP_C_NOEXCEPT
{
    if (handle == nullptr)
    {
        return nullptr;
    }
    const auto* meta = static_cast<const CFileMetadataHandle*>(handle);
    return index < meta->values.size() ? meta->values[index].c_str() : nullptr;
}

extern "C" const uint8_t* ffmpegMetadataArtBytes(const void* handle) AUDIODSP_C_NOEXCEPT
{
    if (handle == nullptr)
    {
        return nullptr;
    }
    const auto* meta = static_cast<const CFileMetadataHandle*>(handle);
    return meta->art.empty() ? nullptr : meta->art.data();
}

extern "C" const char* ffmpegMetadataArtMime(const void* handle) AUDIODSP_C_NOEXCEPT
{
    if (handle == nullptr)
    {
        return nullptr;
    }
    const auto* meta = static_cast<const CFileMetadataHandle*>(handle);
    return meta->artMime.empty() ? nullptr : meta->artMime.c_str();
}
