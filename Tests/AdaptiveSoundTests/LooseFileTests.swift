@testable import AdaptiveSound
import AppKit
import Foundation
import LibraryBrowseKit
import LibraryScan
import LibraryStore
import PlaybackQueueKit
import RigKit
import Testing

// MARK: - Files from outside the library (R1.1-B, US-LIB-02 / US-PLIST-02)

//
// The real view model over FakeEngine, the real browse and playlists models over a real store. A file in
// no music folder plays from each entry point — Open… and a drop on the Library hand their files to
// `LibraryBrowseModel.openFiles`; Open With and a drop on the Dock icon arrive at the app delegate's
// `application(_:open:)` — and no `tracks` row is written; its queue slot names it by path (S5). Added to a
// playlist it becomes a song in no music folder, there after a relaunch, and wears the dead-file badge
// (unavailable) once its file is gone.

@MainActor
@Suite("Loose files — play without joining the library; join playlists (US-LIB-02)", .timeLimit(.minutes(3)),
       .serialized, .attachingLogTail)
struct LooseFileTests {
    /// The app's models over a launched FakeEngine view model and a real store, and a folder of files
    /// outside the library.
    @MainActor
    private struct World {
        let player: FakePlayer
        let library: LibraryModel
        let browse: LibraryBrowseModel
        let playlists: PlaylistsModel
        let store: LibraryStore
        let base: URL
        let outside: URL

        static func make() async throws -> World {
            let player = try await FakePlayer.launched(tracks: 2)
            let base = FileManager.default.temporaryDirectory
                .appendingPathComponent("loose-files-\(UUID().uuidString)", isDirectory: true)
            let outside = base.appendingPathComponent("Downloads", isDirectory: true)
            try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
            let store = try await LibraryStore(url: base.appendingPathComponent("library.sqlite3"), appBuild: "test")
            let library = LibraryModel(storeless: ())
            library.store = store
            let browse = LibraryBrowseModel(audio: player.vm, library: library)
            let playlists = PlaylistsModel(library: library, audio: player.vm)
            return World(player: player, library: library, browse: browse, playlists: playlists, store: store,
                         base: base, outside: outside)
        }

        /// A file named `name` in the folder outside the library.
        func file(_ name: String, bytes: Int = 16) -> URL {
            let url = outside.appendingPathComponent(name)
            FileManager.default.createFile(atPath: url.path, contents: Data(repeating: 7, count: bytes))
            return url
        }

        func discard() {
            try? FileManager.default.removeItem(at: base)
        }
    }

    /// Wait until `url` is the song the view model plays.
    private func waitUntilPlaying(_ url: URL, in world: World) async throws {
        let vm = world.player.vm
        try await until("the opened file to be the song playing") {
            vm.selectedTrackIndex.map { vm.queue[$0].file.absoluteURL == url } == true && vm.transportCommand == nil
        }
    }

    @Test("Open… and a drop: the file plays now, after the song playing — no tracks row, a loose slot")
    func openPlaysWithoutARow() async throws {
        let world = try await World.make()
        defer { world.discard() }
        try await world.player.play(at: 0)
        let demo = world.file("demo.flac")
        world.browse.openFiles([demo])
        try await waitUntilPlaying(demo, in: world)
        let vm = world.player.vm
        #expect(vm.queue.map(\.file.absoluteURL).firstIndex(of: demo) == 1) // after the song that was playing
        #expect(vm.queue.count == 3) // the queue kept
        let slot = try #require(vm.queue.first { $0.file.absoluteURL == demo })
        #expect(slot.file.trackID == nil)
        #expect(slot.file.slotRef == .loose(path: demo.path))
        #expect(try await world.store.track(url: demo) == nil)
        #expect(try await world.store.countRows(inTable: "tracks") == 0)
    }

    @Test("Open With (and a drop on the Dock icon): the app delegate plays the files, even before the window")
    func openWithPlays() async throws {
        let world = try await World.make()
        defer { world.discard() }
        let first = world.file("one.mp3")
        let second = world.file("two.flac")
        let delegate = AppDelegate()
        delegate.application(NSApplication.shared, open: [first, second]) // before the window is up: kept
        #expect(world.player.vm.queue.count == 2)
        delegate.browseModel = world.browse // the window appears
        try await waitUntilPlaying(first, in: world)
        let urls = world.player.vm.queue.map(\.file.absoluteURL)
        #expect(urls.firstIndex(of: second) == urls.firstIndex(of: first).map { $0 + 1 })
        #expect(try await world.store.countRows(inTable: "tracks") == 0)
    }

    @Test("a file the library holds plays as its song; a file of another kind is passed over and said so")
    func librarySongAndOtherKinds() async throws {
        let world = try await World.make()
        defer { world.discard() }
        let song = world.file("held.flac")
        let added = try await world.store.addLooseFile(#require(LibraryScanner.makeScannedFile(
            fileURL: song, root: song.deletingLastPathComponent()
        )))
        let notes = world.file("notes.txt")
        world.browse.openFiles([notes, song])
        try await waitUntilPlaying(song, in: world)
        let slot = try #require(world.player.vm.queue.first { $0.file.absoluteURL == song })
        #expect(slot.file.trackID == added)
        #expect(slot.file.slotRef == .track(id: added))
        #expect(!world.player.vm.queue.contains { $0.file.absoluteURL == notes })
        #expect(world.browse.queueToast.toast?.message
            == "Can’t play “notes.txt” — it isn’t an audio file this app plays.")
    }

    /// R1.1-B fix round (review N3): a multi-item add is several writes; when a later one fails, the ones before
    /// it are in the playlist — the add says how many went in (the toast's number), and the failure.
    @Test("a playlist add that fails part-way returns the songs that went in, and says the failure")
    func partialAddCountsWhatWentIn() async throws {
        let world = try await World.make()
        defer { world.discard() }
        let demo = world.file("demo.flac")
        let playlistID = try await world.store.createPlaylist(name: "Demos")
        await world.playlists.loadTree()
        let gone: Int64 = 9999 // a song that left the library while the menu was open
        let added = await world.playlists.add([.file(demo), .track(gone)], toPlaylist: playlistID)
        #expect(added == 1, "the add said \(added) songs went in")
        #expect(try await world.store.entries(inPlaylist: playlistID).count == 1)
        #expect(world.playlists.dialog != nil, "the failure was not said")
    }

    /// R1.1-B fix round (review N9): two opens land in the order they came, each whole.
    @Test("two opens, one after the other, land in the order they came")
    func opensInOrder() async throws {
        let world = try await World.make()
        defer { world.discard() }
        let first = world.file("first.flac")
        let second = world.file("second.flac")
        world.browse.appendFiles([first])
        world.browse.appendFiles([second])
        await world.browse.fileOpenTask?.value
        let urls = world.player.vm.queue.map(\.file.absoluteURL)
        #expect(urls.suffix(2) == [first, second])
    }

    @Test("added to a playlist: a song in no music folder, there after a relaunch; gone, it wears the dead-file badge")
    func playlistAddSurvivesRelaunchAndShowsMissing() async throws {
        let world = try await World.make()
        defer { world.discard() }
        let demo = world.file("demo.flac")
        let playlistID = try await world.store.createPlaylist(name: "Demos")
        await world.playlists.loadTree()
        let added = await world.playlists.add([.file(demo)], toPlaylist: playlistID)
        #expect(added == 1)
        let row = try #require(try await world.store.track(url: demo))
        #expect(row.folderID == nil) // a song in no music folder
        // Relaunch: the store opened again from its file.
        let reopened = try await LibraryStore(url: world.base.appendingPathComponent("library.sqlite3"),
                                              appBuild: "test")
        #expect(try await reopened.entries(inPlaylist: playlistID).map(\.trackID) == [row.id])
        // Gone: its folder is on the startup disk and the file is not — the dead-file badge.
        await world.playlists.loadDetail(id: playlistID)
        #expect(world.playlists.detail.first?.isAvailable == true)
        try FileManager.default.removeItem(at: demo)
        await world.playlists.loadDetail(id: playlistID)
        #expect(world.playlists.detail.first?.availability == .missing)
        #expect(world.playlists.detail.first?.isAvailable == false)
    }
}
