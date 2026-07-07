# S9.5 — Songs view · incremental search · Songs-default · queue toast (test plan)

Status: **test plan** (qa-expert, 2026-07-07). Companion to `s9-5-songs-search-design.md` (§5 F1–F8 + Given/When/Then, §7 non-functional, §8 slice plan) and `s9-5-songs-search-plan.md`. Grounded 100% in this repo's real tooling — there is **no UI-automation framework** (no XCUITest/ViewInspector) and **no coverage-%/automation-% target**; proposing either would be theater. The three real gates are: **`make strict-gate`**, the **C++ golden master `0xE7267654BA01D315`** (a pure regression guard — S9.5 touches no DSP), and the **founder's manual `make run`**. This plan makes the manual gate a precise per-AC checklist and maximises what is genuinely automatable (DAO logic via `VerifyLibraryStore`, VM/decision logic via `swift test`).

---

## 1. QA strategy + risk-based prioritization

### 1.1 What is automatable here, and what is not

| Concern | Covered by | Automatable? |
|---|---|---|
| DAO sort order / tiebreak / NULLs; EXPLAIN plan; projection/mapping; search cap | `VerifyLibraryStore` (`swift run VerifyLibraryStore`, inside `make gate`) | **Yes — deterministic** |
| Queue-verb added-count, dedup, toast decision, search gate (≥2-char / newest-wins), play-from-row index, default landing | `swift test` (native swift-testing) — **only if the pure decision is extracted to a library target** (see §2.2) | **Yes — for the extracted decisions** |
| SwiftUI `Table` render, scroll feel, selection latency, per-row artwork churn, a11y-by-feel, light/dark, Dynamic Type, toast timing/motion | founder `make run` + Instruments | **No — manual** |
| DAO sort/search wall-time at 20k, EXPLAIN-at-real-scale | proposed env-gated `LIBRARY_PERF=1` block (§3) | **Partial — EXPLAIN deterministic, timing advisory** |

The `AdaptiveSound` app is an **executable target** and cannot be `@testable import`-ed (see `Tests/AudioViewModelTests/QueueOpsTests.swift` header). The established idiom is therefore: push the *pure decision* into a **library target** (`PlaybackQueueKit`, cf. `QueueAdvance.appendArmIndex`) and unit-test it directly, or mirror the VM's array behaviour in a `MockAdvanceController`. S9.5's testable logic MUST follow this idiom or it stays manual-only.

### 1.2 Risk-based priority (highest first)

| # | Risk | Why it matters | Primary test | Layer |
|---|---|---|---|---|
| **R1** | **SwiftUI `Table` selection lag at ~20k** | The whole OD-1 architecture (full-load + `NSTableView` escape hatch) hinges on it. This is **the slice-2 `make run` go/no-go**. | Instruments (View-Properties / Hangs / Time Profiler) on the founder's real ~20k library; **hard trigger: click-select + arrow-move ≥ 100 ms ⇒ drop the hot list to `NSTableView`** (pre-approved, not "feels slow"). | **Manual (Instruments)** |
| **R3** | **Sort on JOINed artist/album *names* hits a filesort / `SCAN`** | Trips the BR5 no-`SCAN TABLE tracks` tripwire; silent scale cliff. | `SS2` — asserts no sort SCANs `tracks`, `date_added`/`year` stay index-ordered, and *records* the accepted bounded filesorts (name/title/format/duration). Already landed; re-run + PERF-4 at 20k. | **`VerifyLibraryStore`** |
| **R2** | **Per-row artwork decode churn on fling** | Kills 60fps; art column is the first thing to drop. | `make run` scroll test (fling 20k, watch Instruments Hangs / dropped frames); art projection/keying gated by `SS3` + `BR1`. | **Manual (scroll) + DAO** |
| **R5** | **Toast count vs URL-dedup mismatch** | "Added 3" when only 1 was actually added (2 dups) = lying UI. | `VM-Q` count cases (§2.2) once D2 lands the `@discardableResult -> Int` verbs; toast-message decision unit test. | **`swift test`** |
| **R4** | **`search(limit:)` truncation** | Filter feels incomplete / "N results" lies. | `SS4` search-cap boundary (seed > cap, assert `count == 400` default + explicit `limit:` honoured). | **`VerifyLibraryStore`** |

---

## 2. Automated coverage — F1–F8 acceptance criteria → concrete tests

Legend for **Status**: **LANDED** = check already exists in the tree (re-run, don't rebuild); **ADD** = new check this sprint; **MANUAL** = not automatable here, lives in §4.

### 2.1 `VerifyLibraryStore` (DAO — headless, deterministic; `make gate`)

Temp DBs live under `test-data/` (never `/tmp`), UUID-unique, cleaned on success (kept on failure). New cases append to `songsSortCheckCases()` / `searchCheckCases()` in `Sources/VerifyLibraryStore/main.swift` and follow the `printPass`/`printFail` idiom.

| Check | Asserts | Ground truth | Status |
|---|---|---|---|
| **SS1** `ss1-sort-order-tiebreak` | Every new `TrackSort` returns the derived primary order + deterministic `id` final tiebreak on collisions; documented NULLs-ordering holds; asc/desc are exact reverses where the spec says. | `ChecksSongsSort.swift`, `trackOrder`/`singleKeyTrackOrder` | **LANDED** |
| **SS2** `ss2-sort-explain-plan` | Every new sort: **no `SCAN TABLE tracks`** (BR5 tripwire); `date_added`/`year` index-ordered (no temp-b-tree); the rest recorded as accepted bounded filesorts (R3). | `ChecksSongsSort.swift` | **LANDED** |
| **SS3** `ss3-display-projection` *(new)* | `allTracksDisplay` **projects + maps** the re-added fields (D1/D5): seed a known-fields track + a NULL-fields track; assert exact round-trip AND nils map to `nil`, `artistName` COALESCEs to `""`, `title` falls back to filename. Guards positional decode indices 0–16. | `+BrowseReads.mapDisplayRow` | **ADD** |
| **SS4** `ss4-search-cap` *(new)* | D4/OD-3: seed > 400 matching tracks; assert `search(q).tracks.count == 400` + `search(q, limit:n).count == n`; empty/all-punctuation → `.empty`. | `+Search.search`, `fts-query-safety` | **ADD** |
| **BR4** `br4-pagination` | `allTracksDisplay(sortedBy:)` `limit == nil` == unbounded full-load (OD-1 D6 path); adjacent pages tile no dup/gap. | `ChecksBrowseReads.swift` | **LANDED** |
| **BR5** `br5-explain-plan` | Hot facet reads never `SCAN TABLE tracks` (portable tripwire, no `ANALYZE`). | `ChecksBrowseReads.swift` | **LANDED** |
| FTS `fts-query-*` | Flat bm25 over title/artist/album/genre; injection/diacritics-safe; `field:value` → plain tokens; prefix + implicit-AND; bm25 ranking; deduped shape. | `ChecksSearch*.swift` | **LANDED** |

### 2.2 `swift test` (VM / decision logic — native swift-testing)

**Prerequisite:** requires D2 (`@discardableResult -> Int` verbs) and the pure S9.5 decisions extracted to a library target (cf. `QueueAdvance`). Recommend a small `QueueToastDecision` + `SearchGate` in `PlaybackQueueKit` (or a peer library target) so the executable's non-importability doesn't block coverage. Mirror the count in `MockAdvanceController`.

| Check | Asserts | Idiom | Status |
|---|---|---|---|
| **VM-Q-01…12** | `playNow`/`playNext`/`appendToQueue` array + on-deck + dedup semantics. | `QueueOpsTests` via `MockAdvanceController` | **LANDED** |
| **VM-Q-13** *(new)* | Added-count (D2/OD-2): verbs return the **post-dedup** count; 2 new + 1 dup on a 3-track queue ⇒ `2`. | mock + returned `Int` | **ADD** |
| **VM-Q-14** *(new)* | All-dup add ⇒ `0` (→ "Already in Queue"); empty input ⇒ `0`. | same | **ADD** |
| **VM-Q-15** *(new)* | Multi-select add = **one** coalesced result carrying the true added count. | `QueueToastDecision` | **ADD** |
| **TOAST-1** *(new)* | `.playNow` ⇒ **nil (silent)**; `.addToQueue`/`.playNext` ⇒ message; copy matches count buckets. | pure `QueueToastDecision` | **ADD** |
| **TOAST-2** *(new)* | Visibility gate: suppressed when `selectedTab == .nowPlaying`. | pure decision | **ADD** |
| **TOAST-3** *(new)* | Coalesce/replace: a new add within the window replaces text + resets timer (state fn); the ~2s wall timer + motion are **MANUAL**. | pure state fn | **ADD (partial)** |
| **SEARCH-1** *(new)* | `SearchGate`: `< 2` chars ⇒ no run (restore full list); `≥ 2` ⇒ run. | pure `SearchGate` | **ADD** |
| **SEARCH-2** *(new)* | Newest-wins epoch guard: stale-epoch result dropped; only newest publishes. Debounce *timing* is MANUAL. | pure epoch compare | **ADD (partial)** |
| **ROW-PLAY-1** *(new)* | Play-from-row (D3): given the full ordered set + tapped row id, `indexInFullOrder` is correct (dup-title tiebreak, filtered subset). | pure index fn | **ADD** |
| **DEFAULT-1** *(new)* | Songs-default (F3): landing category constant is `.songs` (if it lives as a named importable constant; else MANUAL). | constant assert | **ADD-or-MANUAL** |

### 2.3 Manual-only ACs (rendering / interaction / a11y — §4 checklist)

All 8 columns rendering; header sort triangle + toggle; system selection highlight; double-click/Return actually playing; ⌘/⇧ multi-select gestures; context-menu presence + Info popover; incremental filter *feel* + zero-results view + clear; A–Z rail scroll; type-to-select; toast visibility/motion/timing/tappability; load/empty/first-run/failed/scanning states; VoiceOver one-element-per-row + custom actions; Dynamic Type clamp; reduce-motion; light/dark tokens; 60fps scroll; selection <100ms.

### 2.4 Full F1–F8 traceability

| F | AC theme | Test(s) | Layer / Status |
|---|---|---|---|
| **F1** | composite default sort; header sort each column asc/desc | SS1 | DAO **LANDED** |
| | 8 columns render; indicator; selection; context menu; states | §4 | **MANUAL** |
| | double-click/Return plays full ordered list from row | ROW-PLAY-1 + §4 | `swift test` **ADD** + MANUAL |
| | reload-once on `libraryRevision` preserving sort | epoch guard (VM) + §4 | **ADD** + MANUAL |
| **F2** | flat bm25; tokens; prefix; AND; diacritics | `fts-query-*` + SS4 | DAO **LANDED/ADD** |
| | ≥2-char gate; newest-wins epoch | SEARCH-1, SEARCH-2 | `swift test` **ADD** |
| | ~120ms debounce; client re-sort; clear restores | §4 (feel) | **MANUAL** |
| **F3** | `selectedCategory` default `.songs` | DEFAULT-1 | **ADD**-or-MANUAL |
| **F4** | silent on Play Now; PlayNext/AddQueue only | TOAST-1 | `swift test` **ADD** |
| | only when `selectedTab != .nowPlaying` | TOAST-2 | `swift test` **ADD** |
| | count = actually-added | VM-Q-13/14/15 | `swift test` **ADD** |
| | ~2s; coalesce+reset; reduce-motion; VO announce | TOAST-3 + §4 | **ADD (partial) + MANUAL** |
| **F5** | `date_added` sortable, desc = recent | SS1 + SS2 | DAO **LANDED** |
| | projected + mapped + rendered human date | SS3 + §4 | DAO **ADD** + MANUAL |
| **F6** | live "N songs"/"N results" | `trackCount()` LANDED; count-from-array (§4) | **LANDED** + MANUAL |
| | A–Z jump alpha-only, hidden when filtered; empty→next | §4 | **MANUAL** |
| **F7** | keyed by `artworkKey` → cache path; batched warm | SS3 + BR1 | DAO **ADD/LANDED** |
| | placeholder, no shift, cache-peek no-flash, cancel-on-scroll | §4 (R2) | **MANUAL** |
| **F8** *(DROPPED — OD-1 full-load)* | no keyset; full set in memory; `trackCount` from array | BR4 (`limit:nil`) | DAO **LANDED** — no new test |

**Edge cases** (design §5) → SS1 (dupes/tiebreak, NULL ordering), SS3 (empty cells / nil mapping), `fts-query-safety` (all-punctuation → no-results not error), SEARCH-1 (drop-below-2 cancels), ROW-PLAY-1 (dup-title play-by-index, filtered subset); very-long-title truncation, multi-select spanning the loaded window, and selection-during-background-reload are **MANUAL** (§4).

---

## 3. Performance test plan (§7 non-functional targets, 20k rows)

### 3.1 Split by measurability (the honest line)

| §7 target | Threshold | Method | Layer |
|---|---|---|---|
| Keystroke → filtered ranked list | **< ~250 ms** (≤120ms debounce + <150ms query/render) | `make run` on 20k + Instruments Time Profiler on the search commit path | **Manual** (DAO portion PERF-3) |
| Scroll flinging 20k | **60fps**, no hitch when artwork warms | `make run` + Instruments (Animation Hitches / FPS); art memory bounded by `NSCache` | **Manual (R2)** |
| Click-select + arrow-move | **< 100 ms** (hard gate) | Instruments View-Properties / Hangs. **≥100ms ⇒ fire the `NSTableView` escape hatch (OD-1).** | **Manual (R1)** |
| Re-sort any column (DAO) | **< ~300 ms** | PERF-3 (advisory) + `make run` feel | **PERF (advisory) + Manual** |
| EXPLAIN: no `SCAN TABLE tracks` at real scale | deterministic | PERF-4 (SS2 re-run at 20k) | **PERF (deterministic)** |
| No main-thread hang | **> 100 ms** anywhere during load/sort/search | Instruments Hangs during `make run` | **Manual** |
| Default-landing re-entry | cached rows same-frame, no empty-flash | `make run` | **Manual** |
| Toast | within one frame; ~2s; never on Now Playing; N adds → one toast | §4 + TOAST-1/2/3 | **swift test + Manual** |

### 3.2 The perf harness — confirmation + minimal extension

**Confirmed:** there is **no `LIBRARY_PERF` harness in code** (only prose in the older `s9-*` docs). The seeding building blocks **do** exist and can reach 20k: `store.upsert([ScannedFile], folderID:, generation:)` (batched) + `store.applyMetadata(_:forTrack:)`.

**Proposed minimal extension** — an **env-gated** block in `VerifyLibraryStore`, appended only when `LIBRARY_PERF == "1"`, and **NOT part of `make gate` / `make strict-gate`** (wall-clock assertions are flaky on shared CI):

- **PERF-1 — bulk seed ~20k** via batched `upsert`; decorate a representative slice with `applyMetadata` (varied + NULLs + collisions). Assert count; report seed wall-time. Reuse `test-data/` temp-DB + cleanup.
- **PERF-2 — `trackCount()` + unbounded `allTracksDisplay` full-load** returns 20k without error (OD-1 D6 path); report wall-time.
- **PERF-3 — DAO sort/search timing (ADVISORY):** time each `TrackSort` + `search(token)`; soft-ceiling sort <~300ms, search <~150ms as a WARNING (not FAIL) — authoritative verdict is the Instruments `make run`.
- **PERF-4 — EXPLAIN at real scale (DETERMINISTIC):** re-run SS2 on the 20k DB; no sort `SCAN`s `tracks`; `date_added`/`year` index-ordered. Store runs no `ANALYZE`/`sqlite_stat1`, so the plan is row-count-independent — hard PASS/FAIL at scale; the portable R3 tripwire at true magnitude.

**Seeding cost:** keep PERF env-gated + founder-run; decorate a representative subset, not all 20k, unless a case needs full metadata.

---

## 4. Manual test checklist — the founder's `make run` gate

Run `make run` on the **real ~20k library**. Tick each. This is the ship criterion for every MANUAL AC above.

**Songs table (F1)**
- [ ] Landing opens on **Songs**; rows same-frame on re-entry (no empty-flash).
- [ ] All 8 columns present + correct: Artwork · Title · Artist · Album · Time · Date Added · Format · Year.
- [ ] Default order grouped-by-artist (Artist→Album→disc→track); nil artist/album render as **blank cells**.
- [ ] Format cell reads e.g. "FLAC · 24/96"; bare "AAC" when rate/depth null; plain text (no badge).
- [ ] Date Added reads "MMM d, yyyy"; nil/0 → blank. Time right-aligned monospaced.
- [ ] Each sortable header: triangle on the active column only; first-click direction per spec (Date Added → **desc**); second click toggles.
- [ ] Sort state survives leaving + returning to the Library tab.
- [ ] **Double-click** and **Return** play from that row; playback **continues past** the loaded window.
- [ ] Single-click selects; ⌘/⇧ multi-select; **system highlight** (not teal), dims on blur, correct light + dark.
- [ ] Context menu: Play · Play Next · Add to Queue · — · Info. Multi-select: Play plays the subset; Play Next/Add to Queue on the whole selection in sort order; Info targets the primary row.
- [ ] Info popover renders format badge + async rate/depth/channels/size + copyable path.

**Filter field / search (F2)**
- [ ] `⌘F` focuses; typing filters as-you-type; 1 char does **not** search; ≥2 does.
- [ ] Rapid typing shows only the last query's results (no stale flicker); feels < ~250ms.
- [ ] Filtered view → relevance order, sort triangle clears, A–Z rail hides, count → "N results".
- [ ] Zero-results shows "No Results" (header + "0 results" visible), never an error — try `!!!`.
- [ ] Clear (`xmark`/Escape) restores full list + prior sort + rail.

**Queue toast (F4)**
- [ ] Add to Queue / Play Next from Library shows a bottom-center capsule; **Play Now shows nothing**.
- [ ] No toast while on the **Now Playing** tab.
- [ ] Count truthful: add 3 where 1 already queued ⇒ "Added 2 to Queue"; all-dup ⇒ "Already in Queue".
- [ ] Multi-select add ⇒ **one** toast with the true count.
- [ ] Rapid adds replace text + reset the ~2s timer (never stack).
- [ ] Tapping the capsule jumps to Now Playing.
- [ ] Reduce Motion on ⇒ fade (no slide); VoiceOver announces the message.

**Count / A–Z / type-select (F6)**
- [ ] Unfiltered header "N songs · total duration" (grouped thousands, singular "1 song"); filtered drops duration.
- [ ] A–Z rail only on alphabetical sorts; hidden when filtered or on Time/Date/Format/Year; tap jumps; empty letter → next non-empty.
- [ ] Type-to-select works (Table has key focus).

**Artwork (F7) / states / a11y / appearance**
- [ ] Thumbnails load without layout shift; placeholder first; no flash on cached rows; **fling 20k smooth (no hitch)** (R2 — art column drops first if it degrades).
- [ ] Loading → spinner; first-run/empty/scanning-empty/failed → shared empty-state; scanning **with** rows shows the table + live-fills preserving sort/selection.
- [ ] VoiceOver: one element/row (composed label), default action plays, Play Next/Add to Queue/Info custom actions; headers announce name + direction.
- [ ] Dynamic Type scales header/count/search; table clamps (fixed 36pt rows); truncated cells expose full text via tooltip/VO.
- [ ] Light + dark both correct (all `DesignSystem` tokens).

**Perf go/no-go (§3.1 — the hard ones)**
- [ ] **Selection latency < 100 ms** (click-select + arrow) via Instruments. **If ≥ 100 ms → invoke the `NSTableView` escape hatch (OD-1).**
- [ ] Scroll ~60fps flinging 20k (Animation Hitches).
- [ ] No main-thread hang > 100 ms during load/sort/search (Hangs).

---

## 5. Regression + exit criteria (Definition of Done)

**Automated gates — all green:**
- [ ] **`make strict-gate`** end-to-end: swiftformat/swiftlint --strict, clang-format, semgrep, suppression-policy, clang-tidy, **periphery --strict**, `swift build`, `swift test` (incl. new VM-Q/TOAST/SEARCH/ROW-PLAY/DEFAULT), `make gate`, null-test coverage guard, `-O2 -Werror`, ASan/UBSan/TSan, `sanitize-library-store`, `leak-check`.
- [ ] **Periphery sequencing:** the re-added `LibraryTrackDisplay` fields + new `TrackSort` cases + `explainAllTracksDisplayPlan` must be **consumed** (Songs UI + SS1/SS2/SS3/SS4) so periphery --strict is green with **no lingering `// periphery:ignore`**; any temp ignore on a backend-first slice carries owner/reason/expiry and is **removed** by the consuming UI slice.
- [ ] **`swift run VerifyLibraryStore`** passes incl. **SS1, SS2 (landed)** + **SS3 (projection/mapping)** + **SS4 (search cap)**.
- [ ] **C++ golden master `0xE7267654BA01D315` byte-identical** — S9.5 touches no DSP.
- [ ] `swift build -c debug` clean under Swift 6 data-race checking.

**Performance (env-gated, founder-run — not in the merge gate):**
- [ ] `LIBRARY_PERF=1 swift run VerifyLibraryStore` green: **PERF-4 EXPLAIN-at-20k deterministic pass**; PERF-1/2/3 report timings with no ceiling WARNING (advisory).

**Founder manual gate (ship criterion):**
- [ ] Every §4 box ticked on the real ~20k library.
- [ ] **R1 verdict recorded:** SwiftUI `Table` selection < 100 ms, **or** the `NSTableView` fallback taken + re-verified < 100 ms.
- [ ] Founder sign-off on search feel, scroll feel, toast behaviour, a11y-by-eye, light/dark.

**Go / No-Go**
- **GO** iff: `make strict-gate` green (periphery clean, no lingering ignores) · golden master unchanged · `VerifyLibraryStore` green incl. SS3 + SS4 · PERF-4 deterministic pass at 20k · every §4 box ticked · R1 selection-latency gate met · founder sign-off.
- **NO-GO** if any strict-gate step fails, the golden master drifts, a periphery `ignore` remains on a re-added field, PERF-4 shows a `SCAN TABLE tracks`, or selection latency ≥ 100 ms with the fallback **not** taken.
