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
}
