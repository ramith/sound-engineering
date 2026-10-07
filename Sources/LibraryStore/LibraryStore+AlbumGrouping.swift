// LibraryStore+AlbumGrouping — assigning songs to albums (S10.8 C2), GRDB-backed.
//
// The pure rule is `AlbumGrouping`; this is where the store applies it. A regroup reads the
// in-scope songs' RAW album inputs (title, album-artist tag, compilation flag, artist, path),
// keys them with `AlbumGrouping.keys(for:)`, credits each group (its tag, else the derived
// "Various Artists" / shared artist / Unknown Artist), resolves the album row on the
// (title, album_artist_id, folder_key, edition_year) key, and rewrites `album_id` ONLY for songs whose album
// changed. Then each touched album's SHOWN year and cover follow its members
// (`AlbumGrouping.display` — fix round C1/C8). A pure function of stored columns — idempotent,
// cancel-safe, re-runnable.
//
// Who runs it (fix round B2 — a per-write regroup made a pass O(k²) in a title's song count):
//   • the WHOLE library, at the end of every metadata pass and in `removeRoot`
//     (`refreshDerivedFacets`) — the AUTHORITY. A pass's tag writes do no album work; each
//     records the debt (`schema_info.regroup_owed`) in its own transaction, the end-of-pass
//     regroup clears it, and a pass cut off before its end leaves it set, so the next launch runs
//     the end-of-pass step. The whole-library pass also catches what no tag write sees: songs that
//     MOVED folder (a Finder move keeps its tags) or were DELETED. Unchanged albums cost a read,
//     never a write;
//   • ONE song's titles, for a single tag write outside a pass (`applyMetadata`): every song
//     sharing its old or new album title — the smallest complete scope, since a tagged album's
//     year split (C2 final round) weighs all its folders, and adoption all of a folder's songs — and
//     then the display of every album touched. An album that write vacates is deleted in the same
//     write (B4).

import Foundation
import GRDB

public extension LibraryStore {
    // MARK: - SQL

    /// The grouping + display inputs of the songs in scope, in id order (so "the first song's
    /// spelling" is deterministic). The artist NAME rides along for the credit; the id-0 sentinel
    /// joins as no artist. `scope` is the WHERE condition.
    private static func selectGroupingRowsSQL(scope: String) -> String {
        "SELECT t.id, t.url, t.album_title, t.album_artist_tag, t.compilation, t.artist_id, ar.name, "
            + "t.album_id, t.year, t.disc_no, t.track_no, t.artwork_key FROM tracks t "
            + "LEFT JOIN artists ar ON ar.id = t.artist_id AND t.artist_id <> \(unknownArtistID) "
            + "WHERE \(scope) ORDER BY t.id;"
    }

    /// Every song that is, or should be, on an album — the whole-library regroup's scope.
    private static let wholeLibraryScope = "t.album_title IS NOT NULL OR t.album_id IS NOT NULL"
    /// One song plus every song with one of `titleCount` titles: the single-write scope.
    private static func titlesScope(titleCount: Int) -> String {
        guard titleCount > 0 else { return "t.id = ?" }
        return "t.id = ? OR t.album_title IN (\(databaseQuestionMarks(count: titleCount)))"
    }

    /// Insert an album row on its total key (race-safe; `ON CONFLICT … DO NOTHING`).
    private static let insertAlbumSQL =
        "INSERT INTO albums(title, album_artist_id, folder_key, edition_year) VALUES (?, ?, ?, ?) "
            + "ON CONFLICT(title, album_artist_id, folder_key, edition_year) DO NOTHING;"
    /// Select an album id by its total key.
    private static let selectAlbumIDByKeySQL =
        "SELECT id FROM albums WHERE title = ? AND album_artist_id = ? AND folder_key = ? AND edition_year = ?;"
    /// Point a song at its album (NULL = no album).
    private static let setTrackAlbumSQL = "UPDATE tracks SET album_id = ? WHERE id = ?;"
    /// Every album's shown year + cover.
    private static let selectAllAlbumDisplaySQL = "SELECT id, year, artwork_key FROM albums;"
    /// The shown year + cover of `count` albums (ids bound as placeholders).
    private static func selectAlbumDisplaySQL(count: Int) -> String {
        "SELECT id, year, artwork_key FROM albums WHERE id IN (\(databaseQuestionMarks(count: count)));"
    }

    /// The display inputs of every song on `count` albums (ids bound as placeholders).
    private static func selectMemberDisplaySQL(count: Int) -> String {
        "SELECT album_id, id, year, disc_no, track_no, artwork_key FROM tracks "
            + "WHERE album_id IN (\(databaseQuestionMarks(count: count)));"
    }

    /// Show an album's year + cover.
    private static let updateAlbumDisplaySQL = "UPDATE albums SET year = ?, artwork_key = ? WHERE id = ?;"
    /// Delete an album row (one a single write vacated).
    private static let deleteAlbumSQL = "DELETE FROM albums WHERE id = ?;"
    /// Record the end-of-pass regroup debt (written only when it flips).
    private static let markRegroupOwedSQL =
        "UPDATE schema_info SET regroup_owed = 1 WHERE id = 1 AND regroup_owed = 0;"
    /// Clear the debt — the whole-library regroup just ran.
    private static let clearRegroupOwedSQL =
        "UPDATE schema_info SET regroup_owed = 0 WHERE id = 1 AND regroup_owed <> 0;"
    /// Read the debt.
    private static let selectRegroupOwedSQL = "SELECT regroup_owed FROM schema_info WHERE id = 1;"

    // MARK: - Whole-library refresh (the end-of-pass step)

    /// Regroup every song's album, then reap the albums/artists/genres nothing references — ONE
    /// write. `MetadataScanner` runs it at the end of every pass (before the artwork sweep, so art
    /// a reaped album held is reclaimed the same pass); returns the sweep counts.
    @discardableResult
    func refreshDerivedFacets() async throws -> FacetSweepCounts {
        try await dbWriter.write { db in try self.refreshDerivedFacetsLocked(db) }
    }

    /// The body of `refreshDerivedFacets`, so `removeRoot` can fold it into its transaction. Clears
    /// the end-of-pass regroup debt in the same write.
    @discardableResult
    internal func refreshDerivedFacetsLocked(_ db: Database) throws -> FacetSweepCounts {
        let rows = try GroupingRow.fetchAll(db, sql: Self.selectGroupingRowsSQL(scope: Self.wholeLibraryScope))
        let members = try assignAlbums(db, rows)
        var shown: [Int64: AlbumDisplay] = [:]
        for row in try Row.fetchAll(db, sql: Self.selectAllAlbumDisplaySQL) {
            shown[row[0]] = AlbumDisplay(year: row[1], artworkKey: row[2])
        }
        for (albumID, songs) in members {
            try showDisplay(db, albumID: albumID, members: songs.map(\.display), shown: shown[albumID])
        }
        let counts = try sweepOrphanFacetsLocked(db)
        try db.execute(sql: Self.clearRegroupOwedSQL)
        return counts
    }

    /// Whether a metadata pass wrote tags whose end-of-pass regroup has not run yet (a pass cut
    /// off at quit) — the app then runs the pass at launch even with no song pending.
    func isAlbumRegroupOwed() async throws -> Bool {
        try await dbWriter.read { db in try (Int.fetchOne(db, sql: Self.selectRegroupOwedSQL) ?? 0) != 0 }
    }

    // MARK: - Single-write upkeep

    /// Record that a pass wrote tags whose albums the end-of-pass regroup will settle (in the
    /// writing transaction, so the debt can never be lost).
    internal func markAlbumRegroupOwedLocked(_ db: Database) throws {
        try db.execute(sql: Self.markRegroupOwedSQL)
    }

    /// Regroup after a single tag write outside a pass: the song and every song sharing one of
    /// `titles` (its old and new album title). Album identity never crosses titles, and within one
    /// title everything a write can change is there — the folder's adoption (C3), an untagged
    /// album's credit and year split, a tagged album's year split across all its folders. Then every
    /// touched album shows its members' year and cover, and an album the write vacated is deleted.
    internal func regroupOwnAlbumLocked(_ db: Database, trackID: Int64, titles: Set<String>) throws {
        let rows = try GroupingRow.fetchAll(
            db, sql: Self.selectGroupingRowsSQL(scope: Self.titlesScope(titleCount: titles.count)),
            arguments: [trackID] + StatementArguments(Array(titles))
        )
        let previous = Set(rows.compactMap(\.albumID))
        let touched = try previous.union(assignAlbums(db, rows).keys)
        try refreshAlbumDisplay(db, albumIDs: touched)
    }

    // MARK: - Regroup core

    /// Assign each row to the album its key names (resolving or creating the row), writing
    /// `album_id` only where it changes — a song with no key leaves its album. Returns the rows
    /// now on each album.
    private func assignAlbums(_ db: Database, _ rows: [GroupingRow]) throws -> [Int64: [GroupingRow]] {
        var groups: [AlbumGroupKey: [GroupingRow]] = [:]
        for (row, key) in zip(rows, AlbumGrouping.keys(for: rows)) {
            guard let key else {
                if row.albumID != nil {
                    try db.execute(sql: Self.setTrackAlbumSQL, arguments: [nil, row.id])
                }
                continue
            }
            groups[key, default: []].append(row)
        }
        var members: [Int64: [GroupingRow]] = [:]
        for (key, songs) in groups {
            let albumID = try resolveAlbumRow(db, key: key, artistID: albumArtistID(db, key: key, members: songs))
            for song in songs where song.albumID != albumID {
                try db.execute(sql: Self.setTrackAlbumSQL, arguments: [albumID, song.id])
            }
            members[albumID, default: []] += songs
        }
        return members
    }

    /// The album artist's row id for one group: its album-artist tag when it has one, else the
    /// credit `AlbumGrouping.derivedArtist` derives from the songs' artist names — a shared artist
    /// is the row of the first song so named, or (a primary artist no song is credited to alone,
    /// "X" of "X feat. Y" — C6) the row of that name.
    private func albumArtistID(_ db: Database, key: AlbumGroupKey, members: [GroupingRow]) throws -> Int64 {
        if let tag = key.taggedArtist {
            return try resolveArtist(db, named: tag)
        }
        let credit = AlbumGrouping.derivedArtist(
            anyCompilation: members.contains(where: \.isCompilation), artists: members.map(\.artistName)
        )
        switch credit {
        case .various:
            return try resolveArtist(db, named: variousArtistsName)
        case let .shared(name):
            if let artistID = members.first(where: { AlbumGrouping.presentArtist($0.artistName) == name })?.artistID {
                return artistID
            }
            return try resolveArtist(db, named: name)
        case .unknown:
            return unknownArtistID
        }
    }

    /// Resolve (query-then-insert) the album row for `key` credited to `artistID`. RACE-SAFE.
    private func resolveAlbumRow(_ db: Database, key: AlbumGroupKey, artistID: Int64) throws -> Int64 {
        let arguments: StatementArguments = [key.title, artistID, key.folderKey, key.editionYear]
        if let existing = try Int64.fetchOne(db, sql: Self.selectAlbumIDByKeySQL, arguments: arguments) {
            return existing
        }
        try db.execute(sql: Self.insertAlbumSQL, arguments: arguments)
        guard let id = try Int64.fetchOne(db, sql: Self.selectAlbumIDByKeySQL, arguments: arguments) else {
            throw SQLiteError.internalError(message: "resolveAlbumRow: row for key not found after insert")
        }
        return id
    }

    // MARK: - Display (year + cover)

    /// Bring each of `albumIDs` in line with ALL its members (read by `album_id`): its shown year
    /// and cover follow `AlbumGrouping.display`, and an album left with no song is deleted (B4 —
    /// no zero-song tile, even before the next facet sweep).
    private func refreshAlbumDisplay(_ db: Database, albumIDs: Set<Int64>) throws {
        guard !albumIDs.isEmpty else { return }
        let ids = StatementArguments(Array(albumIDs))
        var members: [Int64: [AlbumMemberDisplay]] = [:]
        for row in try Row.fetchAll(db, sql: Self.selectMemberDisplaySQL(count: albumIDs.count), arguments: ids) {
            members[row[0], default: []].append(
                AlbumMemberDisplay(songID: row[1], year: row[2], discNo: row[3], trackNo: row[4], artworkKey: row[5])
            )
        }
        for row in try Row.fetchAll(db, sql: Self.selectAlbumDisplaySQL(count: albumIDs.count), arguments: ids) {
            let albumID: Int64 = row[0]
            guard let songs = members[albumID] else {
                try db.execute(sql: Self.deleteAlbumSQL, arguments: [albumID])
                continue
            }
            try showDisplay(db, albumID: albumID, members: songs, shown: AlbumDisplay(year: row[1], artworkKey: row[2]))
        }
    }

    /// Write an album's year + cover when `AlbumGrouping.display` of its members differs from what
    /// it `shown` (nil = not read) — unchanged albums are never written.
    private func showDisplay(
        _ db: Database, albumID: Int64, members: [AlbumMemberDisplay], shown: AlbumDisplay?
    ) throws {
        let display = AlbumGrouping.display(of: members)
        guard display != shown else { return }
        try db.execute(sql: Self.updateAlbumDisplaySQL, arguments: [display.year, display.artworkKey, albumID])
    }
}

// MARK: - Album upkeep

/// How a tag write keeps albums current (C2 fix round, B2).
enum AlbumUpkeep {
    /// Inside a metadata pass: no album work per write — the end-of-pass regroup is the
    /// authority; the write records the debt (`schema_info.regroup_owed`).
    case deferredToPassEnd
    /// A single write outside a pass: regroup the songs sharing its old or new title, in that write.
    case sameTitles
}

// MARK: - Grouping row

/// One song's album-grouping and display inputs, decoded positionally from the regroup SELECTs.
private struct GroupingRow: FetchableRecord, AlbumGroupingSong {
    let id: Int64
    let path: String
    let albumTitle: String?
    let albumArtistTag: String?
    let isCompilation: Bool
    let artistID: Int64?
    let artistName: String?
    let albumID: Int64?
    let display: AlbumMemberDisplay

    var year: Int? {
        display.year
    }

    init(row: Row) {
        id = row[0]
        path = row[1] ?? ""
        albumTitle = row[2]
        albumArtistTag = row[3]
        isCompilation = (row[4] as Int64? ?? 0) != 0
        artistID = row[5]
        artistName = row[6]
        albumID = row[7]
        display = AlbumMemberDisplay(songID: row[0], year: row[8], discNo: row[9], trackNo: row[10],
                                     artworkKey: row[11])
    }
}
