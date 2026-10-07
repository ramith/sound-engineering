// ChecksAlbumArtistData — S10.8 C2 album artists, the data side:
//   ALB-03 user data survives the re-read — a store written by the PREVIOUS release (schema v6,
//          built by the production migrator capped at v6) is opened by this build: v7 migrates,
//          the derived-data bump queues every song, and the app's metadata pass re-reads them.
//          Every user column and table is compared byte-for-byte before and after, through raw
//          SQL (not the API under test), and the bump happens exactly once;
//   ALB-04 one missing-artist string everywhere — the Albums credit, every song row, the album-
//          artist cell and a literal "Unknown Artist" tag all resolve to `unknownArtistName`, and
//          the Artists list never shows it. (The UI's literal ban is the semgrep rule
//          `library-one-unknown-artist-string`.)

import Foundation
import GRDB
import LibraryScan
import LibraryStore

// MARK: - ALB-03 — user data survives the re-read

/// The previous release's library, written straight into a v6 store: two songs by Ann in one
/// folder on an untagged album (the pre-C2 "Unknown Artist" credit), with play history, a loved
/// flag, a rating and frecency; a user playlist (one song twice) inside a playlist folder; and the
/// built-in queue holding a song.
private let previousReleaseSeedSQL = [
    "INSERT INTO folders(id, path, is_root) VALUES (1, '/ALB03/Lib', 1);",
    "INSERT INTO artists(id, name, sort_name) VALUES (1, 'Ann', 'Ann');",
    "INSERT INTO albums(id, title, album_artist_id, year) VALUES (1, 'Party Mix', 0, 2011);",
    """
    INSERT INTO tracks(id, url, folder_id, relative_path, name, format, file_size, mtime, album_id,
        artist_id, title, year, date_added, last_seen_scan, metadata_scanned, play_count, rating, loved,
        last_played, frecency_score, frecency_rank)
    VALUES
        (1, '/ALB03/Lib/Party/m1.flac', 1, 'Party/m1.flac', 'm1', 'FLAC', 101, 1000, 1, 1, 'M One', 2011,
         1690000000, 1, 1, 7, 4, 1, 1700000000, 2.5, 1700100000.5),
        (2, '/ALB03/Lib/Party/m2.flac', 1, 'Party/m2.flac', 'm2', 'FLAC', 102, 1000, 1, 1, 'M Two', 2011,
         1690000001, 1, 1, 3, NULL, 0, 1700000500, 1.0, 1700000500.0);
    """,
    "INSERT INTO playlist_folders(id, parent_id, name, position, created_at) VALUES (1, NULL, 'Kept', 0, 1690000000);",
    "INSERT INTO playlists(id, name, is_builtin, created_at, folder_id) VALUES (10, 'Keepers', 0, 1690000000, 1);",
    """
    INSERT INTO playlist_entries(playlist_id, track_id, position, added_at)
    VALUES (10, 2, 0, 1690000100), (10, 1, 1, 1690000101), (10, 2, 2, 1690000102);
    """,
    """
    INSERT INTO playlist_entries(playlist_id, track_id, position, added_at)
    SELECT id, 1, 0, 1690000200 FROM playlists WHERE is_builtin = 1;
    """,
]

/// Every USER column and table, as text rows in id order — compared before vs after.
private let userDataQueries = [
    "SELECT id, play_count, loved, rating, last_played, frecency_score, frecency_rank, date_added "
        + "FROM tracks ORDER BY id;",
    "SELECT id, name, is_builtin, created_at, folder_id FROM playlists ORDER BY id;",
    "SELECT id, playlist_id, track_id, position, added_at FROM playlist_entries ORDER BY id;",
    "SELECT id, parent_id, name, position, created_at FROM playlist_folders ORDER BY id;",
]

/// Read the user-data snapshot of the store file at `url` through a separate READ-ONLY connection.
private func userDataSnapshot(at url: URL) throws -> [String] {
    var config = Configuration()
    config.readonly = true
    let queue = try DatabaseQueue(path: url.path, configuration: config)
    return try queue.read { db in
        try userDataQueries.flatMap { sql in try Row.fetchAll(db, sql: sql).map(\.description) }
    }
}

/// Build the previous release's v6 store at `url` and return its user-data snapshot.
private func seedPreviousReleaseStore(at url: URL) throws -> [String] {
    let queue = try DatabaseQueue(path: url.path)
    try migrator(through: 6).migrate(queue)
    try queue.write { db in
        for statement in previousReleaseSeedSQL {
            try db.execute(sql: statement)
        }
    }
    return try queue.read { db in
        try userDataQueries.flatMap { sql in try Row.fetchAll(db, sql: sql).map(\.description) }
    }
}

func checkReReadKeepsUserData(number: Int, url: URL) async -> Bool {
    let cacheDir = url.deletingLastPathComponent()
        .appendingPathComponent("alb03-cache-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: cacheDir) }
    do {
        let before = try seedPreviousReleaseStore(at: url)
        let store = try await LibraryStore(url: url, appBuild: "verify")
        guard try await migratedAndQueued(store, url: url, before: before, number: number) else { return false }

        // The one-time re-read — the app's metadata pass. The files now say "compilation" (the tag
        // C2 starts reading), so the album must turn "Various Artists" though one artist sings both.
        let reRead: [String: TrackMetadata] = [
            "m1.flac": TrackMetadata(title: "M One (re-read)", artistName: "Ann", albumTitle: "Party Mix",
                                     isCompilation: true, year: 2011),
            "m2.flac": TrackMetadata(title: "M Two (re-read)", artistName: "Ann", albumTitle: "Party Mix",
                                     isCompilation: true, year: 2011),
        ]
        try await MetadataScanner().run(generation: store.beginScanGeneration(), into: store,
                                        cache: ArtworkCache(directory: cacheDir),
                                        extractor: TagTableExtractor(tags: reRead))
        guard try await store.tracksNeedingMetadata(limit: 10).isEmpty,
              try await store.track(id: 1)?.title == "M One (re-read)",
              try await expectAlbums(store, ["Party Mix": ["\(variousArtistsName) ×2"]], "after the re-read",
                                     number: number) else {
            printFail(number, "ALB-03: the re-read did not re-derive the songs and their album"); return false
        }
        guard try userDataSnapshot(at: url) == before else {
            try printFail(number, "ALB-03: the re-read changed user data:\n\(userDataSnapshot(at: url))\nvs\n\(before)")
            return false
        }
        guard try await keptThroughTheAPI(store, number: number) else { return false }

        // Exactly once: reopening neither bumps nor queues again.
        let reopened = try await LibraryStore(url: url, appBuild: "verify")
        guard !reopened.derivedDataRefreshed, try await reopened.tracksNeedingMetadata(limit: 10).isEmpty else {
            printFail(number, "ALB-03: reopening re-queued the re-read (the bump must happen once)"); return false
        }
        printPass(number, "ALB-03 user data survives the re-read: a v6 (previous-release) store opens at "
            + "v\(currentSchemaVersion) with album ids kept, the derived-data bump queues every song ONCE, the "
            + "metadata pass re-reads them (the new compilation flag re-credits the album to "
            + "\(variousArtistsName)), and play counts, loved, ratings, last played, frecency, date added, "
            + "song ids, playlists, entries (order + duplicates), playlist folders and the queue are "
            + "byte-identical before and after (raw SQL, read-only connection)")
        return true
    } catch {
        printFail(number, "ALB-03 threw: \(error)"); return false
    }
}

/// After open: migrated to the current schema, album ids intact through the albums rebuild, every
/// song queued for the re-read, and no user data touched by the migration or the bump.
private func migratedAndQueued(_ store: LibraryStore, url: URL, before: [String], number: Int) async throws -> Bool {
    guard await store.schemaVersion() == currentSchemaVersion, store.derivedDataRefreshed else {
        printFail(number, "ALB-03: the v6 store did not migrate to v\(currentSchemaVersion) + bump"); return false
    }
    guard try await store.track(id: 1)?.albumID == 1, try await store.track(id: 2)?.albumID == 1 else {
        printFail(number, "ALB-03: the albums rebuild lost the songs' album ids"); return false
    }
    guard try await store.tracksNeedingMetadata(limit: 10).sorted() == [1, 2] else {
        printFail(number, "ALB-03: the derived-data bump did not queue every song for a re-read"); return false
    }
    guard try userDataSnapshot(at: url) == before else {
        printFail(number, "ALB-03: the v7 migration or the bump changed user data"); return false
    }
    return true
}

/// The same user data, read back through the store's own API (what the app shows).
private func keptThroughTheAPI(_ store: LibraryStore, number: Int) async throws -> Bool {
    let keepers = try await store.entries(inPlaylist: 10).map(\.trackID)
    let queue = try await store.entries(inPlaylist: store.currentPlaylistID()).map(\.trackID)
    guard keepers == [2, 1, 2], queue == [1],
          try await store.userState(trackID: 1) == TrackUserState(playCount: 7, loved: true, rating: 4),
          try await store.userState(trackID: 2) == TrackUserState(playCount: 3, loved: false, rating: nil),
          try await store.frecencyState(id: 1)?.score == 2.5 else {
        printFail(number, "ALB-03: the API reads back different playlists / user state after the re-read")
        return false
    }
    return true
}

// MARK: - ALB-04 — one missing-artist string everywhere

func checkOneMissingArtistString(number: Int, url: URL) async -> Bool {
    do {
        let fixture = try await AlbumFixture("alb04", url: url, songs: [
            song("Anon/anon.flac", songTags(nil, album: "Nameless")),
            song("Named/named.flac", songTags("Named", album: "Named Album")),
            song("Loose/noalbum.flac", TrackMetadata(title: "No Album")),
            // A tag that literally says the missing-artist string is the sentinel, not a 2nd artist.
            song("Literal/literal.flac", TrackMetadata(title: "Literal", artistName: unknownArtistName)),
        ])
        let store = fixture.store
        guard try await expectAlbums(store, ["Nameless": ["\(unknownArtistName) ×1"], "Named Album": ["Named ×1"]],
                                     "the Albums credit", number: number),
            try await songRowsReadTheOneString(store, number: number) else { return false }
        guard try await !store.artists().contains(where: { $0.name == unknownArtistName }),
              try await store.countRows(inTable: "artists") == 2 else {
            printFail(number, "ALB-04: the Artists list shows '\(unknownArtistName)' or a second such artist row")
            return false
        }
        printPass(number, "ALB-04 one missing-artist string: the Albums credit, a no-artist song's row, a "
            + "no-album song's row and the album-artist cell all read '\(unknownArtistName)' (no-album → no "
            + "credit); a literal '\(unknownArtistName)' tag IS the sentinel (no 2nd row), and the Artists list "
            + "never shows it; the UI literal is banned by semgrep library-one-unknown-artist-string")
        return true
    } catch {
        printFail(number, "ALB-04 threw: \(error)"); return false
    }
}

/// Every song row's artist and album-artist cells resolve through `unknownArtistName`.
private func songRowsReadTheOneString(_ store: LibraryStore, number: Int) async throws -> Bool {
    var rows: [String: LibraryTrackDisplay] = [:]
    for row in try await store.allTracksDisplay() {
        rows[row.url.lastPathComponent] = row
    }
    guard let anon = rows["anon.flac"], let named = rows["named.flac"], let noAlbum = rows["noalbum.flac"],
          let literal = rows["literal.flac"] else {
        printFail(number, "ALB-04: fixture rows missing"); return false
    }
    let cells = [
        (anon.artistDisplayName, unknownArtistName), (anon.albumArtistDisplayName, unknownArtistName),
        (named.artistDisplayName, "Named"), (named.albumArtistDisplayName, "Named"),
        (noAlbum.artistDisplayName, unknownArtistName), (noAlbum.albumArtistDisplayName, ""),
        (literal.artistDisplayName, unknownArtistName),
    ]
    guard cells.allSatisfy({ $0.0 == $0.1 }), literal.artistID == unknownArtistID else {
        printFail(number, "ALB-04: song cells read \(cells.map(\.0)), expected \(cells.map(\.1)) "
            + "(literal artist id \(String(describing: literal.artistID)))")
        return false
    }
    return true
}
