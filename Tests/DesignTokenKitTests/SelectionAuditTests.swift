// R4-SEL — the selected row's visibility and its text (S10.8 B2a). Own file, same posture as
// R4-TAB / R4-CHIP: shares the `ratio` / threshold helpers with the base R4 suite.

import DesignTokenKit
import Testing

/// A selected row draws `rowSelected` on the card (Songs, the rail) or on the window (the queue
/// and playlist detail in light). The tint must SHOW — a multi-selection was invisible at the
/// shipped light 1.10:1 — and every text on it must stay AA. The trade-off is physical: a visible
/// tint takes black-55% tertiary below 4.5:1, so tertiary text on a selected row promotes
/// (`labelTertiaryOnSelection`, the selected-row text rule).
@Suite("Contrast audit — the selected row (R4-SEL)")
struct SelectionAuditTests {
    /// Not a WCAG pair: the selection is also exposed as `.isSelected` to VoiceOver. A floor that
    /// keeps the light tint visible against what it sits on.
    static let minimumVisibility = 1.3

    /// What a light selected row sits on: the card as it renders (shadows under it), the opaque
    /// RT/IC card, and the window.
    private static let lightBackdrops = [
        CardSeparationAuditTests.shadedLightFill(Palette.panelFill),
        Palette.panelFill.value(for: .light, increasedContrast: true).over(Palette.window.light),
        Palette.window.light,
    ]

    /// Every text a selected row carries: primary, secondary, tertiary (promoted), the rail's
    /// active label (`accentText`) and a selected queue row's title (`accentForeground`).
    private static let texts: [(name: String, pair: AppearancePair)] = [
        ("label", Palette.label), ("labelSecondary", Palette.labelSecondary),
        ("labelTertiaryOnSelection", Palette.labelTertiaryOnSelection),
        ("accentText", Palette.accentText), ("accentForeground", Palette.accentForeground),
    ]

    @Test("R4-SEL-01: the light selection tint shows against the card and the window")
    func lightTintVisible() {
        for backdrop in Self.lightBackdrops {
            let selected = Palette.rowSelected.light.over(backdrop)
            let ratio = RGBAColor.contrastRatio(selected, backdrop)
            #expect(ratio >= Self.minimumVisibility, "rowSelected vs its backdrop = \(ratio)")
        }
    }

    @Test("R4-SEL-02: every text on a light selected row clears AA, the promoted tertiary included")
    func lightSelectedRowText() {
        for backdrop in Self.lightBackdrops {
            let selected = Palette.rowSelected.light.over(backdrop)
            for text in Self.texts {
                let ratio = ContrastAuditTests.ratio(label: text.pair, on: selected, .light)
                #expect(ratio >= ContrastAuditTests.textAA, "\(text.name) on rowSelected = \(ratio)")
            }
            // A selected queue row's format badge: accentText on the toggled-chip fill.
            let badge = Palette.controlActiveFill.light.over(selected)
            let badgeRatio = ContrastAuditTests.ratio(label: Palette.accentText, on: badge, .light)
            #expect(badgeRatio >= ContrastAuditTests.textAA, "accentText on badge⊕rowSelected = \(badgeRatio)")
        }
    }

    /// Dark is unchanged here. Its tertiary on the selected row measures 4.46:1 on the card — a
    /// pre-existing AA miss that waits on the founder's decision about dark selection (a shipped
    /// dark value); pinned so the fix flips this test.
    @Test("R4-SEL-03: dark selected-row text (tertiary pinned: 4.46:1, founder decision)")
    func darkSelectedRowText() {
        let card = Palette.panelFill.dark.over(Palette.window.dark)
        let selected = Palette.rowSelected.dark.over(card)
        for text in Self.texts where text.name != "labelTertiaryOnSelection" {
            let ratio = ContrastAuditTests.ratio(label: text.pair, on: selected, .dark)
            #expect(ratio >= ContrastAuditTests.textAA, "\(text.name) on dark rowSelected = \(ratio)")
        }
        let tertiary = ContrastAuditTests.ratio(label: Palette.labelTertiaryOnSelection, on: selected, .dark)
        #expect(Palette.labelTertiaryOnSelection.dark == Palette.labelTertiary.dark)
        withKnownIssue("founder decision: dark selection strength / dark tertiary on a selected row") {
            #expect(tertiary >= ContrastAuditTests.textAA, "tertiary on dark rowSelected = \(tertiary)")
        }
    }
}
