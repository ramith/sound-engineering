import Foundation
import LibraryScan
import LibraryStore
import Testing

// P5a panel (council stage 4) — UNCOMMITTED adversarial tests. LIB-02: does the end-of-walk sweep
// delete songs a walk failed to SEE (not songs that are gone)? Each test asserts the CORRECT
// property (a song that is still on disk keeps its row, playlist entry and play count), so a
// failure is the evidence.

enum P5aFixture {
    static func base(_ tag: String) -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("p5a-\(tag)-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @discardableResult
    static func files(in dir: URL, count: Int, prefix: String = "Song") throws -> [URL] {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return (0 ..< count).map { index in
            let url = dir.appendingPathComponent(String(format: "%03d \(prefix).flac", index))
            FileManager.default.createFile(atPath: url.path, contents: Data([UInt8(index & 0xFF), 1, 2]))
            return url
        }
    }

    static func store(_ base: URL) async throws -> LibraryStore {
        try await LibraryStore(url: base.appendingPathComponent("library.sqlite3"), appBuild: "p5a")
    }

    /// The user data hung on one song: its playlist entries (user playlist) and play count.
    static func userData(_ store: LibraryStore, trackID: Int64, playlistID: Int64) async throws
        -> (rowExists: Bool, entries: Int, playCount: Int64?) {
        let exists = try await store.track(id: trackID) != nil
        let entries = try await store.entries(inPlaylist: playlistID).count
        let plays = try await store.userState(trackID: trackID)?.playCount
        return (exists, entries, plays)
    }
}

@Suite("P5a LIB-02 — a sweep after a walk that did not see everything", .serialized)
struct P5aSweepBreakTests {
    /// A subfolder the walk cannot read (permissions changed, another user's folder, a TCC-protected
    /// folder under the root) — its songs are still on disk.
    @Test("LIB-02a: an unreadable subfolder's songs survive a reconcile", arguments: [0o000, 0o444] as [UInt16])
    func unreadableSubfolderIsNotSwept(mode: UInt16) async throws {
        let base = P5aFixture.base("lib02a")
        let music = base.appendingPathComponent("Music", isDirectory: true)
        let albumB = music.appendingPathComponent("Album B", isDirectory: true)
        defer {
            chmod(albumB.path, 0o755)
            try? FileManager.default.removeItem(at: base)
        }
        try P5aFixture.files(in: music.appendingPathComponent("Album A"), count: 5)
        let bFiles = try P5aFixture.files(in: albumB, count: 5)
        let store = try await P5aFixture.store(base)
        let root = try await store.addRoot(music)
        _ = try await LibraryScanner().scan(root: music, folderID: root, into: store)
        #expect(try await store.trackCount(inFolder: root) == 10)

        let songB = try #require(try await store.track(url: bFiles[0])).id
        let playlist = try await store.createPlaylist(name: "Keep me")
        _ = try await store.appendEntry(playlistID: playlist, trackID: songB)
        try await store.incrementPlayCount(id: songB, playedAt: 1_760_000_000)
        try await store.incrementPlayCount(id: songB, playedAt: 1_760_000_100)

        #expect(chmod(albumB.path, mode_t(mode)) == 0)
        let result = try await LibraryScanner().scan(root: music, folderID: root, into: store)
        chmod(albumB.path, 0o755)
        let stillOnDisk = bFiles.allSatisfy { FileManager.default.fileExists(atPath: $0.path) }
        let after = try await P5aFixture.userData(store, trackID: songB, playlistID: playlist)
        print("P5A LIB-02a mode=\(String(mode, radix: 8)) seen=\(result.filesSeen) skipped=\(result.filesSkipped) "
            + "swept=\(result.orphansSwept) kept=\(try await store.trackCount(inFolder: root)) "
            + "filesStillOnDisk=\(stillOnDisk) songRow=\(after.rowExists) entries=\(after.entries) "
            + "plays=\(String(describing: after.playCount))")
        #expect(stillOnDisk)
        #expect(result.orphansSwept == 0, "swept \(result.orphansSwept) songs that are on disk")
        #expect(after.rowExists && after.entries == 1 && after.playCount == 2)
    }

    /// The volume goes away in the middle of a walk (a USB drive unplugged, a NAS share dropping,
    /// a laptop sleeping with a drive attached). The first batch was seen, the rest was not.
    @Test("LIB-02b: a volume that goes away mid-walk keeps the songs the walk had not reached")
    func volumeLostMidWalkIsNotSwept() async throws {
        let base = P5aFixture.base("lib02b")
        defer { try? FileManager.default.removeItem(at: base) }
        let image = base.appendingPathComponent("vol.dmg")
        let mount = base.appendingPathComponent("mnt", isDirectory: true)
        try FileManager.default.createDirectory(at: mount, withIntermediateDirectories: true)
        #expect(Self.hdiutil(["create", "-size", "40m", "-fs", "APFS", "-volname", "P5A02B", image.path]) == 0)
        #expect(Self.hdiutil(["attach", "-nobrowse", "-mountpoint", mount.path, image.path]) == 0)
        defer { _ = Self.hdiutil(["detach", "-force", mount.path]) }

        let music = mount.appendingPathComponent("Music", isDirectory: true)
        var all: [URL] = []
        for album in 0 ..< 20 {
            try all += P5aFixture.files(in: music.appendingPathComponent("Album \(album)"), count: 40)
        }
        let store = try await P5aFixture.store(base) // the store is NOT on the volume
        let root = try await store.addRoot(music)
        _ = try await LibraryScanner().scan(root: music, folderID: root, into: store)
        #expect(try await store.trackCount(inFolder: root) == 800)
        let playlist = try await store.createPlaylist(name: "Road trip")
        let ids = try await store.tracks(inFolder: root).map(\.id)
        _ = try await store.appendEntries(playlistID: playlist, trackIDs: ids)
        for id in ids {
            try await store.incrementPlayCount(id: id, playedAt: 1_760_000_000)
        }

        // The reconcile: after its FIRST committed batch the volume is force-detached.
        let detached = LockedFlag()
        let result = try await LibraryScanner().scan(root: music, folderID: root, into: store, progress: { _ in
            if !detached.value {
                detached.value = true
                _ = Self.hdiutil(["detach", "-force", mount.path])
            }
        })
        let kept = try await store.trackCount(inFolder: root)
        let entries = try await store.entries(inPlaylist: playlist).count
        print("P5A LIB-02b seen=\(result.filesSeen) skipped=\(result.filesSkipped) swept=\(result.orphansSwept) "
            + "kept=\(kept)/800 playlistEntries=\(entries)/800")
        // Remount: every file is still there.
        #expect(Self.hdiutil(["attach", "-nobrowse", "-mountpoint", mount.path, image.path]) == 0)
        let onDisk = all.filter { FileManager.default.fileExists(atPath: $0.path) }.count
        print("P5A LIB-02b after remount: \(onDisk)/800 files on disk")
        #expect(onDisk == 800)
        #expect(result.orphansSwept == 0, "swept \(result.orphansSwept) songs that are on the volume")
        #expect(kept == 800 && entries == 800)
    }

    /// Control: a walk that DID see everything still reaps a genuinely deleted song.
    @Test("LIB-02 control: a genuine delete is still swept")
    func genuineDeleteIsSwept() async throws {
        let base = P5aFixture.base("lib02c")
        defer { try? FileManager.default.removeItem(at: base) }
        let music = base.appendingPathComponent("Music", isDirectory: true)
        let files = try P5aFixture.files(in: music.appendingPathComponent("A"), count: 5)
        let store = try await P5aFixture.store(base)
        let root = try await store.addRoot(music)
        _ = try await LibraryScanner().scan(root: music, folderID: root, into: store)
        try FileManager.default.removeItem(at: files[0])
        let result = try await LibraryScanner().scan(root: music, folderID: root, into: store)
        #expect(result.orphansSwept == 1)
        #expect(try await store.trackCount(inFolder: root) == 4)
    }

    static func hdiutil(_ arguments: [String]) -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return -1
        }
        process.waitUntilExit()
        return process.terminationStatus
    }
}

final class LockedFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var raised = false
    var value: Bool {
        get { lock.withLock { raised } }
        set { lock.withLock { raised = newValue } }
    }
}

@Suite("P5a LIB-02 — a different volume at the root's path", .serialized)
struct P5aSameNameVolumeTests {
    /// Two drives with the same volume name (two Samsung "T7"s, two "Untitled" / "NO NAME" sticks):
    /// with drive X away, drive Y mounts at X's old path. The app's volume-change handler restamps
    /// the root's (dev, inode) from whatever is there and reconciles it (LibraryModel+VolumeMonitor).
    @Test("LIB-02d: a same-named drive at the root's path does not delete the other drive's songs")
    func sameNamedVolumeAtRootPath() async throws {
        let base = P5aFixture.base("lib02d")
        defer { try? FileManager.default.removeItem(at: base) }
        let mount = base.appendingPathComponent("T7", isDirectory: true)
        try FileManager.default.createDirectory(at: mount, withIntermediateDirectories: true)
        let driveX = base.appendingPathComponent("x.dmg")
        let driveY = base.appendingPathComponent("y.dmg")
        for image in [driveX, driveY] {
            #expect(P5aSweepBreakTests.hdiutil(["create", "-size", "20m", "-fs", "APFS", "-volname", "T7", image.path]) == 0)
        }
        // Drive X: the user's library, 60 songs in a playlist.
        #expect(P5aSweepBreakTests.hdiutil(["attach", "-nobrowse", "-mountpoint", mount.path, driveX.path]) == 0)
        let music = mount.appendingPathComponent("Music", isDirectory: true)
        try P5aFixture.files(in: music.appendingPathComponent("Albums"), count: 60, prefix: "X")
        let store = try await P5aFixture.store(base)
        let signatureX = LibraryScanner.deviceInode(of: music)
        let root = try await store.addRoot(music, dev: signatureX.dev, inode: signatureX.inode)
        _ = try await LibraryScanner().scan(root: music, folderID: root, into: store)
        let playlist = try await store.createPlaylist(name: "Drive X favourites")
        _ = try await store.appendEntries(playlistID: playlist, trackIDs: try await store.tracks(inFolder: root).map(\.id))
        #expect(P5aSweepBreakTests.hdiutil(["detach", "-force", mount.path]) == 0)

        // Drive Y (same name) at the same path, with its own Music folder and 2 songs.
        #expect(P5aSweepBreakTests.hdiutil(["attach", "-nobrowse", "-mountpoint", mount.path, driveY.path]) == 0)
        try P5aFixture.files(in: music.appendingPathComponent("Other"), count: 2, prefix: "Y")
        // handleVolumeChange: reachable → restamp → reconcile.
        let reachable = RootReachabilityProbe.isReachable(music)
        let signatureY = LibraryScanner.deviceInode(of: music)
        try await store.restampRoot(id: root, dev: signatureY.dev, inode: signatureY.inode)
        let result = try await LibraryScanner().scan(root: music, folderID: root, into: store)
        let entryRows = try await store.entries(inPlaylist: playlist)
        let entries = entryRows.count
        var survivors: [String] = []
        for entry in entryRows {
            if let track = try await store.track(id: entry.trackID) {
                survivors.append("id\(track.id)→\(track.relativePath)\(track.name)")
            }
        }
        print("P5A LIB-02d surviving playlist rows now point at: \(survivors)")
        _ = P5aSweepBreakTests.hdiutil(["detach", "-force", mount.path])

        // Drive X comes back: its 60 songs are on it, but the library no longer has them.
        #expect(P5aSweepBreakTests.hdiutil(["attach", "-nobrowse", "-mountpoint", mount.path, driveX.path]) == 0)
        defer { _ = P5aSweepBreakTests.hdiutil(["detach", "-force", mount.path]) }
        let sameDevice = signatureX.dev == signatureY.dev && signatureX.inode == signatureY.inode
        print("P5A LIB-02d reachable=\(reachable) sameRootIdentity=\(sameDevice) seen=\(result.filesSeen) "
            + "swept=\(result.orphansSwept) playlistEntries=\(entries)/60")
        #expect(result.orphansSwept == 0, "a different drive at the path swept \(result.orphansSwept) of drive X's songs")
        #expect(entries == 60)
    }
}
