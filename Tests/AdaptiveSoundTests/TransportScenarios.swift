@testable import AdaptiveSound
import Foundation
import PlaybackQueueKit
import Testing

// MARK: - Play, pause and stop against a busy engine (council C-15, P4-2)

//
// Each scenario runs the shipped `AudioViewModel` against `OnDeckEngineModel` with its queue busy
// (`holdTransport`): what the view model sends waits, and reaches the engine in the order the
// scenario says — as it arrived (`engineQueue` is FIFO), or overtaken by a later command on its hop
// there. Then everything lands, the view model finishes (`Rig.quiesce`), and the scenario reports
// whether the user hears what the app shows. These are council P4's E1 repros, on the real view model.

/// The order a scenario's two commands reach `engineQueue`.
enum CommandOrder: String, CaseIterable, Sendable, CustomStringConvertible {
    /// As they arrived: the queue is FIFO.
    case asArrived = "as they arrived"
    /// The later command overtook the earlier one on its hop to the queue.
    case overtaken = "the later one overtakes"

    var description: String {
        rawValue
    }
}

@MainActor
enum TransportScenarios {
    /// Run the held commands in `order`, then let everything land.
    private static func land(_ rig: Rig, _ order: CommandOrder) async throws {
        if order == .overtaken {
            for epoch in rig.engine.heldEpochs.sorted(by: >) {
                rig.engine.runHeld(epoch: epoch)
                try await rig.runViewModelOut()
            }
        }
        try await rig.quiesce()
        rig.tick()
        try await rig.quiesce()
    }

    /// STOP-THEN-PLAY: t0 plays; Stop, then a double-click on t2 while the engine is busy.
    static func stopThenPlay(pure: Bool, order: CommandOrder, commands: CommandSemantics) async throws -> Outcome {
        let rig = try await Rig.playing(tracks: 4, pure: pure, commands: commands)
        rig.engine.holdTransport(true)
        let calls = rig.engine.callCount
        rig.vm.stopPlayback()
        try await rig.waitForEngineCall(after: calls) // the stop's first call waits on the busy engine
        let callsAfterStop = rig.engine.callCount
        rig.vm.playTrack(at: 2)
        try await rig.waitForEngineCall(after: callsAfterStop)
        try await land(rig, order)
        let ok = rig.engine.current == track(2) && !rig.engine.ended && rig.vm.isPlaying && rig.shown == track(2)
        return Outcome(ok: ok, detail: "STOP-THEN-PLAY on \(OnDeckScenarios.pathName(pure)), \(order) [\(commands)]: "
            + rig.state)
    }

    /// PAUSE-THEN-PLAY: t0 plays; Pause, then Play while the engine is busy — it must resume.
    static func pauseThenPlay(pure: Bool, order: CommandOrder, commands: CommandSemantics) async throws -> Outcome {
        let rig = try await Rig.playing(tracks: 4, pure: pure, commands: commands)
        rig.engine.holdTransport(true)
        let calls = rig.engine.callCount
        rig.vm.pause()
        try await rig.waitForEngineCall(after: calls)
        let callsAfterPause = rig.engine.callCount
        rig.vm.play()
        try await rig.waitForEngineCall(after: callsAfterPause)
        try await land(rig, order)
        let ok = rig.engine.current == track(0) && !rig.engine.ended && rig.vm.isPlaying && rig.shown == track(0)
            && rig.vm.pausedResumePosition == nil
        return Outcome(ok: ok, detail: "PAUSE-THEN-PLAY on \(OnDeckScenarios.pathName(pure)), \(order) "
            + "[\(commands)]: " + rig.state)
    }

    /// STOP+PLAY-SAME-TURN: Stop and a click on t2 in one main-thread turn (two queued commands).
    static func stopAndPlaySameTurn(pure: Bool, commands: CommandSemantics) async throws -> Outcome {
        let rig = try await Rig.playing(tracks: 4, pure: pure, commands: commands)
        rig.engine.holdTransport(true)
        rig.vm.stopPlayback()
        rig.vm.playTrack(at: 2)
        try await land(rig, .asArrived)
        let ok = rig.engine.current == track(2) && !rig.engine.ended && rig.vm.isPlaying && rig.shown == track(2)
        return Outcome(ok: ok, detail: "STOP+PLAY-SAME-TURN on \(OnDeckScenarios.pathName(pure)) [\(commands)]: "
            + rig.state)
    }

    /// PLAY-THEN-NEXT: from stopped, Play, then Next before the start lands (a media key; a Pure DAC
    /// changing rate takes seconds). The user must hear the song the app shows: t1.
    static func playThenNext(pure: Bool, order: CommandOrder, commands: CommandSemantics) async throws -> Outcome {
        let rig = Rig(tracks: 4, commands: commands)
        rig.vm.pureModeEnabled = pure
        rig.engine.holdTransport(true)
        let calls = rig.engine.callCount
        rig.vm.play()
        try await rig.waitForEngineCall(after: calls)
        rig.vm.nextTrack()
        try await rig.waitForCommands() // (532ab79: Next during a start only re-selected — no command)
        try await land(rig, order)
        let ok = rig.engine.current == track(1) && !rig.engine.ended && rig.vm.isPlaying && rig.shown == track(1)
        return Outcome(ok: ok, detail: "PLAY-THEN-NEXT on \(OnDeckScenarios.pathName(pure)), \(order) [\(commands)]: "
            + rig.state)
    }

    /// SPACE-SPACE (PLAY-THEN-PAUSE): from stopped, Space, then Space again during the start. The second
    /// press pauses what the first started: one start at most, then silence, paused at the top — Play
    /// resumes there.
    static func spaceSpace(pure: Bool, order: CommandOrder, commands: CommandSemantics) async throws -> Outcome {
        let rig = Rig(tracks: 4, commands: commands)
        rig.vm.pureModeEnabled = pure
        rig.engine.holdTransport(true)
        let calls = rig.engine.callCount
        rig.vm.togglePlayPause()
        try await rig.waitForEngineCall(after: calls)
        let callsAfterFirst = rig.engine.callCount
        rig.vm.togglePlayPause()
        try await rig.waitForEngineCall(after: callsAfterFirst)
        try await land(rig, order)
        let starts = rig.engine.heard.count(where: \.isStart)
        let ok = starts <= 1 && rig.engine.current == nil && !rig.vm.isPlaying && rig.vm.pausedResumePosition == 0
        return Outcome(ok: ok, detail: "SPACE-SPACE on \(OnDeckScenarios.pathName(pure)), \(order) [\(commands)]: "
            + "\(starts) start(s); " + rig.state)
    }

    /// PAUSE-AT-END (P4-7): Pause in the last moments of the last song, and its end lands in the same
    /// turn, before the engine has stopped. The pause holds: Play resumes where it was, it is not an end
    /// of the queue (which dropped the place: Play started again from 0:00).
    static func pauseAtEnd(pure: Bool, commands: CommandSemantics) async throws -> Outcome {
        let rig = try await Rig.playing(tracks: 3, at: 2, pure: pure, commands: commands)
        rig.engine.holdTransport(true)
        rig.vm.playbackPosition = 199.9
        rig.vm.pause()
        rig.engine.trackEnds() // nothing on deck: the end flag
        rig.tick() // before the pause's task has run
        try await rig.quiesce()
        rig.tick()
        try await rig.quiesce()
        let ok = rig.vm.pausedResumePosition == 199.9 && !rig.vm.isPlaying && rig.engine.current == nil
        return Outcome(ok: ok, detail: "PAUSE-AT-END on \(OnDeckScenarios.pathName(pure)) [\(commands)]: " + rig.state)
    }
}
