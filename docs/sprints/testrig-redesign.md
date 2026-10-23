# The test-rig redesign (2026-10-19 → 2026-10-23)

A sprint of its own, between R1.1-A and R1.1-B. The founder's decision: "Whole redesign before any new feature".

**Why.** PR #91 (R1.1-A) went red on CI seven times, and each run showed one new failure. Not one bad test, but three causes:
- **Tool drift (3 runs):** Periphery's tap broke behind `|| true`; cppcheck moved 2.21 → 2.22; clang-tidy behaviour changed.
- **A combination checked only in CI (1 run):** each lane was verified alone.
- **Tests that depended on time or the machine (3 runs):** RenderGate's 1 s deadline, ANALYZER-05's 30 s hold, and a process-wide context-switch count.

The gate stopped at the first failure, so each cause cost an 80-minute run. Founder: "redesign the test rig to avoid these problems… widen the aperture", and "check the support of the test framework".

**Panel and plan.** Three reviewers (qa-expert, refactoring-specialist, architect-reviewer) each wrote a report: [2026-10 test-rig reviews](../reviews/2026-10-testrig/). The synthesis gives the four rules:
1. **Time only ever breaks hangs.** Every wait waits for a state. Its cap fails loudly, naming the state. Nothing carries on past a deadline.
2. **Measure the component, never the machine.**
3. **Each test owns its world.**
4. **Every run has a ceiling and reports everything.**

## Founder decisions
1. **The gate runs everything to completion:** parallel CI jobs plus one summary check, still named `strict-gate`. Merging stays manual.
2. **One toolchain manifest** (`toolchain/toolchain.env`): exact versions and checksums, one install script on the Mac and CI, and a parity check first.
   - Amended 2026-10-21: **everything moves to Xcode 27.1 (Swift 6.4).** CI uses GitHub's `xcode-27` image (macOS 27), while the product targets macOS 26.
3. **The C++ runner adopts GoogleTest** (1.18.0, a submodule), plus our own per-test watchdog.
4. **Whole redesign before any new feature.**
5. **swift-clocks, test-only** (1.1.1, the latest; it builds on Swift 6.4).
6. **The main-thread-stall check is judged by behaviour, not a stopwatch.**
7. **Flaky tests are fixed immediately,** never quarantined or retried.

Later answers:
- **The architecture review (2026-10-22):**
  - a macOS 26 runtime check, nightly and before every release;
  - nightly failures open one GitHub issue;
  - the toolchain cache trimmed;
  - FFmpeg must not be able to switch off the gate.
- **FFmpeg "works with any version":** researched, and placed in the backlog for later ([US-R1F-17](../product/backlog.md)).

## What changed
**Xcode 27.1 bring-up (PR #94, merged before the redesign PR):**
- SwiftPM's new build engine broke `-import-objc-header`. The code now uses `import AudioDSP` (the module map), and the dead bridging header is gone.
- `-D_LIBCPP_DISABLE_AVAILABILITY` is removed. It made binaries call a macOS 27-only libc++ symbol, which fails to load on macOS 26.
- Swift 6.4's capture rules are satisfied.
- `make build` finds the app through `--show-bin-path`.

**The gate (lane A, plus fixes from the architecture review):**
- **One step registry,** `scripts/gate/steps.tsv` (34 steps), and one runner, `scripts/gate/run.sh`.
  - Collect-all, a watchdog per step, and a result record per step.
  - A step that covers zero files or tests fails.
  - Exit 134 from the C++ watchdog is reported as a named hang.
- **CI** (`strict-ci.yml`): jobs `static`, `swift`, `cpp`, `asan` and `tsan` on `xcode-27`, plus the `strict-gate` summary on Ubuntu.
  - The summary reads one stamped run per job; a missing, stale or duplicate run is red.
  - Every job has a time limit. A run on main is never cancelled, pending or running.
  - Actions are SHA-pinned.
- **Toolchain** (`scripts/toolchain/`):
  - exact pins with checksums: SwiftFormat, SwiftLint, Periphery 2.21.2, LLVM 23.1.3 (only clang-tidy and clang-format kept), cppcheck 2.22.0 built from source, semgrep 1.180.0 hash-locked, actionlint, Python 3.12, GoogleTest;
  - a parity table, where FFmpeg is info only;
  - the cache is trimmed, and old versions are pruned.
- **New checks:**
  - `deployment-target`, plus an `availability-ban` on the flags that hide availability;
  - `macos26-run.sh` (the `macos26-*` workflows): binaries built on 27 must load and pass on a macOS 26 runner, nightly and before a release;
  - `report-selftest`, `timelimit-guard`, `registry-lint` and `semgrep-rule-tests`;
  - `swift-test-rig`, for the heavy real-engine suites run one at a time.
- **Other workflows:** a weekly **canary** (latest tools, one issue); a **nightly stress** run (the Swift suites, the C++ Concurrent tier shuffled, and the verifiers on one cooperative thread; a failure opens one issue).
- **Worktree blind spots closed:** SwiftFormat reads the worktree's own config; `core.hooksPath` is relative; the hooks use the pinned tools; a submodule that isn't checked out is named.
- **Local tiers:** `make check` (T2), `make combine-check` (T3), `make stress` (the CI-like profile: CPU hogs in their own process group, and `LIBDISPATCH_COOPERATIVE_POOL_STRICT=1`).

**C++ (lane B):**
- The null test runs on **GoogleTest 1.18.0** (`Tests/NullTestRunner.h`). The 245 tests keep their names; the golden master is unchanged.
- Each test sits in one tier: Correctness 141, Concurrent 89, AccuracySweep 10, Timing 5. 58 tests are serial-only.
- A per-test watchdog prints `[HANG] <test>`. It uses awake time, so a sleeping Mac doesn't trip it.
- The `rig::` primitives are in `TestSupport.h`.
- Timing checks use thread CPU time with ≥ 10× tripwires. Strict budgets live only in the `-O2` timing tier.
- The gate runs plain, ASan and TSan on every tier, in 3 shards each.

**Swift (lane C):**
- **RigKit** (`Tests/RigKit`): `until` (caps on SuspendingClock), `blocking`, `Hold` and the log tail.
- **Product seams,** each defaulting to today's behaviour:
  - `TransportTicker`, `WorkTracker`, injected `Clock`s for the debounces, and `SettingsStore.pendingWrite`;
  - a quiet `UXLog` sink in tests;
  - `StreamObserver` on the Enhanced path (nil in the app).
- **The track-loudness decode runs on its own queue.** It used to block Swift's cooperative pool.
- **S1–S14 and R1–R10 migrated.** The Enhanced rig runs in lock-step with the completion chain.
- **A semgrep rule, `test-no-raw-time`.**

**Verifiers and the stall check (lane C2):**
- The **main-thread-stall check holds the engine lock on purpose** and passes only if main keeps finishing work during the hold. A planted lock read on main fails it, by name.
- VerifyLibraryStore's deadline is a watchdog thread. It found, and the lane fixed, a real deadlock under one cooperative thread.
- VerifyAUGraph's waits have caps.

**One engine double (lane D):**
- `FakeEngine` (DeviceTestEngine, promoted) is the one double. `OnDeckEngineModel` composes it.
- 68 mirror tests are deleted (MockAudioEngine, MockAdvanceController, MockPlaylistController). 48 tests on the real `AudioViewModel` replace them, plus 3 shell-toast clock tests.
- The coverage map is in the [lane D report](../reviews/2026-10-testrig/lane-d-report.md). The mirror had drifted from the app: it de-duplicated the queue, its end-of-queue only flipped flags, and its device-loss test ran no code.

## Evidence
- **Counts:** Swift tests 962 → 963, explained by the RigKit and seam tests and the mirror replacement. The C++ null test is 245: 244 pass and 1 is skipped (the pending test).
- **Mutation proof:** every migrated or rewritten test was seen failing against a planted bug, then passing.
  - Lane B: 18 plants.
  - Lane C: one per hazard.
  - Lane C2: every hazard.
  - Lane D: 47 plants.
- **Stress:** under the CI-like profile.
  - Lane B: 340/340 C++ runs.
  - Lanes C and D: 10/10 per suite.
  - Lane C2: 30/30 verifier runs.
- **The full local gate** (`--tier ci`, pinned tools, Xcode 27.1, macOS 26.6) passed on the combined branch: 30/30 steps, before the review fixes added more.
- **The planted-failure proof on GitHub** is the PR's draft run (below).

## Follow-ups (each in known-issues or the backlog)
- **KI-ENG-05:** the library scan and the metadata pass can still starve the cooperative pool on 3-core Macs.
- **KI-ENG-06:** missing test seams (the device-menu sort; two view countdowns) and process-global test state (`FFmpegOptIn.isOn`).
- **KI-ENG-07:** `research/eq-engine-break-it/build-measure.sh` does not build.
- **KI-ENG-08:** the dead "Already in Queue" toast; the guard for a negative index in `playTrack(at:)`.
- **US-R1F-17:** FFmpeg that works with any installed version (recommended design: run `ffmpeg` / `ffprobe` as separate programs; [research](../reviews/2026-10-testrig/ffmpeg-research.md)).
- **Expected test-count floors** (review M8): set from the first CI run's counts.
- **Per-variant test-data folders,** so plain, ASan and TSan can run in parallel locally (review L15).

## Mini-retro
- **Prove a flake diagnosis by reproducing CI's exact failure before fixing it.** ANALYZER-05 and ANALYZER-04 were both reproduced by injecting the delay.
- **A gate that has never run where it will run isn't proven.** The review found a summary that would have been red on every CI run, and three scripts committed without the executable bit. Run the CI path (the draft PR) before trusting it.
- **Worktrees hide configuration** (SwiftFormat's walk-up, an absolute `core.hooksPath`). Check tools from inside a worktree, not only from the main checkout.
- **A commit message must not claim evidence that doesn't exist yet.** One did, here ("10/10" before it was true); it was reworded when combined.
- **One-thread stress (`LIBDISPATCH_COOPERATIVE_POOL_STRICT=1`) finds blocked-pool bugs nothing else finds:** the analyser decode, and the verifier's deadlock.
