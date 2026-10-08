import LibraryBrowseKit
import Testing

// MARK: - FixedRowReveal (S10.8 E1 — scroll into view by arithmetic, the End-key hang fix)

@Suite("FixedRowReveal — the least scroll that shows a fixed-height row")
struct FixedRowRevealTests {
    /// Songs' metrics: 48pt rows between 6pt insets; a viewport ten rows tall (480pt).
    private func offset(_ index: Int, top: Double, height: Double = 480) -> Double? {
        FixedRowReveal.offset(revealing: index, rowHeight: 48, inset: 6, visibleTop: top, visibleHeight: height)
    }

    @Test("a row already fully in view needs no scroll")
    func inViewIsNil() {
        #expect(offset(3, top: 0) == nil)
        #expect(offset(12, top: 480) == nil)
    }

    @Test("a row above the view comes in at the top — the first row with the list's top inset")
    func aboveScrollsToItsTop() {
        #expect(offset(5, top: 480) == 240) // row 5's top, less its inset: 6 + 240 - 6
        #expect(offset(0, top: 480) == 0) // Home: back to the very top
    }

    @Test("a row below the view comes in at the bottom, with its inset")
    func belowScrollsToItsBottom() {
        // Row 10's bottom + inset = 480 + 48 + 12 = 540; less the 480pt view.
        #expect(offset(10, top: 0) == 60)
        // End over 10,000 rows: the content's end (6 + 480,000 + 6 = 480,012) at the view's bottom.
        #expect(offset(9999, top: 0) == 479_532)
    }

    @Test("a row exactly at either edge is in view; one point past is not")
    func edges() {
        // Row 5 spans 246…294; less / plus its inset, 240…300.
        #expect(offset(5, top: 240, height: 60) == nil)
        #expect(offset(5, top: 241, height: 60) == 240)
        #expect(offset(5, top: 240, height: 59) == 240) // too short to hold it: its top
        // Row 8 spans 390…438; with its insets it ends at 444.
        #expect(offset(8, top: 0, height: 444) == nil)
        #expect(offset(8, top: 0, height: 443) == 1)
    }

    @Test("a view shorter than a row shows the row's top")
    func shortViewShowsTop() {
        #expect(offset(4, top: 0, height: 20) == 192)
        #expect(offset(4, top: 500, height: 20) == 192)
    }

    @Test("the reveal never depends on how many rows the list has — O(1) by construction")
    func independentOfRowCount() {
        // The signature takes no rows at all: the lazy stack is never asked to place one.
        #expect(offset(1_000_000, top: 0, height: 480) == 47_999_580) // its bottom + inset, 48,000,060, less 480
    }
}
