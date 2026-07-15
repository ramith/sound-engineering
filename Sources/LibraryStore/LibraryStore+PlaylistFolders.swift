// LibraryStore+PlaylistFolders — the playlist-FOLDER DAO (S10.3, schema v5), GRDB-backed.
//
// Folders are an adjacency-list tree (`playlist_folders.parent_id` self-ref) holding playlists
// (`playlists.folder_id`) and subfolders. Same single-writer/one-txn discipline as the playlist
// DAO. Delete is "folder owns its contents" (D-folder-delete): a `DELETE` of the folder row
// CASCADEs to subfolders + the playlists it holds + their entries — the DAO snapshots the whole
// subtree BEFORE the delete and can re-insert it, which is what backs the UI's undo. Reparent is
// cycle-guarded inside the write txn (a folder can't become its own ancestor).

import Foundation
import GRDB

// MARK: - Value types

/// A playlist-folder row. `parentID == nil` is a root-level folder.
public struct PlaylistFolder: Sendable, Identifiable, Equatable {
    public let id: Int64
    public let parentID: Int64?
    public let name: String
    public let position: Int
    public let createdAt: Int64

    public init(id: Int64, parentID: Int64?, name: String, position: Int, createdAt: Int64) {
        self.id = id
        self.parentID = parentID
        self.name = name
        self.position = position
        self.createdAt = createdAt
    }
}

extension PlaylistFolder: FetchableRecord {
    /// Decodes a row projected as `id, parent_id, name, position, created_at`.
    public init(row: Row) {
        self.init(id: row[0], parentID: row[1], name: row[2] ?? "",
                  position: Int(row[3] as Int64), createdAt: row[4])
    }
}

/// A captured folder subtree (the folder, its descendant folders, the playlists they hold, and
/// those playlists' entries) — snapshotted before a cascade delete so the UI can UNDO by
/// re-inserting it verbatim (ids preserved). `Sendable` value type; no `Database` escapes.
public struct PlaylistSubtreeSnapshot: Sendable, Equatable {
    /// A playlist's raw restorable columns (the display `Playlist` omits `folder_id`).
    public struct PlaylistRow: Sendable, Equatable {
        public let id: Int64
        public let name: String
        public let isBuiltin: Bool
        public let folderID: Int64?
        public let createdAt: Int64
    }

    public let folders: [PlaylistFolder]
    public let playlists: [PlaylistRow]
    public let entries: [PlaylistEntry]

    public var isEmpty: Bool {
        folders.isEmpty && playlists.isEmpty && entries.isEmpty
    }
}

public extension LibraryStore {
    // MARK: - SQL

    private static let selectFoldersSQL =
        "SELECT id, parent_id, name, position, created_at FROM playlist_folders "
            + "ORDER BY position ASC, name COLLATE NOCASE ASC, id ASC;"
    private static let insertFolderSQL =
        "INSERT INTO playlist_folders(parent_id, name, position, created_at) VALUES (?, ?, ?, ?);"
    private static let maxFolderPositionSQL =
        "SELECT COALESCE(MAX(position), -1) FROM playlist_folders WHERE parent_id IS ?;"
    private static let renameFolderSQL = "UPDATE playlist_folders SET name = ? WHERE id = ?;"
    private static let reparentFolderSQL = "UPDATE playlist_folders SET parent_id = ? WHERE id = ?;"
    private static let deleteFolderSQL = "DELETE FROM playlist_folders WHERE id = ?;"
    private static let folderExistsSQL = "SELECT 1 FROM playlist_folders WHERE id = ?;"
    /// Distinguishes an absent playlist (→ `.notFound`) from the built-in (→ `.builtinImmutable`)
    /// so `setPlaylistFolder` reports the right reason instead of a silent 0-row no-op.
    private static let playlistIsBuiltinSQL = "SELECT is_builtin FROM playlists WHERE id = ?;"
    /// Move a USER playlist into a folder (or to root, `folder_id = NULL`); never the built-in.
    private static let setPlaylistFolderSQL =
        "UPDATE playlists SET folder_id = ? WHERE id = ? AND is_builtin = 0;"
    /// The subtree of folder ids rooted at `?` (inclusive), via a recursive descendant walk.
    private static let subtreeFolderIDsSQL = """
    WITH RECURSIVE sub(id) AS (
        SELECT ?
        UNION
        SELECT pf.id FROM playlist_folders pf JOIN sub ON pf.parent_id = sub.id
    )
    SELECT id FROM sub;
    """

    // MARK: - Reads

    /// Every folder, ordered by (position, name) — the caller builds the tree from `parentID`.
    func folders() async throws -> [PlaylistFolder] {
        try await dbWriter.read { db in try PlaylistFolder.fetchAll(db, sql: Self.selectFoldersSQL) }
    }

    // MARK: - Lifecycle

    /// Create a folder under `parentID` (nil = root), appended at the end of its siblings. Throws
    /// `.notFound` if `parentID` is given but absent. Folder names are NOT required unique
    /// (organizational; only PLAYLIST names are globally unique — D-names). Returns the new id.
    @discardableResult
    func createFolder(name: String, parentID: Int64?) async throws -> Int64 {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw PlaylistMutationError.invalidName(name) }
        return try await dbWriter.write { db in
            if let parentID, try Int64.fetchOne(db, sql: Self.folderExistsSQL, arguments: [parentID]) == nil {
                throw PlaylistMutationError.notFound(id: parentID)
            }
            let maxPos = try Int64.fetchOne(db, sql: Self.maxFolderPositionSQL, arguments: [parentID]) ?? -1
            try db.execute(sql: Self.insertFolderSQL,
                           arguments: [parentID, trimmed, maxPos + 1, LibraryStore.nowSeconds()])
            return db.lastInsertedRowID
        }
    }

    /// Rename a folder (empty/whitespace rejected). Throws `.notFound` for a missing id.
    func renameFolder(id: Int64, to name: String) async throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw PlaylistMutationError.invalidName(name) }
        try await dbWriter.write { db in
            guard try Int64.fetchOne(db, sql: Self.folderExistsSQL, arguments: [id]) != nil else {
                throw PlaylistMutationError.notFound(id: id)
            }
            try db.execute(sql: Self.renameFolderSQL, arguments: [trimmed, id])
        }
    }

    /// Move a playlist into `folderID` (nil = root). Playlist-scoped, never the built-in "current".
    /// Throws `.notFound` for an absent playlist and `.builtinImmutable` for the built-in (matching
    /// the sibling DAO idiom — not a silent 0-row no-op); `.notFound` for a missing target folder.
    func setPlaylistFolder(playlistID: Int64, folderID: Int64?) async throws {
        try await dbWriter.write { db in
            guard let isBuiltin = try Int64.fetchOne(db, sql: Self.playlistIsBuiltinSQL, arguments: [playlistID]) else {
                throw PlaylistMutationError.notFound(id: playlistID)
            }
            guard isBuiltin == 0 else { throw PlaylistMutationError.builtinImmutable(id: playlistID) }
            if let folderID, try Int64.fetchOne(db, sql: Self.folderExistsSQL, arguments: [folderID]) == nil {
                throw PlaylistMutationError.notFound(id: folderID)
            }
            try db.execute(sql: Self.setPlaylistFolderSQL, arguments: [folderID, playlistID])
        }
    }

    /// Reparent `id` under `newParentID` (nil = root). CYCLE-GUARDED inside the write txn: rejects
    /// making a folder its own ancestor (target == the node, or target is in the node's subtree),
    /// which would orphan a cycle. Throws `.notFound` for a missing node/parent, `.wouldCreateCycle`
    /// for a cycle (so the UI can distinguish a bad move from a bad name).
    func reparentFolder(id: Int64, newParentID: Int64?) async throws {
        try await dbWriter.write { db in
            guard try Int64.fetchOne(db, sql: Self.folderExistsSQL, arguments: [id]) != nil else {
                throw PlaylistMutationError.notFound(id: id)
            }
            if let newParentID {
                guard try Int64.fetchOne(db, sql: Self.folderExistsSQL, arguments: [newParentID]) != nil else {
                    throw PlaylistMutationError.notFound(id: newParentID)
                }
                // Cycle check: the new parent must NOT be inside the subtree rooted at `id`.
                let subtree = try Set(Int64.fetchAll(db, sql: Self.subtreeFolderIDsSQL, arguments: [id]))
                guard !subtree.contains(newParentID) else {
                    throw PlaylistMutationError.wouldCreateCycle(id: id, newParentID: newParentID)
                }
            }
            try db.execute(sql: Self.reparentFolderSQL, arguments: [newParentID, id])
        }
    }

    // MARK: - Delete (cascade) + undo snapshot

    /// Delete a folder and everything it owns. Snapshots the whole subtree (the folder + descendant
    /// folders + the playlists they hold + those playlists' entries) BEFORE the `DELETE` (whose
    /// `ON DELETE CASCADE` removes it all in one txn), and RETURNS the snapshot so the UI can undo
    /// via `restoreFolderSubtree`. Throws `.notFound` for a missing id.
    @discardableResult
    func deleteFolder(id: Int64) async throws -> PlaylistSubtreeSnapshot {
        try await dbWriter.write { db in
            guard try Int64.fetchOne(db, sql: Self.folderExistsSQL, arguments: [id]) != nil else {
                throw PlaylistMutationError.notFound(id: id)
            }
            let snapshot = try Self.snapshotSubtree(db, rootFolderID: id)
            try db.execute(sql: Self.deleteFolderSQL, arguments: [id]) // CASCADE does the rest
            return snapshot
        }
    }

    /// Capture the subtree rooted at `rootFolderID` as value structs (folders top-down so a restore
    /// can insert parents before children even without deferred FKs; playlists + their entries).
    private static func snapshotSubtree(_ db: Database, rootFolderID: Int64) throws -> PlaylistSubtreeSnapshot {
        let folderIDs = try Int64.fetchAll(db, sql: subtreeFolderIDsSQL, arguments: [rootFolderID])
        let idList = folderIDs.map(String.init).joined(separator: ",") // ids are DB-derived Int64s, safe
        // Folders, shallow-first (parents before children) so re-insert satisfies the self-FK.
        let folders = try PlaylistFolder.fetchAll(
            db, sql: "SELECT id, parent_id, name, position, created_at FROM playlist_folders "
                + "WHERE id IN (\(idList)) ORDER BY (parent_id IS NOT NULL), id;"
        )
        let playlists = try PlaylistSubtreeSnapshot.PlaylistRow.rows(
            db, sql: "SELECT id, name, is_builtin, folder_id, created_at FROM playlists "
                + "WHERE folder_id IN (\(idList));"
        )
        let playlistIDList = playlists.map { String($0.id) }.joined(separator: ",")
        let entries: [PlaylistEntry] = playlists.isEmpty ? [] : try PlaylistEntry.fetchAll(
            db, sql: "SELECT id, playlist_id, track_id, position, added_at FROM playlist_entries "
                + "WHERE playlist_id IN (\(playlistIDList)) ORDER BY playlist_id, position;"
        )
        return PlaylistSubtreeSnapshot(folders: folders, playlists: playlists, entries: entries)
    }

    /// Re-insert a previously-deleted subtree (UNDO), preserving every id. Runs with deferred FKs so
    /// insertion order within the txn is unconstrained; the graph is internally consistent because
    /// it was captured as a whole. A no-op for an empty snapshot.
    ///
    /// Best-effort for the IMMEDIATE-undo model the UI uses: if the world changed between the delete
    /// and the undo (a freed rowid reissued → PK collision; a re-created playlist reusing the deleted
    /// name → UNIQUE violation; a referenced track/parent deleted → deferred-FK failure at commit),
    /// the single txn ROLLS BACK and this THROWS — it never leaves partial/corrupt state. Callers
    /// should surface the throw, not swallow it.
    func restoreFolderSubtree(_ snapshot: PlaylistSubtreeSnapshot) async throws {
        guard !snapshot.isEmpty else { return }
        try await dbWriter.write { db in
            try db.execute(sql: "PRAGMA defer_foreign_keys = ON;")
            for folder in snapshot.folders {
                try db.execute(
                    sql: "INSERT INTO playlist_folders(id, parent_id, name, position, created_at) "
                        + "VALUES (?, ?, ?, ?, ?);",
                    arguments: [folder.id, folder.parentID, folder.name, folder.position, folder.createdAt]
                )
            }
            for playlist in snapshot.playlists {
                try db.execute(
                    sql: "INSERT INTO playlists(id, name, is_builtin, folder_id, created_at) "
                        + "VALUES (?, ?, ?, ?, ?);",
                    arguments: [playlist.id, playlist.name, playlist.isBuiltin ? 1 : 0,
                                playlist.folderID, playlist.createdAt]
                )
            }
            for entry in snapshot.entries {
                try db.execute(
                    sql: "INSERT INTO playlist_entries(id, playlist_id, track_id, position, added_at) "
                        + "VALUES (?, ?, ?, ?, ?);",
                    arguments: [entry.id, entry.playlistID, entry.trackID, entry.position, entry.addedAt]
                )
            }
        }
    }
}

private extension PlaylistSubtreeSnapshot.PlaylistRow {
    /// Fetch raw playlist restore-rows for the snapshot.
    static func rows(_ db: Database, sql: String) throws -> [Self] {
        try Row.fetchAll(db, sql: sql).map {
            Self(id: $0[0], name: $0[1] ?? "", isBuiltin: ($0[2] as Int64) != 0,
                 folderID: $0[3], createdAt: $0[4])
        }
    }
}
