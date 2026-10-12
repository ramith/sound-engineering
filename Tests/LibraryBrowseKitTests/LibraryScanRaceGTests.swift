import Foundation
import LibraryScan
import LibraryStore
import Testing

// MARK: - Sprint G break-it: two REAL walks of one music folder at once (G-LIB-01b)

/// The scanner-level twin of G-LIB-01 (LibraryBreakItGTests): two real LibraryScanner walks of ONE
/// folder on disk, the way LibraryModel let them overlap before S10.8 G (the add or re-add of a folder
/// was never gated against a live reconcile of the same folder; `FolderWalkSchedule` now is, and the
/// store never lowers a stamp, which is what this pins). The first walk is the
/// slower one: its progress callback holds it 200 ms per 256-file batch, standing in for a walk that
/// leads over a cold disk or NAS (the second walk follows over a warm cache) or a utility-priority
/// add-scan behind a user-initiated reconcile (a volume mount, handleVolumeChange). The second walk
/// overtakes it, and its end-of-walk sweep deletes files that are on disk.
///
/// Needs the LibraryScan target, a test-only dependency of LibraryBrowseKitTests (Package.swift).
@Suite("Sprint G break-it — two walks of one folder on disk")
struct LibraryScanRaceGTests {
    /// Set once, read by the polling test: the first walk has written its first batch.
    private final class Signal: @unchecked Sendable {
        private let lock = NSLock()
        private var raised = false
        func raise() {
            lock.withLock { raised = true }
        }

        var isRaised: Bool {
            lock.withLock { raised }
        }
    }

    @Test("G-LIB-01b: an overlapping later walk never sweeps a file that is on disk", arguments: [false, true])
    func overlappingRealWalksKeepEveryFile(folderAlreadyScanned: Bool) async throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("sprint-g-scan-race-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: base) }
        let music = base.appendingPathComponent("Music", isDirectory: true)
        let fileCount = 1200
        for index in 0 ..< fileCount {
            let album = music.appendingPathComponent("Album \(index / 12)", isDirectory: true)
            try FileManager.default.createDirectory(at: album, withIntermediateDirectories: true)
            let name = String(format: "%02d Song.flac", index % 12)
            let path = album.appendingPathComponent(name).path
            #expect(FileManager.default.createFile(atPath: path, contents: Data([1])))
        }
        let store = try await LibraryStore(url: base.appendingPathComponent("library.sqlite3"), appBuild: "break-it")
        let root = try await store.addRoot(music)
        if folderAlreadyScanned {
            _ = try await LibraryScanner().scan(root: music, folderID: root, into: store)
        }

        // Walk A (the add-scan) leads, and is the slower walk.
        let firstBatch = Signal()
        let walkA = Task {
            try await LibraryScanner().scan(root: music, folderID: root, into: store, progress: { _ in
                firstBatch.raise()
                Thread.sleep(forTimeInterval: 0.2)
            })
        }
        while !firstBatch.isRaised {
            try await Task.sleep(for: .milliseconds(1))
        }
        // Walk B (the reconcile) starts once A has written a batch, so it takes the higher generation.
        let walkB = Task { try await LibraryScanner().scan(root: music, folderID: root, into: store) }
        let resultA = try await walkA.value
        let resultB = try await walkB.value

        #expect(resultB.generation > resultA.generation)
        #expect(resultA.orphansSwept + resultB.orphansSwept == 0,
                "the sweeps deleted \(resultA.orphansSwept + resultB.orphansSwept) of \(fileCount) files on disk")
        let kept = try await store.trackCount(inFolder: root)
        #expect(kept == fileCount)
    }
}
