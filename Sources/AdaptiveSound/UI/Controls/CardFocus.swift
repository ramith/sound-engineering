// MARK: - Card focus (S10.8 D fix round, K1 — a filter and the list it filters)

/// Where key focus sits in a host that has a `FilterPill` over a list or grid — Songs, Albums,
/// Artists, Genres, the Now Playing queue, the playlist picker. The host owns ONE value of it
/// (`@FocusState var focus: CardFocus?`): the pill is focused while it equals `.filter`, the list or
/// grid while it equals `.content`. So Escape in the pill hands focus over with a single write
/// (`focus = .content`), never two writes to two focus states that race in one transaction.
enum CardFocus: Hashable {
    /// The filter pill.
    case filter
    /// The list or grid the filter narrows.
    case content
}
