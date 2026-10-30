@testable import AdaptiveSound
@preconcurrency import AVFoundation
import Foundation
import RigKit
import Testing

// MARK: - A file that can't play says why (R1.1-B fix round, F1: break-it LOW-3, KI-PB-22, KI-LIB-12)

//
// Every open failure used to read "This file type isn't supported (.flac)", although the app plays FLAC, WAV and
// stereo Opus; and a 48 kHz FLAC Apple's decoder refuses (blocks under 192 samples) started, played silence and
// skipped with no word. Through the REAL bridge's start (`playFile`) on an offline device, each kind of file is
// refused before anything plays, with what is wrong: a type the app doesn't play, a file it can't read (damaged or
// not audio), or a variant macOS can't decode. The banner reads "Playback failed: " + this. Nothing is heard.

@Suite("A file that can't play is refused with why (LOW-3)", .serialized, .timeLimit(.minutes(5)), .attachingLogTail)
struct UnplayableFileTests {
    /// What the bridge's start answered: the error's words, or nil when it started.
    private static func refusal(playing url: URL) async throws -> String? {
        let rig = try await MultichannelDeviceRig.make(deviceChannels: 2)
        var said: String?
        do {
            try await rig.play(url)
            _ = try await rig.render(frames: 4800)
        } catch {
            said = error.localizedDescription
        }
        await rig.finish()
        return said
    }

    /// A file of `bytes` named `name` in test-data/reader/ (removed by the caller).
    private static func file(named name: String, bytes: [UInt8]) throws -> URL {
        let directory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("test-data/reader", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("\(UUID().uuidString)-\(name)")
        try Data(bytes).write(to: url)
        return url
    }

    /// Bytes no decoder takes for audio (a fixed pattern: the same file every run).
    private static let noise: [UInt8] = (0 ..< 4096).map { UInt8(truncatingIfNeeded: ($0 &* 187) ^ ($0 >> 3)) }

    @Test("a 48 kHz FLAC with blocks under 192 is refused as one macOS can't decode, never played as silence")
    func tinyBlockFlacIsRefused() async throws {
        let url = try BreakItTinyFlac.write(named: "refused-48k", rate: 48000, blockSize: 128)
        defer { try? FileManager.default.removeItem(at: url) }
        let said = try #require(try await Self.refusal(playing: url), "the tiny-block FLAC started")
        #expect(said == "macOS can't decode this kind of file (.flac).", "\(said)")
    }

    @Test("a 5.1 Opus file (KI-LIB-12) is a variant macOS can't decode")
    func surroundOpusIsAVariant() async throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Fixtures/reader/surround-5.1-48k.opus")
        let said = try #require(try await Self.refusal(playing: url), "the 5.1 Opus started")
        #expect(said == "macOS can't decode this kind of file (.opus).", "\(said)")
    }

    @Test("a .wav of random bytes (11-broken-files 115) can't be read — it may be damaged")
    func randomBytesWavIsUnreadable() async throws {
        let url = try Self.file(named: "random.wav", bytes: Self.noise)
        defer { try? FileManager.default.removeItem(at: url) }
        let said = try #require(try await Self.refusal(playing: url), "random bytes started")
        #expect(said == "This file can't be read — it may be damaged (.wav).", "\(said)")
    }

    @Test("a zero-byte FLAC (11-broken-files 113) can't be read — it may be damaged")
    func zeroByteFlacIsUnreadable() async throws {
        let url = try Self.file(named: "empty.flac", bytes: [])
        defer { try? FileManager.default.removeItem(at: url) }
        let said = try #require(try await Self.refusal(playing: url), "a zero-byte file started")
        #expect(said == "This file can't be read — it may be damaged (.flac).", "\(said)")
    }

    @Test("a type the app doesn't play is still said so")
    func unknownTypeIsUnsupported() async throws {
        let url = try Self.file(named: "notes.xyz", bytes: Self.noise)
        defer { try? FileManager.default.removeItem(at: url) }
        let said = try #require(try await Self.refusal(playing: url), "a .xyz file started")
        #expect(said == "This file type isn't supported (.xyz).", "\(said)")
    }
}
