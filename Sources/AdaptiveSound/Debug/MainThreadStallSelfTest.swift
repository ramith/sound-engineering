#if DEBUG
    import AppKit
    import AudioDSP
    @preconcurrency import AVFoundation
    import Foundation
    import OutputDeviceKit
    import Synchronization

    // MARK: - `make main-thread-stall` (S10.8 G, the disconnect freeze)

    /// `AdaptiveSound -ASMainThreadStall <mode>`: hold AVFAudio's engine-wide lock — as macOS held a
    /// dying device's — and prove the main thread never waits on it. Runs the REAL bridge and view
    /// model on an offline engine (`StallRig`: no device opened, nothing heard).
    ///
    /// Judged by BEHAVIOUR, not a stopwatch. The rig holds the lock until THIS test releases it; the
    /// run passes only if, while the lock is held, main keeps finishing its work: `minRounds` probe
    /// rounds (every way the main thread reaches the engine) complete and `minRoundTrips` main-queue
    /// probes come back. A main thread that touches the lock cannot finish until the release, and the
    /// hang cap fails the run naming what main was inside. A control read of the old kind (a live
    /// `isPlaying` / `isRunning`) runs on a background thread and must still be waiting when main is
    /// done — proof that the lock really was held. Timings are printed as information; no millisecond
    /// threshold decides.
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
        /// Probe rounds main must finish, and main-queue round trips it must serve, with the lock held.
        static let minRounds = 20
        static let minRoundTrips = 10

        /// What one held phase does: the control read, what happens once the holder is inside, one
        /// step of main's work, and the extra state the phase waits for.
        private struct HoldPlan {
            let label: String
            let control: @Sendable () -> Void
            let trigger: () -> Void
            let step: () -> Void
            let finished: () -> Bool
        }

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
            let bridge = rig.bridge
            if mode == "stop" {
                rig.startPlaying()
                waitFor("the transport clock to publish a playhead") { bridge.snapshot().transport.position != nil }
            } else {
                rig.onEngineQueue("the transport clock to start") { bridge.startTransportClock() }
            }
            let viewModel = makeViewModel(bridge, tracks: 1)
            viewModel.isPlaying = true
            let probe = EntryProbe(viewModel: viewModel, bridge: bridge)
            let watchdog = StallWatchdog()
            watchdog.start()
            if mode == "stop" {
                rig.holdInStop(on: bridge.configChangeQueue)
            } else {
                rig.holdInStart()
            }
            let plan = HoldPlan(label: "mode=\(mode)",
                                control: { liveRead(bridge, player: mode == "stop") }, trigger: {},
                                step: { probe.round() }, finished: { true })
            let held = holdWindow(plan, probe: probe, watchdog: watchdog)
            rig.stopRendering()
            return held
        }

        /// The old kind of read, which waits on the engine lock: the player's `isPlaying`, or the engine's
        /// `isRunning`. Only ever called off the main thread.
        private nonisolated static func liveRead(_ bridge: AudioEngineBridge, player: Bool) {
            if player {
                _ = bridge.playerNodeRef?.isPlaying
            } else {
                _ = bridge.avEngineRef?.isRunning
            }
        }

        /// The one held phase: wait for the holder to be INSIDE the lock, start the control read, let main
        /// work until it has finished enough (the hang cap breaks a main that cannot), check the control is
        /// still waiting, then release — and wait for the control read to finish, which only the release
        /// allows.
        private static func holdWindow(_ plan: HoldPlan, probe: EntryProbe, watchdog: StallWatchdog) -> Bool {
            waitFor("the holder to be inside the engine lock") { StallHold.shared.isInside }
            let control = StallControlRead()
            control.start(plan.control)
            let cap = StallHangCap()
            cap.begin("main finishing \(minRounds) probe rounds and \(minRoundTrips) main-queue round trips",
                      progress: probe.progress)
            probe.progress.enter("the \(plan.label) trigger")
            plan.trigger()
            probe.progress.leave()
            repeat {
                plan.step()
                pump(0.004)
            } while probe.rounds < minRounds || watchdog.roundTrips < minRoundTrips || !plan.finished()
            let queueWait = watchdog.worstMilliseconds
            let stillHeld = control.isWaiting // read while the hold lasts
            let roundTrips = watchdog.roundTrips
            StallHold.shared.release()
            cap.end()
            watchdog.stop()
            waitFor("the control read to finish after the release") { control.isDone }
            probe.printTable(title: "\(plan.label)")
            print("while the engine lock was held: \(probe.rounds) probe rounds, \(roundTrips) main-queue round trips")
            print("main-queue longest wait (information)".padding(toLength: 52, withPad: " ", startingAt: 0)
                + String(format: "    %8.3f ms", queueWait))
            guard stillHeld else { return report("the control read finished during the hold: the lock was not held") }
            return true
        }

        // MARK: - The founder's repro

        private static func deviceLossRun() -> Bool {
            let rig = StallRig()
            guard rig.buildGraph(slowUnit: false) else { return report("the graph did not build") }
            rig.startPlaying()
            let bridge = rig.bridge
            rig.onEngineQueue("the output rule to register") {
                bridge.updateOutputSelection { $0.adopt(0x7FFF_FFF0, uid: "") } // the app's device: gone
                bridge.setPinPlaybackToSelectedDevice(false) // any adoption stays in the app
                bridge.registerOutputDeviceListeners()
            }
            let viewModel = makeViewModel(bridge, tracks: 1)
            viewModel.selectedTrackIndex = 0
            viewModel.isPlaying = true
            viewModel.duration = 20
            waitFor("the playhead to pass 0.3 s before the device is lost") {
                viewModel.tickTransport()
                return viewModel.playbackPosition > 0.3
            }
            let probe = EntryProbe(viewModel: viewModel, bridge: bridge)
            let watchdog = StallWatchdog()
            watchdog.start()
            rig.holdInStop(on: DispatchQueue(label: "avfaudio-internal-stand-in"))
            let placeBefore = Mutex<Double>(0)
            let plan = HoldPlan(
                label: "mode=device-loss",
                control: { liveRead(bridge, player: true) },
                trigger: {
                    viewModel.tickTransport() // the last playhead read before the loss
                    placeBefore.withLock { $0 = viewModel.playbackPosition }
                    bridge.outputDeviceDidChange(.engineReconfigured)
                    bridge.outputDeviceDidChange(.targetAliveChanged)
                },
                step: { probe.tickOnly() },
                finished: { !viewModel.isPlaying } // paused after the device loss: a state, not a deadline
            )
            let held = holdWindow(plan, probe: probe, watchdog: watchdog)
            rig.stopRendering()
            let before = placeBefore.withLock { $0 }
            let place = viewModel.pausedResumePosition ?? -1
            print("paused after the device loss; place \(before) → \(place)")
            guard held else { return false }
            guard abs(place - before) < 0.25 else { return report("the place was not kept") }
            return true
        }

        // MARK: - Review MAJOR-1

        private static func endedAdvanceRun() -> Bool {
            let rig = StallRig()
            guard rig.buildGraph(slowUnit: false) else { return report("the graph did not build") }
            rig.startPlaying()
            let bridge = rig.bridge
            let device = getDefaultOutputDeviceID()
            bridge.updateOutputSelection { $0.adopt(device, uid: "") }
            bridge.setPinPlaybackToSelectedDevice(false) // a start never re-asserts the system default
            guard let files = writeTracks(["A", "B", "C"]) else { return report("no test files") }
            defer { files.forEach { try? FileManager.default.removeItem(at: $0) } }
            let viewModel = makeViewModel(bridge, urls: files)
            viewModel.selectedTrackIndex = 0
            viewModel.pendingNextIndex = 1
            viewModel.isPlaying = true
            bridge.gaplessPlaybackEnded = true // A ended; B queued but not armed (Pure cross-rate)
            waitFor("the clock to publish the end flag") { bridge.snapshot().transport.ended }
            // B's start is slow: the engine queue is held until THIS test lets it go.
            let release = DispatchSemaphore(value: 0)
            bridge.engineQueue.async { StallVerdict.wait(release, for: "the test's release of B's start") }
            waitFor("the advance to B") {
                viewModel.tickTransport()
                return viewModel.selectedTrackIndex == 1
            }
            // B's start still waits and A's end flag is still set: ticks must not act on it.
            for _ in 0 ..< 12 {
                viewModel.tickTransport()
                pump(0.01)
            }
            let stoppedEarly = !viewModel.isPlaying || viewModel.selectedTrackIndex != 1
            release.signal()
            waitFor("B's start to finish") {
                viewModel.tickTransport()
                return viewModel.transportCommand == nil
            }
            for _ in 0 ..< 6 {
                viewModel.tickTransport()
                pump(0.01)
            }
            rig.stopRendering()
            print("after the advance: playing \(viewModel.isPlaying), selected \(viewModel.selectedTrackIndex ?? -1)")
            guard !stoppedEarly, viewModel.isPlaying, viewModel.selectedTrackIndex == 1 else {
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

        /// Run the main loop until `state` holds. Its generous cap only breaks a hang: it fails, naming the
        /// state, and never carries on past the deadline.
        static func waitFor(_ state: String, cap: Double = StallVerdict.hangCap, _ condition: () -> Bool) {
            let deadline = ContinuousClock.now + .seconds(cap)
            while !condition() {
                if ContinuousClock.now >= deadline {
                    StallVerdict.fail("\(state) did not happen within \(Int(cap)) s")
                }
                pump(0.002)
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
