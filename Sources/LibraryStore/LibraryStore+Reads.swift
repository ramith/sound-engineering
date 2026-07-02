// LibraryStore+Reads — the read side of the S8.1b DAO (design §4).
//
// Every read here goes through the actor-isolated connection and returns only
// `Sendable` value types. CRITICAL (design §2a): reads make NO filesystem calls and
// assert NO file existence — a `tracks.url` may point at a path that has since been
// deleted / modified / moved while the app was closed or running. A diverged row is
// still fully queryable; reconciliation is a scan's job (S8.2/S8.4), never a read's.
//
// The `tracks` column list + row mapper are centralised (`trackColumns` /
// `mapTrackRow`) so every track-returning query decodes identically — one place to
// keep column order and the read model in lock-step.

import Foundation

public extension LibraryStore {
    // MARK: - Track column list + mapper (single source of truth)

    /// The `tracks` columns, in the fixed order `mapTrackRow` decodes. Every
    /// track-returning SELECT projects exactly this list so decoding never drifts.
    internal static let trackColumns =
        "id, url, folder_id, relative_path, name, format, file_size, mtime, inode, "
            + "album_id, artist_id, title, track_no, disc_no, year, duration_ms, artwork_key"

    /// Decode the current row of `statement` (projected as `trackColumns`) into a
    /// `LibraryTrack`. `url` is reconstructed from the stored string with
    /// `URL(fileURLWithPath:)`; no filesystem access, no existence assertion.
    internal func mapTrackRow(_ statement: SQLiteStatement) -> LibraryTrack {
        LibraryTrack(
            id: statement.columnInt64(0),
            url: URL(fileURLWithPath: statement.columnText(1) ?? ""),
            folderID: statement.columnIsNull(2) ? nil : statement.columnInt64(2),
            relativePath: statement.columnText(3) ?? "",
            name: statement.columnText(4) ?? "",
            format: statement.columnText(5) ?? "",
            fileSize: statement.columnInt64(6),
            mtime: statement.columnInt64(7),
            inode: statement.columnIsNull(8) ? nil : statement.columnInt64(8),
            albumID: statement.columnIsNull(9) ? nil : statement.columnInt64(9),
            artistID: statement.columnIsNull(10) ? nil : statement.columnInt64(10),
            title: statement.columnText(11),
            trackNo: statement.columnIsNull(12) ? nil : statement.columnInt(12),
            discNo: statement.columnIsNull(13) ? nil : statement.columnInt(13),
            year: statement.columnIsNull(14) ? nil : statement.columnInt(14),
            durationMs: statement.columnInt64(15),
            artworkKey: statement.columnText(16)
        )
    }

    /// Run `sql` (projecting `trackColumns`), binding `bind` to it, and map every
    /// row to a `LibraryTrack`. The shared engine for all track list reads.
    internal func fetchTracks(_ sql: String, bind: (SQLiteStatement) throws -> Void = { _ in }) throws
        -> [LibraryTrack] {
        let statement = try connection.prepare(sql)
        defer { statement.finalize() }
        try bind(statement)
        var tracks: [LibraryTrack] = []
        while try statement.step() {
            tracks.append(mapTrackRow(statement))
        }
        return tracks
    }

    // MARK: - Track reads

    /// All tracks in the store, ordered by `sortedBy`. Reads never touch the FS (§2a).
    func allTracks(sortedBy sort: TrackSort = .name) throws -> [LibraryTrack] {
        let order: String
        switch sort {
        case .name:
            order = "name COLLATE NOCASE ASC, id ASC"
        case .album:
            // Album-then-disc/track; NULL album_id sorts last, then a stable id tie-break.
            order = "album_id IS NULL, album_id ASC, disc_no ASC, track_no ASC, id ASC"
        case .dateAddedDescending:
            order = "date_added DESC, id DESC"
        }
        return try fetchTracks(
            "SELECT \(LibraryStore.trackColumns) FROM tracks ORDER BY \(order);"
        )
    }

    /// The single track at `url` (its normalised key form), or `nil` if absent.
    func track(url: URL) throws -> LibraryTrack? {
        let key = PathNormalizer.normalizedString(for: url)
        let rows = try fetchTracks(
            "SELECT \(LibraryStore.trackColumns) FROM tracks WHERE url = ?;"
        ) { statement in
            try statement.bind(key, at: 1)
        }
        return rows.first
    }

    /// The single track with stable id `id`, or `nil` if absent.
    func track(id: Int64) throws -> LibraryTrack? {
        let rows = try fetchTracks(
            "SELECT \(LibraryStore.trackColumns) FROM tracks WHERE id = ?;"
        ) { statement in
            try statement.bind(id, at: 1)
        }
        return rows.first
    }

    /// All tracks directly under folder `folderID`, name-ordered.
    func tracks(inFolder folderID: Int64) throws -> [LibraryTrack] {
        try fetchTracks(
            "SELECT \(LibraryStore.trackColumns) FROM tracks WHERE folder_id = ? "
                + "ORDER BY name COLLATE NOCASE ASC, id ASC;"
        ) { statement in
            try statement.bind(folderID, at: 1)
        }
    }

    /// All tracks on album `albumID`, ordered by disc then track number (the
    /// album-detail order) with a stable id tie-break for untagged track numbers.
    func tracks(inAlbum albumID: Int64) throws -> [LibraryTrack] {
        try fetchTracks(
            "SELECT \(LibraryStore.trackColumns) FROM tracks WHERE album_id = ? "
                + "ORDER BY disc_no ASC, track_no ASC, id ASC;"
        ) { statement in
            try statement.bind(albumID, at: 1)
        }
    }

    /// Total number of track rows in the store.
    func trackCount() throws -> Int {
        try Int(connection.scalarInt("SELECT count(*) FROM tracks;") ?? 0)
    }
}
