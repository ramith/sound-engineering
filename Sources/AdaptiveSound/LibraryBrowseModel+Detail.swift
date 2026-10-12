import Foundation
import LibraryBrowseKit
import LibraryStore

// MARK: - LibraryBrowseModel + detail pages (S10.8 E2/E3)

/// The album, artist and genre pages' one read (`LibraryDetailPage`): the page's header facet and its
/// songs, laid out as the page shows them. Split into a same-type extension for file length, like
/// `+Facets` and `+Play`.
@MainActor
extension LibraryBrowseModel {
    /// A page's content, over its songs as the store reads them, laid out OFF the main actor
    /// (`layout(_:arrangement:)`):
    /// - an album: its title, album artist, year and cover; its songs in disc / track order, numbered;
    /// - an artist: its name and its tile's cover (decision 35); its songs under one header per
    ///   album, numbered within each;
    /// - a genre: its name; one flat list (its cover mosaic is the Genres grid's, read live by the
    ///   header — decision 34).
    /// `.gone` when the album, artist or genre has left the library; `.failed` when a read throws or
    /// the store isn't ready — the page then keeps what it shows (review 14).
    func detailContent(_ ref: FacetRef) async -> LibraryDetailLoad {
        guard let store else { return .failed }
        do {
            switch ref {
            case let .album(id):
                guard let album = try await store.album(id: id) else { return .gone }
                return try await .page(LibraryDetailContent(
                    title: album.title, subtitle: album.albumArtist, year: album.year, artworkKey: album.artworkKey,
                    layout: Self.layout(readFacetTracks(ref, from: store), arrangement: ref.arrangement)
                ))
            case let .artist(id):
                guard let artist = try await store.artist(id: id) else { return .gone }
                return try await .page(LibraryDetailContent(
                    title: artist.name, subtitle: nil, year: nil, artworkKey: artist.artworkKey,
                    layout: Self.layout(readFacetTracks(ref, from: store), arrangement: ref.arrangement)
                ))
            case let .genre(id):
                guard let genre = try await store.genre(id: id) else { return .gone }
                return try await .page(LibraryDetailContent(
                    title: genre.name, subtitle: nil, year: nil, artworkKey: nil,
                    layout: Self.layout(readFacetTracks(ref, from: store), arrangement: ref.arrangement)
                ))
            }
        } catch {
            return .failed
        }
    }

    /// A page's layout, built off the main actor: ordering a large genre or artist (disc, track and
    /// title sorts) is real work, and the main actor draws the app (review 19).
    @concurrent
    nonisolated static func layout(_ tracks: [LibraryTrackDisplay], arrangement: DetailTrackArrangement) async
        -> DetailTrackLayout<LibraryTrackDisplay> {
        DetailTrackLayout(tracks: tracks, arrangement: arrangement)
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

    /// How this facet's page arranges its songs — ONE mapping, shared by the page (`detailContent`)
    /// and the tile's verbs (`facetRows`), so both take the same order.
    var arrangement: DetailTrackArrangement {
        switch self {
        case .album: .album
        case .artist: .byAlbum
        case .genre: .flat
        }
    }
}
