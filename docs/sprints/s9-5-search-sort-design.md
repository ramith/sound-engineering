# S9.5 — Songs search + sortable columns (design)

Status: **DRAFT — brainstormed + research-grounded; pending expert review (architect-reviewer · the-fool) → founder manual-review → questions → implement.** Companion to [s9-5-songs-search-design.md](s9-5-songs-search-design.md) (the authoritative S9.5 spec) and its [test plan](s9-5-songs-search-test-plan.md). This doc covers the **search + sortable-headers slice** (slice 4 + the sort-header half of slice 3) and **supersedes the relevance-order choice in §10.2** of the main design (see §2).

---

## 1. Why this slice, and what it is

The Songs table (`SongsView`) shipped as a shell: 9 fixed columns, composite default order, count line, single-click play-next+jump, context menu, Info popover. It has **no sortable headers** (`Table(model.songs, selection:)` — no `sortOrder:` binding) and **no search field**. The FTS5 search backend is fully built and gated (`LibraryStore.search(_:limit:400) -> SearchResults`, bm25, tokenized, injection/diacritics-safe, over title·artist·album·genre) but **unwired to any UI**.

This slice wires both, as **one coherent unit**, because on macOS they are two halves of the same behavior: a data table is sortable, and a filter narrows it *while preserving that sort*. Shipping search first (without sortable headers) would ship a non-standard intermediate state.

## 2. Research finding that reshapes the design (2026-07-08)

Two independent web/HIG research passes (macOS music players + Apple HIG/framework docs) converged with **high confidence**:

- **The dominant, Apple-native convention for an in-table filter box is filter-preserves-sort:** typing narrows the rows but keeps the user's current column sort; headers stay clickable to re-sort the filtered subset. Apple Music's in-list Filter Field ("results sorted as in the view you are searching"), Swinsian, foobar2000, MusicBee, Quod Libet, Audirvana, Meta, Doppler, and Finder all do this. Relevance-reorder is a *separate global-search-surface* pattern (Apple Music sidebar Search grid, Mail Top Hits); only Roon reorders in-table, and it drops sortable headers to do so.
- **HIG** frames a song-list search field as "a filter on the current view" (narrow-in-place); relevance-first ordering is guidance for dedicated *results screens*. In **SwiftUI and AppKit, filtering and sorting are orthogonal by construction** — `Array.filter` preserves order; the table's `sortOrder`/`sortDescriptors` independently govern arrangement. Nothing reorders a filtered table by relevance unless deliberately coded.
- **Sortable click-headers** with a single active-column triangle + asc/desc toggle are near-universal and rendered automatically by both `Table(sortOrder:)` and `NSTableView` (`sortDescriptorPrototype`).

**Consequence — this doc changes prior decisions (founder sign-off required at manual-review):**
- **Supersedes main-design §10.2's** "entering filter → rows swap to bm25 relevance order, sort triangle clears ('Relevance')." → **Filter preserves the current sort; the triangle stays; headers keep re-sorting the (filtered) subset.**
- **Also supersedes main-design §11.5's** "In filtered / relevance mode (§10.2) the triangle is already cleared ('Relevance')" (customizable-columns spec) — filter-preserves-sort keeps the triangle, so that sentence no longer holds. *(Caught by architect-review M4.)*
- **Refines founder decision #3 ("bm25-ranked").** → **FTS5 is the *matcher*, not the *display order*.** We keep every matching-quality property (tokenization, prefix as-you-type, diacritics folding, genre coverage, injection safety) and drop the bm25 *ordering*, which the native filter convention does not use. Relevance ordering, if ever wanted, belongs to a future global/grouped search surface (the produced-but-unconsumed `SearchResults.albums/.artists`, S9.6+ — confirmed to have **no current UI consumer**; deferring strands nothing).

This is licensed by the founder's directive (2026-07-08): *"both of these forks are standard behaviours of filtering and searching … then adopt."*

## 3. Adopted behavior spec

### 3.1 Sortable columns (full list)
- `Table` gains a `sortOrder: [KeyPathComparator<LibraryTrackDisplay>]` binding. The platform renders the single active-column triangle and toggles asc/desc on click.
- On `sortOrder` change, map the **primary** comparator (keypath + direction) → a `TrackSort` case → set `LibraryBrowseModel.songSort` → `loadSongs()` re-reads **DAO-side** (keeps ordering index-driven / EXPLAIN-gated per SS2/BR5 — not a client-side sort of 20k rows).
- **Sortable columns:** Title, Artist, Album, Time, Date Added, Quality (by `format`), Year, Disc #, File Size. **Non-sortable:** Artwork (no header), Genre (BR5 temp-b-tree hazard → display-only per main §12.5).
- **⚠️ Artist-column backend delta (REQUIRED — caught by both reviews, H1/#2):** `TrackSort` has `.artistAlbumTrack` (composite, ascending-only) but **no plain single-key artist sort and no descending artist**, so Artist-as-written is unmappable (the composite anchor makes the *first* Artist click toggle straight into a non-existent artist-desc). **Resolution (locked): add `.artistNameAsc` / `.artistNameDesc`** to `TrackSort` + `trackOrder` (`LibrarySortOrders.swift`) + `descendingTrackSorts` (`LibraryStore+BrowseReads.swift`) + SS1/SS2 gate rows (`ChecksSongsSort.swift`). `.artistAlbumTrack` stays **only** as the pre-click grouped *default anchor*; the first Artist click switches to `.artistNameAsc`. **⇒ this slice is UI + one filter read + a small (2-case) sort-backend delta — not purely UI.**
- **First-click direction:** Title/Album/Quality/Year/Disc#/FileSize → asc; **Date Added → desc** (recently-added); Time → asc. Second click toggles. Each column's `sortUsing:` declares its opening `order:` explicitly; `applySortOrder` maps **keypath + direction** and normalizes, with a defined fallback for any unrecognized comparator (→ composite default). **Artist is the exception:** it is the seeded active column (the composite anchor presents it as ascending), so its *first* click **toggles to desc** (`.artistNameDesc`) and the second returns to `.artistNameAsc` — standard platform toggle-of-the-active-column, confirmed acceptable in code review.
- **`sortOrder` is DERIVED FROM `songSort` (single source of truth — REQUIRED, swiftui #1).** `songSort` lives on the model and persists across the tab-`switch` teardown; a table-subtree `@State sortOrder` does **not** (it would re-seed to the anchor on every return → triangle-says-Artist-while-rows-are-Year desync). So the model owns the comparator array (or derives the seed from `songSort` via an inverse map when the table appears). `[KeyPathComparator<LibraryTrackDisplay>]` is `Sendable`, fine on the `@MainActor @Observable` model.
- **Composite default anchor:** initial `sortOrder` shows the Artist triangle while `songSort = .artistAlbumTrack` drives the composite order (Artist→Album→disc→track→id). `onChange(of:)` does **not** fire on the initial seed, so seeding never clobbers the composite (swiftui-confirmed). This is Music.app's grouped-default idiom; accepted.

### 3.2 Filter field (search)
- Trailing in `SongsHeader` (44pt band): `RoundedRectangle(Radius.control)` `Color.card` + 0.5 hairline, height 28, min 180 / ideal 240; leading `magnifyingglass` (`labelTertiary`), `TextField` (`Font.body`, placeholder **"Filter Songs"** — "Filter" not "Search", matching the adopted paradigm + Apple Music's Filter Field), trailing `xmark.circle.fill` clear when non-empty.
- **⌘F** focuses (hidden button + `@FocusState`); **Escape** clears-then-defocuses.
- **≥2-char gate**, **~120 ms debounce**, off-main, **newest-wins**.

### 3.3 Filter behavior (the adopted core)
- Typing **narrows** `songs` to the FTS-matched subset; **does not** clear `sortOrder`, `songSort`, or the triangle.
- The narrowed subset is presented **in the current sort** (see §4 for the two candidate mechanisms).
- Headers keep working while filtered (re-sort the subset).
- Count line: unfiltered **"N songs · total duration"**; filtered **"N results"** (drop duration; `0` → "0 results").
- **Clear** (xmark / Escape / drop below 2 chars) restores the full list + the exact prior sort, **no re-read**.
- **Zero results** (≥2 chars, matched set empty) → `ContentUnavailableView` (magnifyingglass, "No Results", "No songs match “\(query)”.") with the header still shown (field + "0 results").
- **Junk input** (≥2 chars whose tokens sanitize to nothing, e.g. `!!!` → `ftsMatchQuery` returns nil) → treated as **zero results**, never an error, never a silent restore-to-full.
- **A–Z rail** (not yet built; tail/trim) is hidden while filtered when it exists.
- **Play-from-row / context menu / multi-select** operate over the **visible (possibly filtered) set** in its current order — single-click still = play-next+jump (§12.6 of main design), multi-select Play = the selected subset.

## 4. bm25-matcher reconciliation — A2 LOCKED (both reviews concur)

Both keep FTS5 as the matcher and present results in the user's current sort. **Both expert reviews independently chose A2**; A1 is recorded as the rejected fallback.

**A2 — membership-filter the in-memory sorted set (LOCKED).**
Add a light IDs-only read `searchMatchingIDs(_ q:) -> Set<Int64>` and then `visibleSongs = matchedIDs.map { ids in songs.filter { ids.contains($0.id) } } ?? songs`.
- **Build it on the shared seam (M3):** reuse `LibraryStore.ftsMatchQuery(for:)` + the identical `WHERE tracks_fts MATCH ?`, differing only in `SELECT rowid`, **no `ORDER BY bm25`, no `LIMIT`, no joins** (`tracks_fts.rowid == tracks.id`, so it touches neither `tracks` nor the artist/album joins). Guarantees it can never diverge from `search()` on membership.
- **Empty-set, never nil (M3):** junk input (`ftsMatchQuery → nil`) and <2 chars return `matchedIDs = []` → drives the zero-results branch. `nil` is reserved for "not filtering" (full list). All-rows is never returned.
- ➕ **Exactly the Apple-Music Filter-Field semantics**: the already-`songSort`-ordered `songs` array is filtered in place → order preserved for free, **no client re-sort, no cap, one ordering path** (no drift-prone client comparator set that must replicate `trackOrder`'s NOCASE/NULLS/tiebreak SQL). Can only ever *hide* a row, never fabricate one.
- ➕ bm25 genuinely unused (we only need membership) → the honest story: "FTS5 is our matcher; presentation honors your column sort."
- ➖ One small new DAO read (a query, **no schema change / no migration**). Needs one `VerifyLibraryStore` case: membership parity **vs an *unbounded* `search()`** (NOT the default 400 — a >400-match fixture would legitimately differ, since A2 is a superset) + EXPLAIN clean (`SELECT rowid FROM tracks_fts` yields a `SCAN tracks_fts` virtual-table step, which the `detailIsTracksTableScan` tripwire does not flag; still assert `tracks` is untouched).

**A1 — rejected fallback.** `store.search(q, limit: 400).tracks` re-sorted client-side. Rejected because the 400-cap bites the *common* case, not a rare edge: a 2-char prefix over title·artist·album·genre on a 20k library routinely exceeds 400 hits (architect M1), so you'd see the 400-most-relevant-then-re-sorted with ~hundreds silently dropped and a count that reads "400" meaning "≥400" — contradicting OD-3's honest count. A1 also forks the sort into a second (client-side comparator) path that must replicate `trackOrder`'s SQL semantics — a drift hazard (M2).

## 5. Model deltas (`LibraryBrowseModel`)

- **Add** `searchQuery: String = ""`; `matchedIDs: Set<Int64>? = nil` (**nil = not filtering** → `visibleSongs` short-circuits to `songs`; `[]` = filtering, zero matches → zero-results).
- **Add** `visibleSongs: [LibraryTrackDisplay]` — the single source the view binds to for rows, count, AND play/context row-resolution. **Cache it (L1):** recompute only when `songs` or `matchedIDs` changes (not per-`body`), since selection lives as `@State` in the table subtree and every arrow-key move re-evals `body` — with OD-1's hard <100 ms selection gate we don't want an O(n) refilter per keystroke. When `matchedIDs == nil`, return `songs` by identity (no copy).
- **Add** `searchEpoch: Int` (monotonic) — newest-wins guard for the actor round-trip that `.task(id:)` cancellation can't interrupt mid-flight.
- **Sort mapping:** `func applySortOrder(_ comparators: [KeyPathComparator<LibraryTrackDisplay>])` → map primary comparator (keypath **+ `.order`**) → `TrackSort` (incl. the new `.artistNameAsc/Desc`) → set `songSort` → `loadSongs()`. Unrecognized comparator → composite default. `songSort` already exists (line 52) and drives `allTracksDisplay(sortedBy:)`.
- **Search run — epoch bumped at the TOP, before the gate (REQUIRED, H2/#4):**
  ```swift
  func runFilter() async {
      let e = bump()                                   // bump FIRST so the clear path invalidates in-flight reads
      guard searchQuery.trimmed.count >= 2 else { matchedIDs = nil; return }
      guard let ids = try? await store.searchMatchingIDs(searchQuery), e == searchEpoch
      else { return }                                  // stale epoch OR store error → keep last-good, no publish
      matchedIDs = ids                                 // [] on junk/no-match (never nil here)
  }
  ```
  Bumping *after* the `>=2` guard leaves a hole: type "ab" (epoch 1, in flight) → backspace to "a" (clear, no bump) → the "ab" read resumes and republishes a phantom filter over an empty field. Bump-first closes it. The pure newest-wins test **must** include this cross-2-char-boundary case.
- **Background reload (L2):** `reloadIfScanChanged` replaces `songs` but leaves `matchedIDs`; a live scan adding matching tracks won't surface them until re-typed. **Re-run the active filter after a `libraryRevision` reload** (correctness-over-demoability) — or document the staleness explicitly. *(Founder call, §11.)*
- Queue verbs (`playNext`/`append`/`playTrackNextNow`) **unchanged** in this slice (truthful-count / OD-2 + the toast are a separate slice).

## 6. View deltas

- **`SongsTable`:** bind `Table(model.visibleSongs, selection:sortOrder:)` where `sortOrder` reflects the model's single-source-of-truth (§3.1, NOT a re-seeding `@State`); add `sortUsing: KeyPathComparator(\.<field>, order: <opening>)` per sortable `TableColumn`; **two-param** `.onChange(of: sortOrder) { _, newValue in model.applySortOrder(newValue) }` (the one-param form is deprecated; do **not** pass `initial: true` — it would clobber the composite anchor). **Repoint all play/context/row-resolution to `model.visibleSongs`, not `model.songs` (REQUIRED, #3)** — else a multi-select "Play" while filtered plays hidden tracks. Orphaned selection IDs after filtering are inert/benign.
- **`SongsHeader`:** add the trailing filter field (§3.2); bind the `TextField` via a local `@Bindable var model = model` (Environment yields no binding — don't hand-roll `Binding(get:set:)`); `@FocusState` for ⌘F; count line reads filtered vs unfiltered from `model` (§3.3).
- **⌘F / Escape specifics:** the ⌘F hidden button must stay installed via `.hidden()` (not an `if` / `.disabled` — both drop the `keyboardShortcut`). Prefer `.onExitCommand` (the macOS Cancel hook) over `.onKeyPress(.escape)` for clears-then-defocuses; verify the handler is actually reached from the focused field.
- **`SongsView.content`:** add the zero-results branch (header + `ContentUnavailableView`) distinct from empty-library.
- **No new tokens** beyond the existing `SongsList` enum + `Radius.control`/`Color.card`. Modern-idiom nit while File Size becomes sortable: prefer `track.fileSize.formatted(.byteCount(style: .file))` over the stored `ByteCountFormatter`.

## 7. Debounce / cancellation contract

- View: `.task(id: model.searchQuery) { try? await Task.sleep(for: .milliseconds(120)); guard !Task.isCancelled else { return }; await model.runFilter() }`. A new keystroke changes the task id → the sleeping task is cancelled → newest-wins on the debounce.
- Model: epoch guard on publish (the actor call, once dispatched, may complete after a newer query; the guard drops the stale result).
- Target (main design §7): keystroke → filtered list **< ~250 ms**. A2's `searchMatchingIDs` + in-memory `filter` over ≤20k is well inside budget; the debounce dominates.

## 8. Accessibility

- **Sortable headers announce name + direction** and post an `AccessibilityNotification.Announcement` on sort change (both frameworks support this).
- **Row VO label is unchanged** and independent of which columns show (title, artist||"Unknown Artist", album, duration; value = quality/year/date) — hiding/sorting columns never changes a row's spoken identity.
- Filter field: standard `TextField` a11y; clear button labeled. Focus order: filter → headers → rows.
- Reduce-Motion: no row-set-swap animation on filter (don't animate the Table diff; the count text may crossfade).

## 9. Test hooks (feeds the qa-expert test-plan addendum)

**Automatable (headless):**
- `VerifyLibraryStore`: **[A2]** `searchMatchingIDs` membership parity vs `search().tracks.map(\.id)` on the same query; EXPLAIN no `SCAN TABLE tracks`; ≥2-char/junk (`!!!`) → empty; diacritics/prefix parity with existing `fts-query-*`.
- `swift test` (pure decisions extracted per the test-plan idiom): `SearchGate` (<2 → no run / restore full; ≥2 → run); newest-wins epoch compare (stale dropped); sort-comparator → `TrackSort` mapping (each sortable column, asc/desc); filtered play-from-row index correctness (visible subset, dup-title tiebreak).

**Manual (`make run`, §4 of the test plan):** filter feel < ~250 ms; **sort preserved across filter** (the key adopted behavior — filter, confirm order unchanged; click a header while filtered, confirm subset re-sorts); triangle single/active; ⌘F / Escape; zero-results view; clear restores full + prior sort; light/dark; VoiceOver header announcements.

## 10. Scope

**Decomposition (L3):** one slice, **two commits behind one gate — sortable-headers first, then filter.** Sort-headers has zero new *matching* backend (the `TrackSort` orders + SS EXPLAIN gate shipped) beyond the Artist 2-case delta; landing it first isolates the R1 selection-lag interaction of a full-20k re-sort re-read for the founder make-run, surfaces the Artist gap on its own, and keeps each diff reviewable. Filter (the new read + zero-results + epoch machinery) second.

**IN:** sortable headers (full list, DAO-side re-read) + the Artist `.artistNameAsc/Desc` delta; ⌘F filter field; filter-preserves-sort (**A2 locked**); ≥2-char + debounce + newest-wins; filtered "N results"; zero-results + junk-input states; clear-restores; header a11y announcements.

**OUT (other slices):** queue toast + OD-2 truthful counts (next slice); customizable columns / Columns button (§11/§12 main design); A–Z rail + type-to-select (tail/trim); Artists/Genres/Years + full a11y pass + drag-to-queue (S9.6); global grouped/relevance search surface (S9.6+, would consume `SearchResults.albums/.artists`); Genre header-sort (BR5 hazard, display-only).

## 11. Founder decisions (RESOLVED 2026-07-08)

*(A1-vs-A2 resolved by both reviews → A2 locked.)*

1. **Decision reversal — CONFIRMED.** Adopt filter-preserves-sort + FTS-as-matcher (drop in-table bm25 ordering); supersedes main §10.2 **and §11.5**, refines decision #3.
2. **Artist column — ADD `.artistNameAsc/.artistNameDesc`.** True click-to-sort/toggle column; composite stays as the grouped default anchor. (Includes the `trackOrder` + `descendingTrackSorts` + SS1/SS2 gate delta.)
3. **Placeholder — "Filter Songs".**
4. **Background reload — RE-RUN the active filter** after a `libraryRevision` reload.

## 12. Expert-review log (2026-07-08)

**swiftui-pro — GO-WITH-CHANGES.** Endorsed: DAO-driven sort, composite anchor (`onChange` doesn't fire on seed), A2 over A1, custom field over `.searchable`, `.task(id:)`+epoch debounce. Required: (#1) derive `sortOrder` from persisted `songSort` — table-subtree `@State` desyncs the triangle across tab teardown; (#2) resolve the Artist `TrackSort` gap + map keypath **+ direction** with a fallback; (#3) repoint row-resolution to `visibleSongs`; (#4) bump epoch at top of `runFilter`; (#5) two-param `onChange`. Nits: `@Bindable` for the field, `.onExitCommand` for Escape, `.hidden()` ⌘F button, `.formatted(.byteCount)`, don't blanket-`try?` a real store error.

**architect-reviewer — GO-WITH-CHANGES, adopt A2.** Confirmed blast radius clean (`SearchResults.albums/.artists` + bm25 order consumed only by VerifyLibraryStore Q6/Q7; no UI consumer). Blockers: H1 (Artist gap — same as #2) and H2 (epoch hole — same as #4). Also: M1/M2 (A1's cap bites the common 2-char case; A2 unifies the sort path) → A2; M3 (`searchMatchingIDs` on shared `ftsMatchQuery`, empty-set-not-nil, parity vs *unbounded* `search()`, EXPLAIN); M4 (also supersede §11.5); L1 (cache `visibleSongs`); L2 (re-filter on reload); L3 (two commits, sort first).

**All required changes are folded into §2–§10 above.** Both reviewers independently flagged the Artist gap (H1/#2) and the epoch hole (H2/#4) — treat those as the two must-fix blockers.
