#if DEBUG
    import AppKit
    @preconcurrency import AVFoundation
    import Foundation
    import PlaybackQueueKit

    // MARK: - `make main-thread-stall` (S10.8 G, the disconnect freeze)

    /// `AdaptiveSound -ASMainThreadStall <mode>`: hold AVFAudio's engine-wide lock for seconds — as
    /// macOS held a dying device's — and prove the main thread never waits on it. Runs the REAL
    /// bridge and view model on an offline engine (`StallRig`: no device opened, nothing heard), times
    /// every main-thread entry while the lock is held, and exits 0 only if every call returned
    /// within `bound`, at most 1% took over `target` (an NSLog write or a scheduler hiccup can; a
    /// wait on the engine would make them all slow), and the main queue never waited past
    /// `queueBound`. A control read of the old kind (a live `isPlaying` / `isRunning` on main) must
    /// still wait, proving the lock really was held.
    ///
    /// Modes: `stop` (`player.stop()` holds the lock on `configChangeQueue`, the re-establish case),
    /// `start` (a slow `engine.start()` on `engineQueue`), `device-loss` (the founder's repro: the
    /// output rule pauses while the lock is held), `ended-advance` (a queue advance whose start is
    /// slow must not be stopped by the replaced track's end flag — review MAJOR-1).
    ///
    /// Like the picture sheets it runs before the single-instance lock: no library store, no app
    /// setting (a private defaults suite), no audio device.
    @MainActor
    enum MainThreadStallSelfTest {
        static let target = 5.0 // ms, what a main-thread entry takes
        static let bound = 25.0 // ms, what no main-thread entry may take (the freeze took 3–7 s)
        static let queueBound = 25.0 // ms, the main queue's longest wait
        static let holdSeconds = 2.5

        static func runIfRequested() {
            let arguments = ProcessInfo.processInfo.arguments
            guard let flag = arguments.firstIndex(of: "-ASMainThreadStall") else { return }
            NSApplication.shared.setActivationPolicy(.prohibited) // no Dock icon, never frontmost
            let mode = arguments.indices.contains(flag + 1) ? arguments[flag + 1] : "stop"
            let passed: Bool
            switch mode {
            case "stop", "start": passed = holdRun(mode: mode)
            case "device-loss": passed = deviceLossRun()
            case "ended-advance": passed = endedAdvanceRun()
            default:
                print("main-thread-stall: unknown mode '\(mode)' (stop | start | device-loss | ended-advance)")
                exit(2)
            }
            print("main-thread-stall \(mode): \(passed ? "PASS" : "FAIL")")
            exit(passed ? 0 : 1)
        }

        // MARK: - Hold modes

        private static func holdRun(mode: String) -> Bool {
            let rig = StallRig()
            guard rig.buildGraph(slowUnit: mode == "start") else { return report("the graph did not build") }
            if mode == "stop" {
                rig.startPlaying()
            } else {
                rig.bridge.engineQueue.async { rig.bridge.startTransportClock() }
            }
            pump(0.5)
            let viewModel = makeViewModel(rig.bridge, tracks: 1)
            viewModel.isPlaying = true
            let probe = EntryProbe(viewModel: viewModel, bridge: rig.bridge)
            let watchdog = StallWatchdog()
            watchdog.start()
            if mode == "stop" {
                rig.holdInStop(on: rig.bridge.configChangeQueue, seconds: holdSeconds)
            } else {
                rig.holdInStart(seconds: holdSeconds)
            }
            pump(0.15) // let the holder get inside the lock
            watchdog.reset()
            let window = ContinuousClock.now
            while ContinuousClock.now - window < .seconds(holdSeconds - 0.8) {
                probe.round()
                pump(0.004)
            }
            let queueWait = watchdog.worstMilliseconds
            // CONTROL, after the probes: a live AVFAudio read on main still waits (the lock was held).
            let control = milliseconds {
                if mode == "stop" {
                    _ = rig.bridge.playerNodeRef?.isPlaying
                } else {
                    _ = rig.bridge.avEngineRef?.isRunning
                }
            }
            watchdog.stop()
            rig.stopRendering()
            probe.printTable(title: "mode=\(mode) hold=\(holdSeconds)s")
            print("main-queue longest wait".padding(toLength: 52, withPad: " ", startingAt: 0)
                + String(format: "    %8.3f ms", queueWait))
            print("CONTROL live AVFAudio read on main".padding(toLength: 52, withPad: " ", startingAt: 0)
                + String(format: "    %8.1f ms", control))
            guard entriesPassed(probe) else { return false }
            guard queueWait < queueBound else { return report("the main queue waited \(queueWait) ms") }
            guard control >= 300 else { return report("the control did not wait: the lock was not held") }
            return true
        }

        private static func entriesPassed(_ probe: EntryProbe) -> Bool {
            guard probe.worst < bound else { return report("a main-thread entry took \(probe.worst) ms") }
            guard probe.shareOverTarget <= 0.01 else {
                return report("\(Int(probe.shareOverTarget * 100))% of the calls took over \(target) ms")
            }
            return true
        }

        // MARK: - The founder's repro

        private static func deviceLossRun() -> Bool {
            let rig = StallRig()
            guard rig.buildGraph(slowUnit: false) else { return report("the graph did not build") }
            rig.startPlaying()
            let bridge = rig.bridge
            let ready = DispatchSemaphore(value: 0)
            bridge.engineQueue.async {
                bridge.setCurrentDeviceID(0x7FFF_FFF0) // the app's device: gone
                bridge.setPinPlaybackToSelectedDevice(false) // any adoption stays in the app
                bridge.registerOutputDeviceListeners()
                ready.signal()
            }
            ready.wait()
            let viewModel = makeViewModel(bridge, tracks: 1)
            viewModel.selectedTrackIndex = 0
            viewModel.isPlaying = true
            viewModel.duration = 20
            for _ in 0 ..< 8 {
                viewModel.tickTransport()
                pump(0.05)
            }
            let placeBefore = viewModel.playbackPosition
            rig.holdInStop(on: DispatchQueue(label: "avfaudio-internal-stand-in"), seconds: holdSeconds)
            pump(0.05)
            let lossAt = ContinuousClock.now
            bridge.outputDeviceDidChange(.engineReconfigured)
            bridge.outputDeviceDidChange(.targetAliveChanged)
            let probe = EntryProbe(viewModel: viewModel, bridge: bridge)
            var pausedAfter: Duration?
            while ContinuousClock.now - lossAt < .seconds(holdSeconds) {
                probe.tickOnly()
                if pausedAfter == nil, !viewModel.isPlaying {
                    pausedAfter = ContinuousClock.now - lossAt
                }
                pump(0.01)
            }
            rig.stopRendering()
            probe.printTable(title: "mode=device-loss hold=\(holdSeconds)s")
            let place = viewModel.pausedResumePosition ?? -1
            print("paused after \(pausedAfter.map { "\($0)" } ?? "NEVER"); place \(placeBefore) → \(place)")
            guard let pausedAfter, pausedAfter < .milliseconds(500) else { return report("no pause within 500 ms") }
            guard abs(place - placeBefore) < 0.25 else { return report("the place was not kept") }
            return entriesPassed(probe)
        }

        // MARK: - Review MAJOR-1

        private static func endedAdvanceRun() -> Bool {
            let rig = StallRig()
            guard rig.buildGraph(slowUnit: false) else { return report("the graph did not build") }
            rig.startPlaying()
            pump(0.3)
            let bridge = rig.bridge
            bridge.setCurrentDeviceID(getDefaultOutputDeviceID())
            bridge.setPinPlaybackToSelectedDevice(false) // a start never re-asserts the system default
            guard let files = writeTracks(["A", "B", "C"]) else { return report("no test files") }
            defer { files.forEach { try? FileManager.default.removeItem(at: $0) } }
            let viewModel = makeViewModel(bridge, urls: files)
            viewModel.selectedTrackIndex = 0
            viewModel.pendingNextIndex = 1
            viewModel.isPlaying = true
            bridge.gaplessPlaybackEnded = true // A ended; B queued but not armed (Pure cross-rate)
            pump(0.1) // the clock publishes the end flag
            bridge.engineQueue.async { Thread.sleep(forTimeInterval: 0.3) } // B's start is slow
            for _ in 0 ..< 12 {
                viewModel.tickTransport()
                pump(0.05)
            }
            pump(0.5)
            rig.stopRendering()
            print("after the advance: playing \(viewModel.isPlaying), selected \(viewModel.selectedTrackIndex ?? -1)")
            guard viewModel.isPlaying, viewModel.selectedTrackIndex == 1 else {
                return report("the advance was stopped by the replaced track's end flag")
            }
            return true
        }

        // MARK: - Helpers

        private static func makeViewModel(_ bridge: AudioEngineBridge, tracks: Int) -> AudioViewModel {
            let urls = (0 ..< tracks).map { URL(fileURLWithPath: "/nonexistent/stall/track\($0).caf") }
            return makeViewModel(bridge, urls: urls)
        }

        private static func makeViewModel(_ bridge: AudioEngineBridge, urls: [URL]) -> AudioViewModel {
            let suite = "AdaptiveSound.MainThreadStall"
            guard let defaults = UserDefaults(suiteName: suite) else {
                print("main-thread-stall FAIL: no defaults suite")
                exit(2)
            }
            defaults.removePersistentDomain(forName: suite)
            let viewModel = AudioViewModel(defaults: defaults, engine: bridge)
            viewModel.isEngineReady = true
            viewModel.queue = urls.map { url in
                QueueItem(file: AudioFile(name: url.lastPathComponent, relativePath: "", absoluteURL: url,
                                          format: "CAF", durationSeconds: 2))
            }
            return viewModel
        }

        private static func writeTracks(_ names: [String]) -> [URL]? {
            let folder = FileManager.default.temporaryDirectory
                .appendingPathComponent("AdaptiveSound-stall-\(UUID().uuidString)")
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            guard let format = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2) else { return nil }
            return names.compactMap { name -> URL? in
                let url = folder.appendingPathComponent("\(name).caf")
                guard let file = try? AVAudioFile(forWriting: url, settings: format.settings),
                      let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 96000) else { return nil }
                buffer.frameLength = 96000
                try? file.write(from: buffer)
                return url
            }
        }

        static func pump(_ seconds: Double) {
            RunLoop.main.run(until: Date(timeIntervalSinceNow: seconds))
        }

        static func milliseconds(_ body: () -> Void) -> Double {
            let elapsed = ContinuousClock().measure(body)
            return Double(elapsed.components.seconds) * 1000 + Double(elapsed.components.attoseconds) * 1e-15
        }

        private static func report(_ failure: String) -> Bool {
            print("main-thread-stall FAIL: \(failure)")
            return false
        }
    }
#endif
