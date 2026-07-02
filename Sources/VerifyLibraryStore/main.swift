// VerifyLibraryStore — headless S8.1 acceptance gate for the persistent library
// store (design §6). `swift test` is unusable here (swift-testing macro skew), so
// this is a runnable executable (`swift run VerifyLibraryStore`) that asserts,
// against the REAL LibraryStore code, the harness plan:
//
//   S8.1a (store foundation):
//     SCHEMA-1  fresh create → user_version == 1, integrity_check ok, WAL +
//               foreign_keys + busy_timeout set, all v1 tables present + sentinel.
//     SCHEMA-2  first-run idempotency (open the same fresh DB twice).
//     SCHEMA-3  migration-runner preserves data across a version bump.
//     SCHEMA-4  migration is transactional (all-or-nothing).
//     SCHEMA-5  corrupt file (+ live -wal/-shm) → quarantine + rebuild, no crash;
//               plus the actor's own auto-repair path end to end.
//     SCHEMA-6  downgrade guard — newer user_version → schemaTooNew + rebuild.
//     RESTART   durability — write, drop the store, reopen → rows present.
//
//   S8.1b (DAO + concurrency/FS-divergence):
//     B  CRUD/integrity — round-trip, UNIQUE(url) typed conflict, FK detach, M1.
//     C  facets — album/artist/genre/year/folder-boundary vs computed expectations.
//     D  concurrency — WAL/busy_timeout, snapshot isolation, BUSY, stress, abort.
//     E  idempotency + identity — no-bump re-upsert, M2 classify, M6 moveTrack.
//     F  filesystem divergence — diverged-row read, orphan primitives, no-dup, loose.
//
// Idiom mirrors Sources/VerifyAUGraph/main.swift EXACTLY: `fail(_) -> Never`,
// numbered PASS/FAIL lines, exit(0) ONLY when every check passes. Temp databases
// live under test-data/ (NEVER /tmp), are UUID-unique, and are removed on overall
// success (kept on failure for post-mortem).

import Foundation
import LibraryStore

// MARK: - VerifyAUGraph-idiom failure + PASS/FAIL reporting

func fail(_ message: String) -> Never {
    print("VERIFY FAIL: \(message)")
    exit(1)
}

/// Print a numbered PASS line.
func printPass(_ number: Int, _ message: String) {
    print("check \(number) PASS: \(message)")
}

/// Print a numbered FAIL line.
func printFail(_ number: Int, _ message: String) {
    print("check \(number) FAIL: \(message)")
}

// MARK: - test-data/ temp-DB management (never /tmp)

/// The `test-data/` directory (repo-relative, resolved from the working directory
/// `swift run` uses — the package root). Fixtures live here, never /tmp.
let testDataDirectory: URL = {
    let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
    let directory = cwd.appendingPathComponent("test-data", isDirectory: true)
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
}()

/// A unique run identifier so this invocation's fixtures never collide and are
/// individually cleanable.
let runIdentifier = UUID().uuidString

/// Build a unique store URL under `test-data/` for a named case.
func tempStoreURL(_ label: String) -> URL {
    testDataDirectory.appendingPathComponent("verify-\(label)-\(runIdentifier).sqlite3")
}

/// Remove a store file and any `-wal`/`-shm`/quarantine siblings created for it.
func cleanupStore(_ url: URL) {
    let fileManager = FileManager.default
    let directory = url.deletingLastPathComponent()
    let stem = url.deletingPathExtension().lastPathComponent
    guard let contents = try? fileManager.contentsOfDirectory(atPath: directory.path) else { return }
    for name in contents where name.hasPrefix(stem) {
        try? fileManager.removeItem(at: directory.appendingPathComponent(name))
    }
}

// MARK: - Two-invocation restart mode (optional, process-boundary durability)

/// `swift run VerifyLibraryStore --restart-write <path>` seeds three rows into the
/// store at <path> and exits 0. `--restart-read <path>` opens it and exits 0 only
/// if the three rows are present. A true process-boundary durability check for the
/// founder to run manually; the in-process RESTART case already proves the on-disk
/// round-trip within the default run.
func runRestartSubcommandIfRequested() async {
    let arguments = CommandLine.arguments
    guard arguments.count >= 3 else { return }
    let mode = arguments[1]
    let url = URL(fileURLWithPath: arguments[2])

    switch mode {
    case "--restart-write":
        do {
            let store = try await LibraryStore(url: url, appBuild: "verify-restart")
            for suffix in ["A", "B", "C"] {
                _ = try await store.seedFolderRow(path: "/Music/Restart-\(suffix)")
            }
            print("restart-write ok: seeded 3 rows into \(url.lastPathComponent)")
            exit(0)
        } catch {
            fail("restart-write threw: \(error)")
        }
    case "--restart-read":
        do {
            let store = try await LibraryStore(url: url, appBuild: "verify-restart")
            let count = try await store.countRows(inTable: "folders")
            guard count == 3 else { fail("restart-read: expected 3 rows, found \(count)") }
            print("restart-read ok: 3 rows survived the process restart")
            exit(0)
        } catch {
            fail("restart-read threw: \(error)")
        }
    default:
        return
    }
}

// MARK: - Driver

/// One check case: its temp store URL and an async body returning PASS/FAIL.
struct CheckCase {
    let label: String
    let run: (Int, URL) async -> Bool
}

func runAllChecks() async {
    await runRestartSubcommandIfRequested()

    print("=== VerifyLibraryStore — S8.1a store + S8.1b DAO/concurrency/FS-divergence ===")
    print("test-data dir: \(testDataDirectory.path)")
    print("run id: \(runIdentifier)")

    let cases: [CheckCase] = [
        // S8.1a — store foundation (unchanged).
        CheckCase(label: "schema1-fresh", run: checkFreshCreate),
        CheckCase(label: "schema2-idempotent", run: checkIdempotentReopen),
        CheckCase(label: "schema3-preserve") { number, url in checkMigrationPreservesData(number: number, url: url) },
        CheckCase(label: "schema4-txn") { number, url in checkMigrationTransactional(number: number, url: url) },
        CheckCase(label: "schema5-corrupt", run: checkCorruptQuarantineRebuild),
        CheckCase(label: "schema5b-autorepair", run: checkActorAutoRepair),
        CheckCase(label: "schema6-downgrade", run: checkDowngradeGuard),
        CheckCase(label: "restart-durability", run: checkRestartDurability),
        // S8.1b — DAO + concurrency + FS divergence.
        CheckCase(label: "b-crud-integrity", run: checkCRUDIntegrity),
        CheckCase(label: "c-facets", run: checkFacets),
        CheckCase(label: "d-concurrency", run: checkConcurrency),
        CheckCase(label: "e-idempotency-identity", run: checkIdempotencyIdentity),
        CheckCase(label: "f-fs-divergence", run: checkFilesystemDivergence),
    ]

    var passed = 0
    var usedURLs: [URL] = []
    for (index, testCase) in cases.enumerated() {
        let number = index + 1
        let url = tempStoreURL(testCase.label)
        usedURLs.append(url)
        // Each case starts from a clean slate (no stale sibling files).
        cleanupStore(url)
        let caseResult = await testCase.run(number, url)
        if caseResult {
            passed += 1
        } else {
            // Keep this case's fixtures for post-mortem; clean up the earlier
            // (passed) ones, then fail hard in the VerifyAUGraph idiom.
            for earlier in usedURLs where earlier != url {
                cleanupStore(earlier)
            }
            fail("check \(number) (\(testCase.label)) failed — fixtures kept at "
                + "\(url.lastPathComponent) under test-data/")
        }
    }

    // All passed — clean up every temp fixture and exit 0.
    for url in usedURLs {
        cleanupStore(url)
    }
    print("=== SUMMARY: \(passed)/\(cases.count) checks PASSED "
        + "(S8.1a: SCHEMA-1..6 + RESTART; S8.1b: B CRUD/integrity, C facets, D concurrency, "
        + "E idempotency+identity, F filesystem-divergence) ===")
    print("ALL LIBRARY-STORE CHECKS PASSED — store opens/migrates + schema v\(currentSchemaVersion); "
        + "DAO CRUD/upsert/moveTrack/facets correct; WAL snapshot isolation + stress integrity ok; "
        + "idempotent + id-stable; tolerates a filesystem that diverged from the store")
    exit(0)
}

await runAllChecks()
