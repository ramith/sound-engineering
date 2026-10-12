// LAY-SET-01 + SLOT-07 — the Settings tab's card column (S10.8 F2) and its status column. Every
// number comes from `SettingsLayout`, which the views are framed to. AppKit measures here (the TEST
// target); the Kit stays UI-free. The strings are literals because the views that draw them live in
// the app target (`PureModeSettingsSection`, `SignalPathStatus`, `SignalPathInfo`): if one changes,
// update it here too. NSFont metrics ≈ (not ==) SwiftUI's, hence the 2 pt margin the other slots use.

import AppKit
import DesignTokenKit
import Testing

@Suite("Settings layout — the card column and the status column (LAY-SET-01, SLOT-07)")
struct SettingsLayoutTests {
    private static let minimumWindow = NowPlayingLayout.windowMinWidth
    private static let defaultWindow = 1000.0
    /// Large text (macOS max ≈ 1.4× default — the Kit's documented headroom factor).
    private static let largeText = NowPlayingLayout.maxTypeHeadroom
    /// The NSFont ↔ SwiftUI metric seam, as in `SlotFitTests`.
    private static let margin = 2.0

    /// The status labels, as `SignalPathStatus` draws them.
    private static let statusLabels = ["Playing through", "Format", "Decoder", "EQ Preset"]
    /// The widest value of each fixed vocabulary: the path, a hi-res format at its widest rate
    /// (`SignalPathInfo.rateString`, 5 digits + " kHz") and bit string (`bitsString`), the decoder, the
    /// EQ while Pure plays, and the longest built-in preset edited (`EQSession.presetLabel`). A My
    /// Preset's name is the user's own and unbounded: it wraps in the value column rather than truncating.
    private static let statusValues = [
        "Enhanced", "705.6 kHz · 32-bit float", "FFmpeg", "Off in Pure Mode", "Bass & Treble · edited",
    ]

    /// `DesignSystem.Font.caption` (callout) — the status labels.
    private static func captionWidth(_ string: String) -> Double {
        let font = NSFont.preferredFont(forTextStyle: .callout)
        return NSAttributedString(string: string, attributes: [.font: font]).size().width
    }

    /// `DesignSystem.Font.caption`, monospaced — the status values.
    private static func captionMonoWidth(_ string: String) -> Double {
        let size = NSFont.preferredFont(forTextStyle: .callout).pointSize
        let font = NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
        return NSAttributedString(string: string, attributes: [.font: font]).size().width
    }

    @Test("LAY-SET-01a: the cards are the readable width, centred with the Twin Panels insets, at 880 and 1000")
    func columnWidth() {
        for window in [Self.minimumWindow, Self.defaultWindow] {
            let card = SettingsLayout.cardWidth(windowWidth: window)
            #expect(card == SettingsLayout.columnMaxWidth, "\(window) pt window: card \(card) pt")
            #expect(card + 2 * SettingsLayout.insetHorizontal <= window, "\(window) pt window: no room for the insets")
        }
        #expect(SettingsLayout.insetTop == EQScreenLayout.insetTop, "the cards' top edge matches Library's and EQ's")
    }

    @Test("SLOT-07a: every status label fits the label column, at default and large text")
    func statusLabelsFit() {
        for label in Self.statusLabels {
            let measured = Self.captionWidth(label)
            #expect(measured <= SettingsLayout.statusLabelWidth - Self.margin,
                    "'\(label)' measures \(measured) pt against the \(SettingsLayout.statusLabelWidth) pt column")
            #expect(measured * Self.largeText <= SettingsLayout.statusLabelWidth - Self.margin,
                    "'\(label)' at large text measures \(measured * Self.largeText) pt")
        }
    }

    @Test("SLOT-07b: every fixed-vocabulary status value fits the value column on one line at the 880 pt window")
    func statusValuesFit() {
        let column = SettingsLayout.statusValueWidth(windowWidth: Self.minimumWindow)
        for value in Self.statusValues {
            let measured = Self.captionMonoWidth(value) * Self.largeText
            #expect(measured <= column - Self.margin,
                    "'\(value)' at large text measures \(measured) pt against the \(column) pt value column")
        }
    }

    /// Each card's title row as `SettingsCard` lays it out: the title, the least gap
    /// (`titleAccessoryGap`, the row's only spacing) and, on Output Device, the chrome's device pill at
    /// its width cap (`DevicePillMetrics.maxWidth`) — side by side at the minimum window, never pushed
    /// under.
    @Test("LAY-SET-01b: a card's title row holds its title beside the device pill at the 880 pt window")
    func titleRowFits() {
        let title = NSFont.systemFont(ofSize: NSFont.preferredFont(forTextStyle: .title3).pointSize,
                                      weight: .semibold)
        let inner = SettingsLayout.cardWidth(windowWidth: Self.minimumWindow) - 2 * SettingsLayout.cardPadding
        for name in ["Output Device", "Pure Mode (Bit-Perfect)"] {
            let measured = NSAttributedString(string: name, attributes: [.font: title]).size().width * Self.largeText
            let row = measured + SettingsLayout.titleAccessoryGap + DevicePillMetrics.maxWidth
            #expect(row <= inner - Self.margin,
                    "'\(name)' at large text + the gap + the pill (\(row) pt) don't fit the \(inner) pt row")
        }
    }
}
