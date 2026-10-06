// SLOT-04 — the Songs column-header row joins the S9 truncation class (see
// DesignTokenKitTests/SlotFitTests for SLOT-01..03): every fixed-width column's header label,
// plus its sort arrow when the column is sortable, must fit the column's own width.
//
// The founder's 2026-10-06 screenshot showed "TRA…" for Track #: a 44pt column cannot hold its
// upper-cased "TRACK #" label. The fix was three compact header labels, the mock's own
// capitalisation, and two slightly wider columns — this test is what keeps the next new column
// (or a relabel, or a width tweak) from reintroducing the truncation.
//
// Honestly a gross-misfit net, like its siblings: NSFont metrics ≈ (not ==) SwiftUI's resolved
// font, so the margin absorbs the seam. AppKit is allowed HERE (the TEST target measures); the
// Kit itself stays UI-import-free.

import AppKit
import LibraryBrowseKit
import Testing

@Suite("Songs column catalog — header fit (S9 truncation class)")
struct SongColumnHeaderFitTests {
    /// Measure a string in the header row's style: `DesignSystem.Font.micro` (subheadline) at
    /// `.heavy`, tracked by `SongColumn.headerTracking` — the same constant the view applies.
    /// (The font itself lives in the app target, out of this test's reach; if the header's text
    /// style ever changes, update both.)
    private func headerWidth(_ string: String) -> Double {
        let size = NSFont.preferredFont(forTextStyle: .subheadline).pointSize
        let font = NSFont.systemFont(ofSize: size, weight: .heavy)
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .kern: SongColumn.headerTracking]
        return NSAttributedString(string: string, attributes: attributes).size().width
    }

    @Test("SLOT-04: every fixed-width column's header (+ sort arrow when sortable) fits its column")
    func everyHeaderFitsItsColumn() {
        let arrow = Double(SongColumn.headerArrowSpacing + SongColumn.headerArrowSize)
        for column in SongColumn.allCases {
            // `index` has no header text; `title` is the one flexible column (min 240, far wider).
            guard column != .index, let width = column.width else { continue }
            let needed = headerWidth(column.headerLabel) + (column.isSortable ? arrow : 0)
            // 2pt margin: absorbs the NSFont↔SwiftUI metric seam without masking a real misfit.
            #expect(needed <= Double(width) - 2,
                    "\(column.rawValue): header '\(column.headerLabel)' needs \(needed)pt in a \(width)pt column")
        }
    }

    /// The compact header is a SHORTENING of the menu label, never a different word list: it may
    /// only drop characters, so VoiceOver's full `label` and the visible header stay recognisably
    /// the same column.
    @Test("SLOT-05: a compact header label is never longer than the full label")
    func compactHeaderNeverLonger() {
        for column in SongColumn.allCases {
            #expect(column.headerLabel.count <= column.label.count,
                    "\(column.rawValue): header '\(column.headerLabel)' vs label '\(column.label)'")
        }
    }
}
