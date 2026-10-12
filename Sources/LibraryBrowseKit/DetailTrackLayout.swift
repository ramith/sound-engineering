// MARK: - DetailTrackLayout (S10.8 E2/E3 — a detail page's song list, as it is shown)

/// The song list of an album, artist or genre page as it is SHOWN: the songs in display order, what
/// the list draws (`items` — the songs, an artist page's album headers, a multi-disc album's disc
/// headers), and what playing a row plays. Built once per load from the page's read and its
/// `DetailTrackArrangement`, so the list does no per-row work of its own.
///
/// `rows` is the ONE order on the page: the selection kit's rows (`ListSelection`), the keys' order,
/// and the play order — so what plays is always what is shown, top to bottom (PLAY-02), even where
/// the grouping or an album's own order (`AlbumTrackOrder`) moved a song from its place in the read.
/// A browse tile's verbs take the same order (`pageOrder`). Knows nothing of Songs' columns or sort
/// (COL-01).
public struct DetailTrackLayout<Track: DetailTrack> {
    /// One line of the list.
    public enum Item: Identifiable {
        /// An artist page's album header: its title and year (nil when unknown).
        case header(albumID: Int64, title: String, year: String?)
        /// A disc's sub-header, in an album with more than one disc; nil: the songs with no disc
        /// number, which end the album.
        case discHeader(albumID: Int64, disc: Int?)
        /// A song, the number that leads it (nil: none), and — where its album has more than one
        /// disc — its disc.
        case row(Track, number: Int?, disc: Int?)

        public var id: ItemID {
            switch self {
            case let .header(albumID, _, _): .header(albumID)
            case let .discHeader(albumID, disc): .discHeader(albumID: albumID, disc: disc)
            case let .row(track, _, _): .row(track.id)
            }
        }
    }

    /// A line's identity in the list.
    public enum ItemID: Hashable {
        case header(Int64)
        case discHeader(albumID: Int64, disc: Int?)
        case row(Track.ID)
    }

    public let arrangement: DetailTrackArrangement
    /// The songs in the order shown.
    public let rows: [Track]
    /// What the list draws, in order.
    public let items: [Item]
    /// Each row's place in `rows`, by id — so a click, a key or Return finds its row without a scan.
    private let positions: [Track.ID: Int]
    /// The headers above each row, for placing it by arithmetic.
    private let headers: [RowHeaders]

    /// The headers above one row: how many of each kind in all, and which sit directly on it.
    private struct RowHeaders: Sendable {
        var albumsAbove = 0
        var discsAbove = 0
        /// An album header and/or a disc header sits directly above this row: it starts them.
        var leadsAlbum = false
        var leadsDisc = false
    }

    public init(tracks: [Track], arrangement: DetailTrackArrangement) {
        self.arrangement = arrangement
        // The albums in an order no scan can change (year, title, id; loose songs last).
        let albums = FacetAlbumGrouping.pageOrder(FacetAlbumGrouping.sections(from: tracks))
        switch arrangement {
        case .album:
            items = Self.albumRows(tracks, albumID: albums.first?.id ?? FacetAlbumGrouping.noAlbumID,
                                   isWholeAlbum: true)
        case .byAlbum:
            // A header per album (`FacetAlbumGrouping`), then its songs in the album's own order;
            // the songs with no album, by title.
            items = albums.flatMap { album in
                [.header(albumID: album.id, title: album.title, year: album.year)]
                    + (album.id == FacetAlbumGrouping.noAlbumID ? Self.looseRows(album.tracks)
                        : Self.albumRows(album.tracks, albumID: album.id, isWholeAlbum: false))
            }
        case .flat:
            // One list, each album's run in that album's own order — so a genre agrees with the
            // album's and the artist's pages — with no headers or numbers.
            items = albums.flatMap { album in
                album.id == FacetAlbumGrouping.noAlbumID ? Self.looseRows(album.tracks)
                    : AlbumTrackOrder.playing(album.tracks).map { .row($0.track, number: nil, disc: nil) }
            }
        }
        // The rows ARE the songs drawn, top to bottom — so the queue can only be the shown order (PLAY-02).
        var rows: [Track] = []
        var headers: [RowHeaders] = []
        var pending = RowHeaders()
        for item in items {
            switch item {
            case .header:
                pending.albumsAbove += 1
                pending.leadsAlbum = true
            case .discHeader:
                pending.discsAbove += 1
                pending.leadsDisc = true
            case let .row(track, _, _):
                rows.append(track)
                headers.append(pending)
                pending.leadsAlbum = false
                pending.leadsDisc = false
            }
        }
        self.rows = rows
        self.headers = headers
        // A page lists a song once (the reads are one row per song); were one listed twice, the first wins.
        positions = Dictionary(rows.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// The page's songs in the order it shows them — what a browse tile's Play, Play Next, Add to
    /// Queue and Add to Playlist take, so a tile and its page can't disagree.
    public static func pageOrder(_ tracks: [Track], arrangement: DetailTrackArrangement) -> [Track] {
        DetailTrackLayout(tracks: tracks, arrangement: arrangement).rows
    }

    /// One album's songs as rows: in playing order (`AlbumTrackOrder` — disc, track, title), each led by
    /// its track number, under a sub-header per disc when the album has more than one. An untagged
    /// song shows no number — one made up from its place would read as its track — except on an
    /// album's own page (`isWholeAlbum`) when the WHOLE album has none: then it is numbered by place.
    /// An artist's page holds only some of an album's songs, so it never numbers by place.
    private static func albumRows(_ tracks: [Track], albumID: Int64, isWholeAlbum: Bool) -> [Item] {
        let ordered = AlbumTrackOrder.playing(tracks)
        let numbersByPlace = isWholeAlbum && ordered.allSatisfy { $0.track.taggedTrackNo == nil }
        let isMultiDisc = Set(ordered.compactMap(\.disc)).count > 1
        var items: [Item] = []
        for (place, entry) in ordered.enumerated() {
            if isMultiDisc, place == 0 || entry.disc != ordered[place - 1].disc {
                items.append(.discHeader(albumID: albumID, disc: entry.disc))
            }
            items.append(.row(entry.track, number: numbersByPlace ? place + 1 : entry.track.taggedTrackNo,
                              disc: isMultiDisc ? entry.disc : nil))
        }
        return items
    }

    /// Songs with no album: by title, unnumbered (their track numbers are other albums').
    private static func looseRows(_ tracks: [Track]) -> [Item] {
        AlbumTrackOrder.byTitle(tracks).map { .row($0, number: nil, disc: nil) }
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

    // MARK: Placing a row (scroll into view, Page Up / Down)

    /// Where row `index` sits in the list's content, for scrolling it into view by arithmetic
    /// (`FixedRowReveal`): its top, less the list's inset, and its height. The first song of an album
    /// or of a disc brings the header above it, so moving up onto it shows where it belongs.
    public func span(ofRow index: Int, metrics: DetailListMetrics) -> (top: Double, height: Double) {
        let above = headers[index]
        let top = Double(index) * metrics.rowHeight + Double(above.albumsAbove) * metrics.albumHeaderHeight
            + Double(above.discsAbove) * metrics.discHeaderHeight
        let lead = (above.leadsAlbum ? metrics.albumHeaderHeight : 0) + (above.leadsDisc ? metrics.discHeaderHeight : 0)
        return (top - lead, metrics.rowHeight + lead)
    }

    /// How many rows a Page Up (`direction` −1) or Page Down (+1) moves from row `index`: as many as
    /// fit in one viewport less the row left behind (which stays in view) — walked span by span, so
    /// the headers between the rows count for their height. At least one; fewer at either end.
    public func pageRows(from index: Int, direction: Int, viewportHeight: Double,
                         metrics: DetailListMetrics) -> Int {
        var room = viewportHeight - metrics.rowHeight
        var count = 0
        var lower = direction > 0 ? index + 1 : index // the lower row of each step: its lead-in lies between
        while rows.indices.contains(lower), lower - (direction > 0 ? 0 : 1) >= 0 {
            room -= span(ofRow: lower, metrics: metrics).height
            if room < 0 {
                break
            }
            count += 1
            lower += direction
        }
        return max(count, 1)
    }
}

/// Two layouts are equal when they show the same songs in the same order the same way: everything a
/// layout draws — headers, numbers, discs — follows from its rows and its arrangement. So a reload
/// that changed nothing compares equal (and isn't published), and comparing one layout with itself
/// is O(1) (the rows share storage).
extension DetailTrackLayout: Equatable where Track: Equatable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.arrangement == rhs.arrangement && lhs.rows == rhs.rows
    }
}

extension DetailTrackLayout: Sendable where Track: Sendable, Track.ID: Sendable {}
extension DetailTrackLayout.Item: Sendable where Track: Sendable, Track.ID: Sendable {}
extension DetailTrackLayout.ItemID: Sendable where Track.ID: Sendable {}
