// LibraryStore+Playlists — the playlist/queue DAO (S10.1, design §4), GRDB-backed.
//
// Single writer by construction (see LibraryStore+DAO): every mutation is one
// `dbWriter.write { db in … }` closure = one IMMEDIATE transaction, so read-then-write
// helpers (untitled-N lowest-unused, the built-in bootstrap, insert-at/reorder
// renormalization, loose-add) are atomic / TOCTOU-free without a hand-rolled BEGIN.
//
// Identity (design §2/§0.2): entries reference the durable `tracks.id`, never `url`.
// A playlist can hold the SAME track more than once — each entry has its OWN id + a
// `position` ordering key. `track_id → tracks.id ON DELETE CASCADE`: a genuinely-deleted
// track (file gone / explicit delete) drops out of its playlists (founder decision §0.2).
// Duplicate USER playlist names are rejected (§0.4); the built-in "current" is exempt.

import Foundation
import GRDB

// MARK: - Value types (Sendable — cross the store boundary; no Database escapes)

/// A playlist row. `entryCount` is resolved by the list query (LEFT JOIN COUNT).
public struct Playlist: Sendable, Identifiable, Equatable {
    public let id: Int64
    public let name: String
    public let isBuiltin: Bool
    public let createdAt: Int64
    public let entryCount: Int

    public init(id: Int64, name: String, isBuiltin: Bool, createdAt: Int64, entryCount: Int) {
        self.id = id
        self.name = name
        self.isBuiltin = isBuiltin
        self.createdAt = createdAt
        self.entryCount = entryCount
    }
}

/// An ordered playlist entry. Its OWN `id` is what lets a track repeat within one playlist.
public struct PlaylistEntry: Sendable, Identifiable, Equatable {
    public let id: Int64
    public let playlistID: Int64
    public let trackID: Int64
    public let position: Int
    public let addedAt: Int64

    public init(id: Int64, playlistID: Int64, trackID: Int64, position: Int, addedAt: Int64) {
        self.id = id
        self.playlistID = playlistID
        self.trackID = trackID
        self.position = position
        self.addedAt = addedAt
    }
}

/// Result of adding a (possibly non-library) loose file to a playlist.
public struct LooseAddResult: Sendable, Equatable {
    public let trackID: Int64
    public let entryID: Int64

    public init(trackID: Int64, entryID: Int64) {
        self.trackID = trackID
        self.entryID = entryID
    }
}

/// A create/rename collided with an existing USER playlist name (`UNIQUE(name) WHERE
/// is_builtin=0`). Mirrors `URLConflict`; the UI (S10.3) decides auto-suffix vs. inline message.
public struct PlaylistNameConflict: Error, Sendable, Equatable {
    public let name: String
    public let existingID: Int64
    public init(name: String, existingID: Int64) {
        self.name = name
        self.existingID = existingID
    }
}

/// Defensive guards for built-in / missing playlists.
public enum PlaylistMutationError: Error, Sendable, Equatable {
    /// Rename/delete of the built-in "current" playlist is rejected.
    case builtinImmutable(id: Int64)
    /// No playlist row for the given id.
    case notFound(id: Int64)
}

// MARK: - Row decoding

extension Playlist: FetchableRecord {
    /// Decodes a row projected as `id, name, is_builtin, created_at, entry_count`.
    public init(row: Row) {
        self.init(id: row[0], name: row[1] ?? "", isBuiltin: (row[2] as Int64) != 0,
                  createdAt: row[3], entryCount: Int(row[4] as Int64))
    }
}

extension PlaylistEntry: FetchableRecord {
    /// Decodes a row projected as `id, playlist_id, track_id, position, added_at`.
    public init(row: Row) {
        self.init(id: row[0], playlistID: row[1], trackID: row[2],
                  position: Int(row[3] as Int64), addedAt: row[4])
    }
}

public extension LibraryStore {
    // MARK: - SQL

    private static let selectPlaylistsSQL = """
    SELECT p.id, p.name, p.is_builtin, p.created_at,
           (SELECT COUNT(*) FROM playlist_entries e WHERE e.playlist_id = p.id) AS entry_count
    FROM playlists p
    ORDER BY p.is_builtin DESC, p.name COLLATE NOCASE ASC, p.id ASC;
    """
    private static let selectPlaylistByIDSQL = """
    SELECT p.id, p.name, p.is_builtin, p.created_at,
           (SELECT COUNT(*) FROM playlist_entries e WHERE e.playlist_id = p.id) AS entry_count
    FROM playlists p WHERE p.id = ?;
    """
    private static let selectPlaylistCountSQL = "SELECT COUNT(*) FROM playlists;"
    private static let selectEntriesSQL =
        "SELECT id, playlist_id, track_id, position, added_at FROM playlist_entries "
            + "WHERE playlist_id = ? ORDER BY position ASC, id ASC;"
    private static let selectUserNameConflictSQL =
        "SELECT id FROM playlists WHERE name = ? AND is_builtin = 0 LIMIT 1;"
    private static let selectIsBuiltinSQL = "SELECT is_builtin FROM playlists WHERE id = ?;"
    private static let selectBuiltinIDSQL = "SELECT id FROM playlists WHERE is_builtin = 1 LIMIT 1;"
    private static let selectUntitledNamesSQL =
        "SELECT name FROM playlists WHERE name LIKE 'New Playlist%';"
    private static let insertUserPlaylistSQL =
        "INSERT INTO playlists(name, is_builtin, created_at) VALUES (?, 0, ?);"
    private static let renamePlaylistSQL = "UPDATE playlists SET name = ? WHERE id = ?;"
    private static let deletePlaylistSQL = "DELETE FROM playlists WHERE id = ?;"
    private static let maxPositionSQL =
        "SELECT COALESCE(MAX(position), -1) FROM playlist_entries WHERE playlist_id = ?;"
    private static let insertEntrySQL =
        "INSERT INTO playlist_entries(playlist_id, track_id, position, added_at) VALUES (?, ?, ?, ?);"
    private static let deleteEntryByIDSQL = "DELETE FROM playlist_entries WHERE id = ?;"
    private static let selectEntryIDsInOrderSQL =
        "SELECT id FROM playlist_entries WHERE playlist_id = ? ORDER BY position ASC, id ASC;"
    private static let updateEntryPositionSQL =
        "UPDATE playlist_entries SET position = ? WHERE id = ? AND playlist_id = ?;"

    // MARK: - Playlist lifecycle

    /// Create a user playlist. Throws `PlaylistNameConflict` if a user playlist already holds
    /// `name` (the read-then-insert is atomic in the single-writer txn; the `UNIQUE(name)
    /// WHERE is_builtin=0` index is the backstop). Returns the new id.
    @discardableResult
    func createPlaylist(name: String) async throws -> Int64 {
        try await dbWriter.write { db in
            if let existing = try Int64.fetchOne(db, sql: Self.selectUserNameConflictSQL, arguments: [name]) {
                throw PlaylistNameConflict(name: name, existingID: existing)
            }
            try db.execute(sql: Self.insertUserPlaylistSQL,
                           arguments: [name, LibraryStore.nowSeconds()])
            return db.lastInsertedRowID
        }
    }

    /// Create a playlist with an Apple-style default name ("New Playlist", then "New Playlist 2",
    /// … lowest-unused). Race-safe: the scan-then-insert runs in one write txn.
    @discardableResult
    func createUntitledPlaylist() async throws -> Int64 {
        try await dbWriter.write { db in
            let taken = try Set(String.fetchAll(db, sql: Self.selectUntitledNamesSQL))
            let name = Self.lowestUnusedDefaultName(taken: taken)
            try db.execute(sql: Self.insertUserPlaylistSQL,
                           arguments: [name, LibraryStore.nowSeconds()])
            return db.lastInsertedRowID
        }
    }

    /// "New Playlist", else the lowest "New Playlist N" (N ≥ 2) not already taken (Apple-style).
    static func lowestUnusedDefaultName(taken: Set<String>) -> String {
        let base = "New Playlist"
        if !taken.contains(base) { return base }
        var n = 2
        while taken.contains("\(base) \(n)") {
            n += 1
        }
        return "\(base) \(n)"
    }

    /// Rename a playlist. Rejects the built-in ("current") with `.builtinImmutable`, a missing id
    /// with `.notFound`, and a user-name collision with `PlaylistNameConflict`.
    func renamePlaylist(id: Int64, to name: String) async throws {
        try await dbWriter.write { db in
            guard let isBuiltin = try Int64.fetchOne(db, sql: Self.selectIsBuiltinSQL, arguments: [id]) else {
                throw PlaylistMutationError.notFound(id: id)
            }
            if isBuiltin != 0 { throw PlaylistMutationError.builtinImmutable(id: id) }
            if let existing = try Int64.fetchOne(db, sql: Self.selectUserNameConflictSQL, arguments: [name]),
               existing != id {
                throw PlaylistNameConflict(name: name, existingID: existing)
            }
            try db.execute(sql: Self.renamePlaylistSQL, arguments: [name, id])
        }
    }

    /// Delete a playlist (its entries CASCADE). Rejects the built-in with `.builtinImmutable`,
    /// a missing id with `.notFound`.
    func deletePlaylist(id: Int64) async throws {
        try await dbWriter.write { db in
            guard let isBuiltin = try Int64.fetchOne(db, sql: Self.selectIsBuiltinSQL, arguments: [id]) else {
                throw PlaylistMutationError.notFound(id: id)
            }
            if isBuiltin != 0 { throw PlaylistMutationError.builtinImmutable(id: id) }
            try db.execute(sql: Self.deletePlaylistSQL, arguments: [id])
        }
    }

    // MARK: - Reads

    func playlists() async throws -> [Playlist] {
        try await dbWriter.read { db in try Playlist.fetchAll(db, sql: Self.selectPlaylistsSQL) }
    }

    func playlist(id: Int64) async throws -> Playlist? {
        try await dbWriter.read { db in try Playlist.fetchOne(db, sql: Self.selectPlaylistByIDSQL, arguments: [id]) }
    }

    func playlistCount() async throws -> Int {
        try await dbWriter.read { db in try Int(Int64.fetchOne(db, sql: Self.selectPlaylistCountSQL) ?? 0) }
    }

    func entries(inPlaylist id: Int64) async throws -> [PlaylistEntry] {
        try await dbWriter.read { db in try PlaylistEntry.fetchAll(db, sql: Self.selectEntriesSQL, arguments: [id]) }
    }

    // MARK: - Built-in "current" queue playlist

    /// Idempotent: return the existing built-in id, else seed "current" (belt-and-braces for the
    /// DEBUG erase-rebuild path; the v3 migration also seeds it).
    @discardableResult
    func bootstrapBuiltinCurrentPlaylist() async throws -> Int64 {
        try await dbWriter.write { db in try Self.builtinIDLocked(db) }
    }

    /// The built-in "current" playlist id (bootstraps if somehow absent).
    func currentPlaylistID() async throws -> Int64 {
        try await dbWriter.write { db in try Self.builtinIDLocked(db) }
    }

    private static func builtinIDLocked(_ db: Database) throws -> Int64 {
        if let id = try Int64.fetchOne(db, sql: selectBuiltinIDSQL) { return id }
        try Schema.seedBuiltinCurrentPlaylist(db, timestamp: LibraryStore.nowSeconds())
        guard let id = try Int64.fetchOne(db, sql: selectBuiltinIDSQL) else {
            throw SQLiteError.internalError(message: "builtin 'current' playlist not found after seed")
        }
        return id
    }

    // MARK: - Ordered membership

    /// Append a track to the end of a playlist (`position = MAX+1`). Returns the new entry id.
    @discardableResult
    func appendEntry(playlistID: Int64, trackID: Int64) async throws -> Int64 {
        try await dbWriter.write { db in try self.appendEntryLocked(db, playlistID: playlistID, trackID: trackID) }
    }

    /// Append several tracks (in order) to a playlist in one transaction.
    @discardableResult
    func appendEntries(playlistID: Int64, trackIDs: [Int64]) async throws -> [Int64] {
        try await dbWriter.write { db in
            var ids: [Int64] = []
            for trackID in trackIDs {
                try ids.append(self.appendEntryLocked(db, playlistID: playlistID, trackID: trackID))
            }
            return ids
        }
    }

    private func appendEntryLocked(_ db: Database, playlistID: Int64, trackID: Int64) throws -> Int64 {
        let maxPos = try Int64.fetchOne(db, sql: Self.maxPositionSQL, arguments: [playlistID]) ?? -1
        let nextPos = maxPos + 1
        try db.execute(sql: Self.insertEntrySQL,
                       arguments: [playlistID, trackID, nextPos, LibraryStore.nowSeconds()])
        return db.lastInsertedRowID
    }

    /// Insert a track at ordinal `index` (clamped to `[0, count]`). Renormalizes the playlist's
    /// entry positions to dense `0..n` in the one txn. Returns the new entry id.
    @discardableResult
    func insertEntry(playlistID: Int64, trackID: Int64, at index: Int) async throws -> Int64 {
        try await dbWriter.write { db in
            let order = try Int64.fetchAll(db, sql: Self.selectEntryIDsInOrderSQL, arguments: [playlistID])
            let clamped = min(max(index, 0), order.count)
            // Append the new entry (temporary position), then splice it into `order` and renumber.
            let newID = try self.appendEntryLocked(db, playlistID: playlistID, trackID: trackID)
            var newOrder = order
            newOrder.insert(newID, at: clamped)
            try Self.renumberLocked(db, playlistID: playlistID, entryIDsInOrder: newOrder)
            return newID
        }
    }

    func removeEntry(id entryID: Int64) async throws {
        try await dbWriter.write { db in try db.execute(sql: Self.deleteEntryByIDSQL, arguments: [entryID]) }
    }

    /// Remove several entries by id (one DELETE per id — ids bound, never spliced).
    func removeEntries(ids entryIDs: [Int64]) async throws {
        guard !entryIDs.isEmpty else { return }
        try await dbWriter.write { db in
            for id in entryIDs {
                try db.execute(sql: Self.deleteEntryByIDSQL, arguments: [id])
            }
        }
    }

    /// Reorder a playlist by rewriting each listed entry's `position` to its index (dense
    /// `0..n-1`). `entryIDsInOrder` must be the playlist's entries; unknown ids are ignored by
    /// the `AND playlist_id = ?` guard.
    func reorderPlaylist(id playlistID: Int64, entryIDsInOrder ids: [Int64]) async throws {
        try await dbWriter.write { db in
            try Self.renumberLocked(db, playlistID: playlistID, entryIDsInOrder: ids)
        }
    }

    private static func renumberLocked(_ db: Database, playlistID: Int64, entryIDsInOrder ids: [Int64]) throws {
        for (index, entryID) in ids.enumerated() {
            try db.execute(sql: updateEntryPositionSQL, arguments: [Int64(index), entryID, playlistID])
        }
    }

    // MARK: - Loose-file add

    /// Add a (possibly non-library) file to a playlist: create its `tracks` row (folder_id NULL)
    /// if new — reusing the internal `upsertOne` (URL-idempotent + FTS-seeding) — then append an
    /// entry. Atomic in one write txn.
    @discardableResult
    func addLooseFileToPlaylist(_ file: ScannedFile, playlistID: Int64) async throws -> LooseAddResult {
        try await dbWriter.write { db in
            let generation = try Self.nextScanGeneration(db)
            let trackID = try self.upsertOne(db, file, folderID: nil, generation: generation,
                                             dateAdded: LibraryStore.nowSeconds())
            let entryID = try self.appendEntryLocked(db, playlistID: playlistID, trackID: trackID)
            return LooseAddResult(trackID: trackID, entryID: entryID)
        }
    }
}
