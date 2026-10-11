// MARK: - DetailTrackLayout (S10.8 E2/E3 — a detail page's song list, as it is shown)

/// The song list of an album, artist or genre page as it is SHOWN: the songs in display order, what
/// the list draws (`items`), and what playing a row plays. Built once per load from the page's read
/// and its `DetailTrackArrangement`, so the list does no per-row work of its own.
///
/// `rows` is the ONE order on the page: the selection kit's rows (`ListSelection`), the keys' order,
/// and the play order — so what plays is always what is shown, top to bottom (PLAY-02). Knows nothing
/// of Songs' columns or sort (COL-01).
public struct DetailTrackLayout<Track: DetailTrack> {
    /// One line of the list.
    public enum Item: Identifiable {
        /// A song, and the number that leads it.
        case row(Track, number: Int?)

        public var id: ItemID {
            switch self {
            case let .row(track, _): .row(track.id)
            }
        }
    }

    /// A line's identity in the list.
    public enum ItemID: Hashable {
        case row(Track.ID)
    }

    /// The songs in the order shown.
    public let rows: [Track]
    /// What the list draws, in order.
    public let items: [Item]
    /// Each row's place in `rows`, by id — so a click, a key or Return finds its row without a scan.
    private let positions: [Track.ID: Int]

    public init(tracks: [Track], arrangement: DetailTrackArrangement) {
        switch arrangement {
        case .album:
            rows = tracks
            items = tracks.enumerated().map { index, track in .row(track, number: track.trackNo ?? index + 1) }
        }
        // A page lists a song once (the reads are one row per song); were one listed twice, the first wins.
        positions = Dictionary(rows.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// The row's place in `rows`, or nil when it is not on the page.
    public func index(of id: Track.ID) -> Int? {
        positions[id]
    }

    /// What playing a row plays — the page's play context (decision 11): the whole page in the order
    /// shown, starting at that row, so the songs after it follow. (On Songs a row plays alone.) Nil
    /// for a row not on the page.
    public func playFromRow(_ id: Track.ID) -> (tracks: [Track], startIndex: Int)? {
        index(of: id).map { (rows, $0) }
    }
}
