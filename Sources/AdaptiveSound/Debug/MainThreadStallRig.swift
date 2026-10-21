#if DEBUG
    import AudioDSP
    import AudioToolbox
    @preconcurrency import AVFoundation
    import Foundation
    import Synchronization

    // MARK: - The rig behind `make main-thread-stall` (S10.8 G, the disconnect freeze)

    //
    // The REAL `AudioEngineBridge` graph — the real effects and spatial AUs, taps, meter, analyzers,
    // transport clock — built on an AVAudioEngine in OFFLINE manual-rendering mode, so no audio
    // device is opened and nothing is heard; a background thread pulls the render as a device would.
    // On top of it the REAL `AudioViewModel`. The rig then makes AVFAudio's engine-wide lock
    // (`AVAudioNodeImplBase::GetAttachAndEngineLock`) wait for seconds, as macOS made it wait on a
    // dying device, and times every main-thread entry. Adopted from the S10.8 G review's breaker
    // harness; the lock-holding techniques are the main-thread audit's experiments 1 and 2.

    /// A v3 AU whose `allocateRenderResources` holds when the hold is armed: `engine.start()` holds
    /// the engine lock while it allocates (audit experiment 2) — a slow Bluetooth start.
    final class StallSlowAU: AUAudioUnit {
        static let description = AudioComponentDescription(
            componentType: kAudioUnitType_Effect, componentSubType: 0x736C_6F77, // 'slow'
            componentManufacturer: 0x4153_5374, componentFlags: 0, componentFlagsMask: 0 // 'ASSt'
        )
        private var inputBusArray: AUAudioUnitBusArray?
        private var outputBusArray: AUAudioUnitBusArray?

        override init(componentDescription: AudioComponentDescription,
                      options: AudioComponentInstantiationOptions = []) throws {
            try super.init(componentDescription: componentDescription, options: options)
            guard let format = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2) else { return }
            inputBusArray = try AUAudioUnitBusArray(audioUnit: self, busType: .input,
                                                    busses: [AUAudioUnitBus(format: format)])
            outputBusArray = try AUAudioUnitBusArray(audioUnit: self, busType: .output,
                                                     busses: [AUAudioUnitBus(format: format)])
        }

        override var inputBusses: AUAudioUnitBusArray {
            inputBusArray ?? super.inputBusses
        }

        override var outputBusses: AUAudioUnitBusArray {
            outputBusArray ?? super.outputBusses
        }

        override func allocateRenderResources() throws {
            try super.allocateRenderResources()
            StallHold.shared.holdIfArmed()
        }

        override var internalRenderBlock: AUInternalRenderBlock {
            { _, _, frames, _, output, _, pull in
                guard let pull else { return kAudioUnitErr_NoConnection }
                var flags = AudioUnitRenderActionFlags()
                var stamp = AudioTimeStamp()
                return pull(&flags, &stamp, frames, 0, output)
            }
        }
    }

    /// Main-queue responsiveness: a background thread posts a block to the main queue every 2 ms. Each
    /// block that RUNS is a round trip — the main queue is being served. The count is the oracle (the
    /// longest wait is printed as information only).
    final class StallWatchdog: Sendable {
        private let worst = Mutex<Double>(0)
        private let trips = Atomic<Int>(0)
        private let running = Atomic<Bool>(false)

        var worstMilliseconds: Double {
            worst.withLock { $0 } * 1000
        }

        /// Main-queue probes that came back.
        var roundTrips: Int {
            trips.load(ordering: .acquiring)
        }

        func start() {
            running.store(true, ordering: .releasing)
            Thread.detachNewThread { [self] in
                while running.load(ordering: .acquiring) {
                    let stamp = ContinuousClock.now
                    DispatchQueue.main.async { self.record(ContinuousClock.now - stamp) }
                    usleep(2000)
                }
            }
        }

        func stop() {
            running.store(false, ordering: .releasing)
        }

        private func record(_ wait: Duration) {
            let seconds = Double(wait.components.seconds) + Double(wait.components.attoseconds) * 1e-18
            worst.withLock { $0 = max($0, seconds) }
            trips.wrappingAdd(1, ordering: .releasing)
        }
    }

    /// The real bridge on an offline engine, and the ways to hold its lock.
    final class StallRig: Sendable {
        let bridge = AudioEngineBridge()
        private let rendering = Atomic<Bool>(false)

        /// Build the real graph on an offline engine (on `engineQueue`, as `initialize()` does).
        /// `slowUnit` adds `StallSlowAU`, for the slow-start hold.
        func buildGraph(slowUnit: Bool) -> Bool {
            registerAdaptiveAudioUnitSubclass()
            registerSpatialRendererAUSubclass()
            AUAudioUnit.registerSubclass(StallSlowAU.self, as: StallSlowAU.description,
                                         name: "AdaptiveSound: StallSlowAU", version: 1)
            let built = DispatchSemaphore(value: 0)
            let success = Atomic<Bool>(false)
            let bridge = bridge
            bridge.engineQueue.async {
                guard let format = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2),
                      let engine = Self.offlineEngine(format: format) else {
                    built.signal()
                    return
                }
                bridge.setAvEngine(engine)
                let player = AVAudioPlayerNode()
                bridge.setPlayerNode(player)
                engine.attach(player)
                bridge.instantiateAndBuildGraph(engine: engine, player: player, format: format) { ok in
                    success.store(ok, ordering: .releasing)
                    guard slowUnit else {
                        built.signal()
                        return
                    }
                    Self.attachSlowUnit(to: engine, format: format) { built.signal() }
                }
            }
            StallVerdict.wait(built, for: "the offline graph to build")
            return success.load(ordering: .acquiring)
        }

        private static func offlineEngine(format: AVAudioFormat) -> AVAudioEngine? {
            let engine = AVAudioEngine()
            do {
                try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 4096)
                return engine
            } catch {
                return nil
            }
        }

        private static func attachSlowUnit(to engine: AVAudioEngine, format: AVAudioFormat,
                                           done: @escaping @Sendable () -> Void) {
            AVAudioUnit.instantiate(with: StallSlowAU.description, options: []) { unit, _ in
                if let unit {
                    engine.attach(unit)
                    let feeder = AVAudioPlayerNode()
                    engine.attach(feeder)
                    engine.connect(feeder, to: unit, format: format)
                    let bus = engine.mainMixerNode.nextAvailableInputBus
                    engine.connect(unit, to: engine.mainMixerNode, fromBus: 0, toBus: bus, format: format)
                }
                done()
            }
        }

        /// Start the engine and play a quiet 20 s tone through the real graph, then pull the render
        /// on a background thread every 10 ms — the device stand-in.
        func startPlaying() {
            let started = DispatchSemaphore(value: 0)
            let bridge = bridge
            bridge.engineQueue.async {
                defer { started.signal() }
                guard let engine = bridge.avEngineRef, let player = bridge.playerNodeRef,
                      let tone = Self.tone(format: player.outputFormat(forBus: 0)) else { return }
                bridge.installSpectrumTap()
                try? engine.start()
                player.scheduleBuffer(tone, at: nil)
                player.play()
                // One render before the clock samples: the first render makes the render time valid.
                if let out = AVAudioPCMBuffer(pcmFormat: engine.manualRenderingFormat, frameCapacity: 4096) {
                    _ = try? engine.renderOffline(480, to: out)
                }
                bridge.enhancedPlayIntent = true
                bridge.startTransportClock()
            }
            StallVerdict.wait(started, for: "the engine to start playing")
            rendering.store(true, ordering: .releasing)
            Thread.detachNewThread { [self] in
                guard let engine = bridge.avEngineRef,
                      let out = AVAudioPCMBuffer(pcmFormat: engine.manualRenderingFormat, frameCapacity: 4096)
                else { return }
                while rendering.load(ordering: .acquiring) {
                    _ = try? engine.renderOffline(480, to: out)
                    usleep(10000)
                }
            }
        }

        func stopRendering() {
            rendering.store(false, ordering: .releasing)
        }

        private static func tone(format: AVAudioFormat) -> AVAudioPCMBuffer? {
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 48000 * 20),
                  let channels = buffer.floatChannelData else { return nil }
            buffer.frameLength = buffer.frameCapacity
            for frame in 0 ..< Int(buffer.frameLength) {
                let sample = Float(0.05 * sin(Double(frame) * 2 * .pi * 440 / 48000))
                for channel in 0 ..< Int(format.channelCount) {
                    channels[channel][frame] = sample
                }
            }
            return buffer
        }

        /// Hold the engine lock until the test releases it: `player.stop()` on `queue` runs a completion
        /// handler that waits inside the lock (audit experiment 1) — the re-establish, pause or
        /// device-loss stop. `StallHold.shared.isInside` says when the holder is in.
        func holdInStop(on queue: DispatchQueue) {
            guard let player = bridge.playerNodeRef,
                  let small = AVAudioPCMBuffer(pcmFormat: player.outputFormat(forBus: 0), frameCapacity: 4800)
            else { return }
            small.frameLength = 4800
            player.scheduleBuffer(small, completionCallbackType: .dataConsumed) { _ in
                StallHold.shared.holdIfArmed()
            }
            StallHold.shared.arm()
            let bridge = bridge
            queue.async { bridge.playerNodeRef?.stop() }
        }

        /// Hold the engine lock until the test releases it, in `engine.start()` (the slow AU's allocation).
        func holdInStart() {
            StallHold.shared.arm()
            let bridge = bridge
            bridge.engineQueue.async { try? bridge.avEngineRef?.start() }
        }

        /// Run `work` on `engineQueue` and tell the caller when it has run (a state, not a pause).
        func onEngineQueue(_ what: String, _ work: @escaping @Sendable () -> Void) {
            let done = DispatchSemaphore(value: 0)
            bridge.engineQueue.async {
                work()
                done.signal()
            }
            StallVerdict.wait(done, for: what)
        }
    }
#endif
