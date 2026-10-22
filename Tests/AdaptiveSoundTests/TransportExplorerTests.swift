@testable import AdaptiveSound
import Foundation
import PlaybackQueueKit
import Testing

// MARK: - Random schedules of play, pause, seek, stop and Next against a busy engine (council C-15)

//
// Council P4's E1 explorer, on the shipped view model. Each schedule plays t0 or starts from stopped
// (Pure or Enhanced), then interleaves a short script of what the user presses — Play, Pause, Space,
// Stop, Next, a seek, a click on a row, and the queue edits of council C-17 (Add to Queue, Play
// Next, a drag) — with what the engine does in its own time: run a command
// waiting on its busy queue (the oldest, as `engineQueue` runs them; or, under `.any`, whichever — the
// hops there keep no order), deliver an on-deck request, land a Pure open, end the track, a tick, and
// the view model's tasks running. Then everything lands, a few ticks, and the end state is checked:
//
//   app shows Playing ⇒ the engine plays     (the headline: "Playing" over silence, a frozen playhead)
//   the engine plays ⇒ the app shows Playing
//   both play ⇒ the same song, and the app's next is the engine's armed pick.
//
// A seam an edit had not yet reached (A2 / A2′, KI-PB-16 — the Engine sprint's seam identity) is the
// documented residual: counted apart, as the D41 explorer counts it (`Rig.tickJudgingSeam`).

@MainActor
struct TransportExplorer {
    /// How the engine runs the commands waiting on its queue.
    enum Order: String, Sendable {
        /// Oldest first: `engineQueue` is FIFO (council P4's E1 model).
        case asArrived = "as they arrived"
        /// Any of them: the hops to the queue keep no order.
        case any = "in any order"
    }

    struct Report: CustomStringConvertible {
        var schedules = 0
        var residualA2 = 0
        var violations: [String: (count: Int, first: String)] = [:]

        var violationCount: Int {
            violations.values.reduce(0) { $0 + $1.count }
        }

        func count(_ kind: String) -> Int {
            violations[kind]?.count ?? 0
        }

        var description: String {
            let found = violations.sorted { $0.key < $1.key }
                .map { "\($0.value.count)/\(schedules) \($0.key) — first: \($0.value.first)" }
            return "\(schedules) schedules, \(residualA2) A2/A2′ (residual), violations: "
                + (found.isEmpty ? "none" : found.joined(separator: "; "))
        }
    }

    static let silentUnderPlaying = "app shows playing, engine silent"

    private enum Verb: String, CaseIterable {
        case play, pause, toggle, stop, next, seek, click, append, playNext, drag
    }

    private enum Move: String {
        case user, run, deliver, open, end, tick, yield
    }

    let order: Order
    let commands: CommandSemantics
    private(set) var report = Report()
    private var rng: SplitMix64 // the app's (Debug/SplitMix64.swift): a failing schedule reproduces

    init(order: Order, commands: CommandSemantics, seed: UInt64) {
        self.order = order
        self.commands = commands
        rng = SplitMix64(seed: seed)
    }

    mutating func run(schedules: Int) async throws {
        for _ in 0 ..< schedules {
            try await schedule()
            report.schedules += 1
        }
    }

    private mutating func random(_ bound: Int) -> Int {
        Int(rng.next() % UInt64(bound))
    }

    private mutating func schedule() async throws {
        let pure = random(2) == 0
        let rig: Rig
        if random(2) == 0 {
            rig = try await Rig.playing(tracks: 5, pure: pure, commands: commands)
        } else {
            rig = Rig(tracks: 5, commands: commands)
            rig.vm.pureModeEnabled = pure
        }
        rig.engine.holdTransport(true)
        var script = (0 ..< 2 + random(3)).map { _ in Verb.allCases[random(Verb.allCases.count)] }
        var trace = [pure ? "Pure" : "Enhanced", rig.vm.isPlaying ? "playing t0" : "stopped"]
        var seams = 0
        var residualSince: Int? // where `heard` stood at an A2 / A2′ seam, until a fresh start
        for _ in 0 ..< 40 {
            if script.isEmpty, rig.engine.isIdle, random(4) == 0 {
                break
            }
            let move = nextMove(rig, scriptLeft: !script.isEmpty, seams: seams)
            if move == .user {
                let verb = script.removeFirst()
                trace.append(verb.rawValue)
                user(verb, rig: rig)
            } else if move == .tick {
                trace.append("tick")
                judge(rig.tickJudgingSeam(), rig: rig, trace: trace, residualSince: &residualSince)
            } else {
                try trace.append(await engineStep(move, rig: rig, seams: &seams))
            }
        }
        for verb in script {
            trace.append(verb.rawValue)
            user(verb, rig: rig)
        }
        // Everything lands, and the app follows what the engine did (an end, a seam).
        try await rig.quiesce()
        for _ in 0 ..< 3 {
            judge(rig.tickJudgingSeam(), rig: rig, trace: trace, residualSince: &residualSince)
            try await rig.quiesce()
        }
        let residualStands = residualSince.map { since in !rig.engine.heard[since...].contains(where: \.isStart) }
        if let kind = rig.disagreement, !(kind == "wrong song shown" && residualStands == true) {
            note(kind, detail: "\(trace.joined(separator: ",")) → " + rig.state)
        }
    }

    /// What a tick made of a seam: the residual A2 / A2′ is counted apart, and stands until a fresh
    /// start; any other mismatch is a violation.
    private mutating func judge(_ verdict: Rig.SeamVerdict, rig: Rig, trace: [String], residualSince: inout Int?) {
        switch verdict {
        case .none: return
        case .shown: residualSince = nil
        case .residual:
            report.residualA2 += 1
            residualSince = rig.engine.heard.count
        case .intoStalePick:
            note("a seam into a pick other than the newest applied request's",
                 detail: "\(trace.joined(separator: ",")) → " + rig.state)
        case .wrongSong:
            note("wrong song after a seam", detail: "\(trace.joined(separator: ",")) → " + rig.state)
        }
    }

    /// One step the engine (or the view model's own tasks, or the tick) takes in its own time; returns
    /// it for the trace.
    private mutating func engineStep(_ move: Move, rig: Rig, seams: inout Int) async throws -> String {
        switch move {
        case .run:
            let held = rig.engine.heldEpochs
            let epoch = order == .asArrived ? held[0] : held[random(held.count)]
            rig.engine.runHeld(epoch: epoch)
            return "run e\(epoch)"
        case .deliver:
            rig.engine.hop(rank: random(rig.engine.inboundCount))
        case .open:
            rig.engine.finishOpen(random(rig.engine.openingCount))
        case .end:
            seams += 1
            rig.engine.trackEnds()
        case .tick, .yield, .user:
            try await rig.runViewModelOut()
        }
        return move.rawValue
    }

    private mutating func nextMove(_ rig: Rig, scriptLeft: Bool, seams: Int) -> Move {
        var moves: [Move] = [.tick, .yield, .yield]
        if scriptLeft {
            moves += [.user, .user]
        }
        if !rig.engine.heldEpochs.isEmpty {
            moves += [.run, .run]
        }
        if rig.engine.inboundCount > 0 {
            moves.append(.deliver)
        }
        if rig.engine.openingCount > 0 {
            moves.append(.open)
        }
        if seams < 1, rig.engine.current != nil, !rig.engine.ended {
            moves.append(.end)
        }
        return moves[random(moves.count)]
    }

    private mutating func user(_ verb: Verb, rig: Rig) {
        switch verb {
        case .play: rig.vm.play()
        case .pause: rig.vm.pause()
        case .toggle: rig.vm.togglePlayPause()
        case .stop: rig.vm.stopPlayback()
        case .next: rig.vm.nextTrack()
        case .seek: rig.vm.seek(to: 42)
        case .click: rig.vm.playTrack(at: random(rig.vm.queue.count))
        case .append, .playNext, .drag: edit(verb, rig: rig)
        }
    }

    /// A queue edit (council C-17).
    private mutating func edit(_ verb: Verb, rig: Rig) {
        let count = rig.vm.queue.count
        switch verb {
        case .append: rig.vm.appendToQueue([audioFile(100 + count)])
        case .playNext: rig.vm.playNext([audioFile(100 + count)])
        default: rig.vm.moveByDrop(fromID: rig.vm.queue[random(count)].id, toIndex: random(count))
        }
    }

    private mutating func note(_ kind: String, detail: String) {
        let previous = report.violations[kind]
        report.violations[kind] = ((previous?.count ?? 0) + 1, previous?.first ?? detail)
    }
}

@Suite("AudioViewModel × engine — random transport schedules (council C-15)", .serialized, .timeLimit(.minutes(5)))
@MainActor
struct TransportExplorerTests {
    @Test("Explorer: 3000 schedules, commands run as they arrived — the app and the engine always agree")
    func asArrived() async throws {
        var explorer = TransportExplorer(order: .asArrived, commands: .dropsOvertaken, seed: 0x0C15_0001)
        try await explorer.run(schedules: 3000)
        print("[transport explorer] as arrived: \(explorer.report)")
        #expect(explorer.report.violationCount == 0, "\(explorer.report)")
    }

    @Test("Explorer: 3000 schedules, commands overtake each other — the app and the engine always agree")
    func anyOrder() async throws {
        var explorer = TransportExplorer(order: .any, commands: .dropsOvertaken, seed: 0x0C15_0002)
        try await explorer.run(schedules: 3000)
        print("[transport explorer] any order: \(explorer.report)")
        #expect(explorer.report.violationCount == 0, "\(explorer.report)")
    }

    @Test("Explorer ablation: an engine that runs overtaken commands shows Playing over silence")
    func executesEveryBreaks() async throws {
        var explorer = TransportExplorer(order: .any, commands: .executesEvery, seed: 0x0C15_0003)
        try await explorer.run(schedules: 600)
        print("[transport explorer] any order, \(CommandSemantics.executesEvery): \(explorer.report)")
        #expect(explorer.report.count(TransportExplorer.silentUnderPlaying) > 0, "\(explorer.report)")
    }
}
