// MARK: - GridCursorState (S10.8 decision 20 — what a browse grid's keyboard remembers)

/// What a browse grid's keyboard remembers between presses: the ANCHOR — the tile the user chose
/// (nil until then: the cursor is the first tile, unanchored, `GridKeyboardCursor.resolve`) — and
/// the type-to-select prefix. The grids' counterpart of E1's `ListSelection` (a grid has a cursor
/// but no selection), with the same rule for the prefix: any other way the cursor moves ends it.
/// So "b", →, "o" searches "o", not "bo" — the prefix never outlives the tile it found.
public struct GridCursorState<ID: Equatable> {
    public private(set) var anchor: ID?
    private var typeSelectBuffer = TypeSelectBuffer()

    public init() {}

    /// The keyboard cursor over the visible tiles, `columns` to a row.
    public func cursor<Rows: Collection>(in rows: Rows, columns: Int) -> GridKeyboardCursor<ID>?
        where Rows.Element == ID {
        GridKeyboardCursor.resolve(rows: rows, anchor: anchor, columns: columns)
    }

    /// A navigation key: the tile it lands on becomes the anchor, and the prefix ends. Nil — and
    /// nothing changes — when the key should bubble.
    public mutating func move<Rows: RandomAccessCollection>(
        _ move: GridKeyboardCursor<ID>.Move, in rows: Rows, columns: Int
    ) -> ID? where Rows.Element == ID {
        guard let target = cursor(in: rows, columns: columns)?.target(of: move, in: rows) else { return nil }
        choose(target)
        return target
    }

    /// Type-to-select: `typed` extends the prefix (a pause of `TypeSelectBuffer.timeout` starts a new
    /// one), and the first tile in `items` order whose `title` starts with it becomes the anchor. Nil
    /// — the anchor unchanged — when no title matches.
    public mutating func typeSelect<Items: Collection>(
        _ typed: String, at now: ContinuousClock.Instant, in items: Items, title: (Items.Element) -> String
    ) -> ID? where Items.Element: Identifiable, Items.Element.ID == ID {
        let prefix = typeSelectBuffer.append(typed, at: now)
        guard let match = TypeSelectBuffer.firstMatch(for: prefix, in: items, title: title) else { return nil }
        anchor = match.id
        return match.id
    }

    /// The cursor set from outside the keys — the tile being opened, or the one a return brought
    /// back (D6). The prefix ends.
    public mutating func choose(_ id: ID) {
        typeSelectBuffer.reset()
        anchor = id
    }

    /// The grid lost key focus: the prefix ends (the anchor stays for when focus comes back).
    public mutating func endTyping() {
        typeSelectBuffer.reset()
    }
}

extension GridCursorState: Sendable where ID: Sendable {}
