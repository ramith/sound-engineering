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
    // MARK: LIB-02a — an unreadable subfolder

    /// A subfolder the walk may not read (its permissions changed, another user's folder, a folder
    /// privacy settings protect): its songs are still on disk.
    @Test("LIB-02a: an unreadable subfolder's songs survive a walk", .enabled(if: getuid() != 0),
          arguments: [0o000, 0o444] as [UInt16])
    func unreadableSubfolderIsNotSwept(mode: UInt16) async throws {
        let library = try await MusicFolder.make("lib02a")
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
        let locked = try await LibraryScanner().scan(root: library.music, folderID: library.root, into: library.store)
        #expect(locked.orphansSwept == 0)
        chmod(albumB.path, 0o755)

        #expect(try await library.store.trackCount(inFolder: library.root) == 10)
        #expect(try await library.store.entries(inPlaylist: playlist).map(\.trackID) == [song])
        #expect(try await library.store.userState(trackID: song)?.playCount == 2)
        let readable = try await LibraryScanner().scan(root: library.music, folderID: library.root, into: library.store)
        #expect(readable.orphansSwept == 0)
    }

    // MARK: C-55 — the evidence is scoped to what the walk could not read

    /// A subfolder the walk can NEVER read (a NAS's locked `#recycle`, another user's folder) made every
    /// walk of its music folder incomplete: a song deleted anywhere else in the folder was never swept,
    /// and the walk's refusal skipped the tag pass for its new songs (council C-55). The walk is
    /// evidence for everything it did read: only the songs under the unreadable subfolder are kept.
    @Test("C-55: an unreadable subfolder keeps its own songs, and the rest of the folder sweeps",
          .enabled(if: getuid() != 0), arguments: [0o000, 0o444] as [UInt16])
    func unreadableSubfolderDoesNotBlockSweepsElsewhere(mode: UInt16) async throws {
        let library = try await MusicFolder.make("c55")
        let recycle = library.music.appendingPathComponent("#recycle", isDirectory: true)
        defer {
            chmod(recycle.path, 0o755)
            library.discard()
        }
        let albumA = try library.songs(in: "Album A", count: 5)
        let recycled = try library.songs(in: "#recycle", count: 3, prefix: "Old")
        _ = try await LibraryScanner().scan(root: library.music, folderID: library.root, into: library.store)
        let playlist = try await library.playlistOfEverySong()
        #expect(chmod(recycle.path, mode_t(mode)) == 0)

        try FileManager.default.removeItem(at: albumA[0])
        let added = try library.songs(in: "Album A", count: 1, prefix: "New")[0]
        let walk = try await LibraryScanner().scan(root: library.music, folderID: library.root, into: library.store)

        #expect(walk.orphansSwept == 1, "a song deleted beside an unreadable subfolder was not swept")
        #expect(try await library.store.track(url: albumA[0]) == nil)
        #expect(try await library.store.track(url: added) != nil)
        #expect(try await library.store.entries(inPlaylist: playlist).count == 7)
        for song in recycled {
            let row = try await library.store.track(url: song)
            let id = try #require(row, "an unreadable subfolder's song was swept").id
            #expect(try await library.store.userState(trackID: id)?.playCount == 1)
        }
    }

    /// A music folder the walk cannot read at all (its permissions changed, a privacy setting denies
    /// it) is no evidence of anything: the walk is refused, and every song is kept.
    @Test("C-55: a music folder the walk cannot open is refused, every song kept", .enabled(if: getuid() != 0))
    func unreadableMusicFolderIsRefused() async throws {
        let library = try await MusicFolder.make("c55-root")
        defer {
            chmod(library.music.path, 0o755)
            library.discard()
        }
        try library.songs(in: "Album A", count: 4)
        _ = try await LibraryScanner().scan(root: library.music, folderID: library.root, into: library.store)
        #expect(chmod(library.music.path, 0o000) == 0)
        await #expect(throws: library.refusal(.incompleteWalk, stored: 4)) {
            try await LibraryScanner().scan(root: library.music, folderID: library.root, into: library.store)
        }
        chmod(library.music.path, 0o755)
        #expect(try await library.store.trackCount(inFolder: library.root) == 4)
    }

    // MARK: LIB-02b — the drive goes away mid-walk

    /// The drive goes away in the middle of a walk (a USB drive unplugged, a NAS share dropping, a
    /// laptop sleeping with a drive attached): the first batch was seen, the rest was not. Here the
    /// folder leaves its path after the first committed batch, as an unmounted drive's paths do.
    @Test("LIB-02b: a drive that goes away mid-walk keeps the songs the walk had not reached")
    func driveGoneMidWalkIsNotSwept() async throws {
        let library = try await MusicFolder.make("lib02b")
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
        let library = try await MusicFolder.make("lib02d")
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
        let library: MusicFolder
        let drive: DriveAtRoot
        let playlist: Int64
    }

    /// A folder bound to no drive yet — every folder right after the v8 upgrade, until a walk confirms
    /// its drive; here, first walked on a volume with no UUID, which leaves the same state. Its 40 songs
    /// are on drive X, in a playlist, played; then X goes away (its songs move out of the folder).
    private func unboundFolderWithDriveAway(_ tag: String) async throws -> UnboundFolder {
        let library = try await MusicFolder.make(tag)
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
        let library = try await MusicFolder.make("swap")
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
        let library = try await MusicFolder.make("lib02c")
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
        let library = try await MusicFolder.make("no-uuid")
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
