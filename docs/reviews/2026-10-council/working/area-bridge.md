# Area review: the audio engine bridge and its concurrency (Swift)

Reviewer: area code reviewer, council Stage 2. Repo `/Users/ramith/code/sound-engineering` @ 7d7c2cd, read-only.
Scope: `AudioEngineBridge*.swift` (23 files, 4,130 LOC), `AudioPlaybackEngine.swift`, `EngineSnapshot.swift`,
`PureModeSession.swift`, the Swift side of the C-ABI. Nothing was built or run. SFBAudioEngine and Cog were
opened from `main` into `scratchpad/council/exp-bridge/{sfb,cog}`. Apple's `AVAudioPlayerNode.h` was read from the local SDK.

Builds on, does not repeat: `docs/architecture/main-thread-audio-audit-2026-10.md`, the evidence folder
`docs/architecture/evidence/main-thread-stall-2026-10/` (rev-sota M2 and M5, m1 and m3 are referenced, not re-derived),
and the ledger's "Logged post-R1" list: the Enhanced playhead latency and seam domains, the gap at the 48 kHz seam,
the false seam on a Pure to Enhanced restart, play-then-pause lost during a start, `SpectrumDoubleBuffer` TSan.

## Verdict

PR #86 made the main-thread boundary sound. That part is good, and the shape matches the field. Behind that boundary
the bridge is an accretion, not a design.

- The stated isolation model ("all mutable state is confined to one of the serial queues") is **not true as built**.
  Four execution domains drive the same `AVAudioPlayerNode` and `AVAudioEngine`, and the doc comments assert an
  ownership the code does not have.
- The transport is an implicit state machine held in about a dozen variables with three epoch counters and two
  hook slots. Each of those was added after a break-it round; the code carries about 45 review-tag comments
  (`break-it`, `MAJOR`, `P1-2`, `S-1`, `N-2`, `C-1`, `BS1`, `UAF-1`).
- The Enhanced path leans on `AVAudioPlayerNode`'s own schedule as the source of truth for position, seam and end.
  That one decision is the root cause of the epochs, the hooks, the re-establish machinery, the known seam gap, and
  the playhead-latency item already logged. The open-source players avoid it by owning the audio queue.
- None of it can be unit-tested, because the app target cannot be imported, so every tactical fix is pinned only
  by a comment.

Counts: **STRUCTURAL 3, SIGNIFICANT 8, LOCAL 5.**

---

## STRUCTURAL

### BR-1 The isolation model is stated, not enforced, and it is false in at least four places, STRUCTURAL. Criteria: 1, 6
- **Evidence:**
  - The claim: `AudioEngineBridge.swift:18-33` ("ALL mutable stored state is confined to one of the bridge's serial
    dispatch queues"), and `:286-293` ("`engineQueue` owns ALL transport / graph mutation").
  - **configChangeQueue drives the player and engine.** `reestablishEnhancedAfterConfigChange`
    (`+ConfigChange.swift:32-120`) runs on `configChangeQueue` and calls `engine.start()`, `engine.stop()`
    (`:88`), `seekEnhancedResampler` (which calls `player.stop()` and `play()`, `+EnhancedResampler.swift:216,223`),
    `seekEnhancedBestEffort` (`+PureMode.swift:345-360`) and `player.play()`. That is concurrent with
    `engineQueue`'s `startAudio`, `seek` and `stopAudio`.
    - The fix for the resulting race is a TOCTOU re-check, "break-it MAJOR-2": `intentStillLive`
      (`+ConfigChange.swift:82-91`). It narrows the window and does not close it. The intent can clear after line
      86, and the stop would then run first.
    - A concrete interleave: the user presses Play on a new track while a device switches. `startAudio` rewrites
      `lastFileURL` (`+Playback.swift:16`) and the new file. The re-establish already holds `resumePos` from the
      old playhead, and now `seekEnhancedBestEffort(url: lastFileURL, to: resumePos)` starts the new track at the
      old track's position.
  - **A global concurrent queue runs `playFile`.** `openNextFileOrRestart`
    (`+GaplessRoll.swift:161-178`) does `DispatchQueue.global().async { … self.playFile(...) }`.
    - `playFile` reconfigures the graph (`configureGraphForSource`), stops the player, bumps both epochs and
      schedules, all off every bridge queue.
    - It does not consult the play intent, so a Stop that landed in between is followed by zombie audio.
    - It reads `self.avEngine` directly (`:163`), which the accessor docs forbid off-domain.
  - **Direct, unlocked reads of the lock-guarded fields from the wrong domain.** `+Gapless.swift:77`
    (`self.playerNode` on `resampleQueue`, while `engineQueue` writes it via `setPlayerNode`), `+GaplessRoll.swift:163`.
    About 20 more direct `avEngine` / `playerNode` reads sit in engineQueue files. The "ONLY via the accessor"
    rule is a comment.
  - **The graph build finishes off-queue.** `+Graph.swift:19-40`: the two nested `AVAudioUnit.instantiate`
    completions run on an arbitrary queue and write `spatialAudioUnit`, connect nodes and allocate analysis state.
    `initialize()`'s `engineQueue` block has already returned, so a queued `startAudio` is eligible to run in parallel.
  - Instances of the same shape elsewhere: `isReestablishing` (`AudioEngineBridge.swift:298`, a re-entrancy flag on
    a queue that is already serial), and the `Locked` method pairs with `dispatchPrecondition` on `resampleQueue`.
- **Root cause:** isolation is by convention over GCD queues. Nothing in the type system says which domain may
  touch `playerNode`. Every new event source (config-change notification, listener, completion handler, fallback)
  picks its own queue, and the break-it rounds patched each interleave with a flag, an epoch or a re-check.
  Both open-source players put the config change under the same lock as the transport.
  SFB takes `engineMutex_` for the config-change handler: `AudioPlayer.mm:2559-2660`
  (https://github.com/sbooth/SFBAudioEngine/blob/main/Sources/CSFBAudioEngine/Player/AudioPlayer.mm).
- **Why it matters:** an unreproducible class of "wrong position / zombie audio / wrong song" bugs after device
  events, which is the area the founder already hit twice (wrong-song and the freeze). Each such bug is found only
  by a human with hardware. It blocks R2 features that touch the transport.
- **Structural remedy:** one transport isolation domain. Preferred: a single engine-owned domain in which the
  config-change handler and the listeners do not act, they enqueue a command.
  - Concretely: a `@globalActor`-style `EngineActor` backed by `DispatchSerialQueue` (SE-0392 custom executors,
    macOS 14+; the package targets macOS 26). `AVAudioEngine`, `AVAudioPlayerNode`, `PureModeSession` and the
    schedule state become `@EngineActor` members, so the compiler rejects an off-domain touch.
  - The actor must keep all bodies synchronous, with no `await` inside a transport step, to avoid actor
    reentrancy. The main-thread rule then becomes type-enforced: main can only `await`.
  - Cheaper first step without actors: make `configChangeQueue` and the global fallback post one
    `TransportCommand.reestablish(epoch)` to `engineQueue`, and delete `isReestablishing` and the TOCTOU.
  - `AudioEngineBridge.swift:32` justifies "no actor" by RT-safety ("executor hops on the control path"). That is a
    non sequitur: no render or tap code is Swift-actor code; the RT side is the AU C++ and the three tap blocks,
    which do not depend on the control-plane isolation choice.
- **Effort:** L (the cheap first step is M). **Risk:** med to high; the transport is the app's centre. **Depends on:** BR-3 (the command type), BR-4.

### BR-2 The Enhanced path's source of truth is the AVAudioPlayerNode's schedule, so every disturbance must re-derive position and seam, STRUCTURAL. Criteria: 1, 3, 5
- **Evidence:**
  - Position: `liveEnhancedPosition` (`+TransportClock.swift:110-125`) is `base + playerTime.sampleTime/rate`.
    `base` is rewritten by `playFile:187`, `seek` (`+PureMode.swift:218`), `bumpTransitionCount`
    (`+Gapless.swift:202`) and re-establish (`+ConfigChange.swift:118`). `lastKnownEnhancedPositionSeconds` is a
    cache to survive nil render times, written by the clock (`+TransportClock.swift:98`) and by the seam.
  - Seam and end: driven by `.dataPlayedBack` (passthrough, `+Playback.swift:216`, `+GaplessRoll.swift:207`) and
    `.dataConsumed` (resampler, `+EnhancedResamplerSeam.swift:69`) completions hopping to `resampleQueue`.
    - `player.stop()` fires those completions as if they were EOF, so the code carries two epochs
      (`resampleGeneration`, `passthroughGeneration`), bumped at 8 sites (`+EnhancedResampler.swift:148,193,194,260,261`,
      `+PureMode.swift:342`), plus the "nil hook under a live epoch means genuine EOF" inference
      (`+GaplessRoll.swift:112-126`).
    - Header contract: `AVAudioPlayerNode.h` says `DataPlayedBack` is after the device latency, and "stop unschedules
      everything and returns the timeline to 0".
  - Recovery: a config change flushes the node's queue, so `reestablishEnhancedAfterConfigChange`, `seek` and
    `startAudio(startAt:)` are three implementations of "stop, reschedule from X, play" (see BR-8, BR-9).
  - Consequences already in the ledger as separate items: the 48 kHz seam gap (B is scheduled only after A's
    `.dataPlayedBack`, `+GaplessRoll.swift:189-216`); the position and seam in different latency domains (rev-sota
    M2); the track-B loudness gain landing early on the resampler path.
- **Root cause:** the app does not own the queue of audio. It hands ranges to `AVAudioPlayerNode` and tries to
  infer playback state from callbacks that mean different things (`consumed`, `rendered`, `playedBack`) and fire on
  non-EOF events too. The Pure path already has the right model, in C++: `FileDecodeSource` + `SpscRing` +
  `GaplessSource` with render-side frame accounting (`GaplessSource.h:142-157`, per-track base).
- **State of the art (opened):**
  - SFBAudioEngine: `AVAudioSourceNode` pulling from an app-owned SPSC ring, a decode `std::jthread`, an event
    thread, one `engineMutex_`, one `playbackGeneration_` atomic epoch, `pendingSeek_` as one atomic
    (`AudioPlayer.h:127-180`, `AudioPlayer.mm:966,1210-1234,2106`). Gapless is a decoder-queue property
    (the next decoder is pre-decoded into the same ring), and a config change needs no re-schedule because
    nothing is scheduled on the node.
    https://github.com/sbooth/SFBAudioEngine/blob/main/Sources/CSFBAudioEngine/Player/AudioPlayer.h
  - Cog: a ring (`Audio/Engine/Core/CogRing.c`), and heard position = read position minus the latency cached at
    configure time (`Audio/Engine/Output/DeviceOutput.swift`, `Audio/Engine/Facade/PlaybackEngine.swift`).
    https://github.com/losnoco/Cog/tree/main/Audio/Engine
- **Why it matters:** this is the single design decision behind about 60% of the bridge's complexity
  (`+EnhancedResampler*`, `+GaplessRoll`, `+Gapless`, `+ConfigChange`, half of `+PureMode`: roughly 1,500 LOC and
  all the epoch machinery), and it is the reason Enhanced gapless is structurally weaker than Pure. It also makes
  one position model and one seek model impossible, which blocks R2 transport features.
- **Structural remedy:** one transport model for both paths. An `AVAudioSourceNode` (Enhanced) pulls from the same
  decode-and-ring components Pure uses (`FileDecodeSource`, `GaplessSource`), with resampling done on the decode
  thread. That is also the place to use a standardised high-quality SRC, per the "right tool per layer" memory.
  The playhead, seam, end and seek become render-side frame counters. Delete the two epochs, both hooks, `base`,
  `lastKnown`, `onDeckURL` and the re-establish-by-seek.
  - The cost to confirm in a panel: an `AVAudioSourceNode` render block runs inside the effects graph, so the
    ring read must be RT-clean (it already is in Pure), and the SRC quality and CPU must be measured against
    `AVAudioConverter(.max)`.
  - A staged alternative that keeps the node: pre-schedule B behind A at arm time and drive the seam by A's
    completion, with the seam keyed by a frame boundary on `resampleQueue` (rev-sota M2 fix 1). That removes the gap
    but not the epoch machinery.
- **Effort:** L. **Risk:** high (audio path), mitigated by the offline harness plus the gapless contract tests.
  **Depends on:** BR-3, BR-4. Needs an algorithm panel (D37, D39, D40, N13).

### BR-3 The transport is an implicit state machine spread over about a dozen variables, STRUCTURAL. Criteria: 1, 2
- **Evidence:** the state lives in all of these, with no single owner and no transition function:
  `activePath` (lock), `enhancedPlayIntentFlag` (atomic), `SignalPathInfo.interrupted` (lock), `gaplessEndedFlag`
  (atomic), `gaplessTransitionCounter` (atomic), `transportEpoch` (engineQueue), `transportClock != nil`,
  `isReestablishing`, `passthroughGeneration`, `resampleGeneration`, `resampleSession`, `onDeckURL`,
  `onResamplerEOF`, `onPassthroughEOF`, `storedLastFileURL`, `pureEngine != nil`.
  Transitions are written inline, in each entry point: `startAudio` (`+Playback.swift:7`), `stopAudio` (`:243`),
  `seek` (`+PureMode.swift:174`), `attemptPureStart` (`:53`), `pauseForDeviceLoss`
  (`+OutputDeviceMonitor.swift:199`), `stopPlaybackAfterDeviceLoss` (`:218`), `reestablishEnhancedAfterConfigChange`,
  `rollResamplerToNext`, `rollPassthroughToNext`, `markGaplessPlaybackEnded` (`+GaplessRoll.swift:140`).
  - "Stopped" is not a state. It is `activePath == .enhanced && !intent && transportClock == nil`, written in
    three places, in three orders (`stopAudio`, `stopPlaybackAfterDeviceLoss`, `performEngineTeardown`).
  - The same event gets different handling by path: end-of-queue via `gaplessEndedFlag` (Enhanced) vs
    `pureModeEnginePlaybackEnded` (Pure).
- **Root cause:** each new behaviour (gapless, device loss, Pure fallback, config change) was added as a method
  on the class that sets the flags it needs. There is no `State` type, no `Event` type, no reducer.
- **Why it matters:** this is the charter's own example of brittle ("a state machine spread across 20 extension files
  with implicit transitions"). It cannot be exhaustively tested. A new event (a Bluetooth route change mid-seam, a
  seek during Pure rate change) means reading all of those variables and every transition by hand.
- **Structural remedy:** an explicit `TransportState` enum (`idle`, `starting(epoch)`, `playing(path)`,
  `seeking`, `interrupted`, `ended`, `reestablishing`) and a pure reducer
  `(state, event) -> (state, [Effect])` in a Kit (like `PlaybackQueueKit`, which already holds `ResumePoint`,
  `SeekRoute`, `OutputDevicePolicy`). The bridge interprets effects on the one domain from BR-1.
  `OutputDevicePolicy.action(for:facts:)` (OutputDeviceKit) is already the correct template: facts in, action out,
  unit-tested. Extend that pattern to the whole transport. This also gives the "command for transport requests"
  pattern the charter asks for.
- **Effort:** L. **Risk:** med, because the reducer can be built beside the bridge and cross-checked in tests first.
  **Depends on:** pairs with BR-1.

---

## SIGNIFICANT

### BR-4 The bridge is untestable by construction, so every tactical fix is pinned only by a comment, SIGNIFICANT. Criteria: 6
- **Evidence:** the app target cannot be imported by tests (process.md). `AudioEngineBridge` (4,130 LOC) has no unit
  test. There is no seam between the logic and AVFAudio: `AVAudioPlayerNode`, `AVAudioEngine`, `AudioObject*` and
  C-ABI calls are used directly in the logic bodies (`+Playback.swift:211`, `+ConfigChange.swift:64`). Tests run a
  hand-written `AudioPlaybackEngineMirror` (`Tests/AudioViewModelTests/MockAudioEngine.swift:43`), which is a
  second protocol, not the real one.
- **Root cause:** the logic is in a concrete class in an executable target, and the design never separated "decide"
  from "do".
- **Why it matters:** the gapless roll, the resampler, re-establish, the device-volume path and the AU borrow have
  zero automated coverage (map section 7). They are exactly the areas with the most break-it patches.
- **Structural remedy:** (1) BR-3's reducer lives in a Kit and is table-tested. (2) Define thin protocols at the
  hardware edge (`PlayerNodeDriving`, `EngineDriving`, `HALDevices`) that the bridge uses, with `AVFAudio`
  implementations and fakes. (3) Move the bridge into a library target so it is importable. The architecture
  reviewer owns the target layout; the minimum for this area is the reducer plus the edge protocols.
- **Effort:** M to L. **Risk:** low. **Depends on:** BR-3.

### BR-5 `stateLock` is a grab-bag guarded by accessor convention, and three lock idioms coexist, SIGNIFICANT. Criteria: 1, 5, 6
- **Evidence:** the lock guards 14 unrelated fields in two classes: UI-facing values (`storedCachedSignalPath`, pin,
  base seconds) and lifecycle objects (`avEngine`, `playerNode`, `pureEngine`, `storedEffectsUnit`, `storedTapAnalysis`,
  `deviceVolumeWatch`, `pendingDeviceVolume`). The fields are plain `var`s (`AudioEngineBridge.swift:35,36,124,129`),
  readable by name without the lock, and they are (BR-1). The lock itself is a hand-allocated
  `os_unfair_lock_t` (`:101-105`, freed in `deinit`). Elsewhere: `OSAllocatedUnfairLock` in `SnapshotChannel`
  (`PlaybackQueueKit/TransportSnapshot.swift:52`), and `Synchronization.Atomic` for the flags.
- **Root cause:** the lock protects fields, not a value. Nothing makes access go through it.
- **Why it matters:** the "leaf lock, no callouts" rule that PR #86 had to restore (three call-outs had crept in
  under it) is again a rule in a comment. The next field added will repeat the history.
- **Structural remedy:** `Mutex<Shared>` from `Synchronization` (macOS 15+; the package targets 26), with `Shared` a
  struct. The only access is `shared.withLock { … }`, and non-`Sendable` references are returned, never held across
  the lock. The compiler then rejects direct field access, `@unchecked Sendable` on the class shrinks to the
  queue-confined remainder, and the `Atomic`, `Mutex` and `SnapshotChannel` idioms become one family. Split the
  UI-facing published values (one `SnapshotChannel<EngineSnapshot>` published by the clock, as the audit's arch
  reviewer suggested) from the lifecycle objects (owned by the BR-1 domain, not by a lock at all).
- **Effort:** M. **Risk:** low to med. **Depends on:** BR-1 for the full benefit.

### BR-6 `engineQueue` is a head-of-line blocker and `resampleQueue` has two unrelated jobs, SIGNIFICANT. Criteria: 1, 2
- **Evidence:**
  - `engineQueue` runs the 33 ms transport clock, every start, stop and seek, every Pure C-ABI call, the HAL
    enumeration (`+Devices.swift:16-56`) and `selectDevice`, master-gain sets, graph build, `engine.stop()` and `engine.start()`.
    `engine.stop()` after a device loss runs there and can wait about 7 s (`+OutputDeviceMonitor.swift:226`; the
    evidence's founder re-test: "teardown still took about 8 s"). While it waits, the clock, the master-gain
    slider and the device list all queue behind it. The audit accepted that as latency.
  - `seekEnhancedBestEffort` opens an `AVAudioFile` on `engineQueue` (`+PureMode.swift:324`, disk or network IO).
  - Wait edges: `engineQueue` waits on `resampleQueue` at 10 `.sync` sites and on `configChangeQueue`
    (`+OutputDeviceMonitor.swift:46,59`); `configChangeQueue` waits on `resampleQueue` (`+ConfigChange.swift:103`).
    `resampleQueue` does disk reads (`readChunk`, `+EnhancedResamplerSeam.swift:88`), SRC conversion and the next-file
    open (`+GaplessRoll.swift:154`). So a network-volume file open or a long convert delays every Stop and Seek.
    The code admits it: the clock "never waits on resampleQueue, which can be busy in AVFAudio or opening the next
    file" (`+TransportClock.swift:88`).
  - Is the topology cycle-free by construction? It is acyclic today, but only by comment
    (`AudioEngineBridge.swift:289-292`, `+Gapless*.swift` "C-1" notes). The enforcement is libdispatch's
    re-entrant-sync trap, a crash that shows up only when the path runs. The ledger of those traps is the pairs
    `stopEnhancedResampler` / `stopEnhancedResamplerLocked` and `primeEnhancedResamplerLocked`.
  - `resampleQueue` is named for the resampler yet owns `onDeckURL`, both EOF hooks, `passthroughGeneration` and
    `gaplessEnded` for the passthrough path that has no resampler (`AudioEngineBridge.swift:160,187`).
- **Root cause:** queues were added per symptom (`resampleQueue` for the converter, then gapless state moved onto it;
  `configChangeQueue` for notification ordering; `deviceVolumeQueue` for the HAL set). Two of the four queues are
  coherent single-purpose queues (`deviceVolumeQueue`, and `configChangeQueue` as a notification serializer).
  `engineQueue` and `resampleQueue` mix latency-tolerant IO work with the control path.
- **Why it matters:** stop and seek latency is hostage to IO and to the HAL. The stall-class bugs recur wherever a
  blocking call lands on a shared queue.
- **Structural remedy:** a rule, then a topology. The rule: nothing that can wait on IO or the HAL runs on the
  control queue, and the control queue never `.sync`s to a queue that can. The topology: one control domain
  (BR-1); a device-query domain for enumeration, selection and volume reads (extend `deviceVolumeQueue` into that);
  a decode or convert worker that only produces, and replies by async message. With BR-2 the decode worker is the
  C++ thread and `resampleQueue` disappears. If BR-2 is deferred, split `resampleQueue` into a converter worker
  and the seam-state owner, and move `AVAudioFile` opens off `engineQueue`.
- **Effort:** M (L with BR-2). **Risk:** med. **Depends on:** BR-1.

### BR-7 An Enhanced gapless seam across a channel-count change is unguarded, SIGNIFICANT. Criteria: 4
- **Evidence:** `rollPassthroughToNext` (`+GaplessRoll.swift:72-96`) and `rollResamplerToNext` compare only the
  sample rate (`nextRate == graphRate`). Nothing compares channel counts or calls `configureGraphForSource`; that runs only
  in `playFile` (`+Playback.swift:171`). The VM arms the next track regardless
  (`AudioViewModel+AutoAdvance.swift:56`, `+Playlist.swift:111`). Pure has an explicit policy for this: arm result 1
  means "needs reconfigure, do not arm" (`+Gapless.swift:135-142`).
- **Root cause:** the Enhanced "arm" has no compatibility check, because the format negotiation lives only in the
  fresh-start path.
- **Why it matters:** `AVAudioPlayerNode.h:90-91`: with a mismatched channel count "channels will be dropped or
  added as required", which is the naive downmix the multichannel epic exists to prevent. The kernel's channel layout
  tag, the BS.1770 weights and the N-to-M spatial stage are all set for the old width. A 5.1 album followed by a
  stereo track, or a mono track mid-playlist, are ordinary libraries. Untested.
- **Structural remedy:** arm-time compatibility check as a policy function (`GaplessCompatibility.evaluate(current,
  next, graph)` in a Kit, mirroring `pureModeEvaluate`): armable only when channel count and layout match; otherwise
  do not arm and let the VM do a fresh start (a deliberate, honest gap, as Pure does). Needs a break-it test.
- **Effort:** S to M. **Risk:** low.

### BR-8 Seek handling per path has correctness defects and per-path divergence, SIGNIFICANT. Criteria: 3, 4
- **Evidence:**
  - Base is set before success is known. `seek` writes `setEnhancedPositionBaseSeconds(max(seconds, 0))`
    (`+PureMode.swift:218`), then `seekEnhancedBestEffort` returns silently when the file fails to open or the
    target is out of range (`:324,331`) without touching the player. The player keeps playing from the old place
    while the base now claims the new one, so the scrubber jumps. The log still says `result=ok` (`:234`). The
    resampler twin has the same shape (`+EnhancedResampler.swift:197-202` returns `false`; `seek` logs `failed`
    but still resumes OK and the base stays changed).
  - Order dependence at a seam. The base is written on `engineQueue` outside `resampleQueue`. A seam handler already
    queued on `resampleQueue` runs `bumpTransitionCount`, which rewrites the base to `-sampleTime/rate`, after the
    seek set it. The seek's `player.stop()` then restarts `sampleTime` at 0, leaving the base wrong by a track
    length. Narrow, but real.
  - Rounding differs per path (Enhanced truncates, Pure `llround`; map note). Pure reports failure by throwing
    `seekFailed`; Enhanced never does. `engineQueue` file IO on seek (BR-6).
  - Three seek implementations: Pure native (`pureModeEngineSeek`), passthrough re-schedule, resampler re-prime.
- **Root cause:** BR-2 (position is derived from a base that every operation must keep consistent) and BR-3 (no
  place that owns "the seek succeeded, so now the position is X").
- **Structural remedy:** with BR-2, seek is one operation on one model (a frame target and an epoch). Interim: make
  seek transactional. Compute and validate the target first, change the player, then commit the base inside the same
  `resampleQueue` block as the reschedule. Return a typed result for Enhanced too.
- **Effort:** S (interim) / folded into BR-2. **Risk:** low.

### BR-9 The device-lost flag is control state stored inside a display struct, with a non-atomic check-then-act, SIGNIFICANT. Criteria: 1, 4
- **Evidence:** `pauseForDeviceLoss` (`+OutputDeviceMonitor.swift:199-207`): `guard !loadSignalPath().interrupted`, then
  sets intent false, then `storeInterruptedSignalPath()`. `interrupted` is a field of `SignalPathInfo` (the UI's
  signal-path readout). Every `storeSignalPath` overwrites it: `startEnhancedPlayback` (`+Playback.swift:130`),
  `stopAudio` (`:264`), `startPure` (`+PureMode.swift:148`), `tearDown`. The code's own comment records the
  consequence: "a start that ran on this queue in between cleared the flag, and has just stopped too"
  (`+OutputDeviceMonitor.swift:229`). The call comes from the alive-listener queue, `configChangeQueue`, or both, so
  two callers can both pass the guard. It is idempotent today only by luck. A user Play issued after the loss but
  queued before the deferred stop block is stopped by it (by design, but not a stated rule).
- **Root cause:** device-loss is a transport state (BR-3) but is encoded as a readout field.
- **Structural remedy:** `interrupted` becomes a case of `TransportState` (BR-3), changed only by the reducer, and
  `SignalPathInfo` is derived from state rather than stored beside it. Interim: one atomic `output-suspect` flag set
  in the listener block itself (rev-sota M1), cleared only by a numbered start request.
- **Effort:** S interim / M. **Risk:** low. **Depends on:** BR-3.

### BR-10 "Restart at position X" is implemented four times, SIGNIFICANT. Criteria: 3
- **Evidence:** (1) `startAudio(startAt:)` → `playFile`; (2) `seek` → `seekEnhancedBestEffort` /
  `seekEnhancedResampler`; (3) `reestablishEnhancedAfterConfigChange` → the same two seek helpers plus
  `setEnhancedPositionBaseSeconds(resumePos)` again (`+ConfigChange.swift:99-119`), on a different queue; (4) Pure
  restart at the playhead lives in the view model (`AudioViewModel.adoptOutput`, map section 3.3). Three near-identical
  completion closures schedule a segment under an epoch: `+Playback.swift:211-223`, `+PureMode.swift:347-359`,
  `+GaplessRoll.swift:207-215`.
- **Root cause:** BR-2. Each path re-derives the schedule.
- **Structural remedy:** one `restart(at:epoch:)` effect on the engine domain, used by start-with-offset, seek,
  re-establish, and the Pure device move. The view model stops owning a restart policy for Pure that the bridge owns
  for Enhanced.
- **Effort:** M. **Risk:** med. **Depends on:** BR-1, BR-3.

### BR-11 Swift 6 posture: the "no actor" rationale is wrong, and trust-me escapes are the design, SIGNIFICANT. Criteria: 5, 6
- **Evidence:** `@unchecked Sendable` on four types in this area (`AudioEngineBridge.swift:34`,
  `EnhancedResampleSession`, `PureModeSession.swift:33`, plus `LoudnessMeterHandle`), `@preconcurrency import
  AVFoundation` in all 23 files, `MainActor.assumeIsolated` (`+OutputDeviceMonitor.swift:185`) behind a
  `DispatchQueue.main.async`, hand-allocated lock, `withCheckedContinuation` + `queue.async` wrappers in 9 methods
  (not cancellable: a `Task` cancelled while `engineQueue` is wedged stays suspended), and `async throws` on methods
  that never throw (`stopAudio`, `enumerateOutputDevices`; failures are `Bool` returns).
- **State of the art (opened):** SFBAudioEngine and Cog (both opened) use neither Swift actors nor GCD for the
  audio core: SFB is C++ with one unfair mutex, `std::atomic` and `std::jthread`; Cog's engine is Swift over C rings
  with `DispatchQueue.main` for UI. So open-source players give no precedent for actors, and no reason to avoid
  them either. The relevant modern facility is SE-0392 custom executors (`DispatchSerialQueue` as an actor
  executor) plus `Synchronization` (`Mutex`, `Atomic`), both available at the package's macOS 26 floor. The
  `Atomic` half is already adopted; the `Mutex` and actor half are not.
- **Root cause:** the isolation was designed when Swift 5 mode and GCD were the available tools, and the
  concurrency strictness was then satisfied with escapes.
- **Structural remedy:** staged. (1) `Mutex<Shared>` (BR-5). (2) `EngineActor` over the engine's `DispatchSerialQueue`
  (BR-1); `PureModeSession` and the schedule state become actor-isolated, which removes two `@unchecked`. (3) Replace
  `MainActor.assumeIsolated` with `Task { @MainActor in }`, or make the callback `@Sendable` and hop. (4) Typed
  throws for the engine API (`throws(EngineError)`) in place of `Bool` and `Void` results. Accept that GCD stays for
  the CoreAudio listener queues.
- **Effort:** M to L. **Risk:** med. **Depends on:** BR-1, BR-5.

---

## LOCAL

### BR-12 Master Gain and device volume are two mechanisms, LOCAL. Criteria: 3
- **Evidence:** Enhanced `publishMasterGain` (`+MasterGain.swift:24-29`) is a FIFO `engineQueue.async` per slider tick
  (uncoalesced; rev-sota m3 flagged this for Pure, and Pure got the latest-wins drain at `:44-68`, Enhanced did not).
  Pure uses a `stateLock` slot plus a drain on `deviceVolumeQueue`. The "pending slot plus one drain" pattern now
  exists in three places (the Realizer, `requestDeviceVolume`, and the EQ publish).
- **Remedy:** one `LatestValueSink<Value>` (slot plus one drain, a generic over `Mutex`) used by both, with Enhanced
  gain applied on the same sink. **Effort:** S. **Risk:** low.

### BR-13 `initialize()` completes off its queue, LOCAL. Criteria: 1
- See BR-1 evidence (`+Graph.swift:19-40`). **Remedy:** wrap the two instantiate calls in one `async` function
  (`AVAudioUnit.instantiate` has an async form) and run the graph build on the engine domain after it resumes.
  **Effort:** S. **Risk:** low.

### BR-14 The AU borrow count is a spin-wait, LOCAL. Criteria: 1, 6
- **Evidence:** `setEffectsUnit` (`+SharedState.swift:236-238`): `while effectsAUBorrows.load > 0 { sched_yield() }` on
  `engineQueue`. It exists so the last release of the AU never lands on main. A busy-wait is preemptible by the
  very thread it waits for.
- **Remedy:** make "last release off main" structural: the borrow returns a token whose `deinit` hands the
  reference to the engine domain, or hold the AU only in the engine domain and give main a pure C handle that a
  teardown invalidates through an atomic generation. **Effort:** S to M. **Risk:** low.

### BR-15 `AudioPlaybackEngine` is a 20-requirement protocol with eight silent default implementations, LOCAL. Criteria: 2, 6
- **Evidence:** `AudioPlaybackEngine.swift:23-56` defaults `setNextTrack`, `publishMasterGain`, `publishIntensity`,
  `requestDeviceVolume` and more to no-ops; the file mixes lifecycle, transport, gapless, DSP publishing, devices,
  spectrum and monitor reads. The doc comment still describes seek as "best-effort re-schedule".
- **Why it matters:** a conformer that forgets a requirement compiles and silently does nothing (the mock mirror is
  separate, so that is already hiding drift).
- **Remedy:** split by role (`TransportEngine`, `DSPControlPlane`, `DeviceControl`, `MeterSource`), no default
  no-ops, one `EngineCommand` enum for transport requests (ties to BR-3). **Effort:** M. **Risk:** low.

### BR-16 Comment-enforced invariants have started to drift, LOCAL. Criteria: 1
- **Evidence:** `stopEnhancedResampler`'s doc (`+EnhancedResampler.swift:238`) describes "the explicit
  `resampleQueue.async` clear in `stopEnhancedPlayback`", which does not exist. `AudioEngineBridge.swift:18-33` and
  `PureModeSession.swift:12-21` assert confinement that BR-1 shows is false. `+TransportClock.swift:22-23` says the
  sample is "at most one sample behind the hardware" (rev-sota M2: it is ahead). `setPureEngine` guards its
  "only set onto nil" invariant with `assert` (debug only).
- **Remedy:** delete rules that BR-1/BR-3 turn into types; state the rest once, in architecture.md's queue table
  (the reviewer's R10 gap). **Effort:** S.

---

## What is GOOD (keep, copy elsewhere)

1. **The main-thread boundary** (`snapshot()`, `SnapshotChannel`, numbered transport requests with
   `TransportSnapshot.isCurrent(for:)`). The same shape as SFB's sequence numbers
   (`AudioPlayer.h:127-164`). Copy it for any other engine-to-UI state.
2. **`withPureEngine`**: borrow under the lock, call outside it, `dispatchPrecondition` on the owning queue.
3. **`PureModeSession` RAII** with an idempotent, null-safe destroy and `detachPureEngineForTeardown` for slow
   teardown outside the lock.
4. **`OutputDevicePolicy.action(for:facts:)`** (OutputDeviceKit): the correct template for BR-3. Pure decision,
   unit-tested; the bridge only gathers facts and applies actions.
5. **Device-loss pauses without calling `player.stop()`**, and the clock that runs only while something plays.
6. **`TrackLoudnessSink` and `CTrackLoudnessABI`**: a tight protocol seam for the analyzer.
7. **Named acquire/release atomics** over standalone fences (TSan-safe).
8. **`AudioPropertyListener`**: value type holding the exact (object, address, queue, block) it needs for removal.

## Duplicated capability (feeds the duplication pass)

- Playhead derivation: Enhanced (`liveEnhancedPosition` + base + lastKnown + seam re-base) vs Pure (render counter).
- Seek: three implementations (Pure native, passthrough segment, resampler re-prime), different rounding.
- Gapless: Pure `GaplessSource` vs Enhanced two hooks and four roll variants; plus a `playFile` fallback.
- "Restart at X": start-with-offset, seek, re-establish, VM Pure device move (BR-10).
- Passthrough schedule-with-epoch closure: three copies (`+Playback.swift:211`, `+PureMode.swift:347`,
  `+GaplessRoll.swift:207`).
- Master gain: Enhanced FIFO vs Pure latest-wins (BR-12); "slot plus drain": Realizer, device volume, EQ publish.
- Device target changes: `selectDevice`, `applyTargetChange`/`setOutputTarget`, `alignOutputForEnhancedStart`.
- End-of-queue: `gaplessEndedFlag` vs `pureModeEnginePlaybackEnded`.
- Test mirror protocol vs the real protocol (known, process.md).

## Algorithms that need a correctness panel (map IDs)

- **N13** engine epoch stamping and the sampler (count, position, count; `max(old,new)` epoch).
- **D37, D39, D40** resampler start/seek/flush, Enhanced roll, seam re-base (race with a seek at a seam, BR-8).
- **D43** and Pure seek `m2` (rev-sota). **N94** the reconcile (BR-1, BR-9 interleaves). **D84** device-volume drain.
- New for the panel: **arm compatibility** (BR-7), and the AVAudioConverter `.max` flush at EOF
  (`reachedEnd` with `.noDataNow`, `+EnhancedResamplerSeam.swift:155`) versus a `soxr` or libebur128-style
  oracle, needed before BR-2.

## Open questions for the founder

1. Is Enhanced gapless a release promise for libraries with mixed channel counts (BR-7), or may the engine do a
   short fresh start there, as Pure does? Recommended: a short fresh start (honest, matches Pure).
2. Do you accept replacing the Enhanced `AVAudioPlayerNode` schedule with an app-owned ring and source node (BR-2)?
   Recommended: yes, as the R2 transport foundation, built beside the current path and gated by the existing
   offline harness. It removes the seam gap and about 1,500 LOC of epoch machinery.
3. Is a Swift actor backed by `DispatchSerialQueue` acceptable as the single engine domain (BR-1, BR-11), given
   that SFB and Cog use neither? Recommended: yes, because it turns the main-thread freeze rule into a compile error.
4. When the output device is lost, may a Play pressed on the new device before the stale stop runs be stopped
   (BR-9)? Recommended: no; a numbered start must beat an older loss.
