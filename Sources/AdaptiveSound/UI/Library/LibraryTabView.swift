import SwiftUI

// MARK: - Library tab (S9.4)

/// The Library surface: a two-column `NavigationSplitView` (category sidebar + a
/// `NavigationStack` detail for variable-depth drill-down). ★ All browse/nav state lives on
/// the injected `LibraryBrowseModel` (columnVisibility/path/selectedCategory bound to it) —
/// NOT `@State` here — because the enclosing tab `switch` destroys this view on every tab
/// change (design §2). `navigationDestination(for:)` is registered ONCE at the stack root.
struct LibraryTabView: View {
    @Environment(LibraryBrowseModel.self) private var model
    @Environment(AudioViewModel.self) private var audio

    var body: some View {
        @Bindable var model = model
        NavigationSplitView(columnVisibility: $model.columnVisibility) {
            LibrarySidebar()
                .navigationSplitViewColumnWidth(min: 170, ideal: 200, max: 300)
                // R1 (L2, bug 3): drop the split-view sidebar toggle that projects into the
                // window toolbar. The sidebar stays pinned (columnVisibility == .all); the
                // escape hatch for a divider-collapsed sidebar is View ▸ Toggle Sidebar.
                .toolbar(removing: .sidebarToggle)
        } detail: {
            NavigationStack(path: $model.path) {
                LibraryCategoryRoot(category: model.selectedCategory)
                    .navigationDestination(for: LibraryRoute.self) { route in
                        LibraryRouteView(route: route)
                    }
            }
        }
        .background(DesignSystem.Color.window)
        // Backstop for bug 3: with the scene titlebar hidden (L2), keep the split view from
        // surfacing any window-toolbar band of its own (the "second titlebar").
        .toolbarVisibility(.hidden, for: .windowToolbar)
        // Live-fill the grid as a scan / metadata pass / reconcile completes while the tab is
        // open. Coalesced to `libraryRevision` (bumped when metadata builds the album rows) —
        // not per metadata tick, and not the earlier `lastScanResult` (design §7; review B1).
        .onChange(of: audio.libraryRevision) { _, _ in
            Task { await model.reloadIfScanChanged() }
        }
    }
}
