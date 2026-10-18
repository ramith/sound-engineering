@testable import AdaptiveSound
import AudioFormatKit
@preconcurrency import AVFoundation
import Foundation
import PlaybackQueueKit
import Synchronization
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
    /// Further fixture files a test wrote (`writeTrack`), removed with the track by `finish`.
    private var fixtures: [URL] = []

    /// Build the graph, write `tones` (Hz, equal levels summing to `toneAmplitude`) at `rate` (default:
    /// `path`'s) — `frames` long (default `toneSeconds`) — and play the file from the top.
    init(path: SubPath, name: String, tones: [Double] = [440], frames: Int? = nil, rate: Double? = nil) async throws {
        try #require(stall.buildGraph(slowUnit: false), "the real graph did not build offline")
        let fileRate = rate ?? path.fileRate
        let length = frames ?? Int(Self.toneSeconds * fileRate)
        url = try Self.writeTones(tones, named: "\(name)-\(path.rawValue)", rate: fileRate, frames: 0 ..< length)
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
        samples(frames: Int(seconds * Self.graphRate))
    }

    /// Pull exactly `frames` of output in blocks of at most 512 and return its left channel (`nil`:
    /// the render failed). `paced`: each block takes as long as it lasts, as a device pulls it, so
    /// the completion-driven chain runs on a device's time — what a seam's timing depends on.
    func samples(frames total: Int, paced: Bool = false) -> [Float]? {
        guard let engine = bridge.avEngineRef,
              let buffer = AVAudioPCMBuffer(pcmFormat: engine.manualRenderingFormat, frameCapacity: 512)
        else { return nil }
        var left: [Float] = []
        left.reserveCapacity(total)
        while left.count < total {
            let frames = AVAudioFrameCount(min(512, total - left.count))
            guard (try? engine.renderOffline(frames, to: buffer)) == .success,
                  let channel = buffer.floatChannelData?[0] else { return nil }
            left += UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength))
            if paced {
                Thread.sleep(forTimeInterval: Double(frames) / Self.graphRate)
            }
            bridge.resampleQueue.sync {}
        }
        return left
    }

    /// Record what the player itself plays from now on — the bridge's schedule, before the effects
    /// chain — through a tap on its output. Call before the first render: the recording then starts
    /// at the player's first frame.
    func recordPlayer() throws -> PlayerRecording {
        let player = try #require(bridge.playerNodeRef)
        let recording = PlayerRecording()
        player.installTap(onBus: 0, bufferSize: 4800, format: player.outputFormat(forBus: 0)) { buffer, _ in
            recording.append(buffer)
        }
        return recording
    }

    /// The left channel of what the player played (`recordPlayer`). AVFAudio hands a tap its frames
    /// off the render, in whole tap buffers, so a read waits for them.
    final class PlayerRecording: Sendable {
        private let left = Mutex<[Float]>([])

        func append(_ buffer: AVAudioPCMBuffer) {
            guard let channel = buffer.floatChannelData?[0] else { return }
            let frames = UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength))
            left.withLock { $0 += frames }
        }

        /// The first `frames` frames, once delivered (`nil`: not within two seconds).
        func samples(frames: Int) -> [Float]? {
            for _ in 0 ..< 200 {
                let recorded = left.withLock { $0.count >= frames ? Array($0[..<frames]) : nil }
                if let recorded {
                    return recorded
                }
                Thread.sleep(forTimeInterval: 0.01)
            }
            return nil
        }
    }

    /// Pull output in paced 512-frame blocks until `condition` holds after a block, at most `limit`
    /// frames. Returns how many frames had been pulled when it first held (`nil`: it never did, or the
    /// render failed). The condition is read after the block's completions had their time to land.
    func frames(until condition: () -> Bool, limit: Int) -> Int? {
        var pulled = 0
        while pulled < limit {
            guard samples(frames: 512, paced: true) != nil else { return nil }
            pulled += 512
            if condition() {
                return pulled
            }
        }
        return nil
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
        for fixture in fixtures {
            try? FileManager.default.removeItem(at: fixture)
        }
    }

    // MARK: - Fixture

    /// Play `frames` of the tone program at `rate` (the resampler sub-path unless it is the graph's
    /// rate), with the program's next `nextFrames` — so the two join into one sound — on deck as
    /// another track.
    static func playing(_ tones: [Double], rate: Double, frames: Int, thenNext nextFrames: Int,
                        name: String) async throws -> EnhancedTransportRig {
        let rig = try await EnhancedTransportRig(path: rate == graphRate ? .passthrough : .resampler, name: name,
                                                 tones: tones, frames: frames, rate: rate)
        let next = try rig.writeTrack(tones, named: "\(name)-next", rate: rate, frames: frames ..< frames + nextFrames)
        await rig.bridge.setNextTrack(next, ticket: OnDeckTicket(session: 0, sequence: 1))
        return rig
    }

    /// ONE conversion of `frames` frames of the tone program at `rate` from frame `first` to the
    /// graph's rate — the production converter in the production chunks, then its flush: what the
    /// player plays for that stretch of a resampled program.
    static func oneConversion(_ tones: [Double], rate: Double, frames: Int, from first: Int = 0) throws -> [Float] {
        let input = try #require(AVAudioFormat(standardFormatWithSampleRate: rate, channels: 2))
        let output = try #require(AVAudioFormat(standardFormatWithSampleRate: graphRate, channels: 2))
        let resampler = try #require(StreamingResampler(from: input, to: output))
        let chunk = Int(StreamingResampler.inputChunkFrames)
        var converted: [Float] = []
        var start = 0
        for _ in 0 ... frames / chunk + 2 {
            let count = min(chunk, frames - start)
            let buffer = try #require(AVAudioPCMBuffer(pcmFormat: input, frameCapacity: AVAudioFrameCount(chunk)))
            buffer.frameLength = AVAudioFrameCount(count)
            let data = try #require(buffer.floatChannelData)
            for index in 0 ..< count {
                let sample = toneSample(tones, frame: first + start + index, rate: rate)
                data[0][index] = sample
                data[1][index] = sample
            }
            start += count
            let result = try resampler.convert(buffer, inputEnded: count == 0)
            let left = try #require(result.buffer.floatChannelData)
            converted += UnsafeBufferPointer(start: left[0], count: Int(result.buffer.frameLength))
            if result.endOfStream {
                return converted
            }
        }
        Issue.record("the converter never reported the end of its stream")
        return converted
    }

    /// Write another track (removed by `finish`): `frames` of the same tone program at `rate`, on
    /// `channels` channels — `frames` starting where the playing track ends continues its sound.
    func writeTrack(_ tones: [Double], named name: String, rate: Double, frames: Range<Int>,
                    channels: AVAudioChannelCount = 2) throws -> URL {
        let track = try Self.writeTones(tones, named: name, rate: rate, frames: frames, channels: channels)
        fixtures.append(track)
        return track
    }

    /// Frame `frame` of the tone program at `rate`: `tones` (Hz) at equal levels summing to
    /// `toneAmplitude`, every one starting at phase 0 at frame 0 — so consecutive frame ranges
    /// written as separate files join into one continuous sound.
    static func toneSample(_ tones: [Double], frame: Int, rate: Double) -> Float {
        let level = Double(toneAmplitude) / Double(max(tones.count, 1))
        let time = Double(frame) / rate
        return Float(tones.reduce(0) { $0 + level * sin(2 * Double.pi * $1 * time) })
    }

    /// `frames` of the tone program (`toneSample`) as 32-bit float PCM at `rate` on `channels`
    /// channels, in test-data/.
    private static func writeTones(_ tones: [Double], named name: String, rate: Double, frames: Range<Int>,
                                   channels: AVAudioChannelCount = 2) throws -> URL {
        let directory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // AdaptiveSoundTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // the repository
            .appendingPathComponent("test-data/enhanced-transport", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("\(name)-\(UUID().uuidString).wav")
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: rate, AVNumberOfChannelsKey: channels,
            AVLinearPCMBitDepthKey: 32, AVLinearPCMIsFloatKey: true, AVLinearPCMIsBigEndianKey: false,
        ]
        let file = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32,
                                   interleaved: false)
        let count = AVAudioFrameCount(frames.count)
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: count))
        buffer.frameLength = count
        let data = try #require(buffer.floatChannelData)
        for (index, frame) in frames.enumerated() {
            let sample = toneSample(tones, frame: frame, rate: rate)
            for channel in 0 ..< Int(channels) {
                data[channel][index] = sample
            }
        }
        try file.write(from: buffer)
        return url
    }
}
