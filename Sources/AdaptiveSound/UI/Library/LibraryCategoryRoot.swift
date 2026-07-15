import SwiftUI

// MARK: - Category root + drill-down route views (S9.4)

/// The detail-stack root for the selected sidebar category (Songs · Albums · Artists · Genres).
struct LibraryCategoryRoot: View {
    let category: LibraryCategory?

    var body: some View {
        switch category {
        case .albums:
            AlbumGridView()
        case .songs:
            SongsView()
        case .artists:
            ArtistsGridView()
        case .genres:
            GenresListView()
        case .none:
            LibraryPlaceholderView(title: "Library", detail: "Choose a category from the sidebar.")
        }
    }
}

/// The destination for a pushed `LibraryRoute` (album / artist / genre detail, or a selected playlist).
struct LibraryRouteView: View {
    let route: LibraryRoute

    var body: some View {
        switch route {
        case let .album(id):
            AlbumDetailView(albumID: id)
        case let .artist(id):
            ArtistDetailView(artistID: id)
        case let .genre(id):
            GenreDetailView(genreID: id)
        case let .playlist(id):
            PlaylistDetailView(playlistID: id)
        }
    }
}

/// A neutral placeholder for the no-selection sidebar state.
struct LibraryPlaceholderView: View {
    let title: String
    let detail: String

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: "square.dashed")
        } description: {
            Text(detail)
        }
    }
}
