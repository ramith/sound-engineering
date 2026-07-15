# S10.3 — Playlists UX — design (rev. 5 — LOCKED, buildable)

Last R1 gate. Research-grounded ([memo](s10-3-playlists-ux-research.md)) + three SME/Fool review rounds + a QA break-it that overturned the store decision + founder decisions (2026-07-15). **Smart playlists DECOUPLED to post-R1** (see §Deferred). R1 scope: **static playlists + playlist folders + sidebar IA + Play/Next/Queue verbs with undo + dead-file handling.** Stories US-PLIST-02/-03/-04/-08 + folders.

## Locked decisions (founder)
- **D-IA:** playlists live in a **dedicated sidebar section** (not a 5th browse category). Research norm + resolves the mutable-vs-read-only coherence concern.
- **D-store (rev.5, REVERSED):** ~~separate `user-data.sqlite3` store.~~ **ONE store: keep playlists in `library.sqlite3`, and STOP erasing user data** — `LibraryStore.makeMigrator` now sets `eraseDatabaseOnSchemaChange = FALSE`; schema changes are **additive-only, frozen-body** migrations. A QA break-it (qa-expert + Fool) proved the separate-store split was BROKEN: its soft ref was the reused `tracks.id` rowid, which a routine library rebuild reassigns → playlists silently pointed at the WRONG track (worse than a clean wipe); and it protected only playlists while `play_count`/`loved`/`rating`/`frecency` — equally unrebuildable — stayed in the erased cache. One store keeps the FK `ON DELETE CASCADE` (deleted track → dropped entry, atomic), id stability, US-PLIST-08 (move-match keeps id), and protects ALL user data uniformly. §2. See [[feedback-delete-rebuild-dev-db]] (scoped/reversed).
- **D-names:** playlist names are **globally unique** (keep `UNIQUE(name) WHERE is_builtin=0`).
- **D-folder-delete:** deleting a playlist folder **deletes its contents** (playlists + subfolders), guarded by an **undo** (snapshot the subtree for restore). Strict "folder owns its contents".
- **D-play:** **Play (replace queue) / Play Next / Add to Queue**; Play-replace is **reversible** via a "Restore previous queue" undo toast.
- **D-smart:** smart/auto playlists are a **post-R1 fast-follow** (appending their migration later is free + lossless — §Deferred preserves the vetted design).

## 0. Store-decision history (why rev.5 lands on one store)
1. **rev.3 §0.2 (WRONG):** "adding tables wipes playlists" — false; appending a migration never erases (verified vs GRDB source + the repo's own additive v4).
2. **rev.4 (separate store):** to survive a *whole-file* erase (an edited shipped migration, or a corruption/quarantine rebuild), put user data in its own never-erased `user-data.sqlite3`.
3. **rev.5 (QA break-it overturned it — LOCKED):** the separate store's cross-store reference was `tracks.id`, a bare rowid (`INTEGER PRIMARY KEY`, no `AUTOINCREMENT`) that a library rebuild REASSIGNS in scan order → a `user-data` entry for id 5 resolves to a *different* file → **playlists silently show the wrong songs** (worse than the clean wipe the split was meant to prevent), and the sweep can't catch a *reused* id. It also protected only playlists while `play_count`/`loved`/`rating`/`frecency` (equally unrebuildable, and integrated as indexed `tracks` columns the browse `ORDER BY`s — so not movable) stayed exposed. **Root cause:** the library DB was never a *pure* cache — it holds user data too. **Fix:** don't erase it. One store, `eraseDatabaseOnSchemaChange = false`, additive-only; the derived cache is rebuilt by re-scan, not by wiping the file.

## 1. IA — sidebar Playlists section (D-IA)
A dedicated "Playlists" section in the left sidebar, **separate** from the Songs/Albums/Artists/Genres category rail and the Music Folders accordion. **Scrollable, shows the full set** (Audirvana's 2-row truncation is a documented "dealbreaker"). Folders render as a **flattened disclosure tree**. Selecting a playlist → detail in the content area.
- **Composition (swiftui-pro):** collapse the whole sidebar to **one `ScrollView { LazyVStack }` of plain `Button` rows** with a single selection enum — drop `List(selection:)` (its drops don't fire + it races gestures + double-highlight with a second selection system). Keep the `.safeAreaInset(edge:.bottom)` Music Folders footer.
  ```swift
  enum SidebarSelection: Hashable { case category(LibraryCategory), playlist(Int64) }
  ```
  Re-implement ↑/↓ + ←/→ (collapse/expand) via `.onKeyPress` + `@FocusState` (as `PlaylistItemList` does); re-create the selection capsule with `DesignSystem.Color.rowSelected`.
- **Folder tree (swiftui-pro):** **flatten the expanded tree into a depth-annotated array** (`SidebarNode { id, kind, depth }`) and render flat — do NOT use `OutlineGroup`/`DisclosureGroup` (they re-introduce `List` dead-drops OR break LazyVStack laziness + nest drop hit-regions). Expansion = `Set<Int64>` **on the model** (tab switch destroys the view), persisted (`@AppStorage`-JSON, matching `library.foldersExpanded.v1`). Soft-cap indent (~5 levels).

## 2. Architecture — one store, never erase user data (D-store rev.5)
- **`library.sqlite3` stops erasing (DONE, A0):** `LibraryStore.makeMigrator` → `eraseDatabaseOnSchemaChange = false`; migrations are **additive-only, frozen-shipped-body**. Playlists (`playlists`/`playlist_entries`, S10.1) STAY in this store; folders (`playlist_folders`) + post-R1 `playlist_rules` are **appended** as new migrations (v5+). Guarded by the `additive-preserve-schema-bump` VerifyLibraryStore check. Derived cache = rebuilt by re-scan, never by wiping the file.
- **The deleted-track → dropped-entry rule is the existing same-file FK** `playlist_entries.track_id → tracks.id ON DELETE CASCADE` — atomic, no app-layer sweep, no cross-store anything. A folder-removal still keeps playlist-referenced tracks (the S10.1 `unreferencedTrackIDs` Gate-1, unchanged). US-PLIST-08 works because move-match preserves `tracks.id` in place (same file). `tracks.id` is durable because the file is never rebuilt out from under it.
- **`PlaylistsModel`** — new `@MainActor @Observable` composition-root peer over **`library.store`** (the playlist DAO already lives there) + `audio` for queue verbs. Owns the folder/playlist tree, open detail, verbs. **Per-surface epoch tokens** (tree / detail-entries) like `LibraryBrowseModel`; authoritative re-read after each mutation. Nav (`SidebarSelection`, `LibraryRoute.playlist(Int64)`) on `LibraryBrowseModel`. (No repoint of the S10.2 queue consumers — they already use `library.store`.)
- **Reference-add = TYPE-LEVEL (US-PLIST-04):** `LibraryTrackDragItem { trackID: Int64 }` (declared UTType); `addTrackToPlaylist(trackID:playlistID:)` → `appendEntry` only. Can't move a file known by id. No `FileManager` move/copy in the playlist path (strict-gate grep backstop). Pure `PlaylistDropRouter`. Loose-file add uses the existing `addLooseFileToPlaylist` (one txn, same store).
- **Backup/export** of the whole DB (covers playlists + user-state against the corruption/quarantine path) — noted follow-up, out of R1 scope.
- **Built-in "current" invisible + inert:** filter `is_builtin=0` everywhere (pure `PlaylistBrowseVisibility`); DAO-reject mutations on it.
- **Dead / loose files:** entry resolution → `.ok | .missing`; **play SKIPS `.missing` (never halts)**; per-row unavailable indicator; Locate + bulk "Remove missing" + launch orphan-sweep.

## 3. Folders (D-folder-delete)
Adjacency-list `playlist_folders(id, parent_id NULL self-ref, name, position, created_at)` + `playlists.folder_id`. Nested tree; drag a playlist/folder into a folder (reparent — a `SidebarNodeMoveItem` UTType, never a file op). **Cycle-guard inside the write txn** via `WITH RECURSIVE` ancestor walk (reject target == node OR target ∈ descendants(node)). **Delete = CASCADE the contents** (`ON DELETE CASCADE` on `parent_id` + `folder_id`) **+ undo:** snapshot the deleted subtree (folders + playlists + entries) before delete; the undo toast restores it. Depth soft-cap ~5.

## 4. UI (reuse map — corrected)
| Piece | Reuse / build |
|---|---|
| Sidebar tree | `ScrollView { LazyVStack }` of Button rows (§1); each playlist row a `.dropDestination(for: LibraryTrackDragItem)`; grip `.draggable(SidebarNodeMoveItem)` for reparent (grip, not row-wide — avoids the FB7367473 tap/drag race). |
| Playlist **detail** | NEW `PlaylistDetailList` reusing **`PlaylistItemRow`** (NOT `PlaylistItemList` — it's `private` + hardwired to `AudioViewModel.queue`). Same ScrollView+LazyVStack+`@FocusState`+`.onKeyPress` scaffolding. `ForEach` on `PlaylistEntry.id` (dupes allowed). Reorder via grip `.draggable(PlaylistEntryDragItem)` + row `.dropDestination`. |
| Two drops on detail | two declared UTTypes (`playlist-entry` reorder + `library-track` add); reject `.fileURL`/`.audio`. |
| Add-to-playlist | context menu (`New Playlist…` + top-N recent + `Add to Playlist…` → **searchable sheet** reusing `LibraryFilterField`); primary Songs path via `SongsRowResolver.orderedSelection` (no Table drag refactor). |
| Create / rename | `TextField` with a reusable **`.transportFocusGate($focused)`** (extract from `LibraryFilterField` — else Space toggles playback); editing id in parent `@State`; inline `PlaylistNameConflict`; built-in gated. |
| Play | resolve entries → `AudioFile` via batched `tracksDisplay(ids:)` + `AudioFile(_:)` (queue-hydration seam, no N+1). |
| Play undo | snapshot the **in-memory `queue` array synchronously** at replace time (NOT the debounced mirror — stale + drops loose slots); one transient "Restore previous queue" toast (one-level). |
| Artwork | share the existing `ArtworkThumbnailStore` (inject `browse.artworkImage`). |

## 5. QA plan (R1)
- **Pure (`swift test`, LibraryBrowseKit):** `PlaylistDropRouter` (drop → add-ops only, never move); `PlaylistBrowseVisibility` (built-in excluded); `PlaylistAddDecision` (already-present → toast; empty-play no-op; multi-select order/dedupe); loose-entry resolution → `.missing` (retain, skip); folder cycle-guard (self + descendant).
- **Strict-gate grep:** playlist-drop handler references no `moveItem`/`copyItem`.
- **VerifyLibraryStore (headless):** **`additive-preserve-schema-bump`** (GREEN-GATE, DONE, A0: an appended migration preserves seeded data under erase=false — proves the store posture); `pl-move-membership-survives` (real scanner, US-PLIST-08); `pl-reorder-isolation`; `pl-folder-cascade-delete` (same-file FK cascade) + cycle-reject; `pl-explain-plan` (list + entries use indexes); `pl-write-during-scan`; built-in mutation rejected. (No `pl-orphan-sweep` — the same-file `ON DELETE CASCADE` handles deleted-track cleanup atomically; the existing `pl-file-gone-drop` check already covers it.)
- **qa-expert + Fool break-it** post-impl: wrong-target drop; delete open-detail playlist/folder; rename race; reorder during a scan-sweep; duplicate flood; hundreds of playlists + deep nesting; play a moved file (skip+retain); cross-playlist drag = copy; built-in never exposed.
- **Founder by-hand:** create/rename/delete (playlist, folder + undo); drag Songs→playlist (verify no file moved on disk); nest folders; the three play verbs + restore-queue undo; dead-file skip + remove-missing.

## 6. Chunking (phased, build-gated)
- **A0** — ✅ DONE: `library.sqlite3` → `eraseDatabaseOnSchemaChange = false` (additive-only, protects playlists + track user-state) + the `additive-preserve-schema-bump` green-gate. *(The separate-store detour was built then reverted per the QA break-it — §0.)*
- **A** — `playlist_folders` schema as an **additive v5 migration** + folder DAO (CRUD/reparent/cycle-guard/cascade-delete-with-subtree-snapshot for undo) + `PlaylistsModel` peer over `library.store`. (Deleted-track cleanup is the same-file FK cascade — no sweep needed.)
- **B** — sidebar Playlists section (flat first): one ScrollView/LazyVStack, unified selection enum, built-in filtered, scroll, select→detail, create/inline-rename/delete.
- **C** — `PlaylistDetailList` (queue-row reuse): play (verbs + undo), remove, reorder; `ForEach` on entry id.
- **D** — folders UI: flattened disclosure tree, create/rename/delete(+undo), drag-reparent, cycle-guard, depth cap.
- **E** — add-to-playlist: context menu + searchable sheet (US-PLIST-02 incl. loose file) + `LibraryTrackDragItem` UTType + drops (US-PLIST-03/04); `PlaylistDropRouter` + FileMover-spy + strict-gate grep **here**.
- **F** — dead/loose: skip-on-play + unavailable indicator + Locate + remove-missing + orphan-sweep UI.
- **G** — US-PLIST-08 real-scanner seam + `pl-reorder-isolation`/`pl-explain-plan`/`pl-write-during-scan` + strict-gate.

## 7. Open sub-decisions (recommend + proceed unless vetoed)
- **Play a folder** — *recommended:* plays all descendant playlists' tracks in tree order (bounded by a queue-size safety cap). Same for a multi-playlist selection.
- **Backup/export of user data** — *recommended:* out of R1 scope, but note as the belt-and-braces follow-up (the corruption/quarantine rebuild of `library.sqlite3` still loses user data — erase=false only protects the schema-change path, not corruption). Not blocking.

---

## Deferred to post-R1 — Smart / auto playlists (design preserved)
Vetted but decoupled (D-smart). A later additive migration (v6+) adds `playlists.is_smart` + a normalized **`playlist_rules`** table (in `library.sqlite3`, same store as `tracks`); membership is **derived** (a pure `SmartRuleSQLBuilder` → `WHERE` over `tracks`, run when the smart list is opened — a plain same-store query, no cross-store concern). Key review points to honor when built: **fields are predicate-shaped** (genre → `EXISTS(track_genres…)`, artist/album → id sub-select — NOT raw columns); **field+op are closed enums, value always bound** (injection-safe); **live match-count** in the builder + mandatory **limit** (default ~1000) so play-enqueue is bounded; **split the EXPLAIN tripwire** (index-assert equality/range; tolerate `LIKE '%x%'` scan); read-only detail (reuse `PlaylistItemRow`'s nil-`dragPayload` path); polymorphic value editor as a `@ViewBuilder` switch (not `AnyView`) with a draft/commit-on-Save (not live-bound); counts are eventually-consistent (refresh on open + `libraryRevision`, accept slightly-stale sidebar counts). Criteria v1 set: artist/album/genre/year/rating/loved/play_count/last_played/date_added/duration/format/sample_rate/bit_depth/frecency; ops =/≠/contains/>/</between/in-last-N-days; match all/any.
