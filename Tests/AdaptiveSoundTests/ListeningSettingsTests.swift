// R1.1-A, founder decision FD-2 (council C-41, C-102, C-12, C-29, DEV-1): a fresh launch plays the music
// as it was recorded, and the listener's settings come back as they were left — Master Gain never louder —
// on the real `AudioViewModel`, launched and relaunched over one defaults suite of its own (never the
// app's). A relaunch is a second view model over the same defaults, as the app builds one at launch.

@testable import AdaptiveSound
import EQEditKit
import Foundation
import Testing

@MainActor
@Suite("AudioViewModel — a faithful default, and the listener's settings kept", .serialized)
struct ListeningSettingsTests {
    private static let speakers = AudioDeviceModel(
        id: 42, name: "Speakers", sampleRate: 48000, bufferFrameSize: 512,
        uid: "BuiltInSpeakerDevice", modelUID: nil, transportType: 0, type: .builtin
    )

    /// This suite's defaults, emptied before each test (the suite runs its tests one at a time).
    private static let suiteName = "AdaptiveSoundTests.ListeningSettings"

    private let defaults: UserDefaults

    init() throws {
        defaults = try #require(UserDefaults(suiteName: Self.suiteName))
        defaults.removePersistentDomain(forName: Self.suiteName)
    }

    /// A launch: the view model the app builds, over this suite's defaults.
    private func launch(_ engine: DeviceTestEngine = DeviceTestEngine()) -> AudioViewModel {
        AudioViewModel(defaults: defaults, engine: engine)
    }

    /// A launch that brings the engine up on `device`, with `devices` connected.
    private func launchReady(on device: AudioDeviceModel, devices: [AudioDeviceModel]) async
        -> (AudioViewModel, DeviceTestEngine) {
        let engine = DeviceTestEngine()
        engine.state.withLock {
            $0.devices = devices
            $0.engineDevice = device.id
        }
        let viewModel = launch(engine)
        viewModel.initializeEngine()
        await settle()
        viewModel.stopSpectrumTimer()
        return (viewModel, engine)
    }

    /// Let the view model's tasks run: a start, a device read, the settings' write at the end of a turn.
    private func settle() async {
        for _ in 0 ..< 50 {
            await Task.yield()
        }
    }

    // MARK: - A faithful default (C-41)

    @Test("a fresh launch plays as recorded: Intensity 0 (so no leveller, blend or limiter), the EQ off")
    func freshLaunchIsFaithful() async {
        let (viewModel, engine) = await launchReady(on: Self.speakers, devices: [Self.speakers])
        // Intensity 0 is the kernel's P0 / P1 path: no normaliser (leveling), no blend, and with the EQ
        // off no limiter either — the bit-exact anchor (DspBypassTests in the C++ gate).
        #expect(viewModel.intensity == 0)
        #expect(engine.state.withLock { $0.intensities } == [0], "the engine plays Intensity 0 from the first block")
        #expect(viewModel.masterGain == MasterGainLaw.unity)
        #expect(!viewModel.pureModeEnabled)
        #expect(!viewModel.crossfeedEnabled)
        #expect(!viewModel.shuffleEnabled && viewModel.repeatMode == 0)
        #expect(viewModel.pinPlaybackToSelectedDevice)
        // A new install's EQ: Flat, and Off.
        let eq = EQViewModel.loadStore(from: defaults, myPresets: [:])[slot: nil]
        #expect(eq.preset == .builtIn(.flat))
        #expect(!eq.isOn, "a fresh install's EQ is off")
    }
}
