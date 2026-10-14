// Council P4 (queue / transport) — a SCRIPTED model of AudioEngineBridge, compiled beside the REAL
// AudioViewModel sources (run.sh copies them verbatim from the panel-p4 worktree @ a206107).
//
// Modelled from the bridge source (file:line in comments), not from the VM's expectations:
// - engineQueue is a serial FIFO: start / stop / seek / the Pure arm / the clock sample run there
//   one at a time (AudioEngineBridge+Playback.swift:7-44, +TransportClock.swift:31-70).
// - Every transport op first publishes a TRANSITIONAL sample stamped with its epoch, carrying the
//   LAST PUBLISHED seam count and ended=false (+TransportClock.swift:55-61); the op's end publishes a
//   SETTLED live sample (+Playback.swift:37-38).
// - Enhanced seam count is cumulative over the bridge's life (gaplessTransitionCounter, never reset);
//   the Pure count restarts at 0 on each Pure start (GaplessSource.cpp:85 setCurrent).
// - Enhanced setNextTrack REPLACES the on-deck (resampleQueue, +Gapless.swift:61-82).
// - Pure setNextTrack(url) opens on a global queue, then arms on engineQueue; GaplessSource::armNext
//   REFUSES while a track is armed (GaplessSource.cpp:127-130 → PureModeBridge.cpp:357-362);
//   setNextTrack(nil) clears on engineQueue (+Gapless.swift:93-98).
// - The VM's calls reach the queues in CALL order here (the harness is compiled with
//   NonisolatedNonsendingByDefault so the fake's async methods run on the caller's actor). The real
//   bridge's nonisolated async methods hop to the global executor first, so the real system has
//   STRICTLY MORE orderings than this model: anything this model breaks, the app can break.

import Foundation
import PlaybackQueueKit
import SwiftUI

enum PathKind: String { case enhanced, pure, none }

final class AudioEngineBridge: AudioPlaybackEngine, @unchecked Sendable {
    // MARK: what is audible (the ground truth the UI should agree with)
    var current: URL?
    var armed: URL?
    var path: PathKind = .none
    var clockRunning = false
    var enhancedCount: UInt64 = 0
    var pureCount: UInt64 = 0
    var ended = false
    var position: Double?
    var epoch: UInt64 = 0
    var interrupted = false
    /// Every URL that became audible, in order (the "what the user heard" log).
    var heard: [URL] = []
    var refusedArms: [URL] = []
    var pureViable: (URL) -> Bool = { _ in true }
    /// The P3a remedy: the bridge's Pure arm = clearNext() then armNext() (replace, last landing wins).
    var pureArmReplaces = false

    // MARK: queues
    enum OpKind: CustomStringConvertible {
        case start(URL?, Bool, Double, UInt64)
        case stop(UInt64)
        case seek(Double, UInt64)
        case pureArm(URL)
        case pureClear
        var description: String {
            switch self {
            case let .start(url, pure, at, ep): "start(\(url?.lastPathComponent ?? "-"),pure=\(pure),at=\(at),e\(ep))"
            case let .stop(ep): "stop(e\(ep))"
            case let .seek(to, ep): "seek(\(to),e\(ep))"
            case let .pureArm(url): "pureArm(\(url.lastPathComponent))"
            case .pureClear: "pureClear"
            }
        }
    }

    struct Op {
        let kind: OpKind
        let resume: () -> Void
    }

    var engineQueue: [Op] = []
    var resampleQueue: [(url: URL?, resume: () -> Void)] = []
    /// Pure arms whose file open (global queue) has not finished; each lands on engineQueue when opened.
    var pureOpening: [(url: URL, resume: () -> Void)] = []

    var published = TransportSnapshot()
    var onOutputDevicesChanged: (@MainActor () -> Void)?

    // MARK: AudioPlaybackEngine
    func initialize() async throws -> Bool { true }
    func shutdown() async throws {}

    func startAudio(fileURL: URL?, pureMode: Bool, startAt: Double, epoch: UInt64) async throws {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            engineQueue.append(Op(kind: .start(fileURL, pureMode, startAt, epoch)) { cont.resume() })
        }
    }

    func stopAudio(epoch: UInt64) async throws {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            engineQueue.append(Op(kind: .stop(epoch)) { cont.resume() })
        }
    }

    func seek(to seconds: Double, epoch: UInt64) async throws {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            engineQueue.append(Op(kind: .seek(seconds, epoch)) { cont.resume() })
        }
    }

    func setNextTrack(_ fileURL: URL?) async {
        // +Gapless.swift:52-58: routed by the path active WHEN CALLED.
        if path == .pure {
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                if let url = fileURL {
                    pureOpening.append((url, { cont.resume() }))
                } else {
                    engineQueue.append(Op(kind: .pureClear) { cont.resume() })
                }
            }
            return
        }
        guard path == .enhanced else { return }
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            resampleQueue.append((fileURL, { cont.resume() }))
        }
    }

    func snapshot() -> EngineSnapshot {
        var snap = EngineSnapshot()
        snap.transport = published
        snap.signalPath.interrupted = interrupted
        return snap
    }

    func publishMasterGain(decibels _: Float) {}
    func requestDeviceVolume(decibels _: Float) {}
    func publishEQ(points _: [Float], isOn _: Bool) {}
    func publishIntensity(_: Float) {}
    func publishOutputTransport(_: UInt32) {}
    func publishCrossfeed(enabled _: Bool, strength _: CrossfeedStrength) {}
    func enumerateOutputDevices() async throws -> [AudioDeviceModel] { [] }
    func selectDevice(_: UInt32) async throws -> Bool { true }
    func currentOutputDeviceID() -> UInt32 { 0 }
    func setPinPlaybackToSelectedDevice(_: Bool) {}
    @discardableResult
    func readSpectrumBands(into _: inout [Float]) -> Bool { false }
    var monitorChannelCount: Int { 0 }
    @discardableResult
    func readMonitorBands(_: MonitorTap, channel _: Int, into _: inout [Float]) -> Bool { false }

    // MARK: the engine side, stepped by the scenario

    var liveCount: UInt64 { path == .pure ? pureCount : enhancedCount }

    private func begin(_ ep: UInt64, position pos: Double?) {
        epoch = max(epoch, ep)
        published = TransportSnapshot(epoch: epoch, position: pos, transitionCount: published.transitionCount,
                                      ended: false)
    }

    func sample() {
        published = TransportSnapshot(epoch: epoch, position: current == nil ? nil : (position ?? 0.5),
                                      transitionCount: liveCount, ended: ended)
    }

    /// A slow op (a Pure rate change takes seconds): publish the head op's transitional sample only.
    func beginHeadOp() {
        guard let op = engineQueue.first else { return }
        switch op.kind {
        case let .start(_, _, at, ep): begin(ep, position: at > 0 ? at : nil)
        case let .stop(ep): begin(ep, position: nil)
        case let .seek(to, ep): begin(ep, position: to)
        default: break
        }
    }

    /// Run the head of engineQueue. Returns false when empty.
    @discardableResult
    func runEngineOp(resumeCaller: Bool = true) -> Bool {
        guard !engineQueue.isEmpty else { return false }
        let op = engineQueue.removeFirst()
        switch op.kind {
        case let .start(url, pure, at, ep):
            begin(ep, position: at > 0 ? at : nil)
            ended = false
            armed = nil // onDeckURL = nil (+Playback.swift:24-27); a Pure start = a fresh GaplessSource
            if pure, let url, pureViable(url) {
                path = .pure
                pureCount = 0 // GaplessSource::setCurrent
            } else {
                path = .enhanced
            }
            current = url
            position = at
            if let url { heard.append(url) }
            clockRunning = true
            sample()
        case let .stop(ep):
            begin(ep, position: nil)
            current = nil
            armed = nil
            clockRunning = false
            sample()
        case let .seek(to, ep):
            begin(ep, position: to)
            position = to
            sample()
        case let .pureArm(url):
            if path == .pure {
                if armed == nil || pureArmReplaces {
                    armed = url
                } else {
                    refusedArms.append(url) // kNextTrackError: B stays armed
                }
            }
        case .pureClear:
            if path == .pure { armed = nil }
        }
        if resumeCaller { op.resume() }
        return true
    }

    @discardableResult
    func runResampleOp() -> Bool {
        guard !resampleQueue.isEmpty else { return false }
        let op = resampleQueue.removeFirst()
        if path == .enhanced { armed = op.url }
        op.resume()
        return true
    }

    /// A Pure arm's file open finished (index into pureOpening): its arm lands on engineQueue.
    @discardableResult
    func finishPureOpen(_ index: Int = 0) -> Bool {
        guard index < pureOpening.count else { return false }
        let open = pureOpening.remove(at: index)
        engineQueue.append(Op(kind: .pureArm(open.url), resume: open.resume))
        return true
    }

    /// The current track's audio ran out: the seam (armed → current, count + 1) or the end flag.
    func trackEnds() {
        guard current != nil else { return }
        if let next = armed {
            current = next
            armed = nil
            position = 0
            heard.append(next)
            if path == .pure { pureCount += 1 } else { enhancedCount += 1 }
        } else {
            ended = true
        }
    }

    /// The transport clock (33 ms, on engineQueue): only while running.
    func clockTick() {
        if clockRunning { sample() }
    }

    var idle: Bool { engineQueue.isEmpty && resampleQueue.isEmpty && pureOpening.isEmpty }
}

/// The library peer: absent (no store).
@MainActor
final class LibraryModel {}

@MainActor
extension AudioViewModel {
    func hydrateQueueOnLaunch() {}
    func persistQueueCursor() {}
    func scheduleQueueMirror() { hasUserEditedQueue = true }
    func mirrorQueueNow() async {}
}

@MainActor var playCountLog: [String] = []
@MainActor var failures = 0
@MainActor var remedyOn = false
