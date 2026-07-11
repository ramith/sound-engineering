import LibraryBrowseKit
import LibraryStore
import SwiftUI

// MARK: - Artists tab (S9.6 — tile grid)

/// The Artists tile grid (founder feedback: tiles, not a flat list). Each tile shows a
/// representative album cover (there is no artist-photo source) + name + "N songs". Single-click a
/// tile → OPEN the artist detail; Play comes from the hover button + the context menu (mirrors
/// `AlbumGridView`). Hides 0-song artists (e.g. an album-artist-only "Various Artists") via the pure
/// `FacetListVisibility` predicate.
struct ArtistsGridView: View {
    @Environment(LibraryBrowseModel.self) private var model
    /// In-view filter (narrows the visible artists by name, in place — the Apple Filter field).
    @State private var filter = ""

    private let side: CGFloat = 168
    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: side, maximum: 200), spacing: 16)]
    }

    /// 0-song artists hidden (FacetListVisibility), then narrowed by the filter (name substring).
    private var visibleArtists: [ArtistFacet] {
        model.artists.filter { FacetListVisibility.isVisible(trackCount: $0.trackCount) }
    }

    private var filteredArtists: [ArtistFacet] {
        filter.isEmpty ? visibleArtists : visibleArtists.filter { FacetTextFilter.matches($0.name, query: filter) }
    }

    var body: some View {
        content
            .task(id: model.isStoreReady) { await model.loadArtists() }
    }

    @ViewBuilder private var content: some View {
        switch model.artistsState {
        case .idle, .loading:
            if visibleArtists.isEmpty {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                gridWithFilter
            }
        case .loaded:
            if visibleArtists.isEmpty { facetEmpty } else { gridWithFilter }
        case .firstRun:
            LibraryEmptyStateView(kind: model.isPopulating ? .scanning : .firstRun)
        case .empty:
            // Roots exist but no artists: scanning if a pass is live, else the facet-specific empty
            // (songs may exist but be untagged — NOT the "No Music Found" library-empty state).
            if model.isPopulating { LibraryEmptyStateView(kind: .scanning) } else { facetEmpty }
        case let .failed(message):
            LibraryEmptyStateView(kind: .failed(message))
        }
    }

    private var facetEmpty: some View {
        FacetListEmpty(
            title: "No Artists",
            systemImage: "music.mic",
            hint: "Songs without artist tags won't appear here."
        )
    }

    /// Filter header + the narrowed grid (or a "no results" state when the filter matches nothing).
    private var gridWithFilter: some View {
        VStack(spacing: 0) {
            LibraryFilterHeader(count: countLine, filter: $filter, placeholder: "Filter Artists")
            Rectangle().fill(DesignSystem.Color.hairline).frame(height: 0.5)
            if filteredArtists.isEmpty {
                ContentUnavailableView.search(text: filter)
            } else {
                grid
            }
        }
    }

    private var countLine: String {
        let shown = filteredArtists.count
        return "\(shown) artist\(shown == 1 ? "" : "s")"
    }

    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: DesignSystem.Spacing.large) {
                ForEach(filteredArtists) { artist in
                    ArtistGridItem(artist: artist, side: side)
                }
            }
            .padding(DesignSystem.Spacing.medium)
        }
        .task(id: visibleArtists.map(\.id)) {
            await model.warmArtwork(visibleArtists.compactMap(\.artworkKey))
        }
    }
}

// MARK: - Grid item (Open button + hover Play overlay)

/// One artist tile: the whole cell opens the artist detail; the hover Play button is a sibling
/// overlay above it (reliably wins the hit test on macOS), and is a11y-hidden because the cell
/// exposes Play as a custom action. Mirrors `AlbumGridItem`.
private struct ArtistGridItem: View {
    let artist: ArtistFacet
    let side: CGFloat

    @Environment(LibraryBrowseModel.self) private var model
    @State private var hovering = false

    var body: some View {
        Button {
            model.path.append(.artist(artist.id))
        } label: {
            ArtistCell(artist: artist, side: side)
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
        .contextMenu { FacetQueueActions(ref: .artist(artist.id)) }
    }

    private var playButton: some View {
        Button {
            Task { await model.playFacet(.artist(artist.id)) }
        } label: {
            Image(systemName: "play.circle.fill")
                .font(.system(size: max(20, side * 0.26)))
                .symbolRenderingMode(.palette)
                .foregroundStyle(DesignSystem.Color.onAccent, DesignSystem.Color.accent)
                .shadow(radius: 3)
        }
        .buttonStyle(.plain)
        .help("Play")
        .accessibilityHidden(true)
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
