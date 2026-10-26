// LibraryStore+Rebind — "Use this drive": a paused music folder re-rooted on the drive that now holds its
// songs (R1.1-B, US-R1F-03 LIB-VOL-1; seam S4), GRDB-backed.
//
// A folder is paused when its drive is gone, another drive is at its path, or its drive cannot be confirmed
// (`SweepRefusal`). Its songs are where its drive was; the user points the folder at the folder on the new
// drive (a new name — "/Volumes/T7 1" — or the same path on a new drive). The S8.4 move-match cannot carry
// them over: its signature includes (dev, inode), and both differ on another drive. So the re-root goes by
// each song's path UNDER its folder (+ its size) — the scanner looks on the new drive (LibraryScan
// `RootRebinder`, the filesystem side; the store never touches the disk) and hands this each song it found,
// as the walk would read that file there (`ScannedFile`): where the drive spells it, and its own
// (dev, inode).
//
// The founder's rule (2026-10-25): silently — no preview; the folder's songs FOUND on the new drive keep
// their ids, plays, loves, ratings, frecency and playlist membership; songs NOT found are removed, with
// their history; and when NONE is found the rebind is refused and nothing is written — it is the wrong
// drive (the R1 "never wipe on an empty walk" floor). Also refused: a new location that is another music
// folder, or inside one, or holds one; a folder whose songs changed since they were looked for.
//
// ONE write transaction: a kill mid-rebind leaves the before state or the after state. In it, in order:
//   1. the songs not found are deleted with their search rows (their playlist entries and history go with
//      them, by the foreign keys) — FIRST, so none of them can be taken for a file at a kept song's new url;
//   2. every found song takes the file the drive holds: its url and its path under the folder AS THE DRIVE
//      SPELLS THEM (a case-only or NFD difference — the url the walk after will see), and the file's own
//      (dev, inode) — the move-signature, so a later rename or move on the new drive is followed by the
//      S8.4 move-match as anywhere else (break-it BI-P04 / BI-P07). Size and date stay the walk's to judge.
//      Urls move in two steps, so no song's new url collides with another's old one. A row the library
//      holds LOOSE (in no music folder) at a found song's new url — a file from the new drive added to a
//      playlist while the folder was paused — is merged into the found song, its playlist entries and plays
//      carried over; a row of another music folder there refuses the rebind (nothing written);
//   3. the folder row moves to the new path, bound to the new drive;
//   4. the albums regroup — an untagged album is keyed by its folder's path (`AlbumGrouping`), so it re-keys
//      to the new path (album rows hold no user data).
// The walk after the rebind is an ordinary one, on the folder's confirmed drive: every song it keeps is on
// the new drive at the url the walk reads, so its sweep can only reap a file deleted since.

import Foundation
import GRDB

/// Why a rebind wrote nothing.
public enum RebindRefusal: Error, Sendable, Equatable {
    /// None of the folder's songs is on the new drive: it is the wrong drive (the R1 floor).
    case noSongsFound
    /// The chosen folder could not be read — it is not there, or the app may not look inside it — so
    /// nothing is known about the songs on it.
    case unreadableFolder
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
    private static let selectOtherFoldersSQL = "SELECT id, path, dev, inode, volume_uuid FROM folders WHERE id <> ?;"
    /// A page of a folder's songs — id, url, size — in id order after an id.
    private static let selectSongPageSQL =
        "SELECT id, url, relative_path, file_size FROM tracks WHERE folder_id = ? AND id > ? "
            + "ORDER BY id LIMIT ?;"
    /// Every song of a folder: id and name.
    private static let selectFolderSongsSQL = "SELECT id, name FROM tracks WHERE folder_id = ?;"
    /// Park a song at a url no file can have (the first of a url move's two steps).
    private static let parkTrackURLSQL = "UPDATE tracks SET url = ? WHERE id = ?;"
    /// A found song takes the file the new drive holds: its url, path, name and move-signature.
    private static let takeFoundFileSQL =
        "UPDATE tracks SET url = ?, relative_path = ?, name = ?, format = ?, dev = ?, inode = ? WHERE id = ?;"
    /// The row holding a url, and its music folder.
    private static let selectTrackByURLSQL = "SELECT id, folder_id FROM tracks WHERE url = ?;"
    /// Move a folder row to a path, bound to a drive.
    private static let rebindFolderSQL =
        "UPDATE folders SET path = ?, dev = ?, inode = ?, volume_uuid = ? WHERE id = ?;"
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

    /// Re-root `folderID` at `newRoot`, on the drive `identity` names, keeping the songs `found` there — each
    /// with the file the walk would read for it on the new drive — and removing the rest, in ONE transaction
    /// (see the file header). `lookedAt` is every song of the folder the caller looked for: a folder whose
    /// songs differ now is refused (`.songsChanged`), as is one with none of its songs found
    /// (`.noSongsFound`) or a new location another music folder overlaps.
    func rebindRoot(_ folderID: Int64, to newRoot: URL, identity: RootIdentity,
                    found: [Int64: ScannedFile], lookedAt: Set<Int64>) async throws -> RebindOutcome {
        let newPath = PathNormalizer.normalizedString(for: newRoot)
        do {
            return try await dbWriter.write { db in
                guard try String.fetchOne(db, sql: Self.selectFolderPathSQL, arguments: [folderID]) != nil else {
                    return .refused(.notAFolder)
                }
                if let other = try Self.folderOverlapping(db, newPath: newPath, identity: identity,
                                                          excluding: folderID) {
                    return .refused(.overlapsFolder(id: other))
                }
                let songs = try Row.fetchAll(db, sql: Self.selectFolderSongsSQL, arguments: [folderID])
                guard Set(songs.map { $0[0] as Int64 }) == lookedAt else { return .refused(.songsChanged) }
                let kept = songs.compactMap { row -> FoundFile? in
                    found[row[0]].map { FoundFile(id: row[0], storedName: row[1], file: $0) }
                }
                guard !kept.isEmpty else { return .refused(.noSongsFound) }
                let removed = songs.map { $0[0] as Int64 }.filter { found[$0] == nil }
                try self.deleteTrackRows(db, ids: removed)
                try self.takeFoundFiles(db, kept, under: newPath)
                try db.execute(sql: Self.rebindFolderSQL,
                               arguments: [newPath, identity.dev, identity.inode, identity.volume, folderID])
                _ = try self.refreshDerivedFacetsLocked(db)
                return .rebound(kept: kept.count, removed: removed.count)
            }
        } catch let abandoned as RebindAbandoned {
            return .refused(abandoned.refusal) // the transaction rolled back: nothing written
        }
    }

    // MARK: - Parts of the rebind (inside its transaction)

    /// A found song: its id, its name as stored, and the file the new drive holds for it.
    private struct FoundFile {
        let id: Int64
        let storedName: String
        let file: ScannedFile
    }

    /// Thrown inside the rebind's transaction to roll it back and refuse: something only the writes in
    /// progress could find (a row of another music folder at a found song's new url).
    private struct RebindAbandoned: Error {
        let refusal: RebindRefusal
    }

    /// Every kept song takes the file the new drive holds for it (see the file header, step 2): first each
    /// parks at a url no file can have, then each takes its new url, path, name and move-signature — so a new
    /// url never meets another kept song's old one. A LOOSE row at a new url is merged into the kept song
    /// first (`mergeLooseDuplicate`); a row of a music folder there abandons the rebind.
    private func takeFoundFiles(_ db: Database, _ kept: [FoundFile], under newPath: String) throws {
        for song in kept {
            try db.execute(sql: Self.parkTrackURLSQL, arguments: ["rebind:\(song.id)", song.id])
        }
        for song in kept {
            let url = PathNormalizer.normalizedString(for: song.file.url)
            guard PathNormalizer.isComponentBoundaryDescendant(url, of: newPath) else {
                throw SQLiteError.internalError(message: "rebind: a found file is not under the new folder: \(url)")
            }
            if let occupant = try Row.fetchOne(db, sql: Self.selectTrackByURLSQL, arguments: [url]) {
                if let otherFolder = occupant[1] as Int64? {
                    throw RebindAbandoned(refusal: .overlapsFolder(id: otherFolder))
                }
                try mergeLooseDuplicate(db, occupant[0], into: song.id)
            }
            let file = song.file
            try db.execute(sql: Self.takeFoundFileSQL,
                           arguments: [url, file.relativePath, file.name, file.format, file.dev, file.inode, song.id])
            if file.name != song.storedName {
                try syncSearchRow(db, trackID: song.id) // an untagged song's title is its file name
            }
        }
    }

    /// Merge the row `loose` — the same file as `kept`, held in no music folder — into `kept`: its playlist
    /// entries point at `kept`, its plays add to `kept`'s, a love or a rating carries over, the later last
    /// play stands; then the duplicate row goes.
    private func mergeLooseDuplicate(_ db: Database, _ loose: Int64, into kept: Int64) throws {
        try db.execute(sql: Self.repointEntriesSQL, arguments: [kept, loose])
        try db.execute(sql: Self.mergeHistorySQL, arguments: ["loose": loose, "kept": kept])
        try deleteTrackRows(db, ids: [loose])
    }

    /// The music folder a new location at `newPath` would overlap: one at the same path, one it is inside,
    /// one inside it — or the same directory, by its `(dev, inode)`, on the SAME drive or one not yet bound
    /// to a drive, as `addRoot` dedups (st_dev numbers are handed out again after an unmount, so a gone
    /// drive's stored pair may name a directory on another drive now: break-it BI-P06). Never `excluding`
    /// itself. A folder row below the folder's OLD path is another folder like any other: it does not move
    /// with it, and refuses a new location that overlaps it.
    private static func folderOverlapping(_ db: Database, newPath: String, identity: RootIdentity,
                                          excluding folderID: Int64) throws -> Int64? {
        for row in try Row.fetchAll(db, sql: selectOtherFoldersSQL, arguments: [folderID]) {
            let path: String = row[1]
            let volume: String? = row[4]
            let sameDirectory = identity.dev != nil && identity.inode != nil
                && (volume == nil || volume == identity.volume)
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
