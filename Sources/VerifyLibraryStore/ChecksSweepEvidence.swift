// ChecksSweepEvidence — R1 (council P5A-01/02): a sweep deletes only songs POSITIVELY known to be gone.
// Companion to ChecksScanEdge (the empty-walk guard + a vanished root) and ChecksReachability
// (`restampRoot`); LibraryBrowseKitTests' SweepEvidenceTests hold the panel's reproductions (an
// unreadable subfolder, a drive gone mid-walk, another drive at the root's path, a genuine delete).
//   SE-1 the root CHANGES under the walk — another drive at its path, gone from it, or another
//        directory there — and the sweep is refused, whatever the walk saw;
//   SE-2 an INCOMPLETE walk refuses its sweep only when the sweep would delete something: a folder
//        that was never readable does not stop new songs (nor block them on a refusal), a song deleted
//        while part of the folder is unreadable is kept, and the walk that reads it all reaps it;
//   SE-3 the v7 → v8 upgrade adds `folders.volume_uuid` NULL with every root and all user data kept;
//        the root's next walk binds it, and a walk on another drive is refused.
// The drive is the walk's seam (`LibraryScanner(rootIdentity:)`): no disk image is mounted.

import Foundation
import GRDB
import LibraryScan
import LibraryStore

// MARK: - Registration

func sweepEvidenceCheckCases() -> [CheckCase] {
    [
        CheckCase(label: "se1-root-changes-under-walk", run: checkRootChangesUnderWalk),
        CheckCase(label: "se2-incomplete-walk-refuses-only-a-deletion", run: checkIncompleteWalkRefusesOnlyADeletion),
        CheckCase(label: "se3-v8-root-volume-upgrade", run: checkRootVolumeUpgrade),
    ]
}

// MARK: - The drive at the root (the walk's seam)

/// What a walk reads at its root's path: an identity the check sets, and can change mid-walk.
private final class DriveAtRoot: @unchecked Sendable {
    private let lock = NSLock()
    private var current: RootIdentity?

    init(_ identity: RootIdentity?) {
        current = identity
    }

    func change(to identity: RootIdentity?) {
        lock.withLock { current = identity }
    }

    /// A scanner that reads this drive at its root.
    var scanner: LibraryScanner {
        LibraryScanner(rootIdentity: { _ in self.lock.withLock { self.current } })
    }
}

/// Drive A's root directory.
private let driveA = RootIdentity(dev: 41, inode: 410, volumeUUID: "VOL-A")

// MARK: - SE-1 — the root changes under the walk

/// What is at the root's path when the walk ends, and the refusal it must draw.
private struct RootChange {
    let name: String
    let identity: RootIdentity?
    let reason: SweepRefusal.Reason
}

func checkRootChangesUnderWalk(number: Int, url: URL) async -> Bool {
    let changes = [
        RootChange(name: "another drive at its path", identity: RootIdentity(dev: 41, inode: 410, volumeUUID: "VOL-B"),
                   reason: .differentVolume),
        RootChange(name: "gone from its path", identity: nil, reason: .rootVanished),
        RootChange(name: "another directory there", identity: RootIdentity(dev: 42, inode: 410, volumeUUID: "VOL-A"),
                   reason: .rootVanished),
    ]
    do {
        let store = try await LibraryStore(url: url, appBuild: "verify")
        for (index, change) in changes.enumerated() {
            let root = try ScanFixtureBuilder.makeCaseRoot("se1-\(index)")
            for file in 0 ..< 300 { // > one 256-file batch, so the change lands mid-walk
                _ = try ScanFixtureBuilder.writeFile(at: root, subdirs: ["d\(file / 30)"], fileName: "t\(file).flac")
            }
            let folderID = try await store.addRoot(root)
            let drive = DriveAtRoot(driveA)
            _ = try await drive.scanner.scan(root: root, folderID: folderID, into: store)
            try FileManager.default.removeItem(at: root.appendingPathComponent("d0")) // a delete it would sweep
            do {
                _ = try await drive.scanner.scan(root: root, folderID: folderID, into: store,
                                                 progress: { _ in drive.change(to: change.identity) })
                printFail(number, "SE-1: a root \(change.name) mid-walk was swept"); return false
            } catch let refusal as SweepRefusal where refusal.reason == change.reason {}
            guard try await store.trackCount(inFolder: folderID) == 300 else {
                printFail(number, "SE-1: a root \(change.name) mid-walk lost rows"); return false
            }
        }
        printPass(number, "SE-1 a root that changes under its walk — another drive at its path, gone from it, "
            + "or another directory there — refuses the sweep (.differentVolume / .rootVanished), even of a "
            + "song deleted before the walk: the walk is evidence only of the root it began on")
        return true
    } catch {
        printFail(number, "SE-1 threw: \(error)"); return false
    }
}

// MARK: - SE-2 — an incomplete walk refuses only a deletion

func checkIncompleteWalkRefusesOnlyADeletion(number: Int, url: URL) async -> Bool {
    guard getuid() != 0 else {
        printPass(number, "SE-2 skipped: running as root, a chmod 000 folder is still readable")
        return true
    }
    do {
        let store = try await LibraryStore(url: url, appBuild: "verify")
        let root = try ScanFixtureBuilder.makeCaseRoot("se2")
        let songs = try (0 ..< 3).map {
            try ScanFixtureBuilder.writeFile(at: root, subdirs: ["A"], fileName: "a\($0).flac")
        }
        let folderID = try await store.addRoot(root)
        _ = try await LibraryScanner().scan(root: root, folderID: folderID, into: store)
        // A folder the walk may not open arrives with a new song elsewhere: nothing would be deleted.
        let locked = try ScanFixtureBuilder.makeDirectory(at: root, ["Locked"])
        _ = try ScanFixtureBuilder.writeFile(at: locked, fileName: "hidden.flac")
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: locked.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked.path) }
        let added = try ScanFixtureBuilder.writeFile(at: root, subdirs: ["A"], fileName: "new.flac")
        let quiet = try await LibraryScanner().scan(root: root, folderID: folderID, into: store)
        guard quiet.orphansSwept == 0, try await store.track(url: added) != nil else {
            printFail(number, "SE-2: an incomplete walk with nothing unseen did not end as usual"); return false
        }
        // A genuine delete while the folder is still unreadable: kept, the sweep refused.
        try FileManager.default.removeItem(at: songs[0])
        do {
            _ = try await LibraryScanner().scan(root: root, folderID: folderID, into: store)
            printFail(number, "SE-2: an incomplete walk swept"); return false
        } catch let refusal as SweepRefusal where refusal.reason == .incompleteWalk {}
        guard try await store.track(url: songs[0]) != nil else {
            printFail(number, "SE-2: an incomplete walk's refusal still lost the deleted song's row"); return false
        }
        // Readable again: the complete walk reaps exactly the delete.
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked.path)
        let complete = try await LibraryScanner().scan(root: root, folderID: folderID, into: store)
        guard complete.orphansSwept == 1, try await store.track(url: songs[0]) == nil else {
            printFail(number, "SE-2: the complete walk swept \(complete.orphansSwept), expected the 1 delete")
            return false
        }
        printPass(number, "SE-2 an incomplete walk (a folder it may not open) refuses its sweep only when the "
            + "sweep would delete something: with nothing unseen it ends as usual and admits the new song; a "
            + "song deleted meanwhile is kept (.incompleteWalk); the walk that reads it all reaps exactly it")
        return true
    } catch {
        printFail(number, "SE-2 threw: \(error)"); return false
    }
}

// MARK: - SE-3 — the v7 → v8 upgrade, then the binding

/// A v7 (previous-release) store at `url` whose root is `root`, holding `song` — played 3 times and in
/// a user playlist. Returns the song's row id.
private func seedV7Store(at url: URL, root: URL, song: URL) throws -> Int64 {
    guard let file = LibraryScanner.makeScannedFile(fileURL: song, root: root) else {
        throw SQLiteError.internalError(message: "SE-3: the fixture song is not admitted")
    }
    let queue = try DatabaseQueue(path: url.path)
    try migrator(through: 7).migrate(queue)
    return try queue.write { db in
        try db.execute(sql: "INSERT INTO folders(path, is_root, dev, inode) VALUES (?, 1, 7, 70);",
                       arguments: [PathNormalizer.normalizedString(for: root)])
        let folderID = db.lastInsertedRowID
        try db.execute(sql: """
        INSERT INTO tracks(url, folder_id, relative_path, name, format, file_size, mtime, date_added,
                           last_seen_scan, play_count)
        VALUES (?, ?, ?, ?, ?, ?, ?, 1, 1, 3);
        """, arguments: [PathNormalizer.normalizedString(for: song), folderID, file.relativePath, file.name,
                         file.format, file.fileSize, file.mtime])
        let trackID = db.lastInsertedRowID
        try db.execute(sql: "INSERT INTO playlists(name, is_builtin, created_at) VALUES ('Kept', 0, 1);")
        try db.execute(
            sql: "INSERT INTO playlist_entries(playlist_id, track_id, position, added_at) VALUES (?, ?, 0, 1);",
            arguments: [db.lastInsertedRowID, trackID]
        )
        return trackID
    }
}

/// The bound volume of every root in the store file at `url` (NULL → nil), read on its own connection.
private func boundVolumes(at url: URL) throws -> [String?] {
    try DatabaseQueue(path: url.path).read { db in
        try String?.fetchAll(db, sql: "SELECT volume_uuid FROM folders WHERE is_root = 1;")
    }
}

func checkRootVolumeUpgrade(number: Int, url: URL) async -> Bool {
    do {
        let root = try ScanFixtureBuilder.makeCaseRoot("se3")
        let song = try ScanFixtureBuilder.writeFile(at: root, subdirs: ["Album"], fileName: "kept.flac")
        let trackID = try seedV7Store(at: url, root: root, song: song)
        let store = try await LibraryStore(url: url, appBuild: "verify")
        guard await store.schemaVersion() == currentSchemaVersion, try boundVolumes(at: url) == [nil],
              try await store.userState(trackID: trackID)?.playCount == 3,
              let folderID = try await store.roots().first?.id else {
            printFail(number, "SE-3: the v7 store did not upgrade with its root unbound and its data kept")
            return false
        }
        // The root's next walk binds it; a walk on another drive is refused, the song and its entry kept.
        _ = try await DriveAtRoot(driveA).scanner.scan(root: root, folderID: folderID, into: store)
        guard try boundVolumes(at: url) == [driveA.volumeUUID] else {
            printFail(number, "SE-3: the root's first walk after the upgrade did not bind it"); return false
        }
        let driveB = DriveAtRoot(RootIdentity(dev: 41, inode: 410, volumeUUID: "VOL-B"))
        do {
            _ = try await driveB.scanner.scan(root: root, folderID: folderID, into: store)
            printFail(number, "SE-3: a walk on another drive was not refused"); return false
        } catch let refusal as SweepRefusal where refusal.reason == .differentVolume {}
        let playlist = try await store.playlists().first { !$0.isBuiltin }?.id ?? -1
        guard try await store.entries(inPlaylist: playlist).map(\.trackID) == [trackID],
              try await store.userState(trackID: trackID)?.playCount == 3 else {
            printFail(number, "SE-3: user data changed across the upgrade and the walks"); return false
        }
        printPass(number, "SE-3 a v7 store upgrades to v\(currentSchemaVersion): folders.volume_uuid is added "
            + "NULL, the root and its song's play count + playlist entry are kept; the root's next walk binds "
            + "its drive, and a walk on another drive is refused (.differentVolume) with the data intact")
        return true
    } catch {
        printFail(number, "SE-3 threw: \(error)"); return false
    }
}
