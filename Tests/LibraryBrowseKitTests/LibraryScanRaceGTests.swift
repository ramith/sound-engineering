import Foundation
import LibraryScan
import LibraryStore
import RigKit
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
@Suite("Sprint G break-it — two walks of one folder on disk", .timeLimit(.minutes(3)))
struct LibraryScanRaceGTests {
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

        // Walk A (the add-scan) leads, and is the slower walk: held at its first batch, on a thread of its own
        // (it blocks inside the scan), until walk B has finished entirely. So B overtakes A for certain — not
        // when a sleep happens to make it likely — and the hold ends only when the test releases it.
        let executor = OffPoolExecutor("walk-A")
        let (resultA, resultB) = try await withHold("walk A at its first batch") { firstBatch in
            let walkA = Task(executorPreference: executor) {
                try await LibraryScanner().scan(root: music, folderID: root, into: store, progress: { _ in
                    firstBatch.wait()
                })
            }
            try await firstBatch.arrived()
            // Walk B (the reconcile) starts once A has written a batch, so it takes the higher generation, and
            // it runs to its end — its sweep included — while A is still held.
            let resultB = try await Task { try await LibraryScanner().scan(root: music, folderID: root, into: store) }
                .value
            firstBatch.release()
            return try await (walkA.value, resultB)
        }

        #expect(resultB.generation > resultA.generation)
        #expect(resultA.orphansSwept + resultB.orphansSwept == 0,
                "the sweeps deleted \(resultA.orphansSwept + resultB.orphansSwept) of \(fileCount) files on disk")
        let kept = try await store.trackCount(inFolder: root)
        #expect(kept == fileCount)
    }
}
