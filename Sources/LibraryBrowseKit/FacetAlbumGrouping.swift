import Foundation
import LibraryStore

// MARK: - FacetAlbumGrouping (S9.6 — group a facet's songs into album sections)

/// The minimum a track needs to be grouped into album sections. Generic-over-protocol so the pure
/// grouping is unit-tested with a tiny stub, not a full `LibraryTrackDisplay` fixture (the same
/// reason `SongsRowResolver` is generic over `Identifiable`). `LibraryTrackDisplay` conforms below.
public protocol AlbumGroupable {
    var albumID: Int64? { get }
    var albumName: String? { get }
    /// The SONG's own year.
    var year: Int? { get }
    /// Its ALBUM's year, as the album's page shows it — nil when unknown (S10.8 E break-it 2).
    var albumYear: Int? { get }
}

public extension AlbumGroupable {
    /// A song that doesn't know its album's year: the section falls back to its songs' years.
    var albumYear: Int? {
        nil
    }
}

extension LibraryTrackDisplay: AlbumGroupable {}

/// One album's songs within a grouped facet detail (an artist's page).
public struct FacetAlbumSection<Track>: Identifiable {
    /// The album id, or `-1` for the songs with no album. Distinct per section: an album is one
    /// section however its songs arrive.
    public let id: Int64
    public let title: String
    /// The album's year (S10.8 E break-it 2): its own, else the year most of its songs here share;
    /// nil when unknown — and always for the songs with no album, a bucket of unrelated songs.
    public let albumYear: Int?
    public var tracks: [Track]

    /// The year as a header shows it: a bare string (never thousands-grouped), or nil.
    public var year: String? {
        albumYear.map(String.init)
    }

    public init(id: Int64, title: String, albumYear: Int?, tracks: [Track]) {
        self.id = id
        self.title = title
        self.albumYear = albumYear
        self.tracks = tracks
    }
}

public enum FacetAlbumGrouping {
    /// The id of the section that holds the songs with no album ("Unknown Album").
    public static let noAlbumID: Int64 = -1

    /// Group album/disc/track-ordered `tracks` into one section per album, in ONE O(n) pass: the
    /// albums in the order they first appear, each album's songs in their order. The store's reads
    /// are album-ordered, so an album's songs arrive together; one that arrived apart still joins its
    /// album's ONE section (never a second section with the same id). A track with no album groups
    /// under "Unknown Album" (`id -1`). A section's year is its album's (`albumYear`), else the
    /// year most of its songs share (the earliest of a tie); the no-album section has none.
    public static func sections<Track: AlbumGroupable>(
        from tracks: [Track]
    ) -> [FacetAlbumSection<Track>] {
        var sectionOfAlbum: [Int64: Int] = [:]
        let grouped: [FacetAlbumSection<Track>] = tracks.reduce(into: []) { sections, track in
            let albumID = track.albumID ?? noAlbumID
            if let index = sectionOfAlbum[albumID] {
                sections[index].tracks.append(track)
            } else {
                sectionOfAlbum[albumID] = sections.count
                sections.append(FacetAlbumSection(id: albumID, title: track.albumName ?? "Unknown Album",
                                                  albumYear: nil, tracks: [track]))
            }
        }
        return grouped.map { section in
            FacetAlbumSection(id: section.id, title: section.title,
                              albumYear: section.id == noAlbumID ? nil : albumYear(of: section.tracks),
                              tracks: section.tracks)
        }
    }

    /// The albums in the order a page lists them, which no scan can change: by year (undated albums
    /// after dated ones), then title (as the Finder sorts names), then id; the songs with no album
    /// last (S10.8 E break-it 5).
    public static func pageOrder<Track>(_ sections: [FacetAlbumSection<Track>]) -> [FacetAlbumSection<Track>] {
        sections.sorted { left, right in
            if (left.id == noAlbumID) != (right.id == noAlbumID) {
                return right.id == noAlbumID
            }
            let (leftYear, rightYear) = (left.albumYear ?? .max, right.albumYear ?? .max)
            if leftYear != rightYear {
                return leftYear < rightYear
            }
            let titles = left.title.localizedStandardCompare(right.title)
            return titles == .orderedSame ? left.id < right.id : titles == .orderedAscending
        }
    }

    /// An album's year from its songs: the album's own when any song carries it, else the most
    /// common positive song year — the earliest of a tie — or nil.
    private static func albumYear(of tracks: [some AlbumGroupable]) -> Int? {
        if let own = tracks.lazy.compactMap(\.albumYear).first(where: { $0 > 0 }) {
            return own
        }
        let counts = tracks.compactMap { $0.year.flatMap { $0 > 0 ? $0 : nil } }
            .reduce(into: [Int: Int]()) { $0[$1, default: 0] += 1 }
        return counts.max { left, right in
            left.value != right.value ? left.value < right.value : left.key > right.key
        }?.key
    }
}
