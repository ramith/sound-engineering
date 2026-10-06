// R4-FOCUS — the keyboard focus ring's non-text contrast audit (S10.8 A3). Own file, same
// posture as R4-CHIP / R4-TAB: shares only the `ratio`/threshold/grid helpers with the base R4
// suite (that struct is at its type-body limit).

import DesignTokenKit
import Testing

/// The four custom lists (Songs, queue, playlist detail, Library rail) switch the system focus
/// effect off and draw `focusRing` (a 2pt ring) on the keyboard-cursor row instead. A focus
/// indicator is non-text (WCAG 1.4.11 / 2.4.7), so it must clear 3:1 against everything the
/// ring can sit on: the bare window (playlist detail), the glass panel card (Songs, rail), and
/// the selected / now-playing row tints on that card — and, for the queue, the dark glow field.
@Suite("Contrast audit — keyboard focus ring (R4-FOCUS)")
struct FocusRingAuditTests {
    @Test("R4-FOCUS-01: focusRing clears 3:1 on the window, the panel card and the row tints")
    func ringOnCardsAndRows() {
        for appearance in TokenAppearance.allCases {
            for increasedContrast in [false, true] {
                let window = Palette.window.value(for: appearance, increasedContrast: increasedContrast)
                let card = Palette.panelFill.value(for: appearance, increasedContrast: increasedContrast)
                    .over(window)
                let surfaces: [(name: String, color: RGBAColor)] = [
                    ("window", window),
                    ("panelFill⊕window", card),
                    ("rowSelected⊕panelFill⊕window",
                     Palette.rowSelected.value(for: appearance, increasedContrast: increasedContrast).over(card)),
                    ("rowNowPlaying⊕panelFill⊕window",
                     Palette.rowNowPlaying.value(for: appearance, increasedContrast: increasedContrast).over(card)),
                ]
                for surface in surfaces {
                    let ring = Palette.focusRing.value(for: appearance, increasedContrast: increasedContrast)
                        .over(surface.color)
                    let ratio = RGBAColor.contrastRatio(ring, surface.color)
                    #expect(ratio >= ContrastAuditTests.nonTextAA,
                            "focusRing on \(surface.name) (\(appearance), IC \(increasedContrast)) = \(ratio)")
                }
            }
        }
    }

    /// The queue's rows sit on the Now Playing glow field, not on a card (dark only — the field
    /// is gated off in light and under Reduce Transparency / Increase Contrast).
    @Test("R4-FOCUS-02: focusRing clears 3:1 on queue rows over the sampled glow field (dark)")
    func ringOverGlowField() {
        for geometry in ContrastAuditTests.glowGeometries {
            for point in ContrastAuditTests.gridPoints() {
                let glow = GlowFieldSpec.compositeBackdrop(
                    unitX: point.x, unitY: point.y,
                    containerWidth: geometry.width, containerHeight: geometry.height,
                    appearance: .dark
                )
                let surfaces: [(name: String, color: RGBAColor)] = [
                    ("glow", glow),
                    ("rowSelected⊕glow", Palette.rowSelected.dark.over(glow)),
                    ("rowNowPlaying⊕glow", Palette.rowNowPlaying.dark.over(glow)),
                ]
                for surface in surfaces {
                    let ratio = ContrastAuditTests.ratio(label: Palette.focusRing, on: surface.color, .dark)
                    #expect(ratio >= ContrastAuditTests.nonTextAA,
                            "focusRing on \(surface.name) @(\(point.x),\(point.y)) \(geometry.width)pt = \(ratio)")
                }
            }
        }
    }
}
