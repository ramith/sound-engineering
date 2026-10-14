import Foundation
import LibraryScan
import LibraryStore
import Testing

// MARK: - A song is missing only when its folder is there, on its own drive (KI-LIB-01)

/// "Remove Missing…" in a playlist removed every song whose file was not at its path — so with the music
/// drive unplugged it emptied the playlist for good (KI-LIB-01). A file that isn't there is evidence it
/// is GONE only when the folder that holds it is there, on its own drive: the same evidence a walk needs
/// before it sweeps (`SweepRefusal`). Otherwise the song is UNREACHABLE — it may be fine on a drive that
/// is away — and nothing offers to remove it.
@Suite("File availability — missing only on its own drive (KI-LIB-01)", .serialized)
struct FileAvailabilityTests {
    private func availability(_ urls: [URL], in folder: MusicFolder,
                              scanner: LibraryScanner = LibraryScanner()) async throws -> [FileAvailability] {
        let byURL = try await scanner.availability(of: urls, in: folder.store)
        return urls.map { byURL[$0] ?? .available }
    }

    @Test("on its own drive: there is available, deleted is missing")
    func ownDrive() async throws {
        let folder = try await MusicFolder.make("avail-own")
        defer { folder.discard() }
        let songs = try folder.songs(in: "Album", count: 3)
        _ = try await LibraryScanner().scan(root: folder.music, folderID: folder.root, into: folder.store)
        try FileManager.default.removeItem(at: songs[1])
        #expect(try await availability(songs, in: folder) == [.available, .missing, .available])
    }

    @Test("the drive unplugged: every song is unreachable, none missing")
    func driveUnplugged() async throws {
        let folder = try await MusicFolder.make("avail-unplugged")
        defer { folder.discard() }
        let songs = try folder.songs(in: "Album", count: 3)
        _ = try await LibraryScanner().scan(root: folder.music, folderID: folder.root, into: folder.store)
        try FileManager.default.moveItem(at: folder.music, to: folder.base.appendingPathComponent("away"))
        #expect(try await availability(songs, in: folder) == [.unreachable, .unreachable, .unreachable])
    }

    @Test("another drive at the folder's path: a song not on it is unreachable, not missing")
    func otherDriveAtThePath() async throws {
        let folder = try await MusicFolder.make("avail-other-drive")
        defer { folder.discard() }
        let songs = try folder.songs(in: "Album", count: 2)
        let drive = DriveAtRoot(RootIdentity(dev: 80, inode: 8, volume: "X-UUID"))
        _ = try await drive.scanner.scan(root: folder.music, folderID: folder.root, into: folder.store)
        try FileManager.default.removeItem(at: songs[0])
        drive.change(to: RootIdentity(dev: 80, inode: 8, volume: "Y-UUID"))
        #expect(try await availability(songs, in: folder, scanner: drive.scanner) == [.unreachable, .available])
        drive.change(to: RootIdentity(dev: 80, inode: 8, volume: "X-UUID"))
        #expect(try await availability(songs, in: folder, scanner: drive.scanner) == [.missing, .available])
    }

    @Test("an unbound folder whose path holds none of its songs: unreachable")
    func unboundFolderNoneOfItsSongs() async throws {
        let folder = try await MusicFolder.make("avail-unbound")
        defer { folder.discard() }
        let songs = try folder.songs(in: "Album", count: 2)
        let drive = DriveAtRoot(RootIdentity(dev: 81, inode: 8, volume: nil)) // a volume with no UUID
        _ = try await drive.scanner.scan(root: folder.music, folderID: folder.root, into: folder.store)
        try FileManager.default.removeItem(at: folder.music.appendingPathComponent("Album"))
        #expect(try await availability(songs, in: folder, scanner: drive.scanner) == [.unreachable, .unreachable])
    }

    @Test("a song in a folder the app may not read is unreachable, not missing", .enabled(if: getuid() != 0))
    func unreadableFolder() async throws {
        let folder = try await MusicFolder.make("avail-unreadable")
        let locked = folder.music.appendingPathComponent("Locked", isDirectory: true)
        defer {
            chmod(locked.path, 0o755)
            folder.discard()
        }
        let songs = try folder.songs(in: "Locked", count: 1) + folder.songs(in: "Open", count: 1)
        _ = try await LibraryScanner().scan(root: folder.music, folderID: folder.root, into: folder.store)
        #expect(chmod(locked.path, 0o000) == 0)
        #expect(try await availability(songs, in: folder) == [.unreachable, .available])
    }

    @Test("a song in no music folder: missing when its folder is there, unreachable when it is not")
    func looseSong() async throws {
        let folder = try await MusicFolder.make("avail-loose")
        defer { folder.discard() }
        let elsewhere = folder.base.appendingPathComponent("Downloads", isDirectory: true)
        try FileManager.default.createDirectory(at: elsewhere, withIntermediateDirectories: true)
        let loose = elsewhere.appendingPathComponent("single.flac")
        FileManager.default.createFile(atPath: loose.path, contents: Data([1]))
        #expect(try await availability([loose], in: folder) == [.available])
        try FileManager.default.removeItem(at: loose)
        #expect(try await availability([loose], in: folder) == [.missing])
        try FileManager.default.removeItem(at: elsewhere)
        #expect(try await availability([loose], in: folder) == [.unreachable])
    }
}
