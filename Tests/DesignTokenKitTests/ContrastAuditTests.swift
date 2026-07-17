// R4 — the PERMANENT contrast audit (design §7 R4): pure sRGB compositing + WCAG math over
// Kit token data, so "the palette is legible" is a forever-green `swift test` fact, not a
// one-off audit. PR 1a scope = the LEGACY pairs (window/card/panel × label hierarchy — the
// D10 net: when PR 2 re-bases the dark stack, these pairs re-verify the untouched tabs by
// math). Glow/lens/panel-role composites join in PRs 2–5 per the §7 R4 pair table.
//
// Thresholds are the WCAG constants, never tuned: ≥ 4.5:1 text AA; ≥ 3.0:1 non-text.

import DesignTokenKit
import Testing

@Suite("Contrast audit — legacy surfaces (R4)")
struct ContrastAuditTests {
    /// AA threshold for text (WCAG 1.4.3).
    private static let textAA = 4.5

    /// The surfaces labels sit on today: the window itself, and card/panel composited over
    /// the window (they are translucent in dark mode — compositing IS the audit's point).
    private static func surfaces(_ appearance: TokenAppearance) -> [(name: String, color: RGBAColor)] {
        let window = Palette.window.value(for: appearance)
        return [
            ("window", window),
            ("card⊕window", Palette.card.value(for: appearance).over(window)),
            ("panel⊕window", Palette.panel.value(for: appearance).over(window)),
        ]
    }

    /// Effective text color = the (translucent) label composited onto its surface; the
    /// ratio is then between two opaque colors, per WCAG method.
    private static func ratio(label: AppearancePair, on surface: RGBAColor,
                              _ appearance: TokenAppearance) -> Double {
        let text = label.value(for: appearance).over(surface)
        return RGBAColor.contrastRatio(text, surface)
    }

    @Test("R4-LEG-01: label + labelSecondary clear AA on window/card/panel, both appearances")
    func primaryAndSecondaryLabels() {
        for appearance in TokenAppearance.allCases {
            for surface in Self.surfaces(appearance) {
                for (name, label) in [("label", Palette.label),
                                      ("labelSecondary", Palette.labelSecondary)] {
                    let ratio = Self.ratio(label: label, on: surface.color, appearance)
                    #expect(ratio >= Self.textAA,
                            "\(name) on \(surface.name) (\(appearance)) = \(ratio) < \(Self.textAA)")
                }
            }
        }
    }

    /// The S9 audit lifted tertiary for this — but it measured against the WINDOW, not the
    /// translucent card/panel COMPOSITES. This audit's first real find (2026-07-17):
    /// tertiary on panel⊕window (dark) is 4.4601:1 — a genuine pre-existing shortfall,
    /// pinned as a known issue (PR 1a is zero-visual-change) and scheduled for the D10
    /// deep-base re-tune (PR 2), which re-tunes exactly these composites. When PR 2 fixes
    /// it, withKnownIssue flips to "unexpectedly passed" — the reminder to promote it.
    @Test("R4-LEG-02: labelTertiary clears AA (one pinned pre-existing dark-panel shortfall)")
    func tertiaryLabel() {
        for appearance in TokenAppearance.allCases {
            for surface in Self.surfaces(appearance) {
                let ratio = Self.ratio(label: Palette.labelTertiary, on: surface.color, appearance)
                if appearance == .dark, surface.name == "panel⊕window" {
                    withKnownIssue("labelTertiary dark on panel⊕window = 4.46:1 — pre-existing; PR-2 D10 re-tune") {
                        #expect(ratio >= Self.textAA)
                    }
                } else {
                    #expect(ratio >= Self.textAA,
                            "labelTertiary on \(surface.name) (\(appearance)) = \(ratio) < \(Self.textAA)")
                }
            }
        }
    }

    /// statusError aliases today's Color.red look byte-for-byte (PR 1a is zero-visual-change),
    /// and the audit shows that look was NEVER AA except on the dark window (its actual
    /// placement today — the meters sit on the window, no card behind): measured 2026-07-17
    /// dark card⊕window 4.32:1, dark panel⊕window 4.12:1, light all ≈3.0–3.5:1. All pinned
    /// as known issues scheduled for the PR-6 meters/footer restyle (a token-value fix).
    @Test("R4-LEG-03: statusError clears AA on its actual dark surface; rest pinned to PR 6")
    func statusErrorText() {
        // The real placement today: the meters render on the dark window — must pass outright.
        let window = Palette.window.dark
        let onWindow = RGBAColor.contrastRatio(Palette.statusError.dark.over(window), window)
        #expect(onWindow >= Self.textAA, "statusError on window (dark) = \(onWindow) < \(Self.textAA)")

        // Worst-case sweep (dark card/panel composites + all light surfaces): pre-existing
        // shortfalls — tracked, not silently passed, not silently fixed.
        withKnownIssue("statusError off-window surfaces fail AA — pre-existing Color.red look; PR-6 restyle") {
            for surface in Self.surfaces(.dark) where surface.name != "window" {
                let text = Palette.statusError.dark.over(surface.color)
                #expect(RGBAColor.contrastRatio(text, surface.color) >= Self.textAA)
            }
            for surface in Self.surfaces(.light) {
                let text = Palette.statusError.light.over(surface.color)
                #expect(RGBAColor.contrastRatio(text, surface.color) >= Self.textAA)
            }
        }
    }
}
