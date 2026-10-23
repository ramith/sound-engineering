# Test-rig redesign: QA expert (flake science, test design, framework support)

Reviewed: `r1.1a/integration` @ b080a29 (read-only worktree `testrig-review`). Note: `Loudness_WorkersSleepWhileIdle`
was fixed after that commit (0fb9ddb, a per-worker `isParked()` plus a wake counter). Below it is listed as FIXED and used as
the model pattern. Line numbers are from b080a29.

Evidence I opened is listed in the Sources section at the end. Probes are under `scratchpad/testrig/qa/probe` (swift-testing
behaviour) and `scratchpad/testrig/probe-cpu` (wall time vs thread CPU time).

## 0. The short version

- I found 57 timing, scheduling or shared-state hazards in the gated tests and test tools. Four patterns are already the
  right design (section 1.5). The worst open risks are:
  - the Enhanced rig's paced render, which races AVFAudio's completion chain;
  - `make main-thread-stall`'s 25 ms / 5 ms bounds, which measure the machine;
  - wall-clock budgets with less than 3x headroom (`Profiler_Timing`'s predict budget has 1.9x);
  - several waits that cannot fail properly. A hang here costs a 6-hour CI job, because the workflow has no
    `timeout-minutes`.
- The frameworks help less than one might hope. Verified facts:
  - `.serialized` only serializes inside its own suite (docs + probe).
  - `confirmation` does not wait (docs + probe).
  - `.timeLimit` uses minutes only, and cannot end a test that is blocked synchronously (source).
  - swift-testing can repeat tests (`--repetitions`, `--repeat-until fail`), but our SwiftPM 6.3.2 rejects those flags. They
    work through `swiftpm-testing-helper` directly (probe).
  - GoogleTest and Catch2 offer repeat, shuffle, seed and shard, but no per-test timeout. Catch2 calls `std::terminate` on a
    failed `REQUIRE` when exceptions are off, and we build with `-fno-exceptions`.
- So the fix is mostly **test design**: wait for state, not time; measure the code, not the machine; give every run a
  ceiling. Add a small **process** around it: stress any new timing test before merge, run an advisory nightly stress job,
  and keep a quarantine list with an owner and an expiry. Borrow a few framework features rather than migrating.

## 1. Inventory

How I searched: `scratchpad/testrig/qa/grep.sh` greps the whole test scope (Tests/**, the Verify* and SRC tools, the
main-thread-stall sources) for these patterns:
- sleeps: `sleep`, `Task.sleep`, `sleep_for`;
- clocks: `Date()`, `ContinuousClock`, `steady_clock`, `mach_absolute_time`, `clock_gettime`;
- deadlines and waits: `deadline`, `timeout`, `wait(`, `DispatchSemaphore`;
- process counters and scheduling: `getrusage`, `yield`, `asyncAfter`;
- polling and measurement words: `poll`, `spin`, `percent`, `elapsed`, `measure`.

That gave 383 raw hits (`qa/raw-hits.txt`). I triaged every one by hand, mapped the C++ hits to their test functions, and read
every rig and helper in full. I also searched for the patterns grep cannot see: fixed `Task.yield()` counts, shared
`UserDefaults` suites, fixed fixture paths, unbounded loops, and how suites run in parallel. False positives were dropped:
`elapsed` as a playhead value, `PeakHoldTracker`'s injected `elapsed:`, and the injected instants in
TypeSelect/GridCursor/ListSelection, which are deterministic.

**Failure mode**:
- RED = fails loudly;
- GREEN* = passes when it should not (weakened under load, never flakes red);
- HANG = no failure, the job runs on;
- MISLEAD = fails, with the wrong reason.

**Risk**: how likely it is to cost a CI cycle, or to hide a real bug, on a 3-core `macos-26` runner running `swift test`
in parallel, or locally with several gates at once.

### 1.1 Swift suites (`swift test`; swift-testing runs them in parallel by default)

| ID | Where | What | Class | Mode | Risk |
|---|---|---|---|---|---|
| S1 | Tests/AudioViewModelTests/TransportSnapshotTests.swift:44-52 | VM-TS-02: the slowest of 60 `read()`s must take `< 5 ms` (ContinuousClock.measure) | C4 wall-clock threshold | RED | Medium |
| S2 | Tests/AdaptiveSoundTests/SpectrumHandoffTests.swift:28-55 | a 1 s ContinuousClock window; a writer `Thread` busy-loops for that second; `reads > 100` floor | C10 probabilistic, + it loads its neighbours | GREEN* (tears missed) / RED if under 100 reads | Low |
| S3 | Tests/AdaptiveSoundTests/LiveReadoutsTests.swift:28-32 (used :48,:101,:115,:121,:140,:143) | `settle()` = 50 `Task.yield()` | C7 yield count | RED (the next assert) | Low |
| S4 | LiveReadoutsTests.swift:104-108 | `runMainLoop(0.35)`, then `spectrumReads == 0` | C2b negative window | GREEN* | Low |
| S5 | LiveReadoutsTests.swift:117-118 | `runMainLoop(0.35)`, then `snapshotReads > before` (needs 1 of ~7 ticks) | C2a fixed settle | RED | Low |
| S6 | LiveReadoutsTests.swift:123-128 | `runMainLoop(0.1)` ("the tick that finds nothing playing is the last"), then 0.35 s of `reads == 0`. A late last tick lands inside the window | C2a | RED | Medium |
| S7 | LiveReadoutsTests.swift:144-145 | `runMainLoop(0.1)`, then `transportTimer == nil` | C2a | RED | Medium |
| S8 | SeekViewModelTests.swift:33-37; OutputDeviceViewModelTests.swift:61-65; ListeningSettingsTests.swift:59-63; CrossfeedPlaysTests.swift:36-40 | `settle()` = 50 yields, then assert on what the VM's tasks did | C7 | RED | Low |
| S9 | SettingsKitTests/SettingsStoreTests.swift:33-37; R11aSettingsBreakTests.swift:126-128 | 10 yields stand for "end of turn" | C7 | RED | Low |
| S10 | TrackLoudnessKitTests/TrackLoudnessAnalyzerTests.swift:76 | ANALYZER-04: `idle(for: 500 ms)`, then "the long job never finished" | C2b | GREEN* | Low |
| S11 | LibraryBrowseKitTests/LibraryScanRaceGTests.swift:58 | `Thread.sleep(0.2)` per batch makes walk A slower so walk B overtakes. If B doesn't overtake, the sweep check is vacuous | C3 race to be slow | GREEN* | Low |
| S12 | LibraryScanRaceGTests.swift:61-63 | `while !firstBatch.isRaised { Task.sleep(1 ms) }` with **no bound**. If walk A throws before its first batch, this hangs | C9 unbounded wait | HANG (up to 360 min) | Medium |
| S13 | AdaptiveSoundTests/OnDeckRig.swift:50 | one `UserDefaults` suite, "AdaptiveSoundTests.OnDeck", shared by 5 suites (OnDeckContract 20 tests, OnDeckExplorer 2, TransportContract 7, TransportExplorer 3, QueueEditContract 3). They run in parallel with each other (`.serialized` is per suite). The rig re-sets only shuffle, repeat and pure (:52-56) | C6 shared process state | GREEN*/MISLEAD (other settings leak between rigs) | Medium |
| S14 | AdaptiveSoundTests/LiveReadoutSpeechTests.swift:36 | fixed defaults suite in a non-`.serialized` suite (one user today) | C6 | latent | Low |

Already right in Swift:
- TrackLoudnessAnalyzerTests.swift:175-182 and :213-225. A 300 s hang cap that **fails**: `holdExpired`, `Issue.record`.
- `CoalescingWriter.flush()`.
- `UUID()` defaults suites in SeekViewModel, PlaylistRemoveMissing and R11aSettingsBreak.

### 1.2 Rigs (OnDeck / Transport / EnhancedTransport / Seam)

| ID | Where | What | Class | Mode | Risk |
|---|---|---|---|---|---|
| R1 | OnDeckRig.swift:103-115 `waitUntil` | a condition wait; its 20 s deadline throws `RigTimeout(what:)` | C8 bounded poll, loud (good) | RED with a name | Low |
| R2 | OnDeckRig.swift:179-183 `yieldToViewModel(40)`; TransportScenarios.swift:33; TransportExplorerTests.swift:167 (8) | "let the VM's tasks run as far as they can" counted in yields. VM tasks that hop off the main actor run on the cooperative pool, so a seeded explorer schedule is not a full replay | C7 ordering luck | RED that may not reproduce | Low (flake) / Medium (replay) |
| R3 | OnDeckRig.swift:206-226 `quiesce` | "settled" = 2 identical fingerprint rounds; 50 µs naps after round 50; 4000-round cap. A hop slower than two rounds reads as settled | C7/C2 heuristic quiescence | RED | Low |
| R4 | EnhancedTransportRig.swift:127-144 `samples(paced: true)` | each 512-frame block sleeps its own duration (`Thread.sleep`) so the **completion chain** (AVFAudio's completion threads → `resampleQueue`) "runs on a device's time"; then `resampleQueue.sync {}` drains only work that already arrived. Under load a completion arrives after the drain, the stream starves, and the seam, gap or level asserts fail. Used by every Enhanced seam and end test | C3 free-running chain races the test | RED | **High** |
| R5 | EnhancedTransportRig.swift:170-179 `PlayerRecording.samples` | 200 × 10 ms = a 2 s cap for the tap's delivery, then `nil` → `#require` | C8 short budget | RED | Low-Med |
| R6 | EnhancedSeamTests.swift:238-241 `settle` (used :87-89) | `Thread.sleep(0.1)` + drain, then `gaplessTransitionCount == 0` / "A is still playing" | C2b | GREEN* | Low |
| R7 | EnhancedSeamTests.swift:244-251 `waitFor` (used :95,:118,:161,:183) | 100 × 10 ms = 1 s, then `#require` | C8 short budget | RED | Medium |
| R8 | EnhancedEndOfQueueTests.swift:90 | `Task.sleep(300 ms)`, then "a stopped track never reports an end" | C2b | GREEN* | Low |
| R9 | EnhancedEndOfQueueTests.swift:62, :101 `frames(until:limit:)` | paced pulls until the end flag rises; depends on R4's chain keeping up | C3 | RED | Medium |
| R10 | 6 Enhanced suites + StallRig (EnhancedTransportRig.swift:43) | each `.serialized`, but parallel with each other and with all 151 suites. Each builds a real offline graph, renders paced, and registers AU subclasses process-wide | C6 shared state + load amplifier | makes R4/R7/R9 worse | Medium |

Already right in the rigs: OnDeckEngineModel is an in-process model (Mutex, explicit `hop`/`drain`/`runHeld`;
OnDeckEngineModel.swift:39). That is exactly what makes the OnDeck rigs mostly deterministic.

### 1.3 C++ null test (`make gate`; serial by default; also run under ASan+UBSan and TSan at 10-100x slower)

| ID | Where | What | Class | Mode | Risk |
|---|---|---|---|---|---|
| N1 | LoudnessTests.inc:280-391 `Loudness_WorkersSleepWhileIdle` | counted process-wide context switches (`getrusage`, :290, voluntary + involuntary) after a 350 ms settle, limit 10 (:286). CI saw 11. **FIXED in 0fb9ddb**: it now waits for `parked()`, then checks over 300 ms that the worker's *own* `wakes()` count stands still. The window is still a negative window, but a slow machine can only lower that count, never raise it | C5 process-global counter | RED | High → fixed |
| N2 | EqTransitionTests.inc:355-400 `tdEqCpuPercent` (used by `EQ_Cpu_7_1_192k` :637-660 and EqEngineFixTests.inc:924-951 `EQ_Cpu_7_1_AboveSupportedRates`) | CPU% from **wall** `steady_clock`. Apple libc++'s steady_clock is CLOCK_MONOTONIC_RAW, which "also counts cycles when the system is asleep" (src-libcxx/chrono.cpp:175-183). Hence 90 600 % across a Mac sleep. At -O0 the budget is a 1000 % tripwire | C4 measures the machine | RED | Medium (High if an optimised budget is ever gated) |
| N3 | EqDesignerTests.inc:1566-1626 `Designer_Timing` | wall time per design; -O0 budget 3000 µs, CI took 1192 µs (2.5x headroom) | C4 | RED | Medium |
| N4 | TrackLoudnessTests.inc:2063-2200 `Profiler_Timing` | wall; feed budget 250 ms/s (CI 85, 2.9x); **predict budget 40 ms, CI 21 ms (1.9x)** | C4 | RED | **High** |
| N5 | LoudnessNeutralTests.inc:827-900 `Realizer_LoudnessCost` | wall; edit 15 ms (CI 2.0), refresh 100 ms (CI 16.3) | C4 | RED | Low |
| N6 | EqEngineTests.inc:1028-1110 `Realizer_ReinitDuringDrain` | **worst** of 40 re-allocations ≤ 4 × worst idle + 10 ms. One preemption of more than ~10 ms fails it. Registered `parallelSafe=true` (DSPKernelNullTest.cpp:460) | C4 (relative, but worst-case) | RED | Medium |
| N7 | SoakRtAllocTests.inc:269-310 | the **last** buffer's wall time > 50 × median fails: a single sample | C4 | RED | Low-Med |
| N8 | LoudnessNeutralTests.inc:650 `Loudness_EditDebounce` | `sleep_for(400 ms)`, then "the idle refresh published". Production debounces with `dispatch_after` 150 ms (Realizer.mm:104, :553). `parallelSafe=true` | C2a fixed settle | RED | Medium |
| N9 | LoudnessNeutralTests.inc:571-577 `Loudness_AnalysisFails_CausalFallback` | waits up to 10 s per rendered second for the snapshot, **then carries on** and pushes whatever gain is there | C1 deadline that carries on | MISLEAD | Low-Med |
| N10 | LoudnessNeutralTests.inc:803-808 `Soak_DSPKernel_ZeroRtAlloc_CausalTap` | 10 s deadline, then carries on (asserts only `fed != 0`) | C1 | GREEN*/MISLEAD | Low |
| N11 | EqEngineTests.inc:458-468 `Path_Switch_AfterNormaliserAdapted` | 12 s of programme **paced** at 1 ms per block "so the measurement worker keeps up"; then cut ≥ 6 dB. A starved worker drops ring data | C3 worker races the test | RED | Medium |
| N12 | EqEngineFixTests.inc:580-586 `Intensity_Zero_LevelGlide` | the same paced-normaliser pattern | C3 | RED | Medium |
| N13 | EqEngineBreakItTests.inc:150-190 `BreakIt_NonFiniteInput_NormaliserKeepsAdapting` | paced at 500 µs per block, 50 ms settles (:182, :186), then the makeup moved ≥ 1 dB | C3 + C2a | RED | Medium |
| N14 | LoudnessOracleTests.inc:655-670 `…BeginTrackConcurrent` | a bridge thread naps 200 µs while racing the tap | C10 | GREEN* (a missed race) | Low |
| N15 | SnapshotConcurrencyTests.inc:244-263 | a good "reader is running" handshake, then a 2 s deadline for the first accept that **carries on** | C1 | MISLEAD | Low |
| N16 | FileDecodeTests.inc:94/146-160 (100 × 2 ms), :447-457 `drainFrames` (100 attempts, productive ones included), :460-471 `pollFinished` (60 × 2 ms ≈ **120 ms**) | short polling budgets on a background decoder, also run under ASan/TSan | C8 short budget | RED | Medium |
| N17 | PureGaplessTests.inc:45-48, :75-95, :103-114, :262-270 (and GaplessContractTests.inc:101-111, :340-356, :445-458; SoakRtAllocTests.inc:444-455) | idle-spin cap 4000 × 1 ms (good, elastic); `pollGaplessEnded` = 200 × 1 ms (**200 ms**) | C8 | RED | Low-Med |
| N18 | GaplessArmContractTests.inc:89-99 `openArmTrack` | 20 000 × 100 µs ≈ 2 s waiting for the decoder to finish, **then returns the source anyway**. The tests assume "fully decoded, so a short fill means the true end" | C1 | MISLEAD | Low-Med |
| N19 | GaplessArmContractTests.inc:430-470 `runArmRace` (ClearRacesSeam, ArmRacesEnd) | a free render vs the control plane; both outcomes accepted, 2000 trials | C10 by design | GREEN* at worst | Low |
| N20 | DSPKernelNullTest.cpp:553-620; TestSupport.h:631-770 (the runner) | no per-test timeout, no repeat, no shuffle, `--filter` is an exact name, `--parallel` is opt-in | C9 no ceiling | HANG | Medium |
| N21 | fixed paths under test-data/ (e.g. GaplessArmContractTests.inc:32-34); the `ADAPTIVESOUND_DECODER` env var mutated by FileDecode tests | safe only because these entries are serial-only | C6 | latent | Low |

Already right in the null test (keep these as models):
- **GaplessArmContractTests.inc:640-760**: a seam window forced by production `TestPoint` hooks, with no deadline in any
  hand-off. This is the PR #89 fix.
- **RenderGateTests.inc:1-37, :255-380**: interleavings forced with atomics, `kWaitForever`, and an iteration-bounded
  `spinUntil` that fails instead of hanging; the wall clock is info only.
- **N1 after 0fb9ddb**: count the code's own wake-ups.

Not gated: EqEngineBreakItMeasurements.inc (wall-clock CPU, a 6 s storm), report only.

### 1.4 Verifiers and the stall self-test

| ID | Where | What | Class | Mode | Risk |
|---|---|---|---|---|---|
| V1 | Sources/VerifyLibraryStore/Deadline.swift:19-35 `withDeadline` | races the operation against `Task.sleep` in a task group, then `cancelAll()`. But "a group always waits for all of its child tasks to complete before it returns. Even canceled tasks must run until completion" (Apple, withTaskGroup). A real deadlock in a non-cooperative wait (ChecksScanReconcile.swift:287 `readDone.wait()`, or synchronous SQLite) therefore **hangs instead of failing**, against the promise at ChecksScanReconcile.swift:248 | C9 a deadline that cannot fire | HANG | Medium |
| V2 | ChecksConcurrency.swift:26 (20 s phases), :196 (50 ms busy timeout) | condition-bound; the SQLite semantics are deterministic | C8 | RED | Low |
| V3 | ChecksGenreCovers.swift:345-365 GC-05 | the **slowest** of 5 reads must be `< 100 ms` (wall) | C4 | RED | Medium |
| V4 | ChecksAlbumFixRound.swift:208, :233-235 ALB-08 | relative: shared ≤ 3 × distinct + 2 s (two wall runs) | C4 relative | RED | Low |
| V5 | VerifyAUGraph/main.swift:102, :288; VerifyMultichannel.swift:41 | `DispatchSemaphore.wait()` with no timeout on AU instantiate/render completions | C9 | HANG | Low |
| V6 | Sources/AdaptiveSound/Debug/MainThreadStallSelfTest.swift:27-29, :95, :101-102 | no main-thread entry may take 25 ms; at most 1 % over 5 ms; the main queue may not wait 25 ms. It failed at 31.5 ms locally under 3 gates. The property ("main never waits on the engine lock") would show as a wait of **hundreds of ms to 2.5 s**; the bound is set at scheduler-noise scale | C4 measures the machine | RED | **High** |
| V7 | MainThreadStallSelfTest.swift:173-179 (ended-advance) | `pump(0.1)` "the clock publishes the end flag", a fake slow start `Thread.sleep(0.3)` (:174), 12 ticks × 50 ms, `pump(0.5)` | C2a | RED | Medium |
| V8 | MainThreadStallSelfTest.swift:150 | "paused within 500 ms" of the device loss | C4 | RED | Low-Med |
| V9 | MainThreadStallSelfTest.swift:71 + :96 | `pump(0.15)` "let the holder get inside the lock", guarded by the control read ≥ 300 ms | C2, guarded (good) | RED | Low |

Already right among the tools:
- **SRCQualityMeasure/main.swift:110-112** measures with `CLOCK_THREAD_CPUTIME_ID` against a 4x margin, already measured on
  efficiency cores. This is the model for every performance check.
- **ChecksFolderWatch.swift:1-7** tests deterministically through an `ingest` seam in the gate, and keeps the real FSEvents
  stream to a manual `--fsevents-smoke` command.

### 1.5 Pipeline-level hazards

| ID | Where | What | Class | Risk |
|---|---|---|---|---|
| P1 | .github/workflows/strict-ci.yml (no `timeout-minutes`) | the job default is **360 minutes** (GitHub workflow syntax, `jobs.<job_id>.timeout-minutes`: "Default: 360"). Any HANG above costs 6 h | C9 | Medium |
| P2 | `swift test` in strict-gate.sh | swift-testing runs **in parallel by default**, and `.serialized` does not isolate a suite from other suites (probe: overlap true; with `--no-parallel` false). The runner has 3 M1 cores and 7 GB (runners.md). Paced and timed suites run beside 960 other tests | amplifier | Medium |
| P3 | pr91-failed7.log | 207 k `[UX]` NSLog lines (33 MB per run) from parallel tests: synchronous stderr writes add timing noise and bury the one failure line | C6 noise | Low-Med |

## 2. Taxonomy, with counts

There are 57 counted items: S1-S14, R1-R10, N1-N21, V1-V9 and P1-P3. They exclude the six "already
right" patterns noted as models. Each item has one primary class.

| Class | What goes wrong | Items | Count |
|---|---|---|---|
| C1 a deadline that carries on | the wait expires and the test asserts on a half-finished state: a wrong reason, or a pass. This was the ANALYZER-05 bug | N9 N10 N15 N18 | 4 |
| C2a a fixed settle, then a positive assert | "sleep X, it must have happened by now"; a slow machine makes it red | S5 S6 S7 N8 V7 | 5 |
| C2b a fixed window, then a negative assert | "nothing happened in X"; a slow machine makes it vacuously green | S4 S10 R6 R8 | 4 |
| C3 a free-running thread or chain races the test | paced feeding or rendering assumes a worker, queue or completion chain keeps up | R4 R9 N11 N12 N13 S11 | 6 |
| C4 wall-clock performance thresholds | measures the machine: load, frequency, sleep. Worst-of-N statistics make it worse | S1 N2 N3 N4 N5 N6 N7 V3 V4 V6 V8 | 11 |
| C5 process-global counters | counts other threads' work (getrusage) | N1 (fixed) | 1 |
| C6 process-global state shared by parallel tests | defaults suites, AU registration, fixed paths, env vars, log volume | S13 S14 R10 N21 P3 | 5 |
| C7 ordering luck / yield counts | "N yields is enough" / "stable for 2 rounds"; pool hops make it timing-dependent and not replayable | S3 S8 S9 R2 R3 | 5 |
| C8 bounded polls with short budgets (loud) | the right shape, but the budget sits at noise scale (120 ms, 200 ms, 1 s, 2 s) | R1(ok) R5 R7 N16 N17 V2(ok) V9(ok) | 7 (4 risky) |
| C9 no ceiling / a deadline that cannot fire | a hang runs to the CI job limit | S12 N20 V1 V5 P1 | 5 |
| C10 probabilistic detectors | a race may simply not happen; green proves less than it says | S2 N14 N19 | 3 |
| amplifier | parallel-by-default execution beside heavy suites | P2 | 1 |

**By risk**:
- **High: 4**. R4, N4 and V6 are open; N1 is already fixed.
- **Medium: 22**. S6 S7 S12 S13 R2(replay) R7 R9 R10 N2 N3 N6 N8 N11 N12 N13 N16 N20 V1 V3 V7 P1 P2.
- **Low / Low-Med: 31**. Everything else.

**By failure mode**:
- RED (costs a CI cycle): 34;
- GREEN* (hides bugs under load): 9;
- HANG (costs up to 6 h, P1 included): 5;
- MISLEAD: 4;
- latent: 2;
- amplifiers or noise (R10, P2, P3): 3.

What this shows: the test suite fails *loudly* in most places; the fixes since PR #86 moved it that way. The remaining red
flakes come from two families:
1. **measuring the machine** (C4, 11 items);
2. **racing a free-running worker or chain with sleeps** (C2a + C3, 11 items).

The quiet risks are the C2b/C10 negatives, which weaken under load, and the five ways to hang.

## 3. What the frameworks support (from opened sources and probes)

Each feature below covers: what it does, which of our classes it removes, and what it costs.

### 3.1 swift-testing (our toolchain: Swift 6.3.2, Testing library "1902")

- **`.timeLimit(.minutes(n))`**: a test or suite trait. A suite trait applies to each test, and to each case of a
  parameterized test.
  - Minutes only. Seconds and milliseconds are `@available(*, unavailable, message: "Time limit must be specified in
    minutes")` (TimeLimitTrait.swift), and the granularity defaults to 60 s (Configuration.swift:200-202).
  - On expiry it records `.timeLimitExceeded` and the test's task "is cancelled" (LimitingExecutionTime.md).
  - **Source-verified limit:** `withTimeLimit` is a task group racing `Test.Clock().sleep(for:)` against the body, then
    `cancelAll()` (TimeLimitTrait.swift, `withTimeLimit`; Runner.swift:499-509). So, like our `withDeadline`, it records the
    issue on time but **cannot end a body blocked synchronously**: a semaphore, `Thread.sleep`, a C++ wait, or a busy loop
    without a cancellation check. The test ends when the block does. (I read this from source; the 80 s probe was stopped
    before it ran.)
  - The default and maximum limits (`defaultTestTimeLimit`, `maximumTestTimeLimit`, Configuration.swift:172-190) can be set
    only by the launching tool. `swift test` has no flag for them (EntryPoint.swift), so we must use per-suite traits.
  - *Removes:* C9 for async/cooperative hangs (`waitUntil`, `Task.sleep` polls, `sink.wait`), and it makes every hang
    *visible* within minutes. *Does not replace* in-test condition deadlines (our failures are seconds-scale). *Cost:* one
    trait per suite. Nearly free.
- **`confirmation(expectedCount:)`**: "they don't block or suspend the caller while waiting… the requirement is expected to be
  confirmed before `confirmation()` returns" (MigratingFromXCTest.md:514-517).
  - **Probe:** a callback 0.2 s later gives "Confirmation was confirmed 0 times, but expected to be confirmed 1 time".
  - It is an **exact counter**, not a wait. It is useful for "the seam counted exactly once" or "published twice", inside a
    body that already awaits completion (`flush()`, a barrier). `expectedCount: 0` still needs a window, so C2b remains.
    Ranges are allowed.
  - *Removes:* nothing in C1-C3 on its own. It sharpens assertions. *Cost:* nil.
- **`.serialized`**: "doesn't affect the execution of a test relative to its peers or to unrelated tests" (Parallelization.md;
  identical in release/6.2 and 6.3, pt-release-*.swift).
  - **Probe:** two `.serialized` suites overlapped (`true`). With `--no-parallel`, `false`.
  - `.serialized(for: \Key)` / `(for: *)` exist only on main, as `@_spi(Experimental)` (ParallelizationTrait.swift main),
    along with the env var `SWT_EXPERIMENTAL_SERIALIZED_TRAIT_APPLIES_GLOBALLY`. Neither is in our toolchain.
  - *Removes:* C6/C7 inside one suite only. Today's 22 `.serialized` suites (16 of them in AdaptiveSoundTests) still run beside each other.
- **Parallelism controls.** `swift test --no-parallel` turns off swift-testing parallelism for the whole run (probe). Note that
  the `swift test --help` text "default: --no-parallel" is about XCTest; swift-testing defaults to parallel (probe and
  Parallelization.md "By default, tests run in parallel").
  - Two more controls:
    - `--experimental-maximum-parallelization-width N`: hidden in SwiftPM, passed through (stc-release-6.3.swift:167-172;
      ep-release-6.3.swift:492). It caps the width, e.g. 2 on the 3-core runner. It is experimental.
    - `--num-workers` is XCTest-only (SwiftTestCommand.swift:1273).
  - *Removes:* C6/C7/P2 for whatever runs in a `--no-parallel` invocation. *Cost:* a second `swift test` invocation in the
    gate: `--filter` for the timing suites, `--skip` for the rest. That is about 10 s more, because those suites run serially
    anyway.
- **`Issue.record` / `withKnownIssue(_:isIntermittent:)`**: `Issue.record` is how the ANALYZER fix fails a deadline.
  `withKnownIssue(isIntermittent: true)` is the swift-testing form of XCTest's non-strict expected failure
  (MigratingFromXCTest.md:780-800; KnownIssue.swift).
  - A failure inside is reported as known, and its absence is not an error either.
  - *Use:* the **quarantine primitive** (section 4.2), with a comment carrying owner, issue and expiry that a gate script
    checks. *Cost:* nil. *Risk:* rot, so it must expire.
- **Tags and filtering.** `@Tag`/`.tags()` exist, but `swift test --filter` is a regex over test IDs (type and function
  names).
  - **Probe:** filtering by display name ran 0 tests; `--filter 'tag:probe'` ran 0. (The brief saw this too.)
  - Tags help Xcode test plans, not our SwiftPM gate. *Use instead:* a naming convention, e.g. suite types ending
    `TimingTests` / `RigTests`, so one regex selects them.
- **Repeat or "until failure".** The runtime supports `--repetitions N` and `--repeat-until pass|fail`
  (ep-release-6.2.swift:454-457, ep-release-6.3.swift:530-533; Runner+Repetition.swift `applyRepetitionPolicy`). Repeats run in
  the same process.
  - **Our SwiftPM rejects them:** `error: Unknown option '--repetitions'` / `'--repeat-until'` / `'--maximum-repetitions'`
    (probe, Swift 6.3.2). SwiftPM *main* adds `--maximum-repetitions` and `--repeat-until` and forwards them
    (SwiftTestCommand.swift main:174-184, :899-901). That has not shipped to us yet.
  - **Works today** by calling the helper directly (probe):
    `DYLD_FRAMEWORK_PATH=<Xcode>/Platforms/MacOSX.platform/Developer/Library/Frameworks swiftpm-testing-helper
    --test-bundle-path <pkg>Tests.xctest/Contents/MacOS/<pkg>Tests <same> --testing-library swift-testing --filter <regex>
    --repetitions 50 [--repeat-until fail]`.
    - `--repetitions 5` ran 5 times and recorded the 3rd-run failure.
    - `--repeat-until fail` stopped at run 3.
    - **Both exited 1**, but the `--repetitions` summary line still printed "✔ Test run … passed". **Trust only the exit
      code** (as the founder's verify-gate-exit-code rule says).
  - *Removes:* the "13/20 under load" style of manual stress loops. *Cost:* a 20-line `make stress` wrapper.

### 3.2 Point-Free libraries (README and source opened)

- **swift-clocks: `TestClock`, `ImmediateClock`, `UnimplementedClock`** (swift-clocks README). They need **clock injection**:
  production code takes `any Clock<Duration>` and sleeps through it.
  - Caveat from the source: `TestClock.advance` and `checkSuspension` use `Task.megaYield()` (TestClock.swift:153-196). That
    is 20 detached-task yield round-trips (concurrency-extras Task.swift:11-27, tunable by `TASK_MEGA_YIELD_COUNT`), so a
    TestClock alone still carries yield-count luck. Point-Free's README says megaYield "can make flakey async tests a little
    less flakey … Prefer the reliability of serial execution".
  - Where it fits here:
    - `AudioViewModel` transport tick (a 20 Hz `Timer`, AudioViewModel+TransportTick.swift:39): S5-S7;
    - queue-mirror debounce (AudioViewModel+QueueMirror.swift:29);
    - LibraryModel reconcile delay (LibraryModel+Reconcile.swift:128);
    - toasts and bring-back messages.
  - It does **not** fit GCD queues, AVFAudio completion threads, `std::thread` workers, or `dispatch_after`
    (Realizer.mm:553).
  - *Removes:* C2 for the Swift tick and debounce code. *Cost:* a production refactor (Timer → clock-driven task, or an
    injected tick source). It also needs a new SwiftPM dependency, or a ~60-line in-house manual clock. Given the founder's
    "prefer established libs", the dependency is defensible, but the in-house manual clock is enough for our three call sites.
- **swift-concurrency-extras: `withMainSerialExecutor`** (MainSerialExecutor.swift). It installs the process-global
  `swift_task_enqueueGlobal_hook` (:82-100) so that all global-executor jobs run serially on main. The docs warn: "there are no
  scoping guarantees should this mutable variable change during the operation" (:22-28).
  - Under swift-testing's in-process parallelism it serializes **every concurrently running test's tasks**. So it is only
    safe in a `--no-parallel` invocation.
  - Where it fits here: the OnDeck/Transport/QueueEdit rigs. Their engine model is already in-process, so the only
    non-determinism left is pool hops: R2, R3, S3, S8. That would make explorer seeds a full replay.
  - It does not help the Enhanced rig (GCD and AVFAudio).
  - *Cost:* a dependency (or the same hook in about 40 lines of our own test support) plus the separate invocation.

### 3.3 XCTest (Apple docs opened as JSON)

- `XCTestExpectation` / `fulfillment(of:timeout:)` / `XCTWaiter`: a condition wait with a timeout that fails the test. Apple:
  "If you don't specify a timeout … enable test timeouts to prevent unfulfilled expectation from hanging". This is the same
  shape as our `waitUntil`, so it adds nothing over swift-testing plus a shared helper. Mixing the two frameworks costs more.
- `executionTimeAllowance`: works only with "timeouts in your test plan or `-test-timeouts-enabled` … `xcodebuild`", so it is
  not available to `swift test`.
- `measure`:
  - it runs `iterationCount + 1` times and drops the first (XCTMeasureOptions.iterationCount);
  - the default metric is wall clock (`defaultPerformanceMetrics`);
  - `XCTCPUMetric` records CPU time, which "doesn't increase" while the CPU runs another thread or idles.
  - I found no opened source saying `swift test` enforces stored baselines; baselines are an Xcode scheme feature, so treat
    them as unavailable to us.
  - **Borrow the ideas** (warm-up drop, N samples, CPU time, a stored baseline with tolerance); don't adopt XCTest.

### 3.4 The C++ harness: GoogleTest and Catch2 (docs opened)

- **GoogleTest** (docs/advanced.md):
  - `--gtest_repeat=N` (`-1` = forever) with `--gtest_break_on_failure` (:1937-1965);
  - `--gtest_shuffle` with a printed, replayable `--gtest_random_seed`, re-shuffled every iteration (:1973-1989);
  - sharding by environment (:1991);
  - the premature-exit-file protocol (`TEST_PREMATURE_EXIT_FILE`, :2394-2403);
  - `--gtest_fail_fast`;
  - death tests (`ASSERT_DEATH/EXIT`). These fork; the "threadsafe" style re-executes the binary, and it warns when other
    threads are running (:539-590).
  - It tolerates `-fno-exceptions` (`GTEST_HAS_EXCEPTIONS` detection, gtest-port.h:446-456).
  - **No per-test timeout** (none in the advanced-options headings). A runner such as ctest has to provide it.
- **Catch2 v3** (docs):
  - `--order rand` (the default since 3.9.0) and `--rng-seed` (command-line.md:406-430);
  - `--shard-count/--shard-index`; `-a/-x` abort;
  - benchmarks with samples, mean, low/high mean and std dev (benchmarks.md);
  - **with exceptions off, "If an assertion from the `REQUIRE` family of macros fails, `std::terminate` will be called"**, and
    the mode is "experimental" (configuration.md:232-250). We build `-fno-exceptions -fno-rtti`, so one failed `REQUIRE` would
    kill the whole 244-test run.
  - No in-process parallel run (limitations.md:64-73).
- **Verdict: do not migrate** the ~244 registrations. Our runner (TestSupport.h:631-770, DSPKernelNullTest.cpp:553-620)
  already has `--list`, `--filter` and an opt-in `--parallel`. **Borrow four features** (about 150 lines in
  TestSupport.h/main):
  1. `--repeat=N` and `--until-fail`;
  2. `--shuffle[=seed]`, which prints the seed;
  3. a **per-test watchdog**: a thread that, after K seconds (default 120, `ADAPTIVESOUND_TEST_TIMEOUT`), prints
     "[TIMEOUT] <test name>" and `_exit(124)`s. That is our death-by-timeout;
  4. a machine-readable result line per test, plus a separate `[timing]` report.
- Death tests are not needed. Our crash paths already run under the sanitizers.

### 3.5 Clocks and the runner (opened)

- **libc++ `steady_clock` on Apple is `CLOCK_MONOTONIC_RAW`**: "it also counts cycles when the system is asleep"
  (src-libcxx/chrono.cpp:175-183). Swift's `ContinuousClock` is documented as not stopping while the system sleeps (`SuspendingClock` does stop). That is
  from memory; I did not open that page. A Mac nap inside any wall-clock window inflates it; that is the 90 600 % in N2.
- **Probe (`probe-cpu`)**, the same work measured three ways:

  | Condition | Wall time | Thread CPU time |
  |---|---|---|
  | Idle | 389 ms | 372 ms |
  | 28 in-process hogs | **1619 ms (×4.2)** | **395 ms (+6 %)** |
  | Idle again | 524 ms | 407 ms |

  `CLOCK_THREAD_CPUTIME_ID` (already used by SRCQualityMeasure) is the measure to use. Wall budgets with less than 4x headroom
  (N3, N4, S1, V3, V6) sit inside the observed contention band.
- **GitHub**:
  - `jobs.<job_id>.timeout-minutes` "Default: 360", and steps have their own `timeout-minutes` (workflow-syntax.md:1070-1074,
    :1228-1230);
  - `on.schedule` and `on.workflow_dispatch` exist for a nightly or opt-in stress job (:179, :320);
  - `continue-on-error` makes such a job advisory (:1348);
  - `macos-26` = 3 CPU (M1), 7 GB (runners.md:78-90).

### 3.6 Feature → class it removes → cost

| Feature | Removes | Cost |
|---|---|---|
| `.timeLimit` suite traits + job/step `timeout-minutes` + C++ watchdog | C9 (hangs become minutes-scale failures; cooperative waits are cancelled) | about 1 hour |
| A separate `--no-parallel` invocation for timing and rig suites (± max width) | P2 amplification, C6/C7 between suites | about 10 s of gate time |
| Repetitions via `swiftpm-testing-helper` / C++ `--repeat --until-fail --shuffle` | manual stress loops; makes "13/20 under load" routine and reproducible | about 1/2 day |
| `withKnownIssue(isIntermittent:)` + a C++ `quarantined` flag | uncontrolled flake cost (with an expiry check) | about 2 hours |
| `confirmation` with exact counts | weak "≥1" assertions | nil |
| Clock injection (in-house manual clock, or swift-clocks) | C2 in the Swift VM tick and debounces | a production refactor, ~1 day |
| A serial executor (concurrency-extras or a ~40-line hook) for the VM rigs | C7 replayability | a dependency or small code; must run `--no-parallel` |
| Nothing in any framework | C3 (worker or completion-chain races) and C4 (wall-clock budgets) | **test design** (section 4) |

## 4. Recommendations

### 4.1 Test design principles for this codebase

1. **Wait for the state, never for the time.**
   - Every wait is a condition wait. Its deadline is only a hang guard (≥ 30 s in-test, plus `.timeLimit` or the C++
     watchdog around it), and when it expires it **fails, naming the state it waited for**. It never carries on.
   - Models: `Rig.waitUntil` (OnDeckRig.swift:103), the ANALYZER fix (`Issue.record`, `holdExpired`), RenderGate's `spinUntil`.
   - Applies to: C1 (N9 N10 N15 N18) and the short polls (R5 R7 N16 N17). Raise those budgets to hang-guard size; a passing
     run pays nothing for a long budget.
2. **Make the bad outcome unbounded, then any generous guard separates it from noise.**
   - Hold the thing under test until the test releases it: the ANALYZER-05 hold, the seam `TestPoint` hooks.
   - Applied to V6: hold AVFAudio's lock **until the probes are done** (not a 2.5 s timer). Judge "a main-thread entry waited
     on the lock" at **≥ 250 ms**, which is far above scheduler noise (tens of ms) and far below the hold.
   - Keep the 5 / 25 ms responsiveness numbers as `[info]`, or put them in the perf lane.
3. **Drive time and drain work; don't sleep and hope.** Give each asynchronous unit a test-visible way to say "done":
   - `Realizer::barrier()` (exists);
   - `resampleQueue.sync {}` (exists, but only drains what has already arrived);
   - `CoalescingWriter.flush()` (exists);
   - **0fb9ddb's `isParked()` + wake counter** (the model for C++ workers).
   New hooks to add:
   - a `LoudnessModule` processed-frames counter or `drainForTest()` for N11-N13. Each paced block then becomes "push, then
     wait until processed ≥ pushed".
   - a Realizer `flushPendingRefreshForTest()`, or an injectable debounce delay, for N8.
   - for the Enhanced rig (R4/R9): a completions-scheduled vs completions-delivered counter in the bridge, so each render
     block waits for "every completion the render made has run on `resampleQueue`" instead of sleeping one block's length.
     This turns the High item into a condition wait.
   - an injected clock or tick source for the AudioViewModel tick and debounces (S5-S7).
4. **A negative claim needs a positive witness.** Before asserting "X did not happen in window W", assert something that
   proves the system had the chance in W:
   - the cancelled job logged its cancellation (S10);
   - the worker processed the frames;
   - the tick count moved (S4);
   - the completion chain has run past the frame (R6, R8).
   Otherwise a slow machine passes the test vacuously (GREEN*).
5. **Count the code, not the machine.** Never use process-wide counters (`getrusage`), never "context switches", never
   "reads in one second" as a pass criterion. Count per-object events (N1 → 0fb9ddb).
6. **Performance gets its own lane.**
   - The functional gate keeps only *catastrophic tripwires* with ≥ 10x headroom, measured in **thread CPU time**
     (`CLOCK_THREAD_CPUTIME_ID`) and reported as the **minimum** of N runs, never the maximum (N2-N7, S1, V3).
   - Real budgets (EQ 5 % of a core at 192 kHz, designer 250 µs, predict 4 ms) belong to an **optimised** perf job:
     best-of-N, compared with a committed baseline file with a tolerance, advisory unless it misses twice in a row.
   - S1 (VM-TS-02) needs no threshold at all: the publisher stays blocked until after the reads, so a read that waited would
     deadlock and be caught by `.timeLimit`. Delete the 5 ms bound.
7. **Each test owns its world.** Use a `UUID` defaults suite per rig (S13, S14), unique fixture paths, and no env mutation
   outside serial-only tests (N21). Heavy real-engine suites (Enhanced*, the stall rig, the paced C++ tests) run where nothing
   else competes: a separate `swift test --no-parallel --filter '(Enhanced|LiveReadouts|…)'` step, with the main run
   `--skip`ping them.
8. **Every run has a ceiling.**
   - `timeout-minutes` on the CI job (about 150) and on each step;
   - `.timeLimit(.minutes(3))` on every suite that waits;
   - the C++ per-test watchdog;
   - fix `withDeadline` (V1) so a timeout returns at once and the stuck child is abandoned (an unstructured `Task` plus a
     continuation race, then `exit(1)` from the verifier). A task group cannot abandon a child.
   - bound S12's loop.
9. **A failure must replay.** Explorers already print their SplitMix64 seeds. Add a serial executor for the VM rigs so that a
   seed reproduces the whole run (R2/R3). C++ `--shuffle` prints its seed. A stress run prints the iteration that failed.
10. **Probabilistic tests state their power.** C10 tests (S2, N14, N19) keep a coverage floor that is a *count of events*
    (laps, interleavings seen), not a wall-clock window. They run longer, and stricter, in the nightly job.

### 4.2 Flake detection and quarantine, fitted to the founder's way of working

The founder merges by hand, often before CI finishes, and "lets CI run the full gate". So the process must make flakes
**expensive to introduce and cheap to see**, without adding blocking steps:

1. **`make stress TEST=<regex> N=50 LOAD=8` before merging any new or changed timing test.** A timing test is one that starts
   a thread, queue or timer, sleeps, reads a clock, or waits on a condition.
   - Swift: through `swiftpm-testing-helper … --repetitions N --repeat-until fail`, as probed. It switches to SwiftPM's
     `--maximum-repetitions` once the toolchain has it.
   - C++: through the new `DSPKernelNullTest --filter=<name> --repeat=N --until-fail`.
   - Load comes from a bounded hog set run **in its own process group**, with a hard cap and a `trap` that kills the group on
     any exit. macOS has no `timeout`, and the 16 leaked busy loops from the earlier stress run must not happen again.
   - The **exit code** is the verdict. The pass rate goes in the PR body (e.g. "ANALYZER-05 50/50 under LOAD=8").
   - This is the agents' job inside their lane, not the founder's.
2. **A semgrep rule set for Tests/** (the founder already trusts semgrep, and suppressions already need owner, reason and
   expiry in check-suppressions.sh). It flags:
   - `Thread.sleep` / `Task.sleep` / `sleep_for` / `usleep` outside a short allowlist of rig helpers;
   - `for _ in 0 ..< N { await Task.yield() }`;
   - `ContinuousClock.now <` / `steady_clock::now() <` loops not followed by a failing call;
   - `getrusage`;
   - `RunLoop.main.run(until:` with a literal.
   A new raw sleep then needs a justified, expiring suppression, so the class cannot creep back in silently.
3. **A nightly advisory stress job** (`on.schedule` + `on.workflow_dispatch`, `continue-on-error: true`, its own job so it
   never touches merges). It runs:
   - every Swift suite 5x (helper `--repetitions 5`);
   - the null test `--repeat=5 --shuffle` plus TSan once;
   - quarantined tests **strictly**;
   - all of it under a fixed background load.
   It posts one summary: tests that failed, their seed and iteration, and the flake rate. A test failing twice in a week is
   quarantined the next morning, and fixed within its expiry.
4. **A quarantine manifest**, `Tests/QUARANTINE.md` or `.yml`. One row per test: ID, class (C1-C10), owner (lane/agent),
   linked issue, opened date, **expiry ≤ 14 days**.
   - Swift: the body is wrapped in `withKnownIssue("Q-07 …", isIntermittent: true)`.
   - C++: a `quarantined` field on `TestEntry` that prints `[KNOWN-FLAKY]` instead of failing the gate.
   - A strict-gate step (a sibling of check-suppressions.sh) fails when an entry has expired, or when a quarantined test is
     not in the manifest. Quarantine never hides the test: the nightly runs it strictly.
5. **No silent retries in the merge gate.** A retry-until-green gate hides exactly the GREEN* class. If a retry is ever
   allowed, it must be at most one, print `FLAKY: <test>`, and fail the run unless the test is in the manifest.
6. **Make one CI cycle show every test failure.** Today the gate stops at the first failing step, so PR #91 needed 7 runs.
   Inside the "tests" section, run `swift test` (parallel), `swift test` (serial timing set), the null test, the verifiers
   and main-thread-stall; record each exit code; fail at the end with a list. Fail-fast stays for the cheap lint steps.
   (This overlaps the other panelists; it is listed here because it halves the cost of every flake.)
7. **At release close-out** (the founder's whole-app QA pass): run the nightly stress job by hand with `N=20`, and treat any
   flake as a release blocker or a dated quarantine row.

### 4.3 The order to fix the inventory in

Ordered by cost per avoided CI cycle, cheapest insurance first.

1. **Ceilings (half a day):**
   - `timeout-minutes` on the job and each step (P1);
   - `.timeLimit(.minutes(3))` on every suite with waits;
   - bound S12;
   - the C++ watchdog (N20);
   - fix `withDeadline` (V1);
   - timeouts on the VerifyAUGraph semaphores (V5).
   *Removes the 6-hour hang cost (5 items).*
2. **The two remaining High items that measure the machine:**
   - V6 main-thread-stall: hold until released, and a "waited on the lock" bound at hold scale;
   - N4 Profiler_Timing and its siblings N2, N3, N5, N6, N7, V3: thread CPU time, min-of-N, ≥ 10x tripwires in the gate,
     strict budgets in the perf lane;
   - S1: delete the bound.
   *Removes 11 C4 items. This is the largest family.*
3. **Isolation (1 day):**
   - a separate `--no-parallel` `swift test` step for Enhanced*, LiveReadouts, SpectrumHandoff and the stall-adjacent suites
     (P2, R10);
   - UUID defaults suites (S13, S14);
   - cap the main run's width if needed;
   - cut the `[UX]` log volume in tests (P3), e.g. send test runs' NSLog to a file.
4. **The free-running chains (2-3 days, the High item R4):**
   - the Enhanced rig waits on completions-delivered instead of pacing (R4, R9, R7);
   - LoudnessModule processed-frame hooks for N11-N13 (the same idea as 0fb9ddb).
5. **Fixed settles:** an injected tick/clock for S5-S7; a debounce flush for N8; a witness or condition for V7.
6. **Carry-on deadlines and short polls:** N9, N10, N15, N18 fail naming the state; R5, R7, N16 and N17 get hang-guard
   budgets.
7. **Negative windows get positive witnesses:** S4, S10, R6, R8, S11.
8. **Replayability:** a serial executor for the VM rigs (R2, R3, S3, S8, S9). Optional, worth it once MCP / W2 work starts.
9. **The process:** `make stress`, the semgrep rules, the nightly job and the quarantine manifest. Build `make stress` with
   step 1, because every later fix must prove itself with it (repeat-N under load, as ANALYZER-05's "5/5 under 16 CPU hogs"
   did by hand).

## 5. Sources opened

- swift-testing (github.com/swiftlang/swift-testing), all under `scratchpad/testrig/qa/web/`:
  - main: `Sources/Testing/Traits/TimeLimitTrait.swift`, `Traits/ParallelizationTrait.swift`, `Issues/Confirmation.swift`,
    `Issues/KnownIssue.swift`, `Running/Configuration.swift`, `Running/Runner.swift`, `Running/Runner+Repetition.swift`,
    `ABI/EntryPoints/EntryPoint.swift`;
  - DocC: `LimitingExecutionTime.md`, `Parallelization.md`, `MigratingFromXCTest.md`;
  - release/6.2 and release/6.3: `EntryPoint.swift` and `ParallelizationTrait.swift` (`ep-release-*.swift`,
    `pt-release-*.swift`).
- SwiftPM (github.com/swiftlang/swift-package-manager): `Sources/Commands/SwiftTestCommand.swift` on main, release/6.2 and
  release/6.3 (`stc-*.swift`).
- Point-Free:
  - swift-clocks README, `TestClock.swift`, `ImmediateClock.swift`;
  - swift-concurrency-extras README, `MainSerialExecutor.swift`, `Task.swift`, `ReliablyTestingAsync.md`;
  - files are in `qa/web/` and `src-pointfree/`.
- Apple developer documentation (JSON at developer.apple.com/tutorials/data/documentation/…):
  - `swift/withtaskgroup(of:returning:isolation:body:)`;
  - `xctest/xctestcase/measure(_:)`, `measure(metrics:options:block:)`;
  - `xctest/xctmeasureoptions/iterationcount`, `xctest/xctcpumetric`, `xctest/xctestcase/defaultperformancemetrics`;
  - `xctest/xctestcase/fulfillment(of:timeout:enforceorder:)`, `xctest/xctwaiter`;
  - `xctest/xctestcase/executiontimeallowance`.
- GoogleTest `docs/advanced.md` and `gtest-port.h`; Catch2 `docs/command-line.md`, `configuration.md`, `benchmarks.md`,
  `limitations.md` (`src-cpp-frameworks/`).
- libc++ `src/chrono.cpp` (`src-libcxx/`).
- GitHub docs `workflow-syntax.md` (`qa/web/gh-workflow-syntax.md`) and `runners.md` (`src-gh-docs/`).
- Probes (`scratchpad/testrig/qa/probe/`, swift-testing on Swift 6.3.2), each verified:
  - `.serialized` suites overlap; `--no-parallel` stops it;
  - `confirmation` does not wait;
  - SwiftPM rejects `--repetitions` / `--repeat-until` / `--maximum-repetitions`;
  - `swiftpm-testing-helper` honours them, exiting 1 on failure despite a "passed" summary under `--repetitions`;
  - `--filter` does not match display names or tags.
- `scratchpad/testrig/probe-cpu/`: wall vs thread CPU time under contention.
- Not verified by probe: the behaviour of `.timeLimit` on a blocked test. That comes from reading its source; the 80 s probe
  was stopped.
