// ChecksPlaylistScan — S10.3 Chunk G: playlist ⇄ scanner/scale invariants. US-PLIST-08 (membership
// survives a real-scanner move), reorder isolation, the EXPLAIN scale tripwire, and a playlist write
// concurrent with a real scan. Registered via playlistScanCheckCases() in main.swift.

import Foundation
import LibraryScan
import LibraryStore

// MARK: - Registration

func playlistScanCheckCases() -> [CheckCase] {
    [
        CheckCase(label: "pl-move-membership-survives", run: checkPlaylistMoveMembershipSurvives),
        CheckCase(label: "pl-reorder-isolation", run: checkPlaylistReorderIsolation),
        CheckCase(label: "pl-explain-plan", run: checkPlaylistExplainPlan),
        CheckCase(label: "pl-write-during-scan", run: checkPlaylistWriteDuringScan),
    ]
}

// MARK: - US-PLIST-08

/// pl-move-membership-survives: a track's file moves on disk; the REAL scanner move-matches it
/// (preserving `tracks.id`), so a playlist entry referencing it by id is still intact after reconcile.
func checkPlaylistMoveMembershipSurvives(number: Int, url: URL) async -> Bool {
    do {
        let store = try await LibraryStore(url: url, appBuild: "verify")
        let root = try ScanFixtureBuilder.makeCaseRoot("pl-move-survive")
        let oldURL = try ScanFixtureBuilder.writeFile(at: root, subdirs: ["A"], fileName: "keeper.flac", byteCount: 32)
        let folderID = try await store.addRoot(root)
        _ = try await LibraryScanner().scan(root: root, folderID: folderID, into: store)
        guard let id = try await store.track(url: oldURL)?.id else {
            printFail(number, "pl-move-survive: row missing after first scan"); return false
        }
        let playlistID = try await store.createPlaylist(name: "Keepers")
        _ = try await store.appendEntry(playlistID: playlistID, trackID: id)

        // Move the file, then reconcile through the real scanner (move-match keeps the id).
        let destDir = try ScanFixtureBuilder.makeDirectory(at: root, ["B", "C"])
        let newURL = destDir.appendingPathComponent("keeper.flac", isDirectory: false)
        try FileManager.default.moveItem(at: oldURL, to: newURL)
        _ = try await LibraryScanner().scan(root: root, folderID: folderID, into: store)

        guard let moved = try await store.track(url: newURL), moved.id == id else {
            printFail(number, "pl-move-survive: track id NOT preserved across the move"); return false
        }
        let entries = try await store.entries(inPlaylist: playlistID)
        guard entries.count == 1, entries[0].trackID == id else {
            printFail(number, "pl-move-survive: membership LOST across the move (entries=\(entries.map(\.trackID)))")
            return false
        }
        printPass(number, "US-PLIST-08: a playlist entry SURVIVES a Finder move of its file — move-match "
            + "keeps tracks.id, so membership (by id) is intact after reconcile")
        return true
    } catch { printFail(number, "pl-move-membership-survives threw: \(error)"); return false }
}

// MARK: - Reorder isolation

/// pl-reorder-isolation: reordering one playlist leaves every OTHER playlist's order untouched
/// (positions are per-playlist; the renumber is scoped by `playlist_id`).
func checkPlaylistReorderIsolation(number: Int, url: URL) async -> Bool {
    do {
        let seeded = try await seedTracks(url, root: "/M/RI",
                                          paths: ["/M/RI/a.flac", "/M/RI/b.flac", "/M/RI/c.flac"])
        let store = seeded.store
        let t = seeded.trackIDs
        let p1 = try await store.createPlaylist(name: "One")
        let p2 = try await store.createPlaylist(name: "Two")
        _ = try await store.appendEntries(playlistID: p1, trackIDs: t)
        _ = try await store.appendEntries(playlistID: p2, trackIDs: t)
        let p2Before = try await store.entries(inPlaylist: p2).map(\.trackID)

        // Reverse P1's order — must not touch P2.
        let p1Entries = try await store.entries(inPlaylist: p1)
        try await store.reorderPlaylist(id: p1, entryIDsInOrder: p1Entries.map(\.id).reversed())
        let p1After = try await store.entries(inPlaylist: p1).map(\.trackID)
        let p2After = try await store.entries(inPlaylist: p2).map(\.trackID)
        guard p1After == Array(t.reversed()), p2After == p2Before else {
            printFail(number, "pl-reorder-isolation: reordering P1 leaked into P2 (p1=\(p1After) p2=\(p2After))")
            return false
        }
        printPass(number, "pl-reorder-isolation: reordering one playlist leaves every other playlist's "
            + "order untouched (per-playlist renumber)")
        return true
    } catch { printFail(number, "pl-reorder-isolation threw: \(error)"); return false }
}

// MARK: - EXPLAIN scale tripwire

/// pl-explain-plan: the playlist list + entries reads must be INDEX-driven — `playlist_entries` is
/// reached via `idx_playlist_entries_playlist`, never a full table scan (scale: long playlists).
func checkPlaylistExplainPlan(number: Int, url: URL) async -> Bool {
    do {
        let seeded = try await seedTracks(url, root: "/M/EP", paths: ["/M/EP/a.flac", "/M/EP/b.flac"])
        let store = seeded.store
        let playlistID = try await store.createPlaylist(name: "P")
        _ = try await store.appendEntries(playlistID: playlistID, trackIDs: seeded.trackIDs)
        let plan = try await store.explainPlaylistReadsPlan()

        let fullScan = plan.contains { $0.contains("SCAN playlist_entries") && !$0.contains("USING") }
        guard !fullScan else {
            printFail(number, "pl-explain-plan: playlist_entries is FULL-SCANNED: \(plan)"); return false
        }
        guard plan.contains(where: { $0.contains("idx_playlist_entries_playlist") }) else {
            printFail(number, "pl-explain-plan: idx_playlist_entries_playlist not used: \(plan)"); return false
        }
        printPass(number, "pl-explain-plan: the playlist list + entries reads use "
            + "idx_playlist_entries_playlist — never a full SCAN of playlist_entries")
        return true
    } catch { printFail(number, "pl-explain-plan threw: \(error)"); return false }
}

// MARK: - Write during scan

/// pl-write-during-scan: a playlist write concurrent with a REAL scan completes without deadlock or
/// corruption — the single serialized `DatabaseWriter` serializes them, and the entry lands.
func checkPlaylistWriteDuringScan(number: Int, url: URL) async -> Bool {
    do {
        let store = try await LibraryStore(url: url, appBuild: "verify")
        let root = try ScanFixtureBuilder.makeCaseRoot("pl-write-scan")
        for index in 0 ..< 40 {
            _ = try ScanFixtureBuilder.writeFile(at: root, fileName: "s\(index).flac", byteCount: 16)
        }
        let folderID = try await store.addRoot(root)
        _ = try await LibraryScanner().scan(root: root, folderID: folderID, into: store)
        guard let someID = try await store.allTracksDisplay(sortedBy: .artistAlbumTrack, limit: 1).first?.id else {
            printFail(number, "pl-write-scan: no track after the seed scan"); return false
        }
        let playlistID = try await store.createPlaylist(name: "Concurrent")

        // Add more files so the second scan has work, then run it CONCURRENTLY with a playlist write.
        for index in 40 ..< 110 {
            _ = try ScanFixtureBuilder.writeFile(at: root, fileName: "s\(index).flac", byteCount: 16)
        }
        async let scan = LibraryScanner().scan(root: root, folderID: folderID, into: store)
        async let write = store.appendEntry(playlistID: playlistID, trackID: someID)
        _ = try await (scan, write)

        let entries = try await store.entries(inPlaylist: playlistID)
        guard entries.contains(where: { $0.trackID == someID }) else {
            printFail(number, "pl-write-scan: the concurrent playlist write was lost"); return false
        }
        printPass(number, "pl-write-during-scan: a playlist write concurrent with a real scan completes "
            + "without deadlock/corruption — the serialized writer keeps both safe")
        return true
    } catch { printFail(number, "pl-write-during-scan threw: \(error)"); return false }
}
