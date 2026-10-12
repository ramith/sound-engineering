import LibraryBrowseKit
import Testing

// MARK: - ListSelection after ⌘A and across a reload (S10.8 E break-it 7, review 12)

@Suite("ListSelection — ⌘A's anchor, and a page reloaded under the selection")
struct ListSelectionReloadTests {
    private typealias Selection = ListSelection<Int>
    private let rows = [10, 20, 30, 40, 50]

    @Test("⌘A on a list with no anchor starts the range at the first row — ⇧↓ narrows it, never collapses")
    func selectAllAnchorsAFreshList() {
        var selection = Selection()
        selection.selectAll(in: rows)
        #expect(selection.anchor == 10)
        #expect(selection.cursor == 10)
        selection.move(.step(1), extend: true, in: rows)
        #expect(selection.ids == [10, 20]) // the range from the anchor to the cursor's new row
    }

    @Test("⌘A after Esc starts the range at the cursor's row, where the ring was")
    func selectAllAfterEscapeAnchorsTheCursor() {
        var selection = Selection()
        selection.click(30, extend: false, toggle: false, in: rows)
        selection.clear() // Esc: no anchor; the ring stays on 30
        selection.selectAll(in: rows)
        #expect(selection.anchor == 30)
        selection.move(.last, extend: true, in: rows) // ⇧End
        #expect(selection.ids == [30, 40, 50])
    }

    @Test("a reload keeps the selected rows it still shows, and lets go of every other id")
    func keepOnlyDropsGhosts() {
        var selection = Selection()
        selection.click(20, extend: false, toggle: false, in: rows)
        selection.click(40, extend: true, toggle: false, in: rows) // 20…40, anchor 20, cursor 40
        selection.keepOnly([10, 30, 40, 50]) // 20 left the page
        #expect(selection.ids == [30, 40])
        #expect(selection.anchor == nil) // gone with its row
        #expect(selection.cursor == 40)
        selection.keepOnly([10, 30, 50]) // and 40
        #expect(selection.ids == [30])
        #expect(selection.cursor == nil)
        #expect(selection.keyboardCursor(in: [10, 30, 50]) == ListKeyboardCursor(id: 30, isAnchored: true))
    }

    @Test("a reload that keeps every row changes nothing")
    func keepOnlyWithSameRows() {
        var selection = Selection()
        selection.click(20, extend: false, toggle: false, in: rows)
        selection.click(40, extend: true, toggle: false, in: rows)
        let before = selection
        selection.keepOnly(rows.reversed())
        #expect(selection.ids == before.ids)
        #expect(selection.anchor == before.anchor)
        #expect(selection.cursor == before.cursor)
    }
}
