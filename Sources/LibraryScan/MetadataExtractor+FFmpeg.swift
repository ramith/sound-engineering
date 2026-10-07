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
        // The bridge lowercases keys. FFmpeg's demuxers NORMALISE most tags to its generic names
        // before we see them — the flac/ogg Vorbis-comment table maps ALBUMARTIST → `album_artist`,
        // TRACKNUMBER → `track`, DISCNUMBER → `disc`; mp4 `aART` and ID3 `TPE2` also land on
        // `album_artist` — so the generic key leads each ?? chain, and the raw spellings
        // (`albumartist`, `album artist`, `tracknumber`, `discnumber`, `year`/`originaldate`) back
        // it up. (S10.8 C2: the chain once lacked `album_artist`, so EVERY FLAC album artist was
        // dropped → "Unknown Artist"; ALB-02 now reads it from the real fixture.flac.) The
        // compilation flag needs no chain: Vorbis `COMPILATION`, mp4 `cpil` and ID3 `TCMP` (and
        // `TXXX:compilation`) all arrive as `compilation`.
        let meta = TrackMetadata(
            title: tags["title"],
            artistName: tags["artist"],
            albumTitle: tags["album"],
            albumArtistName: tags["album_artist"] ?? tags["albumartist"] ?? tags["album artist"],
            isCompilation: Self.parseFlag(tags["compilation"]),
            year: Self.parseYear(tags["date"] ?? tags["year"] ?? tags["originaldate"]),
            trackNo: Self.parseLeadingInt(tags["track"] ?? tags["tracknumber"]),
            discNo: Self.parseLeadingInt(tags["disc"] ?? tags["discnumber"]),
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
