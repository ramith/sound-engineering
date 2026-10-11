import LibraryBrowseKit
import LibraryStore

// MARK: - Detail page content (S10.8 E2/E3)

/// What an album, artist or genre page shows: its header's text and cover, and its songs as the
/// list shows them (`DetailTrackLayout`). Loaded as one value (`LibraryBrowseModel.detailContent`),
/// so a reload replaces the page in one step — the list's selection, kept by id, carries over.
struct LibraryDetailContent {
    let title: String
    /// The line under the title: an album's album artist; nil on the other pages.
    let subtitle: String?
    /// "1992 · 8 songs · 38 min" — the album's year (when known), the count and the running time,
    /// as Songs' header counts its songs.
    let countLine: String
    /// An album's cover; nil for one without (and on the other pages).
    let artworkKey: String?
    let layout: DetailTrackLayout<LibraryTrackDisplay>

    /// - Parameter year: an album's year (nil or 0: unknown, left out of the count line).
    init(title: String, subtitle: String?, year: Int?, artworkKey: String?,
         layout: DetailTrackLayout<LibraryTrackDisplay>) {
        self.title = title
        self.subtitle = subtitle
        self.artworkKey = artworkKey
        self.layout = layout
        let seconds = layout.rows.reduce(0.0) { $0 + $1.durationSeconds }
        var parts = [FacetCountLabel.songs(count: layout.rows.count), humaneTotalDuration(seconds)]
        if let year, year > 0 {
            parts.insert(String(year), at: 0) // a bare year, never "1,992"
        }
        countLine = parts.joined(separator: " · ")
    }
}
