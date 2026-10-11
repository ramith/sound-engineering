// MARK: - DetailTrackLayout (S10.8 E2/E3 — a detail page's song list, as it is shown)

/// The song list of an album, artist or genre page as it is SHOWN: the songs in display order, what
/// the list draws (`items` — the songs, and an artist page's album headers), and what playing a row
/// plays. Built once per load from the page's read and its `DetailTrackArrangement`, so the list does
/// no per-row work of its own.
///
/// `rows` is the ONE order on the page: the selection kit's rows (`ListSelection`), the keys' order,
/// and the play order — so what plays is always what is shown, top to bottom (PLAY-02), even where
/// the grouping moved a song away from its place in the read. Knows nothing of Songs' columns or
/// sort (COL-01).
public struct DetailTrackLayout<Track: DetailTrack> {
    /// One line of the list.
    public enum Item: Identifiable {
        /// An artist page's album header: its title and year (nil when unknown).
        case header(albumID: Int64, title: String, year: String?)
        /// A song, and the number that leads it (nil: none).
        case row(Track, number: Int?)

        public var id: ItemID {
            switch self {
            case let .header(albumID, _, _): .header(albumID)
            case let .row(track, _): .row(track.id)
            }
        }
    }

    /// A line's identity in the list.
    public enum ItemID: Hashable {
        case header(Int64)
        case row(Track.ID)
    }

    public let arrangement: DetailTrackArrangement
    /// The songs in the order shown.
    public let rows: [Track]
    /// What the list draws, in order.
    public let items: [Item]
    /// Each row's place in `rows`, by id — so a click, a key or Return finds its row without a scan.
    private let positions: [Track.ID: Int]
    /// How many album headers sit above each row (an artist page; empty on the others, which have none).
    private let headersAbove: [Int]

    public init(tracks: [Track], arrangement: DetailTrackArrangement) {
        self.arrangement = arrangement
        switch arrangement {
        case .album:
            rows = tracks
            items = tracks.enumerated().map { index, track in .row(track, number: track.trackNo ?? index + 1) }
            headersAbove = []
        case .byAlbum:
            // A header per album (`FacetAlbumGrouping`), then its songs, each numbered within its album.
            let albums = FacetAlbumGrouping.sections(from: tracks)
            rows = albums.flatMap(\.tracks)
            items = albums.flatMap { album in
                [.header(albumID: album.id, title: album.title, year: album.year)]
                    + album.tracks.enumerated().map { position, track in
                        .row(track, number: track.trackNo ?? position + 1)
                    }
            }
            headersAbove = albums.indices.flatMap { Array(repeating: $0 + 1, count: albums[$0].tracks.count) }
        case .flat:
            rows = tracks
            items = tracks.map { .row($0, number: nil) }
            headersAbove = []
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

    /// Where row `index` sits in the list's content, for scrolling it into view by arithmetic
    /// (`FixedRowReveal`): its top, less the list's inset, and its height — every row `rowHeight` tall,
    /// every album header `headerHeight`. An album's first song brings its header with it, so moving
    /// up onto it shows which album it is in.
    public func span(ofRow index: Int, rowHeight: Double, headerHeight: Double) -> (top: Double, height: Double) {
        let headers = headersAbove.isEmpty ? 0 : headersAbove[index]
        let top = Double(index) * rowHeight + Double(headers) * headerHeight
        let startsAlbum = headers > 0 && (index == 0 || headersAbove[index - 1] != headers)
        return startsAlbum ? (top - headerHeight, rowHeight + headerHeight) : (top, rowHeight)
    }
}
