// MARK: - ListSelection (S10.8 E1 — the selection kit for custom lists)

/// The selection of a custom (non-`List`) list, and the mouse and keyboard verbs that change it the
/// way a macOS list does: click, ⇧-click, ⌘-click; ↑/↓ and ⇧↑/⇧↓; Home / End; Page Up / Down; ⌘A;
/// Esc; type-to-select. Built for the Songs rows and meant for the album, artist and genre pages
/// too, so it knows nothing about columns or sort settings (COL-01): a list hands every verb its
/// CURRENT rows — the visible (filtered) ids in display order — and type-to-select the one title
/// it shows.
///
/// Three pieces of state, all by row id:
/// - `ids` — the selected rows. Kept by id, never by position, so a filter that hides rows or a
///   re-sort that moves them leaves the selection as it was; the verbs act only on the rows they
///   are handed, so a hidden row is never range-selected or moved to.
/// - `anchor` — the FIXED end of a ⇧-range: the row last clicked, ⌘-clicked, or moved to without ⇧.
/// - `cursor` — the MOVING end: the row a ⇧-click or ⇧-arrow moved to. It is the row the focus ring
///   marks, the arrows move from and Return plays, through `keyboardCursor(in:)` — so the ring,
///   ↑/↓, Page keys and Return keep `ListKeyboardCursor`'s rules (A-review, A break-it) rather than
///   restating them.
public struct ListSelection<ID: Hashable> {
    public private(set) var ids: Set<ID> = []
    public private(set) var anchor: ID?
    public private(set) var cursor: ID?
    private var typeSelectBuffer = TypeSelectBuffer()

    /// A keyboard move of the cursor.
    public enum Movement: Equatable, Sendable {
        /// ↑ / ↓ — one row (`ListKeyboardCursor.step`): nothing past either end, so the key bubbles.
        case step(Int)
        /// Page Up / Page Down — the signed page size the list supplies (`ListKeyboardCursor.page`),
        /// stopping at the first or last row.
        case page(Int)
        /// Home / End.
        case first, last
    }

    public init() {}

    /// `ids` selected, with the anchor and cursor on the first of them in `rows` order — a selection
    /// seeded from outside the list (the picture-sheet fixture).
    public init<Rows: Collection>(selecting ids: Set<ID>, in rows: Rows) where Rows.Element == ID {
        self.ids = ids
        anchor = rows.first(where: ids.contains)
        cursor = anchor
    }

    public func contains(_ id: ID) -> Bool {
        ids.contains(id)
    }

    /// Whether a context-menu item chosen on row `id` acts on the whole selection — `id` is one of
    /// SEVERAL selected rows that `rows` shows — rather than on the clicked row alone. A selected row a
    /// filter or a reload hid doesn't count (S10.8 E break-it 10): with only the clicked row of the
    /// selection on screen, the menu acts as that row's own does (on a page, Play plays the page from
    /// it). It walks `rows`, so it is asked when an item is CHOSEN — never while a row's menu is built,
    /// which happens with every row the list builds (the S10.8 End-key hang).
    public func menuActsOnSelection<Rows: Sequence>(clicked id: ID, in rows: Rows) -> Bool
        where Rows.Element == ID {
        guard ids.count > 1, ids.contains(id) else { return false }
        var shown = 0
        for row in rows where ids.contains(row) {
            shown += 1
            if shown > 1 {
                return true
            }
        }
        return false
    }

    // MARK: The keyboard cursor

    /// The ONE row the ring marks, the arrows and Page keys move from, and Return plays, over `rows`
    /// (`ListKeyboardCursor`). It is ANCHORED on the cursor while that row is selected and visible,
    /// else on the first visible selected row — so a ⌘-click that deselects the cursor, or a filter
    /// that hides it, never leaves Return playing a row the selection no longer marks. With no
    /// visible selection it rests UNANCHORED on the cursor row (Esc, or a ⌘-click that empties the
    /// selection, leaves the ring where it was), else on the first row.
    public func keyboardCursor<Rows: Collection>(in rows: Rows) -> ListKeyboardCursor<ID>?
        where Rows.Element == ID {
        let selectedCursor = cursor.flatMap { ids.contains($0) && rows.contains($0) ? $0 : nil }
        let chosen = selectedCursor ?? rows.first(where: ids.contains)
        return ListKeyboardCursor.resolve(rows: rows, anchor: chosen, fallback: cursor)
    }

    // MARK: Mouse

    /// A click on `id`. Plain → `id` alone. ⌘ (`toggle`) → `id` added or removed. ⇧ (`extend`) →
    /// every row from the anchor to `id`, the anchor kept. ⇧ with no visible anchor (none yet, or
    /// a filter hid it) acts as the same click without ⇧.
    public mutating func click<Rows: Collection>(_ id: ID, extend: Bool, toggle: Bool, in rows: Rows)
        where Rows.Element == ID {
        typeSelectBuffer.reset()
        let range = extend ? range(to: id, in: rows) : nil
        if range == nil, toggle {
            if ids.remove(id) == nil {
                ids.insert(id)
            }
            anchor = id
            cursor = id
        } else {
            moveCursor(to: id, selecting: range)
        }
    }

    // MARK: Keyboard

    /// ↑/↓, Page Up / Down, Home / End. Without ⇧ the row moved to becomes the whole selection, the
    /// anchor and the cursor; with ⇧ (`extend`) the selection becomes every row from the anchor to
    /// it and only the cursor moves — or, with no visible anchor, it acts as the move without ⇧.
    /// Returns the row moved to (to scroll into view), or nil when the key moves nothing — an arrow
    /// past either end, an empty list — so it can bubble.
    @discardableResult
    public mutating func move<Rows: BidirectionalCollection>(_ movement: Movement, extend: Bool,
                                                             in rows: Rows) -> ID?
        where Rows.Element == ID {
        guard let target = target(of: movement, in: rows) else { return nil }
        typeSelectBuffer.reset()
        moveCursor(to: target, selecting: extend ? range(to: target, in: rows) : nil)
        return target
    }

    /// ⌘A — exactly the rows handed in: the CURRENT (filtered) rows, so a filter-hidden row is not
    /// selected, and one selected earlier is let go. The anchor and cursor stay — a filter-hidden one
    /// too, so clearing the filter takes the range on from it. With NO anchor (a list just opened, or
    /// after Esc) it starts at the cursor's row, else the first row, so a ⇧-key or ⇧-click after ⌘A
    /// narrows the range instead of collapsing it to one row (S10.8 E break-it 7).
    public mutating func selectAll<Rows: Collection>(in rows: Rows) where Rows.Element == ID {
        typeSelectBuffer.reset()
        ids = Set(rows)
        if anchor == nil {
            anchor = cursor.flatMap { ids.contains($0) ? $0 : nil } ?? rows.first
        }
        if cursor == nil {
            cursor = anchor
        }
    }

    /// The list's rows were replaced (a page reloaded under it): only the selected rows it still
    /// shows stay selected, and an anchor or cursor it no longer shows is let go — no ghost ids, which
    /// a menu or a ⇧-range would otherwise count (S10.8 E review 12). Unlike a filter (SEL-08), a
    /// reload doesn't hide rows to bring them back.
    public mutating func keepOnly<Rows: Sequence>(_ rows: Rows) where Rows.Element == ID {
        let shown = Set(rows)
        ids.formIntersection(shown)
        if let anchor, !shown.contains(anchor) {
            self.anchor = nil
        }
        if let cursor, !shown.contains(cursor) {
            self.cursor = nil
        }
    }

    /// Esc — nothing selected and no anchor. The cursor stays, so the ring keeps its row (now
    /// unanchored) and the next arrow moves on from it.
    public mutating func clear() {
        typeSelectBuffer.reset()
        ids = []
        anchor = nil
    }

    /// Return — the row to activate (play), by `ListKeyboardCursor.activationTarget`, or nil. A row
    /// only the ring marked is claimed first, as an arrow would claim it; an anchored row just
    /// becomes the cursor, the selection untouched.
    public mutating func activate<Rows: Collection>(in rows: Rows, ringVisible: Bool) -> ID?
        where Rows.Element == ID {
        guard let keyboardCursor = keyboardCursor(in: rows),
              let target = keyboardCursor.activationTarget(ringVisible: ringVisible) else { return nil }
        typeSelectBuffer.reset()
        if keyboardCursor.isAnchored {
            cursor = target
        } else {
            moveCursor(to: target)
        }
        return target
    }

    /// The rows a keyboard verb acts on (Play Next, Add to Queue, Info — the row menu's verbs from
    /// the keys): the selected rows that are shown, in display order; with none, the cursor row under
    /// Return's rule (`ListKeyboardCursor.activationTarget` — an unanchored cursor only while its ring
    /// is drawn, so a verb never acts on a row nothing on screen marks). Empty when there is neither.
    public func actionTargets<Rows: Collection>(in rows: Rows, ringVisible: Bool) -> [ID]
        where Rows.Element == ID {
        let selected = rows.filter(ids.contains)
        if !selected.isEmpty {
            return selected
        }
        return keyboardCursor(in: rows)?.activationTarget(ringVisible: ringVisible).map { [$0] } ?? []
    }

    /// Type-to-select: `typed` extends the search (a pause of `TypeSelectBuffer.timeout`
    /// starts a new one), and the selection, anchor and cursor jump to the FIRST row in `rows` order
    /// whose `title` starts with it — ignoring case, diacritics and width. Returns that row, or nil when no
    /// title matches; then nothing changes, as in a macOS list.
    @discardableResult
    public mutating func typeSelect<Rows: Collection>(
        _ typed: String, at now: ContinuousClock.Instant, in rows: Rows, title: (Rows.Element) -> String
    ) -> ID? where Rows.Element: Identifiable, Rows.Element.ID == ID {
        let search = typeSelectBuffer.append(typed, at: now)
        guard let match = TypeSelectBuffer.firstMatch(for: search, in: rows, title: title) else { return nil }
        moveCursor(to: match.id)
        return match.id
    }

    // MARK: Private

    /// The cursor moves to `id`. With a ⇧-`range`, that range is the selection and the anchor stays;
    /// without one, `id` alone is the selection and becomes the anchor too.
    private mutating func moveCursor(to id: ID, selecting range: Set<ID>? = nil) {
        if let range {
            ids = range
        } else {
            ids = [id]
            anchor = id
        }
        cursor = id
    }

    /// The ⇧-range: every row from the anchor to `target` in `rows` order, either way round; nil
    /// when there is no anchor or `rows` doesn't hold it (a filter hid it).
    private func range<Rows: Collection>(to target: ID, in rows: Rows) -> Set<ID>?
        where Rows.Element == ID {
        guard let anchor, let start = rows.firstIndex(of: anchor),
              let end = rows.firstIndex(of: target) else { return nil }
        return Set(rows[min(start, end) ... max(start, end)])
    }

    private func target<Rows: BidirectionalCollection>(of movement: Movement, in rows: Rows) -> ID?
        where Rows.Element == ID {
        switch movement {
        case let .step(delta): keyboardCursor(in: rows)?.step(by: delta, in: rows)
        case let .page(delta): keyboardCursor(in: rows)?.page(by: delta, in: rows)
        case .first: rows.first
        case .last: rows.last
        }
    }
}

extension ListSelection: Sendable where ID: Sendable {}
