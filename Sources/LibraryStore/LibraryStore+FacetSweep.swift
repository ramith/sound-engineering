// LibraryStore+FacetSweep — SF-2 facet-orphan sweep (S8.4).
//
// Reap albums/artists/genres that no track references any more — left behind by move/
// retag/delete churn — so S9 browse shows no phantom empty albums/artists. Reachability-
// based (mirrors `sweepOrphanArtwork`, LibraryStore+MetadataWrite), NEVER a ref-counter
// (counters desync — the artwork design's explicit lesson). PRESERVES the id-0
// unknown-artist sentinel (it backs the M1 total-album key + album resolution). Deletion
// order albums→artists so a dead album's `album_artist_id` reference is gone before the
// artist reachability check — otherwise `ON DELETE SET DEFAULT` on that column could
// silently rewrite a live album's artist to the sentinel. The `*_Locked` form runs inside
// the caller's transaction so `removeRoot` (already in one) can fold it in — SQLite won't
// nest `BEGIN`.

import Foundation

public extension LibraryStore {
    /// Delete facet rows referenced by nothing: albums with no track; artists referenced by
    /// no track AND no album; genres with no `track_genres` — PRESERVING `artists(id=0)`. ONE
    /// transaction. Returns per-table deletion counts. Run it AFTER the track sweep and
    /// BEFORE `sweepOrphanArtwork` (deleting an album nulls its `artwork_key`, which the
    /// artwork sweep then reclaims).
    @discardableResult
    func sweepOrphanFacets() throws -> FacetSweepCounts {
        try connection.transaction { try sweepOrphanFacetsLocked() }
    }

    /// The transaction-free body of `sweepOrphanFacets`, so `removeRoot` can fold it into its
    /// existing transaction. Runs inside the caller's transaction.
    @discardableResult
    internal func sweepOrphanFacetsLocked() throws -> FacetSweepCounts {
        // 1. Albums with no track — freed FIRST so a dead album no longer protects its artist.
        let albums = try deleteReturningCount(
            "DELETE FROM albums WHERE id NOT IN (SELECT album_id FROM tracks WHERE album_id IS NOT NULL);"
        )
        // 2. Artists referenced by NO track AND NO (surviving) album — never the id-0 sentinel.
        let artists = try deleteReturningCount(
            "DELETE FROM artists WHERE id <> ? "
                + "AND id NOT IN (SELECT artist_id FROM tracks WHERE artist_id IS NOT NULL) "
                + "AND id NOT IN (SELECT album_artist_id FROM albums WHERE album_artist_id IS NOT NULL);",
            sentinel: unknownArtistID
        )
        // 3. Genres with no memberships (track_genres cascades when a track is deleted).
        let genres = try deleteReturningCount(
            "DELETE FROM genres WHERE id NOT IN (SELECT genre_id FROM track_genres);"
        )
        return FacetSweepCounts(albums: albums, artists: artists, genres: genres)
    }

    /// Run a DELETE (optionally binding the sentinel id at index 1) and return the row count
    /// it removed. The tiny shared helper for the three facet deletes.
    private func deleteReturningCount(_ sql: String, sentinel: Int64? = nil) throws -> Int {
        let statement = try connection.prepare(sql)
        defer { statement.finalize() }
        if let sentinel {
            try statement.bind(sentinel, at: 1)
        }
        _ = try statement.step()
        return connection.changes()
    }
}
