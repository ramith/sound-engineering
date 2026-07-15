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
    /// A selected playlist's detail (S10.3). Reached from the sidebar Playlists section (a top-level
    /// jump, so it REPLACES `path` rather than pushing — see `LibraryBrowseModel.selectPlaylist`),
    /// and rendered through the same `path.last → LibraryRouteView` seam as the browse drill-downs.
    case playlist(Int64)
}

// MARK: - Sidebar selection (S10.3 — unified category + playlist selection)

/// The single selection model for the rebuilt sidebar (one `ScrollView`/`LazyVStack` of Button rows,
/// not `List(selection:)` whose drops don't fire and which races row gestures — design §1). A row is
/// highlighted when it equals `LibraryBrowseModel.sidebarSelection`. Folders (D) will add nodes to
/// the ordered walk, not new cases here (a folder is a container, not a content selection).
enum SidebarSelection: Hashable {
    case category(LibraryCategory)
    case playlist(Int64)
}
