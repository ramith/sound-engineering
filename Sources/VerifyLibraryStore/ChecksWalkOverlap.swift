// ChecksWalkOverlap — S10.8 G (G-LIB-01): two walks of ONE folder overlapping never delete a song
// that is on disk. The later walk takes the higher generation; where it passes a song first, the
// earlier walk's late write must not pull the song's `last_seen_scan` back below it, or the later
// walk's end-of-walk sweep deletes the song (and, ON DELETE CASCADE, its playlist entries). Driven
// through the DAO the scanner calls (`upsertReconciling` + `sweepOrphans`) on synthetic rows, so
// the interleaving is exact. The app also never overlaps two walks of a folder (LibraryModel's
// FolderWalkSchedule); this pins the store's own guarantee.

import Foundation
import LibraryStore

/// S10.8 G — overlapping walks of one folder. Own function so `allCheckCases` stays short.
func walkOverlapCheckCases() -> [CheckCase] {
    [
        CheckCase(label: "wo1-stamp-never-lowered", run: checkOverlappingWalksNeverLowerAStamp),
    ]
}

/// A synthetic file under `/synthetic/overlap/` (the store never opens it).
private func overlapFile(_ name: String, size: Int64 = 100) -> ScannedFile {
    ScannedFile(
        url: URL(fileURLWithPath: "/synthetic/overlap/\(name).flac"), relativePath: "", name: name,
        format: "FLAC", fileSize: size, mtime: 1000, inode: nil, dev: nil
    )
}

/// wo1: walk A starts, walk B starts after it (higher generation) and passes every song first; A
/// then writes the same songs late — unchanged ("Kept") and with changed content ("Edited", whose
/// conflict UPDATE fires). B's sweep reaps ONLY the song neither walk saw ("Gone"); A's sweep after
/// it reaps nothing; the playlist entry of "Kept" survives.
func checkOverlappingWalksNeverLowerAStamp(number: Int, url: URL) async -> Bool {
    do {
        let store = try await LibraryStore(url: url, appBuild: "verify")
        let root = try await store.addRoot(URL(fileURLWithPath: "/synthetic/overlap"))
        let first = try await store.beginScanGeneration()
        let ids = try await store.upsertReconciling(
            [overlapFile("Kept"), overlapFile("Edited"), overlapFile("Gone")], folderID: root, generation: first
        )
        let playlist = try await store.createPlaylist(name: "Overlap")
        try await store.appendEntries(playlistID: playlist, trackIDs: [ids[0]])

        let walkA = try await store.beginScanGeneration()
        try await store.upsertReconciling([overlapFile("Edited")], folderID: root, generation: walkA)
        let walkB = try await store.beginScanGeneration()
        try await store.upsertReconciling([overlapFile("Kept"), overlapFile("Edited", size: 200)],
                                          folderID: root, generation: walkB)
        // Walk A's late writes: an unchanged song, and one whose content differs again.
        try await store.upsertReconciling([overlapFile("Kept"), overlapFile("Edited", size: 300)],
                                          folderID: root, generation: walkA)

        let sweptByB = try await store.sweepOrphans(inFolders: [root], olderThan: walkB)
        let sweptByA = try await store.sweepOrphans(inFolders: [root], olderThan: walkA)
        let remaining = try await store.allTracks(sortedBy: .name).map(\.name)
        let entries = try await store.entries(inPlaylist: playlist)
        guard walkB > walkA, sweptByB == 1, sweptByA == 0, remaining == ["Edited", "Kept"],
              entries.map(\.trackID) == [ids[0]] else {
            printFail(number, "overlapping walks: B swept \(sweptByB) (want 1), A swept \(sweptByA) (want 0), "
                + "remaining \(remaining), playlist entries \(entries.count) — a late stamp lowered a song")
            return false
        }
        printPass(number, "overlapping walks of one folder: an earlier walk's late write (unchanged or edited) "
            + "never lowers a later walk's stamp — the sweeps reap only the song neither saw; its playlist "
            + "entry survives (G-LIB-01)")
        return true
    } catch {
        printFail(number, "wo1-stamp-never-lowered threw: \(error)"); return false
    }
}
