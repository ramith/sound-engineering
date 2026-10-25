import LibraryBrowseKit
import LibraryStore
import SwiftUI

// MARK: - Genres tab (S9.6; on the browse grid since S10.8 D5, decision 19)

/// The Genres root: the shared browse scaffold and tile (`BrowseGridRoot` → `BrowseGrid`), like
/// Albums and Artists. A genre's art is a 2×2 mosaic of its biggest albums' covers (one cover with
/// one to three, the guitars glyph with none — `CoverArrangement`), from the cover read that loads
/// with the genres (`loadGenres`, paths already warmed); its subtitle is "N songs". Hides 0-song
/// genres (e.g. one orphaned by a retag) via `FacetListVisibility`; opening a genre pushes
/// `.genre(id)` → its page (`LibraryDetailPage`, with the same mosaic as its header — decision 34).
struct GenresListView: View {
    @Environment(LibraryBrowseModel.self) private var model

    var body: some View {
        // Read here, not inside the tile closure, so new covers re-render this root and its tiles.
        let covers = model.genreCoverKeys
        BrowseGridRoot(
            category: .genres,
            items: model.genres.filter { FacetListVisibility.isVisible(trackCount: $0.trackCount) },
            state: model.genresState,
            noun: "genre",
            // Songs may exist but be untagged — NOT the "No Music Found" library-empty state.
            empty: FacetListEmpty(
                title: "No Genres",
                systemImage: "guitars",
                hint: "Songs without a genre tag won't appear here."
            ),
            filterKeys: LibrarySearch.genreKeys,
            title: \.name,
            load: { await model.loadGenres() },
            tile: { genre in
                BrowseTileContent(ref: .genre(genre.id), title: genre.name,
                                  subtitle: FacetCountLabel.songs(count: genre.trackCount),
                                  artworkKeys: covers[genre.id] ?? [])
            }
        )
    }
}
