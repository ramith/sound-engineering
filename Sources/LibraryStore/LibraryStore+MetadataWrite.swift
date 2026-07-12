// LibraryStore+MetadataWrite — the S8.3 metadata/artwork write ops (design §5-8), GRDB-backed.
//
// `applyExtractedResult` folds the tag write (`applyMetadataLocked`), the artwork link, and
// the `metadata_scanned` marker into ONE write transaction, so "attempt recorded" commits
// ATOMICALLY with the write — an interrupt between them can't leave a written-but-unmarked
// row. Orphan artwork is swept by pure REACHABILITY (referenced by no track AND no album),
// NEVER an incremental `ref_count` (counters desync — design §7, vet §11-c).

import Foundation
import GRDB

public extension LibraryStore {
    // MARK: - SQL

    /// `artwork` rows referenced by NO track and NO album (pure reachability orphan test).
    private static let selectOrphanArtworkSQL = """
    SELECT content_hash, cache_path FROM artwork
    WHERE content_hash NOT IN (SELECT artwork_key FROM tracks WHERE artwork_key IS NOT NULL)
      AND content_hash NOT IN (SELECT artwork_key FROM albums WHERE artwork_key IS NOT NULL);
    """
    /// Delete a single `artwork` row by its content hash.
    private static let deleteArtworkByHashSQL = "DELETE FROM artwork WHERE content_hash = ?;"
    /// Point a track at an artwork content hash.
    private static let setTrackArtworkKeySQL = "UPDATE tracks SET artwork_key = ? WHERE id = ?;"
    /// Set a track's album cover to the artwork hash — only when the album has none yet.
    private static let setAlbumArtworkKeySQL =
        "UPDATE albums SET artwork_key = ? "
            + "WHERE id = (SELECT album_id FROM tracks WHERE id = ?) AND artwork_key IS NULL;"
    /// `UPDATE tracks SET metadata_scanned = generation` — the anti-loop attempt marker.
    private static let markMetadataScannedSQL = "UPDATE tracks SET metadata_scanned = ? WHERE id = ?;"

    /// Apply one file's extracted result to `trackID` in ONE write: tags → (optional) artwork
    /// link + album cover → mark scanned at `generation`. Idempotent. ORDER MATTERS: metadata
    /// first (it sets `album_id`), then artwork (it reads `album_id` for the album cover).
    func applyExtractedResult(
        trackID: Int64, meta: TrackMetadata, artwork: ArtworkLink?, generation: Int64
    ) async throws {
        try await dbWriter.write { db in
            try self.applyMetadataLocked(db, meta, forTrack: trackID)
            if let artwork {
                try self.attachArtworkLocked(db, artwork, toTrack: trackID)
            }
            try self.markMetadataScannedLocked(db, trackID: trackID, generation: generation)
        }
    }

    /// Mark a track's metadata attempt complete at `generation` (own write). The pass calls
    /// this standalone for a no-tags / vanished file so it is NEVER revisited (anti-loop).
    func markMetadataScanned(trackID: Int64, generation: Int64) async throws {
        try await dbWriter.write { db in
            try self.markMetadataScannedLocked(db, trackID: trackID, generation: generation)
        }
    }

    /// Delete `artwork` rows that NO track and NO album references (pure reachability — the
    /// authoritative orphan test). Returns the swept `(contentHash, cachePath)` so the caller
    /// removes the on-disk files. Run once at end-of-pass (non-cancelled only).
    func sweepOrphanArtwork() async throws -> [(contentHash: String, cachePath: String)] {
        try await dbWriter.write { db in
            let rows = try Row.fetchAll(db, sql: Self.selectOrphanArtworkSQL)
            let orphans = rows.map { row in
                (contentHash: (row[0] as String?) ?? "", cachePath: (row[1] as String?) ?? "")
            }
            for orphan in orphans {
                try db.execute(sql: Self.deleteArtworkByHashSQL, arguments: [orphan.contentHash])
            }
            return orphans
        }
    }

    // MARK: - Locked helpers (take the caller's `Database`)

    /// Upsert the artwork row + point the track (and, when unset, its album) at it — NO
    /// `ref_count` writes (orphans are swept by reachability). The album update is an SQL guard
    /// (`… AND artwork_key IS NULL`), not read-then-write. Runs in the caller's write txn.
    internal func attachArtworkLocked(_ db: Database, _ link: ArtworkLink, toTrack trackID: Int64) throws {
        try linkArtwork(db, contentHash: link.contentHash, cachePath: link.cachePath,
                        size: link.pixelSize, byteSize: link.byteSize)
        try db.execute(sql: Self.setTrackArtworkKeySQL, arguments: [link.contentHash, trackID])
        // Album cover = the first APPLIED track's art: only when the album has none yet, and a
        // no-album track (subquery → NULL) matches nothing (no-op).
        try db.execute(sql: Self.setAlbumArtworkKeySQL, arguments: [link.contentHash, trackID])
    }

    /// `UPDATE tracks SET metadata_scanned = generation` — the anti-loop attempt marker.
    internal func markMetadataScannedLocked(_ db: Database, trackID: Int64, generation: Int64) throws {
        try db.execute(sql: Self.markMetadataScannedSQL, arguments: [generation, trackID])
    }
}
