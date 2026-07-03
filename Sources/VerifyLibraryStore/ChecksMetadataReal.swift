// ChecksMetadataReal — S8.3 Slice-5 cases M1/M2: REAL-file extraction correctness, the
// one thing stubs/synthetic data can't prove. Drives the full pipeline (LibraryScanner
// scan → MetadataScanner pass → MetadataExtractor) over checked-in self-made fixtures
// (see Tests/Fixtures/artwork-audio/README.md) and asserts the store row carries the
// fixtures' KNOWN embedded tags + cached cover — for the AVFoundation (m4a) and FFmpeg
// (flac) paths. Same VerifyAUGraph idiom.

import Foundation
import LibraryScan
import LibraryStore

/// A checked-in fixture path, relative to the package root (the `swift run` cwd).
private func fixtureURL(_ name: String) -> URL {
    URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        .appendingPathComponent("Tests/Fixtures/artwork-audio/\(name)", isDirectory: false)
}

/// sha256 of the fixtures' embedded 64×64 blue cover PNG. The cover is copied VERBATIM
/// (`-c:v copy`) into both fixture.m4a and fixture.flac, so the extracted bytes are
/// byte-identical across containers AND stable across ffmpeg versions — the artwork_key the
/// pipeline writes must equal this exactly (design §10 M3, byte-exact provenance). If
/// `make regenerate-metadata-fixtures` ever changes the cover, update this + the README table.
private let knownCoverSHA256 = "4c8ff0b8b24e8f75341bf3dae1e8370621da5eed3e2d756fbef54672a5fedcb2"

// MARK: - y / z — real extraction (AVFoundation m4a, FFmpeg flac)

func checkRealMetadataM4A(number: Int, url: URL) async -> Bool {
    await runRealFixture("fixture.m4a", path: "AVFoundation", number: number, url: url)
}

func checkRealMetadataFLAC(number: Int, url: URL) async -> Bool {
    await runRealFixture("fixture.flac", path: "FFmpeg", number: number, url: url)
}

/// Stage `name` into a fresh scan root, run scan + the metadata pass, and assert the store
/// row carries the fixture's known tags + a cached cover.
private func runRealFixture(_ name: String, path: String, number: Int, url: URL) async -> Bool {
    let cacheDir = url.deletingLastPathComponent()
        .appendingPathComponent("realcache-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: cacheDir) }
    do {
        guard FileManager.default.fileExists(atPath: fixtureURL(name).path) else {
            printFail(number, "real(\(name)): fixture missing — run `make regenerate-metadata-fixtures`")
            return false
        }
        let root = testDataDirectory.appendingPathComponent("meta-real-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let file = root.appendingPathComponent(name, isDirectory: false)
        try FileManager.default.copyItem(at: fixtureURL(name), to: file)

        let store = try await LibraryStore(url: url, appBuild: "verify")
        let cache = ArtworkCache(directory: cacheDir)
        let folderID = try await store.addRoot(root)
        let scan = try await LibraryScanner().scan(root: root, folderID: folderID, into: store)
        guard scan.filesSeen == 1 else {
            printFail(number, "real(\(name)): scan saw \(scan.filesSeen) files (expected 1)"); return false
        }
        try await MetadataScanner().run(
            generation: scan.generation, into: store, cache: cache, extractor: MetadataExtractor()
        )
        guard try await assertRealRow(store, cache: cacheDir, file: file, name: name, number: number) else {
            return false
        }
        printPass(number, "real extraction (\(name), \(path) path): scan → metadata pass writes the "
            + "fixture's embedded tags (title/track/disc/year + resolved artist/album/genre) + caches its cover")
        return true
    } catch {
        printFail(number, "real(\(name)) threw: \(error)"); return false
    }
}

/// Assert the store row for `file` carries the fixtures' baked tags + a cached cover.
private func assertRealRow(
    _ store: LibraryStore, cache: URL, file: URL, name: String, number: Int
) async throws -> Bool {
    guard let row = try await store.track(url: file) else {
        printFail(number, "real(\(name)): no track row after the pass"); return false
    }
    guard row.title == "Verify Title", row.trackNo == 3, row.discNo == 1, row.year == 2001 else {
        printFail(number, "real(\(name)): tags wrong (title=\(row.title ?? "nil") trk=\(descInt(row.trackNo)) "
            + "disc=\(descInt(row.discNo)) yr=\(descInt(row.year)))"); return false
    }
    guard row.albumID != nil, row.artistID != nil else {
        printFail(number, "real(\(name)): album/artist not resolved"); return false
    }
    guard try await store.albums().contains(where: { $0.title == "Verify Album" }),
          try await store.artists().contains(where: { $0.name == "Verify Artist" }),
          try Set(await store.genres().map(\.name)).contains("TestGenre") else {
        printFail(number, "real(\(name)): resolved album/artist/genre wrong"); return false
    }
    // The embedded cover — a 64×64 blue PNG copied verbatim (-c:v copy) into BOTH containers —
    // hashes to a KNOWN, version-stable sha256, so this is a byte-exact provenance check (design
    // §10 M3), not just "some art present". A decodable cover also yields <hash>.thumb.jpg.
    guard row.artworkKey == knownCoverSHA256 else {
        printFail(number, "real(\(name)): artwork_key \(row.artworkKey ?? "nil") != known cover sha256 "
            + "(\(knownCoverSHA256))"); return false
    }
    let original = cache.appendingPathComponent("\(knownCoverSHA256).png").path
    let thumb = cache.appendingPathComponent("\(knownCoverSHA256).thumb.jpg").path
    guard FileManager.default.fileExists(atPath: original), FileManager.default.fileExists(atPath: thumb) else {
        printFail(number, "real(\(name)): cached original and/or 512px thumbnail missing"); return false
    }
    return true
}

// MARK: - ac — real tagless file (no-tags.m4a): empty-not-crash + marked (real anti-loop)

/// The REAL extractor on a readable-but-UNTAGGED file must yield no title + no artwork, and
/// the pass must MARK it so it never re-extracts. Proves the real AVFoundation tagless path
/// (the store-level anti-loop is proven synthetically in ChecksMetadataPass); uses the
/// checked-in no-tags.m4a fixture that was otherwise unexercised.
func checkRealNoTags(number: Int, url: URL) async -> Bool {
    let cacheDir = url.deletingLastPathComponent()
        .appendingPathComponent("realcache-notags-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: cacheDir) }
    do {
        guard FileManager.default.fileExists(atPath: fixtureURL("no-tags.m4a").path) else {
            printFail(number, "real(no-tags): fixture missing — run `make regenerate-metadata-fixtures`")
            return false
        }
        let root = testDataDirectory.appendingPathComponent("meta-notags-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let file = root.appendingPathComponent("no-tags.m4a", isDirectory: false)
        try FileManager.default.copyItem(at: fixtureURL("no-tags.m4a"), to: file)

        let store = try await LibraryStore(url: url, appBuild: "verify")
        let cache = ArtworkCache(directory: cacheDir)
        let folderID = try await store.addRoot(root)
        let scan = try await LibraryScanner().scan(root: root, folderID: folderID, into: store)
        guard scan.filesSeen == 1 else {
            printFail(number, "real(no-tags): scan saw \(scan.filesSeen) files (expected 1)"); return false
        }
        try await MetadataScanner().run(
            generation: scan.generation, into: store, cache: cache, extractor: MetadataExtractor()
        )
        guard let row = try await store.track(url: file) else {
            printFail(number, "real(no-tags): no track row after the pass"); return false
        }
        guard row.title == nil, row.artworkKey == nil else {
            printFail(number, "real(no-tags): expected nil title/art, got title=\(row.title ?? "nil") "
                + "art=\(row.artworkKey ?? "nil")"); return false
        }
        guard try await store.tracksNeedingMetadata(limit: 10).isEmpty else {
            printFail(number, "real(no-tags): tagless file NOT marked — would re-extract forever"); return false
        }
        printPass(number, "real tagless file (no-tags.m4a): the REAL extractor reads a readable-but-untagged "
            + "file → nil title + nil artwork, and the pass MARKS it (metadata_scanned) so it is never "
            + "re-extracted (the real-file anti-loop)")
        return true
    } catch {
        printFail(number, "real(no-tags) threw: \(error)"); return false
    }
}

private func descInt(_ value: Int?) -> String {
    value.map(String.init) ?? "nil"
}
