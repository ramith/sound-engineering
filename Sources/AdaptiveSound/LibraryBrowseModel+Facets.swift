import Foundation
import LibraryBrowseKit
import LibraryStore

// MARK: - LibraryBrowseModel facet loading + reads + play verbs (S9.6)

//
// The Artists/Genres/Years list loaders, facet-detail reads, and whole-facet play verbs — split
// from LibraryBrowseModel for file length (the list state lives on the primary decl; it is
// `internal` precisely so this same-type extension can write it).
//
// Each loader is an EXPLICIT copy of `loadAlbums`'s epoch / isStoreReady / firstRun-vs-empty
// discipline — deliberately NOT folded into a generic (gate R1). The load-bearing invariant is the
// newest-wins re-guard after BOTH suspension points (the list read AND the `roots()` read): a
// generic that captured a stale epoch could publish a superseded `.empty`/`.firstRun` flash, and
// the headless gate can't model that race. Three plain copies keep the invariant visible per facet.

@MainActor
extension LibraryBrowseModel {
    // MARK: Loaders (mirror loadAlbums, incl. the SECOND-await epoch re-guard — R1)

    /// Load the Artists list. `firstRun` when no roots are registered, `empty` when roots exist
    /// but no artists yet (mid-scan / untagged), `failed` on error.
    func loadArtists() async {
        guard let store else {
            artistsState = .loading // store still building; reloads on isStoreReady
            return
        }
        artistsLoadEpoch &+= 1
        let epoch = artistsLoadEpoch
        if artists.isEmpty { artistsState = .loading }
        do {
            let loaded = try await store.artists()
            guard epoch == artistsLoadEpoch else { return } // superseded after the list read
            artists = loaded
            if loaded.isEmpty {
                let hasRoots = try await !store.roots().isEmpty
                guard epoch == artistsLoadEpoch else { return } // superseded after the roots read
                artistsState = hasRoots ? .empty : .firstRun
            } else {
                artistsState = .loaded
            }
        } catch {
            guard epoch == artistsLoadEpoch else { return }
            artistsState = .failed(error.localizedDescription)
        }
    }

    /// Load the Genres list (same discipline as `loadArtists`).
    func loadGenres() async {
        guard let store else {
            genresState = .loading
            return
        }
        genresLoadEpoch &+= 1
        let epoch = genresLoadEpoch
        if genres.isEmpty { genresState = .loading }
        do {
            let loaded = try await store.genres()
            guard epoch == genresLoadEpoch else { return }
            genres = loaded
            if loaded.isEmpty {
                let hasRoots = try await !store.roots().isEmpty
                guard epoch == genresLoadEpoch else { return }
                genresState = hasRoots ? .empty : .firstRun
            } else {
                genresState = .loaded
            }
        } catch {
            guard epoch == genresLoadEpoch else { return }
            genresState = .failed(error.localizedDescription)
        }
    }

    /// Load the Years list (`yearFacets()` — per-year song counts; same discipline).
    func loadYears() async {
        guard let store else {
            yearsState = .loading
            return
        }
        yearsLoadEpoch &+= 1
        let epoch = yearsLoadEpoch
        if years.isEmpty { yearsState = .loading }
        do {
            let loaded = try await store.yearFacets()
            guard epoch == yearsLoadEpoch else { return }
            years = loaded
            if loaded.isEmpty {
                let hasRoots = try await !store.roots().isEmpty
                guard epoch == yearsLoadEpoch else { return }
                yearsState = hasRoots ? .empty : .firstRun
            } else {
                yearsState = .loaded
            }
        } catch {
            guard epoch == yearsLoadEpoch else { return }
            yearsState = .failed(error.localizedDescription)
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

    /// Songs whose TRACK year is `year` (`tracks.year`; the Years tab is track-year based).
    func tracks(inYear year: Int) async -> [LibraryTrackDisplay] {
        (try? await store?.tracksDisplay(inYear: year)) ?? []
    }

    // MARK: Whole-facet play verbs (list-row context menus — read-then-enqueue, mirror playAlbum*)

    /// A browse-facet reference for the list-row queue verbs. An enum (not `(kind, Int64)`) because
    /// a year is `Int` while artist/genre are `Int64`; the switch absorbs that asymmetry.
    enum FacetRef {
        case artist(Int64)
        case genre(Int64)
        case year(Int)
    }

    private func facetTracks(_ ref: FacetRef) async -> [LibraryTrackDisplay] {
        switch ref {
        case let .artist(id): return await tracks(byArtist: id)
        case let .genre(id): return await tracks(inGenre: id)
        case let .year(year): return await tracks(inYear: year)
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
