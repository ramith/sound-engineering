// ChecksRebindDrive — R1.1-B fix round: "Use this drive" keeps what it finds AS THE WALK AFTER IT SEES IT.
//   RB-6 THE DRIVE'S SPELLING AND SIGNATURE (break-it BI-P04 / BI-P07) — a copy whose folder and file names
//        differ only in letter case: every song is found, takes the drive's spelling and the file's own
//        (dev, inode); the walk after it sweeps nothing and keeps every id; a song renamed on the new drive
//        afterwards keeps its id through the move-match, as anywhere else. A song whose copy sits under a
//        linked folder (which a walk does not go into) counts as missing.
//   RB-7 THE REMOVED GO FIRST; ONLY A LOOSE ROW MERGES (review S1) — a folder pointed at a folder inside its
//        own old path: a song not found there is removed with its history before the found songs move, so it
//        is never merged into the song that takes its url; a row of ANOTHER music folder at a found song's
//        new url refuses the rebind, nothing written.

import Foundation
import GRDB
import LibraryScan
import LibraryStore

// MARK: - Registration

func rebindDriveCheckCases() -> [CheckCase] {
    [
        CheckCase(label: "rb6-rebind-drive-spelling-signature", run: checkRebindTakesDriveSpellingAndSignature),
        CheckCase(label: "rb7-rebind-removed-first-loose-merge-only", run: checkRebindRemovedFirstLooseOnly),
    ]
}

private let rb6Old = RootIdentity(dev: 81, inode: 810, volume: "RB6-OLD")
private let rb6New = RootIdentity(dev: 82, inode: 820, volume: "RB6-NEW")

/// `name` renamed to `newName` in `directory` — through a parked name, so a case-only rename takes on a
/// case-insensitive volume.
private func rename(_ name: String, to newName: String, in directory: URL) throws {
    let parked = directory.appendingPathComponent("\(newName).parked-\(UUID().uuidString)")
    try FileManager.default.moveItem(at: directory.appendingPathComponent(name), to: parked)
    try FileManager.default.moveItem(at: parked, to: directory.appendingPathComponent(newName))
}

/// The song at `url` in `store` — or a thrown error naming it.
private func song(_ store: LibraryStore, at url: URL) async throws -> LibraryTrack {
    guard let track = try await store.track(url: url) else {
        throw SQLiteError.internalError(message: "no song at \(url.path)")
    }
    return track
}

// MARK: - RB-6

func checkRebindTakesDriveSpellingAndSignature(number: Int, url: URL) async -> Bool {
    do {
        let base = try ScanFixtureBuilder.makeCaseRoot("rb6")
        let oldRoot = try ScanFixtureBuilder.makeDirectory(at: base, ["Old", "Music"])
        let files = [(["Album"], "01.flac", 11), (["Album"], "02.flac", 12), (["Linked"], "03.flac", 13)]
        for (subdirs, name, size) in files {
            try ScanFixtureBuilder.writeFile(at: oldRoot, subdirs: subdirs, fileName: name, byteCount: size)
        }
        let store = try await LibraryStore(url: url, appBuild: "verify")
        let folderID = try await store.addRoot(oldRoot)
        _ = try await LibraryScanner(rootIdentity: { _ in rb6Old }).scan(root: oldRoot, folderID: folderID, into: store)
        let one = try await song(store, at: oldRoot.appendingPathComponent("Album/01.flac")).id
        let two = try await song(store, at: oldRoot.appendingPathComponent("Album/02.flac")).id
        // The copy: "Album" spelled "ALBUM", "02.flac" spelled "02.FLAC"; "Linked" a link to a folder elsewhere.
        let newRoot = base.appendingPathComponent("New/Music", isDirectory: true)
        try FileManager.default.createDirectory(at: newRoot.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: oldRoot, to: newRoot)
        try rename("Album", to: "ALBUM", in: newRoot)
        try rename("02.flac", to: "02.FLAC", in: newRoot.appendingPathComponent("ALBUM"))
        let elsewhere = base.appendingPathComponent("Elsewhere", isDirectory: true)
        try FileManager.default.moveItem(at: newRoot.appendingPathComponent("Linked"), to: elsewhere)
        try FileManager.default.createSymbolicLink(at: newRoot.appendingPathComponent("Linked"),
                                                   withDestinationURL: elsewhere)
        try FileManager.default.removeItem(at: oldRoot)
        let outcome = try await RootRebinder(rootIdentity: { _ in rb6New }).rebind(folderID: folderID, to: newRoot,
                                                                                   in: store)
        guard outcome == .rebound(kept: 2, removed: 1) else {
            printFail(number, "RB-6: expected 2 found and the linked folder's song missing, got \(outcome)")
            return false
        }
        for (id, spelled) in [(one, "ALBUM/01.flac"), (two, "ALBUM/02.FLAC")] {
            let file = newRoot.appendingPathComponent(spelled)
            let signature = LibraryScanner.deviceInode(of: file)
            guard let kept = try await store.track(id: id),
                  PathNormalizer.normalizedString(for: kept.url) == PathNormalizer.normalizedString(for: file),
                  kept.dev == signature.dev, kept.inode == signature.inode else {
                printFail(number, "RB-6: song \(id) did not take the drive's spelling “\(spelled)” and its file's "
                    + "(dev, inode)"); return false
            }
        }
        guard try await walkAndRenameKeepIDs(store, folderID: folderID, newRoot: newRoot, ids: [one, two],
                                             number: number) else { return false }
        printPass(number, "RB-6 “Use this drive” on a copy spelled in other letter cases: each song found takes the "
            + "drive's spelling and its file's (dev, inode); the walk after it sweeps nothing and keeps every id; a "
            + "rename on the new drive keeps the song's id; a song under a linked folder (never walked) is missing")
        return true
    } catch {
        printFail(number, "RB-6 threw: \(error)"); return false
    }
}

/// The walk after the rebind keeps `ids` and sweeps nothing; a rename of the first song on the new drive,
/// then a walk, keeps its id (the S8.4 move-match).
private func walkAndRenameKeepIDs(_ store: LibraryStore, folderID: Int64, newRoot: URL, ids: [Int64],
                                  number: Int) async throws -> Bool {
    let scanner = LibraryScanner(rootIdentity: { _ in rb6New })
    let walk = try await scanner.scan(root: newRoot, folderID: folderID, into: store)
    guard walk.orphansSwept == 0, Set(walk.trackIDs) == Set(ids) else {
        printFail(number, "RB-6: the walk after the rebind swept \(walk.orphansSwept) or changed ids "
            + "(\(walk.trackIDs.sorted()) vs \(ids.sorted()))")
        return false
    }
    try rename("01.flac", to: "01 renamed.flac", in: newRoot.appendingPathComponent("ALBUM"))
    _ = try await scanner.scan(root: newRoot, folderID: folderID, into: store)
    guard try await store.track(id: ids[0])?.url.lastPathComponent == "01 renamed.flac" else {
        printFail(number, "RB-6: a song renamed on the new drive after the rebind lost its id"); return false
    }
    return true
}

// MARK: - RB-7

func checkRebindRemovedFirstLooseOnly(number: Int, url: URL) async -> Bool {
    do {
        let base = try ScanFixtureBuilder.makeCaseRoot("rb7")
        // Two copies of one file: K at "Live/1.flac", R at "Albums/Live/1.flac".
        let oldRoot = try ScanFixtureBuilder.makeDirectory(at: base, ["Music"])
        try ScanFixtureBuilder.writeFile(at: oldRoot, subdirs: ["Live"], fileName: "1.flac", byteCount: 10)
        try ScanFixtureBuilder.writeFile(at: oldRoot, subdirs: ["Albums", "Live"], fileName: "1.flac", byteCount: 10)
        let store = try await LibraryStore(url: url, appBuild: "verify")
        let folderID = try await store.addRoot(oldRoot)
        _ = try await LibraryScanner(rootIdentity: { _ in rb6Old }).scan(root: oldRoot, folderID: folderID, into: store)
        let kept = try await song(store, at: oldRoot.appendingPathComponent("Live/1.flac")).id
        let removed = try await song(store, at: oldRoot.appendingPathComponent("Albums/Live/1.flac")).id
        try await store.setUserState(trackID: kept, playCount: 3, loved: false, rating: nil)
        try await store.setUserState(trackID: removed, playCount: 7, loved: true, rating: 5)
        let playlist = try await store.createPlaylist(name: "Both")
        _ = try await store.appendEntries(playlistID: playlist, trackIDs: [kept, removed])
        // The user picks "Albums", inside the folder's own old path: K is found at Albums/Live/1.flac (R's file).
        let inside = oldRoot.appendingPathComponent("Albums", isDirectory: true)
        let outcome = try await RootRebinder(rootIdentity: { _ in rb6New }).rebind(folderID: folderID, to: inside,
                                                                                   in: store)
        let state = try await store.userState(trackID: kept)
        guard outcome == .rebound(kept: 1, removed: 1), try await store.track(id: removed) == nil,
              state?.playCount == 3, state?.loved == false, state?.rating == nil,
              try await store.entries(inPlaylist: playlist).map(\.trackID) == [kept] else {
            printFail(number, "RB-7: the removed song's history was merged into the kept one, or it survived "
                + "(\(outcome), kept \(String(describing: state)))")
            return false
        }
        guard try await anotherFolderAtTheURLRefuses(base: base, url: url.appendingPathExtension("b"), number: number)
        else { return false }
        printPass(number, "RB-7 a folder pointed inside its own old path: the song not found there is removed with "
            + "its plays, love, rating and playlist place before the found song takes its url — never merged into "
            + "it; a row of another music folder at a found song's new url refuses the rebind, nothing written")
        return true
    } catch {
        printFail(number, "RB-7 threw: \(error)"); return false
    }
}

/// A row of another music folder at a found song's new url refuses the rebind; nothing is written.
private func anotherFolderAtTheURLRefuses(base: URL, url: URL, number: Int) async throws -> Bool {
    let oldRoot = try ScanFixtureBuilder.makeDirectory(at: base, ["A", "Music"])
    try ScanFixtureBuilder.writeFile(at: oldRoot, subdirs: [], fileName: "x.flac", byteCount: 9)
    let store = try await LibraryStore(url: url, appBuild: "verify")
    let folderA = try await store.addRoot(oldRoot)
    _ = try await LibraryScanner(rootIdentity: { _ in rb6Old }).scan(root: oldRoot, folderID: folderA, into: store)
    let newRoot = try ScanFixtureBuilder.makeDirectory(at: base, ["A2", "Music"])
    try ScanFixtureBuilder.writeFile(at: newRoot, subdirs: [], fileName: "x.flac", byteCount: 9)
    // Folder B elsewhere holds a row whose url is the found song's new url (a legacy row, set by hand).
    let otherRoot = try ScanFixtureBuilder.makeDirectory(at: base, ["B"])
    try ScanFixtureBuilder.writeFile(at: otherRoot, subdirs: [], fileName: "y.flac", byteCount: 5)
    let folderB = try await store.addRoot(otherRoot)
    _ = try await LibraryScanner(rootIdentity: { _ in rb6Old }).scan(root: otherRoot, folderID: folderB, into: store)
    let foreign = try await song(store, at: otherRoot.appendingPathComponent("y.flac")).id
    try await store.moveTrack(id: foreign, newURL: newRoot.appendingPathComponent("x.flac"), newFolderID: folderB,
                              newRelativePath: "")
    let before = try storeRows(at: url)
    let outcome = try await RootRebinder(rootIdentity: { _ in rb6New }).rebind(folderID: folderA, to: newRoot,
                                                                               in: store)
    guard outcome == .refused(.overlapsFolder(id: folderB)), try storeRows(at: url) == before else {
        printFail(number, "RB-7: another folder's row at a found song's new url did not refuse the rebind with "
            + "nothing written: \(outcome)")
        return false
    }
    return true
}

/// Every folder and song row of the store file at `url`, as text.
private func storeRows(at url: URL) throws -> String {
    try DatabaseQueue(path: url.path).read { db in
        let folders = try Row.fetchAll(db, sql: "SELECT id, path, dev, inode, volume_uuid FROM folders ORDER BY id;")
        let songs = try Row.fetchAll(db, sql: "SELECT id, url, folder_id, dev, inode, play_count FROM tracks "
            + "ORDER BY id;")
        return "\(folders)|\(songs)"
    }
}
