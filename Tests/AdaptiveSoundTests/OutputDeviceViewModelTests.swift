// N92 — the view model's half of "Return to headphones" (R1), on the real `AudioViewModel`: it shows
// the device the engine plays on, moves Pure playback when the engine moves, and never picks a device
// itself — not after a loss, not at launch, not on a re-initialization: a pick is the user's, and the
// pin returns to it (OutputDeviceSelection).

@testable import AdaptiveSound
import EQEditKit
import Foundation
import RigKit
import Testing

@MainActor
@Suite("AudioViewModel — the output the engine moved to", .timeLimit(.minutes(3)), .attachingLogTail)
struct OutputDeviceViewModelTests {
    private static let headphones = AudioDeviceModel(
        id: 41, name: "Headphones", sampleRate: 48000, bufferFrameSize: 512,
        uid: "AA-BB-CC-DD-EE-FF:output", modelUID: nil, transportType: 0, type: .wireless, isHeadphones: true
    )
    private static let speakers = AudioDeviceModel(
        id: 42, name: "Speakers", sampleRate: 48000, bufferFrameSize: 512,
        uid: "BuiltInSpeakerDevice", modelUID: nil, transportType: 0, type: .builtin, isHeadphones: false
    )
    /// The headphones back from a reconnect: a new id, the same UID.
    private static let headphonesBack = AudioDeviceModel(
        id: 57, name: "Headphones", sampleRate: 48000, bufferFrameSize: 512,
        uid: "AA-BB-CC-DD-EE-FF:output", modelUID: nil, transportType: 0, type: .wireless, isHeadphones: true
    )

    private let engine = FakeEngine()
    private let viewModel: AudioViewModel
    /// This test's own defaults suite, never the app's, removed with it: the view model keeps the
    /// listener's settings there (a pick is remembered).
    private let world = IsolatedDefaults("OutputDevice")

    init() {
        QuietLog.install()
        viewModel = AudioViewModel(defaults: world.defaults, engine: engine)
        viewModel.isEngineReady = true
        viewModel.selectedDevice = Self.headphones
    }

    /// One song in the queue, selected.
    private func queueOneSong() {
        let url = URL(fileURLWithPath: "/nonexistent/song.flac") // never opened: the engine records it
        let song = AudioFile(name: "Song", relativePath: "", absoluteURL: url, format: "FLAC", durationSeconds: 240)
        viewModel.queue = [QueueItem(file: song)]
        viewModel.selectedTrackIndex = 0
    }

    /// The engine moved (or lost) its device and calls back: the view model re-reads.
    private func engineMoves(to device: UInt32, listing devices: [AudioDeviceModel]) async throws {
        engine.state.withLock {
            $0.devices = devices
            $0.engineDevice = device
        }
        viewModel.refreshDevices()
        try await settle()
    }

    /// Wait until the view model's tasks (refresh, start) have finished.
    private func settle() async throws {
        try await viewModel.settled()
    }

    @Test("a lost device is never replaced by a pick: the fallback is the engine's, not the user's")
    func lostDeviceIsNeverPicked() async throws {
        // The headphones are gone and the engine has not moved yet: no device shows, none is picked.
        try await engineMoves(to: Self.headphones.id, listing: [Self.speakers])
        #expect(viewModel.selectedDevice == nil)
        // The engine falls back to the speakers: the pill follows it, still without a pick.
        try await engineMoves(to: Self.speakers.id, listing: [Self.speakers])
        #expect(viewModel.selectedDevice?.id == Self.speakers.id)
        #expect(engine.state.withLock { $0.picks }.isEmpty, "a pick would move the pin to the fallback")
    }

    @Test("Play on the fallback is not a pick")
    func playOnFallbackIsNotAPick() async throws {
        try await engineMoves(to: Self.speakers.id, listing: [Self.speakers])
        queueOneSong()
        viewModel.startPlayback()
        try await settle()
        #expect(engine.state.withLock { $0.starts } == [0])
        #expect(engine.state.withLock { $0.picks }.isEmpty)
    }

    @Test("the chosen headphones come back under a new id while Pure plays on the fallback: playback moves")
    func pureMovesBackToReturningDevice() async throws {
        var identities: [EQOutputKey?] = []
        viewModel.onOutputIdentityChanged = { identities.append($0) }
        try await engineMoves(to: Self.speakers.id, listing: [Self.speakers])
        // Resumed on the speakers, on Pure, 1:30 in.
        queueOneSong()
        viewModel.isPlaying = true
        viewModel.playbackPosition = 90
        engine.state.withLock { $0.signalPath.path = .pure }
        // The engine's rule adopts the headphones back (same UID, new id).
        try await engineMoves(to: Self.headphonesBack.id, listing: [Self.speakers, Self.headphonesBack])
        #expect(viewModel.selectedDevice?.id == Self.headphonesBack.id)
        #expect(identities.last??.uid == Self.headphones.uid, "the per-output EQ is the headphones' again")
        #expect(engine.state.withLock { $0.starts } == [90], "restarted on the headphones at the playhead")
        #expect(engine.state.withLock { $0.picks }.isEmpty)
    }

    @Test("launch shows the device the engine starts on and picks nothing (it is not the user's choice)")
    func launchIsNotAPick() async throws {
        engine.state.withLock {
            $0.devices = [Self.speakers, Self.headphones]
            $0.engineDevice = Self.speakers.id
        }
        viewModel.isEngineReady = false
        viewModel.selectedDevice = nil
        viewModel.initializeEngine()
        try await settle()
        viewModel.disarmTransportTick()
        #expect(viewModel.isEngineReady)
        #expect(viewModel.selectedDevice?.id == Self.speakers.id)
        #expect(engine.state.withLock { $0.picks }.isEmpty, "a launch pick would pin the speakers")
    }

    @Test("a re-initialization while the chosen headphones are away picks nothing: the choice stays")
    func reinitializationIsNotAPick() async throws {
        engine.state.withLock { $0.devices = [Self.speakers, Self.headphones] }
        viewModel.selectDevice(Self.headphones) // the user's pick
        try await settle()
        try await engineMoves(to: Self.speakers.id, listing: [Self.speakers]) // lost; the rule fell back
        viewModel.retryInitialization() // the Retry banner, or the engine-not-initialized self-heal
        try await settle()
        viewModel.disarmTransportTick()
        #expect(viewModel.isEngineReady)
        #expect(viewModel.selectedDevice?.id == Self.speakers.id)
        #expect(engine.state.withLock { $0.picks } == [Self.headphones.id], "only the user's own pick")
    }

    @Test("the user's pick goes to the engine as a pick (the pin moves with it)")
    func menuPickIsAPick() async throws {
        engine.state.withLock { $0.devices = [Self.speakers, Self.headphones] }
        viewModel.selectDevice(Self.speakers)
        try await settle()
        #expect(engine.state.withLock { $0.picks } == [Self.speakers.id])
        #expect(viewModel.selectedDevice?.id == Self.speakers.id)
    }
}
