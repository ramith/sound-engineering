// MARK: - DetailTrackArrangement (S10.8 E2/E3 — how a detail page lays out its songs)

/// How an album, artist or genre page arranges its songs (`DetailTrackLayout`).
public enum DetailTrackArrangement: Sendable {
    /// An album's page: its songs in playing order (`AlbumTrackOrder` — disc, track, title), each
    /// led by its track number.
    case album
    /// An artist's page: its songs under one header per album, each album in its own playing order
    /// and numbered by track; the songs with no album under "Unknown Album", by title.
    case byAlbum
    /// A genre's page: one flat list as read, no numbers (each row names its artist and album instead).
    case flat
}
