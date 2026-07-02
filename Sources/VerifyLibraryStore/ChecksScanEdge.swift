// ChecksScanEdge — S8.2b review-driven coverage: the FS-safety invariants and edge
// cases the first S8.2b pass claimed but did not exercise (qa-expert), plus the
// dev/inode root-identity dedup (founder decision QS3). Same VerifyAUGraph idiom;
// companion to ChecksScan / ChecksScanRescan / ChecksScanReconcile.
//
// Covers, all through the REAL LibraryScanner + REAL SQLite store:
//   • cancellation skips the sweep (QB2, §5/§9) — a scan cancelled mid-walk throws,
//     keeps its committed batch, and does NOT sweep (a deleted file survives the
//     cancelled re-scan, reaped only by a later full re-scan). The exact mechanism
//     AudioViewModel relies on for every re-pick/quit-mid-scan.
//   • a real (non-cancellation) throw mid-walk also skips the sweep (QS1) — a bad
//     folderID → FK violation → the scan rethrows before any commit or sweep.
//   • cross-directory move (QS2) — the realistic move shape: signature preserved,
//     relative_path updated, so S8.4's matcher can reunite it.
//   • root vanishes entirely (QS5) — external-drive-unmount: a re-scan sees 0 files
//     and sweeps every row the root held (the founder's "FS changes while closed").
//   • edge (QS4) — an unreadable (chmod 000) subdir doesn't abort the scan; a symlink
//     is its own entry with its OWN lstat inode (design §3 policy, finally tested).
//   • root identity (QS3) — addRoot dedups by on-disk (dev,inode), so a case-variant
//     path for one directory on a case-insensitive volume isn't a second root.

import Dispatch
import Foundation
import LibraryScan
import LibraryStore

// MARK: - QB2 — cancellation skips the sweep (§5 / §9 D-sweep)

func checkCancellationSkipsSweep(number: Int, url: URL) async -> Bool {
    do {
        let store = try await LibraryStore(url: url, appBuild: "verify")
        guard try await cancellationSkipsSweep(store, number: number) else { return false }
        printPass(number, "cancellation skips sweep (§5/§9): a scan cancelled mid-walk (after batch 1) "
            + "throws CancellationError and does NOT sweep — a file deleted from disk SURVIVES the "
            + "cancelled re-scan and is reaped only by a subsequent full re-scan")
        return true
    } catch {
        printFail(number, "cancellation skips sweep threw: \(error)"); return false
    }
}

/// Full-scan a >2-batch tree, delete one file, then re-scan CANCELLED right after the
/// first batch commits (parked via the progress closure). The cancelled scan must throw
/// and skip its sweep, so the deleted file's (stale-generation) row survives; a later
/// uncancelled re-scan then reaps it. Proves "cancel ⇒ no wrongful delete", not just
/// "no crash".
private func cancellationSkipsSweep(_ store: LibraryStore, number: Int) async throws -> Bool {
    let root = try ScanFixtureBuilder.makeCaseRoot("cancel-sweep")
    let fileCount = 600 // > batchSize 256, so files remain to walk after batch 1 → cancel bites
    var victim: URL?
    for index in 0 ..< fileCount {
        let fileURL = try ScanFixtureBuilder.writeFile(
            at: root, subdirs: ["d\(index / 60)"], fileName: "t\(index).flac"
        )
        if index == 0 { victim = fileURL }
    }
    guard let victim else { printFail(number, "cancel-sweep: fixture build failed"); return false }
    let folderID = try await store.addRoot(root)
    _ = try await LibraryScanner().scan(root: root, folderID: folderID, into: store)
    guard try await store.trackCount() == fileCount else {
        printFail(number, "cancel-sweep: first scan didn't populate \(fileCount) rows"); return false
    }

    try FileManager.default.removeItem(at: victim) // deleted → a completing re-scan WOULD sweep it
    guard try await cancelAfterFirstBatch(store, root: root, folderID: folderID, number: number) else {
        return false
    }
    // Sweep skipped ⇒ the deleted victim's row is still present.
    guard try await store.track(url: victim) != nil else {
        printFail(number, "cancel-sweep: victim row was swept despite cancellation (sweep NOT skipped)"); return false
    }
    // A later full (uncancelled) re-scan now reaps it.
    _ = try await LibraryScanner().scan(root: root, folderID: folderID, into: store)
    guard try await store.track(url: victim) == nil, try await store.trackCount() == fileCount - 1 else {
        printFail(number, "cancel-sweep: full re-scan did not reap the deleted victim"); return false
    }
    return true
}

/// Start a scan, park it in its progress closure after the first committed batch, cancel
/// it while parked, then release it so the next per-file `checkCancellation()` throws.
/// Returns true iff the scan threw `CancellationError` (not a completion, not another error).
private func cancelAfterFirstBatch(
    _ store: LibraryStore, root: URL, folderID: Int64, number: Int
) async throws -> Bool {
    let firstBatch = OneShotLatch()
    let proceed = DispatchSemaphore(value: 0) // released after cancel; wait()ed in the SYNC closure only
    let committed = AsyncStream<Void>.makeStream() // scanner → async: "first batch committed"
    let task = Task {
        try await LibraryScanner().scan(
            root: root, folderID: folderID, into: store,
            progress: { _ in
                // Sync closure: DispatchSemaphore.wait() is legal here (not an async context).
                firstBatch.runOnce {
                    committed.continuation.yield(())
                    committed.continuation.finish()
                    proceed.wait() // park the scanner mid-walk until the test has cancelled
                }
            }
        )
    }
    var batches = committed.stream.makeAsyncIterator()
    _ = await batches.next() // async-await the first committed batch (no async-context semaphore wait)
    task.cancel()
    proceed.signal() // release → the next per-file checkCancellation() throws
    do {
        _ = try await task.value
        printFail(number, "cancel-sweep: cancelled re-scan did NOT throw"); return false
    } catch is CancellationError {
        return true
    } catch {
        printFail(number, "cancel-sweep: re-scan threw \(error), expected CancellationError"); return false
    }
}

// MARK: - QS1 — a real throw mid-walk also skips the sweep

func checkThrowSkipsSweep(number: Int, url: URL) async -> Bool {
    do {
        let store = try await LibraryStore(url: url, appBuild: "verify")
        guard try await throwMidWalkSkipsSweep(store, number: number) else { return false }
        printPass(number, "throw skips sweep: a scan whose upsert throws (a non-existent folderID → FK "
            + "violation) rethrows and reaches NEITHER a partial commit NOR the sweep — trackCount unchanged")
        return true
    } catch {
        printFail(number, "throw-skips-sweep threw: \(error)"); return false
    }
}

/// A `folderID` with no `folders` row makes the batch upsert's INSERT violate the
/// `tracks.folder_id` FK — a real, non-cancellation throw inside the walk, before the
/// sweep. The scan must rethrow it and leave the store untouched (rolled-back txn, no
/// sweep). Distinct failure mode from QB2, locking in "skip the sweep on ANY non-completion".
private func throwMidWalkSkipsSweep(_ store: LibraryStore, number: Int) async throws -> Bool {
    let root = try ScanFixtureBuilder.makeCaseRoot("throw-sweep")
    _ = try ScanFixtureBuilder.writeFile(at: root, fileName: "a.flac")
    _ = try ScanFixtureBuilder.writeFile(at: root, fileName: "b.flac")
    let before = try await store.trackCount()
    let bogusFolderID: Int64 = 999_999 // no such folders row → FK violation on the first upsert
    var threw = false
    do {
        _ = try await LibraryScanner().scan(root: root, folderID: bogusFolderID, into: store)
    } catch is CancellationError {
        printFail(number, "throw-skips-sweep: got CancellationError, expected a store/FK error"); return false
    } catch {
        threw = true
    }
    guard threw else {
        printFail(number, "throw-skips-sweep: scan with a bogus folderID did NOT throw"); return false
    }
    let after = try await store.trackCount()
    guard after == before else {
        printFail(number, "throw-skips-sweep: trackCount changed (\(before) → \(after)) — a partial "
            + "commit or sweep leaked past the throw"); return false
    }
    return true
}

// MARK: - QS2 — cross-directory move preserves the move-signature

func checkCrossDirMove(number: Int, url: URL) async -> Bool {
    do {
        let store = try await LibraryStore(url: url, appBuild: "verify")
        guard try await crossDirMove(store, number: number) else { return false }
        printPass(number, "cross-dir move: moving a file to a DIFFERENT subdir within the root sweeps the "
            + "old path and creates a new row carrying the SAME (dev,inode,size,mtime) move-signature AND "
            + "an updated relative_path — the realistic move shape S8.4's matcher will reunite")
        return true
    } catch {
        printFail(number, "cross-dir move threw: \(error)"); return false
    }
}

/// Same-dir rename (case 17) is the weakest move; this exercises a cross-directory move
/// within one root — the shape S8.4 must reunite. The new row keeps the four-field
/// signature (same inode) and gets a NEW relative_path.
private func crossDirMove(_ store: LibraryStore, number: Int) async throws -> Bool {
    let root = try ScanFixtureBuilder.makeCaseRoot("crossdir-move")
    let oldURL = try ScanFixtureBuilder.writeFile(at: root, subdirs: ["From"], fileName: "song.flac", byteCount: 40)
    let folderID = try await store.addRoot(root)
    _ = try await LibraryScanner().scan(root: root, folderID: folderID, into: store)
    guard let oldRow = try await store.track(url: oldURL), oldRow.relativePath == "From/" else {
        printFail(number, "cross-dir move: first-scan row missing or wrong relative_path"); return false
    }

    let destDir = try ScanFixtureBuilder.makeDirectory(at: root, ["To", "Deep"])
    let newURL = destDir.appendingPathComponent("song.flac", isDirectory: false)
    try FileManager.default.moveItem(at: oldURL, to: newURL)
    let result = try await LibraryScanner().scan(root: root, folderID: folderID, into: store)
    guard result.orphansSwept == 1, try await store.track(url: oldURL) == nil else {
        printFail(number, "cross-dir move: old path not swept (orphansSwept \(result.orphansSwept))"); return false
    }
    guard let newRow = try await store.track(url: newURL) else {
        printFail(number, "cross-dir move: no row at the moved path"); return false
    }
    guard newRow.inode == oldRow.inode, newRow.dev == oldRow.dev,
          newRow.fileSize == oldRow.fileSize, newRow.mtime == oldRow.mtime else {
        printFail(number, "cross-dir move: move-signature not preserved across the directory change"); return false
    }
    guard newRow.relativePath == "To/Deep/", try await store.tracks(inFolder: folderID).count == 1 else {
        printFail(number, "cross-dir move: new relative_path wrong or row count != 1"); return false
    }
    return true
}

// MARK: - QS5 — root vanishes entirely → full sweep

func checkVanishedRoot(number: Int, url: URL) async -> Bool {
    do {
        let store = try await LibraryStore(url: url, appBuild: "verify")
        guard try await vanishedRootFullSweep(store, number: number) else { return false }
        printPass(number, "vanished root (external-drive unmount / folder deleted while closed): a re-scan "
            + "of a root whose whole directory is gone walks 0 files and sweeps EVERY row it held "
            + "(filesSeen 0, orphansSwept == original count, folder now empty)")
        return true
    } catch {
        printFail(number, "vanished-root threw: \(error)"); return false
    }
}

/// The founder's "FS changes while the app is not running" scenario at the ROOT level
/// (distinct from a file inside the root being deleted): the entire root directory
/// disappears. A re-scan enumerates nothing and every row it held is older than the new
/// generation → all swept.
private func vanishedRootFullSweep(_ store: LibraryStore, number: Int) async throws -> Bool {
    let root = try ScanFixtureBuilder.makeCaseRoot("vanished-root")
    for index in 0 ..< 5 {
        _ = try ScanFixtureBuilder.writeFile(at: root, subdirs: ["Sub"], fileName: "t\(index).flac")
    }
    let folderID = try await store.addRoot(root)
    let first = try await LibraryScanner().scan(root: root, folderID: folderID, into: store)
    guard first.filesSeen == 5, try await store.tracks(inFolder: folderID).count == 5 else {
        printFail(number, "vanished-root: first scan didn't populate 5 rows"); return false
    }

    try FileManager.default.removeItem(at: root) // the whole root directory vanishes
    let result = try await LibraryScanner().scan(root: root, folderID: folderID, into: store)
    guard result.filesSeen == 0 else {
        printFail(number, "vanished-root: expected filesSeen 0, got \(result.filesSeen)"); return false
    }
    guard result.orphansSwept == 5, try await store.tracks(inFolder: folderID).isEmpty else {
        printFail(number, "vanished-root: expected all 5 rows swept (orphansSwept \(result.orphansSwept))")
        return false
    }
    return true
}

// MARK: - QS4 — permission-denied subdir + symlink policy

func checkScanEdgePermissionsSymlink(number: Int, url: URL) async -> Bool {
    do {
        let store = try await LibraryStore(url: url, appBuild: "verify")
        guard try await permissionDeniedSubdir(store, number: number) else { return false }
        guard try symlinkSkipped(number: number) else { return false }
        printPass(number, "scan edge: an unreadable (chmod 000) subdir does NOT abort the scan — the "
            + "reachable sibling is still scanned; a symlink is SKIPPED (regular-files-only admission — "
            + "pinned current behavior; symlink-admission is a deferred product decision)")
        return true
    } catch {
        printFail(number, "scan edge (perm/symlink) threw: \(error)"); return false
    }
}

/// A `chmod 000` subdir must not abort the walk: its files are simply never enumerated,
/// while the reachable sibling IS scanned. Permissions are ALWAYS restored (defer) so a
/// failure can't wedge fixture teardown. (Exercises the `restoreWritableRecursively`
/// scaffolding built for this in S8.2a but never used.)
private func permissionDeniedSubdir(_ store: LibraryStore, number: Int) async throws -> Bool {
    let root = try ScanFixtureBuilder.makeCaseRoot("perm-denied")
    let readable = try ScanFixtureBuilder.writeFile(at: root, subdirs: ["Open"], fileName: "reachable.flac")
    let lockedDir = try ScanFixtureBuilder.makeDirectory(at: root, ["Locked"])
    _ = try ScanFixtureBuilder.writeFile(at: lockedDir, fileName: "hidden.flac")
    try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: lockedDir.path)
    defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: lockedDir.path) }

    let folderID = try await store.addRoot(root)
    let result = try await LibraryScanner().scan(root: root, folderID: folderID, into: store)
    guard try await store.track(url: readable) != nil, result.filesSeen >= 1 else {
        printFail(number, "perm-denied: the reachable sibling was not scanned (scan aborted?)"); return false
    }
    return true
}

/// PIN the current symlink behavior: the scanner admits only regular files, so a symlink
/// (even to a supported audio file) is SKIPPED — `makeScannedFile` returns nil because
/// `URLResourceValues.isRegularFile` is false for a symlink, and the walk `try?`-skips it.
/// The design's no-merge + lstat policy (§3, PathNormalizer/FileSignature) governs a
/// symlink's IDENTITY should admission ever be enabled — a deferred product decision, not
/// implemented here. The real target is indexed normally. Tested at `makeScannedFile`
/// (deterministic, independent of enumerator symlink quirks).
private func symlinkSkipped(number: Int) throws -> Bool {
    let root = try ScanFixtureBuilder.makeCaseRoot("symlink")
    let target = try ScanFixtureBuilder.writeFile(at: root, fileName: "real.flac", byteCount: 16)
    let link = root.appendingPathComponent("alias.flac", isDirectory: false)
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)

    guard LibraryScanner.makeScannedFile(fileURL: target, root: root) != nil else {
        printFail(number, "symlink: makeScannedFile nil for the real target (should be a normal row)"); return false
    }
    guard LibraryScanner.makeScannedFile(fileURL: link, root: root) == nil else {
        printFail(number, "symlink: expected the symlink to be SKIPPED (regular-files-only), but it was admitted")
        return false
    }
    return true
}

// MARK: - QS3 — dev/inode root-identity dedup (case-insensitive volume)

func checkRootIdentityDedup(number: Int, url: URL) async -> Bool {
    do {
        let store = try await LibraryStore(url: url, appBuild: "verify")
        guard try await rootIdentityDedup(store, number: number) else { return false }
        printPass(number, "root identity (QS3): addRoot dedups by on-disk (dev,inode) — two paths with the "
            + "SAME (dev,inode) collapse to one root; a real case-variant of one directory is caught on a "
            + "case-insensitive volume (or correctly stays distinct on a case-sensitive one)")
        return true
    } catch {
        printFail(number, "root identity dedup threw: \(error)"); return false
    }
}

/// Two parts: (1) DETERMINISTIC mechanism — two different path strings with the SAME
/// synthetic (dev,inode) collapse to one root (volume-independent); (2) REAL end-to-end
/// — a genuine dir + a case-variant path: the (dev,inode) identity is the arbiter, so it
/// dedups on a case-insensitive volume and correctly stays distinct on a case-sensitive one.
private func rootIdentityDedup(_ store: LibraryStore, number: Int) async throws -> Bool {
    let rootA = try ScanFixtureBuilder.makeCaseRoot("identity-A")
    let rootB = try ScanFixtureBuilder.makeCaseRoot("identity-B")
    let idA = try await store.addRoot(rootA, dev: 42, inode: 777)
    let idB = try await store.addRoot(rootB, dev: 42, inode: 777)
    guard idA == idB, try await store.roots().count == 1 else {
        printFail(number, "root identity: same (dev,inode)/different paths did not collapse to one root")
        return false
    }

    let realDir = try ScanFixtureBuilder.makeCaseRoot("Identity-Real")
    guard let realSig = independentLstat(realDir) else {
        printFail(number, "root identity: lstat failed for the real dir"); return false
    }
    let realID = try await store.addRoot(realDir, dev: realSig.dev, inode: realSig.inode)
    let variant = caseVariantURL(of: realDir)
    let variantSig = independentLstat(variant) // same (dev,inode) on a case-insensitive volume; nil otherwise
    let variantID = try await store.addRoot(variant, dev: variantSig?.dev, inode: variantSig?.inode)
    if let variantSig, variantSig.dev == realSig.dev, variantSig.inode == realSig.inode {
        guard variantID == realID else {
            printFail(number, "root identity: case-variant of the same dir was NOT deduped (case-insensitive volume)")
            return false
        }
    } else {
        guard variantID != realID else {
            printFail(number, "root identity: genuinely distinct dirs were wrongly merged"); return false
        }
    }
    return true
}

/// A case-flipped variant of `url`'s last path component (used to probe case-insensitive
/// volume behavior). On a case-insensitive volume it resolves to the SAME directory.
private func caseVariantURL(of url: URL) -> URL {
    let parent = url.deletingLastPathComponent()
    return parent.appendingPathComponent(url.lastPathComponent.uppercased(), isDirectory: true)
}
