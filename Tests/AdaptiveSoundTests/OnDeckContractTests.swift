@testable import AdaptiveSound
import Foundation
import PlaybackQueueKit
import Testing

// MARK: - What plays next: the view model × engine on-deck contract (council D41)

//
// The shipped `AudioViewModel` against `OnDeckEngineModel` (the bridge's on-deck semantics, steps
// in any order). Under the design every scenario holds; under the semantics it replaced each
// ablation breaks a named scenario — so each piece of the design is necessary. `ArmSemantics.refuse`
// is 672fc0a's: its rows are the D41 defect reproduced on the real view model.

@Suite("AudioViewModel × engine — what plays next (council D41)", .serialized)
@MainActor
struct OnDeckContractTests {
    // MARK: The design holds

    @Test("D41 on Pure: a change of mind while a song plays is what plays next", arguments: ChangeOfMind.allCases)
    func changeOfMindOnPure(_ change: ChangeOfMind) async throws {
        let outcome = try await OnDeckScenarios.changeOfMind(change, pure: true, semantics: .design)
        #expect(outcome.ok, "\(outcome)")
    }

    @Test("D41 on Enhanced: a change of mind while a song plays is what plays next",
          arguments: ChangeOfMind.allCases)
    func changeOfMindOnEnhanced(_ change: ChangeOfMind) async throws {
        let outcome = try await OnDeckScenarios.changeOfMind(change, pure: false, semantics: .design)
        #expect(outcome.ok, "\(outcome)")
    }

    @Test("PURE-REARM-ORDER: two quick Play Next, the second open lands first — the newest is armed")
    func pureRearmOrder() async throws {
        let outcome = try await OnDeckScenarios.pureRearmOrder(semantics: .design)
        #expect(outcome.ok, "\(outcome)")
    }

    @Test("REARM-DELIVERY-ORDER: the newer request arrives first — the older is dropped and never opened")
    func rearmDeliveryOrder() async throws {
        let outcome = try await OnDeckScenarios.rearmDeliveryOrder(semantics: .design)
        #expect(outcome.ok, "\(outcome)")
        #expect(outcome.detail.contains("t10 opened: false"), "a dropped request opened its file: \(outcome)")
    }

    @Test("NEXT-NEXT on Pure: Next, Next while the first prime is in flight — t2 plays once, then t3",
          arguments: NextNextOrder.allCases)
    func nextNextOnPure(_ order: NextNextOrder) async throws {
        let outcome = try await OnDeckScenarios.nextNext(pure: true, order: order, semantics: .design)
        #expect(outcome.ok, "\(outcome)")
    }

    @Test("NEXT-NEXT on Enhanced: Next, Next while the first prime is in flight — t2 plays once, then t3",
          arguments: NextNextOrder.allCases)
    func nextNextOnEnhanced(_ order: NextNextOrder) async throws {
        let outcome = try await OnDeckScenarios.nextNext(pure: false, order: order, semantics: .design)
        #expect(outcome.ok, "\(outcome)")
    }

    @Test("RETRACT-THEN-END: the song ends while the new pick opens — a gap, then the new pick")
    func retractThenEnd() async throws {
        let outcome = try await OnDeckScenarios.retractThenEnd(semantics: .design)
        #expect(outcome.ok, "\(outcome)")
    }

    @Test("LATE-ARM-AFTER-END: the new pick's open lands after the end — refused; it starts once, fresh")
    func lateArmAfterEnd() async throws {
        let outcome = try await OnDeckScenarios.lateArmAfterEnd(semantics: .design)
        #expect(outcome.ok, "\(outcome)")
    }

    @Test("REARM-INCOMPATIBLE: a pick that can't join gaplessly — a gap, then that pick, never the old one")
    func rearmIncompatible() async throws {
        let outcome = try await OnDeckScenarios.rearmIncompatible(semantics: .design)
        #expect(outcome.ok, "\(outcome)")
    }

    @Test("REARM-OPEN-FAILS: a pick that won't open — never the old pick; the app tries it and reports")
    func rearmOpenFails() async throws {
        let outcome = try await OnDeckScenarios.rearmOpenFails(semantics: .design)
        #expect(outcome.ok, "\(outcome)")
    }

    @Test("START-OVERTAKE (AMEND-1): two starts reach the engine reversed — the newest still primes",
          arguments: [true, false])
    func startOvertake(pure: Bool) async throws {
        let outcome = try await OnDeckScenarios.startOvertake(pure: pure, semantics: .design)
        #expect(outcome.ok, "\(outcome)")
    }

    @Test("F-P4-1: Play Next while a start's prime is still arming — the Play Next song plays next",
          arguments: [true, false])
    func playNextDuringPrime(pure: Bool) async throws {
        let outcome = try await OnDeckScenarios.playNextDuringPrime(pure: pure, semantics: .design)
        #expect(outcome.ok, "\(outcome)")
    }

    @Test("LATE-REQUEST is the documented residual A2: not yet admitted at the end, the old pick plays",
          arguments: [true, false])
    func lateRequestIsA2(pure: Bool) async throws {
        // Until the seam reports which track it played (F1), this is what happens; the explorer
        // counts it apart from the violations by the same rule as here.
        let result = try await OnDeckScenarios.lateRequest(pure: pure, semantics: .design)
        #expect(result.heard == track(1) && result.shown == track(9),
                "heard \(name(result.heard)), shown \(name(result.shown))")
        #expect(result.classifiedA2, "the A2 classifier did not recognise LATE-REQUEST")
    }

    // MARK: 672fc0a reproduced, and each piece of the design is necessary

    @Test("672fc0a semantics: every D41 change of mind on Pure plays the OLD pick", arguments: ChangeOfMind.allCases)
    func beforeFixPurePlaysTheOldPick(_ change: ChangeOfMind) async throws {
        let outcome = try await OnDeckScenarios.changeOfMind(change, pure: true, semantics: .refuse)
        #expect(!outcome.ok, "672fc0a semantics should reproduce D41: \(outcome)")
    }

    @Test("672fc0a semantics: Enhanced already applied the change (D41 was Pure-only)",
          arguments: ChangeOfMind.allCases)
    func beforeFixEnhancedApplied(_ change: ChangeOfMind) async throws {
        let outcome = try await OnDeckScenarios.changeOfMind(change, pure: false, semantics: .refuse)
        #expect(outcome.ok, "\(outcome)")
    }

    @Test("672fc0a semantics break the races and the edges too")
    func beforeFixBreaksTheRacesAndEdges() async throws {
        let semantics = ArmSemantics.refuse
        let outcomes = try await [
            OnDeckScenarios.pureRearmOrder(semantics: semantics),
            OnDeckScenarios.rearmDeliveryOrder(semantics: semantics),
            OnDeckScenarios.nextNext(pure: true, order: .staleOpenLandsFirst, semantics: semantics),
            OnDeckScenarios.nextNext(pure: false, order: .staleRequestArrivesLast, semantics: semantics),
            OnDeckScenarios.retractThenEnd(semantics: semantics),
            OnDeckScenarios.lateArmAfterEnd(semantics: semantics),
            OnDeckScenarios.rearmIncompatible(semantics: semantics),
            OnDeckScenarios.rearmOpenFails(semantics: semantics),
        ]
        for outcome in outcomes {
            #expect(!outcome.ok, "672fc0a semantics should break this: \(outcome)")
        }
    }

    @Test("Ablation — clear-then-arm on open (P3a's remedy) loses both races")
    func clearThenArmLosesBothRaces() async throws {
        let semantics = ArmSemantics.clearThenArm
        let race1 = try await OnDeckScenarios.pureRearmOrder(semantics: semantics)
        let race2 = try await OnDeckScenarios.nextNext(pure: true, order: .staleOpenLandsLast, semantics: semantics)
        #expect(!race1.ok, "\(race1)")
        #expect(!race2.ok, "\(race2)")
    }

    @Test("Ablation — the gate without taking the old pick off at admission plays it at a last-moment end")
    func replaceAfterOpenPlaysTheOldPick() async throws {
        let outcome = try await OnDeckScenarios.retractThenEnd(semantics: .gatedReplaceAfterOpen)
        #expect(!outcome.ok, "\(outcome)")
    }

    @Test("Ablation — without 'the end is final' a late arm seams after the end and cuts the song off")
    func withoutEndFinalALateArmSeams() async throws {
        let outcome = try await OnDeckScenarios.lateArmAfterEnd(semantics: .gatedRetractFirst(endFinal: false))
        #expect(!outcome.ok, "\(outcome)")
    }

    @Test("Ablation — sessions that roll back (the design as first written) lose the newest prime",
          arguments: [true, false])
    func rollingBackSessionsLoseThePrime(pure: Bool) async throws {
        // On the engine as D41 found it, which ran an overtaken start (council C-15 drops it now, so
        // it never begins a session: AMEND-1 is a second guard since).
        let semantics = ArmSemantics.gatedRetractFirst(endFinal: true, monotonicSessions: false)
        let outcome = try await OnDeckScenarios.startOvertake(pure: pure, semantics: semantics,
                                                              commands: .executesEvery)
        #expect(!outcome.ok, "\(outcome)")
    }
}
