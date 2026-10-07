// LibraryStore+MetadataWrite — the S8.3 metadata/artwork write ops (design §5-8), GRDB-backed.
//
// `applyExtractedResult` — the metadata PASS's write — folds the tag write
// (`applyMetadataLocked`), the artwork link, and the `metadata_scanned` marker into ONE write
// transaction, so "attempt recorded" commits ATOMICALLY with the write — an interrupt between
// them can't leave a written-but-unmarked row. It does no album work: the end-of-pass regroup
// assigns albums and their covers (S10.8 C2 fix round, B2/C8), and the write records that debt.
// Orphan artwork is swept by pure REACHABILITY (referenced by no track AND no album), NEVER an
// incremental `ref_count` (counters desync — design §7, vet §11-c).

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
    /// `UPDATE tracks SET metadata_scanned = generation` — the anti-loop attempt marker.
    private static let markMetadataScannedSQL = "UPDATE tracks SET metadata_scanned = ? WHERE id = ?;"

    /// Apply one file's extracted result to `trackID` in ONE write — the metadata pass's write:
    /// tags → (optional) artwork link → mark scanned at `generation`. No album work: the
    /// end-of-pass regroup (`refreshDerivedFacets`) assigns the album and its cover, and this
    /// write records that it is owed. Idempotent; a no-op when the song's row is gone (its folder
    /// was removed mid-pass — C2 fix round B3).
    func applyExtractedResult(
        trackID: Int64, meta: TrackMetadata, artwork: ArtworkLink?, generation: Int64
    ) async throws {
        try await dbWriter.write { db in
            guard try self.applyMetadataLocked(db, meta, forTrack: trackID, albums: .deferredToPassEnd) else {
                return
            }
            if let artwork {
                try self.attachArtworkLocked(db, artwork, toTrack: trackID)
            }
            try self.markMetadataScannedLocked(db, trackID: trackID, generation: generation)
        }
    }

    /// Mark a track's metadata attempt complete at `generation` (own write). The pass calls
    /// this standalone for a file that is there but can't be parsed, so it is NEVER revisited
    /// (anti-loop). A file that is NOT there is left pending instead (S10.8 C2 fix round, B1).
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

    /// Upsert the artwork row + point the track at it — NO `ref_count` writes (orphans are swept
    /// by reachability). The ALBUM cover is not set here: the regroup derives it from the album's
    /// first song with art in (disc, track) order (`AlbumGrouping.display`, C2 fix round C8), so it
    /// never depends on which file was read first. Runs in the caller's write txn.
    internal func attachArtworkLocked(_ db: Database, _ link: ArtworkLink, toTrack trackID: Int64) throws {
        try linkArtwork(db, contentHash: link.contentHash, cachePath: link.cachePath,
                        size: link.pixelSize, byteSize: link.byteSize)
        try db.execute(sql: Self.setTrackArtworkKeySQL, arguments: [link.contentHash, trackID])
    }

    /// `UPDATE tracks SET metadata_scanned = generation` — the anti-loop attempt marker.
    internal func markMetadataScannedLocked(_ db: Database, trackID: Int64, generation: Int64) throws {
        try db.execute(sql: Self.markMetadataScannedSQL, arguments: [generation, trackID])
    }
}
