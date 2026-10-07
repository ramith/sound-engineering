// The R4 LIGHT pair table (S10.8 B2b), as data: the light text and non-text pairs the base R4
// suites audit on the plain window (each row names its source), so the candidate light windows
// (LightBackdropAuditTests) and the pale light glow (LightGlowAuditTests) replay the SAME pairs
// on their own backdrops — tuning a token re-verifies every backdrop with no second table.

import DesignTokenKit
import Testing

enum LightPairs {
    /// A token (text or non-text) on a stack of fills composited bottom-up over the backdrop.
    struct Pair {
        let name: String
        let token: AppearancePair
        let fills: [AppearancePair]
        let threshold: Double
    }

    private typealias Named = (name: String, pair: AppearancePair)
    private typealias Stack = (name: String, fills: [AppearancePair])

    private static let hierarchy: [Named] = [
        ("label", Palette.label), ("labelSecondary", Palette.labelSecondary),
        ("labelTertiary", Palette.labelTertiary),
    ]
    private static let primaryPair: [Named] = [("label", Palette.label), ("labelSecondary", Palette.labelSecondary)]

    private static let window: Stack = ("window", [])
    private static let card: Stack = ("card", [Palette.card])
    private static let panel: Stack = ("panel", [Palette.panel])
    private static let panelFill: Stack = ("panelFill", [Palette.panelFill])
    private static let badgeFill: Stack = ("badgeFill", [Palette.badgeFill])
    private static let rowNowPlaying: Stack = ("rowNowPlaying", [Palette.rowNowPlaying])
    private static let rowSelected: Stack = ("rowSelected", [Palette.rowSelected])

    /// Every pair, with the base suite it mirrors.
    static let all: [Pair] = [
        pairs(hierarchy, on: [window, card, panel, panelFill], ContrastAuditTests.textAA,
              "R4-LEG-01/02, R4-PANEL-01"),
        pairs([("labelNav", Palette.labelNav)], on: [panelFill], ContrastAuditTests.textAA, "R4-LEG-LIB-01"),
        pairs(primaryPair, on: [("lensFill", [Palette.lensFill]), ("controlHover", [Palette.controlHover]),
                                ("tabTrack", [Palette.tabTrack]), badgeFill],
              ContrastAuditTests.textAA, "R4-LENS-01, R4-CHIP-01, R4-TAB-01, R4-CONTROL-01"),
        pairs([("statusWarningText", Palette.statusWarningText)], on: [badgeFill], ContrastAuditTests.textAA,
              "R4-BADGE-01"),
        pairs([("label", Palette.label)], on: [("segmentSelected", [Palette.tabTrack, Palette.segmentSelected])],
              ContrastAuditTests.textAA, "R4-CHIP-01"),
        pairs([("accentText", Palette.accentText)], on: [("controlActiveFill", [Palette.controlActiveFill])],
              ContrastAuditTests.textAA, "R4-CHIP-01"),
        pairs([("statusErrorText", Palette.statusErrorText), ("statusWarningText", Palette.statusWarningText)],
              on: [window, card, panel], ContrastAuditTests.textAA, "R4-LEG-03"),
        pairs([("statusError", Palette.statusError)], on: [window, card, panel], ContrastAuditTests.nonTextAA,
              "R4-LEG-03"),
        pairs([("accentForeground", Palette.accentForeground)], on: [window, panelFill, badgeFill],
              ContrastAuditTests.textAA, "R4-TINT-02"),
        pairs([("accentFill", Palette.accentFill)], on: [window, panelFill], ContrastAuditTests.nonTextAA,
              "R4-TINT-01"),
        pairs([("onAccent", Palette.onAccent)], on: [("accentFill", [Palette.accentFill])],
              ContrastAuditTests.nonTextAA, "R4-TINT-04"),
        pairs([("focusRing", Palette.focusRing)],
              on: [window, panelFill, rowSelected, rowNowPlaying,
                   ("panelFill+rowSelected", [Palette.panelFill, Palette.rowSelected]),
                   ("panelFill+rowNowPlaying", [Palette.panelFill, Palette.rowNowPlaying])],
              ContrastAuditTests.nonTextAA, "R4-FOCUS-01/02"),
        pairs([("label", Palette.label)], on: [rowNowPlaying, rowSelected], ContrastAuditTests.textAA,
              "R4-GLOW-02"),
        pairs([("accentTitle", Palette.accentTitle), ("accentText", Palette.accentText)], on: [rowNowPlaying],
              ContrastAuditTests.textAA, "R4-ROW-01"),
        pairs([("meterHotText", Palette.meterHotText)], on: [panelFill], ContrastAuditTests.textAA, "R4-METER-01"),
        pairs([("meterHot", Palette.meterHot)], on: [panelFill], ContrastAuditTests.nonTextAA, "R4-METER-01"),
    ].flatMap(\.self)

    private static func pairs(_ tokens: [Named], on stacks: [Stack], _ threshold: Double,
                              _ source: String) -> [Pair] {
        tokens.flatMap { token in
            stacks.map { stack in
                Pair(name: "\(token.name) on \(stack.name) (\(source))", token: token.pair, fills: stack.fills,
                     threshold: threshold)
            }
        }
    }

    /// Every pair, in LIGHT, on an opaque light `backdrop`; `site` names where it was sampled.
    static func expectAll(on backdrop: RGBAColor, _ site: String) {
        for pair in all {
            let surface = pair.fills.reduce(backdrop) { $1.light.over($0) }
            let ratio = ContrastAuditTests.ratio(label: pair.token, on: surface, .light)
            #expect(ratio >= pair.threshold, "\(pair.name) over \(site) = \(ratio)")
        }
    }
}
