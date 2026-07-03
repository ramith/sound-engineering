// ChecksMetadataStore — S8.3 Slice-1 store-foundation cases (SYNTHETIC data; no real
// files/extraction — that arrives with the tagged fixtures in Slice 5). Drives the
// metadata/artwork WRITE ops through the actor: the `metadata_scanned` marker +
// `tracksNeedingMetadata` + the upsert reset (idempotency + retag), `applyExtractedResult`
// (tags + artwork + album cover in ONE txn), artwork dedup, and reachability-based
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

        guard let row = try await store.track(id: trackID),
              row.title == "Song One", row.trackNo == 3, row.discNo == 1, row.year == 1999,
              row.albumID != nil, row.artistID != nil, row.artworkKey == "hashA" else {
            printFail(number, "apply: track metadata/artwork columns not set correctly"); return false
        }
        guard try await store.albums().contains(where: { $0.title == "The Album" && $0.artworkKey == "hashA" })
        else { printFail(number, "apply: album not resolved or album cover not set"); return false }
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
            + "artist+album, attaches genres, links artwork + sets the album cover — atomically")
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

// MARK: - album-cover first-wins (M5): attachArtworkLocked's `artwork_key IS NULL` guard

/// The album cover is the FIRST applied track's art. `attachArtworkLocked` sets it only when
/// the album has none (`… AND artwork_key IS NULL`), so re-linking a track — or applying a
/// LATER track in the same album — updates the TRACK's art but must NOT override the album
/// cover. Case U covered only album-LESS tracks, so this guard was untested.
func checkAlbumCoverFirstWins(number: Int, url: URL) async -> Bool {
    do {
        let store = try await LibraryStore(url: url, appBuild: "verify")
        let root = try await store.addRoot(URL(fileURLWithPath: "/Music/S83d"))
        let gen = try await store.beginScanGeneration()
        let ids = try await store.upsert([
            makeScanned(path: "/Music/S83d/a.flac", name: "a"),
            makeScanned(path: "/Music/S83d/b.flac", name: "b"),
        ], folderID: root, generation: gen)
        guard ids.count == 2 else { printFail(number, "album-cover: 2-track seed failed"); return false }

        // t0 → art A: the album had no cover, so A becomes the album cover.
        try await applyCover(store, track: ids[0], title: "a", hash: "A", gen: gen)
        guard try await trackArt(store, ids[0]) == "A", try await albumCover(store) == "A" else {
            printFail(number, "album-cover: first apply did not set the album cover to A"); return false
        }
        // Re-link t0 → art B: the TRACK updates; the album cover STAYS A (IS NULL guard).
        try await applyCover(store, track: ids[0], title: "a", hash: "B", gen: gen)
        guard try await trackArt(store, ids[0]) == "B", try await albumCover(store) == "A" else {
            printFail(number, "album-cover: re-link overrode the album cover (IS NULL guard failed)"); return false
        }
        // A SECOND track in the SAME album → art C: album cover still A (not overridden).
        try await applyCover(store, track: ids[1], title: "b", hash: "C", gen: gen)
        guard try await trackArt(store, ids[1]) == "C", try await albumCover(store) == "A" else {
            printFail(number, "album-cover: a later track in the album overrode the album cover"); return false
        }
        printPass(number, "album cover = FIRST applied track's art: the `artwork_key IS NULL` guard means "
            + "re-linking a track (or applying a later track in the album) updates the TRACK art but NEVER "
            + "overrides the album cover")
        return true
    } catch {
        printFail(number, "album-cover-first-wins threw: \(error)"); return false
    }
}

/// Apply `hash` as `track`'s art within album "One Album" (all tracks share the album).
private func applyCover(_ store: LibraryStore, track: Int64, title: String, hash: String, gen: Int64) async throws {
    let meta = TrackMetadata(title: title, artistName: "AA", albumTitle: "One Album", albumArtistName: "AA")
    let link = ArtworkLink(contentHash: hash, cachePath: "/cache/\(hash).jpg",
                           pixelSize: CGSize(width: 10, height: 10), byteSize: 10)
    try await store.applyExtractedResult(trackID: track, meta: meta, artwork: link, generation: gen)
}

private func trackArt(_ store: LibraryStore, _ id: Int64) async throws -> String? {
    try await store.track(id: id)?.artworkKey
}

private func albumCover(_ store: LibraryStore) async throws -> String? {
    try await store.albums().first(where: { $0.title == "One Album" })?.artworkKey
}
