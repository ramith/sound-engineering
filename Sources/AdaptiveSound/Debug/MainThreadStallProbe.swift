#if DEBUG
    import AudioToolbox
    import Foundation

    // MARK: - Every main-thread entry into the engine, timed (`make main-thread-stall`)

    /// One round = every way the main thread reaches the engine: the 20 Hz transport and spectrum
    /// ticks (the snapshot), the monitoring reads, the control-plane publishes the UI fires (EQ,
    /// intensity, crossfeed, the output's transport through `selectedDevice`), Master Gain on both
    /// paths, the pin switch and the chosen device (handed back, read back), a scrub. Each is timed;
    /// the slowest of each is kept.
    @MainActor
    final class EntryProbe {
        private let viewModel: AudioViewModel
        private let bridge: AudioEngineBridge
        private var slowest: [String: Double] = [:]
        private var names: [String] = []
        private var calls = 0
        private var overTarget = 0
        private var toggle = false
        private let flatPoints = [Float](repeating: 0, count: 31)
        private var bands = [Float](repeating: 0, count: 64)
        private let devices = [
            AudioDeviceModel(id: 0x7FFF_0001, name: "Stall A", sampleRate: 48000, bufferFrameSize: 512,
                             uid: "stall-a", modelUID: nil, transportType: 0, type: .wireless),
            AudioDeviceModel(id: 0x7FFF_0002, name: "Stall B", sampleRate: 48000, bufferFrameSize: 512,
                             uid: "stall-b", modelUID: nil, transportType: 0, type: .builtin),
        ]

        init(viewModel: AudioViewModel, bridge: AudioEngineBridge) {
            self.viewModel = viewModel
            self.bridge = bridge
        }

        /// The slowest entry, in ms.
        var worst: Double {
            slowest.values.max() ?? 0
        }

        /// The share of calls over `MainThreadStallSelfTest.target` (5 ms): the odd one is an NSLog
        /// write or a scheduler hiccup; a wait on the engine would make them all slow.
        var shareOverTarget: Double {
            calls > 0 ? Double(overTarget) / Double(calls) : 0
        }

        /// Every entry once.
        func round() {
            toggle.toggle()
            let flip = toggle
            tickOnly()
            measure("monitoring reads") {
                for channel in 0 ..< bridge.monitorChannelCount {
                    _ = bridge.readMonitorBands(.before, channel: channel, into: &bands)
                    _ = bridge.readMonitorBands(.after, channel: channel, into: &bands)
                }
            }
            measure("vm.publishEQ") { viewModel.publishEQ(points: flatPoints, isOn: flip) }
            measure("vm.intensity didSet") { viewModel.intensity = flip ? 0.3 : 0.2 }
            measure("vm.crossfeedEnabled didSet") { viewModel.crossfeedEnabled = flip }
            measure("vm.selectedDevice didSet (EQ identity, transport)") {
                viewModel.selectedDevice = devices[flip ? 0 : 1]
            }
            measure("vm.setMasterGain (Enhanced)") { viewModel.setMasterGain(position: flip ? 0.5 : 0.6) }
            measure("engine.requestDeviceVolume (Pure)") { bridge.requestDeviceVolume(decibels: -10) }
            measure("vm.pinPlaybackToSelectedDevice didSet") { viewModel.pinPlaybackToSelectedDevice = flip }
            measure("engine.restoreChosenOutput") { bridge.restoreChosenOutput(uid: flip ? devices[0].uid : nil) }
            measure("engine.chosenOutputUID") { _ = bridge.chosenOutputUID() }
            measure("vm.seek(to:) [main-thread part]") { viewModel.seek(to: 1) }
            measure("engine.publishChannelLayout") { bridge.publishChannelLayout(kAudioChannelLayoutTag_Stereo) }
        }

        /// The 20 Hz ticks only (the device-loss run, which must also see them pause).
        func tickOnly() {
            measure("bridge.snapshot()") { _ = bridge.snapshot() }
            measure("vm.tickTransport()") { viewModel.tickTransport() }
            measure("vm.tickSpectrum()") { viewModel.tickSpectrum() }
            measure("bridge.readSpectrumBands") { _ = bridge.readSpectrumBands(into: &bands) }
        }

        func printTable(title: String) {
            print("\n=== main-thread-stall latency, \(title) ===")
            for name in names {
                let padded = name.padding(toLength: 52, withPad: " ", startingAt: 0)
                print(padded + String(format: "max %8.3f ms", slowest[name] ?? 0))
            }
            print("calls: \(calls), over 5 ms: \(overTarget)")
        }

        private func measure(_ name: String, _ body: () -> Void) {
            let elapsed = MainThreadStallSelfTest.milliseconds(body)
            if slowest[name] == nil {
                names.append(name)
            }
            slowest[name] = max(slowest[name] ?? 0, elapsed)
            calls += 1
            if elapsed > MainThreadStallSelfTest.target {
                overTarget += 1
            }
        }
    }
#endif
