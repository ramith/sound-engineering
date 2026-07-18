import AppKit
import DesignTokenKit
import Observation

// MARK: - Artwork Glow Sampler (S10.7 PR 7 — founder decision D8)

/// Extracts the current artwork's dominant colors and publishes the CLAMPED per-slot glow
/// palette `GlowField` renders (design §3.3): downsample → pixel votes → the Kit's
/// `SampledGlow` selection + clamp — every published color is audit-admissible by
/// construction (R4-GLOW-D8 proves the clamp box's corner, so no cover can break contrast).
/// Per-track palette cache (the `ArtworkThumbnailStore` pattern); a `nil` palette — missing
/// art, unreadable art, or the token-guarded resolve gap right after a track change — means
/// the brand colors.
@MainActor
@Observable
final class ArtworkGlowSampler {
    /// Per-slot overrides for `GlowFieldSpec.glows`; a nil slot (or nil array) keeps brand.
    private(set) var palette: [RGBAColor?]?

    /// Palette cache keyed by track identity; insertion-ordered for cheap FIFO eviction.
    private var cache: [String: [RGBAColor?]] = [:]
    private var cacheOrder: [String] = []
    private let cacheLimit = 64

    private static let thumbSide = 24

    /// Recompute (or recall) the palette for the current track's artwork. Deliberately
    /// synchronous: a 24×24 downsample + 576 pixel votes is microseconds — no off-main hop,
    /// no Sendable laundering of AppKit types.
    func update(artwork: NSImage?, trackKey: String?) {
        guard let artwork, let trackKey else {
            palette = nil
            return
        }
        if let cached = cache[trackKey] {
            palette = cached
            return
        }
        let computed = Self.samplePalette(from: artwork)
        cache[trackKey] = computed
        cacheOrder.append(trackKey)
        if cacheOrder.count > cacheLimit {
            cache.removeValue(forKey: cacheOrder.removeFirst())
        }
        palette = computed
    }

    /// Downsample to a tiny sRGB thumb and run the pure Kit pipeline over its pixels.
    private static func samplePalette(from artwork: NSImage) -> [RGBAColor?] {
        let side = thumbSide
        guard let cgImage = artwork.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let context = CGContext(
                  data: nil, width: side, height: side,
                  bitsPerComponent: 8, bytesPerRow: side * 4,
                  space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else { return brandOnly }
        context.interpolationQuality = .low
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: side, height: side))
        guard let bytes = context.data else { return brandOnly }

        // PREMULTIPLIED bytes read raw (see RGBAColor.fromPixel's contract): transparent
        // margins premultiply toward black and are dropped by the Kit's vote value floor;
        // partial alpha scales channels uniformly — hue kept, vote weight reduced.
        let buffer = bytes.bindMemory(to: UInt8.self, capacity: side * side * 4)
        var samples: [RGBAColor] = []
        samples.reserveCapacity(side * side)
        for pixel in 0 ..< (side * side) {
            let base = pixel * 4
            samples.append(.fromPixel(red: buffer[base],
                                      green: buffer[base + 1],
                                      blue: buffer[base + 2]))
        }

        let dominant = SampledGlow.dominantColors(samples: samples)
        return GlowFieldSpec.glows.indices.map { slot in
            slot < dominant.count ? SampledGlow.clampedSampledColor(dominant[slot], slot: slot) : nil
        }
    }

    /// All-slots-brand (used for unreadable artwork so the failure is cached too — retrying
    /// a broken image every track revisit would be waste).
    private static var brandOnly: [RGBAColor?] {
        GlowFieldSpec.glows.indices.map { _ in nil }
    }
}
