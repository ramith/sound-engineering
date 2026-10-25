// ChecksRebind — R1.1-B, US-R1F-03 (LIB-VOL-1), seam S4: "Use this drive" — a paused music folder re-rooted
// on the drive that now holds its songs, by each song's path under the folder (+ its size). The founder's
// rule (2026-10-25): silently; the songs found keep their ids and all their user data; the songs not found
// are removed with their history; refused — nothing written — when none is found.
//   RB-1 a copy on a new drive, at a new mount path ("T7 1"), holding 8 of the folder's 10 songs: the 8 keep
//        their ids, plays, loves, ratings, frecency and playlist places; the 2 are removed with their
//        entries and index rows, in the one transaction; the folder is bound to the new drive; the queue's
//        slots re-resolve by track id to the new paths; the walk after it is evidence and sweeps nothing;
//   RB-2 refused, nothing written: a drive holding none of the songs, one whose copies were all re-tagged
//        (another size), a folder that is not there;
//   RB-3 refused, nothing written: the new location is another music folder, inside one, or holds one;
//   RB-4 the same path on a new drive (`.differentVolume`) keeps every id; a folder row below the music
//        folder moves with it; an untagged album (keyed by its folder's path) regroups under the new path
//        with its songs and their user data; a song stored composed (NFC) is found where the drive spells
//        its name and its folder's decomposed (NFD); a song the library already held loose at a found
//        song's new path (added to a playlist while the folder was paused) merges into it;
//   RB-5 a kill mid-rebind leaves the before state or the after state — a child process re-binding a
//        large folder is killed (SIGKILL) at random points, and every store it leaves is one or the other.

import Foundation
import GRDB
import LibraryScan
import LibraryStore

// MARK: - Registration

func rebindCheckCases() -> [CheckCase] {
    [
        CheckCase(label: "rb1-use-this-drive-80-percent", run: checkRebindKeepsFoundRemovesMissing),
        CheckCase(label: "rb2-rebind-refused-none-found", run: checkRebindRefusedWhenNoneFound),
        CheckCase(label: "rb3-rebind-refused-overlap", run: checkRebindRefusedOnOverlap),
        CheckCase(label: "rb4-rebind-same-path-descendants-albums-nfd", run: checkRebindSamePathAndShapes),
        CheckCase(label: "rb5-rebind-kill-before-or-after", run: checkRebindKillLeavesBeforeOrAfter),
    ]
}

// MARK: - The fixture: a music folder on the old drive, and a copy on the new one

/// The old drive and the new one, as a walk and a rebind read them (the scanner's identity seam).
private let oldDrive = RootIdentity(dev: 71, inode: 710, volume: "VOL-OLD")
private let newDrive = RootIdentity(dev: 72, inode: 720, volume: "VOL-NEW")

/// A music folder of `count` songs ("Album N/NN Song.flac", 4 per untagged album) on the old drive, scanned
/// into a store at `url`, each song tagged with its album, played, loved, rated, in a user playlist and in
/// the queue. Returns the folder.
private struct RebindLibrary {
    let store: LibraryStore
    let base: URL
    let oldRoot: URL
    let folderID: Int64
    /// The songs' ids, in path order.
    let ids: [Int64]
    /// Each song's path under the folder, in path order.
    let paths: [String]
    let playlistID: Int64
    let queueID: Int64

    static func make(_ label: String, at url: URL, count: Int, volumeName: String = "T7") async throws -> Self {
        let base = try ScanFixtureBuilder.makeCaseRoot(label)
        let oldRoot = try ScanFixtureBuilder.makeDirectory(at: base, [volumeName, "Music"])
        var paths: [String] = []
        for index in 0 ..< count {
            let album = "Album \(index / 4)"
            let name = String(format: "%02d Song.flac", index)
            try ScanFixtureBuilder.writeFile(at: oldRoot, subdirs: [album], fileName: name, byteCount: 8 + index)
            paths.append("\(album)/\(name)")
        }
        let store = try await LibraryStore(url: url, appBuild: "verify")
        let folderID = try await store.addRoot(oldRoot)
        _ = try await LibraryScanner(rootIdentity: { _ in oldDrive }).scan(root: oldRoot, folderID: folderID,
                                                                           into: store)
        var ids: [Int64] = []
        for path in paths {
            let id = try await requireTrack(store, at: oldRoot.appendingPathComponent(path))
            ids.append(id)
            let album = String(path.prefix { $0 != "/" })
            try await store.applyMetadata(TrackMetadata(title: "Song \(ids.count)", albumTitle: album), forTrack: id)
            try await store.incrementPlayCount(id: id, playedAt: 1_760_000_000 + Int64(ids.count))
            try await store.setUserState(trackID: id, playCount: Int64(ids.count + 5), loved: ids.count % 2 == 0,
                                         rating: Int64(ids.count % 5 + 1))
        }
        let playlistID = try await store.createPlaylist(name: "Road")
        _ = try await store.appendEntries(playlistID: playlistID, trackIDs: ids)
        let queueID = try await store.currentPlaylistID()
        try await store.replaceEntries(playlistID: queueID, trackIDs: ids.reversed())
        return RebindLibrary(store: store, base: base, oldRoot: oldRoot, folderID: folderID, ids: ids, paths: paths,
                             playlistID: playlistID, queueID: queueID)
    }

    /// The folder copied to `volumeName`/Music on the new drive, less the songs at `missing` indexes.
    func copy(to volumeName: String, missing: Set<Int> = []) throws -> URL {
        let newRoot = base.appendingPathComponent(volumeName).appendingPathComponent("Music")
        try FileManager.default.createDirectory(at: newRoot.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: oldRoot, to: newRoot)
        for index in missing {
            try FileManager.default.removeItem(at: newRoot.appendingPathComponent(paths[index]))
        }
        return newRoot
    }

    /// A rebinder that reads `drive` at `newRoot` and nothing anywhere else (the old drive is gone).
    func rebinder(_ drive: RootIdentity = newDrive, at newRoot: URL) -> RootRebinder {
        let key = PathNormalizer.normalizedString(for: newRoot)
        return RootRebinder(rootIdentity: { url in PathNormalizer.normalizedString(for: url) == key ? drive : nil })
    }
}

/// The id of the song the store holds at `url`.
private func requireTrack(_ store: LibraryStore, at url: URL) async throws -> Int64 {
    guard let id = try await store.track(url: url)?.id else { throw RebindCheckError("no song at \(url.path)") }
    return id
}

private struct RebindCheckError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) {
        self.description = description
    }
}

/// Everything a rebind may change, read off the store file at `url` on its own connection: the folder rows,
/// every song's id, url, user data and album title, every playlist entry, the index's rows. Two stores in
/// the same state read the same.
private func rebindState(at url: URL) throws -> String {
    try DatabaseQueue(path: url.path).read { db in
        let folders = try Row.fetchAll(db, sql: "SELECT id, path, volume_uuid FROM folders ORDER BY id;")
        let songs = try Row.fetchAll(db, sql: """
        SELECT t.id, t.url, t.play_count, t.loved, t.rating, t.last_played, t.frecency_rank, al.title
        FROM tracks t LEFT JOIN albums al ON al.id = t.album_id ORDER BY t.id;
        """)
        let entries = try Row.fetchAll(db, sql: "SELECT playlist_id, track_id, position FROM playlist_entries "
            + "ORDER BY playlist_id, position;")
        let indexed = try Int.fetchOne(db, sql: "SELECT count(*) FROM tracks_fts;") ?? -1
        return "\(folders)|\(songs)|\(entries)|\(indexed)"
    }
}

// MARK: - RB-1 — 8 of 10 found: kept with all their user data; 2 removed with theirs

func checkRebindKeepsFoundRemovesMissing(number: Int, url: URL) async -> Bool {
    do {
        let library = try await RebindLibrary.make("rb1", at: url, count: 10)
        let newRoot = try library.copy(to: "T7 1", missing: [3, 8])
        let kept = library.ids.enumerated().filter { ![3, 8].contains($0.offset) }.map(\.element)
        let before = try await userData(of: kept, in: library.store)
        try FileManager.default.removeItem(at: library.oldRoot) // the old drive is gone
        let outcome = try await library.rebinder(at: newRoot).rebind(folderID: library.folderID, to: newRoot,
                                                                     in: library.store)
        guard outcome == .rebound(kept: 8, removed: 2) else {
            printFail(number, "RB-1: expected 8 kept and 2 removed, got \(outcome)"); return false
        }
        guard try await userData(of: kept, in: library.store) == before else {
            printFail(number, "RB-1: a kept song lost user data across the rebind"); return false
        }
        guard try await library.store.track(url: newRoot.appendingPathComponent(library.paths[0]))?.id == kept[0],
              try await library.store.userState(trackID: library.ids[3]) == nil,
              try await library.store.countRows(inTable: "tracks") == 8,
              try await library.store.countRows(inTable: "tracks_fts") == 8 else {
            printFail(number, "RB-1: the kept songs are not at their new paths, or the missing ones (or their index "
                + "rows) remain"); return false
        }
        guard try await library.store.entries(inPlaylist: library.playlistID).map(\.trackID) == kept,
              try await library.store.boundVolume(ofRoot: library.folderID) == newDrive.volume,
              try await library.store.roots().map(\.path) == [PathNormalizer.normalizedString(for: newRoot)] else {
            printFail(number, "RB-1: the playlist lost a kept song's place, or the folder is not on the new drive")
            return false
        }
        guard try await queueAndWalkFollow(library, to: newRoot, kept: kept, number: number) else { return false }
        printPass(number, "RB-1 “Use this drive” on a copy at a new mount path holding 8 of 10 songs: the 8 keep "
            + "their ids, plays, loves, ratings, frecency and playlist places; the 2 are removed with their entries "
            + "and index rows; the folder is bound to the new drive; the queue's slots re-resolve by id; the walk "
            + "after it sweeps nothing")
        return true
    } catch {
        printFail(number, "RB-1 threw: \(error)"); return false
    }
}

/// Each song's user data — plays, love, rating, last play and frecency rank — by id, as text to compare.
private func userData(of ids: [Int64], in store: LibraryStore) async throws -> [Int64: String] {
    var data: [Int64: String] = [:]
    for id in ids {
        let user = try await store.userState(trackID: id)
        let frecency = try await store.frecencyState(id: id)
        data[id] = "\(String(describing: user))|\(String(describing: frecency?.rank))|"
            + "\(String(describing: frecency?.lastPlayed))"
    }
    return data
}

/// The queue's slots (by id, S5) re-resolve to the new paths, and the walk after the rebind — on the
/// folder's confirmed drive — is evidence and sweeps nothing.
private func queueAndWalkFollow(_ library: RebindLibrary, to newRoot: URL, kept: [Int64],
                                number: Int) async throws -> Bool {
    let queue = try await library.store.entries(inPlaylist: library.queueID).map(\.trackID)
    let resolved = try await library.store.tracksDisplay(ids: queue)
    let newPath = PathNormalizer.normalizedString(for: newRoot)
    guard queue == kept.reversed(), resolved.values.allSatisfy({
        PathNormalizer.isComponentBoundaryDescendant(PathNormalizer.normalizedString(for: $0.url), of: newPath)
    }) else {
        printFail(number, "RB-1: the queue's slots do not re-resolve by id to the new drive"); return false
    }
    let walk = try await LibraryScanner(rootIdentity: { _ in newDrive }).scan(
        root: newRoot, folderID: library.folderID, into: library.store
    )
    guard walk.orphansSwept == 0, Set(walk.trackIDs) == Set(kept) else {
        printFail(number, "RB-1: the walk after the rebind swept \(walk.orphansSwept) or changed ids"); return false
    }
    return true
}

// MARK: - RB-2 — none found: refused, nothing written

func checkRebindRefusedWhenNoneFound(number: Int, url: URL) async -> Bool {
    do {
        let library = try await RebindLibrary.make("rb2", at: url, count: 6)
        let before = try rebindState(at: url)
        // A drive holding none of the songs; one whose copies were all re-tagged (another size).
        let empty = try ScanFixtureBuilder.makeDirectory(at: library.base, ["Empty", "Music"])
        try ScanFixtureBuilder.writeFile(at: empty, subdirs: ["Other"], fileName: "x.flac")
        let retagged = try library.copy(to: "Retagged")
        for path in library.paths {
            try ScanFixtureBuilder.overwriteFile(at: retagged.appendingPathComponent(path), byteCount: 300)
        }
        let gone = library.base.appendingPathComponent("Unplugged/Music")
        for newRoot in [empty, retagged, gone] {
            let outcome = try await library.rebinder(at: newRoot).rebind(folderID: library.folderID, to: newRoot,
                                                                         in: library.store)
            guard outcome == .refused(.noSongsFound), try rebindState(at: url) == before else {
                printFail(number, "RB-2: \(newRoot.lastPathComponent) was not refused, or something was written: "
                    + "\(outcome)"); return false
            }
        }
        printPass(number, "RB-2 refused with nothing written — the wrong drive: a drive holding none of the "
            + "folder's songs, one whose copies were all re-tagged (another size), and a folder that is not there "
            + "leave every folder, song, user datum, playlist entry and index row as it was")
        return true
    } catch {
        printFail(number, "RB-2 threw: \(error)"); return false
    }
}

// MARK: - RB-3 — the new location overlaps another music folder: refused, nothing written

func checkRebindRefusedOnOverlap(number: Int, url: URL) async -> Bool {
    do {
        let library = try await RebindLibrary.make("rb3", at: url, count: 4)
        let newRoot = try library.copy(to: "T7 1")
        let other = try await library.store.addRoot(newRoot) // the new location is already a music folder
        let inside = newRoot.appendingPathComponent("Album 0")
        let holder = newRoot.deletingLastPathComponent()
        let before = try rebindState(at: url)
        for candidate in [newRoot, inside, holder] {
            let outcome = try await library.rebinder(at: candidate).rebind(folderID: library.folderID, to: candidate,
                                                                           in: library.store)
            guard outcome == .refused(.overlapsFolder(id: other)), try rebindState(at: url) == before else {
                printFail(number, "RB-3: \(candidate.path) was not refused as overlapping folder \(other): \(outcome)")
                return false
            }
        }
        printPass(number, "RB-3 refused with nothing written: the new location is another music folder, inside "
            + "one, or holds one")
        return true
    } catch {
        printFail(number, "RB-3 threw: \(error)"); return false
    }
}

// MARK: - RB-4 — the same path on a new drive; folders below; untagged albums; NFD; a loose duplicate

func checkRebindSamePathAndShapes(number: Int, url: URL) async -> Bool {
    do {
        guard try await sameDriveNameKeepsEveryID(number: number, url: url),
              try await nfdNamesAndLooseDuplicate(number: number, url: url) else { return false }
        printPass(number, "RB-4 the same path on a new drive keeps every id; a folder row below the music folder "
            + "moves with it; an untagged album regroups under the new path with its songs and their user data; "
            + "songs stored NFC are found where the drive spells names NFD; a loose duplicate merges into the "
            + "found song, its playlist entry and plays carried over")
        return true
    } catch {
        printFail(number, "RB-4 threw: \(error)"); return false
    }
}

/// The same path, another drive (`.differentVolume`): every id kept, a folder row below moved, the untagged
/// albums regrouped under their (unchanged) folder with every song.
private func sameDriveNameKeepsEveryID(number: Int, url: URL) async throws -> Bool {
    let library = try await RebindLibrary.make("rb4a", at: url, count: 8)
    let albumsBefore = try await library.store.albums(sortedBy: .title).map { "\($0.title):\($0.trackCount)" }
    let outcome = try await library.rebinder(at: library.oldRoot).rebind(folderID: library.folderID,
                                                                         to: library.oldRoot, in: library.store)
    let albumsAfter = try await library.store.albums(sortedBy: .title).map { "\($0.title):\($0.trackCount)" }
    guard outcome == .rebound(kept: 8, removed: 0), albumsAfter == albumsBefore,
          try await library.store.boundVolume(ofRoot: library.folderID) == newDrive.volume else {
        printFail(number, "RB-4: the same path on a new drive did not keep every song and album: \(outcome)")
        return false
    }
    // At a new mount path: the folder row below moves, the untagged albums re-key with all their songs.
    let library2 = try await RebindLibrary.make("rb4b", at: url.appendingPathExtension("b"), count: 8)
    let below2 = try await library2.store.seedFolderRow(
        path: library2.oldRoot.appendingPathComponent("Album 1").path, isRoot: false
    )
    let newRoot = try library2.copy(to: "T7 1")
    let users = try await library2.ids.asyncMap { try await library2.store.userState(trackID: $0) }
    _ = try await library2.rebinder(at: newRoot).rebind(folderID: library2.folderID, to: newRoot, in: library2.store)
    let moved = try await DatabaseQueue(path: url.appendingPathExtension("b").path).read { db in
        try String.fetchOne(db, sql: "SELECT path FROM folders WHERE id = ?;", arguments: [below2])
    }
    let albums = try await library2.store.albums(sortedBy: .title)
    let usersAfter = try await library2.ids.asyncMap { try await library2.store.userState(trackID: $0) }
    guard moved == PathNormalizer.normalizedString(for: newRoot.appendingPathComponent("Album 1")),
          albums.map(\.trackCount) == [4, 4], usersAfter == users else {
        printFail(number, "RB-4: a folder row below did not move, or the untagged albums lost songs or user data")
        return false
    }
    return true
}

/// Names the drive spells decomposed (NFD) are found by their stored composed (NFC) paths; and a song the
/// library held loose at a found song's new path merges into it.
private func nfdNamesAndLooseDuplicate(number: Int, url: URL) async throws -> Bool {
    let base = try ScanFixtureBuilder.makeCaseRoot("rb4c")
    let composed = "Bj\u{F6}rk" // stored NFC
    let oldRoot = try ScanFixtureBuilder.makeDirectory(at: base, ["Old", "Music"])
    try ScanFixtureBuilder.writeFile(at: oldRoot, subdirs: [composed], fileName: "Caf\u{E9}.flac", byteCount: 11)
    try ScanFixtureBuilder.writeFile(at: oldRoot, subdirs: [composed], fileName: "Other.flac", byteCount: 12)
    let store = try await LibraryStore(url: url.appendingPathExtension("c"), appBuild: "verify")
    let folderID = try await store.addRoot(oldRoot)
    _ = try await LibraryScanner(rootIdentity: { _ in oldDrive }).scan(root: oldRoot, folderID: folderID, into: store)
    let cafe = try await requireTrack(store, at: oldRoot.appendingPathComponent("\(composed)/Caf\u{E9}.flac"))
    // The new drive spells the folder and file names decomposed.
    let newRoot = try ScanFixtureBuilder.makeDirectory(at: base, ["New", "Music"])
    try ScanFixtureBuilder.writeFile(at: newRoot, subdirs: ["Bjo\u{308}rk"], fileName: "Cafe\u{301}.flac",
                                     byteCount: 11)
    try ScanFixtureBuilder.writeFile(at: newRoot, subdirs: ["Bjo\u{308}rk"], fileName: "Other.flac", byteCount: 12)
    // While the folder was paused, the new drive's copy of "Other" was added to a playlist: a loose row.
    let playlist = try await store.createPlaylist(name: "Loose")
    let otherNew = newRoot.appendingPathComponent("Bjo\u{308}rk/Other.flac")
    guard let looseFile = LibraryScanner.makeScannedFile(fileURL: otherNew, root: otherNew.deletingLastPathComponent())
    else { throw RebindCheckError("the loose fixture file is unreadable") }
    let loose = try await store.addLooseFileToPlaylist(looseFile, playlistID: playlist)
    try await store.incrementPlayCount(id: loose.trackID, playedAt: 1_760_000_100)
    let other = try await requireTrack(store, at: oldRoot.appendingPathComponent("\(composed)/Other.flac"))
    let otherPlays = try await store.userState(trackID: other)?.playCount ?? -1
    let rebinder = RootRebinder(rootIdentity: { _ in newDrive })
    let outcome = try await rebinder.rebind(folderID: folderID, to: newRoot, in: store)
    let merged = try await store.userState(trackID: other)
    guard outcome == .rebound(kept: 2, removed: 0),
          try await store.track(url: newRoot.appendingPathComponent("\(composed)/Caf\u{E9}.flac"))?.id == cafe,
          try await store.entries(inPlaylist: playlist).map(\.trackID) == [other],
          try await store.userState(trackID: loose.trackID) == nil, merged?.playCount == otherPlays + 1 else {
        printFail(number, "RB-4: NFD names on the drive were not matched, or the loose duplicate did not merge: "
            + "\(outcome)")
        return false
    }
    return true
}

// MARK: - RB-5 — a kill mid-rebind leaves the before state or the after state

/// The child mode: `VerifyLibraryStore --rebind-child <store> <folderID> <newRoot>` re-binds and exits 0.
func runRebindChildIfRequested() async {
    let arguments = CommandLine.arguments
    guard arguments.count == 5, arguments[1] == "--rebind-child", let folderID = Int64(arguments[3]) else { return }
    do {
        let store = try await LibraryStore(url: URL(fileURLWithPath: arguments[2]), appBuild: "verify")
        let newRoot = URL(fileURLWithPath: arguments[4])
        _ = try await RootRebinder(rootIdentity: { _ in newDrive }).rebind(folderID: folderID, to: newRoot, in: store)
        exit(0)
    } catch {
        fail("rebind-child threw: \(error)")
    }
}

func checkRebindKillLeavesBeforeOrAfter(number: Int, url: URL) async -> Bool {
    do {
        let library = try await RebindLibrary.make("rb5", at: url, count: 1200)
        let newRoot = try library.copy(to: "T7 1", missing: Set(stride(from: 0, to: 1200, by: 10)))
        try FileManager.default.removeItem(at: library.oldRoot)
        let before = try rebindState(at: url)
        // The after state: a copy re-bound to completion by the same child.
        let finished = url.appendingPathExtension("after")
        try copyStore(url, to: finished)
        try runChild(store: finished, folderID: library.folderID, newRoot: newRoot, killAfter: nil)
        let after = try rebindState(at: finished)
        guard after != before else {
            printFail(number, "RB-5: the completed rebind changed nothing"); return false
        }
        var outcomes: [String: Int] = ["before": 0, "after": 0]
        for attempt in 0 ..< 12 {
            let killed = url.appendingPathExtension("kill\(attempt)")
            try copyStore(url, to: killed)
            try runChild(store: killed, folderID: library.folderID, newRoot: newRoot,
                         killAfter: .milliseconds(Int.random(in: 20 ... 400)))
            _ = try await LibraryStore(url: killed, appBuild: "verify") // recovery: the open path, as at launch
            switch try rebindState(at: killed) {
            case before: outcomes["before", default: 0] += 1
            case after: outcomes["after", default: 0] += 1
            default:
                printFail(number, "RB-5: a kill at attempt \(attempt) left a state that is neither before nor after")
                return false
            }
        }
        printPass(number, "RB-5 a rebind is one transaction: 12 SIGKILLs at random points of a 1,200-song rebind "
            + "left the before state \(outcomes["before"] ?? 0)× and the after state \(outcomes["after"] ?? 0)×, "
            + "never a mix")
        return true
    } catch {
        printFail(number, "RB-5 threw: \(error)"); return false
    }
}

/// Copy the WAL-mode store at `source` (closed) with its sidecars to `target`.
private func copyStore(_ source: URL, to target: URL) throws {
    for suffix in ["", "-wal", "-shm"] where FileManager.default.fileExists(atPath: source.path + suffix) {
        try? FileManager.default.removeItem(atPath: target.path + suffix)
        try FileManager.default.copyItem(atPath: source.path + suffix, toPath: target.path + suffix)
    }
}

/// Run this executable as the rebind child on `store`; SIGKILL it after `killAfter` (nil: let it finish).
private func runChild(store: URL, folderID: Int64, newRoot: URL, killAfter: Duration?) throws {
    let child = Process()
    child.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
    child.arguments = ["--rebind-child", store.path, String(folderID), newRoot.path]
    child.standardOutput = FileHandle.nullDevice
    try child.run()
    if let killAfter {
        let parts = killAfter.components
        usleep(useconds_t(parts.seconds * 1_000_000 + parts.attoseconds / 1_000_000_000_000))
        kill(child.processIdentifier, SIGKILL)
    }
    child.waitUntilExit()
    if killAfter == nil, child.terminationStatus != 0 {
        throw RebindCheckError("the rebind child exited \(child.terminationStatus)")
    }
}

private extension Array {
    /// `map` with an async transform, in order.
    func asyncMap<T>(_ transform: (Element) async throws -> T) async rethrows -> [T] {
        var mapped: [T] = []
        for element in self {
            try mapped.append(await transform(element))
        }
        return mapped
    }
}
