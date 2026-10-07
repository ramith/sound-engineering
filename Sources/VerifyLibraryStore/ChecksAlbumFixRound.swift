// ChecksAlbumFixRound — the S10.8 C2 fix round, store and pass (docs/sprints/s10-8-sweep-ledger.md,
// Sprint C). Each case replays a break-it finding through the app's own pipeline:
//   ALB-06 (A3) v7 checks only the references it can break — a v6 store holding an unrelated
//          dangling reference still migrates; album rows that differed only by year merge, ids
//          kept; a song pointing at a missing album row is unlinked; the scoped check does catch a
//          dangling reference INTO albums;
//   ALB-07 (B1) an offline file stays pending — a pass while the folder is moved away marks none
//          of its songs; after it comes back, a rescan reads them all (album artist + compilation
//          flag); a file that is there but unreadable is still marked (anti-loop);
//   ALB-08 (B2) one shared title costs a pass nothing extra — 1,000 "Unknown Album" songs in 100
//          folders re-read about as fast as 1,000 songs on 100 titles (it was ~30× slower);
//   ALB-09 (B3) a folder removed mid-pass — the pass finishes and writes nothing for the removed
//          songs; a root-scoped pass leaves the other roots' pending songs alone;
//   ALB-10 (B4) no zero-song album — a retag that empties an album deletes it in the same write; a
//          pass cut off midway leaves no ghost, and owes its regroup durably to the next pass.

import Foundation
import GRDB
import LibraryScan
import LibraryStore

// MARK: - Registration

func albumFixRoundCheckCases() -> [CheckCase] {
    [
        CheckCase(label: "alb06-v7-scoped-reference-check", run: checkV7ScopedReferenceCheck),
        CheckCase(label: "alb07-offline-file-stays-pending", run: checkOfflineFileStaysPending),
        CheckCase(label: "alb08-one-title-pass-cost", run: checkOneTitlePassCost),
        CheckCase(label: "alb09-folder-removed-mid-pass", run: checkFolderRemovedMidPass),
        CheckCase(label: "alb10-no-zero-song-album", run: checkNoZeroSongAlbum),
    ]
}

/// Reads only files that are on disk — what the real extractor does (a missing file reads nil).
struct PresentFilesExtractor: MetadataExtracting {
    let tags: TagTableExtractor

    func extract(from url: URL) async -> ExtractedMetadata? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return await tags.extract(from: url)
    }
}

/// A fresh artwork cache next to the store (removed by the caller).
private func cacheDirectory(beside url: URL, _ label: String) -> URL {
    url.deletingLastPathComponent().appendingPathComponent("\(label)-cache-\(UUID().uuidString)", isDirectory: true)
}

// MARK: - ALB-06 (A3) — v7 checks only the references it can break

/// The previous release's library with three kinds of old data: a song whose `artwork_key` names an
/// artwork row that is gone (nothing to do with albums), two album rows that differ ONLY by year
/// (one album under the new key), and a song pointing at an album row that is gone.
private let staleV6SeedSQL = [
    "INSERT INTO folders(id, path, is_root) VALUES (1, '/ALB06/Lib', 1);",
    "INSERT INTO artists(id, name, sort_name) VALUES (1, 'Ann', 'Ann');",
    "INSERT INTO albums(id, title, album_artist_id, year) VALUES (1, 'Hits', 1, 2001), (2, 'Hits', 1, 2003);",
    """
    INSERT INTO tracks(id, url, folder_id, relative_path, name, format, file_size, mtime, album_id, artist_id,
        artwork_key, date_added, play_count)
    VALUES (1, '/ALB06/Lib/a.flac', 1, 'a.flac', 'a', 'FLAC', 1, 1, 1, 1, 'gone-hash', 1690000000, 5),
           (2, '/ALB06/Lib/b.flac', 1, 'b.flac', 'b', 'FLAC', 2, 1, 2, 1, NULL, 1690000000, 0),
           (3, '/ALB06/Lib/c.flac', 1, 'c.flac', 'c', 'FLAC', 3, 1, 99, 1, NULL, 1690000000, 0);
    """,
]

/// A store with foreign keys off for the seed (its dangling references are the point).
private func foreignKeysOffQueue(path: String? = nil) throws -> DatabaseQueue {
    var config = Configuration()
    config.foreignKeysEnabled = false
    return try path.map { try DatabaseQueue(path: $0, configuration: config) } ?? DatabaseQueue(configuration: config)
}

/// Build the stale v6 store at `url` (the production migrator capped at v6).
private func seedStaleV6Store(at url: URL) throws {
    let queue = try foreignKeysOffQueue(path: url.path)
    try migrator(through: 6).migrate(queue)
    try queue.write { db in
        for statement in staleV6SeedSQL {
            try db.execute(sql: statement)
        }
    }
    try queue.close()
}

func checkV7ScopedReferenceCheck(number: Int, url: URL) async -> Bool {
    do {
        try seedStaleV6Store(at: url)
        let store = try await LibraryStore(url: url, appBuild: "verify")
        guard await store.schemaVersion() == currentSchemaVersion, store.quarantinedFrom == nil else {
            printFail(number, "ALB-06: a v6 store with an unrelated dangling reference did not migrate to v7")
            return false
        }
        // Kept ids (FKs were off for the rebuild — no SET NULL cascade), the year-only duplicate merged
        // onto the lowest id, the dangling album link cleared, the unrelated reference left alone.
        let tracks = try await [1, 2, 3].asyncMap { try await store.track(id: $0) }
        guard tracks.map({ $0?.albumID }) == [1, 1, nil], tracks[0]?.artworkKey == "gone-hash",
              try await store.countRows(inTable: "albums") == 1,
              try await store.userState(trackID: 1)?.playCount == 5 else {
            printFail(number, "ALB-06: after v7 the songs' albums are \(tracks.map { $0?.albumID }) (expected "
                + "[1, 1, nil]) or the unrelated reference / user data changed"); return false
        }
        guard try scopedCheckCatchesOnlyAlbumReferences() else {
            printFail(number, "ALB-06: Schema.checkReferences(into: albums) missed a dangling album link or "
                + "tripped on an unrelated one"); return false
        }
        printPass(number, "ALB-06 (A3) v7 checks only the references it can break: a v6 store with a dangling "
            + "tracks.artwork_key migrates; album rows differing only by year merge onto the lowest id, the "
            + "other ids kept (no SET NULL cascade); a song on a missing album row is unlinked; the scoped "
            + "check throws on a dangling link INTO albums and ignores one elsewhere")
        return true
    } catch {
        printFail(number, "ALB-06 threw: \(error)"); return false
    }
}

/// On a fresh v7 schema: `checkReferences(into: "albums")` ignores a dangling `artwork_key` and
/// throws on a dangling `album_id`.
private func scopedCheckCatchesOnlyAlbumReferences() throws -> Bool {
    let queue = try foreignKeysOffQueue()
    try fullMigrator().migrate(queue)
    return try queue.write { db in
        try db.execute(sql: "INSERT INTO tracks(id, url, name, format, file_size, mtime, artwork_key, date_added) "
            + "VALUES (1, '/x/a.flac', 'a', 'FLAC', 1, 1, 'gone-hash', 1);")
        try Schema.checkReferences(db, into: "albums") // an unrelated dangling reference: no throw
        try db.execute(sql: "UPDATE tracks SET album_id = 42 WHERE id = 1;")
        do {
            try Schema.checkReferences(db, into: "albums")
            return false
        } catch {
            return true
        }
    }
}

// MARK: - ALB-07 (B1) — an offline file stays pending

func checkOfflineFileStaysPending(number: Int, url: URL) async -> Bool {
    let cacheDir = cacheDirectory(beside: url, "alb07")
    defer { try? FileManager.default.removeItem(at: cacheDir) }
    do {
        let store = try await LibraryStore(url: url, appBuild: "verify")
        let cache = ArtworkCache(directory: cacheDir)
        let caseRoot = try ScanFixtureBuilder.makeCaseRoot("alb07")
        let library = caseRoot.appendingPathComponent("Lib", isDirectory: true)
        let other = caseRoot.appendingPathComponent("Other", isDirectory: true)
        let songs = [
            song("Album/a1.flac", songTags("Ann", album: "Tagged", albumArtist: "The Band")),
            song("Album/a2.flac", songTags("Bob", album: "Tagged", albumArtist: "The Band")),
            song("Comp/c1.flac", songTags("Cat", album: "Comp", compilation: true)),
            song("Comp/c2.flac", songTags("Cat", album: "Comp", compilation: true)),
        ]
        for (index, spec) in songs.enumerated() {
            try ScanFixtureBuilder.writeFile(at: library, subdirs: spec.folders, fileName: spec.file,
                                             byteCount: 20 + index)
        }
        // A file that IS there but reads nothing (not in the tag table) — still marked (anti-loop).
        try ScanFixtureBuilder.writeFile(at: caseRoot, subdirs: ["Other"], fileName: "broken.flac", byteCount: 40)
        let extractor = PresentFilesExtractor(tags: TagTableExtractor(tags: Dictionary(
            uniqueKeysWithValues: songs.map { ($0.file, $0.meta) }
        )))
        let libraryID = try await store.addRoot(library)
        let otherID = try await store.addRoot(other)
        for (root, id) in [(library, libraryID), (other, otherID)] {
            _ = try await LibraryScanner().scan(root: root, folderID: id, into: store)
        }
        // The launch re-read runs while the library folder is moved away (unmounted volume).
        let away = caseRoot.appendingPathComponent("Lib-away", isDirectory: true)
        try FileManager.default.moveItem(at: library, to: away)
        try await MetadataScanner().run(generation: store.beginScanGeneration(), into: store, cache: cache,
                                        extractor: extractor)
        let offlinePending = try await store.tracksNeedingMetadata(limit: 100, inFolder: libraryID).count
        let brokenPending = try await store.tracksNeedingMetadata(limit: 100, inFolder: otherID).count
        guard offlinePending == songs.count, brokenPending == 0 else {
            printFail(number, "ALB-07: offline pass left \(offlinePending)/\(songs.count) offline songs pending "
                + "and \(brokenPending) unreadable present files pending (expected all / 0)"); return false
        }
        // It comes back; the app's rescan sees every file unchanged — and still reads their tags.
        try FileManager.default.moveItem(at: away, to: library)
        let rescan = try await LibraryScanner().scan(root: library, folderID: libraryID, into: store)
        try await MetadataScanner().run(generation: rescan.generation, into: store, cache: cache, extractor: extractor)
        guard try await store.tracksNeedingMetadata(limit: 100).isEmpty,
              try await expectAlbums(store, ["Tagged": ["The Band ×2"], "Comp": ["\(variousArtistsName) ×2"]],
                                     "after the remount", number: number) else {
            printFail(number, "ALB-07: after the remount the songs were not re-read"); return false
        }
        printPass(number, "ALB-07 (B1) an offline file stays pending: a pass with the library folder moved away "
            + "marks none of its songs (a present-but-unreadable file is still marked — anti-loop); after the "
            + "remount a rescan with every file unchanged reads them all — the album-artist tag and the "
            + "compilation flag land")
        return true
    } catch {
        printFail(number, "ALB-07 threw: \(error)"); return false
    }
}

// MARK: - ALB-08 (B2) — one shared title costs a pass nothing extra

func checkOneTitlePassCost(number: Int, url: URL) async -> Bool {
    do {
        let shared = try await timedReRead(url: url, label: "alb08-shared") { _ in "Unknown Album" }
        let distinctURL = url.deletingLastPathComponent()
            .appendingPathComponent("alb08-distinct-\(UUID().uuidString).sqlite3")
        let distinct = try await timedReRead(url: distinctURL, label: "alb08-distinct") { "Album \($0)" }
        // Before the fix the shared-title re-read regrouped every same-title song per write: ~30× the
        // distinct-title time (22.6 s vs ~0.7 s on the founder's Mac). A linear pass stays within 3× + 2 s.
        guard shared.seconds <= 3 * distinct.seconds + 2, shared.albums == 100, distinct.albums == 100 else {
            printFail(number, "ALB-08: 1,000 songs on ONE title re-read in \(shared.seconds) s vs "
                + "\(distinct.seconds) s "
                + "on 100 titles (albums \(shared.albums) / \(distinct.albums), expected 100 each)"); return false
        }
        printPass(number, "ALB-08 (B2) one shared title costs a pass nothing extra: 1,000 'Unknown Album' songs in "
            + "100 folders re-read in \(String(format: "%.2f", shared.seconds)) s vs "
            + "\(String(format: "%.2f", distinct.seconds)) s for 100 titles (bound 3× + 2 s) — no per-write regroup")
        return true
    } catch {
        printFail(number, "ALB-08 threw: \(error)"); return false
    }
}

/// Scan + read 1,000 songs (10 per folder, the album title of folder n is `title(n)`), then queue
/// every song again (a derived-data bump) and time the re-read pass. Returns its seconds and the
/// album count.
private func timedReRead(
    url: URL, label: String, title: (Int) -> String
) async throws -> (seconds: Double, albums: Int) {
    let songs = (0 ..< 1000).map { index in
        song("F\(index / 10)/s\(index).flac", songTags("Artist \(index / 10)", album: title(index / 10)))
    }
    let fixture = try await AlbumFixture(label, url: url, songs: songs)
    try queueEverySongForReRead(storeAt: url)
    let start = Date()
    try await fixture.rescan()
    return try (Date().timeIntervalSince(start), await fixture.store.albums().count)
}

/// Queue every song of the store at `url` for a tag re-read — what a derived-data bump does —
/// through a second connection.
private func queueEverySongForReRead(storeAt url: URL) throws {
    let queue = try DatabaseQueue(path: url.path)
    try queue.write { db in try db.execute(sql: "UPDATE tracks SET metadata_scanned = 0;") }
    try queue.close()
}

// MARK: - ALB-09 (B3) — a folder removed mid-pass

/// Removes root `folderID` the moment the pass reads a song under `prefix` — the folder is removed
/// while that song's extraction is in flight, so its write lands after the delete.
private struct RemovingExtractor: MetadataExtracting {
    let tags: TagTableExtractor
    let store: LibraryStore
    let folderID: Int64
    let prefix: String

    func extract(from url: URL) async -> ExtractedMetadata? {
        if url.path.hasPrefix(prefix) {
            try? await store.removeRoot(id: folderID)
        }
        return await tags.extract(from: url)
    }
}

func checkFolderRemovedMidPass(number: Int, url: URL) async -> Bool {
    let cacheDir = cacheDirectory(beside: url, "alb09")
    defer { try? FileManager.default.removeItem(at: cacheDir) }
    do {
        let store = try await LibraryStore(url: url, appBuild: "verify")
        let cache = ArtworkCache(directory: cacheDir)
        let caseRoot = try ScanFixtureBuilder.makeCaseRoot("alb09")
        var table: [String: TrackMetadata] = [:]
        var roots: [String: (url: URL, id: Int64)] = [:]
        for name in ["Gone", "Kept", "Later", "Other"] {
            let root = caseRoot.appendingPathComponent(name, isDirectory: true)
            for index in 0 ..< 4 {
                let file = "\(name.lowercased())\(index).flac"
                try ScanFixtureBuilder.writeFile(at: caseRoot, subdirs: [name], fileName: file, byteCount: 10 + index)
                table[file] = TrackMetadata(artistName: "\(name) Artist", albumTitle: "\(name) Album",
                                            genres: ["\(name) Genre"])
            }
            let id = try await store.addRoot(root)
            roots[name] = (root, id)
        }
        guard let gone = roots["Gone"], let kept = roots["Kept"], let later = roots["Later"],
              let other = roots["Other"] else { return false }
        for root in [gone, kept] {
            _ = try await LibraryScanner().scan(root: root.url, folderID: root.id, into: store)
        }
        let removing = RemovingExtractor(tags: TagTableExtractor(tags: table), store: store, folderID: gone.id,
                                         prefix: PathNormalizer.normalizedString(for: gone.url))
        try await MetadataScanner().run(generation: store.beginScanGeneration(), into: store, cache: cache,
                                        extractor: removing)
        let genres = try await Set(store.genres().map(\.name))
        guard try await store.trackCount(inFolder: gone.id) == 0,
              try await store.tracksNeedingMetadata(limit: 100).isEmpty,
              genres == ["Kept Genre"],
              try await expectAlbums(store, ["Kept Album": ["Kept Artist ×4"]], "folder removed mid-pass",
                                     number: number) else {
            printFail(number, "ALB-09: the removed folder's songs left rows / genres (\(genres)) or the pass "
                + "did not finish the kept folder"); return false
        }
        // A live reconcile's pass is scoped to its root: Later's pending songs are read, Other's stay.
        for root in [later, other] {
            _ = try await LibraryScanner().scan(root: root.url, folderID: root.id, into: store)
        }
        try await MetadataScanner().run(generation: store.beginScanGeneration(), into: store, cache: cache,
                                        extractor: TagTableExtractor(tags: table), inFolder: later.id)
        guard try await store.tracksNeedingMetadata(limit: 100, inFolder: later.id).isEmpty,
              try await store.tracksNeedingMetadata(limit: 100, inFolder: other.id).count == 4 else {
            printFail(number, "ALB-09: a root-scoped pass did not read exactly its own root's pending songs")
            return false
        }
        printPass(number, "ALB-09 (B3) a folder removed mid-pass: the pass finishes, writes nothing (no genre, "
            + "artist or album) for the removed songs, and reads the kept folder; a root-scoped (reconcile) "
            + "pass reads its own root's pending songs and leaves another root's alone")
        return true
    } catch {
        printFail(number, "ALB-09 threw: \(error)"); return false
    }
}

// MARK: - ALB-10 (B4) — no zero-song album

func checkNoZeroSongAlbum(number: Int, url: URL) async -> Bool {
    let cacheDir = cacheDirectory(beside: url, "alb10")
    defer { try? FileManager.default.removeItem(at: cacheDir) }
    do {
        let fixture = try await AlbumFixture("alb10", url: url, songs: [
            song("F/solo.flac", songTags("Ann", album: "Solo")), song("F/lone.flac", songTags("Ann", album: "Lone")),
            song("F/p1.flac", songTags("Ann", album: "Pair")), song("F/p2.flac", songTags("Ann", album: "Pair")),
        ])
        let store = fixture.store
        // A single retag that empties "Lone" deletes it in the same write — before any sweep.
        guard let lone = try await store.track(url: fixture.fileURL("F/lone.flac")) else { return false }
        try await store.applyMetadata(songTags("Ann", album: "Pair"), forTrack: lone.id)
        guard try await expectAlbums(store, ["Solo": ["Ann ×1"], "Pair": ["Ann ×3"]], "a retag emptied an album",
                                     number: number),
            try await store.countRows(inTable: "albums") == 2 else { return false }
        // The file "solo.flac" is retagged on disk too; a pass reading it is cut off after that one
        // write (a quit): no album is left empty, and the regroup is owed — durably, across a reopen.
        try fixture.add(song("F/solo.flac", songTags("Ann", album: "Pair"))) // rewrites it: a new size
        let scan = try await LibraryScanner().scan(root: fixture.root, folderID: fixture.folderID, into: store)
        guard try await cancelPassAfterFirstApply(
            store, cache: ArtworkCache(directory: cacheDir), gen: scan.generation,
            extractor: TagTableExtractor(tags: fixture.tags), number: number
        ) else { return false }
        let reopened = try await LibraryStore(url: url, appBuild: "verify")
        guard try await !reopened.albums().contains(where: { $0.trackCount == 0 }),
              try await reopened.isAlbumRegroupOwed() else {
            printFail(number, "ALB-10: a pass cut off midway left a zero-song album or no durable regroup debt")
            return false
        }
        // The next launch runs the pass (nothing pending) for the debt: everything settles.
        try await MetadataScanner().run(generation: reopened.beginScanGeneration(), into: reopened,
                                        cache: ArtworkCache(directory: cacheDir),
                                        extractor: TagTableExtractor(tags: [:]))
        guard try await expectAlbums(reopened, ["Pair": ["Ann ×4"]], "after the owed regroup", number: number),
              try await !reopened.isAlbumRegroupOwed() else { return false }
        printPass(number, "ALB-10 (B4) no zero-song album: a retag that empties an album deletes it in the same "
            + "write; a pass cut off after a write leaves every album with its songs (no per-write album "
            + "work) and records the regroup debt, which survives a reopen and the next pass settles")
        return true
    } catch {
        printFail(number, "ALB-10 threw: \(error)"); return false
    }
}

// MARK: - Helpers

private extension Array {
    /// `map` with an async throwing transform, in order.
    func asyncMap<T>(_ transform: (Element) async throws -> T) async rethrows -> [T] {
        var mapped: [T] = []
        mapped.reserveCapacity(count)
        for element in self {
            try await mapped.append(transform(element))
        }
        return mapped
    }
}
