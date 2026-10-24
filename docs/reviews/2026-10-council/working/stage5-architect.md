# Council Stage 5: architect cross-examination

This report gives the consolidated finding register, the shared root causes, the conflicts resolved, the converged plan,
the founder decisions, and the response to the pre-mortem.

**Reviewer and base.**
- Reviewer: architect-reviewer, cross-examined by the-fool. Read-only.
- Code base: `main` @ `9df49e3`, which is v1.0.0-alpha plus the R1 fix commits `ee8e3dd`…`9df49e3`.
- Every Stage 1–4 report read `7d7c2cd`, so this register was **re-baselined at `9df49e3`**.

**Inputs.**
- All 35 council files in this folder.
- `stage5-fool.md`, the pre-mortem. It is answered point by point in §6, and the points I accepted are folded into §1–§5.

**How claims were checked.**
- Every STRUCTURAL rating and every FIXED-R1 claim was checked against `9df49e3` with `git grep` / `git show`.
- I re-ran the fool's Ogg/Opus probe (`scratchpad/fool-ogg/probe`). No app was launched, and nothing was built in the
  checkout.
- In the Evidence column, ✓ means I checked it at `9df49e3`. Every other file:line comes from the source report, at
  `7d7c2cd`.

**Severity, recalibrated across the reports:**
- **STRUCTURAL:** a design choice whose consequences show up in two or more areas, or that blocks a roadmap epic.
- **SIGNIFICANT:** a real correctness or brittleness risk, or an audible, data or user-visible defect, within one area.
- **LOCAL:** contained. The fix changes no contract.

**Result:**
- **94 OPEN rows.** One of them only points to the logged post-R1 list.
- **9 FIXED-R1 rows.**
- **20 refuted or corrected claims.**
- More than 230 source IDs are merged into these rows.
- **The 93 open findings by severity:** STRUCTURAL 8, SIGNIFICANT 60, LOCAL 25.

---

## 1. Finding register

Column key:
- **Crit:** the charter criteria. 1 = elegance, 2 = patterns, 3 = duplication, 4 = algorithmic correctness, 5 = state
  of the art, 6 = maturity.
- **Sev:** S = STRUCTURAL, G = SIGNIFICANT, L = LOCAL.
- **Effort / risk:** effort S / M / L, then risk low / med / high.
- **R1.1 tag:** the row has a slice in the R1.1 quick-fix list (§4.4).

### A. Architecture and cross-cutting

| ID | Merged sources | Finding | Crit | Status | Sev | User impact | Evidence | Effort / risk |
|---|---|---|---|---|---|---|---|---|
| C-01 | ARCH-1, VM-2, BR-3, N12–N15 (structure), DUP-12 | One play state machine is split between the view model (VM) and the bridge. Neither has a State or Event type. Each side keeps its own epochs. | 1,2,4 | OPEN | S | Every wrong-song, "Playing but silent" and missed-pause bug comes from here. So does Pure's pause being a device teardown (C-100) | ✓ `AudioViewModel.swift:70,74`; ✓ `AudioEngineBridge.swift:79,198,237`. Pause = "stop + resume point" (✓ `+Transport.swift:45-47`). P4 found 8 of 9 defect groups on this seam | L / high. Funded slice only (§4) |
| C-02 | ARCH-2, BR-1 (model), BR-5, BR-11, BR-13, BR-14, VM-10 | Isolation exists only by convention. GCD queues carry "confined to X" comments, and those are false in ≥ 4 places. There is 1 production actor. 8 app types are `@unchecked Sendable`, and 27 files `@preconcurrency import`. There are 3 lock idioms and ~12 hand-rolled "newest wins" counters. Tasks are fire-and-forget; the device-refresh ordering is unproven (LOCAL, per the fool). There is an AU spin-wait, and the graph is built off its queue. | 1,5,6 | OPEN | S | Freeze, zombie-audio and wrong-song bugs that only a person with hardware finds | ✓ the only actor is `TrackLoudnessAnalyzer.swift:89`; ✓ `AudioEngineBridge.swift:35`; ✓ `+SharedState.swift:239` (spin); ✓ 27 `@preconcurrency` files | Cheap step M (`Mutex`, enqueue-a-command) / actor only inside W2 |
| C-03 | ARCH-3, ARCH-11, BT-5 (structural half) | The app target is a 28k-LOC monolith. The main-thread and layering rules are regexes. The VM defaults its own concrete engine. There are 3 C-import mechanisms, and the bridging header is dead. | 1,6,3 | OPEN | S | None directly. The next freeze comes through a path the regex misses | ✓ `AudioViewModel.swift:407`; ✓ 3 × `-import-objc-header` in `Package.swift`; ✓ the unreferenced `AdaptiveSound-Bridging-Header.h` | M (one `PlaybackEngine` target, not a 5-module split) / med |
| C-04 | ARCH-4 (downgraded per the fool) | The file URL is the identity of a playable thing in the VM, the engine API, the Pure C-ABI and the loudness token, and `tracks.url` is UNIQUE. The store already has a durable `tracks.id`; play counts and playlists use it. | 1,2 | OPEN | G (S if CUE is wanted) | Blocks CUE and virtual tracks only | ✓ `AudioFile.swift:10`; ✓ `+DAO.swift:75`; ✓ `AudioPlaybackEngine.swift:76,141`; ✓ `TrackIdentity.swift:28`; ✓ play counts by id at `+PlayTracking.swift:66-71` | M (type) + L (bounded sources) / med. Only if S11 keeps CUE |
| C-05 | ARCH-5, UI-3, VM-11, VM-12, BR-15, DUP-4 (verbs) | There is no command catalogue: four kinds of command are `didSet`s behind bindings, and five surfaces are wired by hand. There are no menu-bar verbs, no `FocusedValue` and no `UndoManager`. The 20-requirement engine protocol has silent no-op defaults. | 1,2,3 | OPEN | S | Library verbs are not in the menu bar; there is no ⌘Z; each list has different verbs. An MCP gateway written today would be a second control path | ✓ `AudioViewModel.swift:142-145`; ✓ 0 `FocusedValue` and 0 `UndoManager`; ✓ `AudioPlaybackEngine.swift:33` | S (`didSet` → intents) now. The M catalogue comes when MCP graduates |
| C-06 | ARCH-8, VM-3, VM-6, BR-9 | There is no event channel. The app learns of engine changes by diffing a polled 20 Hz snapshot, by single-slot closures, and by control facts stored in display structs. Revision counters are bumped by hand. Now Playing works by "remember to refresh". | 1,2,3 | OPEN | S | A stale Control Center. Seams are handled up to 50 ms late, and not at all during a stall. Wake-ups while idle | `+SpectrumTimer.swift:18,35,92-130`; `+OutputDeviceMonitor.swift:199-229`; ✓ `libraryRevision` ×24 | M-L / med. Funded by MCP v2 / S14-adaptive |
| C-07 | DSP-01, BR-2, BR-10, DUP-1, D39 (root) | There are two playback engines. Enhanced hands the audio queue to `AVAudioPlayerNode`'s schedule; Pure owns a C++ source pipeline. The result is 4 restart paths, 3 seeks, 2 playheads, 2 end flags and 2 seam-count domains, and they already disagree. | 2,3,5 | OPEN | S | The Enhanced gaps, clicks, early re-base and seek hang (C-21–C-25). Every transport fix lands twice | ✓ Enhanced opens `AVAudioFile` (`+Playback.swift:161`); `FileDecodeSource.cpp:900-1152`; P3 replicas | Fix in place first (R1.1). Then the SFB spike decides adopt vs in-house (L / high) |
| C-08 | ARCH-6, D73, docs-arch F2 (narrowed per the fool) | Five probe/decode paths each open files themselves. Ogg Vorbis and Opus **do** open through `AVAudioFile` on macOS 26, so FFmpeg is nearly redundant. The scanner's list omits `.opus` and `.oga`. | 1,3 | OPEN | L | Opus files never reach the library | ✓ re-run probe: `v.ogg` / `o.ogg` / `o.opus` all open (`scratchpad/fool-ogg`); ✓ `+PureMode.swift:47`; `LibraryScanner.swift:38-40` | S / low (R1.1) |
| C-09 | ARCH-7, P1 (the SVF can host shelves) | The EQ is one vertical 31-band contract with one intent. Its loudness-neutral gain covers the whole curve. | 1,2 | OPEN | G | Would neutralise an S14 compensation tilt. Blocks S12 (PEQ / AutoEq) and S13 | ✓ `Realizer.mm:430`; `TargetState.h:28-49,158-162` | S14 needs only S-M: neutral gain from the taste-only design. `EQProgram` is M-L, at S12 |
| C-10 | ARCH-9, VM-9, DSP-17, DUP-17 (logging), process §3.2, fool §3.5 | There is no observability. No `os.Logger`, no signposts, no MetricKit, no "Copy Diagnostics", no issue template, no hang detector beyond the engine-lock class. All `errorMessage`s share one last-writer-wins slot. Store errors are swallowed by 34 `try?`. C-ABI results are int and bool. | 6,5 | OPEN | G | Field logs are lost from an `open`-launched app. A public alpha has no way to send feedback back. Messages get erased | ✓ 0 `os.Logger`; ✓ `UXLog.swift:7`; `.github/` has no issue template | S each (R1.1). Typed errors only at the MCP boundary |
| C-11 | VM-1, ARCH-10, ARCH-12 | God objects are split across extension files to satisfy lint. AudioViewModel is 14 files and 56 vars, the bridge 23 files, the store 18. The Kit pattern lacks a stateful core. | 1,2,6 | OPEN | G | None directly | ✓ 14 + 23 files; ✓ 56 `var`s | Inside the funded refactors. **No new lint fitness gate** (fool) |
| C-12 | VM-5, DUP-17 (keys), product #1, KI-SET-01 | Listening settings are not persisted: Pure, Intensity, crossfeed, and the chosen device. The *effective* value overwrites the intent (crossfeed). The setting keys live in 4 places. Master Gain is split out as C-102. | 1,3,6 | OPEN | G | Every launch forgets Pure and crossfeed | ✓ `AudioViewModel.swift:106`; ✓ `+Devices.swift:82-83` | M / low (`SettingsStore`) |
| C-13 | VM-6 (composition root), VM-13 | The composition root is closure wiring in `App.init` plus a window `onAppear`. Play from the menu-bar extra can run before the engine is initialised. | 1 | OPEN | L | "Engine not ready" from the menu bar | `AdaptiveSound.swift:52-138` | S / low |
| C-103 | fool §3.6 | Distribution and identity. Ad-hoc signing gives each release a new code identity, so TCC grants (removable and network volumes) are likely asked again; unverified. There is no updater, no LICENSE, and the GRDB notice is not bundled. 11 no-op security-scope calls exist (there is no sandbox), and the `bookmark` column is unused. | 6 | OPEN | G (if public) | Re-prompts after each update; testers never hear of R1.1; nobody may legally reuse the code | ✓ 11 `startAccessingSecurityScopedResource`; ✓ `allow_auto_merge: false` and no licence (`gh api`); `Makefile:61-74` | S-M / low. FD-7 |

### B. Transport and queue

| ID | Merged sources | Finding | Crit | Status | Sev | User impact | Evidence | Effort / risk |
|---|---|---|---|---|---|---|---|---|
| C-14 | P4-1, N13b/c, N14, N15, D41 follow-up F1 / A2 / A2′ | The engine reports a seam as an anonymous count, and the VM guesses the track from `pendingNextIndex`. **SEAM-AT-START:** a stale count leaks into a new start. **COUNT-DOMAIN:** Pure counts per start, Enhanced counts cumulatively. **A2 / A2′:** a late request, or an edit between a seam and the next tick, shows the wrong song. `ended` stays latched across a seek. | 1,4 | OPEN | G | The title and the play count name a song other than the one you hear | p4 §4 P4-1; d41-design §6; `+TransportClock.swift:55-61` | S-M short (R1.1) / L full (W2) |
| C-15 | P4-2, P4-7, VM-2 ("starting"), N12, N13a, N17, N20 | Epochs guard samples, not commands. Stop is numbered inside its Task, and it is two engine calls. There is no starting or pausing state. `pendingNextIndex = nil` means both "suppress" and "end of queue". | 1,4 | OPEN | G | Shows Playing over a silent engine. A Pause during a start is dropped. A double Space starts twice. A pause in the last tick restarts at 0:00 | ✓ `+Lifecycle.swift:160-161,174-175`; P4 E1 STOP-THEN-PLAY / PAUSE-THEN-PLAY on the real VM sources | S-M / low-med (R1.1) |
| C-16 | P4-3, N1, N2, N21, KI-PB-03 | Shuffle draws with replacement. Previous has no history, and with repeat off shuffle never ends. | 4,5 | OPEN | G | Shuffle repeats songs, and Previous is random | P4: 0 of 2000 runs end; 26.8 plays to hear 10 songs | M / low |
| C-17 | P4-4, P4-5, N4, N6, N18, the "append during prime" twin of F-P4-1 | The on-deck pick goes stale after queue edits: a song dragged in under the current one never plays; a repeat-all append waits a whole cycle; a one-track shuffle plus an append stops. An append during a start's prime isn't armed. `playNextNow` ignores duplicates. | 4 | OPEN | G | A song you queued is skipped, or the queue stops early | ✓ `+Queue.swift:183` (`guard isPlaying`); P4-4/5 | S / low (R1.1) |
| C-18 | VM-7, DUP-6 (current track), UI-8, VM-11 | Selection and the armed track are row indices. "Current track" is derived about 10 times, with different guards. The O(n) `playlist` shim runs in views that are always mounted. Control Center enables Play past the end. | 1,3,4 | OPEN | G | Wrong track after edits (rare); slow views on a 10k-song queue | `AudioViewModel.swift:226-244`; `NowPlayingController.swift:308` | M / med |
| C-19 | P4-6, N26, VM-3 (stall), ledger | Play-through accrues wall time while `isPlaying`, not audio actually heard. | 4 | OPEN | L | Inflated or misattributed plays | P4: 1.01 s credited per 1.0 s of silence | S (R1.1) / M |
| C-20 | P4-8, N27, N29 | Frecency has no v4 backfill, and a play stamped in the future dominates for years. | 4 | OPEN | L | Recently Played misses older songs | `Schema.swift:390-396` | S / low |

### C. Enhanced path and bridge

| ID | Merged sources | Finding | Crit | Status | Sev | User impact | Evidence | Effort / risk |
|---|---|---|---|---|---|---|---|---|
| C-21 | D39 a/b, rev-sota M5, KI-GAP-01 | At 48 kHz, track B is scheduled only after A's `.dataPlayedBack`, so the gap equals the device latency (27–215 ms). The resampler roll race inserts up to 279 frames. | 4,5 | OPEN | G | Audible gaps on "gapless" albums | `+GaplessRoll.swift:189-216`; P3-SOTA: scheduling from `.dataConsumed` gives a 0-frame gap | S / low (R1.1) |
| C-22 | D39 c | A resampler→resampler seam clicks (−18 to −26 dB re peak), because each track gets its own converter. | 4 | OPEN | G | A click at every join on a 44.1 or 96 kHz album | `+GaplessRoll.swift:248-257` | S-M / low (R1.1) |
| C-23 | D40, rev-sota M2 (corrected) | The seam re-base and B's loudness switch land 0–186 ms early. The N-2 fallback stays stuck at 0:00 after a seek. | 4 | OPEN | G | B's gain is applied to A's tail; the clock is stuck | `Gapless.swift:186,196-201` | M / med |
| C-24 | BR-7, D39 (A4) | An Enhanced seam across a change in channel count is unguarded: only the rate is compared. | 4 | OPEN | G | Mono→stereo drops R; 6-ch drops C, LFE and surrounds, or goes silent | ✓ `+GaplessRoll.swift:39-42,77-81` | S / low (R1.1) |
| C-25 | BR-8, D37 (seek), DUP-1 | Enhanced seek writes the position base before it knows the seek succeeded. **Dragging the scrubber to the end** of any non-48 kHz track is refused (93 % of track lengths), and playback then stays silent forever. NaN traps. The restart paths disagree on clamping. | 4,3 | OPEN | G (**R1.1 blocker**: "music stopped") | Drag to the end of a 44.1 kHz CD rip and the music stops and never moves on | ✓ `NowPlayingBar.swift:332-333` (`dragFraction * duration`); ✓ `+EnhancedResampler.swift:193-202`; ✓ `+PureMode.swift:226,338-339` | S / low (R1.1 #2) |
| C-26 | D37 (quality), D38 | SRC uses AVAudioConverter's Normal algorithm: −8.25 dB at 20 kHz, and 192→48 aliases at −21 dB. The claim "Mastering stalls" is false. A device not at 48 kHz gets a hidden second SRC. `SRCQualityMeasure` passes a −7 dB error. | 4,5 | OPEN | G | Rolled-off treble in Enhanced, the default mode | ✓ `+EnhancedResampler.swift:82`; ✓ `+Gapless.swift:259` | S / low (R1.1) |
| C-27 | BR-1 (instances), BR-6 | The bridge drives the player off `engineQueue`: a config-change TOCTOU, and a global-queue `playFile` fallback. `engineQueue` is head-of-line blocked: a 7 s `engine.stop`, file opens, 10 `.sync` edges. | 1,4 | OPEN | G | Wrong position or zombie audio around device switches; a frozen clock and gain slider during teardown | ✓ `+ConfigChange.swift:32,86-87`; ✓ `+GaplessRoll.swift:161` | M / med. Cheap step: post a command to `engineQueue` (fool, BR-1) |
| C-28 | P5B-04, N94 | An Enhanced start races the output rule: 1–3 of every 11–36 interleavings end silent or on the wrong device. The N92 fix did not change this. | 4 | OPEN | G | It shows Playing with no sound after a Bluetooth connect plus Play | `+Playback.swift:96,123`; p5b-reconnect-recheck §5 | S / low (R1.1) |
| C-29 | BR-12, DUP-8 (slot), KI-SET-02, product #12, D84 | Master Gain and device volume are two mechanisms. A gain cut doesn't carry into Pure. Pure→Enhanced attenuates twice. "Silent" sets the device to its minimum. Devices with per-channel volume only read as fixed. | 3,4 | OPEN | G | Loudness jumps across a mode switch; "silent" isn't silent | `+MasterGain.swift:24-68,140-170` | S / low (R1.1) |
| C-30 | DUP-3, D44 (gate), VM-11, KI-DEV-01, P5B-10/N97, DSP-05 (helpers) | Output-device facts are classified 4 different ways. The built-in jack isn't counted as "headphones", while AirPlay and Bluetooth speakers are. A failed rate read becomes 48 kHz. A string sentinel is used. 3 paths make a device the output. The menu sort is unstable. | 3,4 | OPEN | G | Crossfeed is unavailable on wired headphones; the limiter ceiling and the Pure decision can disagree | `AudioViewModel.swift:166-171`; `CoreAudioDevice.cpp:246-265,321-345` | M (classification S in R1.1) |

### D. Pure and HAL

| ID | Merged sources | Finding | Crit | Status | Sev | User impact | Evidence | Effort / risk |
|---|---|---|---|---|---|---|---|---|
| C-100 | fool §3.2 (new) | **Pure pause is a full device teardown.** Pause = stop, and stop runs `tearDownPure()`, which releases hog and restores the device's original nominal rate. Pausing and resuming a 44.1 kHz file on a 48 kHz DAC switches the DAC's rate twice. Another app can take the device during the pause. Not verified on hardware. | 1,4 | OPEN | G | Relay clicks or mute on DACs at every pause; possibly losing the device | ✓ `+Transport.swift:45-47`; ✓ `stopAudio` → `tearDownPure()`; ✓ `HALOutputEngine.mm:350-351` (save, then restore) | M / med. Needs a DAC (FD-5) |
| C-31 | DSP-05, D75, D77, purefix (c) | The HAL device-state contract is incomplete. The physical format and mixability are never restored. Hog is set "by value", but the property toggles. Properties are set then read without a listener. Shared mode has no rate listener. The rate and the format are set in two separate steps. | 4,5,6 | OPEN | G | The DAC is left in Pure's format; bit-perfect silently isn't | `HALOutputEngine.mm:308-336,672-711,895-969`; VLC `auhal.c`; Cog | M / med (HIL) |
| C-32 | D72, N98 / P5B-06, D73, purefix (b) | Capability facts are not single-source. A rate *range* is reduced to its endpoints. `integerCapable` is read from the current format. The Swift policy call sends bits = 32 / float. `requiresHog` is pinned true in the tests but false in production. | 4,6 | OPEN | L | Pure is refused on devices that report rate ranges | ✓ `PureModePolicy.cpp:139` vs ✓ `PureModeBridge.cpp:229` | S / low |
| C-33 | D71 (depth), D74 (rounding) | A 24-bit source on a 16-bit-only device is labelled BitPerfectInteger, and is truncated without TPDF. | 4,5 | OPEN | L | A false "bit-perfect" badge | ✓ `PureModeFormat.cpp:78-97`; ✓ the policy has no depth check | S / low (R1.1) |
| C-34 | DSP-02, DUP-15 (ABI), purefix (a) (narrowed per the fool) | The C-ABI's int results flatten the reason Pure declined. `void*` handles come in 3 conventions, and ownership is described only in prose. | 1,5,6 | OPEN | G | "Pure unavailable" never says why | `PureModeBridge.h:118-185`; `PureModeBridge.cpp:138-205` | S now (a named reason enum, surfaced in the UI). Typed handles only when a bridge is next touched |
| C-35 | D79 | The FFmpeg seek ignores the stream's `start_time`. A refused decoder seek skips the buffered audio. | 4 | OPEN | L | Moot if FFmpeg is deleted (FD-3) | `FileDecodeSource.cpp:643,780,984-1000` | S / low |
| C-36 | DSP-06 (remedy 1), DSP-15, D78 note, p3a-d41 §4 | A seek mutates the consumer-owned ring, and the decode thread is respawned per seek. The ring is sized in floats: 0.17 s at 192 kHz / 8 ch. The thread has no QoS. Parked sessions keep their threads. | 1,5 | OPEN | L | Underrun risk at high rates | `FileDecodeSource.cpp:89-107,988-1002,1094` | M / med |
| C-37 | D42 | Pure's same-format predicate demands the same bit depth and float flag, and ignores the channel layout. | 4,5 | OPEN | L | A gap at a 16↔24-bit album join | `GaplessSource.cpp:67-76`; SFB compares rate, channels and layout | S / low (R1.1) |

### E. DSP chain and loudness

| ID | Merged sources | Finding | Crit | Status | Sev | User impact | Evidence | Effort / risk |
|---|---|---|---|---|---|---|---|---|
| C-38 | D20, P2-2, DSP-07 (reset), product LUFS row | The normaliser is a session-long AGC. The makeup gain carries across tracks. A gapless run is never re-measured, so a quiet track is gated out. +12 dB of makeup feeding a −1 dBTP limiter is DRC by default. The makeup snaps to 0 dB on re-allocation. ReplayGain / R128 tags are not read. | 4,5 | OPEN | S | Quiet tracks stay quiet, loud ones get squashed, and the level jumps after a device change | ✓ the meter resets per `playFile` (`LufsMeter.h:237-243` via ✓ `+ChannelLayout.swift:64-74`); the makeup never resets (`LoudnessModule.cpp:62,283`) | Off the default path at S (C-41 / FD-2); the real fix is M (S14 slice) |
| C-39 | D34, P2-1 | The limiter's dual release is dead code: in practice it is a single 500 ms release. | 4,5 | OPEN | G | One snare hit ducks the music for about 1 s | ✓ `LimiterModule.h:398-416` | S / low (R1.1) |
| C-40 | D50, DSP-10 (4), P2-7 | The Intensity blend is equal-power on correlated wet ≈ dry: +2.0 dB at the default, +3.0 dB at 0.5. A test pins it. | 4,5 | OPEN | G | The knob changes loudness, not sound | ✓ `DSPKernel.cpp:274-275`; `IntensityTests.inc:236-280` | S / low (R1.1) |
| C-41 | D48, P2-9, DSP-10 (3), product §0.3, fool §4 #2 | **Every fresh launch plays processed.** Intensity defaults to 0.20, which switches on C-38, C-39 (via the −1 dBTP ceiling) and C-40. And Intensity is hollow: Clarity and BRIR are identity stubs in the real-time path. | 1,2 | OPEN | G | The default sound contradicts "faithful > processed" | ✓ `AudioViewModel.swift:142` (`= 0.20`); `ClarityModule.h:33`; `DSPKernel.cpp:401-407` | S / low (**R1.1 #1**, FD-2) |
| C-42 | D44, D45, P2-3 | The crossfeed is not bs2b. The ITD is counted twice and the direct path is flat, giving a −4.2 to −6.3 dB centre notch near 1 kHz. The "Default" preset is mislabelled. | 4,5 | OPEN | G | Hollow vocals with crossfeed on | `CrossfeedModule.cpp:95-120`; libbs2b | S-M / low (R1.1) |
| C-43 | D46, DSP-08, P2-6, docs F1/F2, KI-MC-01 | N→M truncation: 5.1 or 7.1 on a stereo output keeps slots 0–1 only. The limiter sits before the spatial AU, so any fold-down breaks the ceiling. | 4 | OPEN | G | On headphones, a 5.1 file loses its centre (the vocals), LFE and surrounds | ✓ `SpatialRenderKernel.cpp:59-80,175-177` | S-M / low (FD-9) |
| C-44 | D46 (order), D47, P2-8 | Channel roles are never derived from labels. ALAC / AAC 5.1 is routed by position. 3-, 4-, 5- and 7-channel files fall back to stereo. 8 channels are forced to 7.1 A. | 4,5 | OPEN | G | Every channel on the wrong speaker; 5.0 files lose C, Ls and Rs | `+Reconfigure.swift:97-105`; P2 probe on real files | M / med |
| C-45 | D19, D70, P2-4, P2-5, DSP-07 (layout) | BS.1770 weights: only 5 tags decode, so LFE gets weight 1 on common files. The 7.1 back surrounds get 1.41 where the standard says 1.00, and a test pins it. After re-allocation the weights reset to {1,1,0,…} (−16.9 LU). The layout bypasses the Realizer and races re-init. | 4,3 | OPEN | G | Multichannel files are levelled wrong | ✓ `AUAudioUnit.mm:231-234`; ✓ the Realizer has no layout | M / med |
| C-46 | DSP-09, D59, P2-10 | The real-time analysis tap exists twice. Its workers poll forever (about 200 wake-ups per second while paused). There are four loudness meters, and the UI's "Integrated" spans the whole session. | 3,5 | OPEN | G | Battery drain while paused; a misleading Integrated readout | `LoudnessModule.cpp:240-244`; `LoudnessMeterBridge.cpp:51-60` | M (reset per track S, R1.1) |
| C-47 | DSP-10 (1,2,5), DSP-07 (lifecycle) | The chain is hand-wired: no stage concept, and the P0–P3 path choice is a set of booleans. Every allocate rebuilds the modules and their threads. | 1,2 | OPEN | L | None directly | `DSPKernel.cpp:62-76,176-224` | M / med |
| C-48 | DSP-13, DUP-16, D32 (latent) | Rate domains and constants disagree. Swift hard-codes 48000 ×7. The EQ designs up to 768 kHz, the profiler and limiter cap at 192 kHz. | 3,4 | OPEN | L | Latent today. Live if the graph ever follows the device rate (SFB or W4) | `AudioConstants.h:31-33`; ✓ `+Lifecycle.swift:46` | S / low |
| C-49 | D7, Q-1 | Below 44 kHz the EQ silently plays flat. | 4 | OPEN | L | The EQ is off on AirPods while the mic is in use | `Realizer.mm:416-423` | S-M / low |
| C-50 | DSP-11, D67, D60, D31 note | Numeric hygiene. Flush-to-zero is never restored. A comment says FZ doesn't flush doubles; it does. The ramp stagnates. True peak can read below the sample peak. | 5,4 | OPEN | L | None audible | `FlushToZero.h:32-40`; `LufsMeter.h:123-128` | S / low |

### F. Live readouts, visuals and accessibility

| ID | Merged sources | Finding | Crit | Status | Sev | User impact | Evidence | Effort / risk |
|---|---|---|---|---|---|---|---|---|
| C-51 | D53–D57, Q-2 | The spectrum analyser reads +4.26 dB high. N = 4096 at every rate. The hand-off tears frames (a TSan race). The caps run at half speed. | 4,6 | OPEN | L | A flat-topped analyser that is wrong at high rates | ✓ `SpectrumAnalyzer.swift:109` | S / low (R1.1) |
| C-52 | UI-2, VM-3 (idle), VM-4, DUP-12, docs-product F5, fool §3.8 | The live visuals cost too much. The analyser is 88 animated views at 20 Hz (~18× the update cost of a `Canvas`). Two 20 Hz main-thread timers run while paused and while the app sits in the menu bar. Energy use has never been measured. | 1,3,5 | OPEN | G | CPU and battery in a menu-bar app | `SpectrumAnalyzerView.swift:50-84`; `+SpectrumTimer.swift:14-41` | S (timer gating, R1.1) + M (`Canvas`) / low |
| C-53 | VM-4, UI-4 | The scrubber and its accessibility modifiers re-evaluate 20 times a second. Readings sit in the accessibility *labels*. `.updatesFrequently` is used once. | 1,5,6 | OPEN | G | VoiceOver keeps the app busy (stated in the release notes) | `NowPlayingBar.swift:222-223,356-363`; `LoudnessMetersView.swift:108-109` | S-M / low (R1.1) |

### G. Library and user data

| ID | Merged sources | Finding | Crit | Status | Sev | User impact | Evidence | Effort / risk |
|---|---|---|---|---|---|---|---|---|
| C-54 | p5a-libfix-recheck RC-g, RC-e, RC-a/b | There is no lossless rebind. The documented remedy (remove and re-add the folder) resets plays, loved and rating for every song not in a playlist. During the unbound window, a same-named backup drive can be bound and swept. | 4,6 | OPEN | G | Following our own known-issues advice loses your history | RC-g repro | S / low (R1.1: "Use this drive") |
| C-55 | p5a Q3, LIB-06 (paused), product #14 | A refusal covers the whole root: one unreadable subfolder freezes reaping and the tag pass for that root. The paused state is invisible. | 4,6 | OPEN | G | Deleted songs never leave; new songs stay untagged; you're never told | `LibraryModel+Reconcile.swift:141-149` | S-M / low (R1.1) |
| C-56 | LIB-02 step 2, P5A-01 remedy 2, KI-LIB-01, Q-5, fool §4 #11 | LIB-02 is **narrowed, not closed**. Deletion is still immediate after a trusted walk: there is no `missing_since` tombstone. "Remove Missing" can't tell unplugged from deleted. A corrupt store is quarantined without salvage. | 4,6 | OPEN | G | An unplugged drive loses playlist entries; a corrupt store strands your playlists | `PlaylistsModel+DeadFiles.swift:33-34` | M-L / med. Before any new scan or watch feature |
| C-101 | fool §3.3 (new) | **User data has exactly one copy.** There is no playlist export (no M3U) and no "Back up library data". The only backups are made before migrations. | 6 | OPEN | G | One disk or store failure loses every playlist and the whole play history | ✓ no M3U writer in `Sources/`; `StoreBackup.swift` (pre-migration only) | S / low (R1.1) |
| C-57 | LIB-03, P5A-03/05/06/07/08 | Move and identity break in several ways. A cross-root move loses its id depending on walk order. The scan generation isn't unique. Hard links, replace-in-place and same-second rewrites break identity. The metadata pass can lose an update. | 4 | OPEN | G | Moving music loses plays and playlist entries | `+DAO.swift:167-175`; `+MoveMatch.swift:~28` | M (with S slices in R1.1) / med |
| C-58 | LIB-01, LIB-09, LIB-15, DUP-8, P5B-01 / N72 | Reads aren't reactive. `libraryRevision` is used 24 times, there are 9 hand-kept epochs, and the views decide when to reload. The reload path isn't newest-wins. | 1,2,3,5 | OPEN | G | Brief flashes of an empty or "unavailable" list; a fresh scan match stays hidden | ✓ 9 epochs; ✓ 0 `ValueObservation` | P5B-01 fix S (R1.1). One `LoadSlot` S-M. `ValueObservation` funded by smart lists |
| C-59 | LIB-06, ARCH-2 b | Library activity is a model-owned machine of about 11 mutable fields, with three "supersede" idioms. It is untested. | 1,2,6 | OPEN | G | The G-LIB class of races can recur | `LibraryModel+Scan.swift:~165-182` | M-L / med |
| C-60 | LIB-08, N31, fool §3.7 | Every file-system change triggers a whole-root walk, a whole-library regroup and 4 full reloads. There is **no library-size target and no performance gate.** | 1,4,5 | OPEN | G | Churn at 50k–200k tracks, which is common for audiophiles | `LibraryModel+Reconcile.swift:~85` | Perf gate S; incremental L (FD-10) |
| C-61 | LIB-05, LIB-11, DUP-9, P5A-04, P5B-07/11, Q-6 | Search uses 3 different semantics. Sinhala vowel signs act as separators (මාල = මිල). NFD text can't be found. Type-select folds marks. There is no global search. | 3,4,5 | OPEN | G | Searching in Sinhala returns the wrong words; results differ by tab | P5A SRCH-1..5; `LibraryStore+Search.swift:16-48` | S-M / low |
| C-62 | LIB-04, LIB-16 | The store exposes about 25 test hooks and about 20 operations the app never calls (the playlist-folder DAO among them). | 3,6 | OPEN | L | None | `LibraryStore.swift:62-175` | M / low |
| C-63 | LIB-07, LIB-16, DUP-10, DUP-11 | Raw SQL with 56 positional reads, ordered only by comments. The title fallback is written 4 times, and several write paths exist twice. | 1,3 | OPEN | G | A schema change can mis-decode silently | `BrowseReads.swift:~60,304` | M / low-med |
| C-64 | LIB-10, N71 | Migrations hold four sources of version truth, plus permanent v7 refusal code. | 1,6 | OPEN | L | None | `Schema+AlbumArtists.swift:1-5` | M / med |
| C-65 | LIB-12, DUP-8, DUP-17, VM-5 (cursor), product #3 | The queue mirror's debounce can race. The cursor reaches UserDefaults only at a clean quit. The queue doubles as a built-in playlist. | 3,4 | OPEN | G | A crash or force-quit loses your place | `+QueueMirror.swift:25-36`; `+Lifecycle.swift:125` | S / M |
| C-66 | LIB-13 (partly refuted), DUP-10, N52 / N76, Q-1 | Album rules live in two layers: the year tie differs, but only transiently; the album-folder derivation differs. | 3,4 | OPEN | L | The year differs mid-scan | `AlbumGrouping+Years.swift:25` | XS / low |
| C-67 | LIB-17, P5A-09/10/11, Q-4 | Unicode and path normalisation: `PathNormalizer` is not pure; the nested-root check is case-sensitive; playlist names compare ASCII-only and allow NFD duplicates; the collation is NOCASE. | 4,5 | OPEN | L | "Été" and "été" are both allowed; "Ångström" sorts after "Z" | P5A-09/10/11 | S-M / low |
| C-68 | LIB-14 | Store errors are swallowed into "empty". A failed roots read stops the watcher silently. | 6 | OPEN | L | The first-run screen can appear over a real library | `LibraryModel+Reconcile.swift:58` | S / low (R1.1) |
| C-69 | docs-product F4, LIB-04 | There is no loose-file entry: no Open…, no drop target, no document types. US-LIB-02 (Must) is undelivered. | 6 | OPEN | G | You can't play a file that is outside the library | `LibraryStore+DAO.swift:226` | S-M / low |

### H. User interface

| ID | Merged sources | Finding | Crit | Status | Sev | User impact | Evidence | Effort / risk |
|---|---|---|---|---|---|---|---|---|
| C-70 | UI-1, DUP-4 | There are six list scaffolds with 3 click models. The queue has no multi-select. Fixes have reached only some of the lists. | 1,3,5 | OPEN | G | Inconsistent clicks; a double-click logs two plays | `PlaylistItemList.swift:43,115,173,265` | L (queue and playlist first, M) / med |
| C-71 | P5B-02 / N83 | `ListSelection` is not macOS-faithful: ⇧ after ⌘ drops rows, and ⌘A then ⇧-arrow collapses the selection. | 4,5 | OPEN | G | A multi-selection loses rows | NSTableView oracle | S-M / low (R1.1) |
| C-72 | UI-5 | View state is lost on a tab switch (the grids excepted). | 1,3 | OPEN | G | The selection is gone after a glance at another tab | `TabContentView.swift:16-27` | M / low-med |
| C-73 | UI-6, DUP-7, DUP-14 | Colours are values, not roles. The audit proves the palette, not how it is used. Tokens stop at primitives and live in 6 homes. | 1,3,6 | OPEN | G | The same label renders in two sizes | `DesignSystem.swift:120-122,179` | M / low |
| C-74 | P5B-12 / N123, N116 | The "Pure unavailable" badge measures 4.474:1 over the teal glow, below 4.5. The audit grid misses the worst points. | 4,6 | OPEN | L | Fails WCAG AA | `HeroBand.swift:113-116` | S / low (R1.1) |
| C-75 | UI-8, DUP-6, DUP-7, fool §3.9 | Presentation is re-derived in views. The signal-path wording appears 4 times with 2 spoken forms. There are 5 rate formatters, which disagree by locale. `accessibilityDifferentiateWithoutColor` has 0 uses, so colour-only states are unchecked. | 3,4,6 | OPEN | G | The footer and the hero disagree | `NowPlayingBar.swift:387-453`; ✓ 0 differentiate-without-colour | S-M / low |
| C-76 | UI-7, DUP-5, P5B-08 | Four transient-message components. The restore toast is neither announced nor pausable. A stale "Already in Queue" toast appears. | 3,5 | OPEN | L | The only undo expires silently for VoiceOver users | `QueueRestoreToast.swift:17-34` | S / low (R1.1) |
| C-77 | UI-9 | The custom chrome forces workarounds, and Liquid Glass is banned while the release notes claim it. | 1,5 | OPEN | G | The release notes promise a look the app doesn't have | `AppShell.swift:27-50`; `v1.0.0-alpha.md:35` | S spike / L |
| C-78 | UI-10, VM-1 (fixtures) | Picture-sheet hooks sit inside 12 production views. | 6,1 | OPEN | G | None in release builds | `LibraryDetailPage.swift:74-79` | M / low |
| C-79 | UI-11/12/13, P5B-05, P5B-09 | Local cleanups: the sort has 3 representations; Dynamic Type is a no-op; O(n) work per frame; a thumbnail that is 1 px short becomes permanent; the dominant-colour pick has edge cases. | 1,3,5,6 | OPEN | L | A blurry tile now and then | `ThumbnailUpgrade.swift:11-13` | S each / low |

### I. Test, build, CI and hygiene

| ID | Merged sources | Finding | Crit | Status | Sev | User impact | Evidence | Effort / risk |
|---|---|---|---|---|---|---|---|---|
| C-80 | BT-1, VM-8, DUP-2, BR-4, p4-d41-impl-break §4, fool §4 #9 | **Partly landed in R1, and the duplication grew.** `AdaptiveSoundTests` now imports the app, but about 61 tests still run on drifted mirrors. There are now **4 engine doubles**: `SheetEngine`, `DeviceTestEngine` and `OnDeckEngineModel` (all conform), plus `MockAudioEngine` (a mirror). The D41 bridge glue is untested. | 6,3 | OPEN (reduced) | S | Green tests, red production | ✓ `Package.swift` test target `AdaptiveSoundTests`; ✓ the 4 doubles | M / low |
| C-81 | BT-2, BT-11, DUP-13, X1 | There are five harness cultures. The golden hash is copied into 2 files. The multichannel "oracle" re-types production constants. | 3,6,4 | OPEN | G | One failure reported per run | `VerifyLibraryStore/main.swift:36-40`; `MultichannelTests.inc:647-687` | S (`--filter` plus continue-on-failure; fool) / migrate opportunistically |
| C-82 | BT-3 | The C++ suite is one 24k-line translation unit with a manual registry. Tests have no per-test cost, tags or timeout. | 1,6 | OPEN | G | None directly | `DSPKernelNullTest.cpp:56-93` | M / low |
| C-83 | BT-4, BT-5, BT-10, BT-12, process §4, fool §5 | **CI is not the gate.** There is no required check and no auto-merge, and main runs get cancelled. CI is one serial 87-minute job. The sanitizers rerun the accuracy sweeps. No Swift TSan, no -O2 run. 25 semgrep rules have no tests. | 6 | OPEN | G | None directly | ✓ `allow_auto_merge: false`; `strict-ci.yml:12-14` | S (the one rule) + M (parallel jobs) / low |
| C-84 | BT-6, BT-8 | Timing tests use wall-clock deadlines and µs budgets. There is no injected `Clock`, and `.timeLimit` is used 0 times. | 1,6 | OPEN | G | None directly; 5+ flakes in a week | `EqDesignerTests.inc:1558-1575` | M / low |
| C-85 | BT-9, every panel's "top missing proofs" | Independent oracles are missing exactly where they are cheap, and several tests pin defects as correct. The panels' harnesses are uncommitted. | 4,6 | OPEN | G | None directly; it is why C-22, C-26, C-39, C-40, C-42, C-45 and C-71 shipped | panel exp folders | M / low |
| C-86 | DSP-12, DUP-15, D64, D66, D80, D81 | Dead and placeholder code, including the leaking `RtSwappableResource`, the dead AU C-ABI and the reference tone. | 1,6 | OPEN | L | None | ✓ `AUAudioUnit.mm:369` | S / low |
| C-87 | DSP-14, DUP-15 | The AU scaffolding is duplicated, and the copies have already diverged: the effects render block doesn't guard against a nil `pull`. | 3 | OPEN | L | A latent crash | `AUAudioUnit.mm:88-108` | S / low |
| C-88 | DSP-16, BR-16, BT-7, the docs-arch drift list | Stale contracts, comments and scripts. | 1,6 | OPEN | L | None | ✓ `Package.swift` test comments | S / low |
| C-99 | fool §3.1 (new) | **FFmpeg is an unnamed attack surface.** Its demuxers run *first* on every FLAC, Ogg and Opus file during the background metadata pass. It is dlopened from user-writable `/opt/homebrew/lib`, and also by bare leaf name. Notarizing would need `disable-library-validation`. The process runs with no sandbox. | 6,5 | OPEN | G | One crafted file in a downloaded album can run code with your rights | ✓ `MetadataExtractor.swift:55-62`; ✓ `FileDecodeSource.cpp:386-399` (`""` prefix) | S / low (delete it after a real-corpus check; FD-3) |
| C-102 | fool §3.4 (new) | **Master Gain resets to unity, the loudest setting, at every launch** (it is a turn-down-only law). This is hearing safety, not just convenience. | 4,6 | OPEN | G | A 20 dB turn-down for sensitive in-ear monitors comes back 20 dB louder after relaunch | ✓ `AudioViewModel.swift:195` (`= MasterGainLaw.unity`, not persisted) | S / low (R1.1): never restore above the stored value |
| C-89 | docs-product known-issues (44), ledger | The logged post-R1 items are **referenced, not re-registered** here. They go to R1.1 triage. | — | OPEN | n/a | e.g. `--:--` after relaunch; the wrong queue restored | `known-issues.md` (`docs/council-recon-product`) | — |

### K. Fixed in R1 (v1.0.0-alpha, PRs #88 and #89, checked at `9df49e3`)

| ID | Merged sources | Finding | Orig. sev | Fixed by (✓) | Follow-ups (→ open row) |
|---|---|---|---|---|---|
| C-90 | D71, DSP-03, D76 (width) | A Pure track whose channel count differed from the device's played silence forever | G | `231a927`: ✓ `PureModePolicy.cpp:132-134` | Reason only logged → C-34; hog split → C-32; format left changed → C-31; depth → C-33 |
| C-91 | D74, D76, DSP-04 | A packed-24 heap overrun, NaN undefined behaviour, +Inf rendered at full scale, a ⌈bits/8⌉ write bound | G | `231a927`: ✓ `NativePcmFormat::fromAsbd` (`HALOutputEngine.mm:705`) | Check that HDMI isn't now declined → FD-5 |
| C-92 | DSP-06 (liveness, teardown), D63 / N100, BT-6 (gate test) | The RenderGate's close() could starve; a teardown use-after-free window; the gate tests could hang | G | `ee8e3dd` `7643826` `e5f9e72` `f9986a6` `8686aea`: ✓ `requestClose` / `awaitQuiet` (`HALOutputEngine.mm:846`); ✓ `parkIfRenderOutlivedStop` | Parked threads; seek still needs the gate → C-36 |
| C-93 | D41, P4 §1, docs-product F1 | Pure played the old next track after an edit; REARM-ORDER; NEXT-NEXT; START-OVERTAKE | G | `cffba63` `da8e5cc` `f8da838`: ✓ `OnDeckGate` (`OnDeckTicket.swift:38`) | A2/A2′ and `ended` across a seek → C-14; glue untested → C-80 |
| C-94 | p3a-d41-cpp-break §3 | A re-arm inside the seam claim could destroy the track being adopted | L | `73ebb44`: ✓ `lastArmed_` | — |
| C-95 | F-P4-1 | A Play Next during a prime played the old pick | L | `27e3176`: ✓ `+Queue.swift:125` | Its append twin → C-17 |
| C-96 | N92, P5B-03, H1, H2, round-3 §6 | The device pin fought the reconnected headphones; the launch device counted as a pick; H1/H2; the OFF copy | G | `cdf8dcb` `b2781c2` `e2d6037`: ✓ `chosenUID` | The choice lasts one session → C-12; C-28 unchanged |
| C-97 | LIB-02, P5A-01/02, N32/33/44, ATK-4/6 | Songs were swept after an incomplete walk, after a walk of another same-named drive, and from unbound roots | S (data loss) | `e362e81` `46ec9ba` `340de12`: ✓ `SweepRefusal`, ✓ `volume_uuid` | **Narrowed, not closed:** rebind → C-54; root-wide refusal → C-55; tombstone → C-56; export/backup → C-101 |
| C-98 | D41 H3e | A Pure arm couldn't happen until the previous track was reaped | L | `cffba63`: `armNext` reaps first | — |

### Refuted or corrected claims

| # | Claim (source) | Verdict | Evidence |
|---|---|---|---|
| R-1 | Disc-folder parsing is duplicated (LIB-13) | REFUTED | The kit calls `AlbumGrouping.discNumber` (`LibraryTrackDisplay+DetailTrack.swift:13`) |
| R-2 | SwiftPM can't `@testable import` the executable (`Package.swift`, BR-4, process §8) | REFUTED | BT-1 E1; ✓ `AdaptiveSoundTests` |
| R-3 | "Mastering SRC would stall live playback" (`+EnhancedResampler.swift:80-82`) | REFUTED | P3: it streams at 100–190× real time per channel |
| R-4 | "A Swift actor means executor hops" (`AudioEngineBridge.swift:32`) | REFUTED | arch E1 |
| R-5 | The dual-stage release is state of the art and shipped (review-sota, Sprint-4 retro) | REFUTED | P2 invariant proof plus a measured τ of 500 ms |
| R-6 | `SRCQualityMeasure` "all tones pass" (B5) | REFUTED | It prints −7.23 dB at 20 kHz and still says PASS |
| R-7 | The seam re-base is about 372 ms + L early (rev-sota M2) | CORRECTED | 0–186 ms + L, and it can be late |
| R-8 | The meter is never reset per track (P2-SOTA) | PARTLY REFUTED | ✓ It resets on every user `playFile`; it does not reset on gapless or seek; the makeup never resets |
| R-9 | After a device change, LFE = 1 and the surrounds = 1.0 (DSP-07) | CORRECTED | The audible module goes to {1,1,0,…} (P2-5) |
| R-10 | D41 and D63 are PROVEN-CORRECT (P3-SOTA) | REFUTED as row verdicts | Only the seam and safety were proven (P4) |
| R-11 | The RenderGate CI failure is a test artefact (BT E2) | REFUTED | P3 H4: 386 of 400 closes starved |
| R-12 | "No caller does stop + start in one turn" (VM-2) | SUPERSEDED | P4 reaches it through interleavings |
| R-13 | "The golden master verifies the bypass" (architecture.md) | WRONG | docs-arch |
| R-14 | "Each known issue is guarded by `withKnownIssue`" | WRONG | 0 uses |
| R-15 | "None of this is urgent for R1.1" (arch §0) | PARTLY REFUTED | The audible defects are urgent |
| R-16 | The limiter breaches above 192 kHz (DUP-16) | DOWNGRADED (latent) | ✓ The graph is fixed at 48 kHz |
| R-17 | "S14 needs only Master Gain + the realizer" (product) | PARTLY REFUTED | ✓ `Realizer.mm:430` neutralises a tilt, so one taste-only neutral design is needed (S-M) |
| R-18 | "FAT/exFAT volumes have no UUID" (R1 known issue) | CORRECTED | macOS synthesises one (ATK-5) |
| R-19 | **"Ogg/Opus decode only through FFmpeg, so FFmpeg-only files fail in Enhanced"** (DSP-01, ARCH-6, DSP Q5) | **REFUTED on macOS 26** | The fool's probe, re-run by me: ✓ `AVAudioFile` opens `.ogg` (Vorbis), `.ogg` and `.opus` (Opus) |
| R-20 | "AVFoundation doesn't read Vorbis album artist / compilation" (`MetadataExtractor.swift:55-56`) | STALE | `MetadataExtractor+AVFoundation.swift:64-80` maps `vorb/ALBUMARTIST`; fool `meta.swift` |

---

## 2. Shared root causes

| Root | What the design does | Findings it explains |
|---|---|---|
| **RC-1. The transport has two owners and no identity** | The engine reports anonymous counts. Epochs filter samples, not commands. The engine has no starting state and **no pause primitive**, so the VM builds pause as stop. On Pure, stop is a device teardown. | C-01, C-14, C-15, C-17, C-18, C-19, C-27, C-28, **C-100**, C-11. FIXED: C-93, C-95 |
| **RC-2. Two engines; Enhanced delegates its audio queue to `AVAudioPlayerNode`** | Enhanced re-derives position, seams, end and seek from completion callbacks. Pure already has the right model. | C-07, C-21–C-26, C-29, C-36, C-37, the COUNT-DOMAIN half of C-14 |
| **RC-3. Isolation and layering are conventions inside a monolith** | GCD, comments, regex rules, `@unchecked`, all in one executable target. | C-02, C-03, C-11, C-13, C-27, C-28, C-59, C-78, C-80, C-83 |
| **RC-4. No command / state / event vocabulary** | Commands are methods, `didSet`s and closures. State flows out through polling, hooks, display flags and counters. | C-05, C-06, C-12, C-13, C-52, C-53, C-58, C-70, C-76; it blocks a *catalogue-based* EP-MCP |
| **RC-5. A path is identity, and user data has one copy** | Item = URL, track = signature, root = path, and absence was read as deletion. The one store file is never exported. | C-04, C-54, C-55, C-56, C-57, C-60, C-67, C-69, **C-101**. FIXED: C-97 |
| **RC-6. The Realizer owns the EQ, but not the rest of what is audible** | The layout bypasses it. Loudness scope is undefined. Placeholder stages run in the real-time path. Channel roles come from positions. **The default is processed.** | C-09, C-38, C-40, C-41, C-43–C-50 |
| **RC-7. Tests test copies and pin today's output; time is ambient** | Mirrors, self-oracles, pinned goldens, wall-clock deadlines. | C-80, C-81, C-82, C-84, C-85; the escape route for C-22, C-26, C-39, C-40, C-42, C-45, C-71 |
| **RC-8. Primitives get extracted, but older sites are never moved onto them** | Correct single owners exist (`CoalescingWriter`, `rateString`, `FixedRowReveal`, …), and call sites bypass them. | C-18, C-30, C-63, C-65, C-66, C-70, C-73, C-75, C-76, C-79, C-87, C-48, C-46 |
| **RC-9. Operating a public release was never designed** (new, from the pre-mortem) | No logger, diagnostics or crash reports; no signing identity, updater or licence; a runtime-loaded C demuxer; no backup; settings that come back *louder*. | C-10, C-99, C-101, C-102, C-103, C-83 |

How the roots relate:
- **RC-1 and RC-2 reinforce each other.** The VM owns pause and the Pure device restart *because* the Enhanced engine cannot express them. There are two count domains because there are two engines.
- **RC-3 is why both went unnoticed.**
- **RC-4 is what EP-MCP collides with first.**
- **RC-6 is what S12–S14 collide with first.**
- **RC-7 is why the panels found audible defects behind green gates.**
- **RC-9 decides whether R1 can safely go public.**

---

## 3. Conflicts resolved

1. **ARCH-1 vs VM-2 vs BR-3 (who owns the transport).** Resolution: ARCH-1's split, **built only as a funded slice** (§4).
   - **Evidence.** P4 traced its defect groups to two mechanisms, and both vanish only when the party that knows what is audible owns the transition and reports identity: SFB's `setNowPlaying(decoder)`, Cog's `didBeginTrack`. R1's `OnDeckGate` already sits inside engine admission.
   - **Now (R1.1).** VM-2's starting/pausing state lands in R1.1 (C-15).
   - **Later.** BR-3's facts→action shape becomes the `Player` reducer, if W2 is funded.
   - **If the SFB spike wins,** SFB owns the player. W2 then shrinks to a queue reducer plus an adapter over SFB's delegate events.

2. **DSP-01 vs BR-2.** These are the same target, described from two sides. The pre-mortem adds a third option: **adopt SFBAudioEngine**. Resolution: **fix the measured defects in place first** (R1.1). Then run a **1-week SFB spike** with explicit criteria (§4.5). Build in-house only if SFB fails them.
   - **What doesn't change either way:**
     - Pure keeps its own HAL engine. SFB is AVAudioEngine-based and has no hog or integer path. So "two engines" persists in every option, and the shared part has to be the **decoders / sources**.
     - The spike must therefore also test SFB decoders as a `DecodeBackend` feeding Pure's `GaplessSource`.

3. **DSP-08 (BS.775) vs the "no naive downmix" rule.** BS.775 meets the rule's intent: it is a standard matrix at the device boundary, and it is replaced in the same slot by S18. Truncation is the most naive option of all. Two preconditions:
   - label-driven channel roles (C-44);
   - a ceiling after the spatial stage (P2-6).

   This goes to the founder as FD-9.

4. **D41 (P3a vs P3b).** Adjudicated by P4: the seam was proven, the arm contract was broken. **FIXED in R1** (C-93, C-94, C-98, C-95). The residue stays OPEN in C-14, C-17 and C-80.

5. **LIB-13.** The disc-parser duplication is refuted (R-1). The year tie is transient → LOCAL. The real residue is the album-folder rule (C-66).

6. **D20 reset semantics (P2 breaker vs SOTA).** Resolved by reading the code (R-8). Both remedies converge on a static per-track or album gain from the analysis.

7. **DSP-02 STRUCTURAL vs arch "keep the C wall".** Keep the wall. Now: a named reason enum and dead-ABI deletion. Typed handles come only when a bridge is next touched (C-34, narrowed per the fool).

8. **"S14 first" (product) vs "W5 + W2 before S14" (arch).** Resolution: **S14-lite needs only a taste-only neutral design**, with compensation realized inside the 31-point contract (the fool's slice). That is S-M.
   - **Caveat:** taste ±12 plus compensation must respect the ±12 dB trust clamp (`Realizer.h:121-124`). Give compensation its own headroom, or cap it.
   - W2 and the full `EQProgram` wait for S14-adaptive and S12 respectively.

9. **EP-MCP placement.**
   - arch: after W2 / W3.
   - My first draft: after W1.
   - The fool: a spike after R1.1, with the catalogue only after proven weekly use.

   **Resolution: the fool's order, with one condition.** The spike (about 8 hand-written tools over the existing `@MainActor` verbs) ships **after R1.1's transport fixes** (C-14 short, C-15). P4 showed that single-client interleavings break today, and an agent is a fast client. When MCP graduates, FR-AGENT-01 ("coverage generated from the command catalogue") makes the catalogue required. Then build it, with `AgentGateway` depending only on a Foundation-only `PlayerAPI`. The spike must also verify that App Intents register in a SwiftPM-built bundle.

10. **Waves (arch) vs feature-funded slices (fool).** Resolution: **slices.** The project's record supports the fool:
    - S10.8 was estimated at 3 SP and became ~45 SP;
    - the R1 fixes went from 3 lanes to 5 and grew by +7.4k lines;
    - W2 un-parks the founder's own "decide later" item.

    The wave *contents* stay as the slice catalogue (§4.3), under a 2-week cap and finish-or-revert.

11. **Over-reach items** where I accept the fool's cheaper path:
    - ARCH-2: the cheap enqueue step plus `Mutex`, not an actor conversion.
    - ARCH-9: `os.Logger` plus `AppNotice` plus diagnostics.
    - ARCH-10: no fitness gate.
    - BT-2: `--filter` plus continue-on-failure.
    - W3: one `PlaybackEngine` target.
    - LIB-01: `LoadSlot` now; `ValueObservation` funded by smart lists.
    - DSP-02: as in item 7.

    Where I **reject** the fool, see §6 (DSP-01 → LOCAL; VM-2's epoch "latent").

---

## 4. Converged plan: feature-funded slices, not waves

### 4.1 Rules (adopted from the pre-mortem)
1. **No standalone structural wave.** A structural slice ships only with the feature that needs it, or when its trigger fires (§4.3).
2. **A 2-week cap per slice, and finish-or-revert at the sprint boundary.** A strangler is never left with two live owners.
3. **Spike before building** wherever an established library might do the job (SFBAudioEngine), per the founder's own rule.
4. **Hardware before audio-path changes.** Buy a USB DAC before W4, SFB adoption or C-100.
5. **CI is the only gate** (C-83): a required `strict-gate` check plus auto-merge; main runs are never cancelled; flaky tests are quarantined the same day; lanes run only a fast local check; and a stress run under load is required for any new timing test.
6. **Evidence is durable.** Commit every breaker's red test as a regression test (or delete it). Push the council's WIP branch.

### 4.2 Sequence
1. **Now, at most 2 weeks, in parallel:**
   - **R1.1-A, "faithful, durable, honest"** (§4.4);
   - **W0-lite:** rule 5; migrate the ~61 mirror tests onto `AdaptiveSoundTests` and delete the mirrors; commit the panel harnesses; add `--filter` and continue-on-failure to `VerifyLibraryStore`;
   - **three spikes:** SFBAudioEngine (1 week); SP-MCP (2–3 days, read-only and transport tools); the USB-DAC HIL pass, with Pure pause / resume.
2. **R1.1-B,** decision-gated M items (at most 2 weeks), then a dogfood week. No R2 until R1.1 has been the daily driver for a week.
3. **R2 in the product's order, each feature carrying its slice:** S14-lite (+ the W5-min slice) → S12 (+ `EQProgram`) → S13 → S11-lite (CUE only if `.cue` files exist, + SFB adoption or W4). EP-MCP graduates when the spike is used weekly (+ catalogue). Smart lists (+ `ValueObservation`).
4. **W2 (one transport owner)** is funded by EP-MCP v2 control of output/Pure, S14-adaptive events, or crossfade. It is **triggered** by any wrong-song or silent-playing bug reported after R1.1's transport fixes.

### 4.3 Slice catalogue (the former waves)

> **A review record, not a to-do list (annotated 2026-10-23).** This catalogue is what the council found and how it proposed to pay for it; it is not maintained as a schedule. The [roadmap reconciliation](../../../product/roadmap-reconciliation-2026-10/README.md) of 2026-10-23 moved or closed several of its rows: C-38 (the static per-track / album gain with its true-peak cap) is scheduled once, in R1.1-B — not again under W5 / S12; C-45's rest and C-47 (the layout owner and the stage concept) go to the Engine sprint with the fold's final home; C-46, C-50, C-12 and C-30 were closed in R1.1-A, though the W5 and R1.1-B rows below still list them. Read the [roadmap](../../../product/roadmap.md) and the [sprint plan](../../../sprints/sprint-plan.md) for what is scheduled; read this table for why.

| Slice | Funded by / trigger | Closes | Effort / risk | Depends on |
|---|---|---|---|---|
| **W0-lite** | Now: every later slice needs it | C-80, C-83 (rule), C-85 (commit harnesses), C-81 (idiom), C-88, C-03 (`import AudioDSP`) | M / low | — |
| **R1.1-A** | Now | §4.4 | about 2 weeks of lanes / low | FD-2, FD-3 |
| **R1.1-B** | Decisions | C-12 (`SettingsStore`), C-43/C-44/C-45 (BS.775 + roles + ceiling; FD-9), C-16 (shuffle permutation), C-61 (one search rule + global ⌘F), C-65 (atomic queue restore), C-69 (loose files), C-49, C-30 (classification), C-70 (queue/playlist container M) | M each / low-med | FD-2, FD-9 |
| **MCP slice** | The SP-MCP spike is used weekly | C-05 (catalogue + dispatcher in a Foundation-only `PlayerAPI`; protocol split), C-13, C-18 (`PlayQueue` by slot id), C-04 (the `ItemID` half), typed `CommandError` | M / low-med | R1.1 transport rows; FD-8 |
| **W5-min → W5** | S14-lite → S12 / S13 | W5-min: C-09 (taste-only neutrality, a compensation layer, a level input). W5: `FilterSpec`, C-38 (static per-track/album gain + true-peak cap), C-45 (Realizer layout intent), C-46, C-47, C-50 | S-M → M-L / med (deliberate golden re-baseline) | — |
| **W2** | MCP v2 / S14-adaptive / crossfade, or a post-R1.1 transport bug | C-01, C-06, C-14 (full), C-15 (full), C-19, C-27 (cheap step first), C-28, C-02 (engine), C-11; library lane C-58, C-59 | L / high (time-boxed per event family) | W0-lite, MCP slice |
| **SFB adoption or W4** | S11 breadth / crossfade / A-B loop, **after the SFB spike** | C-07, C-21–C-26 (structurally), C-36, C-37, C-48, C-04 (bounded / region sources), C-08 | L / high (P3 seam replicas as contract tests; by ear) | the spike, the DAC, FD-4 |
| **W3-lite** | Whichever first touches the bridge (W2 or SFB) | C-03 (one `PlaybackEngine` library target with `internal` AVFAudio / HAL), C-78 | M / med | W2 or SFB |
| **Durable library** | Before any new scan or watch feature; before public users | C-56 (tombstone), C-57, C-60 (incremental, against the FD-10 target), C-62, C-63, C-64, C-66, C-67 | L / med | R1.1-A library rows; FD-10 |
| **WU** | Smart lists / undo / R2 UI surfaces | C-05 UI half (`FocusedValue`, `UndoManager`), C-70, C-72, C-73, C-75, C-77, C-79 | L / med | MCP slice (catalogue) or `didSet`-intents |

### 4.4 R1.1-A: "faithful, durable, honest" (each S unless marked)

**Faithful default and safety (first):**
- **#1, C-41:** default Intensity 0, leveling and EQ off (FD-2). This takes C-38, C-39 and C-40 off the default path.
- **#2, C-25:** seek-to-end becomes "end now"; a transactional seek with a finiteness check.
- **#3, C-102:** persist Master Gain, and never restore it louder than stored.
- **#4, C-26:** `.mastering` SRC, plus a passband/stopband gate.

**Playback:**
- C-21: schedule track B ahead.
- C-24: a width guard.
- C-22: a persistent converter (S-M).
- C-15: synchronous stop numbering; the bridge drops stale commands; a starting/pausing state (S-M).
- C-14 (short): an epoch-scoped seam count plus the audible on-deck sequence (S-M).
- C-17: append during prime; recompute the next track after edits; `playNextNow` by slot.
- C-28, C-19, C-20.

**Audible DSP:**
- C-39 (slow attack on the slow branch).
- C-40 (correlation-compensated blend).
- C-42 (bs2b-faithful crossfeed, with DataSource-based headphone detection).
- C-46: per-track "Integrated".
- C-50: scoped flush-to-zero.

**Pure honesty:**
- C-33, C-34 (a named reason enum, shown in the UI), C-37, C-29, C-32.

**Observability and data:**
- C-10: `os.Logger` behind `logUX`, MetricKit crash payloads into the data folder, Help ▸ "Copy Diagnostics", an issue template.
- C-101: M3U8 playlist export, and "Back up library data…" via `VACUUM INTO` / GRDB backup.

**FFmpeg and formats:**
- C-99 / C-08: run the real-corpus check (embedded `PICTURE`, multichannel and 32-bit FLAC, ID3-prefixed FLAC, Opus). If it passes, **delete FFmpeg**: the decode fallback, `MetadataBridge`, the dlopen and the version guard (FD-3).
- Scan `.opus` and `.oga`, with a format table test.
- C-35 becomes moot.

**Library:**
- C-54: "Use this drive", plus the known-issues warning.
- C-55: scoped evidence, and "paused" shown in the UI (S-M).
- C-68.
- C-57 slices: optimistic metadata apply; inode refresh; move source = "the URL no longer exists".
- C-58: the P5B-01 two-line fix.
- C-61 slice: tokenizer categories plus NFC (S-M).

**User interface:**
- C-53 (quantised elapsed time; a `liveReadout` modifier).
- C-52 (timers gated on `isPlaying` or visibility; an energy reading in the release checklist).
- C-51, C-71, C-74, C-76, and C-79 (thumbnail).

**Hygiene:**
- C-86, C-87, C-88.

**Logged items:**
- Triage the 44 logged known issues (C-89).

**Release (if FD-7 = public):**
- C-103: LICENSE and notices; Developer ID and notarization (simpler without FFmpeg); a clean-Mac first-run test; a decision on the security-scope calls.

### 4.5 SFBAudioEngine spike: pass criteria (1 week, outside the main checkout)

**Scope:** SFB @ 9ed712d. MIT; SwiftPM; `modifyProcessingGraph:` (`SFBAudioPlayer.h:302`) inserts nodes only between `sourceNode` and `mainMixerNode`; the delegate exposes `decodingStarted` (`:345`) and `nowPlayingChanged` (`:381`).

1. **Quality.** Our two AUs run inside SFB's graph, bit-exact against today's kernel at 48 kHz.
   - SFB converts only to a standard deinterleaved format at the file's rate (`AudioPlayer.mm:394`). Sample-rate conversion therefore happens in the engine's mixer path.
   - Measure that SRC against C-26's gate (≤ 0.1 dB to 20 kHz, ≤ −100 dB stopband).
   - Our DSP would then run at the file's rate, which makes C-48's rate domain live.
2. **Gapless and seek.** 44.1 → 44.1 and 48 → 48 joins are sample-continuous on the P3 replica oracle. Seek-to-end ends cleanly. SFB's rule for a rate or layout change is a "non-gapless join" (`AudioPlayer.mm:1468`), which is the same as our FD-7 default.
3. **Device change, latency and the main thread.** No main-thread engine calls (the PR #86 rule). Measure the latency of a device change and of a seek.
4. **Supply chain.**
   - SFB brings about 21 packages, including about 10 binary xcframeworks (FLAC, Ogg, Opus, Vorbis, WavPack, MAC, mpg123, lame, sndfile, TTA). Today the app has 1 dependency, GRDB.
   - These are in-process C parsers too (bundled and signed rather than dlopened), so C-99's risk class remains in a different form.
   - Licences: mpg123 and libsndfile are LGPL. That is OK under the founder's rule, but must be listed.
5. **Pure.** Does an SFB decoder fit as a `DecodeBackend` for Pure's `GaplessSource`? If yes, there is one decode layer. If no, Pure keeps `ExtAudioFile`.

**Outcome:**
- If it passes → adopt for Enhanced at S11 time, and W4 is not built.
- If it fails → keep the R1.1 in-place fixes, and build W4 only when S11 breadth or crossfade is scheduled.

### 4.6 What each roadmap block needs

| Roadmap | Needs |
|---|---|
| **S11** (formats, CUE) | CUE only if `.cue` files exist: `ItemID` (MCP slice) + region / bounded sources (SFB `SFBAudioRegionDecoder`, or W4) + a `cue_index` store key. Format breadth comes from SFB or W4; Opus is already native |
| **S12** (PEQ / AutoEq) | W5: `FilterSpec`, per-band g glide, SVF shelves |
| **S13** (device correction) | W5: a correction layer plus taste on one graph |
| **S14** (loudness compensation) | **W5-min only** for S14-lite. S14-adaptive needs the Enhanced system volume observed (DeviceIO) plus W2 events |
| **S15–S18** | W2 events; the W5 stage concept; per-track analysis at the seam (SFB or W4); S18 replaces the BS.775 slot |
| **EP-MCP** | Spike after the R1.1 transport fixes. Graduates to the catalogue + `PlayerAPI` + `AgentGateway` (MCP slice). v2 control of output / Pure after W2 |

### 4.7 Pre-mortem of *this* plan

| Failure | Early warning | Prevention |
|---|---|---|
| R1.1 sprawls | Anything over S in R1.1-A | Move it to R1.1-B or into its slice |
| W2 is never funded, and the RC-1 class persists | A wrong-song or silent-playing bug after R1.1 | That bug is W2's trigger, not another patch |
| The SFB spike is skipped "because we already know the design" | W4 work starts without a spike report | Rule 3 |
| CI rule 5 erodes | A merge by hand mid-CI; a test un-quarantined without a fix | One button (auto-merge); the quarantine ledger is checked at plan review |

---

## 5. Founder decisions: 10

Recommendation first. Each line also says what the decision blocks.

| # | Question (plain words) | Options, recommended first | Blocks |
|---|---|---|---|
| **FD-1** | What comes next? | **A:** two weeks of "faithful, durable, honest" fixes (R1.1) plus three short spikes; then R2 features in order (S14 → S12 → S13 → S11-lite), each carrying only the restructuring it needs. B: do the restructuring waves first. C: start S11 as planned | Everything |
| **FD-2** | What should a fresh launch sound like, and what should it remember? | **A:** faithful: Intensity 0, leveling off, EQ off. Remember Pure, Master Gain (never louder than you left it), crossfeed, shuffle/repeat and the chosen device. Hide Intensity until it does something real. Leveling becomes a named setting (album/track gain from the existing analysis, off by default). B: remember everything, but keep today's processed default. C: as today | R1.1-A #1/#3, R1.1-B |
| **FD-3** | FFmpeg? | **A:** delete it once a check on your real files passes. macOS 26 already plays and tags Ogg/Opus/FLAC, and FFmpeg is the biggest security risk. B: keep it as an opt-in. C: keep it as is | R1.1-A, notarization |
| **FD-4** | How should the Enhanced (default) engine be fixed? | **A:** fix the measured bugs in place now; spike SFBAudioEngine for 1 week; adopt it if it passes §4.5; build our own only if it fails. B: build our own (W4) without a spike | SFB / W4, S11 |
| **FD-5** | Buy a USB DAC now? | **A:** yes (~$100–200), before any change to Pure or the audio path. Verify bit-perfect output, pause/resume (C-100) and that HDMI still works. B: keep Pure unverified | C-100, C-31, public bit-perfect claim |
| **FD-6** | Merge policy | **A:** CI is the only gate: required check + auto-merge (you click "Enable auto-merge"), main runs never cancelled, flaky tests quarantined the same day. B: as today | W0-lite |
| **FD-7** | Is R1 public? | **A:** yes: GPL-3.0 licence, Developer ID + notarization, diagnostics, a clean-Mac first run. B: keep a quiet private alpha | C-103, release |
| **FD-8** | EP-MCP | **A:** a small read-only + transport spike after the R1.1 transport fixes; build the full command catalogue only when you use it weekly. Agents may lower volume freely; raises are capped and confirmed. B: wait for the transport rework | MCP slice |
| **FD-9** | 5.1/7.1 music on headphones or stereo speakers until S18 | **A:** a standard ITU BS.775 fold (no LFE), after fixing the channel order, with a safety limiter after it. B: Apple's environment node. C: keep dropping the centre and surrounds, as a known issue | R1.1-B, S18 |
| **FD-10** | How big a library, and how safe? | **A:** target 100k songs with a performance gate. Missing files become "missing", not deleted (a grace period). Playlist export + a "Back up library data" item now. B: 20k songs and today's rules | Durable library slice, C-60 |

**Decided by the plan unless you object.** Each item follows the recommendation in the source finding.
- **Transport and playback:**
  - W2 is built only when funded or triggered (§4.2).
  - Shuffle becomes a permutation with history.
  - A track join that changes format (width or rate) is an honest short gap; bit depth no longer breaks Pure gapless.
  - SRC: Mastering now; the in-house persistent converter only if SFB fails.
  - DSP rate domain: 44.1–192 kHz.
- **Sound:**
  - Crossfeed uses the bs2b ladder (Jmeier / Cmoy / bs2b) and can be enabled on any output.
  - EQ below 44.1 kHz uses a reduced band set.
  - Pure honesty labels (the reason shown; "not bit-perfect" when the device's depth is lower).
- **Library and search:**
  - One search rule (ranked FTS prefix, Unicode-correct), global ⌘F, Love + smart lists in R1.1-B.
  - Finder-order collation.
  - Loose-file Open… and drop.
  - Remove the playlist-folder data-access layer.
  - "Use this drive".
  - Count your `.cue` files before S11; if there are about zero, CUE becomes "Could".
- **User interface:**
  - Single click selects, double-click / Return plays, everywhere; the same verbs on every song list.
  - Undo through Edit ▸ Undo.
  - A toolbar spike before any chrome work, and correct the Liquid Glass claim now.
- **Tests and dead code:**
  - Retire the mirrors; `VerifyLibraryStore` gets `--filter` and continue-on-failure.
  - `swift-clocks` as a test-only dependency.
  - Delete the dead C++ and placeholders.
  - No new lint fitness gate.
  - Navigation state moves out of the audio view model.
- **Process:**
  - At most 6 concurrent agents.
  - No added ceremonies (rotating break-it, pinned "Now" issue) until rule 5 has held for a month.
  - Docs-only roadmap questions go to the Stage 6 docs PR.
  - Agent permission allow-lists stay *your* call, in your own settings.

---

## 6. Response to the pre-mortem (`stage5-fool.md`)

| # | The fool's point | Verdict | Evidence / what changed here |
|---|---|---|---|
| 1 | Re-baseline at `9df49e3`; W0 partly landed; 3 fakes | **ACCEPT (already done)** | Every row was checked at `9df49e3` (✓ marks); 9 FIXED-R1 rows. There are **4** engine doubles, not 3 (✓ `SheetEngine`, `DeviceTestEngine`, `OnDeckEngineModel`, `MockAudioEngine`); C-80 is now M |
| 2 | W0–W5 is a feature-blocking rewrite; use feature-funded slices with a cap and finish-or-revert | **ACCEPT** | §4 rewritten: no standalone waves; 2-week cap; finish-or-revert; W2 funded or triggered. The wave contents are kept as the slice catalogue, so the structural findings still have a home |
| 3 | SFBAudioEngine adoption was never evaluated; spike first | **ACCEPT, with additions** | §4.5: pass criteria. Added: SFB brings ~21 packages / ~10 binary C decoders (supply chain; still in-process parsers); it has no Pure path, so two engines persist and the spike must test SFB decoders as Pure's `DecodeBackend`; SRC moves into the mixer, which makes C-48 live |
| 4 | `AVAudioFile` opens Ogg/Opus; FFmpeg is redundant and an attack surface; delete it | **ACCEPT** (after a corpus check) | Re-ran the probe ✓. R-19 / R-20; C-08 → LOCAL; new C-99 (✓ `MetadataExtractor.swift:55-62`, ✓ `FileDecodeSource.cpp:386-399` with the bare-name `""` prefix); FD-3 |
| 5a | The default path is processed (Intensity 0.20) | **ACCEPT** | C-41 reframed; R1.1-A #1 (✓ `AudioViewModel.swift:142`) |
| 5b | Seek-to-end silence on non-48 kHz tracks | **ACCEPT, already in the register; raised to "R1.1 blocker"** | C-25; the scrubber path ✓ `NowPlayingBar.swift:332-333` → ✓ `+EnhancedResampler.swift:193-202`; R1.1-A #2 |
| 5c | Master Gain resets to full at launch (hearing safety) | **ACCEPT** | New C-102 (✓ `AudioViewModel.swift:195`); R1.1-A #3 |
| 5d | No `os.Logger` | **ACCEPT** | C-10 widened (MetricKit, Copy Diagnostics, issue template); moved into R1.1-A |
| 6a | ARCH-6 → LOCAL | **ACCEPT** | C-08 → L |
| 6b | DSP-01 → LOCAL | **REJECT** | The two-engine root is evidenced by measured defects unrelated to format coverage: the C-21 gap, the C-22 click, the C-23 early re-base, the C-24 width seam, the C-25 seek hang (P3 replicas), and COUNT-DOMAIN (P4). It stays STRUCTURAL. **The remedy changed** (fix in place + SFB spike), the rating did not |
| 6c | ARCH-7: S14 needs only a second layer exempt from neutrality | **ACCEPT, with a caveat** | §3 item 8: W5-min = taste-only neutrality (S-M); the full `EQProgram` waits for S12. Caveat: taste ±12 plus compensation must respect the ±12 dB clamp (`Realizer.h:121-124`) |
| 6d | ARCH-4: play counts already key on `tracks.id`; only CUE is blocked | **ACCEPT** | ✓ `+PlayTracking.swift:66-71` → `incrementPlayCount(id:)`; C-04 → G (S only if CUE is kept) |
| 6e | VM-10 → LOCAL | **ACCEPT** | The `engineQueue` FIFO orders the enumerations; the remaining device-refresh ordering is noted as unproven/LOCAL inside C-02 |
| 6f | BR-1: the cheap "post a command" fix suffices | **ACCEPT** | C-27 remedy = the enqueue-a-command step (M); the actor conversion happens only inside a funded W2 |
| 6g | LIB-02 is narrowed, not closed | **ACCEPT (already modelled)** | C-97 says "narrowed"; C-54 / C-55 / C-56 are OPEN; C-56 is scheduled before any new scan or watch feature |
| 6h | VM-2: the stop epoch is latent | **REJECT** | P4 E1 reproduced STOP-THEN-PLAY and PAUSE-THEN-PLAY on the **real VM sources** (engine silent, app shows Playing) through the two-call stop numbered inside its Task (✓ `+Lifecycle.swift:160-161,174-175`). No same-turn caller is needed. C-15 stays SIGNIFICANT |
| 7a | Pure pause = a full device teardown | **ACCEPT** | New C-100 (✓ `stopAudio` → `tearDownPure`; ✓ `HALOutputEngine.mm:350-351`). It is the clearest RC-1 evidence: the engine has no pause primitive. Needs FD-5 |
| 7b | No playlist export or backup | **ACCEPT** | New C-101; R1.1-A |
| 7c | Observability (`os.Logger`, MetricKit, diagnostics) | **ACCEPT** | C-10; new root RC-9 |
| 7d | Distribution: ad-hoc identity, no updater, no LICENSE, 11 no-op scope calls | **ACCEPT** | New C-103 (✓ 11 calls; ✓ `allow_auto_merge: false`); FD-7. The TCC re-prompt is unverified |
| 7e | No library-size target or performance gate | **ACCEPT** | C-60 widened; FD-10 |
| 7f | Energy: two 20 Hz timers | **ACCEPT (already in C-52; now R1.1)** | Timers gated in R1.1-A; an energy reading added to the release checklist |
| 7g | `accessibilityDifferentiateWithoutColor` has 0 uses | **ACCEPT** (LOCAL note) | ✓ 0 uses; in C-75 |
| 8 | CI is the only gate: required check, auto-merge, uncancelled main, quarantine, fast local check | **ACCEPT** | §4.1 rule 5; C-83; FD-6. Also accepted: drop the rotating break-it, echo-back and "Now" issue for a month; cap agents at 6; commit the breakers' tests; push the WIP branch |
| 9 | ≤10 founder decisions | **ACCEPT** | §5: 10 decisions. Everything else is "decided by the plan unless you object" |
| §2 | Over-reach: W1 catalogue, W3 split, ARCH-2 actor, ARCH-10 fitness, BT-2 retirement, LIB-01, DSP-02, ARCH-9 | **ACCEPT 7, PARTLY 1** | Accepted: cheaper paths, §3 item 11. PARTLY on the W1 catalogue: the spike comes first (accepted), but founder requirement FR-AGENT-01 asks for coverage generated from a catalogue, so the catalogue is required once MCP graduates, not optional |
| §2 | EP-MCP needs no transport work because G-RACE is engine-internal | **PARTLY** | Agreed that multi-client concurrency isn't the mechanism. But P4's single-client interleavings (C-14, C-15) do break today, and an agent is a fast client. So the spike comes **after** the R1.1 transport fixes, not before |
| §6 | "Faithful and durable first, then features carrying their own slice" | **ACCEPT** | This is the §4.2 sequence |
