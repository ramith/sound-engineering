@testable import AdaptiveSound
@preconcurrency import AVFoundation
import Foundation
import PlaybackQueueKit
import Testing

// MARK: - The real Enhanced path on an offline engine, for the transport tests

/// The REAL `AudioEngineBridge` — its graph with the real effects and spatial AUs (`StallRig`, the
/// `make main-thread-stall` rig) — on an AVAudioEngine in OFFLINE manual-rendering mode: no device
/// is opened, nothing is heard. A test plays a generated tone file through the bridge's own start
/// (`playFile`), seeks through its own entry (`seek(to:epoch:)`), and pulls the render itself, so
/// what it reads — the transport snapshot the view model reads, the playhead, the rendered samples
/// — is what the production code did. The CoreAudio HAL is never touched: the device-facing part of
/// a start (`startAudio` → `alignOutputForEnhancedStart`) is the one step left out.
final class EnhancedTransportRig: @unchecked Sendable {
    /// The two Enhanced sub-paths. A file at the graph's rate (48 kHz) is scheduled straight onto the
    /// player; any other rate streams through the resampler.
    enum SubPath: String, CaseIterable, Sendable, CustomTestStringConvertible {
        case passthrough
        case resampler

        var fileRate: Double {
            self == .passthrough ? 48000 : 44100
        }

        var testDescription: String {
            rawValue
        }
    }

    static let graphRate = 48000.0
    /// The fixture's length: long enough that every test stays inside the resampler's primed lead
    /// (three 8192-frame chunks ≈ 0.56 s) after each seek, so no check waits on the completion chain.
    static let toneSeconds = 2.0
    /// The fixture's level (−12 dBFS), well above the silence threshold after the DSP.
    static let toneAmplitude: Float = 0.25
    /// A rendered peak below this is silence (the DSP's tails decay far below it).
    static let silence: Float = 1e-4

    let stall = StallRig()
    var bridge: AudioEngineBridge {
        stall.bridge
    }

    let url: URL
    /// The track's length as the view model computes it (`refreshDuration`: frames / rate).
    let duration: Double
    private var nextEpoch: UInt64 = 0

    /// Build the graph, write `tones` (Hz, equal levels summing to `toneAmplitude`) at `path`'s
    /// rate, and play the file from the top.
    init(path: SubPath, name: String, tones: [Double] = [440]) async throws {
        try #require(stall.buildGraph(slowUnit: false), "the real graph did not build offline")
        url = try Self.writeTones(tones, named: "\(name)-\(path.rawValue)", rate: path.fileRate)
        let file = try AVAudioFile(forReading: url)
        duration = Double(file.length) / file.processingFormat.sampleRate
        try await play()
    }

    // MARK: - Driving the bridge

    /// Start the file through the bridge's own start (`playFile`) on `engineQueue`, as `startAudio`
    /// does after its device step: the engine runs, the URL and the play intent are recorded.
    private func play() async throws {
        let bridge = bridge
        let url = url
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            bridge.engineQueue.async {
                do {
                    guard let engine = bridge.avEngineRef, let player = bridge.playerNodeRef else {
                        throw AudioBridgeError.engineNotInitialized
                    }
                    if !engine.isRunning {
                        try engine.start()
                    }
                    bridge.setLastFileURL(url)
                    try bridge.playFile(at: url, engine: engine, playerNode: player, startAt: 0)
                    bridge.enhancedPlayIntent = true
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Seek through the bridge's own entry, numbered as the view model numbers it. Returns the
    /// error the seek threw (`nil`: it did not throw) and the request's epoch.
    @discardableResult
    func seek(to seconds: Double) async -> (error: Error?, epoch: UInt64) {
        nextEpoch += 1
        let epoch = nextEpoch
        do {
            try await bridge.seek(to: seconds, epoch: epoch)
            return (nil, epoch)
        } catch {
            return (error, epoch)
        }
    }

    /// The transport as the view model reads it.
    var transport: TransportSnapshot {
        bridge.snapshot().transport
    }

    /// The live Enhanced playhead (the clock's read), off the main thread.
    var position: Double? {
        bridge.liveEnhancedPosition()
    }

    /// Pull `seconds` of output, the device stand-in, and return its left channel (`nil`: the render
    /// failed). The resampler's queue is drained after every block, so its chain keeps up.
    func samples(seconds: Double) -> [Float]? {
        guard let engine = bridge.avEngineRef,
              let buffer = AVAudioPCMBuffer(pcmFormat: engine.manualRenderingFormat, frameCapacity: 512)
        else { return nil }
        let total = Int(seconds * Self.graphRate)
        var left: [Float] = []
        left.reserveCapacity(total)
        while left.count < total {
            let frames = AVAudioFrameCount(min(512, total - left.count))
            guard (try? engine.renderOffline(frames, to: buffer)) == .success,
                  let channel = buffer.floatChannelData?[0] else { return nil }
            left += UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength))
            bridge.resampleQueue.sync {}
        }
        return left
    }

    /// Pull `seconds` of output and return its peak after the first `skipping` seconds (the DSP's
    /// look-ahead and tails), or `nil` when the render failed.
    func render(seconds: Double, skipping: Double = 0) -> Float? {
        guard let left = samples(seconds: seconds) else { return nil }
        let skip = min(Int(skipping * Self.graphRate), left.count)
        return left[skip...].reduce(0) { max($0, abs($1)) }
    }

    /// Stop the bridge and remove the fixture.
    func finish() async {
        try? await bridge.shutdown()
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - Fixture

    /// Stereo `tones` (equal levels, summing to `toneAmplitude`), `toneSeconds` long, as 32-bit float
    /// PCM at `rate`, in test-data/.
    private static func writeTones(_ tones: [Double], named name: String, rate: Double) throws -> URL {
        let directory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // AdaptiveSoundTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // the repository
            .appendingPathComponent("test-data/enhanced-transport", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("\(name)-\(UUID().uuidString).wav")
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: rate, AVNumberOfChannelsKey: 2,
            AVLinearPCMBitDepthKey: 32, AVLinearPCMIsFloatKey: true, AVLinearPCMIsBigEndianKey: false,
        ]
        let file = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32,
                                   interleaved: false)
        let frames = AVAudioFrameCount(toneSeconds * rate)
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: frames))
        buffer.frameLength = frames
        let channels = try #require(buffer.floatChannelData)
        let level = Double(toneAmplitude) / Double(max(tones.count, 1))
        for frame in 0 ..< Int(frames) {
            let time = Double(frame) / rate
            let sample = Float(tones.reduce(0) { $0 + level * sin(2 * Double.pi * $1 * time) })
            channels[0][frame] = sample
            channels[1][frame] = sample
        }
        try file.write(from: buffer)
        return url
    }
}
