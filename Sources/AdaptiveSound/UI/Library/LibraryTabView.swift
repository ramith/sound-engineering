import DesignTokenKit
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

            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(.horizontal, 22)
        .padding(.top, 22)
        .padding(.bottom, 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Twin Panels backdrop (S10.8 PR-B): window base + one soft teal glow behind both
        // cards (png/00). GlowField paints DesignSystem.Color.window and gates the glow to
        // dark / no-Reduce-Transparency; the two floating cards (PR-C/D) then sit over it.
        .background { GlowField(glows: GlowFieldSpec.libraryGlows) }
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
