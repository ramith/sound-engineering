# S10.3 — Playlists UX — design (rev. 3 — research-grounded, scope expanded)

Last R1 gate. Founder expanded scope (2026-07-15, post market research — see [research memo](s10-3-playlists-ux-research.md)) to match category norms: **sidebar Playlists section + folders/nesting + smart (rules-based) playlists + Play/Next/Queue verb set with undo.** Stories: US-PLIST-02, -03, -04, -08 **+ new: playlist folders, smart playlists.** M3U import-export still deprioritized.

> **Re-estimate:** rev.1/2 was ~6 SP (UI over the existing static DAO). Folders + smart playlists are **net-new schema + DAO + UI** — realistically **~15–18 SP**. Recommend delivering as phased chunks (A–H, §8), each independently gated; R1 can gate on the static+folders+IA core (A–E) with smart playlists (F–G) as a fast follow if timeline pressure appears. Flagging, not relitigating — the scope calls are locked.

## 0. Store status
S10.1 built the **static-playlist DAO** (create/rename/delete/append/insert/remove/reorder/loose-add, built-in "current", name-conflict, CASCADE; 22 headless checks). **NET-NEW for rev.3:** (a) **playlist folders** (hierarchy) and (b) **smart playlists** (rules + evaluation) — both need schema + DAO. Confirmed absent today.

### 0.1 Reviewer-corrected premises (carried from rev.2)
- **No scan-folder drop target exists** (folders added via open-panel; US-LIB-07 move-on-drag deferred) → reference-add safety is **type-level** (§2), not handler-discipline.
- **`FacetTrackListView`/`AlbumDetailView` are `List(selection:)`** — drop/reorder dead on macOS 26 → detail body reuses the **queue's `LazyVStack`/`PlaylistItemRow`**, header only.
- **`playlists()` returns the built-in first, unfiltered**, and its mutation verbs are unguarded for it → filter + guard everywhere.
- **`LibrarySidebar` is itself a `List(selection:)`** of static category labels → a Playlists *section* needing per-row drop + context-menu + inline rename can't live inside that `List` (drop won't fire, gestures race). The sidebar likely splits into the category `List` + a **`LazyVStack` Playlists tree** (SME to confirm the exact composition).

### 0.2 DATA-LOSS RISK (must decide — §9.5)
The GRDB store uses `eraseDatabaseOnSchemaChange = true` because the song DB is a *rebuildable cache of on-disk files* ([[feedback-delete-rebuild-dev-db]]). **But playlists / folders / smart-rules are USER data that cannot be rebuilt.** Adding folders + smart-playlist tables bumps the schema → **wipes existing user playlists.** Fine in dev (drop-and-recreate always); **a data-loss bug for a shipped R1 user.** Options in §9.5. This must be resolved before the schema bump lands.

## 1. IA — sidebar Playlists section (LOCKED: founder + research)
A **dedicated "Playlists" section in the left `LibrarySidebar`**, visually separate from the Songs/Albums/Artists/Genres category rail and the Music Folders accordion (the researched dominant pattern: Roon/MusicBee/Apple/Audirvana). **Scrollable / shows the full set** (Audirvana's ~2-row truncation is a documented "dealbreaker"). Selecting a playlist (or smart playlist) shows its detail in the content area (a `LibraryRoute.playlist(Int64)` / `.smartPlaylist(Int64)`). **Folders render as a nesting tree** (disclosure rows) within the section. Nav state on `LibraryBrowseModel`; data on `PlaylistsModel`.

## 2. Architecture
- **`PlaylistsModel` — new `@MainActor @Observable` peer** (not extending the read-only, scan-revision browse cache). Composition-root-owned + injected; composes `library` (store) + `audio` (queue verbs). Holds the folder/playlist tree, open detail, smart-playlist results, and mutating verbs. **Epoch-guarded authoritative re-read** after each mutation (newest-wins); **also refresh on `library.libraryRevision`** (CASCADE shrink + smart-playlist re-evaluation depend on it).
- **Schema additions (drop-and-recreate; no migration):**
  - **Folders:** a nullable `parent_folder_id` self-reference — simplest is a `playlist_folders(id, parent_id NULL REFERENCES playlist_folders(id) ON DELETE …, name, position, created_at)` table + `playlists.folder_id INTEGER NULL REFERENCES playlist_folders(id)`. Smart + static playlists both live in folders. Guard against parent-cycle on move.
  - **Smart playlists:** `playlists.is_smart INTEGER NOT NULL DEFAULT 0` + a rules representation. Recommend a **normalized `playlist_rules` table** (playlist_id, field, op, value, conjunction) over a JSON blob (queryable, testable, no blob parsing) + `match_all/any`, optional `limit` + `sort`. Membership is **derived** (a built SQL `WHERE` over `tracks`), never stored as `playlist_entries`.
- **Reference-add safety = TYPE-LEVEL (US-PLIST-04):** library-track drag payload `LibraryTrackDragItem { trackID: Int64 }` (declared UTType); `addTrackToPlaylist(trackID:playlistID:)` → `store.appendEntry` only. Cannot move a file known only by id. Loose add reads tags + writes a row (read-only w.r.t. the file). No `FileManager` move/copy anywhere in the playlist path. Pure `PlaylistDropRouter` for testability.
- **Built-in "current" invisible + inert:** filter `is_builtin=0` in every surface (tree, add targets, drops) via pure `PlaylistBrowseVisibility`; DAO-reject mutations on the built-in.
- **Dead / loose files:** entry resolution yields `.ok | .missing`; **play SKIPS a `.missing` entry (never halts)**; detail shows a per-row "unavailable" indicator; actions: Locate (single) + "Remove missing" (bulk) + launch orphan-sweep of unreferenced loose rows. (Bulk relink/remap = future.)

## 3. UI (reuse map — corrected + extended)
| Piece | Reuse / build |
|---|---|
| Sidebar Playlists **tree** | `LazyVStack` of disclosure rows (folders) + playlist rows; each playlist row is a `.dropDestination(for: LibraryTrackDragItem)`; scrolls; context menu (New Playlist / New Smart Playlist / New Folder / Rename / Delete); inline rename. NOT inside the category `List`. |
| Playlist **detail** body (static) | queue's `PlaylistItemList`/`PlaylistItemRow` (`LazyVStack` + grip `.draggable` reorder + Delete-to-remove). Header from `FacetTrackListView`. `ForEach` on `PlaylistEntry.id`. |
| Smart-playlist **detail** | same list body but **read-only** (no manual reorder/remove/add — membership is rule-derived); header shows the rule summary + "Edit Rules". |
| Two coexisting drops (detail) | two **declared UTTypes** (`playlist-entry` reorder + `library-track` add); reject `.fileURL`/`.audio`. |
| Add-to-playlist | context menu: `New Playlist…` + top-N recent + `Add to Playlist…` → **searchable sheet** (`LibraryFilterField`); primary Songs path (operates on `SongsRowResolver.orderedSelection` — no `Table` drag refactor). |
| Smart-rule **builder** | a sheet: rows of (field ▸ op ▸ value) + match-all/any + limit + sort; fields from the tracks schema (title/artist/album/genre/year/rating/loved/play_count/last_played/date_added/duration/format/sample_rate/bit_depth/frecency). |
| Create / rename | `TextField` that sets `KeyboardTransportFocus.isTextEntryFocused`; editing id in parent `@State`; inline `PlaylistNameConflict`; built-in gated. |
| Play a playlist | resolve entries → `AudioFile` via batched `tracksDisplay(ids:)` + `AudioFile(_:)` (queue-hydration seam; no N+1). |
| Artwork | share the existing `ArtworkThumbnailStore` (inject `browse.artworkImage` closure). |

## 4. Play semantics (LOCKED: verb set + undo)
Three verbs on a playlist/folder/selection: **Play** (replace the active queue), **Play Next** (insert after current), **Add to Queue** (append) — mirrors Roon/Apple. **Play (replace) is REVERSIBLE**: snapshot the pre-replace queue and show a **"Restore previous queue" undo toast** (a differentiation opening — no comparable offers it; the top real-world queue frustration). Single-track play does **not** over-enqueue the rest. The built-in current-queue stays the invisible playback surface.

## 5. Folders (LOCKED)
Nested folders holding static + smart playlists; sidebar disclosure tree; drag a playlist into a folder (reference move within the tree, never a file op); create/rename/delete (deleting a folder → decide: delete contents vs orphan-to-root — §9.2). Names need not be unique across folders (path-scoped) — decide vs global. Cycle-guard on reparent.

## 6. Smart playlists (LOCKED)
Rule-based, auto-updating, **read-only membership** (derived by evaluating rules against `tracks`). Auto-refresh on open + on `libraryRevision` (§9.3 cadence). Playable via the same verbs (resolve → queue). Not drop targets (can't manually add). Rule builder in §3. v1 criteria set = §9.1 (founder to confirm). Evaluation = a pure rule→SQL `WHERE` builder (testable) + a bounded query (indexed where possible; EXPLAIN-plan tripwire).

## 7. QA plan (rev.3)
- **Pure (`swift test`, LibraryBrowseKit):** `PlaylistDropRouter` (drop → add-ops only, never move); `PlaylistBrowseVisibility` (built-in excluded); `PlaylistAddDecision` (already-present → toast; empty-play no-op; multi-select order/dedupe); loose-entry resolution → `.missing` (retain, skip); **`SmartRuleSQLBuilder`** (each field/op → correct WHERE + args; match-all/any; injection-safe binding; limit/sort); **folder-tree** helpers (cycle-guard on reparent; delete semantics).
- **Strict-gate grep:** the playlist-drop handler references no `moveItem`/`copyItem`.
- **VerifyLibraryStore (headless, new):** `pl-move-membership-survives` (real scanner, §rev.2); `pl-reorder-isolation`; `pl-explain-plan` (static list + entries + **smart-eval** query use indexes); `pl-write-during-scan`; built-in mutation rejected; **`pl-folder-*`** (nest/reparent/cycle-reject/delete-cascade-or-orphan); **`pl-smart-eval`** (seed tracks → rules → assert derived membership; re-eval after a scan changes membership); loose orphan-sweep.
- **qa-expert + Fool break-it** post-impl: wrong-target drop; delete open-detail playlist/folder; rename race; reorder during sweep; duplicate flood; hundreds of playlists + deep nesting (tree perf + query plan); play a moved file (skip+retain); cross-playlist drag = copy; built-in never exposed; **smart rule that matches 50k tracks** (bound/paginate); **circular folder reparent**; **schema-bump data-loss** (§0.2).
- **Founder by-hand:** create/rename/delete (playlist, smart, folder); drag Songs→playlist (verify no file moved); nest folders; build a smart rule + watch it update after a scan; the three play verbs + undo; dead-file skip + remove-missing.

## 8. Chunking (phased, build-gated)
- **A** — schema (folders + smart tables/columns) + DAO (folder CRUD/reparent/cycle-guard; smart CRUD; `SmartRuleSQLBuilder`) + `PlaylistsModel` peer + §0.2 data-loss resolution. Headless checks.
- **B** — sidebar **Playlists section** (flat first): list user playlists (built-in filtered), scroll, select→detail, create/inline-rename/delete.
- **C** — static playlist **detail** (queue list body): play (verbs), remove, reorder; `ForEach` on entry id.
- **D** — **folders**: tree/disclosure in the sidebar, create/rename/delete, drag-playlist-into-folder, cycle-guard.
- **E** — add-to-playlist: context menu + searchable sheet (US-PLIST-02 incl. loose file) + `LibraryTrackDragItem` UTType + drops (US-PLIST-03/04); `PlaylistDropRouter` + FileMover-spy + strict-gate grep **land here**.
- **F** — **smart playlists**: rule builder sheet + read-only detail + auto-refresh + `pl-smart-eval`.
- **G** — dead/loose: skip-on-play + unavailable indicator + Locate + remove-missing + orphan-sweep.
- **H** — US-PLIST-08 real-scanner seam + `pl-reorder-isolation`/`pl-explain-plan`/`pl-write-during-scan` + strict-gate.

## 9. Open founder-brainstorm decisions (recommendation first)
1. **Smart-playlist v1 criteria set** — *recommended:* artist, album, genre, year, rating, loved, play_count, last_played, date_added, duration, format, sample_rate/bit_depth (audiophile-relevant), frecency; ops =/≠/contains/>/</between/in-last-N-days; match all/any; optional limit + sort. Confirm/trim.
2. **Delete a folder** — *recommended:* move its contents up to the parent (orphan-to-root), NOT delete the playlists inside (least destructive) — vs delete-contents (with undo).
3. **Smart-playlist auto-refresh cadence** — *recommended:* re-evaluate on detail-open + on `libraryRevision` (post-scan), not on a timer. Confirm.
4. **Play a folder** — *recommended:* plays all descendant playlists' tracks in tree order (like Play on a folder in Roon) vs no-op.
5. **§0.2 data-loss policy** — *recommended:* make the **playlist/folder/smart tables additive-only (never erase on schema bump)** — i.e., exempt user-data tables from `eraseDatabaseOnSchemaChange`, or split user data into a second store that only ever migrates additively — vs accept dev-wipe now + add export/import before R1 ship. This is the one with real user-data-loss stakes.
