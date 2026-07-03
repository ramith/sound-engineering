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
    var idByPath: [String: Int64] = [:]
    var mtimeByPath: [String: Int64] = [:]
    for fileURL in fileURLs {
        guard let row = try await store.track(url: fileURL) else {
            printFail(number, "idempotent: first-scan row missing for \(fileURL.lastPathComponent)"); return false
        }
        idByPath[fileURL.path] = row.id
        mtimeByPath[fileURL.path] = row.mtime
    }

    let second = try await LibraryScanner().scan(root: root, folderID: folderID, into: store)
    guard second.generation > first.generation else {
        printFail(number, "idempotent: second scan did not advance the generation"); return false
    }
    guard try await store.trackCount() == countAfterFirst else {
        printFail(number, "idempotent: re-scan changed the row count (duplicate)"); return false
    }
    for fileURL in fileURLs {
        guard let row = try await store.track(url: fileURL) else {
            printFail(number, "idempotent: second-scan row missing for \(fileURL.lastPathComponent)"); return false
        }
        guard row.id == idByPath[fileURL.path], row.mtime == mtimeByPath[fileURL.path] else {
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

    // --- ADD a brand-new file on disk. ---
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

    // --- MODIFY an existing file's bytes (size + mtime change) on disk. ---
    try await bumpFileOnDisk(mutable)
    guard let modifiedScanned = LibraryScanner.makeScannedFile(fileURL: mutable, root: root) else {
        printFail(number, "FS-5: makeScannedFile nil for the modified file"); return false
    }
    guard case let .modified(sameID) = try await store.classify(modifiedScanned), sameID == mutableIDBefore else {
        printFail(number, "FS-5: modified file did not classify .modified(sameID)"); return false
    }
    let countBeforeModifyScan = try await store.trackCount()
    _ = try await LibraryScanner().scan(root: root, folderID: folderID, into: store)
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
