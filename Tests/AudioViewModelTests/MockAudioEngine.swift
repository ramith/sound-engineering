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

// MARK: - SignalPathInfo mirror (matches SignalPathInfo from the main target)

enum OutputPathKindMirror { case enhanced, pure }
enum PureModeDecisionUIMirror { case fullBitPerfect, rateMatchedFloat, fallbackEnhanced }
enum DecoderKindUIMirror { case apple, ffmpeg }

struct SignalPathInfoMirror: Equatable {
    var path: OutputPathKindMirror = .enhanced
    var decision: PureModeDecisionUIMirror = .fallbackEnhanced
    var achievedSampleRate: Double = 0
    var bitDepth: UInt32 = 0
    var isFloat: Bool = false
    var exclusiveHog: Bool = false
    var rateMatched: Bool = false
    var decoder: DecoderKindUIMirror?
    var fellBackToEnhanced: Bool = false
}

// MARK: - Protocol mirror (matches AudioPlaybackEngine exactly)

protocol AudioPlaybackEngineMirror: AnyObject {
    func initialize() async throws -> Bool
    func shutdown() async throws
    func startAudio(fileURL: URL?, pureMode: Bool) async throws
    func stopAudio() async throws
    func seek(to seconds: Double) async
    func currentPlaybackPosition() -> Double?
    func currentSignalPath() -> SignalPathInfoMirror
    func setParameter(_ id: UInt32, value: Float) async throws
    func enumerateOutputDevices() async throws -> [AudioDeviceModelMirror]
    func selectDevice(_ deviceID: UInt32) async throws -> Bool
    var onOutputDevicesChanged: (() -> Void)? { get set }
    @discardableResult
    func readSpectrumBands(into out: inout [Float]) -> Bool

    // Gapless / continuous playback
    func setNextTrack(_ fileURL: URL?) async
    func trackTransitionCount() -> UInt64
    func playbackEnded() -> Bool
}

extension AudioPlaybackEngineMirror {
    /// Backward-compatible convenience: start without Pure mode.
    func startAudio(fileURL: URL?) async throws {
        try await startAudio(fileURL: fileURL, pureMode: false)
    }

    /// Default no-op so existing conformers that do not need gapless still build.
    func setNextTrack(_: URL?) async {}
    func trackTransitionCount() -> UInt64 {
        0
    }

    func playbackEnded() -> Bool {
        false
    }
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
    private(set) var seekCallCount = 0
    private(set) var setParameterCallCount = 0
    private(set) var enumerateDevicesCallCount = 0
    private(set) var selectDeviceCallCount = 0
    private(set) var readSpectrumCallCount = 0
    private(set) var setNextTrackCallCount = 0

    // MARK: Captured arguments

    private(set) var lastStartedURL: URL?
    private(set) var lastStartedPureMode: Bool = false
    private(set) var lastSeekedSeconds: Double?
    private(set) var lastSetParameterID: UInt32?
    private(set) var lastSetParameterValue: Float?
    private(set) var lastSelectedDeviceID: UInt32?
    /// Most-recently supplied on-deck URL (nil = cleared).
    private(set) var nextTrackURL: URL?

    // MARK: Configurable stubs

    var initializeResult: Bool = true
    var initializeError: Error?
    /// When set to a non-nil error, `startAudio` throws that error on the next call.
    var startAudioThrowsError: Error?
    var onOutputDevicesChanged: (() -> Void)?
    var mockSignalPath: SignalPathInfoMirror = .init()
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

    // MARK: Gapless state

    /// Monotonic count of completed gapless seams. Incremented by `simulateTrackEnd()`.
    private(set) var transitionCount: UInt64 = 0
    /// True when the current track ended with no next track on deck.
    private(set) var endedFlag: Bool = false

    // MARK: Test helpers

    /// Simulate the current track reaching its end.
    ///
    /// - If `nextTrackURL` is set: increments `transitionCount` (models a gapless seam),
    ///   clears `nextTrackURL` (the on-deck slot is now empty until the VM queues the next).
    /// - If `nextTrackURL` is nil: sets `endedFlag = true` (models playback ending with an
    ///   empty queue).
    func simulateTrackEnd() {
        if nextTrackURL != nil {
            transitionCount += 1
            nextTrackURL = nil
        } else {
            endedFlag = true
        }
    }

    /// Reset all gapless state (useful between test cases).
    func resetGaplessState() {
        transitionCount = 0
        endedFlag = false
        nextTrackURL = nil
    }

    // MARK: Protocol conformance

    func initialize() async throws -> Bool {
        initializeCallCount += 1
        if let err = initializeError { throw err }
        return initializeResult
    }

    func shutdown() async throws {
        shutdownCallCount += 1
    }

    func startAudio(fileURL: URL?, pureMode: Bool) async throws {
        startAudioCallCount += 1
        lastStartedURL = fileURL
        lastStartedPureMode = pureMode
        if let err = startAudioThrowsError { throw err }
        // A fresh startAudio clears the ended flag (new playback session).
        endedFlag = false
    }

    func stopAudio() async throws {
        stopAudioCallCount += 1
    }

    func seek(to seconds: Double) async {
        seekCallCount += 1
        lastSeekedSeconds = seconds
    }

    var mockPlaybackPosition: Double?
    func currentPlaybackPosition() -> Double? {
        mockPlaybackPosition
    }

    func currentSignalPath() -> SignalPathInfoMirror {
        mockSignalPath
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

    // MARK: Gapless protocol methods

    func setNextTrack(_ fileURL: URL?) async {
        setNextTrackCallCount += 1
        nextTrackURL = fileURL
    }

    func trackTransitionCount() -> UInt64 {
        transitionCount
    }

    func playbackEnded() -> Bool {
        endedFlag
    }
}
