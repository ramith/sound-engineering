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
/// ".opus" / ".oga" (played only through the optional FFmpeg fallback) stay out until the scan can
/// tell whether FFmpeg is there — post-R1, in the Sprint G break-it report.
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
}
