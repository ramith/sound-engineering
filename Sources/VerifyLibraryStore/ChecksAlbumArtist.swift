// ChecksAlbumArtist — S10.8 C2 album artists (docs/sprints/s10-8-glass-sweep-plan.md §E Sprint C):
//   ALB-01 the folder fallback — an album with no album-artist tag groups by title + year + folder
//          and is credited to its songs' shared artist (or "Various Artists" / Unknown Artist), and
//          an incremental scan re-credits it when a song joins or leaves;
//   ALB-02 a compilation does not split — the flag is read by BOTH extractors (real files), and a
//          flagged, mixed-artist, two-disc compilation is ONE "Various Artists" album;
//   ALB-05 same-title albums in different folders do not merge — and a folder move regroups.
// (ALB-03 and ALB-04 live in ChecksAlbumArtistData.swift.)
//
// Every case drives the app's OWN pipeline: real files on disk → `LibraryScanner.scan` →
// `MetadataScanner.run` (whose end-of-pass step regroups albums + reaps orphans), with a stub
// extractor answering each file's tags from a table — so no audio is needed, yet nothing about
// grouping is simulated. Expected albums are compared EXACTLY (title → credits × song counts), so
// a ghost zero-song album or a split shows up as a mismatch.

import Foundation
import LibraryScan
import LibraryStore

// MARK: - Registration

func albumArtistCheckCases() -> [CheckCase] {
    [
        CheckCase(label: "alb01-folder-fallback", run: checkAlbumFolderFallback),
        CheckCase(label: "alb02-compilation-no-split", run: checkCompilationDoesNotSplit),
        CheckCase(label: "alb03-reread-keeps-user-data", run: checkReReadKeepsUserData),
        CheckCase(label: "alb04-one-missing-artist-string", run: checkOneMissingArtistString),
        CheckCase(label: "alb05-same-title-folders-dont-merge", run: checkSameTitleFoldersDoNotMerge),
    ]
}

// MARK: - Shared fixture (real files + the real scan → metadata pass)

/// Answers each file's tags from a table keyed by FILE NAME (unique within a fixture). A file
/// missing from the table extracts as unreadable (nil), like a vanished file.
struct TagTableExtractor: MetadataExtracting {
    let tags: [String: TrackMetadata]

    func extract(from url: URL) async -> ExtractedMetadata? {
        tags[url.lastPathComponent].map { ExtractedMetadata(metadata: $0, artwork: nil) }
    }
}

/// One song of a C2 fixture: its path under the case root ("Folder/…/file.flac") and its tags.
/// File names are unique within a fixture (the stub extractor keys on them).
struct SongSpec {
    let path: String
    let meta: TrackMetadata

    var file: String {
        (path as NSString).lastPathComponent
    }

    var folders: [String] {
        Array(path.split(separator: "/").dropLast().map(String.init))
    }
}

/// A song at `path` with `meta` — the fixture tables' shorthand.
func song(_ path: String, _ meta: TrackMetadata) -> SongSpec {
    SongSpec(path: path, meta: meta)
}

/// A scanned library under a real case root: the store, the registered root, and the tag table the
/// stub extractor answers from. `rescan()` runs the app's pipeline again (an incremental scan).
final class AlbumFixture {
    let store: LibraryStore
    let root: URL
    let folderID: Int64
    private let cacheDir: URL
    private(set) var tags: [String: TrackMetadata] = [:]
    /// Distinct sizes per file so the move matcher never sees two files with one signature.
    private var nextByteCount = 16

    init(_ label: String, url: URL, songs: [SongSpec]) async throws {
        store = try await LibraryStore(url: url, appBuild: "verify")
        root = try ScanFixtureBuilder.makeCaseRoot(label)
        cacheDir = url.deletingLastPathComponent()
            .appendingPathComponent("alb-cache-\(UUID().uuidString)", isDirectory: true)
        folderID = try await store.addRoot(root)
        for song in songs {
            try add(song)
        }
        try await rescan()
    }

    deinit {
        try? FileManager.default.removeItem(at: cacheDir)
    }

    /// Write `song`'s file (no scan yet) and return its URL.
    @discardableResult
    func add(_ song: SongSpec) throws -> URL {
        tags[song.file] = song.meta
        nextByteCount += 1
        return try ScanFixtureBuilder.writeFile(at: root, subdirs: song.folders, fileName: song.file,
                                                byteCount: nextByteCount)
    }

    /// The URL of the file at `path` under the case root.
    func fileURL(_ path: String) -> URL {
        root.appendingPathComponent(path, isDirectory: false)
    }

    /// The app's pipeline: structural scan (move-matching, orphan sweep), then the metadata pass.
    func rescan() async throws {
        let result = try await LibraryScanner().scan(root: root, folderID: folderID, into: store)
        try await MetadataScanner().run(generation: result.generation, into: store,
                                        cache: ArtworkCache(directory: cacheDir),
                                        extractor: TagTableExtractor(tags: tags))
    }
}

/// Every album in the store as `title → sorted ["<credit> ×<songs>"]` — compared EXACTLY against
/// the expectation, so a split ("… ×1, … ×1"), a merge, or a zero-song ghost ("… ×0") all fail.
func albumSummary(_ store: LibraryStore) async throws -> [String: [String]] {
    var summary: [String: [String]] = [:]
    for album in try await store.albums() {
        summary[album.title, default: []].append("\(album.albumArtist) ×\(album.trackCount)")
    }
    return summary.mapValues { $0.sorted() }
}

/// Compare the store's albums with `expected`; on a mismatch print both and return false.
func expectAlbums(_ store: LibraryStore, _ expected: [String: [String]], _ step: String,
                  number: Int) async throws -> Bool {
    let actual = try await albumSummary(store)
    guard actual == expected.mapValues({ $0.sorted() }) else {
        printFail(number, "\(step): albums \(actual) != expected \(expected)")
        return false
    }
    return true
}

/// Shorthand for a song's tags (no album-artist tag unless given).
func songTags(_ artist: String?, album: String, year: Int? = nil, albumArtist: String? = nil,
              compilation: Bool = false) -> TrackMetadata {
    TrackMetadata(title: nil, artistName: artist, albumTitle: album, albumArtistName: albumArtist,
                  isCompilation: compilation, year: year)
}

// MARK: - ALB-01 — the folder fallback

func checkAlbumFolderFallback(number: Int, url: URL) async -> Bool {
    do {
        let fixture = try await AlbumFixture("alb01", url: url, songs: [
            song("Solo/Album/s1.flac", songTags("Solo Artist", album: "Solo Album", year: 2010)),
            song("Solo/Album/s2.flac", songTags("Solo Artist", album: "Solo Album", year: 2010)),
            // A song with no artist neither adds nor removes one — the album stays Solo Artist's.
            song("Solo/Album/s3.flac", songTags(nil, album: "Solo Album", year: 2010)),
            song("Mixed/Party/m1.flac", songTags("Ann", album: "Party Mix", year: 2011)),
            song("Mixed/Party/m2.flac", songTags("Bob", album: "Party Mix", year: 2011)),
            song("Nobody/Untitled/n1.flac", songTags(nil, album: "Nameless")),
            song("Nobody/Untitled/n2.flac", songTags(nil, album: "Nameless")),
            // A TAGGED album is folder-independent, as before C2: two folders, one album.
            song("Tagged/Part A/t1.flac", songTags("Tag Band", album: "Tagged", year: 2012, albumArtist: "Tag Band")),
            song("Tagged/Part B/t2.flac", songTags("Tag Band", album: "Tagged", year: 2012, albumArtist: "Tag Band")),
        ])
        let base: [String: [String]] = [
            "Solo Album": ["Solo Artist ×3"], "Party Mix": ["\(variousArtistsName) ×2"],
            "Nameless": ["\(unknownArtistName) ×2"], "Tagged": ["Tag Band ×2"],
        ]
        guard try await expectAlbums(fixture.store, base, "first scan", number: number),
              try await soloAlbumListedUnderItsArtist(fixture.store, number: number) else { return false }

        // Incremental scan: a guest's song lands in the solo folder → the album turns
        // "Various Artists" in the same pass, and the vacated "Solo Artist" row is reaped.
        let guestSong = song("Solo/Album/s4.flac", songTags("Guest", album: "Solo Album", year: 2010))
        let guest = try fixture.add(guestSong)
        try await fixture.rescan()
        var joined = base
        joined["Solo Album"] = ["\(variousArtistsName) ×4"]
        guard try await expectAlbums(fixture.store, joined, "a guest song joined", number: number) else { return false }

        // …and when it leaves (a DELETION — no tag write sees it; the end-of-pass regroup does),
        // the album goes back to the shared artist.
        try FileManager.default.removeItem(at: guest)
        try await fixture.rescan()
        guard try await expectAlbums(fixture.store, base, "the guest song left", number: number),
              try await leftGroupRegroupsInTheSameWrite(fixture, number: number),
              try await spellingVariantsAreOneArtist(fixture, number: number) else { return false }

        printPass(number, "ALB-01 folder fallback: untagged albums group by title + year + folder and are "
            + "credited to the shared artist (a no-artist song doesn't change it), mixed artists → "
            + "\(variousArtistsName), no artists → \(unknownArtistName); a tagged album stays one across "
            + "folders; an incremental scan re-credits on join (→ VA) and on delete (→ the artist), no ghosts; "
            + "a retag re-credits the album it left in the same write; NFC/NFD/case spellings of one artist "
            + "are one credit, not \(variousArtistsName)")
        return true
    } catch {
        printFail(number, "ALB-01 threw: \(error)"); return false
    }
}

/// Per-commit consistency: retagging Bob's song onto another album (ONE tag write, no pass)
/// regroups the album it LEFT in that same write — "Party Mix" is Ann's at once, not VA until the
/// next pass (a pass cut off at quit would otherwise leave it wrong).
private func leftGroupRegroupsInTheSameWrite(_ fixture: AlbumFixture, number: Int) async throws -> Bool {
    let store = fixture.store
    guard let bob = try await store.track(url: fixture.fileURL("Mixed/Party/m2.flac")) else {
        printFail(number, "ALB-01: m2.flac missing"); return false
    }
    try await store.applyMetadata(songTags("Bob", album: "Bob Solo", year: 2011), forTrack: bob.id)
    guard let ann = try await store.track(url: fixture.fileURL("Mixed/Party/m1.flac")),
          let albumID = ann.albumID, try await store.album(id: albumID)?.albumArtist == "Ann" else {
        printFail(number, "ALB-01: after a retag, 'Party Mix' was not re-credited to Ann in the same write")
        return false
    }
    return true
}

/// One artist spelled three ways — NFC, NFD (a decomposed tag) and another case — is ONE artist for
/// the credit (not "Various Artists"), while the store still keeps the three exact-spelling rows
/// (S8 artist identity is untouched; merging them is a separate finding, C1's stress library).
private func spellingVariantsAreOneArtist(_ fixture: AlbumFixture, number: Int) async throws -> Bool {
    let spellings = ["Zo\u{00EB} \u{00C5}ngstr\u{00F6}m", "Zo\u{0065}\u{0308} \u{0041}\u{030A}ngstr\u{006F}\u{0308}m",
                     "zo\u{00EB} \u{00E5}ngstr\u{00F6}m"]
    for (index, spelling) in spellings.enumerated() {
        try fixture.add(song("Variants/Album/v\(index).flac", songTags(spelling, album: "Spelled", year: 2013)))
    }
    try await fixture.rescan()
    let key = AlbumGrouping.sameArtistKey(spellings[0])
    let spelled = try await fixture.store.albums().filter { $0.title == "Spelled" }
    let rows = try await fixture.store.artists().filter { AlbumGrouping.sameArtistKey($0.name) == key }
    guard spelled.count == 1, let album = spelled.first, album.trackCount == 3,
          AlbumGrouping.sameArtistKey(album.albumArtist) == key, rows.count == 3 else {
        printFail(number, "ALB-01: spelling variants credited \(spelled.map { "\($0.albumArtist) ×\($0.trackCount)" }) "
            + "(artist rows \(rows.count))")
        return false
    }
    return true
}

/// The derived credit is a real album-artist link: `albums(byArtist:)` lists the album.
private func soloAlbumListedUnderItsArtist(_ store: LibraryStore, number: Int) async throws -> Bool {
    guard let solo = try await store.artists().first(where: { $0.name == "Solo Artist" }),
          try await store.albums(byArtist: solo.id).map(\.title) == ["Solo Album"] else {
        printFail(number, "ALB-01: 'Solo Album' is not listed under Solo Artist (albums(byArtist:))")
        return false
    }
    return true
}

// MARK: - ALB-02 — a compilation does not split

func checkCompilationDoesNotSplit(number: Int, url: URL) async -> Bool {
    do {
        guard await bothExtractorsReadTheAlbumTags(number: number),
              discFoldersFoldIntoTheAlbum(number: number) else { return false }
        let fixture = try await AlbumFixture("alb02", url: url, songs: [
            // A flagged, mixed-artist compilation ripped one folder per disc.
            song("Comp/Hits/CD 1/c1.flac", songTags("Ann", album: "Hits", year: 2015, compilation: true)),
            song("Comp/Hits/CD 1/c2.flac", songTags("Bob", album: "Hits", year: 2015, compilation: true)),
            song("Comp/Hits/CD 2/c3.flac", songTags("Cat", album: "Hits", year: 2015, compilation: true)),
            // The flag alone credits "Various Artists", even when every song is by one artist.
            song("Best/Of/b1.flac", songTags("Dan", album: "Best Of Dan", compilation: true)),
            song("Best/Of/b2.flac", songTags("Dan", album: "Best Of Dan", compilation: true)),
        ])
        guard try await expectAlbums(fixture.store, [
            "Hits": ["\(variousArtistsName) ×3"], "Best Of Dan": ["\(variousArtistsName) ×2"],
        ], "compilations", number: number) else { return false }
        printPass(number, "ALB-02 a compilation does not split: the flag is read from a real m4a (AVFoundation "
            + "cpil) and flac (FFmpeg COMPILATION), absent on the plain fixtures, and both paths read the "
            + "album-artist tag (FLAC's normalised album_artist included); a flagged 3-artist "
            + "compilation across 'CD 1'/'CD 2' is ONE \(variousArtistsName) album, and a flagged "
            + "single-artist one is credited \(variousArtistsName) too")
        return true
    } catch {
        printFail(number, "ALB-02 threw: \(error)"); return false
    }
}

/// Both extraction paths read the two album-credit tags from REAL files: the compilation flag (and
/// not where it's absent), and the album-artist tag — which the FFmpeg path once dropped for every
/// FLAC (FFmpeg normalises Vorbis ALBUMARTIST to `album_artist`; found scanning the C1 stress
/// library), crediting tagged FLAC albums to "Unknown Artist" before C2.
private func bothExtractorsReadTheAlbumTags(number: Int) async -> Bool {
    let expected: [String: (flag: Bool, albumArtist: String?)] = [
        "compilation.m4a": (true, nil), "compilation.flac": (true, nil),
        "fixture.m4a": (false, "Verify Artist"), "fixture.flac": (false, "Verify Artist"),
    ]
    for (file, (flag, albumArtist)) in expected.sorted(by: { $0.key < $1.key }) {
        let fixture = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
            .appendingPathComponent("Tests/Fixtures/artwork-audio/\(file)", isDirectory: false)
        guard let read = await MetadataExtractor().extract(from: fixture) else {
            printFail(number, "ALB-02: \(file) could not be read — run `make regenerate-metadata-fixtures`")
            return false
        }
        guard read.metadata.isCompilation == flag, read.metadata.albumArtistName == albumArtist else {
            printFail(number, "ALB-02: \(file) read compilation=\(read.metadata.isCompilation) album artist="
                + "\(String(describing: read.metadata.albumArtistName)), expected \(flag) / "
                + "\(String(describing: albumArtist))")
            return false
        }
    }
    return true
}

/// A per-disc subfolder folds into its album folder; any other name does not.
private func discFoldersFoldIntoTheAlbum(number: Int) -> Bool {
    let cases: [(path: String, folder: String)] = [
        ("/M/Hits/CD 1/a.flac", "/M/Hits"), ("/M/Hits/Disc2/a.flac", "/M/Hits"),
        ("/M/Hits/disk 003/a.flac", "/M/Hits"), ("/M/Hits/cd-1/a.flac", "/M/Hits"),
        ("/M/Hits/a.flac", "/M/Hits"), ("/M/Hits/CD Collection/a.flac", "/M/Hits/CD Collection"),
        ("/M/Hits/Discography/a.flac", "/M/Hits/Discography"), ("/M/Hits/CD 1234/a.flac", "/M/Hits/CD 1234"),
    ]
    for (path, folder) in cases where AlbumGrouping.albumFolder(ofTrackPath: path) != folder {
        printFail(number, "ALB-02: album folder of \(path) is \(AlbumGrouping.albumFolder(ofTrackPath: path)), "
            + "expected \(folder)")
        return false
    }
    return true
}

// MARK: - ALB-05 — same-title albums in different folders do not merge

func checkSameTitleFoldersDoNotMerge(number: Int, url: URL) async -> Bool {
    do {
        let hits = "Greatest Hits"
        let fixture = try await AlbumFixture("alb05", url: url, songs: [
            song("A/\(hits)/x1.flac", songTags("Queen", album: hits, year: 1981)),
            song("A/\(hits)/x2.flac", songTags("Queen", album: hits, year: 1981)),
            song("B/\(hits)/y1.flac", songTags("Queen", album: hits, year: 1981)),
            song("B/\(hits)/y2.flac", songTags("Queen", album: hits, year: 1981)),
            song("C/\(hits)/z1.flac", songTags("ABBA", album: hits, year: 1981)),
            // Contrast: the album-artist TAG keys folder-independently — these two ARE one album.
            song("D/\(hits)/t1.flac", songTags("Queen", album: hits, year: 1981, albumArtist: "Queen")),
            song("E/\(hits)/t2.flac", songTags("Queen", album: hits, year: 1981, albumArtist: "Queen")),
        ])
        let expected = [hits: ["ABBA ×1", "Queen ×2", "Queen ×2", "Queen ×2"]]
        guard try await expectAlbums(fixture.store, expected, "same-title folders", number: number) else {
            return false
        }

        // A Finder move of one folder: the songs keep their ids (move-matched) and their tags (no
        // re-read), so only the end-of-pass regroup can see the new folder — it must re-key them.
        let x1 = try await fixture.store.track(url: fixture.fileURL("A/\(hits)/x1.flac"))
        let y1 = try await fixture.store.track(url: fixture.fileURL("B/\(hits)/y1.flac"))
        try FileManager.default.moveItem(at: fixture.fileURL("B/\(hits)"), to: fixture.fileURL("B/Remaster"))
        try await fixture.rescan()
        let movedY1 = try await fixture.store.track(url: fixture.fileURL("B/Remaster/y1.flac"))
        let keptX1 = try await fixture.store.track(url: fixture.fileURL("A/\(hits)/x1.flac"))
        guard let x1, let y1, let movedY1, let keptX1, movedY1.id == y1.id,
              movedY1.albumID != y1.albumID, keptX1.albumID == x1.albumID else {
            printFail(number, "ALB-05: a folder move did not re-key the moved album (and only it)")
            return false
        }
        guard try await expectAlbums(fixture.store, expected, "after a folder move", number: number) else {
            return false
        }

        printPass(number, "ALB-05 same-title albums in different folders do not merge: two untagged Queen "
            + "'\(hits)' folders stay two albums, an ABBA one a third, while a tagged one spans two folders; "
            + "a Finder move keeps the song ids and re-keys only the moved album (old row reaped)")
        return true
    } catch {
        printFail(number, "ALB-05 threw: \(error)"); return false
    }
}
