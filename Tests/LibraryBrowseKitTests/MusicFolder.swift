import Foundation
import LibraryScan
import LibraryStore

// MARK: - A music folder on a drive the test controls (SweepEvidenceTests, FileAvailabilityTests)

/// A store with one music folder, in a temporary directory: real files, a real store, the real scanner.
struct MusicFolder {
    let base: URL
    let music: URL
    let store: LibraryStore
    let root: Int64

    static func make(_ tag: String) async throws -> MusicFolder {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("music-folder-\(tag)-\(UUID().uuidString)", isDirectory: true)
        let music = base.appendingPathComponent("Music", isDirectory: true)
        try FileManager.default.createDirectory(at: music, withIntermediateDirectories: true)
        let store = try await LibraryStore(url: base.appendingPathComponent("library.sqlite3"), appBuild: "test")
        return try await MusicFolder(base: base, music: music, store: store, root: store.addRoot(music))
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

/// The drive a walk finds at the folder's path: an identity the test sets, and can change — the
/// scanner's seam (`LibraryScanner(rootIdentity:)`), so a test swaps or removes a drive without
/// mounting one.
final class DriveAtRoot: @unchecked Sendable {
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
