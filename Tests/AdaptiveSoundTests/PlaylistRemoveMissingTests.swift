@testable import AdaptiveSound
import Foundation
import LibraryBrowseKit
import LibraryScan
import LibraryStore
import Testing

// MARK: - Remove Missing never takes a song whose drive is only unplugged (KI-LIB-01)

//
// The real `PlaylistsModel` over a real store and real folders. A playlist's songs are on a music
// drive; the drive is unplugged (its folder leaves its path, as an unmounted volume's paths do). The
// songs can't be played, but that is no evidence they are gone: Remove Missing… must offer none of
// them. With the drive back, a song genuinely deleted from it IS offered, and only that one.

@MainActor
@Suite("Remove Missing — an unplugged drive's songs are kept (KI-LIB-01)", .serialized)
struct PlaylistRemoveMissingTests {
    /// A store with one music folder on a "drive" (a folder that can leave its path), three songs in it
    /// and a playlist of all three, under the real playlists model.
    @MainActor
    private struct Fixture {
        let base: URL
        let drive: URL
        let songs: [URL]
        let playlistID: Int64
        let playlists: PlaylistsModel

        static func make() async throws -> Fixture {
            let base = FileManager.default.temporaryDirectory
                .appendingPathComponent("remove-missing-\(UUID().uuidString)", isDirectory: true)
            let drive = base.appendingPathComponent("T7", isDirectory: true)
            let music = drive.appendingPathComponent("Music", isDirectory: true)
            try FileManager.default.createDirectory(at: music, withIntermediateDirectories: true)
            let songs = (0 ..< 3).map { index in
                let url = music.appendingPathComponent("\(index) Song.flac")
                FileManager.default.createFile(atPath: url.path, contents: Data([UInt8(index), 1, 2]))
                return url
            }
            let store = try await LibraryStore(url: base.appendingPathComponent("library.sqlite3"), appBuild: "test")
            let root = try await store.addRoot(music)
            _ = try await LibraryScanner().scan(root: music, folderID: root, into: store)
            let playlistID = try await store.createPlaylist(name: "Road Trip")
            var trackIDs: [Int64] = []
            for song in songs {
                try trackIDs.append(#require(try await store.track(url: song)).id)
            }
            _ = try await store.appendEntries(playlistID: playlistID, trackIDs: trackIDs)

            // The model reads the store the library holds; no watcher, reconcile or scan runs.
            let library = LibraryModel(storeless: ())
            library.store = store
            let defaults = try #require(UserDefaults(suiteName: "PlaylistRemoveMissingTests.\(UUID().uuidString)"))
            let audio = AudioViewModel(defaults: defaults, engine: FakeEngine())
            let playlists = PlaylistsModel(library: library, audio: audio)
            await playlists.loadTree()
            await playlists.loadDetail(id: playlistID)
            return Fixture(base: base, drive: drive, songs: songs, playlistID: playlistID, playlists: playlists)
        }

        /// The drive is unplugged: its folder leaves its path.
        func unplug() throws {
            try FileManager.default.moveItem(at: drive, to: base.appendingPathComponent("away", isDirectory: true))
        }

        /// The drive is plugged back in.
        func plugIn() throws {
            try FileManager.default.moveItem(at: base.appendingPathComponent("away", isDirectory: true), to: drive)
        }

        func discard() {
            try? FileManager.default.removeItem(at: base)
        }
    }

    @Test("with the drive unplugged, no song is offered for removal, and none is playable")
    func unpluggedDriveOffersNothing() async throws {
        let fixture = try await Fixture.make()
        defer { fixture.discard() }
        let playlists = fixture.playlists
        #expect(playlists.detail.allSatisfy { $0.isAvailable })

        try fixture.unplug()
        await playlists.loadDetail(id: fixture.playlistID)

        #expect(playlists.detail.count == 3)
        #expect(playlists.detail.allSatisfy { !$0.isAvailable }, "an unplugged drive's song still plays")
        #expect(playlists.missingEntryIDs.isEmpty, "an unplugged drive's songs are offered for removal")
        playlists.askToRemoveMissing()
        #expect(playlists.dialog == nil, "Remove Missing asked to remove an unplugged drive's songs")
    }

    @Test("with the drive back, a song deleted from it is offered — that one only")
    func genuineDeleteIsOffered() async throws {
        let fixture = try await Fixture.make()
        defer { fixture.discard() }
        let playlists = fixture.playlists

        try fixture.unplug()
        await playlists.loadDetail(id: fixture.playlistID)
        try fixture.plugIn()
        try FileManager.default.removeItem(at: fixture.songs[1])
        await playlists.loadDetail(id: fixture.playlistID)

        let deleted = try #require(playlists.detail.first { $0.display?.url == fixture.songs[1] }).id
        #expect(playlists.missingEntryIDs == [deleted])
        playlists.askToRemoveMissing()
        #expect(playlists.dialog == .confirmRemoveMissing([deleted]))
        await playlists.confirmRemoveMissing()
        #expect(playlists.detail.count == 2)
        #expect(playlists.detail.allSatisfy { $0.isAvailable })
    }
}
