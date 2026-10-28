@testable import AdaptiveSound
import AudioDSP
@preconcurrency import AVFoundation
import Foundation
import LevelingKit
import PlaybackQueueKit
import RigKit
import Synchronization
import Testing

// MARK: - The leveling plan on the real bridge (R1.1-B, level-and-fold §1.3, §S3; B1, B2, F5, N11)

//
// The REAL `AudioEngineBridge` on an offline engine (`EnhancedTransportRig`): a start's decision and an arm's
// decision reach the planner as their tracks become audible (B2), the plan goes once to both units in the same turn
// (B1) — the effects unit through its C-ABI, the fold through the sink lane 2 installs (a recording sink stands in
// for the spatial unit here) — a resume or a seek of the same track sends nothing, a mode change re-plans the audible
// track and re-arms the next (N11), and an output change re-plans protectively with the gain frozen (F5).

/// What the fold's sink received, in order.
private final class FoldRecord: Sendable {
    let plans = Mutex<[(plan: AsTrackPlan, event: UInt32)]>([])

    var sink: EngineLevelingState.FoldPlanSink {
        { [self] plan, _, event in plans.withLock { $0.append((plan, event.rawValue)) } }
    }

    var count: Int {
        plans.withLock(\.count)
    }

    var last: (plan: AsTrackPlan, event: UInt32)? {
        plans.withLock(\.last)
    }
}

/// The two plans, field by field (NaN equals NaN).
private func samePlan(_ lhs: AsTrackPlan, _ rhs: AsTrackPlan) -> Bool {
    let doubles: [(Double, Double)] = [
        (lhs.levelGainDb, rhs.levelGainDb), (lhs.peakDbtp, rhs.peakDbtp),
        (lhs.workingCeilingDbtp, rhs.workingCeilingDbtp), (lhs.foldTrimDb, rhs.foldTrimDb),
        (lhs.lfeGainLinear, rhs.lfeGainLinear), (lhs.loudnessLufs, rhs.loudnessLufs),
    ]
    return lhs.version == rhs.version && lhs.mode == rhs.mode && lhs.folds == rhs.folds
        && lhs.lfeVariant == rhs.lfeVariant && lhs.foldFromAnalysis == rhs.foldFromAnalysis
        && doubles.allSatisfy { $0.bitPattern == $1.bitPattern }
}

/// A stereo track measured at the engine's rate: `loudness` LUFS, `peak` dBTP.
private func measured(_ loudness: Double, peak: Double, continuous: Bool = false) -> TrackLevelingDecision {
    TrackLevelingDecision(
        mode: .leveled, source: .analysis, continuousWithPrevious: continuous,
        unfolded: .init(loudness: loudness, truePeak: peak), folded: nil,
        roles: [UInt8(AsChannelRoleL.rawValue), UInt8(AsChannelRoleR.rawValue)], peakRate: 48000
    )
}

@Suite("The leveling plan on the real bridge (R1.1-B, §S3)", .serialized, .timeLimit(.minutes(3)), .attachingLogTail)
struct LevelingBridgeTests {
    typealias Rig = EnhancedTransportRig

    /// Start `url` through the bridge's own start (`playFile`), as `startAudio` does, holding `decision` first.
    private static func start(_ rig: Rig, _ url: URL, decision: TrackLevelingDecision?, at seconds: Double = 0)
        async throws {
        let bridge = rig.bridge
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            bridge.engineQueue.async {
                do {
                    guard let engine = bridge.avEngineRef, let player = bridge.playerNodeRef else {
                        throw AudioBridgeError.engineNotInitialized
                    }
                    bridge.holdStartDecision(decision, for: url)
                    bridge.setLastFileURL(url)
                    try bridge.playFile(at: url, engine: engine, playerNode: player, startAt: seconds)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    @Test("LB-1: no decision at audibility plans Off (the fold's worst-case trim): a bug state, never a guess")
    func noDecisionPlansOff() async throws {
        let rig = try await Rig(path: .passthrough, name: "lb-none") // the rig's own start carries no decision
        let plan = try #require(rig.bridge.leveling.audiblePlan)
        #expect(plan.mode == UInt8(AsLevelingModeOff.rawValue) && plan.levelGainDb == 0)
        await rig.finish()
    }

    @Test("LB-2: a start's decision is planned at audibility, once, and both units get the same plan (B1, B2)")
    func aStartsDecisionIsPlannedOnce() async throws {
        let rig = try await Rig(path: .passthrough, name: "lb-start")
        let record = FoldRecord()
        rig.bridge.setFoldPlanSink(record.sink)
        let track = try rig.writeTrack([440], named: "lb-start-b", rate: 48000, frames: 0 ..< 96000)
        try await Self.start(rig, track, decision: measured(-24, peak: -10))
        let plan = try #require(rig.bridge.leveling.audiblePlan)
        #expect(record.count == 1, "the fold got \(record.count) plans for one audibility")
        let delivered = try #require(record.last)
        #expect(samePlan(delivered.plan, plan), "the fold's plan is not the planner's")
        #expect(delivered.event == AsPlanEventFreshStart.rawValue)
        #expect(plan.mode == UInt8(AsLevelingModeLeveled.rawValue))
        #expect(abs(plan.levelGainDb - 6.0) < 1e-9, "g = −18 − (−24): \(plan.levelGainDb)")

        // A resume and a seek of the same track on the same unit send nothing (B1).
        try await Self.start(rig, track, decision: measured(-12, peak: -1), at: 0.5)
        _ = await rig.seek(to: 1.0)
        #expect(record.count == 1, "a resume or a seek sent \(record.count - 1) plans")
        let after = try #require(rig.bridge.leveling.audiblePlan)
        #expect(samePlan(after, plan), "the plan moved inside the track")
        await rig.finish()
    }

    @Test("LB-3: the armed decision rides to the seam with its pick, continuity and all (B2, B3)")
    func theArmedDecisionRidesToTheSeam() async throws {
        let rig = try await Rig.playing([440], rate: 48000, frames: 24000, thenNext: 48000, name: "lb-seam")
        let record = FoldRecord()
        rig.bridge.setFoldPlanSink(record.sink)
        let next = try rig.writeTrack([440], named: "lb-seam-c", rate: 48000, frames: 24000 ..< 72000)
        await rig.bridge.setNextTrack(next, ticket: OnDeckTicket(session: 0, sequence: 2),
                                      leveling: measured(-20, peak: -8, continuous: true))
        _ = try #require(await rig.samples(frames: 24000 + 9600))
        try await until("the seam to be counted") { rig.bridge.gaplessTransitionCount == 1 }
        let delivered = try #require(record.last)
        #expect(delivered.event == AsPlanEventGaplessSeam.rawValue)
        #expect(abs(delivered.plan.levelGainDb - 2.0) < 1e-9,
                "the pick's own g (−18 − (−20)): \(delivered.plan.levelGainDb)")
        await rig.finish()
    }

    @Test("LB-4: a mode change re-plans the audible track and replaces the armed decision (§1.3, N11)")
    func aModeChangeReplansAndRearms() async throws {
        let rig = try await Rig.playing([440], rate: 48000, frames: 24000, thenNext: 48000, name: "lb-mode")
        let record = FoldRecord()
        rig.bridge.setFoldPlanSink(record.sink)
        let next = try rig.writeTrack([440], named: "lb-mode-c", rate: 48000, frames: 24000 ..< 72000)
        await rig.bridge.setNextTrack(next, ticket: OnDeckTicket(session: 0, sequence: 2), leveling: .off)
        rig.bridge.applyLevelingChange(current: measured(-22, peak: -8), next: measured(-21, peak: -8))
        let changed = try #require(record.last)
        #expect(changed.event == AsPlanEventModeChange.rawValue)
        #expect(abs(changed.plan.levelGainDb - 4.0) < 1e-9, "the audible track's new g: \(changed.plan.levelGainDb)")
        _ = try #require(await rig.samples(frames: 24000 + 9600))
        try await until("the seam to be counted") { rig.bridge.gaplessTransitionCount == 1 }
        let seam = try #require(record.last)
        #expect(seam.event == AsPlanEventGaplessSeam.rawValue)
        #expect(abs(seam.plan.levelGainDb - 3.0) < 1e-9, "the re-armed pick's g: \(seam.plan.levelGainDb)")
        await rig.finish()
    }

    @Test("LB-5: an output change re-plans the audible track protectively, its gain frozen (F5)")
    func anOutputChangeReplansProtectively() async throws {
        let rig = try await Rig(path: .passthrough, name: "lb-output")
        let record = FoldRecord()
        rig.bridge.setFoldPlanSink(record.sink)
        let track = try rig.writeTrack([440], named: "lb-output-b", rate: 48000, frames: 0 ..< 96000)
        rig.bridge.levelingTransportChanged(kAudioDeviceTransportTypeBuiltIn)
        try await Self.start(rig, track, decision: measured(-14, peak: -1))
        let wired = try #require(rig.bridge.leveling.audiblePlan)
        rig.bridge.levelingTransportChanged(kAudioDeviceTransportTypeBluetooth)
        let moved = try #require(record.last)
        #expect(moved.event == AsPlanEventOutputChange.rawValue)
        #expect(moved.plan.levelGainDb == wired.levelGainDb, "g moved at an output change")
        #expect(moved.plan.workingCeilingDbtp < wired.workingCeilingDbtp, "the ceiling did not follow the output")
        let count = record.count
        var same = rig.bridge.leveling.outputState
        rig.bridge.applyOutputState(same) // the same state again: nothing to re-plan
        same.transportType = kAudioDeviceTransportTypeBluetooth
        rig.bridge.applyOutputState(same)
        #expect(record.count == count, "an unchanged output re-planned")
        await rig.finish()
    }

    @Test("LB-6: the armed pick started fresh (a failed gapless roll restarts it) keeps its armed decision")
    func theArmedPickStartedFreshKeepsItsDecision() async throws {
        let rig = try await Rig(path: .passthrough, name: "lb-roll")
        let next = try rig.writeTrack([440], named: "lb-roll-b", rate: 48000, frames: 0 ..< 96000)
        await rig.bridge.setNextTrack(next, ticket: OnDeckTicket(session: 0, sequence: 1),
                                      leveling: measured(-21, peak: -9))
        try await Self.start(rig, next, decision: nil) // the roll's restart: playFile, no start decision
        let plan = try #require(rig.bridge.leveling.audiblePlan)
        #expect(plan.mode == UInt8(AsLevelingModeLeveled.rawValue), "the armed decision was dropped")
        #expect(abs(plan.levelGainDb - 3.0) < 1e-9, "g = −18 − (−21): \(plan.levelGainDb)")
        await rig.finish()
    }
}
