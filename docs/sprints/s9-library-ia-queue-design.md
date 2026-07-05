# S9 — Library IA + "Now Playing = Queue" (design)

Status: **vetted** (3-lens panel: product-manager · business-analyst · ui-designer, 2026-07-06). Founder waived the separate sign-off gate ("go ahead and do it") — implement in gated slices.

Supersedes the folder-load-into-Now-Playing behavior from the early playback work. Grounded on the running-app punch-list (founder, 2026-07-06).

## 1. The model

AdaptiveSound has two surfaces with two jobs, and this change makes the split clean:

- **Library = the durable, browsable source of truth.** You point it at folders on disk; it scans + organizes them into Songs/Albums/Artists/Genres/Years and stays current as those folders change. **Choosing a folder is a Library act, and it *only scans* — it never plays anything.**
- **Now Playing = the transport + the current queue.** An ephemeral, ordered `[AudioFile]`. The *only* things that put tracks in the queue are the explicit play verbs invoked from browse (`playNow`/`playNext`/`appendToQueue`) and the user's own queue edits. Picking a folder never fills the queue; a disk change never rewrites it.

## 2. Locked decisions (founder)

1. **Folder pick = scan-only**, everywhere. Never touches the queue.
2. **Now Playing list = the queue only.**
3. **Album-less songs** (`album_id NULL`) surface in **Songs** (S9.5), never a junk-drawer "Unknown Album".
4. **Sidebar order: Songs, Albums, Artists, Genres, Years** (done — commit 19a7fe8). Default *selection* stays `.albums` until the real Songs list ships (S9.5), then flips to `.songs` (don't launch onto a placeholder).

## 3. Folder management in Library (ui-designer lens)

A **persistent sidebar footer** via `.safeAreaInset(edge: .bottom)` on `LibrarySidebar` — survives category switches + tab teardown, never touches `selectedCategory`/`path`. Rejected: a detail-toolbar "+" (fights the custom 60pt `ToolbarView` chrome) and a "Folders" browse category (wrong altitude — its `.tag` selection would wipe the drill-down `path`).

```
├───────────────────────────┤  hairline (filled Rectangle, DesignSystem.Color.hairline)
│ ⟳ Scanning… 1,204 files   │  AMBIENT scan strip — only while model.isPopulating
├───────────────────────────┤
│ 🗀 Music Folders       +  │  footer: label → popover · "+" → add directly
└───────────────────────────┘
```

- **Add** — footer `+` (and the popover's "Add Folder…") → `.fileImporter([.folder])` → **`scanFolderIntoLibrary(url)` only**. Nested/overlapping picks already reject via `errorMessage` (render inline as `statusWarning`).
- **Roots list** — a popover (~340pt) listing `store.roots()`: folder glyph + middle-truncated path + secondary "N songs · scanned {relative}" / "scanning…".
- **Remove** — per-row `minus.circle` → `.confirmationDialog` (destructive): *"Remove '{folder}' from your library? The audio files on disk aren't deleted."*
- **Scan strip** — three truthful phases keyed on the existing signals: Scan (`scanProgress != nil`, indeterminate — `totalFiles` is always nil), Metadata (`metadataProgress != nil`, determinate), Reconcile (`isReconciling`).
- **First-run** — `LibraryEmptyStateView.firstRun` stays the detail-canvas hero; it and the footer share **one** `addFolder()` path (scan-only) so behavior can't drift. Unify the CTA verb to **"Add Folder…"**.

## 4. Now Playing = queue-only (ui-designer + BA)

Remove from `PlaylistView`/`PlaylistControlsView`: the "Choose Folder…" button, the folder chip (`folderPathDisplay`), `showFolderPicker`, and the `.fileImporter`. Keep shuffle/repeat/jump-to-now-playing (legitimate queue controls).

- Relabel header micro "PLAYLIST" → **"QUEUE"**; subtitle "{n} files · recursive" → **"{n} tracks"**.
- Context items "Remove from Playlist"/"Clear Playlist" → **"Remove from Queue"/"Clear Queue"**.
- **Empty-queue state** (`playlist.isEmpty`) → `ContentUnavailableView`: title "Queue is Empty", body "Browse your Library and press Play to start listening.", primary **"Browse Library"** → `selectedTab = .library`. (`AudioViewModel` owns `selectedTab`.)

## 5. Decouple the queue from folders (BA lens — the risky part)

The queue is in-memory, URL-keyed, **not** persisted and **not** a store reference. Retire the folder→queue coupling entirely:

- **Remove** `AudioViewModel.loadMusicFolder(_:)`, `schedulePlaylistRefresh()`, `playlistRefreshTask`, `musicFolderURL` (+ its `didSet`), `folderPathDisplay`.
- **Edit** `handleWatcherBatch` — drop the `playlistTouched`/`visiblePath` branch; `refreshWatchedRoots` — drop the `musicFolderURL` visible-folder branch → **watch store roots only**.
- **Keep** the store reconcile chain (`scheduleReconcile → runReconcile → performReconcile`) — the library stays live on disk changes and bumps `libraryRevision`; only the *queue* stops auto-mutating.
- **No data migration** — nothing was persisted; pure deletion of dead in-memory state. No schema change.
- If `AudioFileEnumerator.enumerate` has no other caller after `loadMusicFolder` goes, it's dead too (verify, don't assume).

`removeLibraryFolder(id:)` (new, on `AudioViewModel`): **cancel** any in-flight `scanTask`/`reconcileDebounce[id]` and clear `reconcilingRoots`/`pendingReconcile` for that id **before** `store.removeRoot(id:)`, then `refreshWatchedRoots()` + bump `libraryRevision`. Surface errors.

**Remove-folder semantics (verified):** (i) its store rows are deleted (no `playlist_tracks` table until S10, so "unreferenced" = all) → albums/artists vanish from browse; (ii) its tracks *in the queue* remain (queue can't be seen by `removeRoot`; files on disk survive); (iii) a track from it *currently playing* keeps playing (engine streams from the URL; `selectedTrackIndex`/`pendingNextIndex` untouched).

## 6. Acceptance criteria (BA — seed the gate/tests)

Relocation: (1) Now Playing has no chooser/importer/chip/"files·recursive"; (2) Library add-folder reachable in every state; (3) a Library folder pick leaves `playlist`/`selectedTrackIndex`/`pendingNextIndex` unchanged.
Decoupling: (4) an FSEvents batch under a root does NOT rewrite `playlist`, but the store still reconciles + bumps `libraryRevision`; (5) fresh launch → empty queue state; (6) no live callers of `loadMusicFolder`/`musicFolderURL`/`folderPathDisplay`/`schedulePlaylistRefresh`/`playlistRefreshTask`.
Add: (7) re-adding a registered/case-variant path doesn't grow `roots()`; (8) nested/overlapping → `errorMessage`, no partial root; (9) no-audio folder → `.emptyLibrary`; (10) store-not-ready → add gated on `isStoreReady`.
Remove: (11) confirm → `removeRoot` + `refreshWatchedRoots` + `libraryRevision` bump; (12) last root → first-run CTA, queue unchanged; (13) queued/playing track from removed folder keeps playing; (14) in-flight scan/reconcile for the root is cancelled before delete.
Browse-builds-queue: (16) Play replaces queue; (17) Play Next dedupes + arms; (18) Add-to-Queue arms only at linear end.
Empty queue: (19) empty → copy + "Browse Library"; (20) action sets `selectedTab == .library`; (21) Clear Queue empties + stops + shows empty state.

## 7. Implementation slices (each builds + gates + commits)

- **Slice A (additive): Library folder management.** `LibraryBrowseModel.roots/loadRoots/addFolder/removeFolder`; `AudioViewModel.removeLibraryFolder(id:)`; sidebar footer + Music-Folders popover + scan strip; unify `LibraryEmptyStateView` CTA through `addFolder()`. (Now Playing still has its chooser — harmless overlap; no gap where you can't add a folder.)
- **Slice B (removal): Now Playing = queue-only + decouple.** Remove the chooser/chip/importer + `loadMusicFolder`/`schedulePlaylistRefresh`/`musicFolderURL`/`folderPathDisplay`/`playlistRefreshTask`; edit watcher/reconcile to store-roots-only; relabel QUEUE + empty-queue state + queue copy.

Order A→B so folder-add is never unavailable between commits. Each slice: swiftui-pro + code-reviewer → build/lint/`make gate` → commit → founder make-run.

## 8. Out of scope (defer)

S10 queue wrapper (per-entry-id slots, dup entries, reorder/save/history, "queue entry unavailable" affordance, play-count `url→id` write-back tolerating a missing row); building the Songs/Artists/Genres/Years lists (S9.5/S9.6 — the Songs-default *flip* rides with S9.5); per-folder scan controls / priorities / multiple DBs; sandbox security-scoped bookmark persistence for roots (S8.4 posture); light-mode tuning; drag-to-import; internal `playlist`→`queue` symbol rename (the user-facing "Queue" label carries the model).
