# Test-rig redesign — synthesis of the three reviews (2026-10-20)

Sources: `qa-expert.md` (57-hazard inventory, taxonomy, framework probes), `refactoring.md` (primitives, seams,
migration with file:line), `architect.md` (gate, toolchain, lanes, determinism, phased plan). All three read
`r1.1a/integration` @ 22287da; f5d1329 (Loudness_WorkersSleepWhileIdle) is the worked example of the target pattern.

## Diagnosis (all three agree)
PR #91's seven red CI runs had three causes — not one bad test:
1. **Tool drift (3 runs):** Periphery's tap broke behind `|| true`; cppcheck 2.21→2.22; clang-tidy behaviour. 8 of 13
   tools differ Mac vs CI (Xcode 26.5 vs 26.6, Swift 6.3.2 vs 6.3.3, LLVM, semgrep, cppcheck, FFmpeg; clang-format unpinned).
2. **Combination checked only in CI (1 run):** lanes verified alone; two imports left behind.
3. **Tests that depend on time or the machine (3 runs):** 57 hazards found — 11 wall-clock performance thresholds,
   7 short polls, 6 free-running chains racing the test, 5 fixed settles, 5 shared-process-state, 5 ordering-luck,
   5 un-ceilinged, 4 carry-on deadlines, 4 fixed "nothing happened" windows, 3 probabilistic detectors. 4 HIGH
   (3 open: the Enhanced rig's paced render, main-thread-stall's 25 ms line, Profiler_Timing's 1.9× wall budget).
**Amplifiers:** the gate stops at the first failure (one cause per 80-min run); swift-testing runs ~14 tests at
once on the Mac but ≤3 on CI's 3-core runners, and tests that BLOCK starve the shared pool; `steady_clock` counts
sleep; a misspelt `--filter` runs 0 tests and exits 0; SwiftFormat lints nothing in agent worktrees; 98 % of the
33 MB CI log is `[UX]` NSLog; no job timeouts (a hang runs 360 min).

## The four rules (consensus)
1. **Time only ever breaks hangs.** Every wait waits for a STATE; its generous cap fails loudly, naming the state;
   nothing ever carries on past a deadline. Holds are released only by the test.
2. **Measure the component, never the machine.** Per-component counters / "done" hooks (f5d1329), thread-CPU time,
   min-of-N, ≥10× tripwires in the gate; real performance budgets live in an optimised perf lane.
3. **Each test owns its world.** Unique storage per test; blocking work off the shared test pool; heavy
   real-engine suites in their own non-parallel step.
4. **Every run has a ceiling and reports everything.** Job/step timeouts, `.timeLimit`, a C++ watchdog; the gate
   runs every check to completion and shows all failures in one summary.

## Conflicts between reviewers — resolved
- **Test clock:** refactoring: swift-clocks **1.1.1** works on our Swift 6.3 (its 6.0 manifest), test-only;
  architect: latest swift-clocks needs 6.4 → write our own ~60-line clock. Both keep the product on the standard
  `Clock` protocol. → Recommend **swift-clocks 1.1.1, test-only, pinned** (founder: prefer established libs);
  our own clock is the fallback if Phase 0 finds it doesn't resolve. Bump at Swift 6.4.
- **C++ runner:** architect: adopt GoogleTest 1.18 (plugs into today's table, no test changes); QA + refactoring
  (+ council BT-3): keep ours, add GoogleTest's ideas (watchdog, repeat/until-fail, shuffle with seed, filter).
  Neither framework has per-test timeouts, so the watchdog is needed either way. → **Founder decision**; 2 of 3
  recommend "borrow the ideas" (smaller, no new dependency); the "prefer established libs" rule pulls to GoogleTest.
- **main-thread-stall oracle:** refactoring: "finished while the lock was held"; QA: hold until released, judge a
  lock wait at ~250 ms. Same idea → **change the oracle** (removes the 25 ms noise line, keeps the protection).
- **`withMainSerialExecutor`:** rejected by all (process-wide; would deadlock ANALYZER-05).

## Phased plan
| Phase | What | Effort | When |
|---|---|---|---|
| 0 | **Stop the bleeding:** CI job/step timeouts; never cancel main runs; gate runs to completion as parallel jobs + one summary check; `[UX]` logs off in tests; worktree SwiftFormat fix; 0-tests filter guard; `make stress` (process-group cleanup); fix VerifyLibraryStore's `withDeadline` (can't fail a deadlock); the 3 open HIGH items | ~2 agent-days | one small PR right after R1.1-A merges |
| 1 | **One toolchain manifest** (exact versions + checksums, Xcode included) read by one install script on Mac and CI; parity check first in every tier; weekly canary proposes bumps | ~2 agent-days | with Phase 0 or early R1.1-B |
| 2 | **Test-helper kit + migration:** Swift `RigKit` (`until`, `blocking`, `Hold`, `TestPoints`, `UnderLoad`), C++ `TestSupport` (waitUntil, Rendezvous, watchdog, repeat/shuffle/load, thread-CPU meter); migrate the 57 hazards in risk order; unique storage; `--no-parallel` step; quarantine policy; semgrep `test-no-raw-time` at the end; `make combine-check` for lanes | 4–6 agent-days, 2 lanes | R1.1-B |
| 3 | **Determinism in the product:** standard `Clock` for the transport tick and 5 debounces, `WorkTracker` for fire-and-forget tasks, `TestPoints.h`; retire the ~61 mirror tests onto one `FakeEngine` | rides W2 | Engine sprint / W2 |
| 4 | **Engine sprint "definition of done":** every engine behaviour tested with no sleeps or wall-clock waits (frame time, which-track events, manual host, seeded explorer) | part of the sprint | Engine sprint |
| 5 | Nightly advisory stress job | small | after Phase 2 |
