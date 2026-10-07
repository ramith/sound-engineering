// LibraryStore+AlbumGrouping — assigning songs to albums (S10.8 C2), GRDB-backed.
//
// The pure rule is `AlbumGrouping`; this is where the store applies it. `regroupAlbumsLocked`
// reads each in-scope song's RAW album inputs (title, album-artist tag, compilation flag, artist,
// year, path), groups them by `AlbumGrouping.key`, credits each group (its tag, else the derived
// "Various Artists" / shared artist / Unknown Artist), resolves the album row on the
// (title, album_artist_id, year, folder_key) key, and rewrites `album_id` ONLY for songs whose
// album changed. It is a pure function of stored columns — idempotent, cancel-safe, re-runnable.
//
// Two scopes, one function:
//   • a TITLE scope — every tag write regroups the songs sharing the written song's old and new
//     album title (`idx_tracks_album_title`), so each commit is consistent;
//   • the WHOLE library — `refreshDerivedFacets` (the end of every metadata pass, and
//     `removeRoot`), which catches what a tag write cannot see: songs that MOVED folder (a
//     Finder move keeps its tags) or were DELETED (a group that lost its second artist goes back
//     from "Various Artists" to the remaining one). Unchanged albums cost a read, never a write.
// A reassigned album's old row is left for the orphan sweep, which runs right after.

import Foundation
import GRDB

public extension LibraryStore {
    // MARK: - SQL

    /// The grouping inputs of the songs in scope, in id order (so "the first song's spelling" is
    /// deterministic). The artist NAME rides along for the shared-artist test; the id-0 sentinel
    /// (a literal "Unknown Artist" tag) joins as no artist. `scope` is the WHERE condition.
    private static func selectGroupingRowsSQL(scope: String) -> String {
        "SELECT t.id, t.url, t.album_title, t.album_artist_tag, t.compilation, t.artist_id, ar.name, "
            + "t.year, t.album_id FROM tracks t "
            + "LEFT JOIN artists ar ON ar.id = t.artist_id AND t.artist_id <> \(unknownArtistID) "
            + "WHERE \(scope) ORDER BY t.id;"
    }

    /// Insert an album row on its total key (race-safe; `ON CONFLICT … DO NOTHING`).
    private static let insertAlbumSQL =
        "INSERT INTO albums(title, album_artist_id, year, folder_key) VALUES (?, ?, ?, ?) "
            + "ON CONFLICT(title, album_artist_id, year, folder_key) DO NOTHING;"
    /// Select an album id by its total key.
    private static let selectAlbumIDByKeySQL =
        "SELECT id FROM albums WHERE title = ? AND album_artist_id = ? AND year = ? AND folder_key = ?;"
    /// Point a song at its album.
    private static let setTrackAlbumSQL = "UPDATE tracks SET album_id = ? WHERE id = ?;"
    /// Give an album that has no cover one of its songs' covers (lowest id — deterministic). Only
    /// when unset, so the first-applied cover still wins on an album that has one.
    private static let seedAlbumCoverSQL =
        "UPDATE albums SET artwork_key = (SELECT artwork_key FROM tracks "
            + "WHERE album_id = ?1 AND artwork_key IS NOT NULL ORDER BY id LIMIT 1) "
            + "WHERE id = ?1 AND artwork_key IS NULL;"

    // MARK: - Whole-library refresh (the end-of-pass step)

    /// Regroup every song's album, then reap the albums/artists/genres nothing references — ONE
    /// write. `MetadataScanner` runs it at the end of every pass (before the artwork sweep, so art
    /// a reaped album held is reclaimed the same pass); returns the sweep counts.
    @discardableResult
    func refreshDerivedFacets() async throws -> FacetSweepCounts {
        try await dbWriter.write { db in try self.refreshDerivedFacetsLocked(db) }
    }

    /// The body of `refreshDerivedFacets`, so `removeRoot` can fold it into its transaction.
    @discardableResult
    internal func refreshDerivedFacetsLocked(_ db: Database) throws -> FacetSweepCounts {
        try regroupAlbumsLocked(db, titles: nil)
        return try sweepOrphanFacetsLocked(db)
    }

    // MARK: - Regroup

    /// Assign every in-scope song to the album `AlbumGrouping` computes for it. `titles == nil` =
    /// the whole library; otherwise only songs whose album title is in `titles` (empty = no-op).
    /// Writes `album_id` only where it changes. Runs inside the caller's write transaction.
    internal func regroupAlbumsLocked(_ db: Database, titles: Set<String>?) throws {
        let rows: [GroupingRow]
        if let titles {
            guard !titles.isEmpty else { return }
            let scope = "t.album_title IN (\(databaseQuestionMarks(count: titles.count)))"
            rows = try GroupingRow.fetchAll(db, sql: Self.selectGroupingRowsSQL(scope: scope),
                                            arguments: StatementArguments(Array(titles)))
        } else {
            rows = try GroupingRow.fetchAll(db, sql: Self.selectGroupingRowsSQL(scope: "t.album_title IS NOT NULL"))
        }
        var groups: [AlbumGroupKey: [GroupingRow]] = [:]
        for row in rows {
            if let key = AlbumGrouping.key(albumTitle: row.albumTitle, albumArtistTag: row.albumArtistTag,
                                           year: row.year, trackPath: row.path) {
                groups[key, default: []].append(row)
            }
        }
        for (key, members) in groups {
            let albumID = try resolveAlbumRow(db, key: key, artistID: albumArtistID(db, key: key, members: members))
            let moved = members.filter { $0.albumID != albumID }
            for member in moved {
                try db.execute(sql: Self.setTrackAlbumSQL, arguments: [albumID, member.id])
            }
            if !moved.isEmpty {
                try db.execute(sql: Self.seedAlbumCoverSQL, arguments: [albumID])
            }
        }
    }

    /// The album artist's row id for one group: its album-artist tag when it has one, else the
    /// credit `AlbumGrouping.derivedArtist` derives from the songs' artist names — a shared artist
    /// is credited as the row of the first song spelling it that way.
    private func albumArtistID(_ db: Database, key: AlbumGroupKey, members: [GroupingRow]) throws -> Int64 {
        if let tag = key.taggedArtist {
            return try resolveArtist(db, named: tag)
        }
        let credit = AlbumGrouping.derivedArtist(
            anyCompilation: members.contains(where: \.isCompilation), artists: members.map(\.artistName)
        )
        switch credit {
        case .various: return try resolveArtist(db, named: variousArtistsName)
        case let .shared(name): return members.first { $0.artistName == name }?.artistID ?? unknownArtistID
        case .unknown: return unknownArtistID
        }
    }

    /// Resolve (query-then-insert) the album row for `key` credited to `artistID`. RACE-SAFE.
    private func resolveAlbumRow(_ db: Database, key: AlbumGroupKey, artistID: Int64) throws -> Int64 {
        let arguments: StatementArguments = [key.title, artistID, Int64(key.year), key.folderKey]
        if let existing = try Int64.fetchOne(db, sql: Self.selectAlbumIDByKeySQL, arguments: arguments) {
            return existing
        }
        try db.execute(sql: Self.insertAlbumSQL, arguments: arguments)
        guard let id = try Int64.fetchOne(db, sql: Self.selectAlbumIDByKeySQL, arguments: arguments) else {
            throw SQLiteError.internalError(message: "resolveAlbumRow: row for key not found after insert")
        }
        return id
    }
}

// MARK: - Grouping row

/// One song's album-grouping inputs, decoded positionally from the regroup SELECTs.
private struct GroupingRow: FetchableRecord {
    let id: Int64
    let path: String
    let albumTitle: String?
    let albumArtistTag: String?
    let isCompilation: Bool
    let artistID: Int64?
    let artistName: String?
    let year: Int?
    let albumID: Int64?

    init(row: Row) {
        id = row[0]
        path = row[1] ?? ""
        albumTitle = row[2]
        albumArtistTag = row[3]
        isCompilation = (row[4] as Int64? ?? 0) != 0
        artistID = row[5]
        artistName = row[6]
        year = row[7]
        albumID = row[8]
    }
}
