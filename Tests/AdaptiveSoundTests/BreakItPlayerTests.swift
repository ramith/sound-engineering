@testable import AdaptiveSound
import Foundation
import LibraryBrowseKit
import LibraryScan
import LibraryStore
import PlaybackQueueKit
import RigKit
import Testing

// MARK: - R1.1-B break-it, the player half: red tests on the real view model and a real store (BI-P)

//
// Each test here was written to FAIL on the combined sprint branch (f52de075) and names what is wrong in
// its message. The shipped `AudioViewModel` over `FakeEngine`, the real `LibraryModel` / `LibraryBrowseModel`
// over a real `LibraryStore` in a folder of its own (the `QueueStateWorld` and `LibraryFolderFixture` the
// sprint's own suites use). Every wait is for a state.

@MainActor
@Suite("R1.1-B break-it — the queue's record and the library's ids (BI-P)", .timeLimit(.minutes(3)),
       .attachingLogTail)
struct BreakItQueueRecordTests {
    /// A song added to the library: the next `tracks` row.
    private func addSong(_ index: Int, to world: QueueStateWorld) async throws -> Int64 {
        let file = ScannedFile(url: track(index), name: "t\(index)", format: "FLAC", fileSize: 1, mtime: 1)
        let ids = try await world.store.upsert([file], folderID: nil, generation: world.store.beginScanGeneration())
        return try #require(ids.first)
    }

    @Test("BI-P01: a queued song leaves the library, a new one arrives — the restore keeps it out of the slot")
    func restoreDoesNotFollowAReusedTrackID() async throws {
        let world = try await QueueStateWorld(songs: 3)
        defer { world.discard() }
        let first = try await world.launch()
        first.vm.playNow((0 ..< 3).map(audioFile), startAt: 2) // t2: id 3, the library's newest song
        try await first.vm.settled()
        try movePlayhead(first, to: 50)
        first.vm.pause()
        try await first.vm.settled()
        _ = try await world.stored(after: first)
        // While the queue is kept: t2's file goes (a sweep, or "Use this drive" leaving it behind), and a
        // new song is scanned in. SQLite hands the new row the highest free rowid — the removed song's.
        try await world.store.delete(id: 3)
        let newcomer = try await addSong(7, to: world)
        try #require(newcomer == 3, "precondition: the new song took the removed song's id")

        let second = try await world.launch()
        #expect(!second.vm.queue.contains { $0.file.absoluteURL == track(7) },
                Comment(rawValue: "the restore put t7 — never queued — in t2's slot: the record names a library song "
                    + "by tracks.id alone, and a removed song's id is reused by the next song added "
                    + "(queue: \(second.vm.queue.map(\.file.name)))"))
        #expect(second.vm.pausedResumePosition == nil,
                "another song was selected at the gone song's place (\(second.vm.pausedResumePosition ?? 0) s)")
    }

    @Test("BI-P02: the live queue follows the library — a removed song's slot never becomes the song that took its id")
    func relinkDoesNotFollowAReusedTrackID() async throws {
        let world = try await QueueStateWorld(songs: 3)
        defer { world.discard() }
        let player = try await world.launch()
        player.vm.playNow((0 ..< 3).map(audioFile), startAt: 0)
        try await playing(player)
        // t2 (id 3) leaves the library and a new song takes id 3; t0 (id 1) really moves — the witness that
        // the queue re-read the library.
        try await world.store.delete(id: 3)
        let newcomer = try await addSong(7, to: world)
        try #require(newcomer == 3, "precondition: the new song took the removed song's id")
        try await world.store.moveTrack(id: 1, newURL: track(8), newFolderID: nil, newRelativePath: "")
        let library = try #require(player.vm.library)
        library.libraryRevision &+= 1 // a scan or a metadata pass finished
        try await until("the queue to follow t0 to its new path") { player.vm.queue[0].file.absoluteURL == track(8) }
        #expect(player.vm.queue[2].file.absoluteURL == track(2),
                Comment(rawValue: "t2's slot now plays \(player.vm.queue[2].file.name) — a song the listener never "
                    + "queued — because the relink reads the queue's songs by tracks.id and the id was reused"))
    }

    @Test("BI-P03: a file opened before the restore that the stored queue already holds is moved, not doubled")
    func openedBeforeTheRestoreIsNotDoubled() async throws {
        let world = try await QueueStateWorld(songs: 3)
        defer { world.discard() }
        let earlier = try await world.launch()
        earlier.vm.playNow((0 ..< 3).map(audioFile), startAt: 0)
        try await earlier.vm.settled()
        _ = try await world.stored(after: earlier)

        // Open With of t2 at launch, before the store is ready — what `openFiles` does for a library song.
        let player = try await FakePlayer.launched(tracks: 0)
        player.vm.playTrackNextNow(audioFile(2))
        try await playing(player)
        world.attach(player.vm)
        player.vm.hydrateQueueOnLaunch()
        try await player.vm.settled()
        // Opened AFTER the restore, `playTrackNextNow` moves t2's slot to after the song selected: t0, t2, t1.
        #expect(player.vm.queue.map(\.file.name) == ["t0", "t2", "t1"],
                Comment(rawValue: "the launch join doubled t2 (the two orders were meant to end in the same queue): "
                    + "\(player.vm.queue.map(\.file.name))"))
    }

    @Test("BI-P03b: no song selected in the stored queue — a file opened before the restore lands as it would after")
    func openedBeforeARestoreWithoutSelectionLandsAsAfter() async throws {
        let world = try await QueueStateWorld(songs: 3)
        defer { world.discard() }
        let earlier = try await world.launch()
        earlier.vm.appendToQueue([audioFile(0), audioFile(1)]) // queued, nothing selected
        try await earlier.vm.settled()
        _ = try await world.stored(after: earlier)

        let player = try await FakePlayer.launched(tracks: 0)
        player.vm.playTrackNextNow(audioFile(2)) // Open With at launch, before the store is ready
        try await playing(player)
        world.attach(player.vm)
        player.vm.hydrateQueueOnLaunch()
        try await player.vm.settled()
        // Opened AFTER the restore, nothing is selected, so `playTrackNextNow` puts t2 first: t2, t0, t1.
        #expect(player.vm.queue.map(\.file.name) == ["t2", "t0", "t1"],
                Comment(rawValue: "the launch join put the opened file at the end, opening after the restore puts "
                    + "it first: \(player.vm.queue.map(\.file.name))"))
    }
}

@MainActor
@Suite("R1.1-B break-it — loose files and \"Use this drive\" (BI-P)", .serialized, .timeLimit(.minutes(3)),
       .attachingLogTail)
struct BreakItLibraryTests {
    @Test("BI-P04: a song found on the new drive under another letter case keeps its id after the walk that follows")
    func caseOnlyDifferenceKeepsTheFoundSong() async throws {
        QuietLog.install()
        let fixture = try await LibraryFolderFixture.make(titled: [("One", "A"), ("Two", "A"), ("Three", "B")])
        defer { fixture.discard() }
        let store = fixture.store
        let library = LibraryModel(storeless: ())
        library.store = store
        let defaults = IsolatedDefaults("BreakItLibraryTests")
        let browse = LibraryBrowseModel(audio: AudioViewModel(defaults: defaults.defaults, engine: FakeEngine()),
                                        library: library)
        let song = try #require(try await store.track(url: fixture.files[2])).id
        let playlist = try await store.createPlaylist(name: "Keep")
        _ = try await store.appendEntries(playlistID: playlist, trackIDs: [song])
        // The copy on the other drive holds every song; one file's name is spelled in capitals there.
        let copy = fixture.base.appendingPathComponent("Music on T7 1", isDirectory: true)
        try FileManager.default.copyItem(at: fixture.music, to: copy)
        let lower = copy.appendingPathComponent("02.flac")
        let parked = copy.appendingPathComponent("02.tmp")
        try FileManager.default.moveItem(at: lower, to: parked)
        try FileManager.default.moveItem(at: parked, to: copy.appendingPathComponent("02.FLAC"))
        try #require(FileManager.default.fileExists(atPath: lower.path),
                     "precondition: this repro needs a case-insensitive volume (the Mac's default)")
        try FileManager.default.removeItem(at: fixture.music)
        library.reconcileState[fixture.folderID] = .paused(.rootVanished)

        _ = await browse.useDrive(copy, for: LibraryFolder(id: fixture.folderID, path: fixture.music.path))
        #expect(browse.queueToast.toast?.message == "“Music” now uses this drive — all 3 songs found.")
        try await until("the reconcile walk after the rebind to end") { library.walkTasks.isEmpty }
        #expect(try await store.track(id: song) != nil,
                Comment(rawValue: "the rebind found 02.FLAC as 02.flac and kept the song, then the walk saw a new "
                    + "file at another url and swept the kept row: its id, plays and playlist place are gone"))
        #expect(try await store.entries(inPlaylist: playlist).map(\.trackID) == [song],
                "the song left its playlist")
    }

    @Test("BI-P07: after \"Use this drive\", a song renamed on the new drive keeps its id, as anywhere else")
    func renameAfterARebindKeepsTheSong() async throws {
        QuietLog.install()
        let fixture = try await LibraryFolderFixture.make(titled: [("One", "A"), ("Two", "A"), ("Three", "B")])
        defer { fixture.discard() }
        let store = fixture.store
        let library = LibraryModel(storeless: ())
        library.store = store
        let defaults = IsolatedDefaults("BreakItLibraryTests")
        let browse = LibraryBrowseModel(audio: AudioViewModel(defaults: defaults.defaults, engine: FakeEngine()),
                                        library: library)
        let song = try #require(try await store.track(url: fixture.files[1])).id
        let playlist = try await store.createPlaylist(name: "Keep")
        _ = try await store.appendEntries(playlistID: playlist, trackIDs: [song])
        // Every song is on the new drive (a Finder copy: same names, sizes and dates; new inodes).
        let copy = fixture.base.appendingPathComponent("Music on T7 1", isDirectory: true)
        try FileManager.default.copyItem(at: fixture.music, to: copy)
        try FileManager.default.removeItem(at: fixture.music)
        library.reconcileState[fixture.folderID] = .paused(.rootVanished)
        _ = await browse.useDrive(copy, for: LibraryFolder(id: fixture.folderID, path: fixture.music.path))
        try await until("the reconcile walk after the rebind to end") { library.walkTasks.isEmpty }
        try #require(try await store.track(id: song) != nil, "precondition: the rebind kept the song")

        // The listener renames the song in Finder; the next walk sees it at its new name.
        try FileManager.default.moveItem(at: copy.appendingPathComponent("01.flac"),
                                         to: copy.appendingPathComponent("01 renamed.flac"))
        library.requestWalk(.reconcile, of: fixture.folderID)
        try await until("the walk after the rename to end") { library.walkTasks.isEmpty }
        // Without the rebind the same rename keeps the id (the S8.4 move-match on dev, inode, size, mtime).
        #expect(try await store.track(id: song)?.url.lastPathComponent == "01 renamed.flac",
                Comment(rawValue: "the renamed song lost its id, plays, love, rating and playlist place: the rebind "
                    + "kept the OLD drive's (dev, inode) on every song it moved, and the walk's upsert leaves "
                    + "them when size and date match, so the move-match never finds the song again"))
        #expect(try await store.entries(inPlaylist: playlist).map(\.trackID) == [song], "the song left its playlist")
    }

    @Test("BI-P05: Open With before the library store is ready — a library song ends up as that song, not a loose path")
    func openedBeforeTheStoreIsMatchedToTheLibrary() async throws {
        let fixture = try await LibraryFolderFixture.make(titled: [("One", "A"), ("Two", "B")])
        defer { fixture.discard() }
        let player = try await FakePlayer.launched(tracks: 0)
        let library = LibraryModel(storeless: ()) // the store still opening (a migration, a backup)
        player.vm.library = library
        let browse = LibraryBrowseModel(audio: player.vm, library: library)
        browse.openFiles([fixture.files[1]])
        try await until("the opened file to play") {
            player.vm.selectedSlotID != nil && player.vm.isPlaying && player.vm.transportCommand == nil
        }
        // The store opens; the composition root's `onStoreReady` runs the queue's launch restore.
        library.store = fixture.store
        player.vm.hydrateQueueOnLaunch()
        try await player.vm.settled()
        let id = try #require(try await fixture.store.track(url: fixture.files[1])).id
        #expect(player.vm.queue.map(\.file.trackID) == [id],
                Comment(rawValue: "a song the library holds stays a loose file for the session — its plays are not "
                    + "counted, and \"Use this drive\" will not follow it"))
        await player.vm.queueStateWriter.flush()
        let stored = try #require(try await fixture.store.queueState())
        #expect(try QueueResumeRecord(storedQueue: stored.record, offset: 0).slots == [.track(id: id)],
                "the record keeps a library song as a loose path")
    }
}
