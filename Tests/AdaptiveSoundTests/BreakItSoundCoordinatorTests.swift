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
}
