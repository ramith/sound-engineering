// LEVEL-MEASURING — "· measuring" only while a measurement is coming (R1.1-B fix round; the break-it's observation:
// a file that can never be analysed kept "5.1 → stereo · measuring" for good). The real view model over FakeEngine,
// with a real analysis store and its scheduler: the scheduler reports a file it cannot analyse, the coordinator keeps
// it, and the song playing's readout — what the fold badge reads — says its measurement is not coming. So does a
// store that will not open. FakePlayer's songs are files that do not exist: no identity, so no analysis.

@testable import AdaptiveSound
import Foundation
import RigKit
import Testing
import TrackLoudnessKit

@MainActor
@Suite("Leveling — '· measuring' only while a measurement is coming", .timeLimit(.minutes(3)), .attachingLogTail)
struct LevelingMeasuringTests {
    /// The engine's readout of a folded first play: the worst-case trim, nothing measured yet.
    private static let unmeasured = LevelingReadout(mode: .unknownCut, gainDb: -5, foldMeasured: false,
                                                    sourceLayout: "5.1")

    /// A folder of the test's own, removed by `discard`.
    private static func folder() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("leveling-measuring-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Song 0 plays its first, unmeasured play, its plan read into the view model.
    private static func playing(_ player: FakePlayer) async throws {
        player.engine.state.withLock { $0.signalPath.leveling = Self.unmeasured }
        try await player.play(at: 0)
        player.vm.refreshLevelingReadout()
    }

    @Test("LEVEL-VM-18: a song the scheduler cannot analyse is not 'measuring' — its analysis is not coming")
    func analysisThatCannotHappen() async throws {
        let folder = try Self.folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let player = try await FakePlayer.launched(tracks: 2)
        try player.vm.attachLevelingAnalysis(TrackAnalysisStore(directory: folder))
        try await Self.playing(player)
        try await until("the song playing's readout to say its measurement is not coming", cap: .seconds(30)) {
            player.vm.signalPath.leveling?.measurementComing == false
        }
        #expect(player.vm.signalPath.leveling?.foldMeasured == false) // the engine's plan, unchanged
    }

    @Test("LEVEL-VM-19: an analysis store that will not open: no song's measurement is coming")
    func storeThatWillNotOpen() async throws {
        let folder = try Self.folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let notAFolder = folder.appendingPathComponent("a-file", isDirectory: false)
        try Data("not a folder".utf8).write(to: notAFolder)
        let player = try await FakePlayer.launched(tracks: 2)
        player.vm.openLevelingAnalysis(in: notAFolder) { _ in Issue.record("a store opened where none can be") }
        try await Self.playing(player)
        try await until("the song playing's readout to say its measurement is not coming", cap: .seconds(30)) {
            player.vm.signalPath.leveling?.measurementComing == false
        }
    }

    @Test("LEVEL-VM-20: with no word of a failure, a first play is 'measuring' (the control)")
    func measurementComing() async throws {
        let player = try await FakePlayer.launched(tracks: 2)
        player.vm.levelingState.testSources = FakeLevelingSources()
        try await Self.playing(player)
        #expect(player.vm.signalPath.leveling?.measurementComing == true)
        #expect(player.vm.signalPath.leveling?.foldMeasured == false)
    }
}
