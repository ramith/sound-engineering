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
        if case let .playlist(id)? = path.last {
            return .playlist(id)
        }
        return .category(selectedCategory ?? .songs)
    }

    /// A rail jump to a browse category: its root, started FRESH (S10.8 D6) — no Filter text and no
    /// remembered place, even when it is the category already showing. (Coming back any other way —
    /// "back", a tab switch, `showCategoryRoot` — returns a grid to where it was.)
    func selectCategory(_ category: LibraryCategory) {
        if !browseFilter.isEmpty {
            browseFilter = ""
        }
        browsePlace = nil
        showCategoryRoot()
        selectedCategory = category
    }

    /// Shows the CURRENT category's root — closes any drill-down or open playlist — keeping its
    /// Filter text and remembered place, so it comes back as the user left it (e.g. when the open
    /// playlist is deleted). An explicit `path` clear, not `selectedCategory`'s didSet: the category
    /// doesn't change, so the didSet wouldn't fire and the playlist would stay on screen.
    func showCategoryRoot() {
        if !path.isEmpty {
            path.removeAll()
        }
    }

    /// A browse drill-down (an album / artist / genre page) is showing over the category root. An
    /// open playlist is not one: it replaced the browse stack (`selectPlaylist`).
    var isBrowseDrillDownOpen: Bool {
        switch path.last {
        case .album, .artist, .genre: true
        case .playlist, nil: false
        }
    }

    /// Select a playlist — a TOP-LEVEL jump that replaces the browse stack (not a drill-down push),
    /// so switching back to a category (which clears `path`) restores the category root cleanly.
    func selectPlaylist(_ id: Int64) {
        path = [.playlist(id)]
    }
}
