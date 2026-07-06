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
    @Environment(AudioViewModel.self) private var audio

    var body: some View {
        HStack(spacing: 0) {
            LibrarySidebar()
                .frame(width: DesignSystem.LayoutMetrics.sidebarIdeal)
                .frame(maxHeight: .infinity)

            Rectangle()
                .fill(DesignSystem.Color.hairline)
                .frame(width: 0.5)
                .frame(maxHeight: .infinity)

            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DesignSystem.Color.window)
        // Live-fill the grid as a scan / metadata pass / reconcile completes while the tab is
        // open. Coalesced to `libraryRevision` (bumped when metadata builds the album rows) — not
        // per metadata tick, and not the earlier `lastScanResult` (design §7; review B1).
        .onChange(of: audio.libraryRevision) { _, _ in
            Task { await model.reloadIfScanChanged() }
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
