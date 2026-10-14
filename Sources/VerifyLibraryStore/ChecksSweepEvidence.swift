// ChecksSweepEvidence — R1 (council P5A-01/02): a sweep deletes only songs POSITIVELY known to be gone.
// Companion to ChecksScanEdge (the empty-walk guard + a vanished root) and ChecksReachability
// (`restampRoot`); LibraryBrowseKitTests' SweepEvidenceTests hold the panel's reproductions (an
// unreadable subfolder, a drive gone mid-walk, another drive at the root's path, a genuine delete).
//   SE-1 the root CHANGES under the walk — another drive at its path, gone from it, or another
//        directory there — and the sweep is refused, whatever the walk saw;
//   SE-2 a walk is evidence of what it READ (R1.1-A, council C-55): a subfolder it may not open keeps
//        its songs while a song deleted elsewhere in the folder is swept and a new one admitted (no
//        refusal, so the tag pass runs); a folder it cannot open at all refuses its sweep, every song
//        kept; readable again, the complete walk reaps nothing that is there;
//   SE-3 the v7 → v8 upgrade adds `folders.volume_uuid` NULL with every root and all user data kept;
//        the root's next walk binds it, and a walk on another drive is refused;
//   SE-4 an upgraded (unbound) root whose path holds none of its songs — another drive with the same
//        name, a stale folder — is not walked, bound or swept, the second time too; its own drive back,
//        it binds (the breaker's ATK-6b/6c).
// The drive is the walk's seam (`LibraryScanner(rootIdentity:)`): no disk image is mounted.

import Foundation
import GRDB
import LibraryScan
import LibraryStore

// MARK: - Registration

func sweepEvidenceCheckCases() -> [CheckCase] {
    [
        CheckCase(label: "se1-root-changes-under-walk", run: checkRootChangesUnderWalk),
        CheckCase(label: "se2-evidence-of-what-it-read", run: checkEvidenceOfWhatItRead),
        CheckCase(label: "se3-v8-root-volume-upgrade", run: checkRootVolumeUpgrade),
        CheckCase(label: "se4-unbound-root-unrecognized", run: checkUnboundRootUnrecognized),
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
private let driveA = RootIdentity(dev: 41, inode: 410, volume: "VOL-A")

// MARK: - SE-1 — the root changes under the walk

/// What is at the root's path when the walk ends, and the refusal it must draw.
private struct RootChange {
    let name: String
    let identity: RootIdentity?
    let reason: SweepRefusal.Reason
}

func checkRootChangesUnderWalk(number: Int, url: URL) async -> Bool {
    let changes = [
        RootChange(name: "another drive at its path", identity: RootIdentity(dev: 41, inode: 410, volume: "VOL-B"),
                   reason: .differentVolume),
        RootChange(name: "gone from its path", identity: nil, reason: .rootVanished),
        RootChange(name: "another directory there", identity: RootIdentity(dev: 42, inode: 410, volume: "VOL-A"),
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

// MARK: - SE-2 — a walk is evidence of what it read (C-55)

func checkEvidenceOfWhatItRead(number: Int, url: URL) async -> Bool {
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
        let locked = try ScanFixtureBuilder.makeDirectory(at: root, ["#recycle"])
        let kept = try ScanFixtureBuilder.writeFile(at: locked, fileName: "kept.flac")
        let folderID = try await store.addRoot(root)
        _ = try await LibraryScanner().scan(root: root, folderID: folderID, into: store)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked.path)
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: root.path)
        }
        // A subfolder the walk may not open; meanwhile one song is deleted and one added elsewhere.
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: locked.path)
        try FileManager.default.removeItem(at: songs[0])
        let added = try ScanFixtureBuilder.writeFile(at: root, subdirs: ["A"], fileName: "new.flac")
        let scoped = try await LibraryScanner().scan(root: root, folderID: folderID, into: store)
        guard scoped.orphansSwept == 1, try await store.track(url: songs[0]) == nil,
              try await store.track(url: kept) != nil, try await store.track(url: added) != nil else {
            printFail(number, "SE-2: beside an unreadable subfolder the walk swept \(scoped.orphansSwept) "
                + "(expected the 1 delete), or lost the subfolder's song, or missed the new one")
            return false
        }
        // The folder itself unreadable: the walk is evidence of nothing — refused, every song kept.
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: root.path)
        do {
            _ = try await LibraryScanner().scan(root: root, folderID: folderID, into: store)
            printFail(number, "SE-2: a walk of a folder it could not open was not refused"); return false
        } catch let refusal as SweepRefusal where refusal.reason == .incompleteWalk {}
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: root.path)
        guard try await store.trackCount(inFolder: folderID) == 4 else {
            printFail(number, "SE-2: the refused walk of an unreadable folder lost rows"); return false
        }
        // Readable again: the complete walk reaps nothing that is there.
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked.path)
        let complete = try await LibraryScanner().scan(root: root, folderID: folderID, into: store)
        guard complete.orphansSwept == 0, try await store.trackCount(inFolder: folderID) == 4 else {
            printFail(number, "SE-2: the complete walk swept \(complete.orphansSwept), expected 0"); return false
        }
        printPass(number, "SE-2 a walk is evidence of what it read (C-55): beside a subfolder it may not open "
            + "it sweeps the 1 song deleted elsewhere, admits the new one and keeps the subfolder's song (no "
            + "refusal); a folder it cannot open at all refuses (.incompleteWalk), every song kept; readable "
            + "again, nothing that is there is swept")
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
        guard try boundVolumes(at: url) == [driveA.volume] else {
            printFail(number, "SE-3: the root's first walk after the upgrade did not bind it"); return false
        }
        let driveB = DriveAtRoot(RootIdentity(dev: 41, inode: 410, volume: "VOL-B"))
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

// MARK: - SE-4 — an unbound root whose path holds none of its songs

func checkUnboundRootUnrecognized(number: Int, url: URL) async -> Bool {
    do {
        let root = try ScanFixtureBuilder.makeCaseRoot("se4")
        let song = try ScanFixtureBuilder.writeFile(at: root, subdirs: ["Album"], fileName: "kept.flac")
        let trackID = try seedV7Store(at: url, root: root, song: song)
        let store = try await LibraryStore(url: url, appBuild: "verify")
        guard let folderID = try await store.roots().first?.id else {
            printFail(number, "SE-4: the upgraded store has no root"); return false
        }
        // Its drive is away; another drive with the same name is at the path, holding other songs.
        let away = root.deletingLastPathComponent().appendingPathComponent("se4-away-\(UUID().uuidString)")
        try FileManager.default.moveItem(at: root.appendingPathComponent("Album"), to: away)
        let other = try ScanFixtureBuilder.writeFile(at: root, subdirs: ["Album"], fileName: "other.flac")
        let driveB = DriveAtRoot(RootIdentity(dev: 41, inode: 410, volume: "VOL-B"))
        for walk in 1 ... 2 {
            do {
                _ = try await driveB.scanner.scan(root: root, folderID: folderID, into: store)
                printFail(number, "SE-4: walk \(walk) of another drive at an unbound root's path was not refused")
                return false
            } catch let refusal as SweepRefusal where refusal.reason == .unrecognizedFolder {}
        }
        guard try boundVolumes(at: url) == [nil], try await store.track(url: other) == nil,
              try await store.userState(trackID: trackID)?.playCount == 3 else {
            printFail(number, "SE-4: the other drive was walked or bound, or the root's song lost its data")
            return false
        }
        // Its own drive is back: recognized, bound, nothing swept.
        try FileManager.default.removeItem(at: root.appendingPathComponent("Album"))
        try FileManager.default.moveItem(at: away, to: root.appendingPathComponent("Album"))
        let back = try await DriveAtRoot(driveA).scanner.scan(root: root, folderID: folderID, into: store)
        guard back.orphansSwept == 0, try boundVolumes(at: url) == [driveA.volume] else {
            printFail(number, "SE-4: the root's own drive, back, was swept or not bound"); return false
        }
        printPass(number, "SE-4 an upgraded root, still unbound, whose path holds none of its songs (another "
            + "drive with the same name) is refused (.unrecognizedFolder) twice — not walked, not bound, its "
            + "song's play count kept; its own drive back, the walk binds it and sweeps nothing")
        return true
    } catch {
        printFail(number, "SE-4 threw: \(error)"); return false
    }
}
