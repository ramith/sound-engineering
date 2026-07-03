// LibraryStore+Roots — root-row maintenance beyond the core DAO (S8.4 slice 5b).
//
// `restampRoot` refreshes a root's on-disk `(dev, inode)` identity — needed when a volume
// remounts with a NEW device number (st_dev is assigned at mount time), so `addRoot`'s
// `(dev, inode)` identity-dedup (QS3) stays correct after a reconnect. Kept out of
// LibraryStore+DAO purely for that file's length budget; cohesive on its own.

import Foundation

public extension LibraryStore {
    /// Re-stamp a root's on-disk `(dev, inode)` identity (e.g. after a remount reassigned
    /// `st_dev`). A no-op if `folderID` is not a row; `nil` values clear the columns.
    func restampRoot(id folderID: Int64, dev: Int64?, inode: Int64?) throws {
        let statement = try connection.prepare("UPDATE folders SET dev = ?, inode = ? WHERE id = ?;")
        defer { statement.finalize() }
        try statement.bind(dev, at: 1)
        try statement.bind(inode, at: 2)
        try statement.bind(folderID, at: 3)
        _ = try statement.step()
    }
}
