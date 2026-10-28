@testable import AdaptiveSound
import AudioDSP
@preconcurrency import AVFoundation
import Foundation
import RigKit
import Testing

// MARK: - F1: a multichannel source keeps every channel in its own slot, at any rate (R1.1-B)

//
// The level-and-fold design's F1 (docs/design/level-and-fold/README.md §2, §8½ C1, §10): on the Enhanced
// path a file of 3 or more channels used to be re-laid into a graph format derived from its channel COUNT —
// 6 → MPEG 5.1 A, 8 → MPEG 7.1 A, anything else → stereo. So a 44.1 kHz AAC / ALAC 5.1 file (C L R Ls Rs
// LFE) came out reordered, a WAVE 7.1 file lost its back pair, and 3-, 4-, 5- and 7-channel files played
// only L and R. Now the graph carries the file's OWN layout, so each source channel arrives in its own
// slot (the converter changes the rate only), and the roles read from the file's labels name the right
// slot. Mono and stereo keep today's formats, and a device narrower than the file (but more than mono)
// folds to stereo rather than keep the first M channels.
//
// Each case plays a generated CAF — one tone per channel, at the layout and rate under test — through the
// REAL bridge's start (`playFile`) on an offline engine whose device has as many channels as the case
// needs, and reads every rendered channel: channel k's tone must arrive in slot k at its level (±0.05 dB)
// and every other channel's tone must stay out of it (< −80 dB).

@Suite("F1 — a multichannel source plays each channel in its own slot", .serialized, .timeLimit(.minutes(5)))
struct MultichannelSourceTests {
    /// A channel layout to write the fixture in: a CoreAudio tag, or per-channel labels (the 7.0 FLAC
    /// in the corpus arrives that way, tag 0).
    enum Layout: Sendable {
        case tag(AudioChannelLayoutTag)
        case labels([AudioChannelLabel])

        var channelLayout: AVAudioChannelLayout? {
            switch self {
            case let .tag(tag):
                AVAudioChannelLayout(layoutTag: tag)
            case let .labels(labels):
                MultichannelFixture.describedLayout(labels)
            }
        }
    }

    /// One source under test.
    struct Source: Sendable, CustomTestStringConvertible {
        let name: String
        let layout: Layout
        let rate: Double

        var testDescription: String {
            name
        }
    }

    static let sources: [Source] = [
        Source(name: "AAC 5.1 (C L R Ls Rs LFE) at 44.1 kHz", layout: .tag(kAudioChannelLayoutTag_AAC_5_1),
               rate: 44100),
        Source(name: "AAC 5.1 at 48 kHz (no resampler)", layout: .tag(kAudioChannelLayoutTag_AAC_5_1), rate: 48000),
        Source(name: "WAVE 7.1 (L R C LFE Rls Rrs Ls Rs) at 44.1 kHz", layout: .tag(kAudioChannelLayoutTag_WAVE_7_1),
               rate: 44100),
        Source(name: "MPEG 7.1 C at 96 kHz", layout: .tag(kAudioChannelLayoutTag_MPEG_7_1_C), rate: 96000),
        Source(name: "3.0 (L R C) at 44.1 kHz", layout: .tag(kAudioChannelLayoutTag_MPEG_3_0_A), rate: 44100),
        Source(name: "quad (L R Rls Rrs) at 44.1 kHz", layout: .tag(kAudioChannelLayoutTag_WAVE_4_0_B), rate: 44100),
        Source(name: "WAVE 5.0 B (L R C Rls Rrs) at 88.2 kHz", layout: .tag(kAudioChannelLayoutTag_WAVE_5_0_B),
               rate: 88200),
        Source(name: "7.0 by per-channel labels at 44.1 kHz", layout: .labels([
            kAudioChannelLabel_Left, kAudioChannelLabel_Right, kAudioChannelLabel_Center,
            kAudioChannelLabel_RearSurroundLeft, kAudioChannelLabel_RearSurroundRight,
            kAudioChannelLabel_LeftSurround, kAudioChannelLabel_RightSurround,
        ]), rate: 44100),
        Source(name: "5 unlabelled channels at 96 kHz", layout: .tag(kAudioChannelLayoutTag_DiscreteInOrder | 5),
               rate: 96000),
        Source(name: "8 unlabelled channels at 48 kHz", layout: .tag(kAudioChannelLayoutTag_DiscreteInOrder | 8),
               rate: 48000),
    ]

    @Test("F1-1: every channel arrives in its own slot at its level; no other channel leaks in", arguments: sources)
    func everyChannelInItsOwnSlot(source: Source) async throws {
        let layout = try #require(source.layout.channelLayout, "the layout builds")
        let channels = Int(layout.channelCount)
        let rig = try await MultichannelDeviceRig.make(deviceChannels: 8)
        let url = try MultichannelFixture.write(layout: layout, rate: source.rate, name: "f1-slot")
        defer { try? FileManager.default.removeItem(at: url) }
        try await rig.play(url)
        let output = try await rig.render(frames: MultichannelFixture.renderFrames)

        #expect(output.count == channels, "the device renders the file's \(channels) channels (got \(output.count))")
        for slot in 0 ..< min(output.count, channels) {
            let window = output[slot][MultichannelFixture.window]
            let own = MultichannelFixture.toneAmplitude(window, frequency: MultichannelFixture.toneHz(slot))
            let ownDb = 20 * log10(own / Double(MultichannelFixture.level))
            #expect(abs(ownDb) <= 0.05, "slot \(slot) plays its own channel at \(ownDb) dB")
            for other in 0 ..< channels where other != slot {
                let leak = MultichannelFixture.toneAmplitude(window, frequency: MultichannelFixture.toneHz(other))
                let leakDb = 20 * log10(max(leak, 1e-12) / Double(MultichannelFixture.level))
                #expect(leakDb < -80, "channel \(other) leaks into slot \(slot) at \(leakDb) dB")
            }
        }
        await rig.finish()
    }

    @Test("F1-2: mono and stereo keep today's graph formats (C1)", arguments: [1, 2] as [AVAudioChannelCount])
    func monoAndStereoKeepTodaysFormats(channels: AVAudioChannelCount) async throws {
        let rig = try await MultichannelDeviceRig.make(deviceChannels: 8)
        let layout = try #require(AVAudioChannelLayout(layoutTag: channels == 1 ? kAudioChannelLayoutTag_Mono
                : kAudioChannelLayoutTag_Stereo))
        let url = try MultichannelFixture.write(layout: layout, rate: 44100, name: "f1-narrow")
        defer { try? FileManager.default.removeItem(at: url) }
        try await rig.play(url)

        let today = try #require(AVAudioFormat(standardFormatWithSampleRate: MultichannelDeviceRig.graphRate,
                                               channels: channels))
        let graph = try #require(rig.bridge.playerNodeRef).outputFormat(forBus: 0)
        #expect(graph == today, "the graph plays \(channels) channel(s) at today's format (got \(graph))")
        await rig.finish()
    }

    @Test("F1-3: a 7.1 file on a 6-channel device folds to stereo, never keeps the first six (C1)")
    func narrowerDeviceFoldsToStereo() async throws {
        let rig = try await MultichannelDeviceRig.make(deviceChannels: 6)
        let layout = try #require(AVAudioChannelLayout(layoutTag: kAudioChannelLayoutTag_WAVE_7_1))
        let url = try MultichannelFixture.write(layout: layout, rate: 48000, name: "f1-fold")
        defer { try? FileManager.default.removeItem(at: url) }
        try await rig.play(url)

        let spatial = try #require(rig.bridge.spatialNode)
        #expect(spatial.inputFormat(forBus: 0).channelCount == 8, "the spatial unit takes all 8 channels")
        #expect(spatial.outputFormat(forBus: 0).channelCount == 2, "and renders the device boundary in stereo")
        await rig.finish()
    }

    @Test("S2: the snapshot reports the fold the spatial unit plays — and none when nothing folds")
    func snapshotReportsTheFold() async throws {
        let rig = try await MultichannelDeviceRig.make(deviceChannels: 2)
        let surround = try #require(AVAudioChannelLayout(layoutTag: kAudioChannelLayoutTag_WAVE_7_1))
        let folded = try MultichannelFixture.write(layout: surround, rate: 48000, name: "s2-fold")
        defer { try? FileManager.default.removeItem(at: folded) }
        try await rig.play(folded)
        let fold = try #require(rig.bridge.snapshot().signalPath.fold, "a 7.1 file on a stereo device folds")
        #expect(fold.sourceChannels == 8 && fold.outputChannels == 2)
        #expect(fold.trimDb <= 0 && fold.backstopPeakGrDb >= 0)

        let stereoLayout = try #require(AVAudioChannelLayout(layoutTag: kAudioChannelLayoutTag_Stereo))
        let stereo = try MultichannelFixture.write(layout: stereoLayout, rate: 48000, name: "s2-stereo")
        defer { try? FileManager.default.removeItem(at: stereo) }
        try await rig.play(stereo)
        #expect(rig.bridge.snapshot().signalPath.fold == nil, "a stereo file on a stereo device does not fold")
        await rig.finish()
    }
}

// MARK: - The fixture: one tone per channel

enum MultichannelFixture {
    /// Per-channel level (−20 dBFS): far below the safety limiter, so the chain plays it untouched.
    static let level: Float = 0.1
    /// The rendered stretch the tests read, and the window measured in it: past the start (the converter's
    /// hold-back, the effects unit's look-ahead), 0.4 s long — a whole number of cycles of every tone, so
    /// one DFT bin reads each tone with no leakage from the others.
    static let renderFrames = 24000
    static let window = 4800 ..< 24000
    /// The fixture's length in seconds (longer than the render, so the tones are steady throughout).
    static let seconds = 0.75

    /// Channel `channel`'s tone: 300, 500, … 1700 Hz — multiples of 100 Hz, whole cycles in `window`.
    static func toneHz(_ channel: Int) -> Double {
        300 + 200 * Double(channel)
    }

    /// Amplitude of the tone at `frequency` in `samples` at 48 kHz: one DFT bin over the slice. Exact for a
    /// steady tone that completes whole cycles in it; zero for every other such tone.
    static func toneAmplitude(_ samples: ArraySlice<Float>, frequency: Double) -> Double {
        var real = 0.0, imaginary = 0.0
        for (index, sample) in samples.enumerated() {
            let phase = 2 * Double.pi * frequency * Double(index) / MultichannelDeviceRig.graphRate
            real += Double(sample) * cos(phase)
            imaginary -= Double(sample) * sin(phase)
        }
        return 2 * (real * real + imaginary * imaginary).squareRoot() / Double(samples.count)
    }

    /// A layout given by per-channel labels (tag `UseChannelDescriptions`).
    static func describedLayout(_ labels: [AudioChannelLabel]) -> AVAudioChannelLayout? {
        guard !labels.isEmpty else { return nil }
        let size = MemoryLayout<AudioChannelLayout>.size
            + (labels.count - 1) * MemoryLayout<AudioChannelDescription>.stride
        let raw = UnsafeMutableRawPointer.allocate(byteCount: size,
                                                   alignment: MemoryLayout<AudioChannelLayout>.alignment)
        defer { raw.deallocate() }
        raw.initializeMemory(as: UInt8.self, repeating: 0, count: size)
        let layout = raw.bindMemory(to: AudioChannelLayout.self, capacity: 1)
        layout.pointee.mChannelLayoutTag = kAudioChannelLayoutTag_UseChannelDescriptions
        layout.pointee.mNumberChannelDescriptions = UInt32(labels.count)
        let descriptions = channelDescriptions(of: layout)
        for (index, label) in labels.enumerated() {
            descriptions[index] = AudioChannelDescription(mChannelLabel: label, mChannelFlags: [],
                                                          mCoordinates: (0, 0, 0))
        }
        return AVAudioChannelLayout(layout: layout)
    }

    /// The descriptions that follow an `AudioChannelLayout` header (a C flexible array).
    private static func channelDescriptions(
        of layout: UnsafeMutablePointer<AudioChannelLayout>
    ) -> UnsafeMutablePointer<AudioChannelDescription> {
        UnsafeMutableRawPointer(layout)
            .advanced(by: MemoryLayout<AudioChannelLayout>.offset(of: \.mChannelDescriptions) ?? 0)
            .assumingMemoryBound(to: AudioChannelDescription.self)
    }

    /// Write `seconds` of one tone per channel (`toneHz`, at `level`) as 32-bit float CAF in `layout` at
    /// `rate`, in test-data/ (CAF keeps any layout: a tag, descriptions or discrete).
    static func write(layout: AVAudioChannelLayout, rate: Double, name: String) throws -> URL {
        let directory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // AdaptiveSoundTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // the repository
            .appendingPathComponent("test-data/multichannel-source", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("\(name)-\(UUID().uuidString).caf")
        let format = AVAudioFormat(standardFormatWithSampleRate: rate, channelLayout: layout)
        let file = try AVAudioFile(forWriting: url, settings: format.settings, commonFormat: .pcmFormatFloat32,
                                   interleaved: false)
        let frames = AVAudioFrameCount(seconds * rate)
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: frames))
        buffer.frameLength = frames
        let data = try #require(buffer.floatChannelData)
        for channel in 0 ..< Int(layout.channelCount) {
            let step = 2 * Double.pi * toneHz(channel) / rate
            for frame in 0 ..< Int(frames) {
                data[channel][frame] = level * Float(sin(step * Double(frame)))
            }
        }
        try file.write(from: buffer)
        return url
    }
}

// MARK: - The real bridge on an offline device of any width

/// The REAL `AudioEngineBridge` — its two-AU graph built by its own `instantiateAndBuildGraph`, at the
/// app's stereo start — on an AVAudioEngine in OFFLINE manual rendering whose output (the device stand-in)
/// has `deviceChannels` channels. Nothing is heard. A file plays through the bridge's own start
/// (`playFile`: the graph re-formats to the source, the resampler or the passthrough route); the render is
/// pulled in lock-step with the completion chain (`StreamLedger`), so a resampled stream never runs dry.
final class MultichannelDeviceRig: @unchecked Sendable {
    static let graphRate = 48000.0

    let bridge = AudioEngineBridge()
    private let ledger = StreamLedger()
    private var renderEpoch = 0
    private var rendered: Int64 = 0

    private init() {}

    static func make(deviceChannels: AVAudioChannelCount) async throws -> MultichannelDeviceRig {
        QuietLog.install()
        registerAdaptiveAudioUnitSubclass()
        registerSpatialRendererAUSubclass()
        let rig = MultichannelDeviceRig()
        rig.bridge.streamObserver.withLock { [ledger = rig.ledger] in $0 = ledger }
        let device = try #require(deviceChannels <= 2
            ? AVAudioFormat(standardFormatWithSampleRate: graphRate, channels: deviceChannels)
            : AVAudioChannelLayout(layoutTag: kAudioChannelLayoutTag_DiscreteInOrder | deviceChannels)
            .map { AVAudioFormat(standardFormatWithSampleRate: graphRate, channelLayout: $0) })
        let bridge = rig.bridge
        let built: Bool = await withCheckedContinuation { continuation in
            bridge.engineQueue.async {
                let engine = AVAudioEngine()
                guard let stereo = AVAudioFormat(standardFormatWithSampleRate: graphRate, channels: 2),
                      (try? engine.enableManualRenderingMode(.offline, format: device, maximumFrameCount: 4096)) != nil
                else {
                    continuation.resume(returning: false)
                    return
                }
                bridge.setAvEngine(engine)
                let player = AVAudioPlayerNode()
                bridge.setPlayerNode(player)
                engine.attach(player)
                bridge.instantiateAndBuildGraph(engine: engine, player: player, format: stereo) { built in
                    continuation.resume(returning: built)
                }
            }
        }
        try #require(built, "the real graph did not build offline")
        return rig
    }

    /// Start `url` through the bridge's own start (`playFile`) on `engineQueue`, as `startAudio` does
    /// after its device step.
    func play(_ url: URL) async throws {
        let bridge = bridge
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

    /// Pull exactly `frames` frames of every rendered channel, 512 at a time, each block in lock-step with
    /// the completion chain (the transport rig's rule, R4). Runs on a thread of its own.
    func render(frames total: Int) async throws -> [[Float]] {
        try await blocking("render") { try self.renderLockStep(frames: total) }
    }

    private func renderLockStep(frames total: Int) throws -> [[Float]] {
        let engine = try #require(bridge.avEngineRef)
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: engine.manualRenderingFormat, frameCapacity: 512))
        var output = [[Float]](repeating: [], count: Int(engine.manualRenderingFormat.channelCount))
        var pulled = 0
        while pulled < total {
            if ledger.epoch != renderEpoch { // the start superseded the schedule: its clock starts at 0
                renderEpoch = ledger.epoch
                rendered = 0
            }
            let frames = AVAudioFrameCount(min(512, total - pulled))
            try #require(try engine.renderOffline(frames, to: buffer) == .success, "the render failed")
            let data = try #require(buffer.floatChannelData)
            for channel in output.indices {
                output[channel] += UnsafeBufferPointer(start: data[channel], count: Int(buffer.frameLength))
            }
            pulled += Int(buffer.frameLength)
            rendered += Int64(buffer.frameLength)
            let renderedSoFar = rendered
            try untilBlocking("the completions due after \(renderedSoFar) rendered frames to be handed on") {
                ledger.undelivered(dueBy: renderedSoFar) == 0
            }
            bridge.resampleQueue.sync {}
            bridge.resampleQueue.sync {}
        }
        return output
    }

    func finish() async {
        try? await bridge.shutdown()
    }
}
