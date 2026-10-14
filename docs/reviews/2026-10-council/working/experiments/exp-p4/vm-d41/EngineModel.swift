// Council P4 review of the D41 design — the bridge model with the design's on-deck contract.
// OnDeckTicket / OnDeckGate are the design's code (d41-design.md §3), verbatim in substance.
// Arm behaviours (design §5): .refuse (today), .clearThenArm (P3a), .gatedReplaceAfterOpen,
// .gatedRetractFirst(endFinal:) (the design).
// Delivery: every setNextTrack lands in `inbound`; a scenario delivers inbound[i] onto engineQueue in
// ANY order (the real nonisolated async hop to engineQueue.async has no order between requests).

import Foundation
import PlaybackQueueKit
import SwiftUI

public struct OnDeckTicket: Sendable, Equatable {
    public let session: UInt64
    public let sequence: UInt64
}

public struct OnDeckGate: Sendable {
    private var session: UInt64 = 0
    private var newest: UInt64 = 0
    public init() {}
    nonisolated(unsafe) public static var monotonic = false // P4 amendment: sessions only move forward
    public mutating func beginSession(_ epoch: UInt64) {
        if Self.monotonic, epoch <= session { return }
        session = epoch; newest = 0
    }
    public mutating func admit(_ t: OnDeckTicket) -> Bool {
        guard t.session == session, t.sequence > newest else { return false }
        newest = t.sequence; return true
    }
    public func isCurrent(_ t: OnDeckTicket) -> Bool { t.session == session && t.sequence == newest }
}

enum ArmMode: Equatable {
    case refuse, clearThenArm, gatedReplaceAfterOpen, gatedRetract(endFinal: Bool)
    var gated: Bool { if case .refuse = self { return false }; if case .clearThenArm = self { return false }; return true }
}

enum PathKind: String { case enhanced, pure, none }

final class AudioEngineBridge: AudioPlaybackEngine, @unchecked Sendable {
    var mode: ArmMode = .gatedRetract(endFinal: true)
    /// Models the N13b/P4-1 remedy (out of the design's scope): seam counts are per start.
    var epochScopedCount = false
    var gate = OnDeckGate()
    var current: URL?
    var armed: URL?
    var armedTicket: OnDeckTicket?
    var path: PathKind = .none
    var clockRunning = false
    var enhancedCount: UInt64 = 0
    var pureCount: UInt64 = 0
    var ended = false
    var position: Double?
    var epoch: UInt64 = 0
    var interrupted = false
    var heard: [URL] = []
    var log: [String] = []
    var pureViable: (URL) -> Bool = { _ in true }
    var compatible: (URL) -> Bool = { _ in true }
    var readable: (URL) -> Bool = { _ in true }
    /// The newest on-deck ticket the VM has SENT (for classifying the A2 residual).
    var newestSent: OnDeckTicket?
    /// Highest request sequence the engine has RESOLVED (admitted or dropped).
    var resolvedMax: UInt64 = 0

    enum OpKind: CustomStringConvertible {
        case start(URL?, Bool, Double, UInt64), stop(UInt64), seek(Double, UInt64)
        case onDeck(URL?, OnDeckTicket)
        case pureArm(URL, OnDeckTicket)
        var description: String {
            switch self {
            case let .start(u, p, a, e): "start(\(u.map { $0.deletingPathExtension().lastPathComponent } ?? "-"),p=\(p),at=\(a),e\(e))"
            case let .stop(e): "stop(e\(e))"
            case let .seek(t, e): "seek(\(t),e\(e))"
            case let .onDeck(u, t): "onDeck(\(u.map { $0.deletingPathExtension().lastPathComponent } ?? "nil"),\(t.session):\(t.sequence))"
            case let .pureArm(u, t): "pureArm(\(u.deletingPathExtension().lastPathComponent),\(t.session):\(t.sequence))"
            }
        }
    }

    struct Op { let kind: OpKind; let resume: () -> Void }
    var engineQueue: [Op] = []
    var inbound: [Op] = [] // on-deck requests not yet on engineQueue
    var pureOpening: [(url: URL, ticket: OnDeckTicket, resume: () -> Void)] = []
    var published = TransportSnapshot()
    var onOutputDevicesChanged: (@MainActor () -> Void)?

    func initialize() async throws -> Bool { true }
    func shutdown() async throws {}
    func startAudio(fileURL: URL?, pureMode: Bool, startAt: Double, epoch: UInt64) async throws {
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            engineQueue.append(Op(kind: .start(fileURL, pureMode, startAt, epoch)) { c.resume() })
        }
    }
    func stopAudio(epoch: UInt64) async throws {
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            engineQueue.append(Op(kind: .stop(epoch)) { c.resume() })
        }
    }
    func seek(to seconds: Double, epoch: UInt64) async throws {
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            engineQueue.append(Op(kind: .seek(seconds, epoch)) { c.resume() })
        }
    }
    func setNextTrack(_ fileURL: URL?, ticket: OnDeckTicket) async {
        if newestSent == nil || ticket.sequence > newestSent!.sequence { newestSent = ticket }
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            inbound.append(Op(kind: .onDeck(fileURL, ticket)) { c.resume() })
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
    @discardableResult func readSpectrumBands(into _: inout [Float]) -> Bool { false }
    var monitorChannelCount: Int { 0 }
    @discardableResult func readMonitorBands(_: MonitorTap, channel _: Int, into _: inout [Float]) -> Bool { false }

    var liveCount: UInt64 { path == .pure ? pureCount : enhancedCount }
    private func begin(_ ep: UInt64, position pos: Double?) {
        epoch = max(epoch, ep)
        published = TransportSnapshot(epoch: epoch, position: pos, transitionCount: published.transitionCount, ended: false)
    }
    func sample() {
        published = TransportSnapshot(epoch: epoch, position: current == nil ? nil : (position ?? 0.5),
                                      transitionCount: liveCount, ended: ended)
    }

    /// Deliver inbound[i] onto engineQueue (arbitrary order).
    @discardableResult
    func deliver(_ i: Int = 0) -> Bool {
        guard i >= 0, i < inbound.count else { return false }
        engineQueue.append(inbound.remove(at: i))
        return true
    }

    @discardableResult
    func runEngineOp() -> Bool {
        guard !engineQueue.isEmpty else { return false }
        let op = engineQueue.removeFirst()
        var resumeNow = true
        switch op.kind {
        case let .start(url, pure, at, ep):
            if epochScopedCount {
                enhancedCount = 0; pureCount = 0
                published.transitionCount = 0
            }
            begin(ep, position: at > 0 ? at : nil)
            if mode.gated { gate.beginSession(ep) }
            ended = false
            armed = nil; armedTicket = nil
            path = pure && url != nil && pureViable(url!) ? .pure : .enhanced
            if path == .pure { pureCount = 0 }
            current = url
            position = at
            if let url { heard.append(url) }
            clockRunning = true
            sample()
        case let .stop(ep):
            begin(ep, position: nil)
            if mode.gated { gate.beginSession(ep) }
            current = nil; armed = nil; armedTicket = nil
            clockRunning = false
            sample()
        case let .seek(to, ep):
            begin(ep, position: to)
            position = to // `ended` stays latched across a seek (design leaves it alone)
            sample()
        case let .onDeck(url, ticket):
            resolvedMax = max(resolvedMax, ticket.sequence)
            resumeNow = admitOnDeck(url, ticket, resume: op.resume)
        case let .pureArm(url, ticket):
            pureArmLands(url, ticket)
        }
        if resumeNow { op.resume() }
        return true
    }

    /// Returns whether the caller resumes now (false: it resumes when its Pure arm lands).
    private func admitOnDeck(_ url: URL?, _ ticket: OnDeckTicket, resume: @escaping () -> Void) -> Bool {
        if !mode.gated {
            // today / P3a: no gate; Enhanced replaces; Pure opens then arms (refuse or clear+arm)
            if path == .enhanced { armed = url; armedTicket = ticket; return true }
            guard path == .pure else { return true }
            guard let url else { armed = nil; armedTicket = nil; return true }
            pureOpening.append((url, ticket, resume))
            return false
        }
        guard gate.admit(ticket) else { log.append("stale, dropped \(ticket.session):\(ticket.sequence)"); return true }
        if path == .enhanced {
            armed = url; armedTicket = ticket // onDeckURL set at admission
            return true
        }
        guard path == .pure else { return true }
        if case .gatedRetract = mode { armed = nil; armedTicket = nil } // old pick off at admission
        guard let url else { armed = nil; armedTicket = nil; return true }
        pureOpening.append((url, ticket, resume))
        return false
    }

    private func pureArmLands(_ url: URL, _ ticket: OnDeckTicket) {
        guard path == .pure else { return }
        switch mode {
        case .refuse:
            if armed == nil { armed = url; armedTicket = ticket } else { log.append("refused \(url.lastPathComponent)") }
        case .clearThenArm:
            armed = url; armedTicket = ticket
        case .gatedReplaceAfterOpen:
            guard gate.isCurrent(ticket), compatible(url), readable(url) else { return }
            if ended { lateArmAfterEnd(url, ticket); return } // no end rule in this ablation
            armed = url; armedTicket = ticket
        case let .gatedRetract(endFinal):
            guard gate.isCurrent(ticket), compatible(url), readable(url) else { return }
            if ended {
                if endFinal { log.append("ended → not armed"); return }
                lateArmAfterEnd(url, ticket); return
            }
            armed = url; armedTicket = ticket
        }
    }

    /// Without "the end is final": the render, still pulling, finds an armed source after EOF and seams.
    private func lateArmAfterEnd(_ url: URL, _ ticket: OnDeckTicket) {
        ended = false
        current = url
        heard.append(url)
        pureCount += 1
        armed = nil; armedTicket = nil
        log.append("LATE SEAM after end into \(url.lastPathComponent)")
    }

    @discardableResult
    func finishPureOpen(_ index: Int = 0) -> Bool {
        guard index >= 0, index < pureOpening.count else { return false }
        let open = pureOpening.remove(at: index)
        engineQueue.append(Op(kind: .pureArm(open.url, open.ticket), resume: open.resume))
        return true
    }

    /// The audio of the current track runs out. Returns whether an A2 condition held (a newer on-deck
    /// request was sent but not yet admitted).
    @discardableResult
    func trackEnds() -> Bool {
        guard current != nil, !ended else { return false }
        let a2 = unadmittedNewer()
        if let next = armed {
            current = next; armed = nil; armedTicket = nil; position = 0
            heard.append(next)
            if path == .pure { pureCount += 1 } else { enhancedCount += 1 }
        } else {
            ended = true
        }
        return a2
    }

    /// A request newer than what is armed has been sent but not admitted (still inbound or queued).
    func unadmittedNewer() -> Bool {
        let pending = (inbound + engineQueue).compactMap { op -> OnDeckTicket? in
            if case let .onDeck(_, t) = op.kind { return t }; return nil
        }
        return !pending.isEmpty
    }

    func clockTick() { if clockRunning { sample() } }
    var idle: Bool { engineQueue.isEmpty && inbound.isEmpty && pureOpening.isEmpty }
}

@MainActor final class LibraryModel {}
@MainActor
extension AudioViewModel {
    func hydrateQueueOnLaunch() {}
    func persistQueueCursor() {}
    func scheduleQueueMirror() { hasUserEditedQueue = true }
    func mirrorQueueNow() async {}
}
@MainActor var playCountLog: [String] = []
@MainActor var failures = 0
@MainActor var armMode: ArmMode = .gatedRetract(endFinal: true)
@MainActor var scopedCount = false
