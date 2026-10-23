> **Status (2026-10-13):** findings S1-A…S3 fixed (rules: [architecture.md, "Threading rules (app ↔ engine)"](architecture.md#threading-rules-app--engine); regression test `make main-thread-stall` reproduces Experiments 1–2) and the Pure-seek side finding fixed — both **merged in PR #86** (`dd5e02d`; the Pure-seek fix is `8db09c8` + `dd5e02d`); `accruePlayThrough` is deferred past R1. The `scratchpad/audit-mt/` artifacts named below were not kept. **The file:line references below are as of `457f895`, before the fix** (e.g. the bridge's `currentPlaybackPosition` is gone; the tick now reads `snapshot()`).

# Audit: every path where the main thread can wait on audio

**Scope.** `origin/main` @ 457f895. Local `main` @ 32adbb1 differs only in docs, so `Sources/` is identical. Branches `*main-thread-stall*` and the worktree `g-fix-stall` were not looked at.

**Method.**
- Read the code end to end: the bridge, the view models, the UI, the C-ABI and the C++ HAL/decoder code.
- Ran two standalone experiments in `scratchpad/audit-mt/`. Both use offline manual rendering, so no audio device is used.
- A research subagent did the web research. I re-opened the load-bearing quotes myself: the local macOS 26 SDK headers, forum thread 770787, and the SFB, Cog, AudioKit and Aural sources at pinned commits.

---

## 0. The mechanism (proven): one engine-wide lock

Every AVFAudio accessor on any node attached to an `AVAudioEngine` takes one engine-wide recursive mutex: `AVAudioNodeImplBase::GetAttachAndEngineLock()`. `stop`, `start`, `pause` and `connect` hold that mutex for their whole duration, including any time they spend waiting on the HAL.

### Experiment 1 (`nodelock.swift`)

Setup:
- Manual offline rendering mode.
- A scheduled buffer whose completion handler sleeps 2 s.
- `player.stop()` called on a background queue.

`stop()` runs the completion handler synchronously inside `AVAudioPlayerNodeImpl::StopImpl → ~BufferCommand → CallCompletionHandler` while holding the lock. The `sample` excerpt is in `audit-mt/sample-excerpt.txt`.

Each probe below was made from the main thread in its own process:

| Main-thread call while another thread is inside `player.stop()` | Waited |
|---|---|
| `player.isPlaying`, `.lastRenderTime`, `.playerTime(forNodeTime:)` | 1.70 s, BLOCKED |
| `player.volume` get/set, `.outputFormat(forBus:)`, `.scheduleBuffer` | 1.70 s, BLOCKED |
| **a different node**: `other.isPlaying`, `other.lastRenderTime` | 1.70 s, BLOCKED |
| `engine.isRunning`, `engine.mainMixerNode`, `engine.outputNode.outputFormat`, `mixer.outputVolume` | 1.70 s, BLOCKED |
| `mixer.installTap` / `removeTap` | 1.70 s, BLOCKED |
| **`AVAudioUnit.auAudioUnit` of an attached unit**, `auAudioUnit.outputBusses[0].format`, `AVAudioUnitEQ.bands[0].gain = …` | 1.70 s, BLOCKED |
| `auAudioUnit` of a unit **not attached** to the engine | 0.000 s |
| `isPlaying` on a node of a **different engine** | 0.000 s |

The main thread's stack was `-[AVAudioPlayerNode isPlaying] → AVAudioNodeImplBase::GetAttachAndEngineLock()`, a try-lock/sleep spin on a `std::recursive_mutex`. Developer Forums thread 770787 shows the same frame, and its poster concludes: "All these calls invoke AVAudioNodeImplBase::GetAttachAndEngineLock internally" (https://developer.apple.com/forums/thread/770787).

### Experiment 2 (`startlock.swift`)

Setup:
- A custom v3 `AUAudioUnit` whose `allocateRenderResources` sleeps 2 s.
- The unit is instantiated with `AVAudioUnit.instantiate`, exactly as the app does it.

While `engine.start()` runs on a worker, `other.isPlaying`, `slowUnit.auAudioUnit` and `engine.isRunning` each block on main for about 1.7 s. The worker's stack is `-[AVAudioEngine startAndReturnError:] → AVAudioEngineImpl::Initialize → AVAudioEngineGraph::Initialize → … → allocateRenderResources` (`audit-mt/sample2-excerpt.txt`).

So `engine.start()` holds the engine lock while it initialises the graph, and that includes the AUHAL output unit's work against the device. The experiment also showed that `AVAudioUnit.instantiate`'s completion for an in-process v3 AU runs **on the calling queue**. The app's graph build therefore runs on `engineQueue`, not on main.

### Apple's header (local MacOSX 26 SDK)

`AVAudioPlayerNode.h:74-76`:
> "Setting or getting properties on an AVAudioPlayerNode while the AVAudioEngine is running requires some synchronisation between the calling threads internally."

`AVAudioPlayerNode.h:145-146`:
> "a player should not be stopped from within a completion handler callback because it can deadlock while trying to unschedule previously scheduled buffers."

`AVAudioEngine.h:893-895`:
> "the engine must not be deallocated from within the client's notification handler because the callback happens on an internal dispatch queue and can deadlock while trying to synchronously teardown the engine."

### Consequence

The bug's `sample` showed main stuck in `isPlaying` while `stop()` was stuck in `GetOutputPresentationLatency → AudioUnitGetProperty` on the HAL device mutex. Put that together with the experiments: **any main-thread call into any AVFAudio object of the live engine waits as long as any engine-lock holder waits on the HAL.** That includes `.auAudioUnit` on the effects AU.

The engine-lock holders in this app, none of them on main, are:

| Holder | Queue |
|---|---|
| `player.stop()`, `engine.stop()` in `stopPlaybackAfterDeviceLoss` | engineQueue |
| `stopEnhancedPlayback` (pause, stop, entering Pure) | engineQueue |
| `playFile` → `player.stop()`, `engine.start()` (every Enhanced start or resume; a Bluetooth output start is slow) | engineQueue |
| `seekEnhancedResampler` / `seekEnhancedBestEffort` → `player.stop()` (user seek) | engineQueue |
| Re-establish → `engine.start()`, then seek → `player.stop()` (every followed or re-asserted route change) | configChangeQueue |
| `reconfigureGraph` → `engine.pause()` / `start()` | engineQueue |
| Every resampleQueue `scheduleBuffer`, `scheduleFile`, `lastRenderTime`, `outputFormat`, `.auAudioUnit` | resampleQueue |
| Very likely AVAudioEngine's own internal stop on a device change. The header says the engine "stops itself" before posting the notification. | AVFAudio internal |

---

## 1. Ranked path list

Severity scale:
- **S1**: 20 Hz timer path.
- **S2**: a user action or an event that coincides with a route change.
- **S3**: launch or quit only.

"Can block for seconds" asks whether the path can block during a route change or device teardown.

### S1-A. Tick → playhead → AVAudioPlayerNode (the reported bug)

- **Entry:** `AudioViewModel+SpectrumTimer.swift:35-41` (transport `Timer`, 20 Hz, `RunLoop.main`) → `tickTransport` :56 → `pollPlayhead` :136 → `AudioEngineBridge+Playback.swift:254 currentPlaybackPosition` → :266-268 `playerNode.isPlaying`, `.lastRenderTime`, `.playerTime(forNodeTime:)`.
- **Blocks on:** the engine lock. Its holders are listed in §0.
- **Seconds?** **YES.** Proven by the bug's sample and by Experiment 1. Device loss, the re-establish `player.stop()`, and `engine.start()` on Bluetooth all qualify.
- **Runs when:** the view model is playing and not paused.
- **Also on this path:**
  - `withPureEngine` takes `stateLock` (see S1-C).
  - `playerNode` is read with no synchronisation. `playerNodeRef` is not used, so this is a data race with `setPlayerNode(nil)`.

### S1-B. Tick → `refreshEQDesignRate` → `AVAudioUnit.auAudioUnit` (not yet reported; the most important item)

- **Entry:** `tickTransport` → `pollEngineReadouts` (`SpectrumTimer.swift:151-164`) → :163 `refreshEQDesignRate()` (`AudioViewModel.swift:397-402`) → `engine.eqSampleRate()` (`AudioEngineBridge+EQControl.swift:40-44`) → `dspAudioUnitRef` (`stateLock`) → **:42 `unit.auAudioUnit`** → the C-ABI `eqDesignSampleRate`. That last call is an atomic load and is harmless.
- **Blocks on:** the engine lock (Experiment 1, the `auAudioUnit` row; Experiment 2).
- **Seconds?** **YES**, for the same holders as S1-A.
- **Runs when:** **unconditionally on every tick: playing, paused, interrupted or idle.**
- **Consequence:** a fix that only snapshots the playhead still freezes the main thread. It would freeze one call later, in `refreshEQDesignRate`.

### S1-C. Tick → `stateLock` (os_unfair_lock) held by a thread doing HAL, AVFAudio, join or dealloc work

**Entries on main**, every tick:
- `currentSignalPath()`, unconditional (`SpectrumTimer.swift:156` → `loadSignalPath`).
- `currentPlaybackPosition` (`withPureEngine`, then the base and last-known position).
- `eqSampleRate` (`dspAudioUnitRef`).
- `trackTransitionCount` and `playbackEnded` (`withPureEngine`).
- On user actions: `setPinPlaybackToSelectedDevice`, `currentOutputDeviceID`, and `adoptOutput` → `currentSignalPath`.

**Slow holders:**

1. **Pure seek holds `stateLock` across HAL teardown.**
   - `AudioEngineBridge+PureMode.swift:174`: `withPureEngine { pureModeEngineSeek }` on engineQueue.
   - `PureModeBridge.cpp:208` `engine->stop()` = `HALOutputEngine::teardown()` (`HALOutputEngine.mm:889`). That runs `AudioOutputUnitStop`, `AudioUnitUninitialize`, `AudioComponentInstanceDispose`, a nominal-rate restore (`AudioObjectSetPropertyData`) and a hog release.
   - Then `active->seek()`: a decode-thread join plus a file seek.
   - Then `engine->start()`.
   - **Seconds?** **YES** if the device is going away (the same HAL device mutex). It costs tens to hundreds of ms normally, because hog release and rate restore are slow.
   - **Triggers:** every Pure scrub, and every Pure resume-from-pause (`startPlayback(resumeFrom:)` → `engine.seek`).
   - **Severity:** S1, since the tick waits; the trigger itself is S2.
2. **An AVFAudio call under the leaf lock.** `AudioEngineBridge+ConfigChange.swift:78`: `mutateSignalPath { $0.achievedSampleRate = engine.outputNode.outputFormat(forBus: 0).sampleRate }`.
   - The closure runs inside `withStateLock`, so configChangeQueue holds `stateLock` while it waits on the engine lock and the output-device format.
   - This is the **only** violation of the leaf-lock rule in the file, and it chains S1-C into the engine lock.
   - **Seconds?** **YES** on a route change.
3. **Decode-thread joins under the lock.** Both run on `DispatchQueue.global()`:
   - `withPureEngine { pureModeEngineClearNextTrack }` (`+Gapless.swift:97` → `GaplessSource::clearNext` → `FileDecodeSource` dtor → `joinDecodeThread`).
   - `pureModeEngineArmOpenedNextTrack` (`:114`). On a needs-reconfigure or refused arm, the just-opened decoder is destroyed inside the call and its live decode thread is joined.
   - **Seconds?** **UNLIKELY** on local disk, where a join is bounded by one `readChunk`. **YES** on a slow network or spun-down volume.
   - **Triggers:** queue edits, Pause, Stop, and `setNextTrack(nil)` on device loss.
4. **Teardown and re-init release objects inside the lock.** `resetGraphStateAfterShutdown` (`+Lifecycle.swift:146-149`) → `setDspAudioUnit(nil)`, `setAvEngine(nil)`, `setPlayerNode(nil)`.
   - The assignment drops the last reference inside `withStateLock`.
   - The AU's dealloc runs `Realizer::shutdown()`, a `dispatch_sync` barrier.
   - The `AVAudioEngine` dealloc disposes the IO unit, which is HAL work.
   - **Seconds?** **UNLIKELY**.
   - **Triggers:** `retryInitialization` (the engine-not-ready self-heal) and quit. The 20 Hz timers are still live during both.
5. **The main thread reaps on Pure.** `pureModeEnginePollTrackAdvance` → `reapRetired()` joins a retired decode thread **on main**. It is called from the tick and from `primeGaplessPipeline` (`AudioViewModel+Playback.swift:108`).
   - **Seconds?** **NO** in practice: the retired source has already hit EOF and its thread has exited. It is still main-thread join work by contract.

### S1-D. Tick → `resampleQueue.sync` (Enhanced) → AVFAudio and file I/O on resampleQueue

- **Entry:** `tickTransport` :85 `trackTransitionCount()` (`+Gapless.swift:144`) and :95 `playbackEnded()` (:155). Also `primeGaplessPipeline` on main after every start.
- **Work that holds resampleQueue:**
  - Resampler iterations (`+EnhancedResamplerSeam.swift:88` `AVAudioFile.read`, then convert, then :69 `player.scheduleBuffer`, which takes the engine lock).
  - The prime inside `startEnhancedResampler`'s `resampleQueue.sync` (`+EnhancedResampler.swift:97-101`; three read/convert/schedule rounds). It is called from engineQueue (play, seek) and configChangeQueue (re-establish).
  - Seam handlers:
    - `AVAudioFile(forReading:)` of the next track (`+GaplessRoll.swift:154`).
    - `player.outputFormat` (:39, :77).
    - `scheduleFile` (:207).
    - `bumpTransitionCount`, which calls `lastRenderTime` and `playerTime` (`+Gapless.swift:202-203`) and then `trackBecameAudible` → `withLoudnessAU` → `.auAudioUnit` (`+TrackLoudness.swift:57`).
- **Seconds?**
  - **YES** for file I/O at a gapless seam on a network or sleeping volume. Opening the next file can take seconds and the tick waits the whole time.
  - **POSSIBLE** for the engine lock, when a resampleQueue block is mid-AVFAudio call while another thread holds the lock. One case is a re-establish prime while the engine lock is held elsewhere.
  - In the device-loss flow it is mostly avoided: the generation bump runs before `player.stop()`, so later iterations bail before `scheduleBuffer`. That protection is incidental, not designed.
- **Runs when:** the view model is playing.

### S1-E. Not blocking, but unsynchronised reads on the main tick (correctness)

- `readSpectrumBands` (`AudioEngineBridge.swift:280`) reads `spectrumAnalyzer`.
- `currentLoudness` (:303) reads `loudnessMeter`.
- `MonitoringViewModel.tick` (`UI/Monitoring/MonitoringViewModel.swift:67-79`) → `monitorChannelCount` and `readMonitorBands` read the `beforeAnalyzers` / `afterAnalyzers` arrays.

All of these are written on engineQueue (allocation, reconfigure resize, teardown) with no synchronisation. The payload read is lock-free (`SpectrumDoubleBuffer` uses `Atomic`; the loudness readout reads C++ atomics), so there is no stall. The references themselves are data races that can become a use-after-free at teardown.

### S2-A. Master Gain on Pure → HAL on main

- **Entry:** slider → `AudioViewModel+MasterGain.swift:33` `engine.setDeviceVolume` → `+MasterGain.swift:41-47`.
  - `DeviceHardwareVolume.set` makes two HAL calls: `GetPropertyData` (range) and `SetPropertyData` (dB).
  - `DeviceHardwareVolume.read` makes three: `HasProperty`, `IsPropertySettable`, `GetPropertyData`.
  - That is five synchronous HAL calls per drag sample.
- **Also on main:** the volume listener is registered on **`DispatchQueue.main`** (`+MasterGain.swift:57-60`). Its block runs `DeviceHardwareVolume.read`, three HAL calls, on main for every volume change on that device.
- **Seconds?** **YES** if the device is mid-teardown, for example Pure on a USB DAC or Bluetooth device that is disappearing. HAL property calls are synchronous mach round-trips to coreaudiod (JUCE forum: main thread "blocks forever in … AudioObjectHasProperty … HALC_ProxyObject::HasProperty … mach_msg"). The listener can fire at exactly that moment.
- **Not a problem:** the slider's 20 Hz display reads `signalPath.deviceVolume` from the snapshot, with no HAL call.

### S2-B. EQ / Intensity / Crossfeed / transport publishes → `.auAudioUnit` on main

- **Entries:**
  - `EQViewModel.publish` (`EQViewModel.swift:134-137`) → `AudioViewModel.publishEQ` → `+EQControl.swift:28`. It fires on every pointer sample of a drag, on `onEngineReady`, and on `outputDidChange`.
  - `intensity` didSet → `+IntensityControl.swift:28`.
  - `crossfeedEnabled` / `crossfeedStrength` didSet → `+CrossfeedControl.swift:36`.
  - `selectedDevice` didSet (`AudioViewModel.swift:75-80`) → `publishOutputTransport` (`+EQControl.swift:50`) **and** `onOutputIdentityChanged` → EQ `outputDidChange` → `publishEQ`.
  - `adoptOutput` (`AudioViewModel+Devices.swift:78-87`): it sets `selectedDevice` and auto-disables crossfeed on a non-headphone output, which hits two or three of the publishes above.
- **Blocks on:** the engine lock.
- **Seconds?** **YES.** The `refreshDevices` / `adoptOutput` path runs *because* the route changed. In follow and re-assert flows, configChangeQueue's re-establish (`engine.start()`, `player.stop()`) can be holding the engine lock at that moment.
  - In the pure device-loss flow, `refreshDevices` awaits `enumerateOutputDevices`, which is queued on engineQueue *behind* the stuck stop. So it lands after the stop. The picker is late by about 7 s, but the main thread is not blocked.

### S2-C. Settings, transport and picker actions → `stateLock`, or waiting behind engineQueue

- **What is synchronous on main:** the pin toggle → `setPinPlaybackToSelectedDevice`, and `adoptOutput` → `currentSignalPath`. Both take `stateLock` only, so they inherit the S1-C holders.
- **What only waits:** play, pause, stop, seek, next, select device and refresh devices are all `async` and hop to engineQueue. The main thread is never blocked. They do queue behind any stalled engineQueue work, so UI actions are late but not frozen.
- **The crossfeed headphone check** (`deviceIsHeadphones`) is a pure model read. Its side effect is the S2-B publish.

### S3. Launch and quit

- **Launch:**
  - `AudioViewModel.init` → `eqSampleRate()`: the AU is still nil, so it returns 48000 with no AVFAudio call.
  - `initializeEngine` is async. The graph build runs on engineQueue, because the instantiate completion runs on the caller's queue (Experiment 2).
  - `publishPlaybackIntents` then makes three `.auAudioUnit` calls on main (see S2-B). The engine has not started yet, so this is unlikely to block.
- **Quit:** `AppDelegate.applicationShouldTerminate` → `.terminateLater` plus an async teardown. There is no `applicationWillTerminate`. The main thread never blocks synchronously.
  - The 20 Hz timers stop only inside `AudioViewModel.shutdown()` (`+Lifecycle.swift:130`), *after* `flushPendingOrders`, `libraryModel.shutdown` and `mirrorQueueNow`. Until then, ticks keep contending with the teardown (S1-B, S1-C(4)).
  - A quit during a device teardown waits on the HAL. The quit hangs, but the UI stays live.

### Checked and clean

- Tap blocks (`+Graph.swift:136-215`) make no engine API calls.
- The Realizer C-ABI publishes take a slot mutex (O(1)) plus `dispatch_async`. `eqDesignSampleRate` is an atomic load.
- `TrackLoudnessAnalyzer` uses `AsyncStream` and does not block.
- The `AVAudioFile` opens in `TrackInfoCard` and `refreshDuration` are detached.
- NowPlaying, MenuBar and the Settings views only read the model.
- The `AVAudioEngineConfigurationChange` observer (`queue: nil`) only does `configChangeQueue.async`.
- Completion handlers only do `resampleQueue.async`. That matters because `stop()` runs them synchronously under the engine lock (Experiment 1).
- `OutputDevicePolicy` is pure.

### Off-main stalls that delay the UI (no freeze)

- engineQueue is serial. `enumerateOutputDevices`, `selectDevice`, `startAudio` and `seek` all queue behind a 7 s stop.
- configChangeQueue makes HAL reads (`isDeviceAlive`, `getDefaultOutputDeviceID`, `selectOutputDeviceC`) against a dying device.
- `registerOutputDeviceListeners` and `unregisterOutputDeviceListeners` run `configChangeQueue.sync` from engineQueue, so init and shutdown wait on those HAL reads.

---

## 2. What the field does

Every source below was opened in this session.

- **SFBAudioEngine** (sbooth, 9ed712d) uses an `AVAudioSourceNode` that pulls its own ring buffer; there is no AVAudioPlayerNode.
  - The render block counts frames. An events thread publishes a `TransportSnapshot`, and `playbackTime()` reads it lock-free (`loadTransportSnapshot()`, `AudioPlayer.h:534-549`).
  - `isPlaying` is a cached flag (`AudioPlayer.h:284` "Cached value of `engine_.isRunning`"; :510 `bits::has_all(flags, Flags::engineRunning | Flags::playing)`).
  - Config change is handled on AVFAudio's internal queue under its own `engineMutex_`.
  - https://github.com/sbooth/SFBAudioEngine/blob/9ed712d4ec6a38c0b14015175989100ffb3e09ba/Sources/CSFBAudioEngine/Player/AudioPlayer.h
- **Cog** (fb2ed48, new engine) runs a main-thread `Timer(timeInterval: 0.02 …)` (`PlaybackEngine.swift:423`).
  - The timer reads `cog_ring_read_position(pump.ring)` (:919, :1027), an `atomic_load` (acquire), minus `latencyFrames` cached at format time (:1043).
  - The tick makes no HAL or AU calls. HAL listeners run on a private queue.
  - https://github.com/losnoco/Cog/blob/fb2ed48de8358f858732f8b04f290914578f5fd5/Audio/Engine/Facade/PlaybackEngine.swift
- **VLC** CoreAudio pushes timing out of the render callback (`aout_TimingReport`) and queries latency once at start.
  - Its commit c8cd58f fixed "a deadlock between the render callback and AudioUnitStop()" by caching latency instead of calling `AudioUnitGetProperty` per render.
  - https://github.com/videolan/vlc/commit/c8cd58f922afd512245ff812a3aa13093d0bee75
- **AVPlayer** (Apple's own model) pushes time to the UI with `addPeriodicTimeObserver(… queue: …)`.
  - https://developer.apple.com/documentation/avfoundation/avplayer/addperiodictimeobserver(forinterval:queue:using:)
- **Counter-examples with exactly our bug pattern:**
  - AudioKit `AudioPlayer` (`AudioPlayer+Playback.swift:157` `guard let nodeTime = playerNode.lastRenderTime …`).
  - Aural Player (`AuralPlayerNode.swift:58`, polled from a main-queue repeating task).
  - The forum 770787 poster replaced `playerNode.isPlaying` with an `atomic_bool` and a self-counted position.
- **Apple:**
  - Gives no general thread-safety statement for AVAudioEngine.
  - Gives no "never call the HAL on main" statement. Forum threads 758022 and 698490 ask and have no replies.
  - The `AudioHardware.h:382-389` listener queue doc says blocks are "dispatched asynchronously", except IO-context properties, which are "dispatched synchronously".

**In short:** the playhead and play state are app-owned values, fed from the render path or the app's own transport intent and read lock-free. Latency is cached. The UI timer never calls AVAudioPlayerNode, AVAudioEngine or the HAL.

---

## 3. What any correct fix must satisfy (the checklist)

1. **No AVFAudio on main, at all.**
   - The main thread must not touch any object attached to the live engine. That means not `isPlaying`, `lastRenderTime` or `playerTime`, and also not **`AVAudioUnit.auAudioUnit`**.
   - That covers `eqSampleRate` on the tick, `publishEQ`, `publishIntensity`, `publishCrossfeed`, `publishOutputTransport`, the publishes at engine-ready, and the publishes triggered by `adoptOutput`.
   - Capture the AU's opaque handle once, off-main, at instantiate time and keep it alive through the publish. Do not re-derive it from `AVAudioUnit` on main.
2. **No CoreAudio HAL calls on main.**
   - Move `setDeviceVolume` (set plus read-back) to a control queue.
   - Register the device-volume listener on a non-main queue that writes the snapshot.
3. **The tick reads only a published snapshot.** That covers the playhead, transition count, ended flag, interrupted flag, signal path, loudness and EQ design rate.
   - Use lock-free atomics, or a leaf lock whose every holder is O(1) with no callouts.
   - **No `.sync` from main onto any bridge queue.** Today `trackTransitionCount` and `playbackEnded` do `resampleQueue.sync`, and so does `primeGaplessPipeline`.
   - Use named-atomic acquire/release, not standalone fences (the project's TSan rule; SFB's seqlock uses the fence form).
4. **`stateLock`, or any lock main takes, is never held across:**
   - Pure C-ABI calls that stop, start or tear down the HAL engine, or join threads: `pureModeEngineSeek`, `ClearNextTrack`, `ArmOpenedNextTrack`, and the reap in `PollTrackAdvance`.
   - AVFAudio calls (`ConfigChange.swift:78`).
   - Object deallocation inside the closure (`setAvEngine(nil)`, `setDspAudioUnit(nil)`, `setPlayerNode(nil)`).
   - The Pure handle's lifetime needs a mechanism other than "lock across the call", such as shared ownership or a generation and a borrow. Pure's position, transition count and ended flag must be readable without that lock.
5. **The Pure reap moves off main.** The `PollTrackAdvance` reap joins a thread. Keep the "regular polling reaps" contract with a control-queue reaper.
6. **The Enhanced playhead does not come from the node at UI time.**
   - Acceptable sources: a render-side or tap-side frame counter, or the last good value published by a non-main sampler. Cache latency at start.
   - The gapless re-zero (base at the seam) and the seek base must keep their current contracts.
   - Any sampler that calls `lastRenderTime` must run on a queue that main never waits on. **resampleQueue does not qualify.**
7. **Every engine-lock holder is covered, not only `stopPlaybackAfterDeviceLoss`:**
   - re-establish (`player.stop()` and `engine.start()` on configChangeQueue);
   - user seek;
   - pause and stop;
   - every Enhanced `engine.start()` (slow on Bluetooth);
   - `reconfigureGraph`;
   - resampleQueue's AVFAudio calls.
8. **`interrupted` is published before any call that can block on the HAL.** Today it is set on configChangeQueue before the engineQueue stop; keep that. After seeing it, the view model must make no synchronous engine call.
9. **Completion handlers stay `async`-only.** `stop()` runs them synchronously under the engine lock, so they must never `.sync` onto resampleQueue or main, take a lock with callouts, or call `stop()` (Apple header :145).
10. **Tests:**
    - **Regression test:** hold the engine lock for 2–3 s, using the completion-handler-sleep or slow-`allocateRenderResources` technique in manual rendering mode (`audit-mt/*.swift`). Assert that `tickTransport`, `tickSpectrum` and the monitoring tick, plus `publishEQ`, `setMasterGain` and `adoptOutput`, each return in under ~5 ms.
    - **Static guard:** check that no AVFAudio or HAL symbol is reachable from `@MainActor` code.
11. **Do not enable `NonisolatedNonsendingByDefault` without re-auditing.** The bridge's `async` methods would then run their synchronous preludes on the main actor.

---

## 4. Side findings (outside the stall, found along the way)

- **Pure seek likely leaves Pure silent.** Not run; found by reading the code, please verify.
  - `pureModeEngineSeek` calls `engine->stop()`, which equals `teardown()`. That disposes the AUHAL and clears `initialized_` and `unit_`.
  - It then calls `engine->start()`, which returns false when `!initialized_ || unit_ == nullptr` (`HALOutputEngine.mm:458-476`). The result is ignored.
  - This affects Pure scrubbing and Pure resume-from-pause.
- **`accruePlayThrough` counts a stalled tick as heard time.** A 7 s freeze while `isPlaying` is still true counts 7 s of "heard" time even though the device was dead.
- **`currentPlaybackPosition` reads `playerNode` directly**, not through `playerNodeRef`. That is a data race with teardown.

## 5. Artifacts

All under `scratchpad/audit-mt/`:
- `nodelock.swift` (Experiment 1) and `startlock.swift` (Experiment 2).
- `sample-excerpt.txt` and `sample2-excerpt.txt`: the stacks showing `GetAttachAndEngineLock` and `startAndReturnError → Initialize`.
- `dl/`: the opened headers and sources.
