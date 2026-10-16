// R1.1-A, founder decision FD-2 (council C-41, C-102, C-12, C-29, DEV-1): a fresh launch plays the music
// as it was recorded, and the listener's settings come back as they were left — Master Gain never louder —
// on the real `AudioViewModel`, launched and relaunched over one defaults suite of its own (never the
// app's). A relaunch is a second view model over the same defaults, as the app builds one at launch.

@testable import AdaptiveSound
import EQEditKit
import Foundation
import LibraryScan
import Testing

@MainActor
@Suite("AudioViewModel — a faithful default, and the listener's settings kept", .serialized)
struct ListeningSettingsTests {
    private static let headphones = AudioDeviceModel(
        id: 41, name: "Headphones", sampleRate: 48000, bufferFrameSize: 512,
        uid: "AA-BB-CC-DD-EE-FF:output", modelUID: nil, transportType: 0, type: .wireless, isHeadphones: true
    )
    private static let speakers = AudioDeviceModel(
        id: 42, name: "Speakers", sampleRate: 48000, bufferFrameSize: 512,
        uid: "BuiltInSpeakerDevice", modelUID: nil, transportType: 0, type: .builtin, isHeadphones: false
    )

    /// Where the listener's settings are kept (`SettingsStore`): a versioned key, so a later format
    /// gets a key of its own and this one stays readable.
    private static let settingsKey = "listeningSettingsV1"
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

    /// One song in the queue, selected.
    private func queueOneSong(_ viewModel: AudioViewModel) {
        let url = URL(fileURLWithPath: "/nonexistent/song.flac") // never opened: the engine records it
        let song = AudioFile(name: "Song", relativePath: "", absoluteURL: url, format: "FLAC", durationSeconds: 240)
        viewModel.queue = [QueueItem(file: song)]
        viewModel.selectedTrackIndex = 0
    }

    /// The listener's settings as a stored blob, written by hand (a damaged or foreign value).
    private func store(_ json: String) {
        defaults.set(Data(json.utf8), forKey: Self.settingsKey)
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

    // MARK: - Remembered settings (C-102, C-12)

    @Test("Pure, Master Gain, crossfeed and its strength, shuffle, repeat and the pin come back after a relaunch")
    func settingsRoundTrip() async {
        let first = launch()
        first.pureModeEnabled = true
        first.masterGain = -12
        first.crossfeedEnabled = true
        first.crossfeedStrength = .strong
        first.shuffleEnabled = true
        first.repeatMode = 2
        first.pinPlaybackToSelectedDevice = false
        await settle()

        let relaunched = launch()
        #expect(relaunched.pureModeEnabled)
        #expect(relaunched.masterGain == -12)
        #expect(relaunched.crossfeedEnabled)
        #expect(relaunched.crossfeedStrength == .strong)
        #expect(relaunched.shuffleEnabled)
        #expect(relaunched.repeatMode == 2)
        #expect(!relaunched.pinPlaybackToSelectedDevice)
        #expect(relaunched.intensity == 0, "Intensity is hidden and held at 0: never restored")
    }

    @Test("crossfeed is kept as the listener chose it, not as the output allowed it (C-12)")
    func crossfeedIntentSurvivesSpeakers() async {
        let (viewModel, engine) = await launchReady(on: Self.headphones, devices: [Self.headphones, Self.speakers])
        viewModel.crossfeedEnabled = true
        // The output moves to the speakers: crossfeed can't play there.
        engine.state.withLock { $0.engineDevice = Self.speakers.id }
        viewModel.refreshDevices()
        await settle()
        #expect(engine.state.withLock { $0.crossfeeds }.last == false, "crossfeed doesn't play on the speakers")
        #expect(viewModel.crossfeedEnabled, "the speakers hold crossfeed off, not the listener's choice")

        let relaunched = launch()
        #expect(relaunched.crossfeedEnabled, "it comes back on with the headphones")
    }

    @Test("R1's shuffle and repeat come back at launch, with or without a queue to restore")
    func shuffleAndRepeatFromR1() {
        // R1 kept them beside the queue cursor, and read them only when a queue was restored.
        defaults.set(true, forKey: "queue.cursor.shuffle")
        defaults.set(1, forKey: "queue.cursor.repeatMode")
        let viewModel = launch()
        #expect(viewModel.shuffleEnabled)
        #expect(viewModel.repeatMode == 1)
    }

    // MARK: - Master Gain is never restored louder than it was left (C-102)

    @Test("Master Gain comes back where it was left — a turn-down, or Silent")
    func masterGainComesBackAsLeft() async {
        launch().masterGain = -20
        await settle()
        #expect(launch().masterGain == -20)

        launch().setMasterGain(position: 0) // the bottom stop: Silent
        await settle()
        #expect(launch().masterGain == -.infinity)
    }

    @Test("a stored level that can't be what was left comes back Silent, never louder")
    func masterGainNeverLouder() {
        // Above unity: the law is turn-down only, so this was never left.
        store(#"{"version":1,"masterGainDecibels":6}"#)
        #expect(launch().masterGain == -.infinity)
        // Not a level at all.
        store(#"{"version":1,"masterGainDecibels":"loud"}"#)
        #expect(launch().masterGain == -.infinity)
        store(#"{"version":1,"masterGainDecibels":"NaN"}"#)
        #expect(launch().masterGain == -.infinity)
        // The whole value unreadable: whatever level was left is unknown.
        defaults.set(Data("not settings".utf8), forKey: Self.settingsKey)
        #expect(launch().masterGain == -.infinity)
        // Never stored (an R1 user's first launch): unity, as R1 played.
        defaults.removeObject(forKey: Self.settingsKey)
        #expect(launch().masterGain == MasterGainLaw.unity)
    }

    // MARK: - Master Gain on Pure is the device's own volume (C-29; founder 2026-10-15)

    @Test("turned down, the view model still asks for Pure: the engine turns the device down, or waits")
    func pureIsAskedForAtAnyLevel() async {
        let engine = DeviceTestEngine()
        let viewModel = launch(engine)
        viewModel.isEngineReady = true
        queueOneSong(viewModel)
        viewModel.masterGain = -20
        viewModel.pureModeEnabled = true
        viewModel.startPlayback()
        await settle()
        // The engine knows the device: it lowers its volume by Master Gain (MasterGainOnPure), or — on a
        // device with no volume the app can set — waits, and says so (PureModeReason.waitsForMasterGain).
        #expect(engine.state.withLock { $0.pureModes } == [true])
        #expect(engine.state.withLock { $0.masterGains.last } == -20, "the engine has the level to turn down by")
    }

    @Test("on Pure the slider is still Master Gain; on a device with no volume the app can set, it stays at 0 dB")
    func sliderOnPure() {
        let viewModel = launch()
        viewModel.masterGain = -12
        viewModel.signalPath.path = .pure
        viewModel.signalPath.deviceVolume = .decibels(-32)
        #expect(viewModel.masterGainControl == .pureDevice(decibels: -12))
        viewModel.setMasterGain(position: MasterGainLaw.position(decibels: -6))
        #expect(abs(viewModel.masterGain - -6) < 0.01, "the engine moves the device from the level it found")
        viewModel.masterGain = MasterGainLaw.unity
        viewModel.signalPath.deviceVolume = .fixed
        #expect(viewModel.masterGainControl == .deviceFixed)
        #expect(!viewModel.masterGainControl.isAdjustable)
    }

    @Test("the device-volume loans the engine holds are kept, and handed back to the engine at the next launch")
    func loansKeptAcrossALaunch() async {
        let loan = PureVolumeLoan(deviceUID: "AppleUSBAudioEngine:DAC:1", ceiling: -20, anchor: -20, lastSet: -32)
        let (viewModel, _) = await launchReady(on: Self.speakers, devices: [Self.speakers])
        viewModel.rememberPureVolumeLoans([loan]) // as the tick reads them from the snapshot
        await settle()
        // The app died while Pure had the DAC turned down: the next launch hands the loan back.
        let (_, relaunchedEngine) = await launchReady(on: Self.speakers, devices: [Self.speakers])
        #expect(relaunchedEngine.state.withLock { $0.returnedLoans } == [[loan]])
    }

    // MARK: - The chosen output device (DEV-1)

    @Test("the device the user chose comes back after a relaunch; the device the app launches on is not a choice")
    func chosenDeviceKept() async {
        // Launched on the speakers: nothing chosen, so nothing comes back.
        let devices = [Self.speakers, Self.headphones]
        _ = await launchReady(on: Self.speakers, devices: devices)
        let (second, secondEngine) = await launchReady(on: Self.speakers, devices: devices)
        #expect(secondEngine.state.withLock { $0.restoredChoices } == [nil], "the launch device was not chosen")

        // The user picks the headphones; the next launch gets them back as the choice, not as a pick.
        second.selectDevice(Self.headphones)
        await settle()
        let (_, thirdEngine) = await launchReady(on: Self.speakers, devices: devices)
        #expect(thirdEngine.state.withLock { $0.restoredChoices } == [Self.headphones.uid])
        #expect(thirdEngine.state.withLock { $0.picks }.isEmpty, "a restored choice is not a pick")
    }

    @Test("turning \"Keep playback on this device\" on chooses the device in use, and that choice is kept")
    func pinOnChoiceKept() async {
        let devices = [Self.speakers, Self.headphones]
        let (viewModel, _) = await launchReady(on: Self.headphones, devices: devices)
        viewModel.pinPlaybackToSelectedDevice = false
        viewModel.pinPlaybackToSelectedDevice = true // "this device": the headphones
        await settle()
        let (_, relaunchedEngine) = await launchReady(on: Self.speakers, devices: devices)
        #expect(relaunchedEngine.state.withLock { $0.restoredChoices } == [Self.headphones.uid])
    }

    // MARK: - A damaged value falls back to the faithful default

    @Test("FFmpeg is off on a new install; turned on, it is kept and opens the process's switch (FD-3)")
    func ffmpegOptIn() async {
        defer { FFmpegOptIn.isOn = false }
        let fresh = launch()
        #expect(!fresh.useFFmpeg)
        #expect(!FFmpegOptIn.isOn, "a new install never loads FFmpeg")

        fresh.useFFmpeg = true
        #expect(FFmpegOptIn.isOn)
        await settle()
        FFmpegOptIn.isOn = false // a new process starts with the switch off
        let relaunched = launch()
        #expect(relaunched.useFFmpeg)
        #expect(FFmpegOptIn.isOn, "the switch is set from the kept setting at launch, before any library work")

        relaunched.useFFmpeg = false
        #expect(!FFmpegOptIn.isOn)
    }

    @Test("a stored value that can't be read is the faithful default (Master Gain: Silent)")
    func corruptValuesFallBack() {
        store(#"{"version":1,"pureMode":"yes","crossfeed":2,"crossfeedPreset":42,"shuffle":"on","#
            + #""repeatMode":9,"keepPlaybackOnDevice":"maybe","chosenOutputUID":"","masterGainDecibels":[]}"#)
        let viewModel = launch()
        #expect(!viewModel.pureModeEnabled)
        #expect(!viewModel.crossfeedEnabled)
        #expect(viewModel.crossfeedStrength == .defaultStrength)
        #expect(!viewModel.shuffleEnabled)
        #expect(viewModel.repeatMode == 0)
        #expect(viewModel.pinPlaybackToSelectedDevice)
        #expect(viewModel.intensity == 0)
        #expect(viewModel.masterGain == -.infinity, "never louder than it was left: an unreadable level is Silent")
    }
}
