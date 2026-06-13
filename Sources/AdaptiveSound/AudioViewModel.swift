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
    @Published var errorMessage: String?
    @Published var selectedDevice: AudioDeviceModel?
    @Published var availableDevices: [AudioDeviceModel] = []
    @Published var sampleRate: UInt32 = 0
    @Published var bufferFrameSize: UInt32 = 0

    private let audioEngine: AudioEngineBridge

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
}

// MARK: - C++ Bridge

class AudioEngineBridge {
    func initialize() async throws -> Bool {
        // Bridge to C++ AudioEngine::initialize()
        // For now, return true to allow UI development to proceed
        return true
    }

    func shutdown() async throws {
        // Bridge to C++ AudioEngine::shutdown()
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
}
