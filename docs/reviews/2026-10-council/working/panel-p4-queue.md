# Panel P4: queue, transport and play stats (N1–N29), plus the D41 adjudication

Repo `main` @ a206107, worktree `.claude/worktrees/panel-p4` (detached). Scratch: `scratchpad/council/exp-p4/`.

## How I tested

I did not trust the code's comments, its tests, or earlier reviews. I formed a view first, then read the earlier evidence.

### E1: VM harness (`exp-p4/vm/`, `run.sh`)
- **What it runs.** The **real** `AudioViewModel` sources, copied verbatim (13 VM files plus `EngineSnapshot` / `TransportSnapshot`). `+PlayTracking` is real too, except the store write, which a recorder replaces.
- **Why a new engine model.** The old break-it harness (`breakit/s10-8-g-playback-shell`) is built against the pre-snapshot protocol, and it no longer compiles. Its fake engine logged `setNextTrack` calls, which gives "replace" semantics, and that is why it could not see the Pure refusal.
- **The engine model** (`EngineModel.swift`) follows the bridge source, not what the VM expects:
  - `engineQueue` is one serial FIFO.
  - Every transport op publishes a **transitional sample**. It carries the **last published** seam count, `ended = false`, and the op's epoch (`+TransportClock.swift:55-61`). The op then publishes a settled sample.
  - The **Enhanced** seam count is cumulative (`gaplessTransitionCounter`, never reset). The **Pure** count restarts at 0 on each start (`GaplessSource.cpp:85`).
  - Enhanced `setNextTrack` **replaces** the on-deck (`+Gapless.swift:61-82`).
  - Pure `setNextTrack(url)` opens the file on a global queue, then arms on `engineQueue`. `armNext` **refuses** while a track is armed (`GaplessSource.cpp:127-130` → `PureModeBridge.cpp:357-362`).
  - `stopAudio` does not check its epoch (`+Playback.swift:243-269`).
- **The model's limit.** The VM's calls reach the queues in call order (the harness compiles with `NonisolatedNonsendingByDefault`). The real nonisolated async bridge methods hop to the global executor first. So the app has **strictly more** orderings than this model: anything broken here can break in the app.
- **What it drives.** Targeted scenarios, plus a random-schedule explorer: 3000 schedules mixing play / pause / seek / stop / next / toggle with engine-op steps, file-open completions, main-actor drains, 20 Hz ticks and one seam.
- **Results:** `exp-p4/vm-results.log`.

### E2: Kit property tests (swift-testing, uncommitted, in the worktree)
- Files: `Tests/AudioViewModelTests/P4CouncilPropertyTests.swift` and `Tests/LibraryBrowseKitTests/P4CouncilFrecencyTests.swift`. Copies are in `exp-p4/kit-tests/`; the log is `exp-p4/kit-tests.log`.
- `Package.swift` is edited locally to list the first file.
- What they cover:
  - a chi-square test of the shuffle pick;
  - an exhaustive spec check of next and previous;
  - model-based tests of `playNextNow` and `QueueRestorePoint`;
  - an independent oracle for `PlayThroughTracker`;
  - a brute-force exponential-decay oracle for frecency.

### References opened
- **VLC `src/playlist/randomizer.c`.** Its design comment, lines 42-68, says:
  - "an item must never be selected twice";
  - "\"prev\" navigates back in the history of previously selected items";
  - "if loop is disabled, there is only one cycle";
  - the order is built as an incremental Fisher-Yates shuffle.
- **Spotify Engineering, "How to shuffle songs?" (2014-02-28).** Spotify shuffle was a Fisher-Yates permutation, later spread by artist.
- **foobar2000 "Shuffle (tracks)" vs "Random".** Shuffle is a per-playlist randomised order that is played through. Random is draws with repeats. This is from Hydrogenaudio forum posts that quote the FAQ, so it is second-hand.
- **Mozilla wiki, *User:Jesse/NewFrecency*.**
  - The score is a sum of exponential decays.
  - "store now() + t in the database"; "Sorting by (current) frecency score is equivalent to sorting by reverse date (on which the frecency will be 1)".
  - The wiki uses a 30-day half-life; the app uses 7 days.
- **Last.fm scrobbling API.** "The track must be longer than 30 seconds. And the track has been played for at least half its duration, or for 4 minutes (whichever occurs earlier.)"
- **SFBAudioEngine and Cog**, as opened in `arch.md` ARCH-1: one transport generation; the player pulls the next item; plays are counted from heard frames.

---

## 1. D41 adjudication (P3a DEFECT vs P3b PROVEN-CORRECT): **DEFECT, SIGNIFICANT.** Both panels are right about what they each measured.

**What each panel checked:**
- **P3b checked the seam itself:** sample accuracy, an exactly-once exchange, and the off-RT reap. I agree that part holds.
- **P3a checked the arm contract** at the C++ level. It is broken.
- **What decides the row is the contract between the VM and the bridge.**
  - The VM treats `setNextTrack(url)` as **replace**. It sets `pendingNextIndex` synchronously and never reads the outcome back.
  - The Enhanced path implements replace.
  - The Pure path refuses a second arm, and the refusal reaches the VM only as a log line (`+Gapless.swift:118`, "→ error").

**Which app sequences reach "arm while armed"**, measured on the real VM sources. In every BROKEN row the user hears the old armed track, while the app shows the new pick in the queue highlight, footer title, duration, Now Playing and Control Center. The new pick is then **skipped**, and the play count goes to the wrong track.

| App sequence while a song plays on **Pure** | Reaches it? | Hears / Shows after the seam |
|---|---|---|
| Play Next (`playNext` → `armOnDeck`, `+Queue.swift:122-124`) | **yes** | t1 / t9 |
| Shuffle on (`rearmOnDeck`, `+Playlist.swift:159-167`) | **yes** | t1 / random pick |
| Shuffle off | **yes** | old random pick / t1 |
| Repeat all → one | **yes** | t1 / t0 (repeat shown, next song heard) |
| Repeat one → off | **yes** | t0 again / t1 |
| Remove the on-deck row (`adjustPendingNextIndexAfterRemoval`, `+Playlist.swift:99-115`) | **yes** | **the removed song plays** / t2 |
| Repeat off → all, mid-queue | no (same pick) | agree |
| Append, remove another row, drag-reorder, Next/Previous/click (a new start clears the deck) | no | agree |
| Same six sequences on **Enhanced** | no (replace) | agree |

**The P3a remedy is necessary but not sufficient:**
- **With the remedy,** `clear()` then `armNext()` on `engineQueue` fixes all six (`D41/Pure+remedy/*` HOLDS).
- **But a Pure arm runs in two steps** (open on a global queue, then arm on `engineQueue`), so arms from different requests can land in any order:
  - **PURE-REARM-ORDER:** two quick Play Next. The second file open finishes first, so the remedy arms **t10** while the app promises **t11**.
  - **NEXT-NEXT/Pure:** Next, then Next, while the first prime's open is in flight. The stale arm (t2, made for the old start) lands on the **new** session, where t2 is already current. **t2 plays twice**, while the app shows t3 (refused: t3).
- **The full fix:** stamp every arm with the transport epoch plus an arm sequence number. The engine applies only the newest arm for the current start (replace semantics), and drops the rest.

---

## 2. ARCH-1 check (two transport owners): **confirmed.** It causes wrong-song and stale-state outcomes in my rows.

Eight of my nine defect groups sit on the VM ↔ bridge seam. The common cause:
- **Selection is inferred, not reported.** The engine reports a seam as an anonymous **count**. The VM infers *which* track is audible from its own `pendingNextIndex`.
- **Epochs guard only reads.** They filter **samples**, never **commands**.
- **The VM has no "starting" state:** `isPlaying` is false for the whole start.

Measured outcomes:
- wrong song shown: D41, NEXT-NEXT, SEAM-AT-START, COUNT-DOMAIN, PLAY-THEN-NEXT;
- the app shows Playing over a silent engine: STOP-THEN-PLAY, PAUSE-THEN-PLAY;
- the engine plays while the app shows stopped (explorer);
- play counts credited to the wrong track (every wrong-song case).

**Explorer, 3000 random schedules:**

| End state | Schedules |
|---|---|
| app shows playing, engine silent | 101–106 (~3.4 %) |
| wrong song shown | 73–75 (~2.5 %) |
| app's next ≠ engine's armed | 51–52 (~1.7 %) |
| engine plays, app shows stopped or paused | 46–48 (~1.5 %) |

---

## 3. Verdict table

| ID | Algorithm | Verdict | Evidence | Missing proof |
|---|---|---|---|---|
| N1 | `QueueAdvance.nextIndex` | **DEFECT** (shuffle branch; P4-3) | The linear / repeat part equals the spec exhaustively: 624 cases, count 0–7, every mode. Shuffle is a with-replacement walk: it **never ends with repeat off** (0/2000 runs end), and needs a mean of **26.8 plays to hear all 10 tracks** (16.8 repeats; a permutation needs 10). | — (redesign) |
| N2 | `previousIndex` | **DEFECT** (P4-3) | Under shuffle, Next then Previous returns to the song you came from only **27–38 / 200** times (≈ 1/(n−1)). Spec (VLC, Apple, Spotify): Previous walks back the history. | — |
| N3 | `uniformRandomExcluding` | **PROVEN-CORRECT** | Chi-square over 65 (count, current) cells × 20k draws: worst χ²/crit(p = 0.001) = 0.81, 0 rejections, never returns current. Bijection skip-over-current plus `Int.random` (unbiased). | VM-QA-08 tests range only; land the chi-square |
| N4 | `appendArmIndex` | **DEFECT** LOCAL (P4-4) | Repeat-all on the last song, then append t7: plays **t0**, not t7 (the appended song waits a whole cycle). Shuffle on a 1-track queue, then append: the queue **stops**. | Spec case for repeat-all / shuffle |
| N5 | `PlaybackOrder.onDeck` | **PROVEN-CORRECT** (the rule) | VM-PO-01..10 encode the doc's spec. **Its caller (`rearmOnDeck`) reaches D41 on Pure** (§1). | A caller test on a Pure-semantics engine |
| N6 | `QueueInsert.playNextNow` | **DEFECT** LOCAL (P4-5) | With duplicates (allowed since S10.2), 419–443 / 20k random cases: re-clicking the **playing** track, when an earlier duplicate exists, moves that duplicate to after the current and plays it, instead of restarting. The doc still says "the queue forbids duplicate URLs". | Duplicate-aware tests |
| N7 | `QueueRestorePoint.afterReplace` | **PROVEN-CORRECT** | Model test, 20k random replace / edit / restore sequences vs an oracle built from the doc ("same slots, same order" = untouched): 0 violations, ids preserved. | — (land it) |
| N8 | `ResumePoint` | **PROVEN-CORRECT** | Answers for its own slot only (exhaustive over 6 ids). VM-level: 1500 random edit sequences keep it with its slot (E1 ID-STABILITY). | — |
| N9 | `SeekRoute` | **PROVEN-CORRECT** | 4-case truth table, exhaustive; "paused wins" covers the pause in flight. | — |
| N10 | `TransportSnapshot.isCurrent` | **PROVEN-CORRECT** (the rule) | `epoch ≥ requested`, exhaustive incl. UInt64 edges. The **protocol** around it is defective (N12/N13). | — |
| N11 | `SnapshotChannel` | **PROVEN-CORRECT** | A copy under `OSAllocatedUnfairLock`, no caller code under the lock; VM-TS-01..03. | — |
| N12 | VM epoch numbering + stop gate | **DEFECT** SIGNIFICANT (P4-2) | The stop / pause epoch is numbered **inside** the Task (`+Lifecycle.swift:171,185`). Stop is **two** engine calls (`setNextTrack(nil)`, then `stopAudio`). The gate is a single number, so a start numbered after a stale stop passes it. Repros: STOP-THEN-PLAY and PAUSE-THEN-PLAY on Pure → engine **silent**, app **Playing**, playhead frozen; STOP+PLAY-SAME-TURN → the click is lost. | A VM harness on a real-semantics engine |
| N13 | Engine epoch stamping + sampler | **DEFECT** SIGNIFICANT (P4-1, P4-2) | (a) A stale `stopAudio` still stops (`+Playback.swift:243-269`); `max(epoch)` only fixes the label. (b) The transitional sample carries the last **published** count, which the VM may have ignored as stale (`+TransportClock.swift:58-60`), so the next start shows it as a seam (SEAM-AT-START, both paths). (c) Two count domains, one field: Enhanced is cumulative, Pure is per-start (COUNT-DOMAIN, Pure→Enhanced). The count → position → count read is right. | Engine-level epoch tests |
| N14 | Gapless auto-advance tick | **DEFECT** (P4-1, P4-7) | It advances on any count rise under a current epoch, with no identity check (SEAM-AT-START, COUNT-DOMAIN). `pendingNextIndex = nil` means both "suppress" and "end of queue" (7 sites: `+Lifecycle:157`, `+Playback:73`, `+Playlist:75,127`, `+SpectrumTimer:87,120`, `+Transport:50`). A Pause in the last tick of a song whose next needs a reconfigure becomes **end-of-queue**: the resume point is dropped, the play is counted, and Play restarts from 0:00 (PAUSE-NEAR-END). The comment at `:96-100` ("the next tick catches any remaining delta") contradicts `lastTransitionCount = currentCount`. A jump of 2 or more is unreachable by construction (one-slot deck, VM-driven arm), so that one is LOCAL. | Real-code tick tests |
| N15 | `handleTrackTransition` | **DEFECT** STRUCTURAL (P4-1) | It assumes `pendingNextIndex` is what the engine played. Fed wrong by D41, NEXT-NEXT and SEAM-AT-START. | Same |
| N16 | `pollPlayhead` | **CORRECT-UNPROVEN** | The rule is right. It inherits P4-2's stuck state (Playing, frozen position). | A real-code test |
| N17 | `startPlayback` / prime | **DEFECT** SIGNIFICANT (P4-2) | `isPlaying` stays false for the whole start, so Next during a start only re-selects. PLAY-THEN-NEXT (both paths): **hears t0, shows t1, Playing**. The prime also re-sets `pendingNextIndex` after a pause is already in flight. | — |
| N18 | Queue-edit re-indexing | **DEFECT** SIGNIFICANT (P4-4) | Ids are stable (1500 random sequences: selection, on-deck and resume point all keep their slot). But under **linear** order the armed pick is kept by identity after a reorder: drag t3 under the playing t0 → queue `[t0,t3,t1,t2,t4,t5]`, **heard `[t0,t1,t2,t4,t5]`: t3 is never played**, on both paths. Spec (VLC / foobar2000): next = the row after the current, computed at track end. | — |
| N19 | Queue verbs | **DEFECT** (via §1, P4-4) | `playNext`, `armOnDeck` and the re-arm on removal reach D41 on Pure. The QueueOps mirror still dedupes, so VM-Q-11 and VM-Q-13..15 assert retired behaviour (map). | Real-code verb tests |
| N20 | Press-Play start choice | **DEFECT** (P4-2; ledger-known) | Space, Space during a start: the second press **starts again** (2 starts), and the pause is lost. | — |
| N21 | `canGoNext` / `canGoPrevious` | **CORRECT-UNPROVEN** | Same function as the verbs; deterministic nil-ness. It inherits N1: under shuffle, Next is always enabled because the queue never ends. | A unit test |
| N22 | Queue cursor restore | **CORRECT-UNPROVEN** | Exact (position, id) → id → nil. Latent: a nil-trackID slot saves no id, so after relaunch its offset applies to whatever slid into the row. There is no UI entry for loose files today. | Tests |
| N23 | Queue → playlist mirror | **CORRECT-UNPROVEN** | A full snapshot self-heals on the next edit. It depends on GRDB writer FIFO for last-writer order. | VM debounce test |
| N24 | `NowPlayingSnapshot` / plan | **PROVEN-CORRECT** | NP-01..10 cover the decisions. It faithfully shows the VM's wrong song in the §2 states. | — |
| N25 | `PlayThroughTracker` | **PROVEN-CORRECT** | Independent oracle, 20k random runs with deltas in (−1, 12): fires exactly once at the first accrual reaching min(0.6·d, 240) for d ≥ 30, else never. The 60 % (Last.fm: 50 %) is product decision D2. | — |
| N26 | Monotonic accrual driver | **DEFECT** LOCAL (P4-6) | It counts **wall time while `isPlaying`**, not heard audio. The logged suspicion is confirmed and is wider than stalls: **1.01 s credited per 1.0 s of silence** before `interrupted` is published; **0.56 s of a 0.6 s slow start** credited to the new song. The uptime clock is right for sleep. | Engine-side heard-frame counting |
| N27 | Frecency `frecencyAfterPlay` | **PROVEN-CORRECT** (clock edge LOCAL) | Brute-force oracle (Σ 2^(−(T−tᵢ)/H)): accumulator relative error ≤ 3e-16; **0 inversions in 132k pair comparisons**, read up to 10 years later; 2 years at one play per minute stays at 14542.87 vs the bound 14542.87. Clock set back 7 days at one play: the final score is 19 % low, and it self-heals. **One play stamped 5 years ahead stays above a track played 3× this week for ~1812 days.** | — (land the oracle) |
| N28 | `incrementPlayCount` | **PROVEN-CORRECT** | One write transaction (read → compute → update); VLS checks plus the N27 oracle. | — |
| N29 | Recently-Played read | **QUESTIONABLE** LOCAL (P4-8) | `ORDER BY rank DESC, id DESC` is equivalent to frecency order (N27). But v3→v4 has **no backfill** (`Schema.swift:390-396`; its rationale, "counts reset via the delete-rebuild posture", is stale since S10.3 preserves user data). Songs played before v4 sort **last** until they are played again. | — |

**Counts:** PROVEN-CORRECT 11 (N3, N5, N7–N11, N24, N25, N27, N28) · CORRECT-UNPROVEN 4 (N16, N21, N22, N23) · **DEFECT 13** (N1, N2, N4, N6, N12–N15, N17–N20, N26) · QUESTIONABLE 1 (N29).

---

## 4. DEFECT / QUESTIONABLE details

### P4-1: The engine reports a seam without saying which track is audible. STRUCTURAL (N13–N15, N19, D41)

**Evidence** (E1, real VM sources):
- **D41:** six Pure sequences (§1).
- **NEXT-NEXT/Pure:** t2 plays twice; the app shows t3.
- **SEAM-AT-START:**
  - The user clicks t3 just as the t0→t1 seam lands.
  - The seam was published under the old epoch and ignored, then carried into the start's transitional sample (`seen.transitionCount`).
  - A tick during the start (a Pure rate change takes seconds) advances to t1.
  - Result on both paths: **hears t3, shows t1**, until the next seam.
- **COUNT-DOMAIN:** a Pure → Enhanced start republishes the cumulative Enhanced count (4) against a Pure baseline (0). A tick before the prime advances: **hears t3, shows t1**.

**Root cause:**
- The engine reports a seam as an anonymous count, and the VM decides from its own `pendingNextIndex` which track that means.
- Arms are not stamped with an epoch; the Pure arm refuses where the VM assumes replace.
- The two paths keep two count domains.

**Remedy:**
- Short term (S–M):
  - Make the Pure arm replace (`clearNext` + `armNext` on `engineQueue`).
  - Stamp every `setNextTrack` with (start epoch, arm sequence number), and have the engine drop stale arms.
  - Make the seam count epoch-scoped: reset it per start on both paths, or have the VM take the first current sample of a start as its baseline, never as a seam.
  - Publish `currentURL` / an item token in `TransportSnapshot`. `handleTrackTransition` then sets the selection from the engine's report, not from `pendingNextIndex`.
- Structural: ARCH-1's `Player`, which pulls the next item (Cog `playbackEngineNextTrack`) and emits `didBeginTrack(item)`.

**Effort / risk:** S–M for the short-term fixes, low risk. L as part of ARCH-1.

### P4-2: Epochs guard samples, not commands; a stop is two calls and is numbered late; the VM has no "starting" state. SIGNIFICANT (N12, N13, N17, N20)

**Evidence:**
- **STOP-THEN-PLAY/Pure:** Stop, then double-click t2 while `engineQueue` is busy. The `setNextTrack(nil)` clear queues ahead of the start, and the stop lands after it. Result: **engine SILENT, app Playing t2**, playhead frozen. No end flag ever arrives, so it stays stuck until the user acts.
- **PAUSE-THEN-PLAY/Pure:** the same shape; **engine SILENT, app Playing**.
- **On Enhanced** the clear goes to `resampleQueue`. These hold when that queue is free, and fail when it is busy (for example, opening the next file).
- **PLAY-THEN-NEXT** (both paths): hears t0, shows t1.
- **PLAY-THEN-PAUSE:** two starts.
- **STOP+PLAY-SAME-TURN:** the stop gets epoch 3, after the start's 2, so the start is abandoned and the click is lost. A replay of the explorer case shows the converse: the engine plays while the app shows stopped.
- **Explorer:** four end-state classes, 1.5–3.4 % of random schedules each.

**Root cause:**
- `nextStopEpoch()` runs inside `performPause` / `performStop`, not in `pause()` / `stopPlayback()`.
- The redundant `setNextTrack(nil)` makes a stop two awaits. `stopAudio` already clears the deck (`+Playback.swift:256-259`) and tears down Pure.
- The bridge executes a transport op whatever its epoch.
- `isPlaying` is the only state the VM has.

**Remedy (S):**
- Number the stop or pause synchronously in `pause()` / `stopPlayback()`.
- Drop the redundant `setNextTrack(nil)`.
- In the bridge, drop any start, stop or seek whose epoch is older than the newest it has begun. This is the SFB generation idiom applied to commands.
- Add a VM `transportState` (`starting / playing / pausing / paused / stopped`) set synchronously, so that Pause and Next during a start act on the start.

**Effort / risk:** S–M, low–medium risk. This is the reducer that ARCH-1 / VM-2 propose.

### P4-3: Shuffle is a with-replacement random walk, not a permutation. SIGNIFICANT (N1, N2, N21)

**Evidence:**
- A 5-track queue with shuffle on and repeat off played **41 tracks before the 40-play cap**, 36 of them repeats.
- 10 tracks: 0/2000 passes end; a mean of 26.8 plays to hear every track.
- Previous goes back only 27–38 / 200 times.
- The "Repeat off" control is therefore ignored under shuffle.
- **Spec:**
  - VLC `randomizer.c:42-68`: no item twice per cycle; "prev" walks the history; loop off = one cycle, then stop.
  - Spotify: Fisher-Yates.
  - foobar2000 "Shuffle (tracks)" (second-hand, via forum posts quoting the FAQ).

**Root cause:** `nextIndex` draws `uniformRandomExcluding` each time and keeps no order. The picker itself is correct (N3).

**Remedy:**
- Keep a per-queue shuffle order of slot ids, built by on-demand Fisher-Yates (VLC's incremental form, which survives inserts and removals), plus a history cursor.
- Next and Previous move the cursor. Repeat-off ends after the last; repeat-all reshuffles each cycle.
- `PlaybackOrder.onDeck` and `appendArmIndex` then read the order.

**Effort / risk:** M, low risk (a pure Kit type, testable). Optional later: Spotify-style artist spreading.

### P4-4: The cached on-deck pick goes stale under linear order. SIGNIFICANT (N18, N4)

**Evidence:**
- **REORDER-DRAG-NEXT:** dragging a song under the playing one makes it **never play** (both paths).
- **REORDER-LINEAR:** `[t3,t0*,t2,t1]` plays t0, t1, then ends; t2 is skipped.
- **APPEND:**
  - repeat-all on the last song: the appended song waits a full cycle;
  - shuffle with one track: the queue stops after the current song.
- Everything stays id-stable; the result is still wrong.

**Root cause:**
- `pendingNextIndex` is a cached `next(current)`.
- `movePlaylistItems` re-anchors it by id (deliberately, `+Playlist.swift:10-15`).
- `appendArmIndex` leaves it alone except at the linear end.
- Under linear order, a queue edit changes what "next" means.

**Remedy:**
- After any queue edit while playing, recompute `next` under the current order.
- Re-arm if it differs, except when a shuffle pick or a Play Next override stands.
- This is one rule in place of three special cases (VLC computes next on demand).

**Effort / risk:** S, low risk. Re-arming on Pure needs the P4-1 replace-arm first.

### P4-5: `playNextNow` assumes no duplicates. LOCAL (N6)

- **Evidence:** 419–443 / 20k cases. Re-clicking the playing song, when an earlier duplicate exists, moves the duplicate instead of restarting.
- **Remedy:** pass the current **slot id**, and treat "clicked track == the playing slot's track" as a restart. Update the "forbids duplicate URLs" docs.
- **Effort:** S.

### P4-6: Play-through accrues wall time, not heard audio. LOCAL (N26)

- **Evidence:** 1.01 s per 1.0 s of silence; 0.56 of 0.6 s of a slow start. Wrong-song states (P4-1) also credit the wrong song.
- **Remedy:**
  - Short term: accrue only when the current-epoch snapshot's position advanced since the last tick, with `delta = min(wall, Δposition)`.
  - Structural: engine-side heard-frame accounting (Cog `scrobbleListened`, ARCH-1).
- **Effort:** S / M.

### P4-7: `pendingNextIndex = nil` both suppresses and means "end of queue". LOCAL (N14)

- **Evidence:** PAUSE-NEAR-END. A Pause during the last tick of a song whose next needs a reconfigure becomes a stop: the resume point is dropped, the play is counted, and Play starts from 0:00.
- **Remedy:** gate the tick on the transport state (P4-2), not on a nil index.
- **Effort:** S.

### P4-8: Frecency edges. LOCAL / QUESTIONABLE (N27, N29)

- **N29:** add a v4 backfill, `frecency_score = 1, frecency_rank = last_played WHERE play_count > 0 AND frecency_rank IS NULL`. This places songs played before v4 by recency. Effort S.
- **N27:** a mis-stamped future play dominates Recently-Played for years.
  - Option: decay from `max(lastPlayed, now)` and clamp `now` to `max(now, lastPlayed)` when writing. That stops the over-decay after the clock is set back.
  - A future stamp cannot be detected without a trusted clock, so the rest is a product call. Recommendation: accept, and document.

---

## 5. Existing tests: proof or mirror?

- **Kit tests are spec examples.** VM-QA, VM-PO, VM-QI, VM-QR, VM-RP, VM-SR, VM-TS and NP are adequate for the pure rules they cover.
- **Missing from them:**
  - uniformity (VM-QA-08 checks range only);
  - duplicates in VM-QI;
  - any test of the **contract with the engine**.
- **App-target transport logic is tested through `MockAdvanceController`, a hand mirror.**
  - It cannot express the Pure refusal, the transitional sample, the count domains, or command ordering, so every defect class here passes it.
  - The QueueOps mirror still dedupes, so it asserts retired behaviour.
- **VLS frecency checks partly derive their expected values from the production function.** My brute-force oracle supplies the independent proof.
- **Recommendation:** land E1 (real VM sources + a bridge-semantics engine model) as a gate target, and replace the mirror tests with it. Land E2's property tests.

## 6. Agreement with earlier evidence (read after forming my view)

- **G break-it B6** (re-arm on a shuffle / repeat change) is what added `rearmOnDeck`. Its fake engine logged arms (replace), so the fix was verified on semantics Pure does not have. That is how D41 shipped.
- **Main-thread audit §4** ("a stalled tick counts as heard"): I agree, and the problem is wider: slow starts and pre-interrupt silence count too.
- **Ledger** "shuffle on + repeat off never ends": confirmed. It is also not a permutation, and Previous has no history.
- **P3a D41:** agree, and extended (§1). **P3b D41:** right about the seam, but it did not test the arm contract.
- **ARCH-1:** confirmed by measurement (§2).
