import Accelerate
import AVFoundation
import Foundation

// MARK: - AudioEngineBridge

/// Concrete `AudioPlaybackEngine` that drives `AVAudioEngine` + CoreAudio.
///
/// Device enumeration is wired to real CoreAudio data via the C-ABI functions
/// exported from `AUAudioUnit.mm` (`enumerateOutputDevicesC`, `selectOutputDeviceC`).
/// No mock data — every `AudioDeviceModel` reflects an actual system device.
final class AudioEngineBridge: AudioPlaybackEngine {
    private var avEngine: AVAudioEngine?
    private var playerNode: AVAudioPlayerNode?
    private var referenceToneBuffer: AVAudioPCMBuffer?

    // MARK: - Spectrum Analyzer

    /// Owns the FFT state and the lock-free double-buffer.
    /// Created in `initialize()` (off the audio thread) so all buffers are
    /// pre-allocated before the tap fires.
    private var spectrumAnalyzer: SpectrumAnalyzer?

    /// Tap is installed on mainMixerNode's output; the node's format fixes
    /// the sample rate that `SpectrumAnalyzer` must be initialised with.
    private var tapInstalled = false

    // MARK: - Initialize

    func initialize() async throws -> Bool {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                do {
                    self.avEngine = AVAudioEngine()
                    guard let engine = self.avEngine else {
                        continuation.resume(returning: false)
                        return
                    }

                    // Use stereo 48 kHz format to support any input file (mono, stereo, WebM, etc).
                    // AVAudio will automatically convert any file format to match this.
                    let audioFormat = AVAudioFormat(standardFormatWithSampleRate: 48000.0, channels: 2) ??
                        AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48000.0, channels: 2, interleaved: false)

                    self.playerNode = AVAudioPlayerNode()
                    if let playerNode = self.playerNode, let format = audioFormat {
                        engine.attach(playerNode)
                        engine.connect(playerNode, to: engine.mainMixerNode, format: format)
                    }

                    // Pre-allocate the spectrum analyzer using the mixer's output sample rate.
                    // This MUST happen off the audio thread (vDSP_create_fftsetup allocates).
                    let mixerSampleRate = Float(engine.mainMixerNode.outputFormat(forBus: 0).sampleRate)
                    let sampleRate = mixerSampleRate > 0 ? mixerSampleRate : 48000.0
                    self.spectrumAnalyzer = SpectrumAnalyzer(
                        fftSize: SpectrumConstants.fftSize,
                        sampleRate: sampleRate
                    )

                    continuation.resume(returning: true)
                } catch {
                    continuation.resume(returning: false)
                }
            }
        }
    }

    // MARK: - Spectrum tap

    /// Install a single output tap on `mainMixerNode`.
    ///
    /// The tap block runs on the audio thread (or a CoreAudio I/O thread).
    /// It may NOT allocate, lock, log, or call Obj-C/Swift runtime.
    ///
    /// Buffer size of 4096 aligns with `SpectrumConstants.fftSize` so the
    /// analyzer can process one tap delivery per FFT frame. AVAudioEngine
    /// will round up to a power-of-two multiple of the hardware buffer size
    /// automatically if needed.
    private func installSpectrumTap() {
        guard let engine = avEngine, !tapInstalled else { return }
        let mixer = engine.mainMixerNode
        let mixerFormat = mixer.outputFormat(forBus: 0)

        mixer.installTap(onBus: 0,
                         bufferSize: AVAudioFrameCount(SpectrumConstants.fftSize),
                         format: mixerFormat)
        { [weak self] (buffer: AVAudioPCMBuffer, _: AVAudioTime) in
            // --- AUDIO THREAD ---
            // Access only pre-allocated state through the analyzer pointer.
            guard let analyzer = self?.spectrumAnalyzer else { return }
            let abl = buffer.mutableAudioBufferList
            analyzer.processTapBuffer(
                abl,
                frameCount: buffer.frameLength,
                channelCount: buffer.format.channelCount
            )
        }
        tapInstalled = true
    }

    private func removeSpectrumTap() {
        guard let engine = avEngine, tapInstalled else { return }
        engine.mainMixerNode.removeTap(onBus: 0)
        tapInstalled = false
    }

    // MARK: - Public spectrum read (called from main thread via ViewModel)

    /// Copy the latest 44 band magnitudes into `out`. Returns `false` if no
    /// data has been published yet (engine not running or no signal).
    @discardableResult
    func readSpectrumBands(into out: inout [Float]) -> Bool {
        return spectrumAnalyzer?.doubleBuffer.read(into: &out) ?? false
    }

    // MARK: - Shutdown

    func shutdown() async throws {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                self.removeSpectrumTap()
                if let playerNode = self.playerNode, playerNode.isPlaying {
                    playerNode.stop()
                }
                if let engine = self.avEngine, engine.isRunning {
                    engine.stop()
                }
                self.avEngine = nil
                self.playerNode = nil
                self.referenceToneBuffer = nil
                self.spectrumAnalyzer = nil
                continuation.resume()
            }
        }
    }

    // MARK: - Device Enumeration (real CoreAudio data)

    /// Enumerate output devices using the C-ABI bridge to CoreAudio.
    /// Returns real device IDs, names, sample rates, and types — no mock data.
    func enumerateOutputDevices() async throws -> [AudioDeviceModel] {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                let maxDevices = 32
                var buffer = [CDeviceInfo](repeating: CDeviceInfo(), count: maxDevices)
                let count = enumerateOutputDevicesC(&buffer, UInt32(maxDevices))

                var models: [AudioDeviceModel] = []
                models.reserveCapacity(Int(count))

                for index in 0 ..< Int(count) {
                    let info = buffer[index]
                    let name = withUnsafeBytes(of: info.name) { rawPtr -> String in
                        let ptr = rawPtr.bindMemory(to: CChar.self)
                        guard let base = ptr.baseAddress else { return "" }
                        return String(cString: base)
                    }
                    let deviceType = AudioDeviceModel.DeviceType(rawValue: info.deviceType)
                    models.append(AudioDeviceModel(
                        id: info.deviceID,
                        name: name,
                        sampleRate: info.sampleRate,
                        bufferFrameSize: info.bufferFrameSize,
                        type: deviceType
                    ))
                }

                // Sort: built-in first, then wireless, then USB, then unknown.
                // Within each type, sort alphabetically by name.
                models.sort { lhs, rhs in
                    let lhsOrder = lhs.type.sortOrder
                    let rhsOrder = rhs.type.sortOrder
                    if lhsOrder != rhsOrder { return lhsOrder < rhsOrder }
                    return lhs.name < rhs.name
                }

                continuation.resume(returning: models)
            }
        }
    }

    func selectDevice(_ deviceID: UInt32) async throws -> Bool {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                // selectOutputDeviceC returns Int32: 1 = success, 0 = failure
                let result = selectOutputDeviceC(deviceID)
                continuation.resume(returning: result != 0)
            }
        }
    }

    // MARK: - Playback

    func startAudio(fileURL: URL? = nil) async throws {
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global().async {
                do {
                    guard let engine = self.avEngine, let playerNode = self.playerNode else {
                        throw AudioBridgeError.engineNotInitialized
                    }

                    // Start the engine first
                    if !engine.isRunning {
                        try engine.start()
                    }

                    // Install the spectrum tap once the engine is running.
                    // installSpectrumTap is idempotent (guarded by tapInstalled flag).
                    self.installSpectrumTap()

                    if let fileURL = fileURL {
                        // Establish security-scoped access for sandboxed macOS file access
                        let didAccess = fileURL.startAccessingSecurityScopedResource()
                        defer { if didAccess { fileURL.stopAccessingSecurityScopedResource() } }

                        // Load and schedule the audio file (AVAudioFile handles format conversion)
                        do {
                            // CRITICAL: Stop and reset the player before scheduling a new file.
                            // If we don't stop, the new file queues AFTER the old one instead of replacing it.
                            // This ensures track switching happens immediately, not after current track finishes.
                            if playerNode.isPlaying {
                                playerNode.stop()
                            }

                            let audioFile = try AVAudioFile(forReading: fileURL)
                            playerNode.scheduleFile(audioFile, at: nil)
                            playerNode.play()
                        } catch {
                            throw AudioBridgeError.unsupportedFormat(fileURL.pathExtension)
                        }
                    } else {
                        // Fallback to reference tone if no file provided
                        self.referenceToneBuffer = self.generateReferenceTone(
                            frequency: 1000.0,
                            duration: 5.0,
                            sampleRate: 48000.0
                        )

                        if let buffer = self.referenceToneBuffer {
                            if !playerNode.isPlaying {
                                playerNode.play()
                            }
                            playerNode.scheduleBuffer(buffer, at: nil)
                        }
                    }

                    continuation.resume(returning: ())
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func stopAudio() async throws {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                if let playerNode = self.playerNode, playerNode.isPlaying {
                    playerNode.stop()
                }
                if let engine = self.avEngine, engine.isRunning {
                    engine.stop()
                }
                self.removeSpectrumTap()
                self.referenceToneBuffer = nil
                continuation.resume()
            }
        }
    }

    func currentPlaybackPosition() -> Double? {
        // Derive the playhead from the player node's render time. sampleTime counts
        // from 0 at play() and accumulates while playing — divide by the rate to get
        // seconds. AVAudioPlayerNode time queries are safe to call from any thread.
        guard let playerNode, playerNode.isPlaying,
              let nodeTime = playerNode.lastRenderTime,
              let playerTime = playerNode.playerTime(forNodeTime: nodeTime),
              playerTime.sampleRate > 0
        else {
            return nil
        }
        return Double(playerTime.sampleTime) / playerTime.sampleRate
    }

    func setParameter(_ id: UInt32, value: Float) async throws {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                if id == 0 {
                    // Master gain parameter
                    if let playerNode = self.playerNode {
                        playerNode.volume = value
                    }
                }
                continuation.resume()
            }
        }
    }

    // MARK: - Reference Tone Generation (using vDSP)

    func generateReferenceTone(
        frequency: Float,
        duration: Float,
        sampleRate: Float
    ) -> AVAudioPCMBuffer? {
        let frameCount = AVAudioFrameCount(duration * sampleRate)

        guard let format = AVAudioFormat(standardFormatWithSampleRate: Double(sampleRate), channels: 1) else {
            return nil
        }

        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            return nil
        }

        buffer.frameLength = frameCount

        guard let floatChannelData = buffer.floatChannelData else {
            return nil
        }

        let floatData = floatChannelData[0]

        // Generate sine wave using vDSP
        // Phase increment per sample: 2π * frequency / sampleRate
        let phaseIncrement = 2.0 * Float.pi * frequency / sampleRate

        // Build angle array: angle[i] = phaseIncrement * i
        var angles = [Float](repeating: 0, count: Int(frameCount))
        for sampleIndex in 0 ..< Int(frameCount) {
            angles[sampleIndex] = phaseIncrement * Float(sampleIndex)
        }

        // Compute sine using vForce.sin (Accelerate, vectorised single-precision)
        let sineValues = vForce.sin(angles)
        sineValues.withUnsafeBufferPointer { src in
            guard let srcBase = src.baseAddress else { return }
            UnsafeMutableBufferPointer(start: floatData, count: Int(frameCount))
                .baseAddress
                .map { dst in
                    cblas_scopy(Int32(frameCount), srcBase, 1, dst, 1)
                }
        }

        // Apply gain
        var gain = Float(0.3)
        vDSP_vsmul(floatData, 1, &gain, floatData, 1, vDSP_Length(frameCount))

        return buffer
    }
}

// MARK: - AudioDeviceModel.DeviceType sort order

private extension AudioDeviceModel.DeviceType {
    var sortOrder: Int {
        switch self {
        case .builtin: return 0
        case .wireless: return 1
        case .usb: return 2
        case .unknown: return 3
        }
    }
}
