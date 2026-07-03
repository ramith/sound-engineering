// ChecksFacetSweep — S8.4 Slice 2 SF-2 facet-orphan sweep cases. Pure store logic (no
// filesystem): seed tagged tracks via applyMetadata, orphan facets by deleting tracks,
// then assert sweepOrphanFacets reaps exactly the unreferenced albums/artists/genres —
// and NEVER the id-0 sentinel or a still-referenced facet. Same VerifyAUGraph idiom.

import CoreGraphics
import Foundation
import LibraryStore

// MARK: - F1 / F3 / F5 / F6 — basics (zero-track album, referenced kept, genre, idempotent)

func checkFacetSweepBasics(number: Int, url: URL) async -> Bool {
    do {
        let store = try await LibraryStore(url: url, appBuild: "verify")
        // Two tracks on album "Live" (genres too); one track on album "Ghost".
        let live1 = try await seedTaggedTrack(store, path: "/f/live1.flac",
                                              meta: TrackMetadata(title: "L1", artistName: "Band",
                                                                  albumTitle: "Live", genres: ["Xtest"]))
        _ = try await seedTaggedTrack(store, path: "/f/live2.flac",
                                      meta: TrackMetadata(title: "L2", artistName: "Band", albumTitle: "Live"))
        let ghost = try await seedTaggedTrack(store, path: "/f/ghost.flac",
                                              meta: TrackMetadata(title: "G", artistName: "Solo", albumTitle: "Ghost"))
        guard try await store.albums().contains(where: { $0.title == "Ghost" }),
              try await store.genres().contains(where: { $0.name == "Xtest" }) else {
            printFail(number, "facet-basics: seed albums/genres missing"); return false
        }
        // Delete the Ghost track and ONE Live track → Ghost is zero-track; Live keeps one.
        try await store.delete(id: ghost)
        try await store.delete(id: live1)
        let counts = try await store.sweepOrphanFacets()
        guard try await !store.albums().contains(where: { $0.title == "Ghost" }), counts.albums >= 1 else {
            printFail(number, "facet-basics: zero-track album 'Ghost' not swept"); return false
        }
        guard let liveAlbum = try await store.albums().first(where: { $0.title == "Live" }),
              liveAlbum.trackCount == 1 else {
            printFail(number, "facet-basics: still-referenced album 'Live' was wrongly swept"); return false
        }
        // Xtest genre came ONLY from live1 (now deleted → track_genres cascaded) → swept.
        guard try await !store.genres().contains(where: { $0.name == "Xtest" }) else {
            printFail(number, "facet-basics: orphan genre 'Xtest' not swept"); return false
        }
        // Idempotent: a second sweep changes nothing.
        let second = try await store.sweepOrphanFacets()
        guard second.albums == 0, second.artists == 0, second.genres == 0 else {
            printFail(number, "facet-basics: second sweep was not a no-op (\(second))"); return false
        }
        printPass(number, "facet sweep basics: a zero-track album + its orphan genre are swept; a "
            + "still-referenced album survives; a second sweep is a no-op (idempotent)")
        return true
    } catch {
        printFail(number, "facet-basics threw: \(error)"); return false
    }
}

// MARK: - F2 / F4 — sentinel never swept; album-artist-only artist kept (two-arm reachability)

func checkFacetSweepSentinelAndAlbumArtist(number: Int, url: URL) async -> Bool {
    do {
        let store = try await LibraryStore(url: url, appBuild: "verify")
        // A compilation-style row: album "Comp" whose album_artist is "VA", but the TRACK has
        // no artist_id (artistName nil). So "VA" is referenced ONLY as an album_artist.
        let comp = try await seedTaggedTrack(store, path: "/f/comp.flac",
                                             meta: TrackMetadata(title: "C", albumTitle: "Comp", albumArtistName: "VA"))
        guard let vaID = try await store.artists().first(where: { $0.name == "VA" })?.id else {
            printFail(number, "facet-artist: album-artist 'VA' not resolved"); return false
        }
        // Sweep: VA is reachable via the live album → KEPT; its album's album_artist_id unchanged
        // (MF-3 — must NOT be rewritten to the id-0 sentinel by ON DELETE SET DEFAULT).
        _ = try await store.sweepOrphanFacets()
        guard let compAlbum = try await store.albums().first(where: { $0.title == "Comp" }),
              compAlbum.albumArtistID == vaID else {
            printFail(number, "facet-artist: album-artist-only artist swept OR album_artist_id rewritten"); return false
        }
        // The id-0 sentinel is never swept (it backs the M1 album key).
        guard try await store.countRows(inTable: "artists") >= 1,
              try await store.artists().first(where: { $0.id == unknownArtistID }) == nil else {
            printFail(number, "facet-artist: sentinel missing, or wrongly listed in the artists facet"); return false
        }
        // Now delete the track → Comp is zero-track → album swept → VA becomes unreachable → swept.
        try await store.delete(id: comp)
        _ = try await store.sweepOrphanFacets()
        guard try await !store.artists().contains(where: { $0.name == "VA" }),
              try await store.countRows(inTable: "artists") == 1 else { // only the sentinel remains
            printFail(number, "facet-artist: now-unreferenced 'VA' not swept, or sentinel lost"); return false
        }
        printPass(number, "facet sweep sentinel/album-artist: an artist referenced only as an album_artist "
            + "is KEPT (album_artist_id not rewritten); the id-0 sentinel is NEVER swept; once its album "
            + "goes the artist is reaped")
        return true
    } catch {
        printFail(number, "facet-artist threw: \(error)"); return false
    }
}

// MARK: - F8 — album deletion orphans artwork, then sweepOrphanArtwork reclaims it

func checkFacetSweepArtworkInteraction(number: Int, url: URL) async -> Bool {
    do {
        let store = try await LibraryStore(url: url, appBuild: "verify")
        let file = ScannedFile(url: URL(fileURLWithPath: "/f/art.flac"), relativePath: "", name: "art",
                               format: "FLAC", fileSize: 1, mtime: 1, inode: nil, dev: nil)
        let id = try await store.addLooseFile(file)
        let art = ArtworkLink(contentHash: "hashZ", cachePath: "/cache/hashZ.jpg",
                              pixelSize: CGSize(width: 300, height: 300), byteSize: 1024)
        let gen = try await store.beginScanGeneration()
        try await store.applyExtractedResult(
            trackID: id, meta: TrackMetadata(title: "A", albumTitle: "Art"), artwork: art, generation: gen
        )
        // Delete the track → album "Art" is zero-track. Facet sweep removes the album, whose
        // ON DELETE SET NULL nulls its artwork_key → hashZ is now referenced by nothing.
        try await store.delete(id: id)
        _ = try await store.sweepOrphanFacets()
        let reclaimed = try await store.sweepOrphanArtwork()
        guard reclaimed.contains(where: { $0.contentHash == "hashZ" }) else {
            printFail(number, "facet-artwork: artwork orphaned by album deletion was NOT reclaimed"); return false
        }
        printPass(number, "facet sweep + artwork: deleting a track sweeps its zero-track album, whose nulled "
            + "artwork_key leaves the cover referenced by nothing → sweepOrphanArtwork reclaims it (run order)")
        return true
    } catch {
        printFail(number, "facet-artwork threw: \(error)"); return false
    }
}

// MARK: - Seed helper

/// Add a loose track at a synthetic path (no FS) and apply `meta` to it, returning its id.
private func seedTaggedTrack(_ store: LibraryStore, path: String, meta: TrackMetadata) async throws -> Int64 {
    let file = ScannedFile(url: URL(fileURLWithPath: path), relativePath: "", name: "seed",
                           format: "FLAC", fileSize: 1, mtime: 1, inode: nil, dev: nil)
    let id = try await store.addLooseFile(file)
    try await store.applyMetadata(meta, forTrack: id)
    return id
}
