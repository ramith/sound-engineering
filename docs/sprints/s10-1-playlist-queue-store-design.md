# S10.1 — Playlist/queue persistence spine (design)

**Document ID:** S10.1-DESIGN-001
**Status:** DESIGN — team-vetted (BA · swift-expert · qa-expert) + **architect + the-fool gate: GO-WITH-CHANGES** (must-fixes folded in below). **Pending founder brainstorm + sign-off BEFORE implementation** (§0). Then implement → founder bug-fix + manual test → retro.
**Sprint:** S10.1, first of the S10 series — see [s10-queue-playlists-macos-plan.md](s10-queue-playlists-macos-plan.md) + [sprint-plan.md](sprint-plan.md).
**Authored by:** AdaptiveSound team — business-analyst (scope/stories), swift-expert (schema/DAO/concurrency/migration), qa-expert (headless gate), architect-reviewer + the-fool (gate verdict), synthesized by the orchestrator.
**Builds on:** the shipped GRDB-backed `LibraryStore` (S8). Current code anchors cited throughout.

---

## 0. Decisions needing the founder (brainstorm these before code)

**Two are load-bearing (1 + 2); the rest are micro-defaults you can rubber-stamp or overrule.**

1. **⭐ Persistence durability — narrows the delete-rebuild policy.** Playlists are **user-authored data that cannot be rebuilt from the filesystem** — unlike the track/album cache. The store today uses GRDB `eraseDatabaseOnSchemaChange = true` (drop-and-recreate on any schema change), fine for "a rebuildable cache of on-disk files" but wrong for playlists: it would **erase** them on a schema-edit, and worse, a rebuild **reassigns `tracks.id` in scan order** so `playlist_entries.track_id` would point at the **wrong song** — silent corruption. **Recommendation (revised after the gate): set `eraseDatabaseOnSchemaChange = false` *uniformly* (dev + release) and add a one-command `make reset-db`** to replace the automatic wipe in your dev loop. *(The gate showed a DEBUG-only-erase gate would let an accidental edit to a shipped migration pass green in dev but silently no-op / corrupt in release — the uniform-false option removes that dev-vs-release divergence and makes the CI gate exercise the real posture.)* Playlist tables ship as a **real additive `v3-playlists` migration**; new rule **never edit a migration that already shipped** — enforced by a migration-immutability check in the gate (§6), not by discipline alone. → This **narrows [delete-rebuild-dev-db]** from "auto-wipe always" to "manual `make reset-db` in dev; durable in release," so it needs your OK. *(Rejected: DEBUG-only erase — divergence risk; JSON export or a separate playlist DB — neither fixes the `tracks.id`-churn corruption.)*
2. **⭐ `sweepOrphans` on a file gone from disk — spare, or drop?** *(Gate's top catch.)* Closing Gate-1 protects the **rare** explicit "remove folder" path. But `sweepOrphans` runs at the end of **every scan**; a partially-reachable root (flaky mount, one album deleted, permission glitch) passes the empty-walk guard and, with `ON DELETE CASCADE`, would **silently drop the playlist entries** of any unseen track. **Recommendation: SPARE** — a playlist-referenced track whose file vanished is kept as a *loose* row (its entries survive), and a later rescan re-adopts it by URL with its `id` intact (the identity-model payoff). This uses the **same** `NOT IN (SELECT track_id FROM playlist_entries)` filter as Gate-1, so it's near-zero extra work → **fold it into S10.1** (don't defer). *(Alt: drop-on-CASCADE — simpler, but silent irreversible loss on a frequent path; not recommended for an R1 that ships playlists.)*
3. **Queue = the built-in "current" playlist?** Confirm the play queue is literally the `is_builtin=1` "current" row (so reorder/clear/play-next map to `playlist_entries`). **Ship the v3 tables now but seed the builtin lazily at S10.2** (via `bootstrapBuiltinCurrentPlaylist()`), not in the migration — so we don't commit an unvalidated queue model to an unshippable-to-edit artifact before S10.2 validates it.
4. **Micro-decisions (recommended defaults; overrule freely):**
   - **Duplicate playlist name** → `UNIQUE(name) WHERE is_builtin=0` + reject with a typed error; UI (S10.3) chooses auto-suffix vs. inline "name taken". *(Alt: allow duplicates like Apple Music — drop it.)*
   - **`untitled-N`** → lowest-unused N (1,2,3; delete 2 → next is 2). *(Alt: monotonic counter.)*

---

## 1. Scope

**S10.1 = the persistence spine only** — schema + DAO + the Gate-1 fix, proven against synthetic rows via `VerifyLibraryStore`. **No UI.**

| In S10.1 | Deferred |
|---|---|
| `playlists` + `playlist_entries` tables (schema v3, migration) | Queue UX (reorder/play-next/history view) → **S10.2** |
| DAO: create/rename/delete, ordered add/insert/remove/reorder, loose-file add | Playlist browse/edit UI, drag-to-playlist, M3U → **S10.3** |
| Built-in non-deletable **"current"** playlist (store side) | Media keys / Now-Playing → **S10.4** |
| `untitled-N` naming; duplicate-name handling | — |
| **Closes Gate 1 (SEQ-1)** — `removeRoot` **and** `sweepOrphans` both spare playlist-referenced tracks (§0.2 — the symmetric fix) | — |
| **Durability**: additive v3 migration + `eraseDatabaseOnSchemaChange=false` (uniform) + `make reset-db`; a migration-immutability guard in the gate | — |
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
    track_id    INTEGER NOT NULL REFERENCES tracks(id)    ON DELETE CASCADE,  -- §0.3
    position    INTEGER NOT NULL,             -- ordering key, not required contiguous
    added_at    INTEGER NOT NULL);

CREATE INDEX idx_playlist_entries_playlist ON playlist_entries(playlist_id, position);
CREATE INDEX idx_playlist_entries_track    ON playlist_entries(track_id);
```

Migration mirrors the shipped v1→v2 FTS migration (`Schema.swift:262-282`): bump `currentSchemaVersion = 3`, add `MigrationID.v3`, add `"playlists"`/`"playlist_entries"` to `expectedTables`, `createV3Statements`, `migrateV2toV3` — **structural only (tables + indexes, no seed)**; the builtin `current` is seeded lazily by `bootstrapBuiltinCurrentPlaylist()` at S10.2 (§0.3), so the migration commits no unvalidated queue semantics. Additive → **no erase, existing `tracks.id` preserved** (GRDB only erases when an *already-applied* migration's body changes, not when a new one is added). Alongside this, `makeMigrator` sets `eraseDatabaseOnSchemaChange = false` (uniform — §0.1). `position` is a non-contiguous ordering key (append = `MAX(position)+1`; reorder renormalizes to dense `0..n-1` in one txn; no `UNIQUE(playlist_id,position)` so transient reorder collisions don't fail).

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

**Symmetric fix — `sweepOrphans` (§0.2, the gate's top catch):** the *same* filter goes on the per-scan orphan sweep (`LibraryStore+DAO.swift:258-272`, fired every scan by `LibraryScanner.swift:102`) — `DELETE … WHERE <orphan> AND id NOT IN (SELECT track_id FROM playlist_entries)` — so a partially-reachable rescan spares playlist-referenced tracks (kept as loose, re-adopted by URL on a later scan) instead of silently CASCADE-dropping their entries. Without this, Gate-1 only plugs the rare explicit path and leaves the frequent automatic one open.

Flip known-issues SEQ-1 **Gate 1 → CLOSED** and correct the SQL wording to `playlist_entries`.

## 6. Tests / gate (qa) — new `VerifyLibraryStore` checks

`pl-*` checks mirroring the existing `ChecksMoveMatch`/`ChecksCRUD` idiom (`Bool`-returning, registered via `playlistSpineCheckCases()` in `main.swift`, real `LibraryStore`, temp DBs under `test-data/`): CRUD; built-in "current" rename/delete rejected; ordered membership + **same-track-twice**; insert/remove/**reorder** — asserting the resulting **`ORDER BY position` sequence** (not a literal contiguous 0..n-1 vector — positions are a non-contiguous ordering key, §3); loose-file add; `untitled-N` lowest-unused; duplicate-name collision; **zero FS side-effects**; **Gate-1 keep + inverse-sweep pair** (`pl-gate1-referenced-track-kept` + `pl-gate1-unreferenced-track-swept`); **`pl-sweep-referenced-track-kept`** (the §0.2 symmetric fix — a referenced track unseen in a partial rescan is spared, not CASCADE-dropped); multi-playlist reference; **restart durability across a real process boundary** (`--restart-write-playlists`/`--restart-read-playlists` — guards §0.1: playlists survive quit/relaunch, and the additive v2→v3 migration preserves `tracks.id`); **migration-immutability guard** (fingerprint each shipped migration's DDL + id; fail if a shipped migration body changes — the machine enforcement of "never edit a shipped migration"); **US-PLIST-08 seam** (membership survives a folder→folder move — store-provable now that S8.4 shipped, ties `LibraryStore+MoveMatch` to real `playlist_entries`).

**Manual testing (founder, later):** playlist create/reorder/queue by hand + quit-relaunch durability — reserved for after S10.2/S10.3 wire the UI.

## 7. Definition of Done

`make gate` (C++ null-test + `VerifyAUGraph` + `VerifyLibraryStore` incl. all `pl-*`) green + `make strict-gate`; no S8/DSP regressions; SEQ-1 Gate 1 flipped to CLOSED; `playlist_entries` naming reconciled across code + docs. (No coverage-% theater — the gate is the harness.)
