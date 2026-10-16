// R1.1-A (council C-53; VM-4, UI-4; KI-UI-01): VoiceOver hears live readings as values, at the grain
// worth saying. The scrubber's time and its accessibility value read the playhead in whole seconds,
// published only when the second changes — before R1.1 the scrubber observed the 20 Hz playhead, so
// it re-evaluated its accessibility modifiers 20 times a second for a value that changes once. The
// loudness meters' readings move from their labels (the element's NAME changed up to 20 times a
// second) into their values, quantised: LUFS to the LU, the true peak up to the whole dB.

@testable import AdaptiveSound
import Foundation
import Observation
import Testing

@MainActor
@Suite("Live readouts for VoiceOver (C-53)")
struct LiveReadoutSpeechTests {
    /// Raised by an observation's `onChange`.
    private final class Flag: @unchecked Sendable {
        var raised = false
    }

    /// Whether a view that read `model[keyPath:]` would re-render because of `change`.
    private func invalidates<Model: Observable, Value>(_ model: Model, _ keyPath: KeyPath<Model, Value>,
                                                       by change: () -> Void) -> Bool {
        let flag = Flag()
        withObservationTracking {
            _ = model[keyPath: keyPath]
        } onChange: {
            flag.raised = true
        }
        change()
        return flag.raised
    }

    @Test("the scrubber's time changes once a second while the playhead moves 20 times a second")
    func elapsedTimeIsQuantised() throws {
        let defaults = try #require(UserDefaults(suiteName: "AdaptiveSoundTests.LiveReadoutSpeech"))
        let viewModel = AudioViewModel(defaults: defaults, engine: DeviceTestEngine())
        viewModel.playbackPosition = 80
        var changes = 0
        for tick in 1 ... 20 { // one second of the transport tick: 80.05 … 81.0
            let changed = invalidates(viewModel, \.elapsedSeconds) {
                viewModel.playbackPosition = 80 + Double(tick) * 0.05
            }
            changes += changed ? 1 : 0
        }
        #expect(viewModel.elapsedSeconds == 81)
        #expect(changes == 1, "the elapsed seconds changed \(changes) times in one second of playhead")
        // What it shows: the time label's own truncation (`formatDuration`), so the text is unchanged.
        #expect(formatDuration(Double(viewModel.elapsedSeconds)) == formatDuration(viewModel.playbackPosition))
    }

    @Test("a loudness reading is said to the LU: tenths that flicker are one value")
    func loudnessIsSaidToTheLU() {
        #expect(LoudnessSpeech.lufs(-15.94, hasSignal: true) == "-16 LUFS")
        #expect(LoudnessSpeech.lufs(-16.04, hasSignal: true) == "-16 LUFS")
        #expect(LoudnessSpeech.lufs(-15.4, hasSignal: true) == "-15 LUFS")
        #expect(LoudnessSpeech.lufs(-15.9, hasSignal: false) == "no reading")
    }

    @Test("a true peak is said rounded up — never below the peak — and above the ceiling, the ceiling is named")
    func truePeakIsSaidConservatively() {
        #expect(LoudnessSpeech.truePeak(-3.2, live: true, hot: false) == "-3 dBTP")
        #expect(LoudnessSpeech.truePeak(-3.9, live: true, hot: false) == "-3 dBTP")
        #expect(LoudnessSpeech.truePeak(-0.6, live: true, hot: true) == "0 dBTP, above the −1 dBTP ceiling")
        #expect(LoudnessSpeech.truePeak(-80, live: false, hot: false) == "no reading")
    }
}
