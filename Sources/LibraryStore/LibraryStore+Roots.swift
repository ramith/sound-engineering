// LibraryStore+Roots — a root's identity on disk: the directory at its path, and the drive it is
// bound to (S8.4 slice 5b; the drive, R1), GRDB-backed.
//
// A root is registered by PATH, and a path is not a drive: two same-model SSDs ("T7") or two
// "Untitled" sticks mount at the same /Volumes/<name>. So a root is BOUND to the volume it is on, by
// that volume's persistent UUID (`folders.volume_uuid`, schema v8), and every walk begins by
// re-stamping the root from what is at its path now (`restampRoot`, called by `LibraryScanner`):
// a path now on ANOTHER volume is refused, and the root is never walked, swept or re-stamped. An
// unbound root (added before v8, or never walked) is bound by that call.
//
// `(dev, inode)` is not the drive's identity — st_dev is assigned at mount time, and two different
// volumes' folders were seen to share one (council P5A-02). It stays what it was for: `addRoot`'s
// same-directory dedup (QS3), refreshed by the same re-stamp because a remount may reassign st_dev.
//
// A volume that reports no UUID (some network and FAT volumes) leaves its root unbound: it is walked
// as it always was, with no defence against another volume at its path (docs/product/known-issues.md).
// So does the STARTUP volume, by design: no other drive can be at a path on it, and its UUID changes
// with the Mac the library migrates to (`RootReachabilityProbe.identity(of:)`).

import Foundation
import GRDB

/// What is at a root's path right now: the directory's `(dev, inode)` (an `lstat`, as `addRoot`
/// dedups on) and the persistent UUID of the volume it is on — nil when that volume reports none, or
/// is the startup volume. `LibraryScan` reads it (`RootReachabilityProbe.identity(of:)`); the store
/// binds and checks it.
public struct RootIdentity: Sendable, Equatable {
    public let dev: Int64?
    public let inode: Int64?
    public let volumeUUID: String?

    public init(dev: Int64?, inode: Int64?, volumeUUID: String?) {
        self.dev = dev
        self.inode = inode
        self.volumeUUID = volumeUUID
    }
}

public extension LibraryStore {
    // MARK: - SQL

    /// The volume a root is bound to (NULL: unbound), by folder id.
    private static let selectRootVolumeSQL = "SELECT volume_uuid FROM folders WHERE id = ?;"
    /// Re-stamp a root's on-disk `(dev, inode)` identity and its bound volume, by folder id.
    private static let restampRootSQL = "UPDATE folders SET dev = ?, inode = ?, volume_uuid = ? WHERE id = ?;"

    /// Re-stamp root `folderID` from what is at its path now — unless that is another drive.
    ///
    /// Returns false, and changes nothing, when the root is bound to a volume and `identity` is on
    /// another one (or on one that reports no UUID): a different drive at the root's path is never
    /// walked, swept or re-stamped. Otherwise binds an unbound root to `identity`'s volume, refreshes
    /// its `(dev, inode)` (a remount may reassign st_dev; `addRoot`'s dedup stays correct) and returns
    /// true — as it does, writing nothing, when `folderID` is not a row.
    func restampRoot(id folderID: Int64, to identity: RootIdentity) async throws -> Bool {
        try await dbWriter.write { db in
            guard let row = try Row.fetchOne(db, sql: Self.selectRootVolumeSQL, arguments: [folderID]) else {
                return true
            }
            let bound: String? = row[0]
            if let bound, bound != identity.volumeUUID {
                return false
            }
            try db.execute(
                sql: Self.restampRootSQL,
                arguments: [identity.dev, identity.inode, bound ?? identity.volumeUUID, folderID]
            )
            return true
        }
    }
}
