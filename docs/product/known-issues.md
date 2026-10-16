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
| KI-MC-01 | A 5.1 / 7.1 file on a stereo output plays only its front left and right: centre, LFE and surrounds are dropped | HIGH | R1.1-B (BS.775 fold-down, FD-9); S18 replaces it | US-R1F-08 |
| KI-MC-02 | Channel roles come from positions, not the file's labels: an ALAC / AAC 5.1 file plays its centre on the left; 3-, 4-, 5- and 7-channel files fall back to stereo | HIGH | R1.1-B | US-R1F-08 |
| KI-PB-18 | Dragging the scrubber to the end of a track that isn't 48 kHz stops playback for good | HIGH | R1.1-A | US-R1F-11 |
| KI-GAP-05 | An Enhanced gapless join to a file with a different channel count drops channels | HIGH | Engine sprint | US-R1F-02 |
| KI-PB-02 | Repeat turned off mid-song moves on, but with a gap | MEDIUM | Engine sprint | US-R1F-02 |
| KI-PB-03 | Shuffle on + Repeat off never ends the queue | MEDIUM | R1.1-B (shuffle as a permutation) | US-R1F-01 |
| KI-PB-06 | After a relaunch the restored song shows `--:--` and its scrubber is dead until Play | MEDIUM | R1.1-A | US-R1F-01 |
| KI-PB-08 | Clicking the paused current queue row restarts it from 0:00 | MEDIUM | R1.1-A | US-R1F-01 |
| KI-PB-10 | Add to Queue onto an empty queue leaves Play / Space disabled | MEDIUM | R1.1-A | US-R1F-01 |
| KI-PB-11 | "Restore previous queue" restores the wrong queue | MEDIUM | pool | US-R1F-04 |
| KI-PB-12 | A single click on a playlist row replaces the queue and plays | MEDIUM | pool | US-R1F-04 |
| KI-PB-21 | A crash or force-quit loses your place in the queue | MEDIUM | R1.1-B (atomic queue restore) | US-R1F-01 |
| KI-GAP-01 | A short gap at the seam between 48 kHz tracks | MEDIUM | Engine sprint | US-R1F-02 |
| KI-GAP-02 | At a resampled seam to another rate or width, the title and track B's gain switch up to ~0.2 s early | MEDIUM | Engine sprint | US-R1F-02 |
| KI-SND-02 | Enhanced sample-rate conversion rolls off the treble (−8.25 dB at 20 kHz) and lets aliases through | MEDIUM | R1.1-A | US-R1F-11 |
| KI-EQ-01 | Unpinning an output overwrites the shared EQ, with no undo | MEDIUM | pool (first candidate) | US-R1F-06 |
| KI-DEV-03 | An Enhanced start just after a device connects can end silent or on the wrong device | MEDIUM | Engine sprint | EP-PLAYENGINE |
| KI-LIB-02 | A folder whose walk fails outright says nothing; there is no Rescan control *(narrowed in R1.1-A: a paused folder says why)* | ~~MEDIUM~~ LOW | ~~R1.1-A~~ the rest: for triage | US-R1F-03 |
| LIB-VOL-1 | A paused folder on a replaced or UUID-less drive stays paused; re-adding it loses play stats | MEDIUM | R1.1-B ("Use this drive") | US-R1F-03 |
| KI-LIB-03 | A failed first metadata pass leaves "No Music Yet", with no retry | MEDIUM | pool | US-R1F-03 |
| KI-LIB-04 | Dragging a multi-selection onto a playlist adds one song | MEDIUM | pool | US-R1F-04 |
| KI-PURE-01 | On Pure, each pause and resume switches the DAC's sample rate twice (pause is a device teardown) — unverified on hardware | MEDIUM | parked (FD-5) | US-ENG-07 |
| KI-PB-07 | Next / Previous while paused keep the old song's duration | LOW | R1.1-A | US-R1F-01 |
| KI-PB-13 | Two quick tile Plays can land out of order | LOW | pool | US-R1F-04 |
| KI-PB-14 | Stalled ticks count as heard time (play counts) | LOW | pool | US-R1F-01 |
| KI-PB-15 | Recent says "Nothing Played Yet" when the store is not ready or the read failed | LOW | pool | US-R1F-04 |
| KI-PB-16 | A change of the next song in the last moments before a seam can still play the old pick (D41 residual A2 / A2′) | LOW | Engine sprint (seam identity) | US-R1F-01 |
| KI-PB-17 | A scrub back into a track that has already ended (nothing armed) is lost | LOW | Engine sprint (seam identity) | US-R1F-01 |
| KI-GAP-03 | A narrow false seam on a Pure → Enhanced restart | LOW | Engine sprint | US-R1F-02 |
| ENH-001 | Short-track auto-advance is a reconfigure gap, not a seamless seam | LOW | Engine sprint | US-R1F-02 |
| ENH-002 | The UI loudness readout is L/R-only on a >2-channel output | LOW | pool | US-R1F-07 |
| KI-EQ-02 | Esc during a graph drag re-announces "Bring back edits" | LOW | pool | US-R1F-06 |
| KI-EQ-03 | Stacked-shadow darkening on EQ / Settings cards (dark + Reduce Transparency / Increase Contrast) — unverified | LOW | pool | US-R1F-06 |
| KI-DEV-02 | HDMI / DisplayPort outputs read "(Unknown)" | LOW | pool | US-R1F-06 |
| KI-SEC-01 | With FFmpeg turned on (it is off by default), a third-party C parser reads files Apple can't, inside the app | LOW | pool (an XPC helper, or deletion after the corpus check — FD-3) | US-R1F-16 |
| KI-LIB-06 | Genres split on "/" ("Singer/Songwriter" → two tiles) | LOW | pool | US-R1F-04 |
| KI-LIB-07 | Case / Unicode variants split artist and genre tiles | LOW | pool | US-R1F-04 |
| KI-LIB-08 | Sorting Songs by Album orders each album's tracks by scan order | LOW | pool | US-R1F-04 |
| KI-LIB-09 | Two Filter semantics (Songs: token prefix; grids: substring) | LOW | R1.1-B (one search rule) | US-R1F-14 |
| KI-LIB-10 | An empty playlist says "No Tracks Yet" (the app says "songs") | LOW | pool | US-R1F-04 |
| KI-UI-01 | VoiceOver keeps the app fairly busy while a song plays — its code causes are fixed (R1.1-A, live readouts); not yet confirmed with VoiceOver | LOW | R1.1-A (founder's VoiceOver check) | US-R1F-15 |
| KI-ENG-02 | The main-thread stall self-test lacks the breaker's two extra modes and the 5 ms bound | internal | pool | US-R1F-07 |
| KI-ENG-04 | The `eq-light-folded` picture sheet flakes in the renderer | internal | pool | US-R1F-07 |

**Known limitations (by design or not yet built — not defects):** see [the last section](#known-limitations-by-design-or-not-yet-built).

---

## Playback and transport

*(KI-PB-01 — Pure ignored a changed next track — was fixed by PR #88 (council D41); see [Closed](#fixed-by-pr-88--the-r1-blockers-2026-10-14). Its residual windows are KI-PB-16 and KI-PB-17.)*

*(KI-PB-04 — Space during a slow start restarted the song — and KI-PB-09 — a double-click on a queue row started it twice — were fixed in R1.1-A, with KI-PB-19 and KI-PB-20 (council C-15, C-17); see [Closed](#fixed-in-r11-a--playback-correctness-branch-r11atransport).)*

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
milliseconds; a chunk longer before a same-format resampled join, below) · **Scheduled (2026-10-14):** Engine sprint (seam identity, council C-14) · **Forward:** US-R1F-01 (follow-up F1, *seam identity*).

A seam reports a count, not which track it played, so two windows remain (architecture §2.5, "What plays next"):
**A2** — a request not yet admitted on `engineQueue` when the track ends (the rest of the main-thread turn, one hop and
any queue backlog) finds the old pick still armed: the old pick plays while the new one is shown; **A2′** — an edit made
after a seam but before the view model's next tick (up to 50 ms, plus the 33 ms clock) is shown as playing while the
pick the seam took plays. Pinned by the `LATE-REQUEST` scenario (`Tests/AdaptiveSoundTests/OnDeckContractTests.swift`);
the explorers count both windows apart (`OnDeckExplorerTests.swift`, and with Play, Pause and Stop against a busy engine
`TransportExplorerTests.swift`, by one rule: `Rig.tickJudgingSeam`). Since R1.1-A a queue edit re-arms the next song
in more cases (KI-PB-20), so more edits can meet these windows; the outcome in them is unchanged. Since R1.1-A's
one-converter seam (KI-GAP-04), a same-format resampled track's next track is taken when the stream reads past the
playing track's end — 186–372 ms before the join is heard at 44.1 kHz, where the end-of-file roll took it 0–186 ms
before — so A2 is one chunk longer there. Taking it later would bring back the roll's race (P3 D39 b).

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

### KI-GAP-02 — At a resampled seam to another rate or width, the title and track B's gain switch early

**Status:** OPEN (narrowed in R1.1-A) · **Severity:** MEDIUM · **Source:** freeze "Logged post-R1" (playhead latency
compensation and seam domains) · **Scheduled (2026-10-14):** Engine sprint (council C-23) · **Forward:** US-R1F-02.

The resampler seam bumps the transition count when B is primed, i.e. when A's decode reaches end-of-file
(`AudioEngineBridge+GaplessRoll.swift:256-259` → `+Gapless.swift:184-186`), not when B becomes audible; no
presentation latency is applied anywhere. On 44.1 kHz music the title and B's loudness gain switch early, and the
scrubber runs ahead of what is heard (more on Bluetooth). *(Corrected by the council, P3 D40: early by A's last
partial chunk and the converter's flush, 0–186 ms at 44.1 kHz, not ~0.4 s.)*

*Narrowed in R1.1-A ("one converter across a same-rate seam", council C-22; see KI-GAP-04 under Closed):* a seam to a
track of the same rate and channel count — an album — is counted when the player has consumed A's last frame
(`commitJoin`), and the playhead re-bases by exactly A's length; `EnhancedSeamTests` pins both. Still early: a
resampled track followed by one of another rate or width (the end-of-file roll, as above). Still everywhere: no
presentation latency, so the title and scrubber lead what is heard by the device's latency.

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

*(KI-SET-03 — a device volume lowered on Pure stayed lowered on Enhanced — closed in R1.1-A; see
[Closed](#fixed-in-r11-a--pure-honesty-master-gain-on-pure-ffmpeg-as-an-opt-in-branch-r11apure-ffmpeg).)*

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

### KI-DEV-02 — HDMI / DisplayPort outputs read "(Unknown)"

**Status:** OPEN · **Severity:** LOW · **Source:** sweep ledger, "Logged post-R1" · **Scheduled (2026-10-14):** pool · **Forward:** US-R1F-06.

`classifyDeviceType` has no HDMI / DisplayPort case (`CoreAudioDevice.cpp:332-359`); the pill and Settings show
"<name> (Unknown)" (`Models/AudioDeviceModel.swift:86-88`).

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

### KI-LIB-02 — ~~Paused / failed folders are invisible; an emptied folder keeps its songs~~ A folder whose walk fails outright says nothing; there is no Rescan control

**Status:** OPEN, narrowed in R1.1-A (a paused folder says why — below) · **Severity:** ~~MEDIUM~~ LOW (the rest) ·
**Source:** breaker A post-R1 #8 · **Scheduled (2026-10-14):** R1.1-A (council C-55); the rest awaits triage · **Forward:** US-R1F-03.

*(R1.1-A, branch `r1.1a/hygiene` — founder decision 2026-10-15, "a paused folder says why":)* a paused folder's Music
Folders row shows a folder with a question mark, in the warning colour, and its caption line — the slot "Scanning…"
uses — gives the reason in a few words, one per refusal: "Not found — is its drive connected?", "Another drive is using
this name", "Can’t confirm this is the folder’s drive", "Can’t open this folder — check its permissions", "Looks empty —
songs kept". Hovering it says "Its songs stay in your library and playlists, and come back when it’s back."; VoiceOver
reads the reason with the folder's path. The reason travels with the pause (`ReconcileState.paused`), and its words
live in one place (`LibraryBrowseKit`, `MusicFolderStatus`). A volume mount or unmount now asks every folder for a walk,
so a folder whose drive was just unplugged is paused at once instead of reading "watching". An emptied folder still
keeps its songs, by design (S8.4's "never wipe on an empty walk"), and now says so. Tests first:
`Tests/AdaptiveSoundTests/VolumeMonitorPauseTests.swift` (the unplugged folder read "watching" before the fix) and
`Tests/LibraryBrowseKitTests/MusicFolderStatusTests.swift`; the `folder-paused` picture sheet shows the look. **Still
open:** a walk that fails outright — a store error, not a refusal — says nothing on its row, and there is no Rescan
control. *The entry as it stood:*

`reconcileState` / `lastReconcileError` (`LibraryModel.swift:118-120`) have no UI reader. Songs on an unplugged drive
look normal and fail only on play; a folder whose files were all deleted keeps listing them, because the empty-walk
guard refuses the sweep silently. There is no Rescan control. *(Since PR #88 a walk that is not evidence — the folder
unreachable, on another drive, unrecognized, read only in part, or empty — refuses its sweep (`SweepRefusal`, five
reasons) and pauses the folder silently, on the reconcile and on the add walk alike
(`LibraryModel+Reconcile.swift:153-154`, `:165-166`; `LibraryModel+Scan.swift:213-215`). Paused folders are now more
common and still invisible; see LIB-VOL-1.)* *(R1.1-A, branch `r1.1a/library` — council C-55: a subfolder the walk
can't read no longer pauses its folder. The walk is evidence of what it read: it spares the songs under what it could
not read and sweeps, and reads the tags of, the rest (`LibraryScanner`, `LibraryStore.sweepOrphans(…sparing:)`); only a
folder it cannot open at all is still refused, `.incompleteWalk`. Showing a paused folder waits for a founder decision on
its treatment. Also: the volume monitor does not walk a folder whose drive was just unplugged (`handleVolumeChange`
walks only reachable folders), so its state can read "watching" until a walk of it is refused.)* *(Both fixed in
R1.1-A, above.)*

### LIB-VOL-1 — A music folder is bound to its drive; a sweep needs evidence (R1 sweep-evidence fix)

**Status:** OPEN (accepted limitations) · **Severity:** MEDIUM · **Scheduled (2026-10-14):** R1.1-B ("Use this drive", council C-54) · **Forward:** US-R1F-03.

A folder is bound to its drive's volume UUID (the startup disk as itself, since its UUID changes with the Mac); one on a volume that reports no UUID (some network volumes; FAT32/exFAT report one on macOS 26) stays unbound and is walked only while some of its songs are where the library has them — so a folder all of whose files were moved or renamed at once while unbound (on such a volume, or between the v8 upgrade and its first walk) stays paused until it is removed and re-added; so does a folder whose drive is replaced by a different one with the same name (a new or reformatted "T7")~~; and a folder with a subfolder the app can never read never has its deleted songs swept~~ (`LibraryStore+Roots`, `SweepRefusal`). *(The struck limitation is fixed in R1.1-A, council C-55: the walk spares only the songs under what it could not read — see KI-LIB-02.)*

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

**Status:** OPEN — its code causes are fixed in R1.1-A ("VoiceOver hears live readings as values, polled"); the
runtime symptom waits for a VoiceOver check (reported in the [R1 release notes](../releases/v1.0.0-alpha.md); code
reading can't confirm it) · **Severity:** LOW · **Scheduled (2026-10-14):** R1.1-A (council C-53) · **Forward:**
~~US-R1F-07~~ US-R1F-15.

What the code did, and does now: the loudness meters put their readings in the accessibility *label*, so three
elements changed their names up to 20 times a second — the readings are now values, quantised for speech (LUFS to
the LU, the true peak up to the dB), under a fixed label, with `.updatesFrequently`
(`liveReadout(_:value:)`, `UI/Controls/LiveReadout.swift`). The scrubber's accessibility element re-evaluated 20 times
a second for a value that changes once; it now reads the playhead in whole seconds (`AudioViewModel.elapsedSeconds`),
and only its groove follows the 20 Hz playhead. The 20 Hz analyser views (88 animated views) are one `Canvas`,
hidden from accessibility as before, drawn only while a song plays and the window shows. To close: a Time Profiler
run (or Activity Monitor's CPU) with VoiceOver on, Now Playing showing, a song playing.

*(KI-ENG-01 — the spectrum hand-off's data race — was fixed in R1.1-A; see
[Closed](#fixed-in-r11-a--live-readouts-branch-r11areadouts).)*

### KI-ENG-02 — The main-thread stall self-test lacks the breaker's extra modes

**Status:** OPEN · **Severity:** internal · **Source:** freeze "Logged post-R1";
[evidence README](../architecture/evidence/main-thread-stall-2026-10/README.md) · **Scheduled (2026-10-14):** pool · **Forward:** US-R1F-07.

`Debug/MainThreadStallSelfTest.swift:27-43` runs `stop`, `start`, `device-loss` and `ended-advance` with a 25 ms bound
(1% may exceed 5 ms). Port the breaker harness's engineQueue-holder and first-play modes and tighten to <5 ms.

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

*(KI-PB-19 — Playing shown over silence after a quick Stop-then-Play — and KI-PB-20 — a queued song skipped — were fixed in R1.1-A (council C-15, C-17); see [Closed](#fixed-in-r11-a--playback-correctness-branch-r11atransport).)*

### KI-PB-21 — A crash or force-quit loses your place in the queue

**Status:** OPEN · **Severity:** MEDIUM · **Source:** council C-65 (LIB-12; product triage #3) · **Scheduled
(2026-10-14):** R1.1-B (atomic queue restore) · **Forward:** US-R1F-01.

The queue cursor reaches UserDefaults only on a clean quit (`AudioViewModel+Lifecycle.swift:125`), and the queue
mirror's debounce can race its quit-flush (`AudioViewModel+QueueMirror.swift:25-36`), although the kit already has a
coalescing writer for exactly this (`LibraryBrowseKit/CoalescingWriter.swift`).

### KI-SND-02 — Enhanced sample-rate conversion rolls off the treble and lets aliases through

**Status:** OPEN · **Severity:** MEDIUM · **Source:** council C-26 (P3 D37, D38; [engine research
§1](../reviews/2026-10-council/working/engine-research.md#1-new-measurements-avaudioengines-own-sample-rate-conversion-offline-probes))
· **Scheduled (2026-10-14):** R1.1-A · **Forward:** US-R1F-11.

The Enhanced resampler uses `AVAudioConverter`'s Normal algorithm (`AudioEngineBridge+EnhancedResampler.swift:82`):
−8.25 dB at 20 kHz on 44.1 → 48 kHz, and 192 → 48 kHz aliases at −21 dB. A device not at 48 kHz gets a hidden second
conversion. `SRCQualityMeasure` prints −7.23 dB at 20 kHz and still says PASS (council R-6). Apple's Mastering
converter measured flat to 21 kHz, with aliases at or below −160 dB.

### KI-DEV-03 — An Enhanced start just after a device connects can end silent or on the wrong device

**Status:** OPEN · **Severity:** MEDIUM · **Source:** council C-28 (P5B-04; [reconnect re-check
§5](../reviews/2026-10-council/working/p5b-reconnect-recheck.md)) · **Scheduled (2026-10-14):** Engine sprint ·
**Forward:** [EP-PLAYENGINE](backlog.md#ep-playengine--the-engine-sprint).

An Enhanced start races the output-device rule (`AudioEngineBridge+Playback.swift:96, 123`): 1–3 of every 11–36
explored interleavings end silent or on the wrong device, for example Play right after Bluetooth headphones connect.
R1's device-return fix (N92) did not change this.

### KI-SEC-01 — With FFmpeg turned on, a third-party C parser reads files Apple can't, inside the app

**Status:** OPEN, narrowed in R1.1-A · **Severity:** LOW (security; only with FFmpeg turned on) · **Source:** council
C-99 (the pre-mortem §3.1) · **Scheduled (2026-10-15):** pool — an XPC helper for the parse, or deletion after the
real-corpus check (FD-3 keeps FFmpeg) · **Forward:** US-R1F-16.

What R1.1-A closed ("FFmpeg only when asked for"): FFmpeg is an opt-in, **off by default** (Settings ▸ Formats, "Use
FFmpeg for other formats"; `ListeningSettings.useFFmpeg`). While it is off nothing calls `dlopen` for it
(`FFmpegLoader.h`; the null test counts the calls): the tag pass and Pure's decode fallback use Apple only. The tag
pass reads through Apple first for every format, FFmpeg only when it is on and Apple can't read the file — so it no
longer runs first on every FLAC / Ogg / Opus. When on, it loads only from `/opt/homebrew/lib` or `/usr/local/lib`, by
its exact major-versioned name (no bare name, `@loader_path` or DYLD search), only when the file the path resolves to is
owned by root or the user and neither it nor its folder is writable by anyone else (`vetLibrary`), opened by that
resolved path and checked with `dladdr` to be that file; the major-version guard stays.

**What remains, when the listener turns it on:** FFmpeg's demuxers and decoders are C code that parses files from
anywhere — a downloaded album — inside the app's own process, with the user's rights, no sandbox and no XPC wall. A
crafted file Apple can't read reaches them. Its own dependencies (libdav1d, libx264 …) load by the absolute install
names Homebrew built them with, not vetted one by one. A notarized build would need `disable-library-validation` to
load it at all. *(As found at `a206107`:)* the tag pass ran FFmpeg's demuxers first on every `flac`, `ogg`, `oga` and
`opus` file, loaded from `/opt/homebrew/lib` (user-writable), `/usr/local/lib`, or by bare leaf name
(`FileDecodeSource.cpp:386-399`), whenever FFmpeg was installed.

### KI-PURE-01 — On Pure, each pause and resume switches the DAC's sample rate twice

**Status:** OPEN, unverified on hardware · **Severity:** MEDIUM · **Source:** council C-100 (the pre-mortem §3.2) ·
**Scheduled (2026-10-14):** parked (FD-5) · **Forward:** US-ENG-07 (the USB-DAC check).

Pause is a stop (`AudioViewModel+Transport.swift:45-47`); on Pure, stop runs `tearDownPure()`, which releases hog mode
and restores the device's original nominal rate (`HALOutputEngine.mm:350-351`). A 44.1 kHz file on a DAC that sits at
48 kHz switches rate at every pause and again at resume. Many DACs click or mute when that happens, and another app
can take the device during the pause. *(R1.1-A, founder 2026-10-16:)* the device's **volume** no longer moves with it:
the engine knows a pause from a stop (`stopAudio(epoch:pausing:)`), and Pure's hold on the device's volume lasts while
Pure is the device's path (`MasterGainOnPure`, `PureVolumeEvent`) — a pause keeps the level Pure set; only the rate
and hog mode still go and come back.

*(KI-UI-02 — the spectrum analyser read about 4 dB high and two 20 Hz timers ran while idle — and KI-UI-03 — the
analysis workers polled about 200 times a second while paused — were fixed in R1.1-A; see
[Closed](#fixed-in-r11-a--live-readouts-branch-r11areadouts).)*

---

## Known limitations (by design or not yet built)

These are not defects; each is a decision or a planned feature. They are listed so a user of R1 isn't surprised.

| Limitation | Why / where decided | Forward link |
|---|---|---|
| The R1 build is ad-hoc signed and **not notarized**: macOS asks once (Open Anyway) | Founder decision 13 ([glass-sweep plan](../sprints/s10-8-glass-sweep-plan.md)); `Makefile` `dist`, PR #87 | US-REL-01 — release readiness, deferred (FD-7, 2026-10-14) |
| **Pure Mode on Bluetooth / AirPlay** falls back to Enhanced | The link re-encodes, so bit-perfect is impossible (`PureModePolicy.cpp`; `evaluatePureViable`) | — (by design) |
| **Pure Mode plays a track only when its channel count is the device stream's**: a mono file on stereo speakers, or a stereo file on a 4- or 8-channel interface, plays in Enhanced, and Settings says so ("Pure Mode can't play this track on this device…") | R1 fix (PR #88, d540c5c; council D71): before it, such a track played endless silence. `PureModePolicy.cpp:126-135` (`ChannelCountMismatch`); mapping inside Pure (AUHAL `ChannelMap`) is not done | US-ENG-07 follow-up (unscheduled) |
| **On Pure, Master Gain turns the output device's own volume down** (the macOS volume shows it): Pure engages at any level, lowered by the cut from the level found and put back when Pure is left — a stop that ends playback, Enhanced starting, the output moving, quit — but **not at a pause** (founder 2026-10-16: playback resumes there, so the level stays and the Mac's volume indicator doesn't jump); a volume-key press in Pure, or while paused in it, is kept, read as a change to the Mac's own volume with the cut on top, and Pure never sets the device above the level it found (a big raise in Pure comes back capped). **On a device with no volume the app can set** (many DACs, HDMI), Pure waits while Master Gain is turned down, and says so ("Pure waits: Master Gain") | R1.1-A (founder 2026-10-15, council C-29; replaces "Pure waits" where a volume exists). `MasterGainOnPure` (EQEditKit). A device unplugged while lowered gets its level back at the next launch, or the next Pure start on it | — (by design) |
| **Pure Mode declines a device format it cannot write exactly** (non-interleaved, unsigned, 8- / 20-bit, 16-in-32, float64): the track plays in Enhanced | R1 fix (PR #88, d540c5c; council D74): `NativePcmFormat::fromAsbd` (`include/PureModeFormat.h`) admits only float32, int16, packed 24, 24-in-32 and int32 | — (by design) |
| There is **no way to open or play a single file** outside the library (no Finder drop, Open… or Open With), and none to add a non-library file to a playlist | The store supports it (`addLooseFileToPlaylist`, `LibraryStore+Playlists.swift:422`), but the only UI entry was removed with the S9 IA change (7058667 in PR #23, "Now Playing is the queue only") and never re-added | US-LIB-02, US-PLIST-02 — R1.1-B (2026-10-14) |
| A **copy-then-delete move** (cross-volume drag, rsync) gets a new identity: play count, loved flag and playlist entries do not follow | Move-match keys on `(dev, inode, size, mtime)` + format (`LibraryStore+MoveMatch.swift`); `content_hash` is the deferred escape hatch (SEQ-1 Gate 2) | Post-R1 pool (council C-57) |
| **Gapless on the FFmpeg fallback** (Opus / Vorbis pre-skip) is not trimmed. Rare since R1.1-A: FFmpeg is an opt-in, used only for a file Apple can't open (Apple opens Ogg Opus and Vorbis on macOS 26). AAC and MP3 are fine: they decode through Apple on both paths, whose edit list trims the priming | `FileDecodeSource.cpp` (Apple first; FFmpeg only if Apple can't open the file and it is on); `AudioEngineBridge+Gapless.swift:37-42` | US-PLAY-07 → S11-lite |
| **FFmpeg plays only through Pure Mode**: a file only FFmpeg reads (FFmpeg on) plays in Pure on a device Pure can use; Enhanced decodes through Apple only, so there it can't play. FFmpeg turned off after it loaded stays in memory until the app quits (nothing new uses it) | R1.1-A (FD-3): Enhanced is `AVAudioFile`; Pure's decoder is `FileDecodeSource` | — |
| **DSD** is not supported | Deferred past R2, gated on a DSD DAC ([sprint-plan](../sprints/sprint-plan.md) §5) | post-R2 |

---

## Closed

### Fixed in R1.1-A — live readouts (branch `r1.1a/readouts`)

Council C-51, C-52, C-53 and C-46's last half (US-R1F-15, US-R1F-12). Seven commits, named by their subjects: "the
analyser hands the main thread whole frames — a triple buffer, no torn frame", "the spectrum analyser reads true —
every sample, its own band, 0 dBFS for a full-scale sine, at every rate", "the analysis workers sleep while no audio
reaches them", "one live clock — the analyser drawn as one Canvas, sampled only while a song plays and shows; caps in
real time", "the transport tick sleeps when nothing plays", "VoiceOver hears live readings as values, polled", "a
paused lens shows the latest frame as it is". Each fix
landed with its red test first; the tests failed on `2c6e4df` and pass after (Swift: `SpectrumAnalyzerOracleTests`,
`SpectrumHandoffTests`, `LiveReadoutsTests`, `LiveReadoutSpeechTests`; the null test: `Loudness_WorkersSleepWhileIdle`).
KI-UI-01 (VoiceOver's load) has its code causes fixed and waits for a VoiceOver check (above).

#### KI-UI-02 — The spectrum analyser reads about 4 dB high; two timers run while idle

**Status:** ✅ CLOSED in R1.1-A. *The level and the resolution* ("the spectrum analyser reads true"): a 0 dBFS sine
read +3…+4.26 dB (vDSP's normalised Hann scaled as a plain one), the analyser read only the first 4096 frames of each
~100 ms tap buffer (21 % of the audio at 192 kHz) with N = 4096 at every rate (47 Hz bins at 192 kHz: bands shared
bins, the lowest took in DC). Now a short-time FFT runs over every sample — a Hann window of the shipped 85 ms at
every rate (4096 / 8192 / 16 384 frames at 48 / 96 / 192 kHz), half-window hops, zero-padded ×2 — each magnitude is
divided by the window's sum, each band owns the bins inside its 1/6-octave span, and the window's mean is removed.
Measured (`SpectrumAnalyzerOracleTests`, an independent sine oracle): a tone at each of the 44 band centres reads its
dBFS within 0.35 dB, in its own band, at 44.1–192 kHz (before: +1.6…+4.2 dB, the 100 Hz tone in a neighbour's band
from 88.2 kHz up); a burst late in a buffer shows; DC lights nothing. The bars sit ~4 dB (5 % of the lens) lower.
*The timers* ("one live clock", "the transport tick sleeps"): the lens, the EQ's silhouette and Monitoring draw on one
display clock (`LiveTimeline`), running only while a song plays and the window can be seen, and read one
non-observable sampler (`SpectrumSampler`); the lens is one `Canvas` in the shipped look (picture sheets: EQ and
Monitoring identical to the pixel; Now Playing within 5 / 13 of 255 levels on 0.13–0.21 % of pixels, at cap edges).
The 20 Hz transport tick runs only while a song plays or a start, pause or stop is on its way. Measured on the real
views offscreen, under the app's run loop: the lens while playing 116 → 32.6 ms of main-thread CPU a second (6.3 →
0.54 ms per update, drawn 60 times a second instead of 20); paused, 40 engine reads a second → 0, Monitoring's 70 →
0. The peak caps run in real time (they held 1.2 s and fell at half speed: frames come every ~100 ms, each fed a
nominal 1/20 s) — `LiveReadoutsTests`. An energy reading (Activity Monitor's Energy Impact: idle, paused, playing) is
the release checklist's, on the founder's Mac.

#### KI-UI-03 — The real-time analysis workers poll about 200 times a second while paused

**Status:** ✅ CLOSED in R1.1-A ("the analysis workers sleep while no audio reaches them"; its "Integrated" half
closed in the sound lane, above). The normaliser's meter (`LoudnessModule`) polled its ring every 5 ms and the causal
loudness estimate (`CausalLoudnessTap`) every 50 ms, for the AU's whole life — also while playing with leveling off
(the faithful default) or bit-perfect, which feed the normaliser nothing. One primitive, `WorkerParking`
(`include/WorkerParking.h`), serves both: a worker naps while audio flows and, after 200 ms with nothing, parks on a
`std::atomic` wait until the render thread hands it a block (one atomic add per push; a futex wake only when parked)
or it is asked to stop. Measured (`Loudness_WorkersSleepWhileIdle`, the process's context switches in 300 ms of idle):
57 / 60 / 80 on `2c6e4df` (the normaliser paused, a kernel at rest, a causal estimate waiting), 1–3 now; clean under
TSan.

#### KI-ENG-01 — `SpectrumDoubleBuffer` data race

**Status:** ✅ CLOSED in R1.1-A ("the analyser hands the main thread whole frames"). The two-slot buffer let the tap
thread lap a slow reader and overwrite the slot it was copying. `SpectrumTripleBuffer` is the C++ snapshot's
wait-free triple buffer (`TripleBufferSnapshot.h`) in Swift: three raw slots and one control word, swapped with one
acquire-release exchange per side. `SpectrumHandoffTests` (a writer that never pauses against a reader slowed
mid-read, 1 s): about one read in ten tore on `2c6e4df`, none now; clean under TSan.

### Fixed in R1.1-A — the sound chain does what it says (branch `r1.1a/sound`)

Council C-39, C-42 (with C-30's classification slice), C-46 and C-50, and the founder's decision of 2026-10-14 that
crossfeed works on its own (US-R1F-12). Five commits, named by their subjects: "flush-to-zero only while our DSP runs — scoped, then restored", "one hit on the ceiling no longer ducks the music for a second — a program-dependent release",
"crossfeed plays on its own, and it is bs2b — no centre notch", "headphones in the Mac's own jack get crossfeed, an AirPlay speaker does not — one output classifier", "“Integrated” measures the playing track, not the session". Each fix landed with its red test first: the tests failed on
`481c822` and pass after (in the C++ null test: `Crossfeed_CentreFlat_vs_bs2b`, `Crossfeed_ChannelSeparation`,
`Crossfeed_CoeffRecomputeAcrossRates`, `Crossfeed_MatchesBs2bReference`, `Crossfeed_PlaysAtAnyIntensity`,
`Crossfeed_Off_BitExact`, `Limiter_Release_TransientIsFast`, `Limiter_TruePeak_CeilingWithCrossfeed`,
`Render_FlushToZero_Scoped`, `Loudness_MeterBridge_IntegratedPerTrack`, `OutputDevice_Headphones`; in Swift:
`Tests/AdaptiveSoundTests/CrossfeedPlaysTests.swift`). Also closed here, with no entry of its own: council C-50 —
flush-to-zero was set on every render call and never restored, on AVAudioEngine's I/O thread (which Apple's own nodes
share, inside our pull) and on the libdispatch thread that ran `initialize()`; it is now scoped to our own render calls
and workers and restored (`ScopedFlushToZero`, JUCE's `ScopedNoDenormals`), and the `LufsMeter.h` comment that FZ
doesn't flush doubles is corrected (it does, council D67). The analysis workers' polling while paused (KI-UI-03),
still open after this lane, was closed by the live-readouts lane (below).

#### KI-SND-05 — Crossfeed makes no sound while Intensity is held at 0

**Status:** ✅ CLOSED in R1.1-A, "crossfeed plays on its own, and it is bs2b — no centre notch" (founder decision 2026-10-14). Crossfeed is an output stage of the
kernel of its own — after the Intensity blend and the normaliser, before the limiter (`DSPKernel::renderOutput`) — and
plays at its preset's full strength whatever Intensity is. Turned on at Intensity 0 it takes the kernel off the
bit-perfect path (P0 → P1: EQ → crossfeed → limiter); turned off, it glides out over 32 ms and the kernel is bit-exact
again after the 2 s hold. The level control that scaled it twice (the app sent each preset's α as a "level", and the
Realizer multiplied the preset's α by it: Relaxed played α² ≈ 0.11) is gone. Measured (`Crossfeed_PlaysAtAnyIntensity`):
a left-only 300 Hz tone, Strong — near ear −3.836 dB, far ear −9.291 dB at Intensity 0, ½ and 1, as bs2b (before: the
far ear silent at 0, −13.3 dB at ½). The hero's "XF" chip shows whenever crossfeed plays (`SignalPathInfo.audibleCrossfeed`),
and VoiceOver reads it. *The original entry:*

~~**Status:** OPEN · **Severity:** MEDIUM · **Source:** R1.1-A (FD-2) implementation, code reading 2026-10-15 · **Scheduled:** R1.1-A — needs a founder decision · **Forward:** US-R1F-12.~~

*(As found at `481c822`:)* Crossfeed sits in the coloration chain that Intensity blends in (QW1 design: "the Reimagine knob scales it",
[qw1 design](../sprints/qw1-quick-win-differentiators-design.md)). At Intensity 0 the kernel runs P0 (bit-exact) or
P1 (EQ → limiter), and neither runs the chain (`DSPKernel.cpp:229-244`; P0's bypass test ignores crossfeed too). Before
FD-2 the 0.20 default played a 20 % blend of it; now that Intensity is hidden and held at 0, the Headphones ▸
Crossfeed switch turns on and is kept across launches, but nothing changes in the sound (the hero's "XF" chip, gated on
Intensity > 0, already doesn't show). Recommended: US-R1F-12's bs2b rewrite moves crossfeed out of the blend, as an
output stage after it and ahead of the limiter, so it plays at full strength whatever Intensity is; the alternative is
to hide the switch with Intensity until S17.

#### KI-SND-04 — Crossfeed notches the centre; its "Default" preset is mislabelled

**Status:** ✅ CLOSED in R1.1-A, "crossfeed plays on its own, and it is bs2b — no centre notch" (council C-42). The crossfeed is bs2b, re-implemented from libbs2b's
published `bs2b.c` (MIT; not linked — OQ-17): a high-boost shelf on the direct path and a low-pass on the cross path, the
interaural delay being the low-pass's own group delay (~0.25 ms) — no delay line (`Spatial/CrossfeedModule`, coefficients
from bs2b's `init()` in `Realizer.mm`). The strengths are bs2b's own levels: Relaxed = Jmeier (650 Hz, 9.5 dB),
Default = Cmoy (700 Hz, 6.0 dB), Strong = bs2b's default (700 Hz, 4.5 dB — its strongest). Measured against a
transcription of `cross_feed_d()` as the oracle: centred content 0.1–10 kHz now falls smoothly to −1.06 / −1.48 /
−1.75 dB (bs2b's own shelf; was a −4.2 / −4.5 / −6.3 dB notch at 1 kHz), within 0.0001 dB of bs2b; the module matches
bs2b sample for sample within 1.5e-7; the low-frequency feed is −9.53 / −6.03 / −4.53 dB. Gates:
`Crossfeed_CentreFlat_vs_bs2b`, `Crossfeed_MatchesBs2bReference`, `Crossfeed_ChannelSeparation`. With crossfeed on, the
true-peak ceiling still holds (`Limiter_TruePeak_CeilingWithCrossfeed`: worst −1.19 dBTP at −1, −0.32 at −0.1). *The
original entry:*

~~**Status:** OPEN · **Severity:** MEDIUM · **Source:** council C-42 (P2-3, D44, D45) · **Scheduled (2026-10-14):** R1.1-A · **Forward:** US-R1F-12.~~

*(As found at `481c822`:)* The crossfeed counts the interaural delay twice and leaves the direct path flat (`Spatial/CrossfeedModule.cpp:95-120`),
so a centred voice gets a −4.2 to −6.3 dB notch near 1 kHz. The fix follows the bs2b ladder (Jmeier / Cmoy / bs2b),
reimplemented from the published algorithm; libbs2b itself stays unlinked (OQ-17).

#### KI-DEV-01 — Crossfeed is unavailable on wired headphones in the Mac's own jack

**Status:** ✅ CLOSED in R1.1-A, "headphones in the Mac's own jack get crossfeed, an AirPlay speaker does not — one output classifier" (council C-42, C-30's classification slice). One output classifier
decides an output's family and whether it is headphones (`classifyOutputDevice`, `DeviceListPolicy.cpp`, HAL-free and
tested case by case — `OutputDevice_Headphones`); `CoreAudioDevice` reads the facts, the view model only reads the
verdict (`AudioDeviceModel.isHeadphones`). The output's data source decides first (`kAudioDevicePropertyDataSource`):
'hdpn' is headphones — the Mac's own jack included, on its built-in transport — and the internal or an external speaker
is not ('ispk' / 'espk'; the MacBook Pro's speakers read 'ispk'). Without one, or with a line or digital out, the
transport decides: Bluetooth and USB yes, AirPlay no (a receiver: a HomePod, a TV). Limits: a Bluetooth speaker that
reports no data source still reads as headphones (crossfeed plays there only if the listener turned it on); a pre-2018
Mac whose single built-in device switches its data source when headphones go in is read when the device list is, with
no data-source listener. *The original entry:*

~~**Status:** OPEN · **Severity:** MEDIUM · **Source:** product council, code reading 2026-10-13 · **Scheduled (2026-10-14):** R1.1-A (headphones detected by data source, with the crossfeed fix — council C-42, C-30) · **Forward:** US-R1F-12, US-R1F-06 (and S13 device identification).~~

*(As found at `481c822`:)* The headphone gate is "USB or wireless transport" (`AudioViewModel.isHeadphones`, `AudioViewModel+Devices.swift`), and the device type comes from the
transport alone (`Sources/AudioDSP/CoreAudioDevice.cpp:326-343`). The Mac's headphone jack reports the built-in
transport, so wired headphones there are "not headphones": crossfeed is disabled with the "Connect headphones" hint.
The converse also holds: AirPlay speakers count as wireless headphones. The code comment names only the USB false
positive.

#### KI-SND-03 — The limiter's fast release never runs

**Status:** ✅ CLOSED in R1.1-A, "one hit on the ceiling no longer ducks the music for a second — a program-dependent release" (council C-39). The release is program-dependent: two branches, the
deeper wins, each attacking with its own speed — the fast one in 0.5 ms (it holds the ceiling), the slow one in 100 ms
(so only sustained limiting charges it) — and releasing with its own τ, 100 ms and 500 ms, after its own 50 ms LF
hold (`LimiterModule::EnvelopeBranch`; a hold the fast branch's attacks kept re-arming must not pin a deeper slow branch
down, which `Intensity_EndpointsBitExact_Settled` caught in review). Measured on a 5 ms burst at 7.7 dB of reduction: −1.71 dB at 200 ms, −0.23 at
500 ms, −0.09 at 1 s, τ 99.5 ms (was −5.71 / −3.13 / −1.15, τ 500 ms); after 2 s of sustained limiting the release is
still the slow one, τ 499.5 ms (`Limiter_Release_TransientIsFast`, `Limiter_Release_SustainedIsSlow`). The ceiling test
now holds the published −1 dBTP itself, not −1 + 0.30 dB (worst −1.18 dBTP). The golden master was re-baselined
(`0xF0E1D4EF83763709`): its boosted chirp touches the ceiling; with only the old release restored the hash is the old
one, bit for bit. *The original entry:*

~~**Status:** OPEN · **Severity:** MEDIUM · **Source:** council C-39 (P2-1, D34) · **Scheduled (2026-10-14):** R1.1-A · **Forward:** US-R1F-12.~~

*(As found at `481c822`:)* The dual-release branch is dead code (`LimiterModule.h:398-416`); in practice it is one 500 ms release. A single snare
hit that touches the ceiling ducks the music for about a second. Only audible when the limiter engages (Enhanced, with
Intensity above 0 or the EQ on).

### Fixed in R1.1-A — hygiene, and a paused folder says why (branch `r1.1a/hygiene`)

Council C-86, C-87 and C-88, and the founder's paused-folder decision of 2026-10-15 (KI-LIB-02, narrowed — see its entry
under Library). Also closed here, with no entry of its own: council C-87's latent crash — the effects AU's render block
called the host's pull block without checking it, so a render with nothing connected upstream would have crashed (the
spatial AU's copy of the same scaffold checked it). Both AUs now share one scaffold, and with it the one guard:
nothing upstream answers "no connection". Its test came first: `Tests/AdaptiveSoundTests/InProcessAUNoUpstreamTests.swift`
renders each AU through its own render block with no pull block; before the fix the test process died with a
segmentation fault, after it both answer `kAudioUnitErr_NoConnection`. Removed as dead (no caller in the app, its gates
or its tests; C-86): the AUs' direct create / destroy, parameter stubs, second publish plane and spatial routing
override; `RtSwappableResource` (it leaked) and `PerChannel`; the Pure test tone `ToneSource`; and the Enhanced
reference tone, which scheduled a mono buffer on the stereo player — a start now always names its file. Stale
contracts, comments and scripts fixed (C-88): the dead `build-eq-clamp-test.sh`, the snapshot's always-true `bool`
(`TripleBufferSnapshot`), the "swift test is broken" notes, and the docs-arch drift list.

#### KI-ENG-03 — A stale comment names the removed `loudnessMeter` field

**Status:** ✅ CLOSED in R1.1-A (hygiene, council C-88): the comment now says the wrapper is dropped by resetting the taps'
analysis. *The original entry:*

~~**Status:** OPEN (the residual of rev-arch's "removed APIs" note; the semgrep message and the gapless comments were fixed in 17bef99 / 13f6281, PR #86) · **Severity:** internal · **Scheduled (2026-10-14):** R1.1-A (hygiene, council C-88) · **Forward:** US-R1F-07.~~

*(As found:)* `Sources/AdaptiveSound/LoudnessMeterHandle.swift:25` said "drops the wrapper (nils `loudnessMeter`)".

### Fixed in R1.1-A — Pure honesty, Master Gain on Pure, FFmpeg as an opt-in (branch `r1.1a/pure-ffmpeg`)

Council C-34, C-33, C-29, C-99, C-35 and C-08's scanner half (US-R1F-13, US-R1F-16, US-R1F-05); founder decisions FD-3
and 2026-10-15 ("turn the Mac's volume down instead"). Six commits, named by their subjects: "the scan admits .opus
and .oga", "FFmpeg only when asked for", "the FFmpeg seek lands on the frame asked for …", "Pure says why", "Master
Gain on Pure is the device's own volume — the rule …", "in Pure, Master Gain turns the output device's own volume
down …". Each fix landed with its red test first (C++: `FFmpegLoaderTests.inc`, `PureModeTests.inc`,
`FileDecodeTests.inc`; Swift: `LibraryScanFormatsGTests`, `MetadataFFmpegOptInTests`, `FLACPictureTests`,
`MasterGainOnPureTests`, `PureModeReasonTests`, `ListeningSettingsTests`, `SettingsStoreTests`).

- **C-34 — "Pure unavailable" never said why.** One named reason (`PureModeReason`: the C++ policy's codes across the
  C boundary, documented in `PureModeBridge.h`, plus the engine's own "waits for Master Gain") is shown beside the Now
  Playing badge ("Pure off: Bluetooth", "Pure off: needs FFmpeg", "Not bit-perfect" …), its sentence on hover, in
  Settings ▸ Pure Mode, and to VoiceOver. Pure's pre-check reads the file through Pure's own decoder
  (`pureModeEvaluateFile`), not a second `AVAudioFile` probe.
- **C-33 — a 24-bit file on a 16-bit-only device was labelled bit-perfect.** `bitExactness`: Pure decodes through
  float32 (24 significant bits), so an integer source is bit-perfect only up to min(24, the device's bits). It plays,
  labelled "Not bit-perfect" with both depths. *(Follow-up, founder 2026-10-16:)* where the device's integer word is
  narrower than what Pure carries, the float → integer step adds TPDF dither (±1 LSB, triangular, rounded to nearest —
  `convertFloatToNativeDithered`, `ditherWhenConverting`) instead of truncating: a −100 dBFS 1 kHz tone into int16
  comes out at −100.0 dBFS (truncation: silence); at −80 dBFS the 3rd / 5th harmonics fall from −97.9 / −115.6 to
  −139.0 / −150.4 dBFS; the error has no DC and the same power (¼ LSB²) at every input fraction. Exact depth stays
  bit-exact.
- **C-35 — the FFmpeg seek ignored the stream's start time, and a refused seek skipped the buffered audio.** Both
  count from the stream's start now (`streamStart`), and a refused seek moves nothing
  (`FileDecode_Seek_FFmpegHonoursStreamStart`, `_RefusedKeepsBufferedAudio`; fixture `Tests/Fixtures/ffmpeg-seek/`).
- **The FFmpeg tag pass had no fallback for what only it read.** With FFmpeg off by default, Apple reads FLAC / Ogg /
  Opus Vorbis comments in full (track, disc and genre added), a lossless file's source depth from its format flags, and
  a FLAC's cover — its PICTURE block, which AVFoundation doesn't expose, read in bounds-checked Swift (`FLACPicture`,
  also Ogg's base64 METADATA_BLOCK_PICTURE). VerifyLibraryStore's real-file checks pass with FFmpeg off.

#### KI-PB-05 — Pure on / off does not apply at a gapless seam, though Settings says it does

**Status:** ✅ CLOSED in R1.1-A, "Pure says why" (US-R1F-13). The copy says when the switch takes effect: Settings ▸ Pure Mode reads "Takes effect the next time you start a song", and the card "Pure Mode starts the next time you start a song" — a gapless join keeps the path, as the engine does. (Applying the switch at the next seam is not built.) *The original entry:*

~~**Status:** OPEN · **Severity:** MEDIUM · **Source:** breaker B post-R1 #3 · **Scheduled (2026-10-14):** R1.1-A (Pure honesty) · **Forward:** US-R1F-13 (was US-R1F-01).~~

The next track is armed on the path that is playing (`AudioEngineBridge+Gapless.swift:67-71`, the path read when the request is admitted); `pureModeEnabled`'s
`didSet` only logs (`AudioViewModel.swift:106-108`). Settings still says "Starts with the next track."
(`UI/Settings/PureModeSettingsSection.swift:18`, `UI/Settings/SignalPathStatus.swift:38`). The switch takes effect
only at a manual start or a rate-change reconfigure.

#### KI-SET-03 — A device volume lowered on Pure stays lowered on Enhanced

**Status:** ✅ CLOSED in R1.1-A, "in Pure, Master Gain turns the output device's own volume down" (council C-29: one level across both paths). Master Gain is one control: on Pure the engine turns the device's own volume down by it from the level it found (`MasterGainOnPure`), and puts that level back when Pure stops — so Enhanced plays the cut in the app on the device's own level, never on a lowered one. The listener's own change in Pure (the volume keys) is kept, read as a change to the Mac's own volume. "Silent" still sets the device to its minimum, which on some devices is not silence. *The original entry:*

~~**Status:** OPEN (residual of breaker B post-R1 #5, partly fixed by 124178d in PR #85) · **Severity:** LOW ·
**Scheduled (2026-10-14):** pool · **Forward:** US-R1F-05.~~

Every Enhanced start re-applies the app's gain (`AudioEngineBridge+Playback.swift:110`), so the old double-attenuation
and wrong readout are gone. The device volume set on Pure is the macOS output volume, and the Enhanced readout shows
only the app's gain, not it.

#### KI-LIB-05 — `.opus` / `.oga` files are playable but never scanned

**Status:** ✅ CLOSED in R1.1-A, "the scan admits .opus and .oga" (C-08 scanner half). Apple's decoder opens Ogg Opus and Ogg Vorbis on macOS 26, so no FFmpeg is needed; a format table holds every extension the scan admits to a real file that opens (`LibraryScanFormatsGTests`). *The original entry:*

~~**Status:** OPEN · **Severity:** LOW · **Source:** breaker A post-R1 #3 · **Scheduled (2026-10-14):** R1.1-A (Apple decodes Opus natively on macOS 26 — council R-19) · **Forward:** US-R1F-16 (was S11, format hardening).~~

`LibraryScanner.supportedExtensions` (`Sources/LibraryScan/LibraryScanner.swift:50-52`) has no `opus` / `oga`, while the
decoder plays them through the optional FFmpeg fallback and the extractor reads their tags
(`MetadataExtractor.swift:78`). PR #85 (f69421d) added only `.aif`. The scan says nothing about skipped files.

### Fixed in R1.1-A — playback correctness (branch `r1.1a/transport`)

Council C-15 and C-17 (US-R1F-01). Two commits, named by their subjects: "play, pause and stop do what was asked
last" and "what plays next follows the queue as edited". Each fix landed with its red test first, on the real view
model against the engine model of the bridge's semantics, both paths, in either order the commands reach the engine
(`Tests/AdaptiveSoundTests/TransportContractTests.swift`, `QueueEditContractTests.swift`), on the real bridge
(`EnhancedCommandOrderTests.swift`), and as rules (`PlaybackOrderTests` VM-PO-11…15, `QueueInsertTests` VM-QI-07/08).
The transport explorer (council P4's E1, on the shipped view model: `TransportExplorerTests.swift`) found "Playing"
over a silent engine in 116 of 3000 random schedules on `b5c4cd3` (112 with commands overtaking each other), and 0
after — no disagreement of any kind in 6000 schedules, nor in 30 000 more with other seeds; the A2 / A2′ residual
(KI-PB-16) is counted apart.

#### KI-PB-19 — Stop-then-Play or Pause-then-Play in quick succession can show "Playing" over silence

**Status:** ✅ CLOSED in R1.1-A, "play, pause and stop do what was asked last" (council C-15). A Stop or Pause is
numbered in the turn it is pressed, and is one engine call (the stop takes the on-deck pick with it). The engine runs a
start, seek or stop only if it has not begun a newer one (`AudioEngineBridge.beginTransportOperation`), so a Stop that
a Play overtook on its way to the engine is dropped; the view model applies a command's outcome only while it is still
the newest (`AudioViewModel.transportCommand`, `finish`). STOP-THEN-PLAY, PAUSE-THEN-PLAY and a Stop and a click in one
turn play what was asked, and show it. A Pause as a song ends no longer becomes an end of the queue that dropped the
place (P4-7). *The original entry:*

~~**Status:** OPEN · **Severity:** MEDIUM · **Source:** council C-15 (P4 E1, reproduced on the real view-model sources) · **Scheduled (2026-10-14):** R1.1-A · **Forward:** US-R1F-01.~~

*(As found at `b5c4cd3`:)* Stop and Pause take their epoch inside their `Task` (`AudioViewModel+Lifecycle.swift:160-161, 174-175`), Stop is two
engine calls, and there is no starting or pausing state. A quick Play after Stop or Pause can leave the engine silent
while the app shows Playing. KI-PB-04 is the same root seen from a slow start.

#### KI-PB-04 — Play / Space during a slow start restarts the song instead of pausing

**Status:** ✅ CLOSED in R1.1-A, "play, pause and stop do what was asked last" (council C-15). The view model has a
start state: a start, then its prime, until it settles (`transportCommand`). Space during a start pauses it at its
own place — Play resumes there — and never starts it twice; Next during a start starts the next song, so what is heard
is what is shown; a second Play (or Control Center's) joins the start. The play / pause control shows what was asked
last (`playIntent`): Pause from the press of Play on. *The original entry:*

~~**Status:** OPEN · **Severity:** MEDIUM · **Source:** breaker B post-R1 #1 (G-RACE-1) + freeze "Logged post-R1" (fast play-then-pause) · **Scheduled (2026-10-14):** R1.1-A (a starting / pausing state, council C-15) · **Forward:** US-R1F-01.~~

*(As found at `b5c4cd3`:)* `isPlaying` becomes true only after `engine.startAudio` returns and the start's on-deck prime settles
(`AudioViewModel+Playback.swift:74`); `pause()` guards
on it (`AudioViewModel+Transport.swift:46`) and the toggle calls `play()` again (`:57-62`). There is no "start in
flight" state. PR #86 (86a1cbe) fixed only the Stop case (`transportStopEpoch`); `rev-verify.md` records the rest as
still lost.

#### KI-PB-09 — A double-click on a queue row starts the song twice

**Status:** ✅ CLOSED in R1.1-A, "play, pause and stop do what was asked last" (council C-15). The row's guard reads
what was asked (`playIntent`), so a second click on the row that is starting joins the start. *The original entry:*

~~**Status:** OPEN · **Severity:** LOW · **Source:** sweep ledger, "Logged post-R1" · **Scheduled (2026-10-14):** R1.1-A · **Forward:** US-R1F-01.~~

*(As found at `b5c4cd3`:)* Same guard as KI-PB-08 (`PlaylistItemList.swift:165-175`): the second click lands before `isPlaying` flips, so a second
start is requested (and a second play is logged).

#### KI-PB-20 — A queued song can be skipped

**Status:** ✅ CLOSED in R1.1-A, "what plays next follows the queue as edited" (council C-17). After a queue edit — an
append, a drag, a removal — what plays next follows the edit, by one rule (`PlaybackOrder.onDeck(afterEditing:)`,
through `keepOnDeck`) in place of three special cases (the drag's re-anchor, `QueueAdvance.appendArmIndex`, the
removal's re-derive). In order it is the row now under the playing one: a song dragged in under it plays next, the next
song dragged away doesn't, an append to the last song plays next — under Repeat All too — and a one-song shuffle that
grew plays the new song. A shuffle pick or a Play Next stands. An append while the last song's start primes is armed
(the F-P4-1 sibling): edits re-arm from a start's prime on (`onDeckIsLive`). Play-now of the playing song restarts its
own slot, never an earlier copy of it (`QueueInsert.playNextNow` by slot, N6). *The original entry:*

~~**Status:** OPEN · **Severity:** MEDIUM · **Source:** council C-17 (P4-4, P4-5) · **Scheduled (2026-10-14):** R1.1-A · **Forward:** US-R1F-01.~~

*(As found at `b5c4cd3`:)* The on-deck pick is not recomputed after queue edits (`AudioViewModel+Queue.swift:183`, `guard isPlaying`). A song
dragged in under the current one never plays; with Repeat All an append waits a whole cycle; a one-song shuffle plus an
append stops. An append during a start's prime is not armed (its Play Next twin was fixed in R1, PR #88), and
`playNextNow` ignores duplicates.

### Fixed in R1.1-A — library safety and search (branch `r1.1a/library`)

Council lane 6 (C-55, KI-LIB-01, the C-58 / P5B-01 fix, the C-61 slice). Four commits, named by their subjects: "a walk
is evidence of what it read — an unreadable subfolder no longer stops its folder's sweeps", "Remove Missing never takes
a song whose drive is only unplugged", "search reads a word in any script, however it is stored — store v9", "the newer
of two filter reads always wins". Each fix landed with its red test first: the tests failed on `b5c4cd3` and pass after
(`Tests/AdaptiveSoundTests/PlaylistRemoveMissingTests.swift`; in `Tests/LibraryBrowseKitTests/`: `SweepEvidenceTests`
"C-55" and LIB-02a, `SearchScriptsTests`, `FileAvailabilityTests`, `SearchEpochTests` P5B-01; VerifyLibraryStore SE-2
and ST-1, the v8 → v9 upgrade). Also closed here, with no entry of its own: council C-58's P5B-01 — a filtered reload's
older read could land last and hide a newly scanned match (`SearchEpoch.beginRead`). Still open from the lane: the
paused folder's display (KI-LIB-02, a founder decision).

#### KI-LIB-01 — "Remove Missing…" deletes entries whose drive is merely unplugged

**Status:** ✅ CLOSED in R1.1-A, "Remove Missing never takes a song whose drive is only unplugged" (without a tombstone —
FD-10). A playlist entry's file is judged by the library's own sweep evidence (`LibraryScan/FileAvailability.swift`,
`LibraryScanner.availability`): AVAILABLE when it is there; MISSING only when nothing is at its path (`lstat` ENOENT /
ENOTDIR) and its music folder passes the check a walk makes before it starts (`LibraryScanner.rootAtPath`: there, on the
drive it is bound to — unbound, holding some of its songs) — for a song in no music folder, when the folder it was in
is there; otherwise UNREACHABLE (the drive unplugged, another drive with its name at its path, a folder the app may not
read). Remove Missing… offers only missing entries; its dialog says how many unreachable ones stay; an unreachable row's
badge says "Can't be reached — its drive may not be connected". The header still counts both as unavailable, and
neither plays. Consequence, the scanner's own: a music folder deleted whole from disk reads as unreachable too (it
can't be told from an unplugged drive, and the library keeps its songs alike), so its playlist entries are removed one
by one (the row's Remove). *The original entry:*

~~**Status:** OPEN · **Severity:** HIGH (irreversible playlist data loss, behind an explicit confirm the founder accepted
in Sprint E #12) · **Scheduled (2026-10-14):** R1.1-A (without a tombstone — FD-10) · **Forward:** US-R1F-03.~~

*(As found at `b5c4cd3`:)* Availability is a file-existence check only (`PlaylistsModel.swift:265-269`); `missingEntryIDs`
ignores whether the song's music folder is paused / unreachable (`PlaylistsModel+DeadFiles.swift:33-34`). *(Not covered
by R1's sweep-evidence fix, PR #88, which guards the scanner's sweep, not this dialog.)* With the music drive unplugged a
playlist's songs show as missing, and the dialog ("files that are missing from disk will be removed. This can't be
undone.", `UI/Playlist/PlaylistRemoveMissingDialog.swift:21-22`) removes them for good.

#### KI-LIB-11 — Search splits Sinhala words; decomposed text can't be found

**Status:** ✅ CLOSED in R1.1-A (the C-61 slice), "search reads a word in any script, however it is stored — store v9".
Store migration v9 (`Schema+SearchTokens.swift`, additive: the derived `tracks_fts` is recreated and rebuilt from
`tracks` through the write path's own projection; user data untouched) gives the tokenizer every mark as a token
character, `unicode61 remove_diacritics 2 categories 'L* N* Co M*'` (FTS5 §4.3.1): a Sinhala vowel sign is part of its
word, and only a Latin letter's accents fold. The index and every query are put in one normal form first
(`LibraryStore.searchText`) — NFKC, the compatibility form of the NFC the plan named, so a width or ligature variant
(ＪＡＰＡＮ, ﬁ) also meets its plain letters, as type-to-select already promised. The grids' Filter and type-to-select read
a word by the same rule (`LibraryBrowseKit/SearchFold.swift`, council N81 / P5B-07): "මා" selects "මාල", never "මිල".
Consequences: Greek and Cyrillic marks count (ά ≠ α, й ≠ и), as in the index. The three match SHAPES (a word's start,
a substring, the title's start) remain — KI-LIB-09, R1.1-B's one search rule. *The original entry:*

~~**Status:** OPEN · **Severity:** MEDIUM · **Scheduled (2026-10-14):** R1.1-A (tokenizer categories + NFC); R1.1-B (one
search rule + ⌘F) · **Forward:** US-R1F-14.~~

*(As found at `b5c4cd3`:)* The full-text tokenizer treats Sinhala vowel signs as separators, so "මාල" matches "මිල"; text
stored decomposed (NFD) can't be found from a composed query; type-select folds marks; and three search semantics exist
(KI-LIB-09) (`LibraryStore+Search.swift:16-48`).

### Fixed in R1.1-A — one converter across a same-rate seam (branch `r1.1a/seam-converter`)

Council C-22 (P3 D39 b–d, D40), brought forward from the Engine sprint by the founder (2026-10-14, "Fix now in
R1.1-A"), to ship with the Mastering converter (KI-SND-02), whose longer filter made the per-track click longer. One
commit, "a same-rate gapless join plays as one conversion". Its tests came first and failed on `481c822`:
`Tests/AdaptiveSoundTests/EnhancedSeamTests.swift` plays two 44.1 kHz tracks cut from one sound through the real bridge
on an offline engine, paced at a device's speed, records what the player plays (a tap, before the effects chain) and
compares it with ONE Mastering conversion of the joined input; it also pins the seam's frame, the playhead, a seek
before the join is heard, a next track shorter than a chunk, and a join to another rate or width. Five runs under a
16-process CPU load and a ThreadSanitizer run passed.

#### KI-GAP-04 — A click at each join between resampled tracks

**Status:** ✅ CLOSED in R1.1-A, "a same-rate gapless join plays as one conversion" (council C-22). A next track of the same
rate, channel count and layout continues the stream through the same converter (`continueStreamIntoNextTrack`), so a
join converts as one input would: the player's output equals one continuous conversion bit for bit (peak error 0, no
frame inserted or lost) with A ending 64, 4096 or 8100 frames into its last chunk. At `481c822` the join error was
0.019, 0.053 and 0.012 (−22, −13.5 and −26.5 dB re peak), and B came one frame early when A's converted length was
not whole. The seam is counted when the player has consumed A's last frame, with the playhead re-based by exactly A's
length (KI-GAP-02 narrowed). The P3 replica's 279-frame race at a short last chunk did not reproduce on the real code
at `481c822` (Mastering's flush gave its roll ~13 ms of lead, the replica's Normal converter ~1 ms); for these seams it
is gone by construction — no roll at the end of file, and the next file opens with a whole chunk of lead. A join to
another rate or channel count keeps a fresh converter, its click and its end-of-file roll (the Engine sprint's).
*The original entry:*

~~**Status:** OPEN · **Severity:** MEDIUM · **Source:** council C-22 (P3 D39 c) · **Scheduled (2026-10-14):** Engine sprint · **Forward:** US-R1F-02.~~

*(As found at `481c822`:)* Each track gets its own sample-rate converter (`AudioEngineBridge+GaplessRoll.swift:225`),
so the filter state restarts at the seam: a click 18 to 26 dB below peak at every join of a 44.1 or 96 kHz album.

### Fixed in R1.1-A — a faithful default and the listener's settings kept (branch `r1.1a/faithful-default`)

Founder decision FD-2 (2026-10-14). Four commits, named by their subjects: "SettingsKit — the listener's settings and
the one store that keeps them", "a faithful default", "remember the listener's settings", "Pure waits while Master
Gain is turned down". Each fix landed with its red test first: the regression tests failed on `ed19d0e` and pass after
(`Tests/AdaptiveSoundTests/ListeningSettingsTests.swift`, `Tests/SettingsKitTests/SettingsStoreTests.swift`,
`Tests/OutputDeviceKitTests/OutputDeviceRelaunchTests.swift`, `EQMigrationTests` MIGRATE-04 / -10).

#### KI-SND-01 — A fresh launch plays processed sound

**Status:** ✅ CLOSED in R1.1-A, "a faithful default" (council C-41). Intensity defaults to 0, is hidden
(`AudioViewModel.offersIntensity`) and held at 0 until S17 — never restored. At 0 the kernel runs P0 (bit-exact, with
the EQ off) or P1 (EQ → limiter at the EQ-only ceiling): never the normaliser (leveling, C-38) nor the blend's +2 dB
(C-40). A new install's EQ is Flat and Off (`EQMigration.freshInstall`); an existing EQ keeps its own memory. Leveling
becomes its own setting, off by default, in R1.1-B (US-R1F-10). Consequence: KI-SND-05 (closed by the sound lane:
crossfeed now plays on its own). *The original entry:*

~~**Status:** OPEN · **Severity:** MEDIUM · **Scheduled (2026-10-14):** R1.1-A (FD-2) · **Forward:** US-R1F-09.~~

*(As found at `ed19d0e`:)* Intensity defaults to 20 % (`AudioViewModel.swift:142`). That turns on the loudness normaliser, a session-long
integrator whose make-up gain carries across tracks (`LoudnessModule.cpp:62, 283`); the equal-power blend's +2 dB on
correlated material (`DSPKernel.cpp:274-275`); and the limiter's −1 dBTP ceiling. Clarity and BRIR are pass-through
stubs, so the control changes loudness, not sound. FD-2: Intensity 0, leveling off, EQ off at a fresh launch;
Intensity hidden until its effects are real (S17).

#### KI-SET-01 — Pure, device pin, Master Gain, Intensity and crossfeed reset at every launch

**Status:** ✅ CLOSED in R1.1-A, "SettingsKit" + "remember the listener's settings" (council C-102, C-12). Pure, Master
Gain, crossfeed and its strength, shuffle, repeat, "Keep playback on this device" and the chosen output are one typed
value (`SettingsKit.ListeningSettings`), kept by one store (`SettingsStore`, key `listeningSettingsV1`) in the
launch's defaults and restored when the view model is built (`AudioViewModel+ListeningSettings.swift`). Master Gain is
never restored louder than it was left: a stored level above unity or one that can't be read comes back Silent. A bad
field reads as its faithful default. Crossfeed is kept as chosen, not as the output allowed (`crossfeedPlays`).
Shuffle and repeat moved out of the queue cursor: kept on every change, restored with or without a queue. Intensity is
deliberately not kept (KI-SND-01). *The original entry:*

~~**Status:** OPEN · **Severity:** MEDIUM (Master Gain and Pure); LOW (the rest) · **Scheduled (2026-10-14):** R1.1-A
(FD-2) · **Forward:** US-R1F-05.~~

*(As found at `ed19d0e`:)* None has a defaults key: `pureModeEnabled = false` (`AudioViewModel.swift:106`), the pin `= true` (`:116`),
`intensity = 0.20` (`:142`), `crossfeedEnabled = false` (`:153`), strength (`:161`), and Master Gain `= unity`
(`:195`, commented "Not kept across launches (a post-R1 item)"). Only the EQ, the queue cursor (incl. shuffle / repeat),
the Songs columns and the Tone-card fold persist. Someone who turned Master Gain down hears 0 dB after a relaunch. The
output device the user chose is not kept either (DEV-1).

#### KI-SET-02 — A Master Gain cut in Enhanced does not carry into Pure

**Status:** ✅ CLOSED in R1.1-A (the C-29 slice), "Pure waits while Master Gain is turned down". Pure engages only with
Master Gain at 0 dB (`AudioViewModel.startsOnPure`); while it is turned down, Pure waits, Enhanced keeps playing at
the listener's level, and the Pure Mode card says why. Switching Enhanced → Pure never raises the level, in a session
or after a relaunch. *(Superseded later in R1.1-A by "in Pure, Master Gain turns the output device's own volume down"
(founder, 2026-10-15): Pure engages at any level, the device lowered by the cut; it waits only on a device with no
volume the app can set — KI-SET-03, closed above, is the rest of C-29.)* *The original entry:*

~~**Status:** OPEN (by design today; close to hearing safety) · **Severity:** MEDIUM · **Scheduled (2026-10-14):**
R1.1-A (FD-2) · **Forward:** US-R1F-05.~~

*(As found at `ed19d0e`:)* On Pure the slider shows and sets the device's own volume, and the app gain is not applied
(`AudioViewModel+MasterGain.swift:9-17`). Turning Master Gain down in Enhanced, then switching to Pure, plays at the
device's volume, which can be much louder.

#### DEV-1 — The chosen output device is forgotten when the app quits

**Status:** ✅ CLOSED in R1.1-A, "remember the listener's settings". The device the user chose (a pick, or turning
"Keep playback on this device" on) is read back from the engine's `OutputDeviceSelection`, kept with the listener's
settings, and handed back at engine-ready (`AudioPlaybackEngine.restoreChosenOutput` →
`OutputDeviceSelection.restoreChoice`). Handing it back is not a pick: the output rule, asked with `.choiceRestored`,
makes it the app's device when it is here — without touching the system default while nothing plays — and Play puts it
back as the default as in a session. The device the app launches on is still never a choice. Tests:
`OutputDeviceRelaunchTests`, `.choiceRestored` across `OutputDeviceRuleSpaceTests`, `ListeningSettingsTests` "the
device the user chose comes back after a relaunch". *The original entry:*

~~**Status:** OPEN (limitation; R1 ships with it) · **Severity:** MEDIUM · **Scheduled (2026-10-14):** R1.1-A (FD-2) ·
**Forward:** US-R1F-05 (with KI-SET-01).~~

*(As found at `ed19d0e`:)* Within a session the app remembers the output device the user picked (by UID) and returns to it
when it reconnects (`OutputDeviceSelection`). Nothing persists that pick, or the "Keep playback on
this device" switch, across launches. The device the app starts on is not a pick, so after a
relaunch nothing is chosen and the app follows the system default until the user picks again. So
if the user picked the speakers while their headphones were connected, then quit and relaunched,
the app plays wherever macOS sends the sound (the headphones) until they pick the speakers again.
Fix with the settings persistence work: store the chosen UID and the switch, and restore them at
launch. The in-session behaviour is guarded by `OutputDeviceReturnTests`,
`OutputDeviceChoiceTests` and `OutputDeviceRuleSpaceTests`.

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
  Limit: DEV-1 (closed in R1.1-A).
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
