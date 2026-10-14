import Foundation
import GRDB
import LibraryBrowseKit
import LibraryScan
@testable import LibraryStore
import Testing

// P5a panel — UNCOMMITTED adversarial/property tests: migration DATA convergence from every
// historical stop, sort orders against an independent oracle, the two album-year tie rules.

@Suite("P5a store — migrations, sort orders, album year", .serialized)
struct P5aStoreBreakTests {
    // MARK: Migrations

    /// From every historical version k (1…6): user data written at k survives the real open path
    /// (look-first, backup, migrate) to v7, and the schema equals a fresh install's.
    @Test("MIG-1: user data survives the upgrade from every historical version", arguments: 1 ... 6)
    func upgradeFromEveryVersion(from version: Int) async throws {
        let base = P5aFixture.base("mig1-v\(version)")
        defer { try? FileManager.default.removeItem(at: base) }
        let url = base.appendingPathComponent("library.sqlite3")
        do {
            let queue = try DatabaseQueue(path: url.path)
            try LibraryStore.makeMigrator(appBuild: "old", through: version).migrate(queue)
            try await queue.write { db in
                try db.execute(sql: "INSERT INTO folders(path, is_root) VALUES ('/Music', 1);")
                for index in 1 ... 5 {
                    try db.execute(sql: """
                    INSERT INTO tracks(id, url, folder_id, relative_path, name, format, file_size, mtime,
                                       date_added, last_seen_scan, play_count, loved, rating)
                    VALUES (?, ?, 1, '', ?, 'FLAC', 10, 1, 1, 1, ?, ?, ?);
                    """, arguments: [index * 10, "/Music/s\(index).flac", "s\(index)", index, index % 2, index])
                }
                if version >= 3 {
                    try db.execute(sql: "INSERT INTO playlists(id, name, is_builtin, created_at) VALUES (7, 'Mine', 0, 1);")
                    for (position, track) in [30, 10, 50].enumerated() {
                        try db.execute(sql: "INSERT INTO playlist_entries(playlist_id, track_id, position, added_at) VALUES (7, ?, ?, 1);",
                                       arguments: [track, position])
                    }
                }
            }
        }
        let store = try await LibraryStore(url: url, appBuild: "p5a")
        var plays: [Int64] = []
        for index in 1 ... 5 {
            plays.append(try await store.userState(trackID: Int64(index * 10))?.playCount ?? -1)
        }
        let entries = version >= 3 ? try await store.entries(inPlaylist: 7).map(\.trackID) : []
        let schema = await store.schemaVersion()
        let backups = try FileManager.default.contentsOfDirectory(atPath: base.path).filter { $0.contains(".pre-v") }
        print("P5A MIG-1 from v\(version): schema=\(schema) plays=\(plays) entries=\(entries) backups=\(backups.count)")
        #expect(schema == 7)
        #expect(plays == [1, 2, 3, 4, 5])
        if version >= 3 {
            #expect(entries == [30, 10, 50])
        }
        #expect(backups.count >= 1)
    }

    // MARK: Sort orders

    /// Every `TrackSort` must be a strict total order matching its documented spec. The oracle is
    /// written from the docs (LibrarySortOrders.swift), not from the SQL: NOCASE = ASCII-only fold
    /// (sqlite.org/datatype3.html#collation), NULL placement as documented, id breaks ties in the
    /// sort's direction.
    @Test("SORT-1: each TrackSort equals its spec on random data with ties, NULLs and non-ASCII")
    func sortOrdersMatchSpec() async throws {
        let base = P5aFixture.base("sort1")
        defer { try? FileManager.default.removeItem(at: base) }
        let music = base.appendingPathComponent("Music", isDirectory: true)
        var generator = SeededGenerator(seed: 0x5A5A)
        let count = 160
        let files = try P5aFixture.files(in: music, count: count)
        for (index, file) in files.enumerated() {
            let size = Int.random(in: 1 ... 4, using: &generator)
            try Data(repeating: UInt8(index & 0xFF), count: size).write(to: file)
        }
        let store = try await P5aFixture.store(base)
        let root = try await store.addRoot(music)
        let scan = try await LibraryScanner().scan(root: music, folderID: root, into: store)
        let titles = ["abc", "ABC", "Abd", "Émile", "émile", "Zoë", "zoe", "Ångström", "track 10", "track 2", "", "ගීතය"]
        let artists: [String?] = [nil, "Adele", "adele", "ABBA", "Æther", "Björk", "björk"]
        let albums: [String?] = [nil, "Blue", "blue", "Été", "Zed"]
        for file in files {
            let id = try #require(try await store.track(url: file)).id
            let meta = TrackMetadata(
                title: titles.randomElement(using: &generator)!.nilIfEmpty,
                artistName: artists.randomElement(using: &generator)!,
                albumTitle: albums.randomElement(using: &generator)!,
                year: [nil, 1990, 1990, 2001, 0].randomElement(using: &generator)!,
                trackNo: [nil, 1, 2, 2, 10].randomElement(using: &generator)!,
                discNo: [nil, 1, 2].randomElement(using: &generator)!,
                durationMs: [0, 1000, 1000, 2000].randomElement(using: &generator)!
            )
            try await store.applyExtractedResult(trackID: id, meta: meta, artwork: nil, generation: scan.generation)
            try await store.setUserState(trackID: id, playCount: Int64.random(in: 0 ... 3, using: &generator),
                                         loved: false, rating: nil)
        }
        _ = try await store.refreshDerivedFacets()
        let rows = try await store.allTracksDisplay(sortedBy: .name)
        #expect(rows.count == count)

        var failures: [String] = []
        let sorts: [TrackSort] = [
            .name, .titleAsc, .titleDesc, .artistNameAsc, .artistNameDesc, .albumTitleAsc, .albumTitleDesc,
            .durationAsc, .durationDesc, .dateAddedAsc, .dateAddedDescending, .formatAsc, .formatDesc,
            .yearAsc, .yearDesc, .discNoAsc, .discNoDesc, .trackNoAsc, .trackNoDesc, .fileSizeAsc, .fileSizeDesc,
            .playCountAsc, .playCountDesc, .artistAlbumTrack, .albumArtistAsc, .albumArtistDesc,
        ]
        for sort in sorts {
            let got = try await store.allTracksDisplay(sortedBy: sort).map(\.id)
            let expected = rows.sorted { Oracle.precedes($0, $1, sort) }.map(\.id)
            if got != expected {
                let firstDiff = zip(got, expected).enumerated().first { $0.element.0 != $0.element.1 }?.offset ?? -1
                failures.append("\(sort)@\(firstDiff)")
            }
            if Set(got).count != count {
                failures.append("\(sort): not a permutation")
            }
        }
        print("P5A SORT-1 \(sorts.count) orders checked; mismatches: \(failures)")
        #expect(failures.isEmpty)
    }

    // MARK: Album year

    private struct Song: AlbumGroupable {
        let albumID: Int64?
        let albumName: String?
        let year: Int?
        let albumYear: Int?
    }

    @Test("YEAR-1: the store and the facet pages pick the same year for a tie")
    func albumYearTie() {
        let years: [Int?] = [1994, 1995, 1995, 1994]
        let store = AlbumGrouping.dominantYear(years)
        let songs = years.map { Song(albumID: 1, albumName: "A", year: $0, albumYear: nil) }
        let page = FacetAlbumGrouping.sections(from: songs).first?.albumYear
        // Oracle: brute force, documented store rule (max count, tie → latest).
        let counts = Dictionary(grouping: years.compactMap(\.self), by: { $0 }).mapValues(\.count)
        let best = counts.values.max() ?? 0
        let oracle = counts.filter { $0.value == best }.keys.max()
        print("P5A YEAR-1 store.dominantYear=\(String(describing: store)) facetPage=\(String(describing: page)) "
            + "oracle(latest)=\(String(describing: oracle))")
        #expect(store == oracle)
        #expect(page == store, "the facet page and the store disagree on a tied album year")
    }

    @Test("YEAR-2: dominantYear equals a brute-force oracle on random inputs")
    func dominantYearProperty() {
        var generator = SeededGenerator(seed: 42)
        var bad = 0
        for _ in 0 ..< 20000 {
            let years: [Int?] = (0 ..< Int.random(in: 0 ... 9, using: &generator)).map { _ in
                [nil, 0, -5, 1990, 1991, 1992, 2024].randomElement(using: &generator)!
            }
            let positive = years.compactMap { $0 }.filter { $0 > 0 }
            let counts = Dictionary(grouping: positive, by: { $0 }).mapValues(\.count)
            let best = counts.values.max()
            let oracle = best.map { top in counts.filter { $0.value == top }.keys.max()! }
            if AlbumGrouping.dominantYear(years) != oracle {
                bad += 1
            }
        }
        #expect(bad == 0)
    }
}

// MARK: - Oracle (from the documented spec, not the SQL)

enum Oracle {
    /// SQLite NOCASE: ASCII A–Z folded, then BINARY (memcmp of UTF-8).
    static func nocase(_ lhs: String, _ rhs: String) -> Int {
        func fold(_ string: String) -> [UInt8] {
            string.utf8.map { (65 ... 90).contains($0) ? $0 + 32 : $0 }
        }
        let left = fold(lhs)
        let right = fold(rhs)
        for (leftByte, rightByte) in zip(left, right) where leftByte != rightByte {
            return leftByte < rightByte ? -1 : 1
        }
        return left.count == right.count ? 0 : (left.count < right.count ? -1 : 1)
    }

    static func cmp<T: Comparable>(_ lhs: T, _ rhs: T) -> Int {
        lhs == rhs ? 0 : (lhs < rhs ? -1 : 1)
    }

    /// NULL-first for ascending, NULL-last for descending (SQLite default), unless `nullsLast`.
    static func optional<T: Comparable>(_ lhs: T?, _ rhs: T?, desc: Bool, nullsLast: Bool = false) -> Int {
        optional(lhs, rhs, desc: desc, nullsLast: nullsLast, compare: { cmp($0, $1) })
    }

    static func optional<T>(_ lhs: T?, _ rhs: T?, desc: Bool, nullsLast: Bool = false,
                            compare: (T, T) -> Int) -> Int {
        switch (lhs, rhs) {
        case (nil, nil): return 0
        case (nil, _): return (nullsLast || desc) ? 1 : -1
        case (_, nil): return (nullsLast || desc) ? -1 : 1
        case let (left?, right?): return desc ? -compare(left, right) : compare(left, right)
        }
    }

    static func precedes(_ lhs: LibraryTrackDisplay, _ rhs: LibraryTrackDisplay, _ sort: TrackSort) -> Bool {
        let keys = keys(lhs, rhs, sort)
        for key in keys where key != 0 {
            return key < 0
        }
        return false
    }

    // swiftlint:disable:next cyclomatic_complexity function_body_length
    static func keys(_ lhs: LibraryTrackDisplay, _ rhs: LibraryTrackDisplay, _ sort: TrackSort) -> [Int] {
        let idAsc = cmp(lhs.id, rhs.id)
        let title = { (track: LibraryTrackDisplay) in track.title }
        let fileName = { (track: LibraryTrackDisplay) in track.url.deletingPathExtension().lastPathComponent }
        let artist = { (track: LibraryTrackDisplay) -> String? in track.artistName.isEmpty ? nil : track.artistName }
        switch sort {
        case .name: return [nocase(fileName(lhs), fileName(rhs)), idAsc]
        case .titleAsc: return [nocase(title(lhs), title(rhs)), idAsc]
        case .titleDesc: return [-nocase(title(lhs), title(rhs)), -idAsc]
        case .artistNameAsc: return [optional(artist(lhs), artist(rhs), desc: false, nullsLast: true, compare: nocase), idAsc]
        case .artistNameDesc: return [optional(artist(lhs), artist(rhs), desc: true, nullsLast: true, compare: nocase), -idAsc]
        case .albumTitleAsc: return [optional(lhs.albumName, rhs.albumName, desc: false, nullsLast: true, compare: nocase), idAsc]
        case .albumTitleDesc: return [optional(lhs.albumName, rhs.albumName, desc: true, nullsLast: true, compare: nocase), -idAsc]
        case .durationAsc: return [cmp(lhs.durationMs, rhs.durationMs), idAsc]
        case .durationDesc: return [-cmp(lhs.durationMs, rhs.durationMs), -idAsc]
        case .dateAddedAsc: return [cmp(lhs.dateAdded, rhs.dateAdded), idAsc]
        case .dateAddedDescending: return [-cmp(lhs.dateAdded, rhs.dateAdded), -idAsc]
        case .formatAsc: return [nocase(lhs.format, rhs.format), idAsc]
        case .formatDesc: return [-nocase(lhs.format, rhs.format), -idAsc]
        case .yearAsc: return [optional(lhs.year, rhs.year, desc: false), idAsc]
        case .yearDesc: return [optional(lhs.year, rhs.year, desc: true), -idAsc]
        case .discNoAsc: return [optional(lhs.discNo, rhs.discNo, desc: false), idAsc]
        case .discNoDesc: return [optional(lhs.discNo, rhs.discNo, desc: true), -idAsc]
        case .trackNoAsc: return [optional(lhs.trackNo, rhs.trackNo, desc: false), idAsc]
        case .trackNoDesc: return [optional(lhs.trackNo, rhs.trackNo, desc: true), -idAsc]
        case .fileSizeAsc: return [cmp(lhs.fileSize, rhs.fileSize), idAsc]
        case .fileSizeDesc: return [-cmp(lhs.fileSize, rhs.fileSize), -idAsc]
        case .playCountAsc: return [cmp(lhs.playCount, rhs.playCount), idAsc]
        case .playCountDesc: return [-cmp(lhs.playCount, rhs.playCount), -idAsc]
        case .artistAlbumTrack:
            return [optional(artist(lhs), artist(rhs), desc: false, compare: nocase),
                    optional(lhs.albumName, rhs.albumName, desc: false, compare: nocase),
                    optional(lhs.discNo, rhs.discNo, desc: false), optional(lhs.trackNo, rhs.trackNo, desc: false), idAsc]
        case .albumArtistAsc: return [optional(lhs.albumArtistName, rhs.albumArtistName, desc: false, nullsLast: true, compare: nocase), idAsc]
        case .albumArtistDesc: return [optional(lhs.albumArtistName, rhs.albumArtistName, desc: true, nullsLast: true, compare: nocase), -idAsc]
        default: return [idAsc]
        }
    }
}

struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }
}

extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

@Suite("P5a playlist rules")
struct P5aPlaylistRuleTests {
    /// The store's reorder and the kit's ListOrder must agree on every input (the map: "keep in
    /// step", no cross-test). Random partial / duplicate / foreign orders on a real store.
    @Test("PL-1: reorderPlaylist == ListOrder.applying on random orders")
    func reorderMatchesKit() async throws {
        let base = P5aFixture.base("pl1")
        defer { try? FileManager.default.removeItem(at: base) }
        let music = base.appendingPathComponent("Music", isDirectory: true)
        let files = try P5aFixture.files(in: music, count: 8)
        let store = try await P5aFixture.store(base)
        let root = try await store.addRoot(music)
        _ = try await LibraryScanner().scan(root: music, folderID: root, into: store)
        var trackIDs: [Int64] = []
        for file in files {
            trackIDs.append(try #require(try await store.track(url: file)).id)
        }
        let playlist = try await store.createPlaylist(name: "Order")
        _ = try await store.appendEntries(playlistID: playlist, trackIDs: trackIDs + trackIDs.prefix(3))
        var generator = SeededGenerator(seed: 7)
        var mismatches = 0
        for _ in 0 ..< 300 {
            let before = try await store.entries(inPlaylist: playlist)
            let pool = before.map(\.id) + [999_999, -1]
            let order = (0 ..< Int.random(in: 0 ... 14, using: &generator)).map { _ in pool.randomElement(using: &generator)! }
            let expected = ListOrder.applying(order, to: before, id: \.id).map(\.id)
            try await store.reorderPlaylist(id: playlist, entryIDsInOrder: order)
            let after = try await store.entries(inPlaylist: playlist).map(\.id)
            if after != expected {
                mismatches += 1
            }
        }
        let names = ["Été", "été", "ÉTÉ", "Cafe\u{301}", "Café"]
        var created: [String] = []
        for name in names {
            if (try? await store.createPlaylist(name: name)) != nil {
                created.append(name)
            }
        }
        print("P5A PL-1 reorder mismatches=\(mismatches)/300; case/normalization variants accepted as distinct "
            + "playlists: \(created.count)/\(names.count)")
        #expect(mismatches == 0)
    }
}
