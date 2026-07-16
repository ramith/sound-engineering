// ChecksMigrationConvergence — S10.3 break-it (architect BLOCKER "Attack B"). The store now holds
// NON-rebuildable user data, so a migration mistake is a data-loss / crash bug. Two guards live
// here (the strict-gate grep covers "Attack A", re-enabling erase):
//   1. STAGED-UPGRADE CONVERGENCE — a long-time user who upgrades through app versions (reach v1,
//      then apply the rest) must land on the SAME schema as a fresh install.
//   2. GOLDEN FINGERPRINT — a fresh full migrate must produce EXACTLY the committed schema. Editing
//      a SHIPPED migration body changes it (a fresh install would then diverge from an already-
//      migrated user still on the OLD body → `no such column` for UPGRADERS ONLY, invisible in
//      dev). This fails loudly; a LEGIT new migration updates the golden hash in the same commit —
//      a reviewable, intentional change, not a silent drift.

import Foundation
import GRDB
import LibraryStore

// MARK: - Registration

func migrationConvergenceCheckCases() -> [CheckCase] {
    [CheckCase(label: "additive-migration-convergence", run: { number, url in
        checkAdditiveMigrationConvergence(number: number, url: url)
    })]
}

// MARK: - Golden

/// FNV-1a hash of the expected schema fingerprint at `currentSchemaVersion`. Regenerate by running
/// VerifyLibraryStore after a NEW migration and pasting the printed FRESH hash — it should change
/// ONLY when a migration is appended, never from editing a shipped one. (A hash, not the full DDL,
/// so the constant stays one short line.)
let goldenSchemaFingerprintHashV6 = "ba691c5ab17c37ab"

// MARK: - Fingerprint

/// A normalized fingerprint of the store's SCHEMA: the DDL of every app object in `sqlite_master`
/// (whitespace-collapsed so pure reformatting doesn't churn it), excluding GRDB/SQLite internals.
/// DATA (row contents, timestamps) is NOT included — only structure.
func schemaFingerprint(_ db: Database) throws -> String {
    let rows = try Row.fetchAll(db, sql: """
    SELECT type, name, COALESCE(sql, '') AS sql FROM sqlite_master
    WHERE name NOT LIKE 'sqlite_%' AND name NOT LIKE 'grdb_%'
    ORDER BY type, name;
    """)
    return rows.map { row in
        let type: String = row["type"]
        let name: String = row["name"]
        let sql: String = row["sql"]
        let normalized = sql.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }.joined(separator: " ")
        return "\(type)|\(name)|\(normalized)"
    }.joined(separator: "\n")
}

/// Deterministic FNV-1a 64-bit hash (hex) — stable across runs/machines (unlike Swift's seeded
/// `Hasher`), so it's usable as a committed golden.
func fnv1a64Hex(_ string: String) -> String {
    var hash: UInt64 = 0xCBF2_9CE4_8422_2325
    for byte in string.utf8 {
        hash ^= UInt64(byte)
        hash = hash &* 0x0000_0100_0000_01B3
    }
    return String(format: "%016llx", hash)
}

// MARK: - Check

func checkAdditiveMigrationConvergence(number: Int, url _: URL) -> Bool {
    do {
        // Fresh install: full migrate from empty in one shot (in-memory — no file needed).
        let fresh = try DatabaseQueue()
        try fullMigrator().migrate(fresh)
        let freshFingerprint = try fresh.read { db in try schemaFingerprint(db) }

        // Staged upgrade: reach v1, THEN run the full migrator (applies v2..vN onto the v1 store) —
        // as a long-time user receives app updates over time. Must converge to the same schema.
        let staged = try DatabaseQueue()
        try v1OnlyMigrator().migrate(staged)
        try fullMigrator().migrate(staged)
        let stagedFingerprint = try staged.read { db in try schemaFingerprint(db) }

        guard freshFingerprint == stagedFingerprint else {
            printFail(number, "staged upgrade schema diverged from a fresh install:\nFRESH:\n"
                + "\(freshFingerprint)\nSTAGED:\n\(stagedFingerprint)")
            return false
        }
        let freshHash = fnv1a64Hex(freshFingerprint)
        guard freshHash == goldenSchemaFingerprintHashV6 else {
            printFail(number, "schema fingerprint drift — a SHIPPED migration body changed (or a new "
                + "migration landed without updating goldenSchemaFingerprintHashV6). If this is an "
                + "intentional NEW migration, set the golden to: \(freshHash)\nFingerprint:\n\(freshFingerprint)")
            return false
        }
        printPass(number, "additive-migration convergence: staged upgrade == fresh install, and the "
            + "schema fingerprint hash matches the golden (no shipped-body drift)")
        return true
    } catch {
        printFail(number, "additive-migration-convergence threw: \(error)")
        return false
    }
}
