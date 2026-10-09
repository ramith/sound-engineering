// MARK: - GridKeyboardCursor (S10.8 decision 20 — arrow keys on the browse grids)

/// The keyboard cursor of a browse grid (Albums, Artists, Genres): the tile its focus ring marks
/// and its keys act on. Built ON `ListKeyboardCursor`, never beside it — the same resolution (the
/// anchor while it is visible, else the first tile, unanchored) and the same Return rule. It adds
/// only the 2-D moves over the tiles in reading order, `columns` to a row.
///
/// ←/→ step through reading order, so they run on across row ends; ↑/↓ step a whole row, and ↓
/// into a ragged last row that has no tile in this column lands on its last tile. All four are
/// arrows in the `ListKeyboardCursor` sense: nil off either end (so the key bubbles) once the
/// cursor is anchored. The first press on the unanchored seed (the first tile) STEPS from it, as
/// from the queue's playing row (K2): a tile has no selected look, so claiming it in place would
/// change nothing on screen; only an arrow that would leave the grid claims the seed where it is.
/// Home / End and Page Up / Down jump to an absolute tile, so they act from the seed at once; the
/// Page keys stop at the first / last row.
public struct GridKeyboardCursor<ID: Equatable>: Equatable {
    private let cursor: ListKeyboardCursor<ID>
    /// Tiles per row, at least 1 (a list is a one-column grid).
    private let columns: Int

    /// A navigation key.
    public enum Move: Equatable, Sendable {
        case left, right, up, down
        /// Home / End.
        case first, last
        /// Page Up / Page Down, by `rows` rows (at least 1).
        case pageUp(rows: Int), pageDown(rows: Int)
    }

    private init(cursor: ListKeyboardCursor<ID>, columns: Int) {
        self.cursor = cursor
        self.columns = max(1, columns)
    }

    /// `ListKeyboardCursor.resolve` over the visible tiles: the anchor while visible, else the first
    /// tile, unanchored. Nil only for an empty grid — which should then not be a focus stop.
    public static func resolve<Rows: Collection>(
        rows: Rows, anchor: ID?, columns: Int
    ) -> GridKeyboardCursor? where Rows.Element == ID {
        ListKeyboardCursor.resolve(rows: rows, anchor: anchor).map { GridKeyboardCursor(cursor: $0, columns: columns) }
    }

    /// The tile the ring marks.
    public var id: ID {
        cursor.id
    }

    /// The tile `move` lands on, or nil when the key should bubble (an arrow off an edge, or a
    /// cursor no longer in `rows`).
    public func target<Rows: RandomAccessCollection>(of move: Move, in rows: Rows) -> ID?
        where Rows.Element == ID {
        guard let index = rows.firstIndex(of: id) else { return nil }
        let place = GridPlace(position: rows.distance(from: rows.startIndex, to: index),
                              last: rows.count - 1, columns: columns)
        if let delta = place.arrowDelta(move) {
            return cursor.step(by: delta, in: rows, claimsFirstRowSeed: false)
        }
        return rows[rows.index(rows.startIndex, offsetBy: place.jumpPosition(move))]
    }

    /// Return — `ListKeyboardCursor.activationTarget`: the anchored tile always, the unanchored
    /// seed only while the ring marks it.
    public func activationTarget(ringVisible: Bool) -> ID? {
        cursor.activationTarget(ringVisible: ringVisible)
    }
}

extension GridKeyboardCursor: Sendable where ID: Sendable {}

/// The cursor's position in reading order on a grid of `last + 1` tiles — the move arithmetic.
private struct GridPlace {
    let position: Int
    let last: Int
    let columns: Int

    private var row: Int {
        position / columns
    }

    private var lastRow: Int {
        last / columns
    }

    /// The arrows' offset in reading order (for `ListKeyboardCursor.step`); nil for the jump keys.
    /// From the last row ↓ asks for a full row, which leaves the grid (nil, or the seed's in-place
    /// claim); above it, a row down is capped at the last tile — the ragged last row.
    func arrowDelta<ID: Equatable>(_ move: GridKeyboardCursor<ID>.Move) -> Int? {
        switch move {
        case .left: -1
        case .right: 1
        case .up: -columns
        case .down: row == lastRow ? columns : min(columns, last - position)
        case .first, .last, .pageUp, .pageDown: nil
        }
    }

    /// Where a jump key lands, in reading order (the arrows stay put — they go through `step`).
    /// Page keys keep the column, stopping at the first / last row; a ragged last row caps a Page
    /// Down at its last tile.
    func jumpPosition<ID: Equatable>(_ move: GridKeyboardCursor<ID>.Move) -> Int {
        switch move {
        case .first: 0
        case .last: last
        case let .pageUp(rows): position - min(max(1, rows), row) * columns
        case let .pageDown(rows): min(position + min(max(1, rows), lastRow - row) * columns, last)
        case .left, .right, .up, .down: position
        }
    }
}
