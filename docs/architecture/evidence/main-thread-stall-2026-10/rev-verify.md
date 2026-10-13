# Breaker verify pass: S10.8 G main-thread-stall fix @ bc08b7d

**Verdict: SHIP.** No BLOCKER and no MAJOR. Both of last round's MAJORs are fixed and proven. What remains is MINOR, and most of it is pre-existing.

**How this was run.** I checked out bc08b7d detached in `.claude/worktrees/review-breaker` and re-applied my harness and hook there, uncommitted. All artifacts are in `scratchpad/rev-breaker/verify/`.

## Pass/fail

| # | Item | Result | Evidence |
|---|---|---|---|
| 1 | Four 2.5 s lock holds: stop on configChangeQueue, stop on engineQueue, slow `engine.start`, device loss | **PASS** | Every main-thread entry stayed under 1 ms (table below). Main-queue watchdog during each hold: 0.22 / 0.42 / 0.24 / 0.12 ms. One post-hold watchdog spike of 14 ms did not reproduce in 3 reruns (0.02–0.05 ms) and came after the lock was released. Controls blocked 558–597 ms, so the lock really was held. |
| 2a | MAJOR-1 `ended-advance` (real VM and bridge, 300 ms engineQueue delay) | **PASS** | Ticks N+1 to N+5 still see the stale `ended=true`, are ignored as stale-epoch samples, and never stop playback. Final state: `vm.isPlaying=true`, B playing, engine intent true, epoch 1. |
| 2b | Stale snapshot after a slow seek / a slow track switch (real 20 Hz timers) | **PASS** | Seek to 4.0 s from 0.89 s: the scrubber's minimum after the seek is 4.000, so no jump back. Switch A (at 4.40 s) → B: scrubber minus elapsed time stays at most 0.000, so the old place never flashes. |
| 3 | MAJOR-2 crash on the first play and after a re-init (real `startAudio`, clock sampling for 300 ms before the first render) | **PASS** | No crash, and the playhead advances: 0.54 s, and 0.55 s after the re-init. With the guard removed as a mutant, my harness crashes (exit 134, the same NSException). |
| 4 | Semgrep guard | **PASS, with a hole** | All 17 original plants are caught, plus the 6 path plants (MenuBarView, ContentView, TabContentView, App, Monitoring, Spectrum). The repo scans clean. **4 of 5 new downcast plants are missed** (MINOR-1). |
| 5 | TSan | **PASS** | `tsan-meter`: 13,829 meter swaps against 393,771 `snapshot()` reads, 0 warnings (last round: 2). The TSan harness runs found no bridge or snapshot races. `swift test --sanitize=thread` on AudioViewModel, EQEditKit and OutputDeviceKit: 292 of 293 pass, **exit 1**; the one failure is BRK-03, the known exit-test SIGABRT under TSan. The new tests VM-TS-04, VM-AA-RGAP-1 and VM-AA-RGAP-2 pass. |
| 6a | Epoch logic: Next storm, seek storm, pause→play | **PASS** | VM and engine agree on the file, playback state and epoch in all three. |
| 6b | Stop during a slow start | **FAIL 3/3 (pre-existing)** | Ends with `vm.isPlaying=true` while the engine is stopped (MINOR-2). |
| 6c | Clock suspends when idle | **PASS** | After a pause the clock is stopped and the final sample is current-epoch, `position nil`, `ended false`. Resume starts at the paused place (0.69 → 0.88 → 1.27 s). |
| 6d | Master Gain latest-wins | **PASS** | 200 requests while the device queue is stuck: worst main-thread call 0.003 ms, and the final answer is the last request (−19.9 dB). |
| 6e | Pause before any HAL read on device loss | **PASS** | The VM pauses 10 ms after the event and keeps its place (`pausedResumePosition` 0.28). |

### Latency (max ms, about 406 calls each; columns are stop-config / stop-engine / start)

| Entry | stop-config | stop-engine | start |
|---|---|---|---|
| `snapshot` | 0.027 | 0.031 | 0.024 |
| `tickTransport` | 0.125 | 0.110 | 0.098 |
| `tickSpectrum` | 0.077 | 0.067 | 0.147 |
| monitor reads | 0.012 | 0.016 | 0.010 |
| `publishEQ` | 0.014 | 0.012 | 0.016 |
| `intensity` | 0.068 | 0.909 | 0.105 |
| `crossfeedEnabled` / `crossfeedStrength` | ≤0.12 | ≤0.12 | ≤0.12 |
| `selectedDevice` | 0.110 | 0.087 | 0.141 |
| `setMasterGain`, Enhanced | 0.59 | 0.55 | 0.51 |
| `setMasterGain`, Pure | 0.05 | 0.07 | 0.07 |
| pin | 0.03 | 0.05 | 0.02 |
| `currentOutputDeviceID` | 0.001 | 0.001 | 0.011 |
| `refreshDevices` / `seek`, synchronous part | ≤0.09 | ≤0.09 | ≤0.09 |
| `publishChannelLayout` | 0.003 | 0.005 | 0.014 |

**Device-loss run:** `tickTransport` 0.116 ms, `tickSpectrum` 0.092 ms, `snapshot` 0.002 ms.

**The gate self-test (`make main-thread-stall`)** exits 0, with all 4 modes PASS. A mutant that adds a live `isPlaying` inside `snapshot()` makes it FAIL as it should: 2,360 ms on stop, 2,386 ms on start, "no pause" on device loss.

## Findings: all MINOR

1. **MINOR-1: the semgrep guard misses downcasts to the concrete bridge.**
   - `(engine as? AudioEngineBridge)?.applyMasterGain()`, `.spatialAudioUnit?.name`, `.installSpectrumTap()` and `.withEffectsAU { $0 }` all pass the rule. Each reaches the engine-wide lock or escapes a borrowed handle.
   - The only legitimate references to `AudioEngineBridge` outside the bridge are the view model's init default and the Debug self-test.
   - Fix: ban the type name everywhere else.
2. **MINOR-2: stop during a slow start leaves the UI "playing" over a stopped engine (pre-existing).**
   - Seen 3 of 3 times: `vm.isPlaying=true`, `engine.intent=false`, playhead stuck at 0.
   - Cause: the start Task sets `isPlaying = true` after `primeGaplessPipeline` without checking that its request is still the latest.
   - Fix: only set it while `transportEpoch == epoch`.
   - **Related (also pre-existing):** a pause pressed while a start is still in flight is dropped. `pause()` checks `isPlaying`, which is still false at that point, and the toggle path calls `play()` again, so the track restarts from the top.
3. **MINOR-3: the gate self-test has no first-play mode.**
   - The MAJOR-2 regression is unguarded: with the render-time guard removed as a mutant, `make main-thread-stall` still passes while my harness crashes.
   - The gate is also a little looser than my harness: a 25 ms hard bound with at most 1% of calls over 5 ms, and only one stop holder (configChangeQueue).
4. **MINOR-4, pre-existing (the file is untouched by this fix):** TSan reports a Swift access race in `SpectrumDoubleBuffer.write` (tap thread) against `read` (main, `tickSpectrum`). The writer's `slots[next]` mutable access conflicts with the reader's `slots[slot]` access. That can tear a frame, or force a copy-on-write allocation on the tap thread.
5. **MINOR-5, edge cases:**
   - Pure now pauses on any alive-change notification for the app's device without reading its state. It cannot be fooled by a spurious notification, but it can pause on a live device if one arrives.
   - A Pure resume at a place the decoder cannot seek to (e.g. at or past EOF) makes `pureModeEngineStart` return 0, so playback falls back to Enhanced.

## Addendum: the MINOR-1 and MINOR-2 fixes

Branch `sprint/s10-8-g-fix-stall-minors`, cut from bc08b7d. Not pushed. The harness and its hook stay uncommitted in the review worktree.

### Commits

- **795a994: semgrep rule `main-thread-no-concrete-bridge`.** It bans the `AudioEngineBridge` type name outside the bridge's files, except the view model's init default and `Debug/MainThreadStall*.swift`. Comment lines are skipped.
  - All 5 downcast plants are caught.
  - The original plants all still flag (40 results).
  - The real tree passes `semgrep --error` (exit 0).
  - I excluded the whole `Debug/MainThreadStall*.swift` glob rather than only the SelfTest file, because the self-test's Probe and Rig files also name the bridge.
- **4643b9b: `transportStopEpoch` / `nextStopEpoch()`.** Pause and stop number their request as a stop. `startPlayback`'s Task now skips both the queue prime and `isPlaying = true` when a stop was numbered after its start.
  - Only a stop ends a start: a seek or a newer start leaves it alone, so the queue is still primed after a scrub during a slow start.

### Harness results after the fix

| Scenario | Result |
|---|---|
| Stop during a slow start | `vm.isPlaying=false`, engine stopped, 3/3 runs |
| Next storm, seek storm, pause→play | PASS, 3/3 runs |
| `ended-advance`, stale-ui, first-play, idle-clock, gain-coalesce | PASS |
| `make main-thread-stall` | All 4 modes PASS, exit 0 |
| Lock-hold modes | Every entry under 5 ms. Worst single outliers were 1.5–3.7 ms, on NSLog-backed didSets, while the machine's load average was about 8. |

**Not fixed:** a fast play-then-pause during a start is still lost. `pause()` checks `isPlaying`, which is still false at that point, so it returns, and the toggle path calls `play()` again. Fixing it needs a "start in flight" state that both the toggle and `pause()` consult, which is more than the few guarded lines here.

### Checks (real exit codes)

| Check | Exit |
|---|---|
| swiftformat `--lint` on the 3 touched files (0/3 need formatting) | 0 |
| swiftlint `--strict`, whole tree | 0 |
| `semgrep scan --config .semgrep.yml --error` | 0 |
| `swift build` | 0 |
| `make periphery` ("No unused code detected") | 0 |
| `swift test` (727 tests in 111 suites passed) | 0 |
| pre-commit hook, both commits | passed |
