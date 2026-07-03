// ChecksArtworkCache — S8.3 Slice-3 cases: the content-addressed cover-art cache
// (sha256 dedup + original + ImageIO thumbnail). Drives the REAL ArtworkCache against a
// REAL temp dir with a synthesized PNG (CoreGraphics) — no external fixtures needed.
// Same VerifyAUGraph idiom (Bool return, numbered PASS/FAIL).

import CoreGraphics
import Foundation
import ImageIO
import LibraryScan

// MARK: - w — ArtworkCache dedup + thumbnail + removeFiles + undecodable

func checkArtworkCache(number: Int, url: URL) async -> Bool {
    let cacheDir = url.deletingLastPathComponent()
        .appendingPathComponent("artwork-cache-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: cacheDir) }
    let cache = ArtworkCache(directory: cacheDir)
    let fileManager = FileManager.default

    guard let png = makeSolidPNG(width: 800, height: 600) else {
        printFail(number, "artwork-cache: could not synthesize a test PNG"); return false
    }
    do {
        let link = try cache.store(imageData: png, uti: "public.png")
        let thumbPath = ArtworkCache.thumbnailPath(forOriginal: link.cachePath)
        guard fileManager.fileExists(atPath: link.cachePath), fileManager.fileExists(atPath: thumbPath) else {
            printFail(number, "artwork-cache: original and/or thumbnail not written"); return false
        }
        guard link.byteSize == Int64(png.count),
              link.pixelSize.width == 800, link.pixelSize.height == 600 else {
            printFail(number, "artwork-cache: link size/dims wrong (\(link.byteSize), \(link.pixelSize))")
            return false
        }
        guard let thumbMax = thumbnailMaxEdge(atPath: thumbPath), thumbMax <= 512 else {
            printFail(number, "artwork-cache: thumbnail max edge > 512 or unreadable"); return false
        }
        // Dedup: identical bytes → same hash/path (content-addressed).
        let again = try cache.store(imageData: png, uti: "public.png")
        guard again.cachePath == link.cachePath, again.contentHash == link.contentHash else {
            printFail(number, "artwork-cache: dedup produced a different path/hash"); return false
        }
        // removeFiles clears original + derived thumbnail.
        cache.removeFiles(forContentHash: link.contentHash, cachePath: link.cachePath)
        guard !fileManager.fileExists(atPath: link.cachePath), !fileManager.fileExists(atPath: thumbPath) else {
            printFail(number, "artwork-cache: removeFiles left files behind"); return false
        }
        guard try checkUndecodableArt(cache, number: number) else { return false }

        printPass(number, "ArtworkCache: sha256 dedup writes ONE <hash>.<ext> original + a ≤512px "
            + "<hash>.thumb.jpg (dims + byteSize in the link); removeFiles clears both; undecodable "
            + "art → original cached, no thumb, pixelSize .zero (best-effort)")
        return true
    } catch {
        printFail(number, "artwork-cache threw: \(error)"); return false
    }
}

/// Undecodable art: the original is still cached, but NO thumbnail is written and the
/// link's pixelSize is `.zero` (best-effort, never throws — design §4).
private func checkUndecodableArt(_ cache: ArtworkCache, number: Int) throws -> Bool {
    let garbage = Data([0x00, 0x01, 0x02, 0x03, 0x04])
    let link = try cache.store(imageData: garbage, uti: nil)
    let fileManager = FileManager.default
    guard fileManager.fileExists(atPath: link.cachePath) else {
        printFail(number, "artwork-cache: undecodable original not cached"); return false
    }
    guard !fileManager.fileExists(atPath: ArtworkCache.thumbnailPath(forOriginal: link.cachePath)) else {
        printFail(number, "artwork-cache: undecodable art wrongly produced a thumbnail"); return false
    }
    guard link.pixelSize == .zero else {
        printFail(number, "artwork-cache: undecodable art should have pixelSize .zero"); return false
    }
    return true
}

// MARK: - Synthetic image helpers (CoreGraphics/ImageIO)

/// A solid-color RGBA PNG of the given size, or nil if CoreGraphics is unavailable.
private func makeSolidPNG(width: Int, height: Int) -> Data? {
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
    guard let context = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8,
        bytesPerRow: 0, space: colorSpace, bitmapInfo: bitmapInfo
    ) else { return nil }
    context.setFillColor(red: 0.2, green: 0.5, blue: 0.8, alpha: 1.0)
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

/// The longer pixel edge of the image at `path`, or nil if it can't be read.
private func thumbnailMaxEdge(atPath path: String) -> Int? {
    guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
          let source = CGImageSourceCreateWithData(data as CFData, nil),
          let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
          let width = properties[kCGImagePropertyPixelWidth] as? Int,
          let height = properties[kCGImagePropertyPixelHeight] as? Int else { return nil }
    return max(width, height)
}
