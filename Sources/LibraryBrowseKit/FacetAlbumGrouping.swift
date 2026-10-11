import LibraryStore

// MARK: - FacetAlbumGrouping (S9.6 — group a facet's songs into album sections)

/// The minimum a track needs to be grouped into album sections. Generic-over-protocol so the pure
/// grouping is unit-tested with a tiny stub, not a full `LibraryTrackDisplay` fixture (the same
/// reason `SongsRowResolver` is generic over `Identifiable`). `LibraryTrackDisplay` conforms below.
public protocol AlbumGroupable {
    var albumID: Int64? { get }
    var albumName: String? { get }
    var year: Int? { get }
}

extension LibraryTrackDisplay: AlbumGroupable {}

/// One album's songs within a grouped facet detail (an artist's page).
public struct FacetAlbumSection<Track>: Identifiable {
    /// The album id, or `-1` for the songs with no album. Distinct per section: an album is one
    /// section however its songs arrive.
    public let id: Int64
    public let title: String
    /// A bare year string (never thousands-grouped), or nil when the album year is non-positive.
    public let year: String?
    public var tracks: [Track]

    public init(id: Int64, title: String, year: String?, tracks: [Track]) {
        self.id = id
        self.title = title
        self.year = year
        self.tracks = tracks
    }
}

public enum FacetAlbumGrouping {
    /// Group album/disc/track-ordered `tracks` into one section per album, in ONE O(n) pass: the
    /// albums in the order they first appear, each album's songs in their order. The store's reads
    /// are album-ordered, so an album's songs arrive together; one that arrived apart still joins its
    /// album's ONE section (never a second section with the same id). A track with no album groups
    /// under "Unknown Album" (`id -1`); a non-positive year → nil.
    public static func sections<Track: AlbumGroupable>(
        from tracks: [Track]
    ) -> [FacetAlbumSection<Track>] {
        var sectionOfAlbum: [Int64: Int] = [:]
        return tracks.reduce(into: []) { sections, track in
            let albumID = track.albumID ?? -1
            if let index = sectionOfAlbum[albumID] {
                sections[index].tracks.append(track)
            } else {
                sectionOfAlbum[albumID] = sections.count
                let year = (track.year ?? 0) > 0 ? String(track.year ?? 0) : nil
                sections.append(FacetAlbumSection(
                    id: albumID, title: track.albumName ?? "Unknown Album", year: year, tracks: [track]
                ))
            }
        }
    }
}
