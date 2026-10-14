# Area review: view models and app state (@Observable)

Reviewer: swift-expert. Repo @ main (a206107), read-only. One experiment in `scratchpad/council/exp-viewmodels/` (no repo build).
Files read in full: all 14 `AudioViewModel*` files, `EQViewModel*` (3), `AdaptiveSound.swift`, `AppDelegate.swift`, `AppDataLocation.swift`,
`MonitoringViewModel`, `NowPlayingController` (the refresh half), `AudioPlaybackEngine.swift`, `EngineSnapshot`, `SignalPathInfo`,
`PlaybackQueueKit/TransportSnapshot`, the footer scrubber, the spectrum views, the Debug fixtures' use of the VM.

Source note: I had no web tool in this session. "Opened" below means the macOS 26 SDK (`Observation.swiftinterface` contains
`Observations`; `NSView.h:610-616` has `displayLink(target:selector:)`), the Swift 6.3.2 toolchain, and my own experiment.
Links to the Point-Free / Apple / Swift-evolution pages are cited from knowledge and marked "(not re-opened)".

## Summary counts

STRUCTURAL 4 (VM-1, VM-2, VM-3, VM-8) · SIGNIFICANT 6 (VM-4, VM-5, VM-6, VM-7, VM-10, VM-11) · LOCAL 3 (VM-9, VM-12, VM-13).

The thread running through all of them: **`AudioViewModel` is the transport state machine, the queue, the device policy, the settings
holder, the readout cache and the persistence driver at once, driven by two timers that diff counters.** The pure decision kits
(`PlaybackQueueKit`, `OutputDeviceKit`, `EQEditKit`) are good. What is missing is the *stateful* layer between the kits and the views.

---

### VM-1 `AudioViewModel` is a god object with no sub-models and no write protection, STRUCTURAL. Criteria: 1, 2
- **Evidence:**
  - 50 stored properties in `AudioViewModel.swift:13-416`, 14 files / 2,075 LOC. The split into extensions exists to dodge the lint budget, not
    for cohesion: `AudioViewModel+Playback.swift:7-10` ("AudioViewModel.swift — which must hold all `@Observable` stored properties, since
    extensions cannot — under the file-length budget"). Extensions cannot hold state, so state is in one file and its rules in 13 others.
  - Concerns present in one type:
    - transport (`isPlaying`, `resumePoint`, `transportEpoch`, `transportStopEpoch`, `duration`);
    - queue (`queue`, `selectedTrackIndex`, `pendingNextIndex`, `queueRestorePoint`, `queueMirrorTask`, `hasUserEditedQueue`, `queueHydrated`, `shuffleEnabled`, `repeatMode`);
    - output (`availableDevices`, `selectedDevice`, `sampleRate`, `bufferFrameSize`, `pinPlaybackToSelectedDevice`, `pureModeEnabled`);
    - mix intents (`intensity`, `crossfeedEnabled/Strength`, `masterGain`, `deviceVolumeAsked`, `lastMasterGainLogged`);
    - readouts (`signalPath`, `loudness`, `spectrumBars`, `peakCaps`, `peakTracker`, `spectrumScratch`, `eqDesignRate`);
    - play-count tracking (`playThroughTracker`, `lastPlayThroughMonoNanos`, `playCountRevision`);
    - lifecycle (`isEngineReady`, `isInitializing`, two `Timer`s);
    - **shell navigation** (`selectedTab`, `AudioViewModel.swift:54`, read by `LibraryBrowseModel.swift:404`);
    - 3 outbound hooks.
  - Encapsulation: 49 of 50 are plain internal `var`; only `eqDesignRate` is `private(set)` (`:416`). Production views happen not to write transport
    state, but nothing enforces it. The Debug fixtures do write it freely (`SheetFixture.swift:155-168`: `audio.isPlaying = true`,
    `audio.queue = …`, `audio.signalPath = path`; `MainThreadStallSelfTest.swift:61,123-169`: `viewModel.pendingNextIndex = 1`). They are the proof that
    any of 68 files could.
  - The `didSet` observers carry cross-cutting behaviour: `selectedTrackIndex.didSet` drops the resume point AND pings Now Playing (`:281-298`);
    `pinPlaybackToSelectedDevice.didSet` calls the engine (`:106`); `intensity.didSet` publishes (`:132`). Setting a property is a hidden command.
- **Root cause:** the first view model grew by accretion; "ownership" was split sideways (library, EQ, browse peers) but never *downwards*. The file-length
  lint turned a cohesion problem into a file-count problem.
- **Why it matters:** every R2 feature (adaptive intensity, per-track gain, stems) lands as another property plus another `didSet`. Nothing is testable
  alone. 24 view files take the whole model from the environment, so Observation's granularity is the only thing keeping them apart (see VM-4).
- **Structural remedy:** decompose by *reason to change*, each a small `@MainActor @Observable` class with `private(set)` state and intent methods,
  composed by a thin façade (or injected separately via `@Environment`):
  1. `TransportController`: the state machine of VM-2; owns `isPlaying`, epochs, resume point, the engine command queue.
  2. `PlayQueue` (value type in `PlaybackQueueKit`) held by the controller: items, current slot id, armed slot id (VM-7).
  3. `PlayheadModel`: the 20 Hz position only (VM-4).
  4. `OutputController`: devices, selection, pin, Pure intent, `OutputDevicePolicy` application, identity-change event.
  5. `PlaybackIntents` / `MixModel`: intensity, crossfeed, master gain, with the published-to-engine side effect in ONE `publishAll()`, not 4 didSets.
  6. `EngineReadouts`: signal path, loudness, spectrum, design rate (the only thing the tick writes).
  7. `ShellNavigation`: `selectedTab`; it does not belong to audio.
  8. `PlayCountTracker` plus the queue persistence (hydration, mirror, cursor), as a collaborator talking to a `PlayCountSink` / `QueueStore` protocol.
  Reference: Apple's own migration guidance is "one `@Observable` per cohesive model" (Migrating from ObservableObject to Observable, not re-opened).
  The Point-Free reducer-per-feature structure expresses the same idea (see VM-2).
- **Effort:** L. **Risk:** med (mostly mechanical once VM-2/VM-8 give tests). **Depends on:** VM-8 first (tests in place), then VM-2.

### VM-2 The transport is an implicit state machine spread over flags, epochs and index vars, STRUCTURAL. Criteria: 1, 2, 4
- **Evidence:**
  - States exist only as combinations of `isPlaying`, `resumePoint != nil` (slot-keyed), `signalPath.interrupted`, `isEngineReady`, `isInitializing`,
    `pendingNextIndex`, and `transportStopEpoch < epoch`. No type names them.
  - **A "starting" state is missing.** `isPlaying` flips true only after `startAudio` + `primeGaplessPipeline` return (`+Playback.swift:60-68`), which "can
    queue behind a slow device start" (`AudioViewModel.swift:66-69`). In that window:
    - `pause()` is `guard isPlaying else { return }` (`+Transport.swift:46`), so a Pause press is silently dropped and the song starts;
    - `togglePlayPause()` sees `isPlaying == false` and calls `play()` again (`:57-63`), which launches a second `startAudio`, restarting the song.
    The same applies to Pause while "pausing": `isPlaying` stays true until `performPause` finishes (`+Lifecycle.swift:169-177`), so a second press pauses again.
  - **Epoch numbering is asymmetric with its own contract.** `nextTransportEpoch()` says "Call it synchronously, before the request's `Task`"
    (`AudioViewModel.swift:300`). `startPlayback` and `seek` do. But `stopPlayback()` → `Task { await performStop() }` and `pause()` →
    `Task { await performPause() }` take their epoch *inside* the Task (`+Lifecycle.swift:171,185`). Epochs therefore number requests in
    execution order, not call order. `stopPlayback(); startPlayback()` in one synchronous turn gives the start epoch N and the later-running stop N+1,
    so the "stop" kills the start the caller issued after it (`transportStopEpoch < epoch` fails, `+Playback.swift:65`). I did not find a current caller
    that does this. The contract is enforced only by the author's memory.
  - **Flags used as suppressors:** `pendingNextIndex = nil` is written in `pause` (`+Transport.swift:50`), `stopPlayback` (`+Lifecycle.swift:157`), device-loss
    (`+SpectrumTimer.swift:87`), `removeTrack`, `clearPlaylist`, `startPlayback` failure, and the reconfigure-advance branch (`+SpectrumTimer.swift:120`, with a 5-line
    comment on why it must be synchronous). Its job in those places is "so the next tick won't advance", not "the on-deck is empty". That is the charter's
    "flag to suppress a race". The `TransportSnapshot.isCurrent(for:)` epoch gate is the real fix; the flag is belt-and-braces that now has its own invariants.
  - **Transitions are scattered:** the same "track changed" bookkeeping (`resetPlayTracking`, zero `playbackPosition`/`duration`, `refreshDuration`, re-arm) is
    spelled out in `startPlayback`, `handleTrackTransition`, the reconfigure branch and `removeTrack`, with slightly different subsets.
  - `play()` clears `resumePoint` *before* `startPlayback`'s guards (`+Transport.swift:28` then `+Playback.swift:19-27`), so "Engine not ready" loses the paused place.
  - `stopAtEndOfQueue` = `stopPlayback()` (async stop) + `isPlaying = false` + `playbackPosition = 0` (`+AutoAdvance.swift:70-74`), a manual double-write.
- **Root cause:** transport behaviour was added as flags per bug (S10.8 G fixed 13+ blockers in this area; each fix added a flag, an epoch or a comment).
  There is no single place where `(state, event) → (state, effects)` is written, so each new event must reconsider every flag.
- **Why it matters:** this is the area G's break-it round kept finding bugs in, and the map's rows N12, N14-N18, N20, N26 have **no direct tests** (mirror only).
  Any R2 feature that touches playback (stems, crossfades, adaptive tracks) multiplies the flag combinations.
- **Structural remedy:** make the machine explicit and pure, and put it in a kit where the existing test infrastructure reaches it.
  ```
  enum TransportState { stopped, starting(epoch), playing(epoch), pausing(epoch), paused(ResumePoint), ended, interrupted(ResumePoint) }
  enum TransportEvent { userPlay, userPause, userStop, userSeek(s), userSkip(next/prev/index),
                        engineStarted(epoch), engineFailed(epoch, Error), snapshot(EngineSnapshot), deviceLost, queueEdited(QueueEdit) }
  enum TransportEffect { startEngine(file, at, epoch), stopEngine(epoch), seekEngine, armNext(file?), countPlay(slot), refreshDuration, publishNowPlaying }
  func reduce(_ s: inout TransportState, _ e: TransportEvent) -> [TransportEffect]
  ```
  The view model becomes an effect runner plus the reducer's host: it assigns epochs itself inside `reduce` (so call order = epoch order by construction),
  and a single serial `EngineCommandQueue` (an `AsyncStream` consumed by one `Task`) executes effects in order. That also fixes VM-10's ordering. The existing
  kit types (`SeekRoute`, `ResumePoint`, `QueueAdvance`, `PlaybackOrder`) become the reducer's helpers rather than loose functions the VM calls in the right order.
  References: Point-Free TCA reducers (https://github.com/pointfreeco/swift-composable-architecture, not re-opened); SFBAudioEngine's `AudioPlayer` state and
  `playbackState` events (already cited in the repo's `TransportSnapshot` header). **Do not adopt TCA the library:** a 600-line reducer in
  `PlaybackQueueKit` with plain `@Observable` hosting gets the benefit (pure, table-testable) without the dependency or macro cost.
- **Effort:** L. **Risk:** high (this is the code the founder most relies on; G's break-it reports become the regression table). **Depends on:** VM-8; informs VM-1, VM-3, VM-7.

### VM-3 Events are recovered by polling counters at 20 Hz, three loops, never idle, STRUCTURAL. Criteria: 1, 2, 3, 5
- **Evidence:**
  - Two main-thread `Timer`s at 20 Hz (`+SpectrumTimer.swift:18,35`) plus a third polling loop in `MonitoringViewModel.swift:48-54`
    (`Task.sleep(50 ms)` loop) → three timing mechanisms for one rate.
  - Gapless seams, end of queue and device loss are *events* the engine knows at the instant they happen, but they reach the VM as a `transitionCount`
    delta, an `ended` flag and `signalPath.interrupted`, compared tick to tick (`+SpectrumTimer.swift:92-130`). The comment at `:96-100` ("advance by exactly ONE
    track per tick even if the count jumped by more than one") is the polling design leaking: an event stream would deliver each seam once.
  - The engine already has its own off-main transport clock (`AudioEngineBridge+TransportClock`) that samples and publishes into `SnapshotChannel`. So there are *two*
    polling layers (engine clock → snapshot → VM tick → diff).
  - Both timers start at engine-ready and run until shutdown (`+Lifecycle.swift:69,130`), including while paused, while stopped and while the window is closed
    in resident menu-bar mode. `readSpectrumBands` and every `withMutation` on the spectrum arrays run 20×/s for nobody. The comment at `AudioViewModel.swift:213-217` says
    gating the visualizer "may one day" happen; it has not.
  - A tick stall is *counted as heard time* (`+PlayTracking.swift:12`, known, audit §4).
  - Seam handling latency: a seam is acted on up to 50 ms late and only while the main thread is responsive. During the 7 s disconnect stall (the known audit) no advance, no
    re-arm of the next-next track happens.
- **Root cause:** the engine/VM boundary is "state snapshot" only (a good fix for the freeze, per the audit), with no event channel, so every discrete fact must be
  rediscovered by diffing.
- **Why it matters:** correctness (events coalesced or dropped by design), power (idle 20 Hz wakeups ×2 in a menu-bar-resident app), and it forces the epoch machinery
  in VM-2 to exist at all.
- **Structural remedy:** keep `snapshot()` for *state* (position, signal path, loudness) but add `events: AsyncStream<EngineEvent>` (`seam(count)`, `ended(epoch)`,
  `deviceLost`, `started(epoch)`, `failed`) published from the engine's own clock/queues; the VM (reducer, VM-2) consumes it on the main actor. Position/spectrum for
  display get a visibility- and `isPlaying`-gated source (below). Idle cost → zero: no timers while stopped and unobserved.
  Display-rate source: SwiftUI `TimelineView(.animation)` or `NSView.displayLink(target:selector:)` (verified present at `NSView.h:610-616` in the macOS 26 SDK), reading a
  non-observable atomic snapshot inside `Canvas`, so the 20 Hz stream never touches Observation (VM-4). Reference: Cog / SFBAudioEngine drive UI from player callbacks and
  delegate events, not poll diffs (not re-opened).
- **Effort:** M-L. **Risk:** med (engine-side change; the `AudioPlaybackEngine` snapshot contract stays). **Depends on:** VM-2 (consumer); partly independent.

### VM-4 `@Observable` invalidation granularity at 20 Hz, SIGNIFICANT. Criteria: 1, 3, 6
Not profiled (I may not run the app); the findings are from reading what the tick writes and what the views read. Confirm with the Instruments SwiftUI template's
cause-and-effect graph (WWDC25 "Optimize SwiftUI performance with Instruments", not re-opened).
- **Evidence:**
  - `FooterScrubber` reads `viewModel.playbackPosition` in its `body` (`NowPlayingBar.swift:222-223`) → body, with `.accessibilityElement(children: .ignore)`, `.accessibilityLabel`,
    `.accessibilityValue(...)`, `.accessibilityAdjustableAction`, re-evaluates 20×/s **while its visible text and its VoiceOver value change once per second**
    (`formatDuration`, `:356-363`). `playbackPosition` is the whole-view dependency. It is the most plausible VM-side contributor to the VoiceOver 45-80 % main-thread load
    the product council saw: re-asserting an accessibility element's modifiers 20×/s makes AppKit re-diff the AX tree. Hypothesis to confirm with a Time Profiler run under VoiceOver.
  - `pollPlayhead` assigns unconditionally while playing: `playbackPosition = transport?.position ?? playbackPosition` (`+SpectrumTimer.swift:144`). When the sample is stale/nil this
    is a same-value write, and Observation has no equality gate (the file's own header at `:153-157` says so for other fields, and guards those, but not this one).
  - `signalPath` is one aggregate struct read by the pill, hero badges, inspector, footer slot (`NowPlayingBar.swift:232,388,446`, `HeroBand.swift:62`, `InspectorColumn.swift:60`).
    Any field change (a device-volume tick on Pure, `deviceVolumeSet`) invalidates all five. It also carries **copied** intent (`intensityLinear`, `crossfeedStrength`,
    `+SpectrumTimer.swift:166-167`), so the intent lives twice, and a slider drag changes `signalPath` too. See VM-3 of the duplication pass.
  - `tickSpectrum` writes 88 elements one by one (`spectrumBars[bar] = …`, `:196-202`). Each subscript set goes through the macro-generated modify accessor, i.e. 88
    `willSet/didSet` registrar round trips (lock + lookup) per tick before the view sees one change. Build a local `[Float]` and assign once.
  - Only 2 of ~25 non-UI stored properties are `@ObservationIgnored` (`transportEpoch`, `transportStopEpoch`). `spectrumScratch` (written through `inout` every tick), `peakTracker`,
    `playThroughTracker`, `lastPlayThroughMonoNanos`, `lastTransitionCount`, both `Timer`s, `queueMirrorTask`, `isInitializing` and `lastMasterGainLogged` are all tracked, so each write
    enters `withMutation` for nobody (cost) and any view that touches one by accident silently becomes a 20 Hz observer (risk). `+SpectrumTimer.swift:208-209` `peakTracker.update` + `peakCaps` map
    allocate two arrays per tick.
  - The spectrum UI is 88 `RoundedRectangle` views with per-bar implicit animation, re-diffed 20×/s (`SpectrumAnalyzerView.swift:55-78`), and a second consumer
    (`EQGraphSilhouette.swift:20`, smoothing 3 passes in the body). This is a rendering matter for the UI reviewer, but the VM's publish model (an `[Float]` in an observable) is what forces it.
  - Good: `@Observable`'s per-property tracking means the 24 environment readers are *not* all invalidated by `playbackPosition`; the discipline of "guard same-value writes"
    is applied to loudness and signal path.
- **Root cause:** the high-rate, display-only values live in the same observable as the low-rate, behavioural state, and the only throttle is a convention (guard the write).
- **Why it matters:** battery/CPU for a player that is meant to sit in the menu bar, and the accessibility-load symptom.
- **Structural remedy:**
  1. Separate `PlayheadModel` (position only, written at most at display rate) from transport state. Expose *derived, quantised* values for text and AX
     (`elapsedWholeSeconds: Int`, written only on change) and draw the fill/thumb from the fast value only (a `Canvas`/`TimelineView` child), so the label and AX modifiers re-evaluate once per second.
  2. Make the spectrum a non-observable `SpectrumSource` (class + `OSAllocatedUnfairLock` or the existing double-buffer) read inside `TimelineView` + `Canvas`; remove
     `spectrumBars/peakCaps/peakTracker/spectrumScratch` from the model entirely.
  3. A `setIfChanged(_:_:)` helper (or `Observations` with `removeDuplicates`) as the *only* way the tick writes.
  4. Mark every non-UI field `@ObservationIgnored`, or better, move them into the non-observable controllers of VM-1 so the macro never sees them.
  5. `signalPath` split into `OutputPathReadout` (path, rate, depth, decision), `DeviceVolumeReadout`, and remove the copied intent (readers combine `MixModel` + readout in the view).
- **Effort:** M. **Risk:** low-med. **Depends on:** none for 1, 3; VM-1 for 4-5; VM-3 for 2.

### VM-5 Persistence is an afterthought: no settings store, key strings everywhere, user intents reset every launch, SIGNIFICANT. Criteria: 1, 3, 6
- **Evidence, the inventory (what is persisted where):**
  | State | Where | Persisted? |
  |---|---|---|
  | EQ slots / My Presets | `UserDefaults` via `EQViewModel+Persistence` (`eqStateV2`, `eqCustomPresetsV1`; versioned, JSON, migration, `.unreadable` side-copy) | yes, well done |
  | Queue items | GRDB `current` playlist mirror (`+QueueMirror`) | yes (250 ms debounce) |
  | Queue cursor, shuffle, repeat | `UserDefaults` `queue.cursor.*` (private enum in `+QueueHydration.swift:24-30`) | **only at clean quit** (`persistQueueCursor()` called from `shutdown`, `+Lifecycle.swift:125`); a crash restores a stale cursor |
  | Songs column config | `@AppStorage("songs.columns.v2")`, the literal in **two** files (`SongsHeader.swift:30`, `SongsListView.swift:30`) | yes |
  | EQ Tone card folded | `@AppStorage(foldedKey)` | yes |
  | **Pure Mode intent** | `AudioViewModel.pureModeEnabled` (`:98`) | **no** |
  | **Master Gain** | `masterGain` (`:185`, doc: "Not kept across launches (a post-R1 item)") | **no** |
  | **Crossfeed on/strength, Intensity** | `:132-157` | **no** |
  | **"Keep playback on this device"** | `pinPlaybackToSelectedDevice` (`:106`), a labelled Settings toggle (`OutputDeviceSettingsSection.swift:34`) | **no**, a Settings switch that silently resets each launch |
  | `selectedTab`, browse sort/section, selected output | memory | no |
  | Library browse state | memory | no (`LibraryBrowseModel`; not reviewed in depth) |
  - Two failure modes exist for the non-persisted intents. (a) The user's choice is forgotten. (b) The *effective* value overwrites the *intent*: `adoptOutput` sets `crossfeedEnabled = false`
    on a non-headphone device (`+Devices.swift:84-87`), destroying the user's setting; coming back to headphones does not restore it. With a store you would persist intent and derive effective.
  - Each model owns its own raw-key code: `QueueCursorKey`, `EQViewModel.Key`, `@AppStorage` literals. Only the *location* is centralised (`AppDataLocation`, semgrep `persist-one-location`),
    which is good; the *schema* is not.
  - The intents' side effects ride on `didSet` (VM-1), so restoring them in `init` would publish to a nil engine; engine-ready re-publish (`publishPlaybackIntents`) already exists, so persistence would be cheap.
- **Root cause:** the settings pattern was never decided; each feature solved persistence locally or not at all. "Post-R1" deferral hid that the first-launch behaviour of a *player* (Pure, gain, crossfeed) is forgotten.
- **Why it matters:** product council already flagged it; hearing-safety angle: persisting Master Gain *turn-down only* is safe, and "Pure on" persists a mode the user chose
  deliberately; **not** persisting them is the surprising behaviour. For R2 (adaptive Intensity, per-output profiles) a settings store is a prerequisite, and per-output keys (as the EQ already has by UID) need a pattern.
- **Structural remedy:** one `SettingsStore` (`@MainActor @Observable`, injected, wraps the `AppDataLocation.defaults`):
  - typed `Codable` `PlaybackSettings { schemaVersion, pureModeIntent, masterGainDb, intensity, crossfeed{enabled,strength}, pinToDevice, shuffle, repeat }`, stored as ONE versioned JSON value
    (the pattern `eqStateV2` already proves), with typed accessors and a single list of keys;
  - the intents' owner (`PlaybackIntents`, VM-1) reads it at init and writes through on change (debounced, off the drag path), driven by `Observations`/`withObservationTracking`
    rather than a `didSet` per property;
  - cursor persisted periodically (the existing DUR-1 note) and on resign-active, not only at quit;
  - `@AppStorage` stays for pure view state, but the keys become `static let` constants in one `UIPrefs` enum.
  Keep the EQ persistence as is (it is the model to copy).
- **Effort:** M. **Risk:** low. **Depends on:** VM-1 (the intents need an owner to restore into).

### VM-6 State sync by hand-wired hooks; the Now Playing projection is "remember to call refresh", SIGNIFICANT. Criteria: 1, 2, 3
- **Evidence:**
  - `onNowPlayingRefresh?()` is called from 6 `didSet`s plus 3 explicit sites (`AudioViewModel.swift:47,236,295,358,367`; `+Playback.swift:101,154`; `+Lifecycle.swift:194`). The VM's own history
    shows each omission was a bug: "S10.4 QA #1" (stale canGoNext after append/shuffle), "QA #2" (`performStop` self-assign suppressed the hook, `+Lifecycle.swift:191-194`).
  - `NowPlayingController` is a *pure projection* of VM state (title, elapsed, state, enablement) kept in sync by the VM calling it, and it reaches back into `audio.queue`, `audio.playbackPosition`,
    `audio.selectedTrackIndex`.
  - `onEngineReady` is a single closure slot. `EQViewModel.init` assigns it (`EQViewModel.swift:98`); any second subscriber would silently replace it. `onOutputIdentityChanged`,
    `library.onError`, `library.onStoreReady`, `np.resolveMetadata`, `np.loadArtwork` complete a composition root that is ~100 lines of closure wiring in `AdaptiveSound.init`
    (`AdaptiveSound.swift:52-104`), with ownership by `weak` references and window `onAppear` assignments to `AppDelegate` (`:129-133`).
  - `AudioViewModel.library` weak back-edge exists only for play counts (`+PlayTracking.swift:60`).
- **Root cause:** one-directional closure hooks are the sole inter-model pattern; "when X changes, tell Y" is enumerated by the producer instead of declared by the consumer.
- **Why it matters:** each new derived consumer (widget, Watch, R2 adaptive UI) means touching the producer's `didSet`s; missed sites fail silently (stale Control Center).
- **Structural remedy:** make the consumer declare its dependency. `NowPlayingController` observes a derived value `NowPlayingState` (selected track id, elapsed anchor, rate, enablement flags) via
  `Observations { … }` (SE-0475, present in the SDK: `Observation.swiftinterface:43`) or `withObservationTracking` with re-arm, and de-duplicates by `Equatable`. The
  producer drops all 9 hook sites. For one-shot facts (engine ready, output changed, track played) use a typed multi-subscriber event channel (`AsyncStream` broadcast, or a small
  `EngineEvents` struct of `AsyncStream`s) instead of single optional closures; play counts become a `PlayCountSink` protocol injected into the tracker. Put the wiring into
  one `AppModel`/composition type (owns the peers, exposes `start()`/`shutdown()` ordering) so `AppDelegate` gets one strong reference instead of 5 weak assignments.
- **Effort:** M. **Risk:** low-med. **Depends on:** VM-1.

### VM-7 The queue cursor is a row index into a mutable array; invariants are guarded by scattered range checks, SIGNIFICANT. Criteria: 1, 3, 4
- **Evidence:**
  - `selectedTrackIndex: Int?` and `pendingNextIndex: Int?` index `queue: [QueueItem]` (`AudioViewModel.swift:228,281,383`); the doc even admits "plain `Int` offsets" (`:226`).
    The queue is mutated by `move`, `remove`, `playNext`, `playTrackNextNow`, `appendToQueue`, `restorePreviousQueue`, `clearPlaylist`, `playNow`, hydration; re-anchoring by `QueueItem.id`
    is hand-written in `movePlaylistItems` (`+Playlist.swift:16-20`) and remove (`:63-93`, with a P2-2 comment about already-shifted indices), and absent where selection is overwritten.
  - Out-of-range defences repeated: `selectedSlotID` (`AudioViewModel.swift:316`), `playingTrackID` (`+PlayingTrack.swift:11`), `countCurrentPlay` (`+PlayTracking.swift:38`), `selectedTrack()` in
    `NowPlayingController`, `index < playlist.count` in 8 places, `armOnDeck` (`+Queue.swift:197`). `clearPlaylist` sets `queue.removeAll()` *then* `selectedTrackIndex = nil` (`+Playlist.swift:90-93`), so an intermediate state
    with a dangling index exists, and `queue.didSet` already fired the hook inside it.
  - The resume point was already fixed once from row-keyed to slot-keyed (S10.8 G); the *selection and armed next* are still row-keyed. Same bug class, unfixed twin.
  - `playlist` (`:244`) is `queue.map(\.file)`, an O(n) allocation per access. `startPlayback` reads it 3-4 times; `NowPlayingBar.swift:20-23`, `HeroBand.swift:29-30` and `MenuBarView.swift:13-16`
    read `.count` and `[i]` separately, i.e. two full copies per body evaluation. A 10 k-track "play library" makes every one a 20 k-element copy with `AudioFile` string retains.
  - Map N18 (move/drop re-indexing) has no test; remove is tested only on a mirror.
- **Root cause:** the engine's index-based on-deck API shaped the VM state ("the engine's index math is unchanged", `:227`), so the VM adopted indices as identity.
- **Structural remedy:** a `PlayQueue` value type in `PlaybackQueueKit`: `items`, `currentID: UUID?`, `armedID: UUID?`; `move/remove/insert/replace` are its mutating methods and preserve both ids by construction
  (removing the current item picks the successor in the type, not in the VM); `currentIndex`/`armedIndex` are *derived*. The kit already owns `QueueInsert`, `QueueRestorePoint`, `PlaybackOrder`,
  `QueueAdvance`: they become methods of this type and the whole of N5-N7/N18/N19 is table-testable in the kit target. Provide `currentItem` so views never touch `playlist`.
- **Effort:** M. **Risk:** med. **Depends on:** VM-8; feeds VM-2.

### VM-8 Logic reachable only through hand-written mirrors; the premise ("an executable target can't be `@testable import`ed") is obsolete, STRUCTURAL. Criteria: 6, 3
- **Evidence:**
  - `AudioViewModelTests` run against `MockAdvanceController` and `AudioPlaybackEngineMirror` (map §5), copies that already drifted: the mirror still dedupes on add while production retired dedupe in S10.2
    (`MockAdvanceController.swift:323` vs `+Queue.swift:17-19`), so VM-Q-11 and VM-Q-13..15 assert behaviour the app no longer has; "playTrack(at:)" mirror omits `resumePoint = nil`; the mirror checks `isPlaying` before the epoch and omits device-loss and play counting.
    The `AudioPlaybackEngine` doc comment still says "tests inject a `MockAudioEngine`" (`AudioPlaybackEngine.swift:6`), which is the *mirror*, not a conformer.
  - The compensating mechanism is DEBUG harness modes compiled into the production binary: 28 files in `Sources/AdaptiveSound/Debug/` (`MainThreadStallSelfTest` calls `viewModel.tickTransport()` and sets
    `isPlaying`/`pendingNextIndex` by hand, `:123-174`; `SheetFixture` writes VM state directly). They couple to production internals only because they live in the same module.
  - **My experiment** (`scratchpad/council/exp-viewmodels/pkg`): a one-target `.executableTarget` with a `@main struct App`, an `@MainActor @Observable` model, and a swift-testing
    test target doing `@testable import App` and testing the model: **`swift test` passes on this toolchain (Swift 6.3.2, macOS 26, tools-version 6.2).**
    SwiftPM has supported testing executable targets since 5.5 (CHANGELOG, not re-opened). The justification in `Package.swift:155-158` and in 3 test-file headers is therefore stale as a general
    statement. **Open risk, not tested:** the real target uses `-import-objc-header` + `-disable-bridging-pch` unsafeFlags and C++-interop dependencies; I did not build the real package, so whether the
    test target accepts the same flags is unconfirmed (the experiment was on the SwiftPM mechanism only). If it does not, the fallback is the standard one: move the model layer into a library target
    (`AdaptivePlayerCore`) and leave `@main` + views in the thin executable.
- **Root cause:** a SwiftPM constraint that was true in 2024 became a durable architecture rule (kits as "extraction targets") and then a permanent mirror layer.
- **Why it matters:** the highest-risk logic (N12, N14-N18, N20-N22, N26) has no test of the code that ships. The process review's "can't import the app target" is a fixable tooling belief, not a law.
- **Structural remedy:** (1) try `@testable import AdaptiveSound` from the existing test target (S effort: spike to see whether the flags allow it); (2) if it works, delete `AudioPlaybackEngineMirror`,
  `MockAdvanceController`, `MockPlaylistController`, and run the VM tests against the real `AudioViewModel` + a real conformer of `AudioPlaybackEngine` (a test `FakeEngine` with scripted `EngineSnapshot`s; `SheetEngine` is already
  80 % of it); (3) if not, extract the model layer to a library target (the Point-Free/Apple sample-code norm: UI + `@main` in the app, models in a package). Either way the Debug picture/stall tooling
  can then live in its own target depending on the models' public/internal surface instead of #if DEBUG islands.
- **Effort:** S (spike) / M (migration of ~19 test files) / L if extraction is needed. **Risk:** low (tests only) to med (extraction). **Depends on:** none; it unblocks VM-1/2/7.

### VM-9 One global `errorMessage` slot, last writer wins, any success clears it, LOCAL. Criteria: 1
- **Evidence:** `errorMessage` is written from engine init, start failure, seek failure, device selection, pause/stop failure, shutdown, `lib.onError` (`AdaptiveSound.swift:63`), device-loss
  (`+SpectrumTimer.swift:85`), and cleared by `startPlayback` success (`+Playback.swift:69`), `selectDevice` success (`+Devices.swift:29`), `initializeEngine` (`:66`), `retryInitialization`. A library scan error is erased
  by the next successful play; a "device disconnected" message is erased by an unrelated success.
- **Root cause / remedy:** model it as `[AppNotice]` with a source key (`.engine`, `.device`, `.library`), each cleared by its own recovery event, shown by the existing banner (`ErrorBanner.swift`).
- **Effort:** S. **Risk:** low. **Depends on:** none.

### VM-10 Fire-and-forget `Task`s with order dependence and no cancellation, SIGNIFICANT. Criteria: 1, 4
- **Evidence:**
  - `refreshDevices` (`+Devices.swift:43-70`): each device-change notification spawns a `Task` that awaits `enumerateOutputDevices()` and then writes `availableDevices`/`selectedDevice`. Two overlapping
    notifications (a Bluetooth connect fires several) can complete out of order, so an older list can win. `selectDevice` spawns its own `Task` and `adoptOutput`; `refreshDevices` can call
    `selectDevice` from inside its own Task. There is no "latest wins" token, unlike `LibraryBrowseModel`'s 7 load epochs; the same problem was solved there with epochs and not here.
  - `armOnDeck`, `handleTrackTransition`, `adjustPendingNextIndexAfterRemoval` each spawn a `Task { await engine.setNextTrack(url) }` (`+Queue.swift:198`, `+AutoAdvance.swift:52`, `+Playlist.swift:79`). Order between two rapid
    edits relies on unspecified `Task` start order plus the engine's queue FIFO. The code *knows* the hazard: `publishIntensity`'s doc says "an unstructured Task only risks applying an earlier value after a later one
    (S3 finding F4)" and so avoids it there, but the on-deck path accepts it.
  - `stopPlayback()` is fire-and-forget; `shutdown` re-awaits `performStop` separately, so a user Stop racing quit runs two stops.
- **Root cause:** each verb picks its own concurrency idiom; no serial command channel.
- **Structural remedy:** one serial `EngineCommandQueue` (the effect runner of VM-2) for every engine-bound request, and a latest-wins device refresh (`Task` handle cancelled/replaced, or an epoch, mirroring `LibraryBrowseModel`).
- **Effort:** M. **Risk:** med. **Depends on:** VM-2.

### VM-11 Wide, concrete dependencies between models; the kits' seams are good but the VM is bigger than the kit it uses, SIGNIFICANT. Criteria: 1, 2, 3
- **Evidence:**
  - `EQViewModel` holds the whole `AudioViewModel` strongly (`EQViewModel.swift:32`) to use 4 members (`pureModeEngaged`, `isEngineReady`, `eqDesignRate`, `publishEQ`).
  - `LibraryBrowseModel` and `PlaylistsModel` hold `audio` for 6 play verbs (`playNowWithUndo`, `playNext`, `appendToQueue`, `playTrackNextNow`, `selectedTab`, `restorePreviousQueue`), and read UI-nav state (`audio.selectedTab`, `LibraryBrowseModel.swift:404`).
  - `NowPlayingController`, `MenuBarView` and the two browse models each re-derive "the current file" from `queue`+`selectedTrackIndex` (`NowPlayingController.swift:188`, `MenuBarView.swift:13-16`,
    `NowPlayingBar.swift:20-23`, `HeroBand.swift:29-30`): four copies of `index < count ? queue[index].file : nil`.
  - Kit seams, per kit: `PlaybackQueueKit` (pure functions + `TransportSnapshot`/`SnapshotChannel`; good, but stateless: the state that makes the functions hard to call correctly stays in the VM, VM-7);
    `OutputDeviceKit` (`OutputDevicePolicy`, the one rule used by both the bridge and the VM: good); `EQEditKit` (see below).
  - Duplicated logic between VM and kits: the `CADefaultDeviceAggregate-` prefix (map N103: `EQOutputKey.swift:33` / `DeviceListPolicy.cpp:26`); `deviceIsHeadphones` is a Swift heuristic
    over `.wireless/.usb` (`AudioViewModel.swift:166`) while the engine/policy side derives transport separately (`publishOutputTransport`): two classifications of "headphone-class".
- **Remedy:** narrow protocols at the consumer: `EQEngineSink` (publish, readiness, rate, pure flag) for EQ; `QueueCommands` for the browse/playlist models; `currentItem` on the queue (VM-7); one `OutputClass`
  (headphone/speaker/transport) derived once in `OutputDeviceKit` from `transportType`, used by both crossfeed gating and the limiter ceiling.
- **Effort:** M. **Risk:** low. **Depends on:** VM-1, VM-7.

### VM-12 `AudioPlaybackEngine` is one 20-requirement protocol with default no-op implementations for 8 of them, LOCAL. Criteria: 2, 6
- **Evidence:** `AudioPlaybackEngine.swift:34-62` provides default no-ops for `setNextTrack`, `currentOutputDeviceID`, `setPinPlaybackToSelectedDevice`, `publishIntensity`, `publishCrossfeed`, `publishOutputTransport`,
  `publishMasterGain`, `requestDeviceVolume` and says a conformer "still builds". A conformer (or a future engine) that forgets `publishMasterGain` compiles and silently plays at unity; the MasterGain feature has
  a hearing-safety dimension. Gapless is a *contract* (the long header) but not a protocol.
- **Remedy:** split by role (`TransportEngine`, `DSPControl`, `OutputDeviceControl`, `GaplessSource`) and drop the defaults (fakes implement the cases they care about, or a `NoOpDSPControl` is injected explicitly). Natural fit for the effect runner.
- **Effort:** S-M. **Risk:** low. **Depends on:** none.

### VM-13 App lifecycle ownership is split between `init`, window `onAppear` and the delegate, LOCAL. Criteria: 1
- **Evidence:** engine start and delegate wiring happen in `ContentView.onAppear` (`AdaptiveSound.swift:119-138`), though the comment says "Engine lifecycle belongs to the app/scene, NOT a child view's `.task`/`.onDisappear`".
  It is idempotent by guards in three places (`initializeEngine`, `registerCommands`, `commandsRegistered`), a valid defence given resident re-appear, but ownership is still the window. `AppDelegate` holds 5 `weak` refs filled in
  that closure; if the process quits before the window appeared, `audioViewModel != nil || libraryModel != nil` is false and it terminates without the ordered teardown (benign now, fragile as engine start moves earlier).
  The `MenuBarExtra` can issue Play before the window ever ran `initializeEngine` ("Engine not ready", `+Playback.swift:19`).
- **Good:** `AppDataLocation` (one decided-at-launch location, injected, semgrep-enforced; `AppDataLocation.swift`), and `applicationShouldTerminate` with `.terminateLater` and ordered teardown.
- **Remedy:** the `AppModel` composition type of VM-6 owns construction, `start()` (engine init, called from `App.init`/scene-phase), and `shutdown()` ordering; the delegate takes one strong ref.
- **Effort:** S. **Risk:** low. **Depends on:** VM-6.

---

## What is GOOD (keep and copy)

- **`EQViewModel` + `EQSession`.** The model of how to do this: the session (a pure value type in `EQEditKit`) decides, `perform(_ verb: (inout EQSession) -> EQOutcome)` carries out `outcome.effects` (send / saveSlots /
  saveMyPresets / log / toast) in one place. 399 lines, one dispatch to the engine, 11+ SESSION tests, the memoised played curve with an observed design rate. This is the reducer pattern the transport needs (VM-2),
  already working here without a framework.
- **Epoch-stamped `TransportSnapshot` + `SnapshotChannel`**: engine state as a copy under a leaf lock; the right fix for the freeze, and the right seam for an event channel (VM-3).
- **Pure decision kits with tests**: `QueueAdvance`, `PlaybackOrder`, `SeekRoute`, `ResumePoint` (slot-keyed), `QueueRestorePoint.afterReplace`, `OutputDevicePolicy`, `MasterGainLaw`.
- **Persistence done properly where it was done**: `eqStateV2` (one versioned JSON blob, migration with catch-up, `.unreadable` side-copy, a downgrade-friendly v1 key) and the `current` playlist mirror's
  full-snapshot + self-healing design (`+QueueMirror.swift:5-12`).
- **`AppDataLocation`**: one location chosen at launch and injected; the `-ASTestLibrary` debug location rides on it.
- **Cheap guards where applied**: same-value write suppression for `loudness`/`signalPath`/`eqDesignRate`; `@ObservationIgnored` on epochs; the documented "never self-assign in `didSet`" rule.
- **Single entry point for UI play/pause** (`togglePlayPause`) so footer, menu, queue and menu bar cannot drift.
- **Ordered, awaitable shutdown** (`+Lifecycle.shutdown`, `terminateLater`).

## Duplicated capability (for the duplication pass)

1. Current-file derivation (`index < count ? queue[index].file : nil`) in `NowPlayingBar`, `HeroBand`, `MenuBarView`, `NowPlayingController`, `+PlayingTrack`, `+PlayTracking` (and `selectedSlotID`).
2. Three 20 Hz polling mechanisms: two `Timer`s and `MonitoringViewModel`'s `Task.sleep` loop; MonitoringViewModel reads the engine directly, bypassing the VM's readout path.
3. "Intent copied into readout": `signalPath.intensityLinear/crossfeedStrength` re-stated from the VM every tick (`+SpectrumTimer.swift:166-167`).
4. "Headphone-class" classification: `deviceIsHeadphones` (VM) vs the transport type the engine uses for the limiter ceiling (`publishOutputTransport`).
5. Track-change bookkeeping repeated across `startPlayback`, `handleTrackTransition`, reconfigure-advance, `removeTrack` (reset tracking, zero position/duration, refresh duration, re-arm).
6. `songs.columns.v2` literal in two files; per-model raw defaults keys in three places.
7. `countPlayIfNaturalEndQualifies` called at 4 sites with the same pre-advance ordering requirement (map N26's "four completion sites").
8. The VM test mirrors versus production (the extreme case of duplication).

## Algorithms that need a correctness panel (map row IDs)

- **N12 / N14 / N15 / N17** (epoch numbering, stop gate, tick advance, start/prime): the "stop numbered inside the Task" asymmetry and the "starting" state (VM-2); needs a model-checked interleaving test (breaker with a
  scripted engine) once VM-8 gives access to the real code.
- **N16 `pollPlayhead` and N26 play-through accrual**: stale-sample branch, same-value write, stalled-tick counted as heard (known deferral) and the `isPlaying`-true-while-pausing window.
- **N18 move/drop re-indexing and N19 queue verbs**: untested on production; `clearPlaylist` intermediate state; shuffle-order history absence (Previous under shuffle is random, `+AutoAdvance.swift:96-99`: product-visible).
- **N20 press-Play choice, N21 `canGoNext` (random draw inside a computed property), N22 cursor restore, N23 mirror debounce.**
- **D82 / N101 Master Gain law** is fine (tested), but its *persistence and Pure-device-volume interplay* (`deviceVolumeAsked` hold rule, `+MasterGain.swift:24-28`) is an untested state machine of its own.

## Open questions for the founder

1. **Persist the playback intents?** Recommended: yes for Pure intent, Master Gain (turn-down only, so no loudness risk), crossfeed, Intensity, "keep on this device", shuffle/repeat; persist crossfeed *intent* separately from its
   auto-off on non-headphone outputs. The one hesitation is Pure ("start in Pure next launch" surprises someone on speakers); the recommendation is still to persist and let the existing fallback logic handle an unsuitable device.
2. **Is the founder willing to let the VM tests run against the real `AudioViewModel`** (spike S: `@testable import` from the existing test target) and retire the mirrors? Recommended: yes; the mirror has already lied twice.
3. **Event channel from the engine (VM-3) vs keep polling:** recommended to add events for seam / ended / device-lost and keep the snapshot for position; the cost is engine-side work after the audit's snapshot work, so it is a
   post-R1 R2-prep wave item, not an alpha blocker.
4. **Who owns UI navigation state** (`selectedTab`, browse path) long-term? Recommended: a small `ShellNavigation` model so Library/Playlists models stop importing the audio VM for it.
5. **Shuffle history for Previous** (currently random): a product decision that the machine of VM-2/VM-7 makes cheap to do right.

## Suggested ordering (feeds the wave plan)

1. VM-8 spike (S, unblocks everything). 2. VM-5 settings store + VM-9 notices + VM-4 quick wins (local array, guarded writes, quantised elapsed value for text/AX) as a low-risk wave. 3. VM-7 `PlayQueue` + VM-2 reducer
(with VM-10 command queue) as the one big, test-first change. 4. VM-1 decomposition and VM-6/VM-11/VM-13 follow naturally once the reducer exists. 5. VM-3 events when the engine side is next opened.
