# Lane A: review fixes (branch `testrig/gate-review-fixes`)

Worktree `.claude/worktrees/testrig-a`, on top of `testrig/integration` 2831847. Not pushed. Nothing here has run on GitHub yet: every CI claim below is a local proof, and the first real CI run is still the open item B4.

## Commits (on 2831847)

| commit | finding(s) | what |
|---|---|---|
| 731ae69 | B1, B2, H4 | summary reads only step records; one stamped run.json per job; gate output outside `.build`; distinct cache keys; main never cancelled |
| a03824c | H2 | pre-commit hook formats and analyses with the pinned toolchain |
| 4949823 | H3 | swift test streams its output; ten waiting rig suites get `.timeLimit`; timelimit guard |
| 4963ca8 | H3 (guard fix) | guard reads a `@Suite` attribute across its wrapped lines |
| f3c2816 | H1, H5 | macOS 26 runtime job and the nightly issue; availability switches banned |
| da8b7b4 | B3, M1, M2, L10 | FFmpeg is info only; trimmed toolchain cache; Python 3.12 pin; whole-token version matches |
| a993df1 | M5, L1, L13 | registry lint; job timeouts; release builds only the app; docs |

## Per finding

**B1, the summary crashed on every run.** `result.py render` globbed every JSON; it read `semgrep-scan.json` and GoogleTest shard files as step records and died on `KeyError: 'status'`. Now `result.py summary` reads only `**/results/*.json` and `**/run.json`; every problem is a named red row; a crash of the check itself is red. `report.sh` is a thin wrapper. Proof: `scripts/gate/report-selftest.sh` runs seven fixture cases built from the real registry; all seven behave (all-pass exit 0; failure, timeout, missing job, stale run, duplicate run.json, malformed record each exit 1 with the named row). Run under CI identity variables as well: 7 of 7. A real static-job run with CI identity produced stamped records, and the summary named the four absent jobs red.

**B2, stale cache results and doubled rows.** Gate output now lives in `${{ runner.temp }}/gate/<job>`, outside the cached `.build`. Swift and cpp have distinct cache keys. Every run.json and record carries `GITHUB_RUN_ID`, attempt and SHA; the summary rejects any other run. Still open on GitHub: the first real CI run must show this.

**H4, main runs could be cancelled.** The concurrency group is per run for anything that is not a pull request, so a pending main run is never replaced. Still open: needs one real main-like run to see it.

**H2, the hook used tools outside the manifest.** `scripts/toolchain/use-pinned.sh` (sourced by the hook) puts the pinned bin dir first when the install is complete, and says plainly when it is not. `cxx_clang_tidy_path` prefers that dir, and the major pin is read from `LLVM_MAJOR`, so there is one source. Proof: installed, the pinned clang-format resolves first; not installed (empty cache), the NOTE prints and the hook keeps the old behaviour.

**H3, a Swift hang could not be named; ten suites had no time limit.** `swift-test.sh` streams to the step log through `tee` and reads the exit code from `PIPESTATUS`, so a killed step leaves a log that names the last test started. Ten waiting suites now have `.timeLimit(.minutes(5))` (per test under swift-testing); the four wrapped ones are wrapped correctly. `scripts/gate/timelimit-guard.sh` enforces the rule on the real tree (13 suites, all with the limit) and fails on a planted waiting suite without one. The rule could not be a semgrep rule: the attribute spans lines and semgrep's regex rules cannot reliably follow it. Swift test count on the tree: 959 plus 21 rig (T2 run, exit 0). Not done: swiftformat and swiftlint do not stream (they finish in seconds; a hang there is not plausible).

**H1, macOS 26 nightly and release gate.** `macos26-compat.yml` builds the app, VerifyAUGraph and the null test on `xcode-27` and runs them on `macos-26` (`scripts/gate/macos26-run.sh`): four stall modes, the null test's correctness tier, VerifyAUGraph. Any dyld "Symbol not found" or "Library not loaded", or non-zero exit, is red. `release.yml` calls it and needs it before it builds. Proof on this Mac (macOS 26.6): the pass path is 6 of 6 green; a planted binary needing a missing symbol is refused by the loader, named in every row, exit 1. Ban: `scripts/gate/availability-ban.sh` fails any non-comment use of the availability-disabling flags in Package.swift, scripts, Makefile and .github, with a planted case. What it can and cannot catch is written in DEVELOPMENT.md. Not done: the nightly job has never run on GitHub; the review's suggestion to use the macOS 26 runner for the verifiers beyond VerifyAUGraph was left out for time.

**H5, a failing nightly is silent.** `nightly-stress.yml` drops `continue-on-error`; its `issue` job opens or updates one issue with the failing lines and the replay command (the C++ seed is printed in the log). `macos26-nightly.yml` does the same for the macOS 26 job. Nothing blocks a merge. Proof: `nightly-issue.sh` is never run against GitHub; the body is checked only by actionlint.

**B3, FFmpeg could switch off the gate.** Founder direction: a mechanism that works with any FFmpeg. The pin is gone from the manifest. Parity prints `ffmpeg (info)` with the version found, and `ffmpeg analysis` as ON or OFF (OFF names that the FFmpeg branch is not analysed). The setup action's `brew install ffmpeg` is `continue-on-error` with `HOMEBREW_NO_AUTO_UPDATE=1`. The canary reports the Homebrew formula version and the headers it sees. Proof: parity OK with 0 warnings; FFmpeg 9.0.1 shows as INFO. The code side (the analysis flags and the null test's search path) was left to the founder's separate research, as instructed.

**Trimmed toolchain (M1).** LLVM keeps only clang-tidy, clang-format and `lib/clang/23/include` (139 MB, extracted once per checksum into `tools/llvm-<sha>`); the 1.5 GB archive is deleted once extracted. cppcheck and the semgrep venv are shared by checksum. Each manifest folder holds symlinks and `bin.sha256`; install and fast path re-hash every tool file. Install prunes every manifest folder except the current one and one rollback. Proof: it removed `05e6…` and `e42c…` (the two old folders the founder approved) and kept `9878…`. The current version is 69 MB plus 444 MB of shared tools. Parity OK; clang-format (84 files) and clang-tidy (33 files) pass through the runner; the fast path prints "installed and verified" and exits 0. Not proven: a tampered tool file being caught (the fast path re-hashes, but I did not plant a corruption, since the store is shared).

**M2, the venv used whatever `python3` was on PATH.** `PYTHON_VERSION=3.12` is in the manifest; the installer uses `python3.12` and fails clearly without it; CI installs it with a SHA-pinned `actions/setup-python` (v7.1.0). Parity has a python row (major.minor). Proof: parity OK.

**L10, substring version matches.** Versions match whole tokens: `2.21.2` matches "Periphery 2.21.2" and not "2.21.20". Proof: checked on five inputs.

**M5, registry and CI disagree silently.** `scripts/gate/registry-lint.py`: red when a job is not a strict-ci.yml job, a row lacks `ci`, a timeout is malformed, `needs` names no step, a runs-on is not `RUNNER_LABEL`, or a CI job timeout is below its caps plus 20 min. It reads `RUNNER_LABEL`, which nothing read before. Proof: real tree OK (34 rows, 6 jobs); planted bad registry caught 3 of 3 (exit 1).

**L1, job timeouts below step caps.** The lint found static and swift short. Now static 130 and swift 120 minutes; the lint enforces it.

**L13, release built RigKit.** `make release` builds `--product AdaptiveSound` only.

**M6, the summary's own crash turned green.** Done through B1: a crash in the check is red.

**M7, each null step deleted the previous JSON.** `null-run.sh` writes to `null/<step-id>/`.

**M4, named hang classified by exit code.** `run.sh` now classifies a hang by the `[HANG]` line in the log, not by exit 134 (ASan aborts also give 134). The shard runner in `build-null-test.sh` still exits 1 on a hang; that is Lane B's file (see requests).

**L2, release had no timeout.** `timeout-minutes: 60`.

**L3, the lock wait had no cap.** Capped at four hours; names its holder.

**L9, the canary's token reached unverified tools.** `unset GH_TOKEN GITHUB_TOKEN` before the tool steps.

**L11, empty tool directory.** `run.sh` refuses it.

**L12, re-run uploads.** `overwrite: true` on every upload.

**L14, failures visible only at the end.** `::error` annotations as each step fails.

**Proof of the gate run:** `scripts/gate/run.sh --tier check` on this branch exits **0** (21 steps: parity, format, lint, semgrep, suppressions, posture, cppcheck, clang-tidy, actionlint, the summary self-test, timeLimit guard, availability ban, registry lint, swift build, deployment target, swift test 959, rig 21). The first attempt exited 1 because the guard missed wrapped attributes; that was fixed (4963ca8) and the rerun is the proof.

## Left, with a recommendation

- **B4, CI has never run on GitHub.** Recommendation: open a draft PR carrying three planted failures (lint, Swift test, C++ test) and a hang, and read the `strict-gate` table and exit code. Nothing here is proven on GitHub until then. This is the top item.
- **M3, C++ ceilings and the sanitizer hang cap.** `TestSupport.h`'s `kHangCap` is not scaled by `kCeilingScale`, and the ≥10× claim is unmeasured under TSan on CI (local margin 4.2×). Recommendation: scale the cap, and set ceilings from the first CI run's JSON. This is Lane B's C++ file, so it is a request, not my change.
- **M4 remainder, shard runner exit code.** `build-null-test.sh` exits 1 on a sharded hang. Recommendation: exit 134 when any shard did, so the gate's classification and the script agree. Lane B's file.
- **M8, test counts can drop silently.** Recommendation: `scripts/gate/expected-counts.tsv` with minimums, checked by the runner, set from the first CI run's counts and changed only in the same commit as the coverage map. Needs real counts, so it waits for B4.
- **L4 to L7 (Swift rig).** Not my lane. Recommendation: Lane C picks up the `OnDeckRig` quiescence heuristic, `Hold.wait`'s wall clock, the UXLOG-01 sink swap, and the `RunLoopTicker` test.
- **L8, no shellcheck.** Recommendation: pin one checksummed shellcheck and lint `scripts/**/*.sh` and workflow `run:` blocks. About 2,000 lines of gate bash are unchecked.
- **L15, local strict-gate takes about 32 minutes.** Recommendation: per-variant test-data dirs so plain, ASan and TSan run in parallel. Lane B's defines.
- **L16, stale docs.** `architecture.md:183` (the 25 ms oracle), `validation-strategy.md:77` ("cppcheck if installed"), `.periphery.yml:2` (a workflow name that does not exist), `pre-commit` line 31 (a strict-gate.sh pin reference), and `deployment-target.sh`'s comment that claims a macOS 27 symbol shows as minos 27. Recommendation: fix the comment and the docs in one commit; the deployment comment is the one that misleads.
- **Cache rollback.** `9878…` (about 8 GB) is kept as the rollback and will be pruned on the next install after the next manifest change. Recommendation: none; this is the designed behaviour.
- **H3's semgrep rule.** Replaced by the guard script (the reason above). Recommendation: keep the guard.
