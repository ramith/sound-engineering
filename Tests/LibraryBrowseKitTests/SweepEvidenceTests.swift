import Foundation
import LibraryScan
import LibraryStore
import Testing

// MARK: - A sweep needs positive evidence (R1 — council P5A-01 / P5A-02, LIB-02)

/// The council panel's reproductions of LIB-02 (2026-10-13), kept as regression tests. A walk ends by
/// sweeping every song of its folder it did not SEE, and the delete takes the song's playlist entries
/// and play history with it; the panel showed the sweep deleting songs that were still on their drive
/// (an unreadable subfolder, a drive unplugged mid-walk, another drive with the same name at the
/// folder's path). Each test asserts the correct property — a song on its drive keeps its row, its
/// entries and its plays — and that a genuine delete is still swept.
///
/// The panel mounted disk images. Here the drive is the walk's seam (`LibraryScanner(rootIdentity:)`)
/// over real temporary folders, so the tests mount nothing and run as CI's ordinary user; the chmod
/// tests are skipped as root, which can read any folder.
@Suite("A sweep needs positive evidence (LIB-02)", .serialized)
struct SweepEvidenceTests {
    /// A store with one music folder, in a temporary directory.
    private struct Library {
        let base: URL
        let music: URL
        let store: LibraryStore
        let root: Int64

        static func make(_ tag: String) async throws -> Library {
            let base = FileManager.default.temporaryDirectory
                .appendingPathComponent("sweep-evidence-\(tag)-\(UUID().uuidString)", isDirectory: true)
            let music = base.appendingPathComponent("Music", isDirectory: true)
            try FileManager.default.createDirectory(at: music, withIntermediateDirectories: true)
            let store = try await LibraryStore(url: base.appendingPathComponent("library.sqlite3"), appBuild: "test")
            return try await Library(base: base, music: music, store: store, root: store.addRoot(music))
        }

        /// Write `count` songs into `folder` under the music folder.
        @discardableResult
        func songs(in folder: String, count: Int, prefix: String = "Song") throws -> [URL] {
            let directory = music.appendingPathComponent(folder, isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            return (0 ..< count).map { index in
                let url = directory.appendingPathComponent(String(format: "%03d \(prefix).flac", index))
                FileManager.default.createFile(atPath: url.path, contents: Data([UInt8(index & 0xFF), 1, 2]))
                return url
            }
        }

        /// A user playlist of every song in the folder, each played once — what a sweep must not take.
        func playlistOfEverySong() async throws -> Int64 {
            let playlist = try await store.createPlaylist(name: "Keep me")
            let ids = try await store.tracks(inFolder: root).map(\.id)
            _ = try await store.appendEntries(playlistID: playlist, trackIDs: ids)
            for id in ids {
                try await store.incrementPlayCount(id: id, playedAt: 1_760_000_000)
            }
            return playlist
        }

        /// The refusal a walk of this folder throws for `reason`, the folder holding `stored` songs.
        func refusal(_ reason: SweepRefusal.Reason, stored: Int) -> SweepRefusal {
            SweepRefusal(folderID: root, reason: reason, storedRowCount: stored)
        }

        func discard() {
            try? FileManager.default.removeItem(at: base)
        }
    }

    /// The drive a walk finds at the folder's path: an identity the test sets, and can change.
    private final class DriveAtRoot: @unchecked Sendable {
        private let lock = NSLock()
        private var current: RootIdentity?

        init(_ identity: RootIdentity?) {
            current = identity
        }

        func change(to identity: RootIdentity?) {
            lock.withLock { current = identity }
        }

        var scanner: LibraryScanner {
            LibraryScanner(rootIdentity: { _ in self.lock.withLock { self.current } })
        }
    }

    // MARK: LIB-02a — an unreadable subfolder

    /// A subfolder the walk may not read (its permissions changed, another user's folder, a folder
    /// privacy settings protect): its songs are still on disk.
    @Test("LIB-02a: an unreadable subfolder's songs survive a walk", .enabled(if: getuid() != 0),
          arguments: [0o000, 0o444] as [UInt16])
    func unreadableSubfolderIsNotSwept(mode: UInt16) async throws {
        let library = try await Library.make("lib02a")
        let albumB = library.music.appendingPathComponent("Album B", isDirectory: true)
        defer {
            chmod(albumB.path, 0o755)
            library.discard()
        }
        try library.songs(in: "Album A", count: 5)
        let bSongs = try library.songs(in: "Album B", count: 5)
        _ = try await LibraryScanner().scan(root: library.music, folderID: library.root, into: library.store)
        let song = try #require(try await library.store.track(url: bSongs[0])).id
        let playlist = try await library.store.createPlaylist(name: "Keep me")
        _ = try await library.store.appendEntry(playlistID: playlist, trackID: song)
        try await library.store.incrementPlayCount(id: song, playedAt: 1_760_000_000)
        try await library.store.incrementPlayCount(id: song, playedAt: 1_760_000_100)

        #expect(chmod(albumB.path, mode_t(mode)) == 0)
        await #expect(throws: library.refusal(.incompleteWalk, stored: 10)) {
            try await LibraryScanner().scan(root: library.music, folderID: library.root, into: library.store)
        }
        chmod(albumB.path, 0o755)

        #expect(try await library.store.trackCount(inFolder: library.root) == 10)
        #expect(try await library.store.entries(inPlaylist: playlist).map(\.trackID) == [song])
        #expect(try await library.store.userState(trackID: song)?.playCount == 2)
        let readable = try await LibraryScanner().scan(root: library.music, folderID: library.root, into: library.store)
        #expect(readable.orphansSwept == 0)
    }

    // MARK: LIB-02b — the drive goes away mid-walk

    /// The drive goes away in the middle of a walk (a USB drive unplugged, a NAS share dropping, a
    /// laptop sleeping with a drive attached): the first batch was seen, the rest was not. Here the
    /// folder leaves its path after the first committed batch, as an unmounted drive's paths do.
    @Test("LIB-02b: a drive that goes away mid-walk keeps the songs the walk had not reached")
    func driveGoneMidWalkIsNotSwept() async throws {
        let library = try await Library.make("lib02b")
        defer { library.discard() }
        for album in 0 ..< 20 {
            try library.songs(in: "Album \(album)", count: 40)
        }
        _ = try await LibraryScanner().scan(root: library.music, folderID: library.root, into: library.store)
        let playlist = try await library.playlistOfEverySong()
        let songs = try await library.store.tracks(inFolder: library.root).map(\.id)

        let away = library.base.appendingPathComponent("Unplugged", isDirectory: true)
        let unplugged = Flag()
        await #expect(throws: library.refusal(.rootVanished, stored: 800)) {
            try await LibraryScanner().scan(root: library.music, folderID: library.root, into: library.store,
                                            progress: { _ in
                                                if unplugged.raise() {
                                                    try? FileManager.default.moveItem(at: library.music, to: away)
                                                }
                                            })
        }
        try FileManager.default.moveItem(at: away, to: library.music) // plugged back in: all 800 are there

        #expect(try await library.store.tracks(inFolder: library.root).map(\.id) == songs)
        #expect(try await library.store.entries(inPlaylist: playlist).count == 800)
        #expect(try await library.store.userState(trackID: songs[0])?.playCount == 1)
        let back = try await LibraryScanner().scan(root: library.music, folderID: library.root, into: library.store)
        #expect(back.orphansSwept == 0)
    }

    // MARK: LIB-02d — another drive at the folder's path

    /// Two drives with the same name (two "T7" SSDs, two "Untitled" sticks) mount at the same path. With
    /// drive X away, drive Y — its own Music folder, 2 other songs — is at X's folder's path, and the app
    /// reconciles it (`handleVolumeChange`). The panel saw X's 60 songs swept and two of X's ids moved
    /// onto Y's songs; and (dev, inode) cannot tell the drives apart, so only the volume UUID can.
    @Test("LIB-02d: another drive at the folder's path is never walked, swept or re-stamped")
    func otherDriveAtRootPathIsNotSwept() async throws {
        let library = try await Library.make("lib02d")
        defer { library.discard() }
        let driveX = RootIdentity(dev: 16_777_234, inode: 2, volume: "X-UUID")
        let driveY = RootIdentity(dev: 16_777_235, inode: 3, volume: "Y-UUID")
        let drive = DriveAtRoot(driveX)
        try library.songs(in: "Albums", count: 60, prefix: "X")
        _ = try await drive.scanner.scan(root: library.music, folderID: library.root, into: library.store)
        let playlist = try await library.playlistOfEverySong()
        let xIDs = try await library.store.entries(inPlaylist: playlist).map(\.trackID)

        // X goes away; Y is at its path.
        let xAway = library.base.appendingPathComponent("X Albums", isDirectory: true)
        try FileManager.default.moveItem(at: library.music.appendingPathComponent("Albums"), to: xAway)
        let ySongs = try library.songs(in: "Other", count: 2, prefix: "Y")
        drive.change(to: driveY)
        await #expect(throws: library.refusal(.differentVolume, stored: 60)) {
            try await drive.scanner.scan(root: library.music, folderID: library.root, into: library.store)
        }
        #expect(try await library.store.trackCount(inFolder: library.root) == 60)
        #expect(try await library.store.entries(inPlaylist: playlist).map(\.trackID) == xIDs)
        for song in ySongs {
            #expect(try await library.store.track(url: song) == nil, "drive Y was walked")
        }
        let elsewhere = library.base.appendingPathComponent("Elsewhere", isDirectory: true)
        #expect(try await library.store.addRoot(elsewhere, dev: driveY.dev, inode: driveY.inode) != library.root,
                "the folder was re-stamped with drive Y's identity")

        // X comes back: every song keeps its id, entries and plays.
        try FileManager.default.removeItem(at: library.music.appendingPathComponent("Other"))
        try FileManager.default.moveItem(at: xAway, to: library.music.appendingPathComponent("Albums"))
        drive.change(to: driveX)
        let back = try await drive.scanner.scan(root: library.music, folderID: library.root, into: library.store)
        #expect(back.orphansSwept == 0)
        #expect(try await library.store.entries(inPlaylist: playlist).map(\.trackID) == xIDs)
        #expect(try await library.store.userState(trackID: xIDs[0])?.playCount == 1)
    }

    // MARK: An unbound folder (the breaker's ATK-6b / 6c)

    /// A folder bound to no drive, its drive away (see `unboundFolderWithDriveAway`).
    private struct UnboundFolder {
        let library: Library
        let drive: DriveAtRoot
        let playlist: Int64
    }

    /// A folder bound to no drive yet — every folder right after the v8 upgrade, until a walk confirms
    /// its drive; here, first walked on a volume with no UUID, which leaves the same state. Its 40 songs
    /// are on drive X, in a playlist, played; then X goes away (its songs move out of the folder).
    private func unboundFolderWithDriveAway(_ tag: String) async throws -> UnboundFolder {
        let library = try await Library.make(tag)
        try library.songs(in: "Albums", count: 40, prefix: "X")
        let drive = DriveAtRoot(RootIdentity(dev: 60, inode: 6, volume: nil))
        _ = try await drive.scanner.scan(root: library.music, folderID: library.root, into: library.store)
        #expect(try await library.store.boundVolume(ofRoot: library.root) == nil)
        let playlist = try await library.playlistOfEverySong()
        let away = library.base.appendingPathComponent("X Albums", isDirectory: true)
        try FileManager.default.moveItem(at: library.music.appendingPathComponent("Albums"), to: away)
        return UnboundFolder(library: library, drive: drive, playlist: playlist)
    }

    /// The first walk after the upgrade finds a same-named other drive at the folder's path. The panel
    /// saw it bind the folder to that drive and sweep 37 of 40 songs (3 moved onto the other drive's
    /// files) — and every later walk then refused the folder's own drive. A second walk must not be
    /// fooled either: had the first committed the other drive's songs, they would vouch for it now.
    @Test("ATK-6b: an unbound folder's first walk on another drive neither binds it nor sweeps")
    func unboundFolderFirstWalkOnAnotherDrive() async throws {
        let folder = try await unboundFolderWithDriveAway("atk6b")
        let (library, drive, playlist) = (folder.library, folder.drive, folder.playlist)
        defer { library.discard() }
        let ySongs = try library.songs(in: "Albums", count: 3, prefix: "Y")
        drive.change(to: RootIdentity(dev: 61, inode: 6, volume: "Y-UUID"))
        for _ in 0 ..< 2 {
            await #expect(throws: library.refusal(.unrecognizedFolder, stored: 40)) {
                try await drive.scanner.scan(root: library.music, folderID: library.root, into: library.store)
            }
        }
        #expect(try await library.store.boundVolume(ofRoot: library.root) == nil, "bound to the other drive")
        #expect(try await library.store.trackCount(inFolder: library.root) == 40)
        #expect(try await library.store.entries(inPlaylist: playlist).count == 40)
        for song in ySongs {
            #expect(try await library.store.track(url: song) == nil, "the other drive was walked")
        }

        // Drive X comes back: recognized, bound to X, nothing swept.
        try FileManager.default.removeItem(at: library.music.appendingPathComponent("Albums"))
        try FileManager.default.moveItem(at: library.base.appendingPathComponent("X Albums"),
                                         to: library.music.appendingPathComponent("Albums"))
        drive.change(to: RootIdentity(dev: 62, inode: 6, volume: "X-UUID"))
        let back = try await drive.scanner.scan(root: library.music, folderID: library.root, into: library.store)
        #expect(back.orphansSwept == 0)
        #expect(try await library.store.boundVolume(ofRoot: library.root) == "X-UUID")
        #expect(try await library.store.entries(inPlaylist: playlist).count == 40)
    }

    /// The drive is away, and a stale folder at its path on the startup disk holds two songs (an app
    /// wrote into /Volumes/<name> while it was unplugged). The panel saw all 30 songs swept.
    @Test("ATK-6c: an unbound folder whose drive is away is not swept by a stale folder at its path")
    func unboundFolderStaleFolderAtItsPath() async throws {
        let folder = try await unboundFolderWithDriveAway("atk6c")
        let (library, drive, playlist) = (folder.library, folder.drive, folder.playlist)
        defer { library.discard() }
        try library.songs(in: "Albums", count: 2, prefix: "Stale")
        drive.change(to: RootIdentity(dev: 63, inode: 7, volume: RootIdentity.startupDisk))
        await #expect(throws: library.refusal(.unrecognizedFolder, stored: 40)) {
            try await drive.scanner.scan(root: library.music, folderID: library.root, into: library.store)
        }
        #expect(try await library.store.boundVolume(ofRoot: library.root) == nil)
        #expect(try await library.store.trackCount(inFolder: library.root) == 40)
        #expect(try await library.store.entries(inPlaylist: playlist).count == 40)
        #expect(try await library.store.userState(trackID: library.store.tracks(inFolder: library.root)[0].id)?
            .playCount == 1)
    }

    // MARK: A drive swapped mid-walk commits nothing more

    /// The breaker's ATK-4: with the drive swapped mid-walk, the walk went on committing the other
    /// drive's songs (and moving the folder's rows onto them) until its end-of-walk check refused. The
    /// root is now checked before every batch, so the walk stops at the first batch after the swap.
    @Test("a drive swapped mid-walk stops the walk at the next batch, unbound to the other drive")
    func driveSwappedMidWalkCommitsNoMore() async throws {
        let library = try await Library.make("swap")
        defer { library.discard() }
        for album in 0 ..< 3 {
            try library.songs(in: "Album \(album)", count: 300)
        }
        let drive = DriveAtRoot(RootIdentity(dev: 70, inode: 7, volume: "X-UUID"))
        let driveY = RootIdentity(dev: 70, inode: 7, volume: "Y-UUID")
        await #expect(throws: library.refusal(.differentVolume, stored: 0)) {
            try await drive.scanner.scan(root: library.music, folderID: library.root, into: library.store,
                                         progress: { _ in drive.change(to: driveY) })
        }
        #expect(try await library.store.trackCount(inFolder: library.root) == 256,
                "batches after the swap were committed")
        #expect(try await library.store.boundVolume(ofRoot: library.root) == nil)
    }

    // MARK: Controls

    /// A walk that DID see everything still reaps a genuinely deleted song.
    @Test("LIB-02 control: a genuine delete after a complete walk is still swept")
    func genuineDeleteIsSwept() async throws {
        let library = try await Library.make("lib02c")
        defer { library.discard() }
        let songs = try library.songs(in: "A", count: 5)
        _ = try await LibraryScanner().scan(root: library.music, folderID: library.root, into: library.store)
        try FileManager.default.removeItem(at: songs[0])
        let result = try await LibraryScanner().scan(root: library.music, folderID: library.root, into: library.store)
        #expect(result.orphansSwept == 1)
        #expect(try await library.store.trackCount(inFolder: library.root) == 4)
    }

    /// A volume that reports no UUID (some network volumes) leaves its folder unbound: walked and swept
    /// as before while its songs are where the library has them (ATK-6b/6c: when none is, it is not).
    @Test("a folder on a volume with no UUID is walked and swept as before")
    func volumeWithoutUUIDKeepsTodaysBehaviour() async throws {
        let library = try await Library.make("no-uuid")
        defer { library.discard() }
        let songs = try library.songs(in: "A", count: 5)
        let drive = DriveAtRoot(RootIdentity(dev: 50, inode: 5, volume: nil))
        _ = try await drive.scanner.scan(root: library.music, folderID: library.root, into: library.store)
        try FileManager.default.removeItem(at: songs[0])
        drive.change(to: RootIdentity(dev: 50, inode: 5, volume: nil))
        let result = try await drive.scanner.scan(root: library.music, folderID: library.root, into: library.store)
        #expect(result.orphansSwept == 1)
    }

    /// Raised once, from the walk's progress callback.
    private final class Flag: @unchecked Sendable {
        private let lock = NSLock()
        private var raised = false

        /// Raise the flag; true the first time only.
        func raise() -> Bool {
            lock.withLock {
                defer { raised = true }
                return !raised
            }
        }
    }
}
