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
    let cacheFiles = (try? FileManager.default.contentsOfDirectory(atPath: cache.path)) ?? []
    guard row.artworkKey != nil, !cacheFiles.isEmpty else {
        printFail(number, "real(\(name)): cover not extracted/cached (artworkKey=\(row.artworkKey ?? "nil"), "
            + "cacheFiles=\(cacheFiles.count))"); return false
    }
    return true
}

private func descInt(_ value: Int?) -> String {
    value.map(String.init) ?? "nil"
}
