import AudioDSP
import Foundation
import GRDB

/// The analysis store (R1.1-B W5, lane 3-A; level-and-fold "The store and the scheduler", M5, M6, architect N7;
/// US-R1F-10 item 16): every track's `TrackAnalysis`, kept in a rebuildable derived-data file beside the library —
/// `track-analysis.sqlite3` in the app's data folder, its own GRDB connection — and never in the library database.
///
/// - Records are keyed by the file's full identity (path, size, mtime): an edited or replaced file is a new one.
///   One record per path: saving a file's new identity replaces its old one.
/// - A record of another analysis version, or one whose payload will not decode, counts as not analysed and is
///   overwritten by the next save.
/// - The scalar record (numbers, histograms, LFE statistics: a few KB) is kept for every analysed track; the
///   compact −ΔL profiles (up to ~600 KB per basis) are capped at `defaultProfileBudgetBytes` in all, the least
///   recently used going first. A track whose profiles went keeps its numbers. A profile is kept once per
///   measurement: the four fold variants of a file with no LFE share one (`TrackAnalysis.profileSource`).
/// - Everything here can be rebuilt by analysing again, so a file that is not a database or is corrupt is
///   recreated (closed, then the file and its `-wal` / `-shm` deleted), and one found so while open is erased on
///   its connection — never `eraseDatabaseOnSchemaChange`. A file that merely cannot be used now (another
///   connection holds it locked past the busy timeout, a disk or permission error) is never touched: the open
///   throws, and the app plays unanalysed.
///
/// Every method is async and runs one read or one write transaction on the store's own queue: call it from any
/// task, never wait on it from the main thread.
public final class TrackAnalysisStore: Sendable {
    /// The store's file name in the app's data folder (`AppDataLocation.directory`).
    public static let fileName = "track-analysis.sqlite3"
    /// The compact profiles' cap (1 GB).
    public static let defaultProfileBudgetBytes = 1 << 30

    /// The store's file.
    public let url: URL
    private let profileBudgetBytes: Int
    private let queue: DatabaseQueue

    /// Open the store in `directory` (created when missing), recreating a file that is not a database or is
    /// corrupt (`isBroken`). Throws, deleting nothing, when the file cannot be used now — another connection holds it
    /// locked past the 5 s busy timeout (BI-S20), a disk or permission error — or when even a fresh file cannot be
    /// made.
    public init(directory: URL, profileBudgetBytes: Int = defaultProfileBudgetBytes) throws {
        url = directory.appending(path: Self.fileName, directoryHint: .notDirectory)
        self.profileBudgetBytes = profileBudgetBytes
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        do {
            queue = try Self.open(url)
        } catch let error as DatabaseError where Self.isBroken(error) {
            Self.remove(url)
            queue = try Self.open(url)
        }
    }

    /// The current-version records of `identities` that the store holds, by identity — numbers, histograms and LFE
    /// statistics, **without** the profiles (their slots are nil; read them with `profiles(for:bases:)`). An
    /// identity with no usable record is absent.
    public func analyses(for identities: [TrackIdentity]) async throws -> [TrackIdentity: TrackAnalysis] {
        let wanted = Set(identities)
        guard !wanted.isEmpty else { return [:] }
        let paths = Array(Set(wanted.map(\.path)))
        let records = try await perform { db in
            try stride(from: 0, to: paths.count, by: Self.chunk).flatMap { start in
                let slice = Array(paths[start ..< min(start + Self.chunk, paths.count)])
                return try Row.fetchAll(db, sql: Self.selectAnalysesSQL(count: slice.count),
                                        arguments: StatementArguments(slice)).map(Record.init)
            }
        }
        var found: [TrackIdentity: TrackAnalysis] = [:]
        for record in records {
            guard wanted.contains(record.identity), var analysis = record.analysis else { continue }
            analysis.identity = record.identity // after a re-key the payload still names the old path
            found[record.identity] = analysis
        }
        return found
    }

    /// The saved compact profiles of `identity` on `bases` (`TrackAnalysis`'s own indices: 0 as decoded, 1 + v the
    /// fold at LFE variant v) that are still kept, by basis — a basis whose measurement another carries
    /// (`profileSource`) answered with that one's; reading them marks them used. None when the store has no
    /// current-version record of `identity`.
    public func profiles(for identity: TrackIdentity, bases: [Int]) async throws -> [Int: TrackAnalysis.Profile] {
        guard !bases.isEmpty else { return [:] }
        return try await perform { db in
            guard let record = try Row.fetchOne(db, sql: Self.selectRecordSQL, arguments: [identity.path])
                .map(Record.init), record.identity == identity, let analysis = record.analysis else { return [:] }
            var found: [Int: TrackAnalysis.Profile] = [:]
            var read: [Int] = []
            for (source, asked) in Dictionary(grouping: Set(bases), by: analysis.profileSource(of:)) {
                guard let row = try Row.fetchOne(db, sql: Self.selectProfileSQL, arguments: [identity.path, source])
                else { continue }
                let profile = TrackAnalysis.Profile(row: row)
                for basis in asked {
                    found[basis] = profile
                }
                read.append(source)
            }
            if !read.isEmpty {
                let used = try Self.nextUse(db)
                for source in read {
                    try db.execute(sql: Self.touchProfileSQL, arguments: [used, identity.path, source])
                }
            }
            return found
        }
    }

    /// Keep `analysis` (replacing any record at its path, with its profiles — each measurement's once), then trim the
    /// profiles to the cap, least recently used first.
    public func save(_ analysis: TrackAnalysis) async throws {
        var scalars = analysis
        scalars.profiles = analysis.profiles.map { _ in nil }
        let payload = try Self.encoder.encode(scalars)
        let identity = analysis.identity
        let budget = profileBudgetBytes
        try await perform { db in
            try db.execute(sql: Self.deleteRecordSQL, arguments: [identity.path]) // its profiles go with it
            try db.execute(sql: Self.insertRecordSQL, arguments: [
                identity.path, Int64(bitPattern: identity.size), identity.modified, analysis.version, payload,
            ])
            let used = try Self.nextUse(db)
            for (basis, profile) in analysis.profiles.enumerated() where analysis.profileSource(of: basis) == basis {
                guard let profile else { continue }
                let powers = profile.powers.withUnsafeBufferPointer { Data(buffer: $0) }
                try db.execute(sql: Self.insertProfileSQL, arguments: [
                    identity.path, basis, powers.count, used, profile.sampleRate, profile.bandsPerOctave,
                    profile.bandCount, profile.blockCount, profile.blockStrideHops, powers,
                ])
            }
            try db.execute(sql: Self.evictProfilesSQL, arguments: [budget])
        }
    }

    /// After "Use this drive" moved a music folder from `oldRoot` to `newRoot` (both directory paths): every record
    /// under `oldRoot` whose file is at the same place under `newRoot` with the same size and modification time
    /// moves there, with its profiles, so the drive's songs are not analysed again. The rest stay as they are.
    /// Paths compare in their precomposed (NFC) form, the library's. Returns how many moved.
    @discardableResult
    public func rekey(root oldRoot: String, to newRoot: String) async throws -> Int {
        let oldPrefix = Self.directoryPrefix(oldRoot)
        let newPrefix = Self.directoryPrefix(newRoot)
        guard oldPrefix != newPrefix else { return 0 }
        let kept = try await perform { db in
            try Row.fetchAll(db, sql: Self.selectIdentitiesSQL).map(RecordKey.init)
        }
        let moves: [(from: String, to: String)] = kept.compactMap { key in
            let spelled = key.path.precomposedStringWithCanonicalMapping
            guard spelled.hasPrefix(oldPrefix) else { return nil }
            let target = newPrefix + spelled.dropFirst(oldPrefix.count)
            guard let there = TrackIdentity(url: URL(fileURLWithPath: target)), there.size == key.size,
                  there.modified == key.modified else { return nil }
            return (key.path, there.path)
        }
        guard !moves.isEmpty else { return 0 }
        try await perform { db in
            for move in moves {
                try db.execute(sql: Self.deleteRecordSQL, arguments: [move.to])
                try db.execute(sql: Self.movePathSQL, arguments: [move.to, move.from])
            }
        }
        return moves.count
    }
}

// MARK: - The file

extension TrackAnalysisStore {
    /// Paths per `IN (…)` query.
    private static let chunk = 500

    private static let encoder: PropertyListEncoder = {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        return encoder
    }()

    /// The schema, version 1. Append migrations; never edit one, never erase on a change.
    private static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.eraseDatabaseOnSchemaChange = false
        migrator.registerMigration("v1") { db in
            try db.execute(sql: createAnalysisSQL)
            try db.execute(sql: createProfileSQL)
            try db.execute(sql: createProfileUseIndexSQL)
        }
        return migrator
    }

    /// Open (creating) and migrate the file at `url`; throws, with the connection closed, when it will not.
    private static func open(_ url: URL) throws -> DatabaseQueue {
        var configuration = Configuration()
        configuration.busyMode = .timeout(5)
        configuration.foreignKeysEnabled = true
        let queue = try DatabaseQueue(path: url.path, configuration: configuration)
        do {
            try migrator.migrate(queue)
        } catch {
            try? queue.close()
            throw error
        }
        return queue
    }

    /// Whether `error` says the file itself is broken — not a database, or corrupt — so recreating it loses
    /// nothing that analysing again would not restore. Busy, locked, I/O and permission errors are not.
    private static func isBroken(_ error: DatabaseError) -> Bool {
        [.SQLITE_CORRUPT, .SQLITE_NOTADB].contains(error.resultCode)
    }

    /// Delete the file at `url` and its sidecars.
    private static func remove(_ url: URL) {
        for suffix in ["", "-wal", "-shm", "-journal"] {
            try? FileManager.default.removeItem(atPath: url.path + suffix)
        }
    }

    /// One transaction. A file found broken while open is erased on its connection and migrated afresh — the
    /// operation still throws, and the next one finds an empty store.
    private func perform<Value: Sendable>(_ body: @escaping @Sendable (Database) throws -> Value) async throws
        -> Value {
        do {
            return try await queue.write(body)
        } catch let error as DatabaseError where Self.isBroken(error) {
            try? await queue.erase()
            try? Self.migrator.migrate(queue)
            throw error
        }
    }

    /// The next use stamp: one past the newest.
    private static func nextUse(_ db: Database) throws -> Int64 {
        try Int64.fetchOne(db, sql: newestUseSQL).map { $0 + 1 } ?? 1
    }

    /// `path` as a directory prefix in the library's spelling: precomposed, standardized, ending in "/".
    private static func directoryPrefix(_ path: String) -> String {
        let standardized = (path.precomposedStringWithCanonicalMapping as NSString).standardizingPath
        return standardized.hasSuffix("/") ? standardized : standardized + "/"
    }
}

// MARK: - Rows

extension TrackAnalysisStore {
    /// The identity columns of an `analysis` row.
    private struct RecordKey: Sendable {
        let path: String
        let size: UInt64
        let modified: Double

        init(_ row: Row) {
            path = row["path"]
            size = UInt64(bitPattern: row["size"])
            modified = row["mtime"]
        }

        /// The identity it names, field for field (review N10: never through a coder, whose round trip of the
        /// mtime every record's match would hang on).
        var identity: TrackIdentity {
            TrackIdentity(path: path, size: size, modified: modified)
        }
    }

    /// One `analysis` row.
    private struct Record: Sendable {
        let identity: TrackIdentity
        let version: Int
        let payload: Data

        init(_ row: Row) {
            identity = RecordKey(row).identity
            version = row["version"]
            payload = row["payload"]
        }

        var isCurrent: Bool {
            version == Int(AS_TRACK_ANALYSIS_VERSION)
        }

        /// The record's analysis: nil when it is of another version or will not decode.
        var analysis: TrackAnalysis? {
            guard isCurrent, let analysis = try? PropertyListDecoder().decode(TrackAnalysis.self, from: payload),
                  analysis.version == version else { return nil }
            return analysis
        }
    }
}

private extension TrackAnalysis.Profile {
    /// A `profile` row's profile.
    init(row: Row) {
        let bytes: Data = row["powers"]
        var powers = [UInt16](repeating: 0, count: bytes.count / MemoryLayout<UInt16>.size)
        _ = powers.withUnsafeMutableBytes { bytes.copyBytes(to: $0) }
        self.init(sampleRate: row["sample_rate"], bandsPerOctave: row["bands_per_octave"],
                  bandCount: row["band_count"], blockCount: row["block_count"],
                  blockStrideHops: row["block_stride_hops"], powers: powers)
    }
}

// MARK: - SQL

extension TrackAnalysisStore {
    private static let createAnalysisSQL = """
    CREATE TABLE analysis (
        path TEXT PRIMARY KEY NOT NULL,
        size INTEGER NOT NULL,
        mtime REAL NOT NULL,
        version INTEGER NOT NULL,
        payload BLOB NOT NULL
    )
    """
    private static let createProfileSQL = """
    CREATE TABLE profile (
        path TEXT NOT NULL REFERENCES analysis(path) ON DELETE CASCADE ON UPDATE CASCADE,
        basis INTEGER NOT NULL,
        bytes INTEGER NOT NULL,
        last_used INTEGER NOT NULL,
        sample_rate REAL NOT NULL,
        bands_per_octave INTEGER NOT NULL,
        band_count INTEGER NOT NULL,
        block_count INTEGER NOT NULL,
        block_stride_hops INTEGER NOT NULL,
        powers BLOB NOT NULL,
        PRIMARY KEY (path, basis)
    )
    """
    private static let createProfileUseIndexSQL = "CREATE INDEX profile_last_used ON profile(last_used)"

    private static func selectAnalysesSQL(count: Int) -> String {
        "SELECT path, size, mtime, version, payload FROM analysis WHERE path IN ("
            + Array(repeating: "?", count: count).joined(separator: ", ") + ")"
    }

    private static let selectRecordSQL = "SELECT path, size, mtime, version, payload FROM analysis WHERE path = ?"
    private static let selectIdentitiesSQL = "SELECT path, size, mtime FROM analysis"
    private static let selectProfileSQL = """
    SELECT sample_rate, bands_per_octave, band_count, block_count, block_stride_hops, powers
    FROM profile WHERE path = ? AND basis = ?
    """
    private static let touchProfileSQL = "UPDATE profile SET last_used = ? WHERE path = ? AND basis = ?"
    private static let newestUseSQL = "SELECT MAX(last_used) FROM profile"
    private static let deleteRecordSQL = "DELETE FROM analysis WHERE path = ?"
    private static let insertRecordSQL =
        "INSERT INTO analysis (path, size, mtime, version, payload) VALUES (?, ?, ?, ?, ?)"
    private static let insertProfileSQL = """
    INSERT INTO profile (path, basis, bytes, last_used, sample_rate, bands_per_octave, band_count, block_count,
                         block_stride_hops, powers)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    """
    private static let movePathSQL = "UPDATE analysis SET path = ? WHERE path = ?"
    /// Keep the most recently used profiles whose bytes fit the budget; delete the rest.
    private static let evictProfilesSQL = """
    DELETE FROM profile WHERE rowid IN (
        SELECT rowid FROM (
            SELECT rowid, SUM(bytes) OVER (ORDER BY last_used DESC, rowid DESC) AS kept FROM profile
        ) WHERE kept > ?
    )
    """
}
