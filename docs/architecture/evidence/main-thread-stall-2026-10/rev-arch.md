# Reviewer 3 (architect + the fool): S10.8 G main-thread stall fix

Branch `sprint/s10-8-g-fix-main-thread-stall` @ 90a62e8 (8 commits on 5b348fe), reviewed read-only in
`.claude/worktrees/review-arch`. I did not build or run anything. Semgrep was run on the branch (clean)
and on a scratch probe (`scratchpad/arch-sidestep/`) to test the new guard.

## Verdict: ship after named fixes

The core design is right, and it is the shape the field uses (SFB, Cog, VLC):
- the main thread reads one published copy;
- the engine samples itself off-main, on the queue that already serialises every transport change;
- the leaf lock no longer carries callouts;
- the AU handle is captured once, off-main.

Within its scope the fix is complete: all of the audit's S1/S2 freeze paths are closed, not only the
reported one. It leaves the later concurrency cleanup easier, not harder.

What must change before merge:
1. Close the stale-transport window that the design widens (MAJOR-1).
2. Make the stated guard honest and broader (MAJOR-2).
3. Fix the doc comments and test mirror that now describe the old locking rule (MINOR-1/2). These are
   cheap to fix but dangerous to leave.

Ship the Pure seek C++ change as its own PR (§5).

---

## 1. Requirements traceability (audit §3)

| # | Requirement | Status | Evidence (branch file:line) |
|---|---|---|---|
| R1 | No AVFAudio on main (incl. `.auAudioUnit`) | **Met** | The tick reads `engine.snapshot()` (`AudioViewModel+SpectrumTimer.swift:60`). Every control-plane publisher borrows `dspAURef`, an `AUAudioUnit` captured in `setDspAudioUnit` on the instantiate queue (`AudioEngineBridge+SharedState.swift:234-251`, called from `+Graph.swift:28`). Covers EQ (`+EQControl.swift:24,41,49`), intensity, crossfeed, channel layout and track loudness. Their C-ABIs end in `slotMutex_` + `dispatch_async` or `postWeak` (`Realizer.mm:196-203, 292-306`), with no engine lock. `adoptOutput` uses the snapshot (`AudioViewModel+Devices.swift:89`). A grep of VM/UI finds no AVFAudio or HAL symbol except detached `AVAudioFile` opens. |
| R2 | No HAL on main | **Met** | `requestDeviceVolume` runs on `deviceVolumeQueue` (`+MasterGain.swift:42-50`), and so does the listener (`:58-63`). Caveat: FIFO backlog, no coalescing (MINOR-5). |
| R3 | Tick reads only a published snapshot; no `.sync` from main; named atomics | **Mostly met** | `SnapshotChannel` (`PlaybackQueueKit/TransportSnapshot.swift:33-49`); named acquire/release `Atomic`s (`+SharedState.swift:76-95`); signal path under the leaf lock. No `.sync` reachable from main (grep). **Gap:** `loudnessReadout()` reads the `loudnessMeter` reference unsynchronised (`AudioEngineBridge.swift:336`). That is the audit's S1-E race, untouched, and the `EngineSnapshot` doc says "atomics" (MINOR-9). |
| R4 | `stateLock` never held across C-ABI, AVFAudio or dealloc; Pure readable without it | **Met** | `withPureEngine` takes a strong borrow under the lock and calls outside it, on engineQueue only (`+SharedState.swift:197-201`). The config-change rate read is hoisted out of the lock (`+ConfigChange.swift:79-80`). The setters swap under the lock and release after it (`+SharedState.swift:234-292`). Pure lifetime: strong `PureModeSession` borrow plus engineQueue confinement. |
| R5 | Pure reap off main | **Met** | The clock polls `pureModeEnginePollTrackAdvance` on engineQueue (`+TransportClock.swift:58-62`). The "must poll" obligation moved from the view model into the engine (`AudioPlaybackEngine.swift:101-104`), which is an improvement in its own right. |
| R6 | Enhanced playhead not read from the node at UI time; sampler on a queue main never waits on | **Met** | `liveEnhancedPosition` runs on engineQueue (`+TransportClock.swift:82-94`, `dispatchPrecondition(.notOnQueue(.main))`). The seam re-base and seek base contracts are unchanged. Main never `.sync`s onto engineQueue. No render-side counter or cached latency, but those were options, not requirements. |
| R7 | Every engine-lock holder covered | **Met by construction** | Main no longer touches the engine. The device-loss path drops `player.stop()` (`+OutputDeviceMonitor.swift:203-217`), and the next start clears the left-over schedule before `engine.start()` (`+Playback.swift:94-99`). Side effect: engineQueue now takes the engine lock 30×/s in the clock, so user actions can queue behind any holder. That is latency, not a freeze. |
| R8 | `interrupted` published before anything that can block | **Met** | `pauseForDeviceLoss` clears the intent atomic, then calls `storeInterruptedSignalPath`, then `engineQueue.async` (`+OutputDeviceMonitor.swift:185-192`). The view model reacts only with `Task { await … }`. |
| R9 | Completion handlers async-only | **Met** | Untouched. The left-over-schedule completions now fire at the next start's `playerNode.stop()`, and `stopEnhancedResampler`'s generation bump rejects them. |
| R10 | Engine-lock-held regression test + static guard | **Partly** | VM-TS-01..03 test the lock box, which is safe by construction. There is no engine-lock-held test of `tickTransport` / `publishEQ` / `setMasterGain` / `adoptOutput`. The semgrep guard is name- and path-based and is easy to sidestep (MAJOR-2). The test mirror still models the removed API (`Tests/AudioViewModelTests/MockAudioEngine.swift:35-58`). |
| R11 | Don't enable `NonisolatedNonsendingByDefault` | **Met** | Not enabled (`Package.swift`). |

---

## 2. Architecture and elegance

**One snapshot type?** Yes, one type: `EngineSnapshot` (`EngineSnapshot.swift`). It is not one publication, though. `snapshot()` assembles it on read from four sources:
- the channel (transport);
- `stateLock` (signal path);
- the meter reference (loudness);
- an atomic behind the AU borrow (EQ rate).

So transport and signal path can come from different instants. The view model needs no cross-field consistency today, so this is fine for R1. The natural next step is for the clock to publish the whole `EngineSnapshot` through one `SnapshotChannel`, after which main never takes `stateLock` at all. Nothing in this branch blocks that step.

**One owner of the AU handles?** One writer, `setDspAudioUnit`, but two fields (`dspAudioUnit`, `dspAUAudioUnit`; `AudioEngineBridge.swift:59-64`) that have to stay paired. Both are internal `var`s, so a future direct assignment can desync them, and the EQ would then publish to a dead AU. MINOR-6: store them as one optional value, `EffectsUnit { avUnit; au }`.

**A clear rule for which thread may call what?** It exists, but it is spread over four doc comments:
- the protocol's MAIN-THREAD RULE;
- the leaf-lock note in SharedState;
- the TransportClock header;
- the `withPureEngine` doc.

There are also runtime tripwires: `dispatchPrecondition` on `sampleTransport`, `withPureEngine` and `liveEnhancedPosition`. All 9 call sites were checked and satisfy them. These preconditions trap in **release** builds too, which turns a freeze-class bug into a crash. That is a reasonable choice, but it should be stated. There is no queue-ownership table anywhere (see §6).

**Protocol: cleaner or leakier?** Cleaner:
- Six synchronous reads collapse into `snapshot()`.
- `setDeviceVolume` becomes a fire-and-forget `requestDeviceVolume`.
- The leaky "the view model must poll so Pure reaps" contract is now internal to the engine.

One small leak: the UI's "knob hold" concern now rides in engine state as `SignalPathInfo.deviceVolumeSet`. It is defensible, because the view model needs to tell its own answer from an external change. The name reads like a `Set`; `deviceVolumeAnswer` would be clearer.

**Kit boundary.** `TransportSnapshot` + `SnapshotChannel` in PlaybackQueueKit is acceptable. The app target cannot be imported by tests, PlaybackQueueKit already holds transport-ish VM logic (ResumePoint, SeekRoute, PlayThroughTracker), and its tests already live in `AudioViewModelTests`. Removing `import PlaybackQueueKit` from `AudioPlaybackEngine.swift` is correct: the protocol names only `EngineSnapshot`, an app type, so the layering is app → Kit, never the reverse.

`SnapshotChannel` is a nice structural idea. It has no closure API, so no caller work can ever run under its lock. Two nits:
- "Channel" suggests a message stream; `LatestValue<T>` would be clearer.
- It is a generic concurrency primitive living in a queue-domain Kit.

**Semgrep vs type-level guarantee.** The guard does not cover the bug class that actually happened. The original freeze was `engine.currentPlaybackPosition()`, a synchronous protocol member whose body touched AVFAudio inside the bridge. The view model never named an AVFAudio type, so this regex would not have caught it. The probe (`scratchpad/arch-sidestep`) shows these are NOT caught:
- `AVAudioUnitEQ.bands[0].gain` (`\bAVAudio…Unit\b` fails before "EQ");
- `DeviceHardwareVolume.read(id)` (HAL behind a wrapper);
- a blocking synchronous protocol member;
- any file outside the allow-list (`MenuBarView.swift`, `ContentView.swift`, `TabContentView.swift`, `AdaptiveSound.swift`, `PlaylistsModel+*.swift`).

The real boundary is the `AudioPlaybackEngine` synchronous surface: the view model holds only `any AudioPlaybackEngine`. That surface is small:
- `snapshot`;
- the publish methods;
- `requestDeviceVolume`;
- `currentOutputDeviceID`;
- `setPin…`;
- the spectrum and monitor reads.

A full type-level guarantee would be a custom global actor whose executor is engineQueue (`DispatchSerialQueue` is a `SerialExecutor` on macOS 14+). The hardware-touching helpers would be `@EngineActor`, so main could only reach them with `await`. That is not cheap: the bridge is GCD-callback-heavy and would need `assumeIsolated` everywhere. It belongs in the later cleanup.

Cheap now: see MAJOR-2.

**Swift 6.** No new `@unchecked Sendable`, `nonisolated(unsafe)` or `assumeIsolated`:
- `SnapshotChannel` is checked-`Sendable` (`OSAllocatedUnfairLock<Value: Sendable>`).
- The atomics are `let Atomic<…>` (Synchronization), using named acquire/release, which follows the TSan rule.
- The new file uses `@preconcurrency import AVFoundation`, consistent with the other bridge files.

---

## 3. Findings

### BLOCKER
None.

### MAJOR-1: the transport snapshot updates only when a transport op ends, which widens stale windows. A Pure queue can stop at a cross-rate track boundary.

**Where:**
- `+Playback.swift:34,37` and `+PureMode.swift:180,199,225`: `sampleTransport()` runs at the end of the op body.
- The clock cannot run during a body, because both run on engineQueue.
- `AudioViewModel+SpectrumTimer.swift:100-124`: the `transport.ended` branch, ending in `stopAtEndOfQueue()`.
- `PureModeBridge.cpp:143-178`: `ended_` is reset only at `setCurrent`, after the old HAL teardown, the open and the capability query.

**Story.** Pure, mixed-rate queue (or shuffle). Track A ends and B cannot be armed (rate change).
1. Tick 1 sees `ended`, clears `pendingNextIndex` and calls `startPlayback()`. `isPlaying` stays true during the start.
2. The snapshot keeps `ended == true` until the **end** of the startAudio body: HAL teardown with rate restore and hog release, then open, then configure at the new rate, then start. That is easily 100s of ms, several ticks.
3. Tick 2 takes the else branch and calls `stopAtEndOfQueue()`, so `performStop` races the in-flight start.
4. The result is either the album stops, or the UI says Playing while Pure is silent (the start Task sets `isPlaying = true` last).

**History.** This window already existed: before the fix, the live read saw the old session's `ended_` until `setCurrent`. The fix extends it by the configure-plus-start time. VM-AA-RGAP-1 hides it, because its tick 2 sets `isPlaying = false` in the mirror and the test never asserts `isPlaying` (`AutoAdvanceReconfigureGapTests.swift:28-35`, `MockAdvanceController.swift:119-126`).

**Same mechanism, cosmetic:** while playing, the scrubber jumps back to the pre-op position after a scrub or a Next, for the length of the op body. This matters most for a Pure seek (pause, decoder seek, start) and a Bluetooth `engine.start()`. Before the fix the window covered only the queue latency, or the body up to `player.stop()`.

**Fix (small, view model only):**
- Add a `transportOpsInFlight` counter. Increment it synchronously in `startPlayback` and `seek(to:)` before the `Task`; decrement it after the awaited engine call (and after `primeGaplessPipeline` for starts).
- While it is > 0, `tickTransport` skips following the playhead and skips the gapless/ended block. `interrupted` handling stays live.
- Assert `isPlaying` in VM-AA-RGAP-1 tick 2, and update the mirror to `snapshot()` with a lagging-snapshot test.

An engine-side alternative is an epoch or "settled" flag on `TransportSnapshot`. It needs more machinery for the same result.

### MAJOR-2: the stated guard is shallow, and the regression test the audit asked for is absent

**Where:** `.semgrep.yml:62-94`; `Tests/AudioViewModelTests/TransportSnapshotTests.swift`.

**Story.** In a few months, someone adds a synchronous `engine.currentRoute()` that reads `outputNode.outputFormat`, or a `MenuBarView` helper that calls `DeviceHardwareVolume.read`. Semgrep passes and the gate is green, and the next headphone switch-off beach-balls again.

**Fix:**
- Invert the path filter: everything under `Sources/AdaptiveSound/**` except `AudioEngineBridge*.swift`, `PureModeSession.swift`, `LoudnessMeterHandle.swift` and `Spectrum/`.
- Widen the regex to `AVAudio\w*(Node|Engine|Unit\w*)\b|DeviceHardwareVolume\.|AudioUnit(Get|Set)Property`.
- Fix the message, which names the removed `transportSnapshot / currentSignalPath`.
- State in the commit/PR that the load-bearing guarantee is "the `AudioPlaybackEngine` synchronous surface is copy-or-hand-off only", and list that surface in the protocol doc.
- Record R10's engine-lock-held regression test as a tracked follow-up. It needs the bridge in a library target (tests cannot import the executable) or a Verify* executable that compiles the bridge sources. Until then, the acceptance test is the founder's live switch-off repro with `sample` showing main idle.

### MINOR
1. **Stale comments state the OLD lock rule.** These are the dangerous ones:
   - `+PureMode.swift:170-172`: "Pure seek borrows the handle UNDER stateLock so a concurrent device-loss teardown (configChangeQueue)…".
   - `PureModeSession.swift:17-18`: "engineQueue / configChangeQueue or borrowed under stateLock".
   - `+SharedState.swift:9,151-152`.

   A reader who follows them could add a configChangeQueue caller, which is now a release trap. About a dozen more references name removed APIs:
   - `+Gapless.swift:6,32,141,171,176`
   - `AudioEngineBridge.swift:68,134,152`
   - `AudioViewModel+AutoAdvance.swift:9`
   - `AudioViewModel.swift:351`
   - `AudioViewModel+Playback.swift:105`
   - `+Playback.swift:178`
   - `+PureMode.swift:205`

   Fix them in this PR.
2. **The test mirror claims "matches AudioPlaybackEngine exactly"** (`MockAudioEngine.swift:35-58`). It now models live reads, not a snapshot.
3. **`pause()` ignores the `AudioOutputUnitStop` status** (`HALOutputEngine.mm:483-492`). If the stop fails on a dying device, the seek can run concurrently with `pullFloat`, which violates the decoder's precondition. On failure, return without seeking.
4. **Pure resume now audibly plays the intro for ~50-150 ms**, because resume is start-then-seek (`AudioViewModel+Playback.swift:58-63`). Before the fix it was silent; Enhanced already behaves this way. Follow-up: `startAudio(…, startAt:)`.
5. **`requestDeviceVolume` is an unbounded FIFO** of 5 HAL calls per drag sample. Against a stuck device it builds a backlog, then replays stale levels. Make it latest-wins: keep the pending level in an atomic and run one drain.
6. **The paired AU fields can desync.** Store one value (see §2).
7. **`gaplessTransitionCount &+= 1`** (`+Gapless.swift:181`) is a non-atomic read-modify-write through a computed property. It is correct only because there is one writer; use `wrappingAdd`.
8. **The 30 Hz clock is always on** and takes the engine lock even when idle (`+TransportClock.swift:27-36,82-85`). Gate `liveEnhancedPosition` on `enhancedPlayIntent`, or suspend the clock while stopped.
9. **`loudnessMeter` is read unsynchronised in `snapshot()`** (pre-existing S1-E, a use-after-free window at quit or retry). The `EngineSnapshot` doc overclaims; reword it, or fix it in the cleanup.
10. **`setPureNextTrack` blocks a global worker in `engineQueue.sync`** (`+Gapless.swift:117`). Prefer `engineQueue.async` plus resuming the continuation.

---

## 4. Pre-mortem (the fool)

Steelman: the fix makes the main thread independent of every audio lock by publishing copies, and it closes all audit paths, not only the reported one. Granted. Now assume it is a month after R1 and something broke.

1. **"Pure stopped after the first track / says Playing but silent."** This is MAJOR-1.
   - **Path:** the stale `ended` during the reconfigure-gap start leads to `stopAtEndOfQueue`.
   - **Likelihood:** medium-high on Pure with a mixed-rate library or shuffle.
   - **Early sign:** a `playbackEnded — no next track, stopping` log line right after `advancing to queued track`.
2. **"It froze again" through indirection.** A new synchronous protocol member, a wrapper helper, or a file outside the semgrep allow-list reaches AVFAudio or the HAL from main.
   - **Likelihood:** medium over months, because nothing type-level or test-level guards it.
   - **Early sign:** none until a device change.
3. **"It froze again" through `stateLock`.** `mutateSignalPath { … }` and `withStateLock { … }` still accept arbitrary closures. That is exactly how `ConfigChange.swift:78` happened, and main takes this lock every tick.
   - **Likelihood:** low-medium.
   - **Mitigation:** narrow the API to value setters, as `SnapshotChannel` does.
4. **"The scrubber jumps back when I scrub on my DAC / press Next on AirPods."** The position stays stale for the length of the op body.
   - **Likelihood:** high.
   - **Severity:** cosmetic, but it is the kind of polish S10.8 is about.
   - Same fix as MAJOR-1.
5. **"Pure resume blips the intro" or "a Pure scrub crashed once on unplug."**
   - Now that Pure seek works, start-then-seek is audible (MINOR-4).
   - If `AudioOutputUnitStop` fails, the seek races `pullFloat` (MINOR-3).
   - **Likelihood:** medium for the blip, low for the race.

Checked and unlikely:
- **"EQ stopped applying":** `setDspAudioUnit` is the only writer, and reconfigure re-widths the graph without re-instantiating the AU.
- **"Crash on quit":** the clock is cancelled first in the teardown, on engineQueue; it captures `[weak self]`; all preconditions hold.

**Inversion: what assumption, if wrong, breaks the whole approach?**
- The main thread reaches the audio side only through the `AudioPlaybackEngine` synchronous surface, and every member of that surface is a copy or a non-blocking hand-off. Only doc comments and a regex enforce this.
- Corollary: main must never wait on engineQueue. That matters more now, because the clock makes engineQueue an engine-lock contender 30×/s. A single future `engineQueue.sync` from a synchronous member would re-create the freeze.

---

## 5. Scope and risk

- **Size is justified.** A playhead-only fix would still freeze one call later (S1-B `.auAudioUnit`, S2-A HAL), so the AU-handle and Master Gain commits belong to the freeze fix.
- **Out of scope: the Pure seek C++ change (9de5f3e).** It fixes a separate audit §4 side finding.
  - It is low risk: `AudioOutputUnitStop`/`Start` is the canonical pause, and the old path was broken anyway.
  - But no harness covers `pureModeEngineSeek`; it needs by-ear verification on a DAC; and it newly exposes the resume blip.
  - Recommend its own PR, verified by the founder by ear.
- **Split:**
  - Freeze PR: d577eb0, 4a19c1f, a5710e4, ec9a974, 93ecf7e, 90a62e8, 979166 (plus the MAJOR/MINOR fixes). Squash the churn: 4a19c1f samples on resampleQueue and 93ecf7e replaces that with atomics; `transportSnapshot()` is renamed to `snapshot()`.
  - Pure seek PR: 9de5f3e.
- **Release risk is otherwise low.** The behavioural changes on the hot path are:
  - the device-loss path drops `player.stop()`, with the schedule cleared at the next start;
  - the intent and counters move from `resampleQueue.sync` to atomics. The barrier semantics are preserved, because `stopEnhancedResampler` still does `resampleQueue.sync`.

## 6. Docs

Yes. Add a short **"Threading rules (app ↔ engine)"** section to `docs/architecture/architecture.md`. This is non-recoverable rationale, so the docs rule allows it. Contents:
- **Main:** reads only `snapshot()` and calls only non-blocking intent sinks; never `.sync` to a bridge queue.
- **Queue ownership:**
  - engineQueue: transport ops, the clock, every Pure C-ABI call;
  - resampleQueue: resampler and seam state;
  - configChangeQueue: device events;
  - deviceVolumeQueue: Pure device volume.
- **`stateLock`:** a leaf lock, O(1), no callouts, no last-release.
- **Completion handlers:** async-only.
- **Why:** one engine-wide AVFAudio lock is held across HAL waits. Point to the audit's experiments and to forum thread 770787.
