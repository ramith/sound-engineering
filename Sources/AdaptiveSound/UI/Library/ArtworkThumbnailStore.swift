import AppKit
import Foundation
import ImageIO
import LibraryScan
import LibraryStore

// MARK: - Artwork thumbnail loader (S9.4, design §5)

/// Loads cover-art thumbnails for the browse grid from the S8.3 on-disk cache.
///
/// These are LOCAL `<hash>.thumb.jpg` files (not URLs) → no `AsyncImage`. Swift-6-clean
/// by inversion: `NSImage` (not `Sendable`) never leaves `@MainActor`; the only thing
/// crossing the isolation boundary is a freshly-created `CGImage` returned `sending` from
/// an off-main decode. An `NSCache` gives free memory-pressure eviction.
@MainActor
final class ArtworkThumbnailStore {
    private let cache = NSCache<NSString, NSImage>()
    private var paths: [String: String] = [:] // content-hash → original cache_path
    private let store: LibraryStore

    init(store: LibraryStore) {
        self.store = store
        cache.countLimit = 512
    }

    /// Warm the hash→path map for a page of keys in ONE batched query (avoids N queries
    /// for N cells). Idempotent; only fetches keys not already resolved.
    func warm(keys: [String]) async {
        let missing = keys.filter { paths[$0] == nil }
        guard !missing.isEmpty, let map = try? await store.artworkCachePaths(forKeys: missing) else {
            return
        }
        paths.merge(map) { _, new in new }
    }

    /// Synchronous same-actor cache peek — lets a view show a hit immediately (no
    /// placeholder flash) before awaiting the async path.
    func cachedImage(forKey key: String) -> NSImage? {
        cache.object(forKey: key as NSString)
    }

    /// The thumbnail for `key` at up to `maxPixel`, or `nil` (→ placeholder) when the key
    /// is unwarmed / has no cache row / the file is missing or undecodable (never throws).
    func image(forKey key: String, maxPixel: Int) async -> NSImage? {
        if let hit = cache.object(forKey: key as NSString) { return hit }
        // Resolve the path; warm on demand if this key wasn't in a prior page warm.
        if paths[key] == nil { await warm(keys: [key]) }
        guard let original = paths[key] else { return nil }
        let thumb = ArtworkCache.thumbnailPath(forOriginal: original)
        guard let cg = await Self.decode(path: thumb, maxPixel: maxPixel) else { return nil }
        let image = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        cache.setObject(image, forKey: key as NSString, cost: cg.width * cg.height * 4)
        return image
    }

    /// Decode + downsample a thumbnail JPEG OFF the main actor. `@concurrent` pins it off-main
    /// (not relying on the SE-0338 default); the freshly-created `CGImage` is a disconnected
    /// region, so `sending` lets it cross back to `@MainActor` race-free (final-gate #12).
    @concurrent
    private nonisolated static func decode(path: String, maxPixel: Int) async -> sending CGImage? {
        guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil) else {
            return nil
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}
