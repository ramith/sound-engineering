// ArtworkCache — content-addressed cover-art cache (S8.3, design §4).
//
// Cover-art bytes → sha256 → an on-disk `<hash>.<ext>` original + a `<hash>.thumb.jpg`
// downscaled thumbnail (ImageIO), deduped by hash (shared album art = ONE cached pair).
// Returns the `ArtworkLink` (defined in LibraryStore to avoid a cycle) that the store's
// `attachArtwork`/`linkArtwork` consume. The metadata pass writes here off the actor.
//
// Best-effort thumbnail: undecodable art still caches the original (pixelSize `.zero`, no
// thumb) — never throws on the image work (mirrors the scanner's skip discipline). The
// caller (MetadataScanner) removes files on an orphan sweep via `removeFiles`.

import CoreGraphics
import CryptoKit
import Foundation
import ImageIO
import LibraryStore

public struct ArtworkCache: Sendable {
    /// Max edge (px) of the generated thumbnail — retina-grid friendly, small for a grid
    /// of hundreds. The original is kept full-resolution for detail views.
    static let thumbnailMaxPixel = 512
    /// JPEG quality for the thumbnail (visually lossless at grid sizes, small on disk).
    static let thumbnailQuality = 0.82

    private let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    /// Content-address `imageData` (sha256), writing the ORIGINAL (`<hash>.<ext>`, ext from
    /// `uti`) + a thumbnail (`<hash>.thumb.jpg`), deduped by hash — a byte-identical original
    /// already on disk skips both writes. Returns the descriptor `attachArtwork` consumes.
    public func store(imageData: Data, uti: String?) throws -> ArtworkLink {
        let hash = Self.sha256Hex(imageData)
        let originalURL = directory.appendingPathComponent(
            "\(hash).\(Self.fileExtension(forUTI: uti))", isDirectory: false
        )
        // pixelSize is a cheap HEADER read (no full-pixel decode), taken from the in-memory
        // bytes — never re-read from the file, so it can't observe a concurrent writer's
        // half-written file.
        let pixelSize = Self.pixelSize(of: imageData) // `.zero` if undecodable
        // Content-addressed dedup: a byte-identical original already on disk skips the write
        // AND the expensive thumbnail decode/downscale (the real cost — the header read above
        // is negligible). Concurrent callers (the pass fans `store` out across TaskGroup
        // children for shared album art) may race here on the SAME hash/path — deliberately
        // safe: identical bytes ⇒ any duplicate write is idempotent, so no lock is needed.
        if !FileManager.default.fileExists(atPath: originalURL.path) {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try imageData.write(to: originalURL)
            Self.writeThumbnail(from: imageData, to: Self.thumbnailURL(forOriginal: originalURL))
        }
        return ArtworkLink(
            contentHash: hash, cachePath: originalURL.path,
            pixelSize: pixelSize, byteSize: Int64(imageData.count)
        )
    }

    /// The derived thumbnail path for a stored original path (a PURE function — the original
    /// with its extension replaced by `.thumb.jpg`). S9 derives the thumb the same way, so
    /// no thumbnail path is stored in the schema.
    public static func thumbnailPath(forOriginal cachePath: String) -> String {
        thumbnailURL(forOriginal: URL(fileURLWithPath: cachePath)).path
    }

    /// Remove the original + derived thumbnail for a swept (orphaned) artwork. Best-effort.
    /// The thumbnail path is a pure function of `cachePath`, so the content hash isn't needed.
    public func removeFiles(cachePath: String) {
        let original = URL(fileURLWithPath: cachePath)
        try? FileManager.default.removeItem(at: original)
        try? FileManager.default.removeItem(at: Self.thumbnailURL(forOriginal: original))
    }
}

// MARK: - Hashing / paths / image work (pure helpers)

extension ArtworkCache {
    /// Lowercase-hex sha256 of `data` — the dedup key + `artwork.content_hash`.
    static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// The original's file extension for a source UTI (jpg/png, else a neutral `img`).
    static func fileExtension(forUTI uti: String?) -> String {
        switch uti {
        case "public.jpeg": return "jpg"
        case "public.png": return "png"
        default: return "img"
        }
    }

    /// `<dir>/<hash>.<ext>` → `<dir>/<hash>.thumb.jpg`.
    static func thumbnailURL(forOriginal original: URL) -> URL {
        let stem = original.deletingPathExtension().lastPathComponent
        return original.deletingLastPathComponent()
            .appendingPathComponent("\(stem).thumb.jpg", isDirectory: false)
    }

    /// The image's pixel dimensions, or `.zero` if it cannot be decoded.
    static func pixelSize(of data: Data) -> CGSize {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else {
            return .zero
        }
        return CGSize(width: width, height: height)
    }

    /// Downscale `data` to a ≤`thumbnailMaxPixel` JPEG at `url` (best-effort; a no-op if the
    /// source is undecodable or the destination can't be created — never throws).
    static func writeThumbnail(from data: Data, to url: URL) {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return }
        let thumbOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: thumbnailMaxPixel,
        ]
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbOptions as CFDictionary),
              let destination = CGImageDestinationCreateWithURL(
                  url as CFURL, "public.jpeg" as CFString, 1, nil
              ) else { return }
        CGImageDestinationAddImage(
            destination, thumbnail, [kCGImageDestinationLossyCompressionQuality: thumbnailQuality] as CFDictionary
        )
        CGImageDestinationFinalize(destination)
    }
}
