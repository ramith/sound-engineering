import Foundation
import GRDB
import LibraryScan
@testable import LibraryStore
import Testing

// P5a — UNCOMMITTED break-it of the R1 sweep-evidence fix (763cb1b + 46c1276). Real scanner + store
// on temp dirs and real APFS / FAT / exFAT disk images (hdiutil). Every test asserts the SAFE
// property (no row, entry or play lost; a clean walk still reaps), so a red test is a finding.

/// What one walk did: a result, a refusal, or another error.
struct P5aWalk: CustomStringConvertible {
    var result: ScanResult?
    var refusal: SweepRefusal?
    var error: (any Error)?

    var description: String {
        if let result {
            return "ok(seen=\(result.filesSeen) swept=\(result.orphansSwept))"
        }
        if let refusal {
            return "refused(\(refusal.reason), kept=\(refusal.storedRowCount))"
        }
        return "error(\(String(describing: error)))"
    }

    var swept: Int {
        result?.orphansSwept ?? 0
    }

    static func run(_ root: URL, _ folderID: Int64, _ store: LibraryStore,
                    progress: (@Sendable (ScanProgress) -> Void)? = nil) async -> P5aWalk {
        await run(scanner: LibraryScanner(), root, folderID, store, progress: progress)
    }

    static func run(scanner: LibraryScanner, _ root: URL, _ folderID: Int64,
                    _ store: LibraryStore, progress: (@Sendable (ScanProgress) -> Void)? = nil) async -> P5aWalk {
        do {
            return try await P5aWalk(result: scanner.scan(root: root, folderID: folderID, into: store, progress: progress))
        } catch let refusal as SweepRefusal {
            return P5aWalk(refusal: refusal)
        } catch {
            return P5aWalk(error: error)
        }
    }
}

/// A library of songs in one root, every song in a playlist and played once.
struct P5aLibrary {
    let base: URL
    let store: LibraryStore
    let root: URL
    let folderID: Int64
    let playlist: Int64
    let ids: [Int64]

    static func make(base: URL, root: URL) async throws -> P5aLibrary {
        let store = try await P5aFixture.store(base)
        let folderID = try await store.addRoot(root)
        let first = await P5aWalk.run(root, folderID, store)
        #expect(first.result != nil, "first walk: \(first)")
        let ids = try await store.tracks(inFolder: folderID).map(\.id)
        let playlist = try await store.createPlaylist(name: "Everything")
        _ = try await store.appendEntries(playlistID: playlist, trackIDs: ids)
        for id in ids {
            try await store.incrementPlayCount(id: id, playedAt: 1_760_000_000)
        }
        return P5aLibrary(base: base, store: store, root: root, folderID: folderID, playlist: playlist, ids: ids)
    }

    /// (rows still there, playlist entries, total plays) — all must equal `ids.count` when nothing was lost.
    func userData() async throws -> (rows: Int, entries: Int, plays: Int64) {
        var rows = 0
        var plays: Int64 = 0
        for id in ids {
            if try await store.track(id: id) != nil {
                rows += 1
            }
            plays += try await store.userState(trackID: id)?.playCount ?? 0
        }
        return (rows, try await store.entries(inPlaylist: playlist).count, plays)
    }

    func intact() async throws -> Bool {
        let data = try await userData()
        return data.rows == ids.count && data.entries == ids.count && data.plays == Int64(ids.count)
    }

    func volumeUUID() async throws -> String? {
        let queue = try DatabaseQueue(path: base.appendingPathComponent("library.sqlite3").path)
        return try await queue.read { db in
            try String.fetchOne(db, sql: "SELECT volume_uuid FROM folders WHERE id = ?", arguments: [folderID])
        }
    }
}

extension LibraryStore {
    /// The test store's file (P5aFixture puts it at base/library.sqlite3).
    var storeURLForP5a: URL {
        P5aImages.lastStoreURL.value
    }
}

/// hdiutil helpers. Every image a test attaches it force-detaches in a defer.
enum P5aImages {
    final class Box: @unchecked Sendable {
        private let lock = NSLock()
        private var url = URL(fileURLWithPath: "/dev/null")
        var value: URL {
            get { lock.withLock { url } }
            set { lock.withLock { url = newValue } }
        }
    }

    static let lastStoreURL = Box()

    static func create(_ image: URL, name: String, fs: String = "APFS", size: String = "40m") -> Bool {
        P5aSweepBreakTests.hdiutil(["create", "-size", size, "-fs", fs, "-volname", name, "-ov", image.path]) == 0
    }

    static func attach(_ image: URL, at mount: URL) -> Bool {
        P5aSweepBreakTests.hdiutil(["attach", "-nobrowse", "-mountpoint", mount.path, image.path]) == 0
    }

    @discardableResult
    static func detach(_ mount: URL) -> Bool {
        P5aSweepBreakTests.hdiutil(["detach", "-force", mount.path]) == 0
    }

    static func volumeUUID(_ url: URL) -> String? {
        var resolved = url.resolvingSymlinksInPath()
        resolved.removeAllCachedResourceValues()
        return try? resolved.resourceValues(forKeys: [.volumeUUIDStringKey]).volumeUUIDString
    }
}

@Suite("P5a fix break — originals and new attacks", .serialized)
struct P5aFixBreakTests {
    private func base(_ tag: String) -> URL {
        let url = P5aFixture.base(tag)
        P5aImages.lastStoreURL.value = url.appendingPathComponent("library.sqlite3")
        return url
    }

    // MARK: 1. The original cases

    @Test("ORIG LIB-02a: unreadable subfolder (000 / 444)", arguments: [0o000, 0o444] as [UInt16])
    func unreadableSubfolder(mode: UInt16) async throws {
        let base = base("fx02a")
        let music = base.appendingPathComponent("Music", isDirectory: true)
        let albumB = music.appendingPathComponent("Album B", isDirectory: true)
        defer {
            chmod(albumB.path, 0o755)
            try? FileManager.default.removeItem(at: base)
        }
        try P5aFixture.files(in: music.appendingPathComponent("Album A"), count: 5)
        try P5aFixture.files(in: albumB, count: 5)
        let library = try await P5aLibrary.make(base: base, root: music)
        chmod(albumB.path, mode_t(mode))
        let walk = await P5aWalk.run(music, library.folderID, library.store)
        chmod(albumB.path, 0o755)
        let data = try await library.userData()
        // Q3: once readable again, a clean walk reaps a genuine delete — and keeps the rest.
        try FileManager.default.removeItem(at: albumB.appendingPathComponent("000 Song.flac"))
        let clean = await P5aWalk.run(music, library.folderID, library.store)
        print("P5A-FIX LIB-02a mode=\(String(mode, radix: 8)) walk=\(walk) data=\(data) | after restore+1 delete: \(clean)")
        #expect(walk.swept == 0 && data.rows == 10 && data.entries == 10 && data.plays == 10)
        #expect(clean.result?.orphansSwept == 1)
    }

    @Test("ORIG LIB-02b: volume detached mid-walk (800 songs)")
    func volumeDetachedMidWalk() async throws {
        let base = base("fx02b")
        defer { try? FileManager.default.removeItem(at: base) }
        let image = base.appendingPathComponent("x.dmg")
        let mount = base.appendingPathComponent("mnt", isDirectory: true)
        try FileManager.default.createDirectory(at: mount, withIntermediateDirectories: true)
        #expect(P5aImages.create(image, name: "P5AX"))
        #expect(P5aImages.attach(image, at: mount))
        defer { P5aImages.detach(mount) }
        let music = mount.appendingPathComponent("Music", isDirectory: true)
        for album in 0 ..< 20 {
            try P5aFixture.files(in: music.appendingPathComponent("Album \(album)"), count: 40)
        }
        let library = try await P5aLibrary.make(base: base, root: music)
        let bound = try await library.volumeUUID()
        let detached = LockedFlag()
        let walk = await P5aWalk.run(music, library.folderID, library.store, progress: { _ in
            if !detached.value {
                detached.value = true
                P5aImages.detach(mount)
            }
        })
        let data = try await library.userData()
        let rowCount = try await library.store.trackCount()
        // Q3: the drive comes back → the next walk is clean, nothing lost, no ghost rows.
        #expect(P5aImages.attach(image, at: mount))
        let back = await P5aWalk.run(music, library.folderID, library.store)
        let dataBack = try await library.userData()
        let rowsBack = try await library.store.trackCount()
        print("P5A-FIX LIB-02b bound=\(bound ?? "nil") walk=\(walk) data=\(data) totalRows=\(rowCount) | "
            + "remount: \(back) data=\(dataBack) totalRows=\(rowsBack)")
        #expect(walk.swept == 0 && data.rows == 800 && data.entries == 800 && data.plays == 800)
        #expect(rowCount == 800, "the walk added \(rowCount - 800) rows for files that vanished under it")
        #expect(back.result != nil && dataBack.rows == 800 && rowsBack == 800)
    }

    @Test("ORIG LIB-02d: same-named different drive at the root's path, then the original returns")
    func sameNamedDrive() async throws {
        let base = base("fx02d")
        defer { try? FileManager.default.removeItem(at: base) }
        let mount = base.appendingPathComponent("T7", isDirectory: true)
        try FileManager.default.createDirectory(at: mount, withIntermediateDirectories: true)
        let driveX = base.appendingPathComponent("x.dmg")
        let driveY = base.appendingPathComponent("y.dmg")
        #expect(P5aImages.create(driveX, name: "T7") && P5aImages.create(driveY, name: "T7"))
        #expect(P5aImages.attach(driveX, at: mount))
        let music = mount.appendingPathComponent("Music", isDirectory: true)
        try P5aFixture.files(in: music.appendingPathComponent("Albums"), count: 60, prefix: "X")
        let library = try await P5aLibrary.make(base: base, root: music)
        P5aImages.detach(mount)
        #expect(P5aImages.attach(driveY, at: mount))
        try P5aFixture.files(in: music.appendingPathComponent("Other"), count: 2, prefix: "Y")
        let walkY = await P5aWalk.run(music, library.folderID, library.store)
        let dataY = try await library.userData()
        let rowsY = try await library.store.trackCount()
        P5aImages.detach(mount)
        #expect(P5aImages.attach(driveX, at: mount))
        defer { P5aImages.detach(mount) }
        try FileManager.default.removeItem(at: music.appendingPathComponent("Albums/000 X.flac")) // genuine delete
        let walkX = await P5aWalk.run(music, library.folderID, library.store)
        let dataX = try await library.userData()
        print("P5A-FIX LIB-02d drive Y: \(walkY) data=\(dataY) totalRows=\(rowsY) | X back + 1 delete: \(walkX) data=\(dataX)")
        #expect(walkY.swept == 0 && dataY.rows == 60 && dataY.entries == 60 && rowsY == 60)
        #expect(walkX.result?.orphansSwept == 1 && dataX.rows == 59)
    }

    // MARK: 2. New attacks

    @Test("ATK-1: an error at the root itself vs deep inside", arguments: [0, 5])
    func errorDepth(depth: Int) async throws {
        let base = base("atk1-\(depth)")
        let music = base.appendingPathComponent("Music", isDirectory: true)
        var locked = music
        for level in 0 ..< depth {
            locked = locked.appendingPathComponent("L\(level)", isDirectory: true)
        }
        defer {
            chmod(locked.path, 0o755)
            try? FileManager.default.removeItem(at: base)
        }
        try P5aFixture.files(in: music.appendingPathComponent("Top"), count: 3)
        try P5aFixture.files(in: locked.appendingPathComponent("Deep"), count: 3)
        let library = try await P5aLibrary.make(base: base, root: music)
        chmod(locked.path, 0o000)
        let walk = await P5aWalk.run(music, library.folderID, library.store)
        chmod(locked.path, 0o755)
        let data = try await library.userData()
        print("P5A-FIX ATK-1 depth=\(depth) walk=\(walk) data=\(data)")
        #expect(walk.swept == 0 && data.rows == 6 && data.entries == 6)
    }

    @Test("ATK-2: symlink loops inside the root — no hang, no refusal, genuine delete reaped")
    func symlinkLoop() async throws {
        let base = base("atk2")
        defer { try? FileManager.default.removeItem(at: base) }
        let music = base.appendingPathComponent("Music", isDirectory: true)
        let files = try P5aFixture.files(in: music.appendingPathComponent("A"), count: 4)
        let fm = FileManager.default
        try fm.createSymbolicLink(atPath: music.appendingPathComponent("A/up").path, withDestinationPath: "..")
        try fm.createSymbolicLink(atPath: music.appendingPathComponent("A/self").path, withDestinationPath: "self")
        try fm.createSymbolicLink(atPath: music.appendingPathComponent("p.flac").path, withDestinationPath: "q.flac")
        try fm.createSymbolicLink(atPath: music.appendingPathComponent("q.flac").path, withDestinationPath: "p.flac")
        let library = try await P5aLibrary.make(base: base, root: music)
        try fm.removeItem(at: files[0])
        let walk = await P5aWalk.run(music, library.folderID, library.store)
        print("P5A-FIX ATK-2 walk=\(walk) rows=\(try await library.store.trackCount())")
        #expect(walk.result?.orphansSwept == 1)
    }

    @Test("ATK-3: permissions revoked mid-walk")
    func permissionsRevokedMidWalk() async throws {
        let base = base("atk3")
        let music = base.appendingPathComponent("Music", isDirectory: true)
        var albums: [URL] = []
        for album in 0 ..< 12 {
            let dir = music.appendingPathComponent("Album \(album)", isDirectory: true)
            albums.append(dir)
            try P5aFixture.files(in: dir, count: 50)
        }
        defer {
            for dir in albums {
                chmod(dir.path, 0o755)
            }
            try? FileManager.default.removeItem(at: base)
        }
        let library = try await P5aLibrary.make(base: base, root: music)
        let lockedAlbums = albums
        let revoked = LockedFlag()
        let walk = await P5aWalk.run(music, library.folderID, library.store, progress: { _ in
            if !revoked.value {
                revoked.value = true
                for dir in lockedAlbums {
                    chmod(dir.path, 0o000)
                }
            }
        })
        for dir in albums {
            chmod(dir.path, 0o755)
        }
        let data = try await library.userData()
        print("P5A-FIX ATK-3 walk=\(walk) data=\(data)")
        #expect(walk.swept == 0 && data.rows == 600 && data.entries == 600)
    }

    @Test("ATK-4: the volume is swapped mid-walk (same name, other drive)")
    func volumeSwappedMidWalk() async throws {
        let base = base("atk4")
        defer { try? FileManager.default.removeItem(at: base) }
        let mount = base.appendingPathComponent("T7", isDirectory: true)
        try FileManager.default.createDirectory(at: mount, withIntermediateDirectories: true)
        let driveX = base.appendingPathComponent("x.dmg")
        let driveY = base.appendingPathComponent("y.dmg")
        #expect(P5aImages.create(driveX, name: "T7") && P5aImages.create(driveY, name: "T7"))
        #expect(P5aImages.attach(driveY, at: mount))
        let music = mount.appendingPathComponent("Music", isDirectory: true)
        for album in 0 ..< 10 { // drive Y holds the SAME folder layout, other songs
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
        let data = try await library.userData()
        let rows = try await library.store.trackCount()
        var relocated = 0
        for id in library.ids {
            if let url = try await library.store.track(id: id)?.url, url.lastPathComponent.hasSuffix(" Y.flac") {
                relocated += 1
            }
        }
        P5aImages.detach(mount)
        // Drive X comes back: a clean walk. Do X's songs keep their ids, entries and plays?
        #expect(P5aImages.attach(driveX, at: mount))
        let back = await P5aWalk.run(music, library.folderID, library.store)
        let dataBack = try await library.userData()
        let rowsBack = try await library.store.trackCount()
        P5aImages.detach(mount)
        print("P5A-FIX ATK-4 walk=\(walk) data=\(data) totalRows=\(rows) xRowsRelocatedToYFiles=\(relocated) | "
            + "X back: \(back) data=\(dataBack) totalRows=\(rowsBack)")
        #expect(walk.swept == 0 && data.rows == 400 && data.entries == 400)
        #expect(rows == 400, "\(rows - 400) rows of drive Y were added to drive X's folder")
        #expect(relocated == 0, "\(relocated) of X's rows were move-matched onto drive Y's files")
        #expect(dataBack.rows == 400 && dataBack.entries == 400 && dataBack.plays == 400)
    }

    @Test("ATK-5: a root on a volume with no UUID (FAT32 / exFAT): same-name swap", arguments: ["MS-DOS FAT32", "ExFAT"])
    func noUUIDVolume(fs: String) async throws {
        let base = base("atk5")
        defer { try? FileManager.default.removeItem(at: base) }
        let mount = base.appendingPathComponent("STICK", isDirectory: true)
        try FileManager.default.createDirectory(at: mount, withIntermediateDirectories: true)
        let driveX = base.appendingPathComponent("x.dmg")
        let driveY = base.appendingPathComponent("y.dmg")
        guard P5aImages.create(driveX, name: "NONAME", fs: fs, size: "64m"),
              P5aImages.create(driveY, name: "NONAME", fs: fs, size: "64m") else {
            print("P5A-FIX ATK-5 \(fs): hdiutil cannot create this format here — skipped")
            return
        }
        #expect(P5aImages.attach(driveX, at: mount))
        let uuidX = P5aImages.volumeUUID(mount)
        let music = mount.appendingPathComponent("Music", isDirectory: true)
        try P5aFixture.files(in: music, count: 20, prefix: "X")
        let library = try await P5aLibrary.make(base: base, root: music)
        let bound = try await library.volumeUUID()
        P5aImages.detach(mount)
        #expect(P5aImages.attach(driveY, at: mount))
        let uuidY = P5aImages.volumeUUID(mount)
        try P5aFixture.files(in: music, count: 2, prefix: "Y")
        let walk = await P5aWalk.run(music, library.folderID, library.store)
        let data = try await library.userData()
        P5aImages.detach(mount)
        print("P5A-FIX ATK-5 \(fs): uuidX=\(uuidX ?? "nil") uuidY=\(uuidY ?? "nil") bound=\(bound ?? "nil") "
            + "walk on Y=\(walk) data=\(data)")
        #expect(walk.swept == 0 && data.rows == 20, "\(fs): a same-named stick swept the library")
    }

    @Test("ATK-6a: startup-disk root is unbound; a bound drive's path found on the startup disk is refused")
    func startupDisk() async throws {
        let base = base("atk6a")
        defer { try? FileManager.default.removeItem(at: base) }
        // (1) A root on the startup disk stays unbound and still sweeps genuine deletes.
        let local = base.appendingPathComponent("LocalMusic", isDirectory: true)
        let localFiles = try P5aFixture.files(in: local, count: 5)
        let localLibrary = try await P5aLibrary.make(base: base, root: local)
        try FileManager.default.removeItem(at: localFiles[0])
        let localWalk = await P5aWalk.run(local, localLibrary.folderID, localLibrary.store)
        let localBound = try await localLibrary.volumeUUID()
        // (2) A drive-bound root whose drive is away, and a STALE folder at its path on the startup
        // disk (an app wrote into /Volumes/<name> while the drive was unplugged).
        let image = base.appendingPathComponent("x.dmg")
        let mount = base.appendingPathComponent("T7", isDirectory: true)
        try FileManager.default.createDirectory(at: mount, withIntermediateDirectories: true)
        #expect(P5aImages.create(image, name: "T7"))
        #expect(P5aImages.attach(image, at: mount))
        let music = mount.appendingPathComponent("Music", isDirectory: true)
        try P5aFixture.files(in: music, count: 30, prefix: "X")
        let folderID = try await localLibrary.store.addRoot(music)
        let first = await P5aWalk.run(music, folderID, localLibrary.store)
        P5aImages.detach(mount)
        try P5aFixture.files(in: music, count: 2, prefix: "Stale") // on the startup disk now
        let stale = await P5aWalk.run(music, folderID, localLibrary.store)
        let kept = try await localLibrary.store.trackCount(inFolder: folderID)
        try? FileManager.default.removeItem(at: music)
        // (3) The drive comes back: walked normally again.
        #expect(P5aImages.attach(image, at: mount))
        defer { P5aImages.detach(mount) }
        let back = await P5aWalk.run(music, folderID, localLibrary.store)
        print("P5A-FIX ATK-6a startup root: bound=\(localBound ?? "nil") walk=\(localWalk) | drive root first=\(first) "
            + "stale-on-startup=\(stale) kept=\(kept)/30 | back=\(back)")
        #expect(localBound == RootIdentity.startupDisk && localWalk.result?.orphansSwept == 1)
        #expect(stale.refusal?.reason == .differentVolume && kept == 30)
        #expect(back.result != nil)
    }

    /// The upgrade window: every root of a v7 store migrates UNBOUND (NULL), and the first walk binds
    /// it to whatever drive is at its path — the protection starts only after that first walk.
    @Test("ATK-6b: an unbound (pre-v8) root whose first walk after the upgrade finds another drive")
    func unboundFirstWalk() async throws {
        let base = base("atk6b")
        defer { try? FileManager.default.removeItem(at: base) }
        let mount = base.appendingPathComponent("T7", isDirectory: true)
        try FileManager.default.createDirectory(at: mount, withIntermediateDirectories: true)
        let driveX = base.appendingPathComponent("x.dmg")
        let driveY = base.appendingPathComponent("y.dmg")
        #expect(P5aImages.create(driveX, name: "T7") && P5aImages.create(driveY, name: "T7"))
        #expect(P5aImages.attach(driveX, at: mount))
        let music = mount.appendingPathComponent("Music", isDirectory: true)
        try P5aFixture.files(in: music, count: 40, prefix: "X")
        let library = try await P5aLibrary.make(base: base, root: music)
        // Simulate a v7 store just migrated to v8: the root's volume_uuid is NULL.
        let queue = try DatabaseQueue(path: base.appendingPathComponent("library.sqlite3").path)
        try await queue.write { db in try db.execute(sql: "UPDATE folders SET volume_uuid = NULL") }
        try queue.close()
        P5aImages.detach(mount)
        #expect(P5aImages.attach(driveY, at: mount))
        try P5aFixture.files(in: music, count: 3, prefix: "Y")
        let walk = await P5aWalk.run(music, library.folderID, library.store)
        let data = try await library.userData()
        let boundAfterY = try await library.volumeUUID()
        let rowsAfterY = try await library.store.trackCount()
        P5aImages.detach(mount)
        // The right drive returns, with one genuine delete: it binds and walks normally.
        #expect(P5aImages.attach(driveX, at: mount))
        let uuidX = P5aImages.volumeUUID(mount)
        try FileManager.default.removeItem(at: music.appendingPathComponent("000 X.flac"))
        let back = await P5aWalk.run(music, library.folderID, library.store)
        let boundAfterX = try await library.volumeUUID()
        let dataBack = try await library.userData()
        P5aImages.detach(mount)
        print("P5A-FIX ATK-6b unbound root, other drive at first walk: \(walk) data=\(data) totalRows=\(rowsAfterY) "
            + "bound=\(boundAfterY ?? "nil") | X back+1 delete: \(back) bound=\(boundAfterX ?? "nil") (X=\(uuidX ?? "nil")) data=\(dataBack)")
        #expect(walk.swept == 0 && data.rows == 40, "the first walk after the upgrade bound the wrong drive and swept")
        #expect(boundAfterY == nil && rowsAfterY == 40)
        #expect(back.result?.orphansSwept == 1 && boundAfterX == uuidX && dataBack.rows == 39)
    }

    /// An unbound root whose drive is away, with a stale folder at its path on the startup disk
    /// holding a couple of songs (an app wrote into /Volumes/<name> while it was unplugged).
    @Test("ATK-6c: an unbound root, drive away, stale folder with songs on the startup disk")
    func unboundStaleFolder() async throws {
        let base = base("atk6c")
        defer { try? FileManager.default.removeItem(at: base) }
        let mount = base.appendingPathComponent("T7", isDirectory: true)
        try FileManager.default.createDirectory(at: mount, withIntermediateDirectories: true)
        let image = base.appendingPathComponent("x.dmg")
        #expect(P5aImages.create(image, name: "T7"))
        #expect(P5aImages.attach(image, at: mount))
        let music = mount.appendingPathComponent("Music", isDirectory: true)
        try P5aFixture.files(in: music, count: 30, prefix: "X")
        let library = try await P5aLibrary.make(base: base, root: music)
        let queue = try DatabaseQueue(path: base.appendingPathComponent("library.sqlite3").path)
        try await queue.write { db in try db.execute(sql: "UPDATE folders SET volume_uuid = NULL") }
        try queue.close()
        P5aImages.detach(mount)
        try P5aFixture.files(in: music, count: 2, prefix: "Stale")
        let walk = await P5aWalk.run(music, library.folderID, library.store)
        let data = try await library.userData()
        let boundAfterStale = try await library.volumeUUID()
        try FileManager.default.removeItem(at: music)
        #expect(P5aImages.attach(image, at: mount))
        let back = await P5aWalk.run(music, library.folderID, library.store)
        let boundAfterX = try await library.volumeUUID()
        let uuidX = P5aImages.volumeUUID(mount)
        P5aImages.detach(mount)
        print("P5A-FIX ATK-6c unbound + stale startup-disk folder: \(walk) data=\(data) bound=\(boundAfterStale ?? "nil") "
            + "| X back: \(back) bound=\(boundAfterX ?? "nil") (X=\(uuidX ?? "nil"))")
        #expect(walk.swept == 0 && data.rows == 30 && boundAfterStale == nil)
        #expect(back.result != nil && boundAfterX == uuidX)
    }

    /// The volume's own root is the music folder (the user added "/Volumes/T7").
    @Test("ATK-9: the root IS a volume's root — unplugged, then back with a genuine delete")
    func volumeRootAsLibraryRoot() async throws {
        let base = base("atk9")
        defer { try? FileManager.default.removeItem(at: base) }
        let mount = base.appendingPathComponent("T7", isDirectory: true)
        try FileManager.default.createDirectory(at: mount, withIntermediateDirectories: true)
        let image = base.appendingPathComponent("x.dmg")
        #expect(P5aImages.create(image, name: "T7"))
        #expect(P5aImages.attach(image, at: mount))
        let files = try P5aFixture.files(in: mount.appendingPathComponent("Albums"), count: 20, prefix: "X")
        let library = try await P5aLibrary.make(base: base, root: mount)
        P5aImages.detach(mount)
        let away = await P5aWalk.run(mount, library.folderID, library.store) // the empty mount-point folder
        let dataAway = try await library.userData()
        #expect(P5aImages.attach(image, at: mount))
        defer { P5aImages.detach(mount) }
        try FileManager.default.removeItem(at: files[0])
        let back = await P5aWalk.run(mount, library.folderID, library.store)
        print("P5A-FIX ATK-9 away=\(away) data=\(dataAway) | back+1 delete=\(back)")
        #expect(away.swept == 0 && dataAway.rows == 20)
        #expect(back.result?.orphansSwept == 1)
    }

    @Test("ATK-7: restampRoot with a different volume changes nothing")
    func restampDifferentVolume() async throws {
        let base = base("atk7")
        defer { try? FileManager.default.removeItem(at: base) }
        let store = try await P5aFixture.store(base)
        let folder = base.appendingPathComponent("M", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let id = try await store.addRoot(folder)
        let first = try await store.restampRoot(id: id, to: RootIdentity(dev: 1, inode: 2, volume: "AAAA"))
        let other = try await store.restampRoot(id: id, to: RootIdentity(dev: 9, inode: 9, volume: "BBBB"))
        let nilUUID = try await store.restampRoot(id: id, to: RootIdentity(dev: 9, inode: 9, volume: nil))
        let same = try await store.restampRoot(id: id, to: RootIdentity(dev: 3, inode: 4, volume: "AAAA"))
        let queue = try DatabaseQueue(path: base.appendingPathComponent("library.sqlite3").path)
        let row = try queue.read { db in
            try Row.fetchOne(db, sql: "SELECT dev, inode, volume_uuid FROM folders WHERE id = ?", arguments: [id])
        }
        print("P5A-FIX ATK-7 bind=\(first) other=\(other) nilUUID=\(nilUUID) same=\(same) row=\(String(describing: row))")
        #expect(first && !other && !nilUUID && same)
    }

    @Test("ATK-8: a cancelled walk sweeps nothing; the next clean walk reaps a genuine delete")
    func cancelledWalk() async throws {
        let base = base("atk8")
        defer { try? FileManager.default.removeItem(at: base) }
        let music = base.appendingPathComponent("Music", isDirectory: true)
        var files: [URL] = []
        for album in 0 ..< 6 {
            try files += P5aFixture.files(in: music.appendingPathComponent("Album \(album)"), count: 100)
        }
        let library = try await P5aLibrary.make(base: base, root: music)
        try FileManager.default.removeItem(at: files[0])
        let task = Task { await P5aWalk.run(music, library.folderID, library.store, progress: { _ in
            withUnsafeCurrentTask { $0?.cancel() }
        }) }
        let cancelled = await task.value
        let afterCancel = try await library.userData()
        let clean = await P5aWalk.run(music, library.folderID, library.store)
        print("P5A-FIX ATK-8 cancelled=\(cancelled) data=\(afterCancel) | next=\(clean)")
        #expect(cancelled.error is CancellationError && afterCancel.rows == 600)
        #expect(clean.result?.orphansSwept == 1)
    }

    /// Q3 liveness: one permanently unreadable folder (a NAS "#recycle" the account may not open, a
    /// TCC-protected folder) makes EVERY walk incomplete — are genuine deletes ever reaped?
    @Test("Q3: a permanently unreadable empty folder — do genuine deletes ever leave?")
    func permanentIncompleteness() async throws {
        let base = base("q3")
        let music = base.appendingPathComponent("Music", isDirectory: true)
        let recycle = music.appendingPathComponent("#recycle", isDirectory: true)
        defer {
            chmod(recycle.path, 0o755)
            try? FileManager.default.removeItem(at: base)
        }
        let files = try P5aFixture.files(in: music.appendingPathComponent("Album"), count: 5)
        try FileManager.default.createDirectory(at: recycle, withIntermediateDirectories: true)
        chmod(recycle.path, 0o000)
        let library = try await P5aLibrary.make(base: base, root: music)
        try FileManager.default.removeItem(at: files[0])
        var walks: [String] = []
        for _ in 0 ..< 3 {
            walks.append(await P5aWalk.run(music, library.folderID, library.store).description)
        }
        let rows = try await library.store.trackCount(inFolder: library.folderID)
        print("P5A-FIX Q3 walks=\(walks) rowsFor4FilesOnDisk=\(rows)")
        #expect(rows == 4, "a deleted song is never reaped while any folder in the root is unreadable")
    }

    @Test("MIG-8: user data survives the upgrade from every version v1…v7; volume_uuid NULL then bound", arguments: 1 ... 7)
    func upgradeToV8(from version: Int) async throws {
        let base = base("mig8-v\(version)")
        defer { try? FileManager.default.removeItem(at: base) }
        let url = base.appendingPathComponent("library.sqlite3")
        let music = base.appendingPathComponent("Music", isDirectory: true)
        let files = try P5aFixture.files(in: music, count: 3)
        do {
            let queue = try DatabaseQueue(path: url.path)
            try LibraryStore.makeMigrator(appBuild: "old", through: version).migrate(queue)
            try await queue.write { db in
                try db.execute(sql: "INSERT INTO folders(id, path, is_root) VALUES (1, ?, 1);",
                               arguments: [PathNormalizer.normalizedString(for: music)])
                for (index, file) in files.enumerated() {
                    let size = Int64((try? FileManager.default.attributesOfItem(atPath: file.path)[.size] as? Int) ?? 0)
                    let mtime = Int64(((try? FileManager.default.attributesOfItem(atPath: file.path)[.modificationDate]
                            as? Date) ?? Date()).timeIntervalSince1970)
                    try db.execute(sql: """
                    INSERT INTO tracks(id, url, folder_id, relative_path, name, format, file_size, mtime,
                                       date_added, last_seen_scan, play_count)
                    VALUES (?, ?, 1, '', ?, 'FLAC', ?, ?, 1, 1, ?);
                    """, arguments: [(index + 1) * 10, PathNormalizer.normalizedString(for: file),
                                     file.deletingPathExtension().lastPathComponent, size, mtime, index + 1])
                }
                if version >= 3 {
                    try db.execute(sql: "INSERT INTO playlists(id, name, is_builtin, created_at) VALUES (7, 'Mine', 0, 1);")
                    for (position, track) in [30, 10, 20].enumerated() {
                        try db.execute(sql: "INSERT INTO playlist_entries(playlist_id, track_id, position, added_at) "
                            + "VALUES (7, ?, ?, 1);", arguments: [track, position])
                    }
                }
            }
            try queue.close()
        }
        let store = try await LibraryStore(url: url, appBuild: "p5a")
        let schema = await store.schemaVersion()
        let queue = try DatabaseQueue(path: url.path)
        let unboundAfterUpgrade = try await queue.read { db in
            try Row.fetchOne(db, sql: "SELECT volume_uuid IS NULL FROM folders WHERE id = 1")?[0] as Bool?
        }
        let walk = await P5aWalk.run(music, 1, store)
        var plays: [Int64] = []
        for id in [10, 20, 30] {
            plays.append(try await store.userState(trackID: Int64(id))?.playCount ?? -1)
        }
        let entries = version >= 3 ? try await store.entries(inPlaylist: 7).map(\.trackID) : []
        print("P5A-FIX MIG-8 from v\(version): schema=\(schema) unbound=\(String(describing: unboundAfterUpgrade)) "
            + "firstWalk=\(walk) plays=\(plays) entries=\(entries)")
        #expect(schema == 8 && unboundAfterUpgrade == true)
        #expect(plays == [1, 2, 3] && walk.swept == 0)
        if version >= 3 {
            #expect(entries == [30, 10, 20])
        }
    }
}
