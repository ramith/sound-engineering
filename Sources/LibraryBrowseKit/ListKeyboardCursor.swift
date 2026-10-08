// MARK: - ListKeyboardCursor (S10.8 A-review — one cursor resolver per custom list)

/// The keyboard CURSOR of a custom (non-`List`) list — Songs, the queue, the playlist detail,
/// the Library rail: the ONE row its focus ring marks and its keys act on. ↑/↓ move from it,
/// Return activates it, Delete removes it once it is selected. Each list resolves it once from
/// its own state with `resolve`, so the ring and every key agree by construction (they drifted
/// apart when each handler re-derived "the current row" its own way).
///
/// A cursor is ANCHORED when it sits on a row the user chose — a click or an arrow press; that
/// row also wears the list's selection. It is UNANCHORED when the list seeded it because nothing
/// is chosen yet (the playing row, else the first row); then only the focus ring marks it.
/// Generic over the row id, so the rules are unit-tested without fixtures.
public struct ListKeyboardCursor<ID: Equatable>: Equatable {
    public let id: ID
    public let isAnchored: Bool

    /// What the Delete key does (`deleteAction(ringVisible:)`).
    public enum DeleteAction: Equatable {
        /// Remove this row — it is selected, so the user chose it.
        case remove(ID)
        /// Select this row and remove nothing — it was only seeded, so a second Delete is needed.
        case claim(ID)
    }

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

    /// Where the anchor goes once Delete removed `removed` from `rows` (the rows BEFORE the
    /// removal): the row after it, else the row before it — the new last row — else nil (the
    /// list emptied). Holding Delete therefore keeps removing the SELECTED row, walking up from
    /// the end, and never drops the anchor onto an unselected seed such as the playing row.
    public static func anchor<Rows: BidirectionalCollection>(
        afterRemoving removed: ID, from rows: Rows
    ) -> ID? where Rows.Element == ID {
        guard let position = rows.firstIndex(of: removed) else { return nil }
        let next = rows.index(after: position)
        if next != rows.endIndex {
            return rows[next]
        }
        return position == rows.startIndex ? nil : rows[rows.index(before: position)]
    }

    /// ↑/↓ — the row the press lands on. An anchored cursor moves `delta` rows; nil when the move
    /// would leave the list (or the cursor is no longer in `rows`), so the key can bubble.
    ///
    /// An unanchored cursor seeded on the FIRST row is claimed IN PLACE: the first press selects
    /// the row the ring already marks, whichever arrow it was, and never skips past it. Seeded
    /// anywhere else — the queue's playing row, which already wears its own outline, so "stay"
    /// reads as "nothing happened" — the first press moves from it, claiming it in place only
    /// where the move would leave the list.
    public func step<Rows: BidirectionalCollection>(by delta: Int, in rows: Rows) -> ID?
        where Rows.Element == ID {
        guard let position = rows.firstIndex(of: id) else { return nil }
        if !isAnchored, position == rows.startIndex {
            return id
        }
        let limit = delta < 0 ? rows.startIndex : rows.index(before: rows.endIndex)
        let moved = rows.index(position, offsetBy: delta, limitedBy: limit).map { rows[$0] }
        return isAnchored ? moved : moved ?? id
    }

    /// Page Up / Page Down — the row `delta` rows away (the list's page size), STOPPING at the first
    /// or last row instead of bubbling, so a page key always lands on a row. Unlike `step`, a seeded
    /// cursor is never claimed in place: a page press means "go a page", from wherever the ring sits.
    /// Nil only when the cursor is no longer in `rows`.
    public func page<Rows: BidirectionalCollection>(by delta: Int, in rows: Rows) -> ID?
        where Rows.Element == ID {
        guard let position = rows.firstIndex(of: id) else { return nil }
        let limit = delta < 0 ? rows.startIndex : rows.index(before: rows.endIndex)
        return rows[rows.index(position, offsetBy: delta, limitedBy: limit) ?? limit]
    }

    /// Return — the row it activates. Always the cursor when it is anchored (its row wears the
    /// selection); an unanchored cursor only while the ring is drawn, so Return never acts on a
    /// row that nothing on screen marks (e.g. right after a click elsewhere hid the ring).
    /// Activation is not destructive, so the ring alone is mark enough.
    public func activationTarget(ringVisible: Bool) -> ID? {
        isAnchored || ringVisible ? id : nil
    }

    /// Delete — destructive, so it needs a real SELECTION: it removes an anchored cursor's row
    /// and nothing else. On an unanchored cursor (a seeded ring row — e.g. the playing track the
    /// queue rings at launch) it only CLAIMS the row, as an arrow would, so a stray Delete never
    /// removes a row the user did not choose; nil while the ring is hidden, so the key bubbles.
    public func deleteAction(ringVisible: Bool) -> DeleteAction? {
        if isAnchored {
            return .remove(id)
        }
        return ringVisible ? .claim(id) : nil
    }
}

extension ListKeyboardCursor: Sendable where ID: Sendable {}
extension ListKeyboardCursor.DeleteAction: Sendable where ID: Sendable {}
