# Lane A: ShellCheck (L8)

Branch `testrig/shellcheck` (worktree `.claude/worktrees/testrig-a`), on `testrig/integration` 0690ebd. Not pushed. Tests/ not touched.

## Commits

| commit | what |
|---|---|
| 7849afa | ShellCheck 0.11.0 pinned by checksum in `toolchain/toolchain.env`; install.sh installs and asserts it; parity row; source directives moved to the line before `source`; the manifest comment that began "# shellcheck:" (a directive keyword, which broke the manifest's parse); install.sh and check.sh fixes |
| 7805047 | `scripts/gate/shellcheck.sh`: one step over every tracked `*.sh` and `.githooks/*`, with the coverage count; actionlint runs shellcheck on the workflows' `run:` blocks (its default now, not `-shellcheck=`); registry row in the static job |
| ad431d2 | the three `shellcheck disable=SC2046` lines (build-null-test.sh x2, build-leak-check.sh x1) removed by fixing the cause: the flags are read into an array |
| 179c2e1 | the remaining findings fixed at the root in clang-tidy.sh, the pre-commit hook, run.sh, deployment-target.sh, semgrep.sh, availability-ban.sh, stress.sh, canary.sh |
| f1c4d53 | the static job's timeout covers the new step: the registry lint caught 111 min of caps against 130 min; now 140 |

## Scope

- **In scope:** `git ls-files '*.sh' '.githooks/*'` minus `docs/` and `research/` (38 files, plus the hooks). `docs/` and `research/` are the same exclusion the other linters use (SwiftLint, SwiftFormat, Semgrep): archived experiments that nothing builds or runs.
- **Findings:** 89 in total with `-x`. The in-scope files had **27**, all fixed. The archived `docs/` and `research/` scripts have the other **62**, not fixed.
- **Recommendation on the 62:** keep the exclusion. Fixing archived experiments that nothing runs is churn. If the founder wants them linted, that is a separate sweep.

## What each finding class was, and the root fix

- **SC2046 / SC2086 (unquoted `$(...)` word splitting):** the flags were split silently, and suppressed in three places. Now they are read into arrays once (`read -r -a`), and the arrays are expanded quoted. Same arguments reach the compiler: `build-null-test.sh --build` exits 0, and `build-leak-check.sh` exits 0 (clean binary: 0 leaks; planted leak: detected).
- **SC2054 (comma array):** `-fsanitize=address,undefined` is one quoted element. It was always one argument; the quotes say so.
- **SC2329 (never invoked) x2 in run.sh:** shellcheck does not see a named function reached only through `trap`. The handler is inline in the trap string. Verified: a planted SIGINT (sent from Python, so the child is not ignoring it) makes the runner exit **130**, print the interruption, and leave no `sleep` behind.
- **SC2329 in the pre-commit hook:** `yellow()` was unused. Removed.
- **SC2015 (`a && b || c`):** install.sh's `rm && venv || die` is two statements; stress.sh's N check is an `if`.
- **SC2001 (sed for a substitution):** `${var#prefix}`, or a read loop.
- **SC2129:** canary.sh's appends are one group.
- **SC1090 / SC2153 (source not followed, misspelt variable):** the `# shellcheck source=` directive sat above `set -a; source ...`; moved to the line before `source`, so shellcheck follows the manifest and sees `XCODE_BUILD`.
- **SC2016 (single-quoted `$`):** null-coverage.sh's sed address writes `[$]OUTPUT`. Same address, same match.
- **SC2317 (unreachable):** cxx-analysis-flags.sh's `return 1 || exit 1` branch. The parity check's "clang-tidy pin" row already compares an empty pin with the manifest, so the branch is removed.
- **SC2329 in check.sh:** `patch()` had no caller since the FFmpeg row became INFO. Removed.

## Proof

- **Clean:** `scripts/gate/shellcheck.sh` exits 0, covering 38 files (39 once the step itself was tracked).
- **Planted (the step fails):** an unquoted `echo $1` appended to `scripts/gate/clang-format.sh` makes the step exit **1** with SC2086; reverted with git; clean again, exit 0. (A first plant of `planted=foo; echo $planted` was **not** a finding: shellcheck knows a literal has no spaces. The second plant used an unknown value.)
- **Planted (actionlint covers run blocks):** an unquoted `run: echo $PLANTED_UNQUOTED` appended to `release.yml` makes actionlint exit **1** with SC2086 on that line; reverted.
- **Tier check:** `scripts/gate/run.sh --tier check` exits **0**: 22 steps (shellcheck PASS, 39 files; registry-lint OK; timelimit guard 21; availability ban 77 files; swift-test 942; rig 21; deployment target 14 products).
- **Build proofs for the array change:** the null test builds with exit 0; the leak check exits 0 with its planted case; coverage guard OK (28 sources).

## Things you should know

- **The pinned folder changed twice.** Editing the manifest's comment changed its hash, so the folder you were given (`e3138429…`) is no longer the pinned one. The current pinned bin is `68e459c12532774d/bin`. The hook correctly printed its "not installed" note until I reinstalled. Use: `export PATH="~/.cache/adaptivesound-toolchain/68e459c12532774d/bin:$PATH"`.
- **The static job grew.** Its caps are now 111 min; the timeout is 140.
- **The actionlint behaviour changed.** actionlint now runs shellcheck on every `run:` block. Before, those blocks were not checked at all. Lint passes now, and the planted case proves it still checks.
- **One subtle thing about the planted proof:** a plant must be a real finding; shellcheck will not flag a literal. Recorded above, so nobody repeats the mistake.
- **Not done:** the 62 findings in archived `docs/` and `research/` (see Scope). The canary does not report shellcheck's latest release yet. Recommendation: add a shellcheck row to `scripts/gate/canary.sh` in a follow-up, so a new release shows a week early.
