# Testing: the four rules, the gate, and how to write a test

This is the test-rig contract for AdaptiveSound. The gate that runs it is described in
[DEVELOPMENT.md](DEVELOPMENT.md#quality-gates); the step registry is `scripts/gate/steps.tsv`.

## The four rules

1. **Time only ever breaks hangs.** A wait waits for a STATE, never for a clock. Its generous cap fails
   loudly, naming the state it was waiting for, and never carries on past a deadline. A hold is released
   only by the test that placed it.
2. **Measure the component, never the machine.** Count what the component did (a done hook, a counter),
   measure its own thread CPU time, take the minimum of N runs, and use ≥ 10× tripwires in the gate.
   Strict performance budgets live in the optimised timing tier (`make gate` runs `--opt-run`).
3. **Each test owns its world.** Its own storage and its own state. Blocking work stays off the shared
   test pool. Heavy real-engine suites run in their own non-parallel step.
4. **Every run has a ceiling and reports everything.** Each gate step has a timeout, each C++ test has a
   ceiling, and the gate runs every step to completion and shows every failure in one summary.

## The gate, in one paragraph

Every check is a row in `scripts/gate/steps.tsv`. `scripts/gate/run.sh` runs the rows collect-all: a
failure never stops the run, a skip is recorded with its reason, and each step has a watchdog that kills
its whole process group and names the timeout. A step that covers zero files or zero tests **fails**.
Toolchain parity runs first, always. CI runs the same rows as five parallel jobs plus one `strict-gate`
summary check (`scripts/gate/report.sh`).

## The C++ rig (`Tests/`)

The C++ null test is one binary built by `scripts/build-null-test.sh`, on GoogleTest 1.18 (the submodule
`third_party/googletest`, pinned in `toolchain/toolchain.env`).

- **Primitives and conventions:** `Tests/TestSupport.h` (the wait-for-state helper, the thread-CPU meter,
  min-of-N) and `Tests/NullTestRunner.h` (the per-test watchdog and the tier table). Read their header
  comments first; they hold the details.
- **Tiers:** `correctness`, `concurrent`, `accuracySweep`, `timing`. `--tier all` runs every tier; a `-tier`
  entry excludes one. Timing tests assert ≥ 10× tripwires in the plain build, and their strict budgets run
  in the `-O2` timing step (`--opt-run`).
- **Sharding:** `--shards N` runs N processes over the parallel-safe tests, plus one serial group.
  Two null-test processes from one checkout must never run at once, except through `--shards`, because
  they share `test-data/`. The runner serialises the null-test steps for you.
- **A hang:** a test that runs past its ceiling prints `[HANG] <Suite.Test> ran past its N s ceiling. Last
  progress: …` and the process exits **134** with no JSON. The gate reports that as a **named hang**, not a
  generic failure. Ceilings: 120 s (correctness), 300 s (timing), ×3 under ASan, ×8 under TSan.
- **Evidence:** every run writes GoogleTest JSON; `scripts/gate/null-run.sh` counts the tests across all
  of them and fails on zero.
- **Filters:** `--gtest_filter`, `--gtest_repeat`, `--gtest_shuffle`, `--gtest_random_seed`. A filter that
  selects nothing fails.

## Swift tests (`Tests/`)

Swift tests use swift-testing. Two rules the gate enforces:

- `swift test --filter` matches **function or type names**, not `@Test` display names. A misspelt filter
  runs zero tests and exits 0; `scripts/gate/swift-test.sh` turns that into a failure, and it also fails a
  test bundle that did not load.
- Every suite in a file that waits has a `.timeLimit`, and every wait names its state. `scripts/gate/timelimit-guard.sh` fails the gate otherwise (proven on a planted suite).

### RigKit: the one way a Swift test waits

`Tests/RigKit` is a plain library target that test targets (never a product target) depend on. It
`import`s Testing, so a failure it records lands on the caller's line. Every primitive has a
`withKnownIssue` proof in `Tests/RigKitTests` that it fails loudly. **A test here waits only through
these**; the semgrep rule `test-no-raw-time` bans `Thread.sleep`, `Task.sleep`, `usleep`,
`RunLoop.run(until:)`, `DispatchSemaphore` and `ContinuousClock.now +`/`<` in `Tests/` outside RigKit.

| Primitive | Use it for |
|---|---|
| `until("the state", cap:) { … }` | Any wait. Looks, yields, then naps; at its cap it **throws** `RigTimeout` naming the state and the line. The condition runs on the caller's actor (it may read a `@MainActor` model). Caps run on `SuspendingClock`, so a sleeping Mac cannot trip one. |
| `untilOnMainRunLoop("the state") { … }` | A state only a main-run-loop timer or main-queue block brings about. |
| `untilBlocking("the state") { … }` | The synchronous twin, only inside `blocking {}`. |
| `blocking("name") { … }` | Blocking test code (a render, a queue `sync`, a semaphore-like wait). Runs on a thread of its own: swift-testing's pool is one thread per core (three on CI), and a blocked pool thread starves every other test. |
| `OffPoolExecutor` | `Task(executorPreference:)` for an *async* body that blocks (a scan whose progress callback is held). |
| `Hold` / `withHold("what") { hold in … }` | Keep a producer at a point until the **test** releases it. The scope fails the test if the hold expired (its 300 s hang cap), was left held, or was never reached (`mayNotArrive:` opts out). The producer never records an issue itself. |
| `IsolatedDefaults("label")` | A `UserDefaults` suite named by a UUID and removed when released. Never a fixed suite name. |
| `LogTail`, `.attachingLogTail` | The product's `[UX]` log, kept in a ring while tests run (see below) and attached to every issue of a suite that carries the trait. |

### Product seams the rig drives (defaults are the app's behaviour)

- **The transport tick**: `AudioViewModel(makeTicker:)`. The app's is `RunLoopTicker` (a `.common`-mode
  `RunLoop.main` timer). A test passes `TickerBench().maker` and calls `ticker.fire()`.
- **Fire-and-forget work**: every view-model `Task` is spawned through `WorkTracker`. Wait with
  `try await viewModel.settled()` (work idle and the settings write landed). Never yield N times.
- **Clocks**: `clock: any Clock<Duration> = ContinuousClock()` on `LibraryModel`, `ShellToastSlot`,
  `EQBringBackMessage` and `SongsView`. Tests use swift-clocks (test targets only):
  `ImmediateClock()` makes a debounce a no-op (then await the task it started); `TestClock` only when the
  coalescing itself is under test, after `until` shows the sleep is pending.
- **Settings write**: `SettingsStore.pendingWrite`; `await store.pendingWrite?.value`.
- **A shuffle pass's edits, counted**: `ShufflePassTally` (PlaybackQueueKit), a task-local the app never holds. Run the
  edit inside `ShufflePassTally.$current.withValue(tally) { … }` (a task started inside inherits it) and read
  `tally.slotsMoved`: the slots the pass's line writers (insert, remove, `follow`'s one-pass build) wrote or shifted.
  A big edit is proven linear by that count, never by a clock (rule 2): `ShufflePassTests` VM-SP-16,
  `ShuffleBulkEditTests`.
- **The queue writer's book**: `AudioViewModel.queueStateBook` (`QueueStateBook`). Its `recordsBuilt` counts the whole
  resume records `queueStateNow()` built, so a test proves that a write of the playhead alone (the 5 s cadence, a pause,
  a scrub) builds none: `QueueStateEdgeTests` VM-QS-15, VM-QS-16.
- **An open waiting for the store**: `LibraryModel.isWaitingForStore` is true while a file open (Open With, a drop)
  waits in `openedStore()` for the library store to open. Wait for it before the test opens the store: BI-P05
  (`BreakItPlayerTests`).
- **The `[UX]` log**: `logUX` writes through `UXLog.sink` (`NSLog` in the app). `QuietLog.install()`
  (Tests/AdaptiveSoundTests) points it at the ring; the rigs and `IsolatedDefaults`-using view-model tests
  call it. Keep the sink a *struct holding a closure*: a bare closure in a `Mutex` is re-wrapped on every
  access and overflowed the stack after ~100,000 lines.
- **The Enhanced completion chain** (`StreamObserver`, `StreamLedger`): AVFAudio reports a buffer consumed
  ~150 µs *after* the render whose frames reach its end. `EnhancedTransportRig` renders in lock-step: after
  each block it waits (`untilBlocking`) until every completion due by the frames rendered has been handed
  on, then drains `resampleQueue`. No sleeps, no pacing.

### One engine double, no mirrors

A test of the view model drives the **real** `AudioViewModel` (`@testable import AdaptiveSound`). A double
provides inputs, never logic; a pure decision is tested in its Kit (`PlaybackQueueKitTests` for the queue).

- **`FakeEngine`** (`Tests/AdaptiveSoundTests/FakeEngine.swift`) is the one double of `AudioPlaybackEngine`.
  Inputs a test sets in `engine.state`: the devices, the whole snapshot (transport, signal path, loudness,
  the EQ's design rate), spectrum frames, and each call's outcome (an `initialize` that refuses or throws,
  a start error, a refused pick). The record: `calls`, every command in the order sent, with per-kind views
  (`starts`, `stops`, `picks`, `nextTracks`, …). The output choice is the product's `OutputDeviceSelection`.
- **`OnDeckEngineModel`** composes one (`engine.fake`): it keeps only the scripted transport and on-deck
  state machine (holds, hops, opens, seams, the ablations); everything else is the fake's.
- **Two rigs.** `Rig` (OnDeck) for what plays next: the engine seams into what was armed, or ends.
  `FakePlayer` for what the view model does with what the engine reports or answers: launched through
  `initializeEngine`, `engineReports(position:transitionCount:ended:)` stamps the newest request's epoch.
  Both fire the transport tick through `TickerBench`, so it runs only when the app's would.
- `SheetEngine` (`Sources/AdaptiveSound/Debug`) is for `make sheets` only; no test uses it.
- A new view-model test is first seen **failing against a planted bug** in the view model, then passing.

### How to write a waiting test

1. Name the state in words, then wait for it: `try await until("the seam to be counted") { bridge.gaplessTransitionCount == 1 }`.
2. To prove something does **not** happen, first wait for a **positive witness** that it had its chance (a
   count that moved, the stop's own completions delivered), then assert. A sleep window is never the proof.
3. To force an interleaving, **hold** the producer (`withHold`) until the other side has done its part. The
   hold ends only when the test releases it.
4. Code under test that blocks goes in `blocking {}` / `OffPoolExecutor`, never on the cooperative pool.
5. Give the suite `.timeLimit(.minutes(3))` (minutes is the granularity) and, for view-model suites,
   `.attachingLogTail`. Use `IsolatedDefaults`, never a fixed suite name or fixed path.
6. No wall-clock thresholds. Performance belongs to the C++ `-O2` timing tier, or thread CPU time with a
   ≥ 10× tripwire.

### Heavy real-engine suites run on their own

The `Enhanced…Tests` suites build a real offline `AVAudioEngine` graph and register AU subclasses
process-wide. Select them by type name: `--filter 'AdaptiveSoundTests\.Enhanced[A-Za-z]*Tests/'`. The
registry runs that selection with `--no-parallel` and the main run with the same pattern in `--skip`.

### Stressing a Swift test

`make stress TEST=<function or type name> N=10` (below). Strict pool width 1 plus hogs is the harshest
local profile. The exit code is the verdict, and every iteration must run at least one test.

## Repeating a test under load

Before merging a new or changed timing test, repeat it under the CI-like profile:

```bash
make stress TEST=prefetchPromoted N=50        # Swift: swift test --skip-build --filter, every iteration must run ≥ 1 test
make stress KIND=cpp TEST='Loud*' N=50        # C++: one process, repeat, shuffle, with a printed seed
```

The profile puts `ncpu − 3` CPU hogs in their own process group, each killed by a trap on any exit, and
sets `LIBDISPATCH_COOPERATIVE_POOL_STRICT=1`. The exit code is the verdict. Put the pass rate in the PR.
