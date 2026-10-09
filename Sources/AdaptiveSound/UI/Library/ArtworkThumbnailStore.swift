import AppKit
import Foundation
import ImageIO
import LibraryBrowseKit
import LibraryScan
import LibraryStore

// MARK: - Artwork thumbnail loader (S9.4, design §5)

/// Loads cover-art thumbnails for the browse grid from the S8.3 on-disk cache.
///
/// These are LOCAL `<hash>.thumb.jpg` files (not URLs) → no `AsyncImage`. Swift-6-clean
/// by inversion: `NSImage` (not `Sendable`) never leaves `@MainActor`; the only thing
/// crossing the isolation boundary is a freshly-created `CGImage` returned `sending` from
/// an off-main decode. An `NSCache` gives free memory-pressure eviction, bounded by cost.
///
/// The cache is UPGRADE-ONLY (S10.8 D fix round, `ThumbnailUpgrade`): an entry remembers the
/// largest request it serves, and a bigger request re-decodes and replaces it, so a cover first
/// decoded small (a 28-pt Recently Played row) never leaves the 160-pt grid tile showing it soft
/// all session. A smaller request is served from a bigger entry, and a decode never replaces a
/// bigger one.
@MainActor
final class ArtworkThumbnailStore {
    /// One decoded cover and the largest request it serves (`ThumbnailUpgrade.servesUpTo`).
    private final class Thumbnail {
        let image: NSImage
        let servesUpTo: Int

        init(image: NSImage, servesUpTo: Int) {
            self.image = image
            self.servesUpTo = servesUpTo
        }
    }

    /// One in-flight path lookup and the keys it resolves.
    private struct WarmBatch {
        let keys: Set<String>
        let task: Task<Void, Never>
    }

    /// About 128 MB of decoded pixels (4 bytes each) — some 500 grid tiles at 2×.
    private static let cacheCostLimit = 128 * 1024 * 1024

    private let cache = NSCache<NSString, Thumbnail>()
    private var paths: [String: String] = [:] // content-hash → original cache_path
    /// The lookups in flight, so a key already being resolved is awaited, never queried twice.
    private var warming: [UUID: WarmBatch] = [:]
    private let store: LibraryStore

    init(store: LibraryStore) {
        self.store = store
        cache.totalCostLimit = Self.cacheCostLimit
    }

    /// Resolve the hash→path map for `keys` in ONE batched query (avoids N queries for N cells),
    /// SINGLE-FLIGHT: keys another lookup is already resolving are awaited, not queried again.
    /// Returns once every requested key's lookup has finished.
    func warm(keys: [String]) async {
        let requested = Set(keys)
        let inFlight = warming.values.reduce(into: Set<String>()) { $0.formUnion($1.keys) }
        let missing = requested.filter { paths[$0] == nil && !inFlight.contains($0) }
        if !missing.isEmpty {
            let id = UUID()
            let store = store
            let task = Task { [weak self] in
                let map = try? await store.artworkCachePaths(forKeys: Array(missing))
                self?.finishWarm(id, with: map ?? [:])
            }
            warming[id] = WarmBatch(keys: missing, task: task)
        }
        for batch in warming.values where !batch.keys.isDisjoint(with: requested) {
            await batch.task.value
        }
    }

    private func finishWarm(_ id: UUID, with map: [String: String]) {
        paths.merge(map) { _, new in new }
        warming[id] = nil
    }

    /// Synchronous same-actor cache peek, whatever size it holds — lets a view show a hit at once
    /// (no placeholder flash), even as an interim image while a sharper decode is on its way.
    func cachedImage(forKey key: String) -> NSImage? {
        cache.object(forKey: key as NSString)?.image
    }

    /// The thumbnail for `key` at up to `maxPixel`, or `nil` (→ placeholder) when the key has no
    /// cache row or the file is missing or undecodable (never throws). A cached entry that serves
    /// `maxPixel` is returned at once; a smaller one is re-decoded at `maxPixel` and replaced.
    func image(forKey key: String, maxPixel: Int) async -> NSImage? {
        let cached = cache.object(forKey: key as NSString)
        if let cached, ThumbnailUpgrade.serves(cached.servesUpTo, request: maxPixel) {
            return cached.image
        }
        // Resolve the path; a key no batch warmed is looked up now (or awaited, if in flight).
        if paths[key] == nil {
            await warm(keys: [key])
        }
        guard let original = paths[key] else { return cached?.image }
        let thumb = ArtworkCache.thumbnailPath(forOriginal: original)
        guard let cg = await Self.decode(path: thumb, maxPixel: maxPixel) else { return cached?.image }
        let decoded = Thumbnail(
            image: NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height)),
            servesUpTo: ThumbnailUpgrade.servesUpTo(decodedSide: max(cg.width, cg.height), requested: maxPixel)
        )
        // Upgrade only: a bigger decode that landed meanwhile stays.
        let current = cache.object(forKey: key as NSString)
        if let current, !ThumbnailUpgrade.replaces(cached: current.servesUpTo, with: decoded.servesUpTo) {
            return current.image
        }
        cache.setObject(decoded, forKey: key as NSString, cost: cg.width * cg.height * 4)
        return decoded.image
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
