// ChecksScanReconcile — S8.2b reconcile cases (end-of-walk orphan sweep, move-signature
// population, root rejection, and reads-during-scan), driven through the REAL
// LibraryScanner against a REAL temp-dir tree (design §8, §9). Companion to
// ChecksScan.swift / ChecksScanRescan.swift (S8.2a); same VerifyAUGraph idiom.
//
// Covers, all through `LibraryScanner().scan` + `validateNewRoot`:
//   • multi-root sweep isolation (M-A) — each scan's END-OF-WALK sweep is single-root
//     scoped: scanning root B never sweeps root A's rows, and re-scanning A never
//     touches B's; ids stay stable across the other root's scan.
//   • FS-5 delete — a file removed on disk is swept on re-scan (D-sweep); the survivor's
//     row (and id) is untouched. FS-5 rename — a SAME-DIR rename preserves
//     (dev,inode,size,mtime); S8.2 does NOT match the move (that is S8.4), so the old
//     path is swept and a NEW row appears at the new path — but its move-signature must
//     EQUAL the old row's, proving S8.2 populated it for S8.4 to match.
//   • reject nested roots (O-2) — `validateNewRoot` throws NestedRootConflict for an
//     ancestor/descendant of an existing root (carrying the right kind), while an
//     exact-duplicate path and a component-boundary sibling (Rock vs RockAndRoll) are
//     allowed.
//   • reads-during-scan (M-D / SF-4 baseline) — reads issued WHILE a ~500-file scan runs
//     each return under a wall-clock bound (never block unboundedly behind the batched
//     writes); the scan still completes and sees every file.

import Foundation
import LibraryScan
import LibraryStore

// MARK: - Multi-root sweep isolation (M-A)

func checkMultiRootSweepIsolation(number: Int, url: URL) async -> Bool {
    do {
        let store = try await LibraryStore(url: url, appBuild: "verify")
        guard try await multiRootIsolation(store, number: number) else { return false }
        printPass(number, "multi-root sweep isolation (M-A): each scan's end-of-walk sweep is "
            + "single-root scoped — scanning B leaves A's rows (ids stable), re-scanning A "
            + "leaves B's rows; total row count spans both roots")
        return true
    } catch {
        printFail(number, "multi-root sweep isolation threw: \(error)"); return false
    }
}

/// Two roots A and B: scan A, then scan B (whose end-of-walk sweep must NOT touch A),
/// then re-scan A (whose sweep must NOT touch B). Row ids stay stable throughout (M-A).
private func multiRootIsolation(_ store: LibraryStore, number: Int) async throws -> Bool {
    let rootA = try ScanFixtureBuilder.makeCaseRoot("multiroot-A")
    let fileA1 = try ScanFixtureBuilder.writeFile(at: rootA, fileName: "a1.flac")
    let fileA2 = try ScanFixtureBuilder.writeFile(at: rootA, subdirs: ["Sub"], fileName: "a2.mp3")
    let rootB = try ScanFixtureBuilder.makeCaseRoot("multiroot-B")
    _ = try ScanFixtureBuilder.writeFile(at: rootB, fileName: "b1.flac")
    _ = try ScanFixtureBuilder.writeFile(at: rootB, fileName: "b2.wav")

    let folderA = try await store.addRoot(rootA)
    _ = try await LibraryScanner().scan(root: rootA, folderID: folderA, into: store)
    guard let idA1 = try await store.track(url: fileA1)?.id,
          let idA2 = try await store.track(url: fileA2)?.id else {
        printFail(number, "multi-root: root A rows missing after its own scan"); return false
    }

    // Scanning root B runs B's end-of-walk sweep — it must NOT touch root A's rows.
    let folderB = try await store.addRoot(rootB)
    _ = try await LibraryScanner().scan(root: rootB, folderID: folderB, into: store)
    let countBoth = try await store.trackCount()
    guard try await store.track(url: fileA1)?.id == idA1,
          try await store.track(url: fileA2)?.id == idA2, countBoth == 4 else {
        printFail(number, "multi-root: scanning B altered A's rows or the count (\(countBoth) != 4)"); return false
    }

    // Symmetry: re-scanning A (its sweep) must leave B's rows intact.
    let bRowsBefore = try await store.tracks(inFolder: folderB).count
    _ = try await LibraryScanner().scan(root: rootA, folderID: folderA, into: store)
    guard try await store.tracks(inFolder: folderB).count == bRowsBefore else {
        printFail(number, "multi-root: re-scanning root A swept root B's rows"); return false
    }
    return true
}

// MARK: - FS-5 delete + rename (sweep + move-signature)

func checkReconcileDeleteRename(number: Int, url: URL) async -> Bool {
    do {
        let store = try await LibraryStore(url: url, appBuild: "verify")
        guard try await reconcileDelete(store, number: number) else { return false }
        guard try await reconcileRename(store, number: number) else { return false }
        printPass(number, "reconcile (real tree): a deleted file is swept on re-scan (survivor's id "
            + "stable); a renamed file's old row is swept and the new row carries the SAME "
            + "(dev,inode,size,mtime) move-signature (populated now, matched in S8.4)")
        return true
    } catch {
        printFail(number, "reconcile delete/rename threw: \(error)"); return false
    }
}

/// Delete one file on disk between scans: the vanished file's row is swept (D-sweep,
/// `orphansSwept == 1`), the survivor's row and id are untouched.
private func reconcileDelete(_ store: LibraryStore, number: Int) async throws -> Bool {
    let root = try ScanFixtureBuilder.makeCaseRoot("reconcile-delete")
    let keep = try ScanFixtureBuilder.writeFile(at: root, fileName: "keep.flac")
    let doomed = try ScanFixtureBuilder.writeFile(at: root, subdirs: ["Sub"], fileName: "delete-me.flac")
    let folderID = try await store.addRoot(root)
    _ = try await LibraryScanner().scan(root: root, folderID: folderID, into: store)
    guard let keepID = try await store.track(url: keep)?.id else {
        printFail(number, "reconcile-delete: keep row missing after first scan"); return false
    }

    try FileManager.default.removeItem(at: doomed)
    let result = try await LibraryScanner().scan(root: root, folderID: folderID, into: store)
    guard result.orphansSwept == 1 else {
        printFail(number, "reconcile-delete: expected orphansSwept == 1, got \(result.orphansSwept)"); return false
    }
    guard try await store.track(url: doomed) == nil else {
        printFail(number, "reconcile-delete: the deleted file still has a row after re-scan"); return false
    }
    guard try await store.track(url: keep)?.id == keepID else {
        printFail(number, "reconcile-delete: the survivor's row was swept or its id changed"); return false
    }
    return true
}

/// A same-directory rename preserves (dev,inode,size,mtime). S8.2 does NOT match the move
/// (S8.4 does): the old path is swept and a NEW row appears at the new path — but its
/// move-signature must EQUAL the old row's, so S8.4 can later reunite them.
private func reconcileRename(_ store: LibraryStore, number: Int) async throws -> Bool {
    let root = try ScanFixtureBuilder.makeCaseRoot("reconcile-rename")
    let oldURL = try ScanFixtureBuilder.writeFile(at: root, fileName: "rename-me.flac", byteCount: 24)
    let folderID = try await store.addRoot(root)
    _ = try await LibraryScanner().scan(root: root, folderID: folderID, into: store)
    guard let oldRow = try await store.track(url: oldURL) else {
        printFail(number, "reconcile-rename: row missing after first scan"); return false
    }

    let newURL = root.appendingPathComponent("renamed.flac", isDirectory: false)
    try FileManager.default.moveItem(at: oldURL, to: newURL)
    let result = try await LibraryScanner().scan(root: root, folderID: folderID, into: store)
    guard result.orphansSwept == 1, try await store.track(url: oldURL) == nil else {
        printFail(number, "reconcile-rename: old path not swept (orphansSwept \(result.orphansSwept))"); return false
    }
    guard let newRow = try await store.track(url: newURL) else {
        printFail(number, "reconcile-rename: no row at the renamed path"); return false
    }
    guard newRow.inode == oldRow.inode, newRow.dev == oldRow.dev,
          newRow.fileSize == oldRow.fileSize, newRow.mtime == oldRow.mtime else {
        printFail(number, "reconcile-rename: new row's (dev,inode,size,mtime) != old row's — "
            + "S8.4 could not match this move"); return false
    }
    // Folder-scoped (the store is shared with reconcileDelete): the rename root holds
    // exactly the one renamed row (old swept, new added → net one).
    guard try await store.tracks(inFolder: folderID).count == 1 else {
        printFail(number, "reconcile-rename: expected exactly 1 row in the rename root"); return false
    }
    return true
}

// MARK: - Reject nested / overlapping roots (O-2)

func checkRejectNestedRoots(number: Int, url: URL) async -> Bool {
    do {
        let store = try await LibraryStore(url: url, appBuild: "verify")
        guard try await rejectNestedRoots(store, number: number) else { return false }
        printPass(number, "reject nested roots (O-2): validateNewRoot throws NestedRootConflict for a "
            + "descendant (.descendantOfExisting) and an ancestor (.ancestorOfExisting) of an existing "
            + "root, while an exact-duplicate path and a Rock-vs-RockAndRoll sibling are allowed")
        return true
    } catch {
        printFail(number, "reject nested roots threw: \(error)"); return false
    }
}

/// Register `Library` as a root, then validate candidates against `store.roots()`:
/// a nested descendant and a containing ancestor are rejected with the right kind; an
/// exact duplicate and a component-boundary sibling are allowed.
private func rejectNestedRoots(_ store: LibraryStore, number: Int) async throws -> Bool {
    let base = try ScanFixtureBuilder.makeCaseRoot("reject-nested")
    let parent = try ScanFixtureBuilder.makeDirectory(at: base, ["Library"])
    let child = try ScanFixtureBuilder.makeDirectory(at: parent, ["Inner", "Deep"])
    let rock = try ScanFixtureBuilder.makeDirectory(at: base, ["Rock"])
    let rockAndRoll = try ScanFixtureBuilder.makeDirectory(at: base, ["RockAndRoll"])

    _ = try await store.addRoot(parent)
    let existing = try await store.roots().map { URL(fileURLWithPath: $0.path) }

    guard expectConflict(child, against: existing, kind: .descendantOfExisting,
                         number: number, label: "descendant") else { return false }
    guard expectConflict(base, against: existing, kind: .ancestorOfExisting,
                         number: number, label: "ancestor") else { return false }
    guard expectAllowed(parent, against: existing, number: number, label: "exact-duplicate")
    else { return false }
    guard expectAllowed(rock, against: [rockAndRoll], number: number,
                        label: "Rock-vs-RockAndRoll sibling") else { return false }
    return true
}

/// Assert `validateNewRoot` throws a `NestedRootConflict` of `kind`. (`LibraryScanner()`
/// is a stateless trivial init, so it is constructed inline per call.)
private func expectConflict(
    _ root: URL, against existing: [URL], kind expectedKind: RootConflictKind,
    number: Int, label: String
) -> Bool {
    do {
        try LibraryScanner().validateNewRoot(root, against: existing)
        printFail(number, "reject-nested: \(label) did not throw (expected \(expectedKind))"); return false
    } catch let conflict as NestedRootConflict {
        guard conflict.kind == expectedKind else {
            printFail(number, "reject-nested: \(label) kind \(conflict.kind) != \(expectedKind)"); return false
        }
        return true
    } catch {
        printFail(number, "reject-nested: \(label) threw unexpected \(error)"); return false
    }
}

/// Assert `validateNewRoot` does NOT throw (the candidate is allowed).
private func expectAllowed(_ root: URL, against existing: [URL], number: Int, label: String) -> Bool {
    do {
        try LibraryScanner().validateNewRoot(root, against: existing)
        return true
    } catch {
        printFail(number, "reject-nested: \(label) should be allowed but threw \(error)"); return false
    }
}

// MARK: - Reads during scan (M-D / SF-4 baseline)

func checkReadsDuringScan(number: Int, url: URL) async -> Bool {
    do {
        let store = try await LibraryStore(url: url, appBuild: "verify")
        guard try await readsDuringScan(store, number: number) else { return false }
        printPass(number, "reads-during-scan (M-D / SF-4): reads issued while a ~500-file scan runs each "
            + "return under a 5s bound (never block unboundedly behind the batched writes); the scan "
            + "still completes and sees every file")
        return true
    } catch {
        printFail(number, "reads-during-scan threw: \(error)"); return false
    }
}

/// Issue reads concurrently with a ~500-file scan; each read must return under a bound
/// (SF-4 baseline: reads are not starved by the scan's batched writes on the actor).
private func readsDuringScan(_ store: LibraryStore, number: Int) async throws -> Bool {
    let root = try ScanFixtureBuilder.makeCaseRoot("reads-during-scan")
    let fileCount = 500
    for index in 0 ..< fileCount {
        _ = try ScanFixtureBuilder.writeFile(
            at: root, subdirs: ["d\(index / 50)"], fileName: "t\(index).flac"
        )
    }
    let folderID = try await store.addRoot(root)

    // Kick off the scan, then interleave reads that MUST each finish under the bound.
    async let scanned = LibraryScanner().scan(root: root, folderID: folderID, into: store)
    for iteration in 0 ..< 20 {
        let done = try await withDeadline(seconds: 5) { () async throws -> Bool in
            _ = try await store.allTracks(sortedBy: .name)
            return true
        }
        guard done == true else {
            printFail(number, "reads-during-scan: read #\(iteration) exceeded 5s while a scan ran (SF-4)")
            return false
        }
    }
    let result = try await scanned
    guard result.filesSeen == fileCount else {
        printFail(number, "reads-during-scan: scan saw \(result.filesSeen), expected \(fileCount)"); return false
    }
    return true
}
