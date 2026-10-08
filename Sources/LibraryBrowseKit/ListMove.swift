// MARK: - ListMove (S10.8 E4 — Move Up / Down / to Top / to Bottom)

/// A keyboard / menu move of a list's selected rows: the path to reorder a playlist without a drag
/// (an accessibility requirement — design §C's recorded exception). Pure and generic over the row
/// id, so the order arithmetic is unit-tested without fixtures; each list maps the cases to its own
/// titles and shortcuts.
///
/// The selected rows always move as ONE block, in their relative order: Move Up puts the block's
/// first row one place above where the first selected row was, Move Down puts its last row one
/// place below the last, and the edge moves put it at the top or the bottom. A scattered selection
/// therefore gathers into one block on its first move, as a dragged multi-selection does. A move
/// that would change nothing — the block already sits at that edge — is unavailable, which is the
/// "disabled at the edges" rule.
public enum ListMove: CaseIterable, Sendable {
    case toTop
    case up
    case down
    case toBottom

    /// Whether the move changes anything for the rows at `positions` (distinct, `0..<count`) — the
    /// cheap check a menu runs per row; it agrees with `reordering` returning non-nil. Nothing to
    /// move is unavailable; otherwise only a block already against the move's edge is.
    public func isAvailable(forRowsAt positions: some Collection<Int>, count: Int) -> Bool {
        guard let first = positions.min(), let last = positions.max() else { return false }
        let isBlock = last - first + 1 == positions.count
        switch self {
        case .toTop, .up:
            return !isBlock || first > 0
        case .down, .toBottom:
            return !isBlock || last < count - 1
        }
    }

    /// `rows` after moving the rows in `selection` (ids not in `rows` are ignored), or nil when the
    /// move is unavailable. Every row appears exactly once, and the selected rows and the others
    /// each keep their relative order.
    public func reordering<ID: Hashable>(_ rows: [ID], moving selection: Set<ID>) -> [ID]? {
        let positions = rows.indices.filter { selection.contains(rows[$0]) }
        guard let first = positions.first, let last = positions.last,
              isAvailable(forRowsAt: positions, count: rows.count) else { return nil }
        var reordered = rows.filter { !selection.contains($0) }
        reordered.insert(contentsOf: positions.map { rows[$0] },
                         at: blockStart(first: first, last: last, size: positions.count, count: rows.count))
        return reordered
    }

    /// Where the moved block's first row lands, given the first and last selected positions, the
    /// block's size and the list's length.
    private func blockStart(first: Int, last: Int, size: Int, count: Int) -> Int {
        switch self {
        case .toTop:
            0
        case .up:
            max(0, first - 1)
        case .down:
            min(count - 1, last + 1) - (size - 1)
        case .toBottom:
            count - size
        }
    }
}
