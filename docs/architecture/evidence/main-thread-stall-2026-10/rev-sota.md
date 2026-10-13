# Reviewer 2: state of the art and correctness, `sprint/s10-8-g-fix-main-thread-stall` (90a62e8)

**What I read.** The branch was read in the read-only worktree `.claude/worktrees/review-sota` (detached at 90a62e8). The branch was not edited.

**Experiments.** All offline, with no audio device. They are under `scratchpad/rev-sota/`:

| Experiment | What it measures |
|---|---|
| `exp/clockcost.swift` | Cost of one clock sample |
| `exp/consumed.swift` | When `.dataConsumed` fires |
| `exp/latesched.swift` | What happens to a nil-time schedule made after the previous segment ended |
| `rgap-pkg/` | The project's own `MockAdvanceController` with one added assertion |

**Sources I opened this session:**
- The local MacOSX26.5 SDK headers.
- SFBAudioEngine at commit 9ed712d: `AudioPlayer.h` and `AudioPlayer.mm`.
- Cog at commit fb2ed48: `PlaybackEngine.swift`, `DeviceOutput.swift`, `CogRing.c` and `CogRing.h`.
- The VLC c8cd58f patch.
- JUCE forum thread 46579 (JSON API).
- Apple's Energy Efficiency Guide, the "Timers" page.
- The AVPlayer periodic-observer docs (docs JSON and `AVPlayer.h`).
- Apple forum thread 117962 was blocked by a bot check, so I did not use it.

---

## BLOCKER

### B1. The stale snapshot during a long engineQueue command stops a Pure cross-rate auto-advance. The race already existed; this branch makes it close to certain.

**Where:**
- `AudioEngineBridge+Playback.swift:7-41`: `sampleTransport()` runs only at the end of the `startAudio` body.
- `AudioViewModel+SpectrumTimer.swift:100-124`.

**Why the snapshot is stale.** The clock runs on `engineQueue`, so it cannot sample while a command is running there. The `startAudio` body covers all of the following:
- `evaluatePureViable`
- `stopEnhancedPlayback`
- `pureModeEngineStart`: teardown, `queryCapability`, `configure` (hog, then `setRateAndWait`, which polls for up to `kRateChangeTimeoutMs = 2000` at `HALOutputEngine.mm:44`, 880-896), then start.

For that whole time the snapshot keeps the last sample from before the command.

**The failing sequence:**
1. Tick N sees `ended = true` with a queued track.
2. It clears `pendingNextIndex` and calls `startPlayback()`.
3. Tick N+1 still sees the stale `ended = true`, now with `pendingNextIndex == nil`.
4. The VM therefore runs `countPlayIfNaturalEndQualifies(); stopAtEndOfQueue()`, which stops the track that is still starting.

**What the old code did.** Before this branch, `ended` was read live. It turned false at `GaplessSource::setCurrent`, which sets `ended_ = false` (`GaplessSource.cpp:86`). That point is before `configure`, so the window was only teardown plus open.

**Proof with the project's own mirror:**
- The existing test VM-AA-RGAP-1 models exactly this window (`deferEndedReset`).
- Its tick 2 sets `isPlaying = false` in `MockAdvanceController.tick` (lines 123-126), and the test never asserts `isPlaying`.
- My probe (`rgap-pkg`, the same scenario plus `#expect(ctrl.isPlaying)`) **fails**: "tick 2 stopped playback".

**Same cause, smaller symptom.** On a track change while playing, the ticks during the start overwrite `playbackPosition = 0` with the previous track's playhead. The old position flashes under the new title, for up to the length of the start (slow on Bluetooth or on a DAC rate change).

**Fix, the SFB pattern** (`TransportSnapshot.sequenceNumber_`; stale events dropped by `playbackGeneration_`, `AudioPlayer.mm:2160-2190`):
- Add an `epoch` to `TransportSnapshot`.
- `startAudio`, `seek` and `stopAudio` bump it **first**, and publish a cleared transport before any slow work (`ended = false`, `position = nil`).
- The VM ignores `ended` and `position` from epochs older than its last command.
- Add the missing `isPlaying` assertion, and a VM test with a mock whose snapshot stays stale during `startAudio`.

---

## MAJOR

### M1. `interrupted` is not published first

**Where:** `+OutputDeviceMonitor.swift:103-109`.

**What happens.** `reconcileOutputDevice` calls `readOutputDeviceFacts()` before `pauseForDeviceLoss()`. That function makes two HAL reads:
- `isDeviceAlive` on the dying device;
- `getDefaultOutputDeviceID`.

It also runs behind any earlier `configChangeQueue` re-establish that is blocked in `engine.start()` or `liveEnhancedPosition()`.

**Effect.** The app does not beach-ball. But for up to the HAL stall (the founder's capture showed ~7 s), the UI shows "playing" with a frozen scrubber, and `accruePlayThrough` counts that time as heard. The commit message claims "publishes `interrupted` before anything that can wait". That holds only inside `pauseForDeviceLoss`.

**What the field does.** SFB clears its cached `engineRunning | playing` flags **before any AVFAudio call** in the configuration-change handler (`AudioPlayer.mm:2570-2577`).

**Fix:**
- Set an atomic "output suspect, hold the transport" flag inside the listener block itself, for `.targetAliveChanged` and `.engineReconfigured`, before hopping to `configChangeQueue` or reading the HAL.
- Accrue heard time from render progress, not from wall time.

### M2. The Enhanced playhead is below the state of the art on latency and on seams

The clock moves AudioKit's poll (`isPlaying` / `lastRenderTime` / `playerTime`) off the main thread. It is not the render-side counter that SFB and Cog use.

**No latency compensation.** The reported position is the render head, which is ahead of what is heard by the presentation latency (Bluetooth about 150-250 ms).
- Cog computes heard position = read position − `latencyFrames`, where latency = device latency + safety offset + buffer + stream latency, cached at configure time (`DeviceOutput.swift:1267-1285`, `PlaybackEngine.swift:1036-1053`).
- The doc at `TransportClock.swift:22-23` says the tick is "at most one sample behind the hardware". That is wrong: the value is ahead of the hardware.

**Seam re-zero is in inconsistent domains.** `bumpTransitionCount` (`+Gapless.swift:180-205`) re-bases at handler time:
- **Passthrough** (48 kHz files): it fires on `.dataPlayedBack`, which is after the device latency (`AVAudioPlayerNode.h:45-49`). After the first seam, positions are roughly the heard position. Before it, they are the render position. That is a jump of about L.
- **Resampler** (44.1 kHz files, most music): it fires on `.dataConsumed`. My experiment shows that callback fires only when the buffer's last frame has rendered (buffer [0, 8916) was seen at 9216 frames rendered). With 3 buffers primed, end-of-file is detected while **2 buffers (~372 ms) of track A are still queued**, plus L. So the position, the title advance and `trackBecameAudible` (track B's loudness-neutral gain) all land ~0.4 s + L early. B's gain is applied to the tail of A.

**What would match the state of the art inside AVAudioPlayerNode:**
1. Keep the exact boundary in frames on `resampleQueue` (the app knows every frame it schedules). Fire the seam when the render position passes boundary + L, keyed by position (Cog: `pump.presentation.take(through: heard)`).
2. Subtract a latency cached on `engineQueue` after each start or configuration change: `outputNode.presentationLatency` (`AVAudioIONode.h:106-114`) plus the AU latencies. Never fetch it per sample: the bug's own stack was blocked in `GetOutputPresentationLatency`. VLC c8cd58f fixed a deadlock the same way, by fetching once at start.
3. Publish an anchor `(frames, hostTime, rate, playing, epoch)` and let the reader extrapolate with `mach_absolute_time`.

**Long term:** the SFB model, an `AVAudioSourceNode` reading an app-owned ring with render-side frame accounting. Pure's `GaplessSource` already works this way (`renderedFramesCurrent`), so one transport model could serve both paths.

### M3. A Pure resume from Pause plays the start of the track before the seek

**Where:** `AudioViewModel+Playback.swift:58-62`.

**What happens.** `startAudio` returns with HAL render already running from 0. Only then does a separate main-actor hop and `engineQueue` hop issue `seek`. 9de5f3e makes that seek actually work, so the intro now blips audibly before the jump.

**What the field does.** Cog starts at the offset: `feeder.start(with: track, offset: offset, …)` (`PlaybackEngine.swift:419`).

**Fix.** Add `startAudio(…, startAt:)`. On Pure, seek the source and `resetActiveBase` before `engine->start()`. On Enhanced, `scheduleSegment(startingFrame:)` before `play()`.

### M4. The clock samples at 30 Hz forever, including idle and paused

**Where:** `TransportClock.swift:24-36`. The clock starts in `initialize()` and stops only at teardown.

**Cost.** CPU cost is negligible: **0.22 µs per sample** measured, and nothing is added to the render path. But together with the always-on 20 Hz main timer, that is about 50 wakeups per second while idle. It is also 50% more engine-lock traffic than the old 20 Hz poll.

**Apple's guidance.** "Invalidate repeating timers when they're no longer needed" (Energy Efficiency Guide, Timers). AVPlayer's periodic observer fires only "during normal playback" and on jumps, start and stop (`AVPlayer.h:438-447`).

**Fix.** Resume the clock on start and seek; suspend it on stop, end and device loss. With the anchor from M2.3 it could run at 2-4 Hz.

### M5 (existed before this branch, out of scope): the 48 kHz "gapless" seam leaves a gap

**Where:** `+GaplessRoll.swift:189-212`.

**What happens.** B is scheduled only when A's `.dataPlayedBack` fires, which is after the device latency. My experiment shows a nil-time buffer scheduled after the previous one has ended starts from its frame 0 at the next render quantum. That means silence of at least L plus the time to open the file (3072 frames in the test).

**Why the tests miss it.** The offline harness cannot see this. `.dataPlayedBack` "applies only" when rendering to a device.

---

## MINOR

- **m1. A seam between the clock's reads gives an inconsistent sample** (`TransportClock.swift:84-92`).
  - The clock reads three separate domains: the player time, then the base (under `stateLock`), then the count (an atomic).
  - A seam in between yields either the old track's end with the new count, or a slightly negative position.
  - In that case the clock's `setLastKnownEnhancedPositionSeconds` also overwrites the 0 the seam just stored, which feeds the re-establish resume.
  - 4a19c1f avoided this by sampling on `resampleQueue`; 93ecf7e removed that.
  - **Fix:** keep the base, the count and a seam epoch under one lock and read them together; clamp the position at ≥ 0; write the last-known position only if the epoch is unchanged.
- **m2. The Pure seek relies on undocumented stop behaviour and has a small seam race** (`PureModeBridge.cpp:199-221`).
  - It relies on `AudioOutputUnitStop` acting as a render barrier. The header says nothing about this. A JUCE developer states that `AudioDeviceStop` off the IO thread gives no guarantee about further IOProc calls (forum 46579).
  - `activeSource()` is read **before** `pause()`, so a seam in between seeks the retired source.
  - **Fix:** pause first. Add a render-gate handshake (the callback outputs silence and acknowledges), or Cog's seek without a stop (a ring flush acknowledged by the consumer, `CogRing.c:121-195`).
  - Keeping hog, rate and the unit across the seek is the right bit-perfect practice. Cog holds the device while paused and suspends it only after 10 s.
- **m3. Master Gain requests are not coalesced** (`+MasterGain.swift:42-49`).
  - Each drag sample queues 5 HAL calls. A slow or dying device builds a backlog, and the knob rubber-bands.
  - **Fix:** latest value wins, using the Realizer's existing "pending slot + one drain" pattern (`AUAudioUnit.mm` `publishIntensity`).
  - The read-back delay itself is fine: queue time plus at most one 50 ms tick.
  - The listener and the sets share one serial queue, so they stay ordered.
- **m4. The effects AU can be freed on the main thread.** A main-thread borrow from `dspAURef` can end up holding the last reference. The AU's `dealloc` would then run `Realizer::shutdown()` (a `dispatch_sync` barrier) on main. Do the final release on `engineQueue`.
- **m5. Smaller items:**
  - Swift `Mutex` (no allocation, same primitive) fits the code base better than `OSAllocatedUnfairLock`. The lock itself is correct and as cheap as is needed; neither side is real-time.
  - `&+= 1` should be `wrappingAdd(ordering:)`.
  - The semgrep message names APIs that were removed, and a regex cannot follow transitive calls. The audit's requirement-10 end-to-end test (hold the engine lock, time `tickTransport`) was not added.
  - `snapshot()` still reads `loudnessMeter` with no synchronisation (`AudioEngineBridge.swift:336`).
  - `setPureNextTrack` blocks a global worker in `engineQueue.sync`; use async.

---

## At or above the state of the art

- **The main thread reads one copy.** It never touches AVFAudio or the HAL. That matches Cog and SFB and is better than AudioKit and Aural. No fences are used; the atomics are named acquire/release.
- **The AU handle is captured before attach.** It is read on the instantiate queue (`+Graph.swift:28`), and the audit's Experiment 1 showed an unattached `.auAudioUnit` costs 0 s.
  - It stays stable across `reconfigureGraph`, which does not re-instantiate the unit.
  - The C-ABI touches only `_realizer`, which is set in `init` and reset in `dealloc`.
  - Apple's docs (`AVAudioNode.h:150-161`) state no thread or lifetime limits, so ordinary ObjC ownership is sufficient.
- **The `stateLock` leaf rule is restored.** Pure C-ABI calls run outside the lock and are serialized on `engineQueue`. Releases happen after the swap.
- **The Pure playhead is a render-side, per-track frame counter.** Its seam handling is as exact as SFB's.
- **Device loss no longer calls `player.stop()`** (the 7 s offender). Clearing the schedule at the next start, while the engine is stopped, is pragmatic and correct given AVAudioPlayerNode.
- **Master Gain HAL calls and the listener are off main**, on one serial queue.
