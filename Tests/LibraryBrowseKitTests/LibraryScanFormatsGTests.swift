import AVFoundation
import Foundation
import LibraryScan
import Testing

// MARK: - Sprint G break-it: files the scan never admits (G-LIB-02)

/// The scan admits a file only by its extension (`LibraryScanner.supportedExtensions`). It admitted
/// the long ".aiff" spelling but not ".aif", the extension Music and iTunes give every AIFF they
/// import or rip (and Logic, by default): a folder of them showed "No Music Found", and nothing said
/// why. The fix admits ".aif"; both playback paths open it by content (`AVAudioFile` in Enhanced,
/// `ExtAudioFileOpenURL` with no type hint in Pure).
///
/// R1.1-A (council C-08's scanner half, KI-LIB-05): on macOS 26 Apple's own decoder opens Ogg Vorbis
/// and Opus, so ".opus" and ".oga" are admitted too — no FFmpeg needed. The format table below holds
/// the scan to that: every extension it admits opens for playback from a real file of that kind.
///
/// Needs the LibraryScan target, a test-only dependency of LibraryBrowseKitTests (Package.swift).
@Suite("Sprint G break-it — files the scan never admits")
struct LibraryScanFormatsGTests {
    /// A temporary folder, removed by the caller.
    private static func makeFolder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("sprint-g-formats-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    @Test("G-LIB-02: a song the app can play is admitted by the scan", arguments: ["aif", "AIF"])
    func playableExtensionIsScanned(fileExtension: String) throws {
        let folder = try Self.makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let song = folder.appendingPathComponent("01 Song." + fileExtension)
        #expect(FileManager.default.createFile(atPath: song.path, contents: Data([1])))

        let scanned = LibraryScanner.makeScannedFile(fileURL: song, root: folder)
        #expect(scanned != nil, "a .\(fileExtension) file is skipped by the scan")
        #expect(scanned?.format == "AIF")
    }

    /// The other half of "admitted": a real AIFF saved as ".aif" opens the way the Enhanced path
    /// opens a song (`AVAudioFile(forReading:)`), with its rate and width intact.
    @Test("G-LIB-02: a real .aif song opens for playback")
    func aifOpensForPlayback() throws {
        let folder = try Self.makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let song = folder.appendingPathComponent("01 Song.aif")
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 44100, AVNumberOfChannelsKey: 2,
            AVLinearPCMBitDepthKey: 16, AVLinearPCMIsBigEndianKey: true, AVLinearPCMIsFloatKey: false,
        ]
        do {
            let writer = try AVAudioFile(forWriting: song, settings: settings)
            let format = writer.processingFormat
            let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4410))
            buffer.frameLength = 4410
            try writer.write(from: buffer)
        }

        let reader = try AVAudioFile(forReading: song)
        #expect(reader.fileFormat.sampleRate == 44100)
        #expect(reader.fileFormat.channelCount == 2)
        #expect(reader.length == 4410)
        #expect(LibraryScanner.makeScannedFile(fileURL: song, root: folder) != nil)
    }

    // MARK: - The format table (R1.1-A, KI-LIB-05)

    /// Where a real file of each admitted kind comes from: a checked-in fixture (`Tests/Fixtures/
    /// artwork-audio`), copied under the extension, or one this test writes through Apple's encoder.
    enum RealFile: Sendable {
        case fixture(String)
        case written(AudioFormatID)
    }

    /// Every extension the scan admits, with a real file of that kind. A new extension the scan admits
    /// without a row here fails `tableCoversTheScan`.
    static let formatTable: [String: RealFile] = [
        "flac": .fixture("fixture.flac"),
        "mp3": .fixture("compilation.mp3"),
        "mpga": .fixture("compilation.mp3"), // MPEG audio's other spelling (public.mp3)
        "m4a": .fixture("fixture.m4a"),
        "ogg": .fixture("compilation.ogg"), // Ogg Vorbis
        "oga": .fixture("compilation.ogg"), // the audio-only Ogg spelling
        "opus": .fixture("compilation.opus"), // Ogg Opus
        "wav": .written(kAudioFormatLinearPCM),
        "wave": .written(kAudioFormatLinearPCM), // WAV's other spelling
        "bwf": .written(kAudioFormatLinearPCM), // Broadcast WAV: a WAV with a broadcast chunk
        "aiff": .written(kAudioFormatLinearPCM),
        "aif": .written(kAudioFormatLinearPCM),
        "aac": .written(kAudioFormatMPEG4AAC), // ADTS
        "adts": .written(kAudioFormatMPEG4AAC), // ADTS, by its own name
        "alac": .written(kAudioFormatAppleLossless), // an Apple Lossless file named for its codec
    ]

    /// The checked-in fixtures, from this file's place in the repo.
    private static let fixtures = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Fixtures/artwork-audio", isDirectory: true)

    /// A real `fileExtension` song in `folder`.
    private static func realSong(_ fileExtension: String, in folder: URL) throws -> URL {
        let song = folder.appendingPathComponent("01 Song." + fileExtension)
        switch try #require(formatTable[fileExtension]) {
        case let .fixture(name):
            try FileManager.default.copyItem(at: fixtures.appendingPathComponent(name), to: song)
        case let .written(formatID):
            try write(formatID, to: song)
        }
        return song
    }

    /// The extension a kind is written under, where the encoder does not take its own: ALAC as `.m4a`, the
    /// other WAV and ADTS spellings as `.wav` and `.aac` — then renamed. The file type comes from the
    /// extension when writing, and Apple opens a file by its content.
    private static let writtenAs: [String: String] = ["alac": "m4a", "wave": "wav", "bwf": "wav", "adts": "aac"]

    /// 0.1 s of a 44.1 kHz stereo tone, encoded as `formatID` (`writtenAs` the extension it takes).
    private static func write(_ formatID: AudioFormatID, to song: URL) throws {
        let target = writtenAs[song.pathExtension].map { song.deletingPathExtension().appendingPathExtension($0) }
            ?? song
        var settings: [String: Any] = [AVFormatIDKey: formatID, AVSampleRateKey: 44100, AVNumberOfChannelsKey: 2]
        if formatID == kAudioFormatLinearPCM {
            settings[AVLinearPCMBitDepthKey] = 16
            settings[AVLinearPCMIsFloatKey] = false
            settings[AVLinearPCMIsBigEndianKey] = ["aiff", "aif"].contains(song.pathExtension)
        }
        if formatID == kAudioFormatAppleLossless {
            settings[AVEncoderBitDepthHintKey] = 16
        }
        do {
            let writer = try AVAudioFile(forWriting: target, settings: settings)
            let buffer = try #require(AVAudioPCMBuffer(pcmFormat: writer.processingFormat, frameCapacity: 4410))
            buffer.frameLength = 4410
            for channel in 0 ..< Int(buffer.format.channelCount) {
                for frame in 0 ..< 4410 {
                    buffer.floatChannelData?[channel][frame] = Float(sin(Double(frame) * 0.0627)) * 0.25
                }
            }
            try writer.write(from: buffer)
        }
        if target != song {
            try FileManager.default.moveItem(at: target, to: song)
        }
    }

    @Test("the format table holds exactly the extensions the scan admits")
    func tableCoversTheScan() {
        #expect(Set(Self.formatTable.keys) == LibraryScanner.supportedExtensions)
    }

    /// The scanner's half: the scan admits each kind. Its playback half: the file opens the way the
    /// Enhanced path opens a song (`AVAudioFile(forReading:)`) — Apple's decoder, no FFmpeg.
    @Test("every kind of file in the format table is scanned, and opens for playback",
          arguments: Array(formatTable.keys).sorted())
    func scannedAndPlayable(fileExtension: String) throws {
        let folder = try Self.makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let song = try Self.realSong(fileExtension, in: folder)

        #expect(LibraryScanner.makeScannedFile(fileURL: song, root: folder) != nil,
                "a real .\(fileExtension) song is skipped by the scan")
        let reader = try AVAudioFile(forReading: song)
        #expect(reader.length > 0)
        #expect(reader.processingFormat.sampleRate > 0)
    }
}
