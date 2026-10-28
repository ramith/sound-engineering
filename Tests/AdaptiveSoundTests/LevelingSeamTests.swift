@testable import AdaptiveSound
import AudioDSP
import EQEditKit
import Foundation
import LevelingKit
import PlaybackQueueKit
import RigKit
import Testing

// MARK: - The leveling seam on the real view model (R1.1-B, level-and-fold §S1b and §S3)

//
// What lane 1's step 1 freezes for the lanes that build on it: the channel-role numbers as Swift sees them (the
// design asks the C enum, the C++ enum and Swift to agree), and the decision travelling with every request that
// can make a track audible (B2) — a start, and an arm (a clear carries none). Compare reaches the engine apart
// from On, so it can be level-matched (§7).

@MainActor
@Suite("The leveling seam (R1.1-B, §S3)", .timeLimit(.minutes(3)), .attachingLogTail)
struct LevelingSeamTests {
    @Test("LS-1: the channel-role numbers are the persisted ones, as Swift sees them")
    func roleNumbersAsSwiftSeesThem() {
        let roles: [(AsChannelRole, UInt32)] = [
            (AsChannelRoleUnknown, 0), (AsChannelRoleL, 1), (AsChannelRoleR, 2), (AsChannelRoleC, 3),
            (AsChannelRoleLfe, 4), (AsChannelRoleLs, 5), (AsChannelRoleRs, 6), (AsChannelRoleLb, 7),
            (AsChannelRoleRb, 8), (AsChannelRoleCs, 9), (AsChannelRoleLc, 10), (AsChannelRoleRc, 11),
            (AsChannelRoleLw, 12), (AsChannelRoleRw, 13), (AsChannelRoleMono, 14),
        ]
        for (role, number) in roles {
            #expect(role.rawValue == number, "role \(number) reads \(role.rawValue) in Swift")
        }
        #expect(AS_MAX_CHANNELS == 8 && AS_FOLD_LFE_VARIANTS == 4)
        #expect(asLfeVariantGain(UInt8(AsLfeVariantMusic.rawValue)) == 0.5)
    }

    @Test("LS-2: every start carries a decision, and every arm of a pick does; a clear carries none (B2)")
    func everyStartAndArmCarriesADecision() async throws {
        let player = try await FakePlayer.launched(tracks: 3)
        try await player.play(at: 0)
        try await player.vm.settled()
        let (starts, arms, picks) = player.engine.state.withLock { state in
            (state.startLevelings, state.nextLevelings, state.nextTracks)
        }
        #expect(starts == [.off], "the start's decision: \(starts)")
        #expect(!arms.isEmpty, "the start armed no pick")
        for (pick, decision) in zip(picks, arms) {
            #expect((pick == nil) == (decision == nil),
                    "pick \(String(describing: pick)) armed with \(String(describing: decision))")
        }
    }

    @Test("LS-3: Compare reaches the engine apart from On, so it can be level-matched (§7)")
    func compareReachesTheEngineApartFromOn() async throws {
        let player = try await FakePlayer.launched(tracks: 0)
        let points = [Float](repeating: 3, count: 31)
        player.vm.publishEQ(points: points, isOn: true, comparing: true)
        let published = player.calls.compactMap { call -> FakeEngine.Call? in
            if case .eq = call {
                return call
            }
            return nil
        }
        #expect(published.last == .eq(points: points, isOn: true, comparing: true))
    }
}
