// LibraryStore+Roots — root-row maintenance beyond the core DAO (S8.4 slice 5b), GRDB-backed.
//
// `restampRoot` refreshes a root's on-disk `(dev, inode)` identity — needed when a volume
// remounts with a NEW device number (st_dev is assigned at mount time), so `addRoot`'s
// `(dev, inode)` identity-dedup (QS3) stays correct after a reconnect.

import Foundation
import GRDB

public extension LibraryStore {
    // MARK: - SQL

    /// Re-stamp a root's on-disk `(dev, inode)` identity by folder id.
    private static let restampRootSQL = "UPDATE folders SET dev = ?, inode = ? WHERE id = ?;"

    /// Re-stamp a root's on-disk `(dev, inode)` identity (e.g. after a remount reassigned
    /// `st_dev`). A no-op if `folderID` is not a row; `nil` values clear the columns.
    func restampRoot(id folderID: Int64, dev: Int64?, inode: Int64?) async throws {
        try await dbWriter.write { db in
            try db.execute(
                sql: Self.restampRootSQL,
                arguments: [dev, inode, folderID]
            )
        }
    }
}
