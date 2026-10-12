// MARK: - DiscFolder (S10.8 E break-it 1 — a set ripped one folder per disc)

/// The disc a song's folder names — "CD 2" in "Live Set/CD 2/01.flac" — and the album folder that
/// holds that disc folder. A set ripped one folder per disc often carries no disc tags; the store
/// folds its disc folders into one album (S10.8 C2), and the pages order it disc by disc from these
/// (`AlbumTrackOrder`) — only where the songs' disc folders are siblings in one album folder.
public struct DiscFolder: Sendable, Equatable {
    /// The disc the folder's name gives (1 or more).
    public let disc: Int
    /// The folder holding the disc folders, so only siblings count as one set.
    public let albumFolder: String

    public init(disc: Int, albumFolder: String) {
        self.disc = disc
        self.albumFolder = albumFolder
    }
}
