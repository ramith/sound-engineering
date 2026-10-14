// ChecksSearchTokens — R1.1-A, council C-61 / KI-LIB-11: the v8 → v9 search index.
//   ST-1 a v8 (previous-release) store — built by the real migrator, its index written as the v8 seam
//        wrote it, with a playlist and play history — shows the v8 fault first (a Sinhala word finds the
//        word that differs from it by a vowel sign), then opens through the real open path: it reaches
//        v9 with every user row kept, its index is rebuilt with every mark a token character (one FTS
//        row per song), and search finds each Sinhala word alone, an NFD filename by its composed
//        spelling, and a Latin word without its accent.
// LibraryBrowseKitTests' SearchScriptsTests hold the same searches on a fresh store, and the Filter /
// type-to-select agreement.

import Foundation
import GRDB
import LibraryStore

// MARK: - Registration

func searchTokensCheckCases() -> [CheckCase] {
    [CheckCase(label: "st1-v9-search-tokens-upgrade", run: checkSearchTokensUpgrade)]
}

// MARK: - ST-1 — the v8 → v9 upgrade

/// One song of the v8 fixture: its title tag (nil = untagged, found by its filename) and filename.
private struct V8Song {
    let title: String?
    let name: String
}

/// The v8 fixture's songs, in id order: two Sinhala words a vowel sign apart, an untagged song whose
/// filename is stored decomposed (NFD Hangul "노래"), and an accented Latin title.
private let v8Songs = [
    V8Song(title: "මාල", name: "necklace"),
    V8Song(title: "මිල", name: "price"),
    V8Song(title: nil, name: "\u{1102}\u{1169}\u{1105}\u{1162}"),
    V8Song(title: "Beyoncé", name: "halo"),
]

/// A v8 store at `url` holding `v8Songs`, each indexed as the v8 seam indexed it (title or filename, as
/// stored); the first played 5 times and loved; the first and third in a user playlist.
private func seedV8Store(at url: URL) throws {
    let queue = try DatabaseQueue(path: url.path)
    try migrator(through: 8).migrate(queue)
    try queue.write { db in
        for (index, song) in v8Songs.enumerated() {
            try db.execute(sql: """
            INSERT INTO tracks(url, relative_path, name, format, file_size, mtime, title, date_added,
                               last_seen_scan, play_count, loved)
            VALUES (?, '', ?, 'FLAC', 8, 1, ?, 1, 1, ?, ?);
            """, arguments: ["/st1/\(index).flac", song.name, song.title, index == 0 ? 5 : 0, index == 0])
            try db.execute(sql: "INSERT INTO tracks_fts(rowid, title, artist, album, genre) VALUES (?, ?, '', '', '');",
                           arguments: [db.lastInsertedRowID, song.title ?? song.name])
        }
        try db.execute(sql: "INSERT INTO playlists(name, is_builtin, created_at) VALUES ('Kept', 0, 1);")
        let playlist = db.lastInsertedRowID
        for (position, track) in [1, 3].enumerated() {
            try db.execute(
                sql: "INSERT INTO playlist_entries(playlist_id, track_id, position, added_at) VALUES (?, ?, ?, 1);",
                arguments: [playlist, track, position]
            )
        }
    }
}

/// The ids a raw MATCH of `term` finds in the store file at `url`, on its own connection.
private func rawMatches(_ term: String, at url: URL) throws -> Set<Int64> {
    try DatabaseQueue(path: url.path).read { db in
        try Int64.fetchSet(db, sql: "SELECT rowid FROM tracks_fts WHERE tracks_fts MATCH ?;",
                           arguments: ["\"\(term)\"*"])
    }
}

/// The search index's DDL in the store file at `url`.
private func ftsDefinition(at url: URL) throws -> String {
    try DatabaseQueue(path: url.path).read { db in
        try String.fetchOne(db, sql: "SELECT sql FROM sqlite_master WHERE name = 'tracks_fts';") ?? ""
    }
}

func checkSearchTokensUpgrade(number: Int, url: URL) async -> Bool {
    do {
        try seedV8Store(at: url)
        // The v8 fault, first: the old tokenizer splits "මාල" at its vowel sign, so it finds "මිල" too.
        guard try rawMatches("මාල", at: url) == [1, 2] else {
            printFail(number, "ST-1: the v8 fixture does not show the v8 fault (its index is not the v8 one)")
            return false
        }
        let store = try await LibraryStore(url: url, appBuild: "verify")
        let searches: [(query: String, ids: Set<Int64>)] = [("මාල", [1]), ("මිල", [2]), ("노래", [3]), ("beyonce", [4])]
        for (query, ids) in searches {
            let found = try await store.searchMatchingIDs(query)
            guard found == ids else {
                printFail(number, "ST-1: after the upgrade “\(query)” found \(found.sorted()), "
                    + "expected \(ids.sorted())")
                return false
            }
        }
        guard await store.schemaVersion() == currentSchemaVersion,
              try ftsDefinition(at: url).contains("categories 'L* N* Co M*'"),
              try await store.countRows(inTable: "tracks_fts") == v8Songs.count,
              try await store.countRows(inTable: "tracks") == v8Songs.count else {
            printFail(number, "ST-1: the upgraded store is not at v\(currentSchemaVersion) with the v9 index, "
                + "one FTS row per song")
            return false
        }
        let kept = try await store.playlists().first { $0.name == "Kept" }
        let played = try await store.userState(trackID: 1)
        guard let kept, try await store.entries(inPlaylist: kept.id).map(\.trackID) == [1, 3],
              played?.playCount == 5, played?.loved == true else {
            printFail(number, "ST-1: the upgrade lost user data (the playlist, its order, or the play history)")
            return false
        }
        printPass(number, "ST-1 the v8 → v9 upgrade: a v8 store whose index split “මාල” at its vowel sign "
            + "(finding “මිල” too) reaches v\(currentSchemaVersion) with its playlist, order and play history "
            + "kept; its index is rebuilt with every mark a token character, one row per song; “මාල” and "
            + "“මිල” each find only themselves, an NFD filename its composed spelling, “beyonce” “Beyoncé”")
        return true
    } catch {
        printFail(number, "ST-1 threw: \(error)"); return false
    }
}
