// R4-SPEC — the analyzer ramp's non-text contrast audit (S10.8 B2a). Own file, same posture as
// R4-TAB / R4-CHIP: shares the `ratio` / threshold / grid helpers with the base R4 suite.

import DesignTokenKit
import Testing

/// Every analyzer bar must stand off the lens it sits in (WCAG 1.4.11, 3:1), in both appearances —
/// IN THE PLAYING STATE. Each bar is a vertical gradient from its ramp color (top) to the shaded
/// bottom; both ends are audited at a dense sample of positions (the ramp is linear between stops,
/// contrast is not).
///
/// Decorative exemptions — NOT audited, because the bar field is hidden from accessibility
/// (`SpectrumAnalyzerView`; HeroRow exposes the lens element itself), and no tuning could pass them:
/// - the paused dim (the whole field at 40%): even a black bar reaches only 2.81:1 on the light lens
///   at 40% (the light ramp 1.53–1.74:1), and the dark ramp measures 1.86–3.19:1;
/// - the peak caps: dark keeps the shipped 50% (the darkest stop's cap 2.24:1 on the sheets); light
///   raises them to 85% (`SpectrumRamp.capOpacityLight`: 2.66–3.59:1 at the stops' color).
@Suite("Contrast audit — analyzer ramp (R4-SPEC)")
struct SpectrumRampAuditTests {
    /// 129 positions across the field — a superset of the analyzer's 88 bar positions, with
    /// every stop on the grid.
    private static let positions: [Float] = (0 ... 128).map { Float($0) / 128 }

    @Test("R4-SPEC-01: every bar clears non-text 3:1 on the lens, both appearances (playing)")
    func barsOnLens() {
        // Dark: the lens over the sampled glow field (a superset of where the lens sits), and the
        // resolver's opaque lens under Reduce Transparency / Increase Contrast.
        var darkLenses = [Palette.lensFill.value(for: .dark, increasedContrast: true).over(Palette.window.dark)]
        for geometry in ContrastAuditTests.glowGeometries {
            for point in ContrastAuditTests.gridPoints() {
                let glow = GlowFieldSpec.compositeBackdrop(
                    unitX: point.x, unitY: point.y,
                    containerWidth: geometry.width, containerHeight: geometry.height,
                    appearance: .dark
                )
                darkLenses.append(Palette.lensFill.dark.over(glow))
            }
        }
        // Light: the lens as it renders (both light shadows under its fill — the worst case) and
        // the opaque lens.
        let lightLenses = [
            CardSeparationAuditTests.shadedLightFill(Palette.lensFill),
            Palette.lensFill.value(for: .light, increasedContrast: true).over(Palette.window.light),
        ]
        for position in Self.positions {
            let bar = SpectrumRamp.bar(at: position)
            for (appearance, lenses) in [(TokenAppearance.dark, darkLenses), (.light, lightLenses)] {
                // The lowest ratio over the lenses, so a failure names one number per shade.
                for (end, shade) in [("top", bar.top), ("bottom", bar.bottom)] {
                    let worst = lenses.map { ContrastAuditTests.ratio(label: shade, on: $0, appearance) }.min() ?? 0
                    #expect(worst >= ContrastAuditTests.nonTextAA,
                            "bar \(end) @\(position) on the \(appearance) lens = \(worst)")
                }
            }
        }
    }

    /// The founder rule as a test: the light ramp is new, the dark ramp is the shipped one.
    @Test("R4-SPEC-02: the dark ramp and dark caps are the shipped ones")
    func darkRampUnchanged() {
        let shipped: [(position: Float, color: RGBAColor)] = [
            (0.00, RGBAColor(red: 0x1F / 255.0, green: 0x9D / 255.0, blue: 0x8B / 255.0)),
            (0.20, RGBAColor(red: 0x36 / 255.0, green: 0xC1 / 255.0, blue: 0xAB / 255.0)),
            (0.40, RGBAColor(red: 0x4F / 255.0, green: 0xD2 / 255.0, blue: 0xC0 / 255.0)),
            (0.60, RGBAColor(red: 0x7F / 255.0, green: 0xE3 / 255.0, blue: 0xA8 / 255.0)),
            (0.80, RGBAColor(red: 0xA8 / 255.0, green: 0xEC / 255.0, blue: 0x84 / 255.0)),
            (1.00, RGBAColor(red: 0xC8 / 255.0, green: 0xF0 / 255.0, blue: 0x6A / 255.0)),
        ]
        #expect(SpectrumRamp.stops.count == shipped.count)
        for (stop, expected) in zip(SpectrumRamp.stops, shipped) {
            #expect(stop.position == expected.position)
            #expect(stop.color.dark == expected.color, "dark stop @\(expected.position)")
        }
        #expect(SpectrumRamp.bottomShade == 0.82)
        #expect(SpectrumRamp.capOpacityDark == 0.5)
    }
}
