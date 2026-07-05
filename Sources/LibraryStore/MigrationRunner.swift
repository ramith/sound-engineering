// MigrationRunner — the `user_version`-gated, transactional migration runner.
//
// S8.1a (design §5). Brings a store from its on-disk `user_version` up to the
// target version by applying a linear, ordered list of migration steps, ALL
// inside ONE `BEGIN IMMEDIATE … COMMIT`. If any step throws, the whole
// transaction rolls back — `user_version` and data stay at the pre-migration
// state (SCHEMA-4). A store whose version is *newer* than the target trips the
// downgrade guard (`SQLiteError.schemaTooNew`), which `LibraryStore` translates
// into quarantine + rebuild.
//
// Production ships the ordered steps to `currentSchemaVersion`: v0→v1 (create-all
// + seed) and v1→v2 (S9.2 — the `tracks_fts` FTS5 table + backfill). The runner is
// deliberately list-driven so the verify harness can also register TEST-ONLY steps
// to prove the runner mechanically — SCHEMA-3/SCHEMA-4.

import Foundation

/// A single forward migration step: brings the schema from `toVersion - 1` to
/// `toVersion`. The body runs inside the runner's transaction and MUST NOT open
/// its own transaction. It should NOT touch `user_version` (the runner owns that)
/// but v-DDL steps typically call `Schema.writeSchemaInfo` for provenance.
public struct Migration {
    /// The version this step upgrades the store TO (steps apply in ascending order).
    public let toVersion: Int
    /// The migration body. Applied only when the store's current version is
    /// `toVersion - 1`.
    public let apply: (SQLiteConnection) throws -> Void

    /// Create a migration step upgrading to `toVersion` via `apply`.
    public init(toVersion: Int, apply: @escaping (SQLiteConnection) throws -> Void) {
        self.toVersion = toVersion
        self.apply = apply
    }
}

/// Applies ordered migration steps under the `user_version` gate.
public enum MigrationRunner {
    /// The production migration list to reach `currentSchemaVersion`. Injected
    /// `appBuild`/`timestamp` flow into the v0→v1 provenance row.
    public static func productionMigrations(appBuild: String?, timestamp: Int64) -> [Migration] {
        [
            Migration(toVersion: 1) { connection in
                try Schema.migrateV0toV1(connection, appBuild: appBuild, timestamp: timestamp)
            },
            Migration(toVersion: 2) { connection in
                try Schema.migrateV1toV2(connection, appBuild: appBuild, timestamp: timestamp)
            },
        ]
    }

    /// Run every migration whose `toVersion` is greater than the store's current
    /// `user_version`, in ascending order, inside a single transaction, then set
    /// `user_version` to `targetVersion`.
    ///
    /// Behaviour:
    ///   • current == target  → no-op (idempotent open of an up-to-date store).
    ///   • current  < target  → apply the contiguous steps current+1 … target,
    ///     transactionally; a gap (missing step) throws `.migrationMissing`.
    ///   • current  > target  → throw `.schemaTooNew` (the downgrade guard).
    ///
    /// - Parameters:
    ///   - connection: an open connection (pragmas already applied).
    ///   - migrations: the ordered step list (may include test-only steps).
    ///   - targetVersion: the version to migrate TO (defaults to the runner-derived
    ///     max of the step list so test harnesses reach their highest step).
    public static func migrate(
        _ connection: SQLiteConnection,
        migrations: [Migration],
        targetVersion: Int
    ) throws {
        let current = try connection.userVersion()

        if current > targetVersion {
            throw SQLiteError.schemaTooNew(found: current, supported: targetVersion)
        }
        if current == targetVersion {
            return
        }

        let sorted = migrations.sorted { $0.toVersion < $1.toVersion }
        let pending = sorted.filter { $0.toVersion > current && $0.toVersion <= targetVersion }

        // Every version in (current, target] must have exactly one step — a gap
        // would leave the schema in an undefined intermediate state.
        let providedVersions = Set(pending.map(\.toVersion))
        for version in (current + 1) ... targetVersion where !providedVersions.contains(version) {
            throw SQLiteError.migrationMissing(version: version)
        }

        try connection.transaction {
            for step in pending {
                try step.apply(connection)
            }
            try connection.setUserVersion(targetVersion)
        }
    }

    /// Convenience for the production path: derive the target from the production
    /// migration list and run it.
    public static func migrateToCurrent(
        _ connection: SQLiteConnection,
        appBuild: String?,
        timestamp: Int64
    ) throws {
        try migrate(
            connection,
            migrations: productionMigrations(appBuild: appBuild, timestamp: timestamp),
            targetVersion: currentSchemaVersion
        )
    }
}
