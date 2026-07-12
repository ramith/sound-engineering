# S8.1 — Persistent Library-Store Foundation (Design)

**Document ID:** S8.1-DESIGN-002
**Status:** DESIGN — architect-reviewer verdict **GO-WITH-CHANGES**; this revision applies M1–M7. For founder sign-off before implementation.
**Chunk of:** S8 (library spine) — see [sprint-plan.md](sprint-plan.md) §3 (critical path S6✅ → S7✅ → **S8** → S9 → S10 → R1).
**Authored by:** team — business-analyst (scope/stories), swift-expert (schema/DAO/concurrency), qa-expert (tests), architect-reviewer (verdict), synthesized by the orchestrator.
**Decisions locked by founder (2026-07-02):**
- Persistence stack = **system SQLite via a thin Swift wrapper** (`import SQLite3`, **zero external SwiftPM deps**; matches the CoreAudio/Accelerate system-lib idiom + vendored-libebur128 / dlopen-FFmpeg precedent). GRDB/SQLite.swift rejected (would be the first external SPM dep + the same toolchain-skew class that broke `swift test`).
>     **⚠️ SUPERSEDED (2026-07, PR #47) — this storage-engine decision was later REVERSED.** `LibraryStore` was rebuilt on **GRDB.swift**: `public final class LibraryStore: Sendable` over a GRDB `DatabaseWriter`, with `DatabaseMigrator` + `eraseDatabaseOnSchemaChange` in place of the hand-rolled runner. GRDB is now the first (and only) external SwiftPM dependency. *Why the reversal:* the hand-rolled wrapper's migration + concurrency surface cost more than the zero-dep purity bought; GRDB's writer-serialized transactions and migrator subsume both. **The identity model, FS-as-cache, and `ON DELETE SET NULL` decisions below all remain in force — only the storage engine changed.** Current truth = `Sources/LibraryStore/` + `Package.swift`.
- **Identity model** (see §2): `tracks.id` (stable integer) = durable reference identity; `tracks.url` (UNIQUE) = mutable scan-upsert natural key.
- The store is a **rebuildable cache of filesystem state, never assumed consistent with it** (§2a — the FS can change while the app runs or while it's closed).
- **S8.1 split CONFIRMED** → S8.1a (~7 SP store/schema/migration/harness) + S8.1b (~6 SP DAO/tests).
- **Distribution = Developer-ID, NOT sandboxed** → scan-folder roots persist as plain absolute paths; `folders.bookmark` stays reserved-unused.
- **Removing a scan folder KEEPS its tracks as loose** (`folder_id → NULL`), preserving playlist memberships; `removeRoot` deletes only the now-loose tracks no playlist references → schema uses `ON DELETE SET NULL` (not cascade).
- **External (Finder) file moves are FOLLOWED** (not remove+add) → a moved file keeps its `tracks.id` + memberships. Match signature = `inode` + `(size, mtime)`, **populated in S8.2** (load-bearing now), matched in S8.4 (orphan + new-path with same signature → `moveTrack`); `content_hash` remains a later robustness upgrade.

> **v002 changes:** applied architect must-fixes M1 (album NULL-dedup), M2 (classify semantics — doc), M3 (Makefile gate accuracy), M4 (SP split → S8.1a/S8.1b), M5 (`folder_id` nullable — loose files), M6 (`moveTrack` op), M7 (lock the `tracks.id`-keyed playlist contract; playlist tables deferred). Added the **use-case coverage** map (§1a) and the **filesystem-divergence** principle + tests (§2a, §6-F) per founder direction.

---

## 1. Scope

S8.1 builds **only the store foundation**: a SQLite-backed, schema-versioned, queryable, incrementally-updatable library database + its Swift data-access layer + a headless verify harness. **No folder scanning, no metadata extraction, no artwork bytes, no UI** (those are S8.2/S8.3/S8.4/S9). Proven against **synthetic rows**.

**M4 — split into two done-done sub-chunks** (the honest size is ~13 SP; the sprint model caps at 5–10):
- **S8.1a (~7 SP)** — store open/create/close, App-Support location, the `SQLiteConnection` wrapper, WAL + `foreign_keys`/`busy_timeout` pragmas, schema (all §3 DDL), migration runner + corruption/quarantine, and the `VerifyLibraryStore` harness skeleton.
- **S8.1b (~6 SP)** — the DAO: CRUD, upsert (one/batch), `moveTrack`, delete-by-key/by-folder, facet queries, loose-file handling, and the concurrency + FS-divergence test suite.

Each is independently done-done. (Founder: confirm the split, or accept an oversized single S8.1 — the S6 spill precedent exists.)

### 1a. Use-case coverage — how the schema caters to the founder's requirements

| # | Founder requirement | How the design caters |
|---|---|---|
| 1 | Multiple scan folders to play from | `folders` table with multiple `is_root` rows + `addRoot/roots/removeRoot`. |
| 2 | Play a single file NOT in any scan folder | `tracks.folder_id` is **NULLABLE** (M5) — a "loose" track with no folder. |
| 3 | Add a single file to any playlist | Loose track (folder NULL) is a persistent row; playlist references it by `tracks.id`. |
| 4 | Multiple playlists (future); song in many; built-in "current" | Deferred `playlists` + ordered many-to-many `playlist_tracks` (M7), a **pure additive V1→V2 migration**; membership keyed on `tracks.id` (locked now, §8-D7). |
| 5 | Song in ONE scan folder; DUPLICATES in other folders are normal | Track = per-file (per-`url`); `folder_id` is one folder; duplicates = distinct rows (distinct URLs). `content_hash` is non-unique (never collapses dupes). |
| 6 | A song in multiple playlists | `playlist_tracks` is many-to-many (deferred, contract locked). |
| 7 | Drag song(s) folder/playlist → playlist = add a REFERENCE, not a file move | Playlist membership is a `playlist_tracks` row; touches no filesystem. |
| 8 | Drag folder → folder = a filesystem MOVE | `moveTrack(id:newURL:newFolderID:)` (M6): update-in-place, preserving `tracks.id` + playlist memberships + future play-counts. App-initiated moves are known → a named op, not inode-heuristic. |
| 9 | Adding to a playlist ≠ filesystem move | Same as #7 — reference only. |
| 10 | Playlist name user-provided, else "untitled-N" | `playlists.name` (nullable); "untitled-N" is app-level generation (deferred with the tables). |
| 11 | Built-in playlist "current" (the queue) | A seeded `playlists` row `is_builtin=1, name='current'` (deferred with the tables; contract locked). |
| — | **Filesystem changes anytime (app running or closed) must not break us** | §2a: the store is a cache, never assumes FS consistency; reconciled only by scans (S8.2/S8.4); reads never assert FS existence; a missing/changed file fails gracefully at point-of-use and is corrected on next scan. Tested in §6-F. |

### In S8.1 vs. deferred

| In S8.1 | Deferred |
|---|---|
| SQLite store (create/open/close, App-Support location, corruption→quarantine+rebuild) | — |
| Full schema (tracks/albums/artists/genres/folders/artwork/schema_info); metadata columns present-but-NULL | — |
| DAO: upsert (one/batch), **moveTrack**, delete (by-key/by-folder), query-all-under-folder, facet queries, loose-file add/remove | — |
| Stable-id identity + delta signature `(size, mtime, inode)` + `last_seen_scan` generation | S8.4 uses |
| Album/artist/genre/year/folder facets (synthetic fixtures) | S9 uses |
| Artwork **reference** column (content-hash → cache path); no bytes | S8.3 owns extraction/cache/ref_count |
| Schema versioning + forward-migration runner (proven synthetic v0→v1) | S8.2/8.3/8.4/playlists use |
| `swift run VerifyLibraryStore` headless harness | — |
| **`playlists` / `playlist_tracks` tables** — DEFERRED (M7); contract locked in §8-D7, will be the **first real V1→V2 migration** | S10 (queue/playlists) |
| — | S8.2 real scan · S8.3 metadata/art · S8.4 rescan/move reconciliation · S9 UI · S10 queue/playlist DAO+UI |

**Stories (BA):** US-LIB-01..07 (store, schema, keying, delta-upsert, facets+artwork-ref, migration, harness) + **US-LIB-08 moveTrack**, **US-LIB-09 loose-file**. The broader library/playlist use cases are being documented as `EP-LIBRARY`/`EP-PLAYLIST` in [backlog.md](../product/backlog.md).

---

## 2. Identity model (the linchpin — architect-confirmed)

- **`tracks.id` (stable integer) = the durable reference identity.** Everything that points at a track — playlist memberships, future play-counts/ratings — keys off `id`, **never** the URL. A file move or retag never changes `id`, so references survive for free (architect verified: a move-in-place preserved 2 playlist memberships with **zero** membership writes).
- **`tracks.url` (UNIQUE) = the mutable scan-upsert natural key.** Scan upserts key on `url` (`ON CONFLICT(url) DO UPDATE`); `moveTrack` updates `url` in place. `folder_id` plays **no** part in uniqueness (a loose file can later be adopted into a folder via `ON CONFLICT(url) DO UPDATE SET folder_id=…` — one row, verified).

This is what makes loose files, multi-playlist, the queue, and folder→folder moves all reachable as **purely additive** later migrations with zero rework.

### 2a. Filesystem-divergence principle (founder requirement)

**The store is a cache of filesystem state; it is never assumed consistent with the filesystem.** The FS can change **while the app runs** (surfaced by the folder monitor / FSEvents) or **while the app is closed** (unobserved). Therefore:
- The store layer makes **no FS calls and asserts no FS existence** on read — a row may reference a path that has since been deleted, modified, or moved.
- **Reconciliation is by scan only:** S8.2 (initial) and S8.4 (incremental delta) diff the FS against the store using the `(size, mtime, inode)` signature + the `last_seen_scan` generation, then upsert/moveTrack/sweep.
- A missing/changed file is handled **at the point of use** (playback fails gracefully, the UI can flag it) and **corrected on the next scan** — never a crash or store corruption.
- The store is **rebuildable from the filesystem** (the files are the source of truth) — so even total store loss/corruption is recovered by quarantine + re-scan (§5).

S8.1 provides the **primitives** that make this robust (classify, upsert, moveTrack, orphan-sweep, stale-row tolerance); S8.4 implements the reconciliation loop. Both are tested (§6-F).

---

## 3. Schema (DDL sketch)

Goals baked in: **cheap delta updates (S8.4)** via `(file_size, mtime, inode)` + `last_seen_scan`; **indexed facets (S9)**; **artwork by reference**; **stable-id identity + nullable folder** (§2).

```sql
CREATE TABLE schema_info (               -- version + provenance (mirrors EQ versioned-key discipline)
    id INTEGER PRIMARY KEY CHECK (id = 1),
    version INTEGER NOT NULL, app_build TEXT,
    created_at INTEGER NOT NULL, migrated_at INTEGER NOT NULL);
-- PRAGMA user_version set to the same value (the cheap gate read at open).

CREATE TABLE folders (
    id INTEGER PRIMARY KEY,
    parent_id INTEGER REFERENCES folders(id) ON DELETE CASCADE,   -- NULL = scan root
    path TEXT NOT NULL, is_root INTEGER NOT NULL DEFAULT 0,
    bookmark BLOB,                        -- security-scoped bookmark for roots (sandbox-ready; used S8.2+)
    last_scanned INTEGER, UNIQUE(path));
CREATE INDEX idx_folders_parent ON folders(parent_id);

CREATE TABLE artists (id INTEGER PRIMARY KEY, name TEXT NOT NULL, sort_name TEXT, UNIQUE(name));

-- M1 FIX: album natural key must be TOTAL so NULL album-artist/year don't fragment the album grid.
-- album_artist_id defaults to 0 (a reserved "unknown artist" sentinel row seeded at migration),
-- year defaults to 0 ("unknown"); album resolution is a query-then-insert on (title, album_artist_id, year)
-- with these non-NULL defaults, so two untagged "Greatest Hits" collapse to ONE album, not N.
CREATE TABLE albums (
    id INTEGER PRIMARY KEY, title TEXT NOT NULL,
    album_artist_id INTEGER NOT NULL DEFAULT 0 REFERENCES artists(id) ON DELETE SET DEFAULT,
    year INTEGER NOT NULL DEFAULT 0,
    artwork_key TEXT REFERENCES artwork(content_hash) ON DELETE SET NULL,
    UNIQUE(title, album_artist_id, year));
CREATE INDEX idx_albums_artist ON albums(album_artist_id);
CREATE INDEX idx_albums_year   ON albums(year);

CREATE TABLE genres (id INTEGER PRIMARY KEY, name TEXT NOT NULL, UNIQUE(name));

CREATE TABLE tracks (
    id INTEGER PRIMARY KEY,               -- STABLE durable reference identity (§2) — never changes on move/retag
    url TEXT NOT NULL,                     -- absolute file URL = mutable natural key; UNIQUE; updated by moveTrack
    folder_id INTEGER REFERENCES folders(id) ON DELETE SET NULL,  -- M5 NULLABLE (loose file); SET NULL so removing a folder KEEPS its tracks as loose (preserves playlist membership); removeRoot then deletes only unreferenced
    relative_path TEXT NOT NULL DEFAULT '', name TEXT NOT NULL, format TEXT NOT NULL,
    -- delta signature (S8.4). M2: mtime is WHOLE SECONDS (accept the same-second-edit blind spot).
    -- inode + (size,mtime) = the EXTERNAL-MOVE match signature (founder: FOLLOW Finder moves) — POPULATED in S8.2,
    -- matched in S8.4 (orphan + new-path, same signature → moveTrack). Volume-local, so match is scoped per volume.
    file_size INTEGER NOT NULL, mtime INTEGER NOT NULL, inode INTEGER, content_hash TEXT,  -- hash NULL in S8.1/8.2
    -- metadata (columns exist now; populated S8.3 — NULL/0 until then):
    album_id INTEGER REFERENCES albums(id) ON DELETE SET NULL,
    artist_id INTEGER REFERENCES artists(id) ON DELETE SET NULL,
    title TEXT, track_no INTEGER, disc_no INTEGER, year INTEGER,
    duration_ms INTEGER NOT NULL DEFAULT 0, sample_rate INTEGER, bit_depth INTEGER, channels INTEGER,
    artwork_key TEXT REFERENCES artwork(content_hash) ON DELETE SET NULL,
    date_added INTEGER NOT NULL,
    last_seen_scan INTEGER NOT NULL DEFAULT 0,   -- scan generation for orphan sweep; meaningless for loose tracks
    UNIQUE(url));
CREATE INDEX idx_tracks_folder ON tracks(folder_id);
CREATE INDEX idx_tracks_album  ON tracks(album_id);
CREATE INDEX idx_tracks_artist ON tracks(artist_id);
CREATE INDEX idx_tracks_year   ON tracks(year);
CREATE INDEX idx_tracks_added  ON tracks(date_added);
CREATE INDEX idx_tracks_lastseen ON tracks(last_seen_scan);        -- orphan sweep: WHERE folder_id IN(:roots) AND last_seen_scan < :gen
CREATE INDEX idx_tracks_album_order ON tracks(album_id, disc_no, track_no);

CREATE TABLE track_genres (
    track_id INTEGER NOT NULL REFERENCES tracks(id) ON DELETE CASCADE,
    genre_id INTEGER NOT NULL REFERENCES genres(id) ON DELETE CASCADE,
    PRIMARY KEY (track_id, genre_id));
CREATE INDEX idx_trackgenres_genre ON track_genres(genre_id);

CREATE TABLE artwork (                    -- BLOBS LIVE IN THE ON-DISK CACHE (S8.3), NOT HERE
    content_hash TEXT PRIMARY KEY, cache_path TEXT NOT NULL,
    width INTEGER, height INTEGER, byte_size INTEGER,
    ref_count INTEGER NOT NULL DEFAULT 0);   -- maintained by S8.3 (provisioned-unused in S8.1/8.2)

-- DEFERRED (M7) — the first real V1→V2 migration will add, with membership keyed on tracks.id:
--   playlists(id, name, is_builtin, position, created_at)      -- built-in 'current' seeded is_builtin=1
--   playlist_tracks(id, playlist_id→playlists.id, track_id→tracks.id, position, added_at)  -- ordered M:N
```

Notes: `PRAGMA foreign_keys=ON` + `busy_timeout` + `journal_mode=WAL` at every open. **M5** `folder_id` nullable — architect-verified safe: the orphan sweep is folder-scoped (`IN(:roots)` excludes NULL → loose tracks never swept) and `removeRoot` cascade only hits that root's tracks (loose tracks survive). **M1** album key is now total (non-NULL defaults + query-then-insert resolution) so untagged albums don't fragment the S9 grid. Metadata columns present ⇒ **no S8.1→S8.3 migration**.

---

## 4. Data-access layer — a `LibraryStore` actor

New SwiftPM **library target** `LibraryStore` (system `SQLite3` + `Foundation` only), linked by both the app and the harness (à la `AudioFormatKit`). An **`actor`** — single writer + concurrent readers off the main actor; only `Sendable` value types cross (`LibraryTrack`, `ScannedFile`, facets) — no `sqlite3*` handle escapes. Representative API:

```swift
public actor LibraryStore {
    public init(url: URL) async throws                     // open/create + migrate; quarantine+rebuild on corruption
    public static func defaultStoreURL() throws -> URL     // <App Support>/AdaptiveSound/library.sqlite3
    public func schemaVersion() -> Int

    // reads (facets for S9) — NEVER assert filesystem existence (§2a)
    public func allTracks(sortedBy: TrackSort) throws -> [LibraryTrack]
    public func track(url: URL) throws -> LibraryTrack?
    public func tracks(inFolder: Int64) throws -> [LibraryTrack]
    public func albums(sortedBy: FacetSort) throws -> [AlbumFacet]
    public func artists(sortedBy: FacetSort) throws -> [ArtistFacet]
    public func genres() throws -> [GenreFacet]

    // folder roots
    public func addRoot(_ url: URL, bookmark: Data?) throws -> Int64
    public func roots() throws -> [LibraryFolder]
    public func removeRoot(id: Int64) throws               // KEEP playlist-referenced tracks as loose (folder→NULL); delete only unreferenced

    // writes (single writer; S8.2/8.4 consume)
    public func beginScanGeneration() throws -> Int64
    public func classify(_ file: ScannedFile) throws -> TrackDelta          // new/modified(unchanged) from (size,mtime)
    public func upsert(_ files: [ScannedFile], folderID: Int64?, generation: Int64) throws -> [Int64]  // ONE txn; folderID nil = loose
    public func moveTrack(id: Int64, newURL: URL, newFolderID: Int64?, newRelativePath: String) throws  // M6: in-place; preserves id + memberships; newRelativePath is relative to the NEW root (loose move → ""); typed conflict on UNIQUE(url)
    public func sweepOrphans(inFolders: [Int64], olderThan: Int64) throws -> Int
    public func addLooseFile(_ file: ScannedFile) throws -> Int64            // loose track (folder_id NULL)
    public func delete(id: Int64) throws

    // metadata write path (S8.3 fills)
    public func applyMetadata(_ meta: TrackMetadata, forTrack: Int64) throws
    public func linkArtwork(contentHash: String, cachePath: String, size: CGSize, byteSize: Int64) throws

    public func integrityCheck() throws -> Bool            // PRAGMA integrity_check
}
```

**M6 — `moveTrack` contract:** it is DISTINCT from `upsert` (upsert keys on URL and would create a *new* row for the new path, losing memberships — the exact bug the identity model prevents). `moveTrack` does `UPDATE tracks SET url=?, folder_id=?, relative_path=? WHERE id=?`, preserving `id` + all references. Moving onto a path that already has a row (`UNIQUE(url)` collision — e.g., a duplicate) returns a **typed conflict** (same handling as the upsert unique-conflict). The VM consumes the store via `await` exactly like today's off-main `loadMusicFolder` (`Task.detached` + atomic main-actor swap).

---

## 5. Concurrency, migration, corruption

- **WAL** (`journal_mode=WAL`, `synchronous=NORMAL`, `busy_timeout` set — O2): readers see the last committed snapshot concurrently with a writer. **Single writer connection**, actor-isolated (single-writer by construction), batch = one `BEGIN IMMEDIATE…COMMIT`. Reads go through the actor (fine at library scale); a separate `SQLITE_OPEN_READONLY` connection is the **measured-only** escape hatch (trigger: harness stress shows reader latency > target under checkpoint).
- **Migration:** `PRAGMA user_version` gate + a linear `switch` of `migrateV{n}toV{n+1}` steps in one transaction. S8.1 ships **v1** (create-all + seed the "unknown artist" sentinel `artists(id=0)` for the M1 album key). Metadata columns already exist ⇒ S8.2/S8.3 add no migration. **The first real V1→V2 migration is the deferred `playlists`+`playlist_tracks` tables (M7)** — good, it exercises the runner against real (not synthetic) DDL.
- **Corruption / first-run** (the library is a *rebuildable cache*, files are truth — §2a): missing → create+migrate (empty). Corrupt / `integrity_check` fail / newer-than-app version → **quarantine** (rename `library.corrupt-<ts>.sqlite3` **plus its `-wal`/`-shm` sidecars atomically** — O1) + create fresh; next scan repopulates. Never crash, never silently delete.

---

## 6. Test harness + cases

**M3 — accurate gate wiring:** the repo has **no `make gate`/`make library-store-verify` targets today** (the null test is a bare `bash scripts/build-null-test.sh`; `VerifyAUGraph` is `swift run VerifyAUGraph`). This design **adds** `make library-store-verify` (`swift run VerifyLibraryStore`) and a **new** `make gate` wrapping the three commands (`build-null-test.sh` && `swift run VerifyAUGraph` && `swift run VerifyLibraryStore`) — stated as new additions, plus a new "Gate 5" line in [validation-strategy.md](../architecture/validation-strategy.md) and a README note. **Not** in the (fast, lint-only) pre-commit hook; a required pre-merge manual gate like the C++ null test. DSP golden master `0xE7267654BA01D315` untouched.

**Vehicle:** `swift run VerifyLibraryStore` — headless, `VerifyAUGraph` idiom (`fail(_) -> Never { print(...); exit(1) }`, numbered PASS/FAIL, `exit(0)` all-pass), real `LibraryStore` code, temp DBs under `test-data/` (never `/tmp`), unique-named, kept-on-failure.

**Cases:**
- **A. Schema/migration:** fresh-create at v1; first-run idempotency; synthetic v0→v1 preserving data; transactional (all-or-nothing) migration; **corrupt file → quarantine (with live `-wal`/`-shm` present, O1) + rebuild, no crash**; downgrade guard (newer version).
- **B. CRUD/integrity:** round-trip insert/read/update/delete; `UNIQUE(url)` typed conflict; FK integrity with `foreign_keys=ON` verified set; cascade/RESTRICT policy asserted; **M1 — album dedup with NULL/default facets**: two untagged `('Greatest Hits', 0, 0)` collapse to ONE album (fixture includes the all-default-facet album).
- **C. Facets:** album/artist/genre/year/**folder with a real path-boundary check** (`/Music/Rock` ≠ `/Music/RockAndRoll`); empty-result cleanliness; **counts asserted against computed fixture expectations** (catches JOIN fan-out).
- **D. Concurrency:** `journal_mode=wal` + `busy_timeout` verified set; concurrent readers; single-writer + concurrent-readers **snapshot isolation** (a read result ∈ {pre,post}, never torn); `SQLITE_BUSY` handled; a bounded **N-writes ‖ M-reads stress loop** ending in **`PRAGMA integrity_check=ok`** + a row-count ledger; reader survives a writer's mid-txn abort (WAL replay).
- **E. Idempotency + identity:** re-upsert identical row = one row, no spurious `mtime` bump; changed-field upsert updates in place; batch idempotency; **M2 — per-signature-field classify**: an `mtime`-only change AND a `size`-only change each independently yield `.modified`; **M6 — `moveTrack` identity invariant**: after a move-in-place, `tracks.id` is unchanged and (once playlists exist) memberships are preserved with zero membership writes — in S8.1, assert `id` stable + `url`/`folder_id` updated + a synthetic reference row (a stand-in `playlist_tracks`-shaped fixture) still resolves.
- **F. Filesystem divergence (FOUNDER REQUIREMENT — must be in the plan):**
  - **FS-1 (S8.1):** a track row whose `url` points at a **non-existent / changed** path is still queryable/readable — the store performs **no FS check** on read and never crashes. (Proves the store tolerates a FS that diverged while the app was closed or running.)
  - **FS-2 (S8.1):** the delta primitives are correct — a known path with changed `(size|mtime)` → `.modified`; an unseen path → `.new`; a known path **absent** from a scan generation is detectable as an orphan (`last_seen_scan < gen`). These are exactly what S8.4 uses to reconcile divergence.
  - **FS-3 (S8.1):** `moveTrack` + loose-file adoption (`ON CONFLICT(url) DO UPDATE`) leave exactly one row (a file relocated/re-added under a scan root while the app was closed doesn't duplicate).
  - **FS-4 (S8.1):** loose track (folder NULL) **survives** an orphan sweep of an unrelated root AND `removeRoot` of an unrelated root (architect-verified invariants).
  - **FS-5 (flag → S8.4 test plan, required there):** full reconciliation of real FS mutations made **while the app is closed** AND **while it's running** (add/remove/modify/move/rename over a fixture tree → correct deltas via rescan + FSEvents). Belongs to S8.4; noted here so it is not lost and is an explicit S8.4 acceptance criterion.

**Fixtures:** synthetic — a `seedFixtureLibrary` generator (3 artists × 2 albums + a "Various Artists" comp + **an all-default-facet untagged album**, ~25–30 tracks, 2 years, 3 overlapping genres, the confusable `Rock`/`RockAndRoll` folders, **at least one loose file (folder NULL)**) returning `FixtureExpectations` (computed counts). Corrupt/legacy-DB fixtures generated inline (git-ignored).

---

## 7. Integration (purely additive)

Nothing removed; the running app stays byte-identical. `AudioFile`/`AudioFileEnumerator` unchanged (in S8.2 the enumerator becomes the *producer* feeding `ScannedFile`s into `upsert`). `LibraryTrack` is a superset of `AudioFile` (same `url`, `name`, `relativePath`, `format`, duration). `AudioViewModel` gains `private let store: LibraryStore` + an unused-by-UI `var libraryTracks` for the future store-backed browse; the live playlist still comes from `loadMusicFolder` until S8.2/S9. Folder monitor unchanged in S8.1. Establishes `<App Support>/AdaptiveSound/` (sandbox-neutral — App Support is inside the container either way; only root *bookmarks* depend on the sandbox posture, which is S8.2 — O4/D5).

---

## 8. Decisions

| # | Decision | Resolution |
|---|---|---|
| **Identity** | Durable identity vs. natural key | **LOCKED**: `tracks.id` (stable int) = reference identity; `tracks.url` (UNIQUE) = mutable scan key. Playlists/play-counts key off `id`. |
| **FS-divergence** | Store vs. filesystem consistency | **LOCKED (§2a)**: store is a rebuildable cache, never assumes FS consistency; reconciled only by scan; reads never assert FS existence; graceful at point-of-use. Tested §6-F. |
| **D7 (M7)** | Playlists model | **DEFER tables** to the first V1→V2 migration (S10 territory); **LOCK** the `tracks.id`-keyed, ordered many-to-many membership contract + built-in "current" now, so it stays a pure additive migration. |
| **M4** | S8.1 size (~13 SP vs. 5–10 ceiling) | ✅ **CONFIRMED: split** S8.1a (~7) / S8.1b (~6) (§1). |
| D1 | File-move tracking | **`moveTrack` (M6)** for app-initiated moves; **external (Finder) moves are FOLLOWED** (founder) — `inode`+`(size,mtime)` signature populated in S8.2, matched in S8.4 → `moveTrack`. Preserves id + memberships. |
| **Remove folder** | Tracks in playlists when a scan folder is removed | ✅ **Keep as loose** — `folder_id`→NULL (`ON DELETE SET NULL`); `removeRoot` deletes only unreferenced tracks. Playlist memberships survive. |
| D2 | Corrupt store | Quarantine (+ `-wal`/`-shm`) + rebuild from disk. |
| D3 | Exact-dup detection | Defer; `content_hash` reserved, non-unique; duplicates across folders are normal (Req 5). |
| D4 | Multi-artist "feat." | Single track-artist + album-artist for R1; `track_artists` join is a clean later migration. |
| D5 | **Sandbox posture** (App Store vs Developer-ID) | ✅ **CONFIRMED: Developer-ID, not sandboxed.** Roots persist as plain absolute paths; `folders.bookmark` reserved-unused. |

---

## 9. Verification / Definition-of-Done

- `swift run VerifyLibraryStore` exits 0 — cases A–F all PASS; every stress case ends `PRAGMA integrity_check=ok`; concurrency timeouts = FAIL (deadlock), never skipped; **FS-divergence cases (§6-F) included**.
- Store survives process restart (harness two-invocation durability check).
- No regressions: `bash scripts/build-null-test.sh` (117/0, golden master `0xE7267654BA01D315`) + `swift run VerifyAUGraph` green (S8.1 touches no DSP); playback/EQ-persistence/folder-monitor behavior unchanged.
- `swiftlint`/`clang-format` clean; new `LibraryStore`/`VerifyLibraryStore` Swift files lint clean.
- Gate wiring added accurately (M3): `make library-store-verify` + `make gate` (new), README + validation-strategy "Gate 5".
- Docs: architecture.md notes the store exists (location + schema version + the cache/FS-divergence posture); backlog gains `EP-LIBRARY`/`EP-PLAYLIST` + US-LIB-01..09.
- Architect-reviewer GO (this revision applies M1–M7); founder sign-off (runs the harness + eyeballs the DB via `sqlite3` CLI).

---

## 10. Post-implementation review (2026-07-02) — tracked debt

S8.1a+b shipped and were independently reviewed (architect-reviewer: **GO-WITH-CHANGES**, no blockers; refactoring-specialist: 1 reproduced blocker + should-fixes). **Fixed in a follow-up pass:** `moveTrack` relative_path staleness on cross-folder moves (added `newRelativePath`); `date_added` now a real epoch (was the scan-generation counter → wrong "Recently Added"); `SQLITE_OPEN_FULLMUTEX` + a synchronous-only invariant comment; race-safe `resolveArtist/Genre/Album` (`ON CONFLICT DO NOTHING` + re-select); minor hardening.

**Deferred as tracked debt:**
- **SF-2 — facet-orphan sweep → S8.4 ACCEPTANCE ITEM.** `moveTrack`/rescan churn will leave zero-track `albums`/`artists`/`genres` rows (ghost empty albums in S9). No churn exists yet, so deferred — but **S8.4 must add `sweepOrphanFacets()`** (delete facet rows with no referencing track) as an acceptance criterion, or S9 browse shows phantoms.
- **SF-4 — all reads serialize through the writer actor → R1 DEBT for S9.** Acceptable for R1 (batched writes, library scale), but a long S8.2/S8.4 scan makes an S9 browse queue behind write batches (WAL MVCC discarded by the single isolation domain). Seam marked in `LibraryStore+Reads.swift`: if browse jank appears, add a `SQLITE_OPEN_READONLY` read connection. Revisit at S9 with a measurement trigger.
- **Minor notes:** two concurrent `LibraryStore(url:)` on a corrupt file race the quarantine rename (unlikely — single instance today); the harness "path-boundary" check proves distinct-folder-id separation, NOT string-prefix matching — the S8.2 scanner author must validate real `path`-prefix logic when it introduces one.

---

**Next:** **S8.2** — folder scan → store (populating the `(inode, size, mtime)` move-signature), its own design → architect vet → implement → gate cycle.
