# S8.2 — Folder Scan → Library Store (Design)

**Document ID:** S8.2-DESIGN-001
**Status:** DESIGN — architect verdict **GO-WITH-CHANGES** (M-A..M-D applied below); founder decisions confirmed (reject nested roots · re-scan reconciles deletions · metadata-browse/root-only). Ready to implement.
**Chunk of:** S8 (library spine). Consumes the shipped, review-hardened S8.1 store (`LibraryStore` + DAO — now GRDB-backed, `final class … Sendable`; see the SUPERSEDED note in [s8-1-persistent-store-design.md](s8-1-persistent-store-design.md) §Decisions). See [s8-1-persistent-store-design.md](s8-1-persistent-store-design.md).
**Authored by:** team — business-analyst (scope/stories US-LIB-10..17), swift-expert (scanner/signature/integration), qa-expert (real-FS test plan), synthesized by the orchestrator.

## What S8.2 does
Recursively scan the user's real scan folders and write discovered audio files into the S8.1 store — **populating the `(inode, size, mtime)` move-signature** so S8.4 can follow external moves. Extends today's `AudioFileEnumerator` walk; writes **no new SQL** (reuses the S8.1 DAO: `addRoot`/`beginScanGeneration`/`classify`/`upsert`/`sweepOrphans`). Headless-testable against a **real temp-dir tree** (S8.1 tested synthetic rows; S8.2 tests actual files). **Additive** — today's in-memory `loadMusicFolder` playlist is untouched; the store populates in parallel; the UI swaps to store-reads at S9.

---

## 1. Scope + stories

**Stories (BA):** US-LIB-10 scan-root→store · US-LIB-11 populate move-signature · US-LIB-12 off-main + cancellable progress · US-LIB-13 format allowlist · US-LIB-14 path/dedup correctness · US-LIB-15 on-demand full re-scan reconciles deletions · US-LIB-16 reject nested/duplicate roots · US-LIB-17 headless real-tree harness.

### In S8.2 vs deferred
| In S8.2 | Deferred |
|---|---|
| Recursive scan of a registered root → `ScannedFile` → `upsert` | Metadata/tag + artwork extraction → **S8.3** (S8.2 reads FS attributes only, never file contents) |
| `(inode, size, mtime)` signature **populated** on every row | **Matching** an orphan+new-path as a move (`moveTrack`) → **S8.4** |
| **On-demand full re-scan of one root: walk + upsert + `sweepOrphans` for that root** (reconciles deletions) | **Live** FSEvents-driven reconciliation → **S8.4**; `sweepOrphanFacets()` (ghost albums) → **S8.4** (SF-2 debt) |
| Off-main scan + indeterminate progress + cancellation | Progress **UI**, folder-picker UI, error surfacing → **S9** |
| Format allowlist (shared `supportedExtensions`); `UNIQUE(url)`-only dedup; reject nested roots | content-hash dedup (D3, no chunk) |
| Root-row-only + `relative_path` (no subfolder tree) | subfolder `folders` tree (only if S9 wants folder-browse) |
| `AudioViewModel` scan seam (additive; store populates in parallel) | swapping the UI's source from in-memory to store-reads → **S9** |
| Real-temp-dir-tree harness cases in `VerifyLibraryStore` | — |

---

## 2. The scanner — `LibraryScanner`

A new SwiftPM **library target `LibraryScan`** (depends on `LibraryStore`), linked by **both** the app and the harness (the `AudioFormatKit`/`LibraryStore` precedent) so the walk has one implementation, no drift. Keeps the pure-persistence `LibraryStore` module free of filesystem-walk concerns. `AudioFileEnumerator` stays in the app target but references the shared `supportedExtensions` (one-line change; the set becomes the single source of truth).

```swift
public struct LibraryScanner: Sendable {
    public static let supportedExtensions: Set<String> =
        ["flac","mp3","wav","aac","m4a","alac","aiff","ogg"]   // single source of truth

    /// Scan `root` (already addRoot'ed → folderID) and reconcile its subtree into `store`.
    /// Off the main actor. throws on store error or CancellationError.
    public func scan(root: URL, folderID: Int64, into store: LibraryStore,
                     batchSize: Int = 256,
                     progress: (@Sendable (ScanProgress) -> Void)? = nil) async throws -> ScanResult
}
// ScanResult { folderID, generation, filesSeen, filesSkipped, orphansSwept, trackIDs } : Sendable
// ScanProgress { folderID, filesSeenSoFar, totalFiles: Int? (nil = indeterminate) } : Sendable
```

**Scan unit + generations (M-A):** the unit is **one root**. A "scan my library" iterates roots **sequentially, each with its OWN generation and its OWN single-root-scoped sweep** — generations are per-root, never shared (`beginScanGeneration()` is a global `max(last_seen_scan)+1`, so calling it once per root immediately before that root's walk keeps each root's sweep correct and isolated). A sweep is *always* `sweepOrphans(inFolders:[thatFolderID], olderThan:thatGeneration)` — never multi-root, so scanning root B can never touch root A's rows (asserted in §8).

**Call flow (per root):** `let gen = beginScanGeneration()` → walk (`FileManager.enumerator`, reuse `[.skipsHiddenFiles, .skipsPackageDescendants]`) → per file, guard regular-file + supported-ext, build `ScannedFile` (with signature) → append to batch → every `batchSize` files `upsert(batch, folderID:gen)` (one `BEGIN IMMEDIATE…COMMIT` each) → after the walk, `sweepOrphans(inFolders:[folderID], olderThan:gen)`. Batched writes bound transaction size (WAL fsync amortized) and keep each actor hop short so a long scan doesn't starve S9 reads (SF-4 debt — bounded by the §8 reads-during-scan gate, M-D). (`batchSize` is an internal constant, not public API — O-1.)

---

## 3. Move-signature — one walk step per file

Signature is **load-bearing now** (populated in S8.2, matched in S8.4). Per file: **one `URLResourceValues` fetch** (`.isRegularFileKey`, `.fileSizeKey`, `.contentModificationDateKey`) + **one `lstat`** for the real `st_ino` **and `st_dev`** (`URLResourceValues` has no inode field; `.fileResourceIdentifierKey` is opaque/non-persistable, unusable for the `INTEGER inode` column). `mtime = Int64(contentModificationDate.timeIntervalSince1970)` — **whole seconds**, matching the schema (M2) + `LibraryStore.nowSeconds()`. `lstat` (not `stat`) keeps a symlink its own distinct entry (matches `PathNormalizer`'s no-resolve policy). `inode`/`dev` are nil-tolerant end-to-end (a failed `lstat` → `nil`; the file is still tracked, only that one move-signal is lost, `(size,mtime)` still discriminates).

**Capture `st_dev` NOW (M-B).** An `inode` is unique only *within a volume*, so S8.4's move-matcher (orphan + new-path, same signature) would produce **cross-volume false positives** without `st_dev` to scope the match. `st_dev` comes free from the same `lstat` — so the full move-signature is `(dev, inode, size, mtime)`, all populated in S8.2. This adds a nil-tolerant `dev INTEGER` column to `tracks` + `ScannedFile.dev: Int64?` + the `upsert` write path. **No production store exists yet** (the app doesn't construct the store until this seam lands), so `dev` is added to the **v1 schema directly** (fresh stores get it; no migration) — or, if any populated store is found, a clean v1→v2 migration via the runner. It's the same "populate now, match in S8.4" principle already applied to `inode`; splitting the signature across a later migration is exactly what §4's root-only decision avoided. Two syscalls/file is fine at library scale; a single-`lstat`-for-all-four variant is a documented perf fallback, not pre-built.

---

## 4. `relative_path` + folder model

**Root-row only + per-track `relative_path`** (relative to the root, e.g. `"Indie/2024/"`; `""` for root-level). No per-subdirectory `folders` rows — nothing consumes the tree (facets key off `folder_id` + `relative_path`; S9 browse is metadata-faceted, not a Finder tree). It's a clean additive backfill later if S9 wants a tree. **This is the exact value S8.4's `moveTrack(newRelativePath:)` consumes — one computation, two callers.**

Two corrections over today's `AudioFileEnumerator` path handling: (1) normalize **both** sides through `PathNormalizer` before the prefix strip (avoids NFC/NFD mismatch vs. the stored `url` key); (2) **component-boundary** strip (`rootPath == filePath` or `filePath` has `rootPath + "/"` prefix) — directly implements the `/Music/Rock` ≠ `/Music/RockAndRoll` guard the S8.1 review flagged for the S8.2 author.

---

## 5. Progress + cancellation

**Indeterminate count-up** — the walk is single-pass (`FileManager.enumerator` is lazy; a pre-count doubles traversal for a spinner). `ScanProgress.totalFiles = nil`, `filesSeenSoFar` increments per batch via a `@Sendable` callback (bounded rate, off-main → VM hops to `@MainActor` to publish). Progress plumbing mirrors the app's existing **20 Hz polled-counter idiom**, not a first-of-its-kind `AsyncStream`.

**Cancellation:** `Task.checkCancellation()` per file (cancels within one file, not one batch); the VM holds the scan `Task` and cancels on re-trigger/teardown (mirrors the folder-monitor debounce). **The sweep runs only at end-of-walk**, so a cancelled scan leaves already-upserted batches committed (correct) and simply skips the sweep — **no orphan is wrongly deleted from a partial view**. This is why sweep is end-of-walk, not interleaved.

---

## 6. Dedup / overlap / nested roots

Uniqueness is `url` only (Req 5: duplicates across folders are normal → distinct rows; no content-collapse). A loose file found under a root is **adopted** by `url` (`ON CONFLICT DO UPDATE SET folder_id`) — one row, id preserved (the S8.1 FS-3 path, free). **Nested/overlapping/duplicate roots are REJECTED at registration** (a cheap normalized-path component-boundary check against existing `roots()`, before any walk): registering a path that is an ancestor-or-descendant of an existing root throws a typed error. Rationale: overlapping roots would ping-pong a shared file's `folder_id` between roots under `UNIQUE(url)` and confuse each root's end-of-walk sweep. Rejecting is the clean R1 answer and never forecloses relaxing it later. (Exact-duplicate path is already the idempotent `addRoot` no-op.)

---

## 7. Integration seam (additive)

New `AudioViewModel+LibraryScan.swift`: `scanFolderIntoLibrary(url)` cancels any prior scan `Task`, then `Task.detached` → `store.addRoot(url)` → `LibraryScanner().scan(...)` with a progress closure hopping to `@MainActor` (`scanProgress`/`lastScanResult` observable state). Mirrors `loadMusicFolder`'s off-main + main-actor-publish shape; only `Sendable` types cross. The Choose-Folder site *additionally* calls this — today's in-memory `playlist` stays sourced from `loadMusicFolder` (unchanged UX); the store fills in parallel. Folder monitor unchanged in S8.2 (rewiring FSEvents → store reconciliation is S8.4).

---

## 8. Test plan — real temp-dir tree (extends `VerifyLibraryStore`)

Extend the existing harness (one gate, one idiom) — a new `ChecksScan.swift` + a `ScanFixtureBuilder` writing a **real** tree under `test-data/scan-fixtures/<uuid>/` (tiny non-empty byte files — S8.2 reads attributes, not contents; empty files avoided so S8.3's future metadata probe won't make these brittle), per-case unique dir, cleanup-on-success/keep-on-failure (extend the existing `usedURLs` loop). Cases:
- **Scan correctness:** nested tree → exactly the audio rows; `relative_path` exact (incl. `""`); format allowlist (case-insensitive; `.txt`/`.jpg`/`.cue` excluded; a dir named `music.mp3/` not scanned as a leaf); hidden/dotfiles + package descendants excluded; `format` uppercase.
- **Signature:** every row's `size`/`mtime`/`inode`/`dev` **equals an independent `lstat`** (not just non-null — catches a scanner stamping `now` for mtime, or the same inode for two files); survives the round-trip through `upsert`.
- **Idempotent re-scan (through the real scanner):** scan an unchanged tree twice → same count, no dup, no `mtime`/content bump (only `last_seen_scan` generation differs); `classify` → `.unchanged(sameID)`.
- **FS-5 reconciliation (FOUNDER REQUIREMENT):** scan → mutate on disk as if the app were closed → re-scan → assert: **add** (new row, `date_added` = re-scan epoch), **remove** (orphan-swept — S8.2 owns sweep, §9-D1), **modify** (`classify` → `.modified(sameID)`, updated in place), **rename** (S8.2 sees old-gone + new-`.new`; asserts the new row's signature == the old row's signature — the "populated now, matched in S8.4" contract; does NOT itself match).
- **Dedup/overlap:** same content under two roots → 2 distinct rows; nested-root registration → rejected (§6, error carries the conflicting root — O-2).
- **Multi-root sweep isolation (M-A):** register roots A and B (disjoint), scan A then B (each its own generation) → assert B's scan+sweep leaves A's rows fully intact (same ids), and vice-versa — the per-root-generation invariant.
- **Reads-during-scan bound (M-D, SF-4 gate):** run a bounded concurrent reader loop (`allTracks()`/`albums()`) *during* a ~500-file scan under `withDeadline` → each read returns under a generous latency bound. Converts "256-row batches keep hops short" from belief into a gate + gives S9 its baseline; if it fails, the seam-marked `SQLITE_OPEN_READONLY` connection is the known remedy. (No production concurrent reader exists until S9, so this is the first place the SF-4 trigger is measurable.)
- **Progress/cancel:** monotonic progress under a `withDeadline` bound (a stall = FAIL); cancel mid-scan → throws `CancellationError` promptly, `integrityCheck()` ok, partial rows valid (proves the driver batches, not one all-tree commit).
- **Scale sanity:** ~300–500 files under ~20–30 subdirs scans under a generous bound (catches O(n²), e.g. `beginScanGeneration()` per-file); exact count. Not a soak.
- **Edge:** empty root (0 rows, no error); permission-denied subdir (skipped, siblings still scanned, counted-not-swallowed; `chmod` restored before cleanup); TOCTOU (file deleted between enumerate and stat → `try?`-skipped, no crash — preserves today's `AudioFileEnumerator` discipline).

Gate: extend **Gate 5** (`swift run VerifyLibraryStore`) — Makefile/`make gate` unchanged; DSP null-test golden master untouched.

---

## 9. Decisions

| # | Decision | Resolution |
|---|---|---|
| **D-sweep** | Does S8.2 own the orphan-sweep? | ✅ **CONFIRMED — S8.2 owns the on-demand full re-scan incl. `sweepOrphans` for the scanned root** (a full walk knows the root's complete set; folder-scoped sweep never touches other roots or loose tracks). S8.4 owns the LIVE/incremental (FSEvents) reconciliation + move-matching. Per-root generation/sweep sequencing pinned in §2 (M-A). |
| **D-folders** | Folder-tree vs root-only | ✅ **CONFIRMED (founder): metadata-browse / root-only + `relative_path`.** No subfolder tree; cheap additive backfill if S9 ever wants a Finder-tree. |
| **D-nested** | Nested/overlapping scan roots | ✅ **CONFIRMED (founder): reject at registration** (normalized-path component-boundary check vs existing roots, before any walk). The typed error carries the conflicting root (O-2). |
| **D-module** | Where the scanner lives | New **`LibraryScan`** target (depends on `LibraryStore`); app + harness both link it. |
| **D-symlink** | Symlink policy | Scanned as its own row at its own path, unresolved (`lstat`) — consistent with `PathNormalizer`. |
| **D-split** | S8.2 sizing (~21 SP) | ✅ **CONFIRMED: split S8.2a** (scanner core: walk→`ScannedFile`→`upsert`, signature incl. `dev`, format, `relative_path`, dedup) + **S8.2b** (full re-scan+sweep, reject-nested, off-main+progress+cancel, real-tree harness incl. multi-root + reads-during-scan). |

### Architect must-fixes (GO-WITH-CHANGES — all applied above)
- **M-A** — scan unit = one root; **per-root generation + per-root single-scoped sweep** (never shared); §8 multi-root sweep-isolation test. *(§2, §8)*
- **M-B** — **capture `st_dev` now** (same `lstat` as `st_ino`) — completes the `(dev,inode,size,mtime)` move-signature so S8.4 avoids cross-volume false positives / a later migration. Added to schema + `ScannedFile` + `upsert` + signature test. *(§3, §8)*
- **M-C** — the `US-LIB-01` `CASCADE`→`SET NULL` fix is a **backlog docs-only edit; S8.2 changes NO schema for it** (the shipped schema is already correct). Done separately from S8.2's code scope.
- **M-D** — SF-4 reads-during-scan is now a **harness gate** (§8), not prose.

**Forward flags (S8.4, recorded):** directory-symlink loops → a visited-inode guard (deferred; empirically confirm `FileManager.enumerator` doesn't traverse dir-symlink cycles — O-4); music-project packages (`.band`/`.logicx`) stay skipped (current behavior). *(`st_dev` is no longer deferred — captured in S8.2 per M-B.)*

---

## 10. Verification / Definition-of-Done

- `swift run VerifyLibraryStore` exits 0 — the existing 13 checks **plus** the S8.2 scan cases (§8) all PASS; FS-5 reconciliation + signature-vs-`lstat` (incl. `dev`) + cancellation-partial-safety + **multi-root sweep-isolation (M-A)** + **reads-during-scan bound (M-D)** included.
- No regressions: null-test 117/0 (golden master `0xE7267654BA01D315`) + `VerifyAUGraph` green (S8.2 touches no DSP); today's in-memory `loadMusicFolder` playlist + folder monitor behave exactly as before (additive).
- swiftlint `--strict` clean on new `LibraryScan`/harness files; zero force-unwraps.
- `US-LIB-01` backlog erratum applied.
- Architect-reviewer GO; founder sign-off (run `make gate`; optionally scan a real folder + eyeball the DB via `sqlite3`).

---

**Next:** implement **S8.2a** (scanner core + `dev` signature) → gate → commit → **S8.2b** (re-scan/sweep + reject-nested + progress/cancel + real-tree harness incl. multi-root + reads-during-scan) → gate → commit → then **S8.3** (metadata + embedded-art extraction).
