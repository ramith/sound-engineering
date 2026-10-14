# Panel P5b: browse UI logic, device / output policy, design tokens (N72–N99, N115–N123)

Adversarial panelist, repo @ main `a206107`. Worktree `.claude/worktrees/panel-p5b` (detached). The panel's tests
there are uncommitted and are archived in `exp-p5b/tests/`:
- `P5bBrowseBreakTests.swift` (LibraryBrowseKitTests)
- `P5bOutputPolicyBreakTests.swift` (OutputDeviceKitTests)
- `P5bTokenBreakTests.swift` (DesignTokenKitTests)

Last run (`exp-p5b/test-final.log` plus the dense D8 run): 31 tests, 20 pass and 11 fail. Every failure is a
deliberate defect demonstration listed below.

Harnesses, all in `exp-p5b/`:
- `nstable/`: a real `NSTableView` oracle, plus a differential random test of `ListSelection` against it.
- `devlist/fuzz.cpp`: a CF fuzz run under ASan/UBSan.
- `pure.cpp`: Pure viability on a continuous rate range.
- `thumb/probe.swift`: the ImageIO undershoot.
- `rates.c` and `phys.c`: read-only HAL property dumps. No playback, no app launch, the founder's library untouched.

## Verdict table

| ID | Algorithm | Verdict | Evidence (panel) | Missing proof |
|---|---|---|---|---|
| N72 | `SearchEpoch` | **DEFECT** (LOCAL) | Two reads under one epoch (the filtered reload path) that finish out of order: the older snapshot publishes last (P5B-01) | A test of the reload path; today's 4 tests cover only edits |
| N73 | `SearchQueryGate` | **QUESTIONABLE** | It counts graphemes. "කා" (2 scalars, 1 syllable) and "愛" (one whole word) never search (P5B-11) | A product rule for non-Latin queries |
| N74 | `SongSortMapping` | CORRECT-UNPROVEN | Every sortable `SongColumn` comparator (`SongsColumnModel.swift:21-33`) has a `TrackSort`. "Quality" sorts by container name | A test that every sortable column maps to a non-default `TrackSort`. The column→key-path table is in the app target, so a new sortable column falls back to the default sort silently |
| N75 | `AlbumTrackOrder` | PROVEN-CORRECT | Panel: 3 000 random albums (disc/track ≤ 0, nil, folder discs). The order does not depend on the read order (distinct titles). The repo's break-it tests run on a real store with literal expectations | none |
| N76 | `FacetAlbumGrouping` year tie | **QUESTIONABLE** | Tie → earliest (`:101`) vs the store's `dominantYear` tie → latest (`AlbumGrouping+Years.swift:25`). Reachable only when the album row carries no year. Agrees with P5a LIB-13 | Use `AlbumGrouping.dominantYear` in the fallback |
| N77 | `DetailTrackLayout` | PROVEN-CORRECT | Panel oracle: walking the item heights one by one equals `span(ofRow:)` top + lead-in. Rows are a permutation of the songs. 3 000 random pages × `.byAlbum` / `.flat` | none |
| N78 | `ListOrder.applying` | PROVEN-CORRECT | P5a PL-1: equal to the real `reorderPlaylist` on 300 random partial, duplicate and foreign orders (not repeated here) | none |
| N79 | `ListMove` | PROVEN-CORRECT | Repo: an exhaustive permutation property. Panel: exhaustive n ≤ 8, every subset × 4 moves (≈ 2 000 cases) against the placement spec (up → first lands at max(0, first − 1); down → last at min(n − 1, last + 1); edges), plus block contiguity, both relative orders and availability ⇔ non-nil. 0 failures | none |
| N80 | `CoalescingWriter` | CORRECT-UNPROVEN | Panel model test: 300 random submit / complete schedules with a gated sink. ≤ 1 write in flight, FIFO turns, the newest value per key, per-key values strictly increasing, the final value always written, `unsavedValue` exact. Passes | Adopt the model test (the repo has 7 example tests) |
| N81 | `TypeSelectBuffer` | **DEFECT** (LOCAL) | Typing "මා" selects "මිල" (price), not "මාල" (necklace): `.diacriticInsensitive` folds Sinhala vowel signs. The same root as P5A-04 | A Sinhala test (P5B-07) |
| N82 | `ListKeyboardCursor` | PROVEN-CORRECT | Its step / page / limit arithmetic is covered by the panel's exhaustive grid oracle (1 column = a list) and by 20 000 random selection sequences | none (the semantic differences are under N83) |
| N83 | `ListSelection` | **DEFECT** (SIGNIFICANT) | Measured against a real `NSTableView` on macOS 26. A ⇧ after ⌘ drops the ⌘-picked rows. ⌘A then a ⇧-arrow collapses the selection in 2 461 of 2 479 random cases (P5B-02) | The kit's tests are examples written from its own model, with no macOS oracle |
| N84 | Grid cursor / state | PROVEN-CORRECT | Exhaustive: 0–40 tiles × 1–9 columns × every position × 12 keys (incl. Page by 0 / −3 / 1000), anchored and seeded, against an independent (row, column) oracle. 0 mismatches | none |
| N85 | `GridLayoutMath` | PROVEN-CORRECT | 200 000 random integral and fractional widths against a counting oracle. NaN / ±∞ / 0 / negative / 1e308 inputs stay in 1…1000 | none |
| N86 | `FillGridLayout` | PROVEN-CORRECT | Tiles fill the width exactly (no ragged edge). A tile is ≥ the minimum whenever one fits. Hostile widths → a finite tile ≥ 0 | none |
| N87 | `ScrollPlacement` / `FixedRowReveal` | CORRECT-UNPROVEN | `FixedRowReveal` is PROVEN: in view after the scroll, with the minimal move, and nil ⇔ already in view (200 000 cases). `revealAnchorY` never returns nil when the viewport is shorter than the item + 2·margin, so every press re-scrolls (minor) | A property test of `revealAnchorY` |
| N88 | `ThumbnailUpgrade` | **DEFECT** (LOCAL) | ImageIO can decode 1 px under the request from a bigger source. That decode counts as the "whole image" and is served at every size from then on: about 0.6–0.8 % of small-cover decodes (P5B-05) | An in-test ImageIO repro (panel) |
| N89 | `PlaylistDropRouter` / `PlaylistAddDecision` | PROVEN-CORRECT | Equal to an `NSOrderedSet` oracle on 5 000 random lists | none |
| N90 | Small browse decisions | **DEFECT** (LOCAL) | `QueueToastDecision` with 0 added says "Already in Queue". Since S10.2 retired dedupe, 0 means "nothing playable" (P5B-08). The others (filter, labels, latch, mosaic, resolver) read correct | The test pins the stale copy (`QueueToastDecisionTests.swift:29,36`) |
| N91 | `PlaylistsModel` glue | CORRECT-UNPROVEN | The overlay `ListOrder.applying(orderWriter.unsavedValue…)` and the re-read inside the write read correct, given that N78 and N80 are proven | An app-target integration test (none exists) |
| N92 | `OutputDevicePolicy.action` | **DEFECT** (SIGNIFICANT; product decision) | All 360 (event × facts) cases equal a rule written from the founder's decisions. Fixed point holds (18 start-on-a-dead-device cases settle in 2 steps). But the pin moves to the fallback device after a loss, and Play then re-asserts the speakers over the reconnected headphones (P5B-03). 14 unreachable (target 0, alive) cases answer "re-assert device 0" | A reconnect scenario test |
| N93 | `playbackMovesWithOutput` / `resumeAfterDeviceLoss` | CORRECT-UNPROVEN | Panel: `resumeAfterDeviceLoss` is finite and inside 0…duration for every pair of hostile doubles (±∞, NaN, −0, 1e308). The VM branch is tested only through a mirror (VM-AA-13) | A VM-level test |
| N94 | Output monitor reconcile | **DEFECT** (SIGNIFICANT; model-proven, no hardware repro) | Interleaving model built from the code: an Enhanced start with a default-device change ends wrong in 3 of 16 interleavings (pinned) and 1 of 11 (follow): silent "playing", or playback on a device other than the app's (P5B-04) | A hardware repro; the monitor has no test |
| N95 | `deviceListVerdict` | PROVEN-CORRECT | Repo tests cite the header. Panel: exhaustive 1 568 cases (streams × hidden × privacy × uid × name, with the prefix in each) against the documented rule order. 0 mismatches | none |
| N96 | `aggregatePrivacyFromComposition` | PROVEN-CORRECT | Panel fuzz: 200 000 random composition dicts (Bool, the integer types, float, NaN, ±∞, 1e19, string, null, array, data, noise keys) under ASan/UBSan. 0 crashes, 0 meaningful mismatches. The one quirk is harmless: a double of exactly 2^63 decodes Private, while 1e19 decodes Unknown (`CFNumberGetValue` lossy-flag) | none |
| N97 | Device menu sort | **QUESTIONABLE** | `lhs.name < rhs.name` is code-point order (case-sensitive, not Finder order). Equal names have no tie-break and the sort is unstable. The test is a MIRROR comparator (P5B-10) | A test on production code |
| N98 | `evaluatePureMode` (+ flags) | **DEFECT** (LOCAL), in the flag derivation | The rule itself is correct (PureMode_* 7). A continuous `AudioValueRange` is reduced to its endpoints, so 44.1 kHz on a device advertising [8000–192000] gives `RateUnsupportedResample` with target 192 000 (repro `pure.cpp`). `integerCapable` reads the CURRENT physical format, but the engine picks from the AVAILABLE ones. `exclusiveCapable` is never read (P5B-06) | Tests of the flag derivation (none) |
| N99 | `pureModeEvaluate` C bridge | PROVEN-CORRECT | Read in full. Plain marshalling, null-safe. PureModeBridge_* cover every decision branch, null args and the rate copy | none |
| N115 | Source-over | PROVEN-CORRECT | Panel: 20 000 random straight-alpha pairs (translucent backdrops included) against the W3C Compositing L1 premultiplied formula. Associativity holds. A fully transparent pair gives no NaN | none |
| N116 | WCAG luminance / contrast | PROVEN-CORRECT (with the panel's vectors) | black/white = 21, #767676/white = 4.54, #777777/white = 4.48, primaries = Rec.709 weights. The 0.03928 threshold vs WCAG 2.2's 0.04045 differs by 0.0 over every 8-bit value and every gray pair. Monotone, and the round trip holds to 1.7e-16 | Adopt the known-value vectors (the repo has none) and change the constant to the 2.2 text |
| N117 | `AppearancePair.value` | PROVEN-CORRECT | TOK-03, plus the panel's full cube | none |
| N118 | `resolveSurface` | PROVEN-CORRECT | RES tests, plus the panel's full role × appearance × RT × IC cube (opaque whenever RT or IC) | none |
| N119 | Glow visibility / falloff | PROVEN-CORRECT (the function) | Continuous at 0.55, monotone non-increasing, 1 at 0 and 0 at ≥ 1. NaN and zero-size inputs are safe. The AUDITS that sample this field miss its worst points (N123) | — |
| N120 | SampledGlow clamp | PROVEN-CORRECT | 60 000 samples (incl. a 4 096-point lattice) × 3 slots: inside the box, hue kept (cross ratios), idempotent, token alpha forced | none |
| N121 | SampledGlow light pair | PROVEN-CORRECT | 176 869 accepted samples: light channels in [0.83, 1], luminance ≥ the brand pastel's, and the window never darkens at alpha fractions 0.05 / 0.25 / 0.5 / 1 | none |
| N122 | Dominant cover colours | **QUESTIONABLE** | Degenerate covers are fine (empty, transparent, gray ramp, 1 pixel, flat, the full RGB lattice). But 0° is a bucket edge: a 60 % red cover jittering ±8° around 0° splits its vote and loses slot 1 to a 40 % blue, and two near-identical reds take 2 of the 3 slots (P5B-09) | — |
| N123 | Audit corner palette / R4 glow audits | **DEFECT** (LOCAL) | `statusWarningText` on the badge over the glow at the teal centre is **4.474:1 < 4.5**: 4.477 even with the brand palette (R4-BADGE-01's own case). The audit grid's minimum is 4.526, so it passes (P5B-12) | Glow centres and the core-boundary ring in `gridPoints()` |

**Counts (37 rows): PROVEN-CORRECT 19 · CORRECT-UNPROVEN 5 · DEFECT 9 · QUESTIONABLE 4.**

## Defect and questionable details

### P5B-02 (N83): `ListSelection` is not "the way a macOS list does": ⇧ after ⌘, and ⌘A then ⇧-arrow (SIGNIFICANT)

**Spec.** `ListSelection.swift:3-4` claims the verbs "change it the way a macOS list does".
- The reference is AppKit `NSTableView`, which Music and Finder lists use.
- Apple's table-view guide: Shift is for contiguous selections, Command for non-contiguous ones ([Enabling Row Selection](https://developer.apple.com/library/mac/documentation/cocoa/Conceptual/TableView/RowSelection/RowSelection.html)).
- The legacy HIG: "the selection is extended to include everything between the old anchor point and the new active end". On whether the ⌘-built rows survive, observed NSTableView keeps them: [cocoa-dev 2005](https://lists.apple.com/archives/cocoa-dev/2005/Apr/msg01263.html) reports click 0, ⇧3, ⌘9, ⇧7 → {0–3, 7–9}.

**Evidence: the panel's own oracle.** `exp-p5b/nstable/oracle.swift` builds a real 10-row `NSTableView`, sends real NSEvents, and measures the result on this Mac.

| Sequence | NSTableView | Kit |
|---|---|---|
| click 1, ⌘4, ⇧7 | {1,4,5,6,7} | {4,5,6,7} |
| click 1, ⌘5, ⇧↓ | {1,5,6} | {5,6} |
| click 9, ⌘A, ⇧↑ | {0…8} (narrows) | {8,9} |
| click 4, ⌘A, ⇧↓ | all rows | {4,5} |

- The ⌘A case contradicts the kit's own doc at `:121-125`: "a ⇧-key … after ⌘A narrows the range instead of collapsing it" (break-it 7). That fix only covers the case with NO anchor.
- 20 000 random sequences: a ⇧-arrow right after ⌘A collapsed the selection in 2 461 of 2 479 cases.
- Differential run (`diffsel.out`): with plain clicks and arrows only, the kit matches NSTableView everywhere except the edges. Once ⌘-click or ⌘A is in play, 63–80 % of random sequences diverge.
- Every other invariant held over 20 000 sequences with filters, re-sorts and reloads: the anchor and cursor are never ghosts, the ring is in the rows, action targets are in display order, and the menu rule is right.
- Smaller differences (QUESTIONABLE, product choices):
  - ⇧⌘-click: the kit takes a range, NSTableView toggles one row.
  - Home/End: the kit selects, NSTableView only scrolls.
  - An arrow at an edge: the kit keeps the multi-selection and bubbles, NSTableView collapses to the edge row.
  - A plain arrow after a ⌘-deselect: the kit moves from the first selected row, NSTableView from the lead row.

**Root cause.** `moveCursor(to:selecting:)` replaces `ids` with the ⇧-range (`:207-215`). There is no "base selection", the rows held before the current ⇧-gesture. `selectAll` keeps an existing anchor instead of setting anchor = first and lead = last.

**Remedy.**
- Keep `base: Set<ID>`, snapshotted at each non-⇧ verb. A ⇧ verb sets `ids = base ∪ range(anchor…cursor)`.
- ⌘A sets anchor = first row and cursor = last row.
- Decide the four small differences explicitly, and pin them with tests taken from the oracle.

Effort S–M (kit-local, plus a test rewrite). Risk low.

### P5B-03 (N92): the pin moves to the fallback after a disconnect, then fights the reconnected device (SIGNIFICANT, needs a founder decision)

**Spec.**
- Founder decisions (`OutputDevicePolicy.swift:8-15`): pause on loss and never carry on from another device; the pin means "Keep playback on THIS device".
- NFR-REL-02 (`docs/product/requirements.md` ~747): "the user can resume playback after reconnecting".
- The pin is ON by default (`AudioEngineBridge.swift:216`).

**Evidence.** The panel test `pinnedDeviceReconnect` runs this sequence:

1. The user plays on AirPods (A).
2. A drops out; macOS moves the default to the speakers (B). The app pauses and adopts B (`:113`), and the pin now holds B.
3. A reconnects and macOS makes it the default. The app is idle, so nothing happens.
4. The user presses Play. The rule answers `.enhancedStarting` with "re-assert target as default": the app moves the SYSTEM default back to the speakers and plays out loud on them.

`refreshDevices` keeps no memory of the device the user picked (`AudioViewModel+Devices.swift:43-70`).

Apart from this, the rule matches a spec-derived oracle on all 360 cases, and the fixed point holds.

**Root cause.** One field (`currentDeviceID`) carries two meanings: "the device the user pinned" and "the device we fell back to".

**Remedy (recommended).** Keep `pinnedUID` separately. After a loss, adopt the default as a temporary target. When `pinnedUID` reappears (on `devicesChanged`), adopt it again. Never re-assert a fallback the user did not pick.

The alternative is to drop to follow mode after a loss until the user picks a device again. Effort M (bridge + VM). Risk medium (device code). Also: guard the rule against `target == 0` (14 unreachable cases answer "re-assert device 0").

### P5B-04 (N94): the Enhanced start races the output rule (SIGNIFICANT, model-proven, no hardware repro yet)

**Evidence.** The panel's interleaving model `monitorInterleavings` is built from these code facts:
- `startEnhancedPlayback` runs the align (read and act) at `+Playback.swift:96` on `engineQueue`.
- It then runs `engine.start()`, and only then sets `enhancedPlayIntent = true` (`:123`).
- `readOutputDeviceFacts` maps "intent false and not Pure" to `.idle` (`+OutputDeviceMonitor.swift:165-170`).
- A configuration change stops the engine, and the rule restarts it only for `.enhanced` (`+ConfigChange.swift:46-56`).

A default change X (Control Center, or headphones connecting) is interleaved at every point of the start. The bad endings:

| Pin | Bad interleavings | What goes wrong |
|---|---|---|
| ON | 3 of 16 | 1 silent "playing"; 2 playing on B while the app's device, pill and per-output EQ say A |
| OFF | 1 of 11 | 1 silent "playing" |

An example of the silent case: S1 align · S2 `engine.start` · X · R `defaultChanged` [idle] → nothing · R `engineReconfigured` [idle] → nothing · S3 intent = true. The UI shows playing while the engine is stopped.

If the change lands inside `playFile` instead, `player.play()` on a stopped engine may raise. That is unverified.

The window is S1 → S3: `engine.start` (long on Bluetooth) plus `playFile`. The earlier stall-audit evidence (`docs/architecture/evidence/main-thread-stall-2026-10/`) does not cover this window; there is no disagreement, the finding is new.

**Remedy.**
- Publish a "starting Enhanced" state that `readOutputDeviceFacts` reads as `.enhanced`, before `engine.start`. Clear it on failure.
- After intent = true, enqueue one reconcile on `configChangeQueue` that re-reads the facts. It closes every window, because it reads after them.

Effort S. Risk low. A hardware repro is worth doing first: Bluetooth connect + Play.

### P5B-01 (N72): the reload path is not newest-wins (LOCAL)

**Evidence.**
- `runFilter` captures the epoch without bumping it (`LibraryBrowseModel.swift:361`). Only an edit invalidates it (`:111`).
- `reloadIfScanChanged` starts in an unstructured `Task` per revision (`LibraryTabView.swift:53`) and calls `runFilter` (`:390`).
- Reads run on a `DatabasePool` (concurrent).
- So two reloads' reads can finish out of order, and the older snapshot then publishes last. The panel model test shows the guard can't order two reads with the same epoch. Effect: a newly scanned song that matches the query stays hidden until the next revision bump or edit.

**Remedy.** Invalidate per read inside `runFilter`, so the newest-issued read wins. Two lines. Risk low.

### P5B-05 (N88): a 1-px ImageIO undershoot makes a small thumbnail permanent (LOCAL)

**Evidence.**
- `servesUpTo` returns `Int.max` when the decoded side is smaller than the request (`ThumbnailUpgrade.swift:11-13`).
- ImageIO, with the app's exact options (`ArtworkThumbnailStore.swift:123-128`), sometimes returns request − 1 from a larger source. Panel test `thumbnailUndershoot`: a 506×185 source at request 64 gives 63×23, so `serves(Int.max, 320)` is true.
- `thumb/probe.swift` runs the app pipeline (an embedded cover → a ≤512 stored thumb → view requests). 36 of 5 749 decodes (rerun; 47 of 5 755 before) were marked "whole image" and are served at every later size.
- `replaces` never replaces `Int.max`, so a 63-px image stays in a 480-px tile for the session.

**Remedy.** Read the source's pixel size (`CGImageSourceCopyPropertiesAtIndex`) and use `Int.max` only when decoded ≥ source. Effort S.

### P5B-06 (N98): Pure viability on continuous rate ranges (LOCAL); the integer flag (QUESTIONABLE)

**Evidence.**
- `AudioHardwareBase.h`: `kAudioDevicePropertyAvailableNominalSampleRates` are "the valid ranges for the nominal sample rate".
- `getAvailableSampleRates` turns a range into its two endpoints (`CoreAudioDevice.cpp:427-431`). `supportsRate` tests membership within ±1 Hz.
- `pure.cpp`: [8000–192000] with a 44.1 kHz file gives `RateUnsupportedResample` with target 192 000. Pure is refused, though it is safe (it falls back to Enhanced).
- This Mac's devices all report discrete rates, so the impact is limited to devices that report ranges.
- `integerCapable` (`:497`) reads the CURRENT physical format, while `HALOutputEngine` picks integer formats from the AVAILABLE list (`.mm:639-660`). A DAC sitting in float could be judged "RateMatchedFloat". Unverified: no USB DAC was attached.
- `exclusiveCapable` is never read.

**Remedy.** Keep ranges as (min, max) and test containment. Derive `integerCapable` from `AvailablePhysicalFormats` at the rate. Delete `exclusiveCapable`. Effort S–M.

### P5B-07 (N81): type-select ignores Sinhala vowel signs (LOCAL; the same root as P5A-04)

**Evidence.** `firstMatch` uses `.diacriticInsensitive` (`TypeSelectBuffer.swift:43`), and "මා" lands on "මිල". The facet filter fails the same way (P5A-04).

**Remedy.** Fold only the Latin / Greek / Cyrillic combining range (U+0300–036F after NFD) instead of every Mn/Mc mark. That keeps "beyo" → "Beyoncé". Share one matcher with `FacetTextFilter`. Effort S.

### P5B-08 (N90): a stale "Already in Queue" toast (LOCAL)

**Evidence.**
- `QueueToastDecision.swift` maps 0 added to "Already in Queue". That was S9's dedupe, which S10.2 retired (`AudioViewModel+Queue.swift:17-19`).
- `appendToQueue` / `playNext` now return 0 only for an empty input.
- The playlist menu passes 0 when nothing in the playlist is playable (`PlaylistsModel+Play.swift:44-61` → `PlaylistMoreMenu.swift:37`). The toast then claims the songs are queued when nothing was added.

**Remedy.** For 0, show no toast or "Nothing playable to add". Update `QueueToastDecisionTests:29,36`. Effort XS.

### P5B-12 (N123 / N119 audits): the glow audits miss the field's peaks; one real AA failure (LOCAL)

**Evidence.** The R4 grid (`ContrastAuditTests.swift:139-147`, 25×17 points on 1/24 and 1/16) never lands on a glow centre (teal 0.214, 0.067; app glow 0.385, 0.30).

The panel computed a dense grid (≈ 225 000 points, plus the centres) beside the audit grid:

| Pair | Grid min | Dense min | At |
|---|---|---|---|
| R4-GLOW-01 `labelSecondary` | 4.760 | 4.720 | |
| R4-GLOW-04 tertiary outside the core | 4.586 | 4.544 | the lime centre |
| R4-GLOW-APP-01 | 4.798 | 4.720 | |
| **badge `statusWarningText` (D8 lattice and R4-BADGE-01)** | **4.526** | **4.474 (brand 4.477)** | **the teal centre: an AA failure** |

That last pair is the hero's "Pure unavailable" capsule (`HeroBand.swift:113-116`), in the teal-core hero.

**Root cause.** Point sampling without the analytic maxima. The field's brightest points are the glow centres (falloff = 1 there) and the overlaps.

**Remedy.**
- Add every glow centre, plus the t = 0.55 core-boundary ring, to `gridPoints()`. One line.
- Fix the pair: lift the dark `statusWarningText` slightly, or darken the badge fill. Then re-run the R4 suites.

Effort S.

### P5B-09 (N122): hue histogram buckets (QUESTIONABLE, quality)

**Evidence.**
- 12 fixed 30° buckets starting at 0°. A red that jitters around 0° splits between buckets 0 and 11.
- Panel: a 60 % red cover → top colour blue (the 40 % field), and two reds take slots 2 and 3.

**State of the art.**
- A circular histogram with neighbour merging, or buckets offset by half a bucket.
- Better: median cut (ColorThief's MMCQ) or k-means in Oklab, as Android Palette does.

Effort S–M (the clamp still bounds the audit). Risk low.

### P5B-10 (N97): device menu sort (QUESTIONABLE)

**Evidence.**
- `models.sort` uses `lhs.name < rhs.name` (`AudioEngineBridge+Devices.swift:47-54`): code-point order, so "external …" sorts after "Z…".
- Equal names (two "USB Audio Device") have no id tie-break, and `sort` is unstable, so the menu can reorder between refreshes.
- The test re-implements the comparator (`AudioEngineProtocolTests.swift:202-220`).

**Remedy.** `localizedStandardCompare`, then the UID. Extract it to a Kit and test the real function. Effort XS.

### P5B-11 (N73): the 2-character gate on grapheme count (QUESTIONABLE)

**Evidence.** `count >= 2` counts graphemes, so one CJK ideograph (often a whole word) or one Sinhala syllable typed with two keys never queries.

**Remedy (product).** Gate on Unicode scalars, or let any non-ASCII single grapheme through. Pair it with P5A-04's tokenizer fix. Effort XS.

### N76 (QUESTIONABLE): two year-tie rules

Agree with P5a LIB-13: the rules diverge, but the difference is reachable only transiently. Use `AlbumGrouping.dominantYear` in `FacetAlbumGrouping.albumYear(of:)`. Effort XS.

## State of the art
- The rules here are mostly the right algorithms: Porter-Duff source-over, WCAG 2.x contrast, adaptive-grid column math, block moves, newest-wins writers.
- What is dated or missing:
  - WCAG 2.2 text (0.04045).
  - A macOS-faithful selection model (base ∪ range).
  - Range-aware rate support.
  - Perceptual colour extraction: Oklab k-means or MMCQ instead of a fixed RGB-hue histogram.
  - Analytic worst-case points in the contrast audits.
- APCA (WCAG 3 draft) is the emerging contrast metric. Not recommended until WCAG 3 is normative, so stay with WCAG 2.2.

## Top missing proofs (adopt from the panel worktree)
1. The NSTableView-derived selection vectors and the random invariant test (N83).
2. The CoalescingWriter schedule model (N80).
3. Glow centres in the R4 grid (N123), and WCAG known-value vectors (N116).
4. A reconnect scenario and a start/event interleaving test for the device path (N92/N94). The monitor has no test at all.
5. Flag-derivation tests for Pure (N98), and production-code tests for the device sort (N97).
