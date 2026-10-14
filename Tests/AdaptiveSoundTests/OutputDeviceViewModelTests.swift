// N92 — the view model's half of "Return to headphones" (R1), on the real `AudioViewModel`: it shows
// the device the engine plays on, moves Pure playback when the engine moves, and never picks a device
// itself — a pick is the user's, and the pin returns to it (OutputDeviceSelection).

@testable import AdaptiveSound
import EQEditKit
import Foundation
import Testing

@MainActor
@Suite("AudioViewModel — the output the engine moved to")
struct OutputDeviceViewModelTests {
    private static let headphones = AudioDeviceModel(
        id: 41, name: "Headphones", sampleRate: 48000, bufferFrameSize: 512,
        uid: "AA-BB-CC-DD-EE-FF:output", modelUID: nil, transportType: 0, type: .wireless
    )
    private static let speakers = AudioDeviceModel(
        id: 42, name: "Speakers", sampleRate: 48000, bufferFrameSize: 512,
        uid: "BuiltInSpeakerDevice", modelUID: nil, transportType: 0, type: .builtin
    )
    /// The headphones back from a reconnect: a new id, the same UID.
    private static let headphonesBack = AudioDeviceModel(
        id: 57, name: "Headphones", sampleRate: 48000, bufferFrameSize: 512,
        uid: "AA-BB-CC-DD-EE-FF:output", modelUID: nil, transportType: 0, type: .wireless
    )

    private let engine = DeviceTestEngine()
    private let viewModel: AudioViewModel

    init() throws {
        // A private, empty defaults suite: nothing here touches the app's own.
        let defaults = try #require(UserDefaults(suiteName: "OutputDeviceViewModelTests.\(UUID().uuidString)"))
        viewModel = AudioViewModel(defaults: defaults, engine: engine)
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
    private func engineMoves(to device: UInt32, listing devices: [AudioDeviceModel]) async {
        engine.state.withLock {
            $0.devices = devices
            $0.engineDevice = device
        }
        viewModel.refreshDevices()
        await settle()
    }

    /// Let the view model's tasks (refresh, start) run.
    private func settle() async {
        for _ in 0 ..< 50 {
            await Task.yield()
        }
    }

    @Test("a lost device is never replaced by a pick: the fallback is the engine's, not the user's")
    func lostDeviceIsNeverPicked() async {
        // The headphones are gone and the engine has not moved yet: no device shows, none is picked.
        await engineMoves(to: Self.headphones.id, listing: [Self.speakers])
        #expect(viewModel.selectedDevice == nil)
        // The engine falls back to the speakers: the pill follows it, still without a pick.
        await engineMoves(to: Self.speakers.id, listing: [Self.speakers])
        #expect(viewModel.selectedDevice?.id == Self.speakers.id)
        #expect(engine.state.withLock { $0.picks }.isEmpty, "a pick would move the pin to the fallback")
    }

    @Test("Play on the fallback is not a pick")
    func playOnFallbackIsNotAPick() async {
        await engineMoves(to: Self.speakers.id, listing: [Self.speakers])
        queueOneSong()
        viewModel.startPlayback()
        await settle()
        #expect(engine.state.withLock { $0.starts } == [0])
        #expect(engine.state.withLock { $0.picks }.isEmpty)
    }

    @Test("the chosen headphones come back under a new id while Pure plays on the fallback: playback moves")
    func pureMovesBackToReturningDevice() async {
        var identities: [EQOutputKey?] = []
        viewModel.onOutputIdentityChanged = { identities.append($0) }
        await engineMoves(to: Self.speakers.id, listing: [Self.speakers])
        // Resumed on the speakers, on Pure, 1:30 in.
        queueOneSong()
        viewModel.isPlaying = true
        viewModel.playbackPosition = 90
        engine.state.withLock { $0.signalPath.path = .pure }
        // The engine's rule adopts the headphones back (same UID, new id).
        await engineMoves(to: Self.headphonesBack.id, listing: [Self.speakers, Self.headphonesBack])
        #expect(viewModel.selectedDevice?.id == Self.headphonesBack.id)
        #expect(identities.last??.uid == Self.headphones.uid, "the per-output EQ is the headphones' again")
        #expect(engine.state.withLock { $0.starts } == [90], "restarted on the headphones at the playhead")
        #expect(engine.state.withLock { $0.picks }.isEmpty)
    }

    @Test("the user's pick goes to the engine as a pick (the pin moves with it)")
    func menuPickIsAPick() async {
        engine.state.withLock { $0.devices = [Self.speakers, Self.headphones] }
        viewModel.selectDevice(Self.speakers)
        await settle()
        #expect(engine.state.withLock { $0.picks } == [Self.speakers.id])
        #expect(viewModel.selectedDevice?.id == Self.speakers.id)
    }
}
