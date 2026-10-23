# Lane B report: the C++ test rig (GoogleTest, watchdog, deterministic C++ tests)

Branch `testrig/cpp-rig` (worktree `.claude/worktrees/testrig-b`), rebased onto `testrig/integration` @ 94fc3c4
(Xcode 27.1, macOS 26.6). Not pushed. All verification was on Xcode 27.1 (Apple clang 21, clang-2100.3.34.2).

## Summary

The null test runs on GoogleTest 1.18.0 (a submodule, built with our flags in every variant). All 245 `kTests`
entries are registered at run time with unchanged names. A per-test watchdog names a hang and aborts. Each test is in
one tier (Correctness 141, Concurrent 89, AccuracySweep 10, Timing 5) with two flags (serial 58, needsFfmpeg 20).

Hazards N2–N18 are migrated:
- the performance checks use thread CPU time, min-of-N, and ≥ 10× tripwires;
- the paced and settle tests wait on component state;
- the carry-on deadlines fail loudly.

Every migrated hazard failed on a planted bug in the code under test. Plain, ASan+UBSan, TSan, the `-O2 -Werror` compile
and the `-O2` timing run are all green. The golden master is unchanged.

## Commits (on `testrig/integration`)

| Commit | What |
|---|---|
| 7c2ccb1 | `build(test)`: vendor GoogleTest 1.18.0 as `third_party/googletest`. `toolchain/toolchain.env` holds only its rows. |
| 65b1a25 | `WIP(test)`: TestSupport.h includes GoogleTest; `cxx_test_extra_flags` adds the gtest include. This is the WIP commit you asked for at the interruption; squash it if you like. |
| 5c84005 | `test(null-test)`: the runner, tiers, watchdog, rig primitives, migrations N2–N18, the product test seams, and the script interface. |
| 0e0d8e4 | `test(null-test)`: the sanitizer tripwires raised to ≥ 10× what ASan/TSan measure. Some were only 5–9×. |

- GoogleTest v1.18.0 exists. It is a lightweight tag on commit `063de7e9578f82b369302001269680b4b1553359` ("Prepare for v1.18.0 (#5055)", 2026-08-10). It is the latest release; `git ls-remote --tags` shows nothing after it. BSD-3, test-only.
- `toolchain/toolchain.env` on this branch contains exactly the requested block, with `GOOGLETEST_COMMIT=063de7e…`.
- Nothing in `.github/**`, `Makefile`, `scripts/strict-gate.sh` or `scripts/gate/**` was touched. `-D_LIBCPP_DISABLE_AVAILABILITY` is not reintroduced anywhere.
- GoogleTest compiles clean against the macOS 26 deployment target (binary `minos 26.0`, sdk 27.0), with the availability checks on.

## What changed

### Runner: `Tests/NullTestRunner.h` (new) and `Tests/DSPKernelNullTest.cpp`
- **Registration.** `testing::RegisterTest` registers each selected `kTests` entry.
  - The GoogleTest suite is the tier, and the test name is the old name.
  - `logFail` is `ADD_FAILURE_AT` at the call site, with a `std::source_location` default argument, so no call site changed.
  - `logPending` is `GTEST_SKIP`.
  - `logPass` records the verdict, and also fails if the running test passed under another test's `kName`.
  - A body that returns without any verdict fails. That is new, and catches a forgotten `logPass` path.
- The home runner (`runOneTest`, `runAllTests`, `printSummary`, the thread-local buffering, and in-process `--parallel`) is retired.
- **Tiers.** Each entry carries `Tier::{Correctness, Concurrent, AccuracySweep, Timing}` and flags `kSerial` / `kNeedsFfmpeg`.
  - Select them with `--tier=<list>`: comma-separated, a leading `-` excludes. Names: correctness concurrent accuracySweep timing serial parallelSafe needsFfmpeg all.
  - Also `--serial-only` / `--parallel-safe-only`, or `--gtest_filter='Timing.*'`.
  - The tier and flags are JSON properties of each test, along with `cpu_ms` (process CPU, all threads).
- **Watchdog.** A `testing::EmptyTestEventListener` with one `std::jthread`, armed per test.
  - When a test passes its ceiling it prints `[HANG] <Suite.Test> ran past its N s ceiling. Last progress: <note>. Aborting.` and calls `std::abort()`, so the exit is 134.
  - Ceilings by tier: Correctness 120 s; Concurrent, AccuracySweep and Timing 300 s. ASan multiplies them by 3, TSan by 8.
  - Override with `--test-ceiling=S` or `ADAPTIVESOUND_TEST_CEILING`.
  - The ceilings count only the time the Mac is **awake** (`CLOCK_UPTIME_RAW`). This Mac slept through an earlier baseline run and turned a 4-minute run into 80 minutes of wall time; steady_clock would have tripped every cap on waking.
  - `rig::Progress` notes say what a test is doing, and every `rig::waitUntil` sets one, so `[HANG]` names the state being waited for.
- **Zero-test guard.** A filter or tier that selects nothing exits 1 (`--gtest_fail_if_no_test_selected`, injected first, so a caller can still override it).
- **Output.** `setvbuf` line buffering. Each test prints its elapsed time on the `[ OK ]` line, then `[cpu] N ms`.
- **Legacy binary flags.** `--list` (now shows tier and flags) and `--filter=<name>` still work. `--parallel` fails with a pointer to `--shards`.

### Primitives: `Tests/TestSupport.h`, `namespace rig`
- `waitUntil(state, done, cap = 60 s)` and `pumpUntil(state, step, cap)`: wait for a state. A step that makes progress (a drain that pulls) is pumped without napping. On the cap the test fails, naming the state, and the call returns false (`[[nodiscard]]`), so the caller returns. `reached` and `pumped` are the non-reporting forms, for use inside an RT-allocation guard.
- `Rendezvous`: GaplessArmContract's seam pause, generalised. A thread is held at a point until the test releases it. The arrival and the release are bounded waits that name the point.
- `threadCpuTime()` (`clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID)`, as SRCQualityMeasure does) and `minThreadCpu(N, fn)`.
- `Budget{strict, debug, asan, tsan}` and `limit()`. Strict budgets apply only to an optimised, uninstrumented build. `kTimingRuns` is 5 there and 1 elsewhere.
- `AwakeClock` (`CLOCK_UPTIME_RAW`) for every hang cap.

### Product test seams (`Sources/AudioDSP`): no render-thread change, no allocation, no lock on the RT path
- `LoudnessModule::meterCaughtUp()` and `DSPKernel::loudnessMeterCaughtUp()`.
  - Only the measurement worker writes the new flag, around its existing `parking_.idle()` wait.
  - The check is "the ring is empty and the worker is at its idle point". The ring is read first; the ordering argument is in the header comment.
  - It replaces "pace 1 ms per block so the worker keeps up".
- `Realizer::drainsPosted()` / `drainsStarted()`: control-plane counters, incremented in `postDrain()` and at the start of `drain()` on the queue.
- `TestPoints.h` was **not** created. No migration needed a new test point: GaplessSource's three hooks are enough, and the plan says to add points only when a test needs one.

### `scripts/build-null-test.sh`
- Today's flags work unchanged: none, `--build`, `--sanitize`, `--tsan`, `--release-strict`. New: `--opt-run`, `--tier <list>`, `--shards <N>`, and `--gtest_*` pass-through (plus `--test-ceiling=`, `--filter=`, `--list`). They are documented in the header.
- **Default tiers by variant** (`--tier all` overrides):

  | Variant | Default tier |
  |---|---|
  | plain | all |
  | `--sanitize` | `-timing` |
  | `--tsan` | `concurrent` |
  | `--opt-run` | `timing` |

  **This changes what `make sanitize` and `make tsan` select today.** See the open questions.
- `--shards N` runs N GoogleTest shards over the parallel-safe tests, beside one process for the serial tests. Output lines are prefixed per process. Each process's exit code is captured before the prefixing pipe. The run fails if any process failed, or if any process is missing an exit code.
- GoogleTest is compiled from the submodule with each variant's flags into `.build/null-test/gtest-<variant>.o`, so nothing new needs gitignoring. The script auto-initialises the submodule, like libebur128.
- The script fails if the GoogleTest checkout's commit is not `toolchain.env`'s `GOOGLETEST_COMMIT`.
- **JSON output** goes to `.build/null-test/<variant>.json` (sharded: `<variant>.shard<i>.json` and `<variant>.serial.json`), unless `--gtest_output=json:FILE` is given.
- `scripts/lib/cxx-analysis-flags.sh`: `cxx_test_extra_flags` adds `-I third_party/googletest/googletest/include`. As `-I`, it is searched before `-isystem /opt/homebrew/include`, so a Homebrew gtest can never shadow it.
- The strict gate's source-coverage drift guard still parses the script: 22 sources covered before and after, none uncovered.

## Evidence (real exit codes)

| Check | Command | Result |
|---|---|---|
| Plain, before (home runner, 94fc3c4) | `bin-plain` | exit 0. 244 passed + 1 pending (`Reconfiguration_Stereo_5p1_Stereo`). 247.4 s wall, 232.3 s CPU. |
| Plain, after (GoogleTest, before migration) | `build-null-test.sh` | exit 0. 245 run: 244 passed, 1 skipped (the same pending test). |
| Plain, after (migrated) | `DSPKernelNullTest` | exit 0. 245 run: 244 passed, 1 skipped. 372.0 s wall, 290.8 s CPU, under load (see the timing caveat). |
| Plain, sharded (HEAD) | `build-null-test.sh --shards 3` | exit 0. Serial process 58 + shards 62/62/63 = 245; 244 passed + 1 skipped. 220.5 s wall including the build. |
| GoldenMaster_StereoN2_v1 | in the HEAD sharded run | OK. Unchanged. Crossfeed_Bypass_BitExact_GoldenMaster also OK. |
| ASan+UBSan, before | `bin-sanitize` (all) | exit 0. 244 passed. 1240.5 s wall, 1036.3 s CPU. |
| ASan+UBSan, after | `--sanitize` (`-timing`: 240 tests) | exit 0. 239 passed + 1 skipped. 1623.7 s wall, 1115.1 s CPU. No ASan/UBSan reports. |
| TSan, before | `bin-tsan` (all) | exit 0. 244 passed. 2325.0 s wall, 1843.0 s CPU. |
| TSan, after | `--tsan` (`concurrent`: 89 tests) | exit 0. 89 passed. 836.2 s wall, 591.1 s CPU. No TSan warnings. |
| `-O2 -Werror` compile | `--release-strict` | exit 0. |
| `-O2` timing run | `--opt-run` | exit 0. 5/5 passed on the strict budgets. 45.2 s wall including the build. |
| Watchdog, planted hang, `--test-ceiling=5` | | exit 134. `[HANG] Correctness.ZeroInputProducesZeroOutput ran past its 5 s ceiling. Last progress: planted: spinning forever inside the zero-input test.` |
| Watchdog, default ceiling | | exit 134 after 124 s. The 120 s Correctness ceiling fired. |
| Planted never-true `waitUntil` (3 s cap) | | That test FAILED at its call site with `never reached: a planted state that never holds (hang cap 3 s)`. The run went on to the next test. |
| Plants reverted | `git checkout` | `git status` clean. |
| Stress | `tools/stress.sh`: 11 hogs (ncpu−3) with trap cleanup, `--shards 3`, `--gtest_repeat=5 --gtest_shuffle --gtest_random_seed=20261021` over the migrated set | exit 0. 5 iterations × 68 migrated tests = 340 runs, 340 passed. 435 s. Hogs left afterwards: 0. |
| Leak check | `scripts/build-leak-check.sh` | exit 0. Clean binary: 0 leaks; the planted leak was caught. |
| clang-tidy (the gate's invocation, LLVM 23.1.2) | all 33 TUs: AudioDSP, TestBridge, Tests | 33/33 clean. Each touched header is also clean on its own (the pre-commit hook). |
| clang-format 23.1.0 | `--dry-run --Werror` over `Sources Tests` .h/.cpp | exit 0. |
| cppcheck 2.21.0 | the gate's flags over `Sources/AudioDSP Sources/AudioDSPTestBridge` | exit 0. |
| semgrep 1.175.0 | `.semgrep.yml` over Tests and AudioDSP | exit 0. |

Notes on the evidence:
- **Stress seed.** GoogleTest folds the seed into [1, 99999], so 20261021 printed as seeds 61223–61227, one per iteration. Use a seed under 100000 to replay.
- **Timing caveat.** The baselines ran while the Mac was quiet (load ~5). The "after" plain, ASan and TSan runs overlapped other lanes' stress runs and gates (load average 31–46; one run overlapped my own ASan baseline). Wall time is therefore not comparable, and contention also inflates CPU time (efficiency cores, cache).
- **Per-variant read.**
  - TSan drops from 1843 to 591 s CPU, by running the concurrent tier.
  - ASan is about the same: it now skips only the 5 timing tests.
  - Plain shows +25 % CPU under contention. I could not re-measure it quiet: when I tried, another lane's hogs were running.
  - The new waits nap at most 200 µs. The only additional fixed cost is up to about 5 ms per meter catch-up (the worker's existing nap), which is wall time, not CPU.
  - The coordinator's single combined gate run is the clean comparison.
- **Sanitizer cost by tier.** Under ASan, the AccuracySweep tier is 573 of 1115 s CPU. The slowest test, `EQ_LoudnessNeutral_OnOff`, takes 271 s under ASan, well inside its 900 s ceiling.

## Hazards: what each waits on now, and its mutation check

Every plant went into product code under test. Each was reverted with `git checkout`, and the tree is clean.

| ID | Test(s) | Now | Planted bug | Result |
|---|---|---|---|---|
| N2 | EQ_Cpu_7_1_192k, …AboveSupportedRates | Thread CPU, least of 5 fresh modules in the -O2 run. Tripwires: debug 1000 %, ASan 2000 %, TSan 4000 % at 192 kHz, scaled per rate. | 0.3 M-iteration burn per `EQModule::process` (-O2) | FAILED: "31.72 % of one core exceeds 5 %" |
| N3 | Designer_Timing | Thread CPU, least of 5. Strict 250 µs. Tripwires: debug 15 ms, ASan 25 ms, TSan 60 ms. | 1 M burn in `GraphicEQDesigner::design` (-O2); 30 M burn (debug) | FAILED: 2596.8 µs > 250 µs (-O2); 28026 µs > 15000 µs (debug tripwire) |
| N4 | Profiler_Timing | Thread CPU, least of 5 fresh profilers. Strict 40 ms/s and 4 ms. Tripwires: debug 1000/250, ASan 1500/600, TSan 6000/4500. | 10 M burn in `predictLoudnessChangeDb` (-O2) | FAILED: "predict 29.319 ms (≤ 4.0)" |
| N5 | Realizer_LoudnessCost | Thread CPU, least of 5. Strict 1 ms / 5 ms. Tripwires: debug 25/200, ASan 75/600, TSan 250/4000. | 10 M burn in `TrackLoudnessGain::onRefresh` (-O2) | FAILED: "refresh 28.017 ms (≤ 5.0)" |
| N6 | Realizer_ReinitDuringDrain | The Realizer's own counters: at most 1 drain queued at any time. Sampled on both threads all through the burst, after a positive witness that the burst posted a drain. Re-allocation wall times are `[info]` only. | `writeSlot`: `post = true` (a drain per write) | FAILED: "4953 drains waited in the Realizer's queue at once (≤ 1)" |
| N7 | Soak_DSPKernel_ZeroRtAlloc_* | Per-buffer thread CPU. Drift = the **least** cost of the last 64 buffers > 50× the median. A single slow buffer no longer fails. | `DSPKernel::process` burns about 60 ms per call after call 2150 | FAILED: "the last 64 buffers' least cost 4.38e7 ns > 50x median" |
| N8 | Loudness_EditDebounce | Waits for the effect of the real 150 ms debounce: `needsRefresh()` false, read on the Realizer's queue. Not a fixed 400 ms. | `scheduleLoudnessRefresh()` returns at once | FAILED at the 60 s cap: "never reached: the idle refresh ran (needsRefresh() false)" |
| N9 | Loudness_AnalysisFails_CausalFallback | Waits until `causalSeconds()` covers each rendered second; the cap fails. It used to carry on after 10 s. | `applyCausalSnapshot` returns at once | FAILED: "never reached: the causal estimate's snapshot covered the second just rendered" |
| N10 | Soak_DSPKernel_ZeroRtAlloc_CausalTap | Waits for `causalLoudnessFedFrames() > 0`, the positive witness for the assert that follows; the cap fails. | The tap never counts what it fed | FAILED: "never reached: the causal tap's worker fed the profiler" |
| N11 | Path_Switch_AfterNormaliserAdapted | Renders measured: every 8 blocks it waits for `loudnessMeterCaughtUp()`. No 1 ms pacing. | The makeup ignores Intensity (amendment 2 undone) | FAILED: "a 26.184 dB level step at a path switch". A first plant, removing only the slow glide, passed; that is correct, because this test guards the contribution law, not the glide. |
| N12 | Intensity_Zero_LevelGlide | The same meter catch-up. | The contribution glide removed | FAILED: "10–90 % in 70 ms (≥ 1000)" |
| N13 | BreakIt_NonFiniteInput_NormaliserKeepsAdapting | Catches up every 8 blocks. Each makeup reading follows a catch-up, with no 50 ms settles. | LufsMeter no longer reads NaN/Inf as silence | FAILED: "the normaliser froze (makeup -2.40 → -2.40 dB)" |
| N14 | Loudness_MeterBridge_BeginTrack_Concurrent | **Kept as a designed race**, documented at the site. Nothing is asserted on the interleaving; load only weakens the TSan probe and never turns it red. | n/a (not migrated) | |
| N15 | Snapshot_TripleBuffer_WholePayloadNoTear | `waitUntil` for "reader running" and "reader accepted a snapshot". It was an unbounded yield plus a 2 s carry-on. | `publish` copies half the payload | FAILED: "torn read: 212155 accepted copies" |
| N16 | FileDecode_* (drainFrames, pollFinished, the wraparound drain, decodeBitExactCase) | Pull until all the frames arrive or the source is `exhausted()`. Wait for `decoderFinished()`. It was 100 × 2 ms, with productive pulls counted against the budget. | The decoder drops a frame per chunk | FAILED: "decoded 7 of 8 frames"; "299926 of 300000" |
| N17 | PureGapless_*, GaplessContract_*, the Soak_GaplessSource armed loop | `pumpUntil` until the seam or `ended()`/`exhausted()`. The soak uses the non-reporting `pumped` inside the RT guard and reports after disarming. | The armed track is never adopted | FAILED: "drained 2048 of 4096"; "never reached: the render crossed the next seam" |
| N18 | ArmContract_* (`openArmTrack`) | `waitUntil(decoderFinished)`. On the cap it returns nullptr instead of a half-decoded source. | `finished_` is never set | FAILED: "never reached: an arm-contract fixture fully decoded" |
| Seam pause | ArmContract_ArmWhileSeamClaimed/Retired/SeamPublishBounded | `rig::Rendezvous` plus bounded waits. These were unbounded yields. | The `SeamClaimed` test point removed | FAILED: "never reached: the render inside its first seam: the held thread arrived". It took 60 s: the render and the test each wait on the other, and both waits are capped. |
| N19 | ArmContract_ClearRacesSeam, ArmRacesEnd | **Kept as a designed race**, documented. Either outcome passes; only a third, broken outcome fails. The ordered cases are pinned by the seam-window tests. | n/a | |
| N20 | runner | GoogleTest plus the watchdog. | Planted hang | Proven above. |
| N21 | fixtures and env | **Kept serial-only.** The 58 `kSerial` tests share fixture paths under `test-data/` or mutate `ADAPTIVESOUND_DECODER`. GoogleTest runs one test at a time per process; `--shards` keeps every serial test in one process. Unique paths would have meant reworking 54 compile-time path concatenations, which I judged not worth it here. | n/a | |

## What runs where (recommended)

| Gate step | Command | Tests |
|---|---|---|
| cpp: null-debug | `build-null-test.sh` (CI: add `--shards 3`) | All 245 tiers. Timing runs on ≥ 10× tripwires. |
| cpp: null-perf-O2 | `build-null-test.sh --opt-run` | Timing (5) on strict budgets. |
| cpp: -O2 compile | `build-null-test.sh --release-strict` | Compile only. |
| asan | `build-null-test.sh --sanitize` (CI: `--shards 3`) | `-timing`: 240 tests, including AccuracySweep. |
| tsan | `build-null-test.sh --tsan` | `concurrent`: 89 tests. |

Every test runs in the plain step, so each test runs somewhere. The Correctness and AccuracySweep tests are single-threaded; their thread-touching code (the parked analysis workers' start and stop) is also exercised by the concurrent tier under TSan.

## Not done, and why

- **`TestPoints.h`.** Not created; no migration needed a new test point. GaplessSource's hooks remain as they are.
- **Unique fixture paths (N21).** Kept serial-only instead (see the table).
  - **Constraint for Lane A:** two null-test processes from the same checkout must not run at the same time, except through `--shards`. That includes two variants: plain and ASan would collide on `test-data/`. Separate CI jobs on separate machines are fine.
- **Full TSan on the new runner.** Not run: about 40 minutes under the current load. Only the concurrent tier was run under TSan. The old runner's full TSan passed on 94fc3c4.
- **Clean before/after wall times.** Not obtained, because the machine was loaded by other lanes (see the timing caveat).
- **JSON on a hang.** When the watchdog aborts, GoogleTest writes no JSON. The record is the `[HANG]` line plus exit 134. Lane A's runner can treat a missing JSON file plus that exit code as "hang". GoogleTest's `TEST_PREMATURE_EXIT_FILE` is also available.
- **Small run-to-run spread in BreakIt_NonFiniteInput.** The NaN case read −5.40 or −5.50 dB across runs. The cause is in the product: LoudnessModule discards its ring at its first configure, so up to one catch-up window at the very start is discarded. The assertion's margin is about 3 dB against a 1 dB bound, so this does not threaten the test.
- **`research/eq-engine-break-it/build-measure.sh`** (not mine, not gated). It now also needs GoogleTest, because TestSupport.h includes it. It was **already broken at 94fc3c4**: its link list lacks FFmpegLoader.cpp, and `ffmpeg::openLibrary` is undefined. Request below.

## Requests for other lanes

- **Lane A (CI and runner):**
  - CI checkout needs the submodule: `submodules: true`, or `git submodule update --init third_party/googletest`. Without it the script fetches it itself (with `--depth 1`).
  - Have `check.sh` assert `GOOGLETEST_COMMIT` against `git -C third_party/googletest rev-parse HEAD`.
  - Registry rows as in "What runs where". The new flags are `--opt-run`, `--tier`, `--shards N`, `--gtest_output=json:results/null-<variant>.json`.
  - Make each step timeout larger than the per-test ceilings: plain 120/300 s, ASan ×3, TSan ×8.
  - `make stress KIND=cpp` can call `build-null-test.sh --shards 3 --gtest_filter=… --gtest_repeat=N --gtest_shuffle --gtest_random_seed=<1..99999>`.
  - Never run two null-test variants at once from one checkout (N21).
  - `make sanitize` and `make tsan` now default to their tiers. Add `--tier all` if you want the old behaviour.
- **Lane A or the coordinator:** `docs/development/testing.md` (C++ section) should describe the rig primitives, the tiers and the `[HANG]` line. The script header and the `NullTestRunner.h` / `TestSupport.h` comments hold the details.
- **Whoever owns `research/`:** `build-measure.sh` needs FFmpegLoader.cpp and DeviceListPolicy.cpp in its link list, and GoogleTest. The simplest fix is to reuse `.build/null-test/gtest-<variant>.o` and `-I third_party/googletest/googletest/include`.

## Open questions for the founder (recommendation first)

1. **TSan scope. Recommendation: run only the 89 concurrent tests under TSan in the gate.**
   - This cuts TSan from about 31 to about 10 CPU-minutes locally.
   - Every test still runs in the plain and ASan steps.
   - The single-threaded tests cannot show a data race under TSan.
   - The alternative is `--tsan --tier all` at about 3× the cost; a nightly job could run that.
2. **ASan scope. Recommendation: keep the 10 heavy accuracy sweeps under ASan, and shard the asan job 3 ways on CI.**
   - The sweeps are about half of ASan's time. Memory safety is worth the minutes.
   - If the asan job's time budget can't fit them, `--tier=-timing,-accuracySweep` halves it. The sweeps would still run in plain, without ASan.
3. **The debounce test (N8). Recommendation: keep waiting on the real debounce's effect, rather than adding a "flush now" seam to the Realizer.**
   - A flush seam would stop testing that the 150 ms timer actually fires.
   - The state wait costs about 150 ms and cannot flake.

## Name mapping (old → new)

Every old name `X` is now the GoogleTest test `<Tier>.X`. The names are byte-identical: the old `--list` and the new `--list`, after stripping the suite, diff equal for 245 names. Before: 245 entries, 244 passed + 1 pending. After: 245 tests, 244 passed + 1 skipped (the same pending test).

- **Concurrent (89):** Loudness_WorkersSleepWhileIdle, BreakIt_PureDepth_LosslessSourceBits, FileDecode_* (all 24), FFmpeg_OffByDefault_LoadsNothing, FFmpeg_ProbeNamesWhyAFileWontOpen, Gapless_* (5), RoundTrip_BitExact_16bit/24bit, PureGapless_* (5), GaplessContract_* (5), ArmContract_* (9), Realizer_MultiSurfaceRMW_NoClobber_SeqMonotonic, Realizer_Crossfeed_4SurfaceRMW_Clamp, Crossfeed_ebur128_LevelNeutral, Loudness_MeterBridge_BeginTrack_Concurrent, Designer_TwoThreads, Loudness_Profile_SharedAcrossThreads, EQ_ReadbackEqualsEngine, EQ_Off_BitExact, EQ_BitPerfect_P0, Path_Switch_AfterNormaliserAdapted, EQ_PublishRejectsNonFinite, EQ_FZ_OnWhileRendering, EQ_NoSubnormalStates, Soak_DSPKernel_ZeroRtAlloc_EqPaths, EQ_Reallocate_KeepsCurve, EQ_Reallocate_NewRate, Crossfeed_RederivedOnRateChange, Realizer_ReinitDuringDrain, EQ_LoudnessNeutral_OnOff, Loudness_ProfileLate, Loudness_GaplessSeamStep, Loudness_AnalysisFails_CausalFallback, Loudness_EditDebounce, Soak_DSPKernel_ZeroRtAlloc_CausalTap, Limiter_EqOnlyCeiling, BreakIt_InfInput_KernelRecovers, BreakIt_NonFiniteInput_NormaliserKeepsAdapting, Intensity_Zero_LevelGlide, Kernel_P0Switch_LoudMasterStep, RenderGate_CloseWaitsForRenderInside, RenderGate_ConcurrentNeverOverlaps, Soak_DSPKernel_ZeroRtAlloc_CrossfeedBlend, Soak_GaplessSource_ZeroRtAlloc_Pull, Snapshot_Seqlock_ConcurrentNoTear_RACE1, Snapshot_TripleBuffer_WholePayloadNoTear.
- **AccuracySweep (10):** Convert_BitExact_Exhaustive16And24, Intensity_LevelPeakSafetyIntermediate, EQ_Sweep31Bands_48k, EQ_Sweep31Bands_44k, EQ_SweepExtremes_PlusMinus12, Loudness_Profile_PrefixVsFull, EQ_Transitions_Realistic, EQ_Transitions_Adversarial, BreakIt_Transitions_LowBandGestures, EQ_Transitions_SinglePoints. These were chosen by measured CPU: each is a 3–31 s single-threaded sweep at -O0.
- **Timing (5):** Designer_Timing, Profiler_Timing, EQ_Cpu_7_1_192k, Realizer_LoudnessCost, EQ_Cpu_7_1_AboveSupportedRates.
- **Correctness (141):** every other name.
- **serial (58):** every FileDecode_*, FFmpeg_*, Gapless_*, RoundTrip_*, PureGapless_*, GaplessContract_* and ArmContract_* test, plus BreakIt_PureDepth_LosslessSourceBits and Soak_GaplessSource_ZeroRtAlloc_Pull.
- **needsFfmpeg (20):** FileDecode_BitExact_24bit/Float32, NativeRates, Mono_BitExact, Multichannel_4ch, BackendEquivalence, the 8 FileDecode_Seek_* tests, and the 6 FFmpeg_* tests.

Several old in-process "serial" reasons no longer apply across processes, so those tests are not flagged serial:
- the context-switch count (fixed in f5d1329);
- the timing clock (now thread CPU);
- the thread-local RT-allocation guard;
- the per-thread FPCR;
- the paced normaliser (now waits on the meter).

Scratch evidence is in `scratchpad/testrig/laneb/`: logs, JSON, `mutations.log`, `tools/stress.sh`, `tools/mutate.py`.
