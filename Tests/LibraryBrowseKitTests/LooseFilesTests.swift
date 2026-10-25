import Foundation
import LibraryBrowseKit
import Testing
import UniformTypeIdentifiers

// MARK: - Loose files: what an open plays and what it passes over (R1.1-B, US-LIB-02 / US-PLIST-02)

@Suite("LooseFiles — files from outside the library")
struct LooseFilesTests {
    private let song = URL(fileURLWithPath: "/Users/r/Downloads/demo.flac")
    private let upper = URL(fileURLWithPath: "/Users/r/Downloads/Live.MP3")
    private let opus = URL(fileURLWithPath: "/Users/r/Downloads/voice.opus")
    private let notes = URL(fileURLWithPath: "/Users/r/Downloads/notes.txt")
    private let folder = URL(fileURLWithPath: "/Users/r/Downloads/Album")

    @Test("an open plays the audio files the library admits, in order, each once; it passes over the rest")
    func plan() {
        let plan = LooseFiles.plan([song, notes, upper, folder, song, opus]) { $0 == folder }
        #expect(plan.playable == [song, upper, opus])
        #expect(plan.skipped == [notes, folder])
    }

    @Test("a folder named like an audio file is a folder, passed over")
    func folderNamedLikeAudio() {
        let tricky = URL(fileURLWithPath: "/Users/r/music.mp3")
        #expect(LooseFiles.plan([tricky]) { _ in true }.skipped == [tricky])
    }

    @Test("what the app says about what it passed over")
    func skippedMessages() {
        #expect(LooseFiles.skippedMessage([]) { _ in false } == nil)
        #expect(LooseFiles.skippedMessage([notes]) { _ in false }
            == "Can’t play “notes.txt” — it isn’t an audio file this app plays.")
        #expect(LooseFiles.skippedMessage([folder]) { _ in true }
            == "“Album” is a folder — add it under Music Folders to play it.")
        #expect(LooseFiles.skippedMessage([notes, folder]) { $0 == folder }
            == "Skipped 2 items that aren’t audio files this app plays.")
    }

    @Test("Open… offers the system's audio types for the kinds the library admits")
    func contentTypes() throws {
        let types = LooseFiles.contentTypes
        for ext in ["flac", "mp3", "wav", "m4a", "aiff", "ogg"] {
            let type = try #require(UTType(filenameExtension: ext))
            #expect(types.contains(type), "\(ext)")
        }
        #expect(types.allSatisfy { $0.conforms(to: .audio) })
        #expect(Set(types).count == types.count)
    }

    @Test("a playlist add of songs and files keeps the first of each, in order")
    func itemsToAdd() {
        let items: [PlaylistAddItem] = [.track(3), .file(song), .track(3), .file(upper), .file(song)]
        #expect(PlaylistAddDecision.itemsToAdd(items) == [.track(3), .file(song), .file(upper)])
        #expect(PlaylistAddItem.file(song).isFile)
        #expect(!PlaylistAddItem.track(3).isFile)
    }
}
