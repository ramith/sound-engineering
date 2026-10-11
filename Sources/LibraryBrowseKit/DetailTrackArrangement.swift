// MARK: - DetailTrackArrangement (S10.8 E2/E3 — how a detail page lays out its songs)

/// How an album, artist or genre page arranges its songs (`DetailTrackLayout`).
public enum DetailTrackArrangement: Sendable {
    /// An album's page: its songs in disc / track order, each led by its track number — or by its
    /// place in the list when it has none.
    case album
    /// An artist's page: its songs under one header per album, each led by its track number — or
    /// by its place in that album when it has none.
    case byAlbum
    /// A genre's page: one flat list, no numbers (each row names its artist and album instead).
    case flat
}
