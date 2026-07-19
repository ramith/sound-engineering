// R4-ROW — the realigned playing row's contrast audit (S10.8 PR D). Own file, same posture
// as R4-TAB/R4-CHIP: shares the `ratio`/threshold/grid helpers with the base R4 suite.

import DesignTokenKit
import Testing

/// The playing row (`png/04`): a 13% accent card carrying the teal `accentTitle` and an
/// `accentText` duration. The queue is the LEFT flex region, so the card can sit anywhere
/// over the glow field (incl. the teal core — jump-to-now-playing centers it there); the
/// title/duration are audited at every sampled point like R4-GLOW-02's label pairs.
@Suite("Contrast audit — playing row (R4-ROW)")
struct PlayingRowAuditTests {
    @Test("R4-ROW-01: accentTitle + accentText clear AA on the 13% card over its backdrops")
    func playingRowText() {
        // Dark: card ⊕ the real sampled glow field, every grid point (both geometries).
        for geometry in ContrastAuditTests.glowGeometries {
            for point in ContrastAuditTests.gridPoints() {
                let glow = GlowFieldSpec.compositeBackdrop(
                    unitX: point.x, unitY: point.y,
                    containerWidth: geometry.width, containerHeight: geometry.height,
                    appearance: .dark
                )
                let card = Palette.rowNowPlaying.dark.over(glow)
                for (name, text) in [("accentTitle", Palette.accentTitle),
                                     ("accentText", Palette.accentText)] {
                    let ratio = ContrastAuditTests.ratio(label: text, on: card, .dark)
                    #expect(ratio >= ContrastAuditTests.textAA,
                            "\(name) on card⊕glow @(\(point.x),\(point.y)) \(geometry.width)pt = \(ratio)")
                }
            }
        }
        // Light: glows are suppressed — the card composites over the plain window.
        let lightCard = Palette.rowNowPlaying.light.over(Palette.window.light)
        for (name, text) in [("accentTitle", Palette.accentTitle),
                             ("accentText", Palette.accentText)] {
            let ratio = ContrastAuditTests.ratio(label: text, on: lightCard, .light)
            #expect(ratio >= ContrastAuditTests.textAA, "\(name) on light card = \(ratio)")
        }
    }
}
