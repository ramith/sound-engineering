// SampledGlow — the D8 art-sampled glow pipeline's PURE half (S10.7 PR 7, design §3.3):
// dominant-color selection over pixel samples, and the clamp that binds every sampled color
// into token-defined bounds — the §3.1 pre-binding: the R4 audit keeps auditing an
// ENUMERABLE worst case (each slot's ceiling-gray corner), so a pathological cover can never
// blow the contrast budget. The app-side `ArtworkGlowSampler` extracts pixels (AppKit) and
// calls THIS for every decision; the render override and the audit fold share these bounds.

import Foundation

public enum SampledGlow {
    // MARK: Clamp bounds (per glow slot, parallel to `GlowFieldSpec.glows`)

    /// Per-slot sRGB channel ceiling for a SAMPLED glow color. The audit corner — a gray at
    /// this ceiling composited at the slot's token alpha — is the admissible worst case:
    /// sRGB alpha-compositing and relative luminance are both monotone in every source
    /// channel, so no in-box color can composite brighter. The teal slot (top-left, alpha
    /// .28, hosts the hero and the queue head) is the tightest; lime/blue run at ~40%/35%
    /// of that alpha, so they may sample brighter without moving the worst case.
    public static let channelMax: [Double] = [0.62, 0.95, 0.95]

    /// Aesthetic floors — below either, the slot falls back to the BRAND color (audited
    /// separately by the concrete R4-GLOW tests): a near-black sample reads as no glow, a
    /// near-gray one as a muddy wash. Not audit-relevant (fallback = brand = in budget).
    public static let minMaxChannel: Double = 0.22
    public static let minChannelSpread: Double = 0.05

    /// Pixels below these don't VOTE in the histogram (they carry no usable hue): the
    /// value floor drops shadow/letterbox black, the saturation floor drops white/gray.
    public static let voteMinValue: Double = 0.15
    public static let voteMinSaturation: Double = 0.12

    /// Clamp a sampled color into the slot's box: hue-preserving proportional scale-down
    /// (never per-channel truncation, which would shift the hue), with the slot's token
    /// DARK alpha forced (the glow field is dark-only, and alphas are never sampled —
    /// they are the audited quantity). Returns `nil` when the sample fails the aesthetic
    /// floors — the caller keeps the brand color for that slot.
    public static func clampedSampledColor(_ sampled: RGBAColor, slot: Int) -> RGBAColor? {
        guard slot >= 0, slot < GlowFieldSpec.glows.count else { return nil }
        let maxChannel = max(sampled.red, max(sampled.green, sampled.blue))
        let minChannel = min(sampled.red, min(sampled.green, sampled.blue))
        guard maxChannel >= minMaxChannel, maxChannel - minChannel >= minChannelSpread else {
            return nil
        }
        let ceiling = channelMax[slot]
        let scale = maxChannel > ceiling ? ceiling / maxChannel : 1
        return RGBAColor(red: sampled.red * scale,
                         green: sampled.green * scale,
                         blue: sampled.blue * scale,
                         alpha: GlowFieldSpec.glows[slot].color.dark.alpha)
    }

    /// The admissible worst-case palette — each slot's ceiling-gray at its token dark
    /// alpha. R4-GLOW-D8 folds the audit grid with THIS; every real clamped palette
    /// composites strictly darker (channel monotonicity), so passing here proves the
    /// whole sampled color space.
    public static var auditCornerPalette: [RGBAColor?] {
        GlowFieldSpec.glows.indices.map { slot in
            RGBAColor.gray(channelMax[slot],
                           alpha: GlowFieldSpec.glows[slot].color.dark.alpha)
        }
    }

    // MARK: Dominant-color selection (pure, deterministic)

    /// Hue-bucket histogram over pixel samples → up to `GlowFieldSpec.glows.count` dominant
    /// chromatic colors, strongest first (weight = saturation × value, so a small vivid
    /// accent can out-vote a large dull field). Colors are the weighted per-bucket averages.
    /// A cover with no chromatic pixels yields `[]` (every slot → brand). Deterministic:
    /// ties break toward the lower bucket index.
    public static func dominantColors(samples: [RGBAColor]) -> [RGBAColor] {
        let bucketCount = 12
        var weight = [Double](repeating: 0, count: bucketCount)
        var sumRed = [Double](repeating: 0, count: bucketCount)
        var sumGreen = [Double](repeating: 0, count: bucketCount)
        var sumBlue = [Double](repeating: 0, count: bucketCount)

        for pixel in samples {
            let maxChannel = max(pixel.red, max(pixel.green, pixel.blue))
            let minChannel = min(pixel.red, min(pixel.green, pixel.blue))
            let value = maxChannel
            let saturation = maxChannel > 0 ? (maxChannel - minChannel) / maxChannel : 0
            guard value >= voteMinValue, saturation >= voteMinSaturation else { continue }
            let bucket = min(Int(hueFraction(pixel) * Double(bucketCount)), bucketCount - 1)
            let vote = saturation * value
            weight[bucket] += vote
            sumRed[bucket] += pixel.red * vote
            sumGreen[bucket] += pixel.green * vote
            sumBlue[bucket] += pixel.blue * vote
        }

        return weight.indices
            .filter { weight[$0] > 0 }
            .sorted { weight[$0] == weight[$1] ? $0 < $1 : weight[$0] > weight[$1] }
            .prefix(GlowFieldSpec.glows.count)
            .map { bucket in
                RGBAColor(red: sumRed[bucket] / weight[bucket],
                          green: sumGreen[bucket] / weight[bucket],
                          blue: sumBlue[bucket] / weight[bucket])
            }
    }

    /// Standard HSV hue as a fraction in [0, 1). Callers guarantee the pixel is chromatic
    /// (spread > 0); a defensive 0 is returned for the gray case anyway.
    private static func hueFraction(_ pixel: RGBAColor) -> Double {
        let maxChannel = max(pixel.red, max(pixel.green, pixel.blue))
        let minChannel = min(pixel.red, min(pixel.green, pixel.blue))
        let spread = maxChannel - minChannel
        guard spread > 0 else { return 0 }
        let hueSixth: Double = if maxChannel == pixel.red {
            ((pixel.green - pixel.blue) / spread).truncatingRemainder(dividingBy: 6)
        } else if maxChannel == pixel.green {
            (pixel.blue - pixel.red) / spread + 2
        } else {
            (pixel.red - pixel.green) / spread + 4
        }
        let hue = hueSixth / 6
        return hue < 0 ? hue + 1 : hue
    }
}

// MARK: - Pixel ingestion

public extension RGBAColor {
    /// A pixel sample from 8-bit RGBA image bytes (the app-side extractor's entry into the
    /// Kit's color space — keeps raw component construction out of the app target).
    static func fromPixel(red: UInt8, green: UInt8, blue: UInt8) -> RGBAColor {
        RGBAColor(red: Double(red) / 255.0,
                  green: Double(green) / 255.0,
                  blue: Double(blue) / 255.0)
    }
}
