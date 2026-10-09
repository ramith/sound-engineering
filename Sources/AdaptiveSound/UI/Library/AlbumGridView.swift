import LibraryStore
import SwiftUI

// MARK: - Album grid (S9.4)

/// The Albums root: the shared browse scaffold (`BrowseGridRoot` → `BrowseGrid`) over the loaded
/// albums — each tile its cover, title and album artist (VoiceOver adds the year). Single-click a
/// tile → OPEN the album (AlbumDetailView); Play comes from the hover button and the context menu;
/// the keyboard and the return place are the grid's. Filters on title OR album artist. Warms one
/// batched artwork query per album set. The `.loaded`-but-empty state is the library-wide "No Music
/// Found": every album was removed.
struct AlbumGridView: View {
    @Environment(LibraryBrowseModel.self) private var model

    var body: some View {
        BrowseGridRoot(
            category: .albums,
            items: model.albums,
            state: model.albumsState,
            noun: "album",
            empty: LibraryEmptyStateView(kind: .emptyLibrary),
            filterKeys: { [$0.title, $0.albumArtist] },
            title: \.title,
            load: { await model.loadAlbums() },
            tile: { album in
                BrowseTileContent(ref: .album(album.id), title: album.title, subtitle: album.albumArtist,
                                  artworkKeys: album.artworkKey.map { [$0] } ?? [], year: album.year)
            }
        )
        .task(id: model.albums.map(\.id)) {
            await model.warmArtwork(model.albums.compactMap(\.artworkKey))
        }
    }
}
