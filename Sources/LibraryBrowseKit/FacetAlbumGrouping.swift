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

/// One album run within a grouped facet detail (the Artists tab).
public struct FacetAlbumSection<Track>: Identifiable {
    /// The album id, or `-1` for a track with no album. Distinct per section because the input is
    /// album-ordered (a no-album run is contiguous → a single `-1` section), so ids don't collide.
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
    /// Group already album/disc/track-ordered `tracks` into consecutive per-album sections in ONE
    /// O(n) pass (the input is album-ordered, so a same-album run is contiguous — no per-row sort).
    /// A track with no album groups under "Unknown Album" (`id -1`); a non-positive year → nil.
    public static func sections<Track: AlbumGroupable>(
        from tracks: [Track]
    ) -> [FacetAlbumSection<Track>] {
        tracks.reduce(into: []) { sections, track in
            let albumID = track.albumID ?? -1
            if sections.last?.id == albumID {
                sections[sections.count - 1].tracks.append(track)
            } else {
                let year = (track.year ?? 0) > 0 ? String(track.year ?? 0) : nil
                sections.append(FacetAlbumSection(
                    id: albumID, title: track.albumName ?? "Unknown Album", year: year, tracks: [track]
                ))
            }
        }
    }
}
