import LibraryBrowseKit
import Testing

// MARK: - ListSelection (S10.8 E1 — the selection kit)

/// The plan's §G names SEL-01…08 without defining them; these are the definitions (E1):
/// - SEL-01 click, ⇧-click, ⌘-click — the same results as the Songs list before the kit.
/// - SEL-02 ↑/↓ move the cursor and the single selection; the ring row is claimed first.
/// - SEL-03 ⇧↑/⇧↓ extend from the anchor — grow, shrink back across it, continue a ⇧-click.
/// - SEL-04 ⌘A selects exactly the CURRENT (filtered) rows.
/// - SEL-05 Home / End, Page Up / Down by the list's page size, stopping at the ends; ⇧ extends.
/// - SEL-06 type-to-select (`ListSelectionTypeSelectTests`).
/// - SEL-07 Esc clears; Return keeps `ListKeyboardCursor`'s activation rule.
/// - SEL-08 the selection survives filtering and re-sorting, by id.
@Suite("ListSelection — the selection kit's mouse and keyboard verbs")
struct ListSelectionTests {
    private typealias Selection = ListSelection<Int>
    private let rows = [10, 20, 30, 40, 50, 60]

    /// A selection made by clicking `id`.
    private func clicked(_ id: Int) -> Selection {
        var selection = Selection()
        selection.click(id, extend: false, toggle: false, in: rows)
        return selection
    }

    // MARK: SEL-01 — clicks

    @Test("SEL-01 a click selects that row alone; it is the anchor and the cursor")
    func plainClick() {
        var selection = clicked(30)
        selection.click(50, extend: false, toggle: false, in: rows)
        #expect(selection.ids == [50])
        #expect(selection.anchor == 50)
        #expect(selection.cursor == 50)
    }

    @Test("SEL-01 ⇧-click selects anchor…row either way round, keeps the anchor, moves the cursor")
    func shiftClickRange() {
        var selection = clicked(30)
        selection.click(50, extend: true, toggle: false, in: rows)
        #expect(selection.ids == [30, 40, 50])
        #expect(selection.anchor == 30)
        #expect(selection.cursor == 50)
        selection.click(10, extend: true, toggle: false, in: rows) // re-ranges from the SAME anchor
        #expect(selection.ids == [10, 20, 30])
        #expect(selection.anchor == 30)
    }

    @Test("SEL-01 ⌘-click toggles a row in and out and re-anchors on it")
    func commandClickToggles() {
        var selection = clicked(20)
        selection.click(40, extend: false, toggle: true, in: rows)
        #expect(selection.ids == [20, 40])
        #expect(selection.anchor == 40)
        selection.click(20, extend: false, toggle: true, in: rows)
        #expect(selection.ids == [40])
        #expect(selection.anchor == 20)
        #expect(selection.cursor == 20)
    }

    @Test("SEL-01 ⇧-click with no anchor, or a filter-hidden one, acts as the click without ⇧")
    func shiftClickWithoutAnchor() {
        var fresh = Selection()
        fresh.click(30, extend: true, toggle: false, in: rows)
        #expect(fresh.ids == [30])
        #expect(fresh.anchor == 30)

        var hidden = clicked(10)
        hidden.click(40, extend: true, toggle: true, in: [20, 30, 40]) // 10 filtered out; ⌘ also held
        #expect(hidden.ids == [10, 40]) // the ⌘ toggle, not a range from the hidden anchor
    }

    @Test("SEL-01 ⇧ wins over ⌘ when both are held and the anchor is visible")
    func shiftWinsOverCommand() {
        var selection = clicked(20)
        selection.click(40, extend: true, toggle: true, in: rows)
        #expect(selection.ids == [20, 30, 40])
    }

    // MARK: SEL-02 — ↑/↓

    @Test("SEL-02 with nothing chosen the first arrow claims the ring row (the first row) in place")
    func firstArrowClaimsFirstRow() {
        var down = Selection()
        #expect(down.move(.step(1), extend: false, in: rows) == 10)
        #expect(down.ids == [10])
        var up = Selection()
        #expect(up.move(.step(-1), extend: false, in: rows) == 10)
    }

    @Test("SEL-02 ↑/↓ move the cursor, the single selection and the anchor together")
    func arrowsMove() {
        var selection = clicked(30)
        #expect(selection.move(.step(1), extend: false, in: rows) == 40)
        #expect(selection.ids == [40])
        #expect(selection.anchor == 40)
        #expect(selection.move(.step(-1), extend: false, in: rows) == 30)
    }

    @Test("SEL-02 an arrow past either end moves nothing, so the key bubbles")
    func arrowsStopAtEnds() {
        var top = clicked(10)
        #expect(top.move(.step(-1), extend: false, in: rows) == nil)
        #expect(top.ids == [10])
        var bottom = clicked(60)
        #expect(bottom.move(.step(1), extend: false, in: rows) == nil)
    }

    @Test("SEL-02 a plain arrow collapses a multi-selection onto the row it moves to")
    func arrowCollapsesRange() {
        var selection = clicked(20)
        selection.click(40, extend: true, toggle: false, in: rows) // 20…40, cursor 40
        #expect(selection.move(.step(1), extend: false, in: rows) == 50)
        #expect(selection.ids == [50])
    }

    // MARK: SEL-03 — ⇧↑/⇧↓

    @Test("SEL-03 ⇧↓ grows the range from the anchor; ⇧↑ shrinks it back and crosses the anchor")
    func shiftArrowsExtend() {
        var selection = clicked(30)
        selection.move(.step(1), extend: true, in: rows)
        selection.move(.step(1), extend: true, in: rows)
        #expect(selection.ids == [30, 40, 50])
        #expect(selection.anchor == 30)
        #expect(selection.cursor == 50)
        selection.move(.step(-1), extend: true, in: rows)
        selection.move(.step(-1), extend: true, in: rows)
        selection.move(.step(-1), extend: true, in: rows)
        #expect(selection.ids == [20, 30])
        #expect(selection.cursor == 20)
    }

    @Test("SEL-03 ⇧↓ after a ⇧-click continues from the clicked row, not the anchor")
    func shiftArrowContinuesShiftClick() {
        var selection = clicked(20)
        selection.click(40, extend: true, toggle: false, in: rows)
        #expect(selection.move(.step(1), extend: true, in: rows) == 50)
        #expect(selection.ids == [20, 30, 40, 50])
    }

    @Test("SEL-03 ⇧-arrow with nothing selected claims the ring row, then extends from it")
    func shiftArrowFromNothing() {
        var selection = Selection()
        #expect(selection.move(.step(1), extend: true, in: rows) == 10)
        #expect(selection.ids == [10])
        selection.move(.step(1), extend: true, in: rows)
        #expect(selection.ids == [10, 20])
    }

    @Test("SEL-03 ⇧-arrow at an end bubbles and leaves the range alone")
    func shiftArrowAtEnd() {
        var selection = clicked(50)
        selection.move(.step(1), extend: true, in: rows)
        #expect(selection.move(.step(1), extend: true, in: rows) == nil)
        #expect(selection.ids == [50, 60])
    }

    // MARK: SEL-04 — ⌘A

    @Test("SEL-04 ⌘A selects exactly the current (filtered) rows and keeps anchor and cursor")
    func selectAllCurrentRows() {
        var selection = clicked(10)
        let filtered = [20, 40, 60]
        selection.selectAll(in: filtered)
        #expect(selection.ids == [20, 40, 60]) // 10 — hidden by the filter — is let go
        #expect(selection.anchor == 10)
        #expect(selection.cursor == 10)
        // The cursor resolves to the first visible selected row, so Return has a selected target.
        #expect(selection.keyboardCursor(in: filtered) == ListKeyboardCursor(id: 20, isAnchored: true))
    }

    // MARK: SEL-05 — Home / End, Page Up / Down

    @Test("SEL-05 Home and End select the first and last row")
    func homeEnd() {
        var selection = clicked(30)
        #expect(selection.move(.last, extend: false, in: rows) == 60)
        #expect(selection.ids == [60])
        #expect(selection.move(.first, extend: false, in: rows) == 10)
        #expect(selection.ids == [10])
    }

    @Test("SEL-05 ⇧Home / ⇧End extend from the anchor to the end")
    func shiftHomeEnd() {
        var selection = clicked(30)
        selection.move(.last, extend: true, in: rows)
        #expect(selection.ids == [30, 40, 50, 60])
        selection.move(.first, extend: true, in: rows)
        #expect(selection.ids == [10, 20, 30])
    }

    @Test("SEL-05 Page Down / Up move by the list's page size and stop at the ends")
    func pages() {
        var selection = clicked(10)
        #expect(selection.move(.page(2), extend: false, in: rows) == 30)
        #expect(selection.move(.page(2), extend: false, in: rows) == 50)
        #expect(selection.move(.page(2), extend: false, in: rows) == 60) // stops on the last row
        #expect(selection.move(.page(-4), extend: false, in: rows) == 20)
        #expect(selection.move(.page(-4), extend: false, in: rows) == 10)
    }

    @Test("SEL-05 a page key moves at once — the seeded ring row is not claimed in place")
    func pageFromSeed() {
        var selection = Selection()
        #expect(selection.move(.page(3), extend: false, in: rows) == 40)
    }

    @Test("SEL-05 ⇧Page Down extends from the anchor")
    func shiftPage() {
        var selection = clicked(20)
        selection.move(.page(2), extend: true, in: rows)
        #expect(selection.ids == [20, 30, 40])
    }

    @Test("SEL-05 every key on an empty list moves nothing")
    func emptyList() {
        var selection = Selection()
        for movement in [Selection.Movement.step(1), .page(5), .first, .last] {
            #expect(selection.move(movement, extend: false, in: [Int]()) == nil)
        }
        #expect(selection.ids.isEmpty)
    }

    // MARK: SEL-07 — Esc and Return

    @Test("SEL-07 Esc clears the selection and the anchor; the ring keeps its row, unanchored")
    func escClears() {
        var selection = clicked(30)
        selection.click(50, extend: true, toggle: false, in: rows)
        selection.clear()
        #expect(selection.ids.isEmpty)
        #expect(selection.anchor == nil)
        #expect(selection.keyboardCursor(in: rows) == ListKeyboardCursor(id: 50, isAnchored: false))
        // The next arrow moves on from the ring row (not back to the top), and starts a fresh range.
        #expect(selection.move(.step(1), extend: true, in: rows) == 60)
        #expect(selection.ids == [60])
    }

    @Test("SEL-07 Return plays the cursor — the ⇧-moved end of a range — and leaves the range")
    func returnPlaysCursor() {
        var selection = clicked(20)
        selection.move(.step(1), extend: true, in: rows)
        #expect(selection.activate(in: rows, ringVisible: false) == 30)
        #expect(selection.ids == [20, 30])
    }

    @Test("SEL-07 Return on a ring-only row claims it; with the ring hidden it does nothing")
    func returnOnRingRow() {
        var hidden = Selection()
        #expect(hidden.activate(in: rows, ringVisible: false) == nil)
        var ringed = Selection()
        #expect(ringed.activate(in: rows, ringVisible: true) == 10)
        #expect(ringed.ids == [10])
        #expect(ringed.anchor == 10)
    }

    @Test("SEL-07 ⌘-click deselecting the only row: Return can't play it while the ring is hidden")
    func deselectedRowNotPlayed() {
        // A break-it #5: click 20, ⌘-click 20 — the row the user just deselected must not play.
        var selection = clicked(20)
        selection.click(20, extend: false, toggle: true, in: rows)
        #expect(selection.activate(in: rows, ringVisible: false) == nil)
    }

    @Test("SEL-07 ⌘-click deselecting the cursor moves the anchored cursor to a selected row")
    func deselectedCursorFallsToSelection() {
        var selection = clicked(20)
        selection.click(40, extend: false, toggle: true, in: rows)
        selection.click(40, extend: false, toggle: true, in: rows) // cursor 40, now unselected
        #expect(selection.keyboardCursor(in: rows) == ListKeyboardCursor(id: 20, isAnchored: true))
        #expect(selection.activate(in: rows, ringVisible: false) == 20)
    }

    // MARK: SEL-08 — filtering and re-sorting

    @Test("SEL-08 a filter hides selected rows without dropping them; clearing it shows them again")
    func survivesFiltering() {
        var selection = clicked(20)
        selection.click(50, extend: true, toggle: false, in: rows) // 20…50
        let filtered = [10, 30, 60]
        #expect(selection.keyboardCursor(in: filtered) == ListKeyboardCursor(id: 30, isAnchored: true))
        #expect(selection.ids == [20, 30, 40, 50]) // untouched by the filter
    }

    @Test("SEL-08 a ⇧-range covers only the visible rows between its ends")
    func rangeOverVisibleRows() {
        var selection = clicked(10)
        selection.click(50, extend: true, toggle: false, in: [10, 30, 50]) // 20 and 40 hidden
        #expect(selection.ids == [10, 30, 50])
    }

    @Test("SEL-08 a re-sort keeps the selection by id; the cursor follows its row; ⇧↓ uses the new order")
    func survivesResort() {
        var selection = clicked(30)
        selection.move(.step(1), extend: true, in: rows) // 30, 40; cursor 40
        let resorted = [60, 40, 20, 30, 10, 50]
        #expect(selection.keyboardCursor(in: resorted) == ListKeyboardCursor(id: 40, isAnchored: true))
        selection.move(.step(1), extend: true, in: resorted) // the cursor moves to 20
        #expect(selection.ids == [20, 30]) // anchor 30 … cursor 20, in the NEW order
    }

    @Test("a seeded selection anchors on its first row in display order")
    func seeded() {
        let selection = Selection(selecting: [50, 20], in: rows)
        #expect(selection.anchor == 20)
        #expect(selection.cursor == 20)
        #expect(selection.contains(50))
    }
}
