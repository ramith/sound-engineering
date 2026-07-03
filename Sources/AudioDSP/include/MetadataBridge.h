#pragma once

//
// MetadataBridge.h — Pure C header for Swift bridging (S8.3).
//
// The FFmpeg-fallback metadata read for MetadataExtractor: for FLAC/Ogg (and any file
// AVFoundation returns empty tags for), Swift reads embedded tags + cover art + audio
// properties out of a file via the ALREADY-resolved libav* dlopen backend in
// FileDecodeSource.mm — no new dlopen machinery, no link-time FFmpeg.
//
// MUST be valid ISO C11 (no C++, no <cstdint>): it is re-exported by DeviceBridge.h, the
// single Swift-visible module header. #pragma once guards the double-include.
//
// OPAQUE-HANDLE idiom (mirrors PureModeBridge's `void*` create/destroy): the C++ side
// OWNS the extracted storage (std::vector/std::string inside the handle) — there is NO
// manual malloc + no cross-ABI free, so it satisfies the C++ Core Guidelines the raw
// callee-owned-buffer form tripped. Flow from Swift:
//   handle = ffmpegOpenMetadata(path)          // NULL if FFmpeg absent / file unreadable
//   ffmpegMetadataScalars(handle, &scalars)    // fills a caller-allocated POD (counts + props)
//   ffmpegMetadataTagKey/Value(handle, i)      // borrowed const strings (valid until close)
//   ffmpegMetadataArtBytes/ArtMime(handle)     // borrowed const art (valid until close)
//   ffmpegCloseMetadata(handle)                // deletes the handle (defer this in Swift)
// Every returned pointer is owned by the handle and valid ONLY until ffmpegCloseMetadata.
//

#include <stdint.h>

// A noexcept-specifier for the extern "C" bridge functions under C++ (a C++ exception must
// never unwind across the C ABI into Swift — that is UB / std::terminate). Expands to nothing
// for the C compiler Swift's bridging uses, where `noexcept` is not a keyword.
#ifndef AUDIODSP_C_NOEXCEPT
#ifdef __cplusplus
#define AUDIODSP_C_NOEXCEPT noexcept
#else
#define AUDIODSP_C_NOEXCEPT
#endif
#endif

// Scalar metadata read in one call into a caller-allocated POD (no allocation crosses the
// ABI). `tagCount`/`artLength` bound the pointer accessors below.
typedef struct
{
    double durationSeconds;    ///< container duration in seconds; 0 if unknown
    uint32_t sampleRate;       ///< audio codecpar sample_rate (Hz); 0 if unknown
    uint32_t channels;         ///< audio codecpar channel count; 0 if unknown
    uint32_t bitsPerRawSample; ///< audio codecpar bits_per_raw_sample; 0 if unknown/compressed
    uint32_t tagCount;         ///< number of (key,value) tag pairs
    uint32_t artLength;        ///< embedded-art byte length; 0 if none
} CFileMetadataScalars;

#ifdef __cplusplus
extern "C"
{
#endif

    /// Open `path` and extract its metadata into an owned handle, or NULL on ANY failure
    /// (FFmpeg absent, open failure, no such file, `path` NULL). The caller MUST balance a
    /// non-NULL return with exactly one ffmpegCloseMetadata().
    void* ffmpegOpenMetadata(const char* path) AUDIODSP_C_NOEXCEPT;

    /// Destroy a handle from ffmpegOpenMetadata(). NULL-safe.
    void ffmpegCloseMetadata(void* handle) AUDIODSP_C_NOEXCEPT;

    /// Fill `out` (caller-allocated) with the handle's scalar properties + counts. No-op
    /// if either argument is NULL.
    void ffmpegMetadataScalars(void* handle, CFileMetadataScalars* out) AUDIODSP_C_NOEXCEPT;

    /// The lowercased key / the value of tag `index` (< scalars.tagCount), borrowed from
    /// the handle (valid until close). NULL if out of range / handle NULL.
    const char* ffmpegMetadataTagKey(void* handle, uint32_t index) AUDIODSP_C_NOEXCEPT;
    const char* ffmpegMetadataTagValue(void* handle, uint32_t index) AUDIODSP_C_NOEXCEPT;

    /// The embedded-art bytes (scalars.artLength long) / its MIME string, borrowed from the
    /// handle (valid until close). NULL if there is no art / handle NULL.
    const uint8_t* ffmpegMetadataArtBytes(void* handle) AUDIODSP_C_NOEXCEPT;
    const char* ffmpegMetadataArtMime(void* handle) AUDIODSP_C_NOEXCEPT;

#ifdef __cplusplus
} // extern "C"
#endif
