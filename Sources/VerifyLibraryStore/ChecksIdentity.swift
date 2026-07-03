// ChecksIdentity — case E (idempotency + identity). Companion to main.swift.
//
// Covers: re-upsert of an identical row = one row with NO mtime bump; a changed
// field updates in place; scan-twice batch steady state; M2 (an mtime-only change
// AND a size-only change EACH → .modified); and M6 (moveTrack preserves id, updates
// url/folder_id + relative_path, and a SYNTHETIC reference row — a stand-in
// playlist_tracks-shaped (ref_id, track_id) fixture table — still resolves to the
// moved track). The M6 case also proves the cross-folder relative_path fix: a track
// with a NON-EMPTY relative_path moved into a DIFFERENT non-NULL folder takes the NEW
// relative_path (not the stale old one, which was relative to the old root).

import Foundation
import LibraryStore

// MARK: - E — idempotency + identity

func checkIdempotencyIdentity(number: Int, url: URL) async -> Bool {
    do {
        let store = try await LibraryStore(url: url, appBuild: "verify")
        let rootID = try await store.addRoot(URL(fileURLWithPath: "/Music/E"))

        guard try await checkReupsertNoBump(store, number: number, rootID: rootID) else { return false }
        guard try await checkChangedFieldUpdates(store, number: number, rootID: rootID) else { return false }
        guard try await checkBatchSteadyState(store, number: number, rootID: rootID) else { return false }
        guard try await checkClassifyPerField(store, number: number, rootID: rootID) else { return false }
        guard try await checkMoveTrackIdentity(store, url: url, number: number, rootID: rootID) else {
            return false
        }

        printPass(number, "idempotency+identity: re-upsert = 1 row, no mtime bump; changed field updates "
            + "in place; scan-twice steady state; M2 (mtime-only AND size-only each → .modified); "
            + "M6 (moveTrack preserves id, updates url/folder + relative_path, synthetic reference resolves)")
        return true
    } catch {
        printFail(number, "idempotency+identity threw: \(error)"); return false
    }
}

/// Re-upserting the byte-identical scanned file leaves ONE row and does NOT bump
/// mtime (or any content column). last_seen_scan may advance (liveness), and that
/// is the ONLY change permitted.
private func checkReupsertNoBump(_ store: LibraryStore, number: Int, rootID: Int64) async throws -> Bool {
    let file = makeScanned(path: "/Music/E/idem.flac", name: "idem", size: 1234, mtime: 5555)
    let gen1 = try await store.beginScanGeneration()
    let firstIDs = try await store.upsert([file], folderID: rootID, generation: gen1)
    guard let firstID = firstIDs.first, let first = try await store.track(id: firstID) else {
        printFail(number, "idempotency: first upsert failed"); return false
    }
    // Re-upsert the SAME file (a fresh generation, as a re-scan would).
    let gen2 = try await store.beginScanGeneration()
    let secondIDs = try await store.upsert([file], folderID: rootID, generation: gen2)
    guard secondIDs.first == firstID else {
        printFail(number, "idempotency: re-upsert changed the row id (\(secondIDs) vs \(firstID))"); return false
    }
    let count = try await store.trackCount()
    guard count == 1 else {
        printFail(number, "idempotency: re-upsert created a duplicate (count \(count))"); return false
    }
    guard let second = try await store.track(id: firstID),
          second.mtime == first.mtime, second.fileSize == first.fileSize, second.name == first.name else {
        printFail(number, "idempotency: re-upsert bumped a content field (mtime/size/name)"); return false
    }
    return true
}

/// A changed field (a new mtime) updates the SAME row in place — no new row.
private func checkChangedFieldUpdates(_ store: LibraryStore, number: Int, rootID: Int64) async throws -> Bool {
    let original = makeScanned(path: "/Music/E/mut.flac", name: "mut", size: 100, mtime: 10)
    let gen1 = try await store.beginScanGeneration()
    let ids = try await store.upsert([original], folderID: rootID, generation: gen1)
    guard let mutID = ids.first else { printFail(number, "identity: mutate seed failed"); return false }
    let countBefore = try await store.trackCount()

    let changed = makeScanned(path: "/Music/E/mut.flac", name: "mut", size: 100, mtime: 20)
    let gen2 = try await store.beginScanGeneration()
    let ids2 = try await store.upsert([changed], folderID: rootID, generation: gen2)
    guard ids2.first == mutID else {
        printFail(number, "identity: changed-field upsert produced a new id"); return false
    }
    guard try await store.trackCount() == countBefore else {
        printFail(number, "identity: changed-field upsert added a row"); return false
    }
    guard let after = try await store.track(id: mutID), after.mtime == 20 else {
        printFail(number, "identity: changed mtime not applied in place"); return false
    }
    return true
}

/// Scanning the SAME batch twice reaches a steady state: identical row count, and
/// classify reports every file `.unchanged` on the second pass.
private func checkBatchSteadyState(_ store: LibraryStore, number: Int, rootID: Int64) async throws -> Bool {
    let batch = (0 ..< 5).map { makeScanned(path: "/Music/E/batch\($0).flac", name: "batch\($0)") }
    let gen1 = try await store.beginScanGeneration()
    _ = try await store.upsert(batch, folderID: rootID, generation: gen1)
    let countAfterFirst = try await store.trackCount()
    let gen2 = try await store.beginScanGeneration()
    _ = try await store.upsert(batch, folderID: rootID, generation: gen2)
    guard try await store.trackCount() == countAfterFirst else {
        printFail(number, "idempotency: scan-twice changed the row count"); return false
    }
    for file in batch {
        guard case .unchanged = try await store.classify(file) else {
            printFail(number, "idempotency: classify did not report .unchanged on the second scan"); return false
        }
    }
    return true
}

/// M2: an mtime-only change AND (independently) a size-only change EACH yield
/// `.modified` — the classify signature is per-field, not "size AND mtime both".
private func checkClassifyPerField(_ store: LibraryStore, number: Int, rootID: Int64) async throws -> Bool {
    let base = makeScanned(path: "/Music/E/sig.flac", name: "sig", size: 500, mtime: 50)
    let gen = try await store.beginScanGeneration()
    _ = try await store.upsert([base], folderID: rootID, generation: gen)

    let mtimeOnly = makeScanned(path: "/Music/E/sig.flac", name: "sig", size: 500, mtime: 99)
    guard case .modified = try await store.classify(mtimeOnly) else {
        printFail(number, "M2: mtime-only change did NOT classify as .modified"); return false
    }
    let sizeOnly = makeScanned(path: "/Music/E/sig.flac", name: "sig", size: 999, mtime: 50)
    guard case .modified = try await store.classify(sizeOnly) else {
        printFail(number, "M2: size-only change did NOT classify as .modified"); return false
    }
    // Sanity: the identical signature is .unchanged.
    guard case .unchanged = try await store.classify(base) else {
        printFail(number, "M2: identical signature did not classify as .unchanged"); return false
    }
    return true
}

/// M6: moveTrack preserves the stable id and updates url/folder_id + relative_path,
/// AND a SYNTHETIC reference row (a stand-in playlist_tracks-shaped (ref_id, track_id)
/// fixture table the harness creates on a second connection) STILL resolves to the
/// moved track — proving memberships keyed on tracks.id survive an in-place move with
/// zero writes. Also asserts the cross-folder relative_path fix: the seed carries a
/// NON-EMPTY relative_path under /Music/E, is moved into the DIFFERENT root
/// /Music/E-dest with a NEW relative_path, and the stored value is the NEW one (never
/// the stale old path, which was relative to /Music/E).
private func checkMoveTrackIdentity(
    _ store: LibraryStore, url: URL, number: Int, rootID: Int64
) async throws -> Bool {
    let gen = try await store.beginScanGeneration()
    // Seed with a NON-EMPTY relative_path (relative to the /Music/E root).
    let seed = ScannedFile(
        url: URL(fileURLWithPath: "/Music/E/sub/move-src.flac"), relativePath: "sub/move-src.flac",
        name: "move-src", format: "FLAC", fileSize: 4096, mtime: 1000, inode: 42
    )
    let ids = try await store.upsert([seed], folderID: rootID, generation: gen)
    guard let trackID = ids.first else { printFail(number, "M6: move seed failed"); return false }
    guard let seeded = try await store.track(id: trackID), seeded.relativePath == "sub/move-src.flac" else {
        printFail(number, "M6: seed did not store the non-empty relative_path"); return false
    }
    let destFolderID = try await store.addRoot(URL(fileURLWithPath: "/Music/E-dest"))

    // Synthetic reference table + a reference row → this track (a second WAL reader
    // connection; the actor's committed writes are visible to it).
    let refConnection = try SQLiteConnection(path: url.path)
    defer { refConnection.close() }
    try refConnection.exec(
        "CREATE TABLE IF NOT EXISTS synthetic_refs (ref_id INTEGER PRIMARY KEY, track_id INTEGER NOT NULL);"
    )
    try refConnection.exec("INSERT INTO synthetic_refs(ref_id, track_id) VALUES (7, \(trackID));")

    // Move in place into the DIFFERENT root with a NEW relative_path.
    let newURL = URL(fileURLWithPath: "/Music/E-dest/moved/move-dst.flac")
    let newRelativePath = "moved/move-dst.flac"
    try await store.moveTrack(
        id: trackID, newURL: newURL, newFolderID: destFolderID, newRelativePath: newRelativePath
    )

    guard let moved = try await store.track(id: trackID) else {
        printFail(number, "M6: track id \(trackID) vanished after moveTrack"); return false
    }
    guard moved.id == trackID else {
        printFail(number, "M6: moveTrack changed the stable id (\(moved.id) != \(trackID))"); return false
    }
    let movedFolder = String(describing: moved.folderID)
    guard moved.url == newURL, moved.folderID == destFolderID else {
        printFail(number, "M6: moveTrack did not update url/folder (\(moved.url), \(movedFolder))")
        return false
    }
    // The cross-folder fix: relative_path is the NEW value, NOT the stale old one.
    guard moved.relativePath == newRelativePath else {
        printFail(number, "M6: cross-folder move left relative_path '\(moved.relativePath)', "
            + "expected the new '\(newRelativePath)' (stale old path relative to the old root)"); return false
    }
    // The old url must be free now (the row moved, not copied).
    guard try await store.track(url: URL(fileURLWithPath: "/Music/E/sub/move-src.flac")) == nil else {
        printFail(number, "M6: old url still resolves — the move copied instead of moving"); return false
    }
    // The synthetic reference still resolves to the moved track (join on track_id).
    let joined = try refConnection.scalarInt(
        "SELECT t.id FROM synthetic_refs r JOIN tracks t ON t.id = r.track_id WHERE r.ref_id = 7;"
    )
    guard joined == trackID else {
        printFail(number, "M6: synthetic reference no longer resolves to the moved track "
            + "(\(String(describing: joined)) != \(trackID))"); return false
    }
    return true
}
