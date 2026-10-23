# Test-rig redesign — sprint plan (2026-10-20, from the founder's 7 decisions)

Inputs: SYNTHESIS.md (diagnosis, 4 rules, phased plan), qa-expert.md (57 hazards w/ IDs S*/R*/N*/V*/P*, fix order §4.3),
refactoring.md (RigKit / TestSupport primitives, product seams, mirror → FakeEngine), architect.md (step registry §2.1,
collect-all §2.2, CI job graph §2.3, blocking vs advisory §2.5, manifest §3, combine-check §4, determinism §5).

## Founder decisions (binding)
1. Gate runs EVERYTHING to completion: parallel CI jobs + one summary check. Merging stays manual.
2. ONE toolchain manifest (exact versions + checksums, Xcode included) → one install script (Mac + CI) → parity check
   first in every tier. Founder updates the Mac's Xcode 26.5 → 26.6. Weekly canary proposes bumps (advisory).
3. C++ runner: ADOPT GoogleTest 1.18 + our own per-test watchdog.
4. WHOLE redesign BEFORE any new feature (R1.1-B waits).
5. swift-clocks 1.1.1, test-only; the product uses the standard `Clock`. Fallback: our own ~60-line clock.
6. main-thread-stall judged by behaviour (main finishes while the engine lock is held on purpose), not a 25 ms timer.
7. Flaky tests: fix immediately, never quarantine, no retries. Semgrep no-raw-time rule + advisory nightly stress kept
   as early warning (each finding → fix immediately).

## Shape: one sprint, one PR
- Branch `testrig/integration` off `r1.1a/integration` @ 0fb9ddb (the migrated tests include R1.1-A's); rebase onto main
  once PR #91 merges. Lanes branch off it in their own worktrees; I combine; ONE local run of the NEW gate; push; CI.
- ≤ 2 agents at a time. No product behaviour changes except the test seams (clock injection, WorkTracker, TestPoints).
- Docs: `docs/development/testing.md` (the four rules + how to write a test here), DEVELOPMENT.md (toolchain install),
  architecture.md gate paragraph, sprint doc per reference-sprint-doc-conventions.

## Lanes
| Wave | Lane | Agent type | Scope |
|---|---|---|---|
| 1 | A — gate + toolchain | devops / build engineer | step registry `scripts/gate/steps.tsv` + runner `scripts/gate/run.sh` (collect-all, per-step process group + watchdog, results/*.json, zero-tests guard); Makefile/pre-commit call the runner; strict-ci.yml → jobs static / swift / cpp / asan / tsan + `report` (ubuntu) summary check, per-job timeout-minutes, never cancel main; toolchain manifest + install + parity (`scripts/toolchain/`), clang-format/cppcheck/semgrep/LLVM/FFmpeg/Xcode pinned; weekly canary workflow; SwiftFormat worktree config fix; [UX] NSLog off in tests; `make stress` (CPU hogs + LIBDISPATCH_COOPERATIVE_POOL_STRICT=1, trap cleanup); `make combine-check` |
| 1 | B — C++ rig | cpp-pro / modern-cplus-plus-expert | GoogleTest 1.18 from pinned source + checksum, built with our flags (plain/ASan/UBSan/TSan, -O2); existing test table registers as gtest cases (no test rewrites); per-test watchdog; TestSupport: waitUntil (cap fails loudly), Rendezvous, thread-CPU meter, min-of-N; tiers correctness/timing/concurrent; migrate C++ hazards N*/V* (Profiler_Timing family → thread CPU + ≥10× tripwire in gate, strict budgets in -O2 timing tier); VerifyLibraryStore withDeadline; VerifyAUGraph semaphore timeouts; main-thread-stall behaviour oracle; TestPoints.h |
| 2 | C — Swift rig + seams | swift-expert | RigKit test target (`until(_:cap:)` throws, `blocking {}` off the shared pool, `Hold`/`withHold` released only by the test, TestPoints, UnderLoad trait); swift-clocks 1.1.1 pinned test-only; product: standard `Clock` injected for the transport tick + 5 debounces, `WorkTracker` for fire-and-forget tasks; unique per-test storage (UUID suites); `--no-parallel` step for Enhanced*/LiveReadouts/SpectrumHandoff/stall-adjacent; `.timeLimit` on every suite with waits; migrate Swift hazards S*/R* (Enhanced rig waits on completions, not pacing — HIGH R4); semgrep `test-no-raw-time` turned on at the end with ZERO suppressions |
| 2→3 | D — mirrors → FakeEngine | refactoring-specialist | retire ~61 mirror tests onto one FakeEngine built on C's seams; coverage map old→new (no test dropped silently) |
| 3 | Break-it + review | qa-expert, then architect-reviewer | adversarial: full suite N× under `make stress` + strict pool; mutation check per migrated test (planted bug still caught); planted-failure branch proves CI shows ALL failures in one run; parity mismatch fails first with a clear message |

W2 (one transport owner) stays parked; C's seams are W2's scaffolding, not W2 itself.

## Definition of done
- Every wait waits for a state; caps fail loudly naming the state; no test sleeps or carries on past a deadline
  (semgrep rule passes with zero suppressions).
- Full suite green N× in a row on the Mac under `make stress` and under LIBDISPATCH_COOPERATIVE_POOL_STRICT=1;
  a CI stress dispatch green.
- Each migrated test mutation-checked (still fails on its planted bug).
- CI: a branch with 3 planted failures (lint, Swift test, C++ test) shows all three in one run's summary; a hang is
  killed by its timeout and named.
- Parity check green on Mac (after Xcode 26.6) and CI; a deliberate mismatch fails first, clearly.
- Test counts do not drop (962 Swift, 244 C++, 162 store) except mirrors retired onto FakeEngine with the coverage map.
- The new gate's own exit code read, locally once and on CI.

## Founder actions
- Merge PR #91 after the listening/visual check (independent of this sprint).
- Update the Mac's Xcode to 26.6 before Lane A's parity check is enforced locally.
- Engine sprint DoD "no sleeps / no wall-clock waits" recorded in its backlog entry (docs only now).
