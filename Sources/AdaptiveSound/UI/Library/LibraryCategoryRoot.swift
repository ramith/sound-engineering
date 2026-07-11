import SwiftUI

// MARK: - Category root + drill-down route views (S9.4)

/// The detail-stack root for the selected sidebar category. Albums (S9.4) + Songs (S9.5) ship;
/// Artists/Genres/Years (S9.6) show a placeholder until their slice lands.
struct LibraryCategoryRoot: View {
    let category: LibraryCategory?

    var body: some View {
        switch category {
        case .albums:
            AlbumGridView()
        case .songs:
            SongsView()
        case .artists:
            ArtistsListView()
        case .genres:
            GenresListView()
        case .years:
            YearsListView()
        case .none:
            LibraryPlaceholderView(title: "Library", detail: "Choose a category from the sidebar.")
        }
    }
}

/// The destination for a pushed `LibraryRoute`. Album detail ships in S9.4; artist/genre/year
/// details fill in with their categories (S9.6). Those routes aren't reachable yet (only the
/// album grid pushes), so their arms are placeholders keeping the `switch` exhaustive.
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
        case let .year(year):
            YearDetailView(year: year)
        }
    }
}

/// A neutral placeholder for not-yet-built categories/routes (S9.5/S9.6 fill these in).
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
