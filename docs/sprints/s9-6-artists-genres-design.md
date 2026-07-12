# S9.6 — Artists / Genres (finish S9 browse)

> **Note (2026-07-11):** the **Years** tab in this design was **cut during founder review** — a track-year index added little; all Years DAO/gate/UI were removed and the doc renamed accordingly. This design shipped as Artists + Genres only.

**Status:** DESIGN (for expert panel + architect/the-fool gate)
**Author:** main + Explore map (2026-07-10)
**Depends on:** S8 spine, S9.1 reads, S9.2 FTS, S9.4 Albums, S9.5 Songs — all shipped.
**Founder decisions (locked):** detail = **flat song list**; whole-facet queue-add = **context-menu actions now, true drag-and-drop deferred to S10**.

---

## 1. Goal

Replace the three remaining dead `LibraryPlaceholderView` sidebar tabs — **Artists**, **Genres**, **Years** — with real **list → detail** browsing, plus per-facet queue actions. This closes S9; S10 is next; R1 after S10.

This is deliberately a **UI-wiring** slice: routing, DAO reads, and the reusable Albums/Songs building blocks already exist. We add three list roots, three flat song-list details, a small amount of DAO, and gate coverage.

---

## 2. Shape (decided)

- **Roots are lists** (Artists/Genres/Years have no artwork → text rows, native macOS list convention).
- **Details are flat song lists** — reuse the **`AlbumDetailView` template** (`backBar` + `header` + `List(selection:)` of `TrackRow`), **not** the full sortable `SongsTable` (that is the Songs tab; reusing it would collide with its singular `visibleSongs`/`sortOrder`/`searchQuery` state — explicitly avoided).
- **Queue-add** = `AlbumQueueActions`-style context menu / header button (**Play · Play Next · Add to Queue**) on each facet row and inside each detail, routing through the existing `AudioViewModel` queue verbs + `QueueToastDecision`.
- Navigation reuses the existing manual `model.path: [LibraryRoute]` stack (`.artist(Int64)`, `.genre(Int64)`, `.year(Int)` cases already defined). No `NavigationStack` (documented macOS chrome conflict).

### Out of scope (explicit)
- **Drag-and-drop to the queue** → **S10** (queue reorder/drag lands there; no drag infra exists today — net-new `Transferable`/`dropDestination`). Respects sprint boundaries.
- **A–Z jump rail** → deferred (no SwiftUI `Table`/`List` scroll-to-row API; rides the future `NSTableView` fallback).
- **Sortable columns / per-detail search inside a facet detail** — details are fixed-order read-only lists (the global Songs tab owns sort+search). Revisit only if the panel flags it.

---

## 3. Per-tab design

### 3.1 Artists
- **List** (`ArtistsListView`): rows of `ArtistFacet` → `name` + secondary `"N songs"` count. Sorted by name (existing `artists(sortedBy:)`). Row tap → `model.path.append(.artist(id))`. Row context menu = facet queue actions.
- **Detail** (`ArtistDetailView`): header (artist name + Play + `⋯` queue menu), then `List` of `TrackRow` from **`tracksDisplay(byArtist:)`** = **track-artist lens** (`artist_id`) — "songs by this artist," including compilation appearances. (Divergence from the album-artist lens is intentional and pinned by BR2. We are showing *songs*, so the track-artist lens is correct.)

### 3.2 Genres
- **List** (`GenresListView`): rows of `GenreFacet` → `name` + `"N songs"` (`GenreFacet.trackCount` already exists). Tap → `.genre(id)`. Context menu = queue actions.
- **Detail** (`GenreDetailView`): header (genre name + Play + menu) + `List` of `TrackRow` from **`tracksDisplay(inGenre:)`** (via `track_genres` JOIN, no fan-out — BR2b).

### 3.3 Years
- **List** (`YearsListView`): rows of year → `year` + `"N songs"` (needs a per-year count — see §4). Tap → `.year(y)`. Context menu = queue actions.
- **Detail** (`YearDetailView`): header (year + Play + menu) + `List` of `TrackRow` from **`tracksDisplay(inYear:)`** (**new** — see §4).

**Header names without extra reads:** the detail is always reached from its loaded list, so the name/label is read from the already-loaded `model.artists/genres` array (year is the `Int` itself). A single-facet DAO fallback is optional robustness, not required for the nav flow.

---

## 4. DAO + gate additions

| # | Change | Why | Gate |
|---|--------|-----|------|
| D1 | **`tracksDisplay(inYear:)`** new read (`WHERE t.year = ?`, `idx_tracks_year`) | Year detail song list + year queue-add | new `HotRead.tracksDisplayInYear` in BR5 EXPLAIN (index-driven, never `SCAN tracks`) + a BR2c-style set assertion |
| D2 | **`ArtistFacet` carries `trackCount`** — `artistSelectSQL` already computes `count(t.id)`; `mapArtistRow` currently **discards** it | Artists list "N songs" | extend the BR2/BR3 artist assertions to check the count |
| D3 | **Per-year song count** — extend `years()` → `[YearFacet{year, trackCount}]` (or a parallel count read) | Years list "N songs" (consistency with the other two tabs) | BR2c assertion on counts |
| D4 | *(optional)* **`genre(id:)`** single-facet read | robust genre-detail header if list not loaded | BR3-style equality (or skip — use loaded-array lookup) |

**Reused as-is (no change):** `artists(sortedBy:)`, `genres()`, `tracksDisplay(byArtist:)`, `tracksDisplay(inGenre:)`, `artist(id:)`, `LibraryTrackDisplay`, `AudioFile(track)`.

**NO schema migration** — these are read-only DAO additions over the existing v2 schema. (Repo rule: no migrations; the DB is a rebuildable cache.)

---

## 5. Model changes (`LibraryBrowseModel`)

Mirror the existing **Albums list pattern** (`albums` + `albumsState: LoadState` + `loadAlbums()` + epoch). Add:
- `artists: [ArtistFacet]`, `genres: [GenreFacet]`, `years: [YearFacet]` + a `LoadState` each + `loadArtists()/loadGenres()/loadYears()` (mirrors `loadAlbums`).
- Facet queue verbs — either reuse the generic `play/playNext/append([AudioFile])` verbs by having each **detail** resolve its own `[LibraryTrackDisplay]` → `[AudioFile]` (like `AlbumDetailView` does), OR add thin `playArtist(id:)/appendArtist(id:)`-style helpers on the model that read-then-enqueue for the **list-row** context menu (which has no loaded tracks). Prefer the generic verbs inside details; add minimal `enqueueFacet(kind:id:verb:)` for list-row menus.
- Reuse `showQueueToast` / `QueueToastDecision` verbatim.

**Constraints (repo footguns — must hold):**
- Any new `@Observable` property `didSet` must **not self-assign** (→ infinite-recursion crash; build/lint can't catch it — `reference-observable-didset-recursion`).
- Detail song lists use **`List`, not `Table`**. If a row shows artwork, `AlbumArtworkView` must receive `model:` as a **plain `let`** (never `@Environment` in a cell — `reference-swiftui-table-environment-crash`).

---

## 6. Implementation chunks (per-chunk loop: SME build → SME review → build-enforced gate → commit)

1. **DAO + gate** (dao/sql SME): D1–D4 + `VerifyLibraryStore` checks (BR2c/BR5 extensions). Gate: `swift run VerifyLibraryStore` stays green (add rows, keep 100%).
2. **Model** (swift-expert): list arrays + `LoadState`s + `load*()` + facet enqueue helpers. Gate: builds + Songs/Albums unaffected.
3. **Artists tab** (swiftui-pro): `ArtistsListView` + `ArtistDetailView` + wire `LibraryCategoryRoot.artists` / `LibraryRouteView.artist` + context menus + VoiceOver a11y (reuse `SongsAccessibility`-style builders / `TrackRow` a11y).
4. **Genres tab** (swiftui-pro): `GenresListView` + `GenreDetailView` + wire `.genres` / `.genre`.
5. **Years tab** (swiftui-pro): `YearsListView` + `YearDetailView` + wire `.years` / `.year`.
6. **QA + refactor pass** (qa-expert + refactoring-specialist): extract any pure decisions (facet-enqueue resolution, count formatting, empty-state selection) into `LibraryBrowseKit` unit tests; refactoring-specialist no-regression sweep across Songs/Albums.

Each chunk: **`make gate` + `make strict-gate` + `make run`** must pass before commit (per the team-delivery-loop). Replace all 7 `LibraryPlaceholderView` arms by the end (3 roots + 3 detail routes + the `.none` fallback stays or becomes a sensible empty state).

---

## 7. Risks & mitigations

- **Table/@Environment crash** — avoided by using `List` for details and passing `model:` explicitly to any artwork cell.
- **@Observable didSet recursion** — new props clamp locals, never self-assign.
- **Lens confusion (artist)** — locked to track-artist lens for song lists; documented, BR2-pinned.
- **Empty facets** (e.g. tracks with no genre/year) — lists show `LibraryEmptyStateView`; a null-year track simply doesn't appear under Years (documented; matches `years()` non-null semantics).
- **Gate 1 / playlist filter (SEQ-1)** — unrelated, stays open until S10.

---

## 8. Definition of done

- All three tabs browse list → flat song-list detail; play + Play Next + Add to Queue work from list rows and details with truthful toasts.
- Zero `LibraryPlaceholderView` left for artists/genres/years.
- `make gate` (incl. `VerifyLibraryStore` with new BR rows), `make strict-gate`, `make tsan` (unaffected), and `make run` all green.
- New pure decisions unit-tested in `LibraryBrowseKit`.
- `sprint-plan.md` / `roadmap.md` flipped: S9 ✅ done, S10 next.

---

## 9. Panel synthesis & revisions (v2, 2026-07-10)

Five-SME panel (swiftui-pro · swift-expert · ui-designer/native · qa-expert · sql-pro) — all **ship-with-changes**, no rework. Resolutions below are **binding on implementation**; open founder questions are in §9.6.

### 9.1 Blockers (resolved)
- **B-1 Cross-album track numbers (ui-designer #4).** The reused `AlbumDetailView.trackList` passes `leadingNumber: trackNo` — correct for one album, wrong for a facet list spanning albums (resets 1,2,3…). **Resolution:** facet details show **no leading track number**; each row's `secondary` line carries **album** (Artists) or **"Artist · Album"** (Genres/Years). Album-section grouping for the Artists tab is an optional enhancement — **founder Q9.6-a**.
- **B-2 Multi-await epoch re-guard (swift-expert #1).** `loadAlbums` suspends twice (`albums()` then `roots()`) and re-checks the epoch after **each** await. Every facet loader MUST re-`guard epoch == …` after **every** await before publishing, or a superseded load can flash a stale `.firstRun/.empty`. This is why the loader is extracted once (see 9.3).
- **B-3 Empty-facet enqueue must be SILENT (qa B1).** `showQueueToast(verb, added: 0)` renders "Already in Queue" — correct only when a *non-empty* facet was all-dups. A genuinely empty facet (0-song genre/year) must `guard !files.isEmpty` → return before the toast. Encoded in `FacetQueuePlan` (empty → `message: nil`).
- **B-4 `tracksDisplay(inYear:)` ORDER BY (qa D2 · sql #1).** Use `displayAlbumDiscTrackOrder` (`t.album_id, t.disc_no, t.track_no, t.id`) — deterministic, matches `byArtist`, index-friendly.
- **B-5 Years = track-year end-to-end (qa D3).** `years()`, `yearFacets()`, and `tracksDisplay(inYear:)` all filter `t.year`; assert `YearFacet.trackCount == tracksDisplay(inYear:).count` by construction. (Distinct lens from `albums(inYear:)` = `al.year`; add a one-line code comment.)

### 9.2 DAO + gate (final, per sql-pro + qa)
- **D1 `tracksDisplay(inYear:)`** = `displayTracksSQL(whereClause: "WHERE t.year = ?", order: displayAlbumDiscTrackOrder)`. Verified plan: `SEARCH t USING INDEX idx_tracks_year (year=?)` + temp-b-tree sort — **no new index**.
- **D2 `ArtistFacet.trackCount`** = un-discard `count(t.id)` (col 3) in `mapArtistRow` (only constructor). Track-artist lens, matches `tracksDisplay(byArtist:).count`. **Do NOT add `HAVING count>0` to `artistSelectSQL`** — `ChecksFacetSweep.swift:64` depends on `artists()` returning album-artist-only rows, and it would break `artist(id:)`. Hide 0-song artists in the **model/UI layer** instead (9.4).
- **D3 `yearFacets() -> [YearFacet]`** = `SELECT year, COUNT(*) FROM tracks WHERE year IS NOT NULL GROUP BY year ORDER BY year DESC` — `SEARCH … USING COVERING INDEX idx_tracks_year`. **Keep `years() -> [Int]` unchanged** (BR2c + `albums(inYear:)` depend on it); add `yearFacets()` in parallel. New `YearFacet { id=year; year; trackCount }: Sendable, Identifiable, Equatable`.
- **D4 `genre(id:)`** promoted **optional → SHOULD**: details load their own header facet in `.task` (`artist(id:)` exists; `genre(id:)` mirrors it; year is the `Int`) rather than reading a possibly-unloaded list array. Add BR3-style equality gate.
- **Gate rows:** BR6 `tracksDisplay(inYear:)` set + id-distinct (no fan-out) + album/disc/track order + track-year match; **BR6b BR5 EXPLAIN must assert a SEEK** — `SEARCH … USING INDEX idx_tracks_year`, not merely "uses an index" (qa D1: the composite ORDER BY must not degrade to a full `idx_tracks_album_order` scan); BR7 `ArtistFacet.trackCount == artistTrackCounts == tracksDisplay(byArtist:).count`; BR7b 0-song artist ("Various Artists") count 0 + empty detail; BR8 `YearFacet.trackCount == tracksDisplay(inYear:).count`, `sum == total − nullYear`; BR8b (ad-hoc store) null-year track absent from years/detail, present in `allTracksDisplay`; BR9 (ad-hoc) 0-song genre count 0 + empty. Fixtures: add `tracksByYear`, `yearTrackCounts`, `artistTrackCounts` to `FixtureExpectations`.

### 9.3 Model (final, per swift-expert)
- Loaders + facet-enqueue live in **`LibraryBrowseModel+Facets.swift`** (extension) — `@Observable` stored props stay in the primary decl, methods move out (mirrors `AudioViewModel+Queue.swift`); avoids the `type_body_length` 250-warning strict-gate failure.
- One generic `loadFacet<E>(into:state:epoch:read:)` writes the epoch/firstRun/empty logic **once** (B-2 lives in one place). Scope to the three plain facets only — **do not** fold in `songs` (different pipeline) or re-touch shipped `albums`.
- **No `didSet`** on the new facet arrays/states (they drive no derived view state; only `songs`/`matchedIDs` have them). Never self-assign (recursion footgun).
- Facet enqueue is **impure → stays on the model** (touches store + `audio`); ref modeled as **`enum FacetRef { case artist(Int64), genre(Int64), year(Int) }`** (year is `Int`, artist/genre `Int64`). Routes through the shared `audio.playNext/appendToQueue` (dedup + post-dedup count) + `showQueueToast`. Play Now = silent.
- **`reloadIfScanChanged()` extended** to reload artists/genres/years (else the roots go stale mid-scan; it is the only revision-bump refresh path).
- Details own their tracks + header facet in local `@State` + `.task(id: routeID)` (mirrors `AlbumDetailView`).

### 9.4 UI / details (final, per swiftui-pro + ui-designer)
- **Extract one `FacetTrackListView`** (title, subtitle, back-label, `tracks`, verbs, optional album-section grouping) used by all three details; **refactor `AlbumDetailView` onto it** where clean. Kills the 3× copy-paste drift class.
- **Roots** = `List(selection: $selectedID)` of plain text rows (name + trailing "N songs"; **no repeating leading glyph**), double-click / **Return** to activate → `path.append`, native **type-select** + arrow-nav for free. Artists/Genres alpha `NOCASE`; Years desc.
- **Hide 0-song facets** from the Artists **and** Genres lists (`trackCount > 0`) at the model/UI layer (DAO reachability preserved for detail reads + sweep).
- **Detail header:** title + subtitle **"N songs · total duration"** (reuse `humaneTotalDuration`), a prominent **Play** + a **Shuffle** button (infra exists: `shuffleEnabled`; native-expected on whole-facet pages), and the `⋯` (Play Next / Add to Queue) menu. **`⌘[`/Esc** back, **Return** plays the focused row.
- **Facet-specific empty states** (distinct from "No music found"): e.g. Artists → `Label("No Artists", systemImage: "music.mic")`, "Songs without artist tags won't appear here." Keep delegating first-run/scanning/failed states to `LibraryEmptyStateView`.

### 9.5 A11y (final)
- Detail rows expose **Play · Play Next · Add to Queue · Info as `.accessibilityAction(named:)`** (the AlbumDetailView template exposes them **only** in `.contextMenu` — VoiceOver-invisible; do not copy that gap).
- **Parameterize the back-bar label** ("Back to Artists/Genres/Years" — the template hardcodes "Back to Albums").
- Facet rows: a small **pure a11y builder** in `LibraryBrowseKit` ("The Beatles, 42 songs") + Play/Play Next/Add-to-Queue as named row actions (not context-menu-only).

### 9.5b Pure decisions → `LibraryBrowseKit` (unit-tested, per qa)
- `FacetCountLabel.songs(count:)` — "0 songs / 1 song / 1,234 songs" (`.formatted(.number)` grouping to match `songsCountLine`); refactor `AlbumDetailView.subtitleLine` onto it.
- `FacetQueuePlan.plan(facetURLs:queuedURLs:verb:isNowPlayingTab:) -> (submitCount, message?)` — mirrors VM-Q-13..15; **empty → nil (silent)**; all-dup → "Already in Queue"; playNow/nowPlayingTab → nil.
- `FacetDetailState.state(trackCount:) -> .empty | .list`.

### 9.6 Open founder questions (for the "ask questions" step)
- **Q-a — Artists detail layout:** uniformly **flat** (album as row subtitle) vs **grouped by album with section headers** (Apple-Music artist page; still a flat song list, not a grid).
- **Q-b — Shuffle button** on facet detail headers: include now (infra exists) or defer.
- **Q-c — Hide 0-song facets** (e.g. "Various Artists" with 0 track-appearances) from the Artists/Genres lists: yes (native) or show them.

### 9.7 Deferred / follow-up (not this slice)
Article-stripping "The/A" sort (needs metadata write-path `sort_name`); multi-select context-menu targeting; per-detail search. Drag-to-queue + A–Z rail remain **S10**/deferred as before.

---

## 10. Final gate — architect + the-fool (2026-07-10): GO-WITH-CONDITIONS

Architecture verdict **GO-WITH-CONDITIONS**; the-fool pre-mortem converged. The following override earlier §9 wording where they conflict and are **binding**:

- **R1 — No generic `loadFacet<E>`.** Write **three explicit loaders** (`loadArtists/loadGenres/loadYears`), each a copy of the proven `loadAlbums` shape, with the epoch re-`guard` after **every** await (incl. the second `roots()` await for `.firstRun` vs `.empty`). The generic hid exactly that invariant and the headless gate can't catch a broken newest-wins race. (Supersedes swift-expert's optional generic.)
- **R2 — Do NOT refactor the shipped `AlbumDetailView`.** Build `FacetTrackListView` for the **three new details only**. Folding the shipped, visual-only-gated album view onto the shared view (album-only `leadingNumber`/artwork-header/year-subtitle branches) is out of scope → a separate future cleanup.
- **R3 — Drop `FacetQueuePlan`.** Do not re-implement dedup. Facet enqueue calls the shipped `audio.playNext/appendToQueue` (which own dedup + return the post-dedup count), guards `!files.isEmpty` before the toast (empty → silent, exactly the album path), and feeds the real return into the existing tested `QueueToastDecision`. Keep only `FacetCountLabel` + `FacetDetailState` as new Kit pure types.
- **R4 — Chunk order fix.** Kit pure-decisions (`FacetCountLabel`, `FacetDetailState`) are created in **chunk 1** (with the DAO), consumed thereafter; `FacetTrackListView` is created in **chunk 3** (first detail) and reused by 4/5. Chunk 6 = no-regression sweep only (no retro-extraction, no AlbumDetailView fold-in).
- **R5 — "Hide 0-song facets" is a founder question, not decided.** The DAO stays reachable (BR7b/BR9 test count + reachability regardless); IF hidden, it's a **pure tested predicate** (`FacetListVisibility.isVisible(trackCount:)`) in the UI layer, and any reachable 0-song detail still renders the facet empty-state. Resolve via Q-b below.
- **R6 — Respect the founder's shape decisions.** Album-section grouping (Artists) and the Shuffle button are panel *additions* that lean back toward the album-oriented / new-play-mode surfaces the founder did **not** pick. They go to the founder (Q-a, Q-c), not silently in. `FacetTrackListView` takes an optional grouping flag so either answer needs no re-architecture.

**Final founder questions (the "ask" step):** Q-a flat vs album-grouped Artists detail; Q-b hide 0-song facets; Q-c Shuffle button now vs defer. Everything else is settled. On answers → implement chunks 1→6, each `make gate` + `make strict-gate` + `make run` before commit.

### 10.1 Founder answers (2026-07-10) — locked
- **Q-a → Artists detail is GROUPED BY ALBUM** (per-album `Section` headers; still one song list). `FacetTrackListView` gets a grouping mode: **Artists = grouped**, **Genres/Years = flat** (album on the row's secondary line, no leading track number).
- **Q-b → HIDE 0-song facets** from the Artists + Genres lists via a pure `FacetListVisibility.isVisible(trackCount:)` predicate (DAO reachability preserved; any reachable empty detail renders the facet empty-state).
- **Q-c → INCLUDE Shuffle** — `[▶ Play] [🔀 Shuffle]` pair on all three detail headers (reuse `shuffleEnabled`; shuffle = load tracks, enable shuffle, play from a random index).
