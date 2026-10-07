// LibraryStore+Facets — facet reads (S9 browse) + the metadata write path (S8.3), GRDB-backed.
//
// Facet reads (`albums`/`artists`/`genres`) are read-only aggregate queries; like all reads
// they touch no filesystem (§2a). `albums()`/`artists()` delegate to the SHARED
// `fetchAlbums`/`fetchArtists` builders in LibraryStore+FacetDrilldown so the list reads and
// the single-facet reads can never drift and the id-0 sentinel exclusion is defined once.
//
// The metadata write path (`applyMetadata`/`linkArtwork` + the resolvers) stores a song's tags,
// including its RAW album inputs (title, album-artist tag, compilation flag), then keeps its
// album current through `AlbumGrouping` (S10.8 C2 — `LibraryStore+AlbumGrouping`), which amends
// the M1 total album key: tagged albums key on their album artist, untagged ones on their folder.
// A metadata pass leaves the albums to its end-of-pass regroup; a single write regroups its own
// neighbourhood (C2 fix round, B2). Each resolver is RACE-SAFE: `ON CONFLICT(<unique-key>) DO
// NOTHING` then a re-SELECT, so two writers inserting the same brand-new name resolve to the
// winner's row.

import Foundation
import GRDB

// MARK: - GenreFacet row decoding (FetchableRecord)

extension GenreFacet: FetchableRecord {
    /// Decode a `g.id, g.name, count(...)` genre-facet row (positional).
    public init(row: Row) {
        self.init(id: row[0], name: row[1] ?? "", trackCount: row[2])
    }
}

public extension LibraryStore {
    // MARK: - SQL

    /// Genre list entries with DISTINCT track counts, name-ordered.
    private static let selectGenresSQL = """
    SELECT g.id, g.name, count(DISTINCT tg.track_id) AS track_count
    FROM genres g
    LEFT JOIN track_genres tg ON tg.genre_id = g.id
    GROUP BY g.id
    ORDER BY g.name COLLATE NOCASE ASC, g.id ASC;
    """
    /// Upsert the `artwork` reference row (no `ref_count` write — orphans are swept by reachability).
    private static let upsertArtworkSQL = """
    INSERT INTO artwork(content_hash, cache_path, width, height, byte_size, ref_count)
    VALUES (?, ?, ?, ?, ?, 0)
    ON CONFLICT(content_hash) DO UPDATE SET
        cache_path = excluded.cache_path,
        width = excluded.width,
        height = excluded.height,
        byte_size = excluded.byte_size;
    """
    /// Resolve an artist rowid by its unique name.
    private static let selectArtistIDByNameSQL = "SELECT id FROM artists WHERE name = ?;"
    /// Insert an artist (race-safe; `ON CONFLICT(name) DO NOTHING`).
    private static let insertArtistSQL =
        "INSERT INTO artists(name, sort_name) VALUES (?, ?) ON CONFLICT(name) DO NOTHING;"
    /// Resolve a genre rowid by its unique name.
    private static let selectGenreIDByNameSQL = "SELECT id FROM genres WHERE name = ?;"
    /// Insert a genre (race-safe; `ON CONFLICT(name) DO NOTHING`).
    private static let insertGenreSQL =
        "INSERT INTO genres(name) VALUES (?) ON CONFLICT(name) DO NOTHING;"
    /// Write the tag columns onto a track — the raw album inputs included, `album_id` NOT (the
    /// regroup assigns it). Scan-owned and user-state columns are untouched.
    private static let updateTrackMetadataSQL = """
    UPDATE tracks SET
        album_title = ?, album_artist_tag = ?, compilation = ?, artist_id = ?, title = ?,
        track_no = ?, disc_no = ?, year = ?, duration_ms = ?, sample_rate = ?, bit_depth = ?,
        channels = ?
    WHERE id = ?;
    """
    /// A song's stored album title before a tag write (its old album must be regrouped too); no
    /// row = the song is gone (its folder was removed mid-pass).
    private static let selectAlbumTitleSQL = "SELECT album_title FROM tracks WHERE id = ?;"
    /// Clear a track's genre memberships (before re-inserting the current set).
    private static let deleteTrackGenresSQL = "DELETE FROM track_genres WHERE track_id = ?;"
    /// Insert one `track_genres` membership (idempotent via the PK).
    private static let insertTrackGenreSQL =
        "INSERT OR IGNORE INTO track_genres(track_id, genre_id) VALUES (?, ?);"

    // MARK: - Facet reads

    /// Album grid entries with resolved artist name + track count. Delegates to the shared
    /// `fetchAlbums` builder so `album(id:)` returns a facet identical to the list entry.
    func albums(sortedBy sort: FacetSort = .title, limit: Int? = nil, offset: Int = 0) async throws -> [AlbumFacet] {
        let order = sort == .title ? LibraryStore.albumTitleOrder : LibraryStore.albumYearOrder
        let args = StatementArguments(LibraryStore.paginationArgs(limit: limit, offset: offset))
        return try await dbWriter.read { db in
            try Self.fetchAlbums(db, whereClause: "", order: order, limited: limit != nil, arguments: args)
        }
    }

    /// Artist list entries with track count. Excludes the id-0 unknown-artist sentinel (the
    /// exclusion lives in the shared `artistSelectSQL`). Optional `limit`/`offset` paginate.
    func artists(sortedBy sort: FacetSort = .title, limit: Int? = nil, offset: Int = 0) async throws -> [ArtistFacet] {
        let order = sort == .title ? LibraryStore.artistNameOrder : LibraryStore.artistSortNameOrder
        let args = StatementArguments(LibraryStore.paginationArgs(limit: limit, offset: offset))
        return try await dbWriter.read { db in
            try Self.fetchArtists(db, extraWhere: "", order: order, limited: limit != nil, arguments: args)
        }
    }

    /// Genre list entries with DISTINCT track counts. `count(DISTINCT track_id)` so the
    /// many-to-many `track_genres` join cannot fan a track out into multiple counted rows.
    func genres() async throws -> [GenreFacet] {
        try await dbWriter.read { db in
            try GenreFacet.fetchAll(db, sql: Self.selectGenresSQL)
        }
    }

    // MARK: - Metadata write path

    /// Apply `meta` to track `trackID` — a SINGLE write outside a metadata pass: resolve/create the
    /// track-artist and genres, write the tag columns, then regroup the song's own neighbourhood
    /// (`AlbumGrouping`), so the store is consistent at this commit. ONE write transaction.
    /// Idempotent; a no-op when the song is gone.
    func applyMetadata(_ meta: TrackMetadata, forTrack trackID: Int64) async throws {
        _ = try await dbWriter.write { db in
            try self.applyMetadataLocked(db, meta, forTrack: trackID, albums: .ownNeighbourhood)
        }
    }

    /// The body of `applyMetadata`, so `applyExtractedResult` (LibraryStore+MetadataWrite) can
    /// fold it into a SINGLE per-track write alongside the artwork link + the
    /// `metadata_scanned` marker. Runs inside the caller's `Database`. Returns false — writing
    /// nothing — when the song's row is gone (its folder was removed while a pass was reading it,
    /// C2 fix round B3), so no genre or artwork row is written for a song that no longer exists.
    @discardableResult
    internal func applyMetadataLocked(
        _ db: Database, _ meta: TrackMetadata, forTrack trackID: Int64, albums: AlbumUpkeep
    ) throws -> Bool {
        guard let stored = try Row.fetchOne(db, sql: Self.selectAlbumTitleSQL, arguments: [trackID]) else {
            return false
        }
        let previousTitle: String? = stored[0]
        let artistID = try meta.artistName.map { try resolveArtist(db, named: $0) }
        try updateTrackMetadata(db, trackID: trackID, meta: meta, artistID: artistID)
        try replaceGenres(db, forTrack: trackID, names: meta.genres)
        switch albums {
        case .deferredToPassEnd:
            try markAlbumRegroupOwedLocked(db)
        case .ownNeighbourhood:
            let titles = Set([previousTitle, meta.albumTitle].compactMap(\.self))
            try regroupOwnAlbumLocked(db, trackID: trackID, titles: titles)
        }
        // Re-index for search AFTER genres are written so the FTS row is fresh (design §4); its
        // album text is the song's own album title, so it never waits for the regroup.
        try syncSearchRow(db, trackID: trackID)
        return true
    }

    /// Link (or refresh) an artwork cache reference (public convenience; the write path uses
    /// the `Database`-scoped form below). S8.3 owns extraction + the on-disk cache; orphans are
    /// swept by reachability, so there is NO `ref_count` write here.
    func linkArtwork(contentHash: String, cachePath: String, size: CGSize, byteSize: Int64) async throws {
        try await dbWriter.write { db in
            try self.linkArtwork(db, contentHash: contentHash, cachePath: cachePath, size: size, byteSize: byteSize)
        }
    }

    /// The `Database`-scoped body of `linkArtwork` — upsert the `artwork` reference row.
    internal func linkArtwork(
        _ db: Database, contentHash: String, cachePath: String, size: CGSize, byteSize: Int64
    ) throws {
        try db.execute(
            sql: Self.upsertArtworkSQL,
            arguments: [contentHash, cachePath, Int64(size.width), Int64(size.height), byteSize]
        )
    }

    // MARK: - Resolution helpers

    /// Resolve (query-then-insert) an artist by name, returning its rowid. Idempotent via
    /// `UNIQUE(name)`; RACE-SAFE (`ON CONFLICT(name) DO NOTHING` then re-SELECT).
    internal func resolveArtist(_ db: Database, named name: String) throws -> Int64 {
        if let existing = try Int64.fetchOne(db, sql: Self.selectArtistIDByNameSQL, arguments: [name]) {
            return existing
        }
        try db.execute(sql: Self.insertArtistSQL, arguments: [name, name])
        // Re-SELECT (not lastInsertedRowID): on a race the INSERT did nothing and the id
        // belongs to the row the other writer wrote.
        guard let id = try Int64.fetchOne(db, sql: Self.selectArtistIDByNameSQL, arguments: [name]) else {
            throw SQLiteError.internalError(message: "resolveArtist: row for name not found after insert")
        }
        return id
    }

    /// Resolve (query-then-insert) a genre by name, returning its rowid. RACE-SAFE.
    internal func resolveGenre(_ db: Database, named name: String) throws -> Int64 {
        if let existing = try Int64.fetchOne(db, sql: Self.selectGenreIDByNameSQL, arguments: [name]) {
            return existing
        }
        try db.execute(sql: Self.insertGenreSQL, arguments: [name])
        guard let id = try Int64.fetchOne(db, sql: Self.selectGenreIDByNameSQL, arguments: [name]) else {
            throw SQLiteError.internalError(message: "resolveGenre: row for name not found after insert")
        }
        return id
    }

    // MARK: - Private metadata update

    /// Write the tag columns onto the track row (leaving the scan-owned columns — url/folder/
    /// signature — and the user-state columns untouched). The album inputs arrive normalised
    /// (`TrackMetadata.init`, C5): an empty or missing one is already nil.
    private func updateTrackMetadata(
        _ db: Database, trackID: Int64, meta: TrackMetadata, artistID: Int64?
    ) throws {
        try db.execute(
            sql: Self.updateTrackMetadataSQL,
            arguments: [
                meta.albumTitle, meta.albumArtistName, meta.isCompilation ? 1 : 0, artistID, meta.title,
                meta.trackNo.map { Int64($0) }, meta.discNo.map { Int64($0) }, meta.year.map { Int64($0) },
                meta.durationMs,
                meta.sampleRate.map { Int64($0) }, meta.bitDepth.map { Int64($0) },
                meta.channels.map { Int64($0) }, trackID,
            ]
        )
    }

    /// Replace a track's genre memberships with exactly `names` (resolving each), clearing any
    /// no longer present. Runs inside the caller's `Database`.
    private func replaceGenres(_ db: Database, forTrack trackID: Int64, names: [String]) throws {
        try db.execute(sql: Self.deleteTrackGenresSQL, arguments: [trackID])
        for name in names where !name.isEmpty {
            let genreID = try resolveGenre(db, named: name)
            try db.execute(sql: Self.insertTrackGenreSQL, arguments: [trackID, genreID])
        }
    }
}
