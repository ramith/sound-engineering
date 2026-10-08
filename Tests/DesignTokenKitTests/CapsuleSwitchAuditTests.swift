// R4-SEG — the capsule switch's selection contrast audit (S10.8 D3). Own file, same posture as
// R4-CHIP / R4-TAB: shares only the `ratio`/threshold/grid helpers with the base R4 suite.

import DesignTokenKit
import Testing

/// The capsule switch (the queue's Up Next / Recent; the EQ switch from Sprint F) raises its
/// selected segment with `segmentSelected` on the carved `tabTrack` — ≈ 1.3:1 (dark) and ≈ 2.0:1
/// (light) against the track, too faint to carry a selection on its own (WCAG 1.4.11). The cue
/// that is not the fill is the segment's 1pt `accentForeground` ring: it must clear 3:1 against
/// the TRACK outside it and the raised SEGMENT inside it. (The selected title on the segment is
/// R4-CHIP-01's text pair; the light glow replays these pairs through `LightPairs`.)
@Suite("Contrast audit — capsule switch selection (R4-SEG)")
struct CapsuleSwitchAuditTests {
    /// The ring's ratios against the track and the segment, the switch composited on `backdrop`.
    private static func ringRatios(on backdrop: RGBAColor, _ appearance: TokenAppearance,
                                   increasedContrast: Bool = false) -> (track: Double, segment: Double) {
        let track = Palette.tabTrack.value(for: appearance, increasedContrast: increasedContrast).over(backdrop)
        let segment = Palette.segmentSelected.value(for: appearance, increasedContrast: increasedContrast)
            .over(track)
        let ring = Palette.accentForeground.value(for: appearance, increasedContrast: increasedContrast)
        return (RGBAColor.contrastRatio(ring.over(track), track),
                RGBAColor.contrastRatio(ring.over(segment), segment))
    }

    @Test("R4-SEG-02: the selected segment's ring clears 3:1 against the track and the segment, both appearances")
    func selectedSegmentOnWindow() {
        for appearance in TokenAppearance.allCases {
            for increasedContrast in [false, true] {
                let window = Palette.window.value(for: appearance, increasedContrast: increasedContrast)
                let ratios = Self.ringRatios(on: window, appearance, increasedContrast: increasedContrast)
                #expect(ratios.track >= ContrastAuditTests.nonTextAA,
                        "ring on tabTrack⊕window (\(appearance), IC \(increasedContrast)) = \(ratios.track)")
                #expect(ratios.segment >= ContrastAuditTests.nonTextAA,
                        "ring on segmentSelected⊕track (\(appearance), IC \(increasedContrast)) = \(ratios.segment)")
            }
        }
    }

    /// The queue header sits on Now Playing's glow field in dark (the light field is replayed by
    /// `LightPairs`; the field is gated off under Reduce Transparency / Increase Contrast).
    @Test("R4-SEG-02: the selected segment's ring clears 3:1 over the sampled glow field (dark)")
    func selectedSegmentOverGlowField() {
        for geometry in ContrastAuditTests.glowGeometries {
            for point in ContrastAuditTests.gridPoints() {
                let glow = GlowFieldSpec.compositeBackdrop(
                    unitX: point.x, unitY: point.y,
                    containerWidth: geometry.width, containerHeight: geometry.height,
                    appearance: .dark
                )
                let ratios = Self.ringRatios(on: glow, .dark)
                let site = "@(\(point.x),\(point.y)) \(geometry.width)pt"
                #expect(ratios.track >= ContrastAuditTests.nonTextAA, "ring on tabTrack⊕glow \(site) = \(ratios.track)")
                #expect(ratios.segment >= ContrastAuditTests.nonTextAA,
                        "ring on segmentSelected⊕glow \(site) = \(ratios.segment)")
            }
        }
    }
}
