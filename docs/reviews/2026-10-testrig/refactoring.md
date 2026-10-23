# Test-rig redesign: refactoring specialist's design (2026-10-20)

Panel member: refactoring specialist. Scope: the concrete code design of a rig in which the 13 problems in
`BRIEF.md` cannot recur. Review and design only: nothing in `Sources/` or `Tests/` was edited.

Code read at `.claude/worktrees/testrig-review` (= `r1.1a/integration` @ 22287da). The coordinator reports that
`Loudness_WorkersSleepWhileIdle` has since been fixed in f5d1329 (read below). Probes and opened upstream sources
are in `scratchpad/testrig/probe-repeat/` and `scratchpad/testrig/upstream/`.

---

## 0. The answer in plain words

Every timing flake in the brief comes from one of four habits. Each habit is easy to write today, and the safe
alternative is not:

| Habit | Brief items | What goes wrong | The rig's replacement |
|---|---|---|---|
| **A. "Wait a bit, then look."** A fixed sleep, a yield loop or a short deadline, after which the test carries on. | 2, 3, 7, and ~40 sites | On a slow runner the state isn't there yet. The test either asserts on half a state (false red) or, for a negative check, passes without testing anything (false green). | `until(...)`: wait for the state itself. Time is only a generous hang cap (minutes), and hitting it fails the test, naming what never happened. |
| **B. "Hold it, unless it takes too long."** A hold that releases itself on a deadline. | 3 | The test's premise breaks silently (ANALYZER-05: the hold gave up at 30 s and the prefetch finished early). | `Hold`: released only by the test. It is scope-checked, so a hold that expired, was never reached or was never released fails the test at the end of the scope. |
| **C. "Measure the machine."** Wall-clock durations, process-wide counters, % CPU from wall time. | 1, 4, 5, 6 | The number includes other threads, other processes, preemption, and even the Mac sleeping. | Measure the component: its own counters (`isParked`, `wakeCount`, fed frames), its own thread's CPU time (`CLOCK_THREAD_CPUTIME_ID`), and "did it finish while the resource was held" instead of "how long did it take". |
| **D. "Block a shared worker thread."** `Thread.sleep`, semaphores and condition waits inside async tests. | 3 (likely), 13 | On the 3-core CI runner the Swift cooperative pool, and with it swift-testing's parallelism, is 3 threads. Every blocked one starves unrelated tests (see §1.3). | `blocking { }`: run blocking test code on its own thread and await it. No async test blocks a pool thread. |

**Framework support (the founder's question), verified from opened sources:** swift-testing gives the reporting
and backstop pieces: `Issue.record(sourceLocation:)`, `withKnownIssue`, `.timeLimit` (minutes only), `--repetitions`
and `--repeat-until` (in the runner, but `swift test` 6.3 rejects them), and test-scoping traits. It has **no
"wait until" primitive**: `confirmation` checks its count when its closure returns and never waits. Point-Free's
**swift-clocks** is the right established library for injected time; adopt it as a test-only dependency. Point-Free's
**`withMainSerialExecutor`** is the wrong tool here: it is a process-global runtime hook, and in this codebase it
would deadlock ANALYZER-05. **GoogleTest/Catch2**: not now. The council's BT-3 reached the same conclusion, and
the C++ primitives that matter are not in them. The fail-loud wait, the hold and the in-process load must be small
home-grown code, about 250 lines in all, each with a self-test that proves it fails loudly.

---

## 1. Map of today's test-support code

### 1.1 Swift

| Piece | Where | What it is | Notes |
|---|---|---|---|
| `Rig` (OnDeck) | `Tests/AdaptiveSoundTests/OnDeckRig.swift:42-260` | The real `AudioViewModel` over `OnDeckEngineModel`. | **Already has the right wait:** `waitUntil` `:103-115` (20 s, throws `RigTimeout`). But `yieldToViewModel` `:179-183` is a yield-count heuristic, and `quiesce` `:206-226` is round-capped (4000) with 50 µs naps. |
| `OnDeckEngineModel` / `OnDeckEngineState` | `OnDeckEngineModel.swift:35-277`, `OnDeckEngineState.swift` | Scripted engine: holds transport ops (`holdTransport`, `runHeld`), steps hops and opens. | Deterministic by construction: the test chooses every order. Its no-op protocol surface (`:99-128`) duplicates `DeviceTestEngine` and `SheetEngine`. |
| `TransportScenarios` | `TransportScenarios.swift:27-139` | C-15 command-order scenarios on `Rig`. | `:33` calls `yieldToViewModel()` between overtaken runs. |
| `EnhancedTransportRig` | `EnhancedTransportRig.swift:18-308` | The real `AudioEngineBridge` on an offline engine. | `samples(paced:)` `:138-141` calls **`Thread.sleep` per 512-frame block** (real-time pacing on a cooperative thread). `PlayerRecording.samples` `:170-179` polls 200 × 10 ms, then returns `nil`. `frames(until:limit:)` `:185-195` is count-capped (good). |
| `EnhancedSeamTests` helpers | `EnhancedSeamTests.swift:238-252` | `settle` (`Thread.sleep(0.1)`, then `resampleQueue.sync`) and `waitFor` (100 × 10 ms, then `#require`). | `settle` is hope-based. The 1 s cap in `waitFor` is short. |
| `DeviceTestEngine` | `DeviceTestEngine.swift:15-176` | Recording engine on the real protocol. | `:79` `func setNextTrack(_: URL?) async {}` is **not** a protocol requirement (the protocol's is `setNextTrack(_:ticket:)`, `AudioPlaybackEngine.swift:162`). It is dead drift. |
| `MockAudioEngine` + `AudioPlaybackEngineMirror` | `Tests/AudioViewModelTests/MockAudioEngine.swift:19-292` | Mirror protocol and mirror types. | Its own header says "NOT the current protocol's shape" (`:35-41`). DUP-2: already drifted. |
| `MockAdvanceController` | `Tests/AudioViewModelTests/MockAdvanceController.swift` | A copy of the VM's auto-advance state machine. | BT-1/DUP-2: about 61 tests prove a copy. |
| `SheetEngine` | `Sources/AdaptiveSound/Debug/SheetEngine.swift:11-71` | Product debug fake for `make sheets`. | The fourth engine double. |
| `RecordingSink` | `Tests/TrackLoudnessKitTests/TrackLoudnessAnalyzerTests.swift:140-232` | Sink plus a prefix hold. | Hold: `NSCondition` with a 300 s cap (`:175-183`). It sets `expired`, which a test must **remember** to check (`:101`). `wait` (`:213-225`) records an Issue at 300 s, **then `break`s and returns**, so the test carries on. `idle(for:)` (`:229-231`) is a negative window. |
| `LogRecorder`, `Fixtures` | same file `:242-308` | | Fine. |
| Ad-hoc flags | `LibraryScanRaceGTests.swift:21-31` `Signal`; `SweepEvidenceTests.swift:320` `Flag`; `LiveReadoutSpeechTests.swift:17` `Flag`; `SpectrumHandoffTests.swift:18` `StopFlag` | Four home-grown one-bit latches. | Replace with `Synchronization.Atomic` or `Hold`. |
| Five copies of `settle()` | `CrossfeedPlaysTests.swift:36-40`, `LiveReadoutsTests.swift:28-32`, `ListeningSettingsTests.swift:59-63`, `SeekViewModelTests.swift:33-37`, `OutputDeviceViewModelTests.swift:61-65` | `for _ in 0..<50 { await Task.yield() }` | All identical. The VM's work is fire-and-forget `Task {}` (§3.3), so there is nothing to await. |
| `endTurn()` | `SettingsStoreTests.swift:33-37`; `R11aSettingsBreakTests.swift:126-128` | 10 yields | `SettingsStore.save` does `Task { self.flush() }` (`Sources/SettingsKit/SettingsStore.swift:74`). |
| `OutputWorld` | `Tests/OutputDeviceKitTests/OutputWorld.swift:10-128` | A pure value model of CoreAudio over the real Kit rule. | No time and no threads. **This is the model to copy**: decisions in a Kit, a world as data. |
| Time as data | `LibraryBrowseKit` `TypeSelectBuffer.swift:23`, `ListSelection.swift:195`, `GridCursorState.swift:34` (`at now: ContinuousClock.Instant`) | Pure decisions take `now` as a parameter. | **Already the house pattern.** Keep it for Kit decisions. Clock injection is only for the scheduling shells (§3.2). |
| Structured waits (good) | `VolumeMonitorPauseTests.swift:62-66` awaits `reconcileDebounce[...]?.value` and `walkTasks[...]?.value`; `EnhancedSeekTests.swift:164-174` uses a continuation on `configChangeQueue` | Waits on the product's own task or queue. | The gold standard. But the first one pays the product's real 1 s debounce (`LibraryModel+Reconcile.swift:128`). |

### 1.2 C++ (`Tests/DSPKernelNullTest.cpp` + `TestSupport.h` + `*.inc`)

| Piece | Where | Notes |
|---|---|---|
| Runner | `TestSupport.h:621-771`; `main` `DSPKernelNullTest.cpp:~540-632` | `--parallel`, `--list`, exact `--filter=`. **No per-test watchdog, no elapsed time, no repeat, no load.** The gate runs it serially (`build-null-test.sh:184-188`). The CI job has **no `timeout-minutes`** (`.github/workflows/strict-ci.yml`), so a deadlock costs GitHub's 6 h default. |
| `spinUntil` | `RenderGateTests.inc:22-37` | Yield-count bound (20 M), fails loudly, no wall clock. **Good, but local to one file.** |
| `SeamPause` + `seamPauseHook` | `GaplessArmContractTests.inc:630-700` | Deterministic handshake through the product's test points. Its waits are **unbounded** `while (!flag) yield()` loops (`:617-628`, `:676-680`, `:692-697`), so a regression hangs the binary. |
| Product test points | `Sources/AudioDSP/include/GaplessSource.h:172-190, 235-240`; `GaplessSource.cpp:312-325, 212, 372, 374`; enabled by `-DADAPTIVESOUND_GAPLESS_TEST_HOOKS=1` (`scripts/build-null-test.sh:142`) | Compiles to nothing in the app. **The right pattern**, but specific to one class. |
| Poll budgets | `PureGaplessTests.inc:46-49` (4000 × 1 ms; `pollGaplessEnded` 200 × 1 ms `:103-115`); `FileDecodeTests.inc:231-233` (100 attempts × 2 ms; `pollFinished` 60 × 2 ms ≈ 120 ms `:460-470`); `GaplessArmContractTests.inc:46, 91-99` (`openArmTrack`: 20 000 × 100 µs, then **returns the source anyway**) | Short attempt-times-nap budgets for a background decode thread, which is slow under TSan or load. Some carry on silently. |
| Telemetry that exists | `DSPKernel::causalLoudnessFedFrames()`; `GaplessSource::reapCount()/hasPendingReap()`; `Realizer::barrier()`, `loudnessGain().needsRefresh()/causalSeconds()`; since f5d1329 `WorkerParking::isParked()/wakeCount()` | These are the seams tests should wait on. |

### 1.3 The cooperative-pool hypothesis (item 3; flagged as a hypothesis)

- The `macos-26` arm64 runner has **3 vCPU (M1), 7 GB** (GitHub docs, opened:
  https://docs.github.com/en/actions/reference/runners/github-hosted-runners).
- swift-testing runs tests in parallel "using task groups … The number of tests that run concurrently is
  controlled by the Swift runtime" (`Parallelization.md`, opened:
  https://github.com/swiftlang/swift-testing/blob/main/Sources/Testing/Testing.docc/Parallelization.md). The pool
  therefore has 3 threads.
- In `pr91-failed6.log`, ANALYZER-01, 02, 03, 04 and 06 **all "passed after 19.190 seconds"**, and 05 failed
  after 39.8 s. Six-second fixtures took 19 s, all finishing together: a starved pool.
- Blocking calls on pool threads in today's tests: `EnhancedTransportRig.swift:139` (paced `Thread.sleep`, 18
  call sites); `EnhancedSeamTests.swift:239, 247`; `TransportSnapshotTests.swift:36, 40, 55` (semaphores);
  `RecordingSink` `:176-182` (the analyzer's `Task.detached` decode blocks on `NSCondition`);
  `LibraryScanRaceGTests.swift:58` (`Thread.sleep(0.2)` per batch inside the scanner's task).
- **Recommended check before relying on this** (QA lane, S): log `ProcessInfo.activeProcessorCount` and per-test
  durations in one CI run, then move the paced rigs off-pool (§2.1 `blocking`) and compare suite time.

---

## 2. The primitives

### 2.1 Swift: `RigKit` (a new library target at `Tests/RigKit`, depended on only by test targets)

**Probe (passed):** a plain `.target(name: "RigKit", path: "Tests/RigKit")` that does `public import Testing`
builds with Swift 6.3.2 / tools 6.2. An `Issue.record(sourceLocation:)` inside it lands on **the caller's line**
(`scratchpad/testrig/probe-repeat/Tests/RigKit/Until.swift`; the output showed
`recorded a known issue at UntilTests.swift:11`). Point-Free's `ConcurrencyExtrasTestSupport` is built the same
way: a regular target that does `public import Testing`
(https://github.com/pointfreeco/swift-concurrency-extras/blob/1.4.3/Sources/ConcurrencyExtrasTestSupport/TaskLocalTrait.swift).
Periphery already excludes `**/Tests/**` (`.periphery.yml:20-26`).

```swift
// 1. Fail-loud wait. Never returns on failure; time is only the hang cap.
public func until(_ what: String,
                  cap: Duration = .seconds(120),          // a hang breaker, never a pass/fail line
                  sourceLocation: SourceLocation = #_sourceLocation,
                  _ condition: () async throws -> Bool) async throws
// Backoff: Task.yield ×64, then 1 ms sleeps (cancellation-aware, so `.timeLimit` can end it).
// At the cap it throws RigTimeout("never reached: <what> after <cap>, at <file:line>"). It throws only,
// with no separate Issue.record: the probe showed record + throw reports twice.

// 2. Blocking code off the cooperative pool (habit D).
public func blocking<T: Sendable>(_ name: String, _ work: @escaping @Sendable () throws -> T) async throws -> T
// Runs `work` on a dedicated Thread and resumes through a continuation.
// Use for: paced offline renders, semaphores, Thread.sleep-based pacing, queue.sync drains.

// 3. A hold that only the test releases (habit B).
public final class Hold: Sendable {
    public func wait()                 // PRODUCER side, any thread: blocks until release().
                                       // Hang cap 300 s → marks `expired` and returns. It never records an
                                       // Issue from the producer thread (see the note below).
    public func arrived() async throws // TEST side: until(the producer is waiting), fail-loud
    public func release()
}
public func withHold<R>(_ name: String, sourceLocation: SourceLocation = #_sourceLocation,
                        _ body: (Hold) async throws -> R) async throws -> R
// At scope exit, ON THE TEST'S TASK: an Issue if the hold expired, was reached but never released by the
// test, or (unless `mayNotArrive: true`) was never reached. It is scope-checked, like swift-testing's own
// `confirmation`, so nothing can be forgotten. Today's `holdExpired` (TrackLoudnessAnalyzerTests.swift:101)
// is opt-in.

// 4. Test points: "pause the producer at point X" (the Swift form of GaplessSource's hook).
public final class TestPoints<Point: Hashable & Sendable>: Sendable {
    public func reach(_ point: Point)                       // producer: waits if a Hold is armed at `point`
    public func hold(at point: Point) -> Hold               // test: arm before the action
}

// 5. Work that is in flight (needs the product seam in §3.3).
//    The test writes `try await until("the view model's work landed") { vm.work.isIdle }`
//    instead of 50 yields.

// 6. Load in-process, so it cannot leak (brief item 13).
public struct UnderLoad: TestTrait, SuiteTrait, TestScoping
// When the env var RIG_LOAD=k is set, it spins k busy threads for the duration of the test, joined at the
// end. They die with the process: no leaked shell loops. Uses swift-testing's TestScoping
// (ST-0007, the same mechanism as TaskLocalTrait above).
```

**Why the producer never calls `Issue.record`** (opened source): in the 6.3 release, an event posted from a
thread that has no current test configuration "will be lost! Post it to every registered event handler" (that
is, broadcast with no test attached;
https://github.com/swiftlang/swift-testing/blob/release/6.3/Sources/Testing/Events/Event.swift, `_post`, around
lines 320-345). `main` adds attribution by source location, but 6.3 does not have it. So the producer stores the
failure, and the scope reports it on the test's own task.

**Self-tests (required):** every primitive has a `withKnownIssue` test proving that it fails loudly. The probe
`untilFailsLoudAtCap` already shows the pattern. This is the "plant-a-leak" idea applied to the rig itself.

**Swift backstop:** every suite that waits declares `.timeLimit(.minutes(5))`. It only catches hangs. The
granularity is minutes only (`TimeLimitTrait.swift`, "The time limit must be at least one minute"; the local
6.3.2 `.swiftinterface` marks `.seconds/.milliseconds` unavailable). It cancels the test task, which ends
`until` but not a blocked thread. That is one more reason for `blocking {}`.

### 2.2 C++: additions to `TestSupport.h`

```cpp
// 1. Fail-loud wait (promotes RenderGateTests.inc:22-37 `spinUntil`; replaces every attempt × nap budget).
template <typename Pred>
[[nodiscard]] bool waitUntil(const char* what, Pred pred,
                             std::chrono::seconds cap = std::chrono::seconds{120});
// yield ×1000, then 1 ms naps; on the cap: logFail(currentTest, "never reached: <what> after <cap>")
// and return false, so the caller returns. No caller may "carry on" after false (a clang-tidy
// bugprone-unused-return-value / [[nodiscard]] check enforces this).

// 2. Rendezvous: GaplessArmContract's SeamPause, generalised and bounded.
template <typename Point> class Rendezvous {
  public:
    void arm(Point p);                              // test: the producer will stop at p
    void reach(Point p) noexcept;                   // producer (from the product's test hook): if armed,
                                                    // mark arrived, then std::atomic::wait for release
    bool awaitArrival(Point p, const char* what);   // test: waitUntil(arrived)
    void release(Point p);                          // test
    ~Rendezvous();                                  // logFail if an armed point was reached but not released
};

// 3. Watchdog: a per-test hang cap that names the test (council BT-3 item 4).
//    --hang-cap=SECONDS (default 600). A std::jthread that is JOINED, never detached (.semgrep.yml
//    `cpp-no-thread-detach`), prints "[HANG] <test> exceeded N s" and calls std::abort() (sanitizer
//    builds then print the stacks). Plus per-test elapsed time on every PASS/FAIL line (BT-3 item 1).

// 4. Stress driver in the binary itself (brief item 13: no shell loops, nothing to leak).
//    --repeat=N, --until-fail, --load=K (K busy std::jthreads for the run, joined at exit),
//    --filter=<glob>. A filter that matches nothing is an error, not a pass.

// 5. Measure the component, not the process.
struct ThreadCpu {  // clock_gettime(CLOCK_THREAD_CPUTIME_ID): CPU used by THIS thread only
    static double nowSeconds() noexcept;
};
template <typename Fn> double bestOfThreadCpu(int repeats, Fn fn); // the minimum over repeats
```

**Rules that go with them** (to add to `docs/architecture/validation-strategy.md`):

1. **Time is never a pass/fail line in a correctness test.** It only breaks hangs. The property is a count, a
   state or an order.
2. **Prove "never blocks" by completion under an indefinite hold, not by duration.** Hold the resource until
   the reader's work is done. If the reader would wait, it cannot finish, the hold never ends by itself, the hang
   cap fires, and the failure names the reader. This applies to VM-TS-02 and the main-thread-stall rig (§4).
3. **Measure the component:** its own counters, or its own thread's CPU time. Never `getrusage(RUSAGE_SELF)`
   and never wall time for "% of a core". `man clock_gettime` (local): `CLOCK_UPTIME_RAW` "does not increment
   while the system is asleep"; `CLOCK_THREAD_CPUTIME_ID` "tracks the amount of CPU … used by the calling
   thread". Item 6's 90 600 % reading cannot happen with the thread-CPU clock.
4. **Performance budgets** run only in an `-O2` run stage and only on tests tagged `timing` (council BT-12). Use
   the minimum of N runs of thread-CPU time. Taking the minimum over repeats is standard practice; Python's
   `timeit` documentation makes this argument (cited from memory, not opened in this session).
5. **Negative checks** ("X must not happen") need a positive end-marker: wait until the system has handled
   everything that could cause X, then check. A sleep "window" is acceptable only as an extra, never as the
   proof (e.g. ANALYZER-04's 500 ms idle, `TrackLoudnessAnalyzerTests.swift:76`).

**Done example: f5d1329** (`Loudness_WorkersSleepWhileIdle`). `WorkerParking` now exposes `isParked()` (waiting,
and no wake handed since it began to wait) and `wakeCount()`. Only the worker writes them; the render thread never
touches them. The test waits until each worker is parked, reads its count and requires it to stand still. Other
threads' context switches cannot affect it, so the tolerance can be zero. This replaced process-wide
`getrusage(ru_nvcsw + ru_nivcsw)` against a limit of 10, where CI saw 11 (`pr91-failed7.log`: "kernel at rest
woke 11 times", i.e. threads that were not the worker). This is the template for §3.4.

### 2.3 Enforcement: make the unsafe way visible

- **A semgrep rule `test-no-raw-time`** over `Tests/**`, excluding `Tests/RigKit/**` and `Tests/TestSupport.h`.
  It flags `Thread.sleep`, `Task.sleep`, `usleep`, `std::this_thread::sleep_for`, `ContinuousClock.now`,
  `Date()`, `steady_clock::now`, `getrusage`, `RunLoop.main.run(until:`, `DispatchSemaphore(...).wait()`
  inside `async` functions, and `for _ in 0 ..< N { await Task.yield() }`. Justified sites (race drivers that
  pace on purpose, e.g. `LoudnessOracleTests.inc:664`) use the existing suppression policy (owner / reason /
  expiry, `strict-gate.sh` "Suppression policy" step). This is "fix the root, never bypass": the rule names the
  primitive to use instead. Write it with `pattern-not-inside` comment handling; brief item 11's comment-word
  false match is a known semgrep trap.
- **`timeout-minutes`** on the strict-CI job, as a backstop above the C++ watchdog.

---

## 3. Product-code seams (smallest changes, real-time safe)

All of these follow `docs/architecture/architecture.md` §Threading rules: the main thread only touches
main-actor bookkeeping, and the render thread gets nothing new (at most a read of a counter it already writes).

| # | Seam | Where | Change | Thread-rule check |
|---|---|---|---|---|
| 3.1 | **A ticker for the 20 Hz transport tick** | `AudioViewModel+TransportTick.swift:37-48` (`runTransportTickIfLive` builds a `Timer`) | Inject `makeTicker: @MainActor (@escaping @MainActor () -> Void) -> any Ticker`. The default is the same `RunLoop.main` `.common` Timer. The test's `ManualTicker` has `fire()` and `isRunning`. `tickTransport()` and `disarmTransportTick()` already exist "for tests that tick by hand" (`:26-31`). | Main actor only. No AVFAudio. |
| 3.2 | **An injected `Clock` for debounces and lifetimes** | `AudioViewModel+QueueMirror.swift:21-29` (250 ms); `LibraryModel+Reconcile.swift:128` (1000 ms); `UI/Shell/ShellToast.swift:40`; `UI/EQ/EQBringBackMessage.swift:80-83`; `UI/Library/SongsView.swift:37` | Init parameter `clock: any Clock<Duration> = ContinuousClock()`. That is the **stdlib protocol**: the product takes on no dependency. Tests pass swift-clocks' `ImmediateClock` (the debounce becomes a no-op; then await the task handle), or `TestClock` when the coalescing itself is under test. | No thread change. |
| 3.3 | **In-flight work tracker** (kills the five `settle()` copies) | VM fire-and-forget `Task {}` at `AudioViewModel+Devices.swift:39, 63`, `+Lifecycle.swift:24`, `+PlayTracking.swift:67`, `+Playback.swift:60, 96, 154`, `+Queue.swift:197`; `SettingsStore.swift:74` | A `@MainActor final class WorkTracker { func spawn(...) -> Task; var isIdle: Bool; func idle() async }`: a counter incremented at spawn and decremented on completion. `SettingsStore` exposes `pendingWrite: Task<Void, Never>?`. | Main-actor counter. Detached tasks keep their QoS. |
| 3.4 | **Worker telemetry, as f5d1329 did** | `LoudnessModule` (the meter worker) | `meterFedFrames()` like `DSPKernel::causalLoudnessFedFrames()`: a read of the ring's consumer index or a worker-side counter. It replaces "paced" sleeps (`EqEngineBreakItTests.inc:171`, `EqEngineTests.inc:466`, `EqEngineFixTests.inc:584`) and "sleep then read" (`LoudnessTests.inc` 100 ms reads, `EqEngineBreakItTests.inc:182, 186`) with "wait until fed == pushed". | Worker writes it, any thread reads it. The render thread is unchanged. |
| 3.5 | **Test points, generalised** | `GaplessSource.h:172-190, 235-240` (`ADAPTIVESOUND_GAPLESS_TEST_HOOKS`) | Move the hook type and `atTestPoint` into `include/TestPoints.h`: `template <typename Point> struct TestPointHook`, compiled to an empty inline unless `ADAPTIVESOUND_TEST_POINTS` is defined (the null test's build only). GaplessSource keeps its three points. New points are added **only when a test needs one**: no speculative hooks. | In the app it compiles to nothing. In the test build: one acquire load. |
| 3.6 | **The analyzer's hold point** | `TrackLoudnessAnalyzer.swift:166-170` (the decode on `Task.detached`) | No product change needed: the sink is the seam. `RecordingSink` uses `Hold`. Optional: an `init(…, taskPriority:)` so tests can avoid utility-QoS starvation. Weigh this: it changes nothing in the app. | n/a |

**Seams deliberately not proposed:** a deterministic Swift executor for the product (§5); hooks inside
`RenderGate` (its tests already force their orders with atomics); anything on the render path beyond
existing counters.

---

## 4. Migration plan: every timing-dependent site found

Effort: S ≤ ½ day, M ≤ 2 days, L > 2 days. "Order" is the phase in §4.1.

### Swift

| # | Site (file:line) | Today | Target | Effort | Order |
|---|---|---|---|---|---|
| S1 | `TrackLoudnessAnalyzerTests.swift:140-232` (`RecordingSink`), uses at `:23, 40, 42, 55, 57, 74, 91, 93, 98, 100, 114, 116` | `wait` records an Issue, then carries on (`:217-221`); the hold's `expired` flag is opt-in (`:101`); 10 ms polling | `until` with the predicate over events (or a signal from the sink); `withHold` for ANALYZER-05; await `hold.arrived()` instead of polling for the prefix event | S | 1 |
| S2 | `TrackLoudnessAnalyzerTests.swift:76, 229-231` (ANALYZER-04's 500 ms idle) | Sleep window as the negative proof | End-marker: request a third, cached track after the short one, wait for its republish (requests are handled in order: `TrackLoudnessAnalyzer.swift:58-67`), then assert that no long-track whole exists | S | 1 |
| S3 | `EnhancedTransportRig.swift:127-144` (paced `Thread.sleep`), 18 call sites in `EnhancedSeamTests`, `EnhancedEndOfQueueTests`, `EnhancedSeekTests`, `EnhancedResamplerTests` | Blocks pool threads in real time | Run the pull loop inside `blocking {}`. Keep the pacing (the completion chain needs device time) but off-pool | S | 1 |
| S4 | `EnhancedTransportRig.swift:170-179` (`PlayerRecording.samples`, 200 × 10 ms) | 2 s cap, then nil | `until("the tap delivered N frames")`, cap 120 s, inside `blocking` | S | 1 |
| S5 | `EnhancedSeamTests.swift:238-241` (`settle`: sleep 0.1 s) | Hope | Drop the sleep: `resampleQueue.sync {}` already drains the queue. If a completion is still in flight, `until` its effect | S | 1 |
| S6 | `EnhancedSeamTests.swift:244-252` (`waitFor`, 1 s) | Short cap | `until` | S | 1 |
| S7 | `EnhancedEndOfQueueTests.swift:90` (`Task.sleep(300 ms)`, then `!ended`) | Sleep as the negative proof | End-marker: `until(player is not playing && resampleSession == nil)` (or whatever the stop's last completion sets), then `resampleQueue.sync {}`, then assert | S | 1 |
| S8 | `TransportSnapshotTests.swift:28-57` (VM-TS-02) | `slowest < 5 ms` wall-clock assertion; semaphores block a pool thread | Rule 2: the publisher stays stuck until the reads finish; the property is "60 reads completed while stuck". Keep the duration as info only. Run in `blocking {}` | S | 1 |
| S9 | `SpectrumHandoffTests.swift:42-54` | 1 s window; `reads > 100` | Count-based: run until R reads **and** W writer laps that overlapped a read (an atomic "writer is mid-write" witness). Join the writer thread | S | 2 |
| S10 | `LibraryScanRaceGTests.swift:56-63` | `Thread.sleep(0.2)` per batch makes overlap only likely; unbounded 1 ms poll | `withHold`: walk A holds at its first batch until walk B has written a batch (B's progress callback releases it). Overlap is then certain. `until` with a cap | S | 2 |
| S11 | Five `settle()` copies (§1.1) and `OnDeckRig.swift:179-183` `yieldToViewModel`, `TransportScenarios.swift:33`, `TransportExplorerTests.swift:167` | 50/40/8 yields | `until { vm.work.isIdle && <state> }` (needs seam 3.3). In TransportScenarios, keep the yield only where it is part of the scenario's ordering, and say so | M | 3 |
| S12 | `LiveReadoutsTests.swift:35-37`; uses `:104, 117, 123, 125, 144` | `RunLoop.main.run(until: now+0.35)` for both positive and negative checks | Seam 3.1: `ManualTicker.fire()` n times. "Paused, nothing reads" becomes `!ticker.isRunning` plus a read count after k fires | M | 3 |
| S13 | `SettingsStoreTests.swift:33-37`, `R11aSettingsBreakTests.swift:126-128` | 10 yields | `await store.pendingWrite?.value` (seam 3.3) | S | 3 |
| S14 | `VolumeMonitorPauseTests.swift:64` (real 1 s debounce per step) | Correct but slow | Seam 3.2 with `ImmediateClock` | S | 3 |
| S15 | `OnDeckRig.swift:103-115, 206-226` | Already fail-loud | Re-point onto `RigKit.until`. Delete `RigTimeout` duplication | S | 3 |
| S16 | `CoalescingWriterTests.swift:26, 28` | Yields **inside the fake writer** to create suspension points | Fine: this is a scenario, not a wait. Leave it, with a suppression comment | — | — |

### C++

| # | Site (file:line) | Today | Target | Effort | Order |
|---|---|---|---|---|---|
| C1 | `LoudnessTests.inc:270-390` `Loudness_WorkersSleepWhileIdle` | Process `getrusage` | **Done, f5d1329** (`isParked`/`wakeCount`). Also check the commit's 100 ms "sleep then read" lines; if still present, wait on fed frames (seam 3.4) | — | done |
| C2 | `RenderGateTests.inc:22-37` | Local `spinUntil` | Move it to `TestSupport.h` as `waitUntil`. RenderGate keeps its yield-count semantics through the same helper | S | 0 |
| C3 | `GaplessArmContractTests.inc:91-99` `openArmTrack` | 2 s budget, then **returns an undecoded source** | `waitUntil("decoder finished", src->decoderFinished())`; on false, `nullptr` (the callers already handle that) | S | 1 |
| C4 | `GaplessArmContractTests.inc:617-628, 676-680, 692-697` (`SeamPause`) | Unbounded yields | `Rendezvous<TestPoint>` (bounded, names the point) | M | 1 |
| C5 | `PureGaplessTests.inc:46-49, 90, 103-115, 269`; `GaplessContractTests.inc:111, 354, 456`; `SoakRtAllocTests.inc:453` | 4000 × 1 ms / 200 × 1 ms budgets; `pollGaplessEnded` returns the result late | `waitUntil` (120 s cap); count-based drain loops keep their structure. In Soak, the armed thread may only sleep (no alloc), so keep `sleep_for` under a suppression | S | 2 |
| C6 | `FileDecodeTests.inc:231-233, 443-470, 158, 1618` | 100 attempts × 2 ms; `pollFinished` ≈ 120 ms | `waitUntil` | S | 2 |
| C7 | `LoudnessNeutralTests.inc:571-578, 803-808` | 10 s deadline, then **carries on** | `waitUntil`, and fail on false | S | 1 |
| C8 | `LoudnessNeutralTests.inc:650` | Fixed 400 ms, then reads the refreshed gain | `waitUntil(!needsRefresh())` + `barrier()` (both exist) | S | 1 |
| C9 | `EqEngineBreakItTests.inc:171, 182, 186`; `EqEngineTests.inc:466`; `EqEngineFixTests.inc:584` | Paced 0.5–1 ms per block, "so the worker keeps up"; 50 ms, then read | Seam 3.4: push a block, then `waitUntil(meterFedFrames() == pushed)`. No pacing | M | 3 |
| C10 | `EqTransitionTests.inc:383-428`, `EqEngineFixTests.inc:924-946`, `EqEngineBreakItMeasurements` (ungated) | `steady_clock` wall time as "% of one core"; per-flavour constants | `bestOfThreadCpu`; tag `timing`; asserted only in the new `-O2` run stage (BT-12); sanitizer and debug builds report only | M | 4 |
| C11 | `EqDesignerTests.inc:1566-1622`; `TrackLoudnessTests.inc:2068-2074, 2115-2175`; `LoudnessNeutralTests.inc:834-885` | Wall-clock mean per call; three `#if` budgets | Same as C10 | M | 4 |
| C12 | `EqEngineTests.inc:1030-1090` (`Realizer_ReinitDuringDrain`, `burstWorst ≤ 4 × idleWorst + 10 ms`) | Wall-clock ratio | The property is liveness ("reinit is not starved by a busy control thread"). Assert completion with `waitUntil`; report the ratio as info; tag `timing` | S | 4 |
| C13 | `SnapshotConcurrencyTests.inc:258-262` | 2 s, then `verdict()` fails if nothing was accepted | Already fails loudly. Move it onto `waitUntil` for one idiom | S | 2 |
| C14 | `SoakRtAllocTests.inc:268-276` | Per-block ns, **info only** | Leave it | — | — |
| C15 | `LoudnessOracleTests.inc:664`, `EqEngineTests.inc:1064` | Pacing that makes a race driver jitter | Intentional. Suppress with a reason | — | — |

### The two rigs outside `Tests/`

| # | Site | Today | Target | Effort | Order |
|---|---|---|---|---|---|
| R1 | `make main-thread-stall` (`Sources/AdaptiveSound/Debug/MainThreadStallRig.swift`; Makefile `:110-121`: lock held 2.5 s; no entry ≥ 25 ms; ≤ 1 % over 5 ms; the main queue may not wait 25 ms) | Durations under machine load (item 5: 31.5 ms with three gates running) | Rule 2: hold the engine lock until the main thread has run all of its entries and serviced K probe blocks; the oracle is that all of them completed while the lock was held. Durations become info, with one gross tripwire (≥ 1 s). Later, move the rig into `Tests/` (BT-2) | M | 2 |
| R2 | Stress scripts (item 13) | Shell loops that leaked 16 busy loops | Swift: `scripts/stress-swift.sh <function> <N>` builds once, then runs the toolchain's `swiftpm-testing-helper --repetitions N --repeat-until fail --filter <function>` with `RIG_LOAD=k` (in-process `UnderLoad`), and **fails if "with 0 tests"**. C++: `DSPKernelNullTest --filter=… --repeat=N --until-fail --load=K` | S | 0 |

**Probe facts behind R2** (`scratchpad/testrig/probe-repeat`):
- `swift test -- --repetitions 3` fails: "error: 2 unexpected arguments".
- `swiftpm-testing-helper --test-bundle-path B B --testing-library swift-testing --repetitions 3` ran the test 3
  times. It needs `DYLD_FRAMEWORK_PATH=<Xcode>/Platforms/MacOSX.platform/Developer/Library/Frameworks`.
- `--repetitions 4 --repeat-until fail` ran 4 times.
- `--filter 'display name'` ran **0 tests and reported "passed"**. `--filter <functionName>` ran 1.
- Swift 6.4 adds `swift test --maximum-repetitions/--repeat-until` (ST-0024, "Implemented (Swift 6.4)":
  https://github.com/swiftlang/swift-evolution/blob/main/proposals/testing/0024-per-test-case-repetitions.md).
  Switch the script over when the toolchain moves.

### 4.1 Order (phases)

- **Phase 0, the primitives with their self-tests (S–M, one lane):** `RigKit` (`until`, `blocking`, `Hold` /
  `withHold`, `TestPoints`, `UnderLoad`) plus `withKnownIssue` self-tests; `TestSupport.h` `waitUntil`,
  `Rendezvous`, watchdog with per-test elapsed, `--repeat/--until-fail/--load/--filter glob`, `ThreadCpu`;
  `stress-swift.sh`; `timeout-minutes` in CI. Nothing is migrated in this phase, so it is low risk and lands first.
- **Phase 1, the sites that have flaked or carry on silently:** S1–S8, C3, C4, C7, C8. Each is proven by
  stressing it under load with the Phase 0 driver (process.md §4.4's rule) and once under TSan.
- **Phase 2, latent short budgets:** S9, S10, C5, C6, C13, R1.
- **Phase 3, the seams in §3 and what they unlock:** 3.1–3.4 → S11–S15, C9. Then **turn on the
  `test-no-raw-time` semgrep rule**: from here on, a new raw sleep fails lint.
- **Phase 4, the performance lane:** C10–C12 with the `-O2` run stage and `timing` tags (BT-3, BT-12).

Phases 0 and 1 are one lane-sized piece of work. Phases 2–4 can ride with the sprints that touch those files.
Which sprint carries them is the founder's call (sprint boundaries).

---

## 5. Library and framework decisions (opened sources)

| Need | Choice | Evidence (opened) | Verdict |
|---|---|---|---|
| Report a failure at the caller's line | swift-testing `Issue.record(_:sourceLocation:)` | Local 6.3.2 interface `Testing.swiftmodule/arm64-apple-macos.swiftinterface:715-717`; probe | **Use** |
| Prove a primitive fails loudly | `withKnownIssue` | Interface `:100-102`; probe | **Use** |
| Hang backstop | `.timeLimit(.minutes(n))` | `TimeLimitTrait.swift` (https://github.com/swiftlang/swift-testing/blob/main/Sources/Testing/Traits/TimeLimitTrait.swift): minutes only, cancels the body | **Use per waiting suite**. It is not a wait |
| "Wait until a state" | — | `Confirmation.swift`: "When the closure returns, the testing library checks if the confirmation's preconditions have been met" (the `defer` at around `:183`). It does not wait. `testing-asynchronous-code.md` offers only `confirmation`. No evolution proposal adds a waiting confirmation (ST-0001…0029 listed) | **Home-grown `until`** (~30 lines) |
| Count events inside an awaited scope | `confirmation(expectedCount:)`, ranges (ST-0005) | Same | **Use** where the scope can be awaited |
| Serial execution | `.serialized` | `Parallelization.md`: "doesn't affect the execution of a test relative to its peers or to unrelated tests" | Use for shared files only. **Not** load isolation |
| Repeat until it fails | runner `--repetitions/--repeat-until` | `EntryPoint.swift` (release/6.3); probe | **Use through `swiftpm-testing-helper`** until 6.4 |
| Scoped setup and teardown (load) | `TestScoping` trait (ST-0007) | Interface; `TaskLocalTrait.swift` uses it | **Use** for `UnderLoad` |
| Injected time | **swift-clocks 1.1.1** (`TestClock`, `ImmediateClock`) | https://github.com/pointfreeco/swift-clocks/blob/1.1.1/Package%40swift-6.0.swift: our 6.3 toolchain picks this manifest (`Package.swift` needs tools 6.4). Dependencies: swift-concurrency-extras, xctest-dynamic-overlay ≥ 1.13 (IssueReporting), swift-docc-plugin. **No swift-syntax / macro plugin anywhere** (checked xctest-dynamic-overlay 1.13.1 `Package@swift-6.0.swift` and concurrency-extras 1.4.3), so the GRDB note in `Package.swift:10-16` about toolchain skew does not apply | **Adopt, as a dependency of test targets only.** The product depends only on stdlib `Clock` |
| Caveat on `TestClock` | — | `TestClock.swift:161-197`: `advance` relies on `Task.megaYield()` (20 detached yields: `Task.swift`, concurrency-extras) for other tasks to reach their sleep; `run(timeout:)` defaults to **500 ms wall clock** (`:226-264`) | Prefer `ImmediateClock` + awaiting the product's task. With `TestClock`, first `until("the debounce sleeps") { (try? await clock.checkSuspension()) == nil }`, which detects a pending sleep. Never call `run()` with the default timeout |
| Deterministic task order | swift-concurrency-extras `withMainSerialExecutor` | `MainSerialExecutor.swift`: it sets the process-global `swift_task_enqueueGlobal_hook` through `dlsym`; the README says "no scoping guarantees". swift-testing runs tests in parallel in one process. It does not cover GCD queues (`engineQueue`, `resampleQueue`, `configChangeQueue`) or `std::thread` | **Reject.** It would also move `TrackLoudnessAnalyzer`'s `Task.detached` decode onto the main thread, where `RecordingSink`'s blocking hold would **deadlock** ANALYZER-05 |
| A "settle" heuristic | `Task.megaYield` | `Task.swift` | **Reject** as a wait (it is the same 50-yield guess) |
| Locks and latches in tests | stdlib `Synchronization.Mutex/Atomic` | Already used (`OnDeckEngineModel.swift:4`, `SpectrumHandoffTests.swift:18`) | **Use**. Skip `LockIsolated` |
| C++ test framework | GoogleTest / Catch2 | Council BT-3 item 5 (`docs/reviews/2026-10-council/working/area-build-test.md`) reached the same view | **Not now.** They add repeat, shuffle and filter, which the runner gets in about a day, but not the wait, rendezvous or thread-CPU primitives. Their macros would fight clang-tidy, and the rule is to fix lint, never fight it. Revisit if the harness is ever rebuilt |
| C++ waits and handshakes | C++20 `std::atomic::wait/notify`, `std::jthread` | Already used in `WorkerParking.h` | **Use** inside `Rendezvous` and the watchdog. `std::latch/barrier` have no timed wait, so the watchdog covers them |
| Thread CPU time | `clock_gettime(CLOCK_THREAD_CPUTIME_ID)` | `man clock_gettime` (local) | **Use** |

---

## 6. Mirror tests and engine doubles: recommendation

Today there are **four doubles of one engine protocol**: `SheetEngine` (product debug), `DeviceTestEngine`,
`OnDeckEngineModel`, and `MockAudioEngine`, which implements a **mirror** protocol that its own header says has
the wrong shape. There is also `MockAdvanceController`, a copy of the VM's state machine (DUP-2: it has already
drifted, e.g. dedupe and `resumePoint`; about 61 tests prove the copy, BT-1).

**Recommend: retire the mirrors, onto one shared double, in Phase 3, after the primitives.**

1. **One `FakeEngine: AudioPlaybackEngine`** in `Tests/AdaptiveSoundTests/FakeEngine.swift`. It is
   `DeviceTestEngine` promoted: it records every call and serves devices, spectrum and the signal path. Delete
   its stray `setNextTrack(_:)` (`DeviceTestEngine.swift:79`).
2. **`OnDeckEngineModel` composes it.** It keeps only its scripted transport and on-deck state machine (holds,
   hops, opens, seams, the ablation `semantics`) and delegates the rest of the protocol to an embedded
   `FakeEngine`. That removes its no-op block (`OnDeckEngineModel.swift:99-128`). Keep it separate: it is a
   model with ablations, not a recorder, and merging the two would mix concerns.
3. **Rewrite the auto-advance, queue-ops and engine-protocol mirror tests** on the real `AudioViewModel` with
   `Rig` / `OnDeckEngineModel`. They already model seams, ends and the epoch gate, and the waits use `until` +
   `WorkTracker`, so no new `settle()` copies appear. Then delete `MockAudioEngine.swift`,
   `MockAdvanceController.swift` and `AudioEngineProtocolTests.swift`. Tests of the pure Kit
   (`QueueAdvanceTests`, `PlaybackOrderTests`, `TransportSnapshotTests` VM-TS-01/03/04) stay where they are.
4. **`SheetEngine` stays in `Sources/AdaptiveSound/Debug`** for `make sheets`. Tests must not depend on it.

Effort: M (the 26 auto-advance tests are most of it). Risk: low, as long as each rewritten test is first seen
failing against a planted bug (the QA bar).

---

## 7. Open questions for the founder (recommendation first)

1. **Adopt swift-clocks as a test-only dependency?** Recommended: yes. It is the established library for
   injected time, it brings no macros, and the product only takes the stdlib `Clock`. Alternative: a 60-line
   home-grown manual clock (cheaper to own, but it goes against "prefer established libs").
2. **Turn on the `test-no-raw-time` lint rule?** Recommended: yes, at the end of Phase 3. Turning it on earlier
   means a wave of suppressions.
3. **Move the main-thread-stall oracle to "completed while held" (R1)?** Recommended: yes. It removes the 25 ms
   line that machine load can cross, and keeps the protection.
4. **Keep the home-grown C++ runner?** Recommended: yes, with the watchdog, repeat and load added (council BT-3
   agrees).
