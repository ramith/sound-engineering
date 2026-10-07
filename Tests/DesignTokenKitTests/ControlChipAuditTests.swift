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

    /// The chip-visibility floor (S10.8 B3). Not a WCAG pair — the chip's text carries the format
    /// — but a regression net for "the chip disappears into its card", like CARD-SEP.
    static let chipVisibilityFloor = 1.3

    /// S10.8 B3: the format chip ("FLAC", "MP3" — queue, Songs and Recent rows, the track-info card)
    /// is white at rest and the teal tint on a playing or selected row; neither fill separates from
    /// its surface on its own (white 1.02–1.17:1, the teal ~1.10:1), so light edges it with
    /// `controlEdgeLight`, drawn INSIDE the chip over its fill. The chip reads by whichever of its
    /// fill and its edge separates more (on a selected Songs row the white fill itself does).
    /// Audited where the chip sits: the card as it renders (both shadows under it), the opaque
    /// RT/IC card, and the window (the Now Playing queue; the pale glow only brightens it — the
    /// window is the darkest light surface).
    @Test("R4-CHIP-03: the light format chip clears the visibility floor; its text stays AA")
    func formatChipInLight() {
        let window = Palette.window.light
        let surfaces = [
            ("card", CardSeparationAuditTests.shadedLightFill(Palette.panelFill)),
            ("RT/IC card", Palette.panelFill.value(for: .light, increasedContrast: true).over(window)),
            ("window", window),
        ]
        for (surfaceName, surface) in surfaces {
            // (state, what surrounds the chip, the chip's fill, its text)
            let rowNowPlaying = Palette.rowNowPlaying.light.over(surface)
            let rowSelected = Palette.rowSelected.light.over(surface)
            let states = [
                ("resting", surface, Palette.card, Palette.labelSecondary),
                ("resting on a selected row", rowSelected, Palette.card, Palette.labelSecondary),
                ("playing", rowNowPlaying, Palette.controlActiveFill, Palette.accentText),
                ("selected", rowSelected, Palette.controlActiveFill, Palette.accentText),
            ]
            for (state, backdrop, fill, text) in states {
                let chip = fill.light.over(backdrop)
                let edge = GlassDecor.controlEdgeLight.over(chip)
                let visibility = max(RGBAColor.contrastRatio(chip, backdrop), RGBAColor.contrastRatio(edge, backdrop))
                #expect(visibility >= Self.chipVisibilityFloor,
                        "\(state) chip on the \(surfaceName) = \(visibility)")
                let textRatio = ContrastAuditTests.ratio(label: text, on: chip, .light)
                #expect(textRatio >= ContrastAuditTests.textAA,
                        "\(state) chip text on the \(surfaceName) = \(textRatio)")
            }
        }
        // The hero's format · rate chip is the `.badge` glass role: its glass hairline over the
        // badge fill already draws the edge (~1.42:1 on the window); held to the same floor.
        let badge = Palette.badgeFill.light.over(window)
        let badgeEdge = GlassDecor.glassHairline.light.over(badge)
        #expect(RGBAColor.contrastRatio(badgeEdge, window) >= Self.chipVisibilityFloor, "hero chip edge")
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
