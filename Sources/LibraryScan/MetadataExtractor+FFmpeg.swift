// MetadataExtractor+FFmpeg — the FFmpeg fallback path (design §3).
//
// For FLAC/Ogg (and any file AVFoundation returns empty for), read tags + art + audio
// properties via the AudioDSP C bridge, which reuses the existing dlopen'd libav* backend
// — no new dlopen machinery, no link-time FFmpeg. The bridge is an OPAQUE OWNED handle
// (ffmpegOpenMetadata → accessors → ffmpegCloseMetadata, mirroring PureModeBridge): the
// C++ side owns the storage, Swift borrows const pointers valid until close (defer'd).
// FFmpeg absent / file unreadable → ffmpegOpenMetadata returns nil → this returns nil (the
// caller then keeps/falls back to AVFoundation). Vorbis-comment keys are lowercased by the bridge.

import AudioDSP
import Foundation
import LibraryStore

extension MetadataExtractor {
    /// Extract via the FFmpeg C bridge, or nil if FFmpeg is unavailable / can't open the file.
    func ffmpegExtract(_ url: URL) -> ExtractedMetadata? {
        guard let handle = ffmpegOpenMetadata(url.path) else { return nil }
        defer { ffmpegCloseMetadata(handle) }

        var scalars = CFileMetadataScalars()
        ffmpegMetadataScalars(handle, &scalars)
        let tags = Self.tagDictionary(handle, count: scalars.tagCount)
        // The bridge lowercases keys; each ?? chain maps BOTH the Vorbis-comment spelling
        // (FLAC/Ogg: `albumartist`, `tracknumber`, `discnumber`, `date`) and the alternate
        // ID3/container spelling (`album artist`, `track`, `disc`, `year`/`originaldate`).
        let meta = TrackMetadata(
            title: tags["title"],
            artistName: tags["artist"],
            albumTitle: tags["album"],
            albumArtistName: tags["albumartist"] ?? tags["album artist"],
            year: Self.parseYear(tags["date"] ?? tags["year"] ?? tags["originaldate"]),
            trackNo: Self.parseLeadingInt(tags["tracknumber"] ?? tags["track"]),
            discNo: Self.parseLeadingInt(tags["discnumber"] ?? tags["disc"]),
            genres: Self.parseGenres(tags["genre"]),
            durationMs: scalars.durationSeconds > 0 ? Int64((scalars.durationSeconds * 1000).rounded()) : 0,
            sampleRate: scalars.sampleRate > 0 ? Int(scalars.sampleRate) : nil,
            bitDepth: scalars.bitsPerRawSample > 0 ? Int(scalars.bitsPerRawSample) : nil,
            channels: scalars.channels > 0 ? Int(scalars.channels) : nil
        )
        return ExtractedMetadata(metadata: meta, artwork: Self.ffmpegArtwork(handle, scalars: scalars))
    }

    /// Build a `[lowercased-key: value]` map from the handle's borrowed tag strings.
    private static func tagDictionary(_ handle: UnsafeMutableRawPointer, count: UInt32) -> [String: String] {
        var tags: [String: String] = [:]
        for index in 0 ..< count {
            guard let key = ffmpegMetadataTagKey(handle, index),
                  let value = ffmpegMetadataTagValue(handle, index) else { continue }
            tags[String(cString: key)] = String(cString: value)
        }
        return tags
    }

    /// The handle's embedded art (≤ `maxArtBytes`), UTI from its MIME, or nil. The bytes are
    /// COPIED into `Data` before the caller's `defer` closes the handle.
    private static func ffmpegArtwork(_ handle: UnsafeMutableRawPointer,
                                      scalars: CFileMetadataScalars) -> ExtractedArtwork? {
        // Art beyond maxArtBytes is intentionally DROPPED (returns nil): a guard against a
        // pathological embedded image. The track keeps its tags — it just gets no cover.
        guard scalars.artLength > 0, Int(scalars.artLength) <= maxArtBytes,
              let bytes = ffmpegMetadataArtBytes(handle) else { return nil }
        let data = Data(bytes: bytes, count: Int(scalars.artLength))
        let uti = ffmpegMetadataArtMime(handle).map { String(cString: $0) }.flatMap(utiFromMime)
        return ExtractedArtwork(data: data, uti: uti)
    }
}
