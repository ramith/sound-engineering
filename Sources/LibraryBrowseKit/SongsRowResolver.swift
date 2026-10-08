// MARK: - SongsRowResolver (S9.5 — pure play/context row resolution)

/// Pure row-resolution for the Songs table's play/context actions over the VISIBLE (filtered +
/// sorted) set. Generic over `Identifiable` so it needs no `LibraryStore` fixtures to test — the
/// view passes `[LibraryTrackDisplay]`. Extracted from `SongsView` so the "resolve over the visible
/// subset, by id" contract (review #3) is unit-testable rather than an inline closure in the view.
public enum SongsRowResolver {
    /// The selected rows in visible (sort) order — multi-select verbs (Play / Play Next / Add to
    /// Queue) operate on this. A selection id that isn't in `visible` (e.g. left over after a filter
    /// hid its row) is dropped, so a multi-select action can never touch an off-screen track. An
    /// O(n) walk: call it when a verb runs, never while building a row (the S10.8 End-key hang).
    public static func orderedSelection<Row: Identifiable>(
        in visible: [Row], selection: Set<Row.ID>
    ) -> [Row] {
        visible.filter { selection.contains($0.id) }
    }
}
