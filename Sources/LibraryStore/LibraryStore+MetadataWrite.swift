// LibraryStore+MetadataWrite — the S8.3 metadata/artwork write ops (design §5-8).
//
// `applyExtractedResult` folds the tag write (`applyMetadataLocked`), the artwork link,
// and the `metadata_scanned` marker into ONE transaction, so "attempt recorded" commits
// ATOMICALLY with the write — an interrupt between them can't leave a written-but-unmarked
// row (which would needlessly re-extract next pass). Orphan artwork is swept by pure
// REACHABILITY: the delete paths (`delete`/`sweepOrphans`/`removeRoot`) null `artwork_key`
// via the FK without touching a counter, so an incremental `ref_count` would desync — the
// authoritative orphan test is "referenced by no track AND no album" (design §7, vet §11-c).

import Foundation

public extension LibraryStore {
    /// Apply one file's extracted result to `trackID` in ONE transaction: tags →
    /// (optional) artwork link + album cover → mark scanned at `generation`. Idempotent
    /// (both `applyMetadataLocked` and `attachArtworkLocked` are). ORDER MATTERS: metadata
    /// first (it sets `album_id`), then artwork (it reads `album_id` for the album cover).
    func applyExtractedResult(
        trackID: Int64, meta: TrackMetadata, artwork: ArtworkLink?, generation: Int64
    ) throws {
        try connection.transaction {
            try applyMetadataLocked(meta, forTrack: trackID)
            if let artwork {
                try attachArtworkLocked(artwork, toTrack: trackID)
            }
            try markMetadataScannedLocked(trackID: trackID, generation: generation)
        }
    }

    /// Mark a track's metadata attempt complete at `generation` (own transaction). The
    /// pass calls this standalone for a no-tags / vanished file so it is NEVER revisited
    /// (anti-loop); `applyExtractedResult` folds the locked form in for a tagged file.
    func markMetadataScanned(trackID: Int64, generation: Int64) throws {
        try connection.transaction {
            try markMetadataScannedLocked(trackID: trackID, generation: generation)
        }
    }

    /// Delete `artwork` rows that NO track and NO album references (pure reachability —
    /// the authoritative orphan test). Returns the swept `(contentHash, cachePath)` so the
    /// caller removes the on-disk files. Run once at end-of-pass (non-cancelled only).
    func sweepOrphanArtwork() throws -> [(contentHash: String, cachePath: String)] {
        try connection.transaction {
            var orphans: [(contentHash: String, cachePath: String)] = []
            let select = try connection.prepare(
                """
                SELECT content_hash, cache_path FROM artwork
                WHERE content_hash NOT IN (SELECT artwork_key FROM tracks WHERE artwork_key IS NOT NULL)
                  AND content_hash NOT IN (SELECT artwork_key FROM albums WHERE artwork_key IS NOT NULL);
                """
            )
            defer { select.finalize() }
            while try select.step() {
                orphans.append((select.columnText(0) ?? "", select.columnText(1) ?? ""))
            }
            for orphan in orphans {
                let delete = try connection.prepare("DELETE FROM artwork WHERE content_hash = ?;")
                defer { delete.finalize() }
                try delete.bind(orphan.contentHash, at: 1)
                _ = try delete.step()
            }
            return orphans
        }
    }

    // MARK: - Locked helpers (no transaction — the caller supplies one)

    /// Upsert the artwork row + point the track (and, when unset, its album) at it — NO
    /// `ref_count` writes (orphans are swept by reachability). The album update is an SQL
    /// guard (`… AND artwork_key IS NULL`), not read-then-write. Runs in the caller's txn.
    internal func attachArtworkLocked(_ link: ArtworkLink, toTrack trackID: Int64) throws {
        try linkArtwork(
            contentHash: link.contentHash, cachePath: link.cachePath,
            size: link.pixelSize, byteSize: link.byteSize
        )
        let setTrack = try connection.prepare("UPDATE tracks SET artwork_key = ? WHERE id = ?;")
        defer { setTrack.finalize() }
        try setTrack.bind(link.contentHash, at: 1)
        try setTrack.bind(trackID, at: 2)
        _ = try setTrack.step()
        // Album cover = the first APPLIED track's art: only when the album has none yet,
        // and a no-album track (subquery → NULL) matches nothing (no-op).
        let setAlbum = try connection.prepare(
            "UPDATE albums SET artwork_key = ? "
                + "WHERE id = (SELECT album_id FROM tracks WHERE id = ?) AND artwork_key IS NULL;"
        )
        defer { setAlbum.finalize() }
        try setAlbum.bind(link.contentHash, at: 1)
        try setAlbum.bind(trackID, at: 2)
        _ = try setAlbum.step()
    }

    /// `UPDATE tracks SET metadata_scanned = generation` — the anti-loop attempt marker.
    internal func markMetadataScannedLocked(trackID: Int64, generation: Int64) throws {
        let statement = try connection.prepare("UPDATE tracks SET metadata_scanned = ? WHERE id = ?;")
        defer { statement.finalize() }
        try statement.bind(generation, at: 1)
        try statement.bind(trackID, at: 2)
        _ = try statement.step()
    }
}
