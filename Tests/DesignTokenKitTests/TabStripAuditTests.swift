// R4-TAB — the capsule tab strip's contrast audit (S10.8 PR B). Its own FILE (not just its
// own suite): ContrastAuditTests.swift sits at the SwiftLint file-length limit, and this
// audit shares only the `ratio`/threshold helpers with the base suite.

import DesignTokenKit
import Testing

/// The realigned tab strip: inactive/hover text sits on the carved `tabTrack` composited
/// over the chrome band (the plain window, D4); active text is the new dark-on-teal
/// `onAccent` on the iconFill gradient. The gradient's DEEP bottom stop is deliberately not
/// audited as a text backdrop: the capsule's glyphs sit on the bright/mid span (top-to-center
/// of a 28pt capsule); the deep stop is the bottom rim under the baseline.
@Suite("Contrast audit — capsule tab strip (R4-TAB)")
struct TabStripAuditTests {
    @Test("R4-TAB-01: tab text clears AA on the track and on the active teal capsule")
    func tabStripText() {
        for appearance in TokenAppearance.allCases {
            let window = Palette.window.value(for: appearance)
            let track = Palette.tabTrack.value(for: appearance).over(window)
            // Inactive (labelSecondary) + hovered (label) text on the carved track.
            for (name, label) in [("labelSecondary", Palette.labelSecondary),
                                  ("label", Palette.label)] {
                let ratio = ContrastAuditTests.ratio(label: label, on: track, appearance)
                #expect(ratio >= ContrastAuditTests.textAA,
                        "\(name) on tabTrack⊕window (\(appearance)) = \(ratio)")
            }
            // Active text (#0C1413) on the stops its glyphs actually sit on — this is also
            // the audit that retires the old flagged 2.5:1 white-on-accent (play glyphs).
            for (stopName, stop) in [("iconFillTop", Palette.iconFillTop),
                                     ("iconFillMid", Palette.iconFillMid),
                                     ("accent", Palette.accent)] {
                let backdrop = stop.value(for: appearance)
                let text = Palette.onAccent.value(for: appearance).over(backdrop)
                let ratio = RGBAColor.contrastRatio(text, backdrop)
                #expect(ratio >= ContrastAuditTests.textAA,
                        "onAccent on \(stopName) (\(appearance)) = \(ratio)")
            }
        }
    }
}
