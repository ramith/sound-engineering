// LibraryStore+DerivedData — the derived-data version and its one-time tag re-read (S10.8 C2).
//
// The store holds a DERIVED cache (what the tags say: titles, artists, albums, genres, art) next
// to USER data (playlists, play counts, loved, ratings, frecency). When the code that derives the
// cache changes in a way existing rows can't express — C2 starts reading the compilation flag,
// which no stored row carries — the cache must be re-derived from the files. That is a VERSION
// BUMP, not a migration: `derivedDataVersion` goes up, and the first open of an older store
// resets every song's `metadata_scanned` marker, so the next metadata pass re-reads every file's
// tags (the app runs that pass at launch when songs are pending).
//
// User data is untouched BY CONSTRUCTION: the bump writes only `tracks.metadata_scanned` and
// `schema_info.derived_version`; the re-read updates rows IN PLACE (same `tracks.id`, so playlist
// entries keep pointing at them) and its write (`applyExtractedResult`) names no user column.
// VerifyLibraryStore ALB-03 proves it on a store built at the previous schema.

import Foundation
import GRDB

public extension LibraryStore {
    /// The derived-data version this build writes. Bump it when a change to tag reading or to how
    /// the cache is derived needs every song re-read; the store then queues the re-read once, at
    /// open. History: 1 = S10.8 C2 (the compilation flag + album artists).
    static let derivedDataVersion = 1

    /// Read the stored derived-data version.
    private static let selectDerivedVersionSQL = "SELECT derived_version FROM schema_info WHERE id = 1;"
    /// Queue every song for a tag re-read (the metadata pass picks up `metadata_scanned = 0`).
    private static let queueEveryTrackForReReadSQL = "UPDATE tracks SET metadata_scanned = 0;"
    /// Stamp the derived-data version.
    private static let stampDerivedVersionSQL = "UPDATE schema_info SET derived_version = ? WHERE id = 1;"

    /// At open: when the stored derived-data version is older than `derivedDataVersion`, queue
    /// every song for a tag re-read and stamp the new version — in ONE write, so a crash can't
    /// stamp without queueing. Returns whether it did. A store stamped by a NEWER build is left
    /// alone (never re-read backwards).
    internal static func queueTagReReadIfStale(_ writer: any DatabaseWriter) throws -> Bool {
        try writer.write { db in
            let stored = try Int.fetchOne(db, sql: selectDerivedVersionSQL) ?? 0
            guard stored < derivedDataVersion else { return false }
            try db.execute(sql: queueEveryTrackForReReadSQL)
            try db.execute(sql: stampDerivedVersionSQL, arguments: [derivedDataVersion])
            return true
        }
    }
}
