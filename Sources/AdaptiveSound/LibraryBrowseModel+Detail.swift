import Foundation
import LibraryBrowseKit
import LibraryStore

// MARK: - LibraryBrowseModel + detail pages (S10.8 E2/E3)

/// The album, artist and genre pages' one read (`LibraryDetailPage`): the page's header facet and its
/// songs, laid out as the page shows them. Split into a same-type extension for file length, like
/// `+Facets` and `+Play`.
@MainActor
extension LibraryBrowseModel {
    /// An album page's content: its title, album artist, year and cover over its songs in disc /
    /// track order. Nil for the other pages, which move onto it in E3.
    func detailContent(_ ref: FacetRef) async -> LibraryDetailContent? {
        guard case let .album(id) = ref else { return nil }
        let album = await album(id: id)
        let tracks = await facetTracks(ref)
        return LibraryDetailContent(title: album?.title ?? "", subtitle: album?.albumArtist, year: album?.year,
                                    artworkKey: album?.artworkKey,
                                    layout: DetailTrackLayout(tracks: tracks, arrangement: .album))
    }
}

extension LibraryBrowseModel.FacetRef {
    /// The browse category whose grid opens this page: where its back control returns to, and the
    /// glyph its art shows without a cover.
    var category: LibraryCategory {
        switch self {
        case .album: .albums
        case .artist: .artists
        case .genre: .genres
        }
    }
}
