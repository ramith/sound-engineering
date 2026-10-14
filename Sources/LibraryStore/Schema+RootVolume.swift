// Schema+RootVolume — the v7 → v8 migration (R1): the drive a library root is bound to.
//
// A root is registered by its PATH, and a path is not a drive: two same-model SSDs ("T7") or two
// "Untitled" sticks mount at the same /Volumes/<name>. A walk of the other drive saw none of the
// root's songs, so its sweep deleted them, with their playlist entries and play history (council
// P5A-02). `folders.volume_uuid` records the drive a root is bound to — the persistent UUID of its
// volume, or `RootIdentity.startupDisk` ("startup-disk") on the startup disk, whose UUID changes with
// the Mac — and a walk of a root whose path is now on another drive is refused (LibraryStore+Roots).
// `(dev, inode)` cannot serve: st_dev is assigned at mount time, and two different volumes' folders
// were seen to share one.
//
// ADDITIVE and data-preserving: one nullable column, NULL for every existing root until a walk that
// confirms its drive binds it (`restampRoot`). No reference to check: the column has no foreign key,
// so the step runs as the migrator registers every step from v7 on (foreign keys off, `makeMigrator`).

import Foundation
import GRDB

public extension Schema {
    /// The v8 statement: the bound drive, nullable (unbound until a walk confirms the root's drive).
    static let createV8Statements: [String] = [
        "ALTER TABLE folders ADD COLUMN volume_uuid TEXT;",
    ]

    /// Migrate v7 → v8: add `folders.volume_uuid`. Additive; every existing row keeps its data.
    static func migrateV7toV8(_ db: Database, appBuild: String?, timestamp: Int64) throws {
        for statement in createV8Statements {
            try db.execute(sql: statement)
        }
        try writeSchemaInfo(db, version: 8, appBuild: appBuild,
                            createdAt: timestamp, migratedAt: timestamp)
    }
}
