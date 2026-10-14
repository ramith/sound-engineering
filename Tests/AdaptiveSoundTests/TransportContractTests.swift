@testable import AdaptiveSound
import Foundation
import PlaybackQueueKit
import Testing

// MARK: - Play, pause and stop on a busy engine (council C-15)

//
// The shipped `AudioViewModel` against `OnDeckEngineModel` (the bridge's semantics, steps in the
// order each scenario sets). Under the design every scenario holds. On b5c4cd3 they were the
// council's P4 repros: Playing shown over a silent engine, a click lost, a second Space starting the
// song again. The ablation shows the engine's half is necessary: with the view model fixed, an engine
// that still runs an overtaken stop plays nothing while the app shows Playing.

@Suite("AudioViewModel × engine — play, pause and stop on a busy engine (council C-15)", .serialized)
@MainActor
struct TransportContractTests {
    @Test("STOP-THEN-PLAY: Stop, then a click on another song while the engine is busy — that song plays",
          arguments: [true, false], CommandOrder.allCases)
    func stopThenPlay(pure: Bool, order: CommandOrder) async throws {
        let outcome = try await TransportScenarios.stopThenPlay(pure: pure, order: order, commands: .dropsOvertaken)
        #expect(outcome.ok, "\(outcome)")
    }

    @Test("PAUSE-THEN-PLAY: Pause, then Play while the engine is busy — it resumes",
          arguments: [true, false], CommandOrder.allCases)
    func pauseThenPlay(pure: Bool, order: CommandOrder) async throws {
        let outcome = try await TransportScenarios.pauseThenPlay(pure: pure, order: order, commands: .dropsOvertaken)
        #expect(outcome.ok, "\(outcome)")
    }

    @Test("STOP+PLAY-SAME-TURN: Stop and a click in one turn — the click plays", arguments: [true, false])
    func stopAndPlaySameTurn(pure: Bool) async throws {
        let outcome = try await TransportScenarios.stopAndPlaySameTurn(pure: pure, commands: .dropsOvertaken)
        #expect(outcome.ok, "\(outcome)")
    }

    @Test("PLAY-THEN-NEXT: Next during a start — the user hears the song the app shows",
          arguments: [true, false], CommandOrder.allCases)
    func playThenNext(pure: Bool, order: CommandOrder) async throws {
        let outcome = try await TransportScenarios.playThenNext(pure: pure, order: order, commands: .dropsOvertaken)
        #expect(outcome.ok, "\(outcome)")
    }

    @Test("SPACE-SPACE: a second Space during a start pauses it — never a second start",
          arguments: [true, false], CommandOrder.allCases)
    func spaceSpace(pure: Bool, order: CommandOrder) async throws {
        let outcome = try await TransportScenarios.spaceSpace(pure: pure, order: order, commands: .dropsOvertaken)
        #expect(outcome.ok, "\(outcome)")
    }

    @Test("PAUSE-AT-END (P4-7): a Pause as the last song ends holds its place", arguments: [true, false])
    func pauseAtEnd(pure: Bool) async throws {
        let outcome = try await TransportScenarios.pauseAtEnd(pure: pure, commands: .dropsOvertaken)
        #expect(outcome.ok, "\(outcome)")
    }

    @Test("Ablation — an engine that runs an overtaken stop plays nothing under Playing", arguments: [true, false])
    func anEngineThatRunsAnOvertakenStopIsSilent(pure: Bool) async throws {
        let stop = try await TransportScenarios.stopThenPlay(pure: pure, order: .overtaken, commands: .executesEvery)
        let pause = try await TransportScenarios.pauseThenPlay(pure: pure, order: .overtaken, commands: .executesEvery)
        #expect(!stop.ok, "\(stop)")
        #expect(!pause.ok, "\(pause)")
    }
}
