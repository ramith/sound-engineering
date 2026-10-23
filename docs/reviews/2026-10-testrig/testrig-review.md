# Test-rig redesign: architecture review

- **Tree:** read-only worktree `.claude/worktrees/testrig-review2`, detached at 99f046f (origin/main + 34 redesign commits). Lane D is not in the tree and is not reviewed.
- **Method:**
  - Read the gate, the toolchain, both rigs, the product seams and the docs, and compared them with `git show origin/main:scripts/strict-gate.sh` and the old Makefile.
  - Ran read-only probes: `result.py render` and `report.sh` against the last real gate run, a semgrep path-scope probe, action SHA checks against upstream with `git ls-remote`, and the Homebrew ffmpeg formula API.
  - Changed no code and ran no builds or sanitizers. Probe files are in `scratchpad/testrig/review-probe/`.

## Verdict

**The design is right. Approve it after four blocking fixes.**

What is right:
- One registry and one runner, collect-all, parity first, and a watchdog on every step.
- One manifest with checksums.
- GoogleTest with an awake-time watchdog.
- RigKit's state waits.
- The behaviour stall oracle.
- Small product seams that keep the app's behaviour as their default.

The four rules hold in almost every test and verifier I read.

The weak part is the **CI-only path**, which no one has run yet:
- **The `strict-gate` summary is red on every run.** I reproduced it: an all-green run's artifacts give exit 1 and an empty table.
- **The PR `.build` cache can bring old results back.** A job that times out can then show green.
- **One `brew install ffmpeg` can switch off the whole gate,** in every job and in the release.

Five high items are cheap and belong in this sprint:
- the macOS 26 guard, which does not catch the bug it names;
- the pre-commit hook, which runs tools outside the manifest;
- a Swift hang that cannot be named;
- `main` CI runs that can still be cancelled;
- a nightly stress that never tells anyone it failed.

---

## Findings, by severity

### BLOCKING: fix before the redesign PR merges

**B1. The `strict-gate` summary fails on every CI run, including all-green runs.**
- **Where:**
  - `scripts/gate/result.py:85-98`: `render` globs **every** `*.json` under the artifact tree, skipping only `run.json`, and reads `r["status"]` from each.
  - These JSON files are in the run directory and are not step records:
    - `scripts/gate/semgrep.sh:13` writes `$GATE_RUN_DIR/semgrep-scan.json` (static job);
    - `scripts/gate/null-run.sh:17-20` writes `$GATE_RUN_DIR/null/*.json` (cpp, asan, tsan).
  - `scripts/gate/report.sh:47` renders the whole tree, and `:67-69` turns the crash into "FAILED".
- **Evidence:**
  - `python3 scripts/gate/result.py render <last tier-ci run dir>` gives `KeyError: 'status'`, exit 1.
  - I rebuilt the CI artifact layout from gate run 2, which passed 30/30. `report.sh` then exits **1** and prints an empty table plus "strict-gate: FAILED". With the two extra JSON kinds removed, the same tree gives "VERDICT: PASS", exit 0. Files: `review-probe/report-out.txt` and `report-out2.txt`.
- **Why it matters:**
  - Main's CI is the real gate, and this check would be red after every merge.
  - The founder would learn to ignore the one check they are told to read.
  - Nothing local runs `report.sh`, so no gate run could have caught this. It is the same kind of bug as the `report.sh` exec-bit bug fixed in cf8ebb9.
- **Fix:**
  - `render` reads only `**/results/*.json`, the glob `report.sh`'s own missing-check already uses at line 40.
  - Add a registry row `report-selftest` (static job, push and check tiers). It runs `report.sh` on a small checked-in fixture tree:
    - one passing job, carrying a GoogleTest JSON and a semgrep JSON;
    - one job with no `run.json`;
    - one failing step.
  - Assert exit codes 0, 1 and 1. The summary path is then tested on every local run, not first on GitHub.

**B2. A stale PR `.build` cache can make a timed-out or cancelled job look green, and doubles the table from the second PR run on.**
- **Where:**
  - `.github/workflows/strict-ci.yml:60-67` and `:94-101` cache `path: .build` on PRs.
  - `scripts/gate/run.sh:128` puts every run directory under `.build/gate/`.
  - `strict-ci.yml:70-76` (and the other jobs) upload all of `.build/gate/`.
  - `report.sh:36-43` accepts **any** `run.json` and any record under a job's artifact.
- **The chain:**
  1. Run N of a PR passes the swift job. The cache is saved with `.build/gate/job-swift-<N>/` inside it, complete and all-pass.
  2. Run N+1 restores it. If the swift job then hits its timeout, is cancelled, or `run.sh` dies before its verdict, the `if: always()` upload still sends the old run directory.
  3. `report.sh` finds a `run.json` and a record for every step, all passing, and reports green.
- **Also:**
  - Even on normal runs, every old run directory is uploaded again, so rows multiply.
  - The swift and cpp jobs use the **same** key, `build-<hash>-${{ github.run_id }}` (`:65`, `:99`), so one job can restore the other's `.build`, gate directory included.
- **Main is safe:** its `.build` is never restored.
- **Fix:**
  - Clear the gate output before each run, or write it outside `.build`: `GATE_RUN_DIR="$RUNNER_TEMP/gate/<job>"` in CI, or a gitignored `gate-out/`.
  - Exclude it from the cache (`!.build/gate`).
  - Give the two jobs distinct keys (`build-swift-…`, `build-cpp-…`).
  - In `report.sh`, require **exactly one** `run.json` per job, stamped with `GITHUB_RUN_ID`, `GITHUB_RUN_ATTEMPT` and `GITHUB_SHA`, and ignore records from any other run.

**B3. One Homebrew FFmpeg release can switch off the whole gate, and block releases.**
- **Where:**
  - `.github/actions/setup-gate/action.yml:35-37` runs `brew install ffmpeg` with no pin. Homebrew auto-updates first, so it installs whatever is current that day.
  - `scripts/toolchain/check.sh:138-142`: FFmpeg ≠ 9.0.2 is a **FAIL** in CI.
  - `scripts/gate/run.sh:288-289` and `:321-324`: a parity failure **skips every other step**.
  - `release.yml:41-42` runs the same parity check with `CI=true`.
  - `scripts/gate/canary.sh` does not watch FFmpeg at all.
- **Today it passes:** formulae.brew.sh shows ffmpeg **9.0.2 rev 1**, with an `arm64_golden_gate` (macOS 27) bottle.
- **The day Homebrew ships 9.0.3 or 9.1:**
  - all five jobs report only "toolchain-parity failed, everything skipped";
  - a tag cannot be released;
  - the only "fix" is a bump commit to whatever Homebrew has. A Homebrew-installed FFmpeg cannot be pinned to an older version.
- **Why it matters:** this is PR #91's tool drift again, with a worse failure (no signal at all instead of one red step). The FFmpeg version also decides the runtime result of the 20 `needsFfmpeg` C++ tests, not only the headers.
- **Fix:**
  - **This sprint (minimum):**
    - Move FFmpeg out of the parity table into its own blocking registry row, `ffmpeg-version`. Its drift turns one row red while every other check still runs and reports.
    - Add the FFmpeg formula version to the canary report, so the bump is seen a week early.
    - Set `HOMEBREW_NO_AUTO_UPDATE=1` so the job does not also update Homebrew mid-run.
  - **Properly (founder question 1):**
    - Build FFmpeg 9.0.2 from its checksummed source tarball into the toolchain cache (decoders, demuxers and the libs we use, `--disable-programs`), as `install.sh` already does for cppcheck.
    - Point the analysis include path and the null test's FFmpeg search path at it.

**B4. The new CI has never run on GitHub.** This is a verification gap, not a code defect.
- Unproven on the `xcode-27` image:
  - the setup-gate path (`xcode-select` to the RC alias, brew on macOS 27);
  - the semgrep venv on that image's Python (M2);
  - cache size and disk (M1);
  - step times on 3 vCPUs (M3);
  - the artifact layout and `report.sh` (B1 shows this matters).
- The DoD items "planted 3 failures show in one CI run" and "parity green in CI" are still open.
- `workflow_dispatch` only works once the workflow is on the default branch (memory line 81).
- **Fix:** before merging, run the redesign PR's CI, plus one draft PR carrying the three planted failures (lint, Swift test, C++ test) and a planted hang. Read the `strict-gate` exit code and table on both.

### HIGH: cheap, do in this sprint

**H1. The macOS 26 guard does not catch the bug it is documented to catch.**
- **Where:** `scripts/gate/deployment-target.sh:6-9` and `DEVELOPMENT.md:19` say a macOS 27-only symbol "shows up here as minos 27.x". That is not how Mach-O works.
  - `minos` (LC_BUILD_VERSION) comes from the deployment target.
  - Referencing a newer symbol does not change it. The `_LIBCPP_DISABLE_AVAILABILITY` incident produced a `minos 26.0` binary that failed to load on 26.
  - The script also reads the target from `Package.swift` (`:16`), so moving `Package.swift` to `.v27` passes too.
  - It only catches a stray `-mmacosx-version-min` / `-target` override.
- **Why it matters:**
  - CI runs macOS 27, users run 26, and the founder merges on CI's signal.
  - Today the real guards are compile-time: Swift availability checks, ObjC++ `-Wunguarded-availability-new` under the debug `-Werror`, and libc++ availability markup.
  - Plus local runs on the 26.6 Mac. None of these is in CI as such.
- **Fix:**
  - (a) A posture or semgrep rule banning `_LIBCPP_DISABLE_AVAILABILITY` and `-Wno-unguarded-availability*` anywhere in `Package.swift`, `scripts/` and `Makefile`. Cheap, and catches the actual incident.
  - (b) A small advisory job on `runs-on: macos-26` that downloads two binaries the xcode-27 job built and runs them on macOS 26:
    - the debug `AdaptiveSound -ASMainThreadStall stop|start` (it loads the app's full link graph and runs AVFAudio on 26);
    - `Tests/DSPKernelNullTest --tier correctness`.
    - It needs no Xcode 27 on the 26 runner. Run it nightly and in `release.yml` before publishing.
  - (c) Fix the comment and DEVELOPMENT.md: the script guards the deployment target, not symbols.

**H2. The pre-commit hook (T0) runs tools outside the manifest, and auto-formats with them.**
- **Where:**
  - `.githooks/pre-commit:35-43` resolves clang-tidy through `cxx_clang_tidy_path` (`scripts/lib/cxx-analysis-flags.sh:112-123`): Homebrew `llvm@23`, then `opt/llvm`, then PATH, with a **major-only** pin.
  - `:66-80` runs `clang-format -i` and `swiftformat` from PATH, then **re-stages** the files.
  - The hook never puts the toolchain bin first on PATH.
- **On this Mac:** clang-format **23.1.0** and clang-tidy **23.1.2** (Homebrew), against the gate's **23.1.3**. 23.1.2 → 23.1.3 was one of PR #91's red runs.
- **Why it matters:** every agent commit, in every worktree, is formatted and analysed by the old tools, and the gate then lints with the pinned ones. That is founder decision 2's gap in the daily loop.
- **Fix:**
  - The hook starts with `PATH="$(scripts/toolchain/install.sh --print-bin):$PATH"` and fails with "run `make toolchain`" if that directory is incomplete.
  - `cxx_clang_tidy_path` prefers that directory.
  - Retire `CXX_CLANG_TIDY_MAJOR_PIN` as a second pin.

**H3. A hung Swift test cannot be named, and the heaviest suites have no `.timeLimit`.**
- **Where:**
  - `scripts/gate/swift-test.sh:37-39` captures all of `swift test` into `out=$(…)` and prints it only after it returns. When the step watchdog kills a hang (35 min, rig 20 min), `logs/swift-test.log` is **empty**: no "Test X started" line shows which test hung.
  - `docs/development/testing.md:56` says "Every suite with waits has a `.timeLimit`". Ten rig files have none: `OnDeckContractTests`, `OnDeckExplorerTests`, `TransportContractTests`, `TransportExplorerTests`, `QueueEditContractTests`, and `Enhanced{CommandOrder,EndOfQueue,Resampler,Seam,Seek}Tests`.
  - `until` caps cover RigKit waits, but an await on a continuation or a stuck `blocking {}` falls through to the step watchdog.
- **Why it matters:** rule 4, "a hang is killed and named". Swift is the side that hangs.
- **Fix:**
  - Stream `swift test … 2>&1 | tee "$tmp"` (read the exit code from `PIPESTATUS[0]`) and parse the file. Do the same for swiftformat and swiftlint.
  - Add `.timeLimit(.minutes(N))` to those suites.
  - Add a semgrep rule: an `@Suite` in `Tests/` that calls `until`, `waitUntil`, `settled` or `quiesce` must carry `.timeLimit`.

**H4. "A run on main is never cancelled" is not true, and main runs queue behind each other.**
- **Where:** `strict-ci.yml:17-19` uses `group: strict-ci-${{ github.ref }}`, and `DEVELOPMENT.md:87` claims main runs are never cancelled.
- **How GitHub behaves:** a concurrency group holds one running and one *pending* run. A third push to main **cancels the pending one**, whatever `cancel-in-progress` says.
- **Effects:**
  - Two quick merges during a 30–60 min main run leave the middle merge with no gate run at all.
  - Even with two merges, the second waits a full run for its verdict.
- **Fix:** key the group per commit outside PRs: `group: strict-ci-${{ github.event_name == 'pull_request' && github.ref || github.sha }}`.

**H5. The nightly stress can never warn anyone.**
- **Where:** `nightly-stress.yml:35` sets job-level `continue-on-error: true`, so the workflow run ends "success" when stress fails. GitHub sends no failure mail, and unlike the canary no issue is opened.
- **Why it matters:** founder decision 7 keeps the nightly stress as the early warning for flakes, "fix the same day".
- **Fix:** drop `continue-on-error`. It is not a required check, so it is already advisory. Add the canary's "open or update ONE issue" step on `failure()`.

### MEDIUM

**M1. The toolchain cache is ~9.5 GB per manifest version, is never pruned, and is not re-verified on restore.**
- **Size:**
  - `install.sh:113-122` keeps the whole LLVM tarball: `llvm/` is **7.6 GB**, plus the 1.5 GB archive.
  - The hash covers the whole manifest (`:37`), so a GoogleTest bump or a comment edit re-extracts LLVM.
  - This Mac now holds three versions (05e6…, 9878…, e42c…): about **27 GB**.
  - In CI that one cache entry is restored by all five jobs. Free disk on the xcode-27 runners is unmeasured.
- **Verification:**
  - `action.yml:21-22` says "the install script verifies every checksum on restore".
  - But `install.sh:84-88` exits as soon as `.complete` exists. Nothing installed is re-checked, only version strings by parity.
  - The same fast path skips `$GITHUB_PATH` (`:173-176` runs only on a fresh install).
- **Fix:**
  - Keep only `bin/clang-tidy`, `bin/clang-format` and `lib/clang/<v>/include` (about 0.3 GB).
  - Store one directory per tool, keyed by that tool's checksum.
  - Write a `sha256` list of `bin/*` at install time and check it on the fast path, or correct the comment.
  - Prune hash directories the manifest no longer names.

**M2. The semgrep venv uses whatever `python3` is on PATH.**
- **Where:** `install.sh:144` runs `python3 -m venv`. The lock was compiled with `--python-version 3.12` (`semgrep-requirements.txt:2`).
- **The mismatch:** the founder's Mac has 3.12.2, but the xcode-27 image's default `python3` is **3.15.0** (its readme).
- **The risk:** wheels for the C-extension packages (pydantic-core, rpds-py, cryptography, cffi, ruamel-yaml-clib) may be missing for cp315. pip would then build from sdists, or fail the setup step in every job.
- **Fix:**
  - Add `PYTHON_VERSION=3.12` to the manifest and a parity row for it.
  - In CI, use the image's toolcache 3.12 (`/Users/runner/hostedtoolcache/Python/3.12.*`, or `actions/setup-python` SHA-pinned). Locally, fail clearly when 3.12 is absent.

**M3. The C++ ceilings are not "≥ 10× the slowest test", and the hang cap ignores the sanitizers.**
- **Where:**
  - `NullTestRunner.h:160` claims ≥ 10×.
  - The measured local margins in gate run 2 (`.build/gate/tier-ci-20261022T072543Z`):

    | Build | Slowest test | Time | Ceiling | Margin |
    |---|---|---|---|---|
    | TSan | `EQ_LoudnessNeutral_OnOff` | 571 s | 2400 s | **4.2×** |
    | ASan | same test | 141 s | 900 s | 6.4× |
    | debug | same test | 38 s | 300 s | 7.9× |

  - On CI's 3-vCPU M1, with four null-test processes, the TSan margin is likely about 2×.
  - `TestSupport.h:644` `kHangCap{60}` is not scaled, although the watchdog scales ×3 and ×8 (`NullTestRunner.h:165-171`). A state wait that takes more than 60 s under TSan on CI would fail as "never reached".
- **Fix:**
  - Scale `kHangCap` by `kCeilingScale`.
  - Read the first CI run's per-test JSON and set the ceilings from it: per tier×variant, or a per-test override for the 3–4 sweep tests.
  - Correct the comment.

**M4. "Named hang" is reported the wrong way round.**
- **Where:**
  - Sharded runs exit **1** on a hang (`build-null-test.sh:316-329`). The gate's null-debug, null-asan and null-tsan steps are all sharded, so `run.sh:237-240` (rc 134 means named hang) never fires for them.
  - In unsharded runs, any SIGABRT, including an ASan report under `abort_on_error=1` (`build-null-test.sh:275`), is labelled "named hang: a test ran past its ceiling".
  - `testing.md:42` documents the 134 behaviour as the gate's.
- **Fix:**
  - Classify a hang by a `[HANG]` line in the log, not by the exit code.
  - Have the shard runner exit 134 if any process did.

**M5. Nothing checks that the registry and CI agree.**
- **Where:**
  - `report.sh:19` hard-codes `static swift cpp asan tsan`, and `:32` silently ignores rows of any other job. A typo in a row's job column means that step never runs in CI and nobody notices.
  - The tiers column must contain `ci` for `make strict-gate` to run the step; nothing enforces it.
  - `RUNNER_LABEL` (`toolchain.env:23`) is read by nothing. Eight `runs-on: xcode-27` lines are hard-coded.
- **Fix:** a `registry-lint` step (static job, push tier) that fails when:
  - a row's job is not a job in `strict-ci.yml`;
  - a row's tiers lack `ci`;
  - the timeout format is bad;
  - any macOS `runs-on` ≠ `RUNNER_LABEL`.

**M6. `report.sh` turns green if its own missing-job check crashes.**
- **Where:** `report.sh:24-45` puts the Python heredoc in `missing="$(…)"` and never checks its exit status. A traceback, for example `cols[1]` on a malformed registry line, gives empty output, so "no missing jobs".
- **Fix:** capture the status, and treat non-zero as a red "report check crashed".

**M7. Each null-test step deletes the previous one's GoogleTest JSON.**
- **Where:** `null-run.sh:17-18` runs `rm -rf "$GATE_RUN_DIR/null"`. In the cpp job, null-perf-O2 deletes null-debug's per-test JSON before upload. Confirmed locally: only TSan's JSON survived gate run 2.
- **Fix:** write to `$GATE_RUN_DIR/null/<step-id>/`.

**M8. Nothing stops the test counts from dropping.**
- **Where:** every coverage rule is "≥ 1". A deleted test file, or a suite renamed out of the rig filter, lowers 980 / 245 / 162 with no signal. The DoD rule "counts don't drop" is checked by hand.
- **Why now:** Lane D is about to retire about 61 tests on purpose.
- **Fix:** a checked-in `scripts/gate/expected-counts.tsv` (step, minimum) that the runner checks against `GATE_COVERED`. It is changed only on purpose, in the same commit as the coverage map.

### LOW / nice-to-have

**Ceilings and caps**
- **L1.** The job timeouts are below the sum of their step caps, so the job timeout, not the step watchdog, can fire first:
  - swift: 98 min of caps against a 90 min job (`strict-ci.yml:47`);
  - tsan: 183 min of caps plus setup against 200 min.
  - Fix: make each job's timeout at least its step caps plus about 20 min of setup.
- **L2.** `release.yml` has no `timeout-minutes` (rule 4).
- **L3.** The null-test lock wait (`run.sh:175-188`) has no cap and sits outside any watchdog.

**The Swift rig**
- **L4.** `OnDeckRig.runViewModelOut` (`OnDeckRig.swift:173-186`) judges quiescence by "3 stable yield rounds". That is a heuristic counted in yields. It is fine today (mutation-checked, 10/10 under stress); watch it in the nightly.
- **L5.** `Hold.wait` caps on a wall-clock `Date` (`Hold.swift:37-38`), not `SuspendingClock`. It fails loudly, so it is acceptable.
- **L6.** Two problems with the shared log ring:
  - UXLOG-01 swaps the process-wide `[UX]` sink while other tests run (`UXLogSinkTests.swift:18-25`; rule 3), so their tails go missing in that window.
  - `LogTail.append` costs O(capacity) per line once full (`LogTail.swift:20-25`). A head index would fix it.
- **L7.** The product's `RunLoopTicker` (a `.common`-mode timer) no longer has a test after LiveReadouts moved to `ManualTicker`. One `untilOnMainRunLoop` test would cover it.

**Tooling and supply chain**
- **L8.** `actionlint -shellcheck=` (`actionlint.sh:18`): about 2,000 lines of gate bash have no shellcheck. Pin shellcheck (one checksummed binary) and lint `scripts/**/*.sh` and the workflow `run:` blocks.
- **L9.** The canary runs the latest, unverified tool binaries with `GH_TOKEN` in their environment (`canary.yml:30-32`). Scope the token to the `gh api` calls.
- **L10.** `check.sh:47-53` compares versions by substring (`2.21.2` would match `2.21.20`). Compare the extracted version exactly.
- **L11.** `run.sh:133-134`: if `install.sh --print-bin` printed nothing, `PATH=":$PATH"` would put the current directory on PATH. Guard against an empty value.
- **L12.** Add `overwrite: true` to the uploads, so "re-run failed jobs" replaces its artifact.

**Build and visibility**
- **L13.** `RigKit` is a non-test `.target` (`Package.swift:213-216`), so `make release` / `make dist` (`swift build -c release`, `Makefile:46`) compile it, with `import Testing`. No gate step builds `-c release`. Add a `swift build -c release` smoke step, or build only `--product AdaptiveSound` in `make release`.
- **L14.** The architect promised a mid-run view ("at any moment"). Today the table appears only at the end. Emit `::error title=<step>::<reason>` as each step fails, so a mid-CI merge sees failures live.

**Local run time**
- **L15.** A local `make strict-gate` takes about 32 min end to end, null-tsan 16.5 of them. Two changes make it faster:
  - `ADAPTIVESOUND_TEST_DATA_DIR` is a compile-time define (`build-null-test.sh:230`). Making it per variant (`test-data/<variant>`) lets plain, ASan and TSan run at once in one checkout.
  - Then let the runner run the five jobs in parallel locally.

**Stale docs**
- **L16.**
  - `docs/architecture/architecture.md:183` still describes the 25 ms stopwatch oracle.
  - `validation-strategy.md:77` says "cppcheck (if installed)".
  - `.periphery.yml:2` names a `periphery.yml` workflow that does not exist.
  - `pre-commit:31` cites strict-gate.sh's pin assert.
  - `testing.md:127` says "C++: shards"; `stress.sh` runs unsharded.

---

## Founder decisions and the four rules, as built

| Item | Status | Evidence / gap |
|---|---|---|
| D1 run everything; 5 jobs plus one summary | Built; **broken in CI** | `strict-ci.yml`. The summary has B1 and B2. |
| D2 one manifest, one install, parity first | Mostly | Gaps: FFmpeg (B3), the pre-commit hook (H2), the Python interpreter (M2), cache verification (M1). |
| D3 GoogleTest 1.18 plus watchdog | Delivered | `NullTestRunner.h:191-281` (awake clock, listener `Release`, verdict required); submodule commit asserted. |
| D4 the whole redesign first | On track | Lane D still to come. |
| D5 swift-clocks 1.1.1, test-only | Delivered | `Package.swift:21` exact; only `AdaptiveSoundTests` links `Clocks`; the product defaults to `ContinuousClock()`. |
| D6 stall judged by behaviour | Delivered | `MainThreadStallHold.swift`; the hold is released only by the test; a positive witness proves the hold; mutation-proven. |
| D7 no quarantine, no retries; semgrep rule; nightly stress | Partly | No new skips or retries anywhere. The semgrep rule is real: I probed its path scope, 158 test files in and 0 RigKit files. The nightly stress is silent (H5). |
| R1 waits are for states; caps fail loudly | Yes | `until`, `untilBlocking`, `Hold`, C++ `waitUntil`/`pumpUntil`. My grep found no raw waits that slip past the rule (`asyncAfter`, `sleep(for:)`, `wait(timeout:)`, `fulfillment`). Small gaps: L4, L5, the unscaled C++ cap (M3). |
| R2 measure the component | Yes | Thread CPU and min-of-N in C++; verifier CPU tripwires; SRCQualityMeasure on thread CPU (worst case 15× real time against a 2× bar). No wall-clock thresholds remain in Swift tests. |
| R3 each test owns its world | Mostly | `IsolatedDefaults`, off-pool rigs, rig suites `--no-parallel`. Left: serial C++ fixtures (accepted), `FFmpegOptIn.isOn`, the UXLOG-01 sink swap. |
| R4 every run has a ceiling and reports everything | Partly | Step watchdog, job timeouts, the C++ watchdog. Gaps: H3 (Swift hang unnamed, no `timeLimit`), B1, B2, M4, M6, M7, L1–L3. |

**Nothing from the old gate is lost.** Every `strict-gate.sh` step and every `make gate` / `sanitize` / `tsan` / `sanitize-library-store` / `leak-check` / `main-thread-stall` target maps to a registry row with the same command or a stricter one. Checked against `git show origin/main:scripts/strict-gate.sh` and the old Makefile. `strict-gate.sh` is now a three-line wrapper.

**Main's cache:** a stale cache cannot fake a green on main. `.build` is PR-only, and the SwiftPM checkouts are keyed by `Package.resolved`. It can on a PR (B2).

**Permissions and supply chain:**
- Permissions are minimal: `contents: read`; the canary has `issues: write`; the release keeps what it needs.
- All five actions are SHA-pinned. I verified each SHA against its upstream tag (checkout v7.0.1, cache v6.1.0, upload-artifact v7.0.2, download-artifact v8.0.2, attest-build-provenance v4.1.0).
- No `|| true` remains on an install.
- Tool archives are checksummed; semgrep is hash-locked.
- The exceptions are `brew install ffmpeg` (B3) and the interpreter (M2).

---

## What is solid: do not touch

**The gate**
- **`scripts/gate/run.sh`:**
  - collect-all;
  - each step in its own process group, with a TERM-then-KILL watchdog;
  - parity first;
  - only real dependencies skip, and a skip is never green;
  - the zero-coverage rule;
  - the verdict is the AND of the blocking steps;
  - one record per step.
- **The step scripts:**
  - lint tracked files only, with counts against `git ls-files` (this is the worktree fix);
  - semgrep's scanned-file count;
  - `swift-test.sh` sums the per-target lines and treats load failures as fatal;
  - `null-run.sh` fails on no tests, on missing JSON, or on any failed test.
- **The registry format:** one row per check, and the README mapping.

**Toolchain**
- `install.sh`: download, verify, then use; archives stored by checksum; `semgrep-core` and `pysemgrep` linked so Homebrew's cannot take over.
- `check.sh`: an exact Xcode build, a GoogleTest commit row, a clang-tidy major cross-check, and the runner image date.

**The C++ rig**
- tests registered through `RegisterTest` with names unchanged;
- a test that returns without a verdict fails;
- `--gtest_fail_if_no_test_selected` injected first;
- the watchdog on `CLOCK_UPTIME_RAW`, with progress notes naming the waited-for state;
- the `Rendezvous`, the thread-CPU meter and `Budget`/`limit()`.

**The Swift rig**
- `until` runs on `SuspendingClock`, and its condition is `nonisolated(nonsending)`, so it runs on the caller's actor;
- `withHold`'s three failure modes;
- `blocking` and `OffPoolExecutor`;
- `IsolatedDefaults`;
- each primitive has a proof that it fails.

**Product seams**
- They are minimal and keep the app's behaviour as their default, and none touches the real-time path:
  - `RunLoopTicker` is the old timer, unchanged.
  - `WorkTracker` *is* the product's spawn path, so it is not a parallel world.
  - `StreamObserver` is nil in the app. All six schedule sites are wrapped; I checked them.
  - `UXLog.sink` is still NSLog.
  - `SettingsStore.pendingWrite` behaves the same; I checked the interleavings.
  - `LoudnessModule::meterCaughtUp` is written only by the worker, around its idle wait, and read on the `process()` thread. Its ordering argument holds.
  - The `Realizer` counters run on control threads only.

**The analyzer's decode on its own queue.** This is a real product fix, bounded by the coordinator's two jobs, with cancellation through an atomic flag.

**The verifiers (C2):** a watchdog-thread deadline, named semaphore caps, and the strict-pool deadlock fix.

---

## Questions for the founder (recommendation first)

1. **FFmpeg in CI.**
   - **Recommend:** do the cheap fix in this PR. A new FFmpeg version on Homebrew should turn one row red, not switch off the whole gate. The weekly canary should warn a week ahead.
   - Next sprint, pin FFmpeg properly by building 9.0.2 from its checksummed source, as we do for cppcheck.
   - The alternative is to do the proper pin now (about half a day).
2. **Checking the app on macOS 26.**
   - **Recommend:** add a small nightly job, plus a pre-release step, that takes the stall check and the C++ test built on CI's macOS 27 and runs them on GitHub's macOS 26 machine. Also ban the build flag that caused the macOS 27-only symbol.
   - It costs about 10 runner-minutes a night. The current check would not have caught that bug.
3. **Xcode updates on your Mac.**
   - **Recommend:** turn off automatic App Store updates for Xcode, or keep 27.1 side by side as `Xcode_27.1.app`.
   - The gate and the pre-push hook refuse any other Xcode build. An automatic update would block every local gate run and every push until we commit a toolchain bump that CI also has.
4. **The nightly stress.**
   - **Recommend:** when it fails, it opens or updates one GitHub issue, as the canary does.
   - Today it finishes "green with a red job", so you would never hear about a flake.
5. **Disk on your Mac.**
   - The test toolchain takes about 9.5 GB per version, 27 GB today across three versions.
   - **Recommend:** keep only the two LLVM tools we use (about 0.3 GB) and delete old versions automatically.
   - May the two old cache folders (`05e6…`, `e42c…` under `~/.cache/adaptivesound-toolchain/`) be deleted now?
6. **One product change rides in this test-rig PR.** The loudness analyser now decodes on its own queue; the new one-thread stress test found it starving the app's task pool.
   - **Recommend:** keep it in this PR. It does not change the sound.
7. **TSan runs every C++ test** (your "run everything"). It is the slowest CI job.
   - **Recommend:** keep it. Raise the TSan time ceilings once the first CI run shows real times (M3), so a slow machine cannot read as a hang.
