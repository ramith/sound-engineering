import Foundation
import LibraryScan
import Testing

// MARK: - Sprint G break-it: files the scan never admits (G-LIB-02)

/// The scan admits a file only by its extension (LibraryScanner.supportedExtensions: flac, mp3, wav,
/// aac, m4a, alac, aiff, ogg). Two kinds of song the app can play never reach the library:
/// - ".aif", the extension Music and iTunes give every AIFF they import or rip (and Logic, by
///   default). The scan admits only the long ".aiff" spelling.
/// - ".opus" (and ".oga"), which the decoder plays through its FFmpeg fallback (FileDecodeSource.cpp:
///   "for formats Apple decoder cannot open (e.g. Opus)") and whose tags the metadata extractor
///   reads (MetadataExtractor.vorbisCommentExtensions = flac, ogg, oga, opus).
/// A folder of them shows "No Music Found", and nothing says why.
///
/// Needs the LibraryScan target, which this break-it branch adds to LibraryBrowseKitTests in
/// Package.swift (a test-only dependency).
@Suite("Sprint G break-it — files the scan never admits")
struct LibraryScanFormatsGTests {
    @Test("G-LIB-02: a song the app can play is admitted by the scan", arguments: ["aif", "opus", "oga"])
    func playableExtensionIsScanned(fileExtension: String) throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("sprint-g-formats-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let song = folder.appendingPathComponent("01 Song." + fileExtension)
        #expect(FileManager.default.createFile(atPath: song.path, contents: Data([1])))

        let scanned = LibraryScanner.makeScannedFile(fileURL: song, root: folder)
        #expect(scanned != nil, "a .\(fileExtension) file is skipped by the scan")
    }
}
