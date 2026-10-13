# Known Issues

Tracked defects surfaced by tests/review that are not yet fixed. Each entry names the guarding test (or the
red test on a reference branch) where one exists, the place in the code, and where the fix is planned.

> **Reconciled to the code on 2026-10-13 (product council, against `main` at a206107 = R1 / v1.0.0-alpha).**
> Every OPEN entry below was re-checked in the source after PR #85 (Sprint G) and PR #86 (the disconnect-freeze
> fix); items those PRs fixed are listed under **Closed**. This page is the open list the
> [R1 release notes](../releases/v1.0.0-alpha.md) point to.
>
> - **Severity:** **HIGH** = wrong audio, a stuck state, or user data lost; **MEDIUM** = visibly wrong behaviour that
>   has a workaround; **LOW** = rare, cosmetic or wording; **internal** = a developer-only follow-up.
> - **Forward link:** the [backlog](backlog.md) story (or roadmap sprint) that will close the issue. Most post-R1 defects
>   sit in the backlog's **Post-R1 fix pool** (US-R1F-01…07), which is not yet scheduled into a sprint.
> - **Sources:** the Sprint G break-it reports ([library](../sprints/s10-8-g-breakit-library.md),
>   [playback / shell](../sprints/s10-8-g-breakit-playback-shell.md)), the "Logged post-R1" lists in the
>   [sweep ledger](../sprints/s10-8-sweep-ledger.md), and the freeze evidence in
>   [main-thread-stall-2026-10](../architecture/evidence/main-thread-stall-2026-10/README.md).
> - **No `withKnownIssue` guards exist any more** (zero uses in `Tests/`); the old header promise that each entry is
>   guarded by one no longer holds. Where a red test exists, it lives on a reference branch, named in the entry.

---

## Open issues at a glance

| ID | Issue | Severity | Forward link |
|---|---|---|---|
| KI-PB-01 | Pure ignores a changed next track while another is armed (Repeat / Shuffle toggle, Play Next, reorder) | HIGH (needs a live check) | US-R1F-01 |
| KI-LIB-01 | "Remove Missing…" deletes entries whose drive is merely unplugged | HIGH | US-R1F-03 |
| KI-PB-02 | Repeat turned off mid-song moves on, but with a gap | MEDIUM | US-R1F-02 |
| KI-PB-03 | Shuffle on + Repeat off never ends the queue | MEDIUM | US-R1F-01 |
| KI-PB-04 | Play / Space during a slow start restarts the song instead of pausing | MEDIUM | US-R1F-01 |
| KI-PB-05 | Pure on / off does not apply at a gapless seam, though Settings says it does | MEDIUM | US-R1F-01 |
| KI-PB-06 | After a relaunch the restored song shows `--:--` and its scrubber is dead until Play | MEDIUM | US-R1F-01 |
| KI-PB-08 | Clicking the paused current queue row restarts it from 0:00 | MEDIUM | US-R1F-01 |
| KI-PB-10 | Add to Queue onto an empty queue leaves Play / Space disabled | MEDIUM | US-R1F-01 |
| KI-PB-11 | "Restore previous queue" restores the wrong queue | MEDIUM | US-R1F-04 |
| KI-PB-12 | A single click on a playlist row replaces the queue and plays | MEDIUM | US-R1F-04 |
| KI-GAP-01 | A short gap at the seam between 48 kHz tracks | MEDIUM | US-R1F-02 |
| KI-GAP-02 | On resampled seams the title and track B's gain switch ~0.4 s early | MEDIUM | US-R1F-02 |
| KI-SET-01 | Pure, device pin, Master Gain, Intensity and crossfeed reset at every launch | MEDIUM | US-R1F-05 |
| KI-SET-02 | A Master Gain cut in Enhanced does not carry into Pure (Pure plays at device volume) | MEDIUM | US-R1F-05 |
| KI-EQ-01 | Unpinning an output overwrites the shared EQ, with no undo | MEDIUM | US-R1F-06 |
| DEV-1 | The chosen output device is forgotten when the app quits | MEDIUM | US-R1F-05 |
| KI-DEV-01 | Crossfeed is unavailable on wired headphones in the Mac's own jack | MEDIUM | US-R1F-06 |
| KI-LIB-02 | Paused / failed folders are invisible; an emptied folder keeps its songs | MEDIUM | US-R1F-03 |
| LIB-VOL-1 | A paused folder on a replaced or UUID-less drive stays paused; re-adding it loses play stats | MEDIUM | US-R1F-03 |
| KI-LIB-03 | A failed first metadata pass leaves "No Music Yet", with no retry | MEDIUM | US-R1F-03 |
| KI-LIB-04 | Dragging a multi-selection onto a playlist adds one song | MEDIUM | US-R1F-04 |
| KI-PB-07 | Next / Previous while paused keep the old song's duration | LOW | US-R1F-01 |
| KI-PB-09 | A double-click on a queue row starts the song twice | LOW | US-R1F-01 |
| KI-PB-13 | Two quick tile Plays can land out of order | LOW | US-R1F-04 |
| KI-PB-14 | Stalled ticks count as heard time (play counts) | LOW | US-R1F-01 |
| KI-PB-15 | Recent says "Nothing Played Yet" when the store is not ready or the read failed | LOW | US-R1F-04 |
| KI-GAP-03 | A narrow false seam on a Pure → Enhanced restart | LOW | US-R1F-02 |
| ENH-001 | Short-track auto-advance is a reconfigure gap, not a seamless seam | LOW | US-R1F-02 |
| ENH-002 | The UI loudness readout is L/R-only on a >2-channel output | LOW | US-R1F-07 |
| KI-SET-03 | A device volume lowered on Pure stays lowered on Enhanced; the readout doesn't show it | LOW | US-R1F-05 |
| KI-EQ-02 | Esc during a graph drag re-announces "Bring back edits" | LOW | US-R1F-06 |
| KI-EQ-03 | Stacked-shadow darkening on EQ / Settings cards (dark + Reduce Transparency / Increase Contrast) — unverified | LOW | US-R1F-06 |
| KI-DEV-02 | HDMI / DisplayPort outputs read "(Unknown)" | LOW | US-R1F-06 |
| KI-LIB-05 | `.opus` / `.oga` files are playable but never scanned | LOW | S11 (format hardening) |
| KI-LIB-06 | Genres split on "/" ("Singer/Songwriter" → two tiles) | LOW | US-R1F-04 |
| KI-LIB-07 | Case / Unicode variants split artist and genre tiles | LOW | US-R1F-04 |
| KI-LIB-08 | Sorting Songs by Album orders each album's tracks by scan order | LOW | US-R1F-04 |
| KI-LIB-09 | Two Filter semantics (Songs: token prefix; grids: substring) | LOW | US-R1F-04 |
| KI-LIB-10 | An empty playlist says "No Tracks Yet" (the app says "songs") | LOW | US-R1F-04 |
| KI-UI-01 | VoiceOver keeps the app fairly busy while a song plays (release notes; not verifiable from code) | LOW | US-R1F-07 |
| KI-ENG-01 | `SpectrumDoubleBuffer` data race (TSan) | internal | US-R1F-07 |
| KI-ENG-02 | The main-thread stall self-test lacks the breaker's two extra modes and the 5 ms bound | internal | US-R1F-07 |
| KI-ENG-03 | A stale comment names the removed `loudnessMeter` field | internal | US-R1F-07 |
| KI-ENG-04 | The `eq-light-folded` picture sheet flakes in the renderer | internal | US-R1F-07 |

**Known limitations (by design or not yet built — not defects):** see [the last section](#known-limitations-by-design-or-not-yet-built).

---

## Playback and transport

### KI-PB-01 — Pure ignores a changed next track while another is armed

**Status:** OPEN · **Severity:** HIGH (found by reading the code during this reconciliation; needs a live check on a USB
DAC) · **Forward:** US-R1F-01.

On the Pure path the gapless deck has one slot, and a second arm is refused: `pureModeEngineArmOpenedNextTrack` returns
an error when a track is already armed (`Sources/AudioDSP/PureModeBridge.cpp:357-362`; `GaplessSource::armNext`,
`Sources/AudioDSP/GaplessSource.cpp:124-129`). The view model's re-arm (`armOnDeck`,
`Sources/AdaptiveSound/AudioViewModel+Queue.swift:195-201`) pushes the new URL without clearing the slot first
(`setPureNextTrack` clears only for a `nil` URL, `AudioEngineBridge+Gapless.swift:94-100`). So in Pure, a mid-song
Repeat / Shuffle change (the Sprint G re-arm, PR #85) or a queue edit that changes the next song (Play Next, reorder,
remove) leaves the OLD next track armed. At the seam Pure plays it, while the view model advances to its own
`pendingNextIndex` and names a different song. Enhanced is not affected (`onDeckURL` is simply replaced).

### KI-PB-02 — Repeat turned off mid-song moves on, but with a gap

**Status:** OPEN · **Severity:** MEDIUM · **Source:** sweep ledger, "Logged post-R1" (Sprint G) · **Forward:** US-R1F-02.

The view model re-arms correctly (`AudioViewModel+Playlist.swift:159-168` → `armOnDeck`). The seam is not re-armed
seamlessly: on 48 kHz files the gap is most likely KI-GAP-01; on Pure the re-arm is refused (KI-PB-01).

### KI-PB-03 — Shuffle on + Repeat off never ends the queue

**Status:** OPEN · **Severity:** MEDIUM · **Source:** sweep ledger, "Logged post-R1" · **Forward:** US-R1F-01.

`QueueAdvance.nextIndex` returns a random pick before the end-of-queue check, and nothing records which songs have
played (`Sources/PlaybackQueueKit/QueueAdvance.swift:38-45`). With Shuffle on and Repeat off, random songs repeat
forever.

### KI-PB-04 — Play / Space during a slow start restarts the song instead of pausing

**Status:** OPEN · **Severity:** MEDIUM · **Source:** breaker B post-R1 #1 (G-RACE-1) + freeze "Logged post-R1"
(fast play-then-pause) · **Forward:** US-R1F-01.

`isPlaying` becomes true only after `engine.startAudio` returns (`AudioViewModel+Playback.swift:68`); `pause()` guards
on it (`AudioViewModel+Transport.swift:46`) and the toggle calls `play()` again (`:57-62`). There is no "start in
flight" state. PR #86 (86a1cbe) fixed only the Stop case (`transportStopEpoch`); `rev-verify.md` records the rest as
still lost.

### KI-PB-05 — Pure on / off does not apply at a gapless seam, though Settings says it does

**Status:** OPEN · **Severity:** MEDIUM · **Source:** breaker B post-R1 #3 · **Forward:** US-R1F-01.

The next track is armed on the path that is playing (`AudioEngineBridge+Gapless.swift:57`); `pureModeEnabled`'s
`didSet` only logs (`AudioViewModel.swift:98-100`). Settings still says "Starts with the next track."
(`UI/Settings/PureModeSettingsSection.swift:18`, `UI/Settings/SignalPathStatus.swift:38`). The switch takes effect
only at a manual start or a rate-change reconfigure.

### KI-PB-06 — After a relaunch the restored song shows `--:--` and its scrubber is dead

**Status:** OPEN · **Severity:** MEDIUM · **Source:** breaker B post-R1 #6 · **Forward:** US-R1F-01.

`restoreCursor` sets the selection, resume point and position but never `duration`
(`AudioViewModel+QueueHydration.swift:64-78`); the footer and scrubber gate on `duration > 0`
(`UI/Shell/NowPlayingBar.swift:242`, `:294`). Control Center can't seek either, until Play.

### KI-PB-07 — Next / Previous while paused keep the old song's duration

**Status:** OPEN · **Severity:** LOW · **Source:** sweep ledger, "Logged post-R1" · **Forward:** US-R1F-01.

While paused, Next / Previous only move `selectedTrackIndex` (`AudioViewModel+Transport.swift:73-95`);
`refreshDuration` runs only in `startPlayback` (`AudioViewModel+Playback.swift:37`).

### KI-PB-08 — Clicking the paused current queue row restarts it from 0:00

**Status:** OPEN · **Severity:** MEDIUM · **Source:** breaker B post-R1 #10 · **Forward:** US-R1F-01.

The row tap guards only on `isPlaying` (`UI/Playlist/PlaylistItemList.swift:173-174`) and calls `playTrack`, which
clears the resume point (`AudioViewModel+Transport.swift:12`). Return on the same row resumes (`activateCursor`).

### KI-PB-09 — A double-click on a queue row starts the song twice

**Status:** OPEN · **Severity:** LOW · **Source:** sweep ledger, "Logged post-R1" · **Forward:** US-R1F-01.

Same guard as KI-PB-08 (`PlaylistItemList.swift:165-175`): the second click lands before `isPlaying` flips, so a second
start is requested (and a second play is logged).

### KI-PB-10 — Add to Queue onto an empty queue leaves Play / Space disabled

**Status:** OPEN · **Severity:** MEDIUM · **Source:** breaker B post-R1 #9 · **Forward:** US-R1F-01.

`appendToQueue` never selects a track (`AudioViewModel+Queue.swift:173-186`); Controls ▸ Play / Space are disabled on
`selectedTrackIndex == nil` (`AdaptiveSound.swift:167`) and the footer on `track != nil`
(`UI/Shell/NowPlayingBar.swift:31`, `:197`), though `play()` would start track 1. Clicking a queue row works.

### KI-PB-11 — "Restore previous queue" restores the wrong queue

**Status:** OPEN · **Severity:** MEDIUM · **Source:** breaker A post-R1 #4 · **Forward:** US-R1F-04.

`QueueRestorePoint.afterReplace` treats any replace of an untouched installed queue as a double-click and keeps the
older snapshot (`Sources/PlaybackQueueKit/QueueRestorePoint.swift:36-37`; pinned by VM-QR-02). Play album A, then B,
then "Restore previous queue" brings back the queue from before A (or clears the queue if that was empty).

### KI-PB-12 — A single click on a playlist row replaces the queue and plays

**Status:** OPEN · **Severity:** MEDIUM · **Source:** breaker A post-R1 #9 · **Forward:** US-R1F-04.

`PlaylistDetailView.swift:241-244` plays on a tap, while Songs and the album / artist / genre pages select on click and
play on double-click. Selecting a playlist row to move or remove it starts it playing.

### KI-PB-13 — Two quick tile Plays can land out of order

**Status:** OPEN · **Severity:** LOW · **Source:** breaker A post-R1 #12 · **Forward:** US-R1F-04.

`BrowseTile` starts an async `facetRows` read per click (`UI/Library/BrowseTile.swift:111-112` →
`LibraryBrowseModel+Facets.swift:153-155`) with no latest-wins check.

### KI-PB-14 — Stalled ticks count as heard time

**Status:** OPEN · **Severity:** LOW · **Source:** freeze "Logged post-R1" · **Forward:** US-R1F-01.

`accruePlayThrough` adds wall-clock time whenever `isPlaying && duration > 0`
(`AudioViewModel+PlayTracking.swift:18-19`), with no check that audio is rendering; a device stall can inflate play
counts and Recently Played.

### KI-PB-15 — Recent says "Nothing Played Yet" when the store is not ready or the read failed

**Status:** OPEN · **Severity:** LOW · **Source:** breaker B post-R1 #8 · **Forward:** US-R1F-04.

`UI/Playlist/QueueHistoryList.swift:36` never reads `historyState`, and nothing reloads it when the store becomes ready
(`LibraryBrowseModel+History.swift:12`).

---

## Gapless seams

### KI-GAP-01 — A short gap at the seam between 48 kHz tracks

**Status:** OPEN · **Severity:** MEDIUM · **Source:** freeze "Logged post-R1"; R1 release notes · **Forward:** US-R1F-02.

The 48 kHz passthrough schedules the next file only after track A has played back
(`AudioEngineBridge+GaplessRoll.swift:68-90`, `scheduleFile(… .dataPlayedBack)` at `:207-213`), so 48 kHz albums have a
short silence between tracks.

### KI-GAP-02 — On resampled seams the title and track B's gain switch ~0.4 s early

**Status:** OPEN · **Severity:** MEDIUM · **Source:** freeze "Logged post-R1" (playhead latency compensation and seam
domains) · **Forward:** US-R1F-02.

The resampler seam bumps the transition count when B is primed, i.e. when A's decode reaches end-of-file
(`AudioEngineBridge+GaplessRoll.swift:256-259` → `+Gapless.swift:184-186`), not when B becomes audible; no
presentation latency is applied anywhere. On 44.1 kHz music the title and B's loudness gain switch early, and the
scrubber runs ahead of what is heard (more on Bluetooth).

### KI-GAP-03 — A narrow false seam on a Pure → Enhanced restart

**Status:** OPEN · **Severity:** LOW · **Source:** freeze "Logged post-R1" · **Forward:** US-R1F-02.

The Enhanced seam count is never reset (`AudioEngineBridge.swift:168`); the view model's baseline is reset only after
`startAudio` returns (`AudioEngineBridge+Playback.swift:111`). In a narrow window after a Pure → Enhanced fallback the
tick can see a seam that did not happen.

### ENH-001 — Short-track auto-advance is a reconfigure gap, not a seamless seam

**Status:** OPEN (enhancement, low priority) · **Forward:** US-R1F-02.

*(KI-001 — "the VM stops mid-playlist on short tracks" — was **RESOLVED 2026-07-02**: analysis showed the VM already continues via `tickSpectrum()`'s `playbackEnded → advance to pendingNextIndex` branch; the stale `VM-AA-RTR-1` assertion was corrected to the continue behavior. Founder's continue/advance decision is satisfied. The full triage/panel narration is in git.)*

The short-track advance is a fresh-start reconfigure **gap**, not a gapless seam. Making it seamless for arbitrarily-short tracks needs an engine-side **2-deep on-deck queue** — a single on-deck slot can't arm track C until track B is current at the seam, and B may be shorter than the arm latency + the 20 Hz poll interval. Scheduled against the gapless backlog (US-PLAY-08 lineage); low priority (only tiny tracks; fallback is a brief gap, not a stop). ~~Guarded by `VM-AA-RTR-1` (`withKnownIssue` — fails when fixed, prompting a proper assertion).~~ *(Corrected 2026-10-13: `VM-AA-RTR-1` still exists — `Tests/AudioViewModelTests/AutoAdvanceReconfigureGapTests.swift:88` — but `withKnownIssue` was dropped in c63ba7f; it now asserts the fresh-start advance against mocks, so nothing fails when the seamless fix lands. The engine still has one on-deck slot: `onDeckURL`, `AudioEngineBridge.swift:163`.)*

---

## Settings and levels

### KI-SET-01 — Pure, device pin, Master Gain, Intensity and crossfeed reset at every launch

**Status:** OPEN · **Severity:** MEDIUM (Master Gain and Pure); LOW (the rest) · **Source:** breaker B post-R1 #4 ·
**Forward:** US-R1F-05.

None has a defaults key: `pureModeEnabled = false` (`AudioViewModel.swift:98`), the pin `= true` (`:106`),
`intensity = 0.20` (`:132`), `crossfeedEnabled = false` (`:143`), strength (`:151`), and Master Gain `= unity`
(`:185`, commented "Not kept across launches (a post-R1 item)"). Only the EQ, the queue cursor (incl. shuffle / repeat),
the Songs columns and the Tone-card fold persist. Someone who turned Master Gain down hears 0 dB after a relaunch.

### KI-SET-02 — A Master Gain cut in Enhanced does not carry into Pure

**Status:** OPEN (by design today; close to hearing safety) · **Severity:** MEDIUM · **Source:** sweep ledger,
"Logged post-R1" ("an Enhanced trim doesn't carry into Pure") · **Forward:** US-R1F-05.

On Pure the slider shows and sets the device's own volume, and the app gain is not applied
(`AudioViewModel+MasterGain.swift:9-17`). Turning Master Gain down in Enhanced, then switching to Pure, plays at the
device's volume, which can be much louder.

### KI-SET-03 — A device volume lowered on Pure stays lowered on Enhanced

**Status:** OPEN (residual of breaker B post-R1 #5, partly fixed by 124178d in PR #85) · **Severity:** LOW ·
**Forward:** US-R1F-05.

Every Enhanced start re-applies the app's gain (`AudioEngineBridge+Playback.swift:108`), so the old double-attenuation
and wrong readout are gone. The device volume set on Pure is the macOS output volume, and the Enhanced readout shows
only the app's gain, not it.

---

## EQ

### KI-EQ-01 — Unpinning an output overwrites the shared EQ, with no undo

**Status:** OPEN · **Severity:** MEDIUM · **Source:** breaker B post-R1 #7 · **Forward:** US-R1F-06.

`EQStore.unpin` sets `shared = slot.state` (`Sources/EQEditKit/EQStore.swift:112-115`; documented as intended at
`:109-111`, ui-plan §3.3); `togglePin` offers no Bring back (`EQSession+Slots.swift:76`). Every other output silently
loses its (possibly edited) EQ.

### KI-EQ-02 — Esc during a graph drag re-announces "Bring back edits"

**Status:** OPEN · **Severity:** LOW · **Source:** breaker B post-R1 #11 · **Forward:** US-R1F-06.

Esc restores the offer (`EQSession+Stroke.swift:71`), and `UI/EQ/EQBringBackMessage.swift:36` treats nil → offer as
new: the 6 s timer restarts and VoiceOver says "Switched to …" again.

### KI-EQ-03 — Stacked-shadow darkening on EQ / Settings cards (unverified)

**Status:** OPEN (needs a visual check; cannot be judged from code) · **Severity:** LOW · **Source:** sweep ledger,
"Logged post-R1" · **Forward:** US-R1F-06.

Under dark appearance with Reduce Transparency or Increase Contrast, the EQ and Settings cards may darken where shadows
stack.

---

## Output devices

### KI-DEV-01 — Crossfeed is unavailable on wired headphones in the Mac's own jack

**Status:** OPEN · **Severity:** MEDIUM · **Source:** product council, code reading 2026-10-13 · **Forward:** US-R1F-06
(and S13 device identification).

The headphone gate is "USB or wireless transport" (`AudioViewModel.swift:159-171`), and the device type comes from the
transport alone (`Sources/AudioDSP/CoreAudioDevice.cpp:321-338`). The Mac's headphone jack reports the built-in
transport, so wired headphones there are "not headphones": crossfeed is disabled with the "Connect headphones" hint.
The converse also holds: AirPlay speakers count as wireless headphones. The code comment names only the USB false
positive.

### KI-DEV-02 — HDMI / DisplayPort outputs read "(Unknown)"

**Status:** OPEN · **Severity:** LOW · **Source:** sweep ledger, "Logged post-R1" · **Forward:** US-R1F-06.

`classifyDeviceType` has no HDMI / DisplayPort case (`CoreAudioDevice.cpp:327-354`); the pill and Settings show
"<name> (Unknown)" (`Models/AudioDeviceModel.swift:86-88`).

### DEV-1 — The chosen output device is forgotten when the app quits

**Status:** OPEN (limitation; R1 ships with it) · **Severity:** MEDIUM · **Forward:** US-R1F-05 (with KI-SET-01).
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
(`AudioEngineBridge+Graph.swift:170-173`). **Forward:** US-R1F-07.

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
Sprint E #12) · **Source:** breaker A post-R1 #13 · **Forward:** US-R1F-03.

Availability is a file-existence check only (`PlaylistsModel.swift:265-269`); `missingEntryIDs` ignores whether the
song's music folder is paused / unreachable (`PlaylistsModel+DeadFiles.swift:33-34`). With the music drive unplugged a
playlist's songs show as missing, and the dialog ("files that are missing from disk will be removed. This can't be
undone.", `UI/Playlist/PlaylistRemoveMissingDialog.swift:21-22`) removes them for good.

### KI-LIB-02 — Paused / failed folders are invisible; an emptied folder keeps its songs

**Status:** OPEN (slightly improved by 95870a5, PR #85: launch now reconciles every folder and pauses an unreachable one)
· **Severity:** MEDIUM · **Source:** breaker A post-R1 #8 · **Forward:** US-R1F-03.

`reconcileState` / `lastReconcileError` (`LibraryModel.swift:118-120`) have no UI reader. Songs on an unplugged drive
look normal and fail only on play; a folder whose files were all deleted keeps listing them, because the empty-walk
guard refuses the sweep silently (`LibraryModel+Reconcile.swift:153-156`). There is no Rescan control.

### LIB-VOL-1 — A music folder is bound to its drive; a sweep needs evidence (R1 sweep-evidence fix)

**Status:** OPEN (accepted limitations) · **Severity:** MEDIUM · **Forward:** US-R1F-03.

A folder is bound to its drive's volume UUID (the startup disk as itself, since its UUID changes with the Mac); one on a volume that reports no UUID (some network volumes; FAT32/exFAT report one on macOS 26) stays unbound and is walked only while some of its songs are where the library has them — so a folder all of whose files were moved or renamed at once while unbound (on such a volume, or between the v8 upgrade and its first walk) stays paused until it is removed and re-added; so does a folder whose drive is replaced by a different one with the same name (a new or reformatted "T7"); and a folder with a subfolder the app can never read never has its deleted songs swept (`LibraryStore+Roots`, `SweepRefusal`).

**Do not remove and re-add a paused folder as a workaround:** removing a folder deletes every song of it that no
playlist references, so re-adding it brings those songs back with new ids — their play counts, loved flags and
ratings are lost. A lossless "use this drive" action on a paused folder is on the council follow-up list (founder,
2026-10-14). Also narrow: the first walk after the v8 upgrade binds whatever drive is at the folder's path, so a
same-name *backup* drive mounted at that moment can be bound instead of the real one (found by the R1 break-it).

### KI-LIB-03 — A failed first metadata pass leaves "No Music Yet", with no retry

**Status:** OPEN · **Severity:** MEDIUM · **Source:** breaker A post-R1 #11 · **Forward:** US-R1F-03.

On failure the metadata pass clears its progress and reports the error, but bumps no `libraryRevision`
(`LibraryModel+Metadata.swift:37`, `:42-49`), so Songs keeps its first-run call to action while the rail lists the
folder. A relaunch's catch-up may retry the pending tags (not verified).

### KI-LIB-04 — Dragging a multi-selection onto a playlist adds one song

**Status:** OPEN · **Severity:** MEDIUM · **Source:** breaker A post-R1 #5 · **Forward:** US-R1F-04.

The drag payload is the row under the pointer (`UI/Library/SongRowInteraction.swift:33`,
`LibraryTrackDragItem(trackID:)`). The toast is honest ("Added 1 song"); the context menu's Add to Playlist takes the
whole selection.

### KI-LIB-05 — `.opus` / `.oga` files are playable but never scanned

**Status:** OPEN · **Severity:** LOW · **Source:** breaker A post-R1 #3 · **Forward:** S11 (format hardening).

`LibraryScanner.supportedExtensions` (`Sources/LibraryScan/LibraryScanner.swift:38-40`) has no `opus` / `oga`, while the
decoder plays them through the optional FFmpeg fallback and the extractor reads their tags
(`MetadataExtractor.swift:78`). PR #85 (f69421d) added only `.aif`. The scan says nothing about skipped files.

### KI-LIB-06 — Genres split on "/"

**Status:** OPEN · **Severity:** LOW · **Source:** breaker A post-R1 #2 (G-LIB-07; red test on the reference branch
`breakit/s10-8-g-library`, not on main) · **Forward:** US-R1F-04.

`MetadataExtractor.parseGenres` splits on ";" and "/" (`MetadataExtractor.swift:162`): Apple's "Singer/Songwriter",
"Hip-Hop/Rap" and "R&B/Soul" become two Genre tiles each.

### KI-LIB-07 — Case / Unicode variants split artist and genre tiles

**Status:** OPEN · **Severity:** LOW · **Source:** breaker A post-R1 #10 · **Forward:** US-R1F-04.

`artists.name` / `genres.name` are `UNIQUE` with BINARY collation (`Sources/LibraryStore/Schema.swift:116-126`), and
genre names are not NFC-normalised (`LibraryTypes.swift`; artists are). "Rock" and "rock" are two tiles.

### KI-LIB-08 — Sorting Songs by Album orders each album's tracks by scan order

**Status:** OPEN · **Severity:** LOW · **Source:** breaker A post-R1 #6 · **Forward:** US-R1F-04.

The Album and toggled-Artist sorts are title / name then row id, with no disc / track keys
(`LibraryStore+BrowseReads.swift:306-309`), unlike the default artist-album-track sort (`:289-291`).

### KI-LIB-09 — Two Filter semantics

**Status:** OPEN · **Severity:** LOW · **Source:** breaker A post-R1 #7 · **Forward:** US-R1F-04.

Songs filters by FTS token prefix (`LibraryStore+Search.swift:47`), the grids by substring
(`LibraryBrowseKit/FacetTextFilter.swift:16`); "eatles" finds nothing in Songs. A rail jump clears the grids' filter but
not the Songs filter (`LibraryBrowseModel+Sidebar.swift:24-27`).

### KI-LIB-10 — An empty playlist says "No Tracks Yet"

**Status:** OPEN · **Severity:** LOW (wording) · **Source:** breaker A post-R1 #14 · **Forward:** US-R1F-04.

`UI/Playlist/PlaylistDetailView.swift:88`; the rest of the app says "songs".

---

## Accessibility and engineering follow-ups

### KI-UI-01 — VoiceOver keeps the app fairly busy while a song plays

**Status:** OPEN (reported in the [R1 release notes](../releases/v1.0.0-alpha.md); a runtime observation that code
reading can't confirm) · **Severity:** LOW · **Forward:** US-R1F-07.

The likely driver is the 20 Hz main-thread tick invalidating observed state the accessibility tree reads; measure before
changing anything.

### KI-ENG-01 — `SpectrumDoubleBuffer` data race

**Status:** OPEN · **Severity:** internal (also an RT-safety follow-up) · **Source:** freeze "Logged post-R1" ·
**Forward:** US-R1F-07.

Two slots in a Swift array (`Spectrum/SpectrumDoubleBuffer.swift:32`): the writer (`:61`) can lap the reader (`:85`),
giving a torn spectrum frame and a theoretical copy-on-write allocation on the tap thread. Use the named-atomic
triple-buffer idiom the C++ snapshot already uses.

### KI-ENG-02 — The main-thread stall self-test lacks the breaker's extra modes

**Status:** OPEN · **Severity:** internal · **Source:** freeze "Logged post-R1";
[evidence README](../architecture/evidence/main-thread-stall-2026-10/README.md) · **Forward:** US-R1F-07.

`Debug/MainThreadStallSelfTest.swift:26-42` runs `stop`, `start`, `device-loss` and `ended-advance` with a 25 ms bound
(1% may exceed 5 ms). Port the breaker harness's engineQueue-holder and first-play modes and tighten to <5 ms.

### KI-ENG-03 — A stale comment names the removed `loudnessMeter` field

**Status:** OPEN (the residual of rev-arch's "removed APIs" note; the semgrep message and the gapless comments were
fixed in 17bef99 / 13f6281, PR #86) · **Severity:** internal · **Forward:** US-R1F-07.

`Sources/AdaptiveSound/LoudnessMeterHandle.swift:25` still says "drops the wrapper (nils `loudnessMeter`)".

### KI-ENG-04 — The `eq-light-folded` picture sheet flakes in the renderer

**Status:** OPEN (cannot be judged from code) · **Severity:** internal · **Source:** sweep ledger, "Logged post-R1" ·
**Forward:** US-R1F-07.

---

## Known limitations (by design or not yet built)

These are not defects; each is a decision or a planned feature. They are listed so a user of R1 isn't surprised.

| Limitation | Why / where decided | Forward link |
|---|---|---|
| The R1 build is ad-hoc signed and **not notarized**: macOS asks once (Open Anyway) | Founder decision 13 ([glass-sweep plan](../sprints/s10-8-glass-sweep-plan.md)); `Makefile` `dist`, PR #87 | US-REL-01 |
| **Pure Mode on Bluetooth / AirPlay** falls back to Enhanced | The link re-encodes, so bit-perfect is impossible (`PureModePolicy.cpp`; `evaluatePureViable`) | — (by design) |
| There is **no way to open or play a single file** outside the library (no Finder drop, Open… or Open With), and none to add a non-library file to a playlist | The store supports it (`addLooseFileToPlaylist`, `LibraryStore+Playlists.swift:422`), but the only UI entry was removed with the S9 IA change (7058667, "Now Playing is the queue only") and never re-added | US-LIB-02, US-PLIST-02 |
| A **copy-then-delete move** (cross-volume drag, rsync) gets a new identity: play count, loved flag and playlist entries do not follow | Move-match keys on `(dev, inode, size, mtime)` + format (`LibraryStore+MoveMatch.swift`); `content_hash` is the deferred escape hatch (SEQ-1 Gate 2) | Post-R1 pool |
| **Lossy gapless on the FFmpeg backend** keeps encoder delay / padding (Apple's decoder trims it) | `FileDecodeSource.cpp` | US-PLAY-07 → S11 |
| **DSD** is not supported | Deferred past R2, gated on a DSD DAC ([sprint-plan](../sprints/sprint-plan.md) §5) | post-R2 |

---

## Closed

### Fixed by PR #85 / PR #86 (re-verified 2026-10-13)

- **The 13 Sprint G R1 blockers** (5 library, 8 playback / devices / Master Gain) — fixed in PR #85; see the two
  break-it reports and the [sweep ledger](../sprints/s10-8-sweep-ledger.md) "Build, break-it, fixes and live pass".
- **The disconnect freeze** (switching headphones off froze the app 3–7 s) — fixed in PR #86; evidence in
  [main-thread-stall-2026-10](../architecture/evidence/main-thread-stall-2026-10/README.md).
- **G-LIB-03** — New Playlist failed beside a "new playlist" in another case: fixed by ad2ee3c (PR #85), the free name
  is now picked case-blind (`LibraryStore+Playlists.swift:198-199`); regression test
  `Tests/LibraryBrowseKitTests/LibraryBreakItGTests.swift:93`.
- **Breaker B post-R1 #2** — Pure leaked a device-alive listener per manual start: fixed by a4c5bc1 (PR #85), one
  alive listener on the app's device (`AudioEngineBridge+OutputDeviceMonitor.swift:76-91`).
- **Audit S1-E** — the loudness-meter snapshot race / potential use-after-free: fixed by cc976dc (PR #86),
  `withExtendedLifetime(meter)` over a strong copy (`AudioEngineBridge.swift:341-343`).
- **`passUnretained` without `withExtendedLifetime`** on the effects AU: fixed by 69b94aa / cc976dc (PR #86),
  `withEffectsAU` (`AudioEngineBridge+SharedState.swift:252-256`).
- **R10, the engine-lock-held regression test:** added by a861cc6 (PR #86) as `make main-thread-stall` in the strict
  gate.
- **Pure resume played the intro** (start-then-seek): fixed by 92c1801 (PR #86), `startAudio(…, startAt:)`
  (`AudioEngineBridge+PureMode.swift:120`).

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
only — `JOIN playlists p … WHERE p.is_builtin = 0`, `LibraryStore+DAO.swift:365-366` — so songs that were merely in the
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
