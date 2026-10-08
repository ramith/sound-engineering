// MARK: - ListOrder (S10.8 E4 fix round — the store's reorder rule, for the rows on screen)

/// `LibraryStore.reorderPlaylist`'s rule applied to rows in memory, so the rows on screen are what
/// the store holds once that order is written: the listed ids first, in the listed order (an id
/// listed twice, or not among the rows, is ignored), then every unlisted row in its current order.
/// The playlist detail uses it twice — to move its rows at once, and to lay an order that is not
/// saved yet over a re-read that may predate the write. Keep the two rules in step.
public enum ListOrder {
    /// `rows` in `order`, by the store's rule. Every row appears exactly once.
    public static func applying<Row, ID: Hashable>(_ order: [ID], to rows: [Row], id: KeyPath<Row, ID>) -> [Row] {
        let positions = Dictionary(rows.indices.map { (rows[$0][keyPath: id], $0) },
                                   uniquingKeysWith: { first, _ in first })
        var listedIDs = Set<ID>()
        let listed = order.compactMap { listedIDs.insert($0).inserted ? positions[$0] : nil }
        let placed = Set(listed)
        return (listed + rows.indices.filter { !placed.contains($0) }).map { rows[$0] }
    }
}
