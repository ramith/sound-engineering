// MARK: - ListKeyboardCursor (S10.8 A-review — one cursor resolver per custom list)

/// The keyboard CURSOR of a custom (non-`List`) list — Songs, the queue, the playlist detail,
/// the Library rail: the ONE row its focus ring marks and its keys act on. ↑/↓ move from it,
/// Return activates it, Delete removes it. Each list resolves it once from its own state with
/// `resolve`, so the ring and every key agree by construction (they drifted apart when each
/// handler re-derived "the current row" its own way).
///
/// A cursor is ANCHORED when it sits on a row the user chose — a click or an arrow press; that
/// row also wears the list's selection. It is UNANCHORED when the list seeded it because nothing
/// is chosen yet (the playing row, else the first row); then only the focus ring marks it.
/// Generic over the row id, so the rules are unit-tested without fixtures.
public struct ListKeyboardCursor<ID: Equatable>: Equatable {
    public let id: ID
    public let isAnchored: Bool

    public init(id: ID, isAnchored: Bool) {
        self.id = id
        self.isAnchored = isAnchored
    }

    /// Resolves over the VISIBLE rows, so a filter-hidden or removed anchor never counts: the
    /// anchor when visible, else the `fallback` (e.g. the playing row) when visible, else the
    /// first row. Nil only for an empty list — which should then not be a focus stop at all.
    public static func resolve<Rows: Collection>(
        rows: Rows, anchor: ID?, fallback: ID? = nil
    ) -> ListKeyboardCursor? where Rows.Element == ID {
        if let anchor, rows.contains(anchor) {
            return ListKeyboardCursor(id: anchor, isAnchored: true)
        }
        if let fallback, rows.contains(fallback) {
            return ListKeyboardCursor(id: fallback, isAnchored: false)
        }
        return rows.first.map { ListKeyboardCursor(id: $0, isAnchored: false) }
    }

    /// ↑/↓ — the row the press lands on. An unanchored cursor is claimed IN PLACE: the first press
    /// selects the row the ring already marks, whichever arrow it was, and never skips past it.
    /// An anchored cursor moves `delta` rows. Nil when the move would leave the list (or the
    /// cursor is no longer in `rows`), so the key can bubble.
    public func step<Rows: BidirectionalCollection>(by delta: Int, in rows: Rows) -> ID?
        where Rows.Element == ID {
        guard let position = rows.firstIndex(of: id) else { return nil }
        guard isAnchored else { return id }
        let limit = delta < 0 ? rows.startIndex : rows.index(before: rows.endIndex)
        return rows.index(position, offsetBy: delta, limitedBy: limit).map { rows[$0] }
    }

    /// Return / Delete — the row they act on. Always the cursor when it is anchored (its row wears
    /// the selection); an unanchored cursor only while the ring is drawn, so a key never acts on a
    /// row that nothing on screen marks (e.g. right after a click elsewhere hid the ring).
    public func actionTarget(ringVisible: Bool) -> ID? {
        isAnchored || ringVisible ? id : nil
    }
}

extension ListKeyboardCursor: Sendable where ID: Sendable {}
