// R4-METER — the true-peak hot state's contrast audit (S10.8 PR E). Own file, same posture
// as R4-TAB/R4-CHIP/R4-ROW: shares the `ratio`/threshold/grid helpers with the base suite.

import DesignTokenKit
import Testing

/// The hot meter (`png/05`): an amber fill tail (non-text, 3:1) and an amber value readout
/// (text, 4.5:1), both sitting on the inspector panel — audited over the panel's real
/// backdrops: panel⊕glow sampled on the RIGHT half (the inspector's home, per R4-PANEL-01's
/// domain) in dark, and the plain-window/opaque composites both appearances.
@Suite("Contrast audit — true-peak hot meter (R4-METER)")
struct MeterAuditTests {
    @Test("R4-METER-01: hot fill clears non-text and hot text clears AA on the panel")
    func hotMeterOnPanel() {
        // Dark: panel ⊕ the sampled glow field, right half.
        for geometry in ContrastAuditTests.glowGeometries {
            for point in ContrastAuditTests.gridPoints() where point.x >= 0.5 {
                let glow = GlowFieldSpec.compositeBackdrop(
                    unitX: point.x, unitY: point.y,
                    containerWidth: geometry.width, containerHeight: geometry.height,
                    appearance: .dark
                )
                let panel = Palette.panelFill.dark.over(glow)
                assertHotPairs(on: panel, appearance: .dark,
                               where: "panel⊕glow @(\(point.x),\(point.y))")
            }
        }
        // Both appearances: the plain-window composite and the RT/IC opaque fallback.
        for appearance in TokenAppearance.allCases {
            let window = Palette.window.value(for: appearance)
            let panel = Palette.panelFill.value(for: appearance).over(window)
            assertHotPairs(on: panel, appearance: appearance, where: "panel⊕window")
        }
    }

    private func assertHotPairs(on surface: RGBAColor, appearance: TokenAppearance,
                                where site: String) {
        let fill = Palette.meterHot.value(for: appearance).over(surface)
        #expect(RGBAColor.contrastRatio(fill, surface) >= ContrastAuditTests.nonTextAA,
                "meterHot fill on \(site) (\(appearance))")
        let textRatio = ContrastAuditTests.ratio(label: Palette.meterHotText,
                                                 on: surface, appearance)
        #expect(textRatio >= ContrastAuditTests.textAA,
                "meterHotText on \(site) (\(appearance)) = \(textRatio)")
    }
}
