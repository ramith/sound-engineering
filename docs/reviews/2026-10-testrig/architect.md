# Test rig and gate: architecture review (architect lens)

Reviewer: architect (one of three on the panel). Code read: `.claude/worktrees/testrig-review` (= `r1.1a/integration` @ b080a29), the seven PR #91 CI logs, the council's `area-build-test.md` (BT-1…BT-12) and `process.md`, and the memory notes on the gate. Read-only on the repo. My probes and downloaded sources are under `scratchpad/testrig/` (`probe-pkg/`, `probe-cpu/`, `src-*/`). Downloaded sources were read, never built or run.

This builds on the council's findings and does not repeat them. Where I agree with BT-n, I cite it and add what is new.

---

## 0. The short version

1. **The seven PR #91 CI runs had three root causes.** None of them was "a bad test".
   - **Tools drifted** (3 runs): Periphery's tap broke, cppcheck moved 2.21 to 2.22, and clang-tidy differed.
   - **The lane combination was only verified in CI** (1 run): imports the lanes left behind.
   - **Tests depended on time and scheduling** (3 runs): ANALYZER-05 twice, then `Loudness_WorkersSleepWhileIdle`.

   A fail-fast serial gate turned this into one failure per 80-minute run.
2. **Gate: one step list, run as up to five parallel CI jobs, collect-all, with one verdict.** Every step still runs on every PR and on main. Wall time becomes the longest job instead of the sum. Static checks and Periphery report in about 9 minutes. Every failure shows in the same run.
3. **Toolchain: one manifest file** with exact versions and checksums. The local install script and CI both read it, and a parity check runs at the top of the gate. Today eight of thirteen tool versions differ between your Mac and CI, Xcode included (§3.1). A weekly canary turns tool bumps into planned commits instead of surprise red runs.
4. **Lanes: three gaps, each closed at the source.**
   - **SwiftFormat lints nothing inside agent worktrees.** I proved it, found the root cause, and verified a one-flag fix (§4.1).
   - **Whole-program checks need a combine step.** Periphery, semgrep and shared test doubles get a `make combine-check` run on the integration branch before pushing.
   - **Every lint step asserts how many files it covered,** so a blind run fails instead of passing.
5. **Determinism has to be designed into the product.** Clock, scheduling, randomness, logging and per-test storage should be named, injected dependencies. The Engine sprint should make "deterministic from day one" an acceptance criterion:
   - a pull-model core whose time is the sample count;
   - events that carry track identity;
   - an injected scheduler, clock and track sources;
   - a manual host for tests and a seeded explorer of interleavings.

   W2's `Player` reducer is deterministic by construction if time and engine facts arrive as events.
6. **Your question, "check the support of the test framework".**
   - **What the frameworks give us:**
     - hang breakers (`.timeLimit`);
     - per-test isolation hooks (custom `TestScoping` traits);
     - logs attached only to failing tests (`Attachment`);
     - repeat, shuffle with a seed, and sharding (GoogleTest);
     - machine-readable reports.
   - **What no framework can do:** fix a test whose verdict depends on how busy the machine is. That fix is in our design.
   - **Two framework traps I measured:**
     - `.serialized` does not isolate a suite from other suites.
     - A misspelled `swift test --filter` runs zero tests and exits 0.
7. **Adopt:**
   - **Swift:** more of swift-testing (traits, attachments, time limits), plus our own ~60-line manual clock.
   - **Point-Free:** not yet. The latest swift-clocks needs Swift tools 6.4 and our toolchain is 6.3. `withMainSerialExecutor` sets a process-wide hook that would also serialise unrelated tests running in parallel.
   - **C++:** GoogleTest 1.18 (BSD-3), registered from the existing `kTests` table, so no test body changes.
   - **XCTest:** not needed.
8. **Plan:** Phase 0 (about a day) stops the bleeding. Phases 1–2 (about a week, 2 agents) deliver the parallel collect-all gate and the manifest. Phase 3 does test-tier hygiene and GoogleTest. Phase 4 rides on the Engine sprint and W2 (no standalone wave, per FD-1). Seven founder decisions are in §8.

---

## 1. What the evidence says

### 1.1 PR #91, run by run (from the CI logs)

| Run | Failed at | Class | Would a parallel collect-all gate have shown it earlier? |
|---|---|---|---|
| 1 (10-16) | clang-tidy, ~4 min in | tool behaviour (b1cc33c: `readability-trailing-comma` flagged a layout "either way"); CI LLVM 23.1.3 vs local 23.1.2 | same run as 3–4 (static job) |
| 2 (10-18 05:04) | tool check, 1 min in: Periphery tap "depends_on macos: :catalina is disabled", hidden by `brew install … \|\| true` (`strict-ci.yml:57`, old Periphery line) | infra drift; nothing tested | the parity check fails *loudly at install*, not at the tool check |
| 3 (18:48) | cppcheck 2.22 `shadowFunction` (00ca098) | unpinned tool drift | pinned in the manifest → never happens; a canary finds it first |
| 4 (19:14) | Periphery: 2 imports left by lanes + one dead key struct (ea0e48f) | combination-only | `make combine-check` before push |
| 5 (21:23) | `swift test`: ANALYZER-05 (2 == 1) | timing (wait with a deadline) | same run as 3–4; the cpp job would also have run |
| 6 (10-19 06:24) | ANALYZER-05 again: the hold's 30 s deadline | timing (hold with a deadline) | — |
| 7 (06:58) | null test `Loudness_WorkersSleepWhileIdle`: 11 context switches > 10 | measures the environment (process-wide `getrusage`, `LoudnessTests.inc:278-299`) | would have shown in run 5's cpp job, *if* it flaked that run |

Honest count: collect-all plus parallel jobs would have turned the seven runs into roughly three or four. Pins and a combine check would have removed three runs outright. Only better tests remove the timing runs, and that is §5.

### 1.2 Things the logs show that the council did not record

- **The null test's [FAIL] came 5 seconds in, and the gate kept running for 7.7 more minutes before it stopped.** In run 7 the failure printed at 06:50:28 (stderr is unbuffered), and the null test ended at 06:58:07. The sanitizers and leaks never ran.
- **The null test's stdout is fully buffered when piped.** Its first line, `=== DSPKernel Null Test Suite ===`, carries the *end* timestamp (06:58:07.78). In CI there is no progress output at all, so a hang would show nothing. The process review's "silent stretches" are partly this.
- **The CI log is 33 MB, and 98 % of it is app logging from the code under test.** Of 208,221 lines in run 7, 204,014 are `swiftpm-testing-helper … [UX] …` lines. `logUX` is an unconditional `NSLog` (`Sources/AdaptiveSound/UXLog.swift`). The top lines are `pureMode → false` (20,136 times) and `duration = 0.00s` (20,021). Failures drown in it, and synchronous NSLog writes also slow and perturb the tests themselves.
- **Per-step times (run 7, CI):**

  | Step | Time |
  |---|---|
  | Tool check and static checks up to cppcheck | ~23 s |
  | clang-tidy | 2 m 45 s |
  | Periphery | 4 m 30 s (it builds the package) |
  | Debug build | 6 s (Periphery's build is reused) |
  | `swift test` (962 tests, 151 suites) | ~2 m 40 s |
  | Null test | build 26 s, run 7.7 min, serial |

  Sprint G's sanitizer block took 66.9 min (process.md §2.1).

### 1.3 The flake families, named once

| Family | Instances | Root cause | Design answer (§5) |
|---|---|---|---|
| A wait that gives up at a deadline and carries on | RenderGate 1 s close; the seam window's 10 ms; ANALYZER-05's 30 s wait and 30 s hold; `PlayerRecording.samples` gives up after 2 s (`EnhancedTransportRig.swift:169-178`) | the test cannot observe the state it needs, so it guesses with time | an observable state or event; a long hang cap that fails loudly |
| Measuring the machine instead of the code | `WorkersSleepWhileIdle` (process-wide context switches); `EQ_Cpu_7_1` (wall clock across the Mac sleeping); `Designer_Timing`; `Realizer_ReinitDuringDrain` (bound = 4 × idle + 10 ms, `EqEngineTests.inc:1033-1060`) | wall time and process-wide counters include other work and system sleep | thread CPU time, ratio to a calibration loop, optimised-build tier only |
| An absolute threshold between noise and fault | `main-thread-stall` 25 ms bound vs an injected 2.5 s hold (`MainThreadStallSelfTest.swift:27-30`) | the threshold sits near the noise, not between noise and fault | fail above half the injected fault; report the 5 ms / 1 % target as a metric |
| Shared state across parallel tests | `OnDeckRig` shares one `UserDefaults` suite "that every rig shares and rigs in parallel tests write" (`OnDeckRig.swift:50-53`) | `.serialized` does not isolate suites from each other (§6.1) | a per-test isolation trait |
| Sleep used to wait for something | `EnhancedEndOfQueueTests.swift:90` sleeps 300 ms "anything the stop's completions set off has run"; `EnhancedTransportRig` paces renders with `Thread.sleep` (`:139`); `LiveReadoutsTests.swift:36` runs the main run loop for real time | AVFAudio completions arrive on its own threads, on device time | the engine's events derive from frames pulled (Engine sprint, §5.5) |

---

## 2. Gate structure

### 2.1 Principle: define the steps once, run them in many places

Today the step list lives in four places:
- `scripts/strict-gate.sh`, as 19 inline steps;
- `make lint` (a hand copy of four of them, `Makefile:197-201`);
- `make gate` (an `&&` chain, `Makefile:231-232`);
- the pre-commit hook.

Agents also assemble their own subsets.

**Design:**
- One **step registry**, `scripts/gate/steps.tsv`, with one row per step: id, job, tiers, blocking or advisory, timeout, command.
- One **runner**, `scripts/gate/run.sh --job <name> | --tier <name> | --step <id>`.

`make strict-gate`, `make check`, `make lint`, the pre-push hook and every CI job call the runner. "Local and CI cannot diverge" then becomes literally true, and "agents never hand-assemble a subset" is enforced by construction.

```
# id               job      tiers                  blocking  timeout  command
toolchain-parity   static   push,check,combine,ci  yes       2m       scripts/toolchain/check.sh
swiftformat        static   push,check,combine,ci  yes       5m       scripts/gate/swiftformat.sh
periphery          static   combine,ci             yes       15m      scripts/gate/periphery.sh
swift-test         swift    check,combine,ci       yes       30m      scripts/gate/swift-test.sh
null-debug         cpp      combine,ci             yes       30m      scripts/gate/null-test.sh --tier correctness
null-perf-O2       cpp      ci                     yes*      20m      scripts/gate/null-test.sh -O2 --tier timing
tsan-null          tsan     ci                     yes       45m      scripts/gate/null-test.sh --tsan --tier concurrent
…
```

### 2.2 Collect-all inside each job

- **The runner does not stop at the first failure.** Each step runs in its own process group with its own timeout. macOS has no `timeout`, so a small bash watchdog in `scripts/lib/` kills the group.
- **Each step writes `results/<id>.json`:** status, duration, the first 50 failing lines, and a log path.
- **The job's exit code is the AND of its blocking steps.** Only real dependencies are skipped: no build means no tests. Such a skip is recorded as "skipped: build failed", never as green.
- **"Analysed N ≥ 1" guards become a runner rule:** a step that reports covering zero files or zero tests fails. Today only clang-tidy has one (`strict-gate.sh:264-270`).

This keeps the doctrine "read the real exit code": the runner's exit code is the gate's verdict.

### 2.3 CI job graph (fits the 5-concurrent macOS limit)

| Job (macos-26) | Steps | Estimated wall time |
|---|---|---|
| `static` | parity, SwiftFormat, SwiftLint, clang-format, semgrep, suppressions, posture guards, cppcheck, clang-tidy, Periphery | ~9 min (from the run-7 times) |
| `swift` | debug build (`-Werror`), `swift test` (tiers: not `soak`), the main-thread-stall self-test | ~8–10 min |
| `cpp` | null test debug (correctness tier, `--parallel=3`), `-O2` *run* (timing tier, BT-12), VerifyAUGraph, SRCQualityMeasure, VerifyLibraryStore, coverage drift guard, leaks | ~10–14 min |
| `asan` | null test ASan+UBSan (skips accuracy sweeps and timing tests), store ASan | to measure; Sprint D took ~3 min before the sweeps grew |
| `tsan` | null test TSan (concurrent tier only); later Swift TSan on the tagged suites | to measure; ~29 min today, likely ~6–10 min after tiering |
| `report` (ubuntu, `if: always()`) | collects every `results/*.json` and writes ONE table to `$GITHUB_STEP_SUMMARY` plus one check named `gate` | <1 min |

All times except `static` are estimates to verify on the first run. The sanitizer savings depend on the per-test elapsed data (Phase 0 adds it).

Other settings:
- **Per-job `timeout-minutes`.** None exist today, so a hung job burns GitHub's 6-hour default.
- **Never cancel main:** `cancel-in-progress: ${{ github.event_name == 'pull_request' }}`. Today `strict-ci.yml:12-14` cancels main runs too; process.md counted 7, including the freeze fix.
- **The `report` job runs on Linux,** so it does not take a sixth macOS slot.

### 2.4 How this fits your way of working

- **You merge by hand, sometimes mid-CI (FD-6, kept).**
  - The design orders signals by time-to-value. Every PR #91 failure type would be visible within about 10–12 minutes of a push, not at minute 10, 20, 50 or 80 of successive runs.
  - The `gate` check's summary table says, at any moment, what has passed, what failed and what is still running. So a mid-CI merge is an informed one.
  - Main's run on the merge commit stays the real gate: never cancelled, collect-all, and stop-the-line on red.
- **One PR per sprint, CI runs the full gate.** Unchanged. The full gate is still every step on every PR and on main. What changes is wall time and that all failures arrive together.
- **I do not recommend path-based skipping of jobs on PRs** (process.md §4.3 proposed it). With one consolidated PR per sprint, nearly every PR touches every area, so path filters save little and add a way to miss a check. Main and the PR both run everything.

### 2.5 Blocking versus advisory

| Blocking (the `gate` check turns red) | Advisory (a warning row in the summary; never red) |
|---|---|
| Format, lint, clang-format, semgrep, the suppression policy, the posture guards, clang-tidy, cppcheck (once pinned), Periphery | Per-test duration trends and the slowest 20 tests |
| Toolchain parity (exact in CI) | The weekly **canary**: the latest tool versions run the static job and open an issue listing what would change |
| Debug build, `swift test`, the null test (correctness), the `-O2` compile and run, VerifyAUGraph, SRCQualityMeasure, VerifyLibraryStore, the coverage drift guard | The nightly **stress** run: concurrency-tagged tests repeated ×N under the CI-like profile; a failure opens a flake-ledger entry |
| ASan/UBSan, TSan, store ASan, leaks | Performance *trends* (the ratio-to-calibration numbers) |
| The main-thread-stall self-test, with its threshold moved between noise and fault (§5.3) | `make sheets` smoke (render one sheet, check it is not blank). This can become blocking later. |
| CPU budgets: blocking only in the `-O2` timing tier, on thread CPU time as a ratio with a generous margin (marked `yes*` above) | |

One rule keeps collect-all honest: **advisory never turns red, and blocking never turns yellow.** No "it's only the perf step" merges.

### 2.6 Caching (safe first, then fast)

1. **Tool downloads**, keyed by the manifest's hash. They are always safe: checksums are verified on restore too.
2. **SwiftPM checkouts** (`.build/checkouts`, `.build/repositories`), keyed by `Package.resolved`.
3. **`.build` for PR runs only**, keyed by (manifest hash, `Package.resolved`, `Package.swift`), with restore-keys. **Main always builds cold**, so a stale cache can never fake a green on main (memory: "stale builds").
4. **To verify:** let Periphery reuse the `swift` job's build through its index store (`periphery scan --skip-build --index-store-path …`). Periphery is the slowest static step (4.5 min) and today builds the package a second time.

### 2.7 Observability fixes (cheap, high value)

- **Null test:** call `setvbuf(stdout, nullptr, _IOLBF, 0)` in `main`, and print the elapsed time per test (`TestSupport.h:634-681`). This yields both live progress in CI and the data that sanitizer tiering needs (BT-3).
- **App logging under test:**
  - Phase 1: `logUX` writes through a process-wide sink. Tests install a quiet ring buffer, and a failing test attaches its tail with swift-testing's `Attachment.record` (present in our toolchain, §6.1).
  - Production moves from NSLog to `os.Logger`, which does not block the caller the way NSLog does. The stall self-test already allows for "an NSLog write" as a hiccup.
  - Phase 4: per-instance injection through the initializers (§5.2).
- **Reports:** `swift test --xunit-output`, and later GoogleTest's `--gtest_output=json` for the C++ side. The `report` job reads them for per-test status and times.

### 2.8 Local tiers

| Tier | When | What (all through `run.sh`) | Time |
|---|---|---|---|
| T0 pre-commit (exists) | each commit | staged files: format, lint, clang-tidy | seconds |
| T1 pre-push hook | each push | toolchain parity; SwiftFormat, SwiftLint and semgrep over *tracked* files; suppressions; posture guards | ~30–60 s |
| T2 `make check` | a lane says "done" | T1 + debug build + `swift test` + the touched C++ area's null tests + clang-tidy on changed C++ | ~6–10 min |
| T3 `make combine-check` | before pushing the integration branch | T2 + Periphery + clang-tidy all + the null test (correctness, parallel) + VerifyLibraryStore | ~15–20 min |
| T4 CI | each push | everything (§2.3) | ~15–40 min wall time, to measure |
| T5 nightly | main | stress ×N under the CI-like profile, Swift TSan, the canary | — |

None of these is a reason for `--no-verify`. T1 is fast enough never to tempt it.

---

## 3. One toolchain manifest, parity, and reproducing CI

### 3.1 Today's drift (measured 2026-10-19)

| Tool | Founder's Mac | CI (macos-26, 10-18) | Pinned today? |
|---|---|---|---|
| Xcode | 26.5 (17F42) | 26.6 (17F113), the image default; 26.5 is also on the image at `/Applications/Xcode_26.5.app` ([image readme](https://github.com/actions/runner-images/blob/main/images/macos/macos-26-arm64-Readme.md)) | name only (`macos-26`) |
| Swift | 6.3.2 | 6.3.3 | no |
| macOS | 26.6 | 26.6.2 | no |
| Runner image | — | 20260907.0351.1 (10-16), then 20261013.0424.1 (10-18) | no |
| LLVM / clang-tidy | 23.1.2 | 23.1.3_1 | major only (`cxx-analysis-flags.sh:106`) |
| clang-format | 23.1.0 (Homebrew's separate `clang-format` formula, `/opt/homebrew/bin`) | whatever comes first on PATH | **no** (memory: "a known gap") |
| semgrep | 1.175.0 | 1.180.0 | no |
| cppcheck | 2.21.0 | 2.22.0 | no (and the gate treats it as *optional*, `strict-gate.sh:94-96`) |
| ffmpeg (headers) | 9.0.1 | 9.0.2_1 | no; the **release build** also uses them (`release.yml:46`, `\|\| true`) |
| SwiftFormat / SwiftLint / Periphery | 0.63.0 / 0.65.1 / 2.21.2 | same | yes. Only Periphery has a checksum; SwiftFormat and SwiftLint are downloaded unverified (`strict-ci.yml:71-76`). |
| SwiftFormat's Swift version | none ("No Swift version was specified, so some formatting features were disabled", both checkouts) | same | no |
| GRDB | `Package.resolved` | same | yes (resolved), but Dependabot's comment says "zero-dependency" (`.github/dependabot.yml`), so nothing tracks it |
| **CPU** | Apple M4 Pro, 14 cores (10P + 4E), 24 GB | **3 vCPU (M1), 7 GB** ([GitHub runner spec](https://github.com/github/docs/blob/main/data/reusables/actions/supported-github-runners.md)) | — |

### 3.2 The manifest

One file, `toolchain/toolchain.env`. It uses shell-sourceable `KEY=value` lines so bash, make and Actions read it without extra tools. Every tool that can change a verdict is in it.

```
# Xcode / OS — CI selects this Xcode by path; local parity compares xcodebuild -version
XCODE_VERSION=26.6            XCODE_BUILD=17F113     SWIFT_VERSION=6.3.3
RUNNER_LABEL=macos-26         RUNNER_IMAGE_MIN=20261013
SWIFT_FORMAT_LANGUAGE=6.2     # --swiftversion for SwiftFormat (today: unset)
# Swift style + dead code (GitHub release zips)
SWIFTFORMAT_VERSION=0.63.0    SWIFTFORMAT_URL=…  SWIFTFORMAT_SHA256=<fill>
SWIFTLINT_VERSION=0.65.1      SWIFTLINT_URL=…    SWIFTLINT_SHA256=<fill>
PERIPHERY_VERSION=2.21.2      PERIPHERY_URL=…    PERIPHERY_SHA256=e5b4e802…fd4a
# C++ analysis — clang-tidy AND clang-format from ONE LLVM
LLVM_VERSION=23.1.3           LLVM_SOURCE=…      LLVM_SHA256=<fill>
CPPCHECK_VERSION=2.22.0       CPPCHECK_SOURCE=…  CPPCHECK_SHA256=<fill>   # no macOS binary: build once, cache
SEMGREP_VERSION=1.180.0       # pip, hash-locked requirements file in a private venv
FFMPEG_HEADERS_VERSION=9.0.2  # asserted from libavformat/version.h; vendoring is a later option
```

Mechanics:
- **`scripts/toolchain/install.sh`** reads the manifest. It installs into `~/.cache/adaptivesound-toolchain/<manifest-hash>/bin`, verifying every checksum and never touching global Homebrew, then prints the PATH line. CI runs the same script, and `$GITHUB_PATH` gets that one directory.
- **The CI Xcode is selected from the manifest:** `sudo xcode-select -s /Applications/Xcode_${XCODE_VERSION}.app`. Both 26.5 and 26.6 are on the image.
- **No `|| true` anywhere.** A failed install is a red step that says which tool failed.
- **To verify in Phase 2:** the exact-pin mechanism for LLVM (an upstream release tarball versus a Homebrew bottle URL), for cppcheck (build from the source tarball, then cache it) and for semgrep (pip with `--require-hashes`). I did not test these.
- **Release:** `release.yml` installs from the same manifest. The shipped binary then compiles against the same FFmpeg headers the gate analysed.

### 3.3 The parity check (`scripts/toolchain/check.sh`)

Step one of every tier (T1 to T5). It prints one table (tool, expected, actual, verdict).
- **Hard fail, locally and in CI:** every tool that decides pass or fail. That means SwiftFormat, SwiftLint, Periphery, clang-tidy, clang-format, cppcheck and semgrep, by exact version. Exact, because 2.21 to 2.22 and 23.1.2 to 23.1.3 were enough to break CI.
- **Local: warn; CI: fail:** an Xcode or Swift patch mismatch, the macOS patch level, and the FFmpeg headers. Locally you get a yellow line ("your Xcode is 26.5, the gate uses 26.6"), not a blocked gate.
- **CI only:** the runner image version is logged in the summary. If the image is older than `RUNNER_IMAGE_MIN`, the step fails.

### 3.4 Bumping on purpose

- **Rule (today's doctrine, generalised):** a bump is one commit, `toolchain: bump X a→b`, that changes the manifest *and* fixes the new findings. It is never mixed into a feature change.
- **The weekly canary workflow** runs the `static` job with the *latest* version of every tool. It opens one issue listing what each bump would change (new findings, format churn). Drift becomes a planned item instead of a red run on a feature PR. It also defuses the "three time-bombs after an idle gap" from the memory notes.
- **Dependabot:** add the `swift` ecosystem for GRDB, and delete the stale "zero-dependency" comment.
- **Language version:** add `--swiftversion` to `.swiftformat` in its own bump commit. Enabling the "disabled formatting features" will reformat some files.

### 3.5 Reproducing CI's conditions locally (CPU contention and parallelism)

What I measured (probe package at `scratchpad/testrig/probe-pkg/`; each test blocks a thread for 300 ms, so the peak counts threads):

| Setting | Peak tests running at once |
|---|---|
| default `swift test` on your Mac | **14** (CI: at most 3) |
| `swift test --no-parallel` | 1 |
| `swift test --parallel --num-workers 2` | 14: **no effect on swift-testing** |
| `LIBDISPATCH_COOPERATIVE_POOL_STRICT=1 swift test` | **1** |
| `taskpolicy -c background swift test` | 14: no effect |

So swift-testing's width follows the core count, and nothing in `swift test` narrows it to 3. The **CI-like profile** (`GATE_PROFILE=ci-like`) combines three things:
1. **Contention:** `ncpu − 3` CPU hogs at normal priority, started by a supervisor. The supervisor runs them in their own process group and kills the group on any exit (`trap … EXIT INT TERM`). This makes "16 leaked busy loops on the founder's Mac" impossible.
2. **Narrow scheduling for Swift tests:** `LIBDISPATCH_COOPERATIVE_POOL_STRICT=1`. That is width 1, harsher than CI's 3, which is the right side to err on for flakes.
3. **The C++ suite** runs with `--parallel=3` (or `--gtest_*` sharding later).

Use it in `make stress TEST=<id> N=200 PROFILE=ci-like`, the tool behind the "stress before landing" rule:
- Swift has no `--repetitions` through `swift test` (§6.1), so the stress tool loops `swift test --skip-build --filter <id>` and asserts that ≥ 1 test ran each time.
- C++ uses `--gtest_repeat=200 --gtest_shuffle` once GoogleTest is in.

**An exact replica (unverified):** a macOS VM built from the runner image, with 3 vCPU and 7 GB, is the only way to match CI's core count and memory. Tart is the usual tool. I did not open its docs or licence, so treat this as an option to research, not a recommendation.

**CPU budgets on a busy machine** (`scratchpad/testrig/probe-cpu/`): 400 M FMAs, measured on wall time (`steady_clock`) and on thread CPU time (`CLOCK_THREAD_CPUTIME_ID`):

| Condition | Wall | Thread CPU |
|---|---|---|
| idle | 355.6 ms | 355.6 ms |
| 28 hogs in the same process | **977.9 ms (×2.75)** | **410.0 ms (×1.15)** |
| idle again | 355.4 ms | 355.4 ms |

On Apple platforms libc++'s `steady_clock` is `CLOCK_MONOTONIC_RAW`, which "also counts cycles when the system is asleep" ([libcxx/src/chrono.cpp:173-183](https://github.com/llvm/llvm-project/blob/main/libcxx/src/chrono.cpp)). That explains `EQ_Cpu_7_1`'s 90,600 %. Thread CPU time does not advance while the thread is descheduled or the Mac sleeps.

---

## 4. Lanes and combination

### 4.1 SwiftFormat in worktrees: found, root-caused, fixed (verified)

Inside `.claude/worktrees/testrig-review`:

```
$ swiftformat --lint Sources/PlaybackQueueKit
Reading config file at .swiftformat      ← the PARENT repo's
0 files formatted, 1 file skipped.
$ swiftformat --lint Sources/PlaybackQueueKit/*.swift                          ← explicit paths
0 files formatted, 12 files skipped.
$ swiftformat --lint --config "$PWD/.swiftformat" Sources/PlaybackQueueKit
0/12 files require formatting.                                                ← actually linted
```

- **Root cause:** SwiftFormat reads the main checkout's `.swiftformat` (it walks up the parent directories), and that file's `--exclude docs,.claude` excludes the worktree itself. Explicit file paths do not help, so the pre-commit hook's `swiftformat "${swift_files[@]}"` formats nothing in a worktree either.
- **Fix:**
  - Every caller passes `--config "$repo_root/.swiftformat"`: the step script, the hook, and `make format`.
  - Callers lint `git ls-files '*.swift'` instead of a directory walk. The `.claude` exclude is then unnecessary and goes.
  - The step fails if SwiftFormat reports any "skipped" file, or lints fewer files than `git ls-files` lists. That is the same "covered N ≥ expected" guard as clang-tidy's.
- **SwiftLint:** apply the same rule (explicit tracked file list, explicit `--config`). The process review saw a SwiftLint worktree crash, and the same parent-config walk is the likely cause. That is not verified.

### 4.2 Combination-only failures are whole-program checks; give them a step

These steps see the whole program:
- **Periphery:** unused imports and declarations exist only relative to all callers.
- **semgrep and posture guards:** these are file-local, but each lane checks only its own files.
- **Shared test doubles:** a lane changes a double that another lane's tests use.
- **The full build and test.**

A lane's T2 cannot prove any of them. **`make combine-check`** runs T3 (§2.8) on the integration branch, after the linear cherry-pick that consolidation already does and before the push. That is about 15–20 minutes locally, against 80 minutes per CI discovery.

Do it **continuously**: after each lane lands on the integration branch, not only at the end. The R1.1-A integration branch already exists, so this is a habit plus one make target.

### 4.3 semgrep matching words in comments

Short term:
- add `pattern-not-regex: '^\s*(//|///|\*)'` to the regex rules that police code tokens. A match that overlaps a comment line is then dropped.
- add semgrep `--test` fixtures, so each rule has a line it must flag and a comment line it must not (BT-5).

Long term, the compiler enforces the rule. The engine module's AVFAudio and HAL members are `internal` (§5.5), so app code *cannot* name them. The regex then becomes a belt, not the structure.

### 4.4 Shared test doubles

Put shared doubles in **one test-support library target**:
- **A double provides inputs, never logic.** That is the anti-mirror rule from BT-1.
- **It conforms to the live protocol,** so the compiler checks it.
- **It has a named owner.** A lane that changes it says so in its brief, as a cross-owner seam (process.md §5).

---

## 5. Determinism as an architectural property

### 5.1 The rule

**Every source of nondeterminism in the product is a named, injected dependency.** Production passes the real thing. Tests pass a controllable one. The sources are:
- **time:** a `Clock`;
- **scheduling:** an executor or queue with a *drain/barrier*;
- **randomness:** a seedable generator;
- **environment:** a `UserDefaults` suite, file roots, the device list;
- **logging:** a sink.

The codebase already does this in places, and those places have no flakes:
- the Kits take `ContinuousClock.Instant` as a parameter (`TypeSelectBuffer`, `GridCursorState`, `ListSelection`);
- `AudioViewModel(defaults:engine:)`;
- `TrackLoudnessAnalyzer(log:)`;
- `tickTransport()` can be called by hand (`disarmTransportTick`: "in tests that tick by hand").

The rest are ambient.

### 5.2 Where the seams go (and they are not test-only)

| Place | Ambient today | Seam | Production benefit too |
|---|---|---|---|
| VM transport tick | `Timer` 20 Hz on `RunLoop.main` (`AudioViewModel+TransportTick.swift`, `runTransportTickIfLive`) | `TransportTicker` protocol (real: RunLoop timer; test: fired by hand) | under W2, most of the tick becomes engine *events* |
| VM commands | fire-and-forget `Task {}` in about 9 VM files; tests poll `settle()` (`OnDeckRig.swift:96-115`, 20 s deadline) | a **work tracker**: the VM keeps its command tasks; `await vm.work.idle()` | ordered shutdown: quit awaits in-flight commands |
| Bridge queues | 4 `DispatchQueue`s (`AudioEngineBridge.swift:239, 262, 307, 316`); rigs call `bridge.resampleQueue.sync {}` (`EnhancedTransportRig.swift:142`) | `func barrier() async` on the engine | the same barrier orders teardown; W2 folds the queues into one executor |
| Loudness analyzer | `Task.detached(priority: .utility)` per job, plus the `AVAudioFile` decode (`TrackLoudnessAnalyzer.swift:58, 166`) | an injected decoder (a stepped decoder in tests) and an **event stream** (job started, prefix, whole, cancelled, failed) | ANALYZER-04's 500 ms "nothing happened" window (`TrackLoudnessAnalyzerTests.swift:76`) becomes "a cancelled event arrived, with no whole profile before it"; ANALYZER-05's hold moves out of the sink |
| Logging | `logUX` → `NSLog`, unconditional | a sink (Phase 1: process-wide; Phase 4: per instance) | `os.Logger` in production; quiet CI logs; logs attached on failure |
| Test storage | a shared `UserDefaults` suite across parallel rigs | a per-test isolation trait (`TestScoping`, §6.1) that hands each test a UUID-named suite and removes it afterwards | — |
| Randomness | shuffle's generator (**not checked**: if it draws from the system generator, inject a seedable one) | a seed printed on failure | reproducible bug reports |

### 5.3 Three kinds of timing assertion, three designs

1. **Liveness** ("this must finish"). Wait on a state or an event, with a generous hang cap (≥ 10× typical) that **fails loudly**. That is ANALYZER-05's final form. Never assert on the deadline itself.
2. **Performance budgets.**
   - Measure **thread CPU time** (§3.5 probe), not wall time.
   - Express the budget as a **ratio to a calibration loop** run in the same thread and process (BT-6).
   - Run in the `-O2` timing tier only, at user-interactive QoS so the thread prefers P-cores.
   - Sanitizer and `-O0` builds skip these tests instead of carrying "tripwire" constants.
3. **Fault injection** (the stall test).
   - The rig injects a 2.5 s hold; the noise is ~5–30 ms.
   - Put the failure threshold between them: fail on any main-thread entry over half the hold.
   - Report the 25 ms and 5 ms / 1 % targets as metrics.
   - The 31.5 ms local miss under three gates was noise. A real regression waits the full 2.5 s.

Also: **observe states, not proxies.** The context-switch count becomes a per-worker parked flag plus a wake counter. That fix is in progress, and it is the pattern for the rest.

### 5.4 How this fits W2 (one transport owner)

- **W2's `Player` reducer, `(State, Event) -> (State, [Effect])`, is deterministic by construction, provided two things arrive as events:**
  - time, as `.tick(now)`;
  - engine facts, as `.seam(from:to:)`, `.ended(id)` and `.failed(id)`.
- **The effects are data, and a thin runtime executes them.**
  - The tests feed events and check states and effects, with no clock, queue or sleep. The D41 random-schedule explorer becomes a seeded fold over event sequences.
  - The runtime is the one nondeterministic part. It is small and is tested with the manual executor.
- **The seams in §5.2 are W2's scaffolding, not throwaway work:** the ticker, the work tracker, the barrier and the event stream.

### 5.5 The Engine sprint's interface: deterministic from day one

The sprint plan already chooses a pull model (`AVAudioSourceNode` over Pure's C++ decode and gapless pipeline), a separate SwiftPM module and a clean interface. That is the best possible starting point for determinism, because **the engine's time can be the count of frames rendered.** A test advances time by pulling frames, so no sleeps are needed. The `paced: true` sleeps in `EnhancedTransportRig` exist only because `AVAudioPlayerNode`'s completions arrive on AVFAudio's threads on device time.

Proposed shape (a sketch for the sprint's Discovery phase, not a spec):

```swift
// PlaybackEngineKit — its own SwiftPM target. AVFAudio/HAL members are `internal`:
// the app cannot name them (the compiler, not semgrep, enforces "main never touches the engine").
public protocol PlaybackEngine: Sendable {
    /// Non-blocking, ordered, newest-wins per playback; never touches hardware on the caller's thread.
    func send(_ command: EngineCommand)
    /// Facts with identity (fixes C-14's anonymous seam counts and F1/A2):
    /// .started(TrackID, epoch) .seam(from: TrackID, to: TrackID, atFrame:) .ended(TrackID, atFrame:)
    /// .failed(TrackID, EngineFailure) .deviceLost
    var events: AsyncStream<EngineEvent> { get }
    /// One lock-free copy for the readouts (the existing snapshot rule).
    func snapshot() -> EngineSnapshot
    /// Resolves when every command sent before it has been applied (ordered shutdown; tests).
    func barrier() async
}

// The core: pure Swift + the C++ pipeline, no AVFAudio. Built from injected parts:
struct EngineCore {
    init(sources: any TrackSourceFactory,   // prod: Pure's C++ FileDecodeSource/GaplessSource; test: ramps, failures on cue
         scheduler: any EngineScheduler,     // prod: one serial executor; test: ManualScheduler
         clock: any Clock<Duration>)          // only for wall-time limits (device ops); test: manual clock
    func render(into: UnsafeMutableAudioBufferListPointer, frames: Int)   // the RT pull; no locks, no allocation
}
// Hosts: AVAudioSourceNodeHost (production) and ManualHost (tests call render themselves).
```

The harness the sprint should ship with its first commit:
- **`EngineHarness(seed:)`**: `send`, `pump()` (run the control plane until idle), `render(frames:)`, `events`, and `decodeStep()`. Decode-ahead is a step the test schedules, so a decode that lags the render (an underrun) is a *deterministic* test.
- **A seeded interleaving explorer:** at each step it picks one of {deliver a command, run a decode step, render a block}, prints the seed on failure, and `ENGINE_SEED=…` replays it. This upgrades the D41 explorer from the VM's engine *model* to the real engine core.
- **Ramp-continuity oracles** (BT-9): track A plays 0…N and track B plays N…2N, so the output across a seam must be one continuous ramp, at several rate pairs.
- **One conformance suite, run against both Enhanced and Pure.** It turns the gapless invariants 1–7 written in `AudioPlaybackEngine.swift` into executable checks. The protocol comment already says they are "asserted by the shared conformance suite"; make that literally true.
- **A thin AVFAudio adapter,** checked by the existing offline manual-rendering rig and by the HIL checklist. It is the only part that needs them.

What stays non-deterministic on purpose:
- **Real-thread races:** TSan and the stress tier.
- **Real-time priority and audio-device behaviour:** the HIL checklist.

The deterministic tier adds to these and replaces none of them.

**Acceptance criterion to write into the Engine sprint:** "Every engine behaviour in the plan has a deterministic test on the ManualHost (no sleeps, no wall-clock waits). The explorer runs ≥ 10,000 seeded schedules in the gate under a minute."

---

## 6. "Check the support of the test framework" — the answer, from opened sources

### 6.1 swift-testing (our toolchain: Xcode 26.5 / Swift 6.3; upstream `release/6.3`)

What our toolchain has, from the local `Testing.swiftinterface`, with the upstream doc text:

| Feature | What it really does | Use it for | Source |
|---|---|---|---|
| `.timeLimit(.minutes(n))` | cancels the test's task and records `timeLimitExceeded`; **minutes only**, with a granularity of one minute; the shortest limit wins; a run-wide maximum can be configured | a **hang breaker** on every async and rig suite (0 uses today, BT-8). Never a timing assertion. | [LimitingExecutionTime.md](https://github.com/swiftlang/swift-testing/blob/release/6.3/Sources/Testing/Testing.docc/LimitingExecutionTime.md); [TimeLimitTrait.swift:224-241](https://github.com/swiftlang/swift-testing/blob/release/6.3/Sources/Testing/Traits/TimeLimitTrait.swift); interface lines 1108-1130 |
| `.serialized` | serialises the tests *inside* the suite. "This trait does not affect the execution of a test relative to its peers or to unrelated tests." | ordering *within* a suite only. **It does not protect shared global state** (the shared `UserDefaults` suite, env vars, process-wide hooks). | [ParallelizationTrait.swift:11-29](https://github.com/swiftlang/swift-testing/blob/release/6.3/Sources/Testing/Traits/ParallelizationTrait.swift); [Parallelization.md](https://github.com/swiftlang/swift-testing/blob/release/6.3/Sources/Testing/Testing.docc/Parallelization.md) |
| `confirmation(expectedCount:)` (an Int, a range, or 0) | "When the closure returns, the testing library checks…": **it does not wait for later events** | callbacks that happen *inside* the awaited work. Async events need an awaitable event stream from the product (§5.2). | [Confirmation.swift:95-96](https://github.com/swiftlang/swift-testing/blob/release/6.3/Sources/Testing/Issues/Confirmation.swift); [testing-asynchronous-code.md](https://github.com/swiftlang/swift-testing/blob/release/6.3/Sources/Testing/Testing.docc/testing-asynchronous-code.md) |
| `TestScoping` custom traits | wraps each test (or suite) in our own setup and teardown | the **isolation trait**: a per-test `UserDefaults` suite and temp dir, a log capture, a task-local manual clock | interface line 1139; [Trait.swift](https://github.com/swiftlang/swift-testing/blob/release/6.3/Sources/Testing/Traits/Trait.swift) |
| `Attachment.record` + `--attachments-path` | attaches data to the test's result | the log tail of *failing* tests only. This is what fixes the 33 MB log. | interface lines 467-498; `swift test --help` |
| Exit tests, `#expect(processExitsWith:)` | runs a closure in a child process and checks how it exits | test that preconditions and `fatalError` guards fire (BT-8) | interface lines 599-601 |
| `Issue.record(…, severity: .warning)` | a non-failing issue | advisory signals inside the run (perf trend notes) | interface lines 665-717 |
| `Test.cancel()` | cancels at run time | "no FFmpeg on this machine" style skips that are visible in reports | interface line 1222 |
| `withKnownIssue(isIntermittent:)` | expects a failure that may or may not occur | **avoid.** It hides flakes. Allow it only through the suppression policy (owner, reason, expiry). | [KnownIssue.swift](https://github.com/swiftlang/swift-testing/blob/release/6.3/Sources/Testing/Issues/KnownIssue.swift); interface lines 728-731 |
| Run controls | the entry point has `--repetitions`, `--repeat-until`, `--experimental-maximum-parallelization-width`, `--event-stream-output-path` ([EntryPoint.swift:489-535](https://github.com/swiftlang/swift-testing/blob/release/6.3/Sources/Testing/ABI/EntryPoints/EntryPoint.swift)), **but `swift test` in our toolchain exposes none of them** (`swift test --help`). It does expose `--filter`, `--skip`, `--no-parallel`, `--xunit-output`, `--attachments-path`. | — | probe: `--num-workers` has no effect on swift-testing (§3.5) |
| `--filter` | regular expressions over test IDs (module.Suite/function). **A display name matches nothing, and zero matches exits 0** (probe: "No matching test cases were run", exit 0). | every wrapper (stress, gate) asserts ≥ 1 test ran, from the xunit file | probe in `probe-pkg/` |

### 6.2 Point-Free

- **swift-clocks** gives `TestClock`, `ImmediateClock`, `UnimplementedClock` and `AnyClock` ([README](https://github.com/pointfreeco/swift-clocks/blob/main/README.md)). This is exactly what an injected clock wants.
  - **But** the latest release, 1.1.1 (2026-08-27), declares `swift-tools-version: 6.4` ([Package.swift](https://github.com/pointfreeco/swift-clocks/blob/1.1.1/Package.swift)). Our local and CI toolchains are 6.3.x, so they cannot use it.
  - 1.1.0 declares 6.0 ([Package.swift](https://github.com/pointfreeco/swift-clocks/blob/1.1.0/Package.swift)).
  - It also pulls in swift-concurrency-extras, swift-issue-reporting and the docc plugin.
- **swift-concurrency-extras `withMainSerialExecutor`** (1.4.3, 2026-10-14, tools 6.0):
  - It "*attempts* to run all tasks… serially… it relies on a global, mutable variable in the Swift runtime… no scoping guarantees" ([MainSerialExecutor.swift:22-28](https://github.com/pointfreeco/swift-concurrency-extras/blob/main/Sources/ConcurrencyExtras/MainSerialExecutor.swift)).
  - Concretely, it sets `swift_task_enqueueGlobal_hook` for the whole process through `dlsym` (lines 82-101).
  - swift-testing runs tests in parallel in one process, and `.serialized` does not isolate suites from each other (§6.1). So while one test uses it, *every* concurrently running test's tasks go to the main actor.
  - It is only safe in its own `swift test --filter … --no-parallel` invocation. Its `.taskLocal` test trait ([README](https://github.com/pointfreeco/swift-concurrency-extras/blob/main/README.md)) is harmless and handy.
- **Recommendation:**
  - Write our own `ManualClock: Clock` now. The `Clock` protocol is in the standard library, and the clock is about 60 lines in the test-support target, checked by its own tests.
  - Re-evaluate swift-clocks when the toolchain manifest moves to Swift 6.4.
  - Do not build the rig on `withMainSerialExecutor`. Prefer explicit product seams (work tracker, barrier, event stream), which also serve production.
  - If a one-day spike shows it rescues the existing VM suites cheaply, allow it in one isolated, serial test invocation.

### 6.3 XCTest (local SDK headers, `XCTest.framework/Headers`)

- **`executionTimeAllowance`** works only "if test timeouts are enabled", rounds up to the minute, and has Xcode capture a spindump (`XCTestCase.h:200-214`). It is an `xcodebuild` feature, not available through `swift test`.
- **`wait(for:timeout:)` and `fulfillment(of:timeout:)`** are the same wall-clock deadline pattern (`XCTWaiter.h`).
- **`XCTCPUMetric(limitingToCurrentThread:)`** measures CPU, not wall time (`XCTMetric.h:313-328`). This is the right idea, but I found no API in the headers to assert against a stored baseline.
- **Verdict:** nothing to adopt. swift-testing plus thread-CPU measurement covers it.

### 6.4 C++: GoogleTest vs Catch2 vs the home runner

| Need | Home runner (`TestSupport.h:623-770`) | GoogleTest 1.18.0 (BSD-3, 2026-08-10) | Catch2 v3 |
|---|---|---|---|
| Works with our `-fno-exceptions -fno-rtti` compile | yes | **yes**: detects both (`gtest-port.h:451-472, 566-568`) | **weakly**: without exceptions a failing `REQUIRE` calls `std::terminate` ([configuration.md:240-251](https://github.com/catchorg/Catch2/blob/devel/docs/configuration.md)) |
| Repeat until a flake shows | no | `--gtest_repeat`, `--gtest_break_on_failure` ([advanced.md "Repeating the Tests"](https://github.com/google/googletest/blob/main/docs/advanced.md)) | not in its CLI docs |
| Shuffle with a printed, replayable seed | no | `--gtest_shuffle`, `--gtest_random_seed` | `--order rand`, `--rng-seed` |
| Sharding across processes and CI jobs | no | `GTEST_TOTAL_SHARDS` / `GTEST_SHARD_INDEX` | `--shard-count` / `--shard-index` |
| Filter | exact name only (`DSPKernelNullTest.cpp:550-630`) | globs and negatives | tags `[timing]`, `~[slow]` |
| Machine report with per-test time | no | XML and JSON (`--gtest_output=json:…`) | JUnit and other reporters |
| Death tests (preconditions) | no | yes (fork-based on macOS) | no |
| Per-test timeout | no | **no** (none in its docs); its event-listener API lets us add one | **no** (none in its docs); a listener is possible |
| Adoption cost | — | **low**: `testing::RegisterTest` registers tests from our existing `kTests` table at run time ([advanced.md "Registering tests programmatically"](https://github.com/google/googletest/blob/main/docs/advanced.md)), so test bodies don't change; `logFail` maps to `ADD_FAILURE` | a rewrite of the assertions |

**Recommendation: GoogleTest**, vendored as a git submodule like libebur128:
- It is registered from `kTests`, with a ~40-line watchdog listener.
- Each `TestEntry` gains tier flags (`correctness`, `timing`, `accuracySweep`, `concurrent`, `needsFfmpeg`), which become name prefixes or filters.
- Run both runners for one sprint, with equal counts required, then retire the home runner's loop.
- Its BSD-3 licence fits Apache-2.0.
- It answers "prefer established libraries" with zero churn to the 244 test bodies. It also delivers the stress rule natively: `--gtest_repeat=200 --gtest_shuffle --gtest_filter=X`.

**Alternative:** extend the home runner (BT-3, about a day). It is cheaper today, but it re-implements GoogleTest's runner feature by feature, and it has no death tests.

### 6.5 The plain-words answer to your question

The frameworks help where they can:
- they break hangs;
- they repeat and shuffle tests to flush out flakes;
- they isolate each test;
- they attach logs only to failures;
- they report every result.

We use almost none of this today, and we should. No framework can make a test reliable if its pass or fail depends on how busy the machine is. Six of the flakes in §1.3 were that kind. Those are fixed by how we build the product (injected time and scheduling, events with identity) and how we write tests (wait for states, measure CPU not wall time). The Engine sprint is the chance to build the most timing-sensitive part of the app that way from the start.

---

## 7. Phased plan

| Phase | What | Effort | Risk | Lands in |
|---|---|---|---|---|
| **0. Stop the bleeding** | <ul><li>Remove `\|\| true`; checksums for SwiftFormat and SwiftLint; cppcheck required</li><li>Per-job `timeout-minutes`; never cancel main</li><li>Null test line-buffered, with per-test elapsed</li><li>SwiftFormat `--config`, tracked file lists and the covered-count guard (and the same for SwiftLint)</li><li>The "≥ 1 test ran" guard for every filtered run</li><li>The hog supervisor with trap cleanup; `make stress`</li><li>A flake ledger file</li></ul> | S (~1 agent-day) | low | next PR (can ride R1.1-A's close-out, or the rig PR) |
| **1. Collect-all gate + parallel CI** | <ul><li>`steps.tsv` + `run.sh` + `results/*.json`</li><li>The five macOS jobs + the Linux `report` job and the `gate` check</li><li>`make check`, `make combine-check`, the T1 pre-push hook</li><li>Caching (tools, checkouts; `.build` on PRs only)</li><li>The test log sink (quiet + attach on failure)</li></ul> | M (2–3 agent-days) | low–med: workflow churn. Mitigation: keep the old serial job as a nightly run for one week and compare verdicts. | one small "rig" PR |
| **2. Toolchain manifest + parity + canary** | <ul><li>`toolchain.env`, `install.sh`, `check.sh`</li><li>Exact LLVM (clang-tidy *and* clang-format), cppcheck, semgrep and FFmpeg-header pins</li><li>Xcode chosen by path in CI</li><li>`release.yml` uses the manifest</li><li>The weekly canary; Dependabot `swift`; `--swiftversion` in its own bump commit</li></ul> | M (2 agent-days; the pin mechanisms need verifying) | med: an install mechanism may need a second try | same rig PR |
| **3. Test-tier hygiene** | <ul><li>C++ tier flags: sanitizers skip sweeps and timing; the `-O2` run tier with thread-CPU and calibration ratios</li><li>The stall test's threshold set between noise and fault</li><li>The isolation trait (defaults, temp dirs, log capture), suite `.timeLimit` defaults, `ManualClock`</li><li>GoogleTest through `RegisterTest` (both runners in parallel for a sprint)</li><li>semgrep `--test` fixtures and comment exclusion</li><li>Sweep the remaining deadline-and-carry-on waits (§1.3)</li></ul> | M–L (4–6 agent-days; splits well into 2 lanes) | low–med | R1.1-B, or a second rig PR |
| **4. Determinism in the product** | <ul><li>The Engine sprint's interface and harness (§5.5), as its acceptance criterion</li><li>VM ticker, work tracker and bridge barrier</li><li>Analyzer decoder and event-stream seams</li><li>Per-instance log sinks</li><li>W2's reducer when funded (§5.4)</li></ul> | about +10–15 % of those sprints' build time (my estimate) | med | the Engine sprint; W2. No standalone wave (FD-1). |
| **5. Nightly and replica** | <ul><li>Nightly: concurrency-tagged tests repeated ×N under the CI-like profile, Swift TSan, the canary, the trend file</li><li>Optional: research a 3-vCPU VM replica (unverified)</li></ul> | S–M | low | after Phase 1 |

Two agents at a time fits the plan:
- Phases 0–2 are one lane each for the CI and runner work and the toolchain work.
- Phase 3 splits into a Swift lane and a C++ lane.

---

## 8. Decisions for you (recommendation first, plain words)

1. **How CI runs the gate.**
   - **Recommended:** split it into five jobs that run side by side, and have every check run to the end. A single summary then shows every failure at once, usually within 10–15 minutes.
   - Every check still runs on every PR and on main.
   - *Option:* keep today's single job that stops at the first failure (about 80 minutes per discovery).
2. **What stops a merge versus what only warns.**
   - **Recommended:** correctness and safety checks turn the gate red, including CPU budgets in the optimised build. Trends, the weekly "newer tools" canary and the nightly stress run only warn.
   - A red main still means stop and fix the same day. You keep merging by hand (FD-6).
   - *Option:* everything blocking.
3. **Pin every tool exactly, in one file, Xcode included.**
   - **Recommended:** yes, with checksums. The same version runs on your Mac and in CI, and changes come as deliberate one-commit bumps proposed by a weekly canary.
   - For Xcode, move your Mac to **26.6** (CI's default), rather than holding CI back on 26.5.
   - *Option:* pin only the style tools, as today. That accepts more CI-only surprises like cppcheck 2.22.
4. **The C++ test runner.**
   - **Recommended:** adopt GoogleTest (an established, BSD-licensed library). It plugs into today's test list without rewriting the 244 tests and adds repeat, shuffle, sharding and reports.
   - *Option:* keep extending our own runner. It is cheaper for now, but we would keep re-building what GoogleTest already has.
5. **Controlling time in Swift tests.**
   - **Recommended:** our own small manual clock now. Adopt Point-Free's clock library when our toolchain reaches Swift 6.4; its latest version needs that.
   - Don't base the rig on Point-Free's "run everything serially" switch. It changes a process-wide setting and would slow or perturb unrelated tests running at the same time.
   - *Option:* adopt swift-clocks 1.1.0 now, with its two extra dependencies.
6. **The Engine sprint's interface.**
   - **Recommended:** make "every engine behaviour has a test that runs without sleeps or wall-clock waits" part of the Engine sprint's definition of done. That means:
     - time measured in frames played;
     - events that say which track;
     - a seeded explorer that tries thousands of orderings.
   - *Option:* design the interface first and add test seams later. History here says that produces timing tests.
7. **Where this work goes.**
   - **Recommended:** Phases 0–2 as one small "test rig" PR now (about a week with two agents), Phase 3 inside R1.1-B, and Phase 4 inside the Engine sprint and W2.
   - *Option:* fold everything into R1.1-B. That is cheaper to schedule, but the next sprint's PR then pays the 80-minute cycles again.

---

## 9. Pre-mortem of this design (the-fool, "find the failure modes")

**Steelman of the opposite view:** "Just fix the flaky tests and pin the tools. The serial gate is simple, and a parallel graph is more YAML to maintain."

Conceded:
- Three of PR #91's seven runs were tests, and only better tests remove them.
- The serial gate's "cheap checks first" order is good.

Not conceded: the serial gate's cost is structural. Each discovery costs a full cycle, and at 80 minutes per cycle that cost compounds across a one-PR-per-sprint workflow.

Six months on, if this design failed, these are the likely reasons:

| Failure narrative | Early warning | Mitigation built in |
|---|---|---|
| **Parallel jobs queue behind the 5-macOS-job limit.** Two pushes plus a main run make wall time worse than serial. | Jobs show "queued" time in the summary. | Five macOS jobs at most, report on Linux, superseded PR runs cancelled (main never). Measure queue time in the report. |
| **Collect-all breeds tolerance:** "only the perf step is red, merge anyway". | Advisory rows grow, or blocking reds get waved through. | One `gate` verdict; advisory never turns red; the blocking list lives in `steps.tsv`, and changing it is a reviewed commit. |
| **Pinned tools rot,** and a big-bang bump months later breaks everything (the memory notes' "three time-bombs"). | Canary issues pile up unanswered. | The weekly canary plus a standing bump at each sprint start; a canary issue older than one sprint is a planning item. |
| **The determinism seams become a parallel world:** ManualHost tests pass while the AVAudioSourceNode host breaks. That is the mirror failure again (BT-1). | Bugs found by ear that the harness "covered". | The seams sit only at the edges (host, clock, scheduler, sources); the logic under test is the same object. Doubles provide inputs, never logic. The offline-render rig plus the HIL checklist cover the adapter. |
| **GoogleTest adoption disturbs the suite,** or behaves differently under TSan. | Count mismatches; new TSan reports from the framework itself. | Both runners for one sprint with equal counts; register from `kTests`; TSan runs only the `concurrent` tier. |
| **The CI-like local profile is ignored,** because it is slow, and timing tests land unstressed again. | A new flake in CI on a test added that sprint. | `make stress` is one command with leak-proof hogs; the PR template asks for its output when a concurrency or timing test is added (process.md §4.4). Nightly stress is the backstop. |

**Inversion:** what would guarantee the flakes come back?
- Keeping ambient time in the new engine.
- Letting `.serialized` stand in for isolation.
- Accepting a "0 tests ran" green.
- Letting brew pick tool versions.

Each has a named counter above.

---

## Appendix: probe and source locations

- **Probes (mine, built and run in scratch):**
  - `scratchpad/testrig/probe-pkg/`: swift-testing width, filter and `--no-parallel` behaviour.
  - `scratchpad/testrig/probe-cpu/cpu.cpp`: wall versus thread CPU time under contention.
- **Downloaded sources (read only):**
  - `scratchpad/testrig/src-swift-testing/` (release/6.3)
  - `src-pointfree/`
  - `src-cpp-frameworks/` (googletest main, Catch2 devel)
  - `src-libcxx/chrono.cpp`
  - `src-gh-docs/` (runner spec, macos-26-arm64 image readme)
- **Local toolchain interfaces:**
  - `/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/Library/Frameworks/Testing.framework/Versions/A/Modules/Testing.swiftmodule/arm64e-apple-macos.swiftinterface`
  - `…/MacOSX.platform/Developer/Library/Frameworks/XCTest.framework/Headers/`
- **CI logs:** `scratchpad/pr91-failed{,2..7}.log`.
- **Unverified and flagged:**
  - the exact pin mechanisms for LLVM, cppcheck and semgrep;
  - Periphery reusing the build's index store;
  - the sanitizer-tier savings and the per-job wall times (estimates);
  - shuffle's random source;
  - SwiftLint's worktree behaviour;
  - a VM replica of the runner (tart not opened).
