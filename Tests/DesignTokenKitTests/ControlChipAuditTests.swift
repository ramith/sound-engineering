// R4-CHIP — the queue-header control chips' contrast audit (S10.8 PR C). Own file, same
// posture as R4-TAB: shares only the `ratio`/threshold helpers with the base R4 suite.

import DesignTokenKit
import Testing

/// The realigned queue header (`png/03`): 28pt icon chips (resting `badgeFill`, hovered
/// `controlHover`, toggled-on `controlActiveFill` with an `accentText` glyph) and the mini
/// Up Next / Recent capsule pair (a `tabTrack` track with a `segmentSelected` lift). Chips
/// sit on the queue region of the glow field in dark; the plain-window composite is the
/// audit surface (the field's teal core never hosts the header — but the D8 corner suite
/// already bounds field brightening for fills of this class via the badge pair).
@Suite("Contrast audit — queue header control chips (R4-CHIP)")
struct ControlChipAuditTests {
    @Test("R4-CHIP-01: chip glyphs and segment text clear AA on every chip state")
    func chipStates() {
        for appearance in TokenAppearance.allCases {
            let window = Palette.window.value(for: appearance)
            // Resting + hovered chips carry labelSecondary glyphs (label on hover-brighten).
            for (fillName, fill) in [("badgeFill", Palette.badgeFill),
                                     ("controlHover", Palette.controlHover)] {
                let chip = fill.value(for: appearance).over(window)
                for (name, label) in [("label", Palette.label),
                                      ("labelSecondary", Palette.labelSecondary)] {
                    let ratio = ContrastAuditTests.ratio(label: label, on: chip, appearance)
                    #expect(ratio >= ContrastAuditTests.textAA,
                            "\(name) on \(fillName)⊕window (\(appearance)) = \(ratio)")
                }
            }
            // Toggled-on chip: the accentText glyph on the accent-16% tint.
            let active = Palette.controlActiveFill.value(for: appearance).over(window)
            let activeRatio = ContrastAuditTests.ratio(label: Palette.accentText,
                                                       on: active, appearance)
            #expect(activeRatio >= ContrastAuditTests.textAA,
                    "accentText on controlActiveFill⊕window (\(appearance)) = \(activeRatio)")
            // Selected segment: label on segmentSelected ⊕ tabTrack ⊕ window. (Unselected
            // text on the bare track is R4-TAB-01's pair.)
            let track = Palette.tabTrack.value(for: appearance).over(window)
            let segment = Palette.segmentSelected.value(for: appearance).over(track)
            let segRatio = ContrastAuditTests.ratio(label: Palette.label, on: segment, appearance)
            #expect(segRatio >= ContrastAuditTests.textAA,
                    "label on segmentSelected⊕track (\(appearance)) = \(segRatio)")
        }
    }

    /// S10.8 PR F: the hero's realigned ENHANCED chip is the same `controlActiveFill` +
    /// `accentText` pair, but it sits in the hero — the glow field's TEAL CORE (the
    /// field's brightest text seat), so it gets the sampled-field audit like R4-BADGE-01.
    @Test("R4-CHIP-02: hero teal chip text clears AA over the sampled glow field (dark)")
    func heroTealChipOverGlow() {
        for geometry in ContrastAuditTests.glowGeometries {
            for point in ContrastAuditTests.gridPoints() {
                let glow = GlowFieldSpec.compositeBackdrop(
                    unitX: point.x, unitY: point.y,
                    containerWidth: geometry.width, containerHeight: geometry.height,
                    appearance: .dark
                )
                let chip = Palette.controlActiveFill.dark.over(glow)
                let ratio = ContrastAuditTests.ratio(label: Palette.accentText, on: chip, .dark)
                #expect(ratio >= ContrastAuditTests.textAA,
                        "accentText on tealChip⊕glow @(\(point.x),\(point.y)) \(geometry.width)pt = \(ratio)")
            }
        }
    }
}
