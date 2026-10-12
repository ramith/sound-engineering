import Foundation
import LibraryBrowseKit
import LibraryStore
import Testing

// MARK: - Sprint G break-it (S10.8 G — the Library tab, whole-app pass)

/// Red tests from the Sprint G whole-app break-it pass, Library lane (2026-10-12). Each drives the
/// store through the write paths the app uses, in a temporary folder. The findings and their
/// severities are in the Sprint G break-it report (g-breakit-library.md).
@Suite("Sprint G break-it — the Library tab over a real store")
struct LibraryBreakItGTests {
    /// A library in a temporary store with one music folder. The store never opens a file.
    private struct Library {
        let store: LibraryStore
        let folder: URL
        let musicFolder: URL
        let root: Int64

        static func make() async throws -> Library {
            let folder = FileManager.default.temporaryDirectory
                .appendingPathComponent("sprint-g-break-it-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let store = try await LibraryStore(url: folder.appendingPathComponent("library.sqlite3"),
                                               appBuild: "break-it")
            let musicFolder = folder.appendingPathComponent("Music", isDirectory: true)
            let root = try await store.addRoot(musicFolder)
            return Library(store: store, folder: folder, musicFolder: musicFolder, root: root)
        }

        func file(_ name: String) -> ScannedFile {
            ScannedFile(url: musicFolder.appendingPathComponent(name + ".flac"), relativePath: "", name: name,
                        format: "FLAC", fileSize: 1000, mtime: 1000)
        }

        func discard() {
            try? FileManager.default.removeItem(at: folder)
        }
    }

    // MARK: Two walks of one folder at once (G-LIB-01)

    /// Two walks of ONE music folder overlap whenever an add-scan (LibraryModel.performScan: adding a
    /// folder, or re-adding one, the only manual rescan) runs while a live reconcile of the same folder
    /// (runReconcile: an FSEvents change in it, or ANY volume mount or unmount, handleVolumeChange)
    /// walks it. runReconcile gates only on other reconciles, never on scanTask. The later walk takes
    /// the higher generation (max(last_seen_scan) + 1); where it passes a song before the earlier walk
    /// does, the earlier walk then LOWERS that song to its own generation (stampLastSeen writes
    /// unconditionally), and the later walk, ending, sweeps (last_seen_scan < its generation) a song
    /// that is on disk and that both walks saw: its play count, loved flag and, through ON DELETE
    /// CASCADE, every playlist entry of it.
    @Test("G-LIB-01: a song both overlapping walks saw survives the later walk sweep")
    func overlappingWalksNeverSweepASeenSong() async throws {
        let library = try await Library.make()
        defer { library.discard() }
        let store = library.store
        let song = library.file("Kept")
        let other = library.file("Other")

        // The folder as it was: an earlier scan saw both songs, and "Kept" is in a playlist.
        let first = try await store.beginScanGeneration()
        let ids = try await store.upsertReconciling([song, other], folderID: library.root, generation: first)
        let playlist = try await store.createPlaylist(name: "Road Trip")
        try await store.appendEntries(playlistID: playlist, trackIDs: [ids[0]])

        // Walk A (the add-scan) starts and writes a first batch.
        let walkA = try await store.beginScanGeneration()
        try await store.upsertReconciling([other], folderID: library.root, generation: walkA)
        // Walk B (the reconcile) starts after it, so its generation is higher, and reaches "Kept" first.
        let walkB = try await store.beginScanGeneration()
        #expect(walkB > walkA)
        try await store.upsertReconciling([other, song], folderID: library.root, generation: walkB)
        // Walk A reaches "Kept" after walk B did.
        try await store.upsertReconciling([song], folderID: library.root, generation: walkA)
        // Walk B ends: its sweep must reap only what neither walk saw.
        let swept = try await store.sweepOrphans(inFolders: [library.root], olderThan: walkB)

        #expect(swept == 0, "the sweep deleted \(swept) song(s) that are on disk")
        let remaining = try await store.allTracks(sortedBy: .name).map(\.name)
        #expect(remaining == ["Kept", "Other"])
        let entries = try await store.entries(inPlaylist: playlist)
        #expect(entries.count == 1, "the playlist entry of the song went with it (ON DELETE CASCADE)")
    }
}
