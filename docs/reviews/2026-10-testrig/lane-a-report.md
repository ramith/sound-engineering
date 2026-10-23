# Lane A report: the gate and the toolchain

Branch `testrig/gate-toolchain` (worktree `.claude/worktrees/testrig-a`), rebased onto `testrig/integration` @ 96d057f (Xcode 27.1). Not pushed.

**Headline:** the registry, runner, toolchain manifest, parity check, CI workflows and planted-failure proof are done and proven on this Mac. Three things stop a clean end-to-end `--tier ci` from being a valid verdict on this branch, and the coordinator's combine resolves them: (1) the GoogleTest rows from `testrig/cpp-rig` are not here, so parity fails by design; (2) the new `build-null-test.sh` flags (`--shards`, `--tier`, `--opt-run`, `--gtest_*`) are not here, so the null-test steps cannot run; (3) my one full `--tier ci` run was corrupted by my own edit to `run.sh` mid-run (details below), so its exit code 2 is an artifact, not a verdict.

## Commits (on top of 96d057f)

| commit | what |
|---|---|
| 3b331f8 | feat(gate): one step registry, one runner, one toolchain manifest (registry, runner, parity, install, Semgrep fixtures, workflows, docs) |
| e7408fc | wip(gate): composite toolchain action, gate workflows, canary, nightly stress, pre-push tier, DEVELOPMENT.md (rebased from the 26.6 WIP) |
| 0ff9d6e | feat(gate): Xcode 27.1 pins, deployment-target guard, C++ null-test rows, named hangs, lock |

Uncommitted: none.

## What changed, by deliverable

- **Manifest (`toolchain/toolchain.env`):** Xcode 27.1 (27A9275), Swift 6.4, runner `xcode-27`, `XCODE_APP_PATH=/Applications/Xcode_27.1.app`, `RUNNER_IMAGE_MIN=20261012`, `MACOS_CI_IMAGE=27.0.1` (info only). Every verdict tool exact-pinned with a checksum (GitHub digests). Semgrep 1.180.0 hash-locked (`scripts/toolchain/semgrep-requirements.txt`, 915 hashes).
- **Parity (`scripts/toolchain/check.sh`):** Xcode build and Swift exact everywhere (a Mac on another Xcode fails with the fix). macOS is an INFO row that never fails. FFmpeg headers: WARN locally, FAIL in CI. `semgrep-core` is checked too: the CLI runs the core from `PATH`. GoogleTest row asserts `GOOGLETEST_COMMIT` against the submodule. Runner image date checked in CI.
- **Install (`scripts/toolchain/install.sh`):** verifies every sha256; archives stored once per checksum under `~/.cache/adaptivesound-toolchain/archives/` so a manifest bump does not re-download LLVM (1.5 GB). Links the pinned `pysemgrep` and `semgrep-core` into the bin dir (see the Semgrep finding below).
- **Runner (`scripts/gate/run.sh`, `steps.tsv`, `result.py`, `report.sh`):** collect-all; per-step process group and watchdog; `results/<id>.json`; zero-coverage rule; parity first; exit 134 with the null-test `[HANG]` line reported as a **named hang**; `GATE_REGISTRY` override (proof use only); lock so two null-test steps cannot run in one checkout.
- **Step scripts:** swiftformat/swiftlint (tracked files, count guard), clang-format, cppcheck, clang-tidy, semgrep (JSON, scanned-count guard), semgrep-rule-tests (20 rules, fixtures), periphery (2.21.2, index-store recipe), actionlint, swift-test (sums per-target runs; fails on `Failed to open test bundle` / `Fatal error` / `Symbol not found`; 0 tests fails), deployment-target (minos ≤ 26 for every built executable and test bundle), posture, null-coverage, main-thread-stall, stress, null-run (counts GoogleTest JSON, fails on 0 or on any failure).
- **Workflows:** `strict-ci.yml` (jobs static / swift / cpp / asan / tsan on `xcode-27`, `strict-gate` summary on ubuntu, `if: always()`, job timeouts sized from step sums: static 97 of 100 min, swift 75 of 90, cpp 162 of 200, asan 140 of 160, tsan 180 of 200; cancel only on PRs). `release.yml` (same composite; attest v4.1.0; `|| true` removed). `canary.yml` (weekly, advisory, one issue). `nightly-stress.yml` (advisory). Composite `.github/actions/setup-gate` selects Xcode by path. All actions pinned by full SHA with version comments; `actionlint` passes.
- **Dependabot:** `swift` ecosystem added, stale comment removed.
- **Semgrep (`.semgrep.yml`):** comment-line guard on every regex rule (20 rules); a fixture per rule; `semgrep-rule-tests.sh` proves each flags its `ruleid` line and not its comment. Fixtures excluded from Semgrep, SwiftFormat, SwiftLint and the pre-commit hook.
- **Hooks:** `.githooks/pre-push` (the `push` tier). `.githooks/pre-commit` excludes fixtures.
- **Docs:** `docs/development/DEVELOPMENT.md` (tool setup, tiers, gate reading, `make stress`); `docs/development/testing.md` (the four rules, the gate, the C++ rig, Swift rule, stress; Swift rig section deferred to Lane C); `scripts/gate/README.md` (the step mapping).
- **Makefile:** `check`, `combine-check`, `stress`, `toolchain`; gate targets route through the runner.

## Step mapping: today's `strict-gate.sh` and `make gate` → registry

Nothing dropped. Full table with tiers and jobs: `scripts/gate/README.md`.

| Old step | Registry id |
|---|---|
| Tool check and pins | toolchain-parity |
| SwiftFormat lint | swiftformat |
| SwiftLint strict | swiftlint |
| clang-format dry run | clang-format |
| Semgrep | semgrep (+ semgrep-rule-tests, new) |
| Suppression policy | suppressions |
| Migrator guard | posture-migrator |
| Playlist add/drop guard | posture-playlist |
| Kit purity / Dynamic Type guards | posture-layers |
| cppcheck (optional, now pinned) | cppcheck |
| clang-tidy | clang-tidy |
| Periphery | periphery |
| Swift build (debug) | swift-build (+ deployment-target, new) |
| swift test | swift-test |
| `make gate`: null test | null-debug (+ null-perf-O2, new) |
| `make gate`: VerifyAUGraph | verify-au-graph |
| `make gate`: SRCQualityMeasure | src-quality |
| `make gate`: VerifyLibraryStore | verify-library-store |
| main-thread-stall self-test | main-thread-stall |
| null-test source drift guard | null-coverage |
| `-O2 -Werror` compile | null-release-strict |
| ASan/UBSan null (`make sanitize`) | null-asan |
| TSan null (`make tsan`) | null-tsan |
| store ASan | store-asan |
| leaks | leak-check |
| (new) actionlint | actionlint |

## Evidence (commands and real exit codes)

| Check | Command | Exit | Result |
|---|---|---|---|
| Parity on this Mac (before GoogleTest row) | `scripts/toolchain/check.sh` | 0 | OK for all verdict tools; Xcode 27.1 (27A9275) exact; Swift 6.4 exact; macOS 26.6 INFO; FFmpeg 9.0.1 vs 9.0.2 WARN. |
| Parity on this branch (after GoogleTest row) | same | 1 | `googletest` FAIL: "not in toolchain/toolchain.env". Expected until Lane B's rows merge. |
| GoogleTest row proof | `TOOLCHAIN_ENV=<manifest + Lane B's two rows>` `check.sh` | 1 | `googletest` FAIL, "submodule missing". Row fails for the right reason. |
| Planted run (lint + failing test + hang, one run) | `GATE_REGISTRY=<planted> scripts/gate/run.sh --tier ci` | 1 | swiftlint FAIL (force_try, file:line named); swift-test FAIL (`plantedFailure` expectation, head shown); hang TIMEOUT "timed out after 20s", named. Three blocking steps reported in one run. Planted lines reverted with `git checkout`. |
| Misspelt filter | `TEST=NoSuchTestNameXyz scripts/gate/swift-test.sh` | 1 | Fails: no Test run line, 0 tests. |
| Swift full | `scripts/gate/swift-test.sh` | 0 | 962 tests across all targets (matches the coordinator's count). |
| Deployment target | `scripts/gate/deployment-target.sh` | 0 | 13 products, all minos ≤ 26. |
| Periphery (index-store recipe) | `scripts/gate/periphery.sh` | 0 | "No unused code detected" (took 165 s in the full run). |
| Semgrep rules | `scripts/gate/semgrep-rule-tests.sh` | 0 | 20/20 rules. |
| Semgrep scan | `scripts/gate/semgrep.sh` | 0 | 774 files, 0 findings (after fixtures excluded). |
| actionlint | `actionlint -shellcheck= .github/workflows/*.yml` | 0 | Clean. |
| Null-run wrapper, stub | `null-run.sh` with pass / zero / failed / hang stub | 0 / 1 / 1 / 134 | pass: "3 tests", `GATE_COVERED 3`. zero: fails. failed: names `S.T`. hang: `NAMED HANG`. |
| Null-test lock | two runners at once, `null-x` steps | 0, 0 | Second runner printed "waiting", then ran; lock released. |
| `make stress` (Swift), hogs | `TEST=prefetchPromoted N=3 scripts/gate/stress.sh` | 1 | Hogs: 0 before, 11 during, 0 after exit. 0/3 passed (below). |
| `make stress` (Swift), 2 iterations, wrong filter | `TEST=Loudness_WorkersSleepWhileIdle` | 1 | That name is a C++ test, so 0 Swift tests ran and the guard failed each iteration. Correct behaviour. |
| Full CI tier (first run, old registry) | `scripts/gate/run.sh --tier ci` | 2 (artifact) | All 28 steps printed; step verdicts: every one PASS except semgrep, which was FAIL (fixture scan; fixed since, now 0). Final verdict never printed: see below. |
| Step times in that run | | | null-debug 507 s, null-asan 1658 s (27.6 min), null-tsan 3194 s (53 min, under the old 60 min cap), store-asan 48 s, periphery 165 s, clang-tidy 86 s, swift-test 50 s. |

### The corrupted full run (exit 2)

`run.sh` was edited (the null-test lock) while the full `--tier ci` run was executing it. Bash reads a script as it runs, so the edit caused `syntax error near unexpected token '('` at the skip-reporting line. The run wrote its step rows, then could not reach the verdict block. The `exit 2` is that syntax error, not a gate verdict. Lesson: never edit a runner script during a run that uses it. I will not claim that run as a passing gate.

## Finding for Lane C: ANALYZER-05 fails 3 of 3 under the CI-like profile

`make stress` with the strict pool (`LIBDISPATCH_COOPERATIVE_POOL_STRICT=1`) and 11 hogs runs `prefetchPromoted` (ANALYZER-05, `Tests/TrackLoudnessKitTests/TrackLoudnessAnalyzerTests.swift`). All 3 iterations fail after 300 s: the state wait at line 98 (`count(whole: other) == 2`) hits its cap and records an issue; line 103 then fails with "2 == 1" (`events.count(whole: identity.token) == 1`), the PR #91 failure.

My hypothesis, not verified: under width 1 the held prefetch occupies the only pool thread, so the second track's request cannot run until the cap fires. This is the "blocking work off the shared pool" rule. I did not change the test (`Tests/**` is not my lane). It is a real open flake that the stress tool reports correctly.

## Not done, and why

1. **A valid `--tier ci` verdict on this branch.** Blocked by (a) the GoogleTest rows, (b) the new null-test flags, (c) the corrupted run. The coordinator's combine plus one gate run is the proof. I did not run the old flags as a substitute.
2. **Lane B's null-test steps are written but not exercised.** `null-debug` (`--shards 3 --tier all`), `null-perf-O2` (`--opt-run`), `null-asan` and `null-tsan` (`--tier all --shards 3`) follow the coordinator's decisions. `null-run.sh` is tested only against a stub.
3. **Canary and nightly workflows** are not run locally (they need GitHub's network and the runner). `canary.sh` is untested.
4. **`check` tier (T2)** no longer includes the C++ null test (it is `combine,ci,gate` now, to keep T2 fast). Say if T2 should run the correctness tier.
5. **Wall times** are not measurable locally for CI. Estimates (labelled estimates): static ~15 min (clang-tidy 1.5 min, Periphery 3 min, plus its own build); swift ~10 min; cpp ~25 min (null-debug on 3 shards ~8–10, perf ~5, the rest small); asan ~30 min; tsan ~55 min (the local TSan run took 53 min serial; 3 shards should bring it down, unmeasured). Periphery builds its own index in the static job, so the static job duplicates the swift job's build. Estimated cost ~5 min per run.
6. **`make stress KIND=cpp`** is wired to `null-run.sh --shards 3 --gtest_filter --gtest_repeat --gtest_shuffle --gtest_random_seed` with a printed seed. It refuses until `--gtest_repeat` exists in the script (Lane B). Not run.
7. **`research/eq-engine-break-it/build-measure.sh`**: not mine (Lane B flagged it, broken at 96d057f).

## Xcode 27 and macOS 27 notes

- The local `Xcode.app` is 27.1 (27A9275), so local builds are on the pinned Xcode. `/Applications/Xcode_27.1.app` does not exist on this Mac. CI selects it by path: the runner readme lists `Xcode_27.1_Release_Candidate.app` with the alias `Xcode_27.1.app`. I did not create anything in `/Applications` (no sudo).
- `-D_LIBCPP_DISABLE_AVAILABILITY` is absent from every gate script and from `cxx-analysis-flags.sh` (checked). Only archived council experiment scripts under `docs/reviews/` still contain it; nothing builds them.
- **Residual risk:** CI runs macOS 27.0.1 while the product targets macOS 26. The cheap guard is `scripts/gate/deployment-target.sh` (minos per built product, no symbol scan). It passes now (13 products). It would catch a product built against a newer deployment target, but not a symbol that is newer and reached through an older minos. A full symbol check would be the next step if the founder wants it. Not built.
- The Xcode 27 `swiftbuild` engine: bin path always from `swift build --show-bin-path`; `.build/out/Products/Debug` today. No hardcoded directories remain in the gate scripts.

## Requests for other lanes

- **Coordinator (combine):** merge `testrig/cpp-rig`'s `toolchain/toolchain.env` rows (`GOOGLETEST_VERSION`, `GOOGLETEST_COMMIT`) and `.gitmodules` entry. Then run `--tier ci` once on the combined branch. Parity should pass; the null steps should run.
- **Lane B / coordinator:** keep `--gtest_repeat` in `build-null-test.sh` (the stress guard checks for it).
- **Lane C:** ANALYZER-05 (above).
- **Owner of `research/`:** `build-measure.sh` link list (Lane B's request).

## Open questions for the founder

1. **Recommendation:** accept the `xcode-27` label as declared in `.github/actionlint.yaml`. actionlint 1.7.12 (the newest release) does not know the preview label, so every macOS job would fail the lint otherwise. Alternative: wait for an actionlint release that knows it. Declaring the label changes no rule.
2. **Recommendation:** accept the macOS 27 CI vs macOS 26 product residual risk, with `deployment-target.sh` as the guard. A full undefined-symbol check against a 26.0 SDK would catch more; it is a larger job, so I did not build it.
3. **Recommendation:** T2 (`make check`) keeps the C++ null test out (it runs in T3 and CI). Otherwise every lane's "done" bar grows by ~10 min.

## Lessons logged

- Never edit a runner script during a run that uses it (the corrupted run).
- A child process in a fresh job-control group needs its own kill; the stress tool leaked 10 hogs once and was fixed (kills each recorded pid and group). Verified: 0 survive.
- The Semgrep CLI resolves `pysemgrep` and `semgrep-core` from `PATH`. Homebrew's 1.175.0 silently took over until the pinned names were linked into the bin dir.
- `Loudness_WorkersSleepWhileIdle` is a C++ test, not a Swift one; the stress tool is right to refuse it.
