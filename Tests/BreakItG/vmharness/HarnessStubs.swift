// S10.8 G break-it (playback/shell lane) — the stand-ins the VM harness compiles beside the REAL
// AudioViewModel sources (run.sh copies them verbatim). Nothing here is product code: a fake engine
// that records every call and plays nothing, an empty LibraryModel, and no-op stand-ins for the three
// store-backed extensions (+QueueHydration, +QueueMirror, +PlayTracking) the scenarios don't exercise.

import Foundation
import SwiftUI

/// The fake engine, under the name AudioViewModel's default argument expects. Plays nothing: it records
/// what the view model asks for and reports whatever the scenario sets.
final class AudioEngineBridge: AudioPlaybackEngine, @unchecked Sendable {
    struct Start: Equatable {
        let url: URL?
        let pure: Bool
    }

    var starts: [Start] = []
    var stops = 0
    var seeks: [Double] = []
    var armed: [URL?] = []
    var position: Double?
    var transitions: UInt64 = 0
    var ended = false
    var onOutputDevicesChanged: (@MainActor () -> Void)?

    func initialize() async throws -> Bool { true }
    func shutdown() async throws {}
    func startAudio(fileURL: URL?, pureMode: Bool) async throws {
        starts.append(Start(url: fileURL, pure: pureMode))
        ended = false
    }

    func stopAudio() async throws { stops += 1 }
    func setNextTrack(_ fileURL: URL?) async { armed.append(fileURL) }
    func trackTransitionCount() -> UInt64 { transitions }
    func playbackEnded() -> Bool { ended }
    func seek(to seconds: Double) async { seeks.append(seconds) }
    func currentPlaybackPosition() -> Double? { position }
    func currentSignalPath() -> SignalPathInfo { SignalPathInfo() }
    func currentLoudness() -> LoudnessSnapshot { .unmeasured }
    var parameters: [UInt32: Float] = [:]
    func setParameter(_ id: UInt32, value: Float) async throws { parameters[id] = value }
    func publishEQ(points _: [Float], isOn _: Bool) {}
    func eqSampleRate() -> Double { 48000 }
    func enumerateOutputDevices() async throws -> [AudioDeviceModel] { [] }
    func selectDevice(_: UInt32) async throws -> Bool { true }
    @discardableResult
    func readSpectrumBands(into _: inout [Float]) -> Bool { false }
    var monitorChannelCount: Int { 0 }
    @discardableResult
    func readMonitorBands(_: MonitorTap, channel _: Int, into _: inout [Float]) -> Bool { false }
}

/// The library peer: absent (no store), as before the store is ready.
@MainActor
final class LibraryModel {}

@MainActor
extension AudioViewModel {
    // +QueueHydration / +QueueMirror stand-ins (store-backed; not under test here).
    func hydrateQueueOnLaunch() {}
    func persistQueueCursor() {}
    func scheduleQueueMirror() { hasUserEditedQueue = true }
    func mirrorQueueNow() async {}
    // +PlayTracking stand-ins (store-backed play counts; not under test here).
    func accruePlayThrough() {}
    func resetPlayTracking() {}
    func countCurrentPlay() {}
    func countPlayIfNaturalEndQualifies() {}
}
