# S10.3 — Playlists UX — design (rev. 4 — LOCKED, buildable)

Last R1 gate. Research-grounded ([memo](s10-3-playlists-ux-research.md)) + three SME/Fool review rounds + founder decisions (2026-07-15). **Smart playlists DECOUPLED to post-R1** (see §Deferred). R1 scope: **static playlists + playlist folders + sidebar IA + Play/Next/Queue verbs with undo + dead-file handling.** Stories US-PLIST-02/-03/-04/-08 + folders.

## Locked decisions (founder)
- **D-IA:** playlists live in a **dedicated sidebar section** (not a 5th browse category). Research norm + resolves the mutable-vs-read-only coherence concern.
- **D-store:** **separate `user-data.sqlite3` store** for playlists/folders/entries (additive-only, `eraseDatabaseOnSchemaChange = false`); `library.sqlite3` stays the nuke-and-rebuild cache. §2.
- **D-names:** playlist names are **globally unique** (keep `UNIQUE(name) WHERE is_builtin=0`).
- **D-folder-delete:** deleting a playlist folder **deletes its contents** (playlists + subfolders), guarded by an **undo** (snapshot the subtree for restore). Strict "folder owns its contents".
- **D-play:** **Play (replace queue) / Play Next / Add to Queue**; Play-replace is **reversible** via a "Restore previous queue" undo toast.
- **D-smart:** smart/auto playlists are a **post-R1 fast-follow** (appending their migration later is free + lossless — §Deferred preserves the vetted design).

## 0. Corrected premise (was rev.3 §0.2 — WRONG)
Rev.3 claimed "adding folders/smart tables wipes playlists." **False** (architect + Fool, verified against GRDB source + the repo's own v4). `eraseDatabaseOnSchemaChange` erases only on a **downgrade** or an **edited already-shipped migration body** — never on **appending** a new migration. v4 (frecency) appended after v3 (playlists) and preserved data. The real risk is *whole-file collateral erase* from a future edited-migration or a corruption/quarantine rebuild — which **D-store** structurally removes by putting user data in its own never-erased file.

## 1. IA — sidebar Playlists section (D-IA)
A dedicated "Playlists" section in the left sidebar, **separate** from the Songs/Albums/Artists/Genres category rail and the Music Folders accordion. **Scrollable, shows the full set** (Audirvana's 2-row truncation is a documented "dealbreaker"). Folders render as a **flattened disclosure tree**. Selecting a playlist → detail in the content area.
- **Composition (swiftui-pro):** collapse the whole sidebar to **one `ScrollView { LazyVStack }` of plain `Button` rows** with a single selection enum — drop `List(selection:)` (its drops don't fire + it races gestures + double-highlight with a second selection system). Keep the `.safeAreaInset(edge:.bottom)` Music Folders footer.
  ```swift
  enum SidebarSelection: Hashable { case category(LibraryCategory), playlist(Int64) }
  ```
  Re-implement ↑/↓ + ←/→ (collapse/expand) via `.onKeyPress` + `@FocusState` (as `PlaylistItemList` does); re-create the selection capsule with `DesignSystem.Color.rowSelected`.
- **Folder tree (swiftui-pro):** **flatten the expanded tree into a depth-annotated array** (`SidebarNode { id, kind, depth }`) and render flat — do NOT use `OutlineGroup`/`DisclosureGroup` (they re-introduce `List` dead-drops OR break LazyVStack laziness + nest drop hit-regions). Expansion = `Set<Int64>` **on the model** (tab switch destroys the view), persisted (`@AppStorage`-JSON, matching `library.foldersExpanded.v1`). Soft-cap indent (~5 levels).

## 2. Architecture — the separate user-data store (D-store, load-bearing)
- **`UserDataStore`** — a second GRDB store (`user-data.sqlite3`) with its own `DatabaseMigrator`, **`eraseDatabaseOnSchemaChange = false`**, **additive-only frozen-shipped-body discipline**. Holds `playlists`, `playlist_entries`, `playlist_folders` (+ post-R1 `playlist_rules`), and the built-in "current" queue. `library.sqlite3` is unchanged (cache, erase=true).
- **Migrate the S10.1/S10.2 playlist tables out of `library.sqlite3` into `UserDataStore`** (chunk **A0**). Repoint the two shipped S10.2 consumers: `AudioViewModel+QueueMirror.swift` (`replaceEntries`/`currentPlaylistID`) + `AudioViewModel+QueueHydration.swift`. The `LibraryStore+Playlists.swift` DAO moves to the new store.
- **No cross-file FK** (SQLite can't). `playlist_entries.track_id` is a **soft reference** (durable `Int64`). The old `ON DELETE CASCADE` (track delete → drop entry) becomes an **app-layer sweep**: on `library.libraryRevision` change, delete `playlist_entries` whose `track_id` no longer exists in `library.tracks` (this is exactly the founder's "track deleted/moved → remove from playlist" rule; a moved+re-matched track keeps its id, so it survives — US-PLIST-08). Track *identity* stays authoritative in `library.sqlite3`; loose-add writes the track row there, the entry soft-refs the returned id.
- **`PlaylistsModel`** — new `@MainActor @Observable` composition-root peer over `UserDataStore` (+ `library` for track identity/display, `audio` for queue verbs). Owns the folder/playlist tree, open detail, verbs. **Per-surface epoch tokens** (tree / detail-entries) like `LibraryBrowseModel`; refresh on mutation + on `libraryRevision` (for the orphan sweep). Nav (`SidebarSelection`, `LibraryRoute.playlist(Int64)`) on `LibraryBrowseModel`.
- **Reference-add = TYPE-LEVEL (US-PLIST-04):** `LibraryTrackDragItem { trackID: Int64 }` (declared UTType); `addTrackToPlaylist(trackID:playlistID:)` → `appendEntry` only. Can't move a file known by id. No `FileManager` move/copy in the playlist path (strict-gate grep backstop). Pure `PlaylistDropRouter`.
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
- **VerifyUserDataStore / VerifyLibraryStore (headless, new):** **`ud-survives-schema-bump`** (GREEN-GATE, load-bearing: seed playlists+folders → register a throwaway additive migration → assert every user row survives — proves D-store); `pl-move-membership-survives` (real scanner, US-PLIST-08); **`pl-orphan-sweep`** (delete a track in library → the cross-store sweep drops its entries; moved track keeps membership); `pl-reorder-isolation`; `pl-folder-cascade-delete` + cycle-reject; `pl-explain-plan` (list + entries use indexes); `pl-write-during-scan`; built-in mutation rejected.
- **qa-expert + Fool break-it** post-impl: wrong-target drop; delete open-detail playlist/folder; rename race; reorder during sweep; duplicate flood; hundreds of playlists + deep nesting; play a moved file (skip+retain); cross-playlist drag = copy; built-in never exposed; cross-store crash between loose-add's two writes (→ harmless orphan/.missing).
- **Founder by-hand:** create/rename/delete (playlist, folder + undo); drag Songs→playlist (verify no file moved on disk); nest folders; the three play verbs + restore-queue undo; dead-file skip + remove-missing.

## 6. Chunking (phased, build-gated)
- **A0** — `UserDataStore` (separate additive-only store) + migrate playlist tables out of `library.sqlite3` + repoint S10.2 consumers + `ud-survives-schema-bump` green-gate. *(The load-bearing refactor — do first, gate hard.)*
- **A** — `playlist_folders` schema + folder DAO (CRUD/reparent/cycle-guard/cascade-delete-with-subtree-snapshot) + `PlaylistsModel` peer + cross-store orphan sweep on `libraryRevision` (`pl-orphan-sweep`).
- **B** — sidebar Playlists section (flat first): one ScrollView/LazyVStack, unified selection enum, built-in filtered, scroll, select→detail, create/inline-rename/delete.
- **C** — `PlaylistDetailList` (queue-row reuse): play (verbs + undo), remove, reorder; `ForEach` on entry id.
- **D** — folders UI: flattened disclosure tree, create/rename/delete(+undo), drag-reparent, cycle-guard, depth cap.
- **E** — add-to-playlist: context menu + searchable sheet (US-PLIST-02 incl. loose file) + `LibraryTrackDragItem` UTType + drops (US-PLIST-03/04); `PlaylistDropRouter` + FileMover-spy + strict-gate grep **here**.
- **F** — dead/loose: skip-on-play + unavailable indicator + Locate + remove-missing + orphan-sweep UI.
- **G** — US-PLIST-08 real-scanner seam + `pl-reorder-isolation`/`pl-explain-plan`/`pl-write-during-scan` + strict-gate.

## 7. Open sub-decisions (recommend + proceed unless vetoed)
- **Play a folder** — *recommended:* plays all descendant playlists' tracks in tree order (bounded by a queue-size safety cap). Same for a multi-playlist selection.
- **Backup/export of user data** — *recommended:* out of R1 scope, but note as the belt-and-braces follow-up (covers a corrupt `user-data.sqlite3` — the one thing the store-split alone can't). Not blocking.

---

## Deferred to post-R1 — Smart / auto playlists (design preserved)
Vetted but decoupled (D-smart). A later additive `user-data` migration adds `playlists.is_smart` + a normalized **`playlist_rules`** table; membership is **derived** (a pure `SmartRuleSQLBuilder` → `WHERE` over `library.tracks`, run when the smart list is opened — rules read from `user-data`, query runs on `library`; no cross-store JOIN). Key review points to honor when built: **fields are predicate-shaped** (genre → `EXISTS(track_genres…)`, artist/album → id sub-select — NOT raw columns); **field+op are closed enums, value always bound** (injection-safe); **live match-count** in the builder + mandatory **limit** (default ~1000) so play-enqueue is bounded; **split the EXPLAIN tripwire** (index-assert equality/range; tolerate `LIKE '%x%'` scan); read-only detail (reuse `PlaylistItemRow`'s nil-`dragPayload` path); polymorphic value editor as a `@ViewBuilder` switch (not `AnyView`) with a draft/commit-on-Save (not live-bound); counts are eventually-consistent (refresh on open + `libraryRevision`, accept slightly-stale sidebar counts). Criteria v1 set: artist/album/genre/year/rating/loved/play_count/last_played/date_added/duration/format/sample_rate/bit_depth/frecency; ops =/≠/contains/>/</between/in-last-N-days; match all/any.
