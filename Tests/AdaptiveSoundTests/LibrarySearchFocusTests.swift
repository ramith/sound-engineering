@testable import AdaptiveSound
import Foundation
import LibraryBrowseKit
import LibraryScan
import LibraryStore
import RigKit
import Testing

// MARK: - ⌘F: the Library's search from any tab, in one keystroke (R1.1-B, US-R1F-14)

//
// The real browse model. ⌘F is the app's Find command (`LibraryBrowseModel.beginSearch`): from any tab it
// shows the Library's Search page and asks it to focus its field (the focus intent the page takes —
// `LibrarySearchModel.takeFocusRequest`), keeping the field's text. The live keyboard pass on the 10k test
// library (Full Keyboard Access on) is the coordinator's; this is the intent behind it.

@MainActor
@Suite("⌘F — the Library's search from any tab (US-R1F-14)", .serialized, .timeLimit(.minutes(3)), .attachingLogTail)
struct LibrarySearchFocusTests {
    /// A browse model over a store-less library and the real view model over FakeEngine.
    @MainActor
    private struct World {
        let browse: LibraryBrowseModel
        let audio: AudioViewModel
        let library: LibraryModel
        private let defaults = IsolatedDefaults("LibrarySearchFocusTests")

        init() {
            QuietLog.install()
            audio = AudioViewModel(defaults: defaults.defaults, engine: FakeEngine())
            library = LibraryModel(storeless: ())
            browse = LibraryBrowseModel(audio: audio, library: library)
        }
    }

    @Test("⌘F from every tab lands on the Library's Search page and asks for its field",
          arguments: TabSelection.allCases)
    func fromEveryTab(tab: TabSelection) {
        let world = World()
        world.browse.selectCategory(.albums)
        world.audio.selectedTab = tab
        world.browse.beginSearch()
        #expect(world.audio.selectedTab == .library)
        #expect(world.browse.selectedCategory == .search)
        #expect(world.browse.path.isEmpty)
        #expect(world.browse.search.takeFocusRequest(), "⌘F did not ask the Search page to focus its field")
        #expect(!world.browse.search.takeFocusRequest(), "one ⌘F is one focus request")
    }

    @Test("⌘F keeps what the field holds — a field that already has focus keeps its text")
    func keepsText() {
        let world = World()
        world.browse.beginSearch()
        world.browse.search.text = "beyo"
        _ = world.browse.search.takeFocusRequest()
        world.audio.selectedTab = .eq
        world.browse.beginSearch()
        #expect(world.browse.search.text == "beyo")
        #expect(world.browse.search.takeFocusRequest())
    }

    @Test("⌘F over a page opened from a result, or a playlist, returns to the Search page")
    func leavesAPage() {
        let world = World()
        world.browse.beginSearch()
        world.browse.path.append(.album(5))
        world.browse.beginSearch()
        #expect(world.browse.path.isEmpty)
        world.browse.selectPlaylist(3)
        world.browse.beginSearch()
        #expect(world.browse.path.isEmpty)
        #expect(world.browse.selectedCategory == .search)
    }

    @Test("below the one search gate ⌘F searches nothing and shows nothing — the gate holds for ⌘F too")
    func twoCharacterGate() async {
        let world = World()
        world.browse.search.text = "b"
        await world.browse.search.run()
        #expect(world.browse.search.state == .idle)
        #expect(world.browse.search.results.isEmpty)
    }

    /// R1.1-B fix round (review S4): the search runs in the page's task, so a keystroke that supersedes it —
    /// which cancels that task — stops it, rather than leaving a whole-library read and rank running behind.
    @Test("a superseded ⌘F search is cancelled with its task, and publishes nothing")
    func cancelledSearchStops() async throws {
        let world = World()
        let folder = try await LibraryFolderFixture.make(titled: [("Halo", "Beyoncé"), ("Formation", "Beyoncé")])
        defer { folder.discard() }
        world.library.store = folder.store
        world.browse.search.text = "beyo"
        let superseded = Task { await world.browse.search.run() }
        superseded.cancel() // the next keystroke changes the page's task id
        await superseded.value
        #expect(world.browse.search.results.isEmpty, "a cancelled search still read, ranked and published")
        #expect(world.browse.search.state != .done)
        await world.browse.search.run() // the newer search runs to the end
        #expect(world.browse.search.results.songs.count == 2)
        #expect(world.browse.search.state == .done)
    }

    @Test("⌘F's results: the tabs' membership, ranked; “Show All” opens the tab filtered by the query")
    func rankedResultsAndShowAll() async throws {
        let world = World()
        let folder = try await LibraryFolderFixture.make(titled: [
            ("Halo", "Beyoncé"), ("Formation", "Beyoncé"), ("Beyond the Sea", "Bobby Darin"), ("Beyoncé", "Someone"),
        ])
        defer { folder.discard() }
        world.library.store = folder.store
        world.browse.search.text = "beyo"
        await world.browse.search.run()
        let songs = world.browse.search.results.songs.map(\.title)
        #expect(songs == ["Beyoncé", "Beyond the Sea", "Halo", "Formation"]) // the title first, then by artist
        #expect(world.browse.search.results.artists.map(\.name) == ["Beyoncé"])
        world.browse.showAll(.songs)
        #expect(world.browse.selectedCategory == .songs)
        #expect(world.browse.searchQuery == "beyo")
        world.browse.beginSearch()
        world.browse.showAll(.artists)
        #expect(world.browse.selectedCategory == .artists)
        #expect(world.browse.browseFilter == "beyo")
    }
}

/// A store with one music folder of tagged songs, in a temporary directory.
struct LibraryFolderFixture {
    let base: URL
    let music: URL
    let store: LibraryStore
    let folderID: Int64
    /// The songs' files, in order.
    let files: [URL]

    /// Songs titled and credited as given, scanned and tagged.
    static func make(titled songs: [(title: String, artist: String)]) async throws -> LibraryFolderFixture {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("library-fixture-\(UUID().uuidString)", isDirectory: true)
        let music = base.appendingPathComponent("Music", isDirectory: true)
        try FileManager.default.createDirectory(at: music, withIntermediateDirectories: true)
        let files = songs.indices.map { index in
            let url = music.appendingPathComponent(String(format: "%02d.flac", index))
            FileManager.default.createFile(atPath: url.path, contents: Data([UInt8(index), 1, 2, 3]))
            return url
        }
        let store = try await LibraryStore(url: base.appendingPathComponent("library.sqlite3"), appBuild: "test")
        let folderID = try await store.addRoot(music)
        _ = try await LibraryScanner().scan(root: music, folderID: folderID, into: store)
        for (file, song) in zip(files, songs) {
            let id = try #require(try await store.track(url: file)).id
            try await store.applyMetadata(TrackMetadata(title: song.title, artistName: song.artist), forTrack: id)
        }
        return LibraryFolderFixture(base: base, music: music, store: store, folderID: folderID, files: files)
    }

    func discard() {
        try? FileManager.default.removeItem(at: base)
    }
}
