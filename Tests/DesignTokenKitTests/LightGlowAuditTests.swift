// R4 over the LIGHT glow field (S10.8 B2b — the pale-glow backdrop). The base glow audits are
// dark-only because the field never painted in light; under the pale glow it does, so its light
// composite is audited here through the SAME `compositeBackdrop` fold the render reads: Now
// Playing's three glows and the Library's single pool, both geometries, every grid point — the
// brand pastels, and a lattice of art-sampled pastels (the D8 light lift) in every slot.

import DesignTokenKit
import Testing

@Suite("Contrast audit — the pale light glow (R4-GLOW-LIGHT)")
struct LightGlowAuditTests {
    /// One screen's glow field.
    private struct GlowSet {
        let name: String
        let glows: [GlowFieldSpec.Glow]
        /// Only Now Playing's field is art-sampled (album-coloured glow elsewhere is a non-goal).
        let artSampled: Bool
    }

    private static let glowSets = [
        GlowSet(name: "Now Playing", glows: GlowFieldSpec.glows, artSampled: true),
        GlowSet(name: "Library", glows: GlowFieldSpec.libraryGlows, artSampled: false),
    ]

    /// Sampled light palettes: one cover hue in every slot at a time, around the hue circle
    /// (the lift pins each slot's luminance, so the hue is the only free variable).
    private static let sampledPalettes: [[RGBAColor?]] = stride(from: 0.0, to: 1.0, by: 1.0 / 12).map { step in
        let hue = RGBAColor(red: max(0, min(1, abs(step * 6 - 3) - 1)),
                            green: max(0, min(1, 2 - abs(step * 6 - 2))),
                            blue: max(0, min(1, 2 - abs(step * 6 - 4))))
        return GlowFieldSpec.glows.indices.map { SampledGlow.clampedSampledPair(hue, slot: $0)?.light }
    }

    private static func lightComposites(overrides: [RGBAColor?]?) -> [(site: String, color: RGBAColor)] {
        glowSets.flatMap { set in
            ContrastAuditTests.glowGeometries.flatMap { geometry in
                ContrastAuditTests.gridPoints().map { point in
                    let color = GlowFieldSpec.compositeBackdrop(
                        unitX: point.x, unitY: point.y,
                        containerWidth: geometry.width, containerHeight: geometry.height,
                        appearance: .light, glows: set.glows,
                        overrideColors: set.artSampled ? overrides : nil
                    )
                    return ("\(set.name) glow @(\(point.x),\(point.y)) \(geometry.width)pt", color)
                }
            }
        }
    }

    @Test("R4-GLOW-LIGHT-01: the pale glow never darkens the light window — brand and sampled")
    func paleGlowOnlyBrightens() {
        let window = Palette.window.light.relativeLuminance
        for overrides in [nil] + Self.sampledPalettes {
            for sample in Self.lightComposites(overrides: overrides) {
                #expect(sample.color.relativeLuminance >= window - 1e-12,
                        "\(sample.site) darkens the window (sampled: \(overrides != nil))")
            }
        }
    }

    @Test("R4-GLOW-LIGHT-02: every light R4 pair clears its threshold across the pale glow — brand and sampled")
    func lightPairsAcrossTheGlow() {
        for overrides in [nil] + Self.sampledPalettes {
            for sample in Self.lightComposites(overrides: overrides) {
                LightPairs.expectAll(on: sample.color, sample.site)
            }
        }
    }
}
