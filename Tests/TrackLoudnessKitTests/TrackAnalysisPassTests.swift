// PASS — the one analysis pass end to end (R1.1-B, level-and-fold §1.2): a real file through AVAudioFile, the
// Enhanced path's Mastering converter into F1's format at 48 kHz, and the C++ analyzer; the Codable mirror; the
// prefix before the SRC; cancellation and refusals. Fixtures are written at run time into test-data/.

import AudioDSP
import AVFoundation
import Foundation
import Testing
@testable import TrackLoudnessKit

@Suite("TrackAnalysisPass — decode once, measure at the engine rate", .timeLimit(.minutes(5)))
struct TrackAnalysisPassTests {
    @Test("PASS-01: a stereo track — L, TP, blocks, histogram, persisted profile; the mirror round-trips")
    func stereo() throws {
        let url = try ToneFixtures.write(named: "pass-stereo", rate: 48000, channels: 2, seconds: 6) { _, _ in 0.1 }
        let analysis = try Self.analyse(url)
        #expect(analysis.version == Int(AS_TRACK_ANALYSIS_VERSION))
        #expect(analysis.roles == [UInt8(AsChannelRoleL.rawValue), UInt8(AsChannelRoleR.rawValue)])
        #expect(analysis.sourceRateHz == 48000 && analysis.peakRateHz == 48000)
        #expect(abs(analysis.durationSeconds - 6) < 0.001)
        // A stereo 997 Hz tone of amplitude A reads 20·log10(A) LUFS; its true peak is A.
        #expect(abs((analysis.integratedLufs ?? .nan) + 20) < 0.02)
        #expect(abs((analysis.truePeakDbtp ?? .nan) + 20) < 0.05)
        #expect(!analysis.folds && analysis.foldedLufs.allSatisfy { $0 == nil })
        #expect(!analysis.histograms[0].isEmpty && analysis.histograms[1].isEmpty)
        let profile = try #require(analysis.profiles[0])
        #expect(profile.bandsPerOctave == 24 && profile.powers.count == profile.blockCount * profile.bandCount)
        #expect(analysis.profiles[1] == nil)
        let decoded = try JSONDecoder().decode(TrackAnalysis.self, from: JSONEncoder().encode(analysis))
        #expect(decoded == analysis)
    }

    @Test("PASS-02: a 44.1 kHz source is measured after the SRC, at 48 kHz, as its 48 kHz twin")
    func resampled() throws {
        let tone: (Int, Int) -> Float = { _, _ in 0.2 }
        let native = try Self.analyse(ToneFixtures.write(named: "pass-48k", rate: 48000, channels: 2, seconds: 5,
                                                         level: tone))
        let converted = try Self.analyse(ToneFixtures.write(named: "pass-44k", rate: 44100, channels: 2, seconds: 5,
                                                            level: tone))
        #expect(converted.sourceRateHz == 44100 && converted.peakRateHz == 48000)
        #expect(abs((converted.integratedLufs ?? .nan) - (native.integratedLufs ?? .nan)) < 0.01)
        #expect(abs((converted.truePeakDbtp ?? .nan) - (native.truePeakDbtp ?? .nan)) < 0.05)
        #expect(abs(converted.durationSeconds - 5) < 0.01)
    }

    @Test("PASS-03: a label-less 6-channel 44.1 kHz WAV keeps every slot through the SRC (WAV-order roles)")
    func channelIdentityThroughTheConverter() throws {
        // A tone in slot 4 only: by the count fallback it is the lone back pair's left (Lb), the surround:
        // BS.1770 weighs it 1.41 (+1.5 dB), and the fold sends it to L′ only at 0.7071 (−3 dB, one side).
        let url = try ToneFixtures.write(named: "pass-6ch", rate: 44100, channels: 6, seconds: 5) { channel, _ in
            channel == 4 ? 0.1 : 0
        }
        let analysis = try Self.analyse(url)
        let wav51: [AsChannelRole] = [AsChannelRoleL, AsChannelRoleR, AsChannelRoleC, AsChannelRoleLfe,
                                      AsChannelRoleLb, AsChannelRoleRb]
        #expect(analysis.roles == wav51.map { UInt8($0.rawValue) })
        let decoded = try #require(analysis.integratedLufs)
        let folded = try #require(analysis.foldedLufs[0])
        #expect(abs(decoded - (-20 - 3.01 + 1.5)) < 0.05) // one channel of a tone at A: 20·log10(A) − 3.01, +1.5
        #expect(abs((decoded - folded) - (1.5 + 3.01)) < 0.05) // the surround weight, and the fold's −3 dB
        #expect(analysis.folds && analysis.foldedLufs.allSatisfy { $0 == analysis.foldedLufs[0] })
        #expect(analysis.profiles.allSatisfy { $0 != nil })
    }

    @Test("PASS-04: with the profiler, the prefix comes first — before the SRC — then the whole profile")
    func prefixBeforeTheConverter() throws {
        let url = try ToneFixtures.write(named: "pass-prefix", rate: 44100, channels: 2, seconds: 8) { _, _ in 0.1 }
        let identity = try #require(TrackIdentity(url: url))
        var prefixes: [Double] = []
        let outcome = TrackAnalysisPass.analyse(url, identity: identity, profile: true, prefixSeconds: 2,
                                                onPrefix: { prefixes.append($0.info.analysedSeconds) })
        guard case let .analysed(analysis, whole) = outcome else {
            Issue.record("not analysed: \(outcome)")
            return
        }
        #expect(prefixes.count == 1 && (prefixes.first ?? 0) < 3)
        let profile = try #require(whole)
        #expect(profile.info.wholeTrack && profile.info.sampleRate == 44100) // today's profile: the source rate
        #expect(analysis.peakRateHz == 48000)
    }

    @Test("PASS-05: cancelled, unreadable, wider than the engine — no analysis")
    func refusals() throws {
        let url = try ToneFixtures.write(named: "pass-cancel", rate: 48000, channels: 2, seconds: 3) { _, _ in 0.1 }
        let identity = try #require(TrackIdentity(url: url))
        guard case .cancelled = TrackAnalysisPass.analyse(url, identity: identity, isCancelled: { true }) else {
            Issue.record("a cancelled pass reported something else")
            return
        }
        let garbage = try Fixtures.garbage(named: "pass-garbage")
        let garbageIdentity = try #require(TrackIdentity(url: garbage))
        guard case .failed = TrackAnalysisPass.analyse(garbage, identity: garbageIdentity) else {
            Issue.record("an unreadable file was analysed")
            return
        }
        let wide = try ToneFixtures.write(named: "pass-10ch", rate: 48000, channels: 10, seconds: 1) { _, _ in 0.1 }
        let wideIdentity = try #require(TrackIdentity(url: wide))
        guard case let .failed(reason) = TrackAnalysisPass.analyse(wide, identity: wideIdentity) else {
            Issue.record("a 10-channel file was analysed")
            return
        }
        #expect(reason.contains("wider"))
    }

    @Test("PASS-08: an album's pooled loudness gates over every member's blocks (−20 and −40 LUFS pool to −20)")
    func pooled() throws {
        let loud = try Self.analyse(ToneFixtures.write(named: "pass-pool-loud", rate: 48000, channels: 2, seconds: 4,
                                                       level: { _, _ in 0.1 }))
        let quiet = try Self.analyse(ToneFixtures.write(named: "pass-pool-quiet", rate: 48000, channels: 2, seconds: 4,
                                                        level: { _, _ in 0.01 }))
        // The absolute-gated mean is ≈ −23 LUFS, so the relative gate (−33) drops the −40 LUFS track's blocks.
        #expect(abs((TrackAnalysis.pooledLufs([loud, quiet], basis: 0) ?? .nan) + 20) < 0.05)
        #expect(abs((TrackAnalysis.pooledLufs([quiet], basis: 0) ?? .nan) + 40) < 0.05)
        #expect(TrackAnalysis.pooledLufs([], basis: 0) == nil && TrackAnalysis.pooledLufs([loud], basis: 1) == nil)
    }

    private static func analyse(_ url: URL) throws -> TrackAnalysis {
        let identity = try #require(TrackIdentity(url: url))
        guard case let .analysed(analysis, _) = TrackAnalysisPass.analyse(url, identity: identity) else {
            Issue.record("not analysed: \(url.lastPathComponent)")
            throw CancellationError()
        }
        #expect(analysis.identity == identity)
        return analysis
    }
}

/// Tone fixtures: a 997 Hz sine per channel at the amplitude `level(channel, frame)` gives, as 32-bit float WAV
/// with no channel layout.
enum ToneFixtures {
    static func write(named name: String, rate: Double, channels: AVAudioChannelCount, seconds: Double,
                      level: (Int, Int) -> Float) throws -> URL {
        try FileManager.default.createDirectory(at: Fixtures.directory, withIntermediateDirectories: true)
        let url = Fixtures.directory.appendingPathComponent("\(name).wav")
        try? FileManager.default.removeItem(at: url)
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: rate,
            AVNumberOfChannelsKey: channels,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
        ]
        let file = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32,
                                   interleaved: false)
        let total = Int(seconds * rate)
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                                   frameCapacity: AVAudioFrameCount(total)))
        buffer.frameLength = AVAudioFrameCount(total)
        for channel in 0 ..< Int(channels) {
            let samples = try #require(buffer.floatChannelData?[channel])
            for frame in 0 ..< total {
                let phase = 2 * Double.pi * 997 * Double(frame) / rate
                samples[frame] = level(channel, frame) * Float(sin(phase))
            }
        }
        try file.write(from: buffer)
        return url
    }
}

@Suite("A FLAC Apple's decoder refuses (blocks under 192 samples) fails cleanly", .timeLimit(.minutes(1)))
struct TinyBlockFlacTests {
    /// `AVAudioFile.framePosition` raises an uncaught NSException on such a file — its very first read of the
    /// getter, before any decode (the corpus's 26-voice_5.1_48k_flac-tiny-blocks.flac; reproduced here). The decode
    /// pass counts the frames it has read instead, so the read's own error ends the job: no crash.
    @Test("PASS-06: the analysis pass refuses a 128-sample-block FLAC without asking the decoder its position")
    func analysisPass() throws {
        let url = try TinyFlac.write(named: "pass-tiny-blocks", blockSize: 128)
        let identity = try #require(TrackIdentity(url: url))
        guard case .failed = TrackAnalysisPass.analyse(url, identity: identity) else {
            Issue.record("a file the decoder cannot read was analysed")
            return
        }
    }

    @Test("PASS-07: the same encoder at 256-sample blocks decodes — the fixture is valid FLAC")
    func controlDecodes() throws {
        let url = try TinyFlac.write(named: "pass-256-blocks", blockSize: 256)
        let identity = try #require(TrackIdentity(url: url))
        guard case let .analysed(analysis, _) = TrackAnalysisPass.analyse(url, identity: identity) else {
            Issue.record("a valid FLAC was not analysed")
            return
        }
        #expect(abs(analysis.durationSeconds - 1) < 0.001)
    }

    @Test("ANALYZER-07: the track loudness analyzer reports the 128-sample-block FLAC as a failure")
    func loudnessAnalyzer() async throws {
        let url = try TinyFlac.write(named: "analyzer-tiny-blocks", blockSize: 128)
        let identity = try #require(TrackIdentity(url: url))
        let sink = RecordingSink()
        let analyzer = TrackLoudnessAnalyzer(log: { _ in })
        analyzer.analyze(url, identity: identity, as: .current, sink: sink)
        let events = await sink.wait(keeping: analyzer) { $0.contains { $0.isFailure } }
        #expect(events.contains { $0.isFailure && $0.token == identity.token })
    }
}

/// A minimal FLAC (RFC 9639): 16-bit mono at 48 kHz, one second of a 440 Hz tone, VERBATIM subframes in blocks of
/// `blockSize` samples (an 8-bit "block size − 1" in each frame header).
enum TinyFlac {
    static func write(named name: String, blockSize: Int) throws -> URL {
        try FileManager.default.createDirectory(at: Fixtures.directory, withIntermediateDirectories: true)
        let url = Fixtures.directory.appendingPathComponent("\(name).flac")
        let rate = 48000
        let samples = (0 ..< rate).map { Int16(8000 * sin(2 * Double.pi * 440 * Double($0) / Double(rate))) }
        var out = [UInt8]("fLaC".utf8)
        // Block sizes (min, max), frame sizes unknown (0, 0); then 20 bits rate, 3 bits channels − 1 (0), 5 bits
        // bits-per-sample − 1 (15), 36 bits total samples; no MD5.
        var info = bigEndian(UInt64(blockSize), bytes: 2) + bigEndian(UInt64(blockSize), bytes: 2)
        info += [UInt8](repeating: 0, count: 6)
        info += bigEndian((UInt64(rate) << 44) | (15 << 36) | UInt64(samples.count), bytes: 8)
        info += [UInt8](repeating: 0, count: 16)
        out += [0x80] + bigEndian(UInt64(info.count), bytes: 3) + info // the last metadata block: STREAMINFO
        for (number, start) in stride(from: 0, to: samples.count, by: blockSize).enumerated() {
            let block = samples[start ..< min(start + blockSize, samples.count)]
            // Sync + fixed blocking; block size "8 bits − 1 at the end", 48 kHz; mono, 16 bits.
            var frame: [UInt8] = [0xFF, 0xF8, 0x6A, 0x08] + utf8(number) + [UInt8(block.count - 1)]
            frame.append(crc8(frame))
            frame.append(0x02) // a VERBATIM subframe
            for sample in block {
                frame += bigEndian(UInt64(UInt16(bitPattern: sample)), bytes: 2)
            }
            frame += bigEndian(UInt64(crc16(frame)), bytes: 2)
            out += frame
        }
        try Data(out).write(to: url)
        return url
    }

    private static func bigEndian(_ value: UInt64, bytes: Int) -> [UInt8] {
        (0 ..< bytes).reversed().map { UInt8(truncatingIfNeeded: value >> (8 * UInt64($0))) }
    }

    private static func utf8(_ number: Int) -> [UInt8] {
        number < 0x80 ? [UInt8(number)]
            : number < 0x800 ? [UInt8(0xC0 | (number >> 6)), UInt8(0x80 | (number & 0x3F))]
            : [UInt8(0xE0 | (number >> 12)), UInt8(0x80 | ((number >> 6) & 0x3F)), UInt8(0x80 | (number & 0x3F))]
    }

    private static func crc8(_ bytes: [UInt8]) -> UInt8 {
        bytes.reduce(UInt8(0)) { crc, byte in
            (0 ..< 8).reduce(crc ^ byte) { value, _ in value & 0x80 != 0 ? (value << 1) ^ 0x07 : value << 1 }
        }
    }

    private static func crc16(_ bytes: [UInt8]) -> UInt16 {
        bytes.reduce(UInt16(0)) { crc, byte in
            (0 ..< 8).reduce(crc ^ (UInt16(byte) << 8)) { value, _ in
                value & 0x8000 != 0 ? (value << 1) ^ 0x8005 : value << 1
            }
        }
    }
}
