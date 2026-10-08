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
            items: artists,
            state: model.artistsState,
            // Songs may exist but be untagged — NOT the "No Music Found" library-empty state.
            empty: FacetListEmpty(
                title: "No Artists",
                systemImage: "music.mic",
                hint: "Songs without artist tags won't appear here."
            ),
            noun: "artist",
            filterPlaceholder: "Filter Artists",
            filterKeys: { [$0.name] },
            load: { await model.loadArtists() },
            content: { shown in
                BrowseGrid(
                    items: shown,
                    title: \.name,
                    route: { .artist($0.id) },
                    play: { await model.playFacet(.artist($0.id)) },
                    cell: { ArtistCell(artist: $0, side: BrowseGridMetrics.tileSide) },
                    actions: { FacetQueueActions(ref: .artist($0.id)) }
                )
            }
        )
        .task(id: artists.map(\.id)) {
            await model.warmArtwork(artists.compactMap(\.artworkKey))
        }
    }
}

// MARK: - Artist grid cell (art + name + N songs)

/// One artist tile's content: representative album cover + name + "N songs". VoiceOver: one combined
/// element with Play / Play Next / Add-to-Queue actions (Open is the enclosing button's activation).
struct ArtistCell: View {
    let artist: ArtistFacet
    let side: CGFloat

    @Environment(LibraryBrowseModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.small) {
            AlbumArtworkView(key: artist.artworkKey, side: side, model: model)
            Text(artist.name)
                .font(DesignSystem.Font.bodyMedium)
                .foregroundStyle(DesignSystem.Color.label)
                .lineLimit(2, reservesSpace: true)
            Text(FacetCountLabel.songs(count: artist.trackCount))
                .font(DesignSystem.Font.caption)
                .foregroundStyle(DesignSystem.Color.labelSecondary)
                .lineLimit(1)
        }
        .frame(width: side, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(artist.name), \(FacetCountLabel.songs(count: artist.trackCount))")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: "Play") { Task { await model.playFacet(.artist(artist.id)) } }
        .accessibilityAction(named: "Play Next") { Task { await model.playFacetNext(.artist(artist.id)) } }
        .accessibilityAction(named: "Add to Queue") { Task { await model.appendFacet(.artist(artist.id)) } }
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
