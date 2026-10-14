@testable import AdaptiveSound
import Foundation
import PlaybackQueueKit

// MARK: - The engine model's state machine (council D41)

/// What `OnDeckEngineModel` keeps, and every step it takes, as plain mutating code — the model runs
/// each step under its lock.
struct OnDeckEngineState {
    /// What became audible, in order: a fresh start, a gapless seam, or a seam a render callback
    /// made after the end.
    enum Heard: Equatable, CustomStringConvertible {
        case start(URL)
        case seam(URL)
        case lateSeam(URL)

        var isLateSeam: Bool {
            if case .lateSeam = self {
                return true
            }
            return false
        }

        var description: String {
            switch self {
            case let .start(url): "start \(url.trackName)"
            case let .seam(url): "seam \(url.trackName)"
            case let .lateSeam(url): "LATE seam \(url.trackName)"
            }
        }
    }

    /// A seam, the newest request that had taken effect when it fired, and whether the seam went
    /// into that request's pick (the A2 accounting).
    struct Seam {
        let newestApplied: UInt64
        let intoNewestApplied: Bool
    }

    struct Request {
        let url: URL?
        let ticket: OnDeckTicket
    }

    enum TransportOp {
        case start(URL?, pure: Bool, epoch: UInt64)
        case stop(epoch: UInt64)
        case seek(epoch: UInt64)

        var epoch: UInt64 {
            switch self {
            case let .start(_, _, epoch), let .stop(epoch), let .seek(epoch): epoch
            }
        }
    }

    /// A transport op the view model is waiting on; resumed with "the start failed".
    struct HeldOp {
        let op: TransportOp
        let resume: CheckedContinuation<Bool, Never>
    }

    let semantics: ArmSemantics
    let incompatible: Set<URL>
    let unreadable: Set<URL>
    var pure = false
    var playing: URL?
    var armed: URL?
    var ended = false
    var pureCount: UInt64 = 0
    var enhancedCount: UInt64 = 0
    var epoch: UInt64 = 0
    var gate = OnDeckGate()
    var newestApplied: UInt64 = 0
    var newestAppliedURL: URL?
    var inbound: [Request] = []
    var opening: [Request] = []
    var opened: [URL] = []
    var arrivals: [OnDeckTicket] = []
    var holdsTransport = false
    var held: [HeldOp] = []
    var receivedEpoch: UInt64 = 0
    var failedEpochs: Set<UInt64> = []
    var heard: [Heard] = []
    var unprocessedSeams: [Seam] = []
    var published = TransportSnapshot()

    init(semantics: ArmSemantics, incompatible: Set<URL>, unreadable: Set<URL>) {
        self.semantics = semantics
        self.incompatible = incompatible
        self.unreadable = unreadable
    }

    var count: UInt64 {
        pure ? pureCount : enhancedCount
    }

    // MARK: engineQueue

    /// The transport clock's sample (the model runs each op whole, under its lock, so no one sees
    /// an op's transitional sample).
    mutating func publish() {
        published = TransportSnapshot(epoch: epoch, position: playing == nil ? nil : 1,
                                      transitionCount: count, ended: ended)
    }

    /// Run a transport op as `engineQueue` does; returns whether a start failed (unreadable).
    mutating func perform(_ op: TransportOp) -> Bool {
        epoch = max(epoch, op.epoch)
        defer { publish() }
        if case .seek = op {
            return false
        }
        beginPlayback(op.epoch)
        guard case let .start(url, isPure, _) = op else { return false } // a stop
        guard let url, !unreadable.contains(url) else {
            failedEpochs.insert(op.epoch)
            return true
        }
        pure = isPure
        pureCount = 0
        playing = url
        heard.append(.start(url))
        return false
    }

    /// A start or a stop begins a new playback: nothing plays, nothing is armed, every earlier
    /// request is stale. Without monotonic sessions (the design as first written) the engine's
    /// playback is simply the last one begun.
    private mutating func beginPlayback(_ operationEpoch: UInt64) {
        if !semantics.monotonicSessions {
            gate = OnDeckGate()
        }
        gate.beginSession(operationEpoch)
        newestApplied = 0
        newestAppliedURL = nil
        playing = nil
        pure = false
        armed = nil
        ended = false
        unprocessedSeams.removeAll()
    }

    /// An inbound request reaches `engineQueue` — the `rank`-th oldest by its place in the view
    /// model's order: admission, then the arm.
    mutating func deliver(rank: Int) {
        let byAge = inbound.indices.sorted { inbound[$0].ticket.sequence < inbound[$1].ticket.sequence }
        let request = inbound.remove(at: byAge[rank])
        if semantics.gated {
            guard gate.admit(request.ticket) else { return }
        }
        if request.ticket.sequence > newestApplied {
            newestApplied = request.ticket.sequence
            newestAppliedURL = request.url
        }
        guard pure else {
            armed = request.url // Enhanced: the slot, at once
            return
        }
        // Pure: a clear applies at once; a new pick takes the old one off at admission only in the
        // design.
        if request.url == nil || semantics.retractsAtAdmission {
            armed = nil
        }
        if let url = request.url {
            opened.append(url)
            opening.append(request)
        }
    }

    /// The Pure open at `index` lands on `engineQueue`.
    mutating func finishOpen(_ index: Int) {
        let request = opening.remove(at: index)
        guard let url = armable(request) else { return }
        switch semantics {
        case .refuse:
            if armed == nil, !incompatible.contains(url) {
                armed = url
            }
        case .clearThenArm, .gatedReplaceAfterOpen:
            armed = incompatible.contains(url) ? nil : url
        case .gatedRetractFirst:
            // The slot is empty: the admission took the old pick off.
            precondition(armed == nil, "arming over an armed pick")
            armed = incompatible.contains(url) ? nil : url
        }
    }

    /// The pick an opened request may arm, or `nil`: its open failed, a newer request superseded it,
    /// Pure no longer plays, or (when the end is final) the track already ended.
    private func armable(_ request: Request) -> URL? {
        guard let url = request.url, !unreadable.contains(url), pure, playing != nil else { return nil }
        if semantics.gated, !gate.isCurrent(request.ticket) {
            return nil
        }
        return semantics.endFinal && ended ? nil : url
    }

    // MARK: The render

    /// The current track's true end: a seam into the armed pick, or the end flag.
    mutating func trackEnds() {
        guard playing != nil, !ended else { return }
        guard let next = armed else {
            ended = true
            return
        }
        if pure {
            pureCount += 1
        } else {
            enhancedCount += 1
        }
        seam(into: next, late: false)
    }

    /// A render callback after the end. Pure only: Enhanced's end hook has already fired.
    mutating func renderAfterEnd() {
        guard ended, pure, !semantics.endFinal, let next = armed else { return }
        pureCount += 1 // GaplessSource keeps ended set
        seam(into: next, late: true)
    }

    private mutating func seam(into next: URL, late: Bool) {
        playing = next
        armed = nil
        heard.append(late ? .lateSeam(next) : .seam(next))
        unprocessedSeams.append(Seam(newestApplied: newestApplied, intoNewestApplied: next == newestAppliedURL))
    }
}

extension URL {
    /// `t3` for `/nonexistent/ondeck/t3.flac`.
    var trackName: String {
        deletingPathExtension().lastPathComponent
    }
}
