import Foundation

// MARK: - LibraryBrowseModel + sidebar selection (S10.3)

/// Nav state for the rebuilt sidebar (design §1/§2 — nav lives on `LibraryBrowseModel`). Split into
/// this same-type extension for file length (like `+Facets` / `+History`). The sidebar is one
/// `ScrollView`/`LazyVStack` of Button rows with a unified `SidebarSelection`; these are the read
/// (`sidebarSelection`, for the capsule) and the writes (`selectCategory`/`selectPlaylist`).
@MainActor
extension LibraryBrowseModel {
    /// The currently-highlighted sidebar row, derived from nav state: a playlist when the detail is
    /// a `.playlist` route, else the selected category. Read by the sidebar to draw the selection
    /// capsule; WRITTEN via `selectCategory`/`selectPlaylist` (Button taps), never bound directly.
    var sidebarSelection: SidebarSelection {
        if case let .playlist(id)? = path.last { return .playlist(id) }
        return .category(selectedCategory ?? .songs)
    }

    /// Select a browse category — clears any drill-down / open playlist so the category root shows.
    /// Explicit `path` clear (not just `selectedCategory`'s didSet): re-selecting the ALREADY-current
    /// category while a playlist is open leaves `selectedCategory` unchanged, so the didSet wouldn't
    /// fire and the playlist would stay on screen.
    func selectCategory(_ category: LibraryCategory) {
        if !path.isEmpty { path.removeAll() }
        selectedCategory = category
    }

    /// Select a playlist — a TOP-LEVEL jump that replaces the browse stack (not a drill-down push),
    /// so switching back to a category (which clears `path`) restores the category root cleanly.
    func selectPlaylist(_ id: Int64) {
        path = [.playlist(id)]
    }
}
