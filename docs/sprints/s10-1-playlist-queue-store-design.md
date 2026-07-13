# S10.1 — Playlist/queue persistence spine (design)

**Document ID:** S10.1-DESIGN-001
**Status:** DESIGN — team-vetted + architect/the-fool gate + **founder brainstorm 2026-07-13: decisions LOCKED (§0). Ready to implement.** Then → founder bug-fix + manual test → retro.
**Sprint:** S10.1, first of the S10 series — see [s10-queue-playlists-macos-plan.md](s10-queue-playlists-macos-plan.md) + [sprint-plan.md](sprint-plan.md).
**Authored by:** AdaptiveSound team — business-analyst (scope/stories), swift-expert (schema/DAO/concurrency/migration), qa-expert (headless gate), architect-reviewer + the-fool (gate verdict), synthesized by the orchestrator.
**Builds on:** the shipped GRDB-backed `LibraryStore` (S8). Current code anchors cited throughout.

---

## 0. Decisions (founder brainstorm, 2026-07-13) — LOCKED

1. **Durability = keep it simple, deferred.** Leave `eraseDatabaseOnSchemaChange = true` as-is. Pre-first-release, a schema change just drops-and-recreates the DB (playlists included) — accepted; no real users yet. **No** additive-migration discipline, **no** `make reset-db`, **no** migration-immutability guard in S10.1. Real playlist durability (survive a schema change without corruption — the `tracks.id`-churn issue the gate flagged) is a **deferred item to revisit before R1 ships to users** — tracked as a new known-issue, NOT built now.
2. **A file gone from disk → removed from playlists** (`track_id ON DELETE CASCADE`; the per-scan `sweepOrphans` simply drops it — no playlist-spare filter on the sweep). *Distinct from removing a scan **folder***, which still keeps its tracks as loose per the locked EP-LIBRARY rule (Gate-1, §5).
3. **The play queue IS the built-in `is_builtin=1` "current" playlist** — seeded in the v3 migration. (S10.2 builds the queue UX on it.)
4. **Duplicate playlist names prevented** — `UNIQUE(name) WHERE is_builtin=0`; a create/rename to an existing name is rejected with a typed error; the UI (S10.3) decides auto-suffix vs. inline "name taken".
5. **New-playlist default name = Apple-style** — "New Playlist", "New Playlist 2", … (lowest-unused number), which also satisfies (4) since auto-generated names are always unique.

---

## 1. Scope

**S10.1 = the persistence spine only** — schema + DAO + the Gate-1 fix, proven against synthetic rows via `VerifyLibraryStore`. **No UI.**

| In S10.1 | Deferred |
|---|---|
| `playlists` + `playlist_entries` tables (schema v3, migration) | Queue UX (reorder/play-next/history view) → **S10.2** |
| DAO: create/rename/delete, ordered add/insert/remove/reorder, loose-file add | Playlist browse/edit UI, drag-to-playlist, M3U → **S10.3** |
| Built-in non-deletable **"current"** playlist (store side) | Media keys / Now-Playing → **S10.4** |
| `untitled-N` naming; duplicate-name handling | — |
| **Closes Gate 1 (SEQ-1)** — `removeRoot` spares playlist-referenced tracks (kept loose; the locked EP-LIBRARY rule) | Playlist durability across schema change (§0.1) → deferred, new known-issue |
| v3 migration adds the tables + seeds the builtin "current"; `eraseDatabaseOnSchemaChange` stays **true** (durability deferred) | — |
| New `VerifyLibraryStore` playlist checks | — |

Naming: the join table is **`playlist_entries`** (authoritative in the plan + backlog). The stale `playlist_tracks` in `LibraryStore+DAO.swift:347-353`, `known-issues.md` SEQ-1, and the S9 docs get reconciled to `playlist_entries` as part of this sprint. Schema goes **v2 → v3** (FTS5 was v2).

## 2. Stories + acceptance criteria (BA)

- **US-PLIST-01** — many-to-many, user-ordered membership keyed on `tracks.id` (never url); the **same track can appear multiple times** in one playlist (own entry id + `position`).
- **US-PLIST-05** — `untitled-N` lowest-unused naming; duplicate-name collision handled (never two byte-identical names).
- **US-PLIST-06 (store side)** — exactly one built-in `is_builtin=1` "current" playlist; store-layer rejects rename/delete of it defensively (not just UI graying).
- **US-PLIST-07** — many playlists, no artificial limit, indexed (scales to low hundreds).
- **Gate-1 closure (own AC):** removing a scan root must **keep** a track that any playlist references (detached to loose, `folder_id → NULL`); an unreferenced sibling in the same folder is still swept.

**Founder-locked invariants honored:** membership → `tracks.id`; loose-file add sets `folder_id NULL`; playlist add/remove has **zero filesystem side-effects**; referenced tracks survive root removal.

## 3. Schema (DDL — additive v3)

```sql
CREATE TABLE playlists (
    id         INTEGER PRIMARY KEY,
    name       TEXT    NOT NULL,
    is_builtin INTEGER NOT NULL DEFAULT 0,   -- 1 = the non-deletable "current" queue
    created_at INTEGER NOT NULL);
-- Name uniqueness scoped to user playlists so the reserved 'current' can't leak a conflict (§0.4).
CREATE UNIQUE INDEX idx_playlists_name_user ON playlists(name) WHERE is_builtin = 0;

-- At most ONE built-in playlist, as a DB invariant (makes the bootstrap idempotent by construction).
CREATE UNIQUE INDEX idx_playlists_one_builtin ON playlists(is_builtin) WHERE is_builtin = 1;

CREATE TABLE playlist_entries (
    id          INTEGER PRIMARY KEY,          -- OWN identity -> a track can repeat
    playlist_id INTEGER NOT NULL REFERENCES playlists(id) ON DELETE CASCADE,
    track_id    INTEGER NOT NULL REFERENCES tracks(id)    ON DELETE CASCADE,  -- §0.2 (file gone -> drop)
    position    INTEGER NOT NULL,             -- ordering key, not required contiguous
    added_at    INTEGER NOT NULL);

CREATE INDEX idx_playlist_entries_playlist ON playlist_entries(playlist_id, position);
CREATE INDEX idx_playlist_entries_track    ON playlist_entries(track_id);
```

Migration mirrors the shipped v1→v2 FTS migration (`Schema.swift:262-282`): bump `currentSchemaVersion = 3`, add `MigrationID.v3`, add `"playlists"`/`"playlist_entries"` to `expectedTables`, `createV3Statements`, `migrateV2toV3` (create the tables + indexes, then seed the builtin `current` playlist via `INSERT OR IGNORE`, idempotent like `seedSentinelArtist`). `eraseDatabaseOnSchemaChange` **stays `true`** (§0.1 — keep it simple; a pre-R1 schema change drops-and-recreates, playlists included). Adding v3 to a store already at v2 is additive so it won't erase in practice; but we are **not** relying on that for durability — durability is deferred. `position` is a non-contiguous ordering key (append = `MAX(position)+1`; reorder renormalizes to dense `0..n-1` in one txn; no `UNIQUE(playlist_id,position)` so transient reorder collisions don't fail).

## 4. DAO API (new `LibraryStore+Playlists.swift`)

Value types (`Sendable`): `Playlist`, `PlaylistEntry` (own `id`), `LooseAddResult`; typed errors `PlaylistNameConflict`, `PlaylistMutationError.{builtinImmutable,notFound}`.

```
createPlaylist(name:) -> Int64                 // throws PlaylistNameConflict
createUntitledPlaylist() -> Int64              // "untitled-N" lowest-unused
renamePlaylist(id:to:) / deletePlaylist(id:)   // reject is_builtin defensively
playlists() / playlist(id:) / playlistCount() / entries(inPlaylist:)   // reads
bootstrapBuiltinCurrentPlaylist() / currentPlaylistID()   // idempotent
appendEntry / appendEntries / insertEntry(at:) / removeEntry / removeEntries / reorderPlaylist(entryIDsInOrder:)
addLooseFileToPlaylist(_:playlistID:) -> LooseAddResult    // reuses internal upsertOne, folder_id=NULL
```

## 5. Gate-1 fix (SEQ-1)

`unreferencedTrackIDs` (the ⚠️ HARD GATE stub, `LibraryStore+DAO.swift:345-355`) gains the playlist filter; `removeRoot` (`:145-153`) then spares referenced tracks — they detach to loose (`folder_id → NULL`), entries + FTS rows survive:

```swift
let referenced = try Set(Int64.fetchAll(db, sql: "SELECT DISTINCT track_id FROM playlist_entries;"))
return candidates.filter { !referenced.contains($0) }   // candidate ids bound, never spliced
```

**`sweepOrphans` is left as-is (§0.2 — file gone → drop):** the per-scan orphan sweep keeps no playlist filter, so a track whose file genuinely disappeared is CASCADE-dropped from playlists (the founder's call). *Known edge (deferred, note-only):* a **partially**-reachable root (flaky mount) can look like "files gone" to the sweep and drop entries; the existing empty-walk guard (`RootUnreachableError` on `filesSeen==0`) covers the fully-unreachable case but not the partial one — revisit with durability (§0.1) if it bites.

Flip known-issues SEQ-1 **Gate 1 → CLOSED** and correct the SQL wording to `playlist_entries`.

## 6. Tests / gate (qa) — new `VerifyLibraryStore` checks

`pl-*` checks mirroring the existing `ChecksMoveMatch`/`ChecksCRUD` idiom (`Bool`-returning, registered via `playlistSpineCheckCases()` in `main.swift`, real `LibraryStore`, temp DBs under `test-data/`): CRUD; built-in "current" rename/delete rejected; ordered membership + **same-track-twice**; insert/remove/**reorder** — asserting the resulting **`ORDER BY position` sequence** (not a literal contiguous 0..n-1 vector — positions are a non-contiguous ordering key, §3); loose-file add; Apple-style default name + **lowest-unused numbering**; **duplicate-name rejected** (`PlaylistNameConflict`); **zero FS side-effects**; **Gate-1 keep + inverse-sweep pair** (`pl-gate1-referenced-track-kept` — a playlist-referenced track survives `removeRoot` as loose; `pl-gate1-unreferenced-track-swept` — an unreferenced sibling is deleted); **file-gone drop** (`sweepOrphans` CASCADE-drops a referenced track whose file vanished — the §0.2 behavior); multi-playlist reference; basic **persistence across store reopen** (no schema change); **US-PLIST-08 seam** (membership survives a folder→folder move — store-provable now that S8.4 shipped, ties `LibraryStore+MoveMatch` to real `playlist_entries`).

**Manual testing (founder, later):** playlist create/reorder/queue by hand + quit-relaunch durability — reserved for after S10.2/S10.3 wire the UI.

## 7. Definition of Done

`make gate` (C++ null-test + `VerifyAUGraph` + `VerifyLibraryStore` incl. all `pl-*`) green + `make strict-gate`; no S8/DSP regressions; SEQ-1 Gate 1 flipped to CLOSED; `playlist_entries` naming reconciled across code + docs. (No coverage-% theater — the gate is the harness.)
