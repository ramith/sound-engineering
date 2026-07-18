// D8 — the art-sampled glow pipeline's pure half (S10.7 PR 7): the clamp that makes every
// sampled color audit-admissible, and the dominant-color selection. House style: derived
// expectations (bounds come from the Kit constants, never re-typed magic numbers).

import DesignTokenKit
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
