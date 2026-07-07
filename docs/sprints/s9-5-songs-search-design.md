# S9.5 — Songs view · incremental search · Songs-default · queue feedback (design)

Status: **requirements vetted** (product-manager · business-analyst) + **4 decisions locked** (founder) + **UX designed** (ui-designer, §10), all 2026-07-07. Gate (architect-reviewer · the-fool) pending; founder manual-test gate is the ship criterion. Grounded on the S9.1/S9.2/S9.4 code + the S9.5 market/algorithm research.

Supersedes the two conflicting S9.5 blocks in `s9-implementation-plan.md` (to be reconciled to this doc).

## 1. The model / context

S9.4 shipped the Library tab's **Albums** grid + sidebar (Songs·Albums·Artists·Genres·Years, Songs already first) + album detail, over `LibraryBrowseModel`. The backend is further along than the UI: `LibraryStore.search()` (FTS5 + bm25, injection/diacritics-safe), `date_added` (schema + `idx_tracks_added`), and sortable/paginated track reads all exist.

**S9.5 makes the library actually usable as a *library*:** a real **Songs list** (the default landing), **incremental search** that filters it, per-row **format/quality + artwork**, **Recently-Added** sort, and a **queue-add toast** so adds from the Library are confirmed. It is *mostly* UI + wiring — but not purely: several small, headless-gatable backend deltas are required (§6).

Scope lines respected: Artists/Genres/Years lists+details = **S9.6**; playlists / queue-reorder / intentional-duplicates = **S10**; light/dark palette = **S9-T**.

## 2. Locked decisions (founder)

1. **Target scale: medium (~2k–20k tracks).** Perf is a first-class requirement, not an afterthought.
2. **Songs columns (rich):** Artwork thumbnail · Title · Artist · Album · Duration · Date Added · **Format/Quality** (audiophile differentiator, e.g. "FLAC 24/96") · Year. All sortable; default **Artist → Album → disc → track → id**.
3. **Search = incremental filter-the-current-view** — as-you-type, flat, all-fields, **bm25-ranked**. NOT a global grouped Top/Songs/Albums/Artists results view (that's a streaming/catalog pattern we don't need). `field:value` power syntax **deferred**.
4. **Queue toast only when the Up-Next panel isn't visible** — i.e. adding from Library/EQ/Settings; **silent on Now Playing** (whose right panel *is* the queue). ~2s auto-dismiss; multi-select coalesces to one toast.
5. **Default category flips Albums → Songs** (don't launch onto the old placeholder).
6. **Recently-Added sort** on Songs (and the deferred S9.4 item, on Albums).

## 3. Resolved decisions (founder, 2026-07-07)

- **OD-1 — List data = FULL-LOAD + `NSTableView` fallback (NOT keyset).** Load the compact `LibraryTrackDisplay` rows into memory (≤20k small structs ≈ a few MB) and let the view virtualize; if SwiftUI `Table` selection lags at scale, drop the hot list to `NSTableView`-via-`NSViewRepresentable`. No keyset cursor. Matches Quod Libet/foobar + the algorithm research, and `NSTableView` fixes the actual selection-lag cause directly. **⇒ F8 / D6-keyset are DROPPED; sort/search operate over the in-memory set; `trackCount` derives from the array.**
- **OD-2 — Truthful toast count = YES.** `appendToQueue`/`playNext` become `@discardableResult -> Int` (count after URL-dedup); toast reads "Added 2 to Queue" / "Already in Queue" (0-added). (D2)
- **OD-3 — Raise `search(limit:)` to a bounded ~300–500 = YES.** Header reads "N results" (N ≤ cap). (D4)
- **OD-4 — Real "Quality" column = YES.** Project `sample_rate`/`bit_depth` (already in schema) + render "FLAC · 24/96", falling back to bare format when null. (D1/D5)

## 4. Requirements (MoSCoW) — traceable to the functional list in §5

**MUST** — `SongsView` replaces the `.songs` placeholder and is the default landing (flip `selectedCategory`); virtualized full-library list holding the §7 perf bar; all 8 columns render; default composite sort + column-header sort on Title/Artist/Album/Duration/Date Added (DAO-side, EXPLAIN index-driven); double-click/Return = Play-from-row over the full ordered list; single-click selects, ⌘/⇧ multi-select; context menu Play·Play Next·Add to Queue·Info; incremental filter (debounced ~120ms, off-main, cancel-in-flight, ≥2 chars, bm25-flat, zero-results state, clear restores); queue toast (visibility-gated, ~2s, coalesced); load/empty/first-run/failed/scanning states; async per-row artwork via `ArtworkThumbnailStore` (batched warm, cache-peek, cancel-on-scroll).

**SHOULD** — sortable Year + Format/Quality columns; "N songs · total duration" count; Albums Recently-Added sort (deferred S9.4 item); type-to-select; toast tappable → jumps to Now Playing; truthful post-dedup count.

**COULD** — search "N results" feedback; A–Z jump index for alphabetical sorts; column show/hide/reorder + persistence; `.searchScopes` to one field.

**WON'T (this chunk)** — `field:value` syntax; global grouped search results (keep `SearchResults.albums/artists` produced-but-unconsumed for S9.6); Artists/Genres/Years; full a11y pass + drag-to-queue (S9.6); queue reorder/duplicates/playlists + play-count write-back (S10); light/dark palette (S9-T); `NSTableView` as *planned* scope (it's the OD-1 contingency).

## 5. Functional requirements + acceptance (condensed; full Given/When/Then in the BA record)

- **F1 Songs table** — R1.1–1.9: 8 columns; composite default sort; header sort + asc/desc toggle + indicator; sort state on the model (survives teardown); double-click/Return plays the full ordered list from the row (OD-1/§6-D3); single-click selects, multi-select; context menu (Play·Play Next·Add to Queue·Info; multi operates on the selection in sort order, Info on the primary row); load/empty/scanning/failed states; reload-once on `libraryRevision` preserving sort. *(AC-1.1…1.14)*
- **F2 Incremental search** — R2.1–2.6: as-you-type flat bm25 over title/artist/album/genre; ~120ms debounce; off-main + newest-wins cancellation (epoch guard); ≥2-char gate; `field:value` treated as plain tokens; filtered set sorts client-side; clear restores the full list. *(AC-2.1…2.10)*
- **F3 Songs-default** — R3.1: `selectedCategory` default `.songs`. *(AC-3.1…3.3)*
- **F4 Queue toast** — R4.1–4.5: on Play Next / Add to Queue only (Play Now is silent); only when `selectedTab != .nowPlaying`; ~2s; one toast per multi-select action; coalesce/replace + timer reset; count = actually-added (OD-2); reduce-motion + VoiceOver announce. *(AC-4.1…4.8)*
- **F5 Recently-Added sort** — R5.1–5.2: Date Added sortable (desc = recently-added); `date_added` projected+mapped+rendered as a human date. *(AC-5.1…5.4)*
- **F6 Count + jump-to-letter** — R6.1–6.4: live "N songs"/"N results" from a `trackCount()` read; A–Z jump for alphabetical sorts only, hidden while filtered/non-alpha; empty-letter seeks to next non-empty. *(AC-6.1…6.6)*
- **F7 Row artwork (async)** — R7.1–7.3: `ArtworkThumbnailStore` keyed by `artworkKey`; placeholder + no layout shift; sync cache-peek to avoid flash; batched `warmArtwork` per page. *(AC-7.1…7.5)*
- **F8 — DROPPED** (OD-1 = full-load): no keyset pagination. The full ordered set is held in memory; sort/filter/count operate over it. (If the founder `make run` on the real library shows a memory/scroll problem, revisit — but per OD-1 the view-side fix is `NSTableView`, not paging.)

**Edge cases (each test-covered):** empty library / no roots; track with no album/artist/year/artwork (empty cells, deterministic sort, placeholder); duplicate titles (id tiebreak, play-by-index); very long titles (truncate + full text to VO/tooltip); rapid typing (last query wins, drop-below-2 cancels); add-with-nothing-playing; filter-then-sort (client-side); multi-select spanning pages; selection during background reload; all-punctuation query (→ no-results, never error).

## 6. Data / model deltas (headless, gate-first — the "not purely UI" part)

- **D1 — `LibraryTrackDisplay` re-adds** (`LibraryTypes.swift`): `year: Int?`, `artworkKey: String?`, `dateAdded: Int64` (+ `sampleRate:Int?`, `bitDepth:Int?` per OD-4). Map `year`(idx 9)/`artworkKey`(idx 11) in place; **append** `date_added`(14)[`,sample_rate`(15)`,bit_depth`(16)] to `displayTrackColumns` so indices 0–13 don't shift. DB schema untouched (all columns already persist).
- **D2 — queue verbs return added count** (`AudioViewModel+Queue.swift` + `LibraryBrowseModel`) — OD-2.
- **D3 — Play-from-row full-order read**: on Play, model reads the full current sort (bounded) → `playNow(startAt: indexInFullOrder)`, so playback continues past the loaded window; independent of any view paging.
- **D4 — raise `search(limit:)`** — OD-3.
- **D5 — Format/Quality source** — project `sample_rate`/`bit_depth` (OD-4).
- **D6 — full-load (OD-1)**: read the full sorted set via the existing `allTracksDisplay(sortedBy:)` (no cursor, no new paged read); `trackCount` derives from the loaded array. Keep the existing reads.
- **D7 — `TrackSort` expansion** (`LibraryTypes.swift` + `trackOrder`): add title / composite-default / albumTitle / duration / dateAdded-asc / format / year, each with `id` final tiebreaker + explicit nulls-ordering; defined once so bare-`tracks` and Display reads can't drift. Verify each new sort's `EXPLAIN QUERY PLAN` against the BR5 no-`SCAN TABLE tracks` tripwire (JOINed name-sorts are the risk — R3).
- **D8 — `LibraryBrowseModel` new state**: `songs`, `songsState`, `songSort` (default composite), `searchQuery`, search/load epoch guards, `trackCount`, toast state (+ coalescing timer); flip default `.songs`; queue-forwarders return the added count.

## 7. Success criteria / non-functional (target 20k rows)

- **Find-a-song:** keystroke → filtered ranked list **< ~250ms** (≤120ms debounce + <150ms bm25 query/render). Live, no Enter.
- **Scroll:** 60fps flinging 20k; no hitch when the artwork column warms; artwork memory bounded by the existing `NSCache`.
- **Selection/keyboard latency (hard gate):** click-select + arrow-move **< 100ms** at 20k. Failing this is the pre-approved trigger for the `NSTableView` escape hatch (OD-1) — not "feels slow."
- **Sort:** re-sort any column **< ~300ms** DAO-side; `EXPLAIN QUERY PLAN` shows **no `SCAN TABLE tracks`** (BR5).
- **Default-landing:** opens on Songs; re-entry shows cached rows same-frame (no empty-flash); background refresh coalesced to `libraryRevision`.
- **Toast:** within one frame; ~2s; never on Now Playing; N adds → one toast; reports actually-added count.
- **No main-thread hang > 100ms** during load/sort/search at 20k (Instruments clean).
- **Correctness gates unchanged:** `make gate` (VerifyLibraryStore incl. new sort/EXPLAIN cases) · `swiftlint --strict` · **periphery 0** · C++ null golden master `0xE7267654BA01D315` byte-identical (no DSP touched).
- **Accessibility:** each row a single VO element (composed label) + default action plays + context verbs as custom actions; sortable headers announce name+direction; Dynamic Type scales + truncated cells expose full text; reduce-motion on toast/scroll; `DesignSystem` tokens only.

## 8. Prioritized slice plan (refined in `s9-5-songs-search-plan.md`)

1. **Backend micro-adds (headless, gated first)** — D1/D4/D5/D7 (+ D6 per OD-1); `VerifyLibraryStore` + EXPLAIN cases. Surfaces the sort/index risk (R3) before pixels.
2. **Songs list shell + Songs-default + count** — core columns, default sort, double-click/Return play, "N songs · duration". **→ founder `make run` on the real ~20k library = OD-1 go/no-go (SwiftUI `Table` vs `NSTableView`).**
3. **Column richness** — per-row artwork (heaviest), "FLAC 24/96" formatter, Year, full column sort.
4. **Incremental search** — debounced filter → flat bm25 → list; zero-results state.
5. **Queue toast** — visibility-gated capsule, coalesced count, ~2s, tappable doorway.
6. **Tail/trim** — Albums Recently-Added sort, type-to-select, A–Z jump, search count (first to defer to S9.6 if S9.5 spills).

## 9. Risks

- **R1 (biggest) — SwiftUI `Table` at 20k selection lag** → OD-1's `NSTableView` escape hatch, proven on slice 2.
- **R2 — per-row artwork decode churn on fling** → existing `ArtworkThumbnailStore` (cancel-on-scroll, downsample, NSCache); art column is first to drop if scroll degrades.
- **R3 — sorting on JOINed artist/album *names*** may hit a temp-b-tree/`SCAN` and trip the EXPLAIN gate → verify in slice 1; may need a denormalized sort column or an accepted bounded filesort.
- **R4 — `search(limit:50)`** truncates the filter → OD-3.
- **R5 — toast vs dedupe** → OD-2 (report actual count).

---

## 10. UX design (ui-designer, 2026-07-07)

Mirrors the shipped S9.4 idioms (`AlbumDetailView` TrackRow, `AlbumArtworkView`, `LibraryEmptyStateView`, `ErrorBanner`/`EQRecallBanner` capsule) + the `macos-design` HIG skill. Every value is a `DesignSystem` token or a proposed token (§10.8).

### 10.0 View tree
`ContentView(AppShell)` → content = `TabContentView` with `.overlay(.top) ErrorBanner` (existing) + **`.overlay(.bottom) QueueToast`** (NEW, shell-hosted, gated by `selectedTab != .nowPlaying`). Library detail column hosts **`SongsView`** (replaces the `.songs` placeholder in `LibraryCategoryRoot`): `VStack(spacing:0){ SongsHeader (count + search) · Hairline · ZStack{ SongsTable ; AZRail(.trailing) } }`. Default landing = flip `LibraryBrowseModel.selectedCategory` `.albums → .songs`.

### 10.1 Songs table
SwiftUI `Table` with `selection: Set<ID>` + `sortOrder: [KeyPathComparator]` (the binding renders the native platform sort triangle + drives header clicks; observe it, translate the primary comparator to a `TrackSort`, re-read DAO-side so ordering stays index-driven/EXPLAIN-gated). `NSTableView` fallback (OD-1) inherits this visual spec.

| # | Column | Header | Sort | Align | min/ideal/max | Resize |
|---|---|---|---|---|---|---|
| 1 | Artwork | — | no | center | 32 fixed | no |
| 2 | Title | Title | yes | leading | 160/300/∞ (primary flex) | yes |
| 3 | Artist | Artist | yes | leading | 110/170/∞ | yes |
| 4 | Album | Album | yes | leading | 110/190/∞ | yes |
| 5 | Time | Time | yes | trailing | 52/60/72 | no |
| 6 | Date Added | Date Added | yes | leading | 92/112/140 | yes |
| 7 | Format | Format | yes | leading | 96/118/140 | yes |
| 8 | Year | Year | yes | trailing | 44/52/64 | no |

- **Row height 36 fixed** (uniform → helps 60fps virtualization; ~14 rows at min height). At the 880 window-min the sum-of-mins + rail ≈ detail width, so the native Table shows a horizontal scroller at absolute-min; Format + Date Added compress first (acceptable, native).
- **Artwork:** reuse `AlbumArtworkView(key:, side: 28)` verbatim (sync cache-peek → no flash, off-main downsample, cancel-on-scroll, reduce-motion fade, `music.note`-on-`card` placeholder, `Radius.control` clip). Per-row lazy warm suffices; optionally batch `warmArtwork` on the first screenful.
- **Title** `Font.body`/`label`, 1 line tail. **Artist/Album** `Font.body`/`labelSecondary`, 1 line tail; empty artist/nil album → **blank cell** (no "Unknown Artist" in-cell — VO substitutes it). **Time** `Font.body` + `.monospacedDigit()`/`labelTertiary` trailing (uses `formatDuration()`; body+mono, not `monoSmall`, so baselines align across columns). **Date Added** `Font.caption`/`labelTertiary`, "MMM d, yyyy" (nil/0 → blank; new compact date formatter). **Format** `Font.body`+mono/`labelSecondary`: `FORMAT` + (bit&rate ? " · 24/96" : ""), e.g. "FLAC · 24/96", bare "AAC" when null — **plain text, not a colored badge** (badge noise at 20k; badge stays in the Info popover + footer). **Year** `Font.body`+mono/`labelTertiary` trailing (0/nil → blank).
- **Sort:** native headers. First-click direction: Title/Artist/Album/Format/Year → asc; **Date Added → desc** (recently-added); Time → asc. Triangle only on the active column. **Composite default** (Artist→Album→disc→track→id): seed visual `sortOrder` to Artist-asc as the anchor (grouped-by-artist), model applies the composite; first explicit header click switches to that column's plain sort. Sort state persists on the model (survives teardown).
- **Selection:** single-click selects; ⌘/⇧ multi-select; **system list-selection highlight (NOT teal)** — HIG, dims on blur, auto light/dark. **Double-click/Return → Play** the full ordered list from the row (`playNow(startAt: indexInFullOrder)`, D3). **No hover row-fill**, default arrow cursor (single-click = select, not link) — HIG-correct + avoids fling churn.

### 10.2 Filter field (search)
In **SongsHeader** (44pt band, `.padding(.horizontal, 20)`): leading = count line (§10.5), trailing = search field. Field: `RoundedRectangle(Radius.control)` `Color.card` + 0.5 `hairline` stroke, height 28, min 180 / ideal 240, trailing-anchored; leading `magnifyingglass` (`labelTertiary`) + `TextField` (`Font.body`/`label`, placeholder **"Search Songs"**); trailing `xmark.circle.fill` clear when non-empty. **⌘F focuses** (hidden button/`@FocusState`); **Escape** clears-then-defocuses. ≥2 chars · ~120ms debounce · off-main + newest-wins (model). **Transition full↔filtered:** header/field never move; entering filter → rows swap to bm25 **relevance order**, sort triangle clears ("Relevance"; headers still re-sort the subset client-side), A–Z rail hides, count → "N results". Don't animate the row-set swap (Table diff jank); only the count text may crossfade. Clearing restores the full list + prior sort + rail.

### 10.3 States
Header + rail hidden whenever there's no content. Loading → `ProgressView`. First-run/scanning-empty/empty-library/failed → reuse `LibraryEmptyStateView(kind:)` (no new case). Scanning **with rows** → show the table (sidebar scan strip is the only cue; live-fill on `libraryRevision` preserving sort/selection). No-search-results → `ContentUnavailableView` (magnifyingglass, "No Results", "No songs match “\(query)”.") with the **header shown** (field + "0 results"), rail hidden.

### 10.4 Queue toast
`TabContentView.overlay(alignment: .bottom) { QueueToast() }` — bottom sibling of `ErrorBanner`; reads coalesced toast state on `LibraryBrowseModel` (D8). **Bottom-center**, `.padding(.bottom, 16)` (floats above the footer). **Render only when `selectedTab != .nowPlaying`.** Style = `EQRecallBanner` capsule exactly (`.ultraThinMaterial` in `.capsule` + `hairline` stroke; icon `accent`, text `Font.callout`/`label`, trailing `chevron.forward`/`labelTertiary`). Copy (count = actually-added, OD-2): Add to Queue → "Added N to Queue" / "Added to Queue" / "Already in Queue"; Play Next → "Added N to Play Next" / "Playing Next" / "Already in Queue"; **Play Now = silent**. Multi-select → **one** toast, true added count. Whole capsule is a `Button` → `selectedTab = .nowPlaying` (doorway, `.link` pointer). Motion: `.move(edge:.bottom)+.opacity` `.easeInOut(0.25)`; **reduce-motion → `.opacity` only**; ~2.0s auto-dismiss; a new add within the window **replaces text + resets timer** (never stacks). VoiceOver: one `.isButton` element (label = message, hint "Opens Now Playing") + `AccessibilityNotification.Announcement(message)` on appear.

### 10.5 Count + A–Z rail + type-select
**Count** (leading in header, `Font.caption`/`labelSecondary`): unfiltered "**N songs · total**" ("1,240 songs · 3 hr 14 min"; grouping separator; singular "1 song"; needs a humane total-duration formatter); filtered "**N results**" (drop duration; 0 → "0 results"). **A–Z rail:** alphabetical sorts only (Title/Artist/Album; hidden while filtered or on Time/Date/Format/Year); slim 18pt trailing strip (Table trailing inset = 18 so it never overlaps the scroller), A–Z + "#"; `Font.micro`/`labelTertiary`, hover/press → `accent`; tap → `ScrollViewReader.scrollTo(firstRowID, anchor:.top)` on the active sort-key, empty letter seeks the next non-empty bucket; reduce-motion → no scroll animation. **This is COULD-priority — first to defer to S9.6 if the chunk spills.** **Type-to-select:** native Table type-select (no custom UI); ensure the Table has key focus.

### 10.6 Context menu + Info
Mirror `AlbumDetailView`. Single row: Play (full ordered list from row) · Play Next · Add to Queue · — · Info. Multi-select: Play plays the **selected subset** as the queue; Play Next/Add to Queue on the whole selection in sort order; Info on the primary row. Info = `.popover(arrowEdge:.trailing){ TrackInfoCard(file: AudioFile(track)) }` (renders `FormatBadgeView` + async rate/depth/channels/size + copyable path). Play Next/Add to Queue fire the §10.4 toast; **Play is silent**.

### 10.7 Accessibility + light/dark
**Row = one VO element** (`children:.ignore`): label `"\(title), \(artist||"Unknown Artist")"` + album? + duration; value = "\(quality), \(year), added \(fullDate)" (skip nils); truncated cells expose full text to VO + `.help(full)` tooltip. **Default action = Play**; custom actions Play Next / Add to Queue / Info. Sort headers announce name+direction (+ `Announcement` on change). **Dynamic Type:** clamp Table to `.dynamicTypeSize(.small ... .xxLarge)` (36pt fixed rows can't grow to AX5; Info popover + tooltips carry full-fidelity scaling; header/count/search scale normally). Focus order: search → headers → rows → rail; toast announced but out of tab order. **Light/dark:** all `DesignSystem` dynamic tokens (`card`/`panel`/`window`/`hairline`, `label*` clear WCAG AA on `card` per token comments, teal `accent` appearance-independent); selection = system highlight; toast `.ultraThinMaterial`. No hardcoded colors, no `colorScheme` checks.

### 10.8 Token delta
Reuse everything first (`Spacing`, `Radius.control`, `Font.body/caption/micro/callout`, `Color.*`, `LayoutMetrics.screenInsetH`, `AlbumArtworkView`, `EQRecallBanner` recipe). Add one grouped enum in `DesignSystem.swift` (peer of `Footer`/`LayoutMetrics`):
```swift
enum SongsList {
    static let rowHeight: CGFloat = 36          // uniform; dense but artwork-legible; aids virtualization
    static let artwork: CGFloat = 28            // row thumb (denser than the 44pt footer Artwork.thumb)
    static let headerHeight: CGFloat = 44       // SongsHeader (count + search)
    static let searchFieldMinWidth: CGFloat = 180
    static let searchFieldIdealWidth: CGFloat = 240
    static let azRailWidth: CGFloat = 18
}
```
Column min/ideal/max may be inlined on each `TableColumn` (single-consumer). Non-token helpers to add (like `DurationFormatter`): compact date ("MMM d, yyyy"), humane total-duration ("3 hr 14 min"), and the "FLAC · 24/96" quality-string builder (reuse the `TrackInfoCard` kHz rule).

### 10.9 File map (for swiftui-pro)
- **New:** `UI/Library/SongsView.swift` (table + header + A–Z rail), row/column builders, `UI/Shell/QueueToast.swift`.
- **Edit:** `LibraryCategoryRoot.swift` (`.songs` → `SongsView`); `LibraryBrowseModel.swift` (default `.songs` + songs/sort/search/toast state, D8); `ContentView.swift` (bottom `QueueToast` overlay); `DesignSystem.swift` (`SongsList`).
- **Reuse unchanged:** `AlbumArtworkView`, `TrackInfoCard`, `LibraryEmptyStateView`, `FormatBadgeView` (Info only), `DurationFormatter`.

---

*Next: **swiftui-pro** implements the slices (§8: backend micro-adds → Songs list + default-flip → founder `make run` perf go/no-go → columns/artwork → search → toast → tail), each behind build/lint/test/periphery; then **architect-reviewer + the-fool** gate; then the founder manual-test gate.*
