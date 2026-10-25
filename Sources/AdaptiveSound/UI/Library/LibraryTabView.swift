import SwiftUI

// MARK: - Library tab (S9.4)

/// The Library surface: a fixed category sidebar beside a model-driven detail column.
///
/// ★ All browse/nav state lives on the injected `LibraryBrowseModel` (path / selectedCategory) —
/// NOT `@State` here — because the enclosing tab `switch` destroys this view on every tab change
/// (design §2).
///
/// Deliberately NOT a `NavigationSplitView`: on macOS that is backed by `NSSplitViewController`,
/// which force-adopts the "full-height source-list under the titlebar" look and positions itself
/// relative to the WINDOW — ignoring its SwiftUI parent frame and `.clipped()`, so its sidebar and
/// detail rendered UP behind the app's custom chrome band. A plain `HStack` is bounded by the
/// shell's content region like every other tab. Drill-down is a manual switch on `model.path`
/// (a linear stack — only the top entry is visible), pushed by `model.path.append` and popped by
/// the in-content back control, so there is no `NavigationStack`/`navigationDestination` either
/// (same window-owning failure mode).
struct LibraryTabView: View {
    @Environment(LibraryBrowseModel.self) private var model
    @Environment(LibraryModel.self) private var library
    @Environment(PlaylistsModel.self) private var playlists

    var body: some View {
        // Twin Panels layout (S10.8 PR-C): the two floating cards over the shared glow, with the
        // mock's 22pt content inset and 20pt gap; no divider between them (the gap is the seam).
        HStack(spacing: 20) {
            LibrarySidebar() // a fixed-width, content-height glass card that hugs the top

            // The right pane's ONE glass card (S10.8 D1), mounted here and nowhere else: it stays
            // put as the rail moves between Songs, Albums, Artists and Genres, and holds the detail
            // pages and playlists too — none of them paints a card or a background of its own.
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                // The one "Restore previous queue" for every page's queue replace (review 18), at the
                // card's foot — where the playlist page drew its own.
                .overlay(alignment: .bottom) { QueueRestoreToast() }
                .libraryDetailCard()
        }
        .padding(.horizontal, 22)
        .padding(.top, 22)
        .padding(.bottom, 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // No backdrop here: the two floating cards sit over the app glow the shell mounts behind
        // every tab but Now Playing (`TabContentView`, S10.8 F1).
        // Files dropped on the Library from Finder play now, without joining the library (R1.1-B,
        // US-LIB-02). A playlist — its rail row or its page — takes a drop of files as an add instead.
        .dropDestination(for: URL.self) { urls, _ in
            let files = urls.filter(\.isFileURL)
            guard !files.isEmpty else { return false }
            model.openFiles(files)
            return true
        }
        // The playlist dialogs, hosted ONCE for the tab (S10.8 E fix round): a failure is the model's,
        // whichever page raised it — the rail, an Add to Playlist on any page, the playlist page.
        .playlistDialogSheet()
        // Live-fill the grid as a scan / metadata pass / reconcile completes while the tab is
        // open. Coalesced to `libraryRevision` (bumped when metadata builds the album rows) — not
        // per metadata tick, and not the earlier `lastScanResult` (design §7; review B1).
        .onChange(of: library.libraryRevision) { _, _ in
            Task { await model.reloadIfScanChanged() }
            // Playlist entry counts move when a track deletion CASCADE-drops entries (S10.3) — keep
            // the sidebar counts + any open detail truthful on the same coalesced revision bump.
            Task { await playlists.reloadOnLibraryChange() }
        }
    }

    /// The detail column = the top of the (linear) browse stack. `model.path.last` is the pushed
    /// route (album / artist / …); an empty path shows the selected category's root grid or list.
    @ViewBuilder private var detail: some View {
        if let route = model.path.last {
            LibraryRouteView(route: route)
        } else {
            LibraryCategoryRoot(category: model.selectedCategory)
        }
    }
}
