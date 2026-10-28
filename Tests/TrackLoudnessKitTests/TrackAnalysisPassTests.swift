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
