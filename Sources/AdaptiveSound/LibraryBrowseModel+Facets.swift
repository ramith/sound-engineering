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

    /// Load the Genres list (same flat-facet discipline as `loadArtists`).
    func loadGenres() async {
        await loadFlatFacet(into: \.genres, state: \.genresState, epoch: \.genresLoadEpoch,
                            read: { try await $0.genres() })
    }

    /// Shared loader for the flat facet lists (Artists, Genres). Bumps the facet's epoch, publishes
    /// an optimistic `.loading` while the list is empty, reads, then re-guards the epoch after the
    /// list read AND again after the `roots()` read so a superseded load can never publish a stale
    /// `.empty`/`.firstRun` flash (R1). Written ONCE so that newest-wins invariant is correct across
    /// both facets by construction.
    private func loadFlatFacet<T>(
        into arrayKeyPath: ReferenceWritableKeyPath<LibraryBrowseModel, [T]>,
        state stateKeyPath: ReferenceWritableKeyPath<LibraryBrowseModel, LoadState>,
        epoch epochKeyPath: ReferenceWritableKeyPath<LibraryBrowseModel, Int>,
        read: (LibraryStore) async throws -> [T]
    ) async {
        guard let store else {
            self[keyPath: stateKeyPath] = .loading // store still building; reloads on isStoreReady
            return
        }
        self[keyPath: epochKeyPath] &+= 1
        let epoch = self[keyPath: epochKeyPath]
        if self[keyPath: arrayKeyPath].isEmpty { self[keyPath: stateKeyPath] = .loading }
        do {
            let loaded = try await read(store)
            guard epoch == self[keyPath: epochKeyPath] else { return } // superseded after list read
            self[keyPath: arrayKeyPath] = loaded
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

    // MARK: Whole-facet play verbs (list-row context menus — read-then-enqueue, mirror playAlbum*)

    /// A browse-facet reference for the list-row queue verbs.
    enum FacetRef {
        case artist(Int64)
        case genre(Int64)
    }

    private func facetTracks(_ ref: FacetRef) async -> [LibraryTrackDisplay] {
        switch ref {
        case let .artist(id): return await tracks(byArtist: id)
        case let .genre(id): return await tracks(inGenre: id)
        }
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
