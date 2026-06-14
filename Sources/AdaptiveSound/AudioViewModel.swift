import Accelerate
import AVFoundation
import Combine
import Foundation

// MARK: - Audio Device Model

struct AudioDeviceModel: Identifiable, Equatable {
    let id: UInt32
    let name: String
    let sampleRate: UInt32
    let bufferFrameSize: UInt32

    enum DeviceType {
        case builtin
        case usb
        case wireless
        case unknown
    }

    let type: DeviceType

    var displayName: String {
        let typeLabel: String
        switch type {
        case .builtin:
            typeLabel = "Built-in"
        case .usb:
            typeLabel = "USB"
        case .wireless:
            typeLabel = "Wireless"
        case .unknown:
            typeLabel = "Unknown"
        }
        return "\(name) (\(typeLabel))"
    }

    var systemIcon: String {
        switch type {
        case .builtin:
            return "speaker.wave.2.circle"
        case .usb:
            return "cable.connector"
        case .wireless:
            return "airpodspro"
        case .unknown:
            return "questionmark.circle"
        }
    }
}

// MARK: - AudioViewModel

@MainActor
final class AudioViewModel: ObservableObject {
    @Published var isEngineReady = false
    @Published var isPlaying = false
    @Published var errorMessage: String?
    @Published var selectedDevice: AudioDeviceModel?
    @Published var availableDevices: [AudioDeviceModel] = []
    @Published var sampleRate: UInt32 = 0
    @Published var bufferFrameSize: UInt32 = 0
    @Published var masterGain: Float = 0.7 {
        didSet {
            setParameter(masterGainParameterID, value: masterGain)
        }
    }

    private let audioEngine: AudioEngineBridge
    private let masterGainParameterID: UInt32 = 0

    init(audioEngine: AudioEngineBridge = AudioEngineBridge()) {
        self.audioEngine = audioEngine
    }

    // MARK: - Engine Lifecycle

    func initializeEngine() {
        Task.detached { [weak self] in
            do {
                let success = try await self?.audioEngine.initialize() ?? false
                if !success {
                    await MainActor.run {
                        self?.errorMessage = "Failed to initialize audio engine"
                        self?.isEngineReady = false
                    }
                    return
                }

                // Enumerate devices
                let deviceNames = try await self?.audioEngine.getOutputDeviceNames() ?? []
                let devices = deviceNames.enumerated().map { index, name in
                    AudioDeviceModel(
                        id: UInt32(index),
                        name: name,
                        sampleRate: 48000,
                        bufferFrameSize: 512,
                        type: .unknown
                    )
                }

                await MainActor.run {
                    self?.availableDevices = devices
                    self?.selectedDevice = devices.first
                    self?.isEngineReady = true
                    self?.errorMessage = nil
                }
            } catch {
                await MainActor.run {
                    self?.errorMessage = "Engine initialization failed: \(error.localizedDescription)"
                    self?.isEngineReady = false
                }
            }
        }
    }

    func shutdown() {
        stopPlayback()
        Task.detached { [weak self] in
            try await self?.audioEngine.shutdown()
            await MainActor.run {
                self?.isEngineReady = false
            }
        }
    }

    // MARK: - Device Management

    func selectDevice(_ device: AudioDeviceModel) {
        Task.detached { [weak self] in
            do {
                let success = try await self?.audioEngine.selectDevice(device.id) ?? false
                if !success {
                    await MainActor.run {
                        self?.errorMessage = "Failed to select device: \(device.name)"
                    }
                    return
                }

                await MainActor.run {
                    self?.selectedDevice = device
                    self?.sampleRate = device.sampleRate
                    self?.bufferFrameSize = device.bufferFrameSize
                    self?.errorMessage = nil
                }
            } catch {
                await MainActor.run {
                    self?.errorMessage = "Device selection failed: \(error.localizedDescription)"
                }
            }
        }
    }

    func retryInitialization() {
        errorMessage = nil
        isEngineReady = false
        initializeEngine()
    }

    // MARK: - Playback Control

    func startPlayback() {
        guard isEngineReady else {
            errorMessage = "Engine not ready"
            return
        }

        Task.detached { [weak self] in
            do {
                try await self?.audioEngine.startAudio()
                await MainActor.run {
                    self?.isPlaying = true
                    self?.errorMessage = nil
                }
            } catch {
                await MainActor.run {
                    self?.errorMessage = "Playback failed: \(error.localizedDescription)"
                    self?.isPlaying = false
                }
            }
        }
    }

    func stopPlayback() {
        Task.detached { [weak self] in
            do {
                try await self?.audioEngine.stopAudio()
                await MainActor.run {
                    self?.isPlaying = false
                }
            } catch {
                await MainActor.run {
                    self?.errorMessage = "Stop playback failed: \(error.localizedDescription)"
                }
            }
        }
    }

    // MARK: - Parameter Control

    func setParameter(_ id: UInt32, value: Float) {
        Task.detached { [weak self] in
            try await self?.audioEngine.setParameter(id, value: value)
        }
    }
}

// MARK: - C++ Bridge

class AudioEngineBridge {
    private var audioEngine: AVAudioEngine?
    private var playerNode: AVAudioPlayerNode?
    private var referenceToneBuffer: AVAudioPCMBuffer?

    func initialize() async throws -> Bool {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                do {
                    self.audioEngine = AVAudioEngine()
                    guard let engine = self.audioEngine else {
                        continuation.resume(returning: false)
                        return
                    }

                    // Create a mono PCM format at 48 kHz
                    let audioFormat = AVAudioFormat(standardFormatWithSampleRate: 48000.0, channels: 1) ??
                        AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48000.0, channels: 1, interleaved: false)

                    self.playerNode = AVAudioPlayerNode()
                    if let playerNode = self.playerNode, let format = audioFormat {
                        engine.attach(playerNode)
                        engine.connect(playerNode, to: engine.mainMixerNode, format: format)
                    }

                    continuation.resume(returning: true)
                } catch {
                    continuation.resume(returning: false)
                }
            }
        }
    }

    func shutdown() async throws {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                if let playerNode = self.playerNode, playerNode.isPlaying {
                    playerNode.stop()
                }
                if let engine = self.audioEngine, engine.isRunning {
                    engine.stop()
                }
                self.audioEngine = nil
                self.playerNode = nil
                self.referenceToneBuffer = nil
                continuation.resume()
            }
        }
    }

    func getOutputDeviceNames() async throws -> [String] {
        // Bridge to C++ AudioEngine::getOutputDeviceNames()
        // Mock implementation for now
        return ["Built-in Speaker", "AirPods Pro", "USB Audio Interface"]
    }

    func selectDevice(_: UInt32) async throws -> Bool {
        // Bridge to C++ AudioEngine::selectOutputDevice()
        return true
    }

    func startAudio() async throws {
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global().async {
                do {
                    guard let engine = self.audioEngine, let playerNode = self.playerNode else {
                        throw AudioBridgeError.engineNotInitialized
                    }

                    // Start the engine first
                    if !engine.isRunning {
                        try engine.start()
                    }

                    // Generate reference tone (1 kHz, 5 seconds at 48 kHz, mono)
                    self.referenceToneBuffer = self.generateReferenceTone(
                        frequency: 1000.0,
                        duration: 5.0,
                        sampleRate: 48000.0
                    )

                    // Schedule and play the reference tone
                    if let buffer = self.referenceToneBuffer {
                        if !playerNode.isPlaying {
                            playerNode.play()
                        }
                        playerNode.scheduleBuffer(buffer, at: nil)
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
                if let engine = self.audioEngine, engine.isRunning {
                    engine.stop()
                }
                self.referenceToneBuffer = nil
                continuation.resume()
            }
        }
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
        for i in 0 ..< Int(frameCount) {
            angles[i] = phaseIncrement * Float(i)
        }

        // Compute sine using vForce.sin (Accelerate, vectorised single-precision)
        let sineValues = vForce.sin(angles)
        sineValues.withUnsafeBufferPointer { src in
            UnsafeMutableBufferPointer(start: floatData, count: Int(frameCount))
                .baseAddress
                .map { dst in
                    cblas_scopy(Int32(frameCount), src.baseAddress!, 1, dst, 1)
                }
        }

        // Apply gain
        var gain = Float(0.3)
        vDSP_vsmul(floatData, 1, &gain, floatData, 1, vDSP_Length(frameCount))

        return buffer
    }
}

// MARK: - AudioEngineBridge Error

enum AudioBridgeError: Error {
    case engineNotInitialized
    case auInitializationFailed
    case parameterSetFailed
}
