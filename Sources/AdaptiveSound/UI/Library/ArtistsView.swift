import LibraryBrowseKit
import LibraryStore
import SwiftUI

// MARK: - Artists tab (S9.6 — tile grid)

/// The Artists tile grid (founder feedback: tiles, not a flat list) on the shared browse scaffold
/// (`BrowseGridRoot` → `BrowseGrid`). Each tile shows a representative album cover (there is no
/// artist-photo source) + name + "N songs". Single-click a tile → OPEN the artist detail; Play comes
/// from the hover button + the context menu. Hides 0-song artists (e.g. an album-artist-only
/// "Various Artists") via the pure `FacetListVisibility` predicate; filters on the name.
struct ArtistsGridView: View {
    @Environment(LibraryBrowseModel.self) private var model

    /// 0-song artists hidden (FacetListVisibility).
    private var visibleArtists: [ArtistFacet] {
        model.artists.filter { FacetListVisibility.isVisible(trackCount: $0.trackCount) }
    }

    var body: some View {
        let artists = visibleArtists
        BrowseGridRoot(
            category: .artists,
            items: artists,
            state: model.artistsState,
            noun: "artist",
            // Songs may exist but be untagged — NOT the "No Music Found" library-empty state.
            empty: FacetListEmpty(
                title: "No Artists",
                systemImage: "music.mic",
                hint: "Songs without artist tags won't appear here."
            ),
            filterKeys: LibrarySearch.artistKeys,
            title: \.name,
            load: { await model.loadArtists() },
            tile: { artist in
                BrowseTileContent(ref: .artist(artist.id), title: artist.name,
                                  subtitle: FacetCountLabel.songs(count: artist.trackCount),
                                  artworkKeys: artist.artworkKey.map { [$0] } ?? [])
            }
        )
        .task(id: artists.map(\.id)) {
            await model.warmArtwork(artists.compactMap(\.artworkKey))
        }
    }
}
