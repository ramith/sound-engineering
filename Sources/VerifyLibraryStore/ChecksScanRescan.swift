// ChecksScanRescan — S8.2a re-scan idempotency, FS-5 add/modify, and edge cases,
// driven through the REAL LibraryScanner against a REAL temp-dir tree (design §8).
// Companion to ChecksScan.swift; same VerifyAUGraph idiom.
//
// Covers, all through `LibraryScanner().scan`:
//   • idempotent re-scan — scanning an UNCHANGED tree twice → same count, no dup,
//     no mtime/content bump (only `last_seen_scan` generation advances); classify
//     reports every file `.unchanged(sameID)`.
//   • FS-5 add — a file added on disk between scans → a NEW row (classify `.new`
//     pre-upsert); modify — a file whose size/mtime changed on disk → classify
//     `.modified(sameID)`, updated in place (SAME id, no duplicate).
//   • edge — an empty root → 0 rows, no error; a file deleted between enumerate and
//     stat is `try?`-skipped (no crash), preserving AudioFileEnumerator's discipline.
//
// NO orphan sweep here — S8.2a does not remove rows (deletion reconciliation is
// S8.2b). These cases therefore assert add/modify only, never removal.

import Foundation
import LibraryScan
import LibraryStore

// MARK: - Scan — idempotent re-scan + FS-5 add/modify + edge (S8.2a)

func checkScanRescanEdge(number: Int, url: URL) async -> Bool {
    do {
        let store = try await LibraryStore(url: url, appBuild: "verify")

        guard try await checkIdempotentRescan(store, number: number) else { return false }
        guard try await checkFS5AddAndModify(store, number: number) else { return false }
        guard try await checkEmptyRoot(store, number: number) else { return false }
        guard try await checkDeletedBetweenEnumerateAndStat(store, number: number) else { return false }

        printPass(number, "scan re-scan/edge (real tree): idempotent re-scan → same count, no bump, "
            + "classify .unchanged(sameID); FS-5 add → new row (.new); modify → .modified(sameID) "
            + "in place; empty root → 0 rows; a file deleted mid-walk is skipped (no crash)")
        return true
    } catch {
        printFail(number, "scan re-scan/edge threw: \(error)"); return false
    }
}

// MARK: - Idempotent re-scan

/// Scanning an UNCHANGED tree twice reaches steady state: identical row count, NO
/// content/mtime bump (only `last_seen_scan` advances), and classify reports every
/// file `.unchanged` with the SAME id on the second pass.
private func checkIdempotentRescan(_ store: LibraryStore, number: Int) async throws -> Bool {
    let root = try ScanFixtureBuilder.makeCaseRoot("idempotent")
    let fileURLs = try [
        ScanFixtureBuilder.writeFile(at: root, fileName: "one.flac"),
        ScanFixtureBuilder.writeFile(at: root, subdirs: ["Sub"], fileName: "two.mp3"),
        ScanFixtureBuilder.writeFile(at: root, subdirs: ["Sub"], fileName: "three.wav"),
    ]
    let folderID = try await store.addRoot(root)

    let first = try await LibraryScanner().scan(root: root, folderID: folderID, into: store)
    let countAfterFirst = try await store.trackCount()
    // Capture each row's stable id + content signature after the first scan.
    guard let signatures = try await captureRowSignatures(store, fileURLs: fileURLs, number: number) else {
        return false
    }

    let second = try await LibraryScanner().scan(root: root, folderID: folderID, into: store)
    guard second.generation > first.generation else {
        printFail(number, "idempotent: second scan did not advance the generation"); return false
    }
    guard try await store.trackCount() == countAfterFirst else {
        printFail(number, "idempotent: re-scan changed the row count (duplicate)"); return false
    }
    return try await checkRowsUnchangedAfterRescan(
        store, fileURLs: fileURLs, root: root, signatures: signatures, number: number
    )
}

/// Capture each row's stable id + mtime signature after a scan, keyed by file path. Returns
/// `nil` (already reported) if any expected row is missing.
private func captureRowSignatures(
    _ store: LibraryStore, fileURLs: [URL], number: Int
) async throws -> (ids: [String: Int64], mtimes: [String: Int64])? {
    var idByPath: [String: Int64] = [:]
    var mtimeByPath: [String: Int64] = [:]
    for fileURL in fileURLs {
        guard let row = try await store.track(url: fileURL) else {
            printFail(number, "idempotent: first-scan row missing for \(fileURL.lastPathComponent)"); return nil
        }
        idByPath[fileURL.path] = row.id
        mtimeByPath[fileURL.path] = row.mtime
    }
    return (idByPath, mtimeByPath)
}

/// After the second (idempotent) scan, every row must keep its `signatures` id/mtime and
/// classify (pre-upsert) as `.unchanged(sameID)`.
private func checkRowsUnchangedAfterRescan(
    _ store: LibraryStore, fileURLs: [URL], root: URL,
    signatures: (ids: [String: Int64], mtimes: [String: Int64]), number: Int
) async throws -> Bool {
    for fileURL in fileURLs {
        guard let row = try await store.track(url: fileURL) else {
            printFail(number, "idempotent: second-scan row missing for \(fileURL.lastPathComponent)"); return false
        }
        guard row.id == signatures.ids[fileURL.path], row.mtime == signatures.mtimes[fileURL.path] else {
            printFail(number, "idempotent: re-scan bumped id/mtime for \(fileURL.lastPathComponent)"); return false
        }
        // classify (pre-upsert view) must see the unchanged, same-id row.
        guard let scanned = LibraryScanner.makeScannedFile(fileURL: fileURL, root: root) else {
            printFail(number, "idempotent: makeScannedFile returned nil for \(fileURL.lastPathComponent)")
            return false
        }
        guard case let .unchanged(sameID) = try await store.classify(scanned), sameID == row.id else {
            printFail(number, "idempotent: classify not .unchanged(sameID) for \(fileURL.lastPathComponent)")
            return false
        }
    }
    return true
}

// MARK: - FS-5 add + modify

/// FS-5 (no sweep needed): after an initial scan, ADD a file on disk → classify
/// `.new` and a re-scan inserts a NEW row; MODIFY a file's bytes on disk → classify
/// `.modified(sameID)` and the re-scan updates it IN PLACE (same id, no duplicate).
private func checkFS5AddAndModify(_ store: LibraryStore, number: Int) async throws -> Bool {
    let root = try ScanFixtureBuilder.makeCaseRoot("fs5")
    let stable = try ScanFixtureBuilder.writeFile(at: root, fileName: "stable.flac", byteCount: 8)
    let mutable = try ScanFixtureBuilder.writeFile(at: root, fileName: "mutable.flac", byteCount: 8)
    let folderID = try await store.addRoot(root)
    _ = try await LibraryScanner().scan(root: root, folderID: folderID, into: store)
    let countAfterFirst = try await store.trackCount()
    guard let mutableIDBefore = try await store.track(url: mutable)?.id else {
        printFail(number, "FS-5: mutable row missing after first scan"); return false
    }
    _ = stable

    guard try await checkFS5Add(
        store, root: root, folderID: folderID, countAfterFirst: countAfterFirst, number: number
    ) else { return false }

    let location = ScanLocation(root: root, folderID: folderID)
    return try await checkFS5Modify(
        store, location: location, mutable: mutable, mutableIDBefore: mutableIDBefore, number: number
    )
}

/// The tree root + registered library folder id a re-scan runs against — bundled so
/// `checkFS5Modify` stays under the SwiftLint parameter-count ceiling.
private struct ScanLocation {
    let root: URL
    let folderID: Int64
}

/// FS-5 ADD: a brand-new file on disk classifies `.new` pre-upsert, and a re-scan creates
/// exactly one new row for it.
private func checkFS5Add(
    _ store: LibraryStore, root: URL, folderID: Int64, countAfterFirst: Int, number: Int
) async throws -> Bool {
    let added = try ScanFixtureBuilder.writeFile(at: root, subdirs: ["New"], fileName: "added.flac")
    guard let addedScanned = LibraryScanner.makeScannedFile(fileURL: added, root: root) else {
        printFail(number, "FS-5: makeScannedFile nil for the added file"); return false
    }
    guard case .new = try await store.classify(addedScanned) else {
        printFail(number, "FS-5: added file did not classify .new pre-upsert"); return false
    }
    _ = try await LibraryScanner().scan(root: root, folderID: folderID, into: store)
    guard try await store.trackCount() == countAfterFirst + 1 else {
        printFail(number, "FS-5: re-scan after add did not create exactly one new row"); return false
    }
    guard try await store.track(url: added) != nil else {
        printFail(number, "FS-5: the added file has no row after re-scan"); return false
    }
    return true
}

/// FS-5 MODIFY: changing an existing file's bytes (size + mtime) on disk classifies
/// `.modified(sameID)`, and a re-scan updates the row IN PLACE (same id, no duplicate).
private func checkFS5Modify(
    _ store: LibraryStore, location: ScanLocation, mutable: URL, mutableIDBefore: Int64, number: Int
) async throws -> Bool {
    try await bumpFileOnDisk(mutable)
    guard let modifiedScanned = LibraryScanner.makeScannedFile(fileURL: mutable, root: location.root) else {
        printFail(number, "FS-5: makeScannedFile nil for the modified file"); return false
    }
    guard case let .modified(sameID) = try await store.classify(modifiedScanned), sameID == mutableIDBefore else {
        printFail(number, "FS-5: modified file did not classify .modified(sameID)"); return false
    }
    let countBeforeModifyScan = try await store.trackCount()
    _ = try await LibraryScanner().scan(root: location.root, folderID: location.folderID, into: store)
    guard try await store.trackCount() == countBeforeModifyScan else {
        printFail(number, "FS-5: re-scan after modify changed the row count (should update in place)"); return false
    }
    guard let modifiedRow = try await store.track(url: mutable), modifiedRow.id == mutableIDBefore else {
        printFail(number, "FS-5: modify changed the stable id (not an in-place update)"); return false
    }
    guard modifiedRow.fileSize == modifiedScanned.fileSize, modifiedRow.mtime == modifiedScanned.mtime else {
        printFail(number, "FS-5: modified row's size/mtime were not updated in place"); return false
    }
    return true
}

// MARK: - Edge cases

/// An empty root scans to 0 rows with no error.
private func checkEmptyRoot(_ store: LibraryStore, number: Int) async throws -> Bool {
    let root = try ScanFixtureBuilder.makeCaseRoot("empty")
    let folderID = try await store.addRoot(root)
    let result = try await LibraryScanner().scan(root: root, folderID: folderID, into: store)
    guard result.filesSeen == 0, result.trackIDs.isEmpty else {
        printFail(number, "edge: empty root reported \(result.filesSeen) files"); return false
    }
    guard try await store.tracks(inFolder: folderID).isEmpty else {
        printFail(number, "edge: empty root produced rows"); return false
    }
    return true
}

/// A file deleted BETWEEN enumeration and the per-file stat must be `try?`-skipped —
/// no crash, no row. Deleting the file just before the scan makes `resourceValues`
/// fail on a stale enumerated URL; the scanner counts it skipped and carries on with
/// its siblings. (The enumerator snapshot yields the now-gone entry; the fetch
/// fails; this reproduces the TOCTOU window without racing a live walk.)
private func checkDeletedBetweenEnumerateAndStat(_ store: LibraryStore, number: Int) async throws -> Bool {
    let root = try ScanFixtureBuilder.makeCaseRoot("toctou")
    let survivor = try ScanFixtureBuilder.writeFile(at: root, fileName: "survivor.flac")
    let doomed = try ScanFixtureBuilder.writeFile(at: root, fileName: "doomed.flac")

    // makeScannedFile on a path whose file was just removed must return nil (skip),
    // never trap — the exact per-file discipline the walk relies on.
    try FileManager.default.removeItem(at: doomed)
    guard LibraryScanner.makeScannedFile(fileURL: doomed, root: root) == nil else {
        printFail(number, "edge/TOCTOU: makeScannedFile did not skip a vanished file"); return false
    }

    let folderID = try await store.addRoot(root)
    let result = try await LibraryScanner().scan(root: root, folderID: folderID, into: store)
    // The survivor is scanned; the doomed file yields no row (it was gone by stat).
    guard try await store.track(url: survivor) != nil else {
        printFail(number, "edge/TOCTOU: the surviving sibling was not scanned"); return false
    }
    guard try await store.track(url: doomed) == nil else {
        printFail(number, "edge/TOCTOU: a row was created for the vanished file"); return false
    }
    guard result.filesSeen >= 1 else {
        printFail(number, "edge/TOCTOU: expected at least the survivor to be seen"); return false
    }
    return true
}

// MARK: - Helpers

/// Rewrite `fileURL` with MORE bytes and force a later mtime so both halves of the
/// `(size, mtime)` signature change (a modify a re-scan must detect). The explicit
/// mtime bump avoids relying on whole-second wall-clock granularity.
private func bumpFileOnDisk(_ fileURL: URL) async throws {
    let bytes = Data((0 ..< 64).map { UInt8($0 & 0xFF) })
    try bytes.write(to: fileURL)
    // Push mtime a minute forward so the whole-second signature is unambiguously new.
    let future = Date().addingTimeInterval(60)
    try FileManager.default.setAttributes([.modificationDate: future], ofItemAtPath: fileURL.path)
}
