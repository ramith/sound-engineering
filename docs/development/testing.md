# Testing: the four rules, the gate, and how to write a test

This is the test-rig contract for AdaptiveSound. The gate that runs it is described in
[DEVELOPMENT.md](DEVELOPMENT.md#quality-gates); the step registry is `scripts/gate/steps.tsv`.

## The four rules

1. **Time only ever breaks hangs.** A wait waits for a STATE, never for a clock. Its generous cap fails
   loudly, naming the state it was waiting for, and never carries on past a deadline. A hold is released
   only by the test that placed it.
2. **Measure the component, never the machine.** Count what the component did (a done hook, a counter),
   measure its own thread CPU time, take the minimum of N runs, and use ≥ 10× tripwires in the gate.
   Strict performance budgets live in the optimised timing tier (`make gate` runs `--opt-run`).
3. **Each test owns its world.** Its own storage and its own state. Blocking work stays off the shared
   test pool. Heavy real-engine suites run in their own non-parallel step.
4. **Every run has a ceiling and reports everything.** Each gate step has a timeout, each C++ test has a
   ceiling, and the gate runs every step to completion and shows every failure in one summary.

## The gate, in one paragraph

Every check is a row in `scripts/gate/steps.tsv`. `scripts/gate/run.sh` runs the rows collect-all: a
failure never stops the run, a skip is recorded with its reason, and each step has a watchdog that kills
its whole process group and names the timeout. A step that covers zero files or zero tests **fails**.
Toolchain parity runs first, always. CI runs the same rows as five parallel jobs plus one `strict-gate`
summary check (`scripts/gate/report.sh`).

## The C++ rig (`Tests/`)

The C++ null test is one binary built by `scripts/build-null-test.sh`, on GoogleTest 1.18 (the submodule
`third_party/googletest`, pinned in `toolchain/toolchain.env`).

- **Primitives and conventions:** `Tests/TestSupport.h` (the wait-for-state helper, the thread-CPU meter,
  min-of-N) and `Tests/NullTestRunner.h` (the per-test watchdog and the tier table). Read their header
  comments first; they hold the details.
- **Tiers:** `correctness`, `concurrent`, `accuracySweep`, `timing`. `--tier all` runs every tier; a `-tier`
  entry excludes one. Timing tests assert ≥ 10× tripwires in the plain build, and their strict budgets run
  in the `-O2` timing step (`--opt-run`).
- **Sharding:** `--shards N` runs N processes over the parallel-safe tests, plus one serial group.
  Two null-test processes from one checkout must never run at once, except through `--shards`, because
  they share `test-data/`. The runner serialises the null-test steps for you.
- **A hang:** a test that runs past its ceiling prints `[HANG] <Suite.Test> ran past its N s ceiling. Last
  progress: …` and the process exits **134** with no JSON. The gate reports that as a **named hang**, not a
  generic failure. Ceilings: 120 s (correctness), 300 s (timing), ×3 under ASan, ×8 under TSan.
- **Evidence:** every run writes GoogleTest JSON; `scripts/gate/null-run.sh` counts the tests across all
  of them and fails on zero.
- **Filters:** `--gtest_filter`, `--gtest_repeat`, `--gtest_shuffle`, `--gtest_random_seed`. A filter that
  selects nothing fails.

## Swift tests (`Tests/`)

Swift tests use swift-testing. Two rules the gate enforces:

- `swift test --filter` matches **function or type names**, not `@Test` display names. A misspelt filter
  runs zero tests and exits 0; `scripts/gate/swift-test.sh` turns that into a failure, and it also fails a
  test bundle that did not load.
- Every suite with waits has a `.timeLimit`, and every wait names its state.

The Swift rig primitives (the `until` helper, `Hold`, `TestPoints`, the under-load trait) are documented
with the Swift rig when that lane lands.

## Repeating a test under load

Before merging a new or changed timing test, repeat it under the CI-like profile:

```bash
make stress TEST=prefetchPromoted N=50        # Swift: swift test --skip-build --filter, every iteration must run ≥ 1 test
make stress KIND=cpp TEST='Loud*' N=50        # C++: shards, repeat, shuffle, with a printed seed
```

The profile puts `ncpu − 3` CPU hogs in their own process group, each killed by a trap on any exit, and
sets `LIBDISPATCH_COOPERATIVE_POOL_STRICT=1`. The exit code is the verdict. Put the pass rate in the PR.
