> **Status (2026-10-13):** every R1 blocker below was fixed in PR #85 (Sprint G); the post-R1 items are open. The red tests and harness live on the reference branch named below (pushed to origin); the worktree paths are historical.

# Sprint G break-it — Library lane (breaker A)

**Base:** bfd0d19 (origin/main). **Branch:** breakit/s10-8-g-library (worktree agent-a37541b45a31484c2), not pushed.
**Red-test commits:** 7801279 (G-LIB-01, 01b + Package.swift), a9e4916 (G-LIB-02), b42eaa2 (G-LIB-07), cd5a9f2 (G-LIB-03, 04).
**swift test --filter LibraryBrowseKitTests:** 290 tests in 41 suites; the only failures are the six new break-it tests (16 issues).

**Package.swift (this branch only):** LibraryBrowseKitTests gains a test-only dependency on LibraryScan, so G-LIB-01b (two real LibraryScanner walks) and G-LIB-02 / G-LIB-07 (scanner and extractor rules) can run. No product target changes. A fix PR can keep it (the tests become regression tests) or drop it with those two files.

**Result:** 5 R1 blockers (one of them, G-LIB-01, is rare but loses user data; flagged for a founder call), 14 post-R1.

Method: adversarial reading of LibraryModel (+Scan, +Reconcile, +Metadata, +VolumeMonitor), LibraryBrowseModel (+Play, +Facets, +Detail, +Sidebar), PlaylistsModel, the Library and Playlist views, the selection kit, LibraryScan and the store; store-level red tests through the real write paths; a scanner-level harness with real files; no app launch.

## R1 blockers

### G-LIB-01 — two walks of one folder at once delete songs that are on disk (user-data loss)

- **Where:** LibraryModel+Reconcile.swift:123-136 (runReconcile gates on reconcilingRoots only), LibraryModel+Scan.swift:100-114 / 159-190 (performScan, the add and the re-add of a folder, the only manual rescan), LibraryModel+VolumeMonitor.swift:46-54 (ANY volume mount or unmount reconciles every root); store: LibraryStore+DAO.swift:323-325 (stampLastSeen writes last_seen_scan unconditionally), :260-273 (sweep last_seen_scan < generation), :161-169 (generation = max + 1).
- **Scenario:** an add-scan of folder X is walking when a reconcile of X starts (an FSEvents change in X — files still being copied in — or a DMG / USB drive mounting). The reconcile takes the higher generation. Where it passes a file before the add-scan does, the add-scan then LOWERS that row to its own generation, and the reconcile, ending, sweeps it. The song leaves the library with its play count, loved flag and (ON DELETE CASCADE) every playlist entry. Nothing re-adds it until the next change in X (local roots are not rescanned at launch, G-LIB-05).
- **Evidence:** Tests/LibraryBrowseKitTests/LibraryBreakItGTests.swift "G-LIB-01" (store level: the swept song and its playlist entry are gone). Tests/LibraryBrowseKitTests/LibraryScanRaceGTests.swift "G-LIB-01b" (real LibraryScanner over 1,200 real files, add-scan leading and slower): 256 of 1,200 files on disk deleted, for a new folder and for an already-scanned one. A temporary harness (removed) with 3,000 files: no loss when both walks run at SSD speed (0 / 20 ms stalls per batch); 512-1,280 files lost when the leading walk runs at 200 ms per 256 files (a USB HDD or NAS walk, the follower reading a warm cache; or a utility-priority add-scan behind a user-initiated volume-mount reconcile).
- **Honest likelihood:** needs an add / re-add walk of a folder overlapping a reconcile of the same folder, with the earlier walk the slower one. Rare on an internal SSD; plausible on external or network folders. Irreversible when it happens. Founder call between R1 blocker and post-R1; the fix is small either way.
- **Fix area:** never lower a stamp (last_seen_scan = MAX(last_seen_scan, ?) in stampLastSeen and moveMatchedSQL) — turns both tests green; and/or serialise per-root walks in LibraryModel (performScan joins reconcilingRoots, runReconcile defers while scanTask walks that root) — the cleaner app-level rule, but leaves G-LIB-01 (store level) red.

### G-LIB-02 — .aif songs never reach the library (also .opus / .oga)

- **Where:** Sources/LibraryScan/LibraryScanner.swift:39-41 (supportedExtensions: flac, mp3, wav, aac, m4a, alac, aiff, ogg).
- **Scenario:** .aif is the extension Music / iTunes give every AIFF they import or rip (and Logic by default). A folder of them scans to "No Music Found"; mixed folders silently lose those songs. Nothing says why. (.opus / .oga: the decoder plays them through the FFmpeg fallback, FileDecodeSource.cpp:13, and MetadataExtractor.swift:78 reads their tags, but the scan never admits them — post-R1, since it needs FFmpeg at runtime.)
- **Evidence:** Tests/LibraryBrowseKitTests/LibraryScanFormatsGTests.swift "G-LIB-02" (aif, opus, oga all skipped by makeScannedFile). Live: with the test library running, copy any AIFF saved as "x.aif" into its music folder; it never appears in Songs (the reconcile walk skips it).
- **Fix area:** add "aif" (and "aifc" if wanted) to supportedExtensions; decide opus / oga with the FFmpeg-availability rule.

### G-LIB-04 — removing a folder leaves the songs that were in the queue in the library, for good

- **Where:** LibraryStore+DAO.swift:144-154 + :349-364 (removeRoot keeps every track ANY playlist_entries row names); the queue is mirrored into the built-in "current" playlist (AudioViewModel+QueueMirror.swift:39-56); loose rows are never swept (sweep is folder-scoped).
- **Scenario:** the dialog promises "Songs from this folder leave your library unless they’re in a playlist" (MusicFolderRemoveDialog.swift:16-17). The queue counts as a playlist, so the songs queued at that moment (the album just played) stay in Songs, Albums and Artists as loose rows; when the queue moves on they stay anyway, and the user has no way to remove them.
- **Evidence:** LibraryBreakItGTests.swift "G-LIB-04" (after removeRoot and an emptied queue, "Queued" is still in the library). Live (test library): Albums ▸ an album ▸ Play; rail ▸ Music Folders ▸ minus ▸ Remove; Songs and Albums still list that album; play anything else; it is still listed. (A relaunch of the test library re-adds the folder.)
- **Fix area:** removeRoot (and its unreferencedTrackIDs filter) should count only user playlists; the queue mirror must then tolerate a deleted id (mirrorQueueNow writes queue track ids — skip ids with no row, or the FK fails the snapshot for the rest of the session).

### G-LIB-05 — music added or deleted while the app is closed never shows (local folders are never caught up at launch)

- **Where:** LibraryModel+Scan.swift:48-69 (launch reconciles network roots only), LibraryWatcher.swift rebuildStreamLocked (kFSEventStreamEventIdSinceNow). Design s8-4 §1.3 relies on "the existing full re-scan (at addRoot / next launch)" for changes made while closed, but D2 then deferred the launch rescan for local roots ("FSEvents catches them live once open"), which it can’t: the stream starts at "now". There is no Rescan control either.
- **Scenario:** quit; copy an album into a music folder (or delete one); launch. The new album never appears (a deleted one stays listed and fails on play) until something else changes in that folder while the app runs, or any volume mounts.
- **Evidence:** code (above); no test can import LibraryModel. Note the DEBUG test library re-scans its folder on EVERY launch (LibraryModel+Scan.swift:62-65), which masks this in every live pass so far.
- **Live repro (not on the test library):** quit the app; in Finder copy one song into a registered music folder; launch the plain app; Library ▸ Songs ▸ Filter for it: expected it appears after a short "Updating library…"; actual: absent. Then touch any file in that folder (or mount a DMG): it appears about a second later. Delete the copied song afterwards (the same lag applies).
- **Fix area:** schedule a reconcile of every reachable root at launch (scheduleReconcile already exists and is cheap for unchanged files), and consider a Rescan item on a folder row.

### G-LIB-06 — adding a second folder while the first is still scanning leaves the first one half-imported

- **Where:** LibraryModel+Scan.swift:100-114 (scanFolderIntoLibrary cancels scanTask — whatever folder it is walking — before it even validates the new folder) and :191-192 (the cancelled walk ends silently, its unwalked files never queued again).
- **Scenario:** add folder A (thousands of songs); while the rail shows "Scanning… N files", add folder B. A’s walk is cancelled: the songs it had not reached are never added. Nothing resumes it: resumePendingMetadata at launch only reads tags of rows already stored, and local folders are not rescanned at launch (G-LIB-05), so A stays partial until a file in A changes. Worse variant: while A scans, try to add a subfolder of A (or the same parent twice): the add is rejected with "Folder inside an existing library folder…", and A’s scan has been cancelled anyway. (Once A’s walk is done, B’s metadata pass reads every pending song, so only the walk phase is exposed.)
- **Evidence:** code (above); LibraryModel can’t be imported by a test.
- **Live repro (test library, a scratch folder):** make a folder with ~2,000 copies of a test song (e.g. from test-data); rail ▸ Music Folders ▸ "+" ▸ that folder; while "Scanning… N files" shows (N well under 2,000), "+" ▸ any other folder with audio. When both settle, Filter / count that folder’s songs: expected ~2,000; actual: about N. Variant: instead of the second folder, pick a subfolder of the first: the error banner appears and the count stops at N too. Remove the scratch folders after (or make reset-test-library).
- **Fix area:** queue adds instead of cancelling them (or cancel only a re-add of the SAME root), validate before cancelling, and on a cancelled walk schedule a reconcile of that root.

## Post-R1 (one line each)

1. **G-LIB-03 (red test)** — New Playlist fails for good beside a playlist named "new playlist" in any other case: createUntitledPlaylist tests taken names case-sensitively, the name index is COLLATE NOCASE (LibraryStore+Playlists.swift:181-201): "Couldn’t create a playlist: UNIQUE constraint failed". Workaround: rename it.
2. **G-LIB-07 (red test)** — MetadataExtractor.parseGenres splits on "/" (MetadataExtractor.swift:160-165): Apple’s own "Singer/Songwriter", "Hip-Hop/Rap", "R&B/Soul" become two Genres tiles each.
3. **.opus / .oga** — playable via the FFmpeg fallback and tag-read, but never scanned (G-LIB-02 red test covers them).
4. **Restore previous queue restores the wrong queue** — Play album A, listen, Play album B, "Restore previous queue" brings back the queue from before A (and if that was empty, clears the queue and stops), because QueueRestorePoint.afterReplace treats any replace of an untouched installed queue as a double-click (VM-QR-02 pins "the song has moved on meanwhile"). Suggest: collapse only replaces within a short window or of the same page.
5. **Drag a multi-selection to a playlist adds one song** — SongRowInteraction.swift:33 drags only the row under the pointer (LibraryTrackDragItem(trackID: track.id)); Music drags the selection. The toast is honest ("Added 1 song").
6. **Sort pill orders within an album by scan order** — Album ↑/↓ is album title then row id, and Artist ↑ reached by toggling is artist then row id (no album grouping), unlike the default "Artist ↑" composite under the same label (LibraryStore+BrowseReads.swift:306-309).
7. **Two Filter semantics** — Songs filters by FTS token prefix ("eatles" finds nothing, LibraryStore+Search.swift:42-48), the grids by substring (FacetTextFilter); and the Songs filter survives a rail jump to Songs while a rail jump clears the grids’ filter (selectCategory clears browseFilter only; searchQuery is never cleared).
8. **Paused folders and reconcile failures are invisible** — reconcileState and lastReconcileError have no UI reader; songs on an unplugged drive look normal in Songs and fail only on play; a folder whose every file was deleted keeps all its songs forever (empty-walk guard, silent).
9. **Playlist rows play on a single click** — PlaylistDetailView.swift:241-245 replaces the queue on a tap, while Songs and the album / artist / genre pages select on click and play on double-click; clicking a row to select it before ⌥⌘↓ or ⌫ starts it playing.
10. **Case and Unicode variants split facets** — artists.name / genres.name are UNIQUE BINARY: "Rock" and "rock" are two tiles; genre names are not NFC-normalised (artists are). Known class (C2 deferred case variants).
11. **A failed metadata pass after a first add shows "No Music Yet"** — LibraryModel+Metadata.swift:41-48 bumps no libraryRevision on failure, so Songs keeps its first-run call to action while the rail lists the folder; the failed state has no retry.
12. **Two quick tile Plays can land out of order** — BrowseTile.play runs an async facetRows read per click; the earlier click’s read can finish last and win. Rare.
13. **Remove Missing can’t tell "drive not connected" from "deleted"** — entries under a paused root count as missing; the dialog removes them for good (E #12 territory; the founder accepted the dialog).
14. **Wording** — the empty playlist says "No Tracks Yet" while the app says "songs" everywhere else (PlaylistDetailView.swift:88).

## What held up

- Search input sanitising (quotes, operators, emoji, all-punctuation, diacritics) never errors or matches everything; newest-wins epochs on every loader.
- Remove folder during its own walk (cancel and await), during a reconcile (later batches fail on the FK, quietly), double-pressed Remove (second is a no-op).
- Playlist reorder against concurrent remove / add / delete (reorderPlaylist ignores foreign ids and appends omitted ones); playlist name uniqueness is case-blind for create and rename; the dialog latch can’t act twice.
- tracksDisplay(ids:) chunks its IN lists; the Songs list stays O(1) per row; selection kit reloads (keepOnly on the pages, filter semantics on Songs) behave as documented.

## Not covered

- Anything visual (colour, contrast, light mode) and VoiceOver: no app launch in this lane.
- G-LIB-05 and G-LIB-06 rest on code reading (LibraryModel is not importable); live steps above.

## Run it again

- swift test --filter "LibraryBreakItGTests|LibraryScanRaceGTests|LibraryScanFormatsGTests|LibraryGenreNamesGTests" (from the worktree).
