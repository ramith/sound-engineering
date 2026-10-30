@testable import AdaptiveSound
import Foundation
import LevelingKit
import RigKit
import Testing
import TrackLoudnessKit

// MARK: - Break-it, R1.1-B sound half: the leveling coordinator on the real view model (FakeEngine)

@MainActor
@Suite("Break-it, sound: the leveling coordinator", .timeLimit(.minutes(3)), .attachingLogTail)
struct BreakItSoundCoordinatorTests {
    @Test("BI-S06: Play again after a stop — a song analysed during its first play starts from its analysis")
    func replayAfterStopUsesTheAnalysis() async throws {
        // A 5.1 song nobody has measured: its first play is the unknown cut on the fold's worst-case trim, "quieter
        // and clean"; its album is analysed while it plays (the horizon). The founder (2026-10-26): exact from the
        // second play.
        let key = LevelingSlot.key(of: track(0))
        let sources = FakeLevelingSources()
        let player = try await FakePlayer.launched(tracks: 1)
        player.vm.levelingState.testSources = sources
        player.vm.leveling = .track
        try await player.vm.settled()
        try await player.play(at: 0)
        try await player.vm.settled()
        let first = try #require(player.engine.state.withLock(\.startLevelings).last)
        #expect(first.mode == .unknownCut, "the precondition: an unmeasured first play")

        // The scheduler's analysis lands mid-song (`onAnalysed` → a refresh of the horizon).
        let record = try LevelingFixture.analysis(key, loudness: -12, truePeak: -1, surround: true,
                                                  lfe: LevelingFixture.copiedLfe)
        sources.state.withLock { $0.analyses[key] = record }
        player.vm.scheduleLevelingRefresh()
        try await player.vm.settled()
        #expect(player.vm.levelingState.knowledge.library.tracks[key]?.measurement != nil, "the analysis is known")

        // Stop, then Play on the same song: a new play from the top.
        player.vm.stopPlayback()
        try await player.vm.settled()
        try await player.play(at: 0)
        try await player.vm.settled()
        let starts = player.engine.state.withLock(\.startLevelings)
        #expect(starts.count == 2)
        let second = try #require(starts.last)
        #expect(second.source == .analysis && second.mode == .leveled && second.folded != nil,
                "the second play re-sent the first play's decision: \(second.mode) from \(second.source)")
    }

    @Test("BI-S12: a song that cannot be played says so and the queue moves on to the next song")
    func unplayableSongMovesOn() async throws {
        // The brief's clean failure for 11-broken-files, KI-LIB-12 (5.1 Opus) and KI-PB-22: a clear "can't play",
        // and the queue moves on. FakeEngine refuses the start as the bridge refuses a file that won't open.
        let player = try await FakePlayer.launched(tracks: 3)
        player.engine.state.withLock { $0.startError = AudioBridgeError.unsupportedFormat("opus") }
        player.vm.playTrack(at: 0)
        try await player.vm.settled()
        player.engine.state.withLock { $0.startError = nil }
        try await player.vm.settled()
        let started = player.calls.compactMap { call -> URL? in
            if case let .start(url, _, _, _, _) = call {
                return url
            }
            return nil
        }
        #expect(player.vm.errorMessage != nil, "the listener is told")
        #expect(started.contains(track(1)), "the queue stopped at the song it could not play: \(started)")
    }
}
