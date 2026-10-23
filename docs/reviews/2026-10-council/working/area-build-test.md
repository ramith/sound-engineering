# Area review: test architecture, build and CI (as engineering artifacts)

Reviewer: area / build-test. Repo @ 7d7c2cd. Read-only on the repo. Experiments live in `scratchpad/council/exp-build-test/`. The worktree I built in was removed.

**Experiments run (so the claims below are measured, not assumed):**
- **E1: `@testable import` of the executable app target works.** A scratch package, then the real repo in a worktree, with a test target depending on `AdaptiveSound` and `@testable import AdaptiveSound`. `swift test --filter` ran a `@MainActor` test that names `AudioViewModel`. It passed (cold build 151 s). I only proved reachability. I did not instantiate the view model.
- **E2: `RenderGate` close latency under CPU load.** I wrote `exp-build-test/gate.cpp`, which copies the test's race (a hot render loop plus 2000 close/open cycles) against the real `RenderGate.h`. Numbers are in R4.

---

## 0. Verdict

**The tests are strong where the code is pure, and hollow exactly where the escapes were.**

- The kernel has a 198-test C++ suite with real oracles: libebur128, a Python EQ oracle, bit-exact null tests, soak tests that count real-time allocations, and a TSan-modelled lock-free design.
- Nine Swift Kits are tested by decision tables (about 730 `@Test`s).
- The test architecture of everything between them is a workaround for one fact: *the tests believed the app target could not be imported*. That belief is **false** (E1).
- It produced three parallel harness cultures (swift-testing, a hand-rolled C++ runner, and `Verify*` executables), plus a fourth, hidden one: test code compiled into the shipping app's DEBUG binary.
- It also produced about 1,700 lines of mirrors that gave false assurance while B1–B8 escaped.

The gate spends its money on the layer that was stable. Nearly all gate stages are static checks. Not one runs the real app logic.

---

## 1. Findings

### BT-1 The test pyramid has no middle: app logic is proved through copies, and the stated reason is false. STRUCTURAL. Criteria: 6, 1, 3
- **Evidence:**
  - `Tests/AudioViewModelTests/MockAdvanceController.swift:5-14`: a "State machine mirror ... AudioViewModel lives in the `AdaptiveSound` executable target, which SPM cannot @testable import".
  - `Tests/AudioViewModelTests/MockAudioEngine.swift:3-14`: "SPM does not allow @testable import of executable targets". It declares `OutputPathKindMirror`, `SignalPathInfoMirror`, `PureModeDecisionUIMirror`, `AudioPlaybackEngineMirror` and more. Its own comment admits it is not the live protocol: "models the engine's state; NOT the current protocol's shape ... predates [snapshot()/epoch]".
  - The mirror re-implements `startPlayback`, `tick`, `handleTrackTransition`, the epoch gate and the ended/transition logic (`MockAdvanceController.swift:75-190`).
  - Tests that run only against mirrors (grep): AutoAdvance* 26 tests, `AudioEngineProtocolTests` 20, `QueueOpsTests` 15. That is about 61 tests.
  - `AudioEngineProtocolTests` is 252 lines, 20 tests of a test double ("MockAudioEngine — protocol contract"). It tests the `MockAudioEngine` itself and nothing the app ships.
  - 10 of the dir's 19 files are mirror infrastructure or mirror tests, about 1,700 of its 2,702 lines.
  - **E1 shows the premise is wrong.** SwiftPM lets a test target depend on an executable target and `@testable import` it (since 5.5; the toolchain renames `main`). The Swift 6.2 / macOS 26 toolchain here did it. A stale comment in `Package.swift:331-334` and the `VerifyLibraryStore/main.swift:1-3` header say "`swift test` is unusable here (swift-testing macro skew)". That was fixed on 2026-07-02 (memory `reference-build-verify-gotchas`).
- **Root cause:** a past tooling limitation (a broken `swift test`, a belief about executable targets) was solved by copying logic into tests instead of questioning the limitation. The comments then froze the belief. The architecture review owns the real fix (an importable core). But the test side is not blocked on it.
- **Why it matters:**
  - It is the process review's escape root cause (B1–B8, G-LIB-01/06): green mirrors, red production.
  - The mirror also drifts silently. The "match exactly" claim already broke once (the queue mirror that drifted; the epoch gate was added to the mirror by hand).
  - Every transport change is made twice, once in the VM and once in the mirror, and only the mirror is tested.
- **Structural remedy (two steps, the first is S):**
  1. **Now:** add a test target that depends on `AdaptiveSound` (mirroring E1). Delete `MockAdvanceController`, the `*Mirror` types and `AudioEngineProtocolTests`. Rewrite the 26 auto-advance tests against the real `AudioViewModel(defaults:engine:)`. It already takes `any AudioPlaybackEngine`, so one small fake engine that conforms to the live protocol (21 members) is enough. Add a manually advanced clock for the 20 Hz tick (see BT-8).
  2. **Then, by architecture's design:** move VM logic into a library target with an explicit transport state machine. Executable testing is the bridge, not the destination (an executable target's test build re-links the whole app, and the 151 s cold build shows the cost).
  - Caveat to verify first: Periphery (`.periphery.yml` excludes `Tests/**`, so test-only usage will look "unused" for app types: needs `retain` or `// periphery:ignore` policy) and semgrep paths. Neither blocks the plan.
- **Effort:** S for the test-target spike + 1 migrated suite; M to migrate all. **Risk:** low. **Depends on:** none (architecture's remedy builds on it).

### BT-2 Three (really five) harness cultures; the in-app DEBUG self-tests are tests living in the product binary. STRUCTURAL. Criteria: 3, 1, 6
- **Evidence:**
  1. swift-testing targets (7, ~730 `@Test`).
  2. The hand-rolled C++ runner (`TestSupport.h:609-757`: `TestEntry`, `runOneTest`, `runAllTests`, a parallel pool, `--filter`, `--list`).
  3. `VerifyLibraryStore`: 12,165 lines, 157 `printPass` sites, a custom `fail(_:) -> Never` that exits the process on the first failure (`main.swift:36-40`), a hand-written `Deadline.swift`, a hand-numbered `CheckCase` registry (`main.swift:124-190`, 40+ numbered, lettered cases like `"aa-album-cover-deterministic"`). Its header says it "mirrors Sources/VerifyAUGraph/main.swift EXACTLY".
  4. `VerifyAUGraph` (7 files; the same idiom, a separate copy of `fail`).
  5. In the app binary under `#if DEBUG`: `Debug/MainThreadStallSelfTest.swift` (238), `MainThreadStallRig.swift` (255), `MainThreadStallProbe.swift` (98), `SongsPerfRun.swift` (226), `SheetRenderer.swift` + fixtures (2,446 lines in `Sources/AdaptiveSound/Debug/`, 32 `#if DEBUG` blocks), reached by argv flags `-ASMainThreadStall`, `-ASRenderSheets`, `-ASSongsPerf` (`AdaptiveSound.swift`).
  - Plus the standalone `HandleLeakHarness.mm` (leaks(1)), `SRCQualityMeasure` (a measuring exe), `lufs-tool`, `EqEngineBreakItMeasure.cpp` (1,734 lines, un-gated) and `build-eq-clamp-test.sh` (BT-7).
- **Root cause:** each need (store gate, graph gate, in-app rig, C++ suite) invented its own runner because the common runner (swift-testing) looked unusable (BT-1). Four idioms for "check passed" exist.
- **Why it matters:**
  - Each `Verify*` main stops at the first failure, so one run shows one problem. It has no filter, no tags, no timeout trait, no machine-readable report, and no per-test timing. The stage cannot be sharded across CI jobs, which blocks the process review's parallel-CI plan.
  - The in-app rigs carry test code, a real `AudioEngineBridge` stand-in rig, and threshold constants (`target 5 ms`, `bound 25 ms`) inside the product's DEBUG binary. They `exit()`, so they cannot run under `swift test --sanitize=thread`.
  - `Package.swift` grows an executable target per check.
- **Structural remedy:** one Swift harness (swift-testing) with the C++ suite as the only native exception.
  - `VerifyLibraryStore` becomes `LibraryStoreTests` (the checks are already `async` functions over the real store; the only blocker is the `-> Never` + `exit` idiom, which a `#require`/`Issue.record` replaces mechanically). Use tags (`.store`, `.slow`), `@Test(arguments:)` for the format/identity tables, `.timeLimit(.minutes(2))`, `--parallel`.
  - `VerifyAUGraph` (offline manual rendering, AVFoundation only) becomes tests the same way.
  - The stall rig moves out of the app into `Tests/` once BT-1 lands, and then it runs under TSan.
  - The picture-sheet renderer is a legitimately different product (a visual artifact for humans). Keep it, but state it is not a test and give it a smoke test: render one sheet, assert the file exists and is not blank.
- **Effort:** L (staged: store first, M). **Risk:** med (the store gate is the project's best asset; migrate it check-by-check with the old exe in parallel until the count matches). **Depends on:** BT-1.

### BT-3 The C++ suite is one 24,000-line translation unit with no per-test cost, no tags and no timeout. SIGNIFICANT. Criteria: 1, 6
- **Evidence:**
  - `Tests/DSPKernelNullTest.cpp:56-93`: 30+ `.inc` files textually `#include`d into one TU, order "LOAD-BEARING" ("Do not let clang-format alphabetize this block").
  - The registry is a 539-line hand-maintained array (`kTests`). The header comments still number tests "(tests 1-7)", "(tests 8-12)" … while the suite is 198 tests.
  - `TestEntry { name, fn, parallelSafe }` (`TestSupport.h:609`): one boolean for classification. There is no cost class, no `[timing]` tag, no per-test elapsed output.
  - `runAllTests` has no per-test timeout (a deadlock hangs the job; see BT-4 for CI).
  - Serial by default; `--parallel` exists but the gate does not use it (process.md).
  - One crash kills the whole run's report.
  - A header-only failure in any `.inc` rebuilds everything.
- **Root cause:** a runner grown test by test. The registry is manual and the classification too thin to express "what to run under which build".
- **Why it matters:** this is the cost driver the process review measured (about 52 of 87 minutes in silent stretches across 3 builds). The remedy cannot be applied without per-test cost output and tags: the data does not exist today.
- **Structural remedy:**
  1. Add per-test elapsed time to the runner output (S, now).
  2. Widen `TestEntry` to a flag set (`parallelSafe`, `timing`, `accuracySweep`, `needsFfmpeg`, `slow`), and add `--skip=<flag>` / `--only=<flag>`. The sanitizer stages pass `--skip=accuracySweep --skip=timing` (the process review's measured saving).
  3. Self-registration: a `TEST(name, flags)` macro generating a static registrar, as JUCE does (`juce::UnitTest` registers itself on construction and has a category, `getTestsInCategory()`, and a seeded random per run: `juce_UnitTest.h:87-109, 334-338`). It removes the hand list and the stale numbering.
  4. A per-test watchdog (a thread that aborts with the test name after N × the typical time) so that a deadlock reports a name, not a 6-hour job.
  5. Keep the home runner (it is small and fits the build-script model). Adopting Catch2/GoogleTest would add a dependency for what steps 1-4 give in a day.
- **Effort:** M. **Risk:** low. **Depends on:** none (unblocks the process review's CI-shape change).

### BT-4 CI shape and gate design: protection is allocated by history, not by risk; the CI job cannot fail fast or time out. SIGNIFICANT. Criteria: 6
(Builds on process.md §4.3; I only add what it did not cover.)
- **Evidence:**
  - `strict-ci.yml` has one job, no `timeout-minutes` (grep: none in either workflow). GitHub's default job timeout is 360 minutes: a hung C++ test or Swift deadlock burns six hours and blocks the PR. There is also no hang detector in the Swift tests (`.timeLimit` used 0 times in 728 tests).
  - `strict-gate.sh` has 19 `step`s; all are fail-fast, serial. The cheap/high-value stages (format, lint, semgrep) come first, correct. The only stages that run **real app logic** are `swift test` (mirrors, BT-1) and `main-thread-stall`.
  - `.github/dependabot.yml:2-7` says "The package itself is zero-dependency ... no external SwiftPM packages". `Package.swift` has GRDB (`from: 7.0.0`). GRDB is the one external dependency and nothing tracks it. This is the stale-comment-became-wrong-policy pattern.
  - `.periphery.yml:2` says "CI: .github/workflows/periphery.yml". That file does not exist; Periphery runs inside the gate.
  - The gate's stage "Null-test source-coverage drift guard" parses `build-null-test.sh` with `sed -n '/xcrun clang++/,/-o "\$OUTPUT"/p' | grep -oE` (strict-gate.sh): a script scraping another script's text, to avoid keeping one list. It is clever and brittle (it breaks if the compile block is reformatted).
  - The Makefile has dead or overlapping aliases: `ci` = `strict-gate`; `lint` duplicates the gate's static block by hand-copying the four commands (Makefile `lint:` vs `strict-gate.sh`), so "same command" is not literally true; `gate` is both the name of a Makefile target and a stage.
- **Root cause:** the gate grew by "add a stage per escape" (migrator posture, playlist move/copy, Kit-purity, clamp present). There is no stated threat model that says which layer each stage protects.
- **Why it matters:** inline stages like "migrator posture", "playlist add path must never move a file", "Kits stay headless" and "clamp present" are `grep` calls embedded in bash. They are not tested (BT-5), not in the one rule engine, and not discoverable.
- **Structural remedy:**
  1. Per-job `timeout-minutes` (e.g. 30 for static, 45 for C++), plus `swift test --timeout`-style `.timeLimit` defaults via a suite trait.
  2. Move the inline grep stages into `.semgrep.yml` (one engine, one file, with tests: BT-5), or into `Tests/` as swift-testing "architecture tests" that read files (the Swift analogue of ArchUnit: one `@Test` per rule with `#expect` and a clear message).
  3. Add the missing stages the process review lists (Swift TSan, VM harness; BT-1/2 deliver them naturally) rather than only trimming the C++.
  4. `make lint` calls a shared `scripts/lint.sh` that the gate also calls.
  5. Fix the two stale files and add a `swift` ecosystem entry to Dependabot for GRDB (the gate-pin comment for Swift tools is already in strict-ci.yml; GRDB is the unpinned one).
- **Effort:** M. **Risk:** low. **Depends on:** process-review CI split.

### BT-5 Semgrep is the "structure enforcement" layer: 25 regexes, zero tests, and some of its jobs belong to the type system. SIGNIFICANT. Criteria: 1, 6
- **Evidence:**
  - `.semgrep.yml` (342 lines, 20 rules): 25 `pattern-regex`, 0 `pattern:`. No semgrep test fixtures (`git ls-files | grep -i semgrep` lists only `.semgrep.yml` and `.semgrepignore`; no `ruleid:` annotations anywhere). `semgrep --test` is not run.
  - The main-thread rule `main-thread-no-audio-hardware` (`.semgrep.yml:72-90`) is one 700-character regex alternation of identifier names (`\b(playerNodeRef|avEngineRef|effectsNode|playerNode|avEngine)\b|\bAudio(Object(Get|Set|…)…`). It catches tokens, not types: an alias, a protocol extension or a renamed property bypasses it.
  - The "only the bridge" rule family (`main-thread-no-concrete-bridge`, `bridge-not-main-actor`, `coreaudio-listener-not-on-main`) has a positive-lookahead regex special case for exactly one allowed line: `(?!.*\bengine: any AudioPlaybackEngine = AudioEngineBridge\(\))`.
  - The `.sync` rule names the four queues by string.
  - The `ui-no-*` rules (color literal, adhoc material, appearance branching, raw text field) are design-system rules: legitimate for a style-lint.
- **Root cause:** the architecture rule "the main thread never touches the engine" is enforced by text search rather than by a module boundary the compiler checks. The regex rules are therefore load-bearing for a correctness property that cost a 3-7 s freeze.
- **Why it matters:**
  - A regex rule that matches nothing (after a rename) fails silently: nothing in the gate says "rule X still fires". The suppression gate (`check-suppressions.sh`, a good design) polices suppressions; nothing polices the rules.
  - The rule list is long and its protection rests on naming.
- **Structural remedy:**
  1. Add `semgrep --test` fixtures: for each rule, a `ruleid:` line it must flag and an `ok:` line it must not. It turns each rule from a hope into a tested artifact. It is the cheapest high-value fix in this area (S).
  2. For the main-thread rule family, make it unnecessary at the type level (architecture's job, test-side reason stated here): the engine bridge in its own SwiftPM target with `internal` AVFAudio/HAL members and a small public surface (`AudioPlaybackEngine`, `EngineSnapshot`). The app target then cannot name `playerNode` or `AudioEngineBridge`'s internals: the compiler enforces it. The semgrep rule becomes a belt, not the structure. A dedicated global actor for the bridge queue (Swift 6) is the alternative for "never on main".
  3. Keep regex rules only for what the type system cannot say (design-system literals).
- **Effort:** S (tests) + M (module split, architecture). **Risk:** low / med. **Depends on:** architecture review.

### BT-6 Wall-clock deadlines and hand-tuned timing budgets are a pattern. SIGNIFICANT. Criteria: 1, 6
- **Evidence:**
  - `Tests/RenderGateTests.inc:197` `gate.close(std::chrono::seconds{1})` as the failure condition; the failure "close() timed out at seek 1304" is on main CI. `testRenderGateConcurrentNeverOverlaps` at `:222-250`.
  - `Designer_Timing` (`EqDesignerTests.inc:1558-1575`): three `#if` branches with budgets 250 µs, 20,000 µs and 3,000 µs picked per build flavour. The comment admits the first only applies "to an optimised, uninstrumented build".
  - `EQ_Cpu_7_1_AboveSupportedRates` (`EqEngineFixTests.inc:915-946`; the per-rate 1000 % tripwire in `EqTransitionTests.inc:421-427`): "a fixed 1000 % was crossed by TSan at 768 kHz under ordinary machine load". It was patched by scaling the constant.
  - 63 `chrono`/`sleep_for` references in `Tests/*.inc`. Swift: 3 sleeps/polls (`LibraryScanRaceGTests.swift:58,62`, `TrackLoudnessAnalyzerTests.swift:196`: a 10 ms poll loop with a deadline).
  - `MainThreadStallSelfTest.swift:24-27`: `target = 5.0`, `bound = 25.0` ms on a laptop and on hosted runners alike.
- **Root cause:** performance and liveness are asserted as pass/fail on absolute time, in the same run as correctness, with a constant picked once. A constant is a claim about the machine.
- **Why it matters:** each of these is a flake waiting for a slower runner, and fixing one constant at a time (the EQ_Cpu pattern) keeps producing the next one.
- **Structural remedy (three kinds of timing check, three designs):**
  1. **Liveness** ("this must finish"): the test supplies a very generous bound (60 s) and asserts on counts and invariants (no overlaps, no torn reads). Time is only the hang-breaker. For `RenderGate`: keep the 1 s production bound for the code, and pass a long bound in the test (the test's property is *no overlap*, not *1 s*).
  2. **Performance budget**: measure against a calibration loop run in the same process (a fixed FMA kernel), assert the ratio ("EQ costs ≤ k × reference loop"), or report only and compare to a stored baseline. Never hard-code µs per build flavour. Run in the optimised build only.
  3. **Async waits in Swift**: `confirmation()` or an injected `Clock` (see BT-8), not poll loops.
  - Add the process review's stress-under-load rule as a script (`make stress-test`).
- **Effort:** M. **Risk:** low. **Depends on:** BT-3 (tags), BT-8.

### BT-7 Dead and stale build scripts, and test outputs written into the source tree. LOCAL (but a symptom). Criteria: 3, 6
- **Evidence:**
  - `scripts/build-eq-clamp-test.sh` compiles `Sources/AdaptiveSound/EQSafetyClamp.swift` and `Tests/EQSafetyClampTest.swift`. **Neither file exists** (verified). The script is tracked and unreferenced by the Makefile, the gate and CI. (Known from memory-review; I add that `.gitignore:36` still lists `Tests/EQSafetyClampTest` and a stale binary of that name sits in `Tests/`.)
  - `scripts/validate-lufs.sh` + `Tests/lufs-tool.cpp`: ungated, manual. `Tests/EqEngineBreakItMeasure.cpp` + `EqEngineBreakItMeasurements.inc` (1,734 lines) is ungated and built only by `research/eq-engine-break-it/build-measure.sh`, so it can bit-rot against `Sources/AudioDSP` headers without any gate noticing (clang-tidy parses `Tests/*.cpp`, which catches compile errors in `.cpp` but nothing about whether it still measures what its report claims).
  - `scripts/hal-spike*` are ignored but present on disk; the `.semgrepignore` still carries `scripts/hal-spike*` entries.
  - `scripts/build-null-test.sh` writes the binary and a `.ebur128.o` into `Tests/`; `build-leak-check.sh` writes `Tests/HandleLeakHarness*`, `*.dSYM`, a plant log. Build outputs in the source tree are the same class as the process review's "stray build outputs in the repo root".
  - `scripts/build-null-test.sh` header says `./Scripts/build-null-test.sh` (capital S, the path is lowercase); the strict-gate comment cites `FileDecodeSource.mm`; `SpatialRenderKernel.h` points at a renamed file (known).
- **Root cause:** nothing checks that every script is reachable from the Makefile or CI, or that every `Tests/*` source is built by something.
- **Structural remedy:** a gate stage "every `scripts/*.sh` and `Tests/*.cpp|mm` is referenced by the Makefile or a workflow, or listed in an allowlist with a reason" (S; it is the same trick as the null-test coverage guard). Delete `build-eq-clamp-test.sh`. Send all outputs to `.build/testbins/`.
- **Effort:** S. **Risk:** low.

### BT-8 No injected time or deterministic concurrency in the Swift tests; races are tested by sleeping or by not testing. SIGNIFICANT. Criteria: 5, 6
- **Evidence:** `.timeLimit` 0, `.serialized` 0, `.tags` 0, `confirmation` not used, parameterised tests `arguments:` 7 uses in 728 tests (a lot of table-style duplication is written out by hand, e.g. the `DesignTokenKitTests` audits, 28 files / 120 tests). The mirror's `tick()` is invoked synchronously by the test (the mirror hides the real timer). The real 20 Hz tick uses `assumeIsolated` (`AudioViewModel+SpectrumTimer.swift:20-23`), which no test can drive.
- **Root cause:** time is ambient (`Timer`, `Task.sleep`, `ContinuousClock.now`), so tests either cannot drive it (the VM) or have to wait for it.
- **Remedy (state of the art, opened):**
  - Inject a `Clock` into the VM tick and the scan scheduler; tests use pointfree's `TestClock`/`ImmediateClock` (`swift-clocks` README, "TestClock", "ImmediateClock") to advance time explicitly, with no sleeps.
  - For task interleavings, `withMainSerialExecutor` from `swift-concurrency-extras` ("attempts to run all tasks spawned in an operation serially and deterministically", README lines 123-124) makes async tests deterministic. It is a package dependency and uses an unsupported-by-Apple hook, so it is a test-only dependency with a documented risk. Swift has no first-party deterministic scheduler in 6.2.
  - swift-testing features not used at all: `.timeLimit(.minutes(n))` (a hang breaker; the smallest unit is a minute: `TimeLimitTrait.swift:25`), `@Test(arguments:)` zipped/cartesian tables, `.tags` for the `swift test --filter`/`--skip` tiers the gate needs, `confirmation()` for event-count waits, `.serialized` for the few tests that share files, and exit tests (`#expect(processExitsWith:)`, `ExitTest.swift:40`) for precondition/`fatalError` guard paths (the project has many `fatalError`/preconditions with no test that they fire).
- **Effort:** M. **Risk:** low (test-only). **Depends on:** BT-1.

### BT-9 Missing oracles: the algorithms with no test have a known, cheap oracle each. SIGNIFICANT. Criteria: 4, 6
(From the map's row "No automated coverage" and the D-/N- rows. The pattern: the C++ side has oracles because libebur128 and Python existed; the Swift/AVFoundation side has none.)

| Algorithm (map row) | Today | Oracle that exists / is cheap | Where it runs |
|---|---|---|---|
| Spectrum analyzer + `SpectrumDoubleBuffer` | no test; a logged data race | Known-input property tests: a pure tone in bin k peaks in band(k), Parseval/energy within tolerance, silence → floor, a swept sine moves monotonically across bands; a TSan stress test of the double buffer | `swift test --sanitize=thread` |
| Enhanced streaming resampler (D37) | `SRCQualityMeasure` exe "REPLICATES the B4 setup" (`Package.swift:148`): measures its own copy of the configuration, asserts nothing | The same measurement as asserted thresholds (alias/image rejection in dB for 44.1→48, 96→48) calling the real resampler code. Also a **round-trip ramp**: a counter ramp through the real path must come out as a continuous ramp (no dropped/duplicated frames at chunk and seam edges) | swift-testing (BT-1) |
| Enhanced gapless roll | only the C++ contract (`GaplessContractTests`) and mirrors | Offline manual rendering as `VerifyAUGraph` already does: track A = ramp 0..N, track B = ramp N..2N; the output at the seam must be the continuous ramp: no gap, no duplicate, no click, at two sample-rate pairs. This is the classic gapless oracle; the project already has the offline-render rig | swift-testing + `AVAudioEngine` manual rendering |
| Transport epoch numbering | mirror only (BT-1) | Real VM + a fake engine; property: a stale-epoch snapshot is never applied (the stale-`ended` bug the freeze-fix reviewers all found independently) | `swift test` |
| HAL format negotiation + render path | hardware only | Split policy from I/O: the policy (`PureModeFormat`, `DeviceListPolicy`) is already in the C++ suite. For I/O, a private aggregate/null device in a nightly job is not reliable on hosted runners; keep it on the founder's HIL checklist (process review) and test everything above the HAL call | C++ suite (exists) + HIL |
| Output monitor | none | Feed the monitor a recorded device-event sequence; assert the published state | `swift test` |
| Two reorder rules meant to agree (`ListOrder.applying` vs `reorderPlaylist`, map N78) | "keep in step" comment; no test compares them | One property test over random permutations comparing the two | `swift test` |
| Format claims (`.aif` escape) | none | One table test: every extension the scanner claims × a real fixture (`@Test(arguments:)`) | `swift test` |

- **Why it matters:** these were the exact classes of the escapes (resampler, gapless seam, transport, launch path).
- **Effort:** M (each row is S-M once BT-1 lands). **Risk:** low.

### BT-10 Gate stage cost versus protection: sanitizing numeric sweeps adds no signal; Swift runs under no sanitizer. SIGNIFICANT. Criteria: 6
(Extends process.md §2.1, §3.2; I add the analysis, not the measurement.)
- **Evidence:** the three C++ builds (debug, ASan+UBSan, TSan) run all 198 tests, including accuracy sweeps (`EqFrequencyResponseSweepTests.inc`, `EqDesignerTests.inc`, `LoudnessOracleTests.inc`, `LimiterTruePeakTests.inc`) and CPU-budget tests. The tests that need TSan are small: `RenderGateTests.inc`, `SnapshotConcurrencyTests.inc`, the 3 EQ thread tests and the `std::thread` users (only 6 files contain `std::thread`, about 15 uses). UBSan matters for the biquad and vDSP indexing, and ASan for the decode bridge. None of the Swift tests, the real VM, the store (`sanitize-library-store` aside) or the app run under TSan.
- **Remedy:** a *tier* column in the test registry (BT-3): `tsan` runs only tests flagged `concurrent`; ASan/UBSan run everything except `accuracySweep`/`timing`; debug and -O2 run all. Add Swift TSan via `swift test --sanitize=thread` once BT-1 makes the logic reachable. This is the process review's recommendation, restated with its prerequisite (the registry flags) named.
- **Effort:** S once BT-3. **Risk:** low (the per-test cost output must come first, to avoid cutting by guess).

### BT-11 `VerifyLibraryStore` has a different concurrency idiom than the product, and its helpers are `@unchecked Sendable` islands. LOCAL. Criteria: 6
- **Evidence:** `Deadline.swift:36-56` `OneShotLatch: @unchecked Sendable` with a hand `NSLock`, justified in a comment (a `DispatchSemaphore` would trap). `withDeadline` races a task group against `Task.sleep` (a wall-clock bound, BT-6 again). `InstantiateBox: @unchecked Sendable` in `VerifyAUGraph/main.swift`.
- **Remedy:** `Synchronization.Mutex` (the codebase already uses it in `StallGate`) for latches; swift-testing `.timeLimit` replaces `withDeadline` after BT-2.
- **Effort:** S. **Risk:** low.

### BT-12 The real CPU and timing budgets are never asserted anywhere: the only optimised build is compile-only. SIGNIFICANT. Criteria: 4, 6
- **Evidence:** `EqDesignerTests.inc:1558-1580` (`Designer_Timing`: 250 us only `#if defined(__OPTIMIZE__)` and no sanitizer) and `EqTransitionTests.inc:408-428` / `EqEngineFixTests.inc:915-946` (the 5 % of one core budget, "Optimised builds only; -O0 and the sanitizers report"). `build-null-test.sh` compiles without `-O` for every run mode. The only `-O2` mode, `--release-strict` (`:72-73`), sets `BUILD_ONLY=1`, so it never runs. The gate runs debug (-O0), ASan and TSan; the optimised branches are dead code in CI and locally.
- **Root cause:** the budget was written as an `#if` on build flavour, but no stage builds and runs that flavour.
- **Why it matters:** the performance claims (EQ at 192/384/768 kHz, designer under 0.25 ms) have no automated proof. Meanwhile the -O0/sanitizer "tripwire" branches (1000 % of a core, 20 ms) run in the slowest builds and are what flaked (`EQ_Cpu` under TSan). process.md recommends "run CPU budgets in the debug and -O2 builds"; the -O2 run does not exist yet, so that saving needs a new stage first.
- **Structural remedy:** add an `-O2` *run* stage (replacing the plain debug run: fast, about a minute, and it also exposes optimiser-dependent UB) that executes the `timing` tests; delete the tripwire branches from sanitizer builds (skip via the BT-3 flag). Express budgets as a ratio to a calibration loop (BT-6).
- **Effort:** S. **Risk:** low. **Depends on:** BT-3.

---

## 2. What is GOOD: keep and copy

1. **The C++ oracle suite.** libebur128 as a test-only vendored submodule; a Python EQ oracle; bit-exact null tests; the plant-a-leak self-test (`make leak-check`) that proves the leak detector detects. The idea of a test that proves the *test* is not a no-op is excellent. Copy it to the semgrep rules (BT-5).
2. **Tests that compile the real code, not a copy.** `build-null-test.sh` links the production `.cpp`/`.mm` files; the drift guard fails when a new production source is neither compiled nor on a documented allowlist. This is the model for BT-7's script-reachability check.
3. **The Kit extraction pattern.** Nine pure Swift Kits (`PlaybackQueueKit`, `LibraryBrowseKit`, `EQEditKit`, `OutputDeviceKit`, ...) with headless-ness enforced by a gate, and decision tables tested exhaustively (about 730 tests). `TransportSnapshotTests` (VM-TS-02) tests a real lock-free property (a stuck publisher never blocks a reader) with the real type. This is the target shape: the VM's logic should join it.
4. **Token and design audits as oracles** (28 audit files in `DesignTokenKitTests`: contrast, focus ring, meter, spectrum ramp). Headless numeric checks of design rules, not screenshots.
5. **Tool-skew guard and pins** (`strict-gate.sh`: SwiftFormat/SwiftLint exact versions, clang-tidy major) plus the suppression policy (`check-suppressions.sh`: owner/reason/expiry, clang-tidy liveness check). Mature practice.
6. **Single source of C++ flags** (`scripts/lib/cxx-analysis-flags.sh`) shared by the compile, clang-tidy and the pre-commit hook.
7. **Release pipeline**: tag-vs-version check, signed artifacts, Sigstore provenance (`release.yml`).
8. **The fail-fast order** (cheap static first) and the "analysed ≥ 1 file" guards against a silent green.
9. **`RenderGate.h`** itself: named atomics and no standalone fences so TSan models every edge, documented memory-order pairs. Its test checks *no overlap* with a torn-read detector. Only the deadline in the test is the weak part (BT-6).
10. **Root-cause flake fixes** (EQ_Cpu scaled per rate; ANALYZER-05 made deterministic and ANALYZER-06 added): the right habit.

---

## 3. Duplicated capability (for the duplication pass)

- **Four test runners with the same job** (BT-2): swift-testing; `TestSupport.h`; `VerifyLibraryStore`'s `fail`/`printPass`/`CheckCase`; `VerifyAUGraph`'s own `fail`. Two copies of `fail(_:) -> Never` and two numbered PASS/FAIL printers.
- **Mirror type families duplicated from the app** in `MockAudioEngine.swift` (`SignalPathInfoMirror`, `OutputPathKindMirror`, `PureModeDecisionUIMirror`, `DecoderKindUIMirror`, `AudioDeviceModelMirror`, `AudioPlaybackEngineMirror`) and the `MockAdvanceController` state machine (BT-1).
- **Fixture builders in at least four places:** `makeTracks` (VM tests), `DetailTestSongs` / `song(_:by:on:)` (LibraryBrowseKitTests), `ScanFixtureBuilder` + `Fixtures.swift` (VerifyLibraryStore), `SheetFixture+Data.swift song(...)` (app DEBUG). Temp-directory creation is also repeated four times in `LibraryBrowseKitTests` (`FileManager.default.temporaryDirectory…` in `LibraryScanRaceGTests`, `LibraryScanFormatsGTests`, `LibraryBreakItGTests`, `DetailPageBreakItTests`) next to `VerifyLibraryStore`'s `tempStoreURL`, which uses `test-data/`: two policies for the same thing.
- **The stall rig** (`MainThreadStallRig.swift`, 255 lines, a real bridge on an offline engine) and **`VerifyAUGraph`'s offline manual-rendering graph** build the same thing (an offline `AVAudioEngine` with the real AUs) twice.
- **SRCQualityMeasure** replicates the production resampler's configuration instead of using it.
- **Lint rules in three places:** `.semgrep.yml`, inline `grep` stages in `strict-gate.sh`, and SwiftLint custom config (BT-4/5).
- **`make lint` vs. the gate's static block** (hand-copied commands).

## 4. Algorithms needing a correctness panel (map IDs where I know them)

- **D37** Enhanced streaming resampler (no oracle; the seam and chunk handling: the ramp-continuity oracle in BT-9 is the starting prototype).
- The Enhanced gapless roll (`AudioEngineBridge+GaplessRoll.swift`) and its seam against the Pure path.
- The spectrum analyzer and its double buffer (a data race is already logged).
- Transport epochs and the stale-snapshot rule (`TransportSnapshot` / epoch gate).
- **N78** vs the store's reorder rule (two implementations that "keep in step").
- `RenderGate.close()`'s polling loop with a hot renderer: lock-free but not wait-free; a render loop at near-100 % duty can starve the control thread. E2 shows a worst close of 0.7 ms idle, 45-123 ms with 1-2x CPU oversubscription, 114 ms at 4x. So a 1 s failure needs a runner deschedule or starvation; I could not reproduce the main-CI failure. The production duty cycle (a HAL callback every ~10 ms) is far lower than the test's loop, so this is a test-realism issue more than a product bug. The panel should confirm.

## 5. Notes on RenderGate_ConcurrentNeverOverlaps (another agent is fixing it)

Design guidance only. In E2 (a copy of the test's race, 14 cores), no close() reached 1 s with 0, 1x, 2x or 4x CPU hogs, nor under TSan with 0, 1x, 2x hogs. The failure on main CI therefore needs a >1 s stall of the render thread (or the control thread) on a small shared runner. Fix at the root: the test's timeout is a *liveness* bound that it should not enforce at 1 s (BT-6 kind 1). Pass a long bound (30-60 s) into `close()` from the test, keep the 1 s production bound in the product, assert the invariants (overlaps, torn, interleaving), and make the "interleaving" proof count-based (it already is). Do not raise 1 s to 5 s and call it done.

---

## 6. State of the art: what mature audio projects do (opened)

- **JUCE** (`juce_UnitTest.h`): self-registering tests with categories (`getTestsInCategory`), a per-run master seed so a random failure can be replayed (`createRandom`, lines 334-338), `beginTest` scopes. This is a template for BT-3 (registry flags, a replayable seed in the C++ suite; the soak and noise tests use fixed seeds today, good).
- **SFBAudioEngine** (`Tests/SFBAudioEngineTests/SFBAudioEngineTests.swift`): 33 lines, two tests of `InputSource`/`OutputTarget`. I opened it: it is **not** a model of a mature audio test suite. I found no public project at this scale with a better one; the honest benchmark is the libebur128 / ITU-R BS.1770 oracle approach this repo already uses, plus offline rendering for graph tests.
- **swift-testing** (opened, `TimeLimitTrait.swift`, `ExitTest.swift`): time limits (per test or suite), exit tests, parameterisation, tags, `confirmation`. The project uses almost none.
- **Deterministic async**: `swift-concurrency-extras` `withMainSerialExecutor` and `swift-clocks` `TestClock`/`ImmediateClock` (READMEs opened). Swift 6.2 itself has no first-party deterministic scheduler.

## 7. Open questions for the founder

1. **Adopt "test the real app" now?** Recommended: yes, as the first test-architecture step (BT-1, S). It is the single change that most reduces escape risk, and it needs no architecture decision first. Option: wait for the importable-core design from the architecture review.
2. **Retire the `Verify*` executables in favour of swift-testing, check by check?** Recommended: yes, store first, with the old gate running in parallel until the counts match (BT-2). Option: keep them and only fix the idiom (no more first-failure exit).
3. **Is a test-only dependency acceptable** (`swift-clocks`, `swift-concurrency-extras`)? Recommended: `swift-clocks` yes (small, widely used); decide `withMainSerialExecutor` after a one-day spike. Option: a 30-line home-made `ManualClock`.
4. **Which timing checks stay as pass/fail?** Recommended: liveness bounds stay (long); performance budgets become ratio-to-calibration or report-only (BT-6).
5. **Should the picture-sheet renderer stay in the app binary?** Recommended: yes for now (it is a human artifact), with a smoke test; move the stall rig to `Tests/` once BT-1 lands.
