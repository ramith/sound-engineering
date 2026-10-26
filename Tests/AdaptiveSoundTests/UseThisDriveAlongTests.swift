@testable import AdaptiveSound
import Foundation
import LibraryBrowseKit
import LibraryScan
import LibraryStore
import RigKit
import Testing

// MARK: - "Use this drive" serves the whole drive (plan check §6, "Use this drive" (10); R1.1-B fix round)

//
// Two music folders on one drive, both paused when it went: one "Use This Drive…" choice moves both — each
// looked for at its own place on the drive as mounted now. A paused folder elsewhere stays paused. While the
// drive is checked, the rows say so; after, nothing is left checking.

@MainActor
@Suite("“Use this drive” moves the paused folders of the same drive (plan check §6 (10))", .serialized,
       .timeLimit(.minutes(3)), .attachingLogTail)
struct UseThisDriveAlongTests {
    /// Two music folders, "Rock" and "Jazz", on one drive (`Drive`), and "Other" elsewhere — each scanned, so
    /// each is bound to the drive it is on.
    @MainActor
    private struct World {
        let base: URL
        let store: LibraryStore
        let library: LibraryModel
        let browse: LibraryBrowseModel
        let folders: [String: Int64]
        private let defaults = IsolatedDefaults("UseThisDriveAlongTests")

        static func make() async throws -> World {
            QuietLog.install()
            let base = FileManager.default.temporaryDirectory
                .appendingPathComponent("drive-along-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
            let store = try await LibraryStore(url: base.appendingPathComponent("library.sqlite3"), appBuild: "test")
            var folders: [String: Int64] = [:]
            for (path, songs) in [("Drive/Rock", 2), ("Drive/Jazz", 3), ("Elsewhere/Other", 1)] {
                let folder = base.appendingPathComponent(path, isDirectory: true)
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                for index in 0 ..< songs {
                    FileManager.default.createFile(atPath: folder.appendingPathComponent("\(index).flac").path,
                                                   contents: Data([UInt8(index), 7, 7]))
                }
                let id = try await store.addRoot(folder)
                _ = try await LibraryScanner().scan(root: folder, folderID: id, into: store)
                folders[folder.lastPathComponent] = id
            }
            let library = LibraryModel(storeless: ())
            library.store = store
            return World(base: base, store: store, library: library, folders: folders)
        }

        private init(base: URL, store: LibraryStore, library: LibraryModel, folders: [String: Int64]) {
            self.base = base
            self.store = store
            self.library = library
            self.folders = folders
            browse = LibraryBrowseModel(audio: AudioViewModel(defaults: defaults.defaults, engine: FakeEngine()),
                                        library: library)
        }

        /// The drive mounted at a new name ("Drive 1"): the old path gone, every folder paused for it.
        func remountDrive() throws -> URL {
            let moved = base.appendingPathComponent("Drive 1", isDirectory: true)
            try FileManager.default.moveItem(at: base.appendingPathComponent("Drive"), to: moved)
            try FileManager.default.removeItem(at: base.appendingPathComponent("Elsewhere"))
            for id in folders.values {
                library.reconcileState[id] = .paused(.rootVanished)
            }
            return moved
        }
    }

    @Test("one choice for “Rock” moves “Jazz” on the same drive along; a folder elsewhere stays paused")
    func movesTheDrivesFolders() async throws {
        let world = try await World.make()
        defer { try? FileManager.default.removeItem(at: world.base) }
        let jazzIDs = try await world.store.tracks(inFolder: #require(world.folders["Jazz"])).map(\.id)
        let drive = try world.remountDrive()
        let rock = try #require(world.folders["Rock"])
        let rockPath = PathNormalizer.normalizedString(for: world.base.appendingPathComponent("Drive/Rock"))
        let notice = await world.browse.useDrive(drive.appendingPathComponent("Rock"),
                                                 for: LibraryFolder(id: rock, path: rockPath))
        #expect(notice == nil)
        #expect(world.browse.queueToast.toast?.message
            == "“Rock” now uses this drive — all 2 songs found. “Jazz” moved with it — all 3 songs found.")
        let jazz = try #require(world.folders["Jazz"])
        let roots = try await world.store.roots()
        #expect(roots.first { $0.id == jazz }?.path
            == PathNormalizer.normalizedString(for: drive.appendingPathComponent("Jazz")))
        #expect(try await world.store.tracks(inFolder: jazz).map(\.id).sorted() == jazzIDs.sorted(),
                "Jazz's songs kept their ids")
        #expect(world.library.reconcileState[rock]?.pauseReason == nil)
        #expect(world.library.reconcileState[jazz]?.pauseReason == nil)
        let other = try #require(world.folders["Other"])
        #expect(world.library.reconcileState[other] == .paused(.rootVanished),
                "a folder that is not on the drive stays paused")
        #expect(world.library.checkingDriveFolderIDs.isEmpty, "a row is left saying “Checking the drive…”")
        try await until("the reconcile walks after the rebind to end") { world.library.walkTasks.isEmpty }
    }

    @Test("a folder of the drive the new mount does not hold stays paused, and the chosen one is still moved")
    func aMissingSiblingStaysPaused() async throws {
        let world = try await World.make()
        defer { try? FileManager.default.removeItem(at: world.base) }
        let drive = try world.remountDrive()
        try FileManager.default.removeItem(at: drive.appendingPathComponent("Jazz"))
        let rock = try #require(world.folders["Rock"])
        let rockPath = PathNormalizer.normalizedString(for: world.base.appendingPathComponent("Drive/Rock"))
        _ = await world.browse.useDrive(drive.appendingPathComponent("Rock"),
                                        for: LibraryFolder(id: rock, path: rockPath))
        #expect(world.browse.queueToast.toast?.message == "“Rock” now uses this drive — all 2 songs found.")
        let jazz = try #require(world.folders["Jazz"])
        #expect(world.library.reconcileState[jazz] == .paused(.rootVanished))
        try await until("the reconcile walk after the rebind to end") { world.library.walkTasks.isEmpty }
    }
}
