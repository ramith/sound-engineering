@testable import AdaptiveSound
import Foundation
import PlaybackQueueKit

// MARK: - The D41 scenarios, as functions of the arm semantics (council D41)

//
// Each scenario runs the shipped `AudioViewModel` against `OnDeckEngineModel` with the given
// semantics and reports whether the user hears what the app shows (and promised). The tests run
// them under the design (they must hold) and under the semantics the design replaced (each
// ablation must break a named scenario) — see `OnDeckContractTests`.

/// A change of mind while a song plays: the six D41 rows.
enum ChangeOfMind: String, CaseIterable, Sendable, CustomStringConvertible {
    case playNext = "Play Next"
    case shuffleOn = "shuffle on"
    case shuffleOff = "shuffle off"
    case repeatAllToOne = "repeat all → one"
    case repeatOneToOff = "repeat one → off"
    case removeOnDeck = "remove the on-deck row"

    var description: String {
        rawValue
    }

    var shuffleBefore: Bool {
        self == .shuffleOff
    }

    var repeatBefore: Int {
        switch self {
        case .repeatAllToOne: 1
        case .repeatOneToOff: 2
        default: 0
        }
    }

    /// A shuffle pick is random: it can repeat the armed pick (no change of mind to test).
    var isRandom: Bool {
        self == .shuffleOn || self == .shuffleOff
    }

    @MainActor
    func perform(on model: AudioViewModel) {
        switch self {
        case .playNext: model.playNext([audioFile(9)])
        case .shuffleOn, .shuffleOff: model.toggleShuffle()
        case .repeatAllToOne, .repeatOneToOff: model.cycleRepeatMode()
        case .removeOnDeck: model.removeTrack(at: 1)
        }
    }
}

/// Which stale message reaches `engineQueue` when, in NEXT-NEXT.
enum NextNextOrder: String, CaseIterable, Sendable {
    /// The first start's prime is admitted; its open lands after the second start's, first.
    case staleOpenLandsFirst = "the stale open lands first"
    /// … lands last.
    case staleOpenLandsLast = "the stale open lands last"
    /// The first start's prime is still on its way when the second start runs; it arrives last.
    case staleRequestArrivesLast = "the stale request arrives last"
}

@MainActor
enum OnDeckScenarios {
    static func pathName(_ pure: Bool) -> String {
        pure ? "Pure" : "Enhanced"
    }

    /// D41: A plays with B armed; the user changes their mind; A ends.
    static func changeOfMind(_ change: ChangeOfMind, pure: Bool, semantics: ArmSemantics) async throws -> Outcome {
        let attempts = 64
        for attempt in 1 ... attempts {
            let rig = try await Rig.playing(pure: pure, semantics: semantics, shuffle: change.shuffleBefore,
                                            repeatMode: change.repeatBefore)
            let armedBefore = rig.engine.armed
            change.perform(on: rig.vm)
            try await rig.settle()
            let promised = rig.pending
            if change.isRandom, promised == armedBefore, attempt < attempts {
                continue // the shuffle pick repeated the armed one: try again
            }
            rig.engine.drain()
            let armedAfter = rig.engine.armed
            try await rig.endTrackAndFollow()
            let heard = rig.engine.current
            return Outcome(ok: armedAfter == promised && heard == promised && rig.shown == promised,
                           detail: "\(change) on \(pathName(pure)) [\(semantics)]: armed \(name(armedBefore)), "
                               + "promised \(name(promised)), armed after \(name(armedAfter)); after the end "
                               + "HEARS \(name(heard)) / SHOWS \(name(rig.shown))")
        }
        throw RigTimeout(what: "a shuffle pick other than the armed one")
    }

    /// Race 1: two quick Play Next (t10, then t11) while t1 is armed. Admission in the order made,
    /// then the second open lands first.
    static func pureRearmOrder(semantics: ArmSemantics) async throws -> Outcome {
        try await twoPlayNext(semantics: semantics, label: "PURE-REARM-ORDER") { engine in
            engine.hop(rank: 0)
            engine.hop(rank: 0)
            if engine.openingCount == 2 {
                engine.finishOpen(1)
            }
        }
    }

    /// Race 1b: the same two Play Next, but the newer request reaches `engineQueue` first.
    static func rearmDeliveryOrder(semantics: ArmSemantics) async throws -> Outcome {
        try await twoPlayNext(semantics: semantics, label: "REARM-DELIVERY-ORDER") { engine in
            engine.hop(rank: 1)
            engine.hop(rank: 0)
        }
    }

    private static func twoPlayNext(semantics: ArmSemantics, label: String,
                                    deliver: (OnDeckEngineModel) -> Void) async throws -> Outcome {
        let rig = try await Rig.playing(pure: true, semantics: semantics)
        rig.vm.playNext([audioFile(10)])
        rig.vm.playNext([audioFile(11)])
        try await rig.settle()
        let promised = rig.pending
        deliver(rig.engine)
        rig.engine.drain()
        let armed = rig.engine.armed
        let openedStale = rig.engine.opened.contains(track(10))
        try await rig.endTrackAndFollow()
        let heard = rig.engine.current
        return Outcome(ok: armed == promised && heard == promised && rig.shown == promised,
                       detail: "\(label) [\(semantics)]: promised \(name(promised)), armed \(name(armed)) "
                           + "(t10 opened: \(openedStale)); after the end HEARS \(name(heard)) / "
                           + "SHOWS \(name(rig.shown))")
    }

    /// Race 2: Next, then Next again while the first start's prime is in flight.
    static func nextNext(pure: Bool, order: NextNextOrder, semantics: ArmSemantics) async throws -> Outcome {
        let rig = try await Rig.playing(pure: pure, semantics: semantics)
        rig.vm.nextTrack() // start t1; its prime asks for t2
        try await rig.settle()
        if order != .staleRequestArrivesLast {
            rig.engine.hop(rank: 0) // t2 admitted (Pure: opening)
        }
        rig.vm.nextTrack() // start t2; its prime asks for t3
        try await rig.settle()
        switch order {
        case .staleOpenLandsFirst:
            rig.engine.hop(rank: 0)
        case .staleOpenLandsLast:
            rig.engine.hop(rank: 0)
            if rig.engine.openingCount == 2 {
                rig.engine.finishOpen(1)
            }
        case .staleRequestArrivesLast:
            rig.engine.hop(rank: 1) // t3's request first, then the stale t2
            rig.engine.hop(rank: 0)
        }
        rig.engine.drain()
        let armed = rig.engine.armed
        try await rig.endTrackAndFollow()
        let heard = rig.engine.heard
        let ok = armed == track(3) && rig.engine.current == track(3) && rig.shown == track(3)
            && heard.count(where: { $0 == .start(track(2)) || $0 == .seam(track(2)) }) == 1
        return Outcome(ok: ok, detail: "NEXT-NEXT on \(pathName(pure)), \(order.rawValue) [\(semantics)]: armed "
            + "under t2 \(name(armed)); heard \(heard); SHOWS \(name(rig.shown))")
    }

    /// Pure: Play Next t9 is admitted (t1 comes off) and A ends before t9's file opened.
    static func retractThenEnd(semantics: ArmSemantics) async throws -> Outcome {
        let rig = try await Rig.playing(pure: true, semantics: semantics)
        rig.vm.playNext([audioFile(9)])
        try await rig.settle()
        rig.engine.hop(rank: 0)
        rig.engine.trackEnds() // before t9's open lands
        try await rig.follow()
        let heard = rig.engine.heard
        let ok = heard == [.start(track(0)), .start(track(9))] && rig.shown == track(9)
        return Outcome(ok: ok, detail: "RETRACT-THEN-END [\(semantics)]: heard \(heard); SHOWS \(name(rig.shown))")
    }

    /// Pure: as RETRACT-THEN-END, but t9's open lands after the end and before the app's tick, and
    /// the render keeps calling.
    static func lateArmAfterEnd(semantics: ArmSemantics) async throws -> Outcome {
        let rig = try await Rig.playing(pure: true, semantics: semantics)
        rig.vm.playNext([audioFile(9)])
        try await rig.settle()
        rig.engine.hop(rank: 0)
        rig.engine.trackEnds()
        rig.engine.finishOpen(0) // the late open
        rig.engine.renderAfterEnd()
        try await rig.follow()
        try await rig.follow()
        let heard = rig.engine.heard
        let ok = heard == [.start(track(0)), .start(track(9))] && rig.engine.current == track(9)
            && rig.shown == track(9) && rig.vm.isPlaying
        return Outcome(ok: ok, detail: "LATE-ARM-AFTER-END [\(semantics)]: heard \(heard); HEARS "
            + "\(name(rig.engine.current)) / SHOWS \(name(rig.shown)), playing \(rig.vm.isPlaying)")
    }

    /// Pure: Play Next a track that can't join gaplessly (another rate): a gap, then that track.
    static func rearmIncompatible(semantics: ArmSemantics) async throws -> Outcome {
        let rig = try await Rig.playing(pure: true, semantics: semantics, incompatible: [track(9)])
        rig.vm.playNext([audioFile(9)])
        try await rig.settle()
        rig.engine.drain()
        let armed = rig.engine.armed
        try await rig.endTrackAndFollow()
        let heard = rig.engine.heard
        let ok = heard == [.start(track(0)), .start(track(9))] && rig.shown == track(9)
        return Outcome(ok: ok, detail: "REARM-INCOMPATIBLE [\(semantics)]: armed \(name(armed)); heard \(heard); "
            + "SHOWS \(name(rig.shown))")
    }

    /// Pure: Play Next a file that won't open: the old pick must not play; the app tries the file
    /// and reports it.
    static func rearmOpenFails(semantics: ArmSemantics) async throws -> Outcome {
        let rig = try await Rig.playing(pure: true, semantics: semantics, unreadable: [track(9)])
        rig.vm.playNext([audioFile(9)])
        try await rig.settle()
        rig.engine.drain()
        try await rig.endTrackAndFollow()
        let heard = rig.engine.heard
        let ok = heard == [.start(track(0))] && rig.shown == track(9) && rig.vm.errorMessage != nil
            && !rig.vm.isPlaying
        return Outcome(ok: ok, detail: "REARM-OPEN-FAILS [\(semantics)]: heard \(heard); SHOWS "
            + "\(name(rig.shown)), error \(rig.vm.errorMessage ?? "none"), playing \(rig.vm.isPlaying)")
    }

    /// AMEND-1: t0 plays; the user clicks t1, then t3; the two starts reach the engine in the other
    /// order. (Which track then plays is the transport-command race, P4-2 — out of scope.) The newest
    /// playback's on-deck must still arm: the join stays gapless.
    static func startOvertake(pure: Bool, semantics: ArmSemantics) async throws -> Outcome {
        let rig = try await Rig.playing(pure: pure, semantics: semantics)
        rig.engine.holdTransport(true)
        rig.vm.playTrack(at: 1)
        rig.vm.playTrack(at: 3)
        try await rig.waitUntil("both starts to reach the engine") { rig.engine.heldEpochs.count == 2 }
        rig.engine.holdTransport(false)
        let epochs = rig.engine.heldEpochs.sorted()
        rig.engine.runHeld(epoch: epochs[1]) // the newer start first
        rig.engine.runHeld(epoch: epochs[0])
        try await rig.settle()
        rig.engine.drain()
        rig.tick()
        let promised = rig.pending
        let armed = rig.engine.armed
        let audible = rig.engine.current
        try await rig.endTrackAndFollow()
        let ok = armed != nil && armed == promised && rig.engine.current == rig.shown
        return Outcome(ok: ok, detail: "START-OVERTAKE on \(pathName(pure)) [\(semantics)]: HEARS "
            + "\(name(audible)) / SHOWS t3, promised \(name(promised)), armed \(name(armed)); after the end "
            + "HEARS \(name(rig.engine.current)) / SHOWS \(name(rig.shown))")
    }

    /// What LATE-REQUEST leaves: what plays, what the app shows, and whether the explorer's rule
    /// counts the seam as the residual A2.
    struct LateRequest {
        let heard: URL?
        let shown: URL?
        let classifiedA2: Bool
    }

    /// The documented residual A2: Play Next t9 is made, but not yet admitted, when A ends. The old
    /// pick is still armed and plays while the app shows t9 — until seam identity (F1).
    static func lateRequest(pure: Bool, semantics: ArmSemantics) async throws -> LateRequest {
        let rig = try await Rig.playing(pure: pure, semantics: semantics)
        rig.vm.playNext([audioFile(9)])
        try await rig.settle() // made, not delivered
        rig.engine.trackEnds()
        let sequenceAtTick = rig.vm.onDeckSequence
        rig.tick()
        let seam = rig.engine.takeProcessedSeam()
        let classifiedA2 = seam.map { $0.intoNewestApplied && sequenceAtTick > $0.newestApplied } ?? false
        return LateRequest(heard: rig.engine.current, shown: rig.shown, classifiedA2: classifiedA2)
    }
}
