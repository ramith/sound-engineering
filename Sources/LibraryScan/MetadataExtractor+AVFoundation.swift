// MetadataExtractor+AVFoundation — the Apple-native extraction path (design §2).
//
// Primary for mp3/m4a/aac/alac/aiff/wav. Uses async `AVAsset.load` (required in Swift 6):
// tags via `AVMetadataItem` (common → iTunes → ID3 identifier precedence), duration via
// `.duration`, and audio properties from the audio track's `CMAudioFormatDescription`.
// Everything non-Sendable (the asset, the items) stays local to this async function.

import AVFoundation
import CoreMedia
import Foundation
import LibraryStore

extension MetadataExtractor {
    /// Extract via AVFoundation. `nil` ONLY when the asset can't be read at all (the
    /// `.metadata` load throws — vanished/unreadable). A readable-but-tagless file still
    /// returns a TrackMetadata carrying whatever duration/format could be read.
    func avFoundationExtract(_ url: URL) async -> ExtractedMetadata? {
        let asset = AVURLAsset(url: url)
        guard let items = try? await asset.load(.metadata) else { return nil }

        let props = await Self.audioProperties(asset)
        let meta = TrackMetadata(
            title: await Self.firstString(items, [
                .commonIdentifierTitle, .iTunesMetadataSongName, .id3MetadataTitleDescription,
            ]),
            artistName: await Self.firstString(items, [
                .commonIdentifierArtist, .iTunesMetadataArtist, .id3MetadataLeadPerformer,
            ]),
            albumTitle: await Self.firstString(items, [
                .commonIdentifierAlbumName, .iTunesMetadataAlbum, .id3MetadataAlbumTitle,
            ]),
            albumArtistName: await Self.firstString(items, Self.albumArtistIdentifiers),
            isCompilation: await Self.compilationFlag(items),
            year: Self.parseYear(await Self.firstString(items, [
                .commonIdentifierCreationDate, .iTunesMetadataReleaseDate,
                .id3MetadataRecordingTime, .id3MetadataYear,
            ])),
            trackNo: await Self.trackOrDiscNumber(
                items, stringIdentifiers: [.iTunesMetadataTrackNumber, .id3MetadataTrackNumber], binaryAtom: "trkn"
            ),
            discNo: await Self.trackOrDiscNumber(
                items, stringIdentifiers: [.iTunesMetadataDiscNumber, .id3MetadataPartOfASet], binaryAtom: "disk"
            ),
            genres: Self.parseGenres(await Self.firstString(items, [
                .iTunesMetadataUserGenre, .iTunesMetadataPredefinedGenre, .id3MetadataContentType,
            ])),
            durationMs: await Self.durationMs(asset),
            sampleRate: props.sampleRate,
            bitDepth: props.bitDepth,
            channels: props.channels
        )
        return ExtractedMetadata(metadata: meta, artwork: await Self.artwork(items))
    }

    /// Audio-stream properties from the format description (any nil when unavailable).
    struct AudioProperties {
        let sampleRate: Int?
        let bitDepth: Int?
        let channels: Int?
    }

    // MARK: - Field helpers

    /// Where the album-artist tag lives: the iTunes `aART` atom, ID3 `TPE2`, and the Vorbis
    /// `ALBUMARTIST` / `ALBUM ARTIST` comments (ogg/opus/flac when FFmpeg is absent — C2 fix
    /// round, C7; no SDK constants, so the raw `vorb/…` identifiers).
    static let albumArtistIdentifiers: [AVMetadataIdentifier] = [
        .iTunesMetadataAlbumArtist, .id3MetadataBand,
        AVMetadataIdentifier(rawValue: "vorb/ALBUMARTIST"), AVMetadataIdentifier(rawValue: "vorb/ALBUM ARTIST"),
    ]

    /// Where the compilation flag lives, by container (S10.8 C2): the iTunes `cpil` atom (m4a),
    /// iTunes' ID3 `TCMP` frame (mp3 — no SDK constant, so the raw `id3/TCMP` identifier) and
    /// the Vorbis `COMPILATION` / `ITUNESCOMPILATION` comments (flac/ogg/opus when FFmpeg is
    /// absent). `firstString` reads a `cpil` boolean atom through its number value ("1").
    static let compilationIdentifiers: [AVMetadataIdentifier] = [
        .iTunesMetadataDiscCompilation,
        AVMetadataIdentifier(rawValue: "id3/TCMP"),
        AVMetadataIdentifier(rawValue: "vorb/COMPILATION"),
        AVMetadataIdentifier(rawValue: "vorb/ITUNESCOMPILATION"),
    ]

    /// The ID3 user-text frame (`TXXX`), whose DESCRIPTION names the value.
    static let id3UserTextIdentifier = AVMetadataIdentifier(rawValue: "id3/TXXX")

    /// The compilation flag: any of its dedicated keys, or an mp3 `TXXX` frame described `TCMP` or
    /// `compilation` (C2 fix round, C7 — taggers that can't write a `TCMP` frame write that),
    /// saying yes.
    static func compilationFlag(_ items: [AVMetadataItem]) async -> Bool {
        if parseFlag(await firstString(items, compilationIdentifiers)) {
            return true
        }
        for item in AVMetadataItem.metadataItems(from: items, filteredByIdentifier: id3UserTextIdentifier) {
            let description = (try? await item.load(.extraAttributes))??[.info] as? String
            guard let description, compilationUserTextNames.contains(description.lowercased()) else { continue }
            if parseFlag(try? await item.load(.stringValue)) {
                return true
            }
        }
        return false
    }

    /// The first non-empty value across `identifiers` (in precedence order), as a string.
    /// Falls back to `numberValue` because iTunes binary atoms — `trkn` (track) / `disk`
    /// (disc) — have NO `stringValue`; their number is stringified so `parseLeadingInt`
    /// still yields the count.
    static func firstString(_ items: [AVMetadataItem], _ identifiers: [AVMetadataIdentifier]) async -> String? {
        for identifier in identifiers {
            for item in AVMetadataItem.metadataItems(from: items, filteredByIdentifier: identifier) {
                if let value = try? await item.load(.stringValue) {
                    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        return trimmed
                    }
                }
                if let number = try? await item.load(.numberValue) {
                    return number.stringValue
                }
            }
        }
        return nil
    }

    /// Whole-millisecond duration (rounded), or 0 if unknown/indefinite.
    static func durationMs(_ asset: AVURLAsset) async -> Int64 {
        guard let duration = try? await asset.load(.duration), duration.isNumeric else { return 0 }
        let seconds = CMTimeGetSeconds(duration)
        guard seconds.isFinite, seconds > 0 else { return 0 }
        return Int64((seconds * 1000).rounded())
    }

    /// Audio properties from the first audio track's stream description; any nil when
    /// unavailable (missing track, or compressed → mBitsPerChannel 0 → bitDepth nil).
    static func audioProperties(_ asset: AVURLAsset) async -> AudioProperties {
        guard let track = try? await asset.loadTracks(withMediaType: .audio).first,
              let descriptions = try? await track.load(.formatDescriptions),
              let description = descriptions.first,
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(description)?.pointee else {
            return AudioProperties(sampleRate: nil, bitDepth: nil, channels: nil)
        }
        return AudioProperties(
            sampleRate: asbd.mSampleRate > 0 ? Int(asbd.mSampleRate) : nil,
            bitDepth: asbd.mBitsPerChannel > 0 ? Int(asbd.mBitsPerChannel) : nil,
            channels: asbd.mChannelsPerFrame > 0 ? Int(asbd.mChannelsPerFrame) : nil
        )
    }

    /// Track/disc number across taggers: an ID3/string atom ("3/12" → 3) first, else the
    /// iTunes `trkn`/`disk` BINARY atom — 16-bit big-endian `[reserved, number, total, …]`,
    /// so the number is bytes 2–3 (these atoms have NO string/number value).
    static func trackOrDiscNumber(
        _ items: [AVMetadataItem], stringIdentifiers: [AVMetadataIdentifier], binaryAtom: String
    ) async -> Int? {
        if let parsed = parseLeadingInt(await firstString(items, stringIdentifiers)) {
            return parsed
        }
        guard let data = await firstDataValue(items, atomSuffix: binaryAtom), data.count >= 4 else { return nil }
        let bytes = [UInt8](data.prefix(4))
        return Int(bytes[2]) << 8 | Int(bytes[3])
    }

    /// The first non-empty `.dataValue` of an item whose identifier ends with `atomSuffix`
    /// (the raw mp4 atom name — "trkn"/"disk"/"covr"), for BINARY iTunes atoms.
    static func firstDataValue(_ items: [AVMetadataItem], atomSuffix: String) async -> Data? {
        for item in items where item.identifier?.rawValue.hasSuffix(atomSuffix) ?? false {
            if let data = try? await item.load(.dataValue), !data.isEmpty {
                return data
            }
        }
        return nil
    }

    /// The first embedded cover art (≤ `maxArtBytes`), sniffed for its UTI, or nil. Reads
    /// the common-key artwork (mp3 APIC / most formats) then the iTunes `covr` data atom.
    static func artwork(_ items: [AVMetadataItem]) async -> ExtractedArtwork? {
        for item in AVMetadataItem.metadataItems(from: items, filteredByIdentifier: .commonIdentifierArtwork) {
            if let data = try? await item.load(.dataValue), !data.isEmpty, data.count <= maxArtBytes {
                return ExtractedArtwork(data: data, uti: utiFromSniff(data))
            }
        }
        if let data = await firstDataValue(items, atomSuffix: "covr"), data.count <= maxArtBytes {
            return ExtractedArtwork(data: data, uti: utiFromSniff(data))
        }
        return nil
    }
}
