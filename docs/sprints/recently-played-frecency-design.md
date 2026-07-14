# Recently Played (frecency) — design

**Status:** Vetted (architect-reviewer + swiftui-pro design brainstorm + founder brainstorm 2026-07-14). Awaiting architect/the-fool gate → implementation. Traces to backlog **US-PLAY-10**.

Reworks the S10.2 "History" tab (a session, in-memory, append-only log — every play-start added a row, so a click-to-replay duplicated) into an **all-time, per-track, play-count, frecency-ordered** list renamed **"Recently Played."** The dedupe + persistence are a data-source switch, not new plumbing — the durable `play_count`/`last_played` columns already exist and are written today.

---

## 0. Locked decisions (founder brainstorm 2026-07-14)

| # | Decision | Choice |
|---|---|---|
| D1 | Scope | **All-time / persistent** (survives quit), not session-only. |
| D2 | What counts as a play | **≥60% of the track heard**, **capped at ~4 min** (60% OR 4 min, whichever first — Last.fm-style), **once per play-through**. Replaces today's natural-completion rule. |
| D3 | "Heard" detection | **Cumulative heard-time** (only real playback accrues; a seek/scrub is rejected — scrubbing to 90% does NOT count). |
| D4 | Sort | **Frecency** — recency-weighted frequency; recency dominates, count breaks near-ties. |
| D5 | Half-life `H` | **7 days** (a play last week = half of today's; two weeks = a quarter). |
| D6 | Tab name | **"Recently Played"** (label only; internal `QueuePanelMode.history` case unchanged). |
| D7 | Frecency data model | **Decayed-score accumulator column** `frecency_score REAL` (schema v4) — NOT a naive `count×decay`, NOT a per-play events table. Justification in §2. |
| D8 | Pre-R1 count wipe | **Accepted.** `eraseDatabaseOnSchemaChange` means the v3→v4 bump resets everyone's current counts **once**, and counts persist only until the next schema bump pre-R1. Matches the no-migration posture ([[feedback-delete-rebuild-dev-db]]); "preserve play-state columns across schema change" becomes an explicit R1 durability requirement (logged, not built now). |

Defaults applied per the experts (no founder blocker): registered GRDB decay function; dedicated `frecencyTracksDisplay` read; top-**200** cap + pagination; refresh on tab-appear + a `playCountRevision` bump; a dedicated `RecentlyPlayedRow`.

---

## 1. The ≥60% counting rule (app / VM)

**Where:** `AudioViewModel+SpectrumTimer.tickTransport()` — the always-on 20 Hz transport tick that already updates `playbackPosition` and holds `duration`.

**Pure, testable core.** Extract the decision into a pure type (à la `PlaybackQueueKit`) — `PlayThroughTracker` — so it is unit-testable without an engine:
- Inputs per tick: `duration`, current `position`, `maxPlausibleTickDelta`, `thresholdFraction = 0.60`, `capSeconds ≈ 240`.
- State: `heardSeconds`, `lastTickPosition`, `didCount`.
- Per tick (only while `isPlaying`, `duration > 0`, `!didCount`): `delta = position − lastTickPosition`; accrue **only** a plausible playback delta (`0 < delta ≤ maxPlausibleTickDelta`, ~1.0 s) → rejects seek-back (negative) and seek/scroll-forward (large jump); `lastTickPosition = position`.
- Count once when `heardSeconds ≥ min(thresholdFraction · duration, capSeconds)` → `didCount = true`, fire `countCurrentPlay()`.

**Natural-end fallback.** The four existing natural-completion sites (`+SpectrumTimer` :106/:119, `+AutoAdvance` :27/:39) fold into `countCurrentPlay()`, now idempotent via `didCount`. This covers the very-short-track / `duration==0`-race case (a 1–2 s clip can end before the async `AVAudioFile` duration resolves) and any gapless-seam sampling gap. At each site `selectedTrackIndex` still points at the just-finished track.

**Reset** (`resetPlayTracking()`) fires at exactly the two "new play-through" moments — today's `recordPlayStart` sites, replaced 1:1: `startPlayback(resumeFrom:)` guarded by `resumeFrom == nil` (so pause→resume continues the play-through, doesn't reset) and `handleTrackTransition()` (gapless seam / repeat-one → a new countable play-through).

**Edge coverage:** scrub-to-preview → seek delta rejected (no count); very long track → 4-min cap; very short → natural-end fallback; pause/resume → no accrual while paused, no reset on resume; skip before 60% → never counted; re-cross after seek-back → `didCount` guards once. RT-safe: a subtract/compare/bool at 20 Hz on the main thread; the store write stays the existing detached fire-and-forget.

---

## 2. Frecency data model (store) — schema v4

**Decision (D7): one `frecency_score REAL NOT NULL DEFAULT 0` column on `tracks`.** On each counted play, update a decayed accumulator; at read time finish the decay to "now":

```
write:  score_new = score_old · 2^(−(now − last_played)/H) + 1        (first play: score = 1)
read:   frecency(t) = score · 2^(−(t − last_played)/H)
```

This is **mathematically identical** to summing per-play exponential decays (the events-table result) — the accumulator carries the sum decayed to the last-play instant; the read finishes it — at **O(1) storage / write / read**, no unbounded table, no pruning.

- **Rejected — naive `play_count × decay(last_played)`:** multiplies *lifetime* count by a single recency factor, so 1000-plays-one-today scores ~1000 vs 6-plays-all-today ~6 — **violates D4** (recency must outweigh count). It also can't tell "6× today" from "6× over a month" (same count + last_played).
- **Rejected (for now) — per-play `plays(track_id, played_at)` table:** true frecency + future windowed analytics, but unbounded growth + aggregate reads. Revisit only if per-play history / "plays in last N days" gets scoped (would be the trigger to switch). See Deferred.

**`play_count` + `last_played` stay exactly as-is** (Songs "Play Count" column + `.playCountDesc`/`.lastPlayed*` sorts keep working). Clean split: aggregate for counting/display, `frecency_score` for ordering. One counted play updates all three in one atomic `UPDATE`.

**Decay function.** Register a GRDB deterministic scalar `as_frecency_decay(score, last_played, now, H)` via a `prepareDatabase` hook — used by **both** the write's decay term and the read's `ORDER BY`, so the math lives in one place and doesn't depend on SQLite's optional `SQLITE_ENABLE_MATH_FUNCTIONS`.

**Write DAO.** Extend the id-keyed `incrementPlayCount(id:playedAt:)` (keep the URL-keyed fallback) to the atomic three-column update (`frecency_score` via the `CASE`-guarded decay term, `play_count + 1`, `last_played = now`). Increments no longer commute (decay is order-dependent), but the single serialized `DatabaseWriter` + single-writer-per-column make this safe.

---

## 3. The read / sort

Dedicated read (not a `TrackSort.frecency` — the ordering needs runtime `now`/`H` binds the static `trackOrder` machinery can't carry):

```swift
func frecencyTracksDisplay(now: Int64, limit: Int? = 200, offset: Int = 0) async throws -> [LibraryTrackDisplay]
```
Reuses `displayTracksSQL` + `displayTrackColumns` + `displayArtistAlbumJoins` (→ `LibraryTrackDisplay` → the `AudioFile(_:)` adapter, zero new decoding). `WHERE t.play_count > 0` (excludes never-played), `ORDER BY as_frecency_decay(t.frecency_score, t.last_played, ?, ?) DESC, t.id DESC`, `LIMIT ? OFFSET ?` (reuses the clamped pagination args). Computed in SQL so only the top-N cross the actor boundary.

**Scan posture:** frecency is a computed expression over a time-varying `now` → an inherent **filesort** over the `play_count > 0` subset. This is an **accepted, reviewed filesort** (the R3 class already documented in `ChecksSongsSort`), deliberately NOT held to the BR5 "never SCAN TABLE tracks" rule; the gate records it as an exception, bounded by the WHERE + LIMIT.

---

## 4. UX — "Recently Played" (swiftui-pro)

- **Naming (D6):** picker label + header title → "Recently Played" (verify segmented-control width in `make run`; fall back to "Played" in the picker if the second segment truncates, keeping "Recently Played" as the header). Internal enum case stays `.history`.
- **Dedicated `RecentlyPlayedRow`** bound to `LibraryTrackDisplay` (NOT an extension of the `AudioFile`-based `PlaylistItemRow` — wrong input type, divergent anatomy, different a11y contract). Mirrors `TrackRow`'s structure + a11y discipline; reuses `DesignSystem` tokens + `FormatBadgeView`. ~40 lines.
- **Row anatomy:** leading 28pt artwork (`SongsList.artwork`) · title + trailing `FormatBadgeView` on line 1 · **stats cue subtitle "N plays · «relative last-played»"** replacing the always-blank `relativePath` line. **No rank number** (a positional 1,2,3 implies a count ranking, false under frecency), **no trailing duration**. Now-playing `▶` glyph + `rowNowPlaying` tint retained (match by the playing file's id/url).
- **Legibility cue is mandatory** (§ founder principle "if you can't see the logic, you assume it's broken"): the "N plays · 2h ago" subtitle is what makes a 40-play/last-week track sitting above a 1-play/today track read as intentional. Flat list — **no Today/This-Week section headers** (they fight a blended score). Relative time via `Date.RelativeFormatStyle` (localized), computed at load, not per render.
- **Interaction:** tap = play now via the Songs path `LibraryBrowseModel.playTrackNextNow(LibraryTrackDisplay)` → `AudioViewModel.playTrackNextNow(AudioFile(track))` (non-destructive insert-next-and-jump; re-tapping no longer appends). Context menu mirrors the Songs row: Play · Play Next · Add to Queue · — · Show in Library · Info. *(Optional/deferred: a destructive "Reset Play Count" — flagged, not built.)*
- **Empty state:** reword `ContentUnavailableView` → "Tracks you finish will appear here." (drops the false "this session"). **A11y:** History-specific VoiceOver label "«title», N plays, last played «named relative time»" + `.accessibilityAction` + context verbs as `.accessibilityActions`. **Dynamic Type:** token fonts only; let the row grow. **Perf:** `ScrollView`+`LazyVStack`, keyed on the durable `Int64` id, bounded query + `LIMIT`.

---

## 5. Integration + cleanup

**Delete (full replacement, no fallback):** `AudioViewModel+History.swift` (`recordPlayStart`, `playFromHistory`), `Models/HistoryItem.swift`, the `sessionHistory` property; the two `recordPlayStart` call sites → `resetPlayTracking()`. Keeping a parallel session log would reintroduce the dup-on-replay bug.

**History tab binds to** a new `LibraryBrowseModel.history: [LibraryTrackDisplay]` + `historyState` + `loadHistory()` → `store.frecencyTracksDisplay(now:)`, mirroring `loadSongs()`'s epoch-guard / `isStoreReady` / empty-vs-first-run discipline. `QueueHistoryList` rebinds from `viewModel.sessionHistory` to `browse.history` (rendered via `RecentlyPlayedRow`); the header subtitle reads `browse.history.count`. **Refresh:** on History-tab appearance + a `playCountRevision` bump the VM emits inside `countCurrentPlay()` so a just-crossed-60% track reorders without a manual revisit.

**Semantic shift (called out):** "everything started this session, incl. skips, with dups" → "all-time, de-duped, frecency-ordered tracks that crossed the 60% threshold." A track skipped at 10% no longer appears. This is what D1–D4 imply; the rename (D6) signals it.

---

## 6. QA / verification plan

Covers the founder's three targets — **counters, sort order, ≥60% accounting**. Store-side is `VerifyLibraryStore` (headless, numbered checks, derived expectations); the 60% rule is the pure `PlayThroughTracker` under `swift test`; the audio path is founder by-ear. A **qa-expert + the-fool break-it pass on the real implementation** runs after the build ([[feedback-qa-first-class]]).

### ≥60% rule — pure `PlayThroughTracker` (swift-testing)
| Case | Setup | Expected | Invariant |
|---|---|---|---|
| Stop at 59% | accrue to 0.59·dur | NOT counted | threshold is exclusive-below |
| Reach 60% | accrue to 0.60·dur | counted **once** | fires at threshold |
| Past 60% → end | accrue to 100% | still **one** (didCount) | no double count at natural end |
| Seek-forward scrub to 90% | one large +delta | NOT counted | scrub rejected (cumulative, not max-pos) |
| Seek-back then re-cross | cross, −delta, cross again | **one** | didCount guards re-entry |
| Pause/resume across 60% | gap with no ticks, resume | counted once, play-through survives | resume ≠ reset |
| Skip before 60% | reset before threshold | NOT counted | new play-through resets |
| Long track (104 min) | accrue to 240 s | counted at the 4-min cap | D2 cap |
| `duration == 0` | ticks with dur 0 | never counts on tick | guarded; natural-end fallback covers real short tracks |
| Replay later | reset, cross again | **second** count | once-per-play-through |

### Counters — `VerifyLibraryStore`
`recordPlay(id:)` accumulates `play_count` + stamps `last_played` (FR1); per-track independence; exactly-once per qualifying play across the fold-in sites; never-played stays 0 (FR5); persists across store reopen; id-keyed vs url-keyed fallback.

### Frecency order — `VerifyLibraryStore` (derived expectations, never magic numbers)
- **FR2 decay accumulation:** two plays `Δt = H` apart → `frecency_score ≈ 1.5` (±ε).
- **FR3 burst-vs-spread (the D7 correctness proof):** N plays at one instant (score ≈ N) vs N plays spaced by `H` (materially lower) → assert `A.score > B.score`. This is the property the rejected naive model fails.
- **FR4 recency-outweighs-count (D4):** via `frecencyTracksDisplay(now:)`, a low-count-just-played track ranks above a high-count-stale track at `H=7d` (order derived from the formula).
- **FR5 never-played excluded**, **FR6 deterministic id tiebreak**, **FR7 EXPLAIN** = accepted filesort over `play_count>0` + no JOIN fan-out, **FR8 pagination window** (LIMIT/OFFSET), **FR-schema** (v4 present + erase-on-schema-change/foreign-rebuild still pass), **FR-move** (Gate-2: `frecency_score`+`last_played` survive a move-match).

---

## 7. Deferred / open

- **Per-play events table** — only if per-play history / "plays in last N days" analytics get scoped (would replace the accumulator; second schema bump). Not now.
- **Preserve play-state columns across schema change** — an explicit **R1 durability requirement** (D8); today they're wiped on any bump.
- **"Reset Play Count" affordance** — flagged in UX (§4); build only if the founder wants a "forget this" action (needs confirm/undo; the only write from this view).

### Files
`AudioViewModel+SpectrumTimer.swift` (tick detector), `+PlayTracking.swift` (counting entry), `+Playback.swift`/`+AutoAdvance.swift` (reset sites), `AudioViewModel.swift` (state), new `PlayThroughTracker` (pure); delete `+History.swift`/`Models/HistoryItem.swift`; `UI/Playlist/QueueHistoryList.swift` + new `RecentlyPlayedRow`, `PlaylistView.swift` (label/subtitle); `LibraryBrowseModel.swift` (`loadHistory`); `LibraryStore/Schema.swift` (v4), `LibraryStore.swift` (write DAO + `prepareDatabase` decay fn), `LibraryStore+BrowseReads.swift` (`frecencyTracksDisplay`); `VerifyLibraryStore/` (FR checks) + `swift test` (`PlayThroughTracker`).
