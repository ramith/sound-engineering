// LibraryStore+GenreCovers — the genre tile's cover mosaic read (S10.8 D5, browse-grid decision 19).
//
// A genre tile's art is a 2×2 mosaic of the covers of its albums with the most songs in that genre
// (Music.app builds playlist art the same way). `genreCoverArtworkKeys(perGenre:)` answers it for
// EVERY genre in ONE read — the grid asks once, never once per tile. Three window steps (SQLite
// ≥ 3.25; macOS 26 ships 3.51):
//   1. `album_songs` — songs per (genre, album), over albums that HAVE a cover. Grouped per album, so
//      an album lists once however many of its songs are in the genre; a song in two genres counts
//      in both (one `track_genres` row each, unique by its primary key — no DISTINCT needed).
//   2. `covers` — one row per (genre, cover): when two albums wear the same image (one content
//      hash), the better-ranked album keeps it, so a mosaic never shows a cover twice.
//   3. `ranked` — most songs first, ties → the lower album id; the caller's cap cuts each genre.
// A genre with no covered album yields no row, so it is ABSENT from the result (the tile shows the
// placeholder). Like every read it touches no filesystem: the keys resolve to cache paths through
// `artworkCachePaths(forKeys:)`.
//
// Plan (VerifyLibraryStore GC-03): `track_genres` is walked once — the whole grid needs every
// membership — and `tracks` / `albums` are reached by rowid, never a full SCAN of `tracks`. The
// existing indexes serve it; no schema change.

import Foundation
import GRDB

public extension LibraryStore {
    // MARK: - SQL

    /// Every genre's top album covers in rank order (file header, steps 1–3); the one parameter is
    /// the per-genre cap.
    private static let selectGenreCoverKeysSQL = """
    WITH album_songs AS (
        SELECT tg.genre_id, al.id AS album_id, al.artwork_key, count(*) AS songs
        FROM track_genres tg
        JOIN tracks t ON t.id = tg.track_id
        JOIN albums al ON al.id = t.album_id
        WHERE al.artwork_key IS NOT NULL
        GROUP BY tg.genre_id, al.id
    ), covers AS (
        SELECT genre_id, album_id, artwork_key, songs,
               ROW_NUMBER() OVER (PARTITION BY genre_id, artwork_key ORDER BY songs DESC, album_id ASC) AS wearer
        FROM album_songs
    ), ranked AS (
        SELECT genre_id, artwork_key,
               ROW_NUMBER() OVER (PARTITION BY genre_id ORDER BY songs DESC, album_id ASC) AS rank
        FROM covers
        WHERE wearer = 1
    )
    SELECT genre_id, artwork_key FROM ranked WHERE rank <= ? ORDER BY genre_id, rank;
    """

    // MARK: - Genre covers

    /// For every genre with at least one album that has artwork: up to `perGenre` distinct album
    /// artwork keys, from its albums with the most songs in that genre (ties: lower album id first).
    /// Keyed by genre id, keys in rank order; a genre with no covered album is absent, and a
    /// `perGenre` below 1 returns an empty map.
    func genreCoverArtworkKeys(perGenre: Int = 4) async throws -> [Int64: [String]] {
        try await dbWriter.read { db in
            var keys: [Int64: [String]] = [:]
            for row in try Row.fetchAll(db, sql: Self.selectGenreCoverKeysSQL, arguments: [perGenre]) {
                if let genreID = row[0] as Int64?, let artworkKey = row[1] as String? {
                    keys[genreID, default: []].append(artworkKey)
                }
            }
            return keys
        }
    }

    /// The `EXPLAIN QUERY PLAN` `detail` rows for `genreCoverArtworkKeys` (the same SQL constant, so
    /// no drift). Diagnostic/verification hook: proves `tracks` is reached by rowid, never scanned.
    func explainGenreCoverArtworkKeysPlan() async throws -> [String] {
        try await dbWriter.read { db in try Self.collectQueryPlan(db, Self.selectGenreCoverKeysSQL) }
    }
}
