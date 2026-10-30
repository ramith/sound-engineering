@testable import AdaptiveSound
@preconcurrency import AVFoundation
import Foundation
import RigKit
import Testing

// MARK: - The bridge's own reader and the open that probes a file (R1.1-B fix round, F1: KI-PB-22, MEDIUM-3, LOW-3)

//
// `TrackFileReader` is Apple's decoder (`ExtAudioFile`, the one `AVAudioFile` wraps) with its place counted and every
// failure a thrown status — never `AVAudioFile.framePosition`, whose getter and setter kill the process on a file
// the decoder refuses. `openForPlayback` reads a file's first frames on one before anything commits to it.

@Suite("The bridge's reader: AVAudioFile's samples, its place counted, a short read its end (KI-PB-22)",
       .timeLimit(.minutes(2)))
struct TrackReaderTests {
    private static let fixtures = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures")
    /// The break-it's 48 kHz mono AC-3 tone: `length` 96 768, the decoder delivers 96 480.
    static let shortRead48k = fixtures.appendingPathComponent("breakit-sound/tone-ac3-mono-48k.m4a")

    /// A 5.1 file at 44.1 kHz, one tone per channel (32-bit float CAF in test-data/; removed by the caller).
    private static func surroundFile() throws -> URL {
        let layout = try #require(AVAudioChannelLayout(layoutTag: kAudioChannelLayoutTag_MPEG_5_1_A))
        return try MultichannelFixture.write(layout: layout, rate: 44100, name: "reader-5.1")
    }

    /// Every channel of `buffer`'s frames.
    private static func samples(_ buffer: AVAudioPCMBuffer) -> [[Float]] {
        guard let data = buffer.floatChannelData else { return [] }
        return (0 ..< Int(buffer.format.channelCount)).map {
            Array(UnsafeBufferPointer(start: data[$0], count: Int(buffer.frameLength)))
        }
    }

    @Test("it reads what AVAudioFile reads, bit for bit on every channel, and counts its place to the end")
    func readsWhatAVAudioFileReads() throws {
        let url = try Self.surroundFile()
        defer { try? FileManager.default.removeItem(at: url) }
        let file = try AVAudioFile(forReading: url)
        let reader = try TrackFileReader(reading: file)
        let expected = try #require(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 4096))
        let read = try #require(AVAudioPCMBuffer(pcmFormat: reader.processingFormat, frameCapacity: 4096))
        var counted: AVAudioFramePosition = 0
        while !reader.ended {
            try file.read(into: expected, frameCount: 4096)
            try reader.read(into: read, frameCount: 4096)
            counted += AVAudioFramePosition(read.frameLength)
            let from = counted - Int64(read.frameLength)
            #expect(Self.samples(read) == Self.samples(expected), "the frames from \(from)")
            #expect(reader.position == counted)
        }
        #expect(counted == file.length, "the reader delivered \(counted) of the file's \(file.length) frames")
        try reader.read(into: read, frameCount: 4096)
        #expect(read.frameLength == 0, "a read past the end delivers nothing")
    }

    @Test("a seek lands where reading from the top lands, and the place is counted from it")
    func seekLandsWhereReadingLands() throws {
        let url = try Self.surroundFile()
        defer { try? FileManager.default.removeItem(at: url) }
        let file = try AVAudioFile(forReading: url)
        let place: AVAudioFramePosition = 12345
        let fromTop = try TrackFileReader(reading: file)
        let skipped = try #require(AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                                    frameCapacity: AVAudioFrameCount(place)))
        try fromTop.read(into: skipped, frameCount: AVAudioFrameCount(place))
        let seeking = try TrackFileReader(reading: file)
        try seeking.seek(to: place)
        #expect(seeking.position == place)
        let expected = try #require(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 2048))
        let read = try #require(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 2048))
        try fromTop.read(into: expected, frameCount: 2048)
        try seeking.read(into: read, frameCount: 2048)
        #expect(Self.samples(read) == Self.samples(expected))
        #expect(seeking.position == place + 2048)
    }

    @Test("the reader ends on the frames the decoder delivers (a short-reading 48 kHz AC-3 too), no failure after")
    func shortReadEndsOnDeliveredFrames() throws {
        let decoded = try Self.framesDecoded(at: Self.shortRead48k)
        let file = try AVAudioFile(forReading: Self.shortRead48k)
        let reader = try TrackFileReader(reading: file)
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 8192))
        var delivered: AVAudioFramePosition = 0
        while !reader.ended {
            try reader.read(into: buffer, frameCount: 8192)
            delivered += AVAudioFramePosition(buffer.frameLength)
        }
        // Whatever this macOS's decoder gives — macOS 26 delivers 96 480 of the 96 768 frames `length` states, then
        // throws; the CI runner's newer decoder differs — the reader ends exactly there.
        #expect(delivered == decoded, "the reader delivered \(delivered) frames; the decoder gives \(decoded)")
        #expect(decoded <= file.length, "the decoder gave \(decoded) frames, more than the \(file.length) stated")
        try reader.read(into: buffer, frameCount: 8192) // past the end: AVAudioFile throws here on macOS 26
        #expect(buffer.frameLength == 0)
    }

    /// The frames Apple's decoder delivers for `url`, read through a plain `AVAudioFile` until it gives no more or
    /// throws: the end the bridge's reader must stop on. The count is the running macOS's, never a constant.
    static func framesDecoded(at url: URL) throws -> AVAudioFramePosition {
        let file = try AVAudioFile(forReading: url)
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 8192))
        var frames: AVAudioFramePosition = 0
        while (try? file.read(into: buffer, frameCount: 8192)) != nil, buffer.frameLength > 0 {
            frames += AVAudioFramePosition(buffer.frameLength)
        }
        return frames
    }

    @Test("the open probes Apple's decoder: a tiny-block FLAC is refused before anything commits to it")
    func openRefusesWhatTheDecoderCannotRead() throws {
        let tiny = try BreakItTinyFlac.write(named: "probe", rate: 44100, blockSize: 128)
        let control = try BreakItTinyFlac.write(named: "probe", rate: 44100, blockSize: 4096)
        defer {
            try? FileManager.default.removeItem(at: tiny)
            try? FileManager.default.removeItem(at: control)
        }
        #expect(throws: AudioBridgeError.undecodableFormat("flac")) { try AudioEngineBridge.openForPlayback(tiny) }
        let opened = try AudioEngineBridge.openForPlayback(control)
        #expect(opened.length == 44100, "a FLAC of the same tone in 4096-sample blocks opens")
    }

    @Test("what plays straight through: 48 kHz PCM, FLAC and ALAC; a lossy codec or another rate goes to the reader")
    func whatPlaysStraightThrough() throws {
        let mono = try #require(AVAudioChannelLayout(layoutTag: kAudioChannelLayoutTag_Mono))
        let pcm48 = try MultichannelFixture.write(layout: mono, rate: 48000, name: "route-48")
        let pcm44 = try MultichannelFixture.write(layout: mono, rate: 44100, name: "route-44")
        let flac48 = try BreakItTinyFlac.write(named: "route", rate: 48000, blockSize: 4096)
        defer {
            for url in [pcm48, pcm44, flac48] {
                try? FileManager.default.removeItem(at: url)
            }
        }
        let rate = 48000.0
        #expect(try AudioEngineBridge.playsStraightThrough(AVAudioFile(forReading: pcm48), graphRate: rate))
        #expect(try AudioEngineBridge.playsStraightThrough(AVAudioFile(forReading: flac48), graphRate: rate))
        #expect(try !AudioEngineBridge.playsStraightThrough(AVAudioFile(forReading: pcm44), graphRate: rate))
        let ac3 = try AVAudioFile(forReading: Self.shortRead48k)
        #expect(!AudioEngineBridge.playsStraightThrough(ac3, graphRate: rate), "a lossy codec's length is an estimate")
    }
}
