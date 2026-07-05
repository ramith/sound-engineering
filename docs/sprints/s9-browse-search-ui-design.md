# S9 — Browse & Search UI (design)

Status: **VETTED — multi-discipline GO-WITH-CHANGES (all applied). Pending final gate (architect
challenge + the-fool) + founder sign-off on the §1 decisions.** Sprint S9 of the Phase-1
player-maturity arc, on `main` (Swift 6.2 language mode, `.macOS(.v26)`, complete concurrency =
errors). Synthesized from a codebase surface-map + a six-discipline review panel (architect ·
ui-designer · refactoring-specialist · qa-expert · swiftui-pro · competitive research). Follows
the S8.x design idiom; §11 records every finding + resolution.

## 0. Scope & what already exists

S9 turns the shipped-but-unread S8 library spine into a **browseable, searchable, playable**
library — the first UI that reads from `LibraryStore`. Credibility critical-path toward R1.

**In scope:** a **Library** tab (Music.app-style `NavigationSplitView`: sidebar Albums · Artists ·
Songs · Genres · Years + drill-down detail); album grid with cover art; incremental FTS5 search;
and **real queue actions** — Play Now (replace+play), Play Next, Add to Queue — **positional**
(see §1.3).

**Already exists (do NOT rebuild):** the store WRITE + READ-primitive side (S8.1–8.4); facet reads
(`albums`/`artists`/`genres`) and track reads (`allTracks`/`tracks(inAlbum:)`/`track(id:)`) returning
`Sendable` values; the S8.3 artwork cache (`ArtworkCache.thumbnailPath(forOriginal:)`); the
`user_version`-gated single-transaction `MigrationRunner` (+ downgrade→quarantine, verified sound);
the gapless engine + on-deck (`playlist`/`selectedTrackIndex`/`pendingNextIndex`, the **pure**
`computeNextIndex`, the `adjustPendingNextIndexAfterRemoval` re-arm idiom); `DesignSystem` tokens,
`FormatBadgeView`, `formatDuration`; the segmented tab bar (a custom `switch`, **not** a `TabView`).

**S9 builds:** DAO read additions incl. a `LibraryTrackDisplay` name-projection · an FTS5 index
(V2 migration + a `SearchIndex` write-path seam) · a Swift-6-clean artwork thumbnail loader ·
positional queue ops on the existing on-deck machinery · a `LibraryBrowseModel` owned above the
tab switch · the `NavigationSplitView` tree · tests.

## 1. Locked decisions (founder sign-off needed on ★-marked)

1. **Navigation = two-column `NavigationSplitView`** (sidebar Albums·Artists·Songs·Genres·Years +
   a `NavigationStack(path:)` detail for variable-depth drill-down), nested in a new `.library`
   tab. Grows into S10 playlists. (Not three-column: category roots are heterogeneous — grid vs
   Table vs list — and a rigid middle column fights variable drill-down depth.)
2. **Search = SQLite FTS5**, the first real V1→V2 migration. Playlist tables (S10) become V2→V3.
3. ★ **Queue = Play Now / Play Next / Add to Queue in S9, with Play Next honored even under
   shuffle via a single-slot override.** Play Next inserts after current and arms that slot as the
   on-deck **directly** (`armOnDeck`, bypassing `computeNextIndex`) — Music.app's behavior, works
   under shuffle AND linear (§6). Only the **multi-item forced-next FIFO** (which would need a
   *stateful* `computeNextIndex`, races the 20 Hz gapless-seam window, and can't be gated against
   real code today — §11-Q) DEFERS to S10's "queue reorder/save/history." *(Final gate raised the
   bar here: the earlier "positional-only, best-effort under shuffle" was both a self-contradiction
   and a broken-feeling UX; the single-slot override fixes both at near-zero cost.)*
4. **Defer US-LIB-07** (folder-to-folder drag = real filesystem move). In-app drag in S9 is
   **queue-only** via a custom-UTType `Transferable` (never `.fileURL`), so a drag can never
   masquerade as a filesystem move.
5. ★ **Dark-locked for S9** (`.preferredColorScheme(.dark)` at the window-content root). The
   `DesignSystem` palette is hardcoded white-opacity-on-dark with no asset catalog; a real
   light mode is its own sprint. Dark-first is a legitimate audiophile-player choice (Roon,
   Audirvana). This makes every token correct-by-decree and removes "light/dark" from S9's test
   surface. ★ The real risk isn't light-vs-dark, it's **half-themed AppKit surfaces** (final-gate
   #8: `NSMenu` context menus, the `.searchable` field, `Table` headers/sort indicators, focus
   rings) that `.preferredColorScheme` doesn't always force → verify each renders dark in the S9.4/5
   `make run`, and if any leak, set `NSApp.appearance = NSAppearance(named: .darkAqua)` at launch as
   belt-and-braces. Long-term light mode = deferred (needs a semantic/asset-catalog palette).
6. **Interaction model** (native macOS, corrected from the first draft): **single-click on an
   album cell NAVIGATES** to detail (`NavigationLink(value:)`), never destructively plays; Play is
   a secondary action reachable three ways (hover play-button on the art · context menu · VoiceOver
   custom action). **All track lists use `List`/`Table(selection:)`** — single-click selects,
   double-click / `Return` = Play Now. This retires the existing `PlaylistView` `onTapGesture` +
   per-row `onKeyPress` anti-pattern and makes every action keyboard/VoiceOver-reachable.

## 2. Navigation & view tree

New `Sources/AdaptiveSound/UI/Library/` (peer to `UI/Tabs/`). Tab wiring: add `case library` to
`TabSelection` (title/subtitle/SF-Symbol); add `case .library: LibraryTabView()` to
`TabContentView`; the segmented `TabSelectorView` (iterates `.allCases`) picks it up. Put `.library`
first (home/entry).

**★ Make-or-break (swiftui-pro §0): the tab area is a `switch`, not a `TabView` — leaving `.library`
DESTROYS `LibraryTabView` and any `@State` in it.** Therefore **all** browse state
(`selectedCategory`, `path: [LibraryRoute]`, `columnVisibility`, `selection`, `searchQuery`, loaded
arrays) lives on `LibraryBrowseModel` (§7), owned as `@State` in the `App` and injected via
`.environment` — never `@State` in `LibraryTabView`. Use the `NavigationSplitView(columnVisibility:
sidebar:detail:)` initializer bound to the model (the parameterless init stashes visibility in
private `@State` that dies on teardown). Register `navigationDestination(for: LibraryRoute.self)`
**once** at the `NavigationStack` root; push via `NavigationLink(value:)` only (never
`NavigationLink(destination:)`). Model-owned arrays mean returning to the tab shows cached data
instantly, `.task` refreshes in the background (no empty-flash).

`.searchable(text: $model.searchQuery, placement: .sidebar)`. When `!searchQuery.isEmpty`, the
category root swaps to `LibrarySearchResultsView`. Empty/first-run: no roots → a CTA reusing the
folder-pick flow; scanning → a **two-phase** banner (scan is *indeterminate* — `ScanProgress.total
Files` is nil; metadata pass is *determinate*), zero results → `ContentUnavailableView.search`.

## 3. Store read additions (DAO) + the name projection

All in `LibraryStore+Reads.swift`/`+Facets.swift` (actor-isolated, `throws`, project through
`fetchTracks`/`mapTrackRow`, **LEFT JOIN + `COALESCE(...,'')`**, no FS calls, fully synchronous per
the actor invariant). Supporting indexes exist.

1. ★ **`LibraryTrackDisplay` name-projection (required, not optional; ADDED alongside — not a
   re-type).** `LibraryTrack` carries `artistID`/`albumID` but **not the names** — a Songs/search
   row can't render "Title · Artist" from it, and resolving per-row would be N queries. Add a
   `Sendable` `LibraryTrackDisplay` (superset with resolved `artistName`/`albumName`, `title`
   falling back to filename `name`) built by a SQL LEFT JOIN. Expose **NEW** Display-returning reads
   (`allTracksDisplay`, `tracksDisplay(inAlbum:)`/`(byArtist:)`/`(inGenre:)`, and `search`) **beside
   the existing `LibraryTrack` reads, which stay unchanged** — the harness/gate callers of
   `allTracks`/`tracks(inAlbum:)` (`ChecksFSDivergence.swift:58`, `ChecksConcurrency.swift:367`)
   must not break (final-gate #4: re-typing them is a breaking change to tested code). **The UI
   never renders `relativePath` (a filesystem path).**
2. **Artwork path (batched):** `artworkCachePaths(forKeys:) -> [String:String]` (chunk the IN-list
   at a few hundred; limit is 32766). Single-key convenience wraps it.
3. **Drill-downs:** `albums/tracks(byArtist:)`, `albums/tracks(inGenre:)` (JOIN `track_genres`).
4. **Year facet:** `years() -> [Int]` (distinct desc), `albums(inYear:)`.
5. **Single-facet:** `album(id:)`, `artist(id:)` (detail headers; no client-side list-filtering).
6. **Search:** `search(_:limit:) -> SearchResults` (`{tracks:[LibraryTrackDisplay]; albums:[Album
   Facet]; artists:[ArtistFacet]}`), §4.
7. **Pagination guard:** optional `limit`/`offset` on `albums()`/`artists()`/`allTracks()` (nil =
   current unbounded behavior; non-breaking). UI does **not** paginate pre-emptively (§8 Songs).
8. **Query-plan discipline:** every hot read must `SEARCH … USING INDEX`, never `SCAN TABLE tracks`
   — asserted by `EXPLAIN QUERY PLAN` tests (§10, the portable scale gate).

## 4. FTS5 — schema V1→V2 + a `SearchIndex` write-path seam

**Table (V2), rowid = `tracks.id`:**
```sql
CREATE VIRTUAL TABLE tracks_fts USING fts5(
    title, artist, album, genre, tokenize = 'unicode61 remove_diacritics 2');
```

**★ Encapsulate ALL maintenance behind ONE internal seam** (not scattered inline SQL, not SQL
triggers — the single-writer actor lets us maintain it explicitly, and one seam makes completeness
provable):
- `syncSearchRow(trackID:)` — SELECT this track's LEFT-JOINed `COALESCE(title,name)/artist/album/
  group_concat(genre)`, then delete-then-insert its FTS row (rowid = id).
- `deleteSearchRows(ids:)` / a `WHERE rowid IN (SELECT id …)` set form.

**Call sites (the completeness invariant: every track mutation calls one of the two):**
- `upsertOne` INSERT branch (`+DAO.swift:274`) — new row: minimal FTS row from filename so a
  pre-metadata track is findable. **★ Only on a genuine insert** (capture `changes()`/the `.new`
  classification before the unconditional `stampLastSeen`), else a steady-state re-scan churns FTS
  for every unchanged file (breaks the idempotency contract).
- `applyMetadataLocked` (`+Facets.swift:128`) — full enrichment. ★ Place the `syncSearchRow` call
  **inside `applyMetadataLocked`, AFTER `replaceGenres`** (so `group_concat(genre)` is fresh), **not**
  in `applyExtractedResult` — else the public `applyMetadata` entry point silently skips FTS. It
  still commits within the existing per-track transaction.
- ★ **`moveMatchedLocked` (`+MoveMatch.swift:104`) — THE BLOCKER FIX.** The scanner's real reconcile
  path writes `name`/`format` and does **not** reset `metadata_scanned`, so a renamed-in-place
  tagless file would keep a stale FTS title. Call `syncSearchRow` here too. *(The design's first
  draft wrongly excluded "move" by only looking at the app-level `moveTrack`.)*
- Delete sites (grep-verified exhaustive — exactly three `DELETE FROM tracks`): `delete(id:)`,
  `deleteTrackRows(ids:)` (covers `removeRoot`), and **`sweepOrphans`** — ★ capture the doomed ids
  (or `DELETE … WHERE rowid IN (SELECT id … WHERE last_seen_scan<gen)`) **before** the tracks
  DELETE, same txn (reversed order → subquery finds nothing → FTS rows leak).
- `moveTrack` (app-level, url/folder only) and facet-sweep (deletes only zero-reference facets, so
  no live track's FTS goes stale) are correctly **excluded**.
- **SEQ-1 follow-up:** when S10's `playlist_tracks` filter lands, `removeRoot`'s "keep loose
  survivors" must keep *their* FTS rows — gated with the existing SEQ-1 known-issue.

**Migration `migrateV1toV2`:**
- Body uses `connection.exec(...)` **directly** — the runner already owns the single `BEGIN
  IMMEDIATE`; a nested `transaction {}` throws.
- Create the vtable, then **backfill** `INSERT … SELECT` with **LEFT JOINs + `COALESCE(...,'')`**
  (an INNER JOIN would silently drop tracks with no album/artist/genre from the index).
- Call `Schema.writeSchemaInfo(connection, version: 2, …)` so provenance tracks `user_version`.
- Bump `currentSchemaVersion = 2` **in the same change** as adding the step to `productionMigrations`.
  ★ (Final-gate #3, corrected: bump-without-step → `.migrationMissing`, which is **not**
  rebuild-recoverable, so it **propagates** — the store fails to open, `store` stays nil, browse
  degrades to `.failed`; it is **not** quarantined. The *more insidious* half-mistake is
  step-without-bump: the step is silently filtered out of `pending`, `tracks_fts` is never created,
  and `search()` throws only at query time — invisible to open-path tests.) Guard both with an
  assertion: a fresh production-path open has `user_version == 2` **AND** `tracks_fts` exists.
- ★ **FTS5 capability probe before migrating** — FTS is now part of the *required* base, so no-FTS5
  means a fresh create throws and leaves the store nil (no store at all). Probe behind an injectable
  predicate; surface a clear typed error. (System SQLite is 3.51 w/ FTS5 present — low real risk,
  cheap insurance.) Downgrade (v2 opened by v1 build) already → `.schemaTooNew` → quarantine+rebuild
  (verified).
- **Large-library backfill** is O(tracks) inside the open-path txn — off-main (store built in an
  init `Task`), so no main-thread hang; the browse UI sits in `.loading`. Consider a one-time
  "upgrading library" affordance; measure.

**Query builder:** tokenize on whitespace, strip FTS specials (`" * : ( ) -`), drop empty tokens,
wrap each as a quoted prefix `"tok"*`, implicit-AND. Empty / all-stripped → empty results (never a
full-table match, never a syntax error). `ORDER BY bm25`; `LIMIT`. (play-count tiebreak = later.)

## 5. Artwork thumbnail loader (Swift-6-clean)

Local `≤512 px .thumb.jpg` files → **no `AsyncImage`** (URLs only). ★ The naive "actor holding
`NSCache<NSString,NSImage>`" **violates strict concurrency** (`NSImage` isn't `Sendable`). Invert:

- **`@MainActor final class ArtworkThumbnailStore`** — `NSImage` never leaves main; holds an
  `NSCache` (free memory-pressure eviction) + a hash→`cache_path` map. `warm(keys:)` does ONE
  batched `artworkCachePaths(forKeys:)` per grid page. A `@concurrent nonisolated static func
  decode(...) async -> sending CGImage?` runs off-main and returns a freshly-created `CGImage` via
  **`sending`** (a disconnected region — region isolation proves it race-free; no `@unchecked`, no
  `Task.detached`). `NSImage(cgImage:)` is built on main. ★ Annotate `@concurrent` explicitly (Swift
  6.2) rather than relying on the SE-0338 default — the target has no approachable-concurrency opt-in
  today, so the default works now, but a later flip could silently move the decode on-main
  (final-gate #12).
- **`AlbumArtworkView(key:side:)`** — `.task(id: key)` (auto-cancels the decode on scroll/recycle);
  synchronous cache peek to avoid a placeholder flash on hits; SF-Symbol placeholder on nil/miss
  (never throws); fade-in gated on `@Environment(\.accessibilityReduceMotion)`;
  `.accessibilityHidden(true)` (the cell owns the label).
- **Downsample to display size** (`min(512, Int((side*displayScale).rounded(.up)))`) — ~4× less RAM
  than holding 512 px for a ~176 pt cell.

## 6. Queue model — positional Play Now / Play Next / Add to Queue

Reuses the index-addressed engine. New `AudioViewModel+Queue.swift`.

- ★ **`computeNextIndex` stays PURE and untouched** (refactoring BLOCKER). It's a pure function
  called at four sites and — because `AudioViewModel` is an *executable* target SPM can't
  `@testable import` — its 25 auto-advance tests validate a **hand-mirror** (`MockAdvanceController`).
  Threading a stateful jump-queue into it would make the mirror fiction. S9 does positional insert
  only (no forced-next), so `computeNextIndex` needs **zero** edits and all 25 tests stay valid.
- **`LibraryTrackDisplay → AudioFile` adapter** (own file): `url→absoluteURL`, `name = title ?? name`
  (★ else a queued track reverts to its filename in Now-Playing), format/duration map directly.
  Note the stable `Int64` id is dropped (`AudioFile.id = url`); S10's play-count write-back will
  need a url→id lookup — flagged seam.
- ★ **`armOnDeck(index:)` — the shared PRIMITIVE (NOT a re-compute).** Sets `pendingNextIndex =
  index` (or nil) + Task→`setNextTrack(url ?? nil)`. It **does NOT call `computeNextIndex`** and
  **never touches `lastTransitionCount`**. This is the one helper the queue ops share. *(Final-gate
  bug fix: the earlier "`rearmOnDeck` = branch-1 which recomputes" would, under shuffle,
  `randomIndexExcluding` a NEW on-deck track on every append/insert/reorder — throwing away the
  already-primed pick. Only genuine on-deck REMOVAL may re-pick.)*
- **`playNow(_:startAt:)`** — replace `playlist`, set index, `startPlayback()` (re-primes on-deck).
- **`playNext(_:)`** — insert directly after `selectedTrackIndex`, then `armOnDeck(insertedIndex)`
  **directly** (bypass `computeNextIndex`). This honors Play Next **even under shuffle** (a
  single-slot override = Music.app's behavior): `handleTrackTransition` advances to it, then shuffle
  resumes on the following roll. Ships in S9. *(Only the multi-item forced-next FIFO — which would
  need a stateful `computeNextIndex` — defers to S10.)*
- **`appendToQueue(_:)`** — append. Re-arm **only** the linear end-of-queue case (current was last,
  repeat-off → the appended track is now the immediate next): `armOnDeck(newIndex)`. Under shuffle
  or mid-list, **leave the primed on-deck pick untouched** — the appended track just joins the pool
  for the subsequent roll. Never re-roll.
- **`movePlaylistItems`** (scoped behavior-change + its own char-test): if the currently-primed
  on-deck *track* moved, `armOnDeck(its new index)` (id-based); otherwise leave it. Never recompute.
- **Removal (`adjustPendingNextIndexAfterRemoval`) — UNCHANGED and is the ONLY path that may
  re-pick:** branch-1 (the on-deck slot itself was removed → genuinely needs a new pick) keeps its
  `computeNextIndex(assumingCurrent: shifted)` call then `armOnDeck(result)`; the `-1` shift is
  **conditional** (`rawCurrent > removedIndex ? rawCurrent-1 : rawCurrent`), not literal, and runs
  before the `selectedTrackIndex` fixup. Branch-2 (`pending>removed → pending-=1`, keep the same
  on-deck track) stays inline. `primeGaplessPipeline` stays separate (owns `lastTransitionCount`).
- ★ **Queue-entry identity** — `AudioFile.id == url`, so "Add to Queue" twice or "Play Next" a
  queued track creates duplicate ids → `movePlaylistItems`/prune resolve the wrong copy. **Wrap
  queue entries in a per-entry-id struct** (a `UUID` per slot; Music.app parity, allows dups) so
  edits address the right slot. ★ Also stash the `LibraryTrackDisplay.id` (`Int64?`) in the wrapper
  — it disambiguates duplicate-url rows and closes the flagged S10 play-count `url→id` seam for free.
  *(Alternative — dedupe-on-add — rejected: users legitimately queue a track twice.)*
- **`movePlaylistItems` re-arm** is a *behavior change* (today it doesn't re-arm the on-deck after a
  reorder), not a silent refactor — ship it as a scoped fix **with its own characterization test**.
- **RT boundary:** all `@MainActor` VM state; only `setNextTrack` touches the engine (already async,
  off-RT). No new audio-thread work (architect-verified).

## 7. `LibraryBrowseModel`

`@MainActor @Observable final class`, **owned as `@State` in `AdaptiveSound` (the App), injected via
`.environment`** (peer of `AudioViewModel`/`EQViewModel`) — ★ NOT `@State` in `LibraryTabView` (§2
teardown). Holds nav state, per-list `loadState`, facet arrays, `searchResults`; a ref to the
optional `AudioViewModel.store` (degrade to `.failed` if nil, never force-unwrap) + the artwork
store. **Fine-grained `@Observable`:** each leaf reads only what it needs (search field ↔
`searchQuery`, grid ↔ `albums`); no computed prop mixing `searchQuery` + `albums` (widens
invalidation). Loads via `.task`/`.task(id:)` off-main. **Debounced search = `.task(id: searchQuery)`
+ `Task.sleep(200ms)` + `Task.isCancelled`/`q==searchQuery` guards** (auto-cancels stale; simpler
than a manual token). Refresh on scan: `.onChange(of: audio.lastScanResult)` (it's `Equatable`) —
**coalesce to completion, never per `metadataProgress` tick** (else dozens of full re-diffs/sec
through the actor). Browse owns read+selection; calls `audio.playNow/playNext/appendToQueue`.

## 8. The views

`UI/Library/`, one type per file, `DesignSystem.*` tokens directly (not the legacy `Color.asXxx`),
`#Preview` **required** on leaf views (seeded from a `LibraryPreviewData` in-memory model — no real
store). Reuse `formatDuration`; use `FormatBadgeView` **sparingly** (research: over-badging reads
cheap — not on every grid cell).

- **`AlbumGridView`** — full-width `LazyVGrid(.adaptive(min:160,max:200), spacing:16)`. `AlbumCell` =
  1:1 art (`AlbumArtworkView`, `.clipped()` + hairline stroke) + title + artist (drop track-count);
  wrapped in `NavigationLink(value: .album(id))` (single-click opens); hover reveals a Play button;
  `.contextMenu` = Play / Play Next / Add to Queue; `.draggable(DraggableTracks(...))`. `.focusable()`
  + `@FocusState` (grids don't get keyboard focus free). Warm artwork once per page via `.task`.
  ★ **Default landing = "Recently Added"** (sort by `date_added` desc — `idx_tracks_added` +
  `TrackSort.dateAddedDescending` already exist), not an A–Z wall (final-gate #7: mature players
  open on recent/home; an alphabetical grid reads like a file browser). A sort control offers
  Title/Year/Recently-Added.
- **`AlbumDetailView`** — large-art header + title/artist/year/duration + **visible** Play / Shuffle
  / ⋯ buttons (not hover/context-only) + a `List(selection:)` track list (disc/track order).
- **`SongsListView`** — ★ **`Table(of: LibraryTrackDisplay, selection:sortOrder:)`** (virtualized +
  sortable columns Title/Artist/Album/Time + native selection/keyboard nav — the Music.app Songs
  pane). Sort in the DAO/model, not `body`. Don't paginate the UI (50k small structs ≈ 10 MB, views
  virtualize); keep the DAO limit/offset as a guard only.
- **`ArtistListView`/`Detail`, `GenreListView`/`Detail`, `YearListView`/`Detail`** — analogous;
  artists/genres have no art → circular initial-avatar / typographic tile (not a monotonous
  note-square wall); optionally derive an artist thumb from the first album (added read).
- **`LibrarySearchResultsView`** — sectioned Songs / Albums / Artists over `SearchResults`;
  `ContentUnavailableView.search` for empty; optional `.searchScopes`.
- **Shared `TrackRow`** — one row, parameterized on its secondary line (Title·Artist·Album for
  library/search; disc/track# + title + duration in album detail), from `LibraryTrackDisplay`, never
  `relativePath`. Reuse the *visual* layout of `PlaylistItemRow` but **not** its interaction.
- **Queue-action feedback (★ ui-designer HIGH-6 + final-gate #9):** the queue lives on the
  Now-Playing tab, so Play Next / Add to Queue from Library would be silent. Show a transient
  toast/HUD ("Added N songs", "Playing next") reusing the `EQRecallBanner` capsule idiom — and make
  it **tappable to jump to the Now-Playing tab** (`TabSelection` switch), with an optional
  queue-count badge, so it's a doorway to the queue, not just a fire-and-forget notice.
- **Accessibility (in-scope up front):** `AlbumCell` = combined `.accessibilityElement` (label
  "Title, Artist, Year", `.isButton`, art hidden) + custom actions (Play / Play Next / Add to
  Queue); track rows labeled "Title, Artist, duration, format"; `labelSecondary` is the contrast
  **floor** for meaningful text (`labelTertiary` @0.42 fails WCAG AA on `#1E1E1E`); ★ **Dynamic Type:
  drive cell art `side` + grid metrics with `@ScaledMetric`** so the grid reflows (the fixed
  `Font.system(size:)` scale doesn't scale) — test at the largest size; **Reduce Motion** gates all
  motion; icon-only Play/⋯ carry text labels. Full 2-D arrow-key grid traversal = fast-follow (Tab +
  VoiceOver ship in S9).

## 9. Dependency-graph & build wiring

No new package edges (`AdaptiveSound` already imports `LibraryStore` + `LibraryScan`; `ArtworkCache`
is public). Export a custom `UTType` for the queue-drag `Transferable`. No new SwiftPM dep. FTS5
probe at open (§4).

## 10. Test plan

Adopts the qa-expert strategy in full. **No DSP change** → the C++ null golden master
`0xE7267654BA01D315` and `make sanitize`/`tsan` stay byte-identical/unaffected (an *exit criterion*).
Automated coverage lands in the headless **`VerifyLibraryStore`** (authoritative) + **swift-testing**
(pure logic); look/feel + a11y-by-eye + scale-feel are the **founder's `make run`** pass.

**Risk rank:** R1 FTS consistency across all write/delete sites (silent blast radius) · R2 V1→V2
migration (backfill JOIN / idempotency / downgrade) · R3 queue mutation × modes × on-deck · R4
read-during-scan latency · R5 large-library scale · R6 artwork miss / IN-list chunking.

**Headless `VerifyLibraryStore` cases** (extend `allCheckCases()`; reuse `seedFixtureLibrary`/
`FixtureExpectations`, the migration idiom, the `OneShotLatch` rendezvous, `makeSolidPNG`):
- **Reads** BR1 artwork-path map · BR1b cache-miss→absent (no throw) · BR1c IN-list chunking >999 ·
  BR2/BR2b/BR2c artist/genre/year drill-downs (no fan-out) · BR3/BR3b single-facet + sentinel
  exclusion · BR4 pagination window (no dup/gap; nil = unbounded) · **BR5 EXPLAIN-plan: no `SCAN
  TABLE tracks`** (the portable scale tripwire).
- **FTS** FTS-MIG1 migrate+backfill (first runner-vs-DDL exercise) · MIG2 backfill JOIN (findable by
  artist/album/each genre) · MIG3 idempotent re-open (no dup rows) · MIG4 transactional rollback →
  stays v1 · MIG5 downgrade→quarantine · CAP capability-probe error path · SYNC1 insert-minimal ·
  SYNC2 retag re-sync · **SYNC3 rename-of-tagless (`moveMatchedLocked`)** · DEL1 delete · **DEL2
  sweepOrphans ordering (count drops by exactly swept)** · DEL3 removeRoot (SEQ-1-gated loose-survivor
  follow-up) · MOVE no-op · Q1 injection-safety · Q2 all-stripped→empty · Q3 prefix · Q4 implicit-AND
  · Q5 unicode/diacritics · Q6 bm25 ranking (title > album-only) · Q7 deduped result shape.
- **Read-during-scan** BR-SCAN parked-rendezvous read returns committed rows within deadline.
- **Scale (env-gated `LIBRARY_PERF=1`)** PERF-1 bulk-seed 10k/50k · PERF-2 search-at-scale +
  plan-assert · PERF-3 facet/page + plan-assert · PERF-4 search under concurrent write.

**swift-testing (queue logic, via `MockAdvanceController` + `MockAudioEngine`)** VM-Q-01..15: array
effects of playNow/append/playNext; `rearmOnDeck` preserves the transition baseline + primes the
right engine URL; append re-arm at end-under-repeat-off; remove/move index-consistency; existing
VM-AA-01..16 unchanged. Pure helpers (FTS query-builder/sanitizer, thumbnail-path math,
`LibraryTrackDisplay→AudioFile`) unit-tested directly. (The existing **25** auto-advance `@Test`
cases — VM-AA ids 01..19 + RGAP/RTR/device/gap/seam variants — stay unchanged; `computeNextIndex`
is frozen. *Final-gate #12: earlier "01..16" was an undercount.*)

★ **Test-vehicle decision (§11-Q):** the queue ops live in the executable target, so VM-Q tests
would validate the hand-mirror, not shipped code. **Because S9 keeps `computeNextIndex` pure +
positional-only, the delta to the mirror is small** and the mirror + founder manual pass is the
accepted S9 gate. If the founder wants the queue core gated against real code, factor the
next-index/queue core into a `@testable`-importable library target — recorded as an option, not
S9-default.

**Per-slice exit criteria** — see §12; each slice: its cases green + prior 47 + 71 unchanged +
golden master held + `swiftlint --strict` clean.

## 11. Multi-discipline review — resolutions (all applied above)

Six-discipline panel; convergent findings folded into the body. Dispositions:

- **[BLOCKER — architect #1 + refactoring #3, independent] FTS misses `moveMatchedLocked`.** APPLIED
  §4: the `SearchIndex` seam is called from `moveMatchedLocked`; test SYNC3.
- **[architect #2 + refactoring #1 (BLOCKER) + qa R3/testability] forced-next / `computeNextIndex`
  purity.** APPLIED §1.3/§6: `computeNextIndex` frozen; Play Next honored via a single-slot
  `armOnDeck` override (works under shuffle); only the multi-item FIFO → S10. *(Superseded by
  final-gate #1/#2 — see §15.)*
- **[architect #3] queue-entry identity under duplicates.** APPLIED §6: per-entry-id wrapper.
- **[architect #4/#5] migration mechanics (raw exec / LEFT JOIN+COALESCE / `writeSchemaInfo` /
  FTS5 probe / atomic version bump).** APPLIED §4. Downgrade guard verified sound.
- **[refactoring #2] `rearmOnDeck` extraction subtleties (the `-1` shift; keep branch-2 inline;
  don't route `primeGaplessPipeline`).** APPLIED §6.
- **[refactoring #3 + qa R1] FTS = one `SearchIndex` seam (not scattered SQL / not triggers) + the
  `sweepOrphans` capture-before-delete ordering + upsert idempotency (`.new` only).** APPLIED §4.
- **[architect #6 + refactoring #1 + qa §2] test-vehicle honesty (executable-target mirror).**
  APPLIED §10: mirror+manual is the S9 gate (defensible because the queue stays simple); factor-out
  recorded as an option.
- **[ui-designer HIGH-1/2 + swiftui-pro §7] destructive single-click + hover-only a11y.** APPLIED
  §1.6/§8: single-click navigates; `List/Table(selection:)`; Play via hover+menu+Return+a11y.
- **[ui-designer HIGH-3 + swiftui-pro] dark-only tokens vs "light" test line.** APPLIED §1.5:
  dark-lock; "light/dark" removed from the test surface.
- **[ui-designer HIGH-4 + architect #8 + swiftui-pro] `LibraryTrack` has no artist/album name.**
  APPLIED §3.1: `LibraryTrackDisplay` projection; never render `relativePath`; `AudioFile.name =
  title ?? name`.
- **[ui-designer HIGH-5 + swiftui-pro §8] accessibility.** APPLIED §8: combined cell element +
  custom actions, focusable grid, `labelSecondary` floor, `@ScaledMetric`, Reduce-Motion.
- **[ui-designer HIGH-6] silent queue mutation.** APPLIED §8: transient toast.
- **[swiftui-pro §0/§5 — make-or-break] tab `switch` destroys the view → state must live in the
  injected model.** APPLIED §2/§7.
- **[swiftui-pro §4] artwork loader `Sendable` violation.** APPLIED §5: `@MainActor` cache +
  `sending CGImage`.
- **[swiftui-pro §1/§3/§6] two-column split, single `navigationDestination`, `Table` for Songs,
  `.task(id:)` debounce.** APPLIED §2/§7/§8.
- **[qa R5 + architect #14] scale via `EXPLAIN QUERY PLAN` (no `SCAN`), IN-list limit 32766.**
  APPLIED §3.8/§10.
- **[architect #7] `NavigationSplitView`-in-a-tab chrome; #9 S9 heavy for 8 SP; #10 backfill cost;
  #11 indeterminate scan; #12 completion-granularity refresh; #13 diverged-row "file unavailable".**
  APPLIED §2 (two-phase banner), §12 (may spill), §4 (backfill affordance), §7 (coalesce), §8
  (unavailable affordance). Sandbox = non-issue (Developer-ID non-sandboxed, verified).

## 12. Slicing (per-chunk pace, gate each). S9 is heavy for 8 SP — expect it to spill (S6/S8.1 precedent) or trim the tail.
- **S9.1** — DAO reads + `LibraryTrackDisplay` (§3). BR1–BR5. No UI, no schema change.
- **S9.2** — FTS5 V1→V2 + the `SearchIndex` seam (all sites incl. `moveMatchedLocked`) + query
  builder + probe (§4). FTS-MIG/SYNC/DEL/Q + BR-SCAN. Headless.
- **S9.3** — positional queue ops + `rearmOnDeck` extraction + entry-id wrapper + adapter (§6).
  VM-Q-01..15. No browse UI (harness/temp-driven).
- **S9.4** — artwork loader + `LibraryBrowseModel` (injected from App) + tab wiring + two-column
  `NavigationSplitView` + album grid + album detail + Songs `Table` (§5/§7/§8). Founder `make run`.
- **S9.5** — Artist/Genre/Year lists+details + search UI + context-menu queue actions + toast +
  empty/first-run + `#Preview`s + a11y (§8). `LIBRARY_PERF=1` PERF-1..4. Founder `make run` + doc
  reconciliation (§13). *(Candidate trim if spilling: land S9.4 + search + queue first; Genre/Year
  detail + search-result facets as a tail.)*

## 13. Doc reconciliation (part of S9)
sprint-plan.md/roadmap.md: the queue *verbs* (positional Play Now/Next/Append) moved into S9; S10 =
queue reorder/save/history + the shuffle-honoring forced-next + playlists + M3U + media-keys/Now-
Playing. US-LIB-07 deferred out of S9. backlog: re-tag US-LIB-07; add S9 queue-verb acceptance.
Schema note: FTS = V1→V2, playlists = V2→V3.

## 14. Verification (definition of done)
`swift build` clean · `swift test` green (71 + VM-Q) · `make gate` (`VerifyLibraryStore` + BR/FTS/
BR-SCAN, `VerifyAUGraph`, C++ null golden master **unchanged**) · `LIBRARY_PERF=1` PERF green ·
`make sanitize`/`tsan`/`sanitize-library-store`/`leak-check` unaffected (no new C/C++) ·
`swiftlint --strict` clean · founder `make run` visual + a11y-by-eye + scale-feel pass. Commit per
slice.

## 15. Final gate — architect challenge + the-fool pre-mortem (all applied above)

Adversarial second pass on the synthesized plan. Verdict: **implementation-ready after the SHOULD-FIX
cluster** (no unbuildable/data-destroying items). Resolutions:
- ★ **[architect #1 — real bug in the synthesis] shuffle re-roll.** The earlier
  `append/playNext/reorder → rearmOnDeck → computeNextIndex` re-rolled the random on-deck under
  shuffle (contradicting §6's own "don't let shuffle re-pick"). APPLIED §6: extracted a pure
  `armOnDeck(index:)` primitive (no `computeNextIndex`); only genuine on-deck *removal* may re-pick.
- ★ **[architect #2 + the-fool #2] Play Next under shuffle felt broken.** APPLIED §1.3/§6: single-slot
  `armOnDeck(insertedIndex)` override honors Play Next under shuffle (Music.app behavior) — the same
  fix as #1.
- **[architect #3, corrected] "wrongful quarantine" was wrong.** APPLIED §4: bump-without-step
  propagates (store nil, not quarantine); step-without-bump silently skips `tracks_fts` (worse) →
  fresh-open assertion (`user_version==2` AND `tracks_fts` exists).
- **[architect #4] re-typing `allTracks`/`tracks(inAlbum:)` is breaking (live gate callers).** APPLIED
  §3.1: add Display-returning variants *alongside*; existing reads unchanged.
- **[architect #5 + both premortems] the mirror can't catch the shuffle bug.** APPLIED: #1 fixed in
  design so the mirror is correct by construction; a real-VM smoke assertion added to the plan (else
  take D3's factor-out).
- **[architect #7] default landing = Recently Added, not A–Z.** APPLIED §8.
- **[architect #8] dark-lock's real risk = half-themed AppKit surfaces.** APPLIED §1.5: verify +
  `NSApp.appearance = .darkAqua` fallback.
- **[architect #6 + the-fool #3] SF-4 gated on subjective feel / least-representative machine.**
  → gate the read-only-connection decision on a **hard PERF-4 latency threshold**, and force an
  early `make run` on the *real* library *mid-scan* (plan mitigation).
- **[architect #9] queue toast → tappable doorway + count badge.** APPLIED §8.
- **[architect #10] carry `Int64` id in the queue-entry wrapper.** APPLIED §6.
- **[architect #11] wording traps:** `-1` shift is *conditional*; seam call in `applyMetadataLocked`
  *after* `replaceGenres` (not `applyExtractedResult`). APPLIED §4/§6.
- **[architect #12] test count = 25** (not 01..16); pin decode `@concurrent`. APPLIED §5/§10.
- **[the-fool #1 — highest-value] visual/feel feedback back-loaded to S9.4.** → plan mitigation: a
  throwaway static-grid visual spike in S9.1/S9.2 so the founder tunes *feel* early.
- **[the-fool #4] real libraries are messy** (missing art/tags → placeholder wall). → hash-tinted
  initial-tile placeholder (§8) + confirm the real library's art/tag coverage before S9.4.
