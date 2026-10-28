@testable import AdaptiveSound
import Foundation
import LevelingKit
import PlaybackQueueKit
import SettingsKit
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
// the engine in the other order. `setNextTrack` returns once its request is settled — dropped, set,
// or (Pure) armed / left empty — as the bridge's does: a start's prime holds `isPlaying` false until
// then (council F-P4-1 hid behind a model that returned at record).
//
// `semantics` selects the arm behaviour: the design, or one of the behaviours it replaced — the
// ablations that show each piece of the design is necessary. `commands` does the same for the
// transport commands (council C-15): the design drops one older than a command already begun.
//
// Everything else the protocol asks for — the lifecycle, the devices, the levels, the DSP, the rest
// of the snapshot (the signal path, the loudness, the EQ's design rate), the spectrum — is the one
// engine double's (`fake`): it serves what a test sets there and records what the view model sends.

final class OnDeckEngineModel: AudioPlaybackEngine {
    typealias Heard = OnDeckEngineState.Heard
    typealias Seam = OnDeckEngineState.Seam

    private let state: Mutex<OnDeckEngineState>
    /// Everything but the transport and the on-deck: inputs a test sets (a lost device's signal path,
    /// the devices) and the record of what the view model sent.
    let fake = FakeEngine()

    init(semantics: ArmSemantics = .design, commands: CommandSemantics = .dropsOvertaken,
         incompatible: Set<URL> = [], unreadable: Set<URL> = []) {
        state = Mutex(OnDeckEngineState(semantics: semantics, commands: commands, incompatible: incompatible,
                                        unreadable: unreadable))
    }

    // MARK: AudioPlaybackEngine — the transport

    func startAudio(fileURL: URL, pureMode: Bool, startAt _: Double, epoch: UInt64,
                    leveling _: TrackLevelingDecision) async throws {
        if await transport(.start(fileURL, pure: pureMode, epoch: epoch)) {
            throw AudioBridgeError.unsupportedFormat("flac")
        }
    }

    func stopAudio(epoch: UInt64, pausing _: Bool) async throws {
        _ = await transport(.stop(epoch: epoch))
    }

    func seek(to _: Double, epoch: UInt64) async throws {
        _ = await transport(.seek(epoch: epoch))
    }

    /// Run `op` now, or hold it for `runHeld`; returns whether a start failed.
    private func transport(_ op: OnDeckEngineState.TransportOp) async -> Bool {
        await withCheckedContinuation { (resume: CheckedContinuation<Bool, Never>) in
            let failed = state.withLock { model -> Bool? in
                model.receive(op)
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

    func setNextTrack(_ fileURL: URL?, ticket: OnDeckTicket, leveling _: TrackLevelingDecision?) async {
        await withCheckedContinuation { (settled: CheckedContinuation<Void, Never>) in
            state.withLock { model in
                model.arrivals.append(ticket)
                model.inbound.append(OnDeckEngineState.Request(url: fileURL, ticket: ticket, settled: settled))
            }
        }
    }

    /// The transport as this model published it; the rest of the snapshot is the fake's.
    func snapshot() -> EngineSnapshot {
        var snapshot = fake.snapshot()
        snapshot.transport = state.withLock { $0.published }
        return snapshot
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

    /// Run every held op in the order they reached the engine (`engineQueue` is FIFO), and let their
    /// callers go on.
    func runAllHeld() {
        while let epoch = state.withLock({ $0.held.first?.op.epoch }) {
            runHeld(epoch: epoch)
        }
    }

    /// Deliver an inbound request to `engineQueue`: the `rank`-th oldest by the view model's order.
    func hop(rank: Int) {
        settle { model, settled in model.deliver(rank: rank, settled: &settled) }
    }

    /// The Pure open at `index` lands on `engineQueue`.
    func finishOpen(_ index: Int) {
        settle { model, settled in model.finishOpen(index, settled: &settled) }
    }

    /// Run `step` under the lock, then let the callers whose requests it settled go on.
    private func settle(_ step: (inout OnDeckEngineState, inout OnDeckEngineState.Settled) -> Void) {
        let settled = state.withLock { model -> OnDeckEngineState.Settled in
            var settled: OnDeckEngineState.Settled = []
            step(&model, &settled)
            return settled
        }
        settled.forEach { $0.resume() }
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
        settle { model, settled in
            while !model.inbound.isEmpty || !model.opening.isEmpty {
                if model.inbound.isEmpty {
                    model.finishOpen(0, settled: &settled)
                } else {
                    model.deliver(rank: 0, settled: &settled)
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

    /// Whether the playback the engine is in plays on Pure (as its start asked).
    var playsPure: Bool {
        state.withLock { $0.pure }
    }

    /// The view model's callers the engine owes a resumption to: held ops, undelivered requests, opens.
    var owedCallers: Int {
        heldEpochs.count + inboundCount + openingCount
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

    /// The commands the engine dropped as overtaken.
    var droppedEpochs: [UInt64] {
        state.withLock { $0.droppedEpochs }
    }

    /// The transport commands that have reached the engine so far.
    var receivedCount: Int {
        state.withLock { $0.receivedEpochs.count }
    }

    /// Every transport command and on-deck request that has reached the engine so far.
    var callCount: Int {
        state.withLock { $0.receivedEpochs.count + $0.arrivals.count }
    }

    /// Whether every request, open and held command has landed.
    var isIdle: Bool {
        state.withLock(\.isIdle)
    }

    var hasUnprocessedSeam: Bool {
        state.withLock { !$0.unprocessedSeams.isEmpty }
    }

    var canRenderAfterEnd: Bool {
        state.withLock { $0.ended && $0.pure && $0.armed != nil }
    }

    /// Whether every request and transport op the view model made has reached the engine (it numbers
    /// each op, from 1, and sends every one it numbers).
    func hasReceivedEverything(sequence: UInt64, epoch: UInt64) -> Bool {
        state.withLock { model in
            model.arrivals.count == Int(sequence) && model.receivedEpochs.count == Int(epoch)
        }
    }
}

// MARK: AudioPlaybackEngine — everything else is the fake's

extension OnDeckEngineModel {
    func initialize() async throws -> Bool {
        try await fake.initialize()
    }

    func shutdown() async throws {
        try await fake.shutdown()
    }

    func publishMasterGain(decibels: Float) {
        fake.publishMasterGain(decibels: decibels)
    }

    func keepPureVolumeLoans(in journal: PureVolumeLoanJournal) {
        fake.keepPureVolumeLoans(in: journal)
    }

    func publishEQ(points: [Float], isOn: Bool, comparing: Bool) {
        fake.publishEQ(points: points, isOn: isOn, comparing: comparing)
    }

    func publishIntensity(_ intensity: Float) {
        fake.publishIntensity(intensity)
    }

    func publishOutputTransport(_ transportType: UInt32) {
        fake.publishOutputTransport(transportType)
    }

    func publishCrossfeed(enabled: Bool, strength: CrossfeedStrength) {
        fake.publishCrossfeed(enabled: enabled, strength: strength)
    }

    func enumerateOutputDevices() async throws -> [AudioDeviceModel] {
        try await fake.enumerateOutputDevices()
    }

    func selectDevice(_ deviceID: UInt32) async throws -> Bool {
        try await fake.selectDevice(deviceID)
    }

    func currentOutputDeviceID() -> UInt32 {
        fake.currentOutputDeviceID()
    }

    func setPinPlaybackToSelectedDevice(_ pin: Bool) {
        fake.setPinPlaybackToSelectedDevice(pin)
    }

    func restoreChosenOutput(uid: String?) {
        fake.restoreChosenOutput(uid: uid)
    }

    func chosenOutputUID() -> String? {
        fake.chosenOutputUID()
    }

    var onOutputDevicesChanged: (@MainActor () -> Void)? {
        get { fake.onOutputDevicesChanged }
        set { fake.onOutputDevicesChanged = newValue }
    }

    @discardableResult
    func readSpectrumBands(into out: inout [Float]) -> Bool {
        fake.readSpectrumBands(into: &out)
    }

    var monitorChannelCount: Int {
        fake.monitorChannelCount
    }

    @discardableResult
    func readMonitorBands(_ tap: MonitorTap, channel: Int, into out: inout [Float]) -> Bool {
        fake.readMonitorBands(tap, channel: channel, into: &out)
    }

    func setMonitorAnalysis(_ isOn: Bool) {
        fake.setMonitorAnalysis(isOn)
    }
}
