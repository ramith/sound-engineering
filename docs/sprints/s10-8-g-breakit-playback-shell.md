> **Status (2026-10-13):** every R1 blocker below was fixed in PR #85 (Sprint G); the post-R1 items are open. The red tests and harness live on the reference branch named below (pushed to origin); the worktree paths are historical.

# Sprint G break-it, breaker B: playback, transport, EQ, Settings, shell, lifecycle

Base: bfd0d19 (origin/main). Branch: breakit/s10-8-g-playback-shell (worktree agent-a1f9195e6f4bd466a), not pushed.
Red evidence commits: 3013962 (VM harness + engine probe), 562e885 (Master Gain launch scenario). No Sources/ or docs/ change.
Never launched the app, never played audio, never touched the real library or the app defaults.

## How the evidence was produced

- Tests/BreakItG/vmharness/run.sh (run from the repo root after swift build): copies the REAL AudioViewModel
  sources verbatim (AudioViewModel.swift and its +Transport, +Playback, +Playlist, +Queue, +AutoAdvance,
  +Lifecycle, +SpectrumTimer, +Devices, the protocol and models), compiles them with HarnessStubs.swift (a
  recording fake engine named AudioEngineBridge, an empty LibraryModel, no-op store extensions) and runs 11
  scenarios. Today: 10 BROKEN, 1 HOLDS, exit 1. All output goes to .build/breakit-vm inside the worktree.
- Tests/BreakItG/engine-probe/StaleSegmentProbe.swift: AVFoundation OFFLINE manual rendering (no device),
  replaying the exact AVAudioPlayerNode / AVAudioEngine call order of pause, paused scrub, next start. Exit 1.
- Everything else: code reading with file:line, plus live repro steps for the coordinator.
- Stray compiler outputs at 19:07 in the main checkout: not mine. My worktree was checked out at 19:22 and my
  first compile ran at 19:25; every build, swiftc and harness compile ran with the worktree as cwd and wrote
  only under its .build/ (the worktree has no stray .d/.dia/.swiftdeps files).

## Counts

- R1 blocker: 8
- post-R1: 11

## R1 blockers

### B1. A scrub while paused is lost, and plays the OLD song ahead of the next one
- Where: AudioViewModel+Playback.swift:125 seek() moves playbackPosition but not pausedResumePosition, and
  always calls engine.seek. AudioEngineBridge+PureMode.swift:169 seek has no is-playing guard, so on a paused
  (stopped) engine it runs seekEnhancedBestEffort (:303), which stops the player, schedules the rest of the
  file and calls player.play() (:347) on a stopped AVAudioEngine (a no-op: the segment stays queued).
  AudioEngineBridge+Playback.swift:162 playFile only stops the player if isPlaying, so the next start
  appends its file BEHIND that stale segment.
- Scenario 1: pause at 1:30, drag the footer scrubber to 0:30, press Play: the footer jumps back to 1:30 and
  playback resumes at 1:30 (after a blip at 0:30). Harness G-SEEK-1: engine seeks [30, 90].
- Scenario 2 (worse): pause, scrub, then double-click another song (or Next then Play): the rest of the OLD
  song plays first, then the new one, while the footer and hero name the new song and its time runs from 0.
  Probe StaleSegmentProbe: the first rendered block after starting B is track A. Control Center scrubbing
  while paused does the same. In Pure the stale segment sits on the idle Enhanced player and surfaces at the
  next Enhanced start.
- Live repro (audio on a silent device): Now Playing, play any song, Space to pause at about 1:30, drag the
  scrubber to about 0:30, double-click another queue row. Expected: the new song from 0:00. Actual by code:
  the old song from 0:30 to its end, then the new song; [UX] logs an engine seek path=Enhanced while paused.
- Fix area: while paused, a seek only moves the resume point (VM: set pausedResumePosition, no engine call);
  engine seek is a no-op without play intent; playFile always stops / resets the player before scheduling.

### B2. A scrub after the queue ends plays audio behind a stopped UI
- Where: AudioViewModel+SpectrumTimer.swift:112-118 (end of queue sets isPlaying=false and position 0 but
  never stops the engine or clears duration); the footer scrubber stays live while duration is above 0
  (NowPlayingBar.swift FooterScrubber); the engine seek path as in B1, but on a RUNNING engine.
- Scenario: the last song ends; the footer shows Play and 0:00 with the song still loaded; click the
  scrubber: the engine seeks and plays (it was never stopped), the VM still says stopped, every tick snaps
  the scrubber back to 0:00, and Space restarts the song from the top instead of pausing.
- Evidence: harness G-SEEK-2 (engine.seek(60) sent with isPlaying=false; scrubber back to 0.00 s; duration
  still 200 s) + code reading of the engine (no stopAudio at a natural end).
- Live repro: queue one short song, play it to the end, click the middle of the scrubber. Expected: nothing,
  or playback that the footer shows. Actual by code: audio from that point, footer at Play and 0:00.
- Fix area: end of queue performs a real stop (stopAudio, duration 0), or a seek while stopped becomes
  startPlayback(resumeFrom:).

### B3. Enhanced: the output disappearing does not pause; music continues on the fallback device
- Where: the device-alive listener is registered only in startPure (AudioEngineBridge+PureMode.swift:149);
  on Enhanced, AVAudioEngineConfigurationChange re-establishes on the new system default
  (AudioEngineBridge+ConfigChange.swift reestablishEnhancedAfterConfigChange; the play intent is still true);
  the PIN re-assert simply fails (AudioEngineBridge+Devices.swift:164-170) and refreshDevices then selects the
  first device. This contradicts the founder decision in 94b263c (on disconnect: PAUSE instead of
  auto-fallback) and the VM copy Output device disconnected (AudioViewModel+SpectrumTimer.swift:70-80),
  which is never reached on Enhanced, the default mode.
- Scenario: listening on Bluetooth headphones or a USB DAC in Enhanced; the device drops; playback carries
  on out of the Mac speakers.
- Live repro (mute the Mac first; the defect is that audio resumes on the fallback): in Audio MIDI Setup
  create an Aggregate Device over a silent device, pick it in the app pill, play, delete the aggregate.
  Expected: pause and the disconnected banner. Actual by code: [UX] config-change fired ... intent=true, then
  Enhanced re-established after configuration change; playback continues on the default output.
- Fix area: watch the selected device alive-state on Enhanced too (or detect in handleDeviceSetChange that
  the selected device is gone) and run pauseForDeviceLoss.

### B4. Output changed outside the app: audio moves, the app keeps showing (and EQ-ing) the old one
- Where: no kAudioHardwarePropertyDefaultOutputDevice listener (removed in 94b263c), while the Enhanced
  AVAudioEngine follows the system default (AUAudioUnit.mm:343 comment); handleDeviceSetChange acts only on
  device-list changes and only with play intent (AudioEngineBridge+Devices.swift:157-161); selectedDevice
  (and with it onOutputIdentityChanged, the per-output EQ slot, publishOutputTransport and the crossfeed
  headphone check) changes only in selectDevice / refreshDevices (AudioViewModel+Devices.swift).
- Scenarios: (a) while playing, choose another output in macOS Control Center › Sound; (b) paused with Keep
  playback on this device ON, headphones connect and macOS makes them the default, then press Play. Audio
  plays on the new device while the chrome pill and Settings show the old one; the old output EQ pin keeps
  playing (switching output recalls its EQ fails); the limiter ceiling stays on the old transport (built-in
  -0.1 dBTP applied to Bluetooth instead of -1 dBTP, decision 29).
- Live repro: two silent outputs A and B. Pin an EQ to A (Use on A). Play on A, then pick B in Control
  Center › Sound. Expected: the app re-asserts A (app-authoritative), or the pill, the EQ toast and the EQ
  follow B. Actual by code: [UX] config-change fired ... default=B selected=A, no output identity line, the
  pill still reads A.
- Fix area: listen to the default-output property and route it through the PIN / FOLLOW rule, updating
  selectedDevice either way.

### B5. Pure Mode: choosing another output while Pure plays leaves the sound on the old device
- Where: selectDevice only sets the system default and currentDeviceID (AudioEngineBridge+Devices.swift:86-95);
  the config-change handler returns early in Pure (AudioEngineBridge+ConfigChange.swift:29); nothing
  restarts the HAL engine, and same-rate gapless seams keep it on the old device until a manual start.
- Scenario: Settings › Pure on, play, pick another device in the pill: the pill, the EQ toast and the
  Settings card switch; the audio stays on the old device for the rest of the album.
- Live repro: Pure on, play on silent device A (a float device runs RateMatchedFloat Pure), pick B in the
  pill. Expected: playback moves to B. Actual by code: [UX] engine selectDevice: id=B result=ok and no new
  Pure Started line; A stays in use (Audio MIDI Setup).
- Fix area: on a device change during Pure, restart Pure on the new device at the current position (or fall
  back to Enhanced there).

### B6. Repeat (and shuffle) changed while a song plays do not apply to that song
- Where: AudioViewModel+Playlist.swift:126-136 toggleShuffle / cycleRepeatMode only flip the flag; the
  on-deck armed at start stays armed.
- Evidence: harness G-RPT-1 (Repeat One turned on mid-song: the on-deck stays track1, the next song plays),
  G-RPT-2 (Repeat All turned on during the last song: the queue stops), G-RPT-3 (Repeat turned off: the song
  plays once more). Shuffle turned on mid-song likewise plays the linear next once.
- Live repro: play track 1 of an album, click Repeat until it shows One, scrub near the end. Expected:
  track 1 again. Actual: track 2.
- Fix area: after a shuffle / repeat change while playing, re-arm the on-deck from computeNextIndex (the
  armOnDeck primitive in +Queue).

### B7. Queue edits while paused: the next song resumes mid-song, or the paused place is lost
- Where: the resume point is keyed to the INDEX (AudioViewModel.swift:275-276 didSet), not to the slot.
  removeTrack (AudioViewModel+Playlist.swift:76-81) keeps the same index when the paused current row is
  removed (so the didSet does not fire); removing a row above it, or a reorder (Playlist.swift:18), changes
  the index and wipes it.
- Evidence: harness G-PAUSE-1 (remove the paused current song, press Play: track2 starts and seeks to 90 s,
  and the footer keeps the removed song duration, 321 s); G-PAUSE-2 and G-PAUSE-3 (remove or reorder above:
  Play restarts from 0, the scrubber jumps to 0:00).
- Live repro: pause at 1:30, right-click the playing row, Remove from Queue, press Space. Expected: the next
  song from 0:00. Actual: it starts at 1:30, with the removed song duration in the footer.
- Fix area: keep the resume point (and duration) with the QueueItem.id they belong to.

### B8. Master Gain: the readout is not what plays, and the launch value is never sent
- Where: masterGain (AudioViewModel.swift:169) reaches the engine only from its didSet; publishPlaybackIntents
  (AudioViewModel+Lifecycle.swift:85) omits it. The readout is gain*20-10 dB (MasterGainSliderView.swift:21);
  the engine applies playerNode.volume = gain, linear (AudioEngineBridge+Playback.swift:288).
- Evidence: harness G-GAIN-1: nothing sent at engine-ready (volume 1.0 = 0 dB) while the inspector reads
  +4.0 dB; the first slider touch drops the level to -3.1 dB at the same 0.7.
- Live repro: launch, play, nudge Master Gain by one key step (the readout goes +4.0 to +3.8 dB). Actual by
  code: an audible drop of about 3 dB.
- Fix area: publish masterGain at engine-ready (and on path changes); make the readout the applied gain
  (20 log10) or map the slider in dB.

## post-R1 (one line each)

1. G-RACE-1: a second Play or Space during a slow start (Pure, device spin-up) starts the song again instead
   of pausing (isPlaying flips only when the start lands). Harness G-RACE-1.
2. Pure leaks a device-alive listener on every manual track start (startPure re-registers without
   unregistering, AudioEngineBridge+PureMode.swift:149 and +PureModeDeviceMonitor.swift:48); a later unplug of
   that device stops playback on whatever device is then in use, with the disconnected banner.
3. Pure on / off does not apply at a same-rate gapless seam, yet Settings says Pure will engage when the next
   track starts (SignalPathStatus, PureModeSettingsSection); it applies at the next manual start.
4. Nothing in Settings or the inspector persists across launches: Pure Mode, Keep playback on this device,
   Master Gain, Intensity, crossfeed (AudioViewModel.swift:88-100; no defaults keys).
5. In Pure the slider drives the device hardware volume; back on Enhanced the player keeps its old volume and
   the hardware keeps the Pure value (double attenuation, readout wrong).
6. Launch-restored song: duration stays 0 until it plays, so the footer reads --:-- and the scrubber is dead
   (AudioViewModel+QueueHydration restoreCursor never sets duration).
7. Unpinning an output overwrites the shared EQ with the pin (EQStore.unpin: shared = slot.state): the other
   outputs silently lose their (possibly edited) EQ with no Bring back offer. Documented (ui-plan 3.3) but
   destructive.
8. Recent shows Nothing Played Yet while the store is not ready or the read failed (QueueHistoryList ignores
   historyState and never reloads when the store becomes ready).
9. A queue with no current song (Add to Queue onto an empty or cleared queue): footer Play, Space and the
   Controls menu are all disabled although play() would start track 1 (AdaptiveSound.swift Controls menu
   disabled on selectedTrackIndex == nil; NowPlayingBar isLoaded).
10. Clicking the PAUSED current queue row restarts it from 0:00 (the PlaylistItemList tap guard checks
    isPlaying), while Return on the same row resumes.
11. Esc on a graph drag restores the Bring back offer and re-announces it as a fresh Switched to message
    (EQBringBackMessage, onChange of the offer).

## Tried to break, held

- Clear Queue during a start (G-RACE-2): the transport ends stopped.
- No @Observable didSet self-assigns in this lane (AudioViewModel, EQViewModel, NowPlayingController, shell).
- Passthrough epoch: every Enhanced stop / seek / reschedule site bumps passthroughGeneration before
  player.stop; the stale segment of B1 is abandoned by epoch (no wrong-song seam roll from it).
- Keyboard: no onKeyPress(.delete) left in this lane (queue and EQ presets use onDeleteCommand); EQ graph
  arrows, Home, End and Esc, Compare hold on Return / Space, Tone slider arrows are bound on live keys.
- EQ kit: slots, pins by UID with the model fallback, rename / delete while selected, the Save snapshot,
  migration and lenient decode, re-read against the EQ3a break-it list: all its findings are closed.
- Shell toasts stack without overlapping; the stale-toast-on-reopen rule holds by construction.
- Not reachable without hardware or a running app (left to the live pass): sleep / wake, real Bluetooth
  switching, sample-rate changes on a DAC, light / dark flip while playing, 880x640 at the largest text.

## Re-run

- swift build, then Tests/BreakItG/vmharness/run.sh from the worktree root: 10 BROKEN, 1 HOLDS, exit 1.
- swiftc Tests/BreakItG/engine-probe/StaleSegmentProbe.swift -o .build/stale-segment-probe, then run it:
  BROKEN, exit 1 (offline render only).
