@testable import AdaptiveSound
import Foundation
import PlaybackQueueKit
import Synchronization

// MARK: - A scripted model of the bridge's on-deck semantics (council D41)

//
// The REAL `AudioViewModel` (through `@testable import AdaptiveSound`) drives this engine. It keeps
// what the bridge does with a "play next" request, step by step, so a scenario can choose the
// order of everything the app leaves to timing:
//
// - A request (`setNextTrack`) first sits in `inbound`: the hop from the view model's task to
//   `engineQueue` can reorder two requests. `hop` delivers one: admission (`OnDeckGate`, the real
//   type), then — Enhanced — the slot is set; — Pure — the old pick comes off and the new pick's
//   file starts opening (`opening`, the global queue: opens can finish in any order).
// - `finishOpen` lands an open on `engineQueue`: arm if the request is still the newest, the track
//   has not ended, and the pick can join gaplessly (`incompatible`); an `unreadable` file never
//   opens.
// - `trackEnds` is the current track's true end: a seam into the armed pick, or the end flag.
//   `renderAfterEnd` is a later render callback (the end is final — or not, per `semantics`).
// - `clockTick` publishes the transport sample the view model's tick reads.
//
// A start, stop or seek runs when the view model calls it (a start or stop begins a new playback,
// so anything still queued for the old one is dropped — the same outcome as `engineQueue`'s FIFO) —
// or, while `holdsTransport`, waits until `runHeld` runs it, so a scenario can let two starts reach
// the engine in the other order. `setNextTrack` returns once the request is recorded; the bridge
// returns once it is settled — that moves only when a start's `isPlaying = true` lands, which no
// scenario here depends on (they act from a settled, playing state).
//
// `semantics` selects the arm behaviour: the design, or one of the behaviours it replaced — the
// ablations that show each piece of the design is necessary.

final class OnDeckEngineModel: AudioPlaybackEngine {
    typealias Heard = OnDeckEngineState.Heard
    typealias Seam = OnDeckEngineState.Seam

    private let state: Mutex<OnDeckEngineState>

    init(semantics: ArmSemantics = .design, incompatible: Set<URL> = [], unreadable: Set<URL> = []) {
        state = Mutex(OnDeckEngineState(semantics: semantics, incompatible: incompatible, unreadable: unreadable))
    }

    // MARK: AudioPlaybackEngine — the transport

    func initialize() async throws -> Bool {
        true
    }

    func shutdown() async throws {}

    func startAudio(fileURL: URL?, pureMode: Bool, startAt _: Double, epoch: UInt64) async throws {
        if await transport(.start(fileURL, pure: pureMode, epoch: epoch)) {
            throw AudioBridgeError.unsupportedFormat("flac")
        }
    }

    func stopAudio(epoch: UInt64) async throws {
        _ = await transport(.stop(epoch: epoch))
    }

    func seek(to _: Double, epoch: UInt64) async throws {
        _ = await transport(.seek(epoch: epoch))
    }

    /// Run `op` now, or hold it for `runHeld`; returns whether a start failed.
    private func transport(_ op: OnDeckEngineState.TransportOp) async -> Bool {
        await withCheckedContinuation { (resume: CheckedContinuation<Bool, Never>) in
            let failed = state.withLock { model -> Bool? in
                model.receivedEpoch = max(model.receivedEpoch, op.epoch)
                guard !model.holdsTransport else {
                    model.held.append(OnDeckEngineState.HeldOp(op: op, resume: resume))
                    return nil
                }
                return model.perform(op)
            }
            if let failed {
                resume.resume(returning: failed)
            }
        }
    }

    func setNextTrack(_ fileURL: URL?, ticket: OnDeckTicket) async {
        state.withLock { model in
            model.arrivals.append(ticket)
            model.inbound.append(OnDeckEngineState.Request(url: fileURL, ticket: ticket))
        }
    }

    func snapshot() -> EngineSnapshot {
        EngineSnapshot(transport: state.withLock { $0.published })
    }

    // MARK: AudioPlaybackEngine — nothing else plays a part

    func publishEQ(points _: [Float], isOn _: Bool) {}

    func enumerateOutputDevices() async throws -> [AudioDeviceModel] {
        []
    }

    func selectDevice(_: UInt32) async throws -> Bool {
        true
    }

    var onOutputDevicesChanged: (@MainActor () -> Void)? {
        get { nil }
        set { _ = newValue }
    }

    @discardableResult
    func readSpectrumBands(into _: inout [Float]) -> Bool {
        false
    }

    var monitorChannelCount: Int {
        0
    }

    @discardableResult
    func readMonitorBands(_: MonitorTap, channel _: Int, into _: inout [Float]) -> Bool {
        false
    }

    // MARK: The engine's side, stepped by a scenario

    /// Hold the transport ops the view model sends from now on (`true`), or run them as they come.
    func holdTransport(_ hold: Bool) {
        state.withLock { $0.holdsTransport = hold }
    }

    /// Run the held op whose epoch is `epoch`, and let its caller go on.
    func runHeld(epoch: UInt64) {
        let (resume, failed) = state.withLock { model -> (CheckedContinuation<Bool, Never>?, Bool) in
            guard let index = model.held.firstIndex(where: { $0.op.epoch == epoch }) else { return (nil, false) }
            let held = model.held.remove(at: index)
            return (held.resume, model.perform(held.op))
        }
        resume?.resume(returning: failed)
    }

    /// Deliver an inbound request to `engineQueue`: the `rank`-th oldest by the view model's order.
    func hop(rank: Int) {
        state.withLock { $0.deliver(rank: rank) }
    }

    /// The Pure open at `index` lands on `engineQueue`.
    func finishOpen(_ index: Int) {
        state.withLock { $0.finishOpen(index) }
    }

    /// The current track's true end: a seam into the armed pick, or the end flag.
    func trackEnds() {
        state.withLock { $0.trackEnds() }
    }

    /// A render callback after the end.
    func renderAfterEnd() {
        state.withLock { $0.renderAfterEnd() }
    }

    func clockTick() {
        state.withLock { $0.publish() }
    }

    /// Deliver everything in flight — requests in the order they were made, then the opens in the
    /// order they started — until nothing is left.
    func drain() {
        state.withLock { model in
            while !model.inbound.isEmpty || !model.opening.isEmpty {
                if model.inbound.isEmpty {
                    model.finishOpen(0)
                } else {
                    model.deliver(rank: 0)
                }
            }
        }
    }

    /// The seam the view model's tick just processed (the oldest one it had not seen).
    func takeProcessedSeam() -> Seam? {
        state.withLock { $0.unprocessedSeams.isEmpty ? nil : $0.unprocessedSeams.removeFirst() }
    }

    // MARK: Reads

    var current: URL? {
        state.withLock { $0.playing }
    }

    var armed: URL? {
        state.withLock { $0.armed }
    }

    var ended: Bool {
        state.withLock { $0.ended }
    }

    var heard: [Heard] {
        state.withLock { $0.heard }
    }

    var opened: [URL] {
        state.withLock { $0.opened }
    }

    var inboundCount: Int {
        state.withLock { $0.inbound.count }
    }

    var openingCount: Int {
        state.withLock { $0.opening.count }
    }

    var heldEpochs: [UInt64] {
        state.withLock { $0.held.map(\.op.epoch) }
    }

    var hasUnprocessedSeam: Bool {
        state.withLock { !$0.unprocessedSeams.isEmpty }
    }

    var canRenderAfterEnd: Bool {
        state.withLock { $0.ended && $0.pure && $0.armed != nil }
    }

    /// Whether the start numbered `epoch` failed (its file is unreadable).
    func startFailed(epoch: UInt64) -> Bool {
        state.withLock { $0.failedEpochs.contains(epoch) }
    }

    /// Whether every request and transport op the view model made has reached the engine, and the
    /// newest start primed its on-deck (or failed, or waits held): the view model's tasks have
    /// nothing left to send.
    func hasReceivedEverything(sequence: UInt64, epoch: UInt64, session: UInt64) -> Bool {
        state.withLock { model in
            model.arrivals.count == Int(sequence) && model.receivedEpoch == epoch
                && (session == 0 || model.failedEpochs.contains(session)
                    || model.held.contains { $0.op.epoch == session }
                    || model.arrivals.contains { $0.session == session })
        }
    }
}
