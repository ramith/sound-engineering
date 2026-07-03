// ChecksMoveMatch — S8.4 Slice 1 move-matching cases (id-preserving reconcile),
// driven through the REAL LibraryScanner + REAL SQLite store, plus a few that call the
// candidate-selection DAO directly (synthetic rows) where a real filesystem can't stage
// the scenario (two volumes, a signature collision). Same VerifyAUGraph idiom; companion
// to ChecksScanReconcile / ChecksScanEdge (whose reconcileRename / crossDirMove cases
// were upgraded to the id-preserving assertions in this same slice).
//
// The through-line: a moved/renamed file must keep its stable `tracks.id` (via moveTrack/
// moveMatched), NOT be reconciled as delete-old + insert-new (a new id) — the hard gate
// SEQ-1/Gate-2 blocking S9/S10. Every ambiguity resolves to the SAFE side (a new id is
// recoverable; a WRONG id is silent corruption), so the negative cases assert "no match".

import Foundation
import LibraryScan
import LibraryStore

// MARK: - M3 — a move preserves durable, id-keyed user state (the Gate-2 proof)

func checkMoveReferenceSurvives(number: Int, url: URL) async -> Bool {
    do {
        let store = try await LibraryStore(url: url, appBuild: "verify")
        let root = try ScanFixtureBuilder.makeCaseRoot("move-refsurvive")
        let oldURL = try ScanFixtureBuilder.writeFile(at: root, subdirs: ["A"], fileName: "keeper.flac", byteCount: 32)
        let folderID = try await store.addRoot(root)
        _ = try await LibraryScanner().scan(root: root, folderID: folderID, into: store)
        guard let id = try await store.track(url: oldURL)?.id else {
            printFail(number, "move-refsurvive: row missing after first scan"); return false
        }
        // Attach durable, id-keyed user state — the proxy for future playlist membership /
        // play-count / rating / loved that S9/S10 will key on tracks.id.
        try await store.setUserState(trackID: id, playCount: 42, loved: true, rating: 5)

        // Move the file to a different subdir, then reconcile through the real scanner.
        let destDir = try ScanFixtureBuilder.makeDirectory(at: root, ["B", "C"])
        let newURL = destDir.appendingPathComponent("keeper.flac", isDirectory: false)
        try FileManager.default.moveItem(at: oldURL, to: newURL)
        _ = try await LibraryScanner().scan(root: root, folderID: folderID, into: store)

        guard let moved = try await store.track(url: newURL), moved.id == id else {
            printFail(number, "move-refsurvive: id NOT preserved across the move (Gate-2 FAIL — delete+add)")
            return false
        }
        guard let state = try await store.userState(trackID: id),
              state.playCount == 42, state.loved, state.rating == 5 else {
            printFail(number, "move-refsurvive: user-state (play_count/loved/rating) did NOT survive the move "
                + "— Gate-2 NOT closed"); return false
        }
        printPass(number, "move reference-survives (Gate-2): play_count/loved/rating set on a track SURVIVE "
            + "a Finder move on the SAME id — durable identity preserved (the whole point of S8.4)")
        return true
    } catch {
        printFail(number, "move-refsurvive threw: \(error)"); return false
    }
}

// MARK: - M4/M5 — candidate selection (synthetic rows via the DAO)

func checkMoveCandidateSelection(number: Int, url: URL) async -> Bool {
    do {
        let store = try await LibraryStore(url: url, appBuild: "verify")
        // Seed a loose row at generation 1 with a known move-signature.
        let base = syntheticFile(path: "/synthetic/move/a.flac", size: 100, mtime: 5000, inode: 777, dev: 10)
        guard let baseID = try await store.upsert([base], folderID: nil, generation: 1).first else {
            printFail(number, "move-candidate: seed upsert returned no id"); return false
        }
        // Positive control — same signature, NEW url, later gen → matches.
        let sameVol = syntheticFile(path: "/synthetic/move/a-moved.flac", size: 100, mtime: 5000, inode: 777, dev: 10)
        guard try await store.moveCandidate(for: sameVol, generation: 2) == baseID else {
            printFail(number, "move-candidate: a same-signature new path did NOT match"); return false
        }
        // M4 cross-volume — same inode, DIFFERENT dev → NO match (recycled inode on another volume).
        let crossVol = syntheticFile(path: "/synthetic/move/b.flac", size: 100, mtime: 5000, inode: 777, dev: 99)
        guard try await store.moveCandidate(for: crossVol, generation: 2) == nil else {
            printFail(number, "move-candidate: cross-volume (same inode, different dev) wrongly matched"); return false
        }
        // Format corroboration — same (dev,inode,size,mtime), DIFFERENT format → NO match.
        let diffFormat = ScannedFile(
            url: URL(fileURLWithPath: "/synthetic/move/a.mp3"), relativePath: "", name: "a",
            format: "MP3", fileSize: 100, mtime: 5000, inode: 777, dev: 10
        )
        guard try await store.moveCandidate(for: diffFormat, generation: 2) == nil else {
            printFail(number, "move-candidate: a different-format inode reuse wrongly matched"); return false
        }
        // M5 ambiguity — a SECOND identical-signature row makes the match ambiguous → nil.
        let twin = syntheticFile(path: "/synthetic/move/a-twin.flac", size: 100, mtime: 5000, inode: 777, dev: 10)
        _ = try await store.upsert([twin], folderID: nil, generation: 1)
        guard try await store.moveCandidate(for: sameVol, generation: 2) == nil else {
            printFail(number, "move-candidate: an ambiguous (>1 candidate) signature did not resolve to nil")
            return false
        }
        printPass(number, "move-candidate selection: matches a same-signature new path; REFUSES cross-volume "
            + "(same inode/different dev), different-format inode reuse, and >1-candidate ambiguity — every "
            + "uncertainty resolves to no-match (safe)")
        return true
    } catch {
        printFail(number, "move-candidate selection threw: \(error)"); return false
    }
}

// MARK: - M10/M11 — a move must NOT be false-triggered (modify / copy)

func checkMoveNotFalseTriggered(number: Int, url: URL) async -> Bool {
    do {
        let store = try await LibraryStore(url: url, appBuild: "verify")
        guard try await modifyInPlaceIsNotMove(store, number: number) else { return false }
        guard try await copyIsNotMove(store, number: number) else { return false }
        printPass(number, "move NOT false-triggered: an in-place content edit stays the SAME url/id (a "
            + "modify, not a move); a COPY (same content, NEW inode) becomes a new row/new id and leaves "
            + "the original untouched — inode is the load-bearing signal")
        return true
    } catch {
        printFail(number, "move-not-false-triggered threw: \(error)"); return false
    }
}

/// An in-place content edit (same path, changed size/mtime) classifies `.modified` — the
/// url-keyed row keeps its id; it must NEVER be probed as a move.
private func modifyInPlaceIsNotMove(_ store: LibraryStore, number: Int) async throws -> Bool {
    let root = try ScanFixtureBuilder.makeCaseRoot("modify-inplace")
    let fileURL = try ScanFixtureBuilder.writeFile(at: root, fileName: "song.flac", byteCount: 16)
    let folderID = try await store.addRoot(root)
    _ = try await LibraryScanner().scan(root: root, folderID: folderID, into: store)
    guard let id = try await store.track(url: fileURL)?.id else {
        printFail(number, "modify-inplace: row missing after first scan"); return false
    }
    try ScanFixtureBuilder.overwriteFile(at: fileURL, byteCount: 48) // size change → .modified
    let result = try await LibraryScanner().scan(root: root, folderID: folderID, into: store)
    guard result.orphansSwept == 0, let same = try await store.track(url: fileURL),
          same.id == id, same.fileSize == 48 else {
        printFail(number, "modify-inplace: an in-place edit was not a same-url same-id modify"); return false
    }
    return true
}

/// A copy (original stays; the copy is a distinct inode) must become a NEW row — the copy's
/// inode matches no stored row, so `moveCandidate` returns nil and the original is untouched.
private func copyIsNotMove(_ store: LibraryStore, number: Int) async throws -> Bool {
    let root = try ScanFixtureBuilder.makeCaseRoot("copy-notmove")
    let original = try ScanFixtureBuilder.writeFile(at: root, fileName: "orig.flac", byteCount: 24)
    let folderID = try await store.addRoot(root)
    _ = try await LibraryScanner().scan(root: root, folderID: folderID, into: store)
    guard let origID = try await store.track(url: original)?.id else {
        printFail(number, "copy-notmove: original row missing after first scan"); return false
    }
    let copyURL = root.appendingPathComponent("copy.flac", isDirectory: false)
    _ = try ScanFixtureBuilder.copyFile(from: original, to: copyURL)
    let result = try await LibraryScanner().scan(root: root, folderID: folderID, into: store)
    guard result.orphansSwept == 0, try await store.track(url: original)?.id == origID else {
        printFail(number, "copy-notmove: the original row was disturbed by the copy"); return false
    }
    guard let copyRow = try await store.track(url: copyURL), copyRow.id != origID else {
        printFail(number, "copy-notmove: the copy did not become a distinct new row/id"); return false
    }
    return true
}

// MARK: - M7 — target-url collision → typed URLConflict, no silent merge

func checkMoveUrlCollision(number: Int, url: URL) async -> Bool {
    do {
        let store = try await LibraryStore(url: url, appBuild: "verify")
        let fileA = syntheticFile(path: "/synthetic/coll/a.flac", size: 10, mtime: 1000, inode: 1, dev: 1)
        let fileB = syntheticFile(path: "/synthetic/coll/b.flac", size: 20, mtime: 2000, inode: 2, dev: 1)
        guard let idA = try await store.upsert([fileA], folderID: nil, generation: 1).first,
              let idB = try await store.upsert([fileB], folderID: nil, generation: 1).first else {
            printFail(number, "url-collision: seed upsert returned no ids"); return false
        }
        // Attempt to move A onto B's url — must throw URLConflict(existingID: idB), not merge.
        let ontoB = syntheticFile(path: "/synthetic/coll/b.flac", size: 10, mtime: 1000, inode: 1, dev: 1)
        var conflictID: Int64?
        do {
            try await store.moveMatched(id: idA, to: ontoB, newFolderID: nil, generation: 2)
        } catch let conflict as URLConflict {
            conflictID = conflict.existingID
        }
        guard conflictID == idB else {
            printFail(number, "url-collision: moving onto an occupied url did not throw "
                + "URLConflict(existingID: idB)"); return false
        }
        guard try await store.track(id: idA) != nil, try await store.track(id: idB) != nil,
              try await store.trackCount() == 2 else {
            printFail(number, "url-collision: a row was lost/merged after the rejected move"); return false
        }
        printPass(number, "move url-collision: moving a track onto a url another row already holds throws a "
            + "typed URLConflict carrying the occupant id — no silent merge, both ids survive")
        return true
    } catch {
        printFail(number, "url-collision threw: \(error)"); return false
    }
}

// MARK: - M13/M14 — reorg (double move) + cross-root move

func checkMoveReorgAndCrossRoot(number: Int, url: URL) async -> Bool {
    do {
        let store = try await LibraryStore(url: url, appBuild: "verify")
        guard try await doubleMoveReorg(store, number: number) else { return false }
        guard try await crossRootMove(store, number: number) else { return false }
        printPass(number, "move reorg + cross-root: moving TWO distinct files to new paths preserves BOTH ids "
            + "(each inode uniquely matches its own vacated orphan, order-independent); a file dragged from "
            + "root A into root B is matched into B with its id preserved and no duplicate left in A")
        return true
    } catch {
        printFail(number, "move-reorg/cross-root threw: \(error)"); return false
    }
}

/// Two distinct files (distinct inodes) each moved to a new path in one reorg → BOTH ids
/// preserved. Each inode uniquely matches its own vacated orphan, so the outcome is
/// order-independent (the realistic Finder-reorg case; UX stress journey #2).
private func doubleMoveReorg(_ store: LibraryStore, number: Int) async throws -> Bool {
    let root = try ScanFixtureBuilder.makeCaseRoot("reorg")
    let fileA = try ScanFixtureBuilder.writeFile(at: root, subdirs: ["In"], fileName: "a.flac", byteCount: 20)
    let fileB = try ScanFixtureBuilder.writeFile(at: root, subdirs: ["In"], fileName: "b.flac", byteCount: 44)
    let folderID = try await store.addRoot(root)
    _ = try await LibraryScanner().scan(root: root, folderID: folderID, into: store)
    guard let idA = try await store.track(url: fileA)?.id, let idB = try await store.track(url: fileB)?.id else {
        printFail(number, "reorg: rows missing after first scan"); return false
    }
    let dest = try ScanFixtureBuilder.makeDirectory(at: root, ["Out"])
    let newA = dest.appendingPathComponent("a.flac", isDirectory: false)
    let newB = dest.appendingPathComponent("b.flac", isDirectory: false)
    try FileManager.default.moveItem(at: fileA, to: newA)
    try FileManager.default.moveItem(at: fileB, to: newB)
    let result = try await LibraryScanner().scan(root: root, folderID: folderID, into: store)
    guard result.orphansSwept == 0,
          try await store.track(url: newA)?.id == idA, try await store.track(url: newB)?.id == idB,
          try await store.tracks(inFolder: folderID).count == 2 else {
        printFail(number, "reorg: a double move did not preserve both ids (orphansSwept \(result.orphansSwept))")
        return false
    }
    return true
}

/// A file dragged from root A into root B (same volume → inode preserved): re-scanning B
/// matches it (dev+inode) and preserves its id, moving it into B (folder_id=B); A retains
/// no duplicate. Works because `beginScanGeneration` is global-monotonic (B's generation
/// exceeds A's, so A's row is an eligible unswept candidate).
private func crossRootMove(_ store: LibraryStore, number: Int) async throws -> Bool {
    let rootA = try ScanFixtureBuilder.makeCaseRoot("crossroot-A")
    let rootB = try ScanFixtureBuilder.makeCaseRoot("crossroot-B")
    let fileA = try ScanFixtureBuilder.writeFile(at: rootA, fileName: "song.flac", byteCount: 28)
    let folderA = try await store.addRoot(rootA)
    let folderB = try await store.addRoot(rootB)
    _ = try await LibraryScanner().scan(root: rootA, folderID: folderA, into: store)
    _ = try await LibraryScanner().scan(root: rootB, folderID: folderB, into: store)
    guard let id = try await store.track(url: fileA)?.id else {
        printFail(number, "cross-root: row missing after A scan"); return false
    }
    let newURL = rootB.appendingPathComponent("song.flac", isDirectory: false)
    try FileManager.default.moveItem(at: fileA, to: newURL)
    _ = try await LibraryScanner().scan(root: rootB, folderID: folderB, into: store)
    guard let moved = try await store.track(url: newURL), moved.id == id, moved.folderID == folderB else {
        printFail(number, "cross-root: file not matched into B with id preserved + folder_id=B"); return false
    }
    // Folder-scoped (the store is shared with doubleMoveReorg): A must be empty (its one
    // row moved out to B), B holds exactly the moved row, and the old A path has no row.
    guard try await store.track(url: fileA) == nil,
          try await store.tracks(inFolder: folderA).isEmpty,
          try await store.tracks(inFolder: folderB).count == 1 else {
        printFail(number, "cross-root: A retains a row/duplicate or B doesn't hold exactly the moved row")
        return false
    }
    return true
}

// MARK: - Synthetic-row helper (for DAO-direct cases)

/// Build a FLAC `ScannedFile` with an explicit move-signature at a synthetic path (never
/// touched on disk — the store asserts no FS existence). Used by the candidate-selection
/// and url-collision cases, which stage scenarios a real filesystem can't (two volumes,
/// an exact signature collision). The one different-format case constructs `ScannedFile`
/// inline, so this stays FLAC-only and within the parameter-count limit.
private func syntheticFile(path: String, size: Int64, mtime: Int64, inode: Int64?, dev: Int64?) -> ScannedFile {
    ScannedFile(
        url: URL(fileURLWithPath: path), relativePath: "",
        name: URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent,
        format: "FLAC", fileSize: size, mtime: mtime, inode: inode, dev: dev
    )
}
