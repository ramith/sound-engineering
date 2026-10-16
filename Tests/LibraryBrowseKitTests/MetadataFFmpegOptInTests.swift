import CryptoKit
import Foundation
@testable import LibraryScan
import Synchronization
import Testing

// MARK: - FFmpeg only when asked for (R1.1-A, founder decision FD-3, council C-99, KI-SEC-01)

/// FFmpeg's demuxers used to read every FLAC, Ogg and Opus file FIRST in the background tag pass —
/// an in-process C parser on files from anywhere, loaded from a user-writable folder. Now FFmpeg is an
/// opt-in, off by default, and the tag pass reads through Apple first: FFmpeg only when it is on AND
/// Apple can't read the file (or reads none of its core tags). With it off, Apple alone reads every
/// fixture — the album credits included.
///
/// The FFmpeg read is the extractor's seam (`ffmpegRead`), so a test sees whether it ran without
/// loading FFmpeg (the C++ null test proves "off loads nothing" at the dlopen itself).
@Suite("FFmpeg only when asked for — the tag pass")
struct MetadataFFmpegOptInTests {
    /// Every FFmpeg read the extractor asked for, by file name.
    final class FFmpegReads: Sendable {
        private let names = Mutex<[String]>([])
        var all: [String] {
            names.withLock { $0 }
        }

        /// An FFmpeg read that records the ask and reads nothing.
        var reader: @Sendable (URL) -> ExtractedMetadata? {
            { [self] url in
                record(url)
                return nil
            }
        }

        private func record(_ url: URL) {
            names.withLock { $0.append(url.lastPathComponent) }
        }
    }

    /// The checked-in fixtures, from this file's place in the repo.
    private static let fixtures = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Fixtures/artwork-audio", isDirectory: true)

    /// The album credits each fixture carries (ALB-02's table): the compilation flag, the album artist.
    static let albumCredits: [String: (flag: Bool, albumArtist: String?)] = [
        "compilation.m4a": (true, nil), "compilation.flac": (true, nil), "compilation.mp3": (true, nil),
        "compilation.ogg": (true, "Comp Album Artist"), "compilation.opus": (true, "Comp Album Artist"),
        "fixture.m4a": (false, "Verify Artist"), "fixture.flac": (false, "Verify Artist"),
    ]

    @Test("with FFmpeg off, Apple reads every fixture and FFmpeg is never asked",
          arguments: Array(albumCredits.keys).sorted())
    func offReadsThroughAppleOnly(file: String) async throws {
        let reads = FFmpegReads()
        let extractor = MetadataExtractor(usesFFmpeg: false, ffmpegRead: reads.reader)
        let read = try #require(await extractor.extract(from: Self.fixtures.appendingPathComponent(file)))
        #expect(reads.all.isEmpty, "FFmpeg was asked for \(reads.all) with FFmpeg off")
        #expect(read.metadata.title != nil && read.metadata.artistName != nil && read.metadata.albumTitle != nil,
                "Apple read no core tags from \(file)")
        let credits = try #require(Self.albumCredits[file])
        #expect(read.metadata.isCompilation == credits.flag, "compilation flag of \(file)")
        #expect(read.metadata.albumArtistName == credits.albumArtist, "album artist of \(file)")
    }

    /// The fixtures' baked tags and their verbatim cover (Tests/Fixtures/artwork-audio/README.md): a FLAC
    /// library keeps every field and its covers with FFmpeg off.
    @Test("with FFmpeg off, Apple reads a FLAC's whole tag set and its embedded cover",
          arguments: ["fixture.flac", "fixture.m4a"])
    func offReadsTheWholeFLAC(file: String) async throws {
        let reads = FFmpegReads()
        let extractor = MetadataExtractor(usesFFmpeg: false, ffmpegRead: reads.reader)
        let read = try #require(await extractor.extract(from: Self.fixtures.appendingPathComponent(file)))
        let tags = read.metadata
        #expect(tags.title == "Verify Title" && tags.artistName == "Verify Artist" && tags.albumTitle == "Verify Album")
        #expect(tags.year == 2001 && tags.trackNo == 3 && tags.discNo == 1 && tags.genres == ["TestGenre"])
        let cover = try #require(read.artwork, "no cover read from \(file)")
        let digest = SHA256.hash(data: cover.data).map { String(format: "%02x", $0) }.joined()
        #expect(digest == "4c8ff0b8b24e8f75341bf3dae1e8370621da5eed3e2d756fbef54672a5fedcb2")
        #expect(reads.all.isEmpty)
    }

    @Test("with FFmpeg off, a file Apple can't read is not handed to FFmpeg")
    func offNeverFallsBack() async throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("ffmpeg-opt-in-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let broken = folder.appendingPathComponent("broken.flac")
        try Data("fLaC but not really".utf8).write(to: broken)

        let reads = FFmpegReads()
        _ = await MetadataExtractor(usesFFmpeg: false, ffmpegRead: reads.reader).extract(from: broken)
        #expect(reads.all.isEmpty)
    }

    @Test("with FFmpeg on, Apple still reads first: FFmpeg only for a file Apple can't read")
    func onFallsBackOnlyWhenAppleCannot() async throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("ffmpeg-opt-in-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let broken = folder.appendingPathComponent("broken.flac")
        try Data("fLaC but not really".utf8).write(to: broken)

        let reads = FFmpegReads()
        let extractor = MetadataExtractor(usesFFmpeg: true, ffmpegRead: reads.reader)
        for file in Self.albumCredits.keys.sorted() {
            _ = await extractor.extract(from: Self.fixtures.appendingPathComponent(file))
        }
        #expect(reads.all.isEmpty, "FFmpeg read \(reads.all), which Apple reads")
        _ = await extractor.extract(from: broken)
        #expect(reads.all == ["broken.flac"])
    }
}
