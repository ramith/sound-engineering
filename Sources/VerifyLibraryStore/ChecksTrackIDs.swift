// ChecksTrackIDs — R1.1-B fix round (break-it BI-P01 / BI-P02): a song's id is never handed to another.
//   TID-1 ON A FRESH STORE — the newest song removed by each path that removes songs (a delete, a sweep,
//         Remove Folder, "Use this drive" not finding it), the next song added takes a new, never-seen id;
//         and a row inserted by any other path at a removed song's id is refused, so no caller can reuse one.
//   TID-2 THE v12 UPGRADE — a v11 store whose newest song left before the upgrade, while the queue's resume
//         record still names it, opens through the real open path with every user row kept; the next song
//         added takes an id above every id in use AND every id the record names; and the upgraded store
//         converges on a fresh install (the v12 objects are the only additions).

import Foundation
import GRDB
import LibraryScan
import LibraryStore

// MARK: - Registration

func trackIDCheckCases() -> [CheckCase] {
    [
        CheckCase(label: "tid1-track-ids-never-reused", run: checkTrackIDsNeverReused),
        CheckCase(label: "tid2-v12-track-ids-upgrade", run: checkTrackIDsUpgrade),
    ]
}

// MARK: - TID-1 — every removal path, then a new song

/// One new song at `path`, loose, as a scan writes it: its id.
private func addSong(_ store: LibraryStore, _ path: String, folderID: Int64? = nil) async throws -> Int64 {
    let file = makeScanned(path: path, name: (path as NSString).lastPathComponent, inode: nil)
    let ids = try await store.upsert([file], folderID: folderID, generation: store.beginScanGeneration())
    guard let id = ids.first else { throw SQLiteError.internalError(message: "TID: no id for \(path)") }
    return id
}

/// The ids a store handed out: each new song's must be one never seen.
private final class IDLedger {
    let store: LibraryStore
    private var used = Set<Int64>()

    init(_ store: LibraryStore) {
        self.store = store
    }

    /// Add a song at `path`; its id — thrown as a failure when the store handed out a used one.
    @discardableResult
    func fresh(_ path: String, folderID: Int64? = nil, after removal: String) async throws -> Int64 {
        let id = try await addSong(store, path, folderID: folderID)
        guard used.insert(id).inserted else {
            throw SQLiteError.internalError(message: "after \(removal), a new song took the used id \(id)")
        }
        return id
    }

    /// Fail unless the song `id` is gone.
    func expectGone(_ id: Int64, after removal: String) async throws {
        guard try await store.track(id: id) == nil else {
            throw SQLiteError.internalError(message: "\(removal) did not remove song \(id)")
        }
    }
}

func checkTrackIDsNeverReused(number: Int, url: URL) async -> Bool {
    do {
        let ledger = try await IDLedger(LibraryStore(url: url, appBuild: "verify"))
        let store = ledger.store
        for index in 1 ... 3 {
            try await ledger.fresh("/tid1/\(index).flac", after: "the start")
        }
        try await store.delete(id: 3) // a delete of the newest song
        let afterDelete = try await ledger.fresh("/tid1/after-delete.flac", after: "a delete")
        let folder = try await store.addRoot(URL(fileURLWithPath: "/tid1/Folder"))
        let swept = try await ledger.fresh("/tid1/Folder/a.flac", folderID: folder, after: "a delete")
        _ = try await store.sweepOrphans(inFolders: [folder], olderThan: store.beginScanGeneration())
        try await ledger.expectGone(swept, after: "a sweep")
        let afterSweep = try await ledger.fresh("/tid1/after-sweep.flac", after: "a sweep")
        let removed = try await store.addRoot(URL(fileURLWithPath: "/tid1/Removed"))
        let gone = try await ledger.fresh("/tid1/Removed/b.flac", folderID: removed, after: "a sweep")
        try await store.removeRoot(id: removed) // Remove Folder, its newest song in no playlist
        try await ledger.expectGone(gone, after: "Remove Folder")
        let afterRemove = try await ledger.fresh("/tid1/after-remove.flac", after: "Remove Folder")
        try await rebindRemovesTheNewest(ledger)
        // Any other path: a raw insert at a removed song's id is refused.
        guard await rawInsertIsRefused(at: url, id: gone) else {
            printFail(number, "TID-1: a raw insert at a removed song's id \(gone) was accepted"); return false
        }
        printPass(number, "TID-1 a removed song's id is never handed to another: after a delete, a sweep, Remove "
            + "Folder and a rebind took the newest song, each new song took a never-seen id (\(afterDelete), "
            + "\(afterSweep), \(afterRemove), …); a raw insert at a removed song's id is refused")
        return true
    } catch {
        printFail(number, "TID-1: \(error)"); return false
    }
}

/// "Use this drive" removing the folder's newest song (not on the new drive): the next song takes a new id.
private func rebindRemovesTheNewest(_ ledger: IDLedger) async throws {
    let base = testDataDirectory.appendingPathComponent("tid1-\(runIdentifier)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: base) }
    let newRoot = base.appendingPathComponent("New", isDirectory: true)
    try FileManager.default.createDirectory(at: newRoot, withIntermediateDirectories: true)
    FileManager.default.createFile(atPath: newRoot.appendingPathComponent("kept.flac").path,
                                   contents: Data(count: 4096))
    let folder = try await ledger.store.addRoot(URL(fileURLWithPath: "/tid1/Old"))
    try await ledger.fresh("/tid1/Old/kept.flac", folderID: folder, after: "Remove Folder")
    let left = try await ledger.fresh("/tid1/Old/left.flac", folderID: folder, after: "Remove Folder")
    let identity = RootIdentity(dev: 1, inode: 2, volume: "TID-NEW")
    let outcome = try await RootRebinder { _ in identity }.rebind(folderID: folder, to: newRoot, in: ledger.store)
    guard outcome == .rebound(kept: 1, removed: 1) else {
        throw SQLiteError.internalError(message: "the rebind did not keep 1 and remove 1: \(outcome)")
    }
    try await ledger.expectGone(left, after: "a rebind")
    try await ledger.fresh("/tid1/after-rebind.flac", after: "a rebind")
}

/// Whether a `tracks` row inserted directly — not through the store — at `id` is refused.
private func rawInsertIsRefused(at url: URL, id: Int64) async -> Bool {
    do {
        let queue = try DatabaseQueue(path: url.path)
        try await queue.write { db in
            try db.execute(sql: """
            INSERT INTO tracks(id, url, relative_path, name, format, file_size, mtime, date_added)
            VALUES (?, '/tid1/raw.flac', '', 'raw', 'FLAC', 1, 1, 1);
            """, arguments: [id])
        }
        return false
    } catch {
        return true
    }
}

// MARK: - TID-2 — the v11 → v12 upgrade

/// A v11 store at `url`: songs 1–4, song 4 gone since (its id the highest ever used), song 2 in a user
/// playlist, played and loved; the queue's resume record names songs 2 and 4 and a loose file.
private func seedV11Store(at url: URL) throws {
    let queue = try DatabaseQueue(path: url.path)
    try migrator(through: 11).migrate(queue)
    try queue.write { db in
        for index in 1 ... 4 {
            try db.execute(sql: """
            INSERT INTO tracks(id, url, relative_path, name, format, file_size, mtime, date_added, last_seen_scan,
                               play_count, loved)
            VALUES (?, ?, '', ?, 'FLAC', 8, 1, 1, 1, ?, ?);
            """, arguments: [index, "/tid2/\(index).flac", "song \(index)", index == 2 ? 5 : 0, index == 2])
        }
        try db.execute(sql: "DELETE FROM tracks WHERE id = 4;")
        try db.execute(sql: "INSERT INTO playlists(name, is_builtin, created_at) VALUES ('Kept', 0, 1);")
        try db.execute(
            sql: "INSERT INTO playlist_entries(playlist_id, track_id, position, added_at) VALUES (?, 2, 0, 1);",
            arguments: [db.lastInsertedRowID]
        )
        let record = #"{"format":1,"slots":[{"track":{"id":2}},{"loose":{"path":"/x.flac"}},{"track":{"id":4}}],"#
            + #""cursor":2}"#
        try db.execute(sql: "INSERT INTO queue_state(id, revision, record, written_at) VALUES (1, 1, ?, 1);",
                       arguments: [record])
    }
}

func checkTrackIDsUpgrade(number: Int, url: URL) async -> Bool {
    do {
        try seedV11Store(at: url)
        let store = try await LibraryStore(url: url, appBuild: "verify")
        let kept = try await store.playlists().first { $0.name == "Kept" }
        let played = try await store.userState(trackID: 2)
        guard await store.schemaVersion() == currentSchemaVersion, let kept,
              try await store.entries(inPlaylist: kept.id).map(\.trackID) == [2],
              played?.playCount == 5, played?.loved == true, try await store.queueState()?.revision == 1 else {
            printFail(number, "TID-2: the upgrade lost user data (a playlist, play history or the queue record)")
            return false
        }
        let newcomer = try await addSong(store, "/tid2/new.flac")
        guard newcomer == 5 else {
            printFail(number, "TID-2: after the upgrade the next song took id \(newcomer); the record names id 4, "
                + "gone before the upgrade — the next id is 5")
            return false
        }
        guard let added = try v11UpgradeConverges(),
              Set(added).isSuperset(of: ["track_id_high_water", "tracks_id_high_water", "tracks_id_never_reused"])
        else {
            printFail(number, "TID-2: a v11 store upgraded does not converge on a fresh install, changed a v11 "
                + "object, or lacks the v12 objects")
            return false
        }
        printPass(number, "TID-2 the v12 upgrade: a v11 store whose newest song left while the queue's record "
            + "still names it reaches v\(currentSchemaVersion) with every user row kept; the next song takes id 5, "
            + "above every id in use and named; the upgraded schema converges on a fresh install")
        return true
    } catch {
        printFail(number, "TID-2 threw: \(error)"); return false
    }
}

/// The names of the objects a v11 store gains by its upgrade — nil when the upgrade changed or dropped a v11
/// object, or the upgraded schema differs from a fresh install's.
private func v11UpgradeConverges() throws -> [String]? {
    let upgraded = try DatabaseQueue()
    try migrator(through: 11).migrate(upgraded)
    let before = try Set(upgraded.read { db in try schemaFingerprint(db) }.split(separator: "\n"))
    try fullMigrator().migrate(upgraded)
    let after = try upgraded.read { db in try schemaFingerprint(db) }
    let fresh = try DatabaseQueue()
    try fullMigrator().migrate(fresh)
    let afterLines = Set(after.split(separator: "\n"))
    let freshSchema = try fresh.read { db in try schemaFingerprint(db) }
    guard after == freshSchema, before.isSubset(of: afterLines) else { return nil }
    return afterLines.subtracting(before).map { String($0.split(separator: "|")[1]) }
}
