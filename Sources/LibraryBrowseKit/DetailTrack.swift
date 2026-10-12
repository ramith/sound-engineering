// MARK: - DetailTrack (S10.8 E2/E3 — what a detail page's list needs of a song)

/// What the album, artist and genre pages' song list needs of a song: its id, its album (an artist's
/// page groups by album — `AlbumGroupable`), and its place in that album — disc, track number and
/// title (`AlbumTrackOrder`). Nothing of Songs' columns or sort (COL-01). A protocol so
/// `DetailTrackLayout` is tested with a small stub; `LibraryTrackDisplay` conforms
/// (`LibraryTrackDisplay+DetailTrack`).
public protocol DetailTrack: AlbumGroupable, Identifiable {
    /// The title the row shows.
    var title: String { get }
    /// The tagged disc number, or nil when untagged.
    var discNo: Int? { get }
    /// The tagged track number within its disc, or nil when untagged.
    var trackNo: Int? { get }
}
