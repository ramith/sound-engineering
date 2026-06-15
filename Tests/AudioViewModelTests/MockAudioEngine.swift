
@_exported import Foundation // re-export so other files in this module see URL, etc.

// MARK: - MockAudioEngine

//
// Minimal AudioPlaybackEngine conformer for unit tests.
// Lives in the test target — never ships in the application binary.
//
// NOTE: AudioViewModel and AudioPlaybackEngine live in the `AdaptiveSound`
// executable target. SPM does not allow @testable import of executable targets.
// Until AudioViewModel is extracted into a library target (Phase 1.5), this
// file mirrors only the AudioPlaybackEngine protocol surface needed by the tests.
// When the library split lands, replace the mirror with:
//   @testable import AdaptiveSoundCore
// and delete the duplicated protocol + model declarations below.

// MARK: - Protocol mirror (matches AudioPlaybackEngine exactly)

protocol AudioPlaybackEngineMirror: AnyObject {
    func initialize() async throws -> Bool
    func shutdown() async throws
    func startAudio(fileURL: URL?) async throws
    func stopAudio() async throws
    func setParameter(_ id: UInt32, value: Float) async throws
    func enumerateOutputDevices() async throws -> [AudioDeviceModelMirror]
    func selectDevice(_ deviceID: UInt32) async throws -> Bool
    @discardableResult
    func readSpectrumBands(into out: inout [Float]) -> Bool
}

// MARK: - AudioDeviceModel mirror

struct AudioDeviceModelMirror: Identifiable, Equatable {
    let id: UInt32
    let name: String
    let sampleRate: UInt32
    let bufferFrameSize: UInt32

    enum DeviceType { case builtin, usb, wireless, unknown }
    let type: DeviceType
}

// MARK: - MockAudioEngine

final class MockAudioEngine: AudioPlaybackEngineMirror {
    // MARK: Call counters

    private(set) var initializeCallCount = 0
    private(set) var shutdownCallCount = 0
    private(set) var startAudioCallCount = 0
    private(set) var stopAudioCallCount = 0
    private(set) var setParameterCallCount = 0
    private(set) var enumerateDevicesCallCount = 0
    private(set) var selectDeviceCallCount = 0
    private(set) var readSpectrumCallCount = 0

    // MARK: Captured arguments

    private(set) var lastStartedURL: URL?
    private(set) var lastSetParameterID: UInt32?
    private(set) var lastSetParameterValue: Float?
    private(set) var lastSelectedDeviceID: UInt32?

    // MARK: Configurable stubs

    var initializeResult: Bool = true
    var initializeError: Error?
    var enumerateResult: [AudioDeviceModelMirror] = [
        AudioDeviceModelMirror(
            id: 73,
            name: "Built-in Output",
            sampleRate: 48000,
            bufferFrameSize: 512,
            type: .builtin
        ),
        AudioDeviceModelMirror(
            id: 84,
            name: "AirPods Pro",
            sampleRate: 24000,
            bufferFrameSize: 256,
            type: .wireless
        ),
    ]
    var selectDeviceResult: Bool = true
    var spectrumData: [Float] = .init(repeating: 0, count: 44)
    var hasSpectrumData: Bool = false

    // MARK: Protocol conformance

    func initialize() async throws -> Bool {
        initializeCallCount += 1
        if let err = initializeError { throw err }
        return initializeResult
    }

    func shutdown() async throws {
        shutdownCallCount += 1
    }

    func startAudio(fileURL: URL?) async throws {
        startAudioCallCount += 1
        lastStartedURL = fileURL
    }

    func stopAudio() async throws {
        stopAudioCallCount += 1
    }

    func setParameter(_ id: UInt32, value: Float) async throws {
        setParameterCallCount += 1
        lastSetParameterID = id
        lastSetParameterValue = value
    }

    func enumerateOutputDevices() async throws -> [AudioDeviceModelMirror] {
        enumerateDevicesCallCount += 1
        return enumerateResult
    }

    func selectDevice(_ deviceID: UInt32) async throws -> Bool {
        selectDeviceCallCount += 1
        lastSelectedDeviceID = deviceID
        return selectDeviceResult
    }

    @discardableResult
    func readSpectrumBands(into out: inout [Float]) -> Bool {
        readSpectrumCallCount += 1
        guard hasSpectrumData else { return false }
        let count = min(out.count, spectrumData.count)
        out[0 ..< count] = spectrumData[0 ..< count]
        return true
    }
}
