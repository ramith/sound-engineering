# Known Issues

Tracked defects surfaced by tests/review that are not yet fixed. Each entry names the guarding test (or the
red test on a reference branch) where one exists, the place in the code, and where the fix is planned.

> **Reconciled to the code on 2026-10-13 (product council, against `main` at 7d7c2cd), and re-checked on 2026-10-14
> against `9df49e3`, after the R1 blocker fixes (PR #88, #89).** R1 shipped as **v1.0.0-alpha** on 2026-10-14 (tag on
> e2d6037, [release](https://github.com/ramith/sound-engineering/releases/tag/v1.0.0-alpha)). Every OPEN entry below
> was re-checked in the source after PR #85 (Sprint G), PR #86 (the disconnect-freeze fix) and PR #88; items those PRs
> fixed are listed under **Closed**. This page is the open list the [R1 release notes](../releases/v1.0.0-alpha.md)
> point to.
>
> **Scheduled 2026-10-14** by the founder's decisions on the council ([report](../reviews/2026-10-council/README.md),
> [roadmap](roadmap.md#the-post-r1-plan-council-2026-10-14)). The council's user-facing findings that had no entry
> here are now listed too, under [Found by the 2026-10 council](#found-by-the-2026-10-council); each names its
> register row (C-xx, [`stage5-architect.md` §1](../reviews/2026-10-council/working/stage5-architect.md#1-finding-register)).
>
> **Reconciled 2026-10-23** to the founder's decisions on the sound roadmap
> ([roadmap reconciliation](roadmap-reconciliation-2026-10/README.md), "Decisions taken"). Nothing was closed: every
> OPEN entry was re-checked in `main`'s source on 2026-10-23 and the code has not moved. What changed is the forward
> on the entries those decisions touch — each dated "decided 2026-10-23", naming the sprint, the fix in one line and
> the measurement that will prove it (the measurements are collected in the
> [validation strategy](../architecture/validation-strategy.md#verifying-the-2026-10-23-sound-decisions)). Two latent
> defects the reconciliation found are listed under
> [Found by the 2026-10 roadmap reconciliation](#found-by-the-2026-10-roadmap-reconciliation). The sprint names are the
> reconciliation's: **R1.1-B** (the next fix sprint — one sprint, no player / sound split), the **Engine sprint**,
> **S14-lite**, **S12**, **S13**, **S16**, **S17**, **S18**.
>
> **Amended 2026-10-25** to the founder's answers at R1.1-B's plan check
> ([sprint plan §11](../sprints/sprint-plan.md#11-founder-decisions-2026-10-25--r11-bs-plan-check)): Pure declines
> Bluetooth, so the XM4 always plays Enhanced, and leveling in Pure is deferred until the USB DAC arrives (the old
> auto-leveller, KI-PURE-01 and the two Pure rows under Known limitations); "Use this drive" (LIB-VOL-1) and the
> search rule (KI-LIB-09) carry the decided behaviour. R1.1-B lands in two PRs, the player PR first. Nothing closed.
>
> **Amended 2026-10-28** at the close of R1.1-B's player half (PR 1, branch `r1.1b/integration`;
> [sprint record](../sprints/r1-1b-record.md)). Closed: KI-PB-03 (shuffle as a permutation with history), KI-PB-21 (the
> queue's resume record, one writer), KI-LIB-09 (one search rule) and LIB-VOL-1 ("Use this drive"), under
> [Closed](#fixed-in-r11-b--the-player-half-pr-1-branch-r11bintegration); the Known limitations row on playing a single
> file from outside the library is delivered. Added: KI-PB-22 (a FLAC with very short blocks may crash the app —
> suspected), KI-PB-23 and KI-LIB-12, found on the sound half's test corpus (the record's
> [Test material](../sprints/r1-1b-record.md#test-material) describes it and its gaps); KI-PB-24, KI-LIB-13 and
> KI-UI-04, left by the player fix round; KI-LIB-14, the half of KI-LIB-09 the search rule did not touch; and, under
> Known limitations, the one limitation LIB-VOL-1 still accepts. KI-MC-02 is amended: the same fault at rates other
> than 48 kHz, through the resampler.
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
| KI-MC-01 | A 5.1 / 7.1 file on a stereo output plays only its front left and right: centre, LFE and surrounds are dropped | HIGH | R1.1-B (the BS.775 matrix + a per-track trim, FD-9 as amended 2026-10-23); the Engine sprint moves the fold into the engine; S18 renders in that slot | US-R1F-08 |
| KI-MC-02 | Channel roles come from positions, not the file's labels: an ALAC / AAC 5.1 file plays its centre on the left; 3-, 4-, 5- and 7-channel files fall back to stereo | HIGH | R1.1-B, before the fold; re-proved in the Engine sprint's acceptance (2026-10-23) | US-R1F-08 |
| KI-PB-18 | Dragging the scrubber to the end of a track that isn't 48 kHz stops playback for good | HIGH | R1.1-A | US-R1F-11 |
| KI-GAP-05 | An Enhanced gapless join to a file with a different channel count drops channels | HIGH | Engine sprint | US-R1F-02 |
| KI-PB-22 | A FLAC with very short blocks (under 192 samples) may crash the app — suspected: proven in a standalone probe, not yet in the app | HIGH if proven | R1.1-B (proved or cleared in the whole-app break-it; fixed in the sound PR's fix round if proven) | US-PLAY-06 |
| KI-PB-02 | Repeat turned off mid-song moves on, but with a gap | MEDIUM | Engine sprint | US-R1F-02 |
| KI-PB-06 | After a relaunch the restored song shows `--:--` and its scrubber is dead until Play | MEDIUM | R1.1-A | US-R1F-01 |
| KI-PB-08 | Clicking the paused current queue row restarts it from 0:00 | MEDIUM | R1.1-A | US-R1F-01 |
| KI-PB-10 | Add to Queue onto an empty queue leaves Play / Space disabled | MEDIUM | R1.1-A | US-R1F-01 |
| KI-PB-11 | "Restore previous queue" restores the wrong queue | MEDIUM | pool | US-R1F-04 |
| KI-PB-12 | A single click on a playlist row replaces the queue and plays | MEDIUM | pool | US-R1F-04 |
| KI-GAP-01 | A short gap at the seam between 48 kHz tracks | MEDIUM | Engine sprint | US-R1F-02 |
| KI-GAP-02 | At a resampled seam to another rate or width, the title and track B's gain switch up to ~0.2 s early | MEDIUM | Engine sprint (Leveling's seam tolerance until then, 2026-10-23) | US-R1F-02 |
| KI-SND-02 | Enhanced sample-rate conversion rolls off the treble (−8.25 dB at 20 kHz) and lets aliases through | MEDIUM | R1.1-A | US-R1F-11 |
| KI-EQ-01 | Unpinning an output overwrites the shared EQ, with no undo | MEDIUM | ~~pool (first candidate)~~ S12 (decided 2026-10-23: fixed with the per-output memory extension) | US-R1F-06 |
| KI-SND-06 | Crossfeed does nothing on a 5.1 / 7.1 file (it is stereo-only and runs before the fold), while the "XF" chip still shows | MEDIUM | R1.1-B (the chip and the switch read the kernel's bypass); the Engine sprint (crossfeed after the fold) | US-R1F-08, US-R1F-12 |
| KI-SND-07 | The EQ-only −0.1 dBTP ceiling is chosen by the transport alone, never by the output's rate — a wired DAC at 44.1 or 96 kHz would get it today, into an unmeasured conversion after the engine | LOW (latent: no non-48 kHz wired output in use) | Engine sprint (decided 2026-10-23: the rate condition; the conversion measured) | US-PE-03, NFR-QUAL-05 |
| KI-DEV-03 | An Enhanced start just after a device connects can end silent or on the wrong device | MEDIUM | Engine sprint | EP-PLAYENGINE |
| KI-LIB-02 | A folder whose walk fails outright says nothing; there is no Rescan control *(narrowed in R1.1-A: a paused folder says why)* | ~~MEDIUM~~ LOW | ~~R1.1-A~~ the rest: for triage | US-R1F-03 |
| KI-LIB-03 | A failed first metadata pass leaves "No Music Yet", with no retry | MEDIUM | pool | US-R1F-03 |
| KI-LIB-04 | Dragging a multi-selection onto a playlist adds one song | MEDIUM | pool | US-R1F-04 |
| KI-PURE-01 | On Pure, each pause and resume switches the DAC's sample rate twice (pause is a device teardown) — unverified on hardware | MEDIUM | parked (FD-5); its check list grew 2026-10-23 | US-ENG-07 |
| KI-ENG-05 | A library scan or metadata pass can starve the app's background work on a Mac with few cores | LOW | pool (recommended R1.1-B) | US-R1F-18 |
| KI-PB-07 | Next / Previous while paused keep the old song's duration | LOW | R1.1-A | US-R1F-01 |
| KI-PB-13 | Two quick tile Plays can land out of order | LOW | pool | US-R1F-04 |
| KI-PB-14 | Stalled ticks count as heard time (play counts) | LOW | pool | US-R1F-01 |
| KI-PB-15 | Recent says "Nothing Played Yet" when the store is not ready or the read failed | LOW | pool | US-R1F-04 |
| KI-PB-16 | A change of the next song in the last moments before a seam can still play the old pick (D41 residual A2 / A2′) | LOW | Engine sprint (seam identity) | US-R1F-01 |
| KI-PB-17 | A scrub back into a track that has already ended (nothing armed) is lost | LOW | Engine sprint (seam identity) | US-R1F-01 |
| KI-PB-23 | A truncated file shows its full length and stops at the cut; what the app does then is not yet checked | LOW | R1.1-B (the whole-app break-it) | US-PLAY-06 |
| KI-PB-24 | A loose queue slot whose file joins the library stays loose: not marked as playing in the Library, and not moved with the file | LOW | pool | US-LIB-02 |
| KI-GAP-03 | A narrow false seam on a Pure → Enhanced restart | LOW | Engine sprint | US-R1F-02 |
| ENH-001 | Short-track auto-advance is a reconfigure gap, not a seamless seam | LOW | Engine sprint | US-R1F-02 |
| ENH-002 | The UI loudness readout is L/R-only on a >2-channel output | LOW | pool | US-R1F-07 |
| KI-EQ-02 | Esc during a graph drag re-announces "Bring back edits" | LOW | pool | US-R1F-06 |
| KI-EQ-03 | Stacked-shadow darkening on EQ / Settings cards (dark + Reduce Transparency / Increase Contrast) — unverified | LOW | pool | US-R1F-06 |
| KI-EQ-04 | The EQ plays flat below 44 kHz, the designer's floor — latent while the graph is pinned at 48 kHz; live the day it follows the device rate (a Bluetooth headset with its microphone on) | LOW today (latent); HIGH once live | Engine sprint (decided 2026-10-23) | EP-PLAYENGINE (US-PE-01, US-PE-03) |
| KI-DEV-02 | HDMI / DisplayPort outputs read "(Unknown)" | LOW | pool | US-R1F-06 |
| KI-SEC-01 | With FFmpeg turned on (it is off by default), a third-party C parser reads files Apple can't, inside the app | LOW | pool (an XPC helper, or deletion after the corpus check — FD-3) | US-R1F-16 |
| KI-LIB-06 | Genres split on "/" ("Singer/Songwriter" → two tiles) | LOW | pool | US-R1F-04 |
| KI-LIB-07 | Case / Unicode variants split artist and genre tiles | LOW | pool | US-R1F-04 |
| KI-LIB-08 | Sorting Songs by Album orders each album's tracks by scan order | LOW | pool | US-R1F-04 |
| KI-LIB-10 | An empty playlist says "No Tracks Yet" (the app says "songs") | LOW | pool | US-R1F-04 |
| KI-LIB-12 | A 5.1 Opus file is admitted by the scan but cannot play (macOS 26 refuses multichannel Opus) | LOW | R1.1-B (the whole-app break-it) | US-PLAY-06 |
| KI-LIB-13 | macOS 26's NFC / NFKC turns a supplementary-plane letter followed by a combining accent into another character, so search loses that word | LOW (a known limitation) | none — re-index when SR-4 fails | US-R1F-14 |
| KI-LIB-14 | A rail jump clears the grids' Filter but keeps the Songs filter (the rest of KI-LIB-09) | LOW | pool | US-R1F-04 |
| KI-UI-01 | VoiceOver keeps the app fairly busy while a song plays — its code causes are fixed (R1.1-A, live readouts); not yet confirmed with VoiceOver | LOW | R1.1-A (founder's VoiceOver check) | US-R1F-15 |
| KI-UI-04 | "Search Library" (⌘F) replaces the Edit menu's Find, Spelling and Substitutions items: SwiftUI has no placement for Find alone | LOW (a known limitation) | none | US-R1F-14 |
| KI-ENG-02 | The main-thread stall self-test lacks the breaker's two extra modes and the 5 ms bound | internal | pool | US-R1F-07 |
| KI-ENG-04 | The `eq-light-folded` picture sheet flakes in the renderer | internal | pool | US-R1F-07 |
| KI-ENG-08 | A dead "Already in Queue" toast, and a negative index into `playTrack(at:)` | LOW | next time the file is touched | US-R1F-18 |
| KI-ENG-06 | Gaps left in the test seams (device-menu sort, two view countdowns, `FFmpegOptIn.isOn` shared in tests) | internal | pool | US-R1F-18 |
| KI-ENG-07 | `research/eq-engine-break-it/build-measure.sh` does not build | internal | pool | US-R1F-18 |

**Known limitations (by design or not yet built — not defects):** see [the last section](#known-limitations-by-design-or-not-yet-built).

---

## Playback and transport

*(KI-PB-01 — Pure ignored a changed next track — was fixed by PR #88 (council D41); see [Closed](#fixed-by-pr-88--the-r1-blockers-2026-10-14). Its residual windows are KI-PB-16 and KI-PB-17.)*

*(KI-PB-04 — Space during a slow start restarted the song — and KI-PB-09 — a double-click on a queue row started it twice — were fixed in R1.1-A, with KI-PB-19 and KI-PB-20 (council C-15, C-17); see [Closed](#fixed-in-r11-a--playback-correctness-branch-r11atransport).)*

*(KI-PB-03 — shuffle with Repeat off never ended the queue — was closed in R1.1-B with KI-PB-21, the queue's resume
record (council C-16, C-65); see [Closed](#fixed-in-r11-b--the-player-half-pr-1-branch-r11bintegration).)*

### KI-PB-02 — Repeat turned off mid-song moves on, but with a gap

**Status:** OPEN · **Severity:** MEDIUM · **Source:** sweep ledger, "Logged post-R1" (Sprint G) · **Scheduled (2026-10-14):** Engine sprint · **Forward:** US-R1F-02.

The view model re-arms correctly (`AudioViewModel+Playlist.swift:150-159` → `armOnDeck`). The seam is not re-armed
seamlessly: on 48 kHz files the gap is most likely KI-GAP-01. ~~On Pure the re-arm is refused (KI-PB-01).~~ *(Since PR
#88, D41: on Pure the re-arm is applied — the old pick comes off at once and the new one arms when its file opens; a
pick still opening when the song ends, or one of another rate or width, gives a short gap and the right song.)*

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

### KI-PB-22 — A FLAC with very short blocks may crash the app

**Status:** SUSPECTED — proven in a standalone probe, not yet in the app · **Severity:** HIGH if proven (the app quits
mid-play) · **Source:** the R1.1-B test corpus, 2026-10-26 (the sprint record's
[Test material](../sprints/r1-1b-record.md#test-material), corpus finding 4) · **Scheduled (2026-10-28):** R1.1-B —
proved or cleared in the whole-app break-it; fixed in the sound PR's fix round if proven · **Forward:** US-PLAY-06.

Apple's decoder opens a FLAC whose blocks are shorter than 192 samples, but reading it throws `fmt?`, and setting
`AVAudioFile.framePosition` on it raises an Objective-C exception nothing catches, which ends the process. The app sets
`framePosition` in two places: at every start and restart of a file played through the resampler — every file not at
48 kHz (`primeEnhancedResamplerLocked`, `Sources/AdaptiveSound/AudioEngineBridge+EnhancedResampler.swift:58`) — and when
a passthrough seam schedules the next file from its top (`scheduleFileChainingPassthrough`,
`AudioEngineBridge+GaplessRoll.swift:272`). Whether the app reaches either line with such a file, and what it does
then, is not yet checked.

### KI-PB-23 — A truncated file shows its full length and stops at the cut

**Status:** OPEN — what the app does at the cut is not yet checked · **Severity:** LOW · **Source:** the R1.1-B test
corpus, 2026-10-26 (the record's [Test material](../sprints/r1-1b-record.md#test-material), corpus finding 5) ·
**Scheduled (2026-10-28):** R1.1-B — checked in the whole-app break-it · **Forward:** US-PLAY-06.

Apple's decoder opens a file cut short (a download that stopped, a damaged copy) with the length its header states,
then reading it throws at the cut. So the song is listed, and its scrubber drawn, at the full length. How the app
handles the throw — the song's end, an error, the next song — is not yet checked.

### KI-PB-24 — A loose queue slot stays loose after its file joins the library

**Status:** OPEN · **Severity:** LOW · **Source:** the R1.1-B player break-it (M1's wider case) and fix round,
2026-10-26 · **Scheduled (2026-10-28):** pool · **Forward:** US-LIB-02.

A file played from outside the library is a loose slot: no `trackID` (`AudioFile(looseFileAt:)`). If the file then
joins the library while it is in the queue — added to a playlist from the queue, or reached by a scan of a folder
around it — the slot stays loose. The live queue re-reads only its library songs when the library changes
(`relinkLibrarySongs`, `Sources/AdaptiveSound/AudioViewModel+QueueHydration.swift:235-237`), the record keeps the slot
as `.loose(path:)`, and the restore brings a loose slot back loose (`resolve`, `:160-175`), so it stays loose across a
relaunch too, for as long as it is in the queue. Its plays are still counted, by its url — the play counter's
fallback for a song with no id (`AudioViewModel+PlayTracking.swift:69-74`). What it misses is what keys on the id: the
Library's lists and History do not mark it as playing (`playingTrackID`, `AudioViewModel+PlayingTrack.swift:10-13`;
`UI/Playlist/QueueHistoryList.swift:63-67`), Now Playing shows its embedded tags, not the library's
(`NowPlayingController.swift:191-195`), and when "Use this drive" moves the file the slot keeps the old path (`relink`,
`AudioViewModel+QueueHydration.swift:251`). The fix the fix round
named: the relink also resolves the loose slots by url, through the store's batched read
(`LibraryStore.tracksDisplay(urls:)`). A file opened while the store is still opening is not this case: the open waits
for the store (BI-P05, closed with KI-PB-21).

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

*(2026-10-23, card 1: Leveling's gain at a seam is applied "at the seam as the engine counts it" until the Engine
sprint — at a resampled seam to another rate or width that is this issue's 0–186 ms early; a same-format seam is not
early. The Engine sprint's acceptance carries "leveling at the seam" as a contract test: a gapless pair in Album mode
shows one constant gain across the seam, and in Track mode the gain changes on the first audible frame of B.)*

### KI-GAP-03 — A narrow false seam on a Pure → Enhanced restart

**Status:** OPEN · **Severity:** LOW · **Source:** freeze "Logged post-R1" · **Scheduled (2026-10-14):** Engine sprint · **Forward:** US-R1F-02.

The Enhanced seam count is never reset (`AudioEngineBridge.swift:179`); the view model's baseline is reset only after
`startAudio` returns (`AudioEngineBridge+Playback.swift:113`). In a narrow window after a Pure → Enhanced fallback the
tick can see a seam that did not happen.

### ENH-001 — Short-track auto-advance is a reconfigure gap, not a seamless seam

**Status:** OPEN (enhancement, low priority) · **Scheduled (2026-10-14):** Engine sprint (a 2-deep on-deck queue) · **Forward:** US-R1F-02.

*(KI-001 — "the VM stops mid-playlist on short tracks" — was **RESOLVED 2026-07-02**: analysis showed the VM already continues via `tickSpectrum()`'s `playbackEnded → advance to pendingNextIndex` branch; the stale `VM-AA-RTR-1` assertion was corrected to the continue behavior. Founder's continue/advance decision is satisfied. The full triage/panel narration is in git.)*

The short-track advance is a fresh-start reconfigure **gap**, not a gapless seam. Making it seamless for arbitrarily-short tracks needs an engine-side **2-deep on-deck queue** — a single on-deck slot can't arm track C until track B is current at the seam, and B may be shorter than the arm latency + the 20 Hz poll interval. Scheduled against the gapless backlog (US-PLAY-08 lineage); low priority (only tiny tracks; fallback is a brief gap, not a stop). ~~Guarded by `VM-AA-RTR-1` (`withKnownIssue` — fails when fixed, prompting a proper assertion).~~ *(Corrected 2026-10-13: `VM-AA-RTR-1` still exists — `Tests/AudioViewModelTests/AutoAdvanceReconfigureGapTests.swift:88` — but `withKnownIssue` was dropped in af34a53; it now asserts the fresh-start advance against mocks, so nothing fails when the seamless fix lands. The engine still has one on-deck slot: `onDeckURL`, `AudioEngineBridge.swift:174`.)*

---

## Multichannel

### KI-MC-01 — A 5.1 / 7.1 file on a stereo output drops centre, LFE and surrounds

**Status:** OPEN · **Severity:** HIGH (wrong audio: on most 5.1 music the centre carries the lead vocal) · **Source:**
the council's architecture reconciliation (2026-10-13), re-verified here · **Scheduled (2026-10-14):** R1.1-B ·
**Forward:** ~~S18 replaces the interim
truncation with the binaural fold ([S4 design](../sprints/05-sprint-5b-s4-binaural-design.md))~~ *(2026-10-23: the S4
design is superseded; S18 renders in the engine's stereo-out slot once the Engine sprint has moved the fold)*; ~~an interim fix (the S4
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

*(Decided 2026-10-23 — [roadmap reconciliation](roadmap-reconciliation-2026-10/README.md), cards 5 and 8.)*
**The interim, R1.1-B:** the standard fold matrix (ITU-R BS.775-4 Table 2: L′ = L + 0.7071·C + 0.7071·Ls, and the
mirror for R′) in the spatial unit where the truncation lives today, with a **per-track trim** from the folded true
peak the analysis measures — so the net after the fold is a backstop the trim keeps asleep; the **folded loudness**
measured in the same pass, so Leveling levels what the listener hears (the fold reads 1–2 LU under the six-channel
figure when the surrounds carry a modest share); the **LFE decided per track** from the analysis — include at full
level per side when it carries bass the mains do not, omit when it is a low-passed copy of the mains' bass (including
a copy adds +6 dB below ~120 Hz), omit when unknown, the trim computed with that gain (the loudness measurement ignores
LFE either way: BS.1770 weight 0, `Sources/AudioDSP/include/ChannelLayout.h:11-13`); a **"5.1 → stereo" badge**; and
the bit-perfect reason reads "…so Enhanced plays it, folded to stereo". Crossfeed does nothing on a folded file until
the fold moves, and the badge says so (KI-SND-06). FD-9's "with a ceiling after it" is **amended 2026-10-23: a backstop
the trim keeps asleep; one limiter after the fold once the fold moves into the kernel.** **The final arrangement, the
Engine sprint:** the fold inside the engine before the one safety net, crossfeed after it, one owner of the channel
layout from the decoder onward; S18's render then lives in the engine's stereo-out slot. **Proof** (the
[validation strategy](../architecture/validation-strategy.md#verifying-the-2026-10-23-sound-decisions)): the
analyser's folded true peak against libebur128's true peak of the actually folded stereo; a C-only sine folds to
−3.0 dB per side (L = R = C at equal level sums to +4.6 dB per side; the coherent worst case is +7.66 dB); with the
trim, the limiter's gain reduction ≈ 0 dB over the founder's surround albums; a stereo-in-5.1 file (C / LFE / Ls / Rs
silent) through the fold then crossfeed nulls against the plain stereo file through crossfeed — once crossfeed runs
after the fold; the two-album LFE listen on the XM4 (one album whose LFE carries bass the mains don't, one whose LFE
is a copy; a bass-heavy passage three ways, omit / −6 dB / full), pass / fail before it ships. *Prototype first:* the
folded-peak analysis over the founder's surround albums — trims mostly within 0–3 dB say the per-track trim is clearly
right; a cluster near 7 dB says a fixed trim is nearly as good.

## Settings and levels

*(KI-SET-03 — a device volume lowered on Pure stayed lowered on Enhanced — closed in R1.1-A; see
[Closed](#fixed-in-r11-a--pure-honesty-master-gain-on-pure-ffmpeg-as-an-opt-in-branch-r11apure-ffmpeg).)*

**The old auto-leveller** — *decided 2026-10-23, card 1 of the
[roadmap reconciliation](roadmap-reconciliation-2026-10/README.md): **removed in R1.1-B**, not switched off.* The
kernel's session-integrated normaliser is on in the code — `LoudnessParams{makeupGainLinear = 1, lufsTarget = −16,
enabled = 1}` (`Sources/AudioDSP/include/TargetState.h:60-66`; `kDefaultLufsTarget`, `AudioConstants.h:34`), with no
writer anywhere in `Sources/` — and nudges the level toward its target by up to 0.1 dB per gated block (≈ 1 dB/s),
anywhere from −20 to +12 dB (`Sources/AudioDSP/Loudness/LoudnessModule.cpp:276-299`; `LoudnessModule.h:55-57`). It is
silent today only because Intensity is held at 0: P0 and P1 never run it (`Sources/AudioDSP/DSPKernel.cpp:251-262`);
the day Intensity came back, so would it. **The fix, R1.1-B (US-R1F-10):** Leveling is Off / Auto / Album / Track at
**−18 LUFS**, one fixed gain per track or album through the existing per-track gain (`TrackLoudnessGain` →
`eq.outputGainDb`), capped at (ceiling − the track's true peak) — the analysis gains a true-peak field it has none of
today (`Sources/AudioDSP/Loudness/TrackLoudnessProfile.h:88-108`); a fixed −5 dB cut for a track of unknown loudness;
our own analysis first, a file tag only for a track not yet analysed; a gapless album takes the album gain even in
Track mode; the target shown; the normaliser deleted. In Pure, Leveling is a cut on the device's own volume through
the loan (the Master Gain row under [Known limitations](#known-limitations-by-design-or-not-yet-built)) *(amended 2026-10-25: Pure declines Bluetooth, so the XM4 always plays Enhanced — the premise that Pure is the founder's daily mode was wrong; leveling in Pure is deferred until the USB DAC arrives, verified there.)*. Nothing in
Intensity's return (S17) brings it back: Intensity scales only Clarity depth and the room amount, as settings.
**Proof** ([validation strategy](../architecture/validation-strategy.md#verifying-the-2026-10-23-sound-decisions)):
libebur128 on the published gain per track and album (`Loudness_Oracle_Integrated_vs_ebur128`'s 0.2 LU); the
limiter's gain reduction 0 dB over the leveled corpus; an Intensity sweep 0 → 1 → 0 with Leveling Off leaves
integrated LUFS within 0.1 dB (the AGC is gone, not hidden); a gapless pair in Album mode shows one constant gain
across the seam.

---

## EQ

### KI-EQ-01 — Unpinning an output overwrites the shared EQ, with no undo

**Status:** OPEN · **Severity:** MEDIUM · **Source:** breaker B post-R1 #7 · **Scheduled (2026-10-14):** pool (first candidate: it destroys user edits) · **Forward:** US-R1F-06.

`EQStore.unpin` sets `shared = slot.state` (`Sources/EQEditKit/EQStore.swift:112-115`; documented as intended at
`:109-111`, ui-plan §3.3); `togglePin` offers no Bring back (`EQSession+Slots.swift:76`). Every other output silently
loses its (possibly edited) EQ.

*(Decided 2026-10-23, card 6: **S12** — fixed in the same change that extends the per-output memory with the
parametric bands and the correction choice; unpinning stops writing the pin's state over the shared slot. Proof: a
Swift Testing case in `EQEditKitTests` — pin an output, edit, unpin: the shared slot's state is what it was before the
pin, and every other output plays what it played.)*

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

*(LIB-VOL-1 — a paused folder on a replaced drive stayed paused — and KI-LIB-09 — two Filter semantics — were closed in
R1.1-B ("Use this drive"; one search rule, council C-54, C-61); see
[Closed](#fixed-in-r11-b--the-player-half-pr-1-branch-r11bintegration). KI-LIB-09's rail-jump half is KI-LIB-14, below;
LIB-VOL-1's accepted rest is under [Known limitations](#known-limitations-by-design-or-not-yet-built).)*

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

### KI-LIB-10 — An empty playlist says "No Tracks Yet"

**Status:** OPEN · **Severity:** LOW (wording) · **Source:** breaker A post-R1 #14 · **Scheduled (2026-10-14):** pool · **Forward:** US-R1F-04.

`UI/Playlist/PlaylistDetailView.swift:88`; the rest of the app says "songs".

### KI-LIB-12 — A 5.1 Opus file is admitted by the scan but cannot play

**Status:** OPEN — what the app shows is not yet checked · **Severity:** LOW · **Source:** the R1.1-B test corpus,
2026-10-26 (the sprint record's [Test material](../sprints/r1-1b-record.md#test-material), corpus finding 5) ·
**Scheduled (2026-10-28):** R1.1-B — checked in the whole-app break-it · **Forward:** US-PLAY-06.

macOS 26's decoder opens stereo Ogg Opus (KI-LIB-05, closed in R1.1-A) but refuses a multichannel one (`fmt?`), while
the scan admits every `.opus` file (`LibraryScanner.supportedExtensions`,
`Sources/LibraryScan/LibraryScanner.swift:61-64`). So a 5.1 Opus file is listed as a song it cannot play. What the
app shows when it is played is not yet checked.

### KI-LIB-13 — macOS 26 turns a supplementary-plane letter followed by a combining accent into another character

**Status:** OPEN (a known limitation: the platform's) · **Severity:** LOW · **Source:** the R1.1-B player fix round,
2026-10-26 (found while pinning the search index's form) · **Scheduled (2026-10-28):** none — re-index when SR-4 fails
· **Forward:** US-R1F-14.

macOS 26's NFC and NFKC (`precomposedStringWithCanonicalMapping` / `…WithCompatibilityMapping`) compose a letter outside
the Basic Multilingual Plane followed by a combining mark as if it were the BMP character with the same low 16 bits:
U+200A8 U+0301 (a CJK ideograph and an acute accent) becomes U+0385, U+21FBF U+0301 becomes U+1FCE — both Greek accent
signs, which are no word characters (re-run on macOS 26, 2026-10-28). Search reads every title and every query through
NFKC (`SearchRule.normalized`, `Sources/LibraryStore/SearchRule.swift:56`), so both halves agree, but such a word is
lost to search: the title can't be found by it. VerifyLibraryStore SR-4 pins the behaviour: it hashes `normalized`'s
output over every assigned scalar — alone, after a word character, after a symbol, and followed by U+0301 — against
the form's golden
(`Sources/VerifyLibraryStore/ChecksSearchForm.swift:1-11`, `:35`), so an OS that fixes the composition fails SR-4,
which asks for a new form and a re-index. The same composition reaches the store's path normal form for a file name
holding such a pair (`PathNormalizer`, `Sources/LibraryStore/PathNormalizer.swift:48`, `:55`); not checked in the app.

### KI-LIB-14 — A rail jump clears the grids' Filter but keeps the Songs filter

**Status:** OPEN (the half of KI-LIB-09 the one search rule did not touch) · **Severity:** LOW · **Source:** breaker A
post-R1 #7 (with KI-LIB-09) · **Scheduled (2026-10-28):** pool · **Forward:** US-R1F-04.

A rail jump starts a category fresh, with no Filter text (S10.8 D6), but clears only the grids' Filter
(`selectCategory`, `Sources/AdaptiveSound/LibraryBrowseModel+Sidebar.swift:24-31`); the Songs filter (`searchQuery`,
`LibraryBrowseModel.swift:109`) is never cleared, so a rail jump to Songs keeps the last search.

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

### KI-UI-04 — "Search Library" (⌘F) replaces the Edit menu's Find, Spelling and Substitutions items

**Status:** OPEN (a known limitation: SwiftUI's) · **Severity:** LOW · **Source:** the R1.1-B player review, N8
(2026-10-26) · **Scheduled (2026-10-28):** none · **Forward:** US-R1F-14.

⌘F is the Library's search from any tab (R1.1-B, US-R1F-14), so its command replaces the Edit menu's text-editing group
(`CommandGroup(replacing: .textEditing)`, `Sources/AdaptiveSound/AdaptiveSound.swift:161-169`): the app has no document
text to find in, and one ⌘F means one thing. SwiftUI has no placement for the Find items alone: `.textEditing` also
holds Spelling and Grammar and Substitutions, which leave the Edit menu with them (by Apple's placement documentation;
not checked in the running app). A text field's own context menu still offers both. Keeping the group beside "Search
Library" would list two ⌘F items; rebuilding Spelling and Substitutions by hand would lose their check marks; editing
AppKit's main menu under SwiftUI is fragile, because SwiftUI rebuilds it. The reason is recorded beside the command.

### KI-ENG-02 — The main-thread stall self-test lacks the breaker's extra modes

**Status:** OPEN · **Severity:** internal · **Source:** freeze "Logged post-R1";
[evidence README](../architecture/evidence/main-thread-stall-2026-10/README.md) · **Scheduled (2026-10-14):** pool · **Forward:** US-R1F-07.

*(Narrowed in the test-rig redesign, 2026-10: the stopwatch is gone. The check holds the engine lock on purpose and
passes only if main keeps finishing its work during the hold — judged by behaviour, the founder's decision.)* What is
left: `Debug/MainThreadStallSelfTest.swift` runs `stop`, `start`, `device-loss` and `ended-advance`; port the breaker
harness's engineQueue-holder and first-play modes.

### KI-ENG-05 — A library scan or metadata pass can starve the app's background work on a Mac with few cores

**Status:** OPEN · **Severity:** LOW · **Source:** test-rig redesign, lane C's audit
([lane C report](../reviews/2026-10-testrig/lane-c-report.md)) · **Scheduled (2026-10-23):** pool (recommended: R1.1-B) ·
**Forward:** US-R1F-18.

`MetadataScanner.run` runs up to `min(cores, 6)` tasks on Swift's cooperative pool, each doing synchronous
AVFoundation tag reads and ImageIO thumbnails. `LibraryScanner.walk` does synchronous file enumeration there too. On a
3-core Mac a metadata pass can occupy the whole pool for its duration. The track-loudness analyser had the same shape
and was moved to its own queue in the redesign. Fix the same way: the synchronous work on a dedicated queue, the task
awaiting it. (The test suites don't hit this; they pass with one cooperative thread.)

### KI-ENG-06 — Gaps left in the test seams

**Status:** OPEN · **Severity:** internal · **Source:** test-rig redesign, lanes C and D · **Scheduled (2026-10-23):**
pool · **Forward:** US-R1F-18.

- The output-device menu's sort lives in the bridge, with no function a test can call; three old tests sorted a copy
  written in the test file (they are gone). Pull the sort into a function.
- `EQBringBackMessage` and `SongsView` keep their countdowns in private view code, so their injected clocks have no
  test; move each into a small model, as `ShellToastSlot` already is.
- `FFmpegOptIn.isOn` is process-global: a test that turns FFmpeg on shares it with every test in the process.

### KI-ENG-07 — `research/eq-engine-break-it/build-measure.sh` does not build

**Status:** OPEN · **Severity:** internal · **Source:** test-rig redesign, lane B · **Scheduled (2026-10-23):** pool ·
**Forward:** US-R1F-18.

Already broken before the redesign: its link list lacks `FFmpegLoader.cpp` and `DeviceListPolicy.cpp`. It now also
needs GoogleTest, because `TestSupport.h` includes it. Not gated (a research script).

### KI-ENG-08 — A dead "Already in Queue" toast, and a negative index into `playTrack(at:)`

**Status:** OPEN · **Severity:** LOW · **Source:** test-rig redesign, lane D (the mirror had drifted) ·
**Scheduled (2026-10-23):** next time the file is touched · **Forward:** US-R1F-18.

The app has allowed the same song in the queue twice since S10.2 (the founder keeps that), so the "Already in Queue"
toast can no longer appear for a real add: remove it. `playTrack(at:)` would trap on a negative index; no caller can
pass one today. Add `index >= 0` to its guard, with a test.

### KI-ENG-04 — The `eq-light-folded` picture sheet flakes in the renderer

**Status:** OPEN (cannot be judged from code) · **Severity:** internal · **Source:** sweep ledger, "Logged post-R1" ·
**Scheduled (2026-10-14):** pool · **Forward:** US-R1F-07.

---

## Found by the 2026-10 council

The council's register rows that a user can meet and that had no entry above. Each names its row in the
[register](../reviews/2026-10-council/working/stage5-architect.md#1-finding-register) (C-xx), where the full evidence
and the merged source IDs live. File:line references are from the council's reading (`7d7c2cd`, re-checked at
`9df49e3` where the register marks them ✓).

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

*(Amended 2026-10-28: the same family at rates other than 48 kHz.)* R1.1-B's design verify — its breaker, finding F1 —
found it on the Enhanced resampler path too. A file not at 48 kHz is converted from its own channel layout straight to
the graph's (`StreamingResampler(from: file.processingFormat, to: outputFormat)`,
`Sources/AdaptiveSound/AudioEngineBridge+EnhancedResampler.swift:169-170`), whose layout is MPEG 5.1 A or 7.1 A by
channel count (`Sources/AudioFormatKit/MultichannelFormat.swift:53-63`), so Apple's converter maps the channels by
layout: a 7.1 file with back surrounds loses them; an AAC 5.1 file is reordered to the graph's order, so roles read
from the file's own labels would land on the wrong channels; and a 3-, 4-, 5- or 7-channel file, whose count has no
layout and falls back to a stereo graph (`AudioEngineBridge+Reconfigure.swift:110-119`), keeps only L and R. It is
fixed first in R1.1-B's sound build, by lane 2 before the fold. It can be reproduced on demand with the test corpus:
see the sprint record's [Test material](../sprints/r1-1b-record.md#test-material), corpus finding 1.

### KI-GAP-05 — An Enhanced gapless join to a file with a different channel count drops channels

**Status:** OPEN · **Severity:** HIGH (wrong audio) · **Source:** council C-24 (BR-7, D39 A4) · **Scheduled
(2026-10-14):** Engine sprint · **Forward:** US-R1F-02.

The Enhanced roll compares only the sample rate (`AudioEngineBridge+GaplessRoll.swift:39-42, 77-81`). Mono → stereo
drops the right channel; a 6-channel file after a stereo one drops centre, LFE and surrounds, or plays silence. The
council default: a join that changes the format is an honest short gap with every channel present.

*(KI-PB-19 — Playing shown over silence after a quick Stop-then-Play — and KI-PB-20 — a queued song skipped — were fixed in R1.1-A (council C-15, C-17); see [Closed](#fixed-in-r11-a--playback-correctness-branch-r11atransport).)*

*(KI-PB-21 — a crash or force-quit lost the place in the queue — was closed in R1.1-B (council C-65); see
[Closed](#fixed-in-r11-b--the-player-half-pr-1-branch-r11bintegration).)*

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
load it at all. *(As found at `7d7c2cd`:)* the tag pass ran FFmpeg's demuxers first on every `flac`, `ogg`, `oga` and
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

*(Decided 2026-10-23: stays parked on the USB-DAC check (FD-5), and the check list grows — "volume keys during Pure,
then the end of the queue" (the loan's give-back), and Leveling's cut on the loan (card 1, R1.1-B — verifiable on the
XM4 now) *(amended 2026-10-25: Pure declines Bluetooth, so the XM4 always plays Enhanced — the premise that Pure is the founder's daily mode was wrong; leveling in Pure is deferred until the USB DAC arrives, verified there.)* *The give-back's "Volume restored" toast ships in R1.1-B and is
checked on the Mac's built-in output; Leveling's cut on the loan is checked here, on the DAC.* The Engine sprint's acceptance carries the output-side conversion measurement: a −0.1 dBTP signal through the
48 → 44.1 kHz AUHAL path, its peak read at a HAL tap or loopback; an overshoot beyond the limiter's 0.27 dB working
margin (`Sources/AudioDSP/Limiting/LimiterModule.h:103-105`) keeps the −0.1 dB ceiling's rate condition.)*

*(KI-UI-02 — the spectrum analyser read about 4 dB high and two 20 Hz timers ran while idle — and KI-UI-03 — the
analysis workers polled about 200 times a second while paused — were fixed in R1.1-A; see
[Closed](#fixed-in-r11-a--live-readouts-branch-r11areadouts).)*

---

## Found by the 2026-10 roadmap reconciliation

The [reconciliation](roadmap-reconciliation-2026-10/README.md)'s four reviewers read the plan and the source
([technical synthesis](roadmap-reconciliation-2026-10/technical-synthesis.md)); three defects a listener can meet had
no entry above. File:line references were re-checked in `main` on 2026-10-23.

### KI-EQ-04 — The EQ plays flat below 44 kHz

**Status:** OPEN, latent · **Severity:** LOW today (unreachable: the Enhanced graph runs at 48 kHz on every edge);
HIGH the day the graph follows the device rate (wrong audio: the screen says the EQ is on and nothing plays it) ·
**Source:** reconciliation card 9 (council C-49) · **Scheduled (2026-10-23):** the Engine sprint · **Forward:**
[EP-PLAYENGINE](backlog.md#ep-playengine--the-engine-sprint) (US-PE-01's discovery list; US-PE-03's acceptance).

The graphic-EQ designer's domain starts at 44 kHz: `kMinSampleRateHz = 44000.0`
(`Sources/AudioDSP/EQ/GraphicEQDesigner.h:63`; the reason at `:59-62` — below ~44 kHz the top band's centre,
19.95 kHz, is not safely under Nyquist). Outside it `design()` returns false and the Realizer publishes the identity —
"no EQ design at … Hz — playing flat" (`Sources/AudioDSP/AudioEngine/Realizer.mm:403-412`). Today the graph is pinned
at 48 kHz, so the case never arises. The Engine sprint moves processing to the device's own rate; a Bluetooth headset
with its microphone on drops to 16 or 24 kHz, and the EQ would silently play flat while the graph draws a curve and
the chip says it plays. **The fix (the Engine sprint's design, one of two):** a reduced band set below 44.1 kHz (the
centres above Nyquist dropped, the rest solved), or a 44.1 kHz floor on the engine's rate with AUHAL's output-side
conversion measured. **Proof:** with the band set, `EQ_Sweep31Bands_*` run at 16, 24 and 32 kHz — every band whose
centre lies under Nyquist plays within ±1.0 dB of its target (the existing contract) and the read-back marks the bands
that do not play; with the floor, the conversion measurement (a −0.1 dBTP signal through the AUHAL path, its overshoot
read at a HAL tap, inside the limiter's 0.27 dB margin).

### KI-SND-06 — Crossfeed does nothing on a 5.1 / 7.1 file, and the "XF" chip still shows

**Status:** OPEN · **Severity:** MEDIUM (what the screen shows is not what plays; the workaround is the format badge) ·
**Source:** reconciliation card 5 (the chain review's F13) · **Scheduled (2026-10-23):** R1.1-B — the chip and the
switch read the kernel's bypass, and the fold badge says crossfeed is off; the Engine sprint — crossfeed after the
fold · **Forward:** US-R1F-08, US-R1F-12.

Crossfeed is stereo-only: at any other width `CrossfeedModule::process` is a bit-exact pass-through
(`Sources/AudioDSP/Spatial/CrossfeedModule.cpp:47-54`; `isBypassed`, `:40-41`), and it runs in the effects unit at the
file's width N, *before* the spatial unit that narrows to the device (`AudioEngineBridge+Graph.swift:65-73`). So on a
5.1 album on headphones crossfeed never plays. The chip does not know: `SignalPathInfo.audibleCrossfeed` is the chosen
strength whenever the path is Enhanced (`Sources/AdaptiveSound/SignalPathInfo.swift:104-109`), from `crossfeedPlays =
crossfeedEnabled && deviceIsHeadphones` (`AudioViewModel.swift:233-235`) — the channel count is never consulted — and
the hero shows "XF:Strong" (`UI/NowPlaying/HeroBand.swift:110-115`). R1.1-B's interim fold keeps the fold in the
spatial unit, downstream of crossfeed, so the listener's switch still does nothing on a surround album until the
Engine sprint. **The fix:** R1.1-B — the chip and the crossfeed switch (the Headphones control from S18) read the kernel's own bypass, so "XF" never
shows when nothing plays and the "5.1 → stereo" badge says crossfeed is off here; the Engine sprint — the fold moves
inside the engine before the one limiter and crossfeed runs after it, on the folded stereo. **Proof:** R1.1-B — a 5.1
file on headphones with crossfeed on shows no "XF" chip and the switch says why (Swift Testing, `AdaptiveSoundTests`);
`Crossfeed_NonStereo_PassThrough` keeps guarding the kernel. The Engine sprint — a stereo-in-5.1 file (C / LFE / Ls /
Rs silent) through the fold then crossfeed nulls against the plain stereo file through crossfeed, sample for sample
within 1.5e-7 (the bs2b reference's own tolerance, `Crossfeed_MatchesBs2bReference`).

### KI-SND-07 — The EQ-only ceiling is chosen by the transport alone, not by the output's rate

**Status:** OPEN, latent · **Severity:** LOW today (the founder's only wired output, the HDMI soundbar, is 48 kHz-locked —
the engine's rate — so the case never arises); MEDIUM the day a wired DAC at 44.1 or 96 kHz is connected (a −0.1 dBTP
peak sent into a conversion nobody has measured) · **Source:** the reconciliation's ceiling decision ([architecture §0,
the decision-29 amendment](../architecture/architecture.md)) · **Scheduled (2026-10-23):** the Engine sprint ·
**Forward:** [EP-PLAYENGINE](backlog.md#ep-playengine--the-engine-sprint) (US-PE-03), NFR-QUAL-05.

`eqOnlyCeilingLinear(transportType)` returns the −0.1 dBTP EQ-only ceiling for every wired transport (built-in, USB,
FireWire, Thunderbolt, PCI, HDMI, DisplayPort, AVB) and −1 dBTP for everything else
(`Sources/AudioDSP/Limiting/OutputCeiling.h:19-40`); it never consults the device's sample rate. The 2026-10-23 decision
scopes −0.1 dBTP to outputs that are lossless *and* run at the engine's 48 kHz; on a wired output at another rate AUHAL
converts after the engine (unmeasured), so the decided ceiling there is −1 dBTP until the conversion is measured. Today
a 44.1 kHz USB DAC with the EQ on would get −0.1 dBTP. **The fix (the Engine sprint):** the ceiling selection takes the
transport *and* whether the device rate equals the graph rate; the sprint's conversion measurement (a −0.1 dBTP signal
through the 48 → 44.1 kHz AUHAL path, its overshoot read at a HAL tap, inside the limiter's 0.27 dB working margin)
then keeps the rate condition or lifts it. With the peak-safe turn-down (US-R1F-19) the limiter rarely acts on an
EQ'd track anyway, which makes the ceiling's exact value matter less. **Proof:** a null-test case that a wired device
whose rate differs from the graph rate gets −1 dBTP on the EQ-only path; the measurement above, recorded in the Engine
sprint's report.

---

## Known limitations (by design or not yet built)

These are not defects; each is a decision or a planned feature. They are listed so a user of R1 isn't surprised.

| Limitation | Why / where decided | Forward link |
|---|---|---|
| **The FFmpeg fallback works only with the FFmpeg major version it was built against** (today 9.x): with another major installed, files Apple can't open stay unplayable | FFmpeg guarantees its library ABI only within a major; the backend refuses a mismatch rather than crash (`FileDecodeSource.cpp`). The founder wants any version to work: researched 2026-10-22, scheduled later | US-R1F-17 ([research](../reviews/2026-10-testrig/ffmpeg-research.md)) |
| The R1 build is ad-hoc signed and **not notarized**: macOS asks once (Open Anyway) | Founder decision 13 ([glass-sweep plan](../sprints/s10-8-glass-sweep-plan.md)); `Makefile` `dist`, PR #87 | US-REL-01 — release readiness, deferred (FD-7, 2026-10-14) |
| **Pure Mode on Bluetooth / AirPlay** falls back to Enhanced | The link re-encodes, so bit-perfect is impossible (`PureModePolicy.cpp`; `evaluatePureViable`) | — (by design) |
| **Pure Mode plays a track only when its channel count is the device stream's**: a mono file on stereo speakers, or a stereo file on a 4- or 8-channel interface, plays in Enhanced, and Settings says so ("Pure Mode can't play this track on this device…") | R1 fix (PR #88, 231a927; council D71): before it, such a track played endless silence. `PureModePolicy.cpp:126-135` (`ChannelCountMismatch`); mapping inside Pure (AUHAL `ChannelMap`) is not done | US-ENG-07 follow-up (unscheduled) |
| **On Pure, Master Gain turns the output device's own volume down** (the macOS volume shows it): Pure engages at any level, lowered by the cut from the level found and put back when Pure is left — a stop that ends playback, Enhanced starting, the output moving, quit — but **not at a pause** (founder 2026-10-16: playback resumes there, so the level stays and the Mac's volume indicator doesn't jump); a volume-key press in Pure, or while paused in it, is kept, read as a change to the Mac's own volume with the cut on top, and Pure never sets the device above the level it found (a big raise in Pure comes back capped). **On a device with no volume the app can set** (many DACs, HDMI), Pure waits while Master Gain is turned down, and says so ("Pure waits: Master Gain"). **Never louder than Master Gain says** (close-out H-1): a cut deeper than the device's own range waits ("Pure waits: device range"); Silent mutes a device that has a mute (given back with the volume), else waits. While Pure already plays, the slider moved below the device's floor mutes a device that has a mute; **one without holds its floor until the next start**, which waits | R1.1-A (founder 2026-10-15, council C-29; replaces "Pure waits" where a volume exists). `MasterGainOnPure` (EQEditKit). The loans are written ahead of every device change (`PureVolumeLoanJournal`, H-2); a device unplugged while lowered gets its level back when it is seen again (a transport event, a device-list change) or at the next launch. **Decided 2026-10-23 (card 1, R1.1-B; deferred 2026-10-25 until the USB DAC):** the loan also carries **Leveling's cut in Pure** — cut-only, set at the track change, in the device's own steps (under the ~1 dB a listener notices between tracks, never inside one), the loan taught to tell its own moves from the listener's (today any reading more than 0.05 dB from its last set re-anchors as the listener's — `MasterGainOnPure.swift:179, 226-227, 276-277` — so an untaught loan would creep down track after track); the soundbar (`.fixed`: no volume the app can set) gets none and the badge says so; the readout shows both numbers; a "Volume restored" toast when Pure hands the device volume back (R1.1-B, ~~in US-R1F-10's Pure acceptance~~ US-R1F-20 since 2026-10-25; it fires on a stop that ends playback, the end of the queue, Enhanced starting or the output moving — not on a pause or a device loss). Proof: ~~ten Pure track changes on the XM4 leave the device at (the level found − the playing track's cut) within one device step, no creep;~~ the give-back returns the level found exactly. *(amended 2026-10-25: Pure declines Bluetooth, so the XM4 always plays Enhanced — the premise that Pure is the founder's daily mode was wrong; leveling in Pure is deferred until the USB DAC arrives, verified there.)* *The toast stays in R1.1-B — it reports this loan, Master Gain's, not leveling — and is checked on the Mac's built-in output; the leveling cut and its "ten changes, no creep" proof move to the DAC.* | — (by design); the Leveling cut: US-R1F-10 (deferred until the USB DAC); the toast: US-R1F-20 (R1.1-B) |
| **Every processing stage is Enhanced-only** — the EQ and crossfeed today; Leveling, Loudness, correction, Clarity and Spatial as they arrive — and in Pure each control shows one shared **"Not in bit-perfect mode"** state (first instance R1.1-B with Leveling — its row reads "Leveling off (bit-perfect)", founder 2026-10-25 — reused by every later stage; the Pure badge lists what is skipped); the Pure card says in one sentence why there are two "untouched" states (Pure, and Enhanced with nothing on ~~— over Bluetooth the same bits into the same encoder~~ *(corrected 2026-10-25: Pure declines Bluetooth, so over Bluetooth only Enhanced plays)*); Enhance in Pure reads "Not in bit-perfect mode — leave Pure?" with one tap | Decided 2026-10-23 ([roadmap reconciliation](roadmap-reconciliation-2026-10/README.md), cards 3 and 11, and the smaller items); ~~Leveling is the one stage that reaches Pure, on the device's volume (the row above)~~ *(2026-10-25: no stage reaches Pure in R1.1-B — leveling in Pure, on the device's volume, is deferred until the USB DAC; the row above)* | R1.1-B: US-R1F-20 (the shared row state; the Pure card's sentence); each later stage reuses it; Enhance's Pure line: US-UI-08 (S14-lite) |
| **A loose song off the startup disk is never offered by Remove Missing**, only shown unavailable — even if it was really deleted | R1.1-A close-out AV-1 (option b): a loose song has no drive binding, so only on the startup disk can its folder being there prove it gone; elsewhere a same-named drive may stand in its drive's place (`FileAvailability`) | a volume column on loose rows (option a, v10) if it is ever wanted |
| **Pure Mode declines a device format it cannot write exactly** (non-interleaved, unsigned, 8- / 20-bit, 16-in-32, float64): the track plays in Enhanced | R1 fix (PR #88, 231a927; council D74): `NativePcmFormat::fromAsbd` (`include/PureModeFormat.h`) admits only float32, int16, packed 24, 24-in-32 and int32 | — (by design) |
| ~~There is **no way to open or play a single file** outside the library (no Finder drop, Open… or Open With), and none to add a non-library file to a playlist~~ *(delivered in R1.1-B, PR 1: File ▸ Open… (⌘O), a Finder drop on the Library tab, Open With and a drop on the Dock icon play a file now without adding it to the library — a drop on the queue adds it at the end; Add Files… and a Finder drop add one to a playlist, as a song in no music folder; a loose file in the queue persists by its path, `QueueSlotRef.loose` (`Sources/PlaybackQueueKit/QueueSlotRef.swift`), with no `tracks` row — see KI-PB-21 under Closed, and KI-PB-24)* | ~~The store supports it (`addLooseFileToPlaylist`, `LibraryStore+Playlists.swift:422`), but the only UI entry was removed with the S9 IA change (67e4a50 in PR #23, "Now Playing is the queue only") and never re-added~~ *(the store's seam now has its UI callers: `PlaylistsModel+Add.swift`; the open paths: `AppDelegate.application(_:open:)`, `showOpenPanel`, `LibraryBrowseModel+LooseFiles.swift`)* | US-LIB-02, US-PLIST-02 — R1.1-B (2026-10-14) |
| **A music folder on a drive that reports no volume UUID** (some network volumes), all of whose files were moved or renamed at once, stays paused: "Use This Drive…" finds none of its songs at their old paths and refuses. Removing and re-adding it brings the songs back with new ids, without their plays, loves and ratings | LIB-VOL-1's accepted rest (closed in R1.1-B): such a folder is not bound to its drive and is walked only while some of its songs are where the library has them (`LibraryStore+Roots`, `SweepRefusal`); "Use this drive" matches a song by its path under the folder and its size (`LibraryScan/RootRebind.swift`) | — (accepted) |
| A **copy-then-delete move** (cross-volume drag, rsync) gets a new identity: play count, loved flag and playlist entries do not follow | Move-match keys on `(dev, inode, size, mtime)` + format (`LibraryStore+MoveMatch.swift`); `content_hash` is the deferred escape hatch (SEQ-1 Gate 2) | Post-R1 pool (council C-57) |
| **Gapless on the FFmpeg fallback** (Opus / Vorbis pre-skip) is not trimmed. Rare since R1.1-A: FFmpeg is an opt-in, used only for a file Apple can't open (Apple opens Ogg Opus and Vorbis on macOS 26). AAC and MP3 are fine: they decode through Apple on both paths, whose edit list trims the priming | `FileDecodeSource.cpp` (Apple first; FFmpeg only if Apple can't open the file and it is on); `AudioEngineBridge+Gapless.swift:37-42` | US-PLAY-07 → S11-lite |
| **FFmpeg plays only through Pure Mode**: a file only FFmpeg reads (FFmpeg on) plays in Pure on a device Pure can use; Enhanced decodes through Apple only, so there it can't play. FFmpeg turned off after it loaded stays in memory until the app quits (nothing new uses it) | R1.1-A (FD-3): Enhanced is `AVAudioFile`; Pure's decoder is `FileDecodeSource` | — |
| **DSD** is not supported | Deferred past R2, gated on a DSD DAC ([sprint-plan](../sprints/sprint-plan.md) §5) | post-R2 |

---

## Closed

### Fixed in R1.1-B — the player half (PR 1, branch `r1.1b/integration`)

Council C-16, C-65, C-61 (its R1.1-B half) and C-54, with the founder's answers at R1.1-B's plan check, 2026-10-25
(US-R1F-01, US-R1F-14, US-R1F-03; the loose files of US-LIB-02 and US-PLIST-02 are under *Known limitations*). Two
lanes, transport and library, combined; then a code review and a break-it, and one fix round. Each lane's new tests
were first seen failing against a planted bug. The break-it's red tests, BI-P01…BI-P10 (committed red at `b34acf8f`),
pass after the fix round. Two of them changed at the fix, as the [sprint record](../sprints/r1-1b-record.md) says:
BI-P05 was rewritten, because its stand-in store meant both "still opening" and "never opens", and now opens while the
store is opening and checks that the open waits; BI-P01 / BI-P02's precondition required the reused id, which is the
bug itself, and now requires the new song's id to be a new one. The lanes added migrations v10 (the queue's resume
state) and v11 (the search index without the zero-width joiners); the fix round added v12 (a removed song's id is
never handed to another) and v13 (a combining mark that follows no word is no word). All four are additive; the store
is at v13 (`currentSchemaVersion`, `Sources/LibraryStore/Schema.swift:35`). The combined check after the fix round is
in the record's [measured results](../sprints/r1-1b-record.md#measured-results).

#### KI-PB-03 — Shuffle on + Repeat off never ends the queue

**Status:** ✅ CLOSED in R1.1-B, "shuffle as a permutation with history; the queue's resume record, one writer"
(council C-16). Shuffle is a pass (`ShufflePass`, PlaybackQueueKit): every song of the queue once, in an order drawn up
front by Fisher–Yates from a generator whose whole state the pass keeps (`ShuffleGenerator`, SplitMix64), with the pass
before it kept as its history. Next steps on through the pass; Previous walks back through what played, and Next after
Previous goes on in the same order — it never re-rolls. Repeat off ends the queue after the pass; Repeat All starts a
new pass that never begins with the song that just ended. At a pass's first song Previous goes back into the last pass
with Repeat All and restarts the song with Repeat off, and Up Next keeps the queue's own order (both founder,
2026-10-25). A Play Next, or a song picked mid-pass, plays now and counts as played; an added song goes to a random
place after the song armed next, so the armed pick stands. `QueueAdvance` is queue order only (its random picker is
gone), and `PlaybackOrder` composes Repeat One, the pass and queue order. The pass is part of the queue's resume
record, so a relaunch brings back its order, place and history (KI-PB-21, below). Tests: in the Kit, `ShufflePassTests`
VM-SP-01…17 (VM-SP-01: a 100-song pass plays each song once, then the queue ends; VM-SP-15: over 24,000 seeded
5-song passes, each of the 24 orders of the last four songs is drawn 860–1,140 times) and `PlaybackOrderTests`
VM-PO-01…16 (VM-PO-04: Repeat off ends the queue at a pass's end); on the real view model, `ShuffleTransportTests`
VM-SH-01…12 (VM-SH-01: 100 songs, each heard once, then the queue ends, on the Enhanced and the Pure path). *The fix
round:* "a shuffle pass's bulk edits write its line once, not once per song" (review S3) — an edit of many songs (an
Add to Queue, a Play Next, the launch's join) builds the pass's line once, with the same random draws
(`LineInterleave`, a Fenwick tree over the free places), where one insert per song shifted about 10⁸ slots on the main
actor for a 20,000-song Add to Queue (VM-SP-16, VM-SP-17; `ShuffleBulkEditTests` VM-SB-01/02 on the view model, each
counted through `ShufflePassTally`, never a clock); and removing the selected song under shuffle selects the pass's
next song as a step on, not the row that slid in (review N2, in "a failed restore read keeps the writer closed; … a
removal under shuffle selects the pass's next"; VM-SH-12). *The original entry:*

~~**Status:** OPEN · **Severity:** MEDIUM · **Source:** sweep ledger, "Logged post-R1" · **Scheduled (2026-10-14):** R1.1-B (shuffle as a permutation with history, council C-16 — it also stops repeats and a random Previous) · **Forward:** US-R1F-01.~~

*(As found at `0215f777`:)* `QueueAdvance.nextIndex` returns a random pick before the end-of-queue check, and nothing
records which songs have played (`Sources/PlaybackQueueKit/QueueAdvance.swift:38-45`). With Shuffle on and Repeat off,
random songs repeat forever.

#### KI-PB-21 — A crash or force-quit loses your place in the queue

**Status:** ✅ CLOSED in R1.1-B, "the queue's resume state, one record written in one transaction" and "shuffle as a
permutation with history; the queue's resume record, one writer" (council C-65). The queue — its slots, the selected
one and the shuffle pass — is one record, `QueueResumeRecord` (PlaybackQueueKit), each slot named by `QueueSlotRef`: a
library song by its id, a loose file by its path, with no `tracks` row. It lives in two one-row tables migration v10
adds (`Sources/LibraryStore/Schema+QueueState.swift`): `queue_state`, the record and its revision, and
`queue_playhead`, the offset into the selected song and the revision of its record. Each write is one transaction
(`LibraryStore+QueueState.swift`), and a playhead for another revision is refused, so a kill at any instant leaves the
previous state or the next, never a mix. One writer: a `CoalescingWriter` whose sink, `writeQueueState`
(`Sources/AdaptiveSound/AudioViewModel+QueueMirror.swift:87`), is the only caller of the two writes. It writes at once
on every change to the queue, the selected song or the pass, at a pause, a scrub while paused, a stop and the quit;
while a song plays it writes the playhead alone each time it has moved 5 s of the song
(`QueueResumeRecord.playheadCadenceSeconds`, `Sources/PlaybackQueueKit/QueueResumeRecord.swift:29`), so after a crash
the queue comes back paused at most 5 s early. Nothing is written before the launch's restore has read the store — the
launch's empty queue never overwrites it — nor after the quit's last write. The restore
(`AudioViewModel+QueueHydration.swift`) brings back the songs, loose files included, the selected one at its place, and
the shuffle pass; a song gone since is dropped, and when it was the selected one the queue starts at the top (under
shuffle, at the pass's next song), never another song at the old offset. A library from before v10 is read once the
old way — the "current" playlist and the `queue.cursor.*` keys — and written as the record. From the restore on, the
live queue follows the library: a song "Use this drive" moved plays from its new path (VM-QS-10). Tests: in the Kit,
`QueueResumeRecordTests` VM-RR-01…07 and `QueueJoinTests` VM-QJ-01…07; on the real view model over a real
`LibraryStore`, `QueueRestoreTests`, `QueueRestoreJoinTests` and `QueueStateEdgeTests`, VM-QS-01…15 (VM-QS-03, the
cadence: the playhead at 4.9 s writes nothing, at 5.0 s the playhead alone, a pause at once); the process-level kill
harness, VM-KILL-01 (`QueueStateKillTests`: a child process runs the real view model over a real store file and is
sent SIGKILL at a random point, 100 times a run; every stored state must be whole, one the child reached and no older
than its last flush, and the next child must restore exactly it); VerifyLibraryStore QS-1…QS-5 (the v9 → v10 upgrade
keeps every user row; v10 is additive; a round trip; no half write; no mixed read). *The fix round:*
- **The launch join is a Kit rule** ("the launch join ends where opening after the restore would", review M2; BI-P03,
  BI-P03b). What was queued before the restore — a file opened at launch — joins the restored queue where the same
  open after it would put it (`QueueJoin`, `Sources/PlaybackQueueKit/QueueJoin.swift`, through
  `QueueInsert.playNextNow`): right after the restored song, first when none is selected, moving the restored queue's
  slot of the same file rather than doubling it. An Add to Queue made before the restore joins at the end. Both orders
  end in the same queue, song, next song and record (VM-QS-12: four cases, shuffle on and off). One rarer order is not
  exact, as the file's header says: two opens before the restore, the first of a file the restored queue holds.
- **A removed song's id is never handed to another** (migration v12, "a removed song's id is never handed to
  another"; BI-P01, BI-P02). The record names a library song by its id alone, and SQLite gave the next song added the
  highest removed id, so a restore, or the live queue's relink, could put a song the listener never queued in a
  removed song's slot, at its offset. A one-row high-water table and two triggers (`Schema+TrackIDs.swift`) give every
  new song an id above every id ever used, and refuse an insert at or below the mark (VerifyLibraryStore TID-1, TID-2).
- **A failed restore read keeps the writer closed** (review N1): a damaged record restores nothing, and the session's
  first change writes the queue whole (VM-QS-14); any other read failure is read once more, and a second failure keeps
  the writer closed for the session, so the stored queue is never overwritten by one the launch never read (VM-QS-13).
- **The old queue's entries go** (review N10): once the first record is written, the old "current" playlist's entries
  are cleared and the cursor keys removed; the built-in playlist row stays (VM-QS-05).
- **A playhead write builds no record** (review S5): the 5 s cadence, a pause and a scrub write the number alone,
  without rebuilding the whole record on the main actor (VM-QS-15, counted through `QueueStateBook.recordsBuilt`).

Also at the combine: a start keeps its slot, not its row, so a join that moves a song's row while it starts still
primes what follows it (integration, "a start keeps its slot"; VM-QS-11, whose name still says "known issue"). And an
open before the store has opened waits for it, so a library song opened at launch is queued as that song, not as a
loose path ("files from outside the library — matched once the store opens, read off main, in order"; BI-P05,
BI-P05b). *The original entry:*

~~**Status:** OPEN · **Severity:** MEDIUM · **Source:** council C-65 (LIB-12; product triage #3) · **Scheduled (2026-10-14):** R1.1-B (atomic queue restore) · **Forward:** US-R1F-01.~~

*(As found at `0215f777`:)* The queue cursor reaches UserDefaults only on a clean quit
(`AudioViewModel+Lifecycle.swift:125`), and the queue mirror's debounce can race its quit-flush
(`AudioViewModel+QueueMirror.swift:25-36`), although the kit already has a coalescing writer for exactly this
(`LibraryBrowseKit/CoalescingWriter.swift`).

#### KI-LIB-09 — Two Filter semantics

**Status:** ✅ CLOSED in R1.1-B, "one search rule (SearchRule) and the v11 joiner re-index" and "⌘F searches the
library; files from outside it play and join playlists" (council C-61, its R1.1-B half; founder 2026-10-25). One rule,
`SearchRule` (`Sources/LibraryStore/SearchRule.swift`, in the store: the lowest target both halves import): a query
finds an item when every word of the query starts a word of the item, in any order. Songs asks the full-text index
through it (`ftsMatchQuery`, one quoted prefix term per word: `LibraryStore+Search.swift:44-47`); the Albums, Artists,
Genres and Playlists Filters, the queue's filter and the playlist picker (`FacetTextFilter`), type-to-select (the
title's start, `SearchFold`) and ⌘F's sections match in memory through it. Its words are exactly the index tokenizer's
token characters, it folds as the tokenizer folds, and its text is NFKC with the zero-width joiner and non-joiner
folded away, so a Sinhala conjunct is one word typed with or without its joiner. Each tab keeps its own sort; "eyon" no
longer finds "Beyoncé" in the grids (accepted by the founder). ⌘F, "Search Library", opens the Library's Search page
from any tab; its sections — Songs, Albums, Artists, Genres, Playlists — keep exactly what each tab's Filter keeps,
ranked by one rule (`LibrarySearch`, `SearchRelevance`); the card Filters moved to ⌥⌘F. Migration v11 re-writes the
derived index in the rule's form (`Schema+SearchJoiners.swift`; DDL unchanged, user data untouched). Tests:
LibraryBrowseKitTests `SearchRuleTests`, `OneSearchRuleTests` (every query: the Songs search, the four Filters and ⌘F
keep the same items; the in-memory rule agrees with the index, song by song; "beyo" and "eyon"; Sinhala with and
without the joiner, NFD as NFC) and `SearchRelevanceTests`; AdaptiveSoundTests `LibrarySearchFocusTests` (⌘F from every
tab); VerifyLibraryStore SR-1 (every Unicode scalar but NUL — 1,112,063 — through the app's own SQLite tokenizer and the
rule: they agree on each), SR-2 (the v11 upgrade) and SR-3 (the plan check's counter-examples). *The fix round:*
- **One search gate** ("one search gate for every tab and ⌘F — two characters, or one syllable"; BI-P09, and the
  single CJK ideograph of the live keyboard pass). `SearchQueryGate.shouldQuery`
  (`Sources/LibraryBrowseKit/SearchFilterDecisions.swift:46-68`) searches a query of two characters, or of one that is
  a CJK ideograph, kana, a Hangul syllable or a letter of a Brahmic script. `FacetTextFilter.isActive` is that gate
  (`FacetTextFilter.swift:40-42`), so Songs, every Filter and ⌘F answer one query alike; a one-letter Filter in Albums
  no longer narrows while Songs shows everything (`SearchFilterDecisionsTests`).
- **A combining mark that follows no word is no word** (migration v13, "a combining mark that follows no word is no
  word (v13); the index form is pinned"; BI-P08 and the review's wider case). An emoji's variation selector made every
  emoji query find every emoji title ("❤️" found "☀️ Summer"). The rule now folds variation selectors and emoji
  skin-tone modifiers away and drops any combining mark that follows no word character, in the index and the query;
  v13 re-writes the index (`Schema+SearchMarks.swift`). The form the index is written in is pinned (review S6):
  `SearchRule.indexFormVersion` (3) names it, each re-index migration names the form it writes
  (`Schema.searchIndexForms`), and VerifyLibraryStore SR-4 fails when the rule's form is ahead of the latest re-index,
  or when `normalized`'s output over every assigned scalar differs from the form's golden, so a rule change cannot land
  without a re-index. SR-5 upgrades a v12 store that shows the fault.
- **A superseded ⌘F search is cancelled with its task** (review S4; `LibrarySearchFocusTests`).

Not part of the search rule, and unchanged: a rail jump clears the grids' Filter but not the Songs filter — now
KI-LIB-14. *The original entry:*

~~**Status:** OPEN · **Severity:** LOW · **Source:** breaker A post-R1 #7 · **Scheduled (2026-10-14):** R1.1-B (one search rule, council C-61) · **Forward:** US-R1F-04 → US-R1F-14.~~

*(As found at `0215f777`:)* Songs filters by FTS token prefix (`LibraryStore+Search.swift:47`), the grids by substring
(`LibraryBrowseKit/FacetTextFilter.swift:16`); "eatles" finds nothing in Songs. A rail jump clears the grids' filter
but not the Songs filter (`LibraryBrowseModel+Sidebar.swift:24-27`). *(R1.1-B, founder 2026-10-25: one word-start rule
everywhere — a word must start with what is typed — so the grids stop matching substrings and "eyon" no longer finds
"Beyoncé" in the Albums / Artists / Genres filters (accepted); each tab keeps its own sort and ⌘F's results are ranked
— US-R1F-14.)*

#### LIB-VOL-1 — A music folder is bound to its drive; a sweep needs evidence (R1 sweep-evidence fix)

**Status:** ✅ CLOSED in R1.1-B, "\"Use this drive\" — re-root a paused folder by relative path (+ size)" (council
C-54; founder 2026-10-25). A folder paused because its drive is gone, another drive is at its path, or its drive can't
be confirmed — `.rootVanished`, `.differentVolume`, `.unrecognizedFolder`, never `.incompleteWalk` or `.emptyWalk`
(`MusicFolderStatus.offersUseThisDrive`, `Sources/LibraryBrowseKit/MusicFolderStatus.swift:54-59`) — offers "Use This
Drive…", and the listener picks the folder on the drive that now holds its songs. The scanner looks for each song at
its path under the folder, with the same size (`RootRebinder`, `Sources/LibraryScan/RootRebind.swift`); the store
re-roots the folder in ONE transaction (`LibraryStore.rebindRoot`, `LibraryStore+Rebind.swift:139`): the songs found
keep their ids, plays, loves, ratings, frecency and playlist places; the songs not found are removed with their
history; the folder row moves to the new path, bound to the new drive; the albums regroup. Silently, as the founder
decided: no preview. Refused with nothing written, and said: none of the folder's songs is on the drive ("That’s not the
drive for “…” — none of its songs are on it. Nothing was changed."), the new location is, is inside or holds another
music folder, or the folder's songs changed since they were looked for. An ordinary walk follows, on the confirmed
drive. Tests: VerifyLibraryStore RB-1…RB-5 (8 of 10 songs at a new mount name keep their ids, plays, loves, ratings,
frecency and playlist places, the 2 missing go with their entries, and the walk after sweeps nothing; none found →
refused, nothing written; an overlap refused; the same path on a new drive, NFD names, an untagged album; 12 SIGKILLs
in a 1,200-song rebind leave the state before or after, never a mix); AdaptiveSoundTests
`UseThisDriveTests`. *The fix round* — "\"Use this drive\" keeps what it finds as the walk after it sees it" and "a
gone drive's stale (dev, inode) never passes for another drive's folder at an add":
- **The drive's own spelling and signature** (BI-P04, BI-P07). Each song is looked up through the drive's own listings —
  the same name in NFC first, else the one name that differs only in letter case — and only where a walk goes; the
  store takes each found file as the walk reads it: its url as the drive spells it and its own (dev, inode). Before, a
  kept song kept the old drive's move-signature, so a rename on the new drive deleted it with its history, and a
  case-only difference had the walk after the rebind sweep it (VerifyLibraryStore RB-6).
- **The songs not found go first, and only a loose row is merged** (review S1): a removed song's history could be
  merged into a kept song when the new folder is inside the old path; another folder's row at a found song's new url
  now refuses the rebind (RB-7).
- **A gone drive's stale identity** (BI-P06): a (dev, inode) pair is compared only with folders on the same drive, at
  the rebind and when a folder is added (`addRoot`), since macOS hands a gone drive's device number to the next one.
- **Its own words, and a checking state** (review N4): a folder that can't be read is refused as such ("That folder
  can’t be read — is its drive connected? Nothing was changed."), never as the wrong drive; while the drive is checked
  the row says "Checking the drive…", and its "Use This Drive…" and Remove are held (`MusicFolderStatusTests`; the
  `folder-checking` picture sheet).
- **The drive's other folders move with it** (plan check §6, counter-example 10): one choice moves the other paused
  folders bound to the same old drive, each looked for at its own place on the drive as mounted now
  (`RootRebinder.location(of:movedFrom:to:)`); one not there, or holding none of its songs, stays paused
  (`UseThisDriveAlongTests`, `RootRebinderLocationTests`).
- **And migration v12** (KI-PB-21, above): the ids of the songs a rebind removes are never handed to the songs the
  walk after it adds.

Still so, by design, and now under *Known limitations*: a folder on a drive that reports no volume UUID, all of whose
files were moved or renamed at once, stays paused, because the rebind finds none of its songs at their old paths.
*The original entry:*

~~**Status:** OPEN (accepted limitations) · **Severity:** MEDIUM · **Scheduled (2026-10-14):** R1.1-B ("Use this drive", council C-54) · **Forward:** US-R1F-03.~~

*(As found at `0215f777`:)* A folder is bound to its drive's volume UUID (the startup disk as itself, since its UUID
changes with the Mac); one on a volume that reports no UUID (some network volumes; FAT32/exFAT report one on macOS 26)
stays unbound and is walked only while some of its songs are where the library has them — so a folder all of whose
files were moved or renamed at once while unbound (on such a volume, or between the v8 upgrade and its first walk)
stays paused until it is removed and re-added; so does a folder whose drive is replaced by a different one with the
same name (a new or reformatted "T7")~~; and a folder with a subfolder the app can never read never has its deleted
songs swept~~ (`LibraryStore+Roots`, `SweepRefusal`). *(The struck limitation is fixed in R1.1-A, council C-55: the walk
spares only the songs under what it could not read — see KI-LIB-02.)* **Do not remove and re-add a paused folder as a
workaround:** removing a folder deletes every song of it that no playlist references, so re-adding it brings those
songs back with new ids — their play counts, loved flags and ratings are lost. ~~A lossless "use this drive" action on
a paused folder is on the council follow-up list (founder, 2026-10-14).~~ **"Use this drive" (R1.1-B; founder,
2026-10-25):** a silent rebind of the paused folder to its new drive — the folder's songs found there (matched by
relative path + size) keep their ids, plays, loves, ratings and playlist membership; the songs not found on the new
drive are removed, with their history (no preview); refused when none of the folder's songs are found — nothing
changes, and the app says it is the wrong drive. US-R1F-03. Also narrow: the first walk after the v8 upgrade binds
whatever drive is at the folder's path, so a same-name *backup* drive mounted at that moment can be bound instead of
the real one (found by the R1 break-it).

### Fixed in R1.1-A — the close-out break-it's FIX-FIRST items (branch `r1.1a/breakit-fixes`)

Library side (SET-1…4, AV-1) and audio side (H-1…5, D-1), each with the breaker's red test kept as a regression test
(red on b1cc33c):
- **SET-1 / SET-2:** Master Gain is never restored louder for any stored value — another plist type, unreadable
  JSON, a missing or non-numeric level all read Silent, and a damaged value is copied aside.
- **SET-3 / SET-4:** a damaged kept Pure volume loan is never put back above what Pure found, nor as a non-number;
  loans are read one by one.
- **AV-1:** Remove Missing never offers a loose song off the startup disk (see *Known limitations*).
- **H-5:** a Master Gain step on Pure reads the device first, so the listener's own volume change is never undone.
- **H-1:** a cut below the device's range waits; Silent mutes (see *Known limitations*).
- **H-2:** Pure's loans are written ahead of every device change, to their own journal — a crash at any instant
  gives the level back.
- **H-3:** a device lost mid-Pure and back in the same session gets its level back at once.
- **H-4:** a device found above 0 dB gets that level back.
- **D-1:** a 24-bit FLAC / ALAC read by Apple's decoder is known as 24-bit — dithered on a 16-bit word, labelled
  not bit-perfect. **Still owed on hardware (D-2):** whether the AU's negotiated format on a mixable 16-bit DAC
  stream is float32, which would hide the device's depth from the rule (one `logASBD` on a 16-bit DAC).
- **LOW:** a configure failure names the refused rate or channels instead of "device refused" — not unit-testable
  offline; owed with the USB-DAC / HDMI check (FD-5).

### Fixed in R1.1-A — live readouts (branch `r1.1a/readouts`)

Council C-51, C-52, C-53 and C-46's last half (US-R1F-15, US-R1F-12). Seven commits, named by their subjects: "the
analyser hands the main thread whole frames — a triple buffer, no torn frame", "the spectrum analyser reads true —
every sample, its own band, 0 dBFS for a full-scale sine, at every rate", "the analysis workers sleep while no audio
reaches them", "one live clock — the analyser drawn as one Canvas, sampled only while a song plays and shows; caps in
real time", "the transport tick sleeps when nothing plays", "VoiceOver hears live readings as values, polled", "a
paused lens shows the latest frame as it is". Each fix
landed with its red test first; the tests failed on `f0302af` and pass after (Swift: `SpectrumAnalyzerOracleTests`,
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
*The range* (founder decision 2026-10-16, "the analyser shows 20 Hz – 20 kHz"): the 44 bands were 1/6 octave from
37.8 Hz to 6.05 kHz under a "20 Hz – 20 kHz" axis — nothing above 6 kHz showed, and 1 kHz lit the bar under "2 kHz".
They now tile 20 Hz – 20 kHz in equal log steps (≈ 0.23 octave, `SpectrumConstants.bandEdgeHz`), zero-padded ×4 so
the narrowest (20–23.4 Hz) still owns a bin at every rate; tones at 30 Hz, 1 kHz, 10 kHz and 18 kHz read 0 dBFS in
their own bands at every rate, and the worst error over the 44 band centres is 0.09 dB.
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
57 / 60 / 80 on `f0302af` (the normaliser paused, a kernel at rest, a causal estimate waiting), 1–3 now; clean under
TSan.

#### KI-ENG-01 — `SpectrumDoubleBuffer` data race

**Status:** ✅ CLOSED in R1.1-A ("the analyser hands the main thread whole frames"). The two-slot buffer let the tap
thread lap a slow reader and overwrite the slot it was copying. `SpectrumTripleBuffer` is the C++ snapshot's
wait-free triple buffer (`TripleBufferSnapshot.h`) in Swift: three raw slots and one control word, swapped with one
acquire-release exchange per side. `SpectrumHandoffTests` (a writer that never pauses against a reader slowed
mid-read, 1 s): about one read in ten tore on `f0302af`, none now; clean under TSan.

### Fixed in R1.1-A — the sound chain does what it says (branch `r1.1a/sound`)

Council C-39, C-42 (with C-30's classification slice), C-46 and C-50, and the founder's decision of 2026-10-14 that
crossfeed works on its own (US-R1F-12). Five commits, named by their subjects: "flush-to-zero only while our DSP runs — scoped, then restored", "one hit on the ceiling no longer ducks the music for a second — a program-dependent release",
"crossfeed plays on its own, and it is bs2b — no centre notch", "headphones in the Mac's own jack get crossfeed, an AirPlay speaker does not — one output classifier", "“Integrated” measures the playing track, not the session". Each fix landed with its red test first: the tests failed on
`24f5c91` and pass after (in the C++ null test: `Crossfeed_CentreFlat_vs_bs2b`, `Crossfeed_ChannelSeparation`,
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

*(As found at `24f5c91`:)* Crossfeed sits in the coloration chain that Intensity blends in (QW1 design: "the Reimagine knob scales it",
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

*(As found at `24f5c91`:)* The crossfeed counts the interaural delay twice and leaves the direct path flat (`Spatial/CrossfeedModule.cpp:95-120`),
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
no data-source listener. *(2026-10-23, cards 7 and 8: US-R1F-12's "can be enabled on any output" is aligned to this
gate; the gate's rule becomes per-output memory, the output's class only as the default for a never-seen output, and a
manual override — crossfeed remembered per output in **S13** (US-TON-02 Part B / US-DEVICE-03), the one "Headphones:
Off / Crossfeed / Spatial" control replacing the switch in S18 — plus one per-output question, "What's plugged into
this output?", so headphones on a USB DAC read as headphones — **S13**.)* *The original entry:*

~~**Status:** OPEN · **Severity:** MEDIUM · **Source:** product council, code reading 2026-10-13 · **Scheduled (2026-10-14):** R1.1-A (headphones detected by data source, with the crossfeed fix — council C-42, C-30) · **Forward:** US-R1F-12, US-R1F-06 (and S13 device identification).~~

*(As found at `24f5c91`:)* The headphone gate is "USB or wireless transport" (`AudioViewModel.isHeadphones`, `AudioViewModel+Devices.swift`), and the device type comes from the
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

*(As found at `24f5c91`:)* The dual-release branch is dead code (`LimiterModule.h:398-416`); in practice it is one 500 ms release. A single snare
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

~~**Status:** OPEN (the residual of rev-arch's "removed APIs" note; the semgrep message and the gapless comments were fixed in 5fe1367 / 7d296f0, PR #86) · **Severity:** internal · **Scheduled (2026-10-14):** R1.1-A (hygiene, council C-88) · **Forward:** US-R1F-07.~~

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

~~**Status:** OPEN (residual of breaker B post-R1 #5, partly fixed by 97e7e8b in PR #85) · **Severity:** LOW ·
**Scheduled (2026-10-14):** pool · **Forward:** US-R1F-05.~~

Every Enhanced start re-applies the app's gain (`AudioEngineBridge+Playback.swift:110`), so the old double-attenuation
and wrong readout are gone. The device volume set on Pure is the macOS output volume, and the Enhanced readout shows
only the app's gain, not it.

#### KI-LIB-05 — `.opus` / `.oga` files are playable but never scanned

**Status:** ✅ CLOSED in R1.1-A, "the scan admits .opus and .oga" (C-08 scanner half). Apple's decoder opens Ogg Opus and Ogg Vorbis on macOS 26, so no FFmpeg is needed; a format table holds every extension the scan admits to a real file that opens (`LibraryScanFormatsGTests`). *The original entry:*

~~**Status:** OPEN · **Severity:** LOW · **Source:** breaker A post-R1 #3 · **Scheduled (2026-10-14):** R1.1-A (Apple decodes Opus natively on macOS 26 — council R-19) · **Forward:** US-R1F-16 (was S11, format hardening).~~

`LibraryScanner.supportedExtensions` (`Sources/LibraryScan/LibraryScanner.swift:50-52`) has no `opus` / `oga`, while the
decoder plays them through the optional FFmpeg fallback and the extractor reads their tags
(`MetadataExtractor.swift:78`). PR #85 (a061585) added only `.aif`. The scan says nothing about skipped files.

### Fixed in R1.1-A — playback correctness (branch `r1.1a/transport`)

Council C-15 and C-17 (US-R1F-01). Two commits, named by their subjects: "play, pause and stop do what was asked
last" and "what plays next follows the queue as edited". Each fix landed with its red test first, on the real view
model against the engine model of the bridge's semantics, both paths, in either order the commands reach the engine
(`Tests/AdaptiveSoundTests/TransportContractTests.swift`, `QueueEditContractTests.swift`), on the real bridge
(`EnhancedCommandOrderTests.swift`), and as rules (`PlaybackOrderTests` VM-PO-11…15, `QueueInsertTests` VM-QI-07/08).
The transport explorer (council P4's E1, on the shipped view model: `TransportExplorerTests.swift`) found "Playing"
over a silent engine in 116 of 3000 random schedules on `532ab79` (112 with commands overtaking each other), and 0
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

*(As found at `532ab79`:)* Stop and Pause take their epoch inside their `Task` (`AudioViewModel+Lifecycle.swift:160-161, 174-175`), Stop is two
engine calls, and there is no starting or pausing state. A quick Play after Stop or Pause can leave the engine silent
while the app shows Playing. KI-PB-04 is the same root seen from a slow start.

#### KI-PB-04 — Play / Space during a slow start restarts the song instead of pausing

**Status:** ✅ CLOSED in R1.1-A, "play, pause and stop do what was asked last" (council C-15). The view model has a
start state: a start, then its prime, until it settles (`transportCommand`). Space during a start pauses it at its
own place — Play resumes there — and never starts it twice; Next during a start starts the next song, so what is heard
is what is shown; a second Play (or Control Center's) joins the start. The play / pause control shows what was asked
last (`playIntent`): Pause from the press of Play on. *The original entry:*

~~**Status:** OPEN · **Severity:** MEDIUM · **Source:** breaker B post-R1 #1 (G-RACE-1) + freeze "Logged post-R1" (fast play-then-pause) · **Scheduled (2026-10-14):** R1.1-A (a starting / pausing state, council C-15) · **Forward:** US-R1F-01.~~

*(As found at `532ab79`:)* `isPlaying` becomes true only after `engine.startAudio` returns and the start's on-deck prime settles
(`AudioViewModel+Playback.swift:74`); `pause()` guards
on it (`AudioViewModel+Transport.swift:46`) and the toggle calls `play()` again (`:57-62`). There is no "start in
flight" state. PR #86 (c28b416) fixed only the Stop case (`transportStopEpoch`); `rev-verify.md` records the rest as
still lost.

#### KI-PB-09 — A double-click on a queue row starts the song twice

**Status:** ✅ CLOSED in R1.1-A, "play, pause and stop do what was asked last" (council C-15). The row's guard reads
what was asked (`playIntent`), so a second click on the row that is starting joins the start. *The original entry:*

~~**Status:** OPEN · **Severity:** LOW · **Source:** sweep ledger, "Logged post-R1" · **Scheduled (2026-10-14):** R1.1-A · **Forward:** US-R1F-01.~~

*(As found at `532ab79`:)* Same guard as KI-PB-08 (`PlaylistItemList.swift:165-175`): the second click lands before `isPlaying` flips, so a second
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

*(As found at `532ab79`:)* The on-deck pick is not recomputed after queue edits (`AudioViewModel+Queue.swift:183`, `guard isPlaying`). A song
dragged in under the current one never plays; with Repeat All an append waits a whole cycle; a one-song shuffle plus an
append stops. An append during a start's prime is not armed (its Play Next twin was fixed in R1, PR #88), and
`playNextNow` ignores duplicates.

### Fixed in R1.1-A — library safety and search (branch `r1.1a/library`)

Council lane 6 (C-55, KI-LIB-01, the C-58 / P5B-01 fix, the C-61 slice). Four commits, named by their subjects: "a walk
is evidence of what it read — an unreadable subfolder no longer stops its folder's sweeps", "Remove Missing never takes
a song whose drive is only unplugged", "search reads a word in any script, however it is stored — store v9", "the newer
of two filter reads always wins". Each fix landed with its red test first: the tests failed on `532ab79` and pass after
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

*(As found at `532ab79`:)* Availability is a file-existence check only (`PlaylistsModel.swift:265-269`); `missingEntryIDs`
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

*(As found at `532ab79`:)* The full-text tokenizer treats Sinhala vowel signs as separators, so "මාල" matches "මිල"; text
stored decomposed (NFD) can't be found from a composed query; type-select folds marks; and three search semantics exist
(KI-LIB-09) (`LibraryStore+Search.swift:16-48`).

### Fixed in R1.1-A — one converter across a same-rate seam (branch `r1.1a/seam-converter`)

Council C-22 (P3 D39 b–d, D40), brought forward from the Engine sprint by the founder (2026-10-14, "Fix now in
R1.1-A"), to ship with the Mastering converter (KI-SND-02), whose longer filter made the per-track click longer. One
commit, "a same-rate gapless join plays as one conversion". Its tests came first and failed on `24f5c91`:
`Tests/AdaptiveSoundTests/EnhancedSeamTests.swift` plays two 44.1 kHz tracks cut from one sound through the real bridge
on an offline engine, paced at a device's speed, records what the player plays (a tap, before the effects chain) and
compares it with ONE Mastering conversion of the joined input; it also pins the seam's frame, the playhead, a seek
before the join is heard, a next track shorter than a chunk, and a join to another rate or width. Five runs under a
16-process CPU load and a ThreadSanitizer run passed.

#### KI-GAP-04 — A click at each join between resampled tracks

**Status:** ✅ CLOSED in R1.1-A, "a same-rate gapless join plays as one conversion" (council C-22). A next track of the same
rate, channel count and layout continues the stream through the same converter (`continueStreamIntoNextTrack`), so a
join converts as one input would: the player's output equals one continuous conversion bit for bit (peak error 0, no
frame inserted or lost) with A ending 64, 4096 or 8100 frames into its last chunk. At `24f5c91` the join error was
0.019, 0.053 and 0.012 (−22, −13.5 and −26.5 dB re peak), and B came one frame early when A's converted length was
not whole. The seam is counted when the player has consumed A's last frame, with the playhead re-based by exactly A's
length (KI-GAP-02 narrowed). The P3 replica's 279-frame race at a short last chunk did not reproduce on the real code
at `24f5c91` (Mastering's flush gave its roll ~13 ms of lead, the replica's Normal converter ~1 ms); for these seams it
is gone by construction — no roll at the end of file, and the next file opens with a whole chunk of lead. A join to
another rate or channel count keeps a fresh converter, its click and its end-of-file roll (the Engine sprint's).
*The original entry:*

~~**Status:** OPEN · **Severity:** MEDIUM · **Source:** council C-22 (P3 D39 c) · **Scheduled (2026-10-14):** Engine sprint · **Forward:** US-R1F-02.~~

*(As found at `24f5c91`:)* Each track gets its own sample-rate converter (`AudioEngineBridge+GaplessRoll.swift:225`),
so the filter state restarts at the seam: a click 18 to 26 dB below peak at every join of a 44.1 or 96 kHz album.

### Fixed in R1.1-A — the end of the queue plays the last frame (branch `r1.1a/end-of-queue`)

Found by the R1.1-A close-out break-it (audio, S-1). Two commits, named by their subjects: "the Enhanced transport rig
plays any rate and joins tracks" (test fixtures) and "the end of the queue plays the last track to its last frame".
The test came first and failed on `814e719`: `Tests/AdaptiveSoundTests/EnhancedEndOfQueueTests.swift` plays through
the real bridge on an offline engine, paced at a device's speed, and reads the player's own clock when the end rises,
for eight final tracks on both sub-paths; it also pins that a stop or seek in the last moments still cuts at once.
Five runs under a 16-process CPU load and a ThreadSanitizer run passed.

#### KI-GAP-06 — The end of the queue cut the last ~70–200 ms of a resampled final track

**Status:** ✅ CLOSED in R1.1-A, "the end of the queue plays the last track to its last frame" (S-1). The end of a
resampled stream is now its last scheduled buffer's, once heard (`streamPlayedOut`): `.dataPlayedBack`, which waits out
the output's latency, as the passthrough sub-path always used — one rule for both (`playedBackCallbackType`; in
offline manual rendering, which never reports it, `.dataRendered`). A join still pending is counted first, so the seam
always comes before the end. The read iterations after the flush only roll in a next track that is already armed,
where a roll still has its lead. Measured on the player's clock: before, the end rose 5–198 ms before the last frame
(a 1000-frame and a 0.3 s track after a same-rate join: 12 and 119 ms); after, 1–10 ms after it (one render block,
offline). A user's stop or seek still cuts at once. *Never listed open; as found:*

*(As found at `b1cc33c`:)* `readConvertSchedule` raised the end in the read iteration after the flush was scheduled
(`fireResamplerEOFOrEnd` with no hook armed), while the last partial chunk and the flush were still queued — 68–199 ms
at 44.1 / 96 kHz. The view model's stop at the end of the queue (`stopAtEndOfQueue`, 0–50 ms later) cut them:
fade-outs and reverb tails at the end of every album played from 44.1 / 96 kHz files. A track under ~0.4 s after a
same-rate join lost almost all of it, its end raised at the join (`endAwaitsJoin`). And when a next track's request
reached the engine after that early end, the view model's fresh start of it cut the same tail.

### Fixed in R1.1-A — a faithful default and the listener's settings kept (branch `r1.1a/faithful-default`)

Founder decision FD-2 (2026-10-14). Four commits, named by their subjects: "SettingsKit — the listener's settings and
the one store that keeps them", "a faithful default", "remember the listener's settings", "Pure waits while Master
Gain is turned down". Each fix landed with its red test first: the regression tests failed on `4af2b0d` and pass after
(`Tests/AdaptiveSoundTests/ListeningSettingsTests.swift`, `Tests/SettingsKitTests/SettingsStoreTests.swift`,
`Tests/OutputDeviceKitTests/OutputDeviceRelaunchTests.swift`, `EQMigrationTests` MIGRATE-04 / -10).

#### KI-SND-01 — A fresh launch plays processed sound

**Status:** ✅ CLOSED in R1.1-A, "a faithful default" (council C-41). Intensity defaults to 0, is hidden
(`AudioViewModel.offersIntensity`) and held at 0 until S17 — never restored. At 0 the kernel runs P0 (bit-exact, with
the EQ off) or P1 (EQ → limiter at the EQ-only ceiling): never the normaliser (leveling, C-38) nor the blend's +2 dB
(C-40). A new install's EQ is Flat and Off (`EQMigration.freshInstall`); an existing EQ keeps its own memory. Leveling
becomes its own setting, off by default, in R1.1-B (US-R1F-10) *(2026-10-23: Off / Auto / Album / Track at −18 LUFS,
one fixed gain per track or album, the old auto-leveller removed — see [Settings and levels](#settings-and-levels);
Intensity's return, S17, scales only Clarity depth and the room amount, as settings, default 0 — never a leveller,
never a hand-set switch)*. Consequence: KI-SND-05 (closed by the sound lane:
crossfeed now plays on its own). *The original entry:*

~~**Status:** OPEN · **Severity:** MEDIUM · **Scheduled (2026-10-14):** R1.1-A (FD-2) · **Forward:** US-R1F-09.~~

*(As found at `4af2b0d`:)* Intensity defaults to 20 % (`AudioViewModel.swift:142`). That turns on the loudness normaliser, a session-long
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

*(As found at `4af2b0d`:)* None has a defaults key: `pureModeEnabled = false` (`AudioViewModel.swift:106`), the pin `= true` (`:116`),
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

*(As found at `4af2b0d`:)* On Pure the slider shows and sets the device's own volume, and the app gain is not applied
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

*(As found at `4af2b0d`:)* Within a session the app remembers the output device the user picked (by UID) and returns to it
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

**Status:** ✅ CLOSED by PR #88 (da8e5cc, cffba63; the latent arm-inside-a-claimed-seam case 73ebb44) — re-verified
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

*(As found at 7d7c2cd:)* On the Pure path the gapless deck has one slot, and a second arm is refused:
`pureModeEngineArmOpenedNextTrack` returned an error when a track was already armed (`PureModeBridge.cpp`;
`GaplessSource::armNext`). The view model's re-arm (`armOnDeck`) pushed the new URL without clearing the slot first
(`setPureNextTrack` cleared only for a `nil` URL). So in Pure, a mid-song Repeat / Shuffle change (the Sprint G re-arm,
PR #85) or a queue edit that changes the next song (Play Next, reorder, remove) left the OLD next track armed. At the
seam Pure played it, while the view model advanced to its own `pendingNextIndex` and named a different song. Enhanced
was not affected (`onDeckURL` is simply replaced).

#### The other R1 blockers

- **Render gate (the main-CI failure on 7d7c2cd, `RenderGate_ConcurrentNeverOverlaps`)** — `close()` could only win
  between two render passes, so a busy render starved it. Fixed by ee8e3dd, 7643826, f9986a6: `close()` bars new
  passes at once and waits only for the pass inside (`include/RenderGate.h`); the tests assert the guarantee step by
  step, with no wall-clock deadline. **DSP-06:** a teardown never reopens the gate, and a pass that outlived its unit's
  stop leaves its engine and source parked, never freed (e5f9e72, 8686aea).
- **Library data loss (council P5A-01 / P5A-02)** — an unreadable subfolder, a drive unplugged mid-walk or another
  drive with the same name made the sweep delete songs with their playlist entries and play history. A sweep now needs
  positive evidence (`LibraryScan/SweepRefusal.swift`), and each folder is bound to its drive's volume UUID
  (`folders.volume_uuid`, additive migration v8) — e362e81, 46ec9ba, 340de12. Tests: `SweepEvidenceTests`,
  VerifyLibraryStore SE-1…SE-4. Accepted limits: LIB-VOL-1.
- **Pure Mode safety (council D71 / DSP-03, D74 / DSP-04, D76)** — a mono track (or any channel-count mismatch) played
  silence that never ended; a packed 24-bit device format overran the IO buffer; NaN / Inf played at full scale. Fixed
  by 231a927: such a track plays in Enhanced with the existing notice, device formats are written exactly or declined
  (`PureModeFormat.h`), and non-finite samples become silence (`FiniteSamples.h`). See the two Pure rows under *Known
  limitations*.
- **Return to the headphones (council N92)** — after Bluetooth headphones dropped and came back, Play moved the system
  output back to the speakers. The chosen device is now kept apart from a temporary fallback (`OutputDeviceSelection`,
  `OutputDeviceKit`), and playback returns to it once the device menu would list it; the device the app launches on is
  not a choice; a refused pick undoes only itself — cdf8dcb, b2781c2. Tests: `OutputDeviceReturnTests`,
  `OutputDeviceChoiceTests`, `OutputDeviceRuleSpaceTests`, `Tests/AdaptiveSoundTests/OutputDeviceViewModelTests.swift`.
  Limit: DEV-1 (closed in R1.1-A).
- **Play Next during a start's prime played the old pick (council F-P4-1, pre-existing)** — 27e3176: `playNext` arms
  when a pick is on deck or being primed.
- **Settings copy** — with "Keep playback on this device" off, Settings now says "Playback follows your Mac's sound
  output." (e2d6037).
- **PR #89** (9df49e3, after the tag; test-only) — the seam-window arm tests no longer depend on the scheduler (an ASan
  flake on PR #88's CI).

### Fixed by PR #85 / PR #86 (re-verified 2026-10-13)

- **The 13 Sprint G R1 blockers** (5 library, 8 playback / devices / Master Gain) — fixed in PR #85; see the two
  break-it reports and the [sweep ledger](../sprints/s10-8-sweep-ledger.md) "Build, break-it, fixes and live pass".
- **The disconnect freeze** (switching headphones off froze the app 3–7 s) — fixed in PR #86; evidence in
  [main-thread-stall-2026-10](../architecture/evidence/main-thread-stall-2026-10/README.md).
- **G-LIB-03** — New Playlist failed beside a "new playlist" in another case: fixed by 96e98aa (PR #85), the free name
  is now picked case-blind (`LibraryStore+Playlists.swift:198-199`); regression test
  `Tests/LibraryBrowseKitTests/LibraryBreakItGTests.swift:93`.
- **Breaker B post-R1 #2** — Pure leaked a device-alive listener per manual start: fixed by 0533d69 (PR #85), one
  alive listener on the app's device (`AudioEngineBridge+OutputDeviceMonitor.swift:80-95`).
- **Audit S1-E** — the loudness-meter snapshot race / potential use-after-free: fixed by 8f09320 (PR #86),
  `withExtendedLifetime(meter)` over a strong copy (`AudioEngineBridge.swift:346-348`).
- **`passUnretained` without `withExtendedLifetime`** on the effects AU: fixed by 0584ffe / 8f09320 (PR #86),
  `withEffectsAU` (`AudioEngineBridge+SharedState.swift:255-259`).
- **R10, the engine-lock-held regression test:** added by 3f1dfa5 (PR #86) as `make main-thread-stall` in the strict
  gate.
- **Pure resume played the intro** (start-then-seek): fixed by edc9b4e (PR #86), `startAudio(…, startAt:)`
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
`playlist_tracks` sketch.) *(Amended 2026-10-12, PR #85 / 6d0dfef, G-LIB-04: the filter now counts **user** playlists
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
