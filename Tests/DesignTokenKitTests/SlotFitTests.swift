// §7.1 SlotFitTests — the S9 LUFS-truncation class, asserted headlessly: the widest
// LEGITIMATE string for each fixed slot must fit its slot token. Honestly a gross-misfit
// net: NSFont metrics ≈ (not ==) SwiftUI's resolved font, so the margin absorbs the seam —
// this catches "someone shrank the slot token or widened the format string," not 1-pt clips.
// AppKit is allowed HERE (the TEST target measures); the Kit itself stays UI-import-free.

import AppKit
import DesignTokenKit
import Testing

@Suite("Fixed-slot fit (S9 truncation class)")
struct SlotFitTests {
    /// Measure a string in the app's monospaced small-readout style (`DesignSystem.Font
    /// .monoSmall` = subheadline, monospaced design) at REGULAR weight — the footer time
    /// labels' actual configuration (NowPlayingBar's slot-constrained labels use plain
    /// `monoSmall`; the semibold variant is the scrubber tooltip, which is not
    /// slot-constrained — review MINOR-1).
    private func monoSmallWidth(_ string: String) -> Double {
        let size = NSFont.preferredFont(forTextStyle: .subheadline).pointSize
        let font = NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
        return NSAttributedString(string: string, attributes: [.font: font]).size().width
    }

    /// Derived from the slot token — no magic pixel expectations.
    @Test("SLOT-01: the widest mm:ss fits the footer time-label slot with margin")
    func footerTimeLabelFits() {
        let measured = monoSmallWidth("88:88")
        // 2pt margin: absorbs the NSFont↔SwiftUI metric seam without masking a slot shrink.
        #expect(measured <= SlotWidths.footerTimeLabel - 2,
                "'88:88' measures \(measured)pt against the \(SlotWidths.footerTimeLabel)pt slot")
    }

    /// D5 chrome readout: the widest legitimate rate `SignalPathInfo.rateString` emits is a
    /// high-res fractional string — "176.4 kHz" (176 400 Hz, 9 chars). Literal here (the
    /// formatter lives in the app target, out of the Kit test's reach); if the format string
    /// ever changes, update both.
    @Test("SLOT-02: the widest sample-rate string fits the chrome device-pill readout slot")
    func chromeSampleRateFits() {
        let measured = monoSmallWidth("176.4 kHz")
        #expect(measured <= SlotWidths.chromeSampleRate - 2,
                "'176.4 kHz' measures \(measured)pt against the \(SlotWidths.chromeSampleRate)pt slot")
    }

    /// The footer signal slot renders `Circle(6pt) + HStack(spacing:5) + Text` (NowPlayingBar
    /// R4); the widest legitimate text is the Enhanced path at a fractional hi-res rate.
    /// The 120pt slot truncated "Enhanced · 48 kHz" to "48 k…" the moment Enhanced published
    /// a real rate (founder screenshot, PR-6 round) — this asserts the full composition fits.
    @Test("SLOT-03: the widest signal-path readout (+ status dot) fits the footer signal slot")
    func footerSignalSlotFits() {
        let dotAndGap = 6.0 + 5.0 // NowPlayingBar R4: 6pt status dot + HStack spacing 5
        let measured = monoSmallWidth("Enhanced · 176.4 kHz") + dotAndGap
        #expect(measured <= SlotWidths.footerSignalSlot - 2,
                "dot + 'Enhanced · 176.4 kHz' measures \(measured)pt against the \(SlotWidths.footerSignalSlot)pt slot")
    }

    /// The filter pill (S10.8 D2) at its narrowest must still show its whole placeholder: the
    /// founder saw "Filter que" in the queue header at 880×640, a 90pt pill. The pill is
    /// inset + magnifier + gap + text + inset (`FilterPillMetrics`, what `FilterPill` draws with);
    /// the magnifier at the callout size, the text at the body size — `FilterPill`'s two fonts. The
    /// prompts are literals (the views live in the app target): the queue's, and the Library card
    /// header's "Filter <category>". AppKit's magnifier is 1pt wider than SwiftUI's, so the
    /// measure errs wide.
    @Test("SLOT-06: every filter pill's placeholder fits the pill at its narrowest")
    func filterPillPlaceholderFits() throws {
        let callout = NSFont.preferredFont(forTextStyle: .callout).pointSize
        let magnifier = try #require(NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: callout, weight: .regular)))
        let chrome = 2 * FilterPillMetrics.horizontalInset + magnifier.size.width + FilterPillMetrics.itemSpacing
        let body = NSFont.preferredFont(forTextStyle: .body)
        let slots: [(prompt: String, width: Double)] = [
            ("Filter queue", SlotWidths.queueFilter),
            ("Filter Songs", SlotWidths.libraryFilter),
            ("Filter Albums", SlotWidths.libraryFilter),
            ("Filter Artists", SlotWidths.libraryFilter),
            ("Filter Genres", SlotWidths.libraryFilter),
        ]
        for slot in slots {
            let text = NSAttributedString(string: slot.prompt, attributes: [.font: body]).size().width
            // 2pt margin, like the other slots: the NSFont↔SwiftUI seam, never a real misfit.
            #expect(chrome + text <= slot.width - 2,
                    "'\(slot.prompt)' needs \(chrome + text)pt in a \(slot.width)pt pill")
        }
    }
}
