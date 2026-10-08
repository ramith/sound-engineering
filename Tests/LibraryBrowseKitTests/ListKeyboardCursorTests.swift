import LibraryBrowseKit
import Testing

// MARK: - ListKeyboardCursor (S10.8 A-review — one cursor per custom list)

@Suite("ListKeyboardCursor — the ring row, the arrows, Return and Delete agree")
struct ListKeyboardCursorTests {
    private typealias Cursor = ListKeyboardCursor<Int>
    private let rows = [10, 20, 30, 40]

    // MARK: resolve

    @Test("a visible anchor is the cursor, anchored")
    func anchorWins() {
        #expect(Cursor.resolve(rows: rows, anchor: 30, fallback: 20) == Cursor(id: 30, isAnchored: true))
    }

    @Test("a hidden anchor falls back to the visible fallback, unanchored")
    func hiddenAnchorUsesFallback() {
        #expect(Cursor.resolve(rows: rows, anchor: 99, fallback: 20) == Cursor(id: 20, isAnchored: false))
    }

    @Test("no anchor and a hidden fallback → the first row, unanchored")
    func firstRowSeed() {
        #expect(Cursor.resolve(rows: rows, anchor: nil, fallback: 99) == Cursor(id: 10, isAnchored: false))
        #expect(Cursor.resolve(rows: rows, anchor: nil) == Cursor(id: 10, isAnchored: false))
    }

    @Test("an empty list has no cursor (and so no ring and no focus stop)")
    func emptyList() {
        #expect(Cursor.resolve(rows: [Int](), anchor: 10, fallback: 10) == nil)
    }

    @Test("resolves over a lazy (filtered) view without materialising it")
    func lazyRows() {
        let playable = rows.lazy.filter { $0 != 10 }
        #expect(Cursor.resolve(rows: playable, anchor: 10) == Cursor(id: 20, isAnchored: false))
    }

    // MARK: step

    @Test("an unanchored FIRST-row seed is claimed in place by EITHER arrow — never skipped, never wrapped")
    func unanchoredFirstRowClaimsInPlace() {
        let seed = Cursor(id: 10, isAnchored: false)
        #expect(seed.step(by: 1, in: rows) == 10)
        #expect(seed.step(by: -1, in: rows) == 10) // the old queue jumped ↑ to the LAST row
    }

    @Test("an unanchored seed on the playing row moves on the first arrow")
    func unanchoredPlayingRowMoves() {
        // The playing row already wears a teal outline, so "claim in place" looked like the
        // first ↓/↑ in the queue did nothing (A break-it).
        let playing = Cursor(id: 30, isAnchored: false)
        #expect(playing.step(by: 1, in: rows) == 40)
        #expect(playing.step(by: -1, in: rows) == 20)
    }

    @Test("an unanchored seed at the last row claims in place rather than bubbling off the end")
    func unanchoredLastRowClaimsAtEdge() {
        let playing = Cursor(id: 40, isAnchored: false)
        #expect(playing.step(by: 1, in: rows) == 40)
        #expect(playing.step(by: -1, in: rows) == 30)
    }

    @Test("an anchored cursor moves one row each way")
    func anchoredMoves() {
        let cursor = Cursor(id: 20, isAnchored: true)
        #expect(cursor.step(by: 1, in: rows) == 30)
        #expect(cursor.step(by: -1, in: rows) == 10)
    }

    @Test("a move off either end is nil, so the key bubbles")
    func edgesBubble() {
        #expect(Cursor(id: 10, isAnchored: true).step(by: -1, in: rows) == nil)
        #expect(Cursor(id: 40, isAnchored: true).step(by: 1, in: rows) == nil)
    }

    @Test("a cursor that left the rows cannot step")
    func staleCursor() {
        #expect(Cursor(id: 99, isAnchored: true).step(by: 1, in: rows) == nil)
        #expect(Cursor(id: 99, isAnchored: false).step(by: 1, in: rows) == nil)
    }

    // MARK: page (Page Up / Page Down, E1)

    @Test("a page moves `delta` rows and stops ON the first or last row instead of bubbling")
    func pageStopsAtEnds() {
        let cursor = Cursor(id: 20, isAnchored: true)
        #expect(cursor.page(by: 2, in: rows) == 40)
        #expect(cursor.page(by: 9, in: rows) == 40) // past the end → the last row
        #expect(cursor.page(by: -9, in: rows) == 10) // past the start → the first row
        #expect(Cursor(id: 40, isAnchored: true).page(by: 3, in: rows) == 40) // already last: stays
    }

    @Test("a page moves from a seeded first row at once — no claim in place, unlike an arrow")
    func pageNeverClaimsInPlace() {
        #expect(Cursor(id: 10, isAnchored: false).page(by: 2, in: rows) == 30)
    }

    @Test("a cursor that left the rows cannot page")
    func stalePage() {
        #expect(Cursor(id: 99, isAnchored: true).page(by: 2, in: rows) == nil)
    }

    // MARK: activationTarget (Return)

    @Test("Return acts on an anchored cursor whether or not the ring is drawn")
    func anchoredActivates() {
        let cursor = Cursor(id: 20, isAnchored: true)
        #expect(cursor.activationTarget(ringVisible: false) == 20)
        #expect(cursor.activationTarget(ringVisible: true) == 20)
    }

    @Test("Return acts on an unanchored cursor only while the ring marks it")
    func unanchoredActivatesOnlyWhenMarked() {
        let seed = Cursor(id: 10, isAnchored: false)
        #expect(seed.activationTarget(ringVisible: true) == 10)
        #expect(seed.activationTarget(ringVisible: false) == nil)
    }

    // MARK: deleteAction (Delete)

    @Test("Delete removes an anchored (selected) row whether or not the ring is drawn")
    func anchoredDeletes() {
        let cursor = Cursor(id: 20, isAnchored: true)
        #expect(cursor.deleteAction(ringVisible: false) == .remove(20))
        #expect(cursor.deleteAction(ringVisible: true) == .remove(20))
    }

    @Test("ring visible + no selection → Delete removes nothing; it only claims the ring row")
    func unanchoredDeleteOnlyClaims() {
        // The queue rings the PLAYING row at launch with Full Keyboard Access on: one ⌫ removed
        // it, with no undo (A break-it). The ring is not a selection.
        let playing = Cursor(id: 30, isAnchored: false)
        #expect(playing.deleteAction(ringVisible: true) == .claim(30))
    }

    @Test("ring hidden + no selection → Delete does nothing, so the key bubbles")
    func unanchoredUnmarkedDeleteIsNil() {
        #expect(Cursor(id: 10, isAnchored: false).deleteAction(ringVisible: false) == nil)
    }

    // MARK: anchor(afterRemoving:)

    @Test("after a removal the anchor moves to the next row, else the new last row, else nil")
    func anchorAfterRemoving() {
        #expect(Cursor.anchor(afterRemoving: 20, from: rows) == 30)
        #expect(Cursor.anchor(afterRemoving: 40, from: rows) == 30) // the last row → the new last
        #expect(Cursor.anchor(afterRemoving: 10, from: [10]) == nil) // the list emptied
        #expect(Cursor.anchor(afterRemoving: 99, from: rows) == nil) // not a row
    }

    @Test("holding ⌫ at the end of the queue never reaches an unselected row")
    func repeatedDeleteAtEndStaysOnSelection() {
        // The queue: the playing row (30) is the seed. The user selected the LAST row and holds ⌫.
        // Before the fix the anchor was dropped once it ran off the end, the cursor fell back to
        // the playing row, and the next ⌫ removed the PLAYING track — holding ⌫ chewed around it.
        var queue = rows
        var anchor: Int? = 40
        var removed: [Int] = []
        while let cursor = Cursor.resolve(rows: queue, anchor: anchor, fallback: 30) {
            guard case let .remove(id) = cursor.deleteAction(ringVisible: true) else {
                Issue.record("⌫ reached the unselected row \(cursor.id)")
                return
            }
            #expect(id == anchor) // every removal is the row the user had selected
            anchor = Cursor.anchor(afterRemoving: id, from: queue)
            queue.removeAll { $0 == id }
            removed.append(id)
        }
        #expect(removed == [40, 30, 20, 10]) // walks up from the end, one selected row per ⌫
    }
}
