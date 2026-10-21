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

    /// Seconds to sleep inside the engine-wide lock, armed once and taken by whichever holder runs.
    final class StallGate: Sendable {
        static let shared = StallGate()
        private let armed = Mutex<Double>(0)

        func arm(_ seconds: Double) {
            armed.withLock { $0 = seconds }
        }

        func take() -> Double {
            armed.withLock { seconds in
                defer { seconds = 0 }
                return seconds
            }
        }
    }

    /// A v3 AU whose `allocateRenderResources` sleeps when the gate is armed: `engine.start()` holds
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
            let seconds = StallGate.shared.take()
            if seconds > 0 {
                Thread.sleep(forTimeInterval: seconds)
            }
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

    /// Main-queue responsiveness: a background thread posts a stamped block every 2 ms and records
    /// the longest wait.
    final class StallWatchdog: Sendable {
        private let worst = Mutex<Double>(0)
        private let running = Atomic<Bool>(false)

        var worstMilliseconds: Double {
            worst.withLock { $0 } * 1000
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

        func reset() {
            worst.withLock { $0 = 0 }
        }

        func stop() {
            running.store(false, ordering: .releasing)
        }

        private func record(_ wait: Duration) {
            let seconds = Double(wait.components.seconds) + Double(wait.components.attoseconds) * 1e-18
            worst.withLock { $0 = max($0, seconds) }
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
            built.wait()
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
            started.wait()
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

        /// Hold the engine lock for `seconds`: `player.stop()` on `queue` runs a completion handler
        /// that sleeps inside the lock (audit experiment 1) — the re-establish, pause or device-loss
        /// stop.
        func holdInStop(on queue: DispatchQueue, seconds: Double) {
            guard let player = bridge.playerNodeRef,
                  let small = AVAudioPCMBuffer(pcmFormat: player.outputFormat(forBus: 0), frameCapacity: 4800)
            else { return }
            small.frameLength = 4800
            player.scheduleBuffer(small, completionCallbackType: .dataConsumed) { _ in
                let hold = StallGate.shared.take()
                if hold > 0 {
                    Thread.sleep(forTimeInterval: hold)
                }
            }
            StallGate.shared.arm(seconds)
            let bridge = bridge
            queue.async { bridge.playerNodeRef?.stop() }
        }

        /// Hold the engine lock for `seconds` in `engine.start()` (the slow AU's allocation).
        func holdInStart(seconds: Double) {
            StallGate.shared.arm(seconds)
            let bridge = bridge
            bridge.engineQueue.async { try? bridge.avEngineRef?.start() }
        }
    }
#endif
