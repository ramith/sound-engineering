// MARK: - DetailTrack (S10.8 E2/E3 — what a detail page's list needs of a song)

/// What the album, artist and genre pages' song list needs of a song: its id, its album (an artist's
/// page groups by album — `AlbumGroupable`), and its place in that album — disc, track number and
/// title, and the disc its folder names (`AlbumTrackOrder`). Nothing of Songs' columns or sort
/// (COL-01). A protocol so `DetailTrackLayout` is tested with a small stub; `LibraryTrackDisplay`
/// conforms (`LibraryTrackDisplay+DetailTrack`).
public protocol DetailTrack: AlbumGroupable, Identifiable {
    /// The title the row shows.
    var title: String { get }
    /// The tagged disc number, or nil when untagged.
    var discNo: Int? { get }
    /// The tagged track number within its disc, or nil when untagged.
    var trackNo: Int? { get }
    /// The disc its folder names ("CD 2"), or nil when its folder is no disc folder.
    var discFolder: DiscFolder? { get }
}

public extension DetailTrack {
    /// A song whose folder names no disc.
    var discFolder: DiscFolder? {
        nil
    }
}

extension DetailTrack {
    /// The track number as a page uses it: a real one (1 or more). Zero or less is a tagger's "none"
    /// and counts as untagged — it neither orders a song nor leads its row.
    var taggedTrackNo: Int? {
        trackNo.flatMap { $0 > 0 ? $0 : nil }
    }

    /// The disc number as a page uses it: a real one (1 or more), as `taggedTrackNo`.
    var taggedDiscNo: Int? {
        discNo.flatMap { $0 > 0 ? $0 : nil }
    }
}
