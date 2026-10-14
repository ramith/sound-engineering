@testable import AdaptiveSound
import Foundation
import Synchronization

// MARK: - A recording engine for the output-device view-model tests

/// An `AudioPlaybackEngine` with no hardware: it serves the device list and the device the engine
/// plays on that a test sets, and records the picks, starts and Intensity the view model sends it. It conforms
/// to the app's own protocol, so the view model under test is the real one.
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
        /// Every Intensity published.
        var intensities: [Float] = []
        var onOutputDevicesChanged: (@MainActor () -> Void)?
    }

    let state = Mutex(State())

    func initialize() async throws -> Bool {
        true
    }

    func shutdown() async throws {}

    func startAudio(fileURL _: URL?, pureMode _: Bool, startAt: Double, epoch _: UInt64) async throws {
        state.withLock { $0.starts.append(startAt) }
    }

    func stopAudio(epoch _: UInt64) async throws {}

    func setNextTrack(_: URL?) async {}

    func snapshot() -> EngineSnapshot {
        var snapshot = EngineSnapshot()
        snapshot.signalPath = state.withLock { $0.signalPath }
        return snapshot
    }

    func seek(to _: Double, epoch _: UInt64) async throws {}

    func publishMasterGain(decibels _: Float) {}

    func requestDeviceVolume(decibels _: Float) {}

    func publishEQ(points _: [Float], isOn _: Bool) {}

    func publishIntensity(_ intensity: Float) {
        state.withLock { $0.intensities.append(intensity) }
    }

    func publishOutputTransport(_: UInt32) {}

    func publishCrossfeed(enabled _: Bool, strength _: CrossfeedStrength) {}

    func enumerateOutputDevices() async throws -> [AudioDeviceModel] {
        state.withLock { $0.devices }
    }

    func selectDevice(_ deviceID: UInt32) async throws -> Bool {
        state.withLock {
            $0.picks.append(deviceID)
            $0.engineDevice = deviceID
        }
        return true
    }

    func currentOutputDeviceID() -> UInt32 {
        state.withLock { $0.engineDevice }
    }

    func setPinPlaybackToSelectedDevice(_: Bool) {}

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
