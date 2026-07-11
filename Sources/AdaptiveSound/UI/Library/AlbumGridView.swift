import LibraryBrowseKit
import LibraryStore
import SwiftUI

// MARK: - Album grid (S9.4)

/// The full-width adaptive album grid. Single-click a cell → OPEN (appends the album route to
/// `model.path` → AlbumDetailView); Play verbs come from the hover button + the context menu. Warms one
/// batched artwork query per album set. Empty/first-run/scanning/failed states delegate to
/// LibraryEmptyStateView.
struct AlbumGridView: View {
    @Environment(LibraryBrowseModel.self) private var model
    /// In-view filter (narrows the loaded albums by title OR artist, in place — Apple Filter field).
    @State private var filter = ""

    private let side: CGFloat = 168
    /// Adaptive minimum ≥ the fixed cell width, else a column can resolve narrower than the
    /// 168-pt cell and clip it (review S1/layout). Cells are left-aligned within wider columns.
    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: side, maximum: 200), spacing: 16)]
    }

    var body: some View {
        content
            // Keyed on store-readiness so a Library visit BEFORE the async store finishes
            // building reloads once it's ready (review S2) — not stuck on the nil-store spinner.
            .task(id: model.isStoreReady) { await model.loadAlbums() }
    }

    @ViewBuilder private var content: some View {
        switch model.albumsState {
        case .idle, .loading:
            if model.albums.isEmpty {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                gridWithFilter
            }
        case .loaded:
            // `.loaded` but empty means every album was removed — a genuine empty library.
            if model.albums.isEmpty { LibraryEmptyStateView(kind: .emptyLibrary) } else { gridWithFilter }
        case .firstRun:
            // A scan just kicked off from the first-run CTA flips this to a truthful "scanning"
            // until the albums land; otherwise it's the add-a-folder call to action.
            LibraryEmptyStateView(kind: model.isPopulating ? .scanning : .firstRun)
        case .empty:
            // Roots exist, zero albums: scanning if a pass is live, else a genuine "no music"
            // (not the permanent "Scanning…" the old mapping showed — review S1).
            LibraryEmptyStateView(kind: model.isPopulating ? .scanning : .emptyLibrary)
        case let .failed(message):
            LibraryEmptyStateView(kind: .failed(message))
        }
    }

    /// Filter header + the narrowed grid (or a "no results" state when the filter matches nothing).
    private var gridWithFilter: some View {
        VStack(spacing: 0) {
            LibraryFilterHeader(count: countLine, filter: $filter, placeholder: "Filter Albums")
            Rectangle().fill(DesignSystem.Color.hairline).frame(height: 0.5)
            if filteredAlbums.isEmpty {
                ContentUnavailableView.search(text: filter)
            } else {
                grid
            }
        }
    }

    /// Albums narrowed by the filter — matches on title OR album-artist (in place, order preserved).
    private var filteredAlbums: [AlbumFacet] {
        filter.isEmpty
            ? model.albums
            : model.albums.filter { FacetTextFilter.matches([$0.title, $0.albumArtist], query: filter) }
    }

    private var countLine: String {
        let shown = filteredAlbums.count
        return "\(shown) album\(shown == 1 ? "" : "s")"
    }

    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: DesignSystem.Spacing.large) {
                ForEach(filteredAlbums) { album in
                    AlbumGridItem(album: album, side: side)
                }
            }
            .padding(DesignSystem.Spacing.medium)
        }
        .task(id: model.albums.map(\.id)) {
            await model.warmArtwork(model.albums.compactMap(\.artworkKey))
        }
    }
}

// MARK: - Grid item (Open button + hover Play overlay)

/// One grid entry. The whole cell is an Open button (appends the album route to `model.path`).
/// The hover Play button is a SIBLING overlay ABOVE it — not nested in its label — so it reliably wins the hit test
/// on macOS (review §6); it's positioned over the art (top `side`×`side` region), and is
/// `accessibilityHidden` because the cell exposes Play as a custom action.
private struct AlbumGridItem: View {
    let album: AlbumFacet
    let side: CGFloat

    @Environment(LibraryBrowseModel.self) private var model
    @State private var hovering = false

    var body: some View {
        Button {
            model.path.append(.album(album.id))
        } label: {
            AlbumCell(album: album, side: side)
        }
        .buttonStyle(.plain)
        .overlay(alignment: .topLeading) {
            if hovering {
                playButton
                    .padding(DesignSystem.Spacing.small)
                    .frame(width: side, height: side, alignment: .bottomTrailing)
            }
        }
        .onHover { hovering = $0 }
        .contextMenu { AlbumQueueActions(albumID: album.id) }
    }

    private var playButton: some View {
        Button {
            Task { await model.playAlbum(album.id) }
        } label: {
            Image(systemName: "play.circle.fill")
                .font(.system(size: max(20, side * 0.26)))
                .symbolRenderingMode(.palette)
                .foregroundStyle(DesignSystem.Color.onAccent, DesignSystem.Color.accent)
                .shadow(radius: 3)
        }
        .buttonStyle(.plain)
        .help("Play")
        .accessibilityHidden(true) // the cell exposes Play as a custom action
    }
}

// MARK: - Shared album queue-action menu

/// Play / Play Next / Add to Queue for an album — used by the grid context menu and (later)
/// the detail view's `⋯` menu.
struct AlbumQueueActions: View {
    let albumID: Int64
    @Environment(LibraryBrowseModel.self) private var model

    var body: some View {
        Button("Play") { Task { await model.playAlbum(albumID) } }
        Button("Play Next") { Task { await model.playAlbumNext(albumID) } }
        Button("Add to Queue") { Task { await model.appendAlbum(albumID) } }
    }
}
