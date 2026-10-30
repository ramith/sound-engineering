@testable import AdaptiveSound
import AudioDSP
import Foundation
import LevelingKit
import PlaybackQueueKit
import RigKit
import Testing

// MARK: - What the effects unit applies, heard (R1.1-B, review S7)

//
// The bridge's leveling tests read the plan the planner made; these read what the effects unit then plays. The REAL
// bridge renders a −12 dBFS tone offline (`EnhancedTransportRig`, stereo: nothing folds, the EQ is off), so the
// rendered level IS the leveling gain the effects unit applied. One check per event type a plan comes with: a
// fresh start and a gapless seam here; a resume (FOLD-BADGE-02), a mode change (LG-1) and an output change (LG-3)
// read their render beside the fold they move.

@Suite("Leveling — what the effects unit applies, heard (S7)", .serialized, .timeLimit(.minutes(3)),
       .attachingLogTail)
struct LevelingAppliedTests {
    typealias Rig = EnhancedTransportRig

    /// A stereo track measured at the engine's rate: `loudness` LUFS, `peak` dBTP.
    private static func measured(_ loudness: Double, peak: Double) -> TrackLevelingDecision {
        TrackLevelingDecision(mode: .leveled, source: .analysis, continuousWithPrevious: false,
                              unfolded: .init(loudness: loudness, truePeak: peak), folded: nil, roles: [1, 2],
                              peakRate: 48000)
    }

    /// The level of `samples` (the left channel's peak) against the fixture's tone, in dB.
    private static func levelDb(_ samples: ArraySlice<Float>) -> Double {
        20 * log10(Double(samples.reduce(0) { max($0, abs($1)) }) / Double(Rig.toneAmplitude))
    }

    @Test("LA-1: a fresh start plays at its plan's leveling gain from its first audio on (FreshStart)")
    func aFreshStartPlaysItsGain() async throws {
        let rig = try await Rig(path: .passthrough, name: "la-start")
        let track = try rig.writeTrack([440], named: "la-start-b", rate: 48000, frames: 0 ..< 96000)
        let bridge = rig.bridge
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            bridge.engineQueue.async {
                do {
                    guard let engine = bridge.avEngineRef, let player = bridge.playerNodeRef else {
                        throw AudioBridgeError.engineNotInitialized
                    }
                    bridge.holdStartDecision(LevelingStart(decision: Self.measured(-24, peak: -10), listen: .newPlay),
                                             for: track)
                    bridge.setLastFileURL(track)
                    try bridge.playFile(at: track, engine: engine, playerNode: player, startAt: 0)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
        let plan = try #require(bridge.leveling.audiblePlan)
        let left = try #require(await rig.samples(frames: 24000))
        // Past the effects unit's look-ahead and the tone's first cycle: the gain the unit snapped to.
        let heard = Self.levelDb(left[960...])
        #expect(abs(heard - plan.levelGainDb) < 0.05, "heard \(heard) dB, the plan's g \(plan.levelGainDb) dB")
        await rig.finish()
    }

    @Test("LA-2: at a gapless seam the next track plays at its own plan's gain, and the one before at its own")
    func aSeamPlaysTheNextTracksGain() async throws {
        let rig = try await Rig.playing([440], rate: 48000, frames: 24000, thenNext: 48000, name: "la-seam")
        let next = try rig.writeTrack([440], named: "la-seam-c", rate: 48000, frames: 24000 ..< 72000)
        await rig.bridge.setNextTrack(next, ticket: OnDeckTicket(session: 0, sequence: 2),
                                      leveling: Self.measured(-20, peak: -8))
        let first = try #require(rig.bridge.leveling.audiblePlan)
        let left = try #require(await rig.samples(frames: 48000))
        try await until("the seam to be counted") { rig.bridge.gaplessTransitionCount == 1 }
        let seam = try #require(rig.bridge.leveling.audiblePlan)
        #expect(abs(seam.levelGainDb - 2) < 1e-9, "the precondition: the pick's g is +2 dB (\(seam.levelGainDb))")
        let before = Self.levelDb(left[4800 ..< 22800])
        let after = Self.levelDb(left[26400 ..< 48000]) // past the seam's 10 ms glide and the look-ahead
        #expect(abs(before - first.levelGainDb) < 0.05, "before the seam: \(before) dB, its g \(first.levelGainDb)")
        #expect(abs(after - seam.levelGainDb) < 0.05, "after the seam: \(after) dB, the pick's g \(seam.levelGainDb)")
        await rig.finish()
    }
}
