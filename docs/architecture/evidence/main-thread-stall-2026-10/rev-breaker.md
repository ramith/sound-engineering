# Breaker review: S10.8 G main-thread-stall fix

**Branch reviewed:** `sprint/s10-8-g-fix-main-thread-stall` @ 90a62e8 (8 commits on 457f895).

**Worktree:** `.claude/worktrees/review-breaker`, detached. The only local edits are an uncommitted harness plus a one-line hook, and nothing was committed.

**Artifacts:** everything is in `scratchpad/rev-breaker/`:
- `BreakerHarness.swift` and `hook.diff`.
- `run-*.txt` / `run-*.err` (latency runs) and `tsan-*.err`.
- `ended-advance.err`.
- `probes/rendertime.swift`.
- `semgrep/` (the planted violations).
- `swift-test-*.log`.

## Verdict

The freeze fix holds. I could not make the main thread wait on AVFAudio, the HAL or a bridge queue. I tested three kinds of lock holder and an emulation of a full device loss, all driving the real `AudioEngineBridge` and the real `AudioViewModel`, and every main-thread entry stayed at or below 0.54 ms.

The fix does add two MAJOR regressions, both on the new off-main transport clock path, plus several MINOR items.

## Harness (real code, offline only)

**How it runs.** `BreakerHarness.swift` is compiled into the real `AdaptiveSound` target as a DEBUG `AS_BREAKER=<mode>` hook. Run it as `.build/debug/AdaptiveSound`; it exits before the single-instance lock and the UI start.

**What it builds.** It uses the real bridge build path, `instantiateAndBuildGraph`, on an AVAudioEngine in offline manual-rendering mode. That gives:
- the real `AdaptiveSoundAU` and spatial AU;
- the real taps, meter and analyzers;
- the real `setDspAudioUnit`, `startTransportClock` and `installSpectrumTap`.

A background thread pulls `renderOffline` in place of an audio device. On top of the bridge sit the real `AudioViewModel` and `EQViewModel`, with the identity hook wired.

**Lock holds:**

| Mode | What holds the engine-wide lock |
|---|---|
| `stop-config` | `player.stop()` on configChangeQueue, whose completion handler sleeps 2.5 s inside the lock (the re-establish case) |
| `stop-engine` | The same, on engineQueue (pause, stop, seek) |
| `start` | `engine.start()` on engineQueue, with a slow v3 AU whose `allocateRenderResources` sleeps 2.5 s (a slow Bluetooth start) |
| `device-loss` | A stand-in for AVFAudio's internal stop holds the lock on a foreign queue, while the real `outputDeviceDidChange(.engineReconfigured / .targetAliveChanged)` drives reconcile, `pauseForDeviceLoss` and the engineQueue teardown, and the real VM ticks |

**Measurement:** each entry is timed per call, and a background watchdog pings the main queue every 2 ms.

**Controls:** the pre-fix reads, made on main during the hold:
- `player.isPlaying`: **557 ms** (stop-config) and **557 ms** (stop-engine). That is the rest of the 2.5 s hold, so the lock really was held.
- `engine.isRunning` (start mode): **592 ms**.

### Latency table: max ms during a 2.5 s hold (about 410 calls each)

| Main-thread entry | stop-config | stop-engine | start |
|---|---|---|---|
| `bridge.snapshot()` | 0.026 | 0.029 | 0.054 |
| `vm.tickTransport()` | 0.110 | 0.099 | 0.114 |
| `vm.tickSpectrum()` | 0.086 | 0.074 | 0.025 |
| monitor tick reads (`monitorChannelCount` + `readMonitorBands`) | 0.011 | 0.006 | 0.010 |
| `readSpectrumBands` | 0.000 | 0.000 | 0.000 |
| `vm.publishEQ` (EQ send) | 0.015 | 0.013 | 0.023 |
| `intensity` didSet → `publishIntensity` | 0.096 | 0.086 | 0.176 |
| `crossfeedEnabled` / `crossfeedStrength` didSet | 0.045 / 0.022 | 0.039 / 0.024 | 0.098 / 0.091 |
| `selectedDevice` didSet (identity → EQ `outputDidChange` → publish; `publishOutputTransport`) | 0.044 | 0.041 | 0.080 |
| `setMasterGain`, Enhanced | 0.526 | 0.533 | 0.536 |
| `setMasterGain`, Pure → `requestDeviceVolume` | 0.031 | 0.035 | 0.039 |
| `pinPlaybackToSelectedDevice` didSet | 0.015 | 0.017 | 0.063 |
| `currentOutputDeviceID()` | 0.001 | 0.000 | 0.000 |
| `refreshDevices()` / `seek(to:)` (synchronous part) | 0.011 / 0.060 | 0.008 / 0.056 | 0.012 / 0.081 |
| `publishChannelLayout` | 0.003 | 0.003 | 0.009 |
| main-queue watchdog, during the hold | 0.13 | 0.12 | 0.26 |
| main-queue watchdog, 1 s after the hold (queued Tasks land) | 0.09 | 0.04 | 0.04 |

The Enhanced `setMasterGain` figure of about 0.5 ms is the `logMasterGain` NSLog.

**Device-loss mode.** All entries stayed under 0.1 ms, and the watchdog peaked at 0.23 ms. The VM paused **10 ms** after the event and kept its place: `interrupted` landed while the engine lock was still held. The snapshot went stale as designed; it held 0.5 s throughout.

**ThreadSanitizer.** I rebuilt the app with `--sanitize=thread` and ran the stop-config and start harnesses under it. The only report was a race in my own harness flag (since fixed), which is why that run exited 134. There was no report on the bridge, the snapshot channel, the atomics or the publish paths.

## Findings

### MAJOR-1: a stale `ended` makes the Pure rate-change auto-advance stop at the next track (regression)

**Where:**
- `AudioViewModel+SpectrumTimer.swift:100-124`: the `ended` branch.
- `AudioEngineBridge+Playback.swift:34`: the only republish, at the **end** of `startAudio`.
- `AudioEngineBridge+TransportClock.swift`: the clock runs on engineQueue, so it cannot publish while a start occupies that queue.

**Failure.** Track A ends with B queued but not armed. This is the Pure cross-rate "reconfigure gap", KI-001.
1. Tick N advances the queue: it sets `pendingNextIndex = nil` and calls `startPlayback()`.
2. `startAudio(B)` runs on engineQueue: `evaluatePureViable`, then `pureModeEngineStart`, including `setRateAndWait`, which polls up to 2 s for the DAC to change rate.
3. The snapshot keeps `ended == true` for that whole time.
4. Tick N+1 sees `ended` with `pendingNextIndex == nil`, logs "playbackEnded — no next track, stopping" and calls `stopAtEndOfQueue()`.
5. The new track is stopped, and the playlist halts mid-queue.

**Why it is a regression.** Before the fix, the tick read `gapless->ended()` live. That flag clears at `setCurrent()`, which runs **before** `configure` → `setRateAndWait` (`PureModeBridge.cpp`). The old window was therefore about the capability check plus the teardown and file open, usually under one tick. Now it is the whole start, including the rate wait. The rate-change path is exactly the case that waits.

**Evidence.** `ended-advance.err` (real VM, real bridge; a 300 ms engineQueue block stands in for the Pure start's HAL work):
- tick N: "advancing to queued track[1]".
- tick N+1: "playbackEnded — no next track, stopping".
- Snapshot `ended == true` through ticks N+1 to N+6.
- Final state: `vm.isPlaying=false`, engine stopped, the queue stopped at B.

The existing test VM-AA-RGAP-1 runs the same second tick and passes only because it never asserts `isPlaying`. Its mock's else-branch stops too.

**Fix:**
- At the top of `startAudio`, next to `gaplessPlaybackEnded = false`, publish a start sample: `ended: false`, `position: nil`, the count unchanged.
- Or have the VM ignore `ended` while a start it issued is in flight.

### MAJOR-2: the transport clock can raise an uncaught NSException (crash) right after the first Enhanced start

**Where:** `AudioEngineBridge+TransportClock.swift:85-86`. `playerTime(forNodeTime:)` is called on a `lastRenderTime` without checking `isSampleTimeValid` / `isHostTimeValid`.

**Evidence:**
- The harness **crashed** in the real code with AVFAudio's `'required condition is false: nodeTime == nil || nodeTime.sampleTimeValid || nodeTime.hostTimeValid'`. The stack ran `startTransportClock` → `sampleTransport` → `liveEnhancedPosition` → `-[AVAudioPlayerNode playerTimeForNodeTime:]`.
- `probes/rendertime.swift` shows that after the first `engine.start()` + `play()`, and before the first render, `lastRenderTime` is non-nil but has `sampleValid=false, hostValid=false`.
- After a stop or pause and a restart, the time stays valid. After `engine.stop()` it is nil, so the device-loss state is safe.

**Why it is new exposure.** `sampleTransport()` now runs a few milliseconds after `player.play()` in the first `startAudio` after launch or after `retryInitialization`. The old 20 Hz tick did not read the position until the start Task had finished (`isPlaying` was still false).

**Caveat.** I could not confirm the realtime timing without a device. Whether the first IO cycle beats `sampleTransport()` depends on the IO buffer size and how fast the output starts; Bluetooth and large-buffer DACs are the worst case. The fix is one line: guard the validity flags.

### MINOR

1. **The semgrep rule is easy to bypass.**
   - `.semgrep.yml` caught 2 of 17 planted violations; the samples are in `semgrep/`.
   - `AVAudioUnit\b` misses `AVAudioUnitEQ`, `AVAudioUnitTimePitch` and the like. `AVAudioNode` and `AVAudioSourceNode` are not listed.
   - It misses AVFAudio reached through the bridge's own accessors, e.g. `bridge.playerNodeRef?.isPlaying` and `avEngineRef?.isRunning`.
   - It misses the C-ABI wrappers (`getDefaultOutputDeviceID`, `selectOutputDeviceC`, `pureModeEngine*`, `DeviceHardwareVolume`) and `AudioUnitUninitialize`.
   - The listener rule misses `.main` and `let q = DispatchQueue.main`.
   - The include list leaves out the main-actor `MenuBarView.swift`, `ContentView.swift`, `TabContentView.swift` and `AdaptiveSound.swift`. Even a literal `AVAudioPlayerNode` use in those files is not caught.
   - Its message still names `transportSnapshot / currentSignalPath`.
2. **`snapshot()` still races on `loudnessMeter`.** This is audit S1-E and was not fixed. TSan run `tsan-meter.err` flags `AudioEngineBridge.swift:336` (`loudnessReadout`) against the meter replacement made in `resetGraphStateAfterShutdown` and `allocateAnalysisState`. The raw handle is used after the wrapper ref drops, so a re-init while the tick runs (`retryInitialization`) is a potential use-after-free. `readSpectrumBands` and the monitor arrays have the same pattern.
3. **A "strong borrow" does not extend the AU's lifetime under `-O`.** In `dspAURef` followed by `Unmanaged.passUnretained(unit).toOpaque()` (EQ, Intensity, Crossfeed, Transport, Layout, Loudness), the local's last use is `toOpaque()`, so the optimizer may release it before the C call. Wrap the call in `withExtendedLifetime`. This pattern predates the fix.
4. **Pure resume plays a blip from 0:00.** `startAudio` renders from 0, and only then does `seek(resumeFrom)` pause and seek. Until this fix Pure was silent here, so the blip is newly audible.
5. **A failed Pure seek restart (`result 0`) is only logged.** The UI shows "playing" with silence when it is not a device loss.
6. **The stale snapshot shows the old track's playhead for a whole Pure start.** That can be up to 2 s of rate wait after a track switch.
7. **Pre-existing, unchanged:** a Pure → Enhanced restart while playing (`adoptOutput` → `startPlayback(resumeFrom:)`) compares the monotonic Enhanced seam count to a Pure baseline. During the `await seek` that triggers a false `handleTrackTransition`.

## What held up

- **No main-thread path reaches AVFAudio, the HAL, the Pure C-ABI or a `.sync`.**
  - I grepped the VM and UI and checked every synchronous protocol member.
  - The Realizer `slotMutex_` is O(1) and drains outside the lock.
  - Every `stateLock` closure is trivial, and swap-then-release-after-lock holds (the returned value is released after the `defer` unlock).
- **Lifetimes.** `withPureEngine` and every Pure teardown are confined to engineQueue, and the `dispatchPrecondition` callers are correct.
- **The `.auAudioUnit` read moved off main.** It is read once in `setDspAudioUnit`, on the instantiate queue, before the AU is attached.
- **Snapshot semantics.** `interrupted` is published before the slow work. The snapshot channel and the named acquire/release atomics are clean under TSan.
- **Tests.** VM-TS-01..03 pass under TSan. With `swift test --sanitize=thread --filter 'AudioViewModelTests|EQEditKitTests|OutputDeviceKitTests'`, 290 of 291 passed, exit 1. The one failure, EQEditKit BRK-03, is an exit test whose child aborts under TSan; it passes without the sanitizer (291/291, exit 0), and that code is untouched by this fix.
- **The Pure seek fix, by reading.**
  - `pause()` keeps the unit, so `start()` resumes, and a failed resume is now reported.
  - Seek, clear, arm, the clock and teardown are all serialized on engineQueue.
  - `FileDecodeSource::seek` joins the decoder, resets the ring and resets `finished_`, so a seek near EOF cannot fake an EOF or seam.
  - One caveat: `pause()` relies on `AudioOutputUnitStop` returning only once the IO proc has stopped. That is standard but undocumented; the old teardown also had Dispose.
  - A seek storm (key repeat or media keys) only queues behind on engineQueue.
  - A seek during a device loss blocks engineQueue only.
  - None of this could be run without a device.
