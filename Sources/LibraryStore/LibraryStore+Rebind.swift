// LibraryStore+Rebind — "Use this drive": a paused music folder re-rooted on the drive that now holds its
// songs (R1.1-B, US-R1F-03 LIB-VOL-1; seam S4), GRDB-backed.
//
// A folder is paused when its drive is gone, another drive is at its path, or its drive cannot be confirmed
// (`SweepRefusal`). Its songs are where its drive was; the user points the folder at the folder on the new
// drive (a new name — "/Volumes/T7 1" — or the same path on a new drive). The S8.4 move-match cannot carry
// them over: its signature includes (dev, inode), and both differ on another drive. So the re-root goes by
// each song's path UNDER its folder (+ its size) — the scanner looks on the new drive (LibraryScan
// `RootRebinder`, the filesystem side; the store never touches the disk) and hands this the songs it found.
//
// The founder's rule (2026-10-25): silently — no preview; the folder's songs FOUND on the new drive keep
// their ids, plays, loves, ratings, frecency and playlist membership; songs NOT found are removed, with
// their history; and when NONE is found the rebind is refused and nothing is written — it is the wrong
// drive (the R1 "never wipe on an empty walk" floor). Also refused: a new location that is another music
// folder, or inside one, or holds one; a folder whose songs changed since they were looked for.
//
// ONE write transaction: a kill mid-rebind leaves the before state or the after state. In it: the folder
// row (and any folder row below it) moves to the new path, bound to the new drive; every found song's url
// becomes the new path + its path under the folder (in two steps, so no song's new url collides with
// another's old one); a song the library already holds LOOSE at a found song's new url (a file from the new
// drive added to a playlist while the folder was paused) is merged into the found song — its playlist
// entries and play counts carried over — rather than refusing the rebind; the songs not found are deleted
// with their search rows (their playlist entries and history go with them, by the foreign keys); and the
// albums regroup — an untagged album is keyed by its folder's path (`AlbumGrouping`), so it re-keys to the
// new path (album rows hold no user data). The walk after the rebind is an ordinary one, on the folder's
// confirmed drive: every song it keeps is on the new drive, so its sweep can only reap a file deleted since.

import Foundation
import GRDB

/// Why a rebind wrote nothing.
public enum RebindRefusal: Error, Sendable, Equatable {
    /// None of the folder's songs is on the new drive: it is the wrong drive (the R1 floor).
    case noSongsFound
    /// The new location is the music folder `id`, or inside it, or holds it.
    case overlapsFolder(id: Int64)
    /// The folder is no longer a music folder (it was removed).
    case notAFolder
    /// The folder's songs changed since the new drive was looked at (a walk added one): look again.
    case songsChanged
}

/// One of a music folder's songs, as a rebind looks for it on the new drive.
public struct FolderSong: Sendable, Equatable {
    public let id: Int64
    /// Its path under the music folder: its folder's relative path and its file name ("Album/01 Song.flac").
    public let relativePath: String
    /// Its size, as the library last saw it: a copy of another size is another file (a re-tagged one).
    public let fileSize: Int64

    public init(id: Int64, relativePath: String, fileSize: Int64) {
        self.id = id
        self.relativePath = relativePath
        self.fileSize = fileSize
    }
}

/// What a rebind did, or why it did nothing.
public enum RebindOutcome: Sendable, Equatable {
    /// Re-rooted: `kept` songs found on the new drive kept their ids and history; `removed` songs not
    /// found were removed with theirs.
    case rebound(kept: Int, removed: Int)
    /// Nothing was written.
    case refused(RebindRefusal)
}

public extension LibraryStore {
    // MARK: - SQL

    /// A folder row's path, by id.
    private static let selectFolderPathSQL = "SELECT path FROM folders WHERE id = ?;"
    /// Every folder row but `id`: the others a new location must not overlap.
    private static let selectOtherFoldersSQL = "SELECT id, path, dev, inode FROM folders WHERE id <> ?;"
    /// A page of a folder's songs — id, url, size — in id order after an id.
    private static let selectSongPageSQL =
        "SELECT id, url, relative_path, file_size FROM tracks WHERE folder_id = ? AND id > ? "
            + "ORDER BY id LIMIT ?;"
    /// Every song of a folder: id and url.
    private static let selectFolderSongsSQL = "SELECT id, url, relative_path FROM tracks WHERE folder_id = ?;"
    /// Move a song to a url (its relative path under the folder is unchanged).
    private static let setTrackURLSQL = "UPDATE tracks SET url = ? WHERE id = ?;"
    /// The row holding a url.
    private static let selectTrackIDByURLSQL = "SELECT id FROM tracks WHERE url = ?;"
    /// Move a folder row to a path, bound to a drive.
    private static let rebindFolderSQL =
        "UPDATE folders SET path = ?, dev = ?, inode = ?, volume_uuid = ? WHERE id = ?;"
    /// Move a folder row below the music folder to a path.
    private static let moveFolderPathSQL = "UPDATE folders SET path = ? WHERE id = ?;"
    /// Point a loose duplicate's playlist entries at the song it duplicates.
    private static let repointEntriesSQL = "UPDATE playlist_entries SET track_id = ? WHERE track_id = ?;"
    /// Carry a loose duplicate's history onto the song it duplicates.
    private static let mergeHistorySQL = """
    UPDATE tracks SET
        play_count = play_count + (SELECT play_count FROM tracks WHERE id = :loose),
        loved = MAX(loved, (SELECT loved FROM tracks WHERE id = :loose)),
        rating = COALESCE(rating, (SELECT rating FROM tracks WHERE id = :loose)),
        last_played = NULLIF(MAX(COALESCE(last_played, 0),
                                 COALESCE((SELECT last_played FROM tracks WHERE id = :loose), 0)), 0)
    WHERE id = :kept;
    """

    // MARK: - Reads

    /// A page of `folderID`'s songs, in id order after `afterID` (0 to start): each song's path under the
    /// folder ("Album/01 Song.flac" — its folder's relative path and its file name) and its size — what a
    /// rebind looks for on the new drive (`RootRebinder`).
    func relativePaths(inFolder folderID: Int64, afterID: Int64, limit: Int) async throws -> [FolderSong] {
        try await dbWriter.read { db in
            guard let root = try String.fetchOne(db, sql: Self.selectFolderPathSQL, arguments: [folderID]) else {
                return []
            }
            return try Row.fetchAll(db, sql: Self.selectSongPageSQL, arguments: [folderID, afterID, limit]).map { row in
                FolderSong(id: row[0], relativePath: Self.pathUnderFolder(url: row[1], relativeFolder: row[2],
                                                                          root: root),
                           fileSize: row[3])
            }
        }
    }

    // MARK: - Rebind

    /// Re-root `folderID` at `newRoot`, on the drive `identity` names, keeping the songs `found` there and
    /// removing the rest — in ONE transaction (see the file header). `lookedAt` is every song of the folder
    /// the caller looked for: a folder whose songs differ now is refused (`.songsChanged`), as is one with
    /// none of its songs found (`.noSongsFound`) or a new location another music folder overlaps.
    func rebindRoot(_ folderID: Int64, to newRoot: URL, identity: RootIdentity,
                    found: Set<Int64>, lookedAt: Set<Int64>) async throws -> RebindOutcome {
        let newPath = PathNormalizer.normalizedString(for: newRoot)
        return try await dbWriter.write { db in
            guard let oldPath = try String.fetchOne(db, sql: Self.selectFolderPathSQL, arguments: [folderID]) else {
                return .refused(.notAFolder)
            }
            if let other = try Self.folderOverlapping(db, newPath: newPath, identity: identity,
                                                      excluding: folderID, oldPath: oldPath) {
                return .refused(.overlapsFolder(id: other))
            }
            let songs = try Row.fetchAll(db, sql: Self.selectFolderSongsSQL, arguments: [folderID])
            guard Set(songs.map { $0[0] as Int64 }) == lookedAt else { return .refused(.songsChanged) }
            let kept = songs.filter { found.contains($0[0]) }
            guard !kept.isEmpty else { return .refused(.noSongsFound) }
            let removed = songs.map { $0[0] as Int64 }.filter { !found.contains($0) }
            if newPath != oldPath {
                try self.moveSongs(db, kept, from: oldPath, to: newPath)
                try Self.moveFoldersBelow(db, from: oldPath, to: newPath, excluding: folderID)
            }
            try db.execute(sql: Self.rebindFolderSQL,
                           arguments: [newPath, identity.dev, identity.inode, identity.volume, folderID])
            try self.deleteTrackRows(db, ids: removed)
            _ = try self.refreshDerivedFacetsLocked(db)
            return .rebound(kept: kept.count, removed: removed.count)
        }
    }

    // MARK: - Parts of the rebind (inside its transaction)

    /// Move the kept songs' urls from under `oldPath` to under `newPath`: first each to a url no file can
    /// have, then each to its new url — so a new url never meets another kept song's old one. A row the
    /// library holds LOOSE at a new url is merged into the kept song first (`mergeLooseDuplicate`).
    private func moveSongs(_ db: Database, _ kept: [Row], from oldPath: String, to newPath: String) throws {
        let moves = kept.map { row -> (id: Int64, url: String) in
            let underFolder = Self.pathUnderFolder(url: row[1], relativeFolder: row[2], root: oldPath)
            return (row[0], PathNormalizer.directoryPrefix(newPath) + underFolder)
        }
        let keptIDs = Set(moves.map(\.id))
        for move in moves {
            try db.execute(sql: Self.setTrackURLSQL, arguments: ["rebind:\(move.id)", move.id])
        }
        for move in moves {
            if let occupant = try Int64.fetchOne(db, sql: Self.selectTrackIDByURLSQL, arguments: [move.url]),
               !keptIDs.contains(occupant) {
                try mergeLooseDuplicate(db, occupant, into: move.id)
            }
            try db.execute(sql: Self.setTrackURLSQL, arguments: [move.url, move.id])
        }
    }

    /// Merge the row `loose` — the same file as `kept`, held outside the folder — into `kept`: its playlist
    /// entries point at `kept`, its plays add to `kept`'s, a love or a rating carries over, the later last
    /// play stands; then the duplicate row goes.
    private func mergeLooseDuplicate(_ db: Database, _ loose: Int64, into kept: Int64) throws {
        try db.execute(sql: Self.repointEntriesSQL, arguments: [kept, loose])
        try db.execute(sql: Self.mergeHistorySQL, arguments: ["loose": loose, "kept": kept])
        try deleteTrackRows(db, ids: [loose])
    }

    /// Move every folder row strictly below `oldPath` (but `excluding`, the music folder itself) to the
    /// same place below `newPath`.
    private static func moveFoldersBelow(_ db: Database, from oldPath: String, to newPath: String,
                                         excluding folderID: Int64) throws {
        for row in try Row.fetchAll(db, sql: selectOtherFoldersSQL, arguments: [folderID]) {
            let path: String = row[1]
            guard PathNormalizer.isComponentBoundaryDescendant(path, of: oldPath) else { continue }
            let below = path.dropFirst(PathNormalizer.directoryPrefix(oldPath).count)
            try db.execute(sql: moveFolderPathSQL,
                           arguments: [PathNormalizer.directoryPrefix(newPath) + below, row[0] as Int64])
        }
    }

    /// The music folder a new location at `newPath` would overlap: one at the same path or the same
    /// directory (its `(dev, inode)`), one it is inside, or one inside it — never `excluding` itself or a
    /// folder row below its old path (those move with it).
    private static func folderOverlapping(_ db: Database, newPath: String, identity: RootIdentity,
                                          excluding folderID: Int64, oldPath: String) throws -> Int64? {
        for row in try Row.fetchAll(db, sql: selectOtherFoldersSQL, arguments: [folderID]) {
            let path: String = row[1]
            if PathNormalizer.isComponentBoundaryDescendant(path, of: oldPath) {
                continue
            }
            let sameDirectory = identity.dev != nil && identity.inode != nil
                && row[2] as Int64? == identity.dev && row[3] as Int64? == identity.inode
            if path == newPath || sameDirectory
                || PathNormalizer.isComponentBoundaryDescendant(newPath, of: path)
                || PathNormalizer.isComponentBoundaryDescendant(path, of: newPath) {
                return row[0]
            }
        }
        return nil
    }

    /// A song's path under its music folder at `root`: the part of its url below the folder, or — for a url
    /// that is not below it — its stored relative folder and its file name.
    private static func pathUnderFolder(url: String, relativeFolder: String, root: String) -> String {
        if PathNormalizer.isComponentBoundaryDescendant(url, of: root) {
            return String(url.dropFirst(PathNormalizer.directoryPrefix(root).count))
        }
        return relativeFolder + (url as NSString).lastPathComponent
    }
}
