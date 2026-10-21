# The gate: registry, runner, and where each old step went

`scripts/gate/steps.tsv` is the one list of checks. `scripts/gate/run.sh` runs them, collect-all, with a
watchdog per step, a result record per step (`results/<id>.json`), and an exit code that is the AND of
the blocking steps. Read the rules in the header of `run.sh`.

```
scripts/gate/run.sh --list                       # the registry
scripts/gate/run.sh --tier push|check|combine|ci|gate
scripts/gate/run.sh --job static|swift|cpp|asan|tsan
scripts/gate/run.sh --step <id> [--step <id> ...]
```

Outputs land in `.build/gate/<label>-<UTC stamp>/` (gitignored): `summary.md`, `run.json`, `results/*.json`,
`logs/*.log`. CI uploads that directory per job; the `strict-gate` check (`scripts/gate/report.sh`) reads all five.

## Mapping: every step of the old `scripts/strict-gate.sh` (and `make gate`) → registry id

Nothing was dropped. The left column is the old inline step, in its old order.

| Old step (strict-gate.sh, in order) | Registry id | Job | Tiers |
|---|---|---|---|
| Tool check (swift, xcrun, clang-format, swiftformat, swiftlint, semgrep, periphery, make, leaks, pins) | `toolchain-parity` | static | every run |
| SwiftFormat lint | `swiftformat` | static | push, check, combine, ci |
| SwiftLint strict | `swiftlint` | static | push, check, combine, ci |
| clang-format dry-run | `clang-format` | static | check, combine, ci |
| Semgrep | `semgrep` (+ `semgrep-rule-tests`, new: every rule flags its ruleid line and not its comment) | static | push/check/combine/ci |
| Suppression policy | `suppressions` | static | push, check, combine, ci |
| Migrator posture guard | `posture-migrator` | static | push, check, combine, ci |
| Playlist add/drop path guard | `posture-playlist` | static | push, check, combine, ci |
| S10.7 layer-policy guards (Kit purity, Dynamic Type clamps) | `posture-layers` | static | push, check, combine, ci |
| cppcheck (was optional, now pinned and required) | `cppcheck` | static | check, combine, ci |
| clang-tidy (AudioDSP + bridge + tests) | `clang-tidy` | static | check, combine, ci |
| Periphery (hostile, strict) | `periphery` | static | combine, ci |
| Swift build (debug) | `swift-build` | swift | check, combine, ci |
| Swift test | `swift-test` (zero-tests guard) | swift | check, combine, ci |
| `make gate`: null test | `null-debug` | cpp | check, combine, ci, gate |
| `make gate`: VerifyAUGraph | `verify-au-graph` | cpp | combine, ci, gate |
| `make gate`: SRCQualityMeasure | `src-quality` | cpp | combine, ci, gate |
| `make gate`: VerifyLibraryStore | `verify-library-store` | cpp | combine, ci, gate |
| Main-thread-stall self-test | `main-thread-stall` (four modes) | swift | combine, ci |
| Null-test source-coverage drift guard | `null-coverage` | cpp | combine, ci |
| `-O2 -Werror` null test | `null-release-strict` | cpp | ci |
| ASan + UBSan null test (`make sanitize`) | `null-asan` | asan | ci |
| TSan null test (`make tsan`) | `null-tsan` | tsan | ci |
| Store ASan (`make sanitize-library-store`) | `store-asan` | asan | ci |
| Leak detection (`make leak-check`) | `leak-check` | cpp | ci |

New steps with no old counterpart: `actionlint` (workflows), `semgrep-rule-tests`.

## Not in the gate, by design

- `make sheets`, `make songs-perf`, `make run`, `make release`, `make dist`: developer and release targets, not checks.
- The weekly canary (`canary.sh`) and the nightly stress (`make stress`): advisory workflows, never required.
