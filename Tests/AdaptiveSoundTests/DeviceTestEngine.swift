@testable import AdaptiveSound
import Foundation
import SettingsKit
import Synchronization

// MARK: - A recording engine for the output-device view-model tests

/// An `AudioPlaybackEngine` with no hardware: it serves the device list and the device the engine
/// plays on that a test sets, and records the picks, starts, seeks and publishes the view model sends it.
/// It keeps the device the user chose as the bridge does (`OutputDeviceSelection`): a pick chooses
/// it, turning "Keep playback on this device" on chooses the device in use, a restore brings back an
/// earlier session's. It conforms to the app's own protocol, so the view model under test is the
/// real one.
final class DeviceTestEngine: AudioPlaybackEngine {
    /// What a test sets and reads.
    struct State {
        var devices: [AudioDeviceModel] = []
        /// The device the engine plays on (`currentOutputDeviceID`).
        var engineDevice: UInt32 = 0
        var signalPath = SignalPathInfo()
        /// Every `selectDevice` call: the user's picks, the only way the pin moves.
        var picks: [UInt32] = []
        /// Every `startAudio` call's start position.
        var starts: [Double] = []
        /// Every `startAudio` call's `pureMode`.
        var pureModes: [Bool] = []
        /// Every Intensity published.
        var intensities: [Float] = []
        /// Every crossfeed published: whether it plays.
        var crossfeeds: [Bool] = []
        /// Every `restoreChosenOutput` call: an earlier session's choice handed back at engine-ready.
        var restoredChoices: [String?] = []
        /// "Keep playback on this device", as the view model last set it.
        var pinned = true
        /// The UID of the device the user chose (`chosenOutputUID`).
        var chosenUID: String?
        /// Every `seek` call's target.
        var seeks: [Double] = []
        var onOutputDevicesChanged: (@MainActor () -> Void)?
    }

    let state = Mutex(State())

    func initialize() async throws -> Bool {
        true
    }

    func shutdown() async throws {}

    func startAudio(fileURL _: URL?, pureMode: Bool, startAt: Double, epoch _: UInt64) async throws {
        state.withLock {
            $0.starts.append(startAt)
            $0.pureModes.append(pureMode)
        }
    }

    func stopAudio(epoch _: UInt64) async throws {}

    func setNextTrack(_: URL?) async {}

    func snapshot() -> EngineSnapshot {
        var snapshot = EngineSnapshot()
        snapshot.signalPath = state.withLock { $0.signalPath }
        return snapshot
    }

    func seek(to seconds: Double, epoch _: UInt64) async throws {
        state.withLock { $0.seeks.append(seconds) }
    }

    func publishMasterGain(decibels _: Float) {}

    func requestDeviceVolume(decibels _: Float) {}

    func publishEQ(points _: [Float], isOn _: Bool) {}

    func publishIntensity(_ intensity: Float) {
        state.withLock { $0.intensities.append(intensity) }
    }

    func publishOutputTransport(_: UInt32) {}

    func publishCrossfeed(enabled: Bool, strength _: CrossfeedStrength) {
        state.withLock { $0.crossfeeds.append(enabled) }
    }

    func enumerateOutputDevices() async throws -> [AudioDeviceModel] {
        state.withLock { $0.devices }
    }

    func selectDevice(_ deviceID: UInt32) async throws -> Bool {
        state.withLock { state in
            state.picks.append(deviceID)
            state.engineDevice = deviceID
            state.chosenUID = state.devices.first { $0.id == deviceID }?.uid
        }
        return true
    }

    func currentOutputDeviceID() -> UInt32 {
        state.withLock { $0.engineDevice }
    }

    func setPinPlaybackToSelectedDevice(_ pin: Bool) {
        state.withLock { state in
            if pin, !state.pinned {
                state.chosenUID = state.devices.first { $0.id == state.engineDevice }?.uid
            }
            state.pinned = pin
        }
    }

    func restoreChosenOutput(uid: String?) {
        state.withLock {
            $0.restoredChoices.append(uid)
            $0.chosenUID = uid
        }
    }

    func chosenOutputUID() -> String? {
        state.withLock { $0.chosenUID }
    }

    var onOutputDevicesChanged: (@MainActor () -> Void)? {
        get { state.withLock { $0.onOutputDevicesChanged } }
        set { state.withLock { $0.onOutputDevicesChanged = newValue } }
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
}
