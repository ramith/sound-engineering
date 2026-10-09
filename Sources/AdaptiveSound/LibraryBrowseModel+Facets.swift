import Foundation
import LibraryBrowseKit
import LibraryStore

// MARK: - LibraryBrowseModel facet loading + reads + play verbs (S9.6)

//
// The Artists/Genres list loaders, facet-detail reads, and whole-facet play verbs — split from
// LibraryBrowseModel for file length (the list state lives on the primary decl; it is `internal`
// precisely so this same-type extension can write it).
//
// Artists/Genres are the two FLAT facets (no per-item side hook), so they fold into one
// `loadFlatFacet` generic (S3 F6): the load-bearing newest-wins re-guard after BOTH suspension
// points (the list read AND the `roots()` read) is now written ONCE, correct-by-construction,
// rather than hand-copied per facet — which is precisely the drift gate R1 originally feared. Albums
// and Songs keep their bespoke loaders because they have EXTRA steps a generic would obscure (Albums
// calls ensureArtwork(); Songs' `songs` setter drives refreshVisible()).

@MainActor
extension LibraryBrowseModel {
    // MARK: Loaders

    /// Load the Artists list. `firstRun` when no roots are registered, `empty` when roots exist
    /// but no artists yet (mid-scan / untagged), `failed` on error.
    func loadArtists() async {
        await loadFlatFacet(into: \.artists, state: \.artistsState, epoch: \.artistsLoadEpoch,
                            read: { try await $0.artists() })
    }

    /// Load the Genres list and its tiles' covers AS ONE (S10.8 D fix round): the two reads run at
    /// once, the cover paths are warmed, then the genres, their covers and the state publish in one
    /// turn — so the grid never draws a frame of placeholders before its covers arrive, and no tile
    /// looks a cover path up on its own. Same flat-facet discipline as `loadArtists`.
    func loadGenres() async {
        await loadFlatFacet(into: \.genres, state: \.genresState, epoch: \.genresLoadEpoch,
                            read: { try await readGenresWithCovers($0) },
                            alongside: { covers in
                                if genreCoverKeys != covers {
                                    genreCoverKeys = covers
                                }
                            })
    }

    /// The genres, and up to a mosaic's four covers for each (`CoverArrangement`), their paths
    /// warmed in one batch. A failed cover read means NO covers — never the last read's, which a
    /// genre id reused since would wear — and covers of a genre not in the list are dropped.
    private func readGenresWithCovers(_ store: LibraryStore) async throws
        -> (items: [GenreFacet], alongside: [Int64: [String]]) {
        async let genres = store.genres()
        async let covers = store.genreCoverArtworkKeys(perGenre: CoverArrangement.mosaicCount)
        let loaded = try await genres
        let listed = Set(loaded.map(\.id))
        let keys = ((try? await covers) ?? [:]).filter { listed.contains($0.key) }
        await warmArtwork(keys.values.flatMap(\.self))
        return (loaded, keys)
    }

    /// `loadFlatFacet` for a list with nothing published alongside it (Artists).
    private func loadFlatFacet<T>(
        into arrayKeyPath: ReferenceWritableKeyPath<LibraryBrowseModel, [T]>,
        state stateKeyPath: ReferenceWritableKeyPath<LibraryBrowseModel, LoadState>,
        epoch epochKeyPath: ReferenceWritableKeyPath<LibraryBrowseModel, Int>,
        read: (LibraryStore) async throws -> [T]
    ) async {
        await loadFlatFacet(into: arrayKeyPath, state: stateKeyPath, epoch: epochKeyPath,
                            read: { try (await read($0), ()) }, alongside: { _ in })
    }

    /// Shared loader for the flat facet lists (Artists, Genres). Bumps the facet's epoch, publishes
    /// an optimistic `.loading` while the list is empty, reads, then re-guards the epoch after the
    /// list read AND again after the `roots()` read so a superseded load can never publish a stale
    /// `.empty`/`.firstRun` flash (R1). Written ONCE so that newest-wins invariant is correct across
    /// both facets by construction. What the read returns `alongside` the list (the genre covers)
    /// publishes in the same turn as the list.
    private func loadFlatFacet<T, Alongside>(
        into arrayKeyPath: ReferenceWritableKeyPath<LibraryBrowseModel, [T]>,
        state stateKeyPath: ReferenceWritableKeyPath<LibraryBrowseModel, LoadState>,
        epoch epochKeyPath: ReferenceWritableKeyPath<LibraryBrowseModel, Int>,
        read: (LibraryStore) async throws -> (items: [T], alongside: Alongside),
        alongside publishAlongside: (Alongside) -> Void
    ) async {
        guard let store else {
            self[keyPath: stateKeyPath] = .loading // store still building; reloads on isStoreReady
            return
        }
        self[keyPath: epochKeyPath] &+= 1
        let epoch = self[keyPath: epochKeyPath]
        if self[keyPath: arrayKeyPath].isEmpty {
            self[keyPath: stateKeyPath] = .loading
        }
        do {
            let (loaded, alongside) = try await read(store)
            guard epoch == self[keyPath: epochKeyPath] else { return } // superseded after list read
            self[keyPath: arrayKeyPath] = loaded
            publishAlongside(alongside)
            if loaded.isEmpty {
                let hasRoots = try await !store.roots().isEmpty
                guard epoch == self[keyPath: epochKeyPath] else { return } // superseded after roots
                self[keyPath: stateKeyPath] = hasRoots ? .empty : .firstRun
            } else {
                self[keyPath: stateKeyPath] = .loaded
            }
        } catch {
            guard epoch == self[keyPath: epochKeyPath] else { return }
            self[keyPath: stateKeyPath] = .failed(error.localizedDescription)
        }
    }

    // MARK: Detail reads (mirror album(id:)/tracks(inAlbum:); loaded into the detail's local state)

    func artist(id: Int64) async -> ArtistFacet? {
        try? await store?.artist(id: id)
    }

    func genre(id: Int64) async -> GenreFacet? {
        try? await store?.genre(id: id)
    }

    /// Songs by this track-artist (`artist_id`), album/disc/track order.
    func tracks(byArtist id: Int64) async -> [LibraryTrackDisplay] {
        (try? await store?.tracksDisplay(byArtist: id)) ?? []
    }

    func tracks(inGenre id: Int64) async -> [LibraryTrackDisplay] {
        (try? await store?.tracksDisplay(inGenre: id)) ?? []
    }

    // MARK: Whole-facet play verbs (browse tiles — read-then-enqueue)

    /// A browse tile's album, artist or genre: what its queue verbs read, and the page it opens.
    enum FacetRef: Equatable {
        case album(Int64)
        case artist(Int64)
        case genre(Int64)

        var route: LibraryRoute {
            switch self {
            case let .album(id): .album(id)
            case let .artist(id): .artist(id)
            case let .genre(id): .genre(id)
            }
        }
    }

    /// An album's songs in disc / track order; an artist's or a genre's as their pages list them.
    private func facetTracks(_ ref: FacetRef) async -> [LibraryTrackDisplay] {
        switch ref {
        case let .album(id): return await tracks(inAlbum: id)
        case let .artist(id): return await tracks(byArtist: id)
        case let .genre(id): return await tracks(inGenre: id)
        }
    }

    /// The track ids of a whole facet — for a tile's reference-add to a playlist (S10.3). Wraps
    /// the private `facetTracks` read; empty facet → empty (a no-op add).
    func facetTrackIDs(_ ref: FacetRef) async -> [Int64] {
        await facetTracks(ref).map(\.id)
    }

    /// Replace the queue with the whole facet and play (silent, like Play Now everywhere).
    func playFacet(_ ref: FacetRef) async {
        let files = await facetTracks(ref).map(AudioFile.init)
        guard !files.isEmpty else { return }
        audio.playNow(files)
    }

    func playFacetNext(_ ref: FacetRef) async {
        let files = await facetTracks(ref).map(AudioFile.init)
        guard !files.isEmpty else { return } // empty facet → submit nothing, stay silent (gate B-3)
        showQueueToast(.playNext, added: audio.playNext(files))
    }

    func appendFacet(_ ref: FacetRef) async {
        let files = await facetTracks(ref).map(AudioFile.init)
        guard !files.isEmpty else { return } // empty facet → silent (never a false "Already in Queue")
        showQueueToast(.addToQueue, added: audio.appendToQueue(files))
    }

    /// Shuffle a facet's already-loaded tracks (detail-header Shuffle): enable shuffle and play from
    /// a random index, so subsequent tracks shuffle via the engine's on-deck logic.
    func shuffle(_ tracks: [LibraryTrackDisplay]) {
        let files = tracks.map(AudioFile.init)
        guard !files.isEmpty else { return }
        audio.shuffleEnabled = true
        audio.playNow(files, startAt: Int.random(in: 0 ..< files.count))
    }
}
