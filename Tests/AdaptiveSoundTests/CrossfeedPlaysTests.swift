// R1.1-A (council C-42, C-30; founder decision 2026-10-14, KI-SND-05, KI-DEV-01): crossfeed plays on
// headphones as the engine's one output classifier finds them — the Mac's own headphone jack
// included, an AirPlay speaker not — and the hero shows it whenever it plays, Intensity 0 included.
// On the real `AudioViewModel` over its own defaults suite, and the real `SignalPathInfo`.

@testable import AdaptiveSound
import Foundation
import SettingsKit
import Testing

@MainActor
@Suite("Crossfeed — where it plays, and what the hero shows", .serialized)
struct CrossfeedPlaysTests {
    /// Wired headphones in the Mac's own jack: the built-in transport, classified headphones by its
    /// data source ('hdpn').
    private static let jack = AudioDeviceModel(
        id: 61, name: "External Headphones", sampleRate: 48000, bufferFrameSize: 512,
        uid: "BuiltInHeadphoneOutputDevice", modelUID: nil, transportType: 0, type: .builtin,
        isHeadphones: true
    )
    /// An AirPlay speaker: the wireless family, classified not headphones.
    private static let airPlay = AudioDeviceModel(
        id: 62, name: "Living Room", sampleRate: 48000, bufferFrameSize: 512,
        uid: "AirPlay:living-room", modelUID: nil, transportType: 0, type: .wireless, isHeadphones: false
    )

    private static let suiteName = "AdaptiveSoundTests.CrossfeedPlays"
    private let defaults: UserDefaults

    init() throws {
        defaults = try #require(UserDefaults(suiteName: Self.suiteName))
        defaults.removePersistentDomain(forName: Self.suiteName)
    }

    /// Let the view model's tasks run: a start, a device read.
    private func settle() async {
        for _ in 0 ..< 50 {
            await Task.yield()
        }
    }

    @Test("the Mac's own headphone jack plays crossfeed; an AirPlay speaker holds it off")
    func crossfeedFollowsTheClassifier() async {
        let engine = DeviceTestEngine()
        engine.state.withLock {
            $0.devices = [Self.jack, Self.airPlay]
            $0.engineDevice = Self.jack.id
        }
        let viewModel = AudioViewModel(defaults: defaults, engine: engine)
        viewModel.initializeEngine()
        await settle()
        viewModel.stopTransportTick()

        viewModel.crossfeedEnabled = true
        #expect(viewModel.crossfeedPlays, "wired headphones in the built-in jack are headphones")
        #expect(engine.state.withLock { $0.crossfeeds }.last == true)

        engine.state.withLock { $0.engineDevice = Self.airPlay.id }
        viewModel.refreshDevices()
        await settle()
        #expect(!viewModel.crossfeedPlays, "an AirPlay speaker is not headphones")
        #expect(engine.state.withLock { $0.crossfeeds }.last == false)
        #expect(viewModel.crossfeedEnabled, "the speaker holds crossfeed off; the listener's choice stays")
    }

    @Test("the hero shows crossfeed whenever it plays — Intensity 0 included — and never on Pure")
    func heroShowsAudibleCrossfeed() {
        var info = SignalPathInfo()
        info.intensityLinear = 0
        info.crossfeedStrength = .strong
        #expect(info.audibleCrossfeed == .strong, "crossfeed plays at Intensity 0, so the chip shows")
        info.intensityLinear = 0.5
        #expect(info.audibleCrossfeed == .strong)
        info.path = .pure
        #expect(info.audibleCrossfeed == nil, "Pure bypasses the DSP: no crossfeed plays")
        info.path = .enhanced
        info.crossfeedStrength = nil
        #expect(info.audibleCrossfeed == nil, "off, or not on headphones")
        #expect(!SignalPathAccessibility.value(for: info).contains("crossfeed"))
        info.crossfeedStrength = .relaxed
        #expect(SignalPathAccessibility.value(for: info).contains("crossfeed Relaxed"))
    }
}
