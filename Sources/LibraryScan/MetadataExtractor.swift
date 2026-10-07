// MetadataExtractor — read embedded tags + cover art from ONE file (S8.3, design §2).
//
// A stateless `Sendable` value type; a pure PRODUCER — it never touches `LibraryStore`.
// The MetadataScanner pass calls `extract`, then hands the result to the store's
// `applyExtractedResult` + the ArtworkCache. AVFoundation is primary (mp3/m4a/aac/alac/
// aiff/wav); the FFmpeg dlopen backend (via the AudioDSP C bridge) fills FLAC/Ogg/Opus and
// anything AVFoundation returns empty for — mirroring the decode path's fallback model.
//
// `extract` is non-throwing + Optional: every failure is "skip/partial", never
// caller-actionable (mirrors LibraryScanner.makeScannedFile). `nil` means ONLY
// unreadable/vanished; a readable-but-tagless file returns a TrackMetadata carrying just
// duration/format. Nothing non-Sendable (AVAsset, AVMetadataItem, CGImage) escapes.

import AVFoundation
import Foundation
import LibraryStore

/// Embedded cover art as extracted: raw container bytes + the source UTI (the
/// ArtworkCache hashes/decodes/thumbnails; the extractor does no image work).
public struct ExtractedArtwork: Sendable, Equatable {
    public let data: Data
    public let uti: String?

    public init(data: Data, uti: String?) {
        self.data = data
        self.uti = uti
    }
}

/// One file's extracted tags + optional embedded art (both `Sendable`).
public struct ExtractedMetadata: Sendable, Equatable {
    public let metadata: TrackMetadata
    public let artwork: ExtractedArtwork?

    public init(metadata: TrackMetadata, artwork: ExtractedArtwork?) {
        self.metadata = metadata
        self.artwork = artwork
    }
}

/// The extraction seam — a protocol so the metadata pass + tests can inject a stub /
/// counting extractor (the concrete `MetadataExtractor` is the production impl).
public protocol MetadataExtracting: Sendable {
    func extract(from url: URL) async -> ExtractedMetadata?
}

public struct MetadataExtractor: MetadataExtracting {
    /// Embedded art above this size is dropped (art is best-effort; protects pass memory
    /// against a pathological multi-MB cover — design §2 edge cases).
    static let maxArtBytes = 32 * 1024 * 1024

    public init() {}

    /// Read `url`'s tags + embedded art. Extension-routed (design §4): the Vorbis-comment
    /// formats (flac, ogg/oga, opus) → FFmpeg first (AVFoundation reads their core tags but not
    /// the album artist or compilation keys — S10.8 C2 fix round, C7), others → AVFoundation
    /// first with an FFmpeg cross-fill when the core fields came back empty. `nil` ONLY for
    /// unreadable/vanished.
    public func extract(from url: URL) async -> ExtractedMetadata? {
        if Self.vorbisCommentExtensions.contains(url.pathExtension.lowercased()) {
            // FFmpeg first; if it is absent/unavailable, best-effort AVFoundation.
            if let viaFFmpeg = ffmpegExtract(url) {
                return viaFFmpeg
            }
            return await avFoundationExtract(url)
        }
        guard let viaApple = await avFoundationExtract(url) else {
            // AVFoundation could not open it → last-chance FFmpeg (nil if it also can't).
            return ffmpegExtract(url)
        }
        if viaApple.metadata.hasNoCoreTags, let viaFFmpeg = ffmpegExtract(url) {
            return viaApple.merged(with: viaFFmpeg)
        }
        return viaApple
    }

    /// The containers whose tags are Vorbis comments — FFmpeg-first.
    static let vorbisCommentExtensions: Set<String> = ["flac", "ogg", "oga", "opus"]
}

// MARK: - Merge (AVFoundation primary, FFmpeg cross-fill)

extension TrackMetadata {
    /// True when the three identifying text tags are all absent — the trigger for a
    /// cross-fill FFmpeg pass on an AVFoundation-primary format.
    var hasNoCoreTags: Bool {
        title == nil && artistName == nil && albumTitle == nil
    }

    /// A copy preferring `self`'s present fields, filling each nil/empty/zero from `other`.
    func filling(from other: TrackMetadata) -> TrackMetadata {
        TrackMetadata(
            title: title ?? other.title,
            artistName: artistName ?? other.artistName,
            albumTitle: albumTitle ?? other.albumTitle,
            albumArtistName: albumArtistName ?? other.albumArtistName,
            isCompilation: isCompilation || other.isCompilation,
            year: year ?? other.year,
            trackNo: trackNo ?? other.trackNo,
            discNo: discNo ?? other.discNo,
            genres: genres.isEmpty ? other.genres : genres,
            durationMs: durationMs != 0 ? durationMs : other.durationMs,
            sampleRate: sampleRate ?? other.sampleRate,
            bitDepth: bitDepth ?? other.bitDepth,
            channels: channels ?? other.channels
        )
    }
}

extension ExtractedMetadata {
    /// Merge `other` (FFmpeg) into `self` (AVFoundation): AVFoundation wins per-field,
    /// FFmpeg fills the gaps; art is `self`'s if present, else `other`'s.
    func merged(with other: ExtractedMetadata) -> ExtractedMetadata {
        ExtractedMetadata(
            metadata: metadata.filling(from: other.metadata),
            artwork: artwork ?? other.artwork
        )
    }
}

// MARK: - Shared parsing helpers (used by both extraction paths)

extension MetadataExtractor {
    /// The first 4 consecutive digits of a date/year string → `Int`, or nil.
    static func parseYear(_ text: String?) -> Int? {
        guard let text else { return nil }
        var digits = ""
        for character in text where character.isNumber {
            digits.append(character)
            if digits.count == 4 {
                return Int(digits)
            }
        }
        return nil
    }

    /// The leading integer of a `"3/12"`-style track/disc field → `Int`, or nil.
    static func parseLeadingInt(_ text: String?) -> Int? {
        guard let head = text?.split(separator: "/").first else { return nil }
        return Int(head.trimmingCharacters(in: .whitespaces))
    }

    /// The compilation flag's user-text names (C2 fix round, C7), lowercased: iTunes' `TCMP` and a
    /// plain `compilation` in an mp3 `TXXX` frame, and the Vorbis `ITUNESCOMPILATION` comment.
    /// (The dedicated keys — mp4 `cpil`, ID3 `TCMP`, Vorbis `COMPILATION` — are read too.)
    static let compilationUserTextNames: Set<String> = ["tcmp", "compilation", "itunescompilation"]

    /// A boolean tag (the compilation flag) → `true` only for an explicit yes: `1`, `true` or
    /// `yes`, any case, whitespace-trimmed. Absent, `0` or anything else → `false`. ONE parser
    /// for both extraction paths (S10.8 C2), so the two never disagree on a flag.
    static func parseFlag(_ text: String?) -> Bool {
        guard let text else { return false }
        switch text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "1", "true", "yes": return true
        default: return false
        }
    }

    /// Split a genre tag on `;`/`/` into trimmed, non-empty names.
    static func parseGenres(_ text: String?) -> [String] {
        guard let text else { return [] }
        return text.split(whereSeparator: { $0 == ";" || $0 == "/" })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    /// A UTI for a known image MIME string (the two embedded-art formats we tag).
    static func utiFromMime(_ mime: String) -> String? {
        switch mime {
        case "image/jpeg": return "public.jpeg"
        case "image/png": return "public.png"
        default: return nil
        }
    }

    /// Sniff a UTI from an image blob's magic bytes (JPEG / PNG), or nil. Uses a
    /// 0-indexed prefix copy (a `Data` slice is not guaranteed to start at index 0).
    static func utiFromSniff(_ data: Data) -> String? {
        let head = [UInt8](data.prefix(8))
        if head.count >= 3, head[0] == 0xFF, head[1] == 0xD8, head[2] == 0xFF {
            return "public.jpeg"
        }
        if head.count >= 8, head[0] == 0x89, head[1] == 0x50, head[2] == 0x4E, head[3] == 0x47 {
            return "public.png"
        }
        return nil
    }
}
