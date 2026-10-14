import Foundation
import GRDB
import LibraryScan
@testable import LibraryStore
import Testing

// P5a — UNCOMMITTED re-check of 5dcad34 ("an unbound folder is walked only where its songs are, and
// bound only after a walk confirms its drive"): the new rule's own edge cases.

@Suite("P5a recheck — the unbound-folder rule", .serialized)
struct P5aRecheckTests {
    private func base(_ tag: String) -> URL {
        let url = P5aFixture.base(tag)
        P5aImages.lastStoreURL.value = url.appendingPathComponent("library.sqlite3")
        return url
    }

    /// Make the root unbound, as every root is right after the v7 → v8 upgrade.
    private func unbind(_ base: URL) async throws {
        let queue = try DatabaseQueue(path: base.appendingPathComponent("library.sqlite3").path)
        try await queue.write { db in try db.execute(sql: "UPDATE folders SET volume_uuid = NULL") }
        try queue.close()
    }

    /// (a) Unbound root; the user deleted ALL its songs and put new ones in. Bound, the same walk
    /// would sweep the old and add the new.
    @Test("RC-a: unbound root, every song deleted and replaced", arguments: [true, false])
    func allReplaced(unbound: Bool) async throws {
        let base = base("rca")
        defer { try? FileManager.default.removeItem(at: base) }
        let music = base.appendingPathComponent("Music", isDirectory: true)
        let old = try P5aFixture.files(in: music.appendingPathComponent("Old"), count: 5, prefix: "Old")
        let library = try await P5aLibrary.make(base: base, root: music)
        if unbound {
            try await unbind(base)
        }
        for file in old {
            try FileManager.default.removeItem(at: file)
        }
        let new = try P5aFixture.files(in: music.appendingPathComponent("New"), count: 3, prefix: "New")
        var walks: [String] = []
        for _ in 0 ..< 2 {
            walks.append(await P5aWalk.run(music, library.folderID, library.store).description)
        }
        var newInLibrary = 0
        for file in new where try await library.store.track(url: file) != nil {
            newInLibrary += 1
        }
        let rows = try await library.store.trackCount(inFolder: library.folderID)
        print("P5A-RC a unbound=\(unbound) walks=\(walks) rows=\(rows) newSongsInLibrary=\(newInLibrary)/3")
        #expect(newInLibrary == 3, "new songs copied into the folder never reach the library")
    }

    /// (b) Unbound root; the user renamed the one subfolder holding every song (a move inside the
    /// root). Bound, move-match keeps every id.
    @Test("RC-b: unbound root, every song moved inside the root", arguments: [true, false])
    func allMovedInside(unbound: Bool) async throws {
        let base = base("rcb")
        defer { try? FileManager.default.removeItem(at: base) }
        let music = base.appendingPathComponent("Music", isDirectory: true)
        let files = try P5aFixture.files(in: music.appendingPathComponent("Album"), count: 6)
        let library = try await P5aLibrary.make(base: base, root: music)
        if unbound {
            try await unbind(base)
        }
        try FileManager.default.moveItem(at: music.appendingPathComponent("Album"),
                                         to: music.appendingPathComponent("Album (2009)"))
        let walk = await P5aWalk.run(music, library.folderID, library.store)
        let moved = try await library.store.track(url: music.appendingPathComponent("Album (2009)")
            .appendingPathComponent(files[0].lastPathComponent))
        let data = try await library.userData()
        print("P5A-RC b unbound=\(unbound) walk=\(walk) movedRowFound=\(moved != nil) idKept=\(moved?.id == library.ids.first) data=\(data)")
        #expect(walk.result != nil, "the folder is never walked again until removed and re-added")
        #expect(data.rows == 6 && data.entries == 6)
    }

    /// (c) A brand-new EMPTY folder: added, walked, bound; songs copied in later appear.
    @Test("RC-c: a new empty folder, then songs copied in")
    func newEmptyFolder() async throws {
        let base = base("rcc")
        defer { try? FileManager.default.removeItem(at: base) }
        let music = base.appendingPathComponent("Empty", isDirectory: true)
        try FileManager.default.createDirectory(at: music, withIntermediateDirectories: true)
        let store = try await P5aFixture.store(base)
        let folderID = try await store.addRoot(music)
        let first = await P5aWalk.run(music, folderID, store)
        let queue = try DatabaseQueue(path: base.appendingPathComponent("library.sqlite3").path)
        let bound = try await queue.read { db in
            try String.fetchOne(db, sql: "SELECT volume_uuid FROM folders WHERE id = ?", arguments: [folderID])
        }
        try queue.close()
        try P5aFixture.files(in: music, count: 4)
        let second = await P5aWalk.run(music, folderID, store)
        let rows = try await store.trackCount(inFolder: folderID)
        print("P5A-RC c first=\(first) bound=\(bound ?? "nil") second=\(second) rows=\(rows)")
        #expect(first.result != nil && second.result != nil && rows == 4)
    }

    /// (d) Unbound root on its own drive; only 3 of 40 songs remain (37 genuinely deleted).
    @Test("RC-d: unbound first walk where only a few songs remain")
    func fewRemain() async throws {
        let base = base("rcd")
        defer { try? FileManager.default.removeItem(at: base) }
        let music = base.appendingPathComponent("Music", isDirectory: true)
        let files = try P5aFixture.files(in: music, count: 40)
        let library = try await P5aLibrary.make(base: base, root: music)
        try await unbind(base)
        for file in files.dropFirst(3) {
            try FileManager.default.removeItem(at: file)
        }
        let walk = await P5aWalk.run(music, library.folderID, library.store)
        let bound = try await library.volumeUUID()
        print("P5A-RC d walk=\(walk) bound=\(bound ?? "nil")")
        #expect(walk.result?.orphansSwept == 37 && bound == RootIdentity.startupDisk)
    }

    /// (e) The unbound window with a BACKUP drive: same name, same layout for most songs (an older
    /// copy of the library). It holds some of the root's songs where the library has them.
    @Test("RC-e: unbound window, a same-named backup drive holding most of the songs at the same paths")
    func backupDriveInUnboundWindow() async throws {
        let base = base("rce")
        defer { try? FileManager.default.removeItem(at: base) }
        let mount = base.appendingPathComponent("T7", isDirectory: true)
        try FileManager.default.createDirectory(at: mount, withIntermediateDirectories: true)
        let driveX = base.appendingPathComponent("x.dmg")
        let driveY = base.appendingPathComponent("y.dmg")
        #expect(P5aImages.create(driveX, name: "T7") && P5aImages.create(driveY, name: "T7"))
        defer { P5aImages.detach(mount) }
        let music = mount.appendingPathComponent("Music", isDirectory: true)
        // Y: the backup, made when the library had 30 songs.
        #expect(P5aImages.attach(driveY, at: mount))
        try P5aFixture.files(in: music.appendingPathComponent("Albums"), count: 30)
        let uuidY = P5aImages.volumeUUID(mount)
        P5aImages.detach(mount)
        // X: the live library, 40 songs (10 added since the backup), all in a playlist.
        #expect(P5aImages.attach(driveX, at: mount))
        try P5aFixture.files(in: music.appendingPathComponent("Albums"), count: 40)
        let uuidX = P5aImages.volumeUUID(mount)
        let library = try await P5aLibrary.make(base: base, root: music)
        try await unbind(base) // the store was just upgraded to v8
        P5aImages.detach(mount)
        // The first walk after the upgrade finds the backup drive at the path.
        #expect(P5aImages.attach(driveY, at: mount))
        let walkY = await P5aWalk.run(music, library.folderID, library.store)
        let data = try await library.userData()
        let bound = try await library.volumeUUID()
        P5aImages.detach(mount)
        #expect(P5aImages.attach(driveX, at: mount))
        let walkX = await P5aWalk.run(music, library.folderID, library.store)
        let dataX = try await library.userData()
        P5aImages.detach(mount)
        print("P5A-RC e backup Y walk=\(walkY) data=\(data) boundTo=\(bound == uuidY ? "Y" : (bound == uuidX ? "X" : bound ?? "nil")) "
            + "| X back: \(walkX) data=\(dataX)")
        #expect(walkY.swept == 0 && data.rows == 40, "the backup drive swept the songs added since the backup")
        #expect(walkX.result != nil, "the live drive is refused after the backup bound the folder")
    }

    /// (f) The mid-walk swap again: does the per-batch identity check stop foreign rows?
    @Test("RC-f: volume swapped mid-walk — no foreign rows, no relocations (3 runs)")
    func swapMidWalk() async throws {
        var report: [String] = []
        var bad = 0
        for run in 0 ..< 3 {
            let base = base("rcf\(run)")
            defer { try? FileManager.default.removeItem(at: base) }
            let mount = base.appendingPathComponent("T7", isDirectory: true)
            try FileManager.default.createDirectory(at: mount, withIntermediateDirectories: true)
            let driveX = base.appendingPathComponent("x.dmg")
            let driveY = base.appendingPathComponent("y.dmg")
            #expect(P5aImages.create(driveX, name: "T7") && P5aImages.create(driveY, name: "T7"))
            let music = mount.appendingPathComponent("Music", isDirectory: true)
            #expect(P5aImages.attach(driveY, at: mount))
            for album in 0 ..< 10 {
                try P5aFixture.files(in: music.appendingPathComponent("Album \(album)"), count: 40, prefix: "Y")
            }
            P5aImages.detach(mount)
            #expect(P5aImages.attach(driveX, at: mount))
            for album in 0 ..< 10 {
                try P5aFixture.files(in: music.appendingPathComponent("Album \(album)"), count: 40, prefix: "X")
            }
            let library = try await P5aLibrary.make(base: base, root: music)
            let swapped = LockedFlag()
            let walk = await P5aWalk.run(music, library.folderID, library.store, progress: { _ in
                if !swapped.value {
                    swapped.value = true
                    P5aImages.detach(mount)
                    _ = P5aImages.attach(driveY, at: mount)
                }
            })
            let rows = try await library.store.trackCount()
            var relocated = 0
            for id in library.ids {
                if let url = try await library.store.track(id: id)?.url, url.lastPathComponent.hasSuffix(" Y.flac") {
                    relocated += 1
                }
            }
            let data = try await library.userData()
            P5aImages.detach(mount)
            if rows != 400 || relocated != 0 || data.rows != 400 {
                bad += 1
            }
            report.append("run\(run): \(walk) rows=\(rows) relocated=\(relocated) data=\(data)")
        }
        print("P5A-RC f " + report.joined(separator: " | "))
        #expect(bad == 0)
    }
}

@Suite("P5a recheck — the documented remedy")
struct P5aRemedyTests {
    /// known-issues LIB-VOL-1: a paused folder (a replaced same-named drive, an unbound folder whose
    /// songs all moved) "stays paused until the user removes and re-adds the folder". Is that lossless?
    @Test("RC-g: remove + re-add keeps every song's play count, loved flag and playlist entries")
    func removeAndReAdd() async throws {
        let base = P5aFixture.base("rcg")
        defer { try? FileManager.default.removeItem(at: base) }
        let music = base.appendingPathComponent("Music", isDirectory: true)
        let files = try P5aFixture.files(in: music, count: 4)
        let store = try await P5aFixture.store(base)
        let root = try await store.addRoot(music)
        _ = try await LibraryScanner().scan(root: music, folderID: root, into: store)
        var ids: [Int64] = []
        for file in files {
            ids.append(try #require(try await store.track(url: file)).id)
        }
        let playlist = try await store.createPlaylist(name: "Two of them")
        _ = try await store.appendEntries(playlistID: playlist, trackIDs: Array(ids.prefix(2)))
        for id in ids {
            try await store.setUserState(trackID: id, playCount: 7, loved: true, rating: 5)
        }
        try await store.removeRoot(id: root)
        let again = try await store.addRoot(music)
        _ = try await LibraryScanner().scan(root: music, folderID: again, into: store)
        var report: [String] = []
        var lost = 0
        for file in files {
            let track = try #require(try await store.track(url: file))
            let state = try await store.userState(trackID: track.id)
            if state?.playCount != 7 || state?.loved != true {
                lost += 1
            }
            report.append("\(file.lastPathComponent): idKept=\(ids.contains(track.id)) plays=\(state?.playCount ?? -1) loved=\(state?.loved ?? false)")
        }
        let entries = try await store.entries(inPlaylist: playlist).count
        print("P5A-RC g remove+re-add: \(report.joined(separator: "; ")) playlistEntries=\(entries)/2")
        #expect(lost == 0, "\(lost)/4 songs lost their play count / loved flag through remove + re-add")
    }
}
