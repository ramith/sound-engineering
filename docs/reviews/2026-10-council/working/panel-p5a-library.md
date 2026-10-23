# Panel P5a: library scan / identity / store / search / sort / migration (N30–N71)

Panelist: P5a (adversarial, independent). Repo @ `7d7c2cd` (main). Worktree `.claude/worktrees/panel-p5a`.
Every claim below comes from the real `LibraryScanner` / `LibraryStore` / `LibraryBrowseKit` code, driven by new swift-testing
tests on temp dirs and APFS disk images (`hdiutil`), never the founder's library. The tests are UNCOMMITTED and live in
`Tests/LibraryBrowseKitTests/P5a*.swift` in that worktree; copies are in `scratchpad/council/exp-p5a/`, and the full run
log is `exp-p5a/p5a-run.log`. Each test asserts the CORRECT property, so a red test is the evidence.
Re-run: `swift test --filter P5a`. `VerifyLibraryStore` (157/157 PASS) was also run in the worktree (`exp-p5a/vls.log`).

**Counts (42 rows):** PROVEN-CORRECT 16, DEFECT 14, CORRECT-UNPROVEN 9, QUESTIONABLE 3.
**R1-level:** P5A-01 (sweep after an incomplete walk) and P5A-02 (a different volume at a root's path) are data-loss
bugs. They delete rows that hold play counts, loved/rating and playlist entries (`playlist_entries.track_id … ON DELETE CASCADE`,
`Schema.swift:346`), and both reproduce deterministically.

## 1. Verdict table

| Row | Algorithm | Verdict | Evidence (test → result) | Missing proof / note |
|---|---|---|---|---|
| N30 | `FolderWalkSchedule` | PROVEN-CORRECT (value type) | SCHED-1: my own model (written from the header rules, not the code) checked against the real type over 50 000 random op sequences; safety (one walk/folder, ≤1 add, nothing starts while removing/stopped) + liveness (no request lost at drain): 0 violations. Plus 11 existing tests | Driver `LibraryModel+Walks` untested. Note: the schedule *allows* concurrent walks of different folders, which is what exposes P5A-03 |
| N31 | Watcher routing + debounce | CORRECT-UNPROVEN | Code read: component-boundary routing; trailing 1 s debounce | No test of routing with real FSEvents paths (FSEvents reports resolved `/private/...`, which PathNormalizer normalises differently for removed items: P5A-09); no max-wait, so a long copy postpones the reconcile indefinitely |
| N32 | Reachability precheck | **DEFECT** | LIB-02d: a *different* drive at the root's path is "reachable" → walked → swept | Checks existence, not identity (P5A-02) |
| N33 | Empty-walk guard + end sweep | **DEFECT** | LIB-02a/b: partial walks pass the `filesSeen == 0` guard and sweep songs that are on disk | VLS `q-scan-edge-perm-symlink` tests only a FIRST scan of a locked dir (no rows to lose), so it pins "doesn't abort", not "doesn't delete" (P5A-01) |
| N34 | File admission + batching | PROVEN-CORRECT | VLS g-scan-core, q-, G-LIB-02 | A `makeScannedFile == nil` for an *existing* file (stat fails) counts as "skipped" and the file is then swept, which is part of P5A-01 |
| N35 | Scan generation / stamp / sweep | **DEFECT** | LIB-03b: concurrent walks shared one generation in 20/20 trials; LIB-03c: shared gen → new id + ghost row. G-LIB-01 (never lower a stamp) holds: VLS wo1 + G-LIB-01b pass, and I found no same-folder break | `max(last_seen)+1` is read outside the stamping write and not reserved (P5A-03) |
| N36 | `FileSignature` | **DEFECT** | LIB-03e: whole-second mtime; LIB-02d: `(dev, inode)` collided across two distinct volumes (`sameRootIdentity=true`) | APFS keeps ns timestamps; `st_dev` is a mount-time number, not a volume identity (P5A-02, P5A-07) |
| N37 | classify new/unchanged/modified | **DEFECT** | LIB-03e: a same-size rewrite inside one second → `.unchanged` → never re-read | Same root cause as N36 (P5A-07) |
| N38 | Idempotent upsert | **DEFECT** | UPS-1: replace-in-place (new inode, same size+mtime) → row keeps the dead inode (59244051 vs 59244242) → a later rename mints a new id (2 → 4) | dev/inode are excluded from the no-op `WHERE` (P5A-05) |
| N39 | Move-match | **DEFECT** | LIB-03a: cross-root move loses id when the old root reconciles first; LIB-03b2: concurrent, small old root: 10/10 lost; LIB-03d: hard-link rename lost; LIB-02d run 1: FALSE match (X's rows id16/id40 re-pointed at drive Y's different songs) | VLS `ah-move-reorg-crossroot` only scans the NEW root after the move (the favourable order) (P5A-03, P5A-06) |
| N40 | `moveTrack` | PROVEN-CORRECT | VLS e-, ag- (id kept, typed `URLConflict`) | — |
| N41 | `PathNormalizer` | **DEFECT** (LOCAL) | LIB-03h: `/private/tmp` → `/tmp` but `/private/tmp/<missing>` stays: key depends on existence; LIB-02b: 24 kept rows were re-keyed as NEW rows once the volume vanished; `..` resolves symlinks. LIB-03g (NFD → NFC key, opens, idempotent) PASS | Header claims "pure, no filesystem access, symlinks not resolved"; Apple's `standardizingPath` contract says the opposite (P5A-09) |
| N42 | `RelativePathResolver` | PROVEN-CORRECT | VLS g-scan-core (component boundary) | — |
| N43 | Nested-root validation | **DEFECT** (LOCAL) | LIB-03f: `…/music/rock` accepted beside `…/Music` on a case-insensitive volume; LIB-03f2: rows ping-pong between the two roots on every walk | Case-sensitive string compare on a case-insensitive FS (P5A-10) |
| N44 | Root identity dedup / restamp | **DEFECT** (STRUCTURAL) | LIB-02d: `handleVolumeChange` restamps whatever is at the path, then the reconcile sweeps 58–60/60 songs | P5A-02 |
| N45 | `removeRoot` | PROVEN-CORRECT (store) | VLS pl-gate1-*, G-LIB-04, fts-sweep-removeroot | App side untested |
| N46 | Metadata pass | **DEFECT** (LOCAL) | META-1: tags read before a modification are applied after it and mark the song scanned; new tags are never read | No optimistic signature check on apply (P5A-08) |
| N47 | Pass supersession / launch resume | CORRECT-UNPROVEN | Code read: cancel + await chain, `guard scanTask == nil` | No test |
| N48 | Derived-data version bump | PROVEN-CORRECT | VLS alb03 (re-read keeps user data, one write) | — |
| N49 | Album identity `AlbumGrouping.keys` | QUESTIONABLE | Heuristic key (title, tag \| folder, edition year); BINARY title compare; no MusicBrainz Release ID | Tests are literal + self-oracle (`Fixtures.swift` calls the production function) |
| N50 | Tag adoption | CORRECT-UNPROVEN | VLS alb13 (literal) | No property test |
| N51 | Year split | QUESTIONABLE | Product rule; literal tests (alb11, alb17) | — |
| N52 | `dominantYear` | QUESTIONABLE | YEAR-2: equals a brute-force oracle on 20 000 random inputs (its own spec is PROVEN); YEAR-1: store = 1995, facet page = 1994 for the same tie | Two rules for one concept (LIB-13 confirmed) |
| N53 | `derivedArtist` | CORRECT-UNPROVEN | VLS alb02/04/14/16 (literal) | — |
| N54 | Name normalisation | CORRECT-UNPROVEN | Album title / artist / album artist are NFC + trimmed (`TrackMetadata.init`) | **Title, genre and filename `name` are NOT normalised**, which is what breaks SRCH-2 (filed under N63) |
| N55 | Folder / disc grammar | CORRECT-UNPROVEN | Code read; literal tests | LIB-13's "disc parsing duplicated" is **REFUTED**: the kit calls `AlbumGrouping.discNumber(ofFolderName:)` (`LibraryTrackDisplay+DetailTrack.swift:13`). Only "album folder" differs (kit: immediate parent; store: iterated fold). No "Side A/B", no non-English ("Disque 1") |
| N56 | Album display (year + cover) | CORRECT-UNPROVEN | VLS aa (cover deterministic) | Year tie see N52 |
| N57 | Store regroup | CORRECT-UNPROVEN | VLS alb06–10 (literal) | Not attacked in depth |
| N58 | Facet orphan sweep | PROVEN-CORRECT | VLS ai/aj/ak; SQL reviewed: every `NOT IN` sub-select filters NULL (the classic trap avoided) | — |
| N59 | Orphan artwork sweep | PROVEN-CORRECT | VLS u-, ak- (pure reachability) | — |
| N60 | Genre cover ranking | PROVEN-CORRECT | VLS GC-05: independent Swift reference at 10k songs / 300 genres | — |
| N61 | FTS query sanitizer | PROVEN-CORRECT (injection) | SRCH-4: 3 000 random strings of FTS5 syntax (`" * ^ : ( ) NEAR AND OR NOT { } NEAR/2 \0`…): 0 throws, 0 match-all; `OR`/`NOT`/`title:` are literal | Tokenizer behaviour is N62/N63 |
| N62 | `search()` / `searchMatchingIDs` | **DEFECT** (SIGNIFICANT for this founder) | SRCH-1: "මාල" (necklace) also returns "මිල" (price) and "මුල" (root); SRCH-5: the facet filter does the same; SRCH-3: CJK word inside a title not found; SRCH-5: "ear" finds "Pearl Jam" in Artists, not in Songs; `search()` has 0 app callers | P5A-04 |
| N63 | Search-index maintenance | **DEFECT** (LOCAL) | SRCH-2: NFD Hangul filename "노래" not found by the NFC query (0 hits) | Index text is not NFC-normalised; tokenizer uses default categories (P5A-04). Sync completeness itself: VLS fts-sync-* (op counter, not a state check: LIB-11) |
| N64 | Track sort orders | PROVEN-CORRECT (to spec); spec questionable | SORT-1: all 26 `TrackSort`s vs an independent oracle written from the docs (SQLite NOCASE = ASCII-only fold, documented NULL placement, id tiebreak in sort direction), 160 rows with ties, NULLs, case/diacritic variants, Sinhala: 0 mismatches; each a permutation (total order) | NOCASE is not UTS #10: "Ångström"/"Émile" sort after "Z", "track 10" before "track 2", and the facet pages use `localizedStandardCompare` (Q-4) |
| N65 | Facet orders | CORRECT-UNPROVEN | VLS c-facets, br2 (literal) | Same collation question |
| N66 | Playlist store rules | **DEFECT** (LOCAL) for names; reorder PROVEN | PL-1: `reorderPlaylist` == `ListOrder.applying` on 300 random partial/duplicate/foreign orders (closes the map's "no cross-test"); names "Été"/"été"/"ÉTÉ" and NFC vs NFD "Café" all accepted as distinct: 5/5 | P5A-11 |
| N67 | Migrator | PROVEN-CORRECT | MIG-1 (new): stores built at EVERY historical version v1…v6 with user rows (play counts; playlists from v3) opened through the real open path → schema 7, plays `[1…5]`, entries `[30,10,50]` intact, one `.pre-v7` backup each. Plus VLS staged/fresh fingerprint convergence | Gap closed by MIG-1: VLS stages only from v1 and compares SCHEMA, not DATA |
| N68 | Open / refuse / repair | PROVEN-CORRECT | VLS open01–06, schema5/5b/6 (newer store refused byte-identical, incl. hot WAL) | Corrupt → quarantine + empty rebuild, no salvage (Q-5) |
| N69 | `StoreQuarantine` | PROVEN-CORRECT | VLS schema5-corrupt, open05; moves `-wal`/`-shm` with the main file ([SQLite "How To Corrupt"](https://www.sqlite.org/howtocorrupt.html): a WAL must travel with its database; section not re-checked) | — |
| N70 | `StoreBackup` | PROVEN-CORRECT | VLS open02–04; MIG-1 saw a backup per upgrade | — |
| N71 | v6→v7 guards | PROVEN-CORRECT | VLS alb06, open06 | Permanent code for a test-only state (LIB-10) |

## 2. DEFECT details

### P5A-01: The sweep deletes songs a walk failed to see (LIB-02 PROVEN) (STRUCTURAL, R1 blocker)
- **Rows:** N33, N34 (and N35's sweep).
- **Spec:** a sweep may delete only rows whose file is *positively known* to be gone. A file the walk couldn't read is not
  known to be gone. Apple: the enumerator's `errorHandler`, *"If you specify nil for this parameter, the enumerator object
  continues to enumerate items as if you had specified a block that returned true"*
  ([FileManager.enumerator(at:includingPropertiesForKeys:options:errorHandler:)](https://developer.apple.com/documentation/foundation/filemanager/enumerator(at:includingpropertiesforkeys:options:errorhandler:))).
  So errors are silently swallowed. The same page: *"If the method is passed a directory on which another file system is
  mounted (a mount point), it traverses the mount point"*. A sub-volume under a root that unmounts is one more way to get
  a partial walk.
- **Evidence (real scanner + store):**
  - LIB-02a, `chmod 000` and `chmod 444` (r without x) on one of two album folders: `seen=5 swept=5`; the 5 songs are
    still on disk; the playlisted song's row, its playlist entry (1 → 0) and its 2 plays are deleted.
  - LIB-02b, an APFS image with 800 songs, all in a playlist and all played; the volume is force-detached after the
    reconcile's first 256-file batch: `seen=280 swept=544 kept=280/800 playlistEntries=256/800`. After remount, 800/800
    files are on disk. 24 of the "kept" rows are actually NEW rows re-keyed by P5A-09 once the files stopped existing.
  - Control: a genuine delete after a complete walk sweeps exactly 1 (PASS), so the fix must not weaken real deletes.
- **Root cause:** `LibraryScanner.swift:131` passes no `errorHandler`. The only completeness evidence is
  `filesSeen == 0 && preCount > 0` (`:94`). `sweepOrphans` (`LibraryStore+DAO.swift:267`) deletes immediately and
  irreversibly, and the delete cascades to playlist entries.
- **Remedy:**
  1. (S, low risk, before R1) Add an `errorHandler` that records any error and returns `true`. After the walk, refuse the
     sweep (throw like `RootUnreachableError`) if any error was recorded, if any supported-extension entry failed
     `makeScannedFile` while still existing, or if the root is no longer reachable / on the same volume UUID (P5A-02).
     Add a proportional guard: refuse a sweep that would remove more than X% of the folder unless two consecutive clean
     walks agree.
  2. (L) Replace DELETE with a `missing_since` tombstone (additive v8). Reads filter it, a GC purges after N days or N clean
     walks, and move-match may resurrect a tombstoned row. This is the state of the art:
     [Navidrome](https://www.navidrome.org/docs/usage/library/missing-files/): *"Missing files are not removed from the
     database on new scans"* (default `Scanner.PurgeMissing = "never"`), so play counts and playlist references survive,
     plus a `missing fix` remap. Music.app shows "!" rather than dropping the track.
- **Effort/risk:** step 1 S/low; step 2 L/med (every read's WHERE). Add LIB-02a/b as gate tests.

### P5A-02: A root is identified by its path only; another volume at that path is walked and swept (STRUCTURAL, R1)
- **Rows:** N32, N44, N36 (`st_dev`).
- **Spec:** a root's identity must survive remounts and must *distinguish* volumes. `st_dev` is assigned at mount time,
  so it is not that identity. Apple provides a persistent per-volume UUID:
  [`URLResourceKey.volumeUUIDStringKey`](https://developer.apple.com/documentation/foundation/urlresourcekey/volumeuuidstringkey),
  *"the volume's persistent UUID"*.
- **Evidence (LIB-02d):** two APFS images with the same volume name "T7" (two same-model SSDs, or two "Untitled"/"NO NAME"
  sticks, mount at the same `/Volumes/<name>`). Drive X has 60 songs, all in a playlist. X is detached, and Y (a
  `Music` folder with 2 other songs) is attached at the same path. Then I ran the app's `handleVolumeChange` sequence
  (`RootReachabilityProbe` → `restampRoot` → reconcile). Result: `reachable=true sameRootIdentity=true seen=2`, swept 58
  (run 1) / 60 (run 2). In run 1 the 2 surviving playlist rows were a **false move-match**: X's ids 16 and 40 now point at
  Y's `Other/000 Y`, `Other/001 Y`, so X's play history sits on a different song. Even `(dev, inode)` of the two
  distinct `Music` folders was equal (the dev number was reused and fresh APFS inode sequences match).
- **Root cause:** `LibraryModel+VolumeMonitor.swift:49-52` restamps any directory at the path, and `restampRoot`
  (`LibraryStore+Roots.swift:18`) accepts it unconditionally. Move-match trusts `(dev, inode, size, mtime-second, format)`.
- **Remedy:** store `volumeUUID` (plus the root's file ID) per root. Treat a mismatch as "a different volume": pause, never
  walk or sweep, and ask the user. Use the volume UUID instead of `st_dev` in the move signature. Effort M, risk low-med
  (additive column).

### P5A-03: Cross-root moves lose identity, depending on order; the generation is not unique (LIB-03 PROVEN) (SIGNIFICANT)
- **Rows:** N35, N39.
- **Evidence:**
  - LIB-03a, sequential: old root reconciled first → new id 61 ≠ 28, playlist entry and 3 plays deleted. New root
    first → id kept.
  - LIB-03b2, the app's real shape (one FSEvents batch, two 1 s debounces, `FolderWalkSchedule` runs the two folders
    concurrently), small old root, 3 000-song new root: **10/10 trials lost the id**. With equal sizes: 0/20 lost (a race).
  - LIB-03b: the two concurrent walks got the same generation in 20/20 trials.
  - LIB-03c (DAO-level interleaving): with a shared G, the old walk stamps the song at G before the move, so the new walk's
    candidate filter `last_seen_scan < G` excludes it. Result: a new id, and the old row survives its own sweep as a ghost
    (`007 A.flac`), to be deleted by the next walk.
- **Root cause:** `beginScanGeneration` is `max(last_seen_scan)+1` in a separate read (`DAO:167-175`), so it is neither
  unique nor reserved. Move candidates are global, but deletion is per-folder and immediate. "Not stamped this
  generation" stands in for "the old file is gone", which it isn't.
- **Remedy:** (a) the move-source predicate should be "the row's url no longer exists on disk" (one `lstat` per
  candidate), not only `last_seen_scan < G`; (b) with P5A-01's tombstone, a later move-match resurrects the row whatever the
  order; (c) allocate the generation inside a write (a counter row) so it's unique. Effort M, risk med.
- **Existing tests:** VLS `ah-move-reorg-crossroot` scans only the new root after the move, so it pins the happy order.

### P5A-04: Search ignores Sinhala vowel signs; NFD text is unsearchable; tabs disagree (SIGNIFICANT)
- **Rows:** N62, N63 (N54 gap).
- **Spec:** FTS5 §4.3.1 ([sqlite.org/fts5.html#unicode61_tokenizer](https://www.sqlite.org/fts5.html#unicode61_tokenizer)):
  *"all unicode characters assigned to a general category beginning with "L" or "N" … or to category "Co" … are considered
  tokens. All other characters are separators."* The default `categories` is `"L* N* Co"`. So Mn/Mc marks, which include
  every Sinhala vowel sign (U+0DCF–U+0DDF) and the virama (U+0DCA), are **separators**. The doc's own example of the
  remedy is `tokenize = "unicode61 categories 'L* N* Co Mn'"`. unicode61 does not normalise, so NFC vs NFD must be fixed
  before indexing ([UAX #15](https://unicode.org/reports/tr15/)).
- **Evidence:**
  - SRCH-1: "මාල" → [මාල, මිල, මුල]; "මිල" → the same three; "මුල" → the same three (necklace / price / root).
  - SRCH-5: the Albums/Artists/Genres filter (`localizedStandardContains`, diacritic-insensitive) also says "මාල" ⊇ "මිල",
    so neither path keeps Sinhala vowels.
  - SRCH-2: an untagged song whose filename is NFD Hangul "노래" gets 0 hits for the NFC query. Latin NFD "Café" works,
    because unicode61 folds U+0300-range diacritics.
  - SRCH-3: "事変" does not find "東京事変" (an unsegmented CJK run is one token).
  - SRCH-5: "ear" finds "Pearl Jam" in Artists (substring) but not in Songs (prefix-token). `search()` has 0 app callers
    (LIB-05 confirmed). The playlist menu is a fourth rule (`localizedCaseInsensitiveContains`).
- **Prototype of the fix** (python sqlite 3.45, `exp-p5a/fts.py`): with `unicode61 remove_diacritics 2 categories
  'L* N* Co M*'`, "මාල" → [මාල] only, "මිල" → [මිල] only, and Latin "cafe"/"bjork" still match "Café"/"Björk". The trigram
  tokenizer also fixes Sinhala but needs ≥ 3 characters (FTS5 §4.3.4), so "事変" stays unmatched.
- **Remedy:** an additive migration that rebuilds the derived `tracks_fts` with `categories 'L* N* Co M*'` (FTS is a
  derived cache, so dropping and rebuilding it keeps the additive-only rule); NFC-normalise title/name/genre at write and
  the query in `ftsMatchQuery`; for facet filters use `.caseInsensitive` without `.diacriticInsensitive` for scripts whose
  marks are letters (or one shared matcher, per LIB-05). Optional: trigram as a second index for CJK infix. Effort S-M,
  risk low.

### P5A-05: A file replaced in place keeps a dead inode, so its next rename loses the id (LOCAL)
- **Row:** N38. **Evidence:** UPS-1: copy (new inode), restore the mtime, rename over the original (a Time Machine / backup
  restore, `cp -p` + `mv`, or an rsync temp-and-rename) → rescan → stored inode 59244051 vs disk 59244242 → rename → new id
  4 ≠ 2.
- **Root cause:** `upsertTrackSQL`'s conflict `WHERE` (`DAO:85-90`) omits dev/inode by design, so the signature is never
  refreshed when only it changed.
- **Remedy:** a second cheap `UPDATE tracks SET dev=?, inode=? WHERE url=? AND (dev IS NOT ? OR inode IS NOT ?)` that does
  not reset `metadata_scanned`. A no-op rescan still writes nothing. Effort S.

### P5A-06: Renaming one of two hard links loses its id (LOCAL)
- **Row:** N39. **Evidence:** LIB-03d: `one.flac` + hard link `two.flac`, rename `one` → `aaa` → LOST on the first try.
  Two rows share the signature, and when the walk reaches `aaa` before `two`, `LIMIT 2` sees both → "ambiguous" → new id.
- **Remedy:** the same as P5A-03(a): exclude candidates whose url still exists. The survivor is then unique. Effort S.

### P5A-07: Whole-second mtime misses a same-size rewrite in the same second (LOCAL)
- **Rows:** N36/N37. **Evidence:** LIB-03e: rewrite with the same size and mtime .100 → .900 s → `.unchanged`, never re-read.
- **Remedy:** store mtime in ns (APFS has ns `st_mtimespec`), or add `ctime`/change-count to classify. Keep seconds for
  the move signature only. Effort S (additive column). (Reference from memory, not re-opened: beets compares a float mtime in `update`.)

### P5A-08: Metadata pass lost update (LOCAL)
- **Row:** N46. **Evidence:** META-1: pending → extract → the file is modified and the reconcile resets
  `metadata_scanned=0` → the stale apply writes the old tags and marks the song scanned (`pendingAfterStaleApply=false`).
- **Remedy:** optimistic apply: carry the extracted `(size, mtime)` and make `applyExtractedResult` a no-op (leave the
  song pending) when the row's signature differs. Effort S.

### P5A-09: `PathNormalizer` is neither pure nor symlink-free (LOCAL)
- **Row:** N41. **Spec:** Apple `standardizingPath`
  ([doc](https://developer.apple.com/documentation/foundation/nsstring/standardizingpath)): *"Removing an initial component
  of "/private/var/automount", "/var/automount", or "/private" from the path, if the result still indicates an existing file
  or directory (checked by consulting the file system)"* and *"resolving references to the parent directory … using
  resolvingSymlinksInPath"*.
- **Evidence:** LIB-03h: `/private/tmp` → `/tmp`, `/private/tmp/<missing>` → unchanged. LIB-02b: 24 rows re-keyed as
  new once the files vanished. Probe: `link/../f.flac` → `real/f.flac` (symlink resolved).
- **Impact:** low for `/Users` and `/Volumes`; real for anything under `/private` (temp dirs, test folders), and FSEvents
  routing of removed items under such roots (N31).
- **Remedy:** a lexical normaliser (collapse `//`, `.`, lexical `..`, no `/private` stripping), or resolve both sides
  with `realpath(3)` / `canonicalPathKey` at registration. Add the vector tests the map asked for. Effort S.

### P5A-10: The nested-root check is case-sensitive on a case-insensitive volume (LOCAL)
- **Row:** N43. **Evidence:** LIB-03f: `…/music/rock` validated against `…/Music` → accepted. LIB-03f2: each walk moves
  the 4 rows to its own root (`outer=4 inner=0 → 0/4 → 4/0 → 0/4`), which is the ping-pong the file header warns about.
  A symlink root is also accepted (harmless: per Apple, the enumerator URL *"must not be a symbolic link"*, and it yields 0).
- **Remedy:** compare `realpath(3)` / `canonicalPathKey` values (both return the on-disk case, probed), or walk ancestors
  comparing volume UUID + file ID. Realism is low (NSOpenPanel returns on-disk case). Effort S.

### P5A-11: Playlist-name uniqueness is ASCII-only and not NFC (LOCAL)
- **Row:** N66. **Evidence:** PL-1: "Été", "été", "ÉTÉ", NFD "Café", NFC "Café" → 5/5 created. SQLite NOCASE folds
  only ASCII ([datatype3 §7.1](https://www.sqlite.org/datatype3.html#collating_sequences)), while
  `lowestUnusedDefaultName` uses full-Unicode `lowercased()`, so the two halves of one rule disagree.
- **Remedy:** NFC-normalise in `validatedUserName`, and check uniqueness with `caseInsensitiveCompare` / a stored
  `name_key = NFC + case-fold` with a unique index (additive). Effort S.

## 3. QUESTIONABLE details

- **Q-1 (N49) Album identity.** A reasonable Apple-Music-like heuristic, but the title key is BINARY ("Abbey Road" ≠
  "Abbey road") and MusicBrainz IDs are ignored. State of the art (beets, Picard) groups by `MUSICBRAINZ_ALBUMID` when
  present (Picard writes `MusicBrainz Release Id`; link not re-opened: https://picard-docs.musicbrainz.org/en/variables/tags_basic.html) and falls back to heuristics.
  Cost: read one more tag; additive column. Tests are literal / self-oracle.
- **Q-2 (N51) Year split.** A product rule; fine as documented.
- **Q-3 (N52/N76, LIB-13) Two album-year tie rules.** Store: tie → LATEST (`AlbumGrouping+Years.swift:25`); kit fallback:
  tie → EARLIEST (`FacetAlbumGrouping.swift:~101`). YEAR-1 shows they disagree on the same input (1995 vs 1994). The kit
  path runs only when `al.year` is 0/NULL while songs have years, which happens mid-metadata-pass because album work is
  deferred to the end-of-pass regroup. So the disagreement is transient, and the kit copy is near-dead code. Remedy: the
  kit calls `AlbumGrouping.dominantYear`. LIB-13's disc-parser duplication claim is REFUTED (see N55).
- **Q-4 (N64/N65) Collation.** Implementation PROVEN to spec (SORT-1), but the spec is SQLite NOCASE (ASCII fold, code-point
  order), not [UTS #10](https://unicode.org/reports/tr10/) / Finder order. "Ångström" sorts after "Zoë", and "track 10"
  before "track 2". Album sections on artist pages use `localizedStandardCompare`, so the same titles order differently in
  two places. Remedy: a registered ICU / `localizedStandardCompare` collation (GRDB `DatabaseCollation`) or a precomputed
  sort key column. Cost: index rebuild.
- **Q-5 (N68) Corrupt store.** Quarantine + empty rebuild is safe (nothing deleted), but user data stays stranded in the
  quarantined file. SQLite ships a salvage API ([recovery extension](https://www.sqlite.org/recovery.html)) that could
  copy `playlists`, `playlist_entries` and the user columns into the fresh store.
- **Q-6 (N62) CJK infix.** A known unicode61 limitation; trigram (≥3 chars) or an ICU word-break tokenizer is the remedy.

## 4. Where I agree / disagree with earlier evidence (area-library.md)

- **LIB-02:** agree, and it is worse than stated: PROVEN with three independent triggers (unreadable subfolder, volume lost
  mid-walk, a same-named drive), plus one false move-match.
- **LIB-03:** agree; PROVEN (sequential, concurrent 10/10, DAO interleaving). Addition: the existing cross-root VLS check
  covers only the favourable order.
- **LIB-05:** agree; PROVEN. Addition: the facet filter also fails Sinhala (diacritic-insensitive folding treats vowel signs
  as diacritics).
- **LIB-13:** tie rules agree (PROVEN divergent, but reachable only transiently). Disc-folder parsing duplicated: disagree
  (single parser).
- **LIB-17:** agree (PathNormalizer); P5A-09 adds the Apple-doc evidence and a demonstrated re-keying.
- **G-LIB-01 fix:** I could not break the same-folder fix (VLS wo1 + G-LIB-01b pass, `MAX()` stamps). Its blind spot is
  cross-folder (P5A-03).

## 5. Top missing proofs (tests to add to the gate)

1. LIB-02a/b/d as permanent gate tests (partial walk ⇒ zero sweep; different volume ⇒ zero sweep).
2. Cross-root move in both orders and concurrently (LIB-03a/b2).
3. A store-state FTS invariant (`tracks_fts` == projection of `tracks`, `EXCEPT` both ways) after every scenario, and
   a Sinhala/NFD search test (SRCH-1/2).
4. PathNormalizer vector tests (`/private`, `..`+symlink, NFD, trailing slash).
5. Driver tests for `LibraryModel+Walks` / `+Reconcile` / `+VolumeMonitor` (none exist).
6. Keep MIG-1 (data convergence from every version), SORT-1 (oracle) and SCHED-1 (model check): they are the
   independent oracles the rows lacked.
