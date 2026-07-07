# S9.5 — Songs view · incremental search · Songs-default · queue feedback (design)

Status: **requirements vetted** (product-manager · business-analyst) + **4 decisions locked** (founder) + **UX designed** (ui-designer, §10) + **customizable-columns spec** (ui-designer, §11), all 2026-07-07. Gate (architect-reviewer · the-fool) pending; founder manual-test gate is the ship criterion. Grounded on the S9.1/S9.2/S9.4 code + the S9.5 market/algorithm research.

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

**COULD** — search "N results" feedback; A–Z jump index for alphabetical sorts; column show/hide/reorder + persistence (**specced §11 → folded into slice 3** over the cheap catalog); `.searchScopes` to one field.

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
3. **Column richness + customization** — per-row artwork (heaviest), the "FLAC · 24/96" Quality formatter, Year, Track #, full column-header sort, **and customizable columns** (show/hide via the native header menu + a "Columns" button, drag-reorder, resize, versioned-`AppStorage` persistence) over the **cheap** catalog with Artwork/Title locked-on — spec in **§11**. Needs-read columns (Disc #, File Size, Album Artist, Genre, Play Count) are catalogued but deferred behind a projection/EXPLAIN delta (§11.1, fork D-A).
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

## 11. Customizable columns (ui-designer, 2026-07-07)

Promotes the §4 COULD "column show/hide/reorder + persistence" into a shipped **slice-3** feature over the **cheap** catalog (zero extra read), matching Finder / Apple Music / foobar2000. Designed WITH the SwiftUI `Table` grain: **`TableColumnCustomization`** (macOS 14+, `.customizationID` + `.defaultVisibility` per column) gives the header context-menu (show/hide) + drag-reorder + resize + a `Codable` state we persist — and maps 1:1 onto the OD-1 `NSTableView` fallback (§11.9). The spec below (catalog · defaults · interaction · persistence) is **presentation-agnostic** and holds for either backend.

### 11.0 Locked decisions
1. **Customizable set = the CHEAP catalog only** — everything already on `LibraryTrackDisplay` post-D1 (zero extra read): Title (always-on) · Artist · Album · Time · Date Added · Quality · Year · Track # · Format. The **needs-read** columns (Disc # · File Size · Album Artist · Genre · Play Count) are **catalogued (§11.1) but NOT shipped in S9.5** — each needs a projection/join delta vetted against BR5 before it earns a column (founder fork **D-A**).
2. **Two always-on, non-hideable columns.** **Artwork** — locked *all* (no hide / reorder / resize; always the leading column) — and **Title** — locked *hide + reorder* (always the leftmost text column; still resizable). ⇒ the table can never be emptied of columns, so there is **no "0 columns" degenerate state** (§11.6).
3. **Native header context-menu = the primary mechanism**, plus a thin trailing **"Columns" menu button** in `SongsHeader` for discoverability and to home **Reset to Default** (fork **D-B**).
4. **Reorder ON · width-persistence ON** — both are free with `TableColumnCustomization` and expected by the Finder/foobar audience.
5. **One global Songs config**, persisted in a **versioned `@AppStorage`** blob, kept **independent of the model-side sort state** (§11.4, fork **D-C**).

### 11.1 Column catalog
Header · source field (on `LibraryTrackDisplay` unless noted) · cost tier · default-visible · always-on · header-sort · align · min/ideal/max. The stable `customizationID` is in `code`. `∞` = flex (`ideal` with no `max`). All fonts/colors are `DesignSystem` tokens (per-column value formatting, incl. nil/empty, follows the table). Rows above the rule are **cheap** (shipping S9.5); below are **needs-read** (catalogued, deferred — D-A).

| # | Column (header) · `id` | Source field | Cost | Default? | Always-on? | Sort | Align | min/ideal/max |
|---|---|---|---|---|---|---|---|---|
| — | Artwork · `artwork` | `artworkKey` (thumb) | cheap | yes | **yes (all)** | no | center | 32 fixed |
| 1 | Title · `title` | `title` | cheap | yes | **yes (hide+reorder)** | yes | leading | 160/300/∞ |
| 2 | Artist · `artist` | `artistName` | cheap | yes | no | yes | leading | 110/170/∞ |
| 3 | Album · `album` | `albumName` | cheap | yes | no | yes | leading | 110/190/∞ |
| 4 | Time · `time` | `durationMs` | cheap | yes | no | yes | trailing | 52/60/72 |
| 5 | Date Added · `dateAdded` | `dateAdded` | cheap | yes | no | yes (desc-first) | leading | 92/112/140 |
| 6 | Quality · `quality` | `format` + `bitDepth`/`sampleRate` | cheap | yes | no | yes (by `format`) | leading | 96/118/140 |
| 7 | Year · `year` | `year` | cheap | yes | no | yes | trailing | 44/52/64 |
| 8 | Track # · `trackNo` | `trackNo` | cheap | **no** | no | yes | trailing | 44/52/64 |
| 9 | Format · `format` | `format` (bare codec) | cheap | **no** | no | yes | leading | 64/80/100 |
| — | *— needs-read (deferred, D-A) —* | | | | | | | |
| 10 | Disc # · `discNo` | `tracks.disc_no` — projection (+col, **no join**) | needs-read · low | **no** | no | yes | trailing | 44/52/64 |
| 11 | File Size · `fileSize` | `tracks.file_size` — projection (+col, **no join**) | needs-read · low | **no** | no | yes | trailing | 72/88/110 |
| 12 | Album Artist · `albumArtist` | `album_artist_id` → `artists` — projection (**+1 LEFT JOIN**) | needs-read · join | **no** | no | yes (EXPLAIN-gated, R3) | leading | 110/170/∞ |
| 13 | Genre · `genre` | `track_genres` — projection (**+join + agg**) | needs-read · heavy | **no** | no | **no (BR5 temp-b-tree risk)** | leading | 90/130/180 |
| 14 | Play Count · `playCount` | `play_count` user-state — projection (**+read; STALE until S10**) | needs-read · state | **no** | no | yes (desc-first) | trailing | 56/68/88 |

**Value formatting + fonts** (mirrors §10.1; empty/nil rendering is explicit):
- **Artwork** — `AlbumArtworkView(key:, side: 28)` verbatim; `music.note`-on-`card` placeholder. Not in the customization menu (locked all).
- **Title** `Font.body`/`label`, 1-line tail. Never blank (falls back to the filename `name`).
- **Artist** `Font.body`/`labelSecondary`, tail; `""` (no artist) → **blank cell** (VO substitutes "Unknown Artist", §10.7).
- **Album** `Font.body`/`labelSecondary`, tail; `nil` → **blank cell**.
- **Time** `Font.body`+`.monospacedDigit()`/`labelTertiary`, trailing; `formatDuration()` (0 ms → "0:00").
- **Date Added** `Font.caption`/`labelTertiary`, "MMM d, yyyy"; `0`/unknown → **blank**.
- **Quality** `Font.body`+mono/`labelSecondary`: `FORMAT` + (depth&rate ? " · 24/96" : "") → "FLAC · 24/96", bare "AAC" when null. `format` is NOT NULL → never blank. **Plain text, not a colored badge** (badge lives in the Info popover, §10.6).
- **Year** `Font.body`+mono/`labelTertiary`, trailing; `0`/`nil` → **blank**.
- **Track #** `Font.body`+mono/`labelTertiary`, trailing; `nil` → **blank**. (First-click sort = asc.)
- **Format** `Font.body`+mono/`labelSecondary`, leading; never blank. *Codec-only alternative to Quality* — default-hidden to avoid on-screen redundancy; offered for users who want just the container.
- **Disc #** `Font.body`+mono/`labelTertiary`, trailing; `nil` → **blank**.
- **File Size** `Font.body`+mono/`labelTertiary`, trailing; `ByteCountFormatter` / `.byteCount(style: .file)` → "24.1 MB"; `0` → **blank**.
- **Album Artist** `Font.body`/`labelSecondary`, tail; `nil`/`""` → **blank cell**.
- **Genre** `Font.body`/`labelSecondary`, tail; first (or joined) genre name; empty → **blank cell**.
- **Play Count** `Font.body`+mono/`labelTertiary`, trailing; `0` → **blank** (avoids a wall of zeros — and every value is 0 until the S10 write-back). (First-click sort = desc when it ships.)

**Needs-read cost detail** (why they're deferred — D-A): Disc #/File Size are the cheapest — one extra `tracks` SELECT column each, **no join** (file_size already exists on `LibraryTrack`). Album Artist adds one LEFT JOIN (albums→artists) and re-opens the **R3** JOINed-name-sort SCAN risk. Genre is the heaviest — a `track_genres` many-to-many join needing aggregation (a representative genre), and its **sort is a temp-b-tree/BR5 hazard → display-only until EXPLAIN-proven**. Play Count reads `play_count`, but that column has **no write-back until S10** (the §4 WON'T list), so every value would read `0` — misleading to ship now.

### 11.2 Default visible set + order · reset
- **Default visible (left→right):** Artwork · **Title** · Artist · Album · Time · Date Added · Quality · Year — identical to the shipped §10.1 order (the §10.1 "Format" column header is **renamed "Quality"**, same cell content; bare "Format" is now a separate default-hidden column).
- **Available-but-hidden (menu order):** Track # · Format · *(then, once D-A greenlights)* Disc # · File Size · Album Artist · Genre · Play Count.
- **`.defaultVisibility(.hidden)`** marks the available-but-hidden columns; visible ones default `.automatic`.
- **Reset to Default** lives in the "Columns" button menu (below a divider): assigns a fresh `TableColumnCustomization()` → restores default visibility/order/**widths** in one action (the `AppStorage` blob rewrites on the next change). VO announces "Columns reset to default." The native header menu has no reset — that gap is half the reason the button exists (D-B).

### 11.3 Customization mechanism
- **Primary — native header context-menu** (`columnCustomization:` binding): right-click any header → checkmarked show/hide list + drag-reorder + drag-resize. Zero custom UI; the HIG-standard Finder/Mail/Music idiom; inherited free by the `NSTableView` fallback.
- **Discoverability — a thin trailing "Columns" `Menu` button** in `SongsHeader`, placed after the search field (§10.2), glyph `slider.horizontal.3`, `.help("Columns")`. It is a **thin view over the SAME `TableColumnCustomization` state** (`customization[visibility: id]`) → **no drift** with the native menu. It carries the show/hide toggles **plus** Reset to Default. Shown only when the header is (i.e., when rows exist, §10.3/§11.6).
- **Reorder = ON** (drag; Artwork & Title excluded via their locks). **Resize + width-persistence = ON** for the flex text columns; the fixed columns (Artwork, Time, Year, Track #, Disc #) are effectively non-resizable via near-equal min/max.

### 11.4 Persistence
- **Stored payload:** the `Codable` `TableColumnCustomization<LibraryTrackDisplay>` only — per-column **{visibility, order index, width}**. Nothing else.
- **Mechanism:** a **versioned `@AppStorage`** key, `"songs.columns.v1"` (a `Data`/`RawRepresentable` bridge over the `Codable` state). Bump the `.vN` suffix on **any** catalog change (a `customizationID` added/removed/renamed, or a change to the always-on lock set) → a stale / absent / undecodable blob **falls back to a fresh default** `TableColumnCustomization()` (never crashes, never a broken layout).
- **Scope: one global Songs config** (confirmed) — `@AppStorage` (app-wide), **not** `@SceneStorage` (multiple windows share one library layout; D-C).
- **Independent of sort:** column state is stored HERE; sort order stays on `LibraryBrowseModel.songSort` (§10.1). Two stores ⇒ a column edit never perturbs sort, and a sort never rewrites the column blob.

### 11.5 Sorting coexistence
- `sortOrder:` (left-click header → platform triangle) and `columnCustomization:` (right-click menu + drag) are **orthogonal bindings on the same `Table`** and coexist natively (exactly as Finder/Mail). **Left-click = sort; right-click = show/hide/reorder.**
- Only catalog-**sort=yes** columns take a `KeyPathComparator` → `TrackSort` (the D7 orders). Non-sortable columns (Artwork; Genre pre-EXPLAIN) have no header-click and no triangle.
- **Hiding the active-sort column** → sort snaps back to the composite default (Artist→Album→disc→track→id), triangle clears; re-showing the column does **not** auto-restore its sort (an explicit re-click is required). Prevents an invisible sort key.
- **Reorder/resize never change sort;** the triangle rides with its column wherever it moves.
- In **filtered / relevance** mode (§10.2) the triangle is already cleared ("Relevance"); the customization menu + Columns button keep working over the filtered subset.

### 11.6 Degenerate / empty states · a11y · dark theme
- **"Hide everything":** impossible below the **Artwork + Title floor** (both locked). Hiding all removable columns leaves a clean two-column list — still fully usable; no empty-columns state to design.
- **Empty / first-run / scanning / failed:** header (hence the Columns button) + table are hidden when there is no content (§10.3) — customization UI exists only when rows do. In **no-search-results** the header stays shown, so the Columns button remains available (arrange for when results return).
- **a11y — customization menu:** native header-menu items are VoiceOver checkboxes ("Artist, checked"). The **Columns** button = a `Menu` labeled "Columns"; each entry a `Toggle` announced with on/off state; Reset is a button. **Keyboard-only users show/hide via this menu** (drag-reorder is pointer-centric — acceptable; reorder is a COULD nicety, not a parity requirement).
- **a11y — cells:** the composed row VO label (§10.7) stays **stable regardless of which columns are visible** — hiding a column changes the visual grid, NOT the row's spoken identity (title, artist, album, duration in the label; quality/year in the value). Never strip a hidden field from VoiceOver.
- **a11y — headers:** sortable headers announce name+direction (§10.7, `Announcement` on change); the header customization menu is reachable from the VO rotor.
- **Dynamic Type:** unchanged `.small ... .xxLarge` clamp; the native menu + the Columns menu scale with the system.
- **Dark theme:** the native header menu + the Columns menu use system menu material (appearance-correct). The Columns glyph = `labelSecondary`, `accent` on hover/press (matches the §10.2 search-field idiom). No hardcoded colors, no `colorScheme` checks — `DesignSystem` dynamic tokens throughout.

### 11.7 Decisions for founder
**D-A — Which columns ship as customizable in S9.5?**
- **Recommended — CHEAP-only (9 columns):** Title / Artist / Album / Time / Date Added / Quality / Year / Track # / Format. All already projected post-D1 → **zero extra read, zero new backend, holds BR5**. Needs-read columns stay catalogued (§11.1) for a fast-follow once their deltas are gated.
- Option 2 — **Cheap + the two projection-only needs-read (Disc #, File Size):** one extra SELECT column each, **no join**, low risk (still EXPLAIN-checked). Modest reach for two audiophile-relevant fields.
- Option 3 — **Full catalog now (adds Album Artist / Genre / Play Count):** *rejected for S9.5* — the joins re-open the R3 SCAN risk, Genre sort is a temp-b-tree/BR5 hazard, and Play Count reads 0 until the S10 write-back. Right after their deltas are gated, not now.

**D-B — Discoverability affordance beyond the native menu?**
- **Recommended — native header menu (primary) + a thin trailing "Columns" button:** right-click-a-header is genuinely low-discoverability, and **Reset to Default** needs a home the native menu can't give it. The button is a `Menu` over the SAME `TableColumnCustomization` state (no drift) — one glyph in the header, hidden with the empty states.
- Option 2 — **Native menu ONLY:** smallest surface, most HIG-pure (Finder/Music do this), but there's no Reset and many users never discover column customization at all.
- Option 3 — **Custom "Columns" panel that replaces the native menu:** *rejected* — fights the platform grain and forfeits the free `NSTableView`-fallback parity.

**D-C — Persistence scope + mechanism?**
- **Recommended — one global, versioned `@AppStorage` blob** (`"songs.columns.v1"` = `Codable TableColumnCustomization`: visibility + order + width), shared across windows, **independent of** the model-side sort state. A version-suffix bump on any catalog/lock change → stale blobs fall back to default (no crash, no broken layout).
- Option 2 — **per-window `@SceneStorage`:** *rejected* unless independent per-window Songs layouts are wanted (not in scope; multi-window should share one library layout).
- Option 3 — **fold sort order into the same blob:** *rejected* — sort already persists on `LibraryBrowseModel.songSort` (§10.1); keeping the two stores separate means a column edit never perturbs sort and vice-versa.

### 11.8 Slice-plan reconciliation
This §11 **expands §8 slice 3 from fixed → customizable columns** (edited in §8 above) and **promotes** the §4 COULD "column show/hide/reorder + persistence" into that slice, scoped to the **cheap** catalog with Artwork/Title locked-on. The needs-read columns (§11.1) remain a deferred fast-follow behind their projection + EXPLAIN deltas (D-A). No other slice changes; the sort/state model of §10.1 is unchanged (column state is a NEW, independent AppStorage store, §11.4).

### 11.9 Token / impl notes · presentation-agnostic mapping
- **Tokens:** reuse §10.8 (`SongsList`, `DesignSystem.Font`/`Color`, `Radius.control`). No forced additions — the Columns button reuses the search-field's 28pt control height (inline). New non-token constants: the `customizationID` string set + the `"songs.columns.v1"` AppStorage key & version; a `ByteCountFormatter` helper **only if** File Size ships; a genre-string helper **only if** Genre ships. Per-column min/ideal/max are inlined on each `TableColumn` (single consumer, per §10.8).
- **Presentation-agnostic mapping (OD-1 `NSTableView` fallback):** show/hide → `NSTableColumn.isHidden` via a header `NSMenu`; reorder → `allowsColumnReordering`; resize → `min`/`maxWidth` + `allowsColumnResizing`; persistence → `autosaveName` + `autosaveTableColumns` (the `AppStorage`-blob analog; version via an `autosaveName` suffix bump); always-on lock → omit Artwork/Title from the header menu. The catalog / defaults / interaction / persistence spec is identical across both backends.

---

## 12. Founder decisions + full-catalog columns + play-tracking (2026-07-07)

**Founder resolved the §11.7 forks:**
- **D-A → FULL CATALOG NOW.** All 14 columns are customizable this release, incl. the needs-read tier (Disc #, File Size, Album Artist, Genre) and Play Count. Overrides §11's cheap-only recommendation — the needs-read projection/JOIN deltas below are pulled into slice 3.
- **D-B → native header menu + thin "Columns" button** (as recommended; §11 unchanged).
- **D-C → one global versioned `@AppStorage` layout** (as recommended; §11.4 unchanged).
- **Play Count → wire play-tracking now** (founder deliberately pulls increment-on-play forward from S10 to make the column real; §12.3).

**Governing constraint (founder, 2026-07-07): NO DB migrations.** Drop-and-recreate the song DB on any schema change — the library is a rebuildable cache of the on-disk files. Prefer the simplest projection/DAO design; no ALTER/migration logic. *For this change specifically, **no schema change is needed** — `disc_no`, `file_size`, `play_count`, `last_played` all already exist, and Genre/Album-Artist come from existing tables.*

### 12.1 Needs-read columns — projection + JOIN plan (BR5-gated)
- **Projection-only (no JOIN):** Disc # (`t.disc_no`), File Size (`t.file_size`), Play Count (`t.play_count`), Last Played (`t.last_played`, if surfaced) — append to `displayTrackColumns` per the S9.1 "append-only, indices stable" rule. Negligible cost.
- **JOIN-backed (the R3/BR5 hazard):** Album Artist (`albums.album_artist_id → artists.name`, LEFT JOIN on an indexed FK — bounded) and Genre (`track_genres → genres.name`, multi-valued → render as a **correlated scalar subquery** for the primary genre or `GROUP_CONCAT`, **NOT a fan-out JOIN that multiplies rows**).
- **BR5 hard gate:** the extended `allTracksDisplay` must keep `EXPLAIN QUERY PLAN` free of `SCAN TABLE tracks` at 20k. Sort-by-Genre / sort-by-Album-Artist (if offered) are temp-b-tree filesorts (like the composite default, SS2) — acceptable at ≤20k but must be EXPLAIN-classified, with VerifyLibraryStore SS cases added (SS3 projection round-trip extended; a new SS for the JOIN plan).

### 12.2 Value formatting (needs-read)
Disc # — trailing int, blank if nil/0. · File Size — `ByteCountFormatter` ("42.1 MB"), trailing, blank if 0. · Play Count — trailing int, **"—"/blank for 0** (avoid a wall of zeros; the-fool to weigh). · Album Artist — leading text, blank if nil. · Genre — leading text, primary/comma-joined, blank if none.

### 12.3 Play-tracking wiring (pulled forward from S10) — PROPOSED, pre-change review to vet
- **When:** count a play when a track **completes naturally** — in `handleTrackTransition()` (the gapless-seam advance, `AudioViewModel+AutoAdvance.swift`), the **outgoing** track (pre-advance `selectedTrackIndex`) gets +1; also count the final track on the true end-of-queue (out-of-range / stop) branch. **Manual skip (Next) does NOT count** (recommend — "a play = heard through"). Alternative threshold rule (≥50 % / 4 min) is heavier (needs position tracking); completion rule recommended for simplicity.
- **How:** new DAO `incrementPlayCount(trackID:playedAt:)` → `UPDATE tracks SET play_count = play_count + 1, last_played = ? WHERE id = ?` (single atomic statement, no read-modify-write race). Map completed `AudioFile` (URL identity) → `tracks.id` via `track(url:)`.
- **Concurrency:** `LibraryStore` is an actor; fire the write as a detached/fire-and-forget `Task` off the audio/main path — a play-count write must never stall playback. Fires exactly once per (single-shot) seam transition.
- **UI refresh:** the Songs list is a full-load snapshot; a bump reflects on the next `loadSongs`/`libraryRevision` — no per-play table churn (recommend accept).
- **No schema change; no migration.**

### 12.4 De-scope vs S10
Only the **increment-on-play + `last_played` write** is pulled forward. The rest of S10 "history" (recently-played views, play-count smart sorts/lists) stays in S10 — flag there so it isn't rebuilt.

### 12.5 Pre-change review outcomes (architect-reviewer + the-fool, 2026-07-07)
Verdicts: columns §12.1 **GO-WITH-CHANGES**; play-tracking §12.3 **GO-WITH-CHANGES (firing relocation required)**; no-migrations **GO**; EQ persistence **GO** (vetted approach). Required changes:

**Columns (§12.1):**
- **Disc # is ALREADY projected** (`displayTrackColumns` index 8, currently unmapped) → just map it into `LibraryTrackDisplay`; no append. Append `file_size`/`play_count`/`last_played` at indices **17/18/19** (0–16 unchanged; positional decode).
- **Album Artist:** add `LEFT JOIN artists aar ON aar.id = al.album_artist_id`. `albums.album_artist_id` is `NOT NULL DEFAULT 0` (Unknown-Artist sentinel, Schema.swift:96) → **map id==0 → BLANK cell** (not "Unknown Artist"), matching other columns' nil-rendering.
- **Genre:** correlated scalar subquery in the projection (precedent: FTS backfill Schema.swift:215, `group_concat` over `track_genres`) — one row per track, index-seek on the `track_genres` PK. **BR5-safe at design level** (a projection subquery adds no `SCAN TABLE tracks`; BR5 is about the ORDER BY plan); sql-pro confirms it meets §7 timing at 20k. **Genre = display-only, NO header sort** (keep §11.1). Album-Artist sort (if offered) = accepted temp-b-tree filesort (same class as the composite default) → needs a `TrackSort` case + EXPLAIN classification.
- Extend **VerifyLibraryStore SS3** (projection round-trip incl. the new columns) — non-optional (positional decoder w/o test = silent index drift).

**Play-tracking (§12.3) — count at FOUR natural-completion sites, not one** (single-site plan silently under-counts; missing the final/single track is a HARD bug — the normal end-of-queue never enters `handleTrackTransition`, it ends in `tickTransport`):
1. `handleTrackTransition` normal path (gapless seam — Enhanced + Pure same-rate).
2. `handleTrackTransition` out-of-range guard (playlist-shrank-after-arming edge — AutoAdvance:17-22).
3. `tickTransport` → `playbackEnded()` **reconfigure branch** (Pure cross-rate advance — SpectrumTimer:102-111).
4. `tickTransport` → `playbackEnded()` **else branch** (true end-of-queue / single-track — SpectrumTimer:112-116).
- One `@MainActor countCompletion(url:)` helper at all four; **capture the OUTGOING track's URL as a local BEFORE any `selectedTrackIndex` reassign** (AutoAdvance:28 / SpectrumTimer:105).
- DAO: atomic **URL-keyed** `UPDATE tracks SET play_count = play_count + 1, last_played = ? WHERE url = ?` (normalize via `PathNormalizer`); NEW `incrementPlayCount` (NOT `setUserState` — update its S10-deferred comment). Increments commute → fire-and-forget ordering irrelevant; 0 rows for non-library files is correct; store==nil / write-error swallowed, never touches playback.
- Manual skip **CONFIRMED excluded** (primeGaplessPipeline rebaselines `lastTransitionCount`) — do NOT add counts to `startPlayback`/`playTrack`/`armOnDeck`. repeat-one counts each loop (keep).

**Confirmed behavior change (refactoring-specialist, post-change review):** pre-change, EVERY launch recalled the device-mapped preset (F3); post-change, every launch restores "last setting" instead, per the last-setting-wins-at-launch rule above. Intended, not a defect — noting explicitly since it changes launch-time F3 semantics for anyone using per-device preset recall.

**EQ persistence — vetted approach:** `EQLiveState{presetRaw,bandGains}` under `"eqLiveStateV1"` restored in `loadPersistedState()` (validate 31 bands + clamp [-12,+12]); `isUsingDiscreteSteps` → `@AppStorage("eq.discreteSteps.v1")` at the view (display-only); **headless engine-ready re-dispatch** via a new `AudioViewModel.onEngineReady` closure invoked right after `isEngineReady = true` (NOT a view `.onChange` — the AU is live even with the EQ tab closed); device precedence `guard old != nil` in EQTabView's device `.onChange` (last-setting-wins-at-launch).

### 12.6 Single-track activation changed (founder, 2026-07-07) — supersedes D3/OD-1 for single click

Double-click / Return / single-row context-"Play" on ONE track previously replaced the queue with the ENTIRE `songs` list from that row (D3 "the loaded array IS the play order"). Founder: wrong for clicking one song. **New behavior: insert the clicked track immediately after the current track and jump to play it now ("play next + jump"), preserving the rest of the queue** — `QueueInsert.playNextNow` (pure decision, VM-QI tests) + `AudioViewModel.playTrackNextNow`. Multi-select "Play" is unchanged (plays the selected subset). D3/OD-1's "list is the play order" still governs multi-select and any future "play all" affordance. **Shipped + gated** (architect + the-fool: GO, index math verified; refactoring-specialist: no regressions).

---

*Next: **swiftui-pro** implements the remaining chunks in order — (2) EQ remember-last-setting (vetted §12.5), (3) full-catalog columns + play-tracking backend (§12.1/§12.3, both pre-reviews GO), (4) EQ controls redesign, (5) columns UI (after the founder R1 make-run) — each behind the build/lint/test gate + a post-change review (refactoring-specialist + architect-reviewer) + qa-expert coverage → founder manual-test gate. (1) track-click play-next+jump is DONE.*
