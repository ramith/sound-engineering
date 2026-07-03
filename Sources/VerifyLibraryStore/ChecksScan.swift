// ChecksScan — S8.2a scanner-core cases, driven through the REAL LibraryScanner
// against a REAL temp-dir tree (design §8). Companion to ScanFixtureBuilder.swift
// (tree writer) and ChecksScanRescan.swift (idempotent re-scan / FS-5 / edge).
//
// This file covers, all through `LibraryScanner().scan`:
//   • scan-correctness — a nested tree yields EXACTLY the audio rows; non-audio /
//     hidden / package descendants excluded; a `music.mp3/` DIRECTORY is not a
//     leaf; `format` is uppercase.
//   • relative_path — `root/Sub/Deep/x.flac` → "Sub/Deep/"; a root-level file →
//     ""; and the COMPONENT-BOUNDARY case: sibling roots `Rock` and `RockAndRoll`
//     each scanned in isolation, each holding ONLY its own files (the live
//     /Music/Rock vs /Music/RockAndRoll bug).
//   • signature-vs-lstat — every row's (size, mtime, inode, dev) equals a fresh,
//     scanner-independent `lstat`; two distinct files never share an inode.
//
// S8.2a scans ONE root per `scan` call and does NO orphan sweep (that is S8.2b).
// Idiom matches VerifyAUGraph exactly: Bool return, numbered PASS/FAIL.

import Foundation
import LibraryScan
import LibraryStore

// MARK: - Scan — correctness + relative_path + signature (S8.2a)

func checkScanCore(number: Int, url: URL) async -> Bool {
    do {
        let store = try await LibraryStore(url: url, appBuild: "verify")

        guard try await checkScanCorrectness(store, number: number) else { return false }
        guard try await checkRelativePath(store, number: number) else { return false }
        guard try await checkComponentBoundaryRoots(store, number: number) else { return false }
        guard try await checkSignatureVsLstat(store, number: number) else { return false }

        printPass(number, "scan core (real tree): nested walk yields EXACTLY the audio rows "
            + "(non-audio/hidden/package excluded, music.mp3/ dir not a leaf, format uppercase); "
            + "relative_path exact incl. Rock vs RockAndRoll component boundary; every row's "
            + "(size,mtime,inode,dev) == an independent lstat")
        return true
    } catch {
        printFail(number, "scan core threw: \(error)"); return false
    }
}

// MARK: - Scan correctness

/// A nested tree scans to EXACTLY its audio files (by path), with non-audio /
/// hidden / package-descendant entries excluded, a `music.mp3/` directory NOT
/// treated as a leaf, and every stored `format` uppercased.
private func checkScanCorrectness(_ store: LibraryStore, number: Int) async throws -> Bool {
    let root = try ScanFixtureBuilder.makeCaseRoot("correctness")
    let expectedPaths = try ScanFixtureBuilder.buildNestedTree(root)

    let folderID = try await store.addRoot(root)
    let result = try await LibraryScanner().scan(root: root, folderID: folderID, into: store)

    guard result.filesSeen == expectedPaths.count else {
        printFail(number, "scan correctness: filesSeen \(result.filesSeen) != expected \(expectedPaths.count)")
        return false
    }
    let rows = try await store.tracks(inFolder: folderID)
    let storedPaths = Set(rows.map { $0.url.path })
    guard storedPaths == expectedPaths else {
        let missing = expectedPaths.subtracting(storedPaths)
        let extra = storedPaths.subtracting(expectedPaths)
        printFail(number, "scan correctness: row-set mismatch — missing \(missing), extra \(extra)")
        return false
    }
    // format must be uppercase (e.g. the case-insensitive `.FLAC` → "FLAC").
    guard rows.allSatisfy({ $0.format == $0.format.uppercased() && !$0.format.isEmpty }) else {
        printFail(number, "scan correctness: a stored format was not uppercase (\(rows.map(\.format)))")
        return false
    }
    // Sanity: the `music.mp3` DIRECTORY did not itself become a row.
    let dirAsLeaf = root.appendingPathComponent("music.mp3", isDirectory: false).path
    guard !storedPaths.contains(dirAsLeaf) else {
        printFail(number, "scan correctness: the music.mp3/ directory was scanned as a leaf"); return false
    }
    return true
}

// MARK: - relative_path (nested + root-level)

/// `relative_path` is the root-relative CONTAINING directory with a trailing slash
/// (`"Sub/Deep/"`), and `""` for a root-level file.
private func checkRelativePath(_ store: LibraryStore, number: Int) async throws -> Bool {
    let root = try ScanFixtureBuilder.makeCaseRoot("relpath")
    let deep = try ScanFixtureBuilder.writeFile(at: root, subdirs: ["Sub", "Deep"], fileName: "x.flac")
    let rootLevel = try ScanFixtureBuilder.writeFile(at: root, fileName: "top.flac")

    let folderID = try await store.addRoot(root)
    _ = try await LibraryScanner().scan(root: root, folderID: folderID, into: store)

    guard let deepRow = try await store.track(url: deep) else {
        printFail(number, "relative_path: nested file row missing"); return false
    }
    guard deepRow.relativePath == "Sub/Deep/" else {
        printFail(number, "relative_path: nested expected 'Sub/Deep/', got '\(deepRow.relativePath)'"); return false
    }
    guard let topRow = try await store.track(url: rootLevel) else {
        printFail(number, "relative_path: root-level file row missing"); return false
    }
    guard topRow.relativePath == "" else {
        printFail(number, "relative_path: root-level expected '', got '\(topRow.relativePath)'"); return false
    }
    return true
}

// MARK: - Component-boundary roots (Rock vs RockAndRoll)

/// Two sibling roots whose names share a string prefix (`Rock` ⊂ `RockAndRoll`) are
/// each scanned in isolation; each folder must hold ONLY its own files. A raw
/// `dropFirst(root.count)` prefix strip would fold RockAndRoll's files under Rock —
/// this is the exact live bug the component-boundary strip fixes.
private func checkComponentBoundaryRoots(_ store: LibraryStore, number: Int) async throws -> Bool {
    let base = try ScanFixtureBuilder.makeCaseRoot("boundary")
    let rockRoot = try ScanFixtureBuilder.makeDirectory(at: base, ["Rock"])
    let rockAndRollRoot = try ScanFixtureBuilder.makeDirectory(at: base, ["RockAndRoll"])
    let rockFile = try ScanFixtureBuilder.writeFile(at: rockRoot, fileName: "rock-only.flac")
    let rrFile = try ScanFixtureBuilder.writeFile(at: rockAndRollRoot, fileName: "rr-only.flac")

    let rockID = try await store.addRoot(rockRoot)
    let rrID = try await store.addRoot(rockAndRollRoot)
    _ = try await LibraryScanner().scan(root: rockRoot, folderID: rockID, into: store)
    _ = try await LibraryScanner().scan(root: rockAndRollRoot, folderID: rrID, into: store)

    let rockRows = try await store.tracks(inFolder: rockID)
    let rrRows = try await store.tracks(inFolder: rrID)
    guard rockRows.map({ $0.url.path }) == [rockFile.path] else {
        printFail(number, "component boundary: Rock folder held \(rockRows.map(\.url.path)) (expected only rock-only)")
        return false
    }
    guard rrRows.map({ $0.url.path }) == [rrFile.path] else {
        printFail(number, "component boundary: RockAndRoll folder held \(rrRows.map(\.url.path))")
        return false
    }
    // Both root-level in their OWN roots → each relative_path is "".
    guard rockRows.allSatisfy({ $0.relativePath == "" }), rrRows.allSatisfy({ $0.relativePath == "" }) else {
        printFail(number, "component boundary: a sibling-root file got a non-empty relative_path"); return false
    }
    return true
}

// MARK: - Signature vs independent lstat

/// Every stored row's (size, mtime, inode, dev) equals a fresh, scanner-independent
/// `lstat` of the same real file — not merely non-null (catches a scanner stamping
/// `now` for mtime, or the same inode for two files). Two DISTINCT files must have
/// DISTINCT inodes.
private func checkSignatureVsLstat(_ store: LibraryStore, number: Int) async throws -> Bool {
    let root = try ScanFixtureBuilder.makeCaseRoot("signature")
    // Two DIFFERENT files (different sizes) so their inodes must differ.
    let first = try ScanFixtureBuilder.writeFile(at: root, fileName: "one.flac", byteCount: 8)
    let second = try ScanFixtureBuilder.writeFile(at: root, subdirs: ["S"], fileName: "two.flac", byteCount: 32)

    let folderID = try await store.addRoot(root)
    _ = try await LibraryScanner().scan(root: root, folderID: folderID, into: store)

    for fileURL in [first, second] {
        guard let truth = independentLstat(fileURL) else {
            printFail(number, "signature: independent lstat failed for \(fileURL.lastPathComponent)"); return false
        }
        guard let row = try await store.track(url: fileURL) else {
            printFail(number, "signature: row missing for \(fileURL.lastPathComponent)"); return false
        }
        guard row.fileSize == truth.size, row.mtime == truth.mtime else {
            printFail(number, "signature: size/mtime mismatch for \(fileURL.lastPathComponent) — "
                + "stored (\(row.fileSize),\(row.mtime)) vs lstat (\(truth.size),\(truth.mtime))"); return false
        }
        guard row.inode == truth.inode, row.dev == truth.dev else {
            printFail(number, "signature: inode/dev mismatch for \(fileURL.lastPathComponent) — "
                + "stored (\(stringify(row.inode)),\(stringify(row.dev))) vs "
                + "lstat (\(truth.inode),\(truth.dev))"); return false
        }
    }
    // Two distinct files never share an inode.
    guard let firstRow = try await store.track(url: first),
          let secondRow = try await store.track(url: second),
          firstRow.inode != secondRow.inode else {
        printFail(number, "signature: two distinct files shared an inode (or a row was missing)"); return false
    }
    return true
}

/// Render an optional Int64 for a failure message.
private func stringify(_ value: Int64?) -> String {
    value.map(String.init) ?? "nil"
}
