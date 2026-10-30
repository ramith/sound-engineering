@testable import AdaptiveSound
import EQEditKit
import Foundation
import LevelingKit
import OutputDeviceKit
import PlaybackQueueKit
import SettingsKit
import Synchronization

// MARK: - The one engine double (test-rig redesign: one double, no mirror)

/// An `AudioPlaybackEngine` with no hardware and no logic of its own: a double provides inputs, never
/// logic. It serves what a test sets — the devices and the device it plays on, the snapshot (transport,
/// signal path, loudness, the EQ's design rate), the spectrum, and the outcome of a call — and records
/// every command the view model sends, in order (`calls`). The user's output choice is kept by the
/// product's own rule, `OutputDeviceSelection`, as the bridge keeps it, so no copy of that rule lives
/// here. It conforms to the app's own protocol, so the view model under test is the real one.
/// `OnDeckEngineModel` composes one for everything but the transport and the on-deck.
final class FakeEngine: AudioPlaybackEngine {
    /// One command the view model sent, as it sent it.
    enum Call: Equatable {
        case initialize
        case shutdown
        case start(URL, pure: Bool, startAt: Double, epoch: UInt64, leveling: TrackLevelingDecision)
        case stop(epoch: UInt64, pausing: Bool)
        case seek(Double, epoch: UInt64)
        case setNextTrack(URL?, ticket: OnDeckTicket, leveling: TrackLevelingDecision?)
        case levelingChange(current: TrackLevelingDecision, next: TrackLevelingDecision?)
        case masterGain(Float)
        case keepPureVolumeLoans([PureVolumeLoan])
        case eq(points: [Float], isOn: Bool, comparing: Bool)
        case intensity(Float)
        case outputTransport(UInt32)
        case crossfeed(enabled: Bool, strength: CrossfeedStrength)
        case enumerateOutputDevices
        case selectDevice(UInt32)
        case pin(Bool)
        case restoreChosenOutput(String?)
        case monitorAnalysis(Bool)
    }

    /// What a `stopAudio` call was.
    enum StopKind: Equatable {
        case pause, stop
    }

    let state = Mutex(State())

    private func record(_ call: Call) {
        state.withLock { $0.calls.append(call) }
    }

    // MARK: Lifecycle and transport

    func initialize() async throws -> Bool {
        let (result, error) = state.withLock { state in
            state.calls.append(.initialize)
            return (state.initializeResult, state.initializeError)
        }
        if let error {
            throw error
        }
        return result
    }

    func shutdown() async throws {
        record(.shutdown)
    }

    func startAudio(fileURL: URL, pureMode: Bool, startAt: Double, epoch: UInt64,
                    leveling: TrackLevelingDecision) async throws {
        let error = state.withLock { state in
            state.calls.append(.start(fileURL, pure: pureMode, startAt: startAt, epoch: epoch, leveling: leveling))
            return state.startError
        }
        if let error {
            throw error
        }
    }

    func stopAudio(epoch: UInt64, pausing: Bool) async throws {
        record(.stop(epoch: epoch, pausing: pausing))
    }

    func setNextTrack(_ fileURL: URL?, ticket: OnDeckTicket, leveling: TrackLevelingDecision?) async {
        record(.setNextTrack(fileURL, ticket: ticket, leveling: leveling))
    }

    func applyLevelingChange(current: TrackLevelingDecision, next: TrackLevelingDecision?) {
        record(.levelingChange(current: current, next: next))
    }

    func snapshot() -> EngineSnapshot {
        state.withLock { state in
            state.snapshotReads += 1
            return EngineSnapshot(transport: state.transport, signalPath: state.signalPath, loudness: state.loudness,
                                  eqDesignRate: state.eqDesignRate)
        }
    }

    func seek(to seconds: Double, epoch: UInt64) async throws {
        record(.seek(seconds, epoch: epoch))
    }

    // MARK: Levels and the DSP

    func publishMasterGain(decibels: Float) {
        record(.masterGain(decibels))
    }

    func keepPureVolumeLoans(in journal: PureVolumeLoanJournal) {
        record(.keepPureVolumeLoans(journal.loans()))
    }

    func reportPureVolumeRestores(to restored: @escaping @MainActor @Sendable () -> Void) {
        state.withLock { $0.pureVolumeRestored = restored }
    }

    /// Pure gave the device's volume back at another level (`MasterGainOnPure.onRestore`): tell the receiver the
    /// view model gave, on the main actor, as the bridge does.
    @MainActor
    func restorePureVolume() {
        state.withLock(\.pureVolumeRestored)?()
    }

    func publishEQ(points: [Float], isOn: Bool, comparing: Bool) {
        record(.eq(points: points, isOn: isOn, comparing: comparing))
    }

    func publishIntensity(_ intensity: Float) {
        record(.intensity(intensity))
    }

    func publishOutputTransport(_ transportType: UInt32) {
        record(.outputTransport(transportType))
    }

    func publishCrossfeed(enabled: Bool, strength: CrossfeedStrength) {
        record(.crossfeed(enabled: enabled, strength: strength))
    }

    // MARK: Devices

    func enumerateOutputDevices() async throws -> [AudioDeviceModel] {
        state.withLock { state in
            state.calls.append(.enumerateOutputDevices)
            return state.devices
        }
    }

    func selectDevice(_ deviceID: UInt32) async throws -> Bool {
        state.withLock { state in
            state.calls.append(.selectDevice(deviceID))
            guard state.selectResult else { return false }
            state.selection.choose(deviceID, uid: state.uid(of: deviceID))
            return true
        }
    }

    func currentOutputDeviceID() -> UInt32 {
        state.withLock(\.engineDevice)
    }

    func setPinPlaybackToSelectedDevice(_ pin: Bool) {
        state.withLock { state in
            state.calls.append(.pin(pin))
            state.selection.pin(pin)
        }
    }

    func restoreChosenOutput(uid: String?) {
        state.withLock { state in
            state.calls.append(.restoreChosenOutput(uid))
            state.selection.restoreChoice(uid: uid ?? "")
        }
    }

    func chosenOutputUID() -> String? {
        state.withLock { state in
            state.selection.chosenUID.isEmpty ? nil : state.selection.chosenUID
        }
    }

    var onOutputDevicesChanged: (@MainActor () -> Void)? {
        get { state.withLock { $0.onOutputDevicesChanged } }
        set { state.withLock { $0.onOutputDevicesChanged = newValue } }
    }

    // MARK: Spectrum and monitoring

    @discardableResult
    func readSpectrumBands(into out: inout [Float]) -> Bool {
        let frame: [Float]? = state.withLock { state in
            state.spectrumReads += 1
            return state.spectrumFrames.isEmpty ? nil : state.spectrumFrames.removeFirst()
        }
        guard let frame else { return false }
        out = frame
        return true
    }

    var monitorChannelCount: Int {
        0
    }

    @discardableResult
    func readMonitorBands(_: MonitorTap, channel _: Int, into _: inout [Float]) -> Bool {
        false
    }

    func setMonitorAnalysis(_ isOn: Bool) {
        record(.monitorAnalysis(isOn))
    }
}

// MARK: - What a test sets, and the record

extension FakeEngine {
    /// What a test sets (the inputs) and reads (the record).
    struct State {
        // MARK: Inputs

        /// The output devices connected, as `enumerateOutputDevices` lists them.
        var devices: [AudioDeviceModel] = []
        /// The transport as the engine's clock last sampled it: `snapshot()` serves it as set.
        var transport = TransportSnapshot()
        var signalPath = SignalPathInfo()
        var loudness: LoudnessSnapshot = .unmeasured
        var eqDesignRate = 48000.0
        /// The analyser frames still to serve, oldest first: each read takes one (44 bands in 0…1).
        var spectrumFrames: [[Float]] = []
        /// What `initialize` answers, and the error it throws instead when set.
        var initializeResult = true
        var initializeError: (any Error)?
        /// The error `startAudio` throws, when set.
        var startError: (any Error)?
        /// What `selectDevice` answers: `false` is a pick the system refused (nothing changes).
        var selectResult = true
        var onOutputDevicesChanged: (@MainActor () -> Void)?
        /// Who hears that Pure gave a device's volume back at another level (`reportPureVolumeRestores`).
        var pureVolumeRestored: (@MainActor @Sendable () -> Void)?
        /// The device the app plays on and the device the user chose, by the product's rule.
        var selection = OutputDeviceSelection()

        // MARK: The record

        /// Every command, in the order the view model sent them.
        var calls: [Call] = []
        /// How often the view model read the engine's state (`snapshot`) — its transport tick.
        var snapshotReads = 0
        /// How often anything read the analyser's latest frame (`readSpectrumBands`).
        var spectrumReads = 0

        /// The device the engine plays on (`currentOutputDeviceID`). Setting it is the engine moving
        /// there on its own (the output rule's `adopt`): never a pick.
        var engineDevice: UInt32 {
            get { selection.target }
            set { selection.adopt(newValue, uid: uid(of: newValue)) }
        }

        func uid(of device: UInt32) -> String {
            devices.first { $0.id == device }?.uid ?? ""
        }
    }
}

// MARK: - The record, by kind

extension FakeEngine.State {
    /// The commands of one kind, by what each carried.
    func recorded<Value>(_ value: (FakeEngine.Call) -> Value?) -> [Value] {
        calls.compactMap(value)
    }

    /// Every `startAudio` call's start position.
    var starts: [Double] {
        recorded { call in
            guard case let .start(_, _, startAt, _, _) = call else { return nil }
            return startAt
        }
    }

    /// Every `startAudio` call's file.
    var startedURLs: [URL] {
        recorded { call in
            guard case let .start(url, _, _, _, _) = call else { return nil }
            return url
        }
    }

    /// Every `startAudio` call's `pureMode`.
    var pureModes: [Bool] {
        recorded { call in
            guard case let .start(_, pure, _, _, _) = call else { return nil }
            return pure
        }
    }

    /// Every `stopAudio` call: a pause (playback resumes; Pure keeps the device's volume) or a stop.
    var stops: [FakeEngine.StopKind] {
        recorded { call in
            guard case let .stop(_, pausing) = call else { return nil }
            return pausing ? .pause : .stop
        }
    }

    /// Every `seek` call's target.
    var seeks: [Double] {
        recorded { call in
            guard case let .seek(seconds, _) = call else { return nil }
            return seconds
        }
    }

    /// Every on-deck request's pick (`nil`: a clear).
    var nextTracks: [URL?] {
        recorded { call in
            guard case let .setNextTrack(url, _, _) = call else { return nil }
            return .some(url)
        }
    }

    /// Every `startAudio` call's leveling decision (R1.1-B, B2: every start carries one).
    var startLevelings: [TrackLevelingDecision] {
        recorded { call in
            guard case let .start(_, _, _, _, leveling) = call else { return nil }
            return leveling
        }
    }

    /// Every on-deck request's leveling decision (`nil` with a clear).
    var nextLevelings: [TrackLevelingDecision?] {
        recorded { call in
            guard case let .setNextTrack(_, _, leveling) = call else { return nil }
            return .some(leveling)
        }
    }

    /// Every `selectDevice` call: the user's picks, the only way the choice moves by a pick.
    var picks: [UInt32] {
        recorded { call in
            guard case let .selectDevice(device) = call else { return nil }
            return device
        }
    }

    /// Every Master Gain published.
    var masterGains: [Float] {
        recorded { call in
            guard case let .masterGain(decibels) = call else { return nil }
            return decibels
        }
    }

    /// Every Intensity published.
    var intensities: [Float] {
        recorded { call in
            guard case let .intensity(intensity) = call else { return nil }
            return intensity
        }
    }

    /// Every crossfeed published: whether it plays.
    var crossfeeds: [Bool] {
        recorded { call in
            guard case let .crossfeed(enabled, _) = call else { return nil }
            return enabled
        }
    }

    /// Every `keepPureVolumeLoans` call: the loans the journal it was handed holds (an earlier run's).
    var journalLoans: [[PureVolumeLoan]] {
        recorded { call in
            guard case let .keepPureVolumeLoans(loans) = call else { return nil }
            return loans
        }
    }

    /// Every `restoreChosenOutput` call: an earlier session's choice handed back at engine-ready.
    var restoredChoices: [String?] {
        recorded { call in
            guard case let .restoreChosenOutput(uid) = call else { return nil }
            return .some(uid)
        }
    }
}
