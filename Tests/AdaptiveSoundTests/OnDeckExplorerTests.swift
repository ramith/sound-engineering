@testable import AdaptiveSound
import Foundation
import PlaybackQueueKit
import Testing

// MARK: - Random schedules of changes of mind, deliveries, opens, seams and ticks (council D41)

//
// Each schedule starts track 0 (Pure or Enhanced, a random order mode) and mixes, at random, what
// the user does while it plays (Play Next, shuffle, repeat, remove the on-deck row, Next, Add to
// Queue) with what the engine does in its own time (deliver a request — any of them —, land an open
// — any of them —, end the current track, a render callback after the end, a tick). Two invariants:
//
//   I1  when nothing is in flight, the engine's armed pick is the app's promised next (or the deck is
//       empty because that pick can't join gaplessly);
//   I2  every seam goes into the pick of the newest request the engine has applied, and after it
//       the app shows what plays — except when a request the engine had not applied yet (made
//       before the seam and still in flight, A2, or made between the seam and the tick, A2′) moved
//       the app's pick: the documented residual, counted apart (the seam carries no identity
//       until F1).
//
// Transport commands (pause, stop, seek) are left out: their races are P4-2, not this contract.

@MainActor
struct OnDeckExplorer {
    struct Report: CustomStringConvertible {
        var schedules = 0
        var residualA2 = 0
        var firstResidual = ""
        var violations: [String: (count: Int, first: String)] = [:]

        var violationCount: Int {
            violations.values.reduce(0) { $0 + $1.count }
        }

        var description: String {
            let found = violations.sorted { $0.key < $1.key }
                .map { "\($0.value.count)× \($0.key) — first: \($0.value.first)" }
            return "\(schedules) schedules, \(residualA2) A2/A2′ (residual; first: \(firstResidual)), violations: "
                + (found.isEmpty ? "none" : found.joined(separator: "; "))
        }
    }

    private enum Move: String {
        case tick, playNext, shuffle, repeatMode, removeOnDeck, next, append, deliver, open, end, renderAfterEnd
    }

    let semantics: ArmSemantics
    private(set) var report = Report()
    private var rng: SplitMix64 // the app's (Debug/SplitMix64.swift): a failing schedule reproduces

    init(semantics: ArmSemantics, seed: UInt64) {
        self.semantics = semantics
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

    /// What one schedule has done so far.
    private struct Progress {
        var trace: [String]
        var fresh = 100
        var userActions = 0
        var seams = 0
        var residual = false // an A2 / A2′ seam: the app may show another track until the next start
    }

    private mutating func schedule() async throws {
        let pure = random(3) != 0
        let incompatible: Set<URL> = [track(5), track(103)]
        let rig = try await Rig.playing(tracks: 12, pure: pure, semantics: semantics, shuffle: random(4) == 0,
                                        repeatMode: random(3), incompatible: incompatible)
        var progress = Progress(trace: [pure ? "Pure" : "Enhanced"])
        for _ in 0 ..< 24 {
            let move = nextMove(rig, progress: progress)
            progress.trace.append(move.rawValue)
            try await step(move, rig: rig, progress: &progress)
            if case .start = rig.engine.heard.last {
                progress.residual = false
            }
        }
        // Let everything land and the app follow, then check what it shows and promises. The tick acts
        // only once no start is on its way (council C-15): each waits for the view model to finish one.
        for _ in 0 ..< 6 {
            rig.engine.drain()
            try await rig.waitUntil("the view model's start to finish") { rig.viewModelSettled }
            try await tick(rig, progress: &progress)
        }
        rig.engine.drain()
        check(rig, pure: pure, incompatible: incompatible, progress: progress)
    }

    private mutating func step(_ move: Move, rig: Rig, progress: inout Progress) async throws {
        switch move {
        case .tick:
            try await tick(rig, progress: &progress)
        case .deliver:
            rig.engine.hop(rank: random(rig.engine.inboundCount))
        case .open:
            rig.engine.finishOpen(random(rig.engine.openingCount))
        case .end:
            rig.engine.trackEnds()
            progress.seams += 1
        case .renderAfterEnd:
            rig.engine.renderAfterEnd()
        default:
            progress.userActions += 1
            progress.fresh += 1
            user(move, rig: rig, fresh: progress.fresh)
            try await rig.settle()
        }
    }

    private mutating func nextMove(_ rig: Rig, progress: Progress) -> Move {
        var moves: [Move] = [.tick, .tick]
        if progress.userActions < 6 {
            moves += [.playNext, .shuffle, .repeatMode, .next, .append]
            if let pending = rig.vm.pendingNextIndex, pending != rig.vm.selectedTrackIndex {
                moves.append(.removeOnDeck)
            }
        }
        if rig.engine.inboundCount > 0 {
            moves += [.deliver, .deliver]
        }
        if rig.engine.openingCount > 0 {
            moves += [.open, .open]
        }
        if progress.seams < 2, rig.engine.current != nil, !rig.engine.ended, !rig.engine.hasUnprocessedSeam {
            moves.append(.end)
        }
        if rig.engine.canRenderAfterEnd {
            moves.append(.renderAfterEnd)
        }
        return moves[random(moves.count)]
    }

    private func user(_ move: Move, rig: Rig, fresh: Int) {
        switch move {
        case .playNext: rig.vm.playNext([audioFile(fresh)])
        case .shuffle: rig.vm.toggleShuffle()
        case .repeatMode: rig.vm.cycleRepeatMode()
        case .next: rig.vm.nextTrack()
        case .append: rig.vm.appendToQueue([audioFile(fresh)])
        case .removeOnDeck: rig.vm.removeTrack(at: rig.vm.pendingNextIndex ?? 0)
        default: break
        }
    }

    /// One tick; when it takes a seam, the app must show what plays — or the seam is A2 / A2′
    /// (`Rig.tickJudgingSeam`).
    private mutating func tick(_ rig: Rig, progress: inout Progress) async throws {
        let verdict = rig.tickJudgingSeam()
        try await rig.settle()
        switch verdict {
        case .none:
            return
        case .shown:
            progress.residual = false
        case .residual:
            report.residualA2 += 1
            if report.firstResidual.isEmpty {
                report.firstResidual = describe(rig, trace: progress.trace)
            }
            progress.residual = true
        case .intoStalePick:
            note("a seam into a pick other than the newest applied request's", rig: rig, trace: progress.trace)
        case .wrongSong:
            note("wrong song after a seam", rig: rig, trace: progress.trace)
        }
    }

    private mutating func check(_ rig: Rig, pure: Bool, incompatible: Set<URL>, progress: Progress) {
        let trace = progress.trace
        if rig.engine.heard.contains(where: \.isLateSeam) {
            note("a seam after the end", rig: rig, trace: trace)
        }
        guard rig.vm.isPlaying, let audible = rig.engine.current, !rig.engine.ended else { return }
        if audible != rig.shown, !progress.residual {
            note("wrong song shown", rig: rig, trace: trace)
        }
        let promised = rig.pending
        let emptyForAGap = rig.engine.armed == nil && pure && promised.map(incompatible.contains) == true
        if rig.engine.armed != promised, !emptyForAGap {
            note("the app's next is not the engine's armed", rig: rig, trace: trace)
        }
    }

    private func describe(_ rig: Rig, trace: [String]) -> String {
        "\(trace.joined(separator: ",")) → HEARS \(name(rig.engine.current)) / SHOWS "
            + "\(name(rig.shown)), armed \(name(rig.engine.armed)) / promised \(name(rig.pending)); "
            + "heard \(rig.engine.heard)"
    }

    private mutating func note(_ kind: String, rig: Rig, trace: [String]) {
        let detail = describe(rig, trace: trace)
        let previous = report.violations[kind]
        report.violations[kind] = ((previous?.count ?? 0) + 1, previous?.first ?? detail)
    }
}

@Suite("AudioViewModel × engine — random schedules (council D41)", .serialized)
@MainActor
struct OnDeckExplorerTests {
    @Test("Explorer: 3000 random schedules under the design — no violation; A2 / A2′ counted apart")
    func designHoldsOnRandomSchedules() async throws {
        var explorer = OnDeckExplorer(semantics: .design, seed: 0xD410001)
        try await explorer.run(schedules: 3000)
        #expect(explorer.report.violationCount == 0, "\(explorer.report)")
        print("[explorer] design: \(explorer.report)")
    }

    @Test("Explorer ablations: each replaced semantics breaks the invariants on random schedules",
          arguments: [ArmSemantics.refuse, .clearThenArm, .gatedReplaceAfterOpen, .gatedRetractFirst(endFinal: false)])
    func ablationsBreakOnRandomSchedules(_ semantics: ArmSemantics) async throws {
        var explorer = OnDeckExplorer(semantics: semantics, seed: 0xD410002)
        try await explorer.run(schedules: 300)
        #expect(explorer.report.violationCount > 0, "\(semantics) passed: \(explorer.report)")
        print("[explorer] \(semantics): \(explorer.report)")
    }
}
