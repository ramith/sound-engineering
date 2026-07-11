import Foundation

// MARK: - Library drill-down routes (S9.4)

/// A data-driven entry on the Library detail's browse stack (`LibraryBrowseModel.path`, a plain
/// `[LibraryRoute]`). `LibraryTabView` renders `path.last` as the detail — pushed by
/// `model.path.append(route)` and popped by the in-content back control — so this is NOT a
/// `NavigationStack`/`navigationDestination` (that container force-owns the window top on macOS,
/// underlapping the app's custom chrome). `Hashable` is kept for cheap equality/dedup. Album
/// detail ships in S9.4; artist/genre/year details fill in over S9.5/S9.6.
enum LibraryRoute: Hashable {
    case album(Int64)
    case artist(Int64)
    case genre(Int64)
}
