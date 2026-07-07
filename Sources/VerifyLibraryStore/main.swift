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

/// The ordered check list. Extracted from `runAllChecks` to keep that function under the
/// body-length limit as S8.2+ append cases.
func allCheckCases() -> [CheckCase] {
    [
        // S8.1a — store foundation.
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
        // S8.2a — real folder scan → store.
        CheckCase(label: "g-scan-core", run: checkScanCore),
        CheckCase(label: "h-scan-rescan-edge", run: checkScanRescanEdge),
        // S8.2b — reconcile (end-of-walk sweep) + move-signature + root rejection + reads-during-scan.
        CheckCase(label: "i-scan-multiroot-isolation", run: checkMultiRootSweepIsolation),
        CheckCase(label: "j-scan-reconcile-delete-rename", run: checkReconcileDeleteRename),
        CheckCase(label: "k-reject-nested-roots", run: checkRejectNestedRoots),
        CheckCase(label: "l-reads-during-scan", run: checkReadsDuringScan),
        // S8.2b review-driven: FS-safety invariants + edge cases + QS3 root identity.
        CheckCase(label: "m-cancellation-skips-sweep", run: checkCancellationSkipsSweep),
        CheckCase(label: "n-throw-skips-sweep", run: checkThrowSkipsSweep),
        CheckCase(label: "o-cross-dir-move", run: checkCrossDirMove),
        CheckCase(label: "p-vanished-root", run: checkVanishedRoot),
        CheckCase(label: "q-scan-edge-perm-symlink", run: checkScanEdgePermissionsSymlink),
        CheckCase(label: "r-root-identity-dedup", run: checkRootIdentityDedup),
        // S8.3 Slice 1 — metadata/artwork store write ops (synthetic; extraction is Slice 5).
        CheckCase(label: "s-meta-marker", run: checkMetadataMarker),
        CheckCase(label: "t-meta-apply-result", run: checkMetadataApplyResult),
        CheckCase(label: "u-meta-artwork-orphan", run: checkMetadataArtworkOrphan),
        // S8.3 Slice 2 — extractor FS-tolerance smoke (full extraction is Slice 5).
        CheckCase(label: "v-extractor-vanished", run: checkExtractorVanishedFile),
        // S8.3 Slice 3 — ArtworkCache (sha256 dedup + original + 512px thumbnail).
        CheckCase(label: "w-artwork-cache", run: checkArtworkCache),
        // S8.3 Slice 4 — MetadataScanner pass (stub extractors; real files are Slice 5).
        CheckCase(label: "x-metadata-pass", run: checkMetadataPass),
        // S8.3 Slice 5 — REAL-file extraction correctness (self-made tagged fixtures).
        CheckCase(label: "y-real-m4a", run: checkRealMetadataM4A),
        CheckCase(label: "z-real-flac", run: checkRealMetadataFLAC),
        // S8.3 review-driven: album-cover first-wins (M5), pass cancellation (M9), real tagless.
        CheckCase(label: "aa-album-cover-first-wins", run: checkAlbumCoverFirstWins),
        CheckCase(label: "ab-metadata-pass-cancellation", run: checkMetadataPassCancellation),
        CheckCase(label: "ac-real-no-tags", run: checkRealNoTags),
    ] + moveMatchCheckCases() + facetSweepCheckCases() + folderWatchCheckCases()
        + reachabilityCheckCases() + browseReadsCheckCases() + searchCheckCases()
        + songsSortCheckCases()
}

/// S9.2 — FTS5 search: v1→v2 migration/backfill, the write-path sync seam (every
/// mutation site), query safety/matching, and read-during-write. Own function so
/// `allCheckCases` stays within the body-length limit.
func searchCheckCases() -> [CheckCase] {
    [
        CheckCase(label: "fts-mig-backfill", run: checkFtsMigrationBackfill),
        CheckCase(label: "fts-mig-idempotent", run: checkFtsMigrationIdempotent),
        CheckCase(label: "fts-mig-rollback", run: checkFtsMigrationRollback),
        CheckCase(label: "fts-cap-probe", run: checkFtsCapabilityProbe),
        CheckCase(label: "fts-sync-write", run: checkFtsSyncOnWrite),
        CheckCase(label: "fts-sync-rename", run: checkFtsSyncOnRename),
        CheckCase(label: "fts-sync-genre", run: checkFtsGenreWritePath),
        CheckCase(label: "fts-delete-move", run: checkFtsDeleteAndMove),
        CheckCase(label: "fts-sweep-removeroot", run: checkFtsSweepAndRemoveRoot),
        CheckCase(label: "fts-query-safety", run: checkFtsQuerySafety),
        CheckCase(label: "fts-query-matching", run: checkFtsQueryMatching),
        CheckCase(label: "fts-ranking-shape", run: checkFtsRankingAndShape),
        CheckCase(label: "fts-noop-rescan-zero-writes", run: checkFtsNoOpRescanZeroWrites),
        CheckCase(label: "fts-read-during-write", run: checkFtsReadDuringWrite),
    ]
}

/// S8.4 Slice 1 — move-matching (id-preserving reconcile; closes SEQ-1/Gate-2). In its own
/// function so `allCheckCases` stays within the body-length limit.
func moveMatchCheckCases() -> [CheckCase] {
    [
        CheckCase(label: "ad-move-reference-survives", run: checkMoveReferenceSurvives),
        CheckCase(label: "ae-move-candidate-selection", run: checkMoveCandidateSelection),
        CheckCase(label: "af-move-not-false-triggered", run: checkMoveNotFalseTriggered),
        CheckCase(label: "ag-move-url-collision", run: checkMoveUrlCollision),
        CheckCase(label: "ah-move-reorg-crossroot", run: checkMoveReorgAndCrossRoot),
    ]
}

/// S8.4 Slice 2 — SF-2 facet-orphan sweep (zero-track albums/artists/genres; sentinel-safe).
func facetSweepCheckCases() -> [CheckCase] {
    [
        CheckCase(label: "ai-facet-sweep-basics", run: checkFacetSweepBasics),
        CheckCase(label: "aj-facet-sweep-sentinel-albumartist", run: checkFacetSweepSentinelAndAlbumArtist),
        CheckCase(label: "ak-facet-sweep-artwork", run: checkFacetSweepArtworkInteraction),
    ]
}

/// S8.4 Slice 4 — FSEvents LibraryWatcher plumbing (deterministic ingest-seam decode/routing).
func folderWatchCheckCases() -> [CheckCase] {
    [
        CheckCase(label: "al-watcher-ingest", run: checkWatcherIngest),
    ]
}

/// S8.4 Slice 5b — reconcile reachability precheck + root identity re-stamp (headless logic).
func reachabilityCheckCases() -> [CheckCase] {
    [
        CheckCase(label: "am-root-reachability", run: checkRootReachability),
        CheckCase(label: "an-restamp-root", run: checkRestampRoot),
    ]
}

/// S9.1 — browse/search DAO reads (LibraryTrackDisplay projection, artwork-path map,
/// facet drill-downs, pagination, EXPLAIN-plan scale tripwire). In its own function so
/// `allCheckCases` stays within the body-length limit.
func browseReadsCheckCases() -> [CheckCase] {
    [
        CheckCase(label: "br1-artwork-map", run: checkBrowseArtworkMap),
        CheckCase(label: "br1b-artwork-miss", run: checkBrowseArtworkMiss),
        CheckCase(label: "br1c-artwork-chunk", run: checkBrowseArtworkChunking),
        CheckCase(label: "br2-artist-drilldown", run: checkBrowseArtistDrilldown),
        CheckCase(label: "br2b-genre-drilldown", run: checkBrowseGenreDrilldown),
        CheckCase(label: "br2c-year-facet", run: checkBrowseYearFacet),
        CheckCase(label: "br3-single-facet", run: checkBrowseSingleFacet),
        CheckCase(label: "br3b-sentinel-excluded", run: checkBrowseSentinelExcluded),
        CheckCase(label: "br4-pagination", run: checkBrowsePagination),
        CheckCase(label: "br5-explain-plan", run: checkBrowseQueryPlan),
    ]
}

func runAllChecks() async {
    await runRestartSubcommandIfRequested()
    await runFSEventsSmokeIfRequested()

    print("=== VerifyLibraryStore — S8.1a store + S8.1b DAO/concurrency/FS-divergence "
        + "+ S8.2a/b folder scan + reconcile ===")
    print("test-data dir: \(testDataDirectory.path)")
    print("run id: \(runIdentifier)")

    let cases = allCheckCases()

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

    // All passed — clean up every temp fixture and exit 0. (On failure, fail() exits above,
    // so both the store files AND the scan-fixture trees are kept for post-mortem.)
    for url in usedURLs {
        cleanupStore(url)
    }
    // The S8.2 scan cases build real directory trees under test-data/scan-fixtures/<runID>/;
    // remove this run's tree. cleanupScanFixtures() restores writable permission first, so a
    // chmod 0o000 permission-denied fixture (S8.2b, check Q) can't wedge the teardown and leak
    // (a plain removeItem would silently fail on it). (F8: this helper was defined but never called.)
    cleanupScanFixtures()
    printRunSummary(passed: passed, total: cases.count)
    exit(0)
}

/// Print the final PASS summary + banner. Extracted from `runAllChecks` so its long,
/// ever-growing multi-line summary string does not push that function over the
/// body-length limit as each slice appends its cases.
private func printRunSummary(passed: Int, total: Int) {
    print("=== SUMMARY: \(passed)/\(total) checks PASSED "
        + "(S8.1a: SCHEMA-1..6 + RESTART; S8.1b: B CRUD/integrity, C facets, D concurrency, "
        + "E idempotency+identity, F filesystem-divergence; "
        + "S8.2a: G scan-core [correctness/relative-path/boundary/signature], "
        + "H scan-rescan-edge [idempotent/FS-5 add+modify/empty/TOCTOU]; "
        + "S8.2b: I multi-root-sweep-isolation, J reconcile-delete+rename [sweep + move-signature], "
        + "K reject-nested-roots, L reads-during-scan [parked mid-scan rendezvous]; "
        + "S8.2b review: M cancellation-skips-sweep, N throw-skips-sweep, O cross-dir-move [id-preserving], "
        + "P vanished-root [S8.4 empty-walk guard: rows preserved], Q perm-denied+symlink, "
        + "R root-identity-dedup [dev/inode, QS3]; "
        + "S8.3 Slice 1: S meta-marker+idempotency, T applyExtractedResult, U artwork-dedup+orphan-sweep; "
        + "S8.3 Slice 2: V extractor-FS-tolerance; S8.3 Slice 3: W artwork-cache-dedup+thumbnail; "
        + "S8.3 Slice 4: X metadata-pass [enrich+idempotency+anti-loop]; "
        + "S8.3 Slice 5: Y real-m4a [AVFoundation], Z real-flac [FFmpeg]; "
        + "S8.3 review: AA album-cover-first-wins [IS NULL guard], AB metadata-pass-cancellation "
        + "[skips sweep], AC real-no-tags [empty-not-crash + marked]; "
        + "S8.4 Slice 1: AD move-reference-survives [Gate-2: play_count/loved/rating keep the id], "
        + "AE move-candidate-selection [cross-vol/format/ambiguity → no-match], "
        + "AF move-not-false-triggered [modify/copy], AG move-url-collision [typed conflict], "
        + "AH move-reorg-crossroot [double-move + cross-root id-preserving]; "
        + "S8.4 Slice 2: AI facet-sweep-basics [zero-track album/genre swept, referenced kept, idempotent], "
        + "AJ facet-sweep-sentinel-albumartist [id-0 never swept, album-artist-only kept + not rewritten], "
        + "AK facet-sweep-artwork [album deletion → artwork reclaimed]; "
        + "S8.4 Slice 4: AL watcher-ingest [FSEvents decode/routing via ingest seam]; "
        + "S8.4 Slice 5b: AM root-reachability [precheck skips unmounted/deleted], "
        + "AN restamp-root [remount dev/inode re-stamp keeps identity-dedup]; "
        + "S9.1: BR1/1b/1c artwork-path-map+miss+chunked-IN, BR2/2b/2c artist/genre/year "
        + "drill-downs [no fan-out], BR3/3b single-facet+sentinel-excluded, BR4 pagination-window, "
        + "BR5 EXPLAIN no-SCAN-TABLE-tracks; "
        + "S9.2 FTS5: MIG-backfill [all 4 columns] + MIG-idempotent + CAP-probe, SYNC write/rename "
        + "[moveMatched blocker-fix], DEL delete/move + sweep-ordering/removeRoot, Q safety/prefix/"
        + "AND/diacritics/bm25-rank/dedup, no-op-rescan-zero-writes, read-during-write; "
        + "S9.5 D7: SS1 new-TrackSort order + id tiebreak + NULLs-ordering, "
        + "SS2 EXPLAIN no-SCAN-TABLE-tracks + index-ordered date_added/year, filesort rest [R3]; "
        + "S9.5 §12.1/§12.3: SS3 full-catalog projection round-trip [discNo/fileSize/playCount/"
        + "lastPlayed/albumArtistName/genreName + 0-16 index-drift guard], SS4 EXPLAIN shape lock "
        + "[genre CORRELATED SCALAR SUBQUERY + SEARCH aa + BR5 hot-reads recheck], "
        + "SS5 incrementPlayCount [atomic URL-keyed accumulate + independent + silent no-op]) ===")
    print("ALL LIBRARY-STORE CHECKS PASSED — store opens/migrates + schema v\(currentSchemaVersion); "
        + "DAO CRUD/upsert/moveTrack/facets correct; WAL snapshot isolation + stress integrity ok; "
        + "idempotent + id-stable; tolerates a filesystem that diverged from the store")
}

await runAllChecks()
