import LibraryStore
import SwiftUI

// MARK: - Album grid (S9.4)

/// The Albums root: the shared browse scaffold (`BrowseGridRoot` → `BrowseGrid`) over the loaded
/// albums. Single-click a tile → OPEN the album (AlbumDetailView); Play comes from the hover button
/// and the context menu; the keyboard and the return place are the grid's. Filters on title OR
/// album artist. Warms one batched artwork query per album set. The `.loaded`-but-empty state is
/// the library-wide "No Music Found": every album was removed.
struct AlbumGridView: View {
    @Environment(LibraryBrowseModel.self) private var model

    var body: some View {
        BrowseGridRoot(
            items: model.albums,
            state: model.albumsState,
            empty: LibraryEmptyStateView(kind: .emptyLibrary),
            noun: "album",
            filterPlaceholder: "Filter Albums",
            filterKeys: { [$0.title, $0.albumArtist] },
            load: { await model.loadAlbums() },
            content: { albums in
                BrowseGrid(
                    category: .albums,
                    items: albums,
                    title: \.title,
                    route: { .album($0.id) },
                    play: { await model.playAlbum($0.id) },
                    cell: { AlbumCell(album: $0, side: BrowseGridMetrics.tileSide) },
                    actions: { AlbumQueueActions(albumID: $0.id) }
                )
            }
        )
        .task(id: model.albums.map(\.id)) {
            await model.warmArtwork(model.albums.compactMap(\.artworkKey))
        }
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
        // Reference-add the whole album to a playlist; ids resolved on demand (the tile has no loaded
        // tracks). No searchable-picker overflow here — a tile menu has no sheet host (S10.3).
        AddToPlaylistMenu(resolveTrackIDs: { await model.tracks(inAlbum: albumID).map(\.id) })
    }
}
