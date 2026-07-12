// ChecksSearchMigration — S9.2 FTS5 v1→v2 migration/backfill + capability probe.
//
// Split from ChecksSearch (file-length budget). These cases seed a v1 store via RAW SQL —
// bypassing the DAO, whose upsert now syncs FTS and needs the v2 table — to recreate the
// real pre-v2 library a migration upgrades, then assert the backfill. Seeding runs on a raw
// GRDB `DatabaseQueue` migrated by `v1OnlyMigrator()`; because that migrator shares the
// production `Schema.MigrationID` identifiers, the seeded v1 store can be handed to
// `LibraryStore` (FTS-MIG1/2) without tripping the `hasBeenSuperseded` downgrade guard.

import Foundation
import GRDB
import LibraryStore

// MARK: - Raw v1 seeding (no FTS — the pre-v2 state a real migration upgrades)

private func rawResolve(_ db: Database, insert: String, select: String,
                        name: String, bindsTwo: Bool) throws -> Int64 {
    try db.execute(sql: insert, arguments: bindsTwo ? [name, name] : [name])
    guard let id = try Int64.fetchOne(db, sql: select, arguments: [name]) else {
        throw SQLiteError.internalError(message: "rawResolve: row not found after insert")
    }
    return id
}

private func rawResolveAlbum(_ db: Database, title: String, artistID: Int64, year: Int64) throws -> Int64 {
    try db.execute(
        sql: "INSERT INTO albums(title, album_artist_id, year) VALUES (?, ?, ?) "
            + "ON CONFLICT(title, album_artist_id, year) DO NOTHING;",
        arguments: [title, artistID, year]
    )
    guard let id = try Int64.fetchOne(
        db, sql: "SELECT id FROM albums WHERE title = ? AND album_artist_id = ? AND year = ?;",
        arguments: [title, artistID, year]
    ) else {
        throw SQLiteError.internalError(message: "rawResolveAlbum: row not found after insert")
    }
    return id
}

/// One raw v1 track to seed (a parameter object — keeps the seed helper's arg count within
/// the lint budget while staying readable at the call sites).
private struct RawTrackSeed {
    let url: String
    let name: String
    let title: String
    let artist: String
    let album: String
    let year: Int64
    let genres: [String]
}

@discardableResult
private func seedTrackRawAtV1(_ db: Database, _ seed: RawTrackSeed) throws -> Int64 {
    let artistID = try rawResolve(
        db, insert: "INSERT OR IGNORE INTO artists(name, sort_name) VALUES (?, ?);",
        select: "SELECT id FROM artists WHERE name = ?;", name: seed.artist, bindsTwo: true
    )
    let albumID = try rawResolveAlbum(db, title: seed.album, artistID: artistID, year: seed.year)
    try db.execute(
        sql: """
        INSERT INTO tracks(url, relative_path, name, format, file_size, mtime,
                           title, album_id, artist_id, year, date_added, last_seen_scan)
        VALUES (?, '', ?, 'FLAC', 4096, 1000, ?, ?, ?, ?, 0, 0);
        """,
        arguments: [seed.url, seed.name, seed.title, albumID, artistID, seed.year]
    )
    let trackID = db.lastInsertedRowID
    for genre in seed.genres {
        let genreID = try rawResolve(
            db, insert: "INSERT OR IGNORE INTO genres(name) VALUES (?);",
            select: "SELECT id FROM genres WHERE name = ?;", name: genre, bindsTwo: false
        )
        try db.execute(
            sql: "INSERT OR IGNORE INTO track_genres(track_id, genre_id) VALUES (?, ?);",
            arguments: [trackID, genreID]
        )
    }
    return trackID
}

// MARK: - FTS-MIG1/MIG2 — real v1→v2 backfill populates all four columns

func checkFtsMigrationBackfill(number: Int, url: URL) async -> Bool {
    do {
        do {
            let queue = try DatabaseQueue(path: url.path)
            try v1OnlyMigrator().migrate(queue)
            try await queue.write { db in
                try seedTrackRawAtV1(db, RawTrackSeed(
                    url: "/m/dark.flac", name: "dark.flac", title: "Dark Side", artist: "Pink Floyd",
                    album: "The Wall", year: 1979, genres: ["Prog Rock", "Classic"]
                ))
                try seedTrackRawAtV1(db, RawTrackSeed(
                    url: "/m/wish.flac", name: "wish.flac", title: "Wish You Were Here",
                    artist: "Pink Floyd", album: "The Wall", year: 1979, genres: ["Prog Rock"]
                ))
                // A BARE track: NULL artist/album, no genres, no title — proves the backfill's
                // LEFT JOINs keep it (an INNER JOIN would silently drop it → the parity check fails).
                try db.execute(
                    sql: "INSERT INTO tracks(url, relative_path, name, format, file_size, mtime, "
                        + "date_added, last_seen_scan) VALUES "
                        + "('/m/bare.flac', '', 'baremononym.flac', 'FLAC', 4096, 1000, 0, 0);"
                )
            }
            let version = try await queue.read { db in try schemaInfoVersion(db) }
            guard version == 1 else {
                printFail(number, "FTS backfill: pre-migration version \(version) != 1"); return false
            }
        }
        // Opening the store runs the real v1→v2 (FTS create + backfill).
        let store = try await LibraryStore(url: url, appBuild: "verify")
        guard await store.schemaVersion() == 2 else {
            printFail(number, "FTS backfill: store did not reach v2"); return false
        }
        let byTitle = try await store.search("dark").tracks
        let byArtist = try await store.search("floyd").tracks
        let byAlbum = try await store.search("wall").tracks
        let byGenreBoth = try await store.search("prog").tracks
        let byGenreOne = try await store.search("classic").tracks
        // The bare (artist/album/genre-less) track must survive the backfill (LEFT JOIN),
        // and every track must have exactly one FTS row (count parity).
        let byBare = try await store.search("baremononym").tracks
        let ftsCount = try await store.countRows(inTable: "tracks_fts")
        let trackCount = try await store.countRows(inTable: "tracks")
        guard byTitle.contains(where: { $0.title == "Dark Side" }),
              byArtist.count == 2, byAlbum.count == 2, byGenreBoth.count == 2,
              byGenreOne.count == 1, byGenreOne.first?.title == "Dark Side",
              byBare.count == 1, ftsCount == trackCount, trackCount == 3 else {
            printFail(number, "FTS backfill: a column was not searchable, the bare track was dropped "
                + "(INNER-JOIN regression), or tracks_fts(\(ftsCount)) != tracks(\(trackCount))")
            return false
        }
        printPass(number, "FTS-MIG1/2: the REAL v1->v2 backfill makes every track findable by title, "
            + "artist, album, and EACH genre; a bare artist/album/genre-less track survives (LEFT JOIN) "
            + "and tracks_fts row-count == tracks (\(trackCount))")
        return true
    } catch {
        printFail(number, "FTS backfill threw: \(error)"); return false
    }
}

// MARK: - FTS-MIG3 — re-running the migration is idempotent (no duplicate FTS rows)

func checkFtsMigrationIdempotent(number: Int, url: URL) async -> Bool {
    do {
        let queue = try DatabaseQueue(path: url.path)
        try v1OnlyMigrator().migrate(queue)
        _ = try await queue.write { db in
            try seedTrackRawAtV1(db, RawTrackSeed(
                url: "/m/a.flac", name: "a.flac", title: "Alpha", artist: "Band", album: "Rec",
                year: 2020, genres: ["Jazz"]
            ))
        }
        // Run the real v1→v2 (backfill), then run the full migrator AGAIN (a no-op on a v2 store).
        try fullMigrator().migrate(queue)
        let afterFirst = try await queue.read { db in
            try Int.fetchOne(db, sql: "SELECT count(*) FROM tracks_fts;") ?? -1
        }
        try fullMigrator().migrate(queue)
        let afterSecond = try await queue.read { db in
            try Int.fetchOne(db, sql: "SELECT count(*) FROM tracks_fts;") ?? -2
        }
        let version = try await queue.read { db in try schemaInfoVersion(db) }
        guard afterFirst == 1, afterSecond == 1, version == 2 else {
            printFail(number, "FTS-MIG3: re-migration changed FTS row count (\(afterFirst)→\(afterSecond)) "
                + "or version (\(version))"); return false
        }
        printPass(number, "FTS-MIG3: re-running the migration on a v2 store is a no-op — "
            + "tracks_fts stays at 1 row (no duplicate backfill)")
        return true
    } catch {
        printFail(number, "FTS-MIG3 threw: \(error)"); return false
    }
}

// MARK: - CAP — FTS5-unavailable surfaces a clear typed error (no store)

func checkFtsCapabilityProbe(number: Int, url: URL) async -> Bool {
    do {
        let queue = try DatabaseQueue(path: url.path)
        try v1OnlyMigrator().migrate(queue)
        // Force the unavailable path via the injectable predicate.
        var threwFTS5 = false
        do {
            try await queue.write { db in
                try Schema.migrateV1toV2(db, appBuild: "verify", timestamp: testTimestamp,
                                         fts5Available: { _ in false })
            }
        } catch SQLiteError.fts5Unavailable {
            threwFTS5 = true
        }
        guard threwFTS5 else {
            printFail(number, "CAP: FTS5-unavailable did not throw .fts5Unavailable"); return false
        }
        // And it is NOT rebuild-recoverable (a valid store must fail to open, not be quarantined).
        guard !SQLiteError.fts5Unavailable.isRebuildRecoverable else {
            printFail(number, "CAP: .fts5Unavailable must not be rebuild-recoverable"); return false
        }
        printPass(number, "CAP: an FTS5-unavailable build throws a clear typed .fts5Unavailable that "
            + "propagates (not rebuild-recoverable)")
        return true
    } catch {
        printFail(number, "CAP threw: \(error)"); return false
    }
}

// MARK: - FTS-MIG4 — a throwing REAL v1→v2 rolls back atomically (no tracks_fts, stays v1)

func checkFtsMigrationRollback(number: Int, url: URL) async -> Bool {
    do {
        let queue = try DatabaseQueue(path: url.path)
        try v1OnlyMigrator().migrate(queue)
        // A v1→v2 step that runs the REAL FTS create + backfill, THEN throws — GRDB runs each
        // migration in its own transaction, so BOTH the virtual-table DDL and the backfill must
        // roll back atomically (SCHEMA-4 only proves this for a synthetic ALTER step).
        var throwingMigrator = v1OnlyMigrator()
        throwingMigrator.registerMigration(Schema.MigrationID.v2) { db in
            try Schema.migrateV1toV2(db, appBuild: "verify", timestamp: testTimestamp)
            throw MigrationTestError()
        }
        var threw = false
        do {
            try throwingMigrator.migrate(queue)
        } catch {
            threw = true
        }
        let (version, ftsExists) = try await queue.read { db in
            try (schemaInfoVersion(db),
                 Int.fetchOne(
                     db, sql: "SELECT count(*) FROM sqlite_master WHERE type = 'table' AND name = 'tracks_fts';"
                 ) ?? -1)
        }
        guard threw, version == 1, ftsExists == 0 else {
            printFail(number, "FTS-MIG4: a throwing real v1->v2 did not fully roll back "
                + "(version \(version), tracks_fts present=\(ftsExists))"); return false
        }
        printPass(number, "FTS-MIG4: a throwing REAL v1->v2 rolls back atomically — stays at v1 with "
            + "NO tracks_fts (the FTS DDL + backfill run inside the migrator's transaction)")
        return true
    } catch {
        printFail(number, "FTS-MIG4 threw: \(error)"); return false
    }
}
