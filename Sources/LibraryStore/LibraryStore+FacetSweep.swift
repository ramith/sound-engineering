// LibraryStore+FacetSweep — SF-2 facet-orphan sweep (S8.4), GRDB-backed.
//
// Reap albums/artists/genres that no track references any more (left behind by move/retag/
// delete churn). Reachability-based (mirrors `sweepOrphanArtwork`), NEVER a ref-counter.
// PRESERVES the id-0 unknown-artist sentinel (it backs the M1 total-album key). Deletion
// order albums→artists so a dead album's `album_artist_id` reference is gone before the
// artist reachability check — otherwise `ON DELETE SET DEFAULT` could silently rewrite a
// live album's artist to the sentinel. The `*Locked` form runs inside the caller's write
// transaction so `removeRoot` can fold it in.

import Foundation
import GRDB

public extension LibraryStore {
    // MARK: - SQL

    /// Delete albums no track references (freed FIRST so a dead album no longer protects its artist).
    private static let deleteOrphanAlbumsSQL =
        "DELETE FROM albums WHERE id NOT IN (SELECT album_id FROM tracks WHERE album_id IS NOT NULL);"
    /// Delete artists referenced by NO track AND NO (surviving) album — never the id-0 sentinel (bound at ?1).
    private static let deleteOrphanArtistsSQL =
        "DELETE FROM artists WHERE id <> ? "
            + "AND id NOT IN (SELECT artist_id FROM tracks WHERE artist_id IS NOT NULL) "
            + "AND id NOT IN (SELECT album_artist_id FROM albums WHERE album_artist_id IS NOT NULL);"
    /// Delete genres with no `track_genres` memberships.
    private static let deleteOrphanGenresSQL =
        "DELETE FROM genres WHERE id NOT IN (SELECT genre_id FROM track_genres);"

    /// Delete facet rows referenced by nothing: albums with no track; artists referenced by
    /// no track AND no album; genres with no `track_genres` — PRESERVING `artists(id=0)`. ONE
    /// write. Returns per-table deletion counts. Run it AFTER the track sweep and BEFORE
    /// `sweepOrphanArtwork` (deleting an album nulls its `artwork_key`).
    @discardableResult
    func sweepOrphanFacets() async throws -> FacetSweepCounts {
        try await dbWriter.write { db in try self.sweepOrphanFacetsLocked(db) }
    }

    /// The body of `sweepOrphanFacets`, so `removeRoot` can fold it into its existing write
    /// transaction. Runs inside the caller's `Database`.
    @discardableResult
    internal func sweepOrphanFacetsLocked(_ db: Database) throws -> FacetSweepCounts {
        // 1. Albums with no track — freed FIRST so a dead album no longer protects its artist.
        let albums = try Self.deleteReturningCount(db, Self.deleteOrphanAlbumsSQL)
        // 2. Artists referenced by NO track AND NO (surviving) album — never the id-0 sentinel.
        let artists = try Self.deleteReturningCount(db, Self.deleteOrphanArtistsSQL, sentinel: unknownArtistID)
        // 3. Genres with no memberships (track_genres cascades when a track is deleted).
        let genres = try Self.deleteReturningCount(db, Self.deleteOrphanGenresSQL)
        return FacetSweepCounts(albums: albums, artists: artists, genres: genres)
    }

    /// Run a DELETE (optionally binding the sentinel id at index 1) and return the row count
    /// it removed. The tiny shared helper for the three facet deletes.
    private static func deleteReturningCount(_ db: Database, _ sql: String, sentinel: Int64? = nil) throws -> Int {
        if let sentinel {
            try db.execute(sql: sql, arguments: [sentinel])
        } else {
            try db.execute(sql: sql)
        }
        return db.changesCount
    }
}
