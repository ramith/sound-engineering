# S9 — Implementation Plan

Status: **✅ SHIPPED (S9) — execution record.** ⚠️ Superseded in detail by the shipped code + [s9-5-songs-search-design.md](s9-5-songs-search-design.md); kept for the ordering/rationale provenance.
Execution layer for [s9-browse-search-ui-design.md](s9-browse-search-ui-design.md) (the vetted spec).
This plan is *how* we build it: ordering, safety discipline, per-slice file manifest + gate, and the
decisions that need a founder call before code starts.

## A. Founder decisions — SIGNED OFF (2026-07-05)

| # | Decision | Outcome | Consequence for the plan |
|---|----------|---------|--------------------------|
| D1 | Queue scope | **Adopt** — Play Now/Next/Append ship; Play Next = single-slot `armOnDeck` override (honored under shuffle); multi-item FIFO → S10 | §C queue chunks as written |
| D2 | Theming | **Build light + dark NOW** (not dark-lock) | ★ NEW app-wide chunk **S9-T**: migrate `DesignSystem`/`Color.asXxx` to a semantic asset-catalog palette with light+dark variants, fix the AA-failing `labelTertiary`, and re-verify **every existing screen** (Now Playing/EQ/Monitoring/Settings) in both appearances. Precedes the browse UI. |
| D3 | Queue test vehicle | **Extract a `@testable` queue/advance core** | ★ Queue work becomes **S9-Q1/Q2**: a new SPM library target owns the pure next-index + queue-decision logic; `AudioViewModel` delegates; the `MockAdvanceController` hand-mirror is **retired** (real code tested directly). Characterization-tests-first. |
| D4 | Scope | **Accept spill + chunk finely** | §C re-sliced into 8 smaller, independently-gated chunks below |

D2 and D3 both raise the quality bar and add scope (a real palette; real queue-code gating) — consistent with the founder's quality-first / correctness-over-demoability stance. The headless chunks (reads, FTS, queue-core) are unaffected and lead.

## B0. Per-chunk delivery loop (team model — every chunk)

Each chunk runs the same loop, coordinated by the main agent (holds the plan, integrates, enforces):
1. **Todo list** — open a dedicated `TodoWrite` list for the chunk (tasks + tests + gate + review).
2. **Implement** — a subject-matter specialist builds it (store/DAO → swift-expert; queue-core →
   swift-expert + refactoring-specialist; theming/UI → swiftui-pro/ui-designer; C-adjacent →
   modern-cplus-plus-expert). The implementer runs the gate locally and self-corrects.
3. **SME review** — the relevant expert(s) review the diff (code-reviewer always; plus the domain
   SME — swiftui-pro for UI, architect-reviewer for cross-cutting store/concurrency, qa-expert for
   test adequacy). Findings fixed at root.
4. **Gate** — the build-enforced standards below MUST be green (no waivers, no lint suppressions).
5. **Commit** the chunk (no `Co-Authored-By` trailer, per repo policy).

## B. Global discipline (applies to every chunk)

1. **Characterization-test-first for any change to already-tested code.** Before extracting
   `rearmOnDeck`, changing `movePlaylistItems`, or touching a DAO write path, add a test that pins
   *current* behavior, then change, then confirm green. (Named per slice below.)
2. **`computeNextIndex` is frozen** — zero edits in S9 (keeps all 25 auto-advance tests valid).
3. **Every FTS mutation goes through the `SearchIndex` seam** — no inline FTS SQL at call sites;
   the completeness invariant is "every track write/delete calls `syncSearchRow`/`deleteSearchRows`."
4. **Per-slice gate** (must be green to land the slice): `swift build` · relevant new tests ·
   `swift run VerifyLibraryStore` (prior 47 + this slice's cases) · `swift test` (71 + new) ·
   `swiftlint --strict` · C++ null golden master `0xE7267654BA01D315` **unchanged**. Commit per slice.
5. **No DSP change** → `make sanitize`/`tsan`/`sanitize-library-store`/`leak-check` are unaffected
   (re-run `sanitize-library-store` once at the end as cheap insurance, since the harness grew).
6. **Founder visual/a11y/scale pass** (`make run`) gates the UI slices (S9.4, S9.5) — offline tests
   prove data + logic; look/feel is the founder's.

## C. Slice-by-slice

### S9.1 — DAO reads + `LibraryTrackDisplay` (headless; no schema change)
- **Add** (`LibraryStore+Reads.swift`/`+Facets.swift`): `LibraryTrackDisplay` (Sendable; LEFT-JOIN
  resolved `artistName`/`albumName`, `title ?? name`) exposed via **NEW** Display-returning reads
  (`allTracksDisplay`, `tracksDisplay(inAlbum:)`/`(byArtist:)`/`(inGenre:)`) **alongside** the
  existing `LibraryTrack` reads, which **stay unchanged** (gate callers at `ChecksFSDivergence.swift:58`
  / `ChecksConcurrency.swift:367` must not break — §15 #4); `artworkCachePaths(forKeys:)` (chunked IN,
  limit 32766); `albums(byArtist:)`, `albums(inGenre:)`, `years()`, `albums(inYear:)`, `album(id:)`,
  `artist(id:)`; optional `limit`/`offset` on `albums`/`artists`/`allTracks` (defaulted, non-breaking).
- **Tests** (`ChecksBrowseReads.swift`, register in `allCheckCases()`): BR1, BR1b, BR1c, BR2, BR2b,
  BR2c, BR3, BR3b, BR4, **BR5 (EXPLAIN — no `SCAN TABLE tracks`)**.
- **★ the-fool mitigation (early feel):** a throwaway static `AlbumGridView` on fixture data behind a
  debug flag, so the founder can eyeball/tune grid feel **now** rather than first at S9.4.
- **Gate/exit:** `make gate` green + BR1–BR5; prior 47 + 71 unchanged; golden master held.

### S9.2 — FTS5 V1→V2 + the `SearchIndex` seam (headless)
- **Schema/migration:** `tracks_fts` vtable (rowid=id); `migrateV1toV2` via raw `connection.exec`
  (no nested txn) + LEFT-JOIN/COALESCE backfill + `writeSchemaInfo(2)`; bump `currentSchemaVersion=2`
  **and** add to `productionMigrations` in the same commit; FTS5 capability probe (injectable
  predicate) before migrate.
- **Seam:** `syncSearchRow(trackID:)` + `deleteSearchRows(ids:)`; wire into `upsertOne` (`.new`
  only), `applyMetadataLocked` (**inside it, AFTER `replaceGenres`** so `group_concat(genre)` is
  fresh — NOT in `applyExtractedResult`, §15 #11), **`moveMatchedLocked`**, `delete`,
  `deleteTrackRows`, and `sweepOrphans` (capture doomed ids **before** the tracks DELETE). Query
  builder + sanitizer.
- **Char-test-first:** a no-op re-scan performs **zero** FTS writes (pins the idempotency contract
  before adding the `.new`-gated insert).
- **Tests** (`ChecksSearch.swift`): FTS-MIG1–5 (incl. **fresh production-path open: `user_version==2`
  AND `tracks_fts` exists** — §15 #3), CAP, SYNC1–3 (incl. **SYNC3 rename-of-tagless via
  `moveMatchedLocked`**), DEL1–3 (**DEL2 sweep-ordering: count drops by exactly swept**), MOVE,
  Q1–Q7; plus BR-SCAN (read-during-scan rendezvous).
- **Gate/exit:** `make gate` + all FTS cases; migration idempotent/transactional/downgrade-quarantined.

### S9-Q1 — Extract a testable queue/advance core (D3; headless; behavior-preserving)
- **New SPM library target** (e.g. `PlaybackQueueKit`, `@testable`-importable) owning the **pure**
  advance/queue-decision logic: `computeNextIndex`/`computePreviousIndex`/`randomIndexExcluding` and
  the on-deck decision model, as `Sendable` value types / free functions parameterized on
  `(currentIndex, count, shuffle, repeatMode, …)` — no `@MainActor`, no engine.
- **`AudioViewModel` delegates** to the core (thin call-throughs); behavior byte-for-byte preserved.
- **Char-test-first → retire the mirror:** port the **25** auto-advance `@Test` cases to drive the
  **real** core directly, then delete `MockAdvanceController`'s duplicated logic (§15 #5 — the whole
  point of D3: gate real code, not a hand-mirror).
- **Gate/exit:** `swift test` green with the 25 cases now hitting real code; `swift build`;
  `swiftlint --strict`; `make gate`; golden master held.

### S9-Q2 — Queue ops on the core (D1; headless/harness; no browse UI)
- **Add** (`AudioViewModel+Queue.swift` + core): `LibraryTrackDisplay→AudioFile` adapter (`name =
  title ?? name`, own file); per-entry-id queue wrapper (`UUID` slot id **+ `libraryTrackID:
  Int64?`**, §15 #10); the pure **`armOnDeck(index:)` primitive** (sets `pendingNextIndex` +
  `setNextTrack`, **no `computeNextIndex`, no `lastTransitionCount`**); `playNow`; `playNext` =
  insert-after-current + `armOnDeck(insertedIndex)` **directly** (honors shuffle, §15 #1/#2);
  `appendToQueue` = append + arm **only** the linear end-of-queue case (never re-roll under
  shuffle/mid-list); `movePlaylistItems` = re-arm only if the primed on-deck track moved (scoped fix
  + test). Removal path UNCHANGED (branch-1 recompute — the ONLY re-pick path; `-1` shift is
  **conditional**). `primeGaplessPipeline` untouched.
- **Tests:** VM-Q-01..15 against the **real** core (no mirror); pure adapter/query-builder units.
- **Gate/exit:** `swift test` (VM-Q + the ported 25) green; `make gate` green.

### S9-T — Theming foundation: light + dark (D2; app-wide enabler, precedes browse UI)
- **Migrate** `DesignSystem`/`Color.asXxx` from hardcoded white-opacity-on-dark to a **semantic
  asset-catalog palette** with light + dark variants (window/card/panel/hairline/label*/status*/
  accent); fix `labelTertiary`'s AA failure (raise to the `labelSecondary` floor for meaningful text).
- **Re-verify EVERY existing screen** (Now Playing · EQ · Monitoring · Settings) in **both**
  appearances — this touches shipped views, so char-test-first mindset: screenshot/`make run` before
  + after; no functional change, only token source.
- **Gate/exit:** `swift build`; `swiftlint --strict`; `make gate`; **founder `make run` in light AND
  dark** across all existing tabs (no regressions).

### S9.4 — Browse foundation UI (first Library UI; founder `make run`)
- **Add** (`UI/Library/`): `ArtworkThumbnailStore` (`@MainActor` NSCache + `@concurrent nonisolated`
  decode → `sending CGImage`, downsample) + `AlbumArtworkView` (`.task(id:)`, cache-peek, placeholder,
  Reduce-Motion fade); `LibraryBrowseModel` (**owned as `@State` in `AdaptiveSound`, injected via
  `.environment`**) + `LibraryCategory`/`LibraryRoute`; `TabSelection.library` + `TabContentView` arm;
  `LibraryTabView` (two-column `NavigationSplitView(columnVisibility:)` bound to the model +
  `NavigationStack(path:)` + single `navigationDestination`); `AlbumGridView`/`AlbumCell`
  (NavigationLink single-click, hover-Play, context menu, `.focusable`); `AlbumDetailView` (header +
  visible actions + `List(selection:)`); shared `TrackRow`; `LibraryEmptyStateView` (first-run CTA +
  two-phase scan banner). Uses the S9-T semantic tokens (both appearances). Default landing =
  Recently Added (§15 #7).
- **Gate/exit:** `swift build` + `swiftlint --strict` clean; `make gate`; no data race under
  `swift test`. **★ Founder `make run` — on the REAL library, MID-SCAN** (the-fool #3): grid feel,
  layout, both appearances (+ AppKit surfaces themed — §15 #8), browse-while-scanning smoothness,
  single-click-opens / double-click-plays, real-library art/tag coverage (placeholder-wall check).

### S9.5 — Songs Table + incremental search UI (founder `make run`)
- **Add:** `SongsListView` (`Table(of: LibraryTrackDisplay, selection:sortOrder:)`, virtualized +
  sortable); `LibrarySearchResultsView` (sectioned Songs/Albums/Artists; `.searchable` sidebar;
  `.task(id:searchQuery)` debounce; `ContentUnavailableView.search`).
- **Gate/exit:** `make gate`; `swift test`; **`LIBRARY_PERF=1` PERF-1..4** (plan-asserted, no `SCAN`);
  `swiftlint --strict`. Founder `make run`: search feel, large-library scroll.

### S9.6 — Artist/Genre/Year + queue actions + a11y + polish (founder `make run`)
- **Add:** `ArtistListView`/`Detail`, `GenreListView`/`Detail`, `YearListView`/`Detail`;
  `AlbumQueueActions` context menu + the tappable queue-mutation toast (+ count badge, §15 #9);
  `DraggableTracks` (custom UTType) queue drag; full a11y (combined cell element + custom actions,
  `labelSecondary` floor, `@ScaledMetric` reflow, Reduce-Motion, VoiceOver labels); `#Preview`s +
  `LibraryPreviewData`.
- **Gate/exit:** full `make gate` + `swift test`; `swiftlint --strict`; golden master held; re-run
  `sanitize-library-store`/`leak-check`. Founder `make run`: a11y by-eye (VoiceOver/focus/Dynamic
  Type), context-menu affordances. **Doc reconciliation** (design §13): sprint-plan/roadmap/backlog +
  schema-version note.

### S9.4 — core browse surface (first UI; founder `make run`)
- **Add** (`UI/Library/`): `ArtworkThumbnailStore` (`@MainActor` NSCache + `nonisolated` decode →
  `sending CGImage`, downsample to display size) + `AlbumArtworkView` (`.task(id:)`, cache-peek,
  placeholder, Reduce-Motion fade); `LibraryBrowseModel` (**owned as `@State` in `AdaptiveSound`,
  injected via `.environment`**) + `LibraryCategory`/`LibraryRoute`; `.preferredColorScheme(.dark)`
  at the window root (D2); `TabSelection.library` + `TabContentView` arm; `LibraryTabView`
  (two-column `NavigationSplitView(columnVisibility:)` bound to the model + `NavigationStack(path:)`
  + single `navigationDestination`); `AlbumGridView`/`AlbumCell` (NavigationLink single-click,
  hover-Play, context menu, `.focusable`); `AlbumDetailView` (header + visible actions +
  `List(selection:)`); `SongsListView` (`Table`); shared `TrackRow`; `LibraryEmptyStateView`
  (first-run CTA + two-phase scan banner).
- **Tests:** `swift build` + `swiftlint --strict` clean; `make gate` green; loader cache-miss path
  covered upstream (BR1b); no data race under `swift test`.
- **Default landing = Recently Added** (date-added desc), not A–Z (§15 #7); Play Next verified
  under shuffle.
- **★ Founder `make run` — on the REAL library, MID-SCAN** (the-fool #3): grid density/art,
  sidebar+detail layout, dark rendering + **AppKit surfaces dark** (context menus, `.searchable`
  field, `Table` headers — §15 #8), virtualized scroll on a large library, browse-*while-scanning*
  smoothness (the first-impression window), single-click-opens / double-click-plays,
  empty/first-run/scanning, real-library art/tag coverage (the placeholder-wall check, the-fool #4).

### S9.5 — full browse + search + polish (founder `make run`)
- **Add:** `ArtistListView`/`Detail`, `GenreListView`/`Detail`, `YearListView`/`Detail`;
  `LibrarySearchResultsView` (sectioned; `.searchable` sidebar; `.task(id:searchQuery)` debounce;
  `ContentUnavailableView.search`); `AlbumQueueActions` context menu + the queue-mutation toast;
  `DraggableTracks` (custom UTType) queue drag; a11y (combined cell element + custom actions,
  `labelSecondary` floor, `@ScaledMetric` reflow, Reduce-Motion, VoiceOver labels); `#Preview`s +
  `LibraryPreviewData`.
- **Tests:** full `make gate` + `swift test`; **`LIBRARY_PERF=1` PERF-1..4** (plan-asserted, no
  `SCAN`); `swiftlint --strict`; golden master held; re-run `sanitize-library-store`/`leak-check`.
- **Founder `make run`:** search feel, context-menu affordances, a11y by-eye (VoiceOver/focus/
  Dynamic Type), scale-feel on a real 10k–50k library.
- **Doc reconciliation (§13 of the design):** sprint-plan/roadmap/backlog + schema-version note.

## D. Critical path & risk register

**Path:** S9.1 → S9.2 (both headless, de-risk the store) → S9.3 (queue, headless) → S9.4 (first UI)
→ S9.5. S9.1–S9.3 are fully gated offline before any pixel ships.

| Risk | Mitigation | Owner-check |
|------|-----------|-------------|
| FTS stale/missing hit (silent) | one `SearchIndex` seam + `moveMatchedLocked` + sweep-ordering; SYNC3/DEL2 | headless |
| V1→V2 breaks existing libraries | atomic version-bump+step; MIG1–5; backfill LEFT JOIN; probe | headless |
| queue mutation corrupts on-deck/gapless | char-tests-first; `rearmOnDeck` branch-1-only; VM-Q | headless + `make run` |
| tab-switch state loss | model owned in App + injected (not `@State`) | `make run` |
| strict-concurrency on artwork | `@MainActor` cache + `sending CGImage` | `swift build` |
| large-library jank | `Table`/`LazyVGrid` virtualization; coalesced scan-refresh; EXPLAIN no-`SCAN` | PERF + `make run` |
| scope spill (8 SP) | headless slices first; tail-trim ready (D4) | timeline |

## E. What is explicitly NOT in S9
**Multi-item forced-next FIFO** (S10 — single-slot Play Next override DOES ship in S9) · US-LIB-07
folder-move-DnD (later) · light mode (later) · 2-D arrow-key grid traversal (fast-follow) ·
play-count search-tiebreak (later) · playlists / M3U / media-keys / Now-Playing (S10).

**SF-4 read-only second connection — pre-planned, decision gated on a NUMBER (§15 #6):** build it if
PERF-4 (search-under-concurrent-write) exceeds a hard latency threshold OR the S9.4 real-library
mid-scan run stutters — not on subjective feel on the founder's fast machine alone. Threshold to
lock during PERF calibration (design §10): e.g. a facet read parked mid-scan &lt; ~100 ms p95.
