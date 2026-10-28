#if DEBUG
    import AudioToolbox
    import Foundation
    import LevelingKit
    import SettingsKit

    // MARK: - Every main-thread entry into the engine, timed (`make main-thread-stall`)

    /// One round = every way the main thread reaches the engine: the 20 Hz transport and spectrum
    /// ticks (the snapshot), the monitoring reads, the control-plane publishes the UI fires (EQ with
    /// Compare, a Leveling mode change, intensity, crossfeed, the output's transport through
    /// `selectedDevice`), Master Gain on both
    /// paths, the pin switch and the chosen device (handed back, read back), a scrub. Each is timed;
    /// the slowest of each is kept — printed as information; what decides the verdict is that the rounds
    /// FINISH while the engine lock is held (`rounds`), and `progress` names the entry main is inside if
    /// they do not.
    @MainActor
    final class EntryProbe {
        private let viewModel: AudioViewModel
        private let bridge: AudioEngineBridge
        private var slowest: [String: Double] = [:]
        private var names: [String] = []
        private var calls = 0
        private(set) var rounds = 0
        /// The entry main is inside, for the hang cap's message.
        let progress = StallProgress()
        private var toggle = false
        private let flatPoints = [Float](repeating: 0, count: 31)
        /// A leveled decision with nothing measured (the unknown-loudness rule): the mode-change entry's other side.
        private let unknownLoudness = TrackLevelingDecision(
            mode: .unknownCut, source: .unknownCut, continuousWithPrevious: false,
            unfolded: .init(loudness: nil, truePeak: nil), folded: nil, roles: []
        )
        private var bands = [Float](repeating: 0, count: 64)
        /// Pure's loan journal, over the view model's own (isolated) defaults.
        private var loanJournal: PureVolumeLoanJournal {
            PureVolumeLoanJournal(defaults: viewModel.defaults)
        }

        private let devices = [
            AudioDeviceModel(id: 0x7FFF_0001, name: "Stall A", sampleRate: 48000, bufferFrameSize: 512,
                             uid: "stall-a", modelUID: nil, transportType: 0, type: .wireless, isHeadphones: true),
            AudioDeviceModel(id: 0x7FFF_0002, name: "Stall B", sampleRate: 48000, bufferFrameSize: 512,
                             uid: "stall-b", modelUID: nil, transportType: 0, type: .builtin, isHeadphones: false),
        ]

        init(viewModel: AudioViewModel, bridge: AudioEngineBridge) {
            self.viewModel = viewModel
            self.bridge = bridge
        }

        /// Every entry once; `rounds` counts the ones that FINISHED.
        func round() {
            toggle.toggle()
            let flip = toggle
            ticks()
            measure("monitoring reads") {
                for channel in 0 ..< bridge.monitorChannelCount {
                    _ = bridge.readMonitorBands(.before, channel: channel, into: &bands)
                    _ = bridge.readMonitorBands(.after, channel: channel, into: &bands)
                }
            }
            measure("vm.publishEQ") { viewModel.publishEQ(points: flatPoints, isOn: flip, comparing: !flip) }
            measure("engine.applyLevelingChange") {
                bridge.applyLevelingChange(current: flip ? .off : unknownLoudness, next: flip ? nil : .off)
            }
            measure("vm.intensity didSet") { viewModel.intensity = flip ? 0.3 : 0.2 }
            measure("vm.crossfeedEnabled didSet") { viewModel.crossfeedEnabled = flip }
            measure("vm.selectedDevice didSet (EQ identity, transport)") {
                viewModel.selectedDevice = devices[flip ? 0 : 1]
            }
            measure("vm.setMasterGain (Enhanced)") { viewModel.setMasterGain(position: flip ? 0.5 : 0.6) }
            measure("engine.keepPureVolumeLoans") { bridge.keepPureVolumeLoans(in: loanJournal) }
            measure("vm.pinPlaybackToSelectedDevice didSet") { viewModel.pinPlaybackToSelectedDevice = flip }
            measure("engine.restoreChosenOutput") { bridge.restoreChosenOutput(uid: flip ? devices[0].uid : nil) }
            measure("engine.chosenOutputUID") { _ = bridge.chosenOutputUID() }
            measure("vm.seek(to:) [main-thread part]") { viewModel.seek(to: 1) }
            measure("engine.publishChannelLayout") { bridge.publishChannelLayout(kAudioChannelLayoutTag_Stereo) }
            rounds += 1
        }

        /// The 20 Hz ticks only (the device-loss run, which must also see them pause).
        func tickOnly() {
            ticks()
            rounds += 1
        }

        private func ticks() {
            measure("bridge.snapshot()") { _ = bridge.snapshot() }
            measure("vm.tickTransport()") { viewModel.tickTransport() }
            measure("vm.spectrum.lens(at:)") {
                _ = viewModel.spectrum.lens(at: .now, isPlaying: true, isPure: false, reduceMotion: false)
            }
            measure("bridge.readSpectrumBands") { _ = bridge.readSpectrumBands(into: &bands) }
        }

        func printTable(title: String) {
            print("\n=== main-thread-stall latency, \(title) ===")
            for name in names {
                let padded = name.padding(toLength: 52, withPad: " ", startingAt: 0)
                print(padded + String(format: "max %8.3f ms", slowest[name] ?? 0))
            }
            print("calls: \(calls), rounds: \(rounds) (timings are information; no threshold decides)")
        }

        private func measure(_ name: String, _ body: () -> Void) {
            progress.enter(name)
            let elapsed = MainThreadStallSelfTest.milliseconds(body)
            progress.leave()
            if slowest[name] == nil {
                names.append(name)
            }
            slowest[name] = max(slowest[name] ?? 0, elapsed)
            calls += 1
        }
    }
#endif
