import Foundation

// MARK: - Browse tile content (S10.8 D5 — a section's data for one tile)

/// What one browse tile shows and acts on — all a section (Albums, Artists, Genres) supplies per
/// item; the tile, its art and the grid are shared. Album: title / album artist. Artist and genre:
/// name / "N songs".
struct BrowseTileContent {
    /// The tile's album, artist or genre: its queue verbs (Play, Play Next, Add to Queue, Add to
    /// Playlist) and the page it opens.
    let ref: LibraryBrowseModel.FacetRef
    let title: String
    let subtitle: String
    /// Its covers (`CoverArrangement`): a genre's biggest albums', an album's or artist's one, or none.
    let artworkKeys: [String]
    /// VoiceOver's label — "title, subtitle", and an album's year after them. The tooltip shows
    /// the title and subtitle whole, since the tile cuts each to one line.
    let accessibilityLabel: String
    /// VoiceOver's hint — what activating the tile does ("Opens the album"). Set in place of the
    /// one `.help` would give, which repeats the name the label has just read.
    let accessibilityHint: String

    /// - Parameter year: an album's year (0 = unknown, left out).
    init(ref: LibraryBrowseModel.FacetRef, title: String, subtitle: String, artworkKeys: [String],
         year: Int = 0) {
        self.ref = ref
        self.title = title
        self.subtitle = subtitle
        self.artworkKeys = artworkKeys
        accessibilityLabel = ([title, subtitle] + (year > 0 ? ["\(year)"] : [])).joined(separator: ", ")
        accessibilityHint = switch ref {
        case .album: "Opens the album"
        case .artist: "Opens the artist"
        case .genre: "Opens the genre"
        }
    }
}
