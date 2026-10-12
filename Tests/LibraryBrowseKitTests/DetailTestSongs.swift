import LibraryBrowseKit

// MARK: - Detail-page test songs (S10.8 E — shared by the DetailTrackLayout suites)

/// A minimal song: the layout is generic over `DetailTrack`, so no `LibraryTrackDisplay` fixture.
/// (Its optionals default to nil in the memberwise init.)
struct DetailTestSong: DetailTrack, Equatable {
    let id: Int64
    var title = ""
    var albumID: Int64?
    var albumName: String?
    var year: Int?
    var discNo: Int?
    var trackNo: Int?
}

/// The reads the DetailTrackLayout suites lay out, and how they print what a page draws.
enum DetailTestSongs {
    private typealias Song = DetailTestSong

    /// An album as the store reads it — an untagged song FIRST (SQLite sorts a NULL track first).
    static let album = [
        DetailTestSong(id: 13, title: "Untagged", albumID: 1, albumName: "Roja", year: 1992),
        Song(id: 11, title: "Chinna Chinna Aasai", albumID: 1, albumName: "Roja", year: 1992, trackNo: 1),
        Song(id: 12, title: "Kadhal Rojave", albumID: 1, albumName: "Roja", year: 1992, trackNo: 2),
        Song(id: 14, title: "Roja Jaaneman", albumID: 1, albumName: "Roja", year: 1992, trackNo: 4),
    ]

    /// An artist's read, as the store orders it (album id, NULL first): two loose songs with no album
    /// (carrying other albums' track numbers), then two albums — "Rockstar" with one untagged song.
    static let artist = [
        DetailTestSong(id: 42, title: "Zariya", trackNo: 9),
        Song(id: 41, title: "Aao Balma", trackNo: 2),
        Song(id: 21, title: "Kannalanae", albumID: 4, albumName: "Bombay", year: 1995, trackNo: 3),
        Song(id: 22, title: "Hamma Hamma", albumID: 4, albumName: "Bombay", year: 1995, trackNo: 4),
        Song(id: 32, title: "Sadda Haq", albumID: 9, albumName: "Rockstar", year: 2011),
        Song(id: 31, title: "Kun Faya Kun", albumID: 9, albumName: "Rockstar", year: 2011, trackNo: 7),
    ]

    /// A two-disc album, read out of order: a tie, a track with no disc tag, a song with no track
    /// number on disc 2, and one with neither.
    static let twoDiscs = [
        DetailTestSong(id: 1, title: "Beta", albumID: 7, discNo: 2, trackNo: 1),
        Song(id: 2, title: "No Disc Tag", albumID: 7, trackNo: 2), // a track with no disc: disc 1
        Song(id: 3, title: "Zulu", albumID: 7, discNo: 1, trackNo: 1),
        Song(id: 4, title: "Alpha", albumID: 7, discNo: 1, trackNo: 1), // a tie: by title
        Song(id: 5, title: "Disc Two Extra", albumID: 7, discNo: 2), // no track: ends its disc
        Song(id: 6, title: "Hidden", albumID: 7), // neither: ends the album
        Song(id: 7, title: "Track 10", albumID: 7, discNo: 2, trackNo: 10),
        Song(id: 8, title: "Track 9", albumID: 7, discNo: 2, trackNo: 9),
    ]

    /// The pages' heights in these tests: 36 pt rows, 44 pt album headers, 28 pt disc headers.
    static let metrics = DetailListMetrics(rowHeight: 36, albumHeaderHeight: 44, discHeaderHeight: 28)

    /// What the list draws, as text: "h<album id> <title> <year>" for an album header, "d<disc>" for
    /// a disc header ("d-": the songs with no disc), "<id>#<number>" for a song ("-": none).
    static func drawn(_ layout: DetailTrackLayout<DetailTestSong>) -> [String] {
        layout.items.map { item in
            switch item {
            case let .header(albumID, title, year): "h\(albumID) \(title) \(year ?? "-")"
            case let .discHeader(_, disc): "d\(disc.map(String.init) ?? "-")"
            case let .row(song, number, _): "\(song.id)#\(number.map(String.init) ?? "-")"
            }
        }
    }

    /// The songs the list draws, top to bottom.
    static func drawnSongs(_ layout: DetailTrackLayout<DetailTestSong>) -> [Int64] {
        layout.items.compactMap { item in
            if case let .row(song, _, _) = item {
                return song.id
            }
            return nil
        }
    }

    /// Each drawn song's disc cue, as "<id>:<disc>" ("-": none).
    static func drawnDiscs(_ layout: DetailTrackLayout<DetailTestSong>) -> [String] {
        layout.items.compactMap { item in
            if case let .row(song, _, disc) = item {
                return "\(song.id):\(disc.map(String.init) ?? "-")"
            }
            return nil
        }
    }
}
