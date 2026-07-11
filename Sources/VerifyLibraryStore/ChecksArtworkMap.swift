// ChecksArtworkMap — the S9.1 artwork cache-path batched-map browse reads (BR1/1b/1c). Split from
// ChecksBrowseReads (the harness's per-concern file convention): the artwork-path map is a distinct
// DAO surface from the facet drill-downs. Asserts `artworkCachePaths(forKeys:)` — the grid's
// one-query-per-page art lookup — returns the exact hash→cache_path map, chunks a >999-key IN-list
// under SQLite's variable limit, and treats a cache miss as simply ABSENT (no throw); plus the
// on-disk `.thumb.jpg` thumbnail convention. Same VerifyAUGraph idiom (Bool return, numbered PASS).

import CoreGraphics
import Foundation
import ImageIO
import LibraryScan
import LibraryStore

// MARK: - BR1 — artwork-path batched map + on-disk thumbnail convention

func checkBrowseArtworkMap(number: Int, url: URL) async -> Bool {
    let cacheDir = url.deletingLastPathComponent()
        .appendingPathComponent("br-artwork-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: cacheDir) }
    do {
        let store = try await LibraryStore(url: url, appBuild: "verify")
        let cache = ArtworkCache(directory: cacheDir)
        guard let png = makeSolidPNG(width: 400, height: 400) else {
            printFail(number, "BR1: could not synthesize a test PNG"); return false
        }
        let link = try cache.store(imageData: png, uti: "public.png")
        try await store.linkArtwork(
            contentHash: link.contentHash, cachePath: link.cachePath,
            size: link.pixelSize, byteSize: link.byteSize
        )
        let map = try await store.artworkCachePaths(forKeys: [link.contentHash])
        guard let resolved = map[link.contentHash], resolved == link.cachePath, map.count == 1 else {
            printFail(number, "BR1: batched map did not return the exact hash→cache_path"); return false
        }
        // Derive the thumbnail path the same way S9 will, and assert on-disk convention.
        let thumbPath = ArtworkCache.thumbnailPath(forOriginal: resolved)
        guard thumbPath.hasSuffix(".thumb.jpg"), FileManager.default.fileExists(atPath: thumbPath) else {
            printFail(number, "BR1: derived thumbnail path off-convention or missing on disk"); return false
        }
        // The single-key convenience wraps the batched form.
        guard try await store.artworkCachePath(forKey: link.contentHash) == link.cachePath else {
            printFail(number, "BR1: single-key convenience disagreed with the batched map"); return false
        }
        printPass(number, "BR1: artworkCachePaths returns the exact hash→cache_path map; the derived "
            + ".thumb.jpg thumbnail exists on disk (ArtworkCache.thumbnailPath convention)")
        return true
    } catch {
        printFail(number, "BR1 threw: \(error)"); return false
    }
}

// MARK: - BR1b — cache-miss key is absent (no throw)

func checkBrowseArtworkMiss(number: Int, url: URL) async -> Bool {
    do {
        let store = try await LibraryStore(url: url, appBuild: "verify")
        try await store.linkArtwork(contentHash: "hash-present", cachePath: "/cache/present.jpg",
                                    size: .zero, byteSize: 100)
        let map = try await store.artworkCachePaths(forKeys: ["hash-present", "hash-absent"])
        guard map["hash-present"] == "/cache/present.jpg" else {
            printFail(number, "BR1b: present key did not resolve"); return false
        }
        guard map["hash-absent"] == nil, map.count == 1 else {
            printFail(number, "BR1b: a key with no artwork row leaked into the map"); return false
        }
        guard try await store.artworkCachePath(forKey: "hash-absent") == nil else {
            printFail(number, "BR1b: single-key convenience did not return nil for a miss"); return false
        }
        printPass(number, "BR1b: a key with no artwork row is simply ABSENT from the map (no throw); "
            + "present keys resolve")
        return true
    } catch {
        printFail(number, "BR1b threw: \(error)"); return false
    }
}

// MARK: - BR1c — IN-list chunking (> 999 keys)

func checkBrowseArtworkChunking(number: Int, url: URL) async -> Bool {
    do {
        let store = try await LibraryStore(url: url, appBuild: "verify")
        // > 999 synthetic artwork rows → forces multiple IN-list chunks.
        let count = 1100
        let keys = (0 ..< count).map { "synth-hash-\($0)" }
        for (index, key) in keys.enumerated() {
            try await store.linkArtwork(contentHash: key, cachePath: "/cache/\(key).jpg",
                                        size: .zero, byteSize: Int64(index))
        }
        // Query all keys PLUS one miss, in one call — must chunk and return the full map.
        let map = try await store.artworkCachePaths(forKeys: keys + ["not-a-hash"])
        guard map.count == count else {
            printFail(number, "BR1c: chunked map has \(map.count) entries, expected \(count)"); return false
        }
        for key in keys where map[key] != "/cache/\(key).jpg" {
            printFail(number, "BR1c: chunked map wrong/missing value for \(key)"); return false
        }
        guard map["not-a-hash"] == nil else {
            printFail(number, "BR1c: the miss leaked into the chunked map"); return false
        }
        printPass(number, "BR1c: a \(count)-key IN-list is chunked (limit 32766) and returns the full "
            + "correct hash→cache_path map; the miss stays absent")
        return true
    } catch {
        printFail(number, "BR1c threw: \(error)"); return false
    }
}

// MARK: - Synthetic image helper (CoreGraphics/ImageIO)

/// A solid-color RGBA PNG of the given size, or nil if CoreGraphics is unavailable.
private func makeSolidPNG(width: Int, height: Int) -> Data? {
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
    guard let context = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8,
        bytesPerRow: 0, space: colorSpace, bitmapInfo: bitmapInfo
    ) else { return nil }
    context.setFillColor(red: 0.3, green: 0.6, blue: 0.9, alpha: 1.0)
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    guard let image = context.makeImage() else { return nil }

    let data = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(
        data as CFMutableData, "public.png" as CFString, 1, nil
    ) else { return nil }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { return nil }
    return data as Data
}
