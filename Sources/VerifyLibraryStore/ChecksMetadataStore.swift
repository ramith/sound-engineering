// ChecksMetadataStore — S8.3 Slice-1 store-foundation cases (SYNTHETIC data; no real
// files/extraction — that arrives with the tagged fixtures in Slice 5). Drives the
// metadata/artwork WRITE ops through the actor: the `metadata_scanned` marker +
// `tracksNeedingMetadata` + the upsert reset (idempotency + retag), `applyExtractedResult`
// (tags + artwork in ONE txn; the album + its cover at the end-of-pass regroup), artwork dedup,
// the deterministic album cover, and reachability-based
// orphan sweep. Same VerifyAUGraph idiom (Bool return, numbered PASS/FAIL, temp DBs).

import CoreGraphics
import Foundation
import LibraryScan
import LibraryStore

// MARK: - s — metadata_scanned marker + tracksNeedingMetadata + upsert reset

func checkMetadataMarker(number: Int, url: URL) async -> Bool {
    do {
        let store = try await LibraryStore(url: url, appBuild: "verify")
        let root = try await store.addRoot(URL(fileURLWithPath: "/Music/S83"))
        let gen1 = try await store.beginScanGeneration()
        let ids = try await store.upsert([
            makeScanned(path: "/Music/S83/a.flac", name: "a"),
            makeScanned(path: "/Music/S83/b.flac", name: "b"),
            makeScanned(path: "/Music/S83/c.flac", name: "c"),
        ], folderID: root, generation: gen1)
        guard ids.count == 3 else { printFail(number, "marker: 3-track seed failed"); return false }

        guard try await store.tracksNeedingMetadata(limit: 100).count == 3 else {
            printFail(number, "marker: expected all 3 tracks to need metadata initially"); return false
        }
        // applyExtractedResult marks ids[0]; markMetadataScanned marks ids[1].
        try await store.applyExtractedResult(
            trackID: ids[0], meta: TrackMetadata(title: "A!"), artwork: nil, generation: gen1
        )
        try await store.markMetadataScanned(trackID: ids[1], generation: gen1)
        guard try await store.track(id: ids[0])?.title == "A!" else {
            printFail(number, "marker: applyExtractedResult didn't write metadata"); return false
        }
        let remaining = try await store.tracksNeedingMetadata(limit: 100)
        guard remaining == [ids[2]] else {
            printFail(number, "marker: expected only ids[2] remaining, got \(remaining)"); return false
        }
        return await checkMetadataResetOnUpsert(store, number: number, root: root, scannedID: ids[0])
    } catch {
        printFail(number, "metadata marker threw: \(error)"); return false
    }
}

/// An UNCHANGED re-upsert must NOT reset `metadata_scanned` (idempotency); a MODIFIED
/// re-upsert (size/mtime change) MUST reset it to 0 so the retagged file re-extracts.
private func checkMetadataResetOnUpsert(
    _ store: LibraryStore, number: Int, root: Int64, scannedID: Int64
) async -> Bool {
    do {
        let gen2 = try await store.beginScanGeneration()
        _ = try await store.upsert(
            [makeScanned(path: "/Music/S83/a.flac", name: "a")], folderID: root, generation: gen2
        )
        guard try await store.tracksNeedingMetadata(limit: 100).contains(scannedID) == false else {
            printFail(number, "reset: an UNCHANGED re-upsert wrongly reset the marker"); return false
        }
        let gen3 = try await store.beginScanGeneration()
        _ = try await store.upsert(
            [makeScanned(path: "/Music/S83/a.flac", name: "a", size: 9999, mtime: 2000)],
            folderID: root, generation: gen3
        )
        guard try await store.tracksNeedingMetadata(limit: 100).contains(scannedID) else {
            printFail(number, "reset: a MODIFIED re-upsert did NOT reset the marker (a retag would be missed)")
            return false
        }
        printPass(number, "metadata marker: tracksNeedingMetadata drives off metadata_scanned; "
            + "applyExtractedResult + markMetadataScanned set it; an UNCHANGED re-upsert preserves it "
            + "(idempotent) while a MODIFIED re-upsert resets it (retag re-extracts)")
        return true
    } catch {
        printFail(number, "metadata reset threw: \(error)"); return false
    }
}

// MARK: - t — applyExtractedResult (tags + artwork + album cover, one transaction)

func checkMetadataApplyResult(number: Int, url: URL) async -> Bool {
    do {
        let store = try await LibraryStore(url: url, appBuild: "verify")
        let root = try await store.addRoot(URL(fileURLWithPath: "/Music/S83b"))
        let gen = try await store.beginScanGeneration()
        let ids = try await store.upsert(
            [makeScanned(path: "/Music/S83b/song.flac", name: "song")], folderID: root, generation: gen
        )
        guard let trackID = ids.first else { printFail(number, "apply: seed failed"); return false }

        let art = ArtworkLink(
            contentHash: "hashA", cachePath: "/cache/hashA.jpg",
            pixelSize: CGSize(width: 500, height: 500), byteSize: 2048
        )
        let meta = TrackMetadata(
            title: "Song One", artistName: "The Artist", albumTitle: "The Album",
            albumArtistName: "The Artist", year: 1999, trackNo: 3, discNo: 1, genres: ["Rock", "Jazz"]
        )
        try await store.applyExtractedResult(trackID: trackID, meta: meta, artwork: art, generation: gen)

        // The pass write does no album work (S10.8 C2 fix round, B2): it records the regroup debt,
        // and the end-of-pass regroup (`refreshDerivedFacets`) assigns the album and its cover.
        guard let row = try await store.track(id: trackID),
              row.title == "Song One", row.trackNo == 3, row.discNo == 1, row.year == 1999,
              row.albumID == nil, row.artistID != nil, row.artworkKey == "hashA",
              try await store.isAlbumRegroupOwed() else {
            printFail(number, "apply: track metadata/artwork columns not set correctly (or the album "
                + "was assigned per write / the regroup debt not recorded)"); return false
        }
        try await store.refreshDerivedFacets()
        guard try await store.track(id: trackID)?.albumID != nil, try await !store.isAlbumRegroupOwed(),
              try await store.albums().contains(where: { $0.title == "The Album" && $0.artworkKey == "hashA" })
        else { printFail(number, "apply: the end-of-pass regroup did not resolve the album + cover"); return false }
        guard try await store.artists().contains(where: { $0.name == "The Artist" }) else {
            printFail(number, "apply: artist not resolved"); return false
        }
        guard try Set(await store.genres().map(\.name)).isSuperset(of: ["Rock", "Jazz"]) else {
            printFail(number, "apply: genres not attached"); return false
        }
        guard try await store.countRows(inTable: "artwork") == 1 else {
            printFail(number, "apply: expected exactly 1 artwork row"); return false
        }
        printPass(number, "applyExtractedResult (one txn): writes tags (title/track/disc/year), resolves "
            + "the artist, attaches genres, links artwork and records the regroup debt — atomically; the "
            + "end-of-pass regroup then resolves the album + its cover and clears the debt")
        return true
    } catch {
        printFail(number, "apply-result threw: \(error)"); return false
    }
}

// MARK: - u — artwork dedup + reachability-based orphan sweep

func checkMetadataArtworkOrphan(number: Int, url: URL) async -> Bool {
    do {
        let store = try await LibraryStore(url: url, appBuild: "verify")
        let root = try await store.addRoot(URL(fileURLWithPath: "/Music/S83c"))
        let gen = try await store.beginScanGeneration()
        let ids = try await store.upsert([
            makeScanned(path: "/Music/S83c/x.flac", name: "x"),
            makeScanned(path: "/Music/S83c/y.flac", name: "y"),
        ], folderID: root, generation: gen)
        guard ids.count == 2 else { printFail(number, "orphan: seed failed"); return false }

        // Two album-less tracks, SAME cover hash → dedup to ONE artwork row.
        let shared = ArtworkLink(
            contentHash: "dup", cachePath: "/cache/dup.jpg",
            pixelSize: CGSize(width: 300, height: 300), byteSize: 900
        )
        try await store.applyExtractedResult(trackID: ids[0], meta: TrackMetadata(title: "x"),
                                             artwork: shared, generation: gen)
        try await store.applyExtractedResult(trackID: ids[1], meta: TrackMetadata(title: "y"),
                                             artwork: shared, generation: gen)
        guard try await store.countRows(inTable: "artwork") == 1 else {
            printFail(number, "orphan: same-hash art did not dedup to one row"); return false
        }
        return await checkArtworkReachabilitySweep(store, number: number, root: root)
    } catch {
        printFail(number, "artwork dedup/orphan threw: \(error)"); return false
    }
}

/// Orphan sweep is by REACHABILITY: an album-less track re-linked to new art leaves the
/// OLD hash referenced by no track and no album → swept; still-referenced hashes are kept.
private func checkArtworkReachabilitySweep(_ store: LibraryStore, number: Int, root: Int64) async -> Bool {
    do {
        let gen = try await store.beginScanGeneration()
        let ids = try await store.upsert(
            [makeScanned(path: "/Music/S83c/z.flac", name: "z")], folderID: root, generation: gen
        )
        guard let zID = ids.first else { printFail(number, "sweep: seed failed"); return false }
        let old = ArtworkLink(contentHash: "orphanme", cachePath: "/cache/orphanme.jpg",
                              pixelSize: CGSize(width: 100, height: 100), byteSize: 100)
        try await store.applyExtractedResult(trackID: zID, meta: TrackMetadata(title: "z"),
                                             artwork: old, generation: gen)
        guard try await store.sweepOrphanArtwork().isEmpty else {
            printFail(number, "sweep: swept a still-referenced artwork"); return false
        }
        // Re-link z to new art → 'orphanme' is now referenced by no track and no album.
        let new = ArtworkLink(contentHash: "fresh", cachePath: "/cache/fresh.jpg",
                              pixelSize: CGSize(width: 100, height: 100), byteSize: 100)
        try await store.applyExtractedResult(trackID: zID, meta: TrackMetadata(title: "z"),
                                             artwork: new, generation: gen)
        let swept = try await store.sweepOrphanArtwork()
        guard swept.count == 1, swept[0].contentHash == "orphanme" else {
            printFail(number, "sweep: expected exactly 'orphanme' swept, got \(swept.map(\.contentHash))")
            return false
        }
        guard try await store.track(id: zID)?.artworkKey == "fresh",
              try await store.countRows(inTable: "artwork") == 2 else {
            printFail(number, "sweep: 'dup'+'fresh' should survive and z should point at 'fresh'"); return false
        }
        printPass(number, "artwork: same-hash covers dedup to ONE row; orphan sweep is by reachability — "
            + "an album-less track re-linked to new art leaves the old hash referenced by nothing → swept, "
            + "still-referenced hashes kept")
        return true
    } catch {
        printFail(number, "artwork reachability sweep threw: \(error)"); return false
    }
}

// MARK: - v — MetadataExtractor FS-tolerance smoke (Slice 2; full extraction is Slice 5)

func checkExtractorVanishedFile(number: Int, url: URL) async -> Bool {
    // A vanished/unreadable file yields nil (never a throw, never a crash) on BOTH routing
    // paths — flac (FFmpeg-first) and m4a (AVFoundation-first). Full extraction correctness
    // (real tagged fixtures) is Slice 5's M1/M2. `url` (the temp store path) is unused here.
    _ = url
    let extractor = MetadataExtractor()
    let ghostFlac = URL(fileURLWithPath: "/nonexistent-\(UUID().uuidString)/ghost.flac")
    let ghostM4a = URL(fileURLWithPath: "/nonexistent-\(UUID().uuidString)/ghost.m4a")
    guard await extractor.extract(from: ghostFlac) == nil else {
        printFail(number, "extractor: expected nil for a vanished .flac (FFmpeg path)"); return false
    }
    guard await extractor.extract(from: ghostM4a) == nil else {
        printFail(number, "extractor: expected nil for a vanished .m4a (AVFoundation path)"); return false
    }
    printPass(number, "extractor FS-tolerance: a vanished file yields nil (no crash) on both the "
        + "FFmpeg-first (.flac) and AVFoundation-first (.m4a) routing paths")
    return true
}

// MARK: - album cover is deterministic (S10.8 C2 fix round, C8 — replaces M5's "first wins")

/// The album cover is the art of its FIRST song in album order — lowest disc, then track number
/// (a missing disc reads as disc 1, a song without a track number comes last) — whichever file the
/// pass happened to read first. M5's rule ("the first APPLIED track's art wins") made the cover
/// depend on extraction order; C8 replaces it. Proven by applying the same songs in two orders.
func checkAlbumCoverDeterministic(number: Int, url: URL) async -> Bool {
    do {
        let store = try await LibraryStore(url: url, appBuild: "verify")
        let root = try await store.addRoot(URL(fileURLWithPath: "/Music/S83d"))
        let gen = try await store.beginScanGeneration()
        let ids = try await store.upsert(["a", "b", "c", "d"].map {
            makeScanned(path: "/Music/S83d/\($0).flac", name: $0)
        }, folderID: root, generation: gen)
        guard ids.count == 4 else { printFail(number, "album-cover: 4-track seed failed"); return false }
        // Album order: c (disc —, track 1) < b (disc 1, track 2) < d (disc 2, track 1) < a (no track).
        let order = [
            CoverSong(id: ids[0], disc: 1, trackNo: nil, hash: "A"),
            CoverSong(id: ids[1], disc: 1, trackNo: 2, hash: "B"),
            CoverSong(id: ids[2], disc: nil, trackNo: 1, hash: "C"),
            CoverSong(id: ids[3], disc: 2, trackNo: 1, hash: "D"),
        ]
        // Read in file order, then in REVERSE — the cover must be C both times.
        for pass in [order, order.reversed()] {
            for song in pass {
                try await applyCover(store, song, gen: gen)
            }
            try await store.refreshDerivedFacets()
            let cover = try await albumCover(store)
            guard cover == "C" else {
                printFail(number, "album-cover: cover is \(String(describing: cover)) after reading "
                    + "\(pass.map(\.hash)), expected C (disc 1 track 1)"); return false
            }
        }
        // Re-link the first song's art → the cover follows it; renumber that song to track 9 → the
        // new first song's art (B) takes over.
        try await applyCover(store, CoverSong(id: ids[2], disc: nil, trackNo: 1, hash: "E"), gen: gen)
        try await store.refreshDerivedFacets()
        let followed = try await albumCover(store)
        try await applyCover(store, CoverSong(id: ids[2], disc: nil, trackNo: 9, hash: nil), gen: gen)
        try await store.refreshDerivedFacets()
        guard followed == "E", try await albumCover(store) == "B" else {
            printFail(number, "album-cover: the first song's new art (\(String(describing: followed))) or the "
                + "new first song's art did not become the cover"); return false
        }
        printPass(number, "album cover is deterministic (C8): the art of the album's first song in (disc, "
            + "track) order — a missing disc is disc 1, an unnumbered song last — the same whichever order the "
            + "files are read; it follows that song's art, and the album order when a song is renumbered")
        return true
    } catch {
        printFail(number, "album-cover-deterministic threw: \(error)"); return false
    }
}

/// One song of album "One Album": its id, album position and art (nil = leave its art).
private struct CoverSong {
    let id: Int64
    let disc: Int?
    let trackNo: Int?
    let hash: String?
}

/// Apply `song`'s position and art within album "One Album" (all tracks share it).
private func applyCover(_ store: LibraryStore, _ song: CoverSong, gen: Int64) async throws {
    let meta = TrackMetadata(title: "t\(song.id)", artistName: "AA", albumTitle: "One Album", albumArtistName: "AA",
                             trackNo: song.trackNo, discNo: song.disc)
    let link = song.hash.map {
        ArtworkLink(contentHash: $0, cachePath: "/cache/\($0).jpg", pixelSize: CGSize(width: 10, height: 10),
                    byteSize: 10)
    }
    try await store.applyExtractedResult(trackID: song.id, meta: meta, artwork: link, generation: gen)
}

private func trackArt(_ store: LibraryStore, _ id: Int64) async throws -> String? {
    try await store.track(id: id)?.artworkKey
}

private func albumCover(_ store: LibraryStore) async throws -> String? {
    try await store.albums().first(where: { $0.title == "One Album" })?.artworkKey
}
