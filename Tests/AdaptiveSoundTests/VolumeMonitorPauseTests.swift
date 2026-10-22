@testable import AdaptiveSound
import Clocks
import Foundation
import LibraryBrowseKit
import LibraryScan
import LibraryStore
import Testing

// MARK: - An unplugged folder reads paused, and its row says why (KI-LIB-02)

//
// The volume monitor asked for a walk of only the folders it could reach after a mount or an unmount,
// so a folder whose drive had just been unplugged kept reading "watching" until something else walked
// it. It now asks for a walk of every folder: the scanner refuses the one it cannot reach
// (`SweepRefusal`, `.rootVanished`), the folder is paused with that reason, and its Music Folders row
// says why. With the drive back, the next walk is evidence again and the pause ends. The real
// `LibraryModel` over a real store and real folders; the "drive" is a folder that leaves its path, as
// an unmounted volume's paths do.

@MainActor
@Suite("An unplugged folder reads paused, and says why (KI-LIB-02)", .timeLimit(.minutes(3)))
struct VolumeMonitorPauseTests {
    /// A store with one music folder on a "drive", walked once, under the real library model (no
    /// watcher, no metadata pass: `storeless`, then the store).
    @MainActor
    private struct Fixture {
        let base: URL
        let drive: URL
        let folderID: Int64
        let library: LibraryModel

        static func make() async throws -> Fixture {
            let base = FileManager.default.temporaryDirectory
                .appendingPathComponent("volume-pause-\(UUID().uuidString)", isDirectory: true)
            let drive = base.appendingPathComponent("T7", isDirectory: true)
            let music = drive.appendingPathComponent("Music", isDirectory: true)
            try FileManager.default.createDirectory(at: music, withIntermediateDirectories: true)
            for index in 0 ..< 3 {
                let song = music.appendingPathComponent("\(index) Song.flac")
                FileManager.default.createFile(atPath: song.path, contents: Data([UInt8(index), 1, 2]))
            }
            let store = try await LibraryStore(url: base.appendingPathComponent("library.sqlite3"), appBuild: "test")
            let folderID = try await store.addRoot(music)
            _ = try await LibraryScanner().scan(root: music, folderID: folderID, into: store)
            // The reconcile debounce (the product's 1 s) settles at once on an ImmediateClock: the test awaits
            // the walk it asks for, not a second of wall time per step.
            let library = LibraryModel(storeless: (), clock: ImmediateClock())
            library.store = store
            await library.refreshWatchedRoots()
            return Fixture(base: base, drive: drive, folderID: folderID, library: library)
        }

        /// The drive is unplugged: its folder leaves its path.
        func unplug() throws {
            try FileManager.default.moveItem(at: drive, to: base.appendingPathComponent("away", isDirectory: true))
        }

        /// The drive is plugged back in.
        func plugIn() throws {
            try FileManager.default.moveItem(at: base.appendingPathComponent("away", isDirectory: true), to: drive)
        }

        /// The volume monitor's answer to a mount or an unmount, run to its end: the debounced walk it
        /// asks for, then that walk.
        func volumeChanged() async {
            await library.handleVolumeChange()
            await library.reconcileDebounce[folderID]?.value
            await library.walkTasks[folderID]?.value
        }

        /// What the folder's Music Folders row says under its path, as `MusicFoldersSection` reads it.
        var rowStatus: MusicFolderStatus? {
            MusicFolderStatus(isScanning: false, pausedBy: library.reconcileState[folderID]?.pauseReason)
        }

        func discard() {
            try? FileManager.default.removeItem(at: base)
        }
    }

    @Test("a volume change pauses a folder whose drive was just unplugged, and its row says why")
    func unpluggedFolderIsPaused() async throws {
        let fixture = try await Fixture.make()
        defer { fixture.discard() }
        #expect(fixture.library.reconcileState[fixture.folderID] == .watching)
        #expect(fixture.rowStatus == nil)

        try fixture.unplug()
        await fixture.volumeChanged()

        #expect(fixture.library.reconcileState[fixture.folderID] == .paused(.rootVanished),
                "a just-unplugged folder still reads as watched")
        #expect(fixture.rowStatus?.caption == "Not found — is its drive connected?")
        #expect(fixture.rowStatus?.isPaused == true)
    }

    @Test("with the drive back, the next volume change ends the pause")
    func replugEndsThePause() async throws {
        let fixture = try await Fixture.make()
        defer { fixture.discard() }
        try fixture.unplug()
        await fixture.volumeChanged()
        try fixture.plugIn()

        await fixture.volumeChanged()

        #expect(fixture.library.reconcileState[fixture.folderID] == .watching)
        #expect(fixture.rowStatus == nil)
    }
}
