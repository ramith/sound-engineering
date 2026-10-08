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
            filterKeys: { [$0.name] },
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

// MARK: - Artist detail (grouped by album)

/// One artist's songs, GROUPED by album (founder decision Q-a) — reuses `FacetTrackListView` in its
/// grouped mode. Loads the header facet + tracks into local `@State` (mirrors `AlbumDetailView`),
/// keyed on `artistID`. Track-artist lens (`tracksDisplay(byArtist:)`) — songs this artist performs.
struct ArtistDetailView: View {
    let artistID: Int64

    @Environment(LibraryBrowseModel.self) private var model
    @State private var artist: ArtistFacet?
    @State private var tracks: [LibraryTrackDisplay] = []

    var body: some View {
        FacetTrackListView(
            title: artist?.name ?? "",
            backLabel: "Back to Artists",
            tracks: tracks,
            groupByAlbum: true
        )
        .task(id: artistID) {
            artist = await model.artist(id: artistID)
            tracks = await model.tracks(byArtist: artistID)
        }
    }
}
