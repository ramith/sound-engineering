import Foundation
import LibraryBrowseKit
import LibraryStore

// MARK: - LibraryBrowseModel + detail pages (S10.8 E2/E3)

/// The album, artist and genre pages' one read (`LibraryDetailPage`): the page's header facet and its
/// songs, laid out as the page shows them. Split into a same-type extension for file length, like
/// `+Facets` and `+Play`.
@MainActor
extension LibraryBrowseModel {
    /// A page's content, over its songs as the tile's verbs read them (`facetTracks`):
    /// - an album: its title, album artist, year and cover; its songs in disc / track order, numbered;
    /// - an artist: its name and its tile's cover (decision 35); its songs under one header per
    ///   album, numbered within each;
    /// - a genre: its name; one flat list (its cover mosaic is the Genres grid's, read live by the
    ///   header — decision 34).
    func detailContent(_ ref: FacetRef) async -> LibraryDetailContent {
        let tracks = await facetTracks(ref)
        switch ref {
        case let .album(id):
            let album = await album(id: id)
            return LibraryDetailContent(title: album?.title ?? "", subtitle: album?.albumArtist, year: album?.year,
                                        artworkKey: album?.artworkKey,
                                        layout: DetailTrackLayout(tracks: tracks, arrangement: .album))
        case let .artist(id):
            let artist = await artist(id: id)
            return LibraryDetailContent(title: artist?.name ?? "", subtitle: nil, year: nil,
                                        artworkKey: artist?.artworkKey,
                                        layout: DetailTrackLayout(tracks: tracks, arrangement: .byAlbum))
        case let .genre(id):
            let genre = await genre(id: id)
            return LibraryDetailContent(title: genre?.name ?? "", subtitle: nil, year: nil, artworkKey: nil,
                                        layout: DetailTrackLayout(tracks: tracks, arrangement: .flat))
        }
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
