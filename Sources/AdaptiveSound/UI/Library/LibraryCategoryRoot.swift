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

/// The destination for a pushed `LibraryRoute`: an album, artist or genre page — one view,
/// `LibraryDetailPage` (S10.8 E2/E3) — or a selected playlist. Each page wears `.id(route)`: another
/// page is a fresh view, with its own load, selection and scroll, so a page's `ref` never changes
/// under it (the page relies on that).
struct LibraryRouteView: View {
    let route: LibraryRoute

    var body: some View {
        switch route {
        case let .album(id):
            LibraryDetailPage(ref: .album(id)).id(route)
        case let .artist(id):
            LibraryDetailPage(ref: .artist(id)).id(route)
        case let .genre(id):
            LibraryDetailPage(ref: .genre(id)).id(route)
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
