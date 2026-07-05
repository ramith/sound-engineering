import SwiftUI

// MARK: - Category root + drill-down route views (S9.4)

/// The detail-stack root for the selected sidebar category. Albums ships in S9.4; Songs
/// (S9.5) and Artists/Genres/Years (S9.6) show a placeholder until their slice lands.
struct LibraryCategoryRoot: View {
    let category: LibraryCategory?

    var body: some View {
        switch category {
        case .albums:
            AlbumGridView()
        case .songs:
            LibraryPlaceholderView(title: "Songs", detail: "The Songs list arrives in the next update.")
        case .artists:
            LibraryPlaceholderView(title: "Artists", detail: "Artist browsing arrives in a later update.")
        case .genres:
            LibraryPlaceholderView(title: "Genres", detail: "Genre browsing arrives in a later update.")
        case .years:
            LibraryPlaceholderView(title: "Years", detail: "Year browsing arrives in a later update.")
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
        case .artist:
            LibraryPlaceholderView(title: "Artist", detail: "Artist detail arrives in a later update.")
        case .genre:
            LibraryPlaceholderView(title: "Genre", detail: "Genre detail arrives in a later update.")
        case let .year(year):
            LibraryPlaceholderView(title: "\(year)", detail: "Year detail arrives in a later update.")
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
        .navigationTitle(title)
    }
}
