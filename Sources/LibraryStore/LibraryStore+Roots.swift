// LibraryStore+Roots — a root's identity on disk: the directory at its path, and the drive it is
// bound to (S8.4 slice 5b; the drive, R1), GRDB-backed.
//
// A root is registered by PATH, and a path is not a drive: two same-model SSDs ("T7") or two
// "Untitled" sticks mount at the same /Volumes/<name>. So a root is BOUND to the drive it is on
// (`folders.volume_uuid`, schema v8): the volume's persistent UUID, or — on the startup disk —
// `RootIdentity.startupDisk`, because the startup disk's UUID changes with the Mac (Migration
// Assistant, an erase-and-restore) while the library on it comes along. `LibraryScanner` reads the
// binding before a walk (`boundVolume`): a path now on ANOTHER drive is refused, and the root is never
// walked, swept or re-stamped. It binds an unbound root only AFTER a walk that confirmed the drive
// (`restampRoot`) — never to whatever happens to be at the path when the walk starts.
//
// An UNBOUND root — added before v8 and not yet walked since, or on a volume that reports no UUID
// (some network volumes) — has no drive to check, so the scanner first looks for its songs where the
// library has them (`trackURLs`): a folder holding none of them (another drive with the same name, a
// stale folder) is not walked, and so cannot bind the root or leave rows that would vouch for it later.
//
// `(dev, inode)` is not the drive's identity — st_dev is assigned at mount time, and two different
// volumes' folders were seen to share one (council P5A-02). It stays what it was for: `addRoot`'s
// same-directory dedup (QS3), refreshed by the same re-stamp because a remount may reassign st_dev.

import Foundation
import GRDB

/// What is at a root's path right now: the directory's `(dev, inode)` (an `lstat`, as `addRoot`
/// dedups on) and the drive it is on, as a root binds to it. `LibraryScan` reads it
/// (`RootReachabilityProbe.identity(of:)`); the store binds and checks it.
public struct RootIdentity: Sendable, Equatable {
    /// The `volume` of anything on the startup disk — not a UUID: the startup disk is bound as itself,
    /// whichever Mac it is.
    public static let startupDisk = "startup-disk"

    public let dev: Int64?
    public let inode: Int64?
    /// The drive: its volume's persistent UUID, `startupDisk`, or nil when the volume reports no UUID.
    public let volume: String?

    public init(dev: Int64?, inode: Int64?, volume: String?) {
        self.dev = dev
        self.inode = inode
        self.volume = volume
    }
}

public extension LibraryStore {
    // MARK: - SQL

    /// The drive a root is bound to (NULL: unbound), by folder id.
    private static let selectRootVolumeSQL = "SELECT volume_uuid FROM folders WHERE id = ?;"
    /// Re-stamp a root's on-disk `(dev, inode)` identity and its bound drive, by folder id.
    private static let restampRootSQL = "UPDATE folders SET dev = ?, inode = ?, volume_uuid = ? WHERE id = ?;"
    /// A page of a folder's song urls, in id order after an id.
    private static let selectTrackURLPageSQL =
        "SELECT id, url FROM tracks WHERE folder_id = ? AND id > ? ORDER BY id LIMIT ?;"

    /// The drive root `folderID` is bound to — nil while it is unbound (or is not a row).
    func boundVolume(ofRoot folderID: Int64) async throws -> String? {
        try await dbWriter.read { db in try Self.boundVolume(db, ofRoot: folderID) ?? nil }
    }

    /// Re-stamp root `folderID` from what is at its path, after a walk that confirmed it is the root's
    /// own drive (`LibraryScanner.scan`).
    ///
    /// Binds an unbound root to `identity`'s drive (one that reports no UUID leaves it unbound),
    /// refreshes its `(dev, inode)` (a remount may reassign st_dev; `addRoot`'s dedup stays correct) and
    /// returns true — as it does, writing nothing, when `folderID` is not a row. Returns false, and
    /// changes nothing, when the root is bound to another drive: a different drive is never re-stamped.
    func restampRoot(id folderID: Int64, to identity: RootIdentity) async throws -> Bool {
        try await dbWriter.write { db in
            guard let bound = try Self.boundVolume(db, ofRoot: folderID) else { return true }
            if let bound, bound != identity.volume {
                return false
            }
            try db.execute(
                sql: Self.restampRootSQL,
                arguments: [identity.dev, identity.inode, bound ?? identity.volume, folderID]
            )
            return true
        }
    }

    /// A page of `folderID`'s song urls, in id order after `afterID` (0 to start) — where the library
    /// has its songs, for the scanner to look for them on disk before walking an unbound root.
    func trackURLs(inFolder folderID: Int64, afterID: Int64, limit: Int) async throws -> [(id: Int64, url: URL)] {
        try await dbWriter.read { db in
            try Row.fetchAll(db, sql: Self.selectTrackURLPageSQL, arguments: [folderID, afterID, limit]).map { row in
                (id: row[0], url: URL(fileURLWithPath: row[1]))
            }
        }
    }

    /// The drive root `folderID` is bound to: nil when it is not a row, `.some(nil)` while unbound.
    private static func boundVolume(_ db: Database, ofRoot folderID: Int64) throws -> String?? {
        try Row.fetchOne(db, sql: selectRootVolumeSQL, arguments: [folderID]).map { row in row[0] }
    }
}
