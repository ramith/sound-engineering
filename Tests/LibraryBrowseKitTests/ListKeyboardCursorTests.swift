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

    @Test("an unanchored cursor is claimed in place by EITHER arrow — never skipped, never wrapped")
    func unanchoredClaimsInPlace() {
        let seed = Cursor(id: 10, isAnchored: false)
        #expect(seed.step(by: 1, in: rows) == 10)
        #expect(seed.step(by: -1, in: rows) == 10) // the old queue jumped ↑ to the LAST row
        let playing = Cursor(id: 30, isAnchored: false)
        #expect(playing.step(by: 1, in: rows) == 30)
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

    // MARK: actionTarget

    @Test("Return/Delete act on an anchored cursor whether or not the ring is drawn")
    func anchoredActs() {
        let cursor = Cursor(id: 20, isAnchored: true)
        #expect(cursor.actionTarget(ringVisible: false) == 20)
        #expect(cursor.actionTarget(ringVisible: true) == 20)
    }

    @Test("Return/Delete act on an unanchored cursor only while the ring marks it")
    func unanchoredActsOnlyWhenMarked() {
        let seed = Cursor(id: 10, isAnchored: false)
        #expect(seed.actionTarget(ringVisible: true) == 10)
        #expect(seed.actionTarget(ringVisible: false) == nil)
    }
}
