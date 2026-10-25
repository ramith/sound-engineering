@testable import AdaptiveSound
import Foundation
import PlaybackQueueKit
import RigKit
import Testing

// MARK: - Shuffle as a permutation with history, on the real view model (R1.1-B; C-16, KI-PB-03) (VM-SH)

//
// The shipped `AudioViewModel` against `OnDeckEngineModel` (`Rig`): the engine seams into what the view
// model armed, so what is heard is the view model's pick. The rule itself — each song once per pass,
// Previous through what played, the pass's ends — is `ShufflePassTests` (PlaybackQueueKit); these prove
// the wiring: the seams, Next, Previous, the edits and the on-deck pick all follow the one pass, and what
// the app shows is what plays (`Rig.disagreement`). The plan check's §6 shuffle counter-examples are named.

@MainActor
@Suite("Shuffle with history on the real view model (VM-SH)", .timeLimit(.minutes(3)), .attachingLogTail)
struct ShuffleTransportTests {
    /// Let the queue play on by itself until it stops (or `limit` songs started): every song heard, the
    /// one playing first. The app must show what plays at every step.
    private func playOut(_ rig: Rig, limit: Int = 1000) async throws -> [URL] {
        var heard = [rig.shown].compactMap(\.self)
        while rig.vm.isPlaying, heard.count < limit {
            try await rig.endTrackAndFollow()
            #expect(rig.disagreement == nil, "\(rig.state)")
            if rig.vm.isPlaying, let shown = rig.shown {
                heard.append(shown)
            }
        }
        return heard
    }

    /// Press `skip` and let everything it sent land.
    private func press(_ rig: Rig, _ skip: (AudioViewModel) -> Void) async throws {
        skip(rig.vm)
        try await rig.quiesce()
        #expect(rig.disagreement == nil, "\(rig.state)")
    }

    @Test("VM-SH-01 (§6 shuffle 1): 100 songs, one pass — each heard exactly once, then the queue ends",
          arguments: [false, true])
    func onePassThenTheEnd(pure: Bool) async throws {
        let rig = try await Rig.playing(tracks: 100, at: 17, pure: pure, shuffle: true)
        let heard = try await playOut(rig)
        #expect(heard.count == 100 && Set(heard) == Set((0 ..< 100).map(track)), "\(heard.count) songs heard")
        #expect(heard.first == track(17))
        #expect(!rig.vm.isPlaying && rig.engine.current == nil, "shuffle with Repeat off never ended: \(rig.state)")
        #expect(heard != (17 ..< 117).map { track($0 % 100) }, "the pass played the queue's own order")
    }

    @Test("VM-SH-02 (§6 shuffle 2): Previous ×6 walks back through what played; Next ×6 replays it, never re-rolled")
    func previousThenNext() async throws {
        let rig = try await Rig.playing(tracks: 10, at: 0, pure: false, shuffle: true)
        let heard = try await playOut(rig, limit: 7)
        let order = try #require(rig.vm.shufflePass?.permutation)
        for step in 1 ... 6 {
            try await press(rig) { $0.previousTrack() }
            #expect(rig.engine.current == heard[6 - step], "Previous ×\(step)")
        }
        for step in 1 ... 6 {
            try await press(rig) { $0.nextTrack() }
            #expect(rig.engine.current == heard[step], "Next ×\(step) after Previous")
        }
        #expect(rig.vm.shufflePass?.permutation == order, "the pass was re-rolled")
        let rest = try await playOut(rig)
        #expect(Set(heard + rest.dropFirst()).count == 10 && heard.count + rest.count - 1 == 10)
    }

    @Test("VM-SH-03 (§6 shuffle 3, founder 2026-10-25): at a pass's first song, Repeat off restarts the song")
    func previousAtThePassStartRestarts() async throws {
        let rig = try await Rig.playing(tracks: 5, at: 3, pure: false, shuffle: true)
        try await press(rig) { $0.previousTrack() }
        #expect(rig.vm.selectedTrackIndex == 3 && rig.engine.current == track(3))
        #expect(rig.engine.heard == [.start(track(3)), .start(track(3))], "the song did not restart")
        #expect(rig.vm.canGoPrevious, "a restart is a press Previous can make")
    }

    @Test("VM-SH-04 (§6 shuffle 3, founder 2026-10-25): at a pass's first song, Repeat All goes into the last pass")
    func previousAtThePassStartGoesBackUnderRepeatAll() async throws {
        let rig = try await Rig.playing(tracks: 4, at: 0, pure: false, shuffle: true, repeatMode: 1)
        let firstPass = try await playOut(rig, limit: 5) // the whole first pass, and the next one's first song
        #expect(rig.vm.shufflePass?.position == 0 && rig.vm.shufflePass?.history.count == 4)
        for step in 1 ... 4 {
            try await press(rig) { $0.previousTrack() }
            #expect(rig.engine.current == firstPass[4 - step], "Previous ×\(step) into the last pass")
        }
        // Next walks forward again, back into the pass it left — the same order.
        for step in 1 ... 4 {
            try await press(rig) { $0.nextTrack() }
            #expect(rig.engine.current == firstPass[step], "Next ×\(step)")
        }
    }

    @Test("VM-SH-05 (§6 shuffle 10): Repeat All — a new pass never begins with the song that just ended")
    func repeatAllNeverRepeatsAcrossPasses() async throws {
        let rig = try await Rig.playing(tracks: 3, at: 0, pure: false, shuffle: true, repeatMode: 1)
        let heard = try await playOut(rig, limit: 30)
        #expect(heard.count == 30)
        for index in 1 ..< heard.count {
            #expect(heard[index] != heard[index - 1], "song \(index) repeated the one before it")
        }
        for pass in stride(from: 0, to: 30, by: 3) {
            #expect(Set(heard[pass ..< pass + 3]).count == 3, "pass \(pass / 3) is not each song once")
        }
    }

    @Test("VM-SH-06 (§6 shuffle 4): shuffle on mid-song begins the pass at it; off goes on in order from it")
    func shuffleToggledMidSong() async throws {
        let rig = try await Rig.playing(tracks: 8, at: 3, pure: false)
        #expect(rig.engine.armed == track(4))
        try await press(rig) { $0.toggleShuffle() }
        let pass = try #require(rig.vm.shufflePass)
        #expect(pass.current == rig.vm.queue[3].id && pass.position == 0)
        #expect(rig.vm.pendingNextIndex.map { rig.vm.queue[$0].id } == pass.peekNext(repeatMode: 0))
        try await press(rig) { $0.toggleShuffle() }
        #expect(rig.vm.shufflePass == nil && rig.engine.armed == track(4), "off: in order from the song playing")
    }

    @Test("VM-SH-07 (§6 shuffle 5): an append mid-pass keeps the armed pick and plays once in the pass")
    func appendMidPass() async throws {
        let rig = try await Rig.playing(tracks: 6, at: 0, pure: false, shuffle: true)
        let before = try await playOut(rig, limit: 3)
        let armed = rig.engine.armed
        try await press(rig) { $0.appendToQueue([audioFile(6)]) }
        #expect(rig.engine.armed == armed, "the append re-rolled the armed pick")
        let rest = try await playOut(rig)
        let heard = before + rest.dropFirst()
        #expect(heard.count == 7 && Set(heard).count == 7 && heard.contains(track(6)))
    }

    @Test("VM-SH-08 (§6 shuffle 5): removing the armed song re-arms the pass's next; a removed song is never heard")
    func removeTheArmedSong() async throws {
        let rig = try await Rig.playing(tracks: 6, at: 0, pure: false, shuffle: true)
        let armedRow = try #require(rig.vm.pendingNextIndex)
        let removed = rig.vm.queue[armedRow].file.absoluteURL
        let after = try #require(rig.vm.shufflePass?.permutation[2])
        try await press(rig) { $0.removeTrack(at: armedRow) }
        #expect(rig.vm.pendingNextIndex.map { rig.vm.queue[$0].id } == after && rig.engine.armed != removed)
        let heard = try await playOut(rig)
        #expect(heard.count == 5 && !heard.contains(removed))
    }

    @Test("VM-SH-09 (§6 shuffle 6): Play Next under shuffle plays next and counts as played")
    func playNextUnderShuffle() async throws {
        let rig = try await Rig.playing(tracks: 6, at: 0, pure: false, shuffle: true)
        let before = try await playOut(rig, limit: 2)
        try await press(rig) { _ = $0.playNext([audioFile(6), audioFile(7)]) }
        #expect(rig.engine.armed == track(6))
        let rest = try await playOut(rig)
        #expect(Array(rest.prefix(3).dropFirst()) == [track(6), track(7)])
        let heard = before + rest.dropFirst()
        #expect(heard.count == 8 && Set(heard).count == 8, "a song played twice in the pass: \(heard.map(name))")
    }

    @Test("VM-SH-10 (§6 shuffle 7): Repeat One under shuffle repeats the song and leaves the pass as it is")
    func repeatOneUnderShuffle() async throws {
        let rig = try await Rig.playing(tracks: 5, at: 2, pure: false, shuffle: true, repeatMode: 2)
        let pass = rig.vm.shufflePass
        let heard = try await playOut(rig, limit: 4)
        #expect(heard == Array(repeating: track(2), count: 4))
        #expect(rig.vm.shufflePass == pass)
    }

    @Test("VM-SH-11: a song picked mid-pass plays now, counts as played, and the pass goes on")
    func pickedSongCountsAsPlayed() async throws {
        let rig = try await Rig.playing(tracks: 6, at: 0, pure: false, shuffle: true)
        let before = try await playOut(rig, limit: 2)
        let last = try #require(rig.vm.shufflePass?.permutation.last)
        let row = try #require(rig.vm.queueRow(of: last))
        try await press(rig) { $0.playTrack(at: row) }
        #expect(rig.engine.current == rig.vm.queue[row].file.absoluteURL)
        let rest = try await playOut(rig)
        let heard = before + rest
        #expect(heard.count == 6 && Set(heard).count == 6, "the picked song played again: \(heard.map(name))")
    }
}
