// MARK: - SongsRowResolver (S9.5 — pure play/context row resolution)

/// Pure row-resolution for the Songs table's play/context actions over the VISIBLE (filtered +
/// sorted) set. Generic over `Identifiable` so it needs no `LibraryStore` fixtures to test — the
/// view passes `[LibraryTrackDisplay]`. Extracted from `SongsView` so the "resolve over the visible
/// subset, by id" contract (review #3) is unit-testable rather than an inline closure in the view.
public enum SongsRowResolver {
    /// The single row a selection acts on (single-click Play / Return / Info): the FIRST visible row,
    /// in sort order, whose id is selected. `nil` if the selection matches no visible row. Resolving
    /// by id (not title) keeps duplicate titles distinct and honors the filtered subset.
    public static func primaryRow<Row: Identifiable>(
        in visible: [Row], selection: Set<Row.ID>
    ) -> Row? {
        visible.first { selection.contains($0.id) }
    }

    /// The selected rows in visible (sort) order — multi-select verbs (Play / Play Next / Add to
    /// Queue) operate on this. A selection id that isn't in `visible` (e.g. left over after a filter
    /// hid its row) is dropped, so a multi-select action can never touch an off-screen track.
    public static func orderedSelection<Row: Identifiable>(
        in visible: [Row], selection: Set<Row.ID>
    ) -> [Row] {
        visible.filter { selection.contains($0.id) }
    }
}
