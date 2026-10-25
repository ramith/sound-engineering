@testable import AdaptiveSound
import Foundation
import LibraryBrowseKit
import LibraryScan
import LibraryStore
import RigKit
import Testing

// MARK: - "Use this drive" through the library model (R1.1-B, US-R1F-03 LIB-VOL-1)

//
// The real `LibraryModel` and browse model over a real store and real folders. A music folder is paused —
// its drive is gone — and the user points it at the folder on the drive that holds its songs now: the
// rebind keeps the songs found and removes the rest (the store's half is VerifyLibraryStore's RB-1..RB-5),
// the folder is no longer paused, the library's lists reload, and the toast says what happened. A drive
// holding none of its songs changes nothing, and the app says it is the wrong drive.

@MainActor
@Suite("“Use this drive” — rebind a paused folder (LIB-VOL-1)", .serialized, .timeLimit(.minutes(3)),
       .attachingLogTail)
struct UseThisDriveTests {
    @MainActor
    private struct World {
        let fixture: LibraryFolderFixture
        let library: LibraryModel
        let browse: LibraryBrowseModel
        private let defaults = IsolatedDefaults("UseThisDriveTests")

        static func make() async throws -> World {
            QuietLog.install()
            let fixture = try await LibraryFolderFixture.make(titled: [("One", "A"), ("Two", "A"), ("Three", "B")])
            let library = LibraryModel(storeless: ())
            library.store = fixture.store
            return World(fixture: fixture, library: library)
        }

        private init(fixture: LibraryFolderFixture, library: LibraryModel) {
            self.fixture = fixture
            self.library = library
            browse = LibraryBrowseModel(audio: AudioViewModel(defaults: defaults.defaults, engine: FakeEngine()),
                                        library: library)
        }

        /// The folder copied to `name` on "another drive", less the songs at `missing`; the old drive gone,
        /// and the folder paused for it, as a walk leaves it.
        func moveToAnotherDrive(_ name: String, missing: Set<Int> = []) throws -> URL {
            let copy = fixture.base.appendingPathComponent(name, isDirectory: true)
            try FileManager.default.copyItem(at: fixture.music, to: copy)
            for index in missing {
                let name = fixture.files[index].lastPathComponent
                try FileManager.default.removeItem(at: copy.appendingPathComponent(name))
            }
            try FileManager.default.removeItem(at: fixture.music)
            library.reconcileState[fixture.folderID] = .paused(.rootVanished)
            return copy
        }
    }

    @Test("found songs keep their ids, the rest are removed; the folder is unpaused and the toast says so")
    func rebindsAndSays() async throws {
        let world = try await World.make()
        defer { world.fixture.discard() }
        let store = world.fixture.store
        let ids = try await world.fixture.files.asyncIDs(in: store)
        let newRoot = try world.moveToAnotherDrive("Music on T7 1", missing: [2])
        let folder = LibraryFolder(id: world.fixture.folderID, path: world.fixture.music.path)
        let revision = world.library.libraryRevision
        let notice = await world.browse.useDrive(newRoot, for: folder)
        #expect(notice == nil) // done: said in the toast, not a dialog
        #expect(world.browse.queueToast.toast?.message
            == "“Music” now uses this drive — 2 songs found; 1 that isn’t on it was removed.")
        #expect(world.library.reconcileState[world.fixture.folderID]?.pauseReason == nil)
        #expect(world.library.libraryRevision > revision)
        #expect(world.browse.roots.map(\.path) == [PathNormalizer.normalizedString(for: newRoot)])
        let kept = try await store.tracks(inFolder: world.fixture.folderID).map(\.id)
        #expect(Set(kept) == Set(ids.prefix(2)))
        try await until("the reconcile walk after the rebind to end") { world.library.walkTasks.isEmpty }
        #expect(try await store.tracks(inFolder: world.fixture.folderID).map(\.id).sorted() == kept.sorted())
    }

    @Test("a drive holding none of the folder's songs: nothing changes, and the app says it is the wrong drive")
    func wrongDriveRefused() async throws {
        let world = try await World.make()
        defer { world.fixture.discard() }
        let elsewhere = world.fixture.base.appendingPathComponent("Other", isDirectory: true)
        try FileManager.default.createDirectory(at: elsewhere, withIntermediateDirectories: true)
        _ = try world.moveToAnotherDrive("Music on T7 1")
        let folder = LibraryFolder(id: world.fixture.folderID, path: world.fixture.music.path)
        let notice = await world.browse.useDrive(elsewhere, for: folder)
        #expect(notice?.message
            == "That’s not the drive for “Music” — none of its songs are on it. Nothing was changed.")
        #expect(world.library.reconcileState[world.fixture.folderID] == .paused(.rootVanished))
        #expect(try await world.fixture.store.tracks(inFolder: world.fixture.folderID).count == 3)
        #expect(try await world.fixture.store.roots().map(\.path)
            == [PathNormalizer.normalizedString(for: world.fixture.music)])
    }
}

private extension Array where Element == URL {
    /// Each file's song id in `store`, in order.
    func asyncIDs(in store: LibraryStore) async throws -> [Int64] {
        var ids: [Int64] = []
        for url in self {
            try ids.append(#require(try await store.track(url: url)).id)
        }
        return ids
    }
}
