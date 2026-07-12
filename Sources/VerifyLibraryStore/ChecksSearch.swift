// ChecksSearch — S9.2 FTS5 search: the write-path sync seam, query safety/matching,
// and read-during-write (design §4, test plan §10). The v1→v2 migration/backfill +
// capability-probe cases live in ChecksSearchMigration (file-length budget).
//
// Every case here runs on a normally-opened v2 store and drives the real seam via
// upsert / applyMetadata / moveMatched / delete / sweepOrphans / removeRoot,
// asserting through store.search().

import Foundation
import LibraryScan
import LibraryStore

// MARK: - SYNC1/SYNC2 — new track findable by filename; retag re-syncs

func checkFtsSyncOnWrite(number: Int, url: URL) async -> Bool {
    do {
        let store = try await LibraryStore(url: url, appBuild: "verify")
        let generation = try await store.beginScanGeneration()
        let root = try await store.addRoot(URL(fileURLWithPath: "/Music/S"))
        let ids = try await store.upsert(
            [makeScanned(path: "/Music/S/quartzwidget.flac", name: "quartzwidget.flac")],
            folderID: root, generation: generation
        )
        // SYNC1: a pre-metadata track is findable by its filename immediately.
        guard try await store.search("quartzwidget").tracks.count == 1 else {
            printFail(number, "SYNC1: a new pre-metadata track was not findable by filename"); return false
        }
        // SYNC2: applying tags makes the new terms hit and the filename term miss.
        try await store.applyMetadata(
            TrackMetadata(title: "Bohemian Rhapsody", artistName: "Queen", albumTitle: "A Night"),
            forTrack: ids[0]
        )
        guard try await store.search("bohemian").tracks.count == 1,
              try await store.search("queen").tracks.count == 1,
              try await store.search("quartzwidget").tracks.isEmpty else {
            printFail(number, "SYNC2: retag did not re-sync (new terms miss or the old filename still hits)")
            return false
        }
        printPass(number, "SYNC1/2: a new track is findable by filename; applyMetadata re-syncs so the "
            + "tag terms hit and the old filename term misses")
        return true
    } catch {
        printFail(number, "SYNC1/2 threw: \(error)"); return false
    }
}

// MARK: - SYNC3 — rename of a tagless file re-syncs (the blocker-fix: moveMatchedLocked)

func checkFtsSyncOnRename(number: Int, url: URL) async -> Bool {
    do {
        let store = try await LibraryStore(url: url, appBuild: "verify")
        let generation = try await store.beginScanGeneration()
        let root = try await store.addRoot(URL(fileURLWithPath: "/Music/R"))
        let ids = try await store.upsert(
            [makeScanned(path: "/Music/R/olduniquename.flac", name: "olduniquename.flac", inode: 777)],
            folderID: root, generation: generation
        )
        guard try await store.search("olduniquename").tracks.count == 1 else {
            printFail(number, "SYNC3: tagless file not findable by its original name"); return false
        }
        // Rename-in-place via the reconcile move path (rewrites `name`, no metadata reset).
        let moved = makeScanned(path: "/Music/R/newuniquename.flac", name: "newuniquename.flac", inode: 777)
        try await store.moveMatched(id: ids[0], to: moved, newFolderID: root, generation: generation)
        guard try await store.search("newuniquename").tracks.count == 1,
              try await store.search("olduniquename").tracks.isEmpty else {
            printFail(number, "SYNC3: after a tagless rename the new name does not hit or the old still does")
            return false
        }
        printPass(number, "SYNC3: a renamed tagless file (moveMatched) re-syncs FTS — the new filename "
            + "hits, the old misses (the write-path completeness blocker-fix)")
        return true
    } catch {
        printFail(number, "SYNC3 threw: \(error)"); return false
    }
}

// MARK: - SYNC-genre — a genre applied via the write path is searchable

func checkFtsGenreWritePath(number: Int, url: URL) async -> Bool {
    do {
        let store = try await LibraryStore(url: url, appBuild: "verify")
        let generation = try await store.beginScanGeneration()
        let root = try await store.addRoot(URL(fileURLWithPath: "/Music/G"))
        let ids = try await store.upsert(
            [makeScanned(path: "/Music/G/track.flac", name: "track.flac")],
            folderID: root, generation: generation
        )
        // Genre flows replaceGenres → syncSearchRow (which runs AFTER it, so group_concat is
        // fresh). This write-path ordering is distinct from the migration backfill — the only
        // other genre-touching path — and had no coverage.
        try await store.applyMetadata(
            TrackMetadata(title: "Untitled", genres: ["Shoegaze"]), forTrack: ids[0]
        )
        guard try await store.search("shoegaze").tracks.count == 1 else {
            printFail(number, "SYNC-genre: a genre applied via applyMetadata was not searchable"); return false
        }
        printPass(number, "SYNC-genre: a genre written via applyMetadata is searchable — proves the "
            + "syncSearchRow-after-replaceGenres ordering on the write path")
        return true
    } catch {
        printFail(number, "SYNC-genre threw: \(error)"); return false
    }
}

// MARK: - DEL1/MOVE — delete clears the FTS row; a url-only move leaves it intact

func checkFtsDeleteAndMove(number: Int, url: URL) async -> Bool {
    do {
        let store = try await LibraryStore(url: url, appBuild: "verify")
        let generation = try await store.beginScanGeneration()
        let root = try await store.addRoot(URL(fileURLWithPath: "/Music/D"))
        let ids = try await store.upsert(
            [makeScanned(path: "/Music/D/zephyrium.flac", name: "zephyrium.flac")],
            folderID: root, generation: generation
        )
        try await store.applyMetadata(TrackMetadata(title: "Zephyrium Song"), forTrack: ids[0])
        guard try await store.search("zephyrium").tracks.count == 1 else {
            printFail(number, "DEL/MOVE: track not findable pre-move"); return false
        }
        // MOVE: url-only move changes no searchable field → the hit is intact.
        try await store.moveTrack(id: ids[0], newURL: URL(fileURLWithPath: "/Music/D/moved.flac"),
                                  newFolderID: root, newRelativePath: "moved.flac")
        guard try await store.search("zephyrium").tracks.count == 1 else {
            printFail(number, "MOVE: a url-only moveTrack lost the FTS hit"); return false
        }
        // DEL1: deleting the track clears its FTS row.
        try await store.delete(id: ids[0])
        guard try await store.search("zephyrium").tracks.isEmpty else {
            printFail(number, "DEL1: a stale FTS row survived delete(id:)"); return false
        }
        printPass(number, "DEL1/MOVE: delete(id:) clears the FTS row; a url-only moveTrack (no searchable "
            + "field change) keeps the hit")
        return true
    } catch {
        printFail(number, "DEL1/MOVE threw: \(error)"); return false
    }
}

// MARK: - DEL2/DEL3 — sweepOrphans drops FTS by exactly the swept count; removeRoot clears

func checkFtsSweepAndRemoveRoot(number: Int, url: URL) async -> Bool {
    do {
        let store = try await LibraryStore(url: url, appBuild: "verify")
        let gen1 = try await store.beginScanGeneration()
        let root = try await store.addRoot(URL(fileURLWithPath: "/Music/W"))
        _ = try await store.upsert([
            makeScanned(path: "/Music/W/survivorsong.flac", name: "survivorsong.flac", inode: 1),
            makeScanned(path: "/Music/W/orphansong.flac", name: "orphansong.flac", inode: 2),
        ], folderID: root, generation: gen1)
        // Re-scan at a newer generation seeing only the survivor → the orphan is older.
        let gen2 = try await store.beginScanGeneration()
        _ = try await store.upsert(
            [makeScanned(path: "/Music/W/survivorsong.flac", name: "survivorsong.flac", inode: 1)],
            folderID: root, generation: gen2
        )
        let ftsBefore = try await store.countRows(inTable: "tracks_fts")
        let swept = try await store.sweepOrphans(inFolders: [root], olderThan: gen2)
        let ftsAfter = try await store.countRows(inTable: "tracks_fts")
        guard swept == 1, ftsBefore - ftsAfter == swept,
              try await store.search("orphansong").tracks.isEmpty,
              try await store.search("survivorsong").tracks.count == 1 else {
            printFail(number, "DEL2: sweepOrphans FTS delta \(ftsBefore - ftsAfter) != swept \(swept), "
                + "or a stale/dropped hit"); return false
        }
        // DEL3: removeRoot deletes the survivor's row (no playlist refs) → its FTS row too.
        try await store.removeRoot(id: root)
        guard try await store.search("survivorsong").tracks.isEmpty else {
            printFail(number, "DEL3: removeRoot left a stale FTS row"); return false
        }
        printPass(number, "DEL2/3: sweepOrphans drops tracks_fts by EXACTLY the swept count "
            + "(capture-before-delete ordering); removeRoot clears its tracks' FTS rows")
        return true
    } catch {
        printFail(number, "DEL2/3 threw: \(error)"); return false
    }
}

// MARK: - Q1/Q2 — injection safety + empty/all-stripped → empty

func checkFtsQuerySafety(number: Int, url: URL) async -> Bool {
    do {
        let store = try await LibraryStore(url: url, appBuild: "verify")
        let generation = try await store.beginScanGeneration()
        let root = try await store.addRoot(URL(fileURLWithPath: "/Music/Q"))
        let ids = try await store.upsert(
            [makeScanned(path: "/Music/Q/song.flac", name: "song.flac")],
            folderID: root, generation: generation
        )
        try await store.applyMetadata(TrackMetadata(title: "Alpha Beta"), forTrack: ids[0])
        // Q1: FTS5 specials must not throw AND must still MATCH — punctuation SPLITS terms
        // (mirroring unicode61), it does not fuse them. "alpha(beta)" → ["alpha","beta"],
        // which matches "Alpha Beta" (a whitespace-only strip would fuse to "alphabeta" →
        // miss; this is the sanitizer BLOCKER regression guard).
        // Each reduces to terms all present in "Alpha Beta" (alpha and/or beta). NB a digit
        // like "2" would be its own required token (correctly), so it's excluded here.
        for raw in ["alpha*", "\"alpha\"", "alpha(beta)", "alpha:beta", "-alpha", "alpha.beta", "^alpha^"] {
            guard try await store.search(raw).tracks.count == 1 else {
                printFail(number, "Q1: special-char query '\(raw)' did not match 'Alpha Beta' (threw or fused)")
                return false
            }
        }
        // Q2: empty / whitespace / all-special / non-token-alphanumeric (½ ①, category No/Nl
        // that unicode61 drops) → empty results (never a full-table match, never a syntax error).
        for raw in ["", "   ", "\t\n", "* : ( ) -", "\"\"", "()", "½", "①", "½ ①", "^"] {
            guard try await store.search(raw).tracks.isEmpty else {
                printFail(number, "Q2: query '\(raw)' matched or threw instead of returning empty"); return false
            }
        }
        printPass(number, "Q1/2: punctuated queries SPLIT (not fuse) so 'alpha(beta)' matches 'Alpha "
            + "Beta'; empty/whitespace/all-special/non-token (½/①) queries return empty, never a match/throw")
        return true
    } catch {
        printFail(number, "Q1/2 threw: \(error)"); return false
    }
}

// MARK: - Q3/Q4/Q5 — prefix, implicit-AND, unicode/diacritics

func checkFtsQueryMatching(number: Int, url: URL) async -> Bool {
    do {
        let store = try await LibraryStore(url: url, appBuild: "verify")
        let generation = try await store.beginScanGeneration()
        let root = try await store.addRoot(URL(fileURLWithPath: "/Music/M"))
        let ids = try await store.upsert([
            makeScanned(path: "/Music/M/1.flac", name: "1.flac", inode: 11),
            makeScanned(path: "/Music/M/2.flac", name: "2.flac", inode: 12),
        ], folderID: root, generation: generation)
        try await store.applyMetadata(
            TrackMetadata(title: "Dark Side of the Moon", artistName: "Björk"), forTrack: ids[0]
        )
        try await store.applyMetadata(TrackMetadata(title: "Motörhead Anthem"), forTrack: ids[1])
        // Q3 prefix; Q4 implicit-AND; Q5 diacritics (remove_diacritics 2 folds ö→o).
        guard try await store.search("dar").tracks.contains(where: { $0.title.hasPrefix("Dark") }),
              try await store.search("dark side").tracks.count == 1,
              try await store.search("dark xyzzy").tracks.isEmpty,
              try await store.search("bjork").tracks.count == 1,
              try await store.search("motorhead").tracks.count == 1 else {
            printFail(number, "Q3/4/5: prefix, implicit-AND, or diacritic-folding matching failed")
            return false
        }
        printPass(number, "Q3/4/5: prefix ('dar'→Dark), implicit-AND ('dark side' matches, 'dark xyzzy' "
            + "doesn't), and diacritic folding ('bjork'→Björk, 'motorhead'→Motörhead)")
        return true
    } catch {
        printFail(number, "Q3/4/5 threw: \(error)"); return false
    }
}

// MARK: - Q6/Q7 — bm25 ranking (title > album-only) + deduped result facets

func checkFtsRankingAndShape(number: Int, url: URL) async -> Bool {
    do {
        let store = try await LibraryStore(url: url, appBuild: "verify")
        let generation = try await store.beginScanGeneration()
        let root = try await store.addRoot(URL(fileURLWithPath: "/Music/K"))
        let ids = try await store.upsert([
            makeScanned(path: "/Music/K/1.flac", name: "1.flac", inode: 21),
            makeScanned(path: "/Music/K/2.flac", name: "2.flac", inode: 22),
        ], folderID: root, generation: generation)
        // Track 1: term in the album only. Track 2: term in title+album (ranks higher).
        // Both share ONE track-artist and ONE album → the result facets must dedup each.
        try await store.applyMetadata(
            TrackMetadata(title: "Other Song", artistName: "Zephyr Band",
                          albumTitle: "Zephyr Sessions", albumArtistName: "Zephyr Band"),
            forTrack: ids[0]
        )
        try await store.applyMetadata(
            TrackMetadata(title: "Zephyr", artistName: "Zephyr Band",
                          albumTitle: "Zephyr Sessions", albumArtistName: "Zephyr Band"),
            forTrack: ids[1]
        )
        let hits = try await store.search("zephyr")
        // Q6: the stronger hit (title+album) ranks above the album-only hit.
        guard hits.tracks.first?.title == "Zephyr" else {
            printFail(number, "Q6: bm25 did not rank the multi-column hit above the album-only hit"); return false
        }
        // Q7: shared album AND shared artist each appear exactly once in the result facets.
        guard hits.albums.filter({ $0.title == "Zephyr Sessions" }).count == 1 else {
            printFail(number, "Q7: shared album appears more than once in the result facets"); return false
        }
        guard hits.artists.filter({ $0.name == "Zephyr Band" }).count == 1 else {
            printFail(number, "Q7: shared artist appears more than once (or zero times) in the result facets")
            return false
        }
        printPass(number, "Q6/7: the multi-column hit outranks the album-only hit (bm25); the shared "
            + "album AND artist each appear exactly once in the deduped result facets")
        return true
    } catch {
        printFail(number, "Q6/7 threw: \(error)"); return false
    }
}

// MARK: - char-test — a no-op re-scan performs ZERO FTS writes (idempotency)

func checkFtsNoOpRescanZeroWrites(number: Int, url: URL) async -> Bool {
    do {
        let store = try await LibraryStore(url: url, appBuild: "verify")
        let gen1 = try await store.beginScanGeneration()
        let root = try await store.addRoot(URL(fileURLWithPath: "/Music/N"))
        let file = makeScanned(path: "/Music/N/steady.flac", name: "steady.flac", inode: 5)
        let ids = try await store.upsert([file], folderID: root, generation: gen1)
        try await store.applyMetadata(TrackMetadata(title: "Steady State"), forTrack: ids[0])
        let rowid = try await store.search("steady").tracks.first?.id
        // Re-scan the IDENTICAL file at a new generation: an unchanged upsert must NOT
        // touch FTS (no .new insert, no metadata reset). Assert ZERO writes via the
        // counter — end-state alone can't prove it (a delete+reinsert is byte-identical),
        // so this is what actually gates the `.new`-only seed guard.
        let writesBefore = await store.searchIndexWriteCount()
        let gen2 = try await store.beginScanGeneration()
        _ = try await store.upsert([file], folderID: root, generation: gen2)
        let writesAfter = await store.searchIndexWriteCount()
        let hits = try await store.search("steady").tracks
        guard writesAfter == writesBefore else {
            printFail(number, "char-test: a no-op re-scan performed \(writesAfter - writesBefore) FTS "
                + "write(s) — the .new-only seed guard regressed"); return false
        }
        guard hits.count == 1, hits.first?.id == rowid, hits.first?.title == "Steady State" else {
            printFail(number, "char-test: a no-op re-scan disturbed the FTS row"); return false
        }
        printPass(number, "char-test: a no-op re-scan of an unchanged file performs ZERO FTS writes "
            + "(searchIndexWriteCount unchanged — the .new-only seed guard holds)")
        return true
    } catch {
        printFail(number, "char-test threw: \(error)"); return false
    }
}

// MARK: - BR-SCAN — a search racing concurrent writes returns committed rows, no crash

func checkFtsReadDuringWrite(number: Int, url: URL) async -> Bool {
    do {
        let store = try await LibraryStore(url: url, appBuild: "verify")
        let generation = try await store.beginScanGeneration()
        let root = try await store.addRoot(URL(fileURLWithPath: "/Music/B"))
        var collected: [Int64] = []
        for index in 0 ..< 20 {
            let scanned = makeScanned(path: "/Music/B/track\(index).flac",
                                      name: "track\(index).flac", inode: Int64(100 + index))
            collected += try await store.upsert([scanned], folderID: root, generation: generation)
        }
        let ids = collected // immutable snapshot — safe to share into the concurrent writer
        // Concurrently: a writer re-tagging tracks while a reader searches, both on the SAME
        // store (one GRDB DatabasePool — a serialized writer + concurrent reader connections).
        // Reads must see committed rows, never a torn row or a deadlock, and integrity must hold.
        async let writes: Void = {
            for id in ids {
                try await store.applyMetadata(TrackMetadata(title: "Concurrent \(id)"), forTrack: id)
            }
        }()
        var searchesOK = true
        for _ in 0 ..< 40 where searchesOK {
            searchesOK = (try? await store.search("concurrent")) != nil
        }
        try await writes
        let finalHits = try await store.search("concurrent").tracks.count
        guard searchesOK, finalHits == ids.count, try await store.integrityCheck() else {
            printFail(number, "BR-SCAN: a search racing writes threw, missed committed rows "
                + "(\(finalHits)/\(ids.count)), or integrity failed"); return false
        }
        printPass(number, "BR-SCAN: searches racing concurrent metadata writes return committed rows "
            + "(final \(finalHits)/\(ids.count)), never a torn read or deadlock; integrity ok")
        return true
    } catch {
        printFail(number, "BR-SCAN threw: \(error)"); return false
    }
}
