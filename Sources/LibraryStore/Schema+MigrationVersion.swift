// Schema+MigrationVersion — which schema version a migration step reaches (R1.1-B).
//
// GRDB orders and records migrations by identifier alone. Every identifier this store registers starts
// "v<N>-" for the version N its step brings a file to, and the store reads the version from there: the
// version a step registers under (`LibraryStore.makeMigrator` caps the list by it) and the version an
// upgrade's backup is named for (`StoreBackup`, `library.pre-v<N>-<stamp>.sqlite3`). Counting steps
// served while every version had exactly one; R1.1-B's two lanes each add one in parallel (v10 the queue
// state, v11 the search re-index), so a branch may hold v11 without v10 until they combine.

import Foundation

public extension Schema.MigrationID {
    /// The schema version a migration reaches, read from its identifier ("v<N>-…"), or nil for an
    /// identifier that is not named so (a harness's own step).
    static func version(of identifier: String) -> Int? {
        guard identifier.first == "v" else { return nil }
        let digits = identifier.dropFirst().prefix { $0.isASCII && $0.isNumber }
        guard !digits.isEmpty, identifier.dropFirst(1 + digits.count).first == "-" else { return nil }
        return Int(digits)
    }
}
