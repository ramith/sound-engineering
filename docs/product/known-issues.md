# Known Issues

Tracked defects surfaced by tests/review that are not yet fixed. Each entry names the guarding test (or the
red test on a reference branch) where one exists, the place in the code, and where the fix is planned.

> **Reconciled to the code on 2026-10-13 (product council, against `main` at a206107), and re-checked on 2026-10-14
> against `7761693`, after the R1 blocker fixes (PR #88, #89).** R1 shipped as **v1.0.0-alpha** on 2026-10-14 (tag on
> f098821, [release](https://github.com/ramith/sound-engineering/releases/tag/v1.0.0-alpha)). Every OPEN entry below
> was re-checked in the source after PR #85 (Sprint G), PR #86 (the disconnect-freeze fix) and PR #88; items those PRs
> fixed are listed under **Closed**. This page is the open list the [R1 release notes](../releases/v1.0.0-alpha.md)
> point to.
>
> **Scheduled 2026-10-14** by the founder's decisions on the council ([report](../reviews/2026-10-council/README.md),
> [roadmap](roadmap.md#the-post-r1-plan-council-2026-10-14)). The council's user-facing findings that had no entry
> here are now listed too, under [Found by the 2026-10 council](#found-by-the-2026-10-council); each names its
> register row (C-xx, [`stage5-architect.md` §1](../reviews/2026-10-council/working/stage5-architect.md#1-finding-register)).
>
> - **Severity:** **HIGH** = wrong audio, a stuck state, or user data lost; **MEDIUM** = visibly wrong behaviour that
>   has a workaround; **LOW** = rare, cosmetic or wording; **internal** = a developer-only follow-up.
> - **Scheduled:** **R1.1-A** / **R1.1-B** (the two halves of R1.1), the **Engine sprint**, a later roadmap sprint,
>   **pool** (accepted, not scheduled; it rides with the next change that touches its code) or **parked** (waits for
>   hardware, FD-5).
> - **Forward link:** the [backlog](backlog.md) story that will close the issue. Most post-R1 defects sit in the
>   backlog's **Post-R1 fix pool** (US-R1F-01…16).
> - **Sources:** the Sprint G break-it reports ([library](../sprints/s10-8-g-breakit-library.md),
>   [playback / shell](../sprints/s10-8-g-breakit-playback-shell.md)), the "Logged post-R1" lists in the
>   [sweep ledger](../sprints/s10-8-sweep-ledger.md), the freeze evidence in
>   [main-thread-stall-2026-10](../architecture/evidence/main-thread-stall-2026-10/README.md), and the
>   [2026-10 council](../reviews/2026-10-council/README.md).
> - **No `withKnownIssue` guards exist any more** (zero uses in `Tests/`); the old header promise that each entry is
>   guarded by one no longer holds. Where a red test exists, it lives on a reference branch, named in the entry.

---

## Open issues at a glance

| ID | Issue | Severity | Scheduled | Forward link |
|---|---|---|---|---|
| KI-LIB-01 | "Remove Missing…" deletes entries whose drive is merely unplugged | HIGH | R1.1-A | US-R1F-03 |
| KI-MC-01 | A 5.1 / 7.1 file on a stereo output plays only its front left and right: centre, LFE and surrounds are dropped | HIGH | R1.1-B (BS.775 fold-down, FD-9); S18 replaces it | US-R1F-08 |
| KI-MC-02 | Channel roles come from positions, not the file's labels: an ALAC / AAC 5.1 file plays its centre on the left; 3-, 4-, 5- and 7-channel files fall back to stereo | HIGH | R1.1-B | US-R1F-08 |
| KI-PB-18 | Dragging the scrubber to the end of a track that isn't 48 kHz stops playback for good | HIGH | R1.1-A | US-R1F-11 |
| KI-GAP-05 | An Enhanced gapless join to a file with a different channel count drops channels | HIGH | Engine sprint | US-R1F-02 |
| KI-PB-02 | Repeat turned off mid-song moves on, but with a gap | MEDIUM | Engine sprint | US-R1F-02 |
| KI-PB-03 | Shuffle on + Repeat off never ends the queue | MEDIUM | R1.1-B (shuffle as a permutation) | US-R1F-01 |
| KI-PB-04 | Play / Space during a slow start restarts the song instead of pausing | MEDIUM | R1.1-A | US-R1F-01 |
| KI-PB-05 | Pure on / off does not apply at a gapless seam, though Settings says it does | MEDIUM | R1.1-A (Pure honesty) | US-R1F-13 |
| KI-PB-06 | After a relaunch the restored song shows `--:--` and its scrubber is dead until Play | MEDIUM | R1.1-A | US-R1F-01 |
| KI-PB-08 | Clicking the paused current queue row restarts it from 0:00 | MEDIUM | R1.1-A | US-R1F-01 |
| KI-PB-10 | Add to Queue onto an empty queue leaves Play / Space disabled | MEDIUM | R1.1-A | US-R1F-01 |
| KI-PB-11 | "Restore previous queue" restores the wrong queue | MEDIUM | pool | US-R1F-04 |
| KI-PB-12 | A single click on a playlist row replaces the queue and plays | MEDIUM | pool | US-R1F-04 |
| KI-PB-19 | Stop-then-Play or Pause-then-Play in quick succession can show "Playing" over silence | MEDIUM | R1.1-A | US-R1F-01 |
| KI-PB-20 | A queued song can be skipped: one dragged in under the current song, or appended while a start primes | MEDIUM | R1.1-A | US-R1F-01 |
| KI-PB-21 | A crash or force-quit loses your place in the queue | MEDIUM | R1.1-B (atomic queue restore) | US-R1F-01 |
| KI-GAP-01 | A short gap at the seam between 48 kHz tracks | MEDIUM | Engine sprint | US-R1F-02 |
| KI-GAP-02 | On resampled seams the title and track B's gain switch ~0.4 s early | MEDIUM | Engine sprint | US-R1F-02 |
| KI-GAP-04 | A click at each join between resampled tracks (44.1 / 96 kHz albums) | MEDIUM | Engine sprint | US-R1F-02 |
| KI-SND-01 | A fresh launch plays processed sound: Intensity 20 % turns on a session-long leveller, a +2 dB blend and the limiter | MEDIUM | R1.1-A (FD-2) | US-R1F-09 |
| KI-SND-02 | Enhanced sample-rate conversion rolls off the treble (−8.25 dB at 20 kHz) and lets aliases through | MEDIUM | R1.1-A | US-R1F-11 |
| KI-SND-03 | The limiter's fast release never runs: one loud hit ducks the music for about a second | MEDIUM | R1.1-A | US-R1F-12 |
| KI-SND-04 | Crossfeed notches the centre (−4 to −6 dB near 1 kHz); its "Default" preset is mislabelled | MEDIUM | R1.1-A | US-R1F-12 |
| KI-SET-01 | Pure, device pin, Master Gain, Intensity and crossfeed reset at every launch | MEDIUM | R1.1-A (FD-2) | US-R1F-05 |
| KI-SET-02 | A Master Gain cut in Enhanced does not carry into Pure (Pure plays at device volume) | MEDIUM | R1.1-A (FD-2) | US-R1F-05 |
| KI-EQ-01 | Unpinning an output overwrites the shared EQ, with no undo | MEDIUM | pool (first candidate) | US-R1F-06 |
| DEV-1 | The chosen output device is forgotten when the app quits | MEDIUM | R1.1-A (FD-2) | US-R1F-05 |
| KI-DEV-01 | Crossfeed is unavailable on wired headphones in the Mac's own jack | MEDIUM | R1.1-A (with the crossfeed fix) | US-R1F-12, US-R1F-06 |
| KI-DEV-03 | An Enhanced start just after a device connects can end silent or on the wrong device | MEDIUM | Engine sprint | EP-PLAYENGINE |
| KI-LIB-02 | Paused / failed folders are invisible; an emptied folder keeps its songs | MEDIUM | R1.1-A | US-R1F-03 |
| LIB-VOL-1 | A paused folder on a replaced or UUID-less drive stays paused; re-adding it loses play stats | MEDIUM | R1.1-B ("Use this drive") | US-R1F-03 |
| KI-LIB-03 | A failed first metadata pass leaves "No Music Yet", with no retry | MEDIUM | pool | US-R1F-03 |
| KI-LIB-04 | Dragging a multi-selection onto a playlist adds one song | MEDIUM | pool | US-R1F-04 |
| KI-LIB-11 | Search splits Sinhala words at vowel signs; text stored decomposed (NFD) can't be found | MEDIUM | R1.1-A (tokenizer + NFC); R1.1-B (one rule) | US-R1F-14 |
| KI-SEC-01 | If FFmpeg is installed, it parses every FLAC / Ogg / Opus file first during the scan, loaded from a user-writable path | MEDIUM | R1.1-A (opt-in, FD-3) | US-R1F-16 |
| KI-PURE-01 | On Pure, each pause and resume switches the DAC's sample rate twice (pause is a device teardown) — unverified on hardware | MEDIUM | parked (FD-5) | US-ENG-07 |
| KI-PB-07 | Next / Previous while paused keep the old song's duration | LOW | R1.1-A | US-R1F-01 |
| KI-PB-09 | A double-click on a queue row starts the song twice | LOW | R1.1-A | US-R1F-01 |
| KI-PB-13 | Two quick tile Plays can land out of order | LOW | pool | US-R1F-04 |
| KI-PB-14 | Stalled ticks count as heard time (play counts) | LOW | pool | US-R1F-01 |
| KI-PB-15 | Recent says "Nothing Played Yet" when the store is not ready or the read failed | LOW | pool | US-R1F-04 |
| KI-PB-16 | A change of the next song in the last moments before a seam can still play the old pick (D41 residual A2 / A2′) | LOW | Engine sprint (seam identity) | US-R1F-01 |
| KI-PB-17 | A scrub back into a track that has already ended (nothing armed) is lost | LOW | Engine sprint (seam identity) | US-R1F-01 |
| KI-GAP-03 | A narrow false seam on a Pure → Enhanced restart | LOW | Engine sprint | US-R1F-02 |
| ENH-001 | Short-track auto-advance is a reconfigure gap, not a seamless seam | LOW | Engine sprint | US-R1F-02 |
| ENH-002 | The UI loudness readout is L/R-only on a >2-channel output | LOW | pool | US-R1F-07 |
| KI-SET-03 | A device volume lowered on Pure stays lowered on Enhanced; the readout doesn't show it | LOW | pool | US-R1F-05 |
| KI-EQ-02 | Esc during a graph drag re-announces "Bring back edits" | LOW | pool | US-R1F-06 |
| KI-EQ-03 | Stacked-shadow darkening on EQ / Settings cards (dark + Reduce Transparency / Increase Contrast) — unverified | LOW | pool | US-R1F-06 |
| KI-DEV-02 | HDMI / DisplayPort outputs read "(Unknown)" | LOW | pool | US-R1F-06 |
| KI-LIB-05 | `.opus` / `.oga` files are playable but never scanned | LOW | R1.1-A (was S11) | US-R1F-16 |
| KI-LIB-06 | Genres split on "/" ("Singer/Songwriter" → two tiles) | LOW | pool | US-R1F-04 |
| KI-LIB-07 | Case / Unicode variants split artist and genre tiles | LOW | pool | US-R1F-04 |
| KI-LIB-08 | Sorting Songs by Album orders each album's tracks by scan order | LOW | pool | US-R1F-04 |
| KI-LIB-09 | Two Filter semantics (Songs: token prefix; grids: substring) | LOW | R1.1-B (one search rule) | US-R1F-14 |
| KI-LIB-10 | An empty playlist says "No Tracks Yet" (the app says "songs") | LOW | pool | US-R1F-04 |
| KI-UI-01 | VoiceOver keeps the app fairly busy while a song plays (release notes; not verifiable from code) | LOW | R1.1-A | US-R1F-15 |
| KI-UI-02 | The spectrum analyser reads about 4 dB high; two 20 Hz timers run while paused or in the menu bar | LOW | R1.1-A | US-R1F-15 |
| KI-UI-03 | The loudness "Integrated" readout spans the whole session, not the track | LOW | R1.1-A | US-R1F-12 |
| KI-ENG-01 | `SpectrumDoubleBuffer` data race (TSan) | internal | R1.1-A | US-R1F-15 |
| KI-ENG-02 | The main-thread stall self-test lacks the breaker's two extra modes and the 5 ms bound | internal | pool | US-R1F-07 |
| KI-ENG-03 | A stale comment names the removed `loudnessMeter` field | internal | R1.1-A (hygiene) | US-R1F-07 |
| KI-ENG-04 | The `eq-light-folded` picture sheet flakes in the renderer | internal | pool | US-R1F-07 |

**Known limitations (by design or not yet built — not defects):** see [the last section](#known-limitations-by-design-or-not-yet-built).

---

## Playback and transport

*(KI-PB-01 — Pure ignored a changed next track — was fixed by PR #88 (council D41); see [Closed](#fixed-by-pr-88--the-r1-blockers-2026-10-14). Its residual windows are KI-PB-16 and KI-PB-17.)*

### KI-PB-02 — Repeat turned off mid-song moves on, but with a gap

**Status:** OPEN · **Severity:** MEDIUM · **Source:** sweep ledger, "Logged post-R1" (Sprint G) · **Scheduled (2026-10-14):** Engine sprint · **Forward:** US-R1F-02.

The view model re-arms correctly (`AudioViewModel+Playlist.swift:150-159` → `armOnDeck`). The seam is not re-armed
seamlessly: on 48 kHz files the gap is most likely KI-GAP-01. ~~On Pure the re-arm is refused (KI-PB-01).~~ *(Since PR
#88, D41: on Pure the re-arm is applied — the old pick comes off at once and the new one arms when its file opens; a
pick still opening when the song ends, or one of another rate or width, gives a short gap and the right song.)*

### KI-PB-03 — Shuffle on + Repeat off never ends the queue

**Status:** OPEN · **Severity:** MEDIUM · **Source:** sweep ledger, "Logged post-R1" · **Scheduled (2026-10-14):** R1.1-B (shuffle as a permutation with history, council C-16 — it also stops repeats and a random Previous) · **Forward:** US-R1F-01.

`QueueAdvance.nextIndex` returns a random pick before the end-of-queue check, and nothing records which songs have
played (`Sources/PlaybackQueueKit/QueueAdvance.swift:38-45`). With Shuffle on and Repeat off, random songs repeat
forever.

### KI-PB-04 — Play / Space during a slow start restarts the song instead of pausing

**Status:** OPEN · **Severity:** MEDIUM · **Source:** breaker B post-R1 #1 (G-RACE-1) + freeze "Logged post-R1"
(fast play-then-pause) · **Scheduled (2026-10-14):** R1.1-A (a starting / pausing state, council C-15) · **Forward:** US-R1F-01.

`isPlaying` becomes true only after `engine.startAudio` returns and the start's on-deck prime settles
(`AudioViewModel+Playback.swift:74`); `pause()` guards
on it (`AudioViewModel+Transport.swift:46`) and the toggle calls `play()` again (`:57-62`). There is no "start in
flight" state. PR #86 (86a1cbe) fixed only the Stop case (`transportStopEpoch`); `rev-verify.md` records the rest as
still lost.

### KI-PB-05 — Pure on / off does not apply at a gapless seam, though Settings says it does

**Status:** OPEN · **Severity:** MEDIUM · **Source:** breaker B post-R1 #3 · **Scheduled (2026-10-14):** R1.1-A (Pure honesty) · **Forward:** ~~US-R1F-01~~ US-R1F-13.

The next track is armed on the path that is playing (`AudioEngineBridge+Gapless.swift:67-71`, the path read when the request is admitted); `pureModeEnabled`'s
`didSet` only logs (`AudioViewModel.swift:106-108`). Settings still says "Starts with the next track."
(`UI/Settings/PureModeSettingsSection.swift:18`, `UI/Settings/SignalPathStatus.swift:38`). The switch takes effect
only at a manual start or a rate-change reconfigure.

### KI-PB-06 — After a relaunch the restored song shows `--:--` and its scrubber is dead

**Status:** OPEN · **Severity:** MEDIUM · **Source:** breaker B post-R1 #6 · **Scheduled (2026-10-14):** R1.1-A · **Forward:** US-R1F-01.

`restoreCursor` sets the selection, resume point and position but never `duration`
(`AudioViewModel+QueueHydration.swift:64-78`); the footer and scrubber gate on `duration > 0`
(`UI/Shell/NowPlayingBar.swift:242`, `:294`). Control Center can't seek either, until Play.

### KI-PB-07 — Next / Previous while paused keep the old song's duration

**Status:** OPEN · **Severity:** LOW · **Source:** sweep ledger, "Logged post-R1" · **Scheduled (2026-10-14):** R1.1-A · **Forward:** US-R1F-01.

While paused, Next / Previous only move `selectedTrackIndex` (`AudioViewModel+Transport.swift:73-95`);
`refreshDuration` runs only in `startPlayback` (`AudioViewModel+Playback.swift:37`).

### KI-PB-08 — Clicking the paused current queue row restarts it from 0:00

**Status:** OPEN · **Severity:** MEDIUM · **Source:** breaker B post-R1 #10 · **Scheduled (2026-10-14):** R1.1-A · **Forward:** US-R1F-01.

The row tap guards only on `isPlaying` (`UI/Playlist/PlaylistItemList.swift:173-174`) and calls `playTrack`, which
clears the resume point (`AudioViewModel+Transport.swift:12`). Return on the same row resumes (`activateCursor`).

### KI-PB-09 — A double-click on a queue row starts the song twice

**Status:** OPEN · **Severity:** LOW · **Source:** sweep ledger, "Logged post-R1" · **Scheduled (2026-10-14):** R1.1-A · **Forward:** US-R1F-01.

Same guard as KI-PB-08 (`PlaylistItemList.swift:165-175`): the second click lands before `isPlaying` flips, so a second
start is requested (and a second play is logged).

### KI-PB-10 — Add to Queue onto an empty queue leaves Play / Space disabled

**Status:** OPEN · **Severity:** MEDIUM · **Source:** breaker B post-R1 #9 · **Scheduled (2026-10-14):** R1.1-A · **Forward:** US-R1F-01.

`appendToQueue` never selects a track (`AudioViewModel+Queue.swift:176-189`); Controls ▸ Play / Space are disabled on
`selectedTrackIndex == nil` (`AdaptiveSound.swift:167`) and the footer on `track != nil`
(`UI/Shell/NowPlayingBar.swift:31`, `:197`), though `play()` would start track 1. Clicking a queue row works.

### KI-PB-11 — "Restore previous queue" restores the wrong queue

**Status:** OPEN · **Severity:** MEDIUM · **Source:** breaker A post-R1 #4 · **Scheduled (2026-10-14):** pool · **Forward:** US-R1F-04.

`QueueRestorePoint.afterReplace` treats any replace of an untouched installed queue as a double-click and keeps the
older snapshot (`Sources/PlaybackQueueKit/QueueRestorePoint.swift:36-37`; pinned by VM-QR-02). Play album A, then B,
then "Restore previous queue" brings back the queue from before A (or clears the queue if that was empty).

### KI-PB-12 — A single click on a playlist row replaces the queue and plays

**Status:** OPEN · **Severity:** MEDIUM · **Source:** breaker A post-R1 #9 · **Scheduled (2026-10-14):** pool (a council default: a single click selects, a double-click plays, everywhere) · **Forward:** US-R1F-04.

`PlaylistDetailView.swift:241-244` plays on a tap, while Songs and the album / artist / genre pages select on click and
play on double-click. Selecting a playlist row to move or remove it starts it playing.

### KI-PB-13 — Two quick tile Plays can land out of order

**Status:** OPEN · **Severity:** LOW · **Source:** breaker A post-R1 #12 · **Scheduled (2026-10-14):** pool · **Forward:** US-R1F-04.

`BrowseTile` starts an async `facetRows` read per click (`UI/Library/BrowseTile.swift:111-112` →
`LibraryBrowseModel+Facets.swift:153-155`) with no latest-wins check.

### KI-PB-14 — Stalled ticks count as heard time

**Status:** OPEN · **Severity:** LOW · **Source:** freeze "Logged post-R1" · **Scheduled (2026-10-14):** pool (council C-19; the Engine sprint's heard-time events give the full fix) · **Forward:** US-R1F-01.

`accruePlayThrough` adds wall-clock time whenever `isPlaying && duration > 0`
(`AudioViewModel+PlayTracking.swift:18-19`), with no check that audio is rendering; a device stall can inflate play
counts and Recently Played.

### KI-PB-15 — Recent says "Nothing Played Yet" when the store is not ready or the read failed

**Status:** OPEN · **Severity:** LOW · **Source:** breaker B post-R1 #8 · **Scheduled (2026-10-14):** pool · **Forward:** US-R1F-04.

`UI/Playlist/QueueHistoryList.swift:36` never reads `historyState`, and nothing reloads it when the store becomes ready
(`LibraryBrowseModel+History.swift:12`).

### KI-PB-16 — A change of the next song in the last moments before a seam can still play the old pick

**Status:** OPEN (the documented residual of the D41 fix, PR #88) · **Severity:** LOW (a window of tens of
milliseconds) · **Scheduled (2026-10-14):** Engine sprint (seam identity, council C-14) · **Forward:** US-R1F-01 (follow-up F1, *seam identity*).

A seam reports a count, not which track it played, so two windows remain (architecture §2.5, "What plays next"):
**A2** — a request not yet admitted on `engineQueue` when the track ends (the rest of the main-thread turn, one hop and
any queue backlog) finds the old pick still armed: the old pick plays while the new one is shown; **A2′** — an edit made
after a seam but before the view model's next tick (up to 50 ms, plus the 33 ms clock) is shown as playing while the
pick the seam took plays. Pinned by the `LATE-REQUEST` scenario (`Tests/AdaptiveSoundTests/OnDeckContractTests.swift`);
the explorer counts both windows apart (`OnDeckExplorerTests.swift`).

### KI-PB-17 — A scrub back into a track that has already ended is lost

**Status:** OPEN (named in the D41 contract, PR #88) · **Severity:** LOW · **Scheduled (2026-10-14):** Engine sprint (seam identity, council C-14) · **Forward:** US-R1F-01 (with the transport
state-machine work).

`ended` stays latched across a seek, so a scrub back into a track that already ended with nothing armed is lost: the
next tick starts the next track (architecture §2.5, "What plays next").

---

## Gapless seams

### KI-GAP-01 — A short gap at the seam between 48 kHz tracks

**Status:** OPEN · **Severity:** MEDIUM · **Source:** freeze "Logged post-R1"; R1 release notes · **Scheduled (2026-10-14):** Engine sprint (council C-21) · **Forward:** US-R1F-02.

The 48 kHz passthrough schedules the next file only after track A has played back
(`AudioEngineBridge+GaplessRoll.swift:68-90`, `scheduleFile(… .dataPlayedBack)` at `:207-213`), so 48 kHz albums have a
short silence between tracks.

### KI-GAP-02 — On resampled seams the title and track B's gain switch ~0.4 s early

**Status:** OPEN · **Severity:** MEDIUM · **Source:** freeze "Logged post-R1" (playhead latency compensation and seam
domains) · **Scheduled (2026-10-14):** Engine sprint (council C-23) · **Forward:** US-R1F-02.

The resampler seam bumps the transition count when B is primed, i.e. when A's decode reaches end-of-file
(`AudioEngineBridge+GaplessRoll.swift:256-259` → `+Gapless.swift:184-186`), not when B becomes audible; no
presentation latency is applied anywhere. On 44.1 kHz music the title and B's loudness gain switch early, and the
scrubber runs ahead of what is heard (more on Bluetooth).

### KI-GAP-03 — A narrow false seam on a Pure → Enhanced restart

**Status:** OPEN · **Severity:** LOW · **Source:** freeze "Logged post-R1" · **Scheduled (2026-10-14):** Engine sprint · **Forward:** US-R1F-02.

The Enhanced seam count is never reset (`AudioEngineBridge.swift:179`); the view model's baseline is reset only after
`startAudio` returns (`AudioEngineBridge+Playback.swift:113`). In a narrow window after a Pure → Enhanced fallback the
tick can see a seam that did not happen.

### ENH-001 — Short-track auto-advance is a reconfigure gap, not a seamless seam

**Status:** OPEN (enhancement, low priority) · **Scheduled (2026-10-14):** Engine sprint (a 2-deep on-deck queue) · **Forward:** US-R1F-02.

*(KI-001 — "the VM stops mid-playlist on short tracks" — was **RESOLVED 2026-07-02**: analysis showed the VM already continues via `tickSpectrum()`'s `playbackEnded → advance to pendingNextIndex` branch; the stale `VM-AA-RTR-1` assertion was corrected to the continue behavior. Founder's continue/advance decision is satisfied. The full triage/panel narration is in git.)*

The short-track advance is a fresh-start reconfigure **gap**, not a gapless seam. Making it seamless for arbitrarily-short tracks needs an engine-side **2-deep on-deck queue** — a single on-deck slot can't arm track C until track B is current at the seam, and B may be shorter than the arm latency + the 20 Hz poll interval. Scheduled against the gapless backlog (US-PLAY-08 lineage); low priority (only tiny tracks; fallback is a brief gap, not a stop). ~~Guarded by `VM-AA-RTR-1` (`withKnownIssue` — fails when fixed, prompting a proper assertion).~~ *(Corrected 2026-10-13: `VM-AA-RTR-1` still exists — `Tests/AudioViewModelTests/AutoAdvanceReconfigureGapTests.swift:88` — but `withKnownIssue` was dropped in c63ba7f; it now asserts the fresh-start advance against mocks, so nothing fails when the seamless fix lands. The engine still has one on-deck slot: `onDeckURL`, `AudioEngineBridge.swift:174`.)*

---

## Multichannel

### KI-MC-01 — A 5.1 / 7.1 file on a stereo output drops centre, LFE and surrounds

**Status:** OPEN · **Severity:** HIGH (wrong audio: on most 5.1 music the centre carries the lead vocal) · **Source:**
the council's architecture reconciliation (2026-10-13), re-verified here · **Scheduled (2026-10-14):** R1.1-B ·
**Forward:** S18 replaces the interim
truncation with the binaural fold ([S4 design](../sprints/05-sprint-5b-s4-binaural-design.md)); ~~an interim fix (the S4
design's Apple `AVAudioEnvironmentNode` fold pulled forward, or a standard fold-down) is a founder decision~~ → US-R1F-08.
*(Decided 2026-10-14, FD-9: the interim is the standard **ITU-R BS.775** fold-down, at the device boundary, after the
channel-order fix (KI-MC-02) and with a safety ceiling after it (the limiter sits before the spatial stage today —
council C-43). S18's binaural render replaces it in the same slot.)*

The Enhanced graph processes at the file's width N and renders to the device width M = min(N, device) at the spatial
AU (`AudioFormatKit/MultichannelFormat.swift:89-104`, wired in `AudioEngineBridge+Graph.swift:63-73`). When M < N the
kernel runs a **channel-truncation stub**: it copies the first M input channels and discards the rest
(`AudioDSP/Spatial/SpatialRenderKernel.cpp:59-89`, `routeBinauralStub`, "THIS IS NOT THE FINAL BINAURAL BEHAVIOUR").
With the MPEG 5.1 order L R C LFE Ls Rs (`MultichannelFormat.swift:53-54`), a stereo output keeps L and R only. The
"no naive downmix" mandate is why it isn't a matrix fold — but silence for four channels is worse than a naive fold.
The R1 release notes advertise "per-channel before / after spectrum, up to 7.1" without this caveat.

## Settings and levels

### KI-SET-01 — Pure, device pin, Master Gain, Intensity and crossfeed reset at every launch

**Status:** OPEN · **Severity:** MEDIUM (Master Gain and Pure); LOW (the rest) · **Source:** breaker B post-R1 #4 ·
**Scheduled (2026-10-14):** R1.1-A (FD-2: remember the listener's settings; Master Gain never restored louder — council C-102) · **Forward:** US-R1F-05.

None has a defaults key: `pureModeEnabled = false` (`AudioViewModel.swift:106`), the pin `= true` (`:116`),
`intensity = 0.20` (`:142`), `crossfeedEnabled = false` (`:153`), strength (`:161`), and Master Gain `= unity`
(`:195`, commented "Not kept across launches (a post-R1 item)"). Only the EQ, the queue cursor (incl. shuffle / repeat),
the Songs columns and the Tone-card fold persist. Someone who turned Master Gain down hears 0 dB after a relaunch. The
output device the user chose is not kept either (DEV-1).

### KI-SET-02 — A Master Gain cut in Enhanced does not carry into Pure

**Status:** OPEN (by design today; close to hearing safety) · **Severity:** MEDIUM · **Source:** sweep ledger,
"Logged post-R1" ("an Enhanced trim doesn't carry into Pure") · **Scheduled (2026-10-14):** R1.1-A (FD-2) · **Forward:** US-R1F-05.

On Pure the slider shows and sets the device's own volume, and the app gain is not applied
(`AudioViewModel+MasterGain.swift:9-17`). Turning Master Gain down in Enhanced, then switching to Pure, plays at the
device's volume, which can be much louder.

### KI-SET-03 — A device volume lowered on Pure stays lowered on Enhanced

**Status:** OPEN (residual of breaker B post-R1 #5, partly fixed by 124178d in PR #85) · **Severity:** LOW ·
**Scheduled (2026-10-14):** pool · **Forward:** US-R1F-05.

Every Enhanced start re-applies the app's gain (`AudioEngineBridge+Playback.swift:110`), so the old double-attenuation
and wrong readout are gone. The device volume set on Pure is the macOS output volume, and the Enhanced readout shows
only the app's gain, not it.

---

## EQ

### KI-EQ-01 — Unpinning an output overwrites the shared EQ, with no undo

**Status:** OPEN · **Severity:** MEDIUM · **Source:** breaker B post-R1 #7 · **Scheduled (2026-10-14):** pool (first candidate: it destroys user edits) · **Forward:** US-R1F-06.

`EQStore.unpin` sets `shared = slot.state` (`Sources/EQEditKit/EQStore.swift:112-115`; documented as intended at
`:109-111`, ui-plan §3.3); `togglePin` offers no Bring back (`EQSession+Slots.swift:76`). Every other output silently
loses its (possibly edited) EQ.

### KI-EQ-02 — Esc during a graph drag re-announces "Bring back edits"

**Status:** OPEN · **Severity:** LOW · **Source:** breaker B post-R1 #11 · **Scheduled (2026-10-14):** pool · **Forward:** US-R1F-06.

Esc restores the offer (`EQSession+Stroke.swift:71`), and `UI/EQ/EQBringBackMessage.swift:36` treats nil → offer as
new: the 6 s timer restarts and VoiceOver says "Switched to …" again.

### KI-EQ-03 — Stacked-shadow darkening on EQ / Settings cards (unverified)

**Status:** OPEN (needs a visual check; cannot be judged from code) · **Severity:** LOW · **Source:** sweep ledger,
"Logged post-R1" · **Scheduled (2026-10-14):** pool · **Forward:** US-R1F-06.

Under dark appearance with Reduce Transparency or Increase Contrast, the EQ and Settings cards may darken where shadows
stack.

---

## Output devices

### KI-DEV-01 — Crossfeed is unavailable on wired headphones in the Mac's own jack

**Status:** OPEN · **Severity:** MEDIUM · **Source:** product council, code reading 2026-10-13 · **Scheduled (2026-10-14):** R1.1-A (headphones detected by data source, with the crossfeed fix — council C-42, C-30) · **Forward:** US-R1F-12, US-R1F-06
(and S13 device identification).

The headphone gate is "USB or wireless transport" (`AudioViewModel.swift:169-181`), and the device type comes from the
transport alone (`Sources/AudioDSP/CoreAudioDevice.cpp:326-343`). The Mac's headphone jack reports the built-in
transport, so wired headphones there are "not headphones": crossfeed is disabled with the "Connect headphones" hint.
The converse also holds: AirPlay speakers count as wireless headphones. The code comment names only the USB false
positive.

### KI-DEV-02 — HDMI / DisplayPort outputs read "(Unknown)"

**Status:** OPEN · **Severity:** LOW · **Source:** sweep ledger, "Logged post-R1" · **Scheduled (2026-10-14):** pool · **Forward:** US-R1F-06.

`classifyDeviceType` has no HDMI / DisplayPort case (`CoreAudioDevice.cpp:332-359`); the pill and Settings show
"<name> (Unknown)" (`Models/AudioDeviceModel.swift:86-88`).

### DEV-1 — The chosen output device is forgotten when the app quits

**Status:** OPEN (limitation; R1 ships with it) · **Severity:** MEDIUM · **Scheduled (2026-10-14):** R1.1-A (FD-2) · **Forward:** US-R1F-05 (with KI-SET-01).
Left by the N92 fix ("Return to headphones", R1).

Within a session the app remembers the output device the user picked (by UID) and returns to it
when it reconnects (`OutputDeviceSelection`). Nothing persists that pick, or the "Keep playback on
this device" switch, across launches. The device the app starts on is not a pick, so after a
relaunch nothing is chosen and the app follows the system default until the user picks again. So
if the user picked the speakers while their headphones were connected, then quit and relaunched,
the app plays wherever macOS sends the sound (the headphones) until they pick the speakers again.
Fix with the settings persistence work: store the chosen UID and the switch, and restore them at
launch. The in-session behaviour is guarded by `OutputDeviceReturnTests`,
`OutputDeviceChoiceTests` and `OutputDeviceRuleSpaceTests`.

### ENH-002 — UI loudness readout meter is L/R-only for >2-channel device output

**Status:** OPEN (enhancement; UI-only, low priority). Surfaced by the S6 full-team review (MC-1). Re-verified
2026-10-13: the tap still feeds `channels[0]` / `channels[1]` to `loudnessMeterAddStereo`
(`AudioEngineBridge+Graph.swift:170-173`). **Scheduled (2026-10-14):** pool · **Forward:** US-R1F-07.

The Now-Playing loudness meter (`AudioEngineBridge+Graph.installMixerTap` →
`loudnessMeterAddStereo`) measures only L/R of the mixer-output bus. It is **correct for the
common stereo device width** (M == 2 → L/R is every channel) and is a **UI readout only** — it does
**not** drive makeup gain. The audible loudness normalization is the DSP kernel's own
N-channel-weighted `LoudnessModule` (S1/S2), which is unaffected.

For a >2-channel **device** output the integrated LUFS shown reads slightly low (surround energy
unmeasured). A correct N-channel UI meter needs the device-width BS.1770-5 weights (surround ×1.41,
LFE excluded — the `LufsMeter` already supports this via `configureChannels` + `addNonInterleaved`)
configured once at tap install and all M planar channels fed in the tap. Deferred with the
multichannel-output path (the S4 binaural fold is deferred) rather than plumb channel-layout weights
into the RT tap for a path that is not yet primary.

---

## Library and playlists

### KI-LIB-01 — "Remove Missing…" deletes entries whose drive is merely unplugged

**Status:** OPEN · **Severity:** HIGH (irreversible playlist data loss, behind an explicit confirm the founder accepted in
Sprint E #12) · **Source:** breaker A post-R1 #13 · **Scheduled (2026-10-14):** R1.1-A (without a tombstone — FD-10) · **Forward:** US-R1F-03.

Availability is a file-existence check only (`PlaylistsModel.swift:265-269`); `missingEntryIDs` ignores whether the
song's music folder is paused / unreachable (`PlaylistsModel+DeadFiles.swift:33-34`). *(Not covered by R1's
sweep-evidence fix, PR #88, which guards the scanner's sweep, not this dialog.)* With the music drive unplugged a
playlist's songs show as missing, and the dialog ("files that are missing from disk will be removed. This can't be
undone.", `UI/Playlist/PlaylistRemoveMissingDialog.swift:21-22`) removes them for good.

### KI-LIB-02 — Paused / failed folders are invisible; an emptied folder keeps its songs

**Status:** OPEN (slightly improved by 95870a5, PR #85: launch now reconciles every folder and pauses an unreachable one)
· **Severity:** MEDIUM · **Source:** breaker A post-R1 #8 · **Scheduled (2026-10-14):** R1.1-A (council C-55) · **Forward:** US-R1F-03.

`reconcileState` / `lastReconcileError` (`LibraryModel.swift:118-120`) have no UI reader. Songs on an unplugged drive
look normal and fail only on play; a folder whose files were all deleted keeps listing them, because the empty-walk
guard refuses the sweep silently. There is no Rescan control. *(Since PR #88 a walk that is not evidence — the folder
unreachable, on another drive, unrecognized, read only in part, or empty — refuses its sweep (`SweepRefusal`, five
reasons) and pauses the folder silently, on the reconcile and on the add walk alike
(`LibraryModel+Reconcile.swift:153-154`, `:165-166`; `LibraryModel+Scan.swift:213-215`). Paused folders are now more
common and still invisible; see LIB-VOL-1.)*

### LIB-VOL-1 — A music folder is bound to its drive; a sweep needs evidence (R1 sweep-evidence fix)

**Status:** OPEN (accepted limitations) · **Severity:** MEDIUM · **Scheduled (2026-10-14):** R1.1-B ("Use this drive", council C-54) · **Forward:** US-R1F-03.

A folder is bound to its drive's volume UUID (the startup disk as itself, since its UUID changes with the Mac); one on a volume that reports no UUID (some network volumes; FAT32/exFAT report one on macOS 26) stays unbound and is walked only while some of its songs are where the library has them — so a folder all of whose files were moved or renamed at once while unbound (on such a volume, or between the v8 upgrade and its first walk) stays paused until it is removed and re-added; so does a folder whose drive is replaced by a different one with the same name (a new or reformatted "T7"); and a folder with a subfolder the app can never read never has its deleted songs swept (`LibraryStore+Roots`, `SweepRefusal`).

**Do not remove and re-add a paused folder as a workaround:** removing a folder deletes every song of it that no
playlist references, so re-adding it brings those songs back with new ids — their play counts, loved flags and
ratings are lost. A lossless "use this drive" action on a paused folder is on the council follow-up list (founder,
2026-10-14). Also narrow: the first walk after the v8 upgrade binds whatever drive is at the folder's path, so a
same-name *backup* drive mounted at that moment can be bound instead of the real one (found by the R1 break-it).

### KI-LIB-03 — A failed first metadata pass leaves "No Music Yet", with no retry

**Status:** OPEN · **Severity:** MEDIUM · **Source:** breaker A post-R1 #11 · **Scheduled (2026-10-14):** pool · **Forward:** US-R1F-03.

On failure the metadata pass clears its progress and reports the error, but bumps no `libraryRevision`
(`LibraryModel+Metadata.swift:37`, `:42-49`), so Songs keeps its first-run call to action while the rail lists the
folder. A relaunch's catch-up may retry the pending tags (not verified).

### KI-LIB-04 — Dragging a multi-selection onto a playlist adds one song

**Status:** OPEN · **Severity:** MEDIUM · **Source:** breaker A post-R1 #5 · **Scheduled (2026-10-14):** pool · **Forward:** US-R1F-04.

The drag payload is the row under the pointer (`UI/Library/SongRowInteraction.swift:33`,
`LibraryTrackDragItem(trackID:)`). The toast is honest ("Added 1 song"); the context menu's Add to Playlist takes the
whole selection.

### KI-LIB-05 — `.opus` / `.oga` files are playable but never scanned

**Status:** OPEN · **Severity:** LOW · **Source:** breaker A post-R1 #3 · **Scheduled (2026-10-14):** R1.1-A (Apple decodes Opus natively on macOS 26 — council R-19) · **Forward:** ~~S11 (format hardening)~~ US-R1F-16.

`LibraryScanner.supportedExtensions` (`Sources/LibraryScan/LibraryScanner.swift:50-52`) has no `opus` / `oga`, while the
decoder plays them through the optional FFmpeg fallback and the extractor reads their tags
(`MetadataExtractor.swift:78`). PR #85 (f69421d) added only `.aif`. The scan says nothing about skipped files.

### KI-LIB-06 — Genres split on "/"

**Status:** OPEN · **Severity:** LOW · **Source:** breaker A post-R1 #2 (G-LIB-07; red test on the reference branch
`breakit/s10-8-g-library`, not on main) · **Scheduled (2026-10-14):** pool · **Forward:** US-R1F-04.

`MetadataExtractor.parseGenres` splits on ";" and "/" (`MetadataExtractor.swift:162`): Apple's "Singer/Songwriter",
"Hip-Hop/Rap" and "R&B/Soul" become two Genre tiles each.

### KI-LIB-07 — Case / Unicode variants split artist and genre tiles

**Status:** OPEN · **Severity:** LOW · **Source:** breaker A post-R1 #10 · **Scheduled (2026-10-14):** pool · **Forward:** US-R1F-04.

`artists.name` / `genres.name` are `UNIQUE` with BINARY collation (`Sources/LibraryStore/Schema.swift:119-129`), and
genre names are not NFC-normalised (`LibraryTypes.swift`; artists are). "Rock" and "rock" are two tiles.

### KI-LIB-08 — Sorting Songs by Album orders each album's tracks by scan order

**Status:** OPEN · **Severity:** LOW · **Source:** breaker A post-R1 #6 · **Scheduled (2026-10-14):** pool · **Forward:** US-R1F-04.

The Album and toggled-Artist sorts are title / name then row id, with no disc / track keys
(`LibraryStore+BrowseReads.swift:306-309`), unlike the default artist-album-track sort (`:289-291`).

### KI-LIB-09 — Two Filter semantics

**Status:** OPEN · **Severity:** LOW · **Source:** breaker A post-R1 #7 · **Scheduled (2026-10-14):** R1.1-B (one search rule, council C-61) · **Forward:** ~~US-R1F-04~~ US-R1F-14.

Songs filters by FTS token prefix (`LibraryStore+Search.swift:47`), the grids by substring
(`LibraryBrowseKit/FacetTextFilter.swift:16`); "eatles" finds nothing in Songs. A rail jump clears the grids' filter but
not the Songs filter (`LibraryBrowseModel+Sidebar.swift:24-27`).

### KI-LIB-10 — An empty playlist says "No Tracks Yet"

**Status:** OPEN · **Severity:** LOW (wording) · **Source:** breaker A post-R1 #14 · **Scheduled (2026-10-14):** pool · **Forward:** US-R1F-04.

`UI/Playlist/PlaylistDetailView.swift:88`; the rest of the app says "songs".

---

## Accessibility and engineering follow-ups

### KI-UI-01 — VoiceOver keeps the app fairly busy while a song plays

**Status:** OPEN (reported in the [R1 release notes](../releases/v1.0.0-alpha.md); a runtime observation that code
reading can't confirm) · **Severity:** LOW · **Scheduled (2026-10-14):** R1.1-A (council C-53) · **Forward:** ~~US-R1F-07~~ US-R1F-15.

The likely driver is the 20 Hz main-thread tick invalidating observed state the accessibility tree reads; measure before
changing anything.

### KI-ENG-01 — `SpectrumDoubleBuffer` data race

**Status:** OPEN · **Severity:** internal (also an RT-safety follow-up) · **Source:** freeze "Logged post-R1" ·
**Scheduled (2026-10-14):** R1.1-A (council C-51) · **Forward:** ~~US-R1F-07~~ US-R1F-15.

Two slots in a Swift array (`Spectrum/SpectrumDoubleBuffer.swift:32`): the writer (`:61`) can lap the reader (`:85`),
giving a torn spectrum frame and a theoretical copy-on-write allocation on the tap thread. Use the named-atomic
triple-buffer idiom the C++ snapshot already uses.

### KI-ENG-02 — The main-thread stall self-test lacks the breaker's extra modes

**Status:** OPEN · **Severity:** internal · **Source:** freeze "Logged post-R1";
[evidence README](../architecture/evidence/main-thread-stall-2026-10/README.md) · **Scheduled (2026-10-14):** pool · **Forward:** US-R1F-07.

`Debug/MainThreadStallSelfTest.swift:27-43` runs `stop`, `start`, `device-loss` and `ended-advance` with a 25 ms bound
(1% may exceed 5 ms). Port the breaker harness's engineQueue-holder and first-play modes and tighten to <5 ms.

### KI-ENG-03 — A stale comment names the removed `loudnessMeter` field

**Status:** OPEN (the residual of rev-arch's "removed APIs" note; the semgrep message and the gapless comments were
fixed in 17bef99 / 13f6281, PR #86) · **Severity:** internal · **Scheduled (2026-10-14):** R1.1-A (hygiene, council C-88) · **Forward:** US-R1F-07.

`Sources/AdaptiveSound/LoudnessMeterHandle.swift:25` still says "drops the wrapper (nils `loudnessMeter`)".

### KI-ENG-04 — The `eq-light-folded` picture sheet flakes in the renderer

**Status:** OPEN (cannot be judged from code) · **Severity:** internal · **Source:** sweep ledger, "Logged post-R1" ·
**Scheduled (2026-10-14):** pool · **Forward:** US-R1F-07.

---

## Found by the 2026-10 council

The council's register rows that a user can meet and that had no entry above. Each names its row in the
[register](../reviews/2026-10-council/working/stage5-architect.md#1-finding-register) (C-xx), where the full evidence
and the merged source IDs live. File:line references are from the council's reading (`a206107`, re-checked at
`7761693` where the register marks them ✓).

### KI-PB-18 — Dragging the scrubber to the end of a track that isn't 48 kHz stops playback for good

**Status:** OPEN · **Severity:** HIGH (a stuck state) · **Source:** council C-25 (P3 breaker D37; the pre-mortem's
spot-check 1) · **Scheduled (2026-10-14):** R1.1-A · **Forward:** US-R1F-11.

The scrubber drag sends `seek(to: dragFraction * duration)` (`UI/Shell/NowPlayingBar.swift:332-333`), and the view
model passes it through unclamped. On the Enhanced resampler path the bridge moves its position base first, then
refuses the seek at `frame < totalFrames` (`AudioEngineBridge+EnhancedResampler.swift:193-202`): playback stays silent
and never moves on. Every file that isn't 48 kHz takes that path, including 44.1 kHz CD rips. A NaN target traps.

### KI-MC-02 — Channel roles come from positions, not the file's labels

**Status:** OPEN · **Severity:** HIGH (wrong audio) · **Source:** council C-44 (P2 D46, D47, P2-8) · **Scheduled
(2026-10-14):** R1.1-B, before the BS.775 fold-down (FD-9) · **Forward:** US-R1F-08.

Channel roles are never derived from the file's channel-layout labels (`AudioEngineBridge+Reconfigure.swift:97-105`).
An ALAC / AAC 5.1 file, whose order differs from the MPEG order, is routed by position, so its centre plays from the
left; 3-, 4-, 5- and 7-channel files fall back to stereo; 8 channels are forced to 7.1 A. The R1 release notes name
the ALAC / AAC case.

### KI-GAP-05 — An Enhanced gapless join to a file with a different channel count drops channels

**Status:** OPEN · **Severity:** HIGH (wrong audio) · **Source:** council C-24 (BR-7, D39 A4) · **Scheduled
(2026-10-14):** Engine sprint · **Forward:** US-R1F-02.

The Enhanced roll compares only the sample rate (`AudioEngineBridge+GaplessRoll.swift:39-42, 77-81`). Mono → stereo
drops the right channel; a 6-channel file after a stereo one drops centre, LFE and surrounds, or plays silence. The
council default: a join that changes the format is an honest short gap with every channel present.

### KI-PB-19 — Stop-then-Play or Pause-then-Play in quick succession can show "Playing" over silence

**Status:** OPEN · **Severity:** MEDIUM · **Source:** council C-15 (P4 E1, reproduced on the real view-model sources) ·
**Scheduled (2026-10-14):** R1.1-A · **Forward:** US-R1F-01.

Stop and Pause take their epoch inside their `Task` (`AudioViewModel+Lifecycle.swift:160-161, 174-175`), Stop is two
engine calls, and there is no starting or pausing state. A quick Play after Stop or Pause can leave the engine silent
while the app shows Playing. KI-PB-04 is the same root seen from a slow start.

### KI-PB-20 — A queued song can be skipped

**Status:** OPEN · **Severity:** MEDIUM · **Source:** council C-17 (P4-4, P4-5) · **Scheduled (2026-10-14):** R1.1-A ·
**Forward:** US-R1F-01.

The on-deck pick is not recomputed after queue edits (`AudioViewModel+Queue.swift:183`, `guard isPlaying`). A song
dragged in under the current one never plays; with Repeat All an append waits a whole cycle; a one-song shuffle plus an
append stops. An append during a start's prime is not armed (its Play Next twin was fixed in R1, PR #88), and
`playNextNow` ignores duplicates.

### KI-PB-21 — A crash or force-quit loses your place in the queue

**Status:** OPEN · **Severity:** MEDIUM · **Source:** council C-65 (LIB-12; product triage #3) · **Scheduled
(2026-10-14):** R1.1-B (atomic queue restore) · **Forward:** US-R1F-01.

The queue cursor reaches UserDefaults only on a clean quit (`AudioViewModel+Lifecycle.swift:125`), and the queue
mirror's debounce can race its quit-flush (`AudioViewModel+QueueMirror.swift:25-36`), although the kit already has a
coalescing writer for exactly this (`LibraryBrowseKit/CoalescingWriter.swift`).

### KI-GAP-04 — A click at each join between resampled tracks

**Status:** OPEN · **Severity:** MEDIUM · **Source:** council C-22 (P3 D39 c) · **Scheduled (2026-10-14):** Engine
sprint · **Forward:** US-R1F-02.

Each track gets its own sample-rate converter (`AudioEngineBridge+GaplessRoll.swift:248-257`), so the filter state
restarts at the seam: a click 18 to 26 dB below peak at every join of a 44.1 or 96 kHz album.

### KI-SND-01 — A fresh launch plays processed sound

**Status:** OPEN · **Severity:** MEDIUM · **Source:** council C-41, with C-38, C-39 and C-40 (P2 panels; the
pre-mortem) · **Scheduled (2026-10-14):** R1.1-A (FD-2) · **Forward:** US-R1F-09.

Intensity defaults to 20 % (`AudioViewModel.swift:142`). That turns on the loudness normaliser, a session-long
integrator whose make-up gain carries across tracks (`LoudnessModule.cpp:62, 283`); the equal-power blend's +2 dB on
correlated material (`DSPKernel.cpp:274-275`); and the limiter's −1 dBTP ceiling. Clarity and BRIR are pass-through
stubs, so the control changes loudness, not sound. FD-2: Intensity 0, leveling off, EQ off at a fresh launch;
Intensity hidden until its effects are real (S17).

### KI-SND-02 — Enhanced sample-rate conversion rolls off the treble and lets aliases through

**Status:** OPEN · **Severity:** MEDIUM · **Source:** council C-26 (P3 D37, D38; [engine research
§1](../reviews/2026-10-council/working/engine-research.md#1-new-measurements-avaudioengines-own-sample-rate-conversion-offline-probes))
· **Scheduled (2026-10-14):** R1.1-A · **Forward:** US-R1F-11.

The Enhanced resampler uses `AVAudioConverter`'s Normal algorithm (`AudioEngineBridge+EnhancedResampler.swift:82`):
−8.25 dB at 20 kHz on 44.1 → 48 kHz, and 192 → 48 kHz aliases at −21 dB. A device not at 48 kHz gets a hidden second
conversion. `SRCQualityMeasure` prints −7.23 dB at 20 kHz and still says PASS (council R-6). Apple's Mastering
converter measured flat to 21 kHz, with aliases at or below −160 dB.

### KI-SND-03 — The limiter's fast release never runs

**Status:** OPEN · **Severity:** MEDIUM · **Source:** council C-39 (P2-1, D34) · **Scheduled (2026-10-14):** R1.1-A ·
**Forward:** US-R1F-12.

The dual-release branch is dead code (`LimiterModule.h:398-416`); in practice it is one 500 ms release. A single snare
hit that touches the ceiling ducks the music for about a second. Only audible when the limiter engages (Enhanced, with
Intensity above 0 or the EQ on).

### KI-SND-04 — Crossfeed notches the centre; its "Default" preset is mislabelled

**Status:** OPEN · **Severity:** MEDIUM · **Source:** council C-42 (P2-3, D44, D45) · **Scheduled (2026-10-14):**
R1.1-A · **Forward:** US-R1F-12.

The crossfeed counts the interaural delay twice and leaves the direct path flat (`Spatial/CrossfeedModule.cpp:95-120`),
so a centred voice gets a −4.2 to −6.3 dB notch near 1 kHz. The fix follows the bs2b ladder (Jmeier / Cmoy / bs2b),
reimplemented from the published algorithm; libbs2b itself stays unlinked (OQ-17).

### KI-DEV-03 — An Enhanced start just after a device connects can end silent or on the wrong device

**Status:** OPEN · **Severity:** MEDIUM · **Source:** council C-28 (P5B-04; [reconnect re-check
§5](../reviews/2026-10-council/working/p5b-reconnect-recheck.md)) · **Scheduled (2026-10-14):** Engine sprint ·
**Forward:** [EP-PLAYENGINE](backlog.md#ep-playengine--the-engine-sprint).

An Enhanced start races the output-device rule (`AudioEngineBridge+Playback.swift:96, 123`): 1–3 of every 11–36
explored interleavings end silent or on the wrong device, for example Play right after Bluetooth headphones connect.
R1's device-return fix (N92) did not change this.

### KI-LIB-11 — Search splits Sinhala words; decomposed text can't be found

**Status:** OPEN · **Severity:** MEDIUM · **Source:** council C-61 (P5A SRCH-1…5, P5B-07 / -11) · **Scheduled
(2026-10-14):** R1.1-A (tokenizer categories + NFC); R1.1-B (one search rule + ⌘F) · **Forward:** US-R1F-14.

The full-text tokenizer treats Sinhala vowel signs as separators, so "මාල" matches "මිල"; text stored decomposed (NFD)
can't be found from a composed query; type-select folds marks; and three search semantics exist (KI-LIB-09)
(`LibraryStore+Search.swift:16-48`).

### KI-SEC-01 — If FFmpeg is installed, it parses every FLAC / Ogg / Opus file first, from a user-writable path

**Status:** OPEN · **Severity:** MEDIUM (security; only with FFmpeg installed) · **Source:** council C-99 (the
pre-mortem §3.1) · **Scheduled (2026-10-14):** R1.1-A (FD-3) · **Forward:** US-R1F-16.

The background metadata pass runs FFmpeg's demuxers first on every `flac`, `ogg`, `oga` and `opus` file
(`LibraryScan/MetadataExtractor.swift:55-62`). The libraries are `dlopen`ed from `/opt/homebrew/lib` (user-writable),
`/usr/local/lib`, or by bare leaf name (`AudioDSP/FileDecodeSource.cpp:386-399`), in a process with no sandbox. One
crafted file could run code with the user's rights. FD-3 keeps FFmpeg as an opt-in, off by default, loaded only from
fixed absolute paths; the scan uses it only when it is on.

### KI-PURE-01 — On Pure, each pause and resume switches the DAC's sample rate twice

**Status:** OPEN, unverified on hardware · **Severity:** MEDIUM · **Source:** council C-100 (the pre-mortem §3.2) ·
**Scheduled (2026-10-14):** parked (FD-5) · **Forward:** US-ENG-07 (the USB-DAC check).

Pause is a stop (`AudioViewModel+Transport.swift:45-47`); on Pure, stop runs `tearDownPure()`, which releases hog mode
and restores the device's original nominal rate (`HALOutputEngine.mm:350-351`). A 44.1 kHz file on a DAC that sits at
48 kHz switches rate at every pause and again at resume. Many DACs click or mute when that happens, and another app
can take the device during the pause.

### KI-UI-02 — The spectrum analyser reads about 4 dB high; two timers run while idle

**Status:** OPEN · **Severity:** LOW · **Source:** council C-51, C-52 (P1 D53–D57; UI-2) · **Scheduled (2026-10-14):**
R1.1-A · **Forward:** US-R1F-15.

The analyser reads +4.26 dB high and uses N = 4096 at every sample rate (`SpectrumAnalyzer.swift:109`); its hand-off
tears frames (KI-ENG-01). Two 20 Hz main-thread timers run from engine-ready to shutdown, also while paused and while
the app sits in the menu bar (`AudioViewModel+SpectrumTimer.swift:14-41`).

### KI-UI-03 — The loudness "Integrated" readout spans the whole session

**Status:** OPEN · **Severity:** LOW · **Source:** council C-46 (DSP-09, D59, P2-10) · **Scheduled (2026-10-14):**
R1.1-A · **Forward:** US-R1F-12.

The UI's "Integrated" integrates over the session, not the track, and the real-time analysis workers poll about 200
times a second while paused (`LoudnessModule.cpp:240-244`, `LoudnessMeterBridge.cpp:51-60`).

---

## Known limitations (by design or not yet built)

These are not defects; each is a decision or a planned feature. They are listed so a user of R1 isn't surprised.

| Limitation | Why / where decided | Forward link |
|---|---|---|
| The R1 build is ad-hoc signed and **not notarized**: macOS asks once (Open Anyway) | Founder decision 13 ([glass-sweep plan](../sprints/s10-8-glass-sweep-plan.md)); `Makefile` `dist`, PR #87 | US-REL-01 — release readiness, deferred (FD-7, 2026-10-14) |
| **Pure Mode on Bluetooth / AirPlay** falls back to Enhanced | The link re-encodes, so bit-perfect is impossible (`PureModePolicy.cpp`; `evaluatePureViable`) | — (by design) |
| **Pure Mode plays a track only when its channel count is the device stream's**: a mono file on stereo speakers, or a stereo file on a 4- or 8-channel interface, plays in Enhanced, and Settings says so ("Pure Mode can't play this track on this device…") | R1 fix (PR #88, d540c5c; council D71): before it, such a track played endless silence. `PureModePolicy.cpp:126-135` (`ChannelCountMismatch`); mapping inside Pure (AUHAL `ChannelMap`) is not done | US-ENG-07 follow-up (unscheduled) |
| **Pure Mode declines a device format it cannot write exactly** (non-interleaved, unsigned, 8- / 20-bit, 16-in-32, float64): the track plays in Enhanced | R1 fix (PR #88, d540c5c; council D74): `NativePcmFormat::fromAsbd` (`include/PureModeFormat.h`) admits only float32, int16, packed 24, 24-in-32 and int32 | — (by design) |
| There is **no way to open or play a single file** outside the library (no Finder drop, Open… or Open With), and none to add a non-library file to a playlist | The store supports it (`addLooseFileToPlaylist`, `LibraryStore+Playlists.swift:422`), but the only UI entry was removed with the S9 IA change (7058667 in PR #23, "Now Playing is the queue only") and never re-added | US-LIB-02, US-PLIST-02 — R1.1-B (2026-10-14) |
| A **copy-then-delete move** (cross-volume drag, rsync) gets a new identity: play count, loved flag and playlist entries do not follow | Move-match keys on `(dev, inode, size, mtime)` + format (`LibraryStore+MoveMatch.swift`); `content_hash` is the deferred escape hatch (SEQ-1 Gate 2) | Post-R1 pool (council C-57) |
| **Gapless on the FFmpeg fallback** (Opus / Vorbis pre-skip) is not trimmed. AAC and MP3 are fine: they decode through Apple on both paths, whose edit list trims the priming | `FileDecodeSource.cpp:7-16` (Apple first, FFmpeg only if Apple can't open the file); `AudioEngineBridge+Gapless.swift:37-42` | US-PLAY-07 → S11-lite, through the FFmpeg opt-in (FD-3, 2026-10-14) |
| **DSD** is not supported | Deferred past R2, gated on a DSD DAC ([sprint-plan](../sprints/sprint-plan.md) §5) | post-R2 |

---

## Closed

### Fixed by PR #88 — the R1 blockers (2026-10-14)

The council's R1 blocker fixes, approved by the founder before the `v1.0.0-alpha` tag (PR #88, merged 2026-10-14;
PR #89 made one of its tests deterministic). Each was attacked by an independent break-it pass; the evidence is in the
PR and the commit messages.

#### KI-PB-01 — Pure ignored a changed next track while another was armed (council D41)

**Status:** ✅ CLOSED by PR #88 (6492f73, 35b3519; the latent arm-inside-a-claimed-seam case a130b7c) — re-verified
2026-10-14. *The original entry is kept below.* Every on-deck request now carries an `OnDeckTicket`
(`PlaybackQueueKit/OnDeckTicket.swift`) from the view model's one producer, `armOnDeck`
(`AudioViewModel+Queue.swift:201-208`); `engineQueue` admits only the newest request of the current playback
(`OnDeckGate`), and Pure takes the old pick off at admission (`pureModeEngineClearNextTrack`) and arms the new one only
if it is still the newest (`AudioEngineBridge+Gapless.swift:47-156`). In `GaplessSource` the end is final. Tests:
`Tests/AudioViewModelTests/OnDeckGateTests.swift` (VM-OD-01…06), the shipped-view-model scenarios, ablations and
3,000-schedule explorer in `Tests/AdaptiveSoundTests/`, and the null test's `ArmContract_*` suite. Residual windows:
KI-PB-16, KI-PB-17. The founder's by-ear check on a USB DAC is still owed.

~~**Status:** OPEN · **Severity:** HIGH (found by reading the code during this reconciliation; needs a live check on a
USB DAC) · **Forward:** US-R1F-01.~~

*(As found at a206107:)* On the Pure path the gapless deck has one slot, and a second arm is refused:
`pureModeEngineArmOpenedNextTrack` returned an error when a track was already armed (`PureModeBridge.cpp`;
`GaplessSource::armNext`). The view model's re-arm (`armOnDeck`) pushed the new URL without clearing the slot first
(`setPureNextTrack` cleared only for a `nil` URL). So in Pure, a mid-song Repeat / Shuffle change (the Sprint G re-arm,
PR #85) or a queue edit that changes the next song (Play Next, reorder, remove) left the OLD next track armed. At the
seam Pure played it, while the view model advanced to its own `pendingNextIndex` and named a different song. Enhanced
was not affected (`onDeckURL` is simply replaced).

#### The other R1 blockers

- **Render gate (the main-CI failure on a206107, `RenderGate_ConcurrentNeverOverlaps`)** — `close()` could only win
  between two render passes, so a busy render starved it. Fixed by 5be24a4, 7e69c16, 5f78223: `close()` bars new
  passes at once and waits only for the pass inside (`include/RenderGate.h`); the tests assert the guarantee step by
  step, with no wall-clock deadline. **DSP-06:** a teardown never reopens the gate, and a pass that outlived its unit's
  stop leaves its engine and source parked, never freed (2f23dd1, 74db104).
- **Library data loss (council P5A-01 / P5A-02)** — an unreadable subfolder, a drive unplugged mid-walk or another
  drive with the same name made the sweep delete songs with their playlist entries and play history. A sweep now needs
  positive evidence (`LibraryScan/SweepRefusal.swift`), and each folder is bound to its drive's volume UUID
  (`folders.volume_uuid`, additive migration v8) — adeff5e, 6ed2169, dbb52a2. Tests: `SweepEvidenceTests`,
  VerifyLibraryStore SE-1…SE-4. Accepted limits: LIB-VOL-1.
- **Pure Mode safety (council D71 / DSP-03, D74 / DSP-04, D76)** — a mono track (or any channel-count mismatch) played
  silence that never ended; a packed 24-bit device format overran the IO buffer; NaN / Inf played at full scale. Fixed
  by d540c5c: such a track plays in Enhanced with the existing notice, device formats are written exactly or declined
  (`PureModeFormat.h`), and non-finite samples become silence (`FiniteSamples.h`). See the two Pure rows under *Known
  limitations*.
- **Return to the headphones (council N92)** — after Bluetooth headphones dropped and came back, Play moved the system
  output back to the speakers. The chosen device is now kept apart from a temporary fallback (`OutputDeviceSelection`,
  `OutputDeviceKit`), and playback returns to it once the device menu would list it; the device the app launches on is
  not a choice; a refused pick undoes only itself — 5e6644f, 7478d84. Tests: `OutputDeviceReturnTests`,
  `OutputDeviceChoiceTests`, `OutputDeviceRuleSpaceTests`, `Tests/AdaptiveSoundTests/OutputDeviceViewModelTests.swift`.
  Limit: DEV-1.
- **Play Next during a start's prime played the old pick (council F-P4-1, pre-existing)** — a840fe5: `playNext` arms
  when a pick is on deck or being primed.
- **Settings copy** — with "Keep playback on this device" off, Settings now says "Playback follows your Mac's sound
  output." (f098821).
- **PR #89** (7761693, after the tag; test-only) — the seam-window arm tests no longer depend on the scheduler (an ASan
  flake on PR #88's CI).

### Fixed by PR #85 / PR #86 (re-verified 2026-10-13)

- **The 13 Sprint G R1 blockers** (5 library, 8 playback / devices / Master Gain) — fixed in PR #85; see the two
  break-it reports and the [sweep ledger](../sprints/s10-8-sweep-ledger.md) "Build, break-it, fixes and live pass".
- **The disconnect freeze** (switching headphones off froze the app 3–7 s) — fixed in PR #86; evidence in
  [main-thread-stall-2026-10](../architecture/evidence/main-thread-stall-2026-10/README.md).
- **G-LIB-03** — New Playlist failed beside a "new playlist" in another case: fixed by ad2ee3c (PR #85), the free name
  is now picked case-blind (`LibraryStore+Playlists.swift:198-199`); regression test
  `Tests/LibraryBrowseKitTests/LibraryBreakItGTests.swift:93`.
- **Breaker B post-R1 #2** — Pure leaked a device-alive listener per manual start: fixed by a4c5bc1 (PR #85), one
  alive listener on the app's device (`AudioEngineBridge+OutputDeviceMonitor.swift:80-95`).
- **Audit S1-E** — the loudness-meter snapshot race / potential use-after-free: fixed by cc976dc (PR #86),
  `withExtendedLifetime(meter)` over a strong copy (`AudioEngineBridge.swift:346-348`).
- **`passUnretained` without `withExtendedLifetime`** on the effects AU: fixed by 69b94aa / cc976dc (PR #86),
  `withEffectsAU` (`AudioEngineBridge+SharedState.swift:255-259`).
- **R10, the engine-lock-held regression test:** added by a861cc6 (PR #86) as `make main-thread-stall` in the strict
  gate.
- **Pure resume played the intro** (start-then-seek): fixed by 92c1801 (PR #86), `startAudio(…, startAt:)`
  (`AudioEngineBridge+PureMode.swift:128`).

## SEQ-1 — Hard sequencing gates before S9/S10 playlists ship (library data integrity)

**Status:** CLOSED (both gates landed). Surfaced by the S6 full-team review (E1/E2). Gate 2 closed
with S8.4 (move-match); **Gate 1 closed with S10.1** (the `playlist_entries` filter). Kept here as
the record of why the sequencing mattered.

**Verified current state (2026-07-03):** `removeRoot` (LibraryStore+DAO) already implements the
design §8 detach-to-loose flow correctly — it deletes the `folders` row (the `folder_id … ON DELETE
SET NULL` FK detaches the folder's tracks to loose), then deletes only the *unreferenced* ones. The
loose-file path is wired (nullable `folder_id`, `addLooseFile`, and VerifyLibraryStore FS-4 proves a
loose track survives an unrelated root's removal). No code change was needed for E1.

**Gate 1 — `unreferencedTrackIDs` playlist filter — CLOSED (S10.1).** `unreferencedTrackIDs` now
filters candidates against `SELECT DISTINCT track_id FROM playlist_entries`, so `removeRoot` spares
any playlist-referenced track (it detaches to loose, `folder_id → NULL`, entries + FTS rows intact)
and deletes only the genuinely-unreferenced ones. Proven by `VerifyLibraryStore` `pl-gate1-*` checks
(referenced-kept + unreferenced-swept). (Table named `playlist_entries`, not the earlier
`playlist_tracks` sketch.) *(Amended 2026-10-12, PR #85 / ff0e0da, G-LIB-04: the filter now counts **user** playlists
only — `JOIN playlists p … WHERE p.is_builtin = 0`, `LibraryStore+DAO.swift:388-389` — so songs that were merely in the
queue (the built-in "current" playlist) no longer survive a folder removal as un-removable loose rows; the queue
snapshot skips a song that is gone.)*

**Gate 2 — S8.4 id-preserving move-match — CLOSED (landed on `main`).** A filesystem move reconciles as an id-preserving move (signature match on `(dev,inode,size,mtime)` + format), keeping `tracks.id` and durable user-state (play_count/loved/rating). Proven by `VerifyLibraryStore` move checks (`LibraryStore+MoveMatch.swift`); this is now code truth, not a doc claim. **Known limitation (still forward):** a copy-then-delete move (cross-volume drag, rsync) gets a new inode and is NOT matched (id lost) — `content_hash` is the deferred escape hatch. Traces to EP-LIBRARY (US-LIB move-in-place) + EP-PLAYLIST in [backlog.md](backlog.md). **Both gates are now closed.** *(Re-verified 2026-10-13; the stamp is now never lowered — `MAX(last_seen_scan, ?)`, PR #85 G-LIB-01.)*

---

## DUR-1 — Playlist durability across schema change (⚠️ HARD GATE before R1)

**Status:** ✅ CLOSED in S10.3 (verified in code 2026-10-13, before R1): `LibraryStore` sets `eraseDatabaseOnSchemaChange = false` with additive-only, frozen-body migrations; `strict-gate`'s "Migrator posture guard" forbids re-enabling the erase; VerifyLibraryStore's `additive-migration-convergence` check catches an edited shipped migration. *The original note below is kept for history.* *(Since S10.8 C2, PR #70: the open path also takes a pre-upgrade backup — `StoreBackup.swift` — and refuses, never wipes, a store it can't safely open.)*

~~**Status:** OPEN (deferred by founder decision — S10.1 design §0.1; keep it simple pre-release).~~

The store keeps `eraseDatabaseOnSchemaChange = true` (the rebuildable-cache "drop-and-recreate on
schema change" discipline). That is correct for the track/album **cache** but **playlists are
user-authored data that cannot be rebuilt from the filesystem.** Two failure modes once real users
have playlists: (a) a schema change **erases** them; (b) worse, a full rebuild **reassigns
`tracks.id` in scan order**, so surviving `playlist_entries.track_id` would point at the **wrong
song** — silent corruption. Harmless pre-release (no real playlists yet), which is why S10.1 ships
with it deferred.

**⚠️ HARD GATE — MUST be resolved before Release R1 ships playlists to users.** The likely fix
(from the S10.1 design + gate): a real additive migration posture + `eraseDatabaseOnSchemaChange`
off in release (dev keeps a `make reset-db`), plus a migration-immutability guard so an edited
shipped migration can't silently corrupt. Revisit as its own scoped task before R1.
