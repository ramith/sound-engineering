import LibraryBrowseKit
import Testing

// MARK: - GridKeyboardCursor (S10.8 decision 20 — arrow keys on the browse grids)

@Suite("GridKeyboardCursor — 2-D moves over ListKeyboardCursor's rules")
struct GridKeyboardCursorTests {
    private typealias Cursor = GridKeyboardCursor<Int>

    /// Ten tiles, four to a row — a ragged last row:
    ///
    ///     0 1 2 3
    ///     4 5 6 7
    ///     8 9
    private let tiles = Array(0 ..< 10)

    /// The tile `move` lands on from an ANCHORED cursor on `from`.
    private func move(_ move: Cursor.Move, from: Int, columns: Int = 4, in rows: [Int]? = nil) -> Int? {
        let rows = rows ?? tiles
        return Cursor.resolve(rows: rows, anchor: from, columns: columns)?.target(of: move, in: rows)
    }

    // MARK: resolve (ListKeyboardCursor's)

    @Test("a visible anchor is the cursor; a hidden one falls back to the first tile; empty → nil")
    func resolve() {
        #expect(Cursor.resolve(rows: tiles, anchor: 6, columns: 4)?.id == 6)
        #expect(Cursor.resolve(rows: tiles, anchor: 42, columns: 4)?.id == 0)
        #expect(Cursor.resolve(rows: tiles, anchor: nil, columns: 4)?.id == 0)
        #expect(Cursor.resolve(rows: [Int](), anchor: 6, columns: 4) == nil)
    }

    // MARK: ←/→

    @Test("←/→ step through reading order, running on across row ends")
    func leftRight() {
        #expect(move(.left, from: 5) == 4)
        #expect(move(.right, from: 5) == 6)
        #expect(move(.right, from: 3) == 4) // end of row 0 → start of row 1
        #expect(move(.left, from: 4) == 3)
    }

    @Test("←/→ off either end of the grid are nil, so the key bubbles")
    func leftRightEdges() {
        #expect(move(.left, from: 0) == nil)
        #expect(move(.right, from: 9) == nil)
    }

    // MARK: ↑/↓

    @Test("↑/↓ step a whole row in the same column")
    func upDown() {
        #expect(move(.up, from: 5) == 1)
        #expect(move(.down, from: 1) == 5)
        #expect(move(.down, from: 4) == 8)
        #expect(move(.down, from: 5) == 9)
    }

    @Test("↓ into a ragged last row with no tile in this column lands on its last tile")
    func downIntoRaggedRow() {
        #expect(move(.down, from: 6) == 9)
        #expect(move(.down, from: 7) == 9)
    }

    @Test("↑ from the first row and ↓ from the last row are nil, so the key bubbles")
    func upDownEdges() {
        #expect(move(.up, from: 2) == nil)
        #expect(move(.down, from: 8) == nil)
        #expect(move(.down, from: 9) == nil)
    }

    @Test("a full last row: ↓ from it bubbles, and ↓ into it keeps the column")
    func fullLastRow() {
        let even = Array(0 ..< 8) // two full rows of four
        #expect(move(.down, from: 6, in: even) == nil)
        #expect(move(.down, from: 3, in: even) == 7)
    }

    // MARK: The unanchored seed (ListKeyboardCursor's claim rule)

    @Test("the first press of ANY arrow on the unanchored seed claims the first tile in place")
    func seedClaimedInPlace() throws {
        let seed = try #require(Cursor.resolve(rows: tiles, anchor: nil, columns: 4))
        for arrow: Cursor.Move in [.left, .right, .up, .down] {
            #expect(seed.target(of: arrow, in: tiles) == 0)
        }
    }

    @Test("a single-row grid: the seed is still claimed in place by ↓ (never bubbles past the ring)")
    func seedSingleRow() throws {
        let row = [0, 1, 2]
        let seed = try #require(Cursor.resolve(rows: row, anchor: nil, columns: 4))
        #expect(seed.target(of: .down, in: row) == 0)
    }

    // MARK: Home / End

    @Test("Home / End jump to the first / last tile")
    func homeEnd() {
        #expect(move(.first, from: 6) == 0)
        #expect(move(.last, from: 6) == 9)
        #expect(move(.first, from: 0) == 0) // already there: handled, nothing moves
    }

    @Test("Home / End act from the unanchored seed at once (an absolute jump, not an arrow)")
    func homeEndFromSeed() throws {
        let seed = try #require(Cursor.resolve(rows: tiles, anchor: nil, columns: 4))
        #expect(seed.target(of: .last, in: tiles) == 9)
        #expect(seed.target(of: .first, in: tiles) == 0)
    }

    // MARK: Page Up / Down

    @Test("Page Down moves a page of rows in the same column")
    func pageDown() {
        #expect(move(.pageDown(rows: 1), from: 1) == 5)
        #expect(move(.pageDown(rows: 2), from: 1) == 9)
    }

    @Test("Page Down stops at the last row; a ragged last row caps it at the last tile")
    func pageDownStops() {
        #expect(move(.pageDown(rows: 5), from: 1) == 9) // row 2 has column 1
        #expect(move(.pageDown(rows: 5), from: 2) == 9) // row 2 has no column 2 → its last tile
        #expect(move(.pageDown(rows: 5), from: 8) == 8) // already in the last row: stays
    }

    @Test("Page Up moves a page of rows up, stopping at the first row")
    func pageUp() {
        #expect(move(.pageUp(rows: 1), from: 9) == 5)
        #expect(move(.pageUp(rows: 10), from: 6) == 2)
        #expect(move(.pageUp(rows: 3), from: 3) == 3) // already in the first row: stays
    }

    @Test("a page is at least one row")
    func pageAtLeastOneRow() {
        #expect(move(.pageDown(rows: 0), from: 1) == 5)
        #expect(move(.pageUp(rows: -2), from: 5) == 1)
    }

    @Test("Page Down from the unanchored seed moves at once")
    func pageFromSeed() throws {
        let seed = try #require(Cursor.resolve(rows: tiles, anchor: nil, columns: 4))
        #expect(seed.target(of: .pageDown(rows: 1), in: tiles) == 4)
    }

    // MARK: Columns (the layout supplies them)

    @Test("a column change on resize keeps the cursor's tile and re-flows the rows under it")
    func columnChangeOnResize() {
        // Four columns: 5 is row 1 / column 1. Three columns (0 1 2 · 3 4 5 · 6 7 8 · 9): 5 is row 1 / column 2.
        #expect(move(.down, from: 5, columns: 4) == 9)
        #expect(move(.down, from: 5, columns: 3) == 8)
        #expect(move(.up, from: 5, columns: 3) == 2)
        #expect(move(.down, from: 7, columns: 3) == 9) // the new ragged row
        #expect(move(.down, from: 9, columns: 3) == nil)
    }

    @Test("one column is a list: ↑/↓ step one tile; zero or negative columns count as one")
    func oneColumn() {
        #expect(move(.down, from: 4, columns: 1) == 5)
        #expect(move(.up, from: 4, columns: 1) == 3)
        #expect(move(.down, from: 4, columns: 0) == 5)
        #expect(move(.down, from: 4, columns: -3) == 5)
    }

    @Test("more columns than tiles: one row, ↓ and ↑ bubble, ←/→ still walk it")
    func wideGrid() {
        let row = [0, 1, 2]
        #expect(move(.down, from: 1, columns: 8, in: row) == nil)
        #expect(move(.up, from: 1, columns: 8, in: row) == nil)
        #expect(move(.right, from: 1, columns: 8, in: row) == 2)
    }

    // MARK: Staleness and laziness

    @Test("a cursor no longer in the rows cannot move")
    func staleCursor() throws {
        let cursor = try #require(Cursor.resolve(rows: tiles, anchor: 6, columns: 4))
        #expect(cursor.target(of: .right, in: [1, 2, 3]) == nil)
        #expect(cursor.target(of: .last, in: [1, 2, 3]) == nil)
    }

    @Test("works over a lazy view of the tiles")
    func lazyRows() {
        let ids = tiles.lazy.map { $0 * 10 }
        #expect(Cursor.resolve(rows: ids, anchor: 50, columns: 4)?.target(of: .down, in: ids) == 90)
    }

    // MARK: Return (ListKeyboardCursor's activation rule)

    @Test("Return opens an anchored tile with or without the ring; the unanchored seed only under the ring")
    func activation() throws {
        let anchored = try #require(Cursor.resolve(rows: tiles, anchor: 6, columns: 4))
        #expect(anchored.activationTarget(ringVisible: false) == 6)
        #expect(anchored.activationTarget(ringVisible: true) == 6)
        let seed = try #require(Cursor.resolve(rows: tiles, anchor: nil, columns: 4))
        #expect(seed.activationTarget(ringVisible: true) == 0)
        #expect(seed.activationTarget(ringVisible: false) == nil)
    }
}
