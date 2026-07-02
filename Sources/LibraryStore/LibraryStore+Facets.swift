// LibraryStore+Facets — facet reads (S9 browse) + the metadata write path (S8.3).
//
// Facet reads (`albums`/`artists`/`genres`) are read-only aggregate queries; like
// all reads they touch no filesystem (§2a). Track counts are computed by JOIN +
// GROUP BY; the harness asserts the counts against a computed `FixtureExpectations`
// so a JOIN fan-out (a genre counted twice, an album over-counted) is caught.
//
// The metadata write path (`applyMetadata`/`linkArtwork`) is provided now (S8.3
// fills it) so the schema's write side is complete + testable. Album/artist/genre
// resolution implements the M1 TOTAL-ALBUM-KEY query-then-insert: an album is keyed
// on (title, album_artist_id defaulting to the id-0 unknown-artist sentinel, year
// defaulting to 0), so untagged albums collapse to ONE row, never N.

import Foundation

public extension LibraryStore {
    // MARK: - Facet reads

    /// Album grid entries with resolved artist name + track count. `sortedBy`
    /// chooses title or year ordering. Counts come from a LEFT JOIN so a zero-track
    /// album (possible after a sweep) still lists with count 0.
    func albums(sortedBy sort: FacetSort = .title) throws -> [AlbumFacet] {
        let order: String
        switch sort {
        case .title:
            order = "al.title COLLATE NOCASE ASC, al.id ASC"
        case .year:
            order = "al.year ASC, al.title COLLATE NOCASE ASC, al.id ASC"
        }
        let sql = """
        SELECT al.id, al.title, al.album_artist_id, ar.name, al.year,
               count(t.id) AS track_count, al.artwork_key
        FROM albums al
        LEFT JOIN artists ar ON ar.id = al.album_artist_id
        LEFT JOIN tracks t ON t.album_id = al.id
        GROUP BY al.id
        ORDER BY \(order);
        """
        let statement = try connection.prepare(sql)
        defer { statement.finalize() }
        var facets: [AlbumFacet] = []
        while try statement.step() {
            facets.append(AlbumFacet(
                id: statement.columnInt64(0),
                title: statement.columnText(1) ?? "",
                albumArtistID: statement.columnInt64(2),
                albumArtist: statement.columnText(3) ?? "",
                year: statement.columnInt(4),
                trackCount: statement.columnInt(5),
                artworkKey: statement.columnText(6)
            ))
        }
        return facets
    }

    /// Artist list entries with track count. Excludes the id-0 unknown-artist
    /// sentinel so an untagged-only library shows no phantom "Unknown Artist" row
    /// in the artist list (it still backs the album key internally).
    func artists(sortedBy sort: FacetSort = .title) throws -> [ArtistFacet] {
        let order = sort == .title
            ? "ar.name COLLATE NOCASE ASC, ar.id ASC"
            : "ar.sort_name COLLATE NOCASE ASC, ar.name COLLATE NOCASE ASC, ar.id ASC"
        let sql = """
        SELECT ar.id, ar.name, ar.sort_name, count(t.id) AS track_count
        FROM artists ar
        LEFT JOIN tracks t ON t.artist_id = ar.id
        WHERE ar.id <> \(unknownArtistID)
        GROUP BY ar.id
        ORDER BY \(order);
        """
        let statement = try connection.prepare(sql)
        defer { statement.finalize() }
        var facets: [ArtistFacet] = []
        while try statement.step() {
            facets.append(ArtistFacet(
                id: statement.columnInt64(0),
                name: statement.columnText(1) ?? "",
                sortName: statement.columnText(2),
                trackCount: statement.columnInt(3)
            ))
        }
        return facets
    }

    /// Genre list entries with DISTINCT track counts. The count uses
    /// `count(DISTINCT track_id)` so the many-to-many `track_genres` join cannot
    /// fan a track out into multiple counted rows.
    func genres() throws -> [GenreFacet] {
        let sql = """
        SELECT g.id, g.name, count(DISTINCT tg.track_id) AS track_count
        FROM genres g
        LEFT JOIN track_genres tg ON tg.genre_id = g.id
        GROUP BY g.id
        ORDER BY g.name COLLATE NOCASE ASC, g.id ASC;
        """
        let statement = try connection.prepare(sql)
        defer { statement.finalize() }
        var facets: [GenreFacet] = []
        while try statement.step() {
            facets.append(GenreFacet(
                id: statement.columnInt64(0),
                name: statement.columnText(1) ?? "",
                trackCount: statement.columnInt(2)
            ))
        }
        return facets
    }

    // MARK: - Metadata write path (S8.3 fills; provided now)

    /// Apply `meta` to track `trackID`: resolve/create album, track-artist, and
    /// genres, then update the metadata columns. ONE transaction. Album resolution
    /// uses the M1 total-album-key so untagged albums collapse to one. Idempotent —
    /// re-applying identical metadata makes no net change.
    func applyMetadata(_ meta: TrackMetadata, forTrack trackID: Int64) throws {
        try connection.transaction {
            let artistID = try meta.artistName.flatMap { try resolveArtist(named: $0) }
            let albumID = try resolveAlbum(for: meta)
            try updateTrackMetadata(trackID: trackID, meta: meta, albumID: albumID, artistID: artistID)
            try replaceGenres(forTrack: trackID, names: meta.genres)
        }
    }

    /// Link (or refresh) an artwork cache reference. S8.3 owns extraction + the
    /// on-disk cache + `ref_count` maintenance; here we upsert the reference row so
    /// the schema's artwork side is exercisable now.
    func linkArtwork(
        contentHash: String, cachePath: String, size: CGSize, byteSize: Int64
    ) throws {
        let statement = try connection.prepare(
            """
            INSERT INTO artwork(content_hash, cache_path, width, height, byte_size, ref_count)
            VALUES (?, ?, ?, ?, ?, 0)
            ON CONFLICT(content_hash) DO UPDATE SET
                cache_path = excluded.cache_path,
                width = excluded.width,
                height = excluded.height,
                byte_size = excluded.byte_size;
            """
        )
        defer { statement.finalize() }
        try statement.bind(contentHash, at: 1)
        try statement.bind(cachePath, at: 2)
        try statement.bind(Int64(size.width), at: 3)
        try statement.bind(Int64(size.height), at: 4)
        try statement.bind(byteSize, at: 5)
        _ = try statement.step()
    }

    // MARK: - Resolution helpers (M1 total-album-key)

    /// Resolve (query-then-insert) an artist by name, returning its rowid. Idempotent
    /// via `UNIQUE(name)`; a repeat call returns the existing id.
    internal func resolveArtist(named name: String) throws -> Int64 {
        if let existing = try connection.scalarInt("SELECT id FROM artists WHERE name = ?;", bind: name) {
            return existing
        }
        let insert = try connection.prepare("INSERT INTO artists(name, sort_name) VALUES (?, ?);")
        defer { insert.finalize() }
        try insert.bind(name, at: 1)
        try insert.bind(name, at: 2)
        _ = try insert.step()
        return connection.lastInsertRowID()
    }

    /// Resolve (query-then-insert) a genre by name, returning its rowid. Idempotent
    /// via `UNIQUE(name)`.
    internal func resolveGenre(named name: String) throws -> Int64 {
        if let existing = try connection.scalarInt("SELECT id FROM genres WHERE name = ?;", bind: name) {
            return existing
        }
        let insert = try connection.prepare("INSERT INTO genres(name) VALUES (?);")
        defer { insert.finalize() }
        try insert.bind(name, at: 1)
        _ = try insert.step()
        return connection.lastInsertRowID()
    }

    /// Resolve an album for `meta` via the M1 TOTAL-ALBUM-KEY query-then-insert.
    /// Returns `nil` when there is no album title (a track with no album stays
    /// `album_id` NULL rather than joining a bogus empty-title album). The key is
    /// (title, album_artist_id, year) with album_artist_id defaulting to the id-0
    /// unknown-artist sentinel and year defaulting to 0 — so two untagged
    /// ('Greatest Hits', 0, 0) collapse to ONE album, not N.
    internal func resolveAlbum(for meta: TrackMetadata) throws -> Int64? {
        guard let title = meta.albumTitle, !title.isEmpty else { return nil }
        let albumArtistID = try meta.albumArtistName
            .flatMap { try resolveArtist(named: $0) } ?? unknownArtistID
        let year = Int64(meta.year ?? 0)

        let query = try connection.prepare(
            "SELECT id FROM albums WHERE title = ? AND album_artist_id = ? AND year = ?;"
        )
        defer { query.finalize() }
        try query.bind(title, at: 1)
        try query.bind(albumArtistID, at: 2)
        try query.bind(year, at: 3)
        if try query.step() {
            return query.columnInt64(0)
        }

        let insert = try connection.prepare(
            "INSERT INTO albums(title, album_artist_id, year) VALUES (?, ?, ?);"
        )
        defer { insert.finalize() }
        try insert.bind(title, at: 1)
        try insert.bind(albumArtistID, at: 2)
        try insert.bind(year, at: 3)
        _ = try insert.step()
        return connection.lastInsertRowID()
    }

    // MARK: - Private metadata update

    /// Write the resolved metadata columns onto the track row (leaving the
    /// scan-owned columns — url/folder/signature — untouched).
    private func updateTrackMetadata(
        trackID: Int64, meta: TrackMetadata, albumID: Int64?, artistID: Int64?
    ) throws {
        let statement = try connection.prepare(
            """
            UPDATE tracks SET
                album_id = ?, artist_id = ?, title = ?, track_no = ?, disc_no = ?,
                year = ?, duration_ms = ?, sample_rate = ?, bit_depth = ?, channels = ?
            WHERE id = ?;
            """
        )
        defer { statement.finalize() }
        try statement.bind(albumID, at: 1)
        try statement.bind(artistID, at: 2)
        try statement.bind(meta.title, at: 3)
        try statement.bind(meta.trackNo.map(Int64.init), at: 4)
        try statement.bind(meta.discNo.map(Int64.init), at: 5)
        try statement.bind(meta.year.map(Int64.init), at: 6)
        try statement.bind(meta.durationMs, at: 7)
        try statement.bind(meta.sampleRate.map(Int64.init), at: 8)
        try statement.bind(meta.bitDepth.map(Int64.init), at: 9)
        try statement.bind(meta.channels.map(Int64.init), at: 10)
        try statement.bind(trackID, at: 11)
        _ = try statement.step()
    }

    /// Replace a track's genre memberships with exactly `names` (resolving each),
    /// clearing any that are no longer present. Runs inside the caller's transaction.
    private func replaceGenres(forTrack trackID: Int64, names: [String]) throws {
        let clear = try connection.prepare("DELETE FROM track_genres WHERE track_id = ?;")
        defer { clear.finalize() }
        try clear.bind(trackID, at: 1)
        _ = try clear.step()

        for name in names where !name.isEmpty {
            let genreID = try resolveGenre(named: name)
            let link = try connection.prepare(
                "INSERT OR IGNORE INTO track_genres(track_id, genre_id) VALUES (?, ?);"
            )
            defer { link.finalize() }
            try link.bind(trackID, at: 1)
            try link.bind(genreID, at: 2)
            _ = try link.step()
        }
    }
}
