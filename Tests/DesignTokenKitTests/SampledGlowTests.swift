// D8 — the art-sampled glow pipeline's pure half (S10.7 PR 7): the clamp that makes every
// sampled color audit-admissible, and the dominant-color selection. House style: derived
// expectations (bounds come from the Kit constants, never re-typed magic numbers).

import DesignTokenKit
import Foundation
import Testing

@Suite("Sampled glows — clamp + selection (D8)")
struct SampledGlowTests {
    /// Chromatic extremes a pathological cover can produce; every one must land in the
    /// slot's box. (Achromatic extremes — white frames, black letterboxing — are the
    /// FLOORS' cases, D8-CLAMP-03: they reject to brand, they don't clamp.)
    private static let hostileSamples: [RGBAColor] = [
        RGBAColor(red: 1.0, green: 0.05, blue: 0.05), // neon red
        RGBAColor(red: 0.95, green: 0.95, blue: 0.1), // neon yellow
        RGBAColor(red: 0.3, green: 0.6, blue: 1.0), // bright blue
        RGBAColor(red: 0.62, green: 0.3, blue: 0.9), // violet
    ]

    @Test("D8-CLAMP-01: clamped output is inside the slot box with the slot's token alpha")
    func clampedInsideBox() {
        for slot in GlowFieldSpec.glows.indices {
            for sample in Self.hostileSamples {
                guard let clamped = SampledGlow.clampedSampledColor(sample, slot: slot) else {
                    Issue.record("vivid sample unexpectedly rejected: \(sample) slot \(slot)")
                    continue
                }
                let ceiling = SampledGlow.channelMax[slot]
                for (channel, name) in [(clamped.red, "red"), (clamped.green, "green"),
                                        (clamped.blue, "blue")] {
                    #expect(channel <= ceiling + 1e-9, "\(name) \(channel) > \(ceiling) slot \(slot)")
                }
                #expect(clamped.alpha == GlowFieldSpec.glows[slot].color.dark.alpha,
                        "alpha must be the slot's token dark alpha, never sampled")
            }
        }
    }

    @Test("D8-CLAMP-02: scale-down preserves hue (channel ratios), never truncates per-channel")
    func clampPreservesHue() throws {
        let vivid = RGBAColor(red: 1.0, green: 0.4, blue: 0.1)
        let clamped = SampledGlow.clampedSampledColor(vivid, slot: 0)
        let scaled = try #require(clamped)
        // Proportional scale: green/red and blue/red ratios survive.
        #expect(abs(scaled.green / scaled.red - vivid.green / vivid.red) < 1e-9)
        #expect(abs(scaled.blue / scaled.red - vivid.blue / vivid.red) < 1e-9)
        // And the max channel sits exactly at the ceiling (it was above it).
        #expect(abs(scaled.red - SampledGlow.channelMax[0]) < 1e-9)
    }

    @Test("D8-CLAMP-03: aesthetic floors reject near-black and near-gray toward brand fallback")
    func clampFloors() {
        // Darker than the floor (max channel below minMaxChannel).
        let dark = RGBAColor(red: SampledGlow.minMaxChannel - 0.02,
                             green: SampledGlow.minMaxChannel - 0.05, blue: 0.05)
        #expect(SampledGlow.clampedSampledColor(dark, slot: 0) == nil)
        // Grayer than the floor (spread below minChannelSpread).
        let gray = RGBAColor(red: 0.6, green: 0.6 - SampledGlow.minChannelSpread + 0.01, blue: 0.6)
        #expect(SampledGlow.clampedSampledColor(gray, slot: 0) == nil)
        // POST-SCALE floor (review MINOR-4): a barely-chromatic bright sample whose spread
        // collapses under the ceiling scale-down rejects — the floor judges what would RENDER.
        let barelyChromatic = RGBAColor(red: 1.0, green: 0.95, blue: 0.95)
        #expect(SampledGlow.clampedSampledColor(barelyChromatic, slot: 0) == nil)
        // An out-of-range slot is a programming error surfaced as fallback, never a crash.
        #expect(SampledGlow.clampedSampledColor(.gray(0.5), slot: 99) == nil)
    }

    @Test("D8-CLAMP-04: clamping is idempotent per slot")
    func clampIdempotent() {
        for slot in GlowFieldSpec.glows.indices {
            for sample in Self.hostileSamples {
                guard let once = SampledGlow.clampedSampledColor(sample, slot: slot) else { continue }
                let twice = SampledGlow.clampedSampledColor(once, slot: slot)
                #expect(twice == once, "re-clamp must be a no-op (slot \(slot))")
            }
        }
    }

    // MARK: Light lift (S10.8 B2b)

    /// A chromatic lattice over the whole hue circle (HSV, 10° steps × three saturations × two
    /// values) — what a cover's dominant colors can be, beyond the four hostile extremes.
    private static let hueLattice: [RGBAColor] = stride(from: 0.0, to: 360.0, by: 10.0).flatMap { hue in
        [1.0, 0.5, 0.25].flatMap { saturation in
            [1.0, 0.6].map { value in hsv(hue: hue, saturation: saturation, value: value) }
        }
    }

    /// sRGB → linear light (the WCAG linearization) — the test's own oracle, not the Kit's.
    private static func linear(_ channel: Double) -> Double {
        channel <= 0.03928 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
    }

    private static func hsv(hue: Double, saturation: Double, value: Double) -> RGBAColor {
        let chroma = value * saturation
        let sector = hue / 60
        let second = chroma * (1 - abs(sector.truncatingRemainder(dividingBy: 2) - 1))
        let floor = value - chroma
        func color(_ red: Double, _ green: Double, _ blue: Double) -> RGBAColor {
            RGBAColor(red: red + floor, green: green + floor, blue: blue + floor)
        }
        return switch Int(sector) {
        case 0: color(chroma, second, 0)
        case 1: color(second, chroma, 0)
        case 2: color(0, chroma, second)
        case 3: color(0, second, chroma)
        case 4: color(second, 0, chroma)
        default: color(chroma, 0, second)
        }
    }

    @Test("D8-LIGHT-01: the pair's dark half IS the dark clamp, and both reject together")
    func pairDarkHalfIsTheClamp() {
        for slot in GlowFieldSpec.glows.indices {
            for sample in Self.hostileSamples + Self.hueLattice {
                let pair = SampledGlow.clampedSampledPair(sample, slot: slot)
                #expect(pair?.dark == SampledGlow.clampedSampledColor(sample, slot: slot),
                        "dark half drifted from the clamp: \(sample) slot \(slot)")
            }
        }
        #expect(SampledGlow.clampedSampledPair(.gray(0.5), slot: 0) == nil, "achromatic → brand")
        #expect(SampledGlow.clampedSampledPair(.gray(0.5), slot: 99) == nil, "bad slot → brand")
    }

    /// The light half is a pastel at (at least) the slot's brand-pastel luminance, at the
    /// slot's token LIGHT alpha, with the sample's hue: mixing toward white in linear light
    /// scales every channel's distance from white by the same factor — and never by more than
    /// the brand pastel's own depth into the brand hue (so no channel falls below that floor).
    @Test("D8-LIGHT-02: the light half is the hue lifted to the brand pastel's luminance, at the light alpha")
    func lightHalfIsALiftedPastel() throws {
        for slot in GlowFieldSpec.glows.indices {
            let brand = GlowFieldSpec.glows[slot].color
            let pastel = brand.light
            let brandPeak = max(brand.dark.red, max(brand.dark.green, brand.dark.blue))
            let brandHue = RGBAColor(red: brand.dark.red / brandPeak, green: brand.dark.green / brandPeak,
                                     blue: brand.dark.blue / brandPeak)
            let budget = (1 - pastel.relativeLuminance) / (1 - brandHue.relativeLuminance)
            for sample in Self.hostileSamples + Self.hueLattice {
                guard let light = SampledGlow.clampedSampledPair(sample, slot: slot)?.light else { continue }
                #expect(light.alpha == pastel.alpha, "alpha must be the slot's token light alpha")
                #expect(light.relativeLuminance >= pastel.relativeLuminance - 1e-9,
                        "lifted \(light) is darker than the slot pastel (slot \(slot))")
                for channel in [light.red, light.green, light.blue] {
                    #expect(Self.linear(channel) >= 1 - budget - 1e-9,
                            "lifted \(light) is deeper than the slot's tint budget (slot \(slot))")
                }
                let peak = max(sample.red, max(sample.green, sample.blue))
                let channels = [(light.red, sample.red), (light.green, sample.green), (light.blue, sample.blue)]
                let distances = channels.map { lifted, sampled in
                    (lifted: 1 - Self.linear(lifted), hue: 1 - Self.linear(sampled / peak))
                }
                let reference = try #require(distances.max { $0.hue < $1.hue })
                for distance in distances {
                    #expect(abs(distance.lifted * reference.hue - distance.hue * reference.lifted) < 1e-9,
                            "hue not preserved: \(sample) → \(light)")
                }
            }
        }
    }

    /// The pale-glow promise for art: whatever the cover, every slot composited over the light
    /// window only brightens it — at every alpha the falloff reaches, not just the peak
    /// (compositing runs in gamma space, where a saturated hue's low channel can dip the
    /// luminance at a partial alpha even when the hue itself is brighter than the window).
    @Test("D8-LIGHT-03: no sampled light glow darkens the light window, at any falloff alpha")
    func lightHalfNeverDarkens() {
        let window = Palette.window.light
        let fractions = (1 ... 20).map { Double($0) / 20 }
        for slot in GlowFieldSpec.glows.indices {
            for sample in Self.hostileSamples + Self.hueLattice {
                guard let light = SampledGlow.clampedSampledPair(sample, slot: slot)?.light else { continue }
                for fraction in fractions {
                    let composite = light.opacity(light.alpha * fraction).over(window)
                    #expect(composite.relativeLuminance > window.relativeLuminance,
                            "\(sample) slot \(slot) darkens the light window at \(fraction) of peak")
                }
            }
        }
    }

    @Test("D8-SEL-01: selection is deterministic, strongest-chroma-first, achromatic pixels don't vote")
    func selectionRanksChromaticColors() {
        // 60 vivid red + 30 vivid blue + 40 black + 40 white pixels: red then blue, nothing else.
        let red = RGBAColor(red: 0.9, green: 0.1, blue: 0.1)
        let blue = RGBAColor(red: 0.1, green: 0.2, blue: 0.9)
        var samples = Array(repeating: red, count: 60) + Array(repeating: blue, count: 30)
        samples += Array(repeating: RGBAColor.gray(0.02), count: 40) // below the value floor
        samples += Array(repeating: RGBAColor.gray(0.98), count: 40) // below the saturation floor
        let picked = SampledGlow.dominantColors(samples: samples)
        #expect(picked.count == 2)
        // Strongest first: the red bucket outweighs blue. Averages stay in-family.
        #expect(picked[0].red > picked[0].blue, "first pick should be the red family")
        #expect(picked[1].blue > picked[1].red, "second pick should be the blue family")
        // Deterministic: same input, same output.
        #expect(SampledGlow.dominantColors(samples: samples) == picked)
    }

    @Test("D8-SEL-02: an achromatic cover yields no picks (every slot falls back to brand)")
    func selectionAchromaticCover() {
        let samples = (0 ..< 100).map { RGBAColor.gray(Double($0) / 100.0) }
        #expect(SampledGlow.dominantColors(samples: samples).isEmpty)
    }

    @Test("D8-TOK: clamp constants are sane and parallel to the glow slots")
    func clampConstants() {
        #expect(SampledGlow.channelMax.count == GlowFieldSpec.glows.count)
        for ceiling in SampledGlow.channelMax {
            #expect(ceiling > 0 && ceiling <= 1)
        }
        #expect(SampledGlow.minMaxChannel > 0 && SampledGlow.minMaxChannel < 1)
        #expect(SampledGlow.minChannelSpread > 0 && SampledGlow.minChannelSpread < 1)
        // The audit corner carries the slots' token dark alphas — the audited quantity.
        let corner = SampledGlow.auditCornerPalette
        #expect(corner.count == GlowFieldSpec.glows.count)
        for (slot, color) in corner.enumerated() {
            #expect(color?.alpha == GlowFieldSpec.glows[slot].color.dark.alpha)
        }
    }
}
