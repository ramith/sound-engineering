# Lane C report: the Swift test rig and the view-model seams

Branch `testrig/swift-rig` (worktree `.claude/worktrees/testrig-c`), rebased onto `testrig/integration` @ cf8ebb9. 19 commits, no push.
My ea0c119 (LiveReadouts waits) was dropped on the rebase as already in #93; the LiveReadouts suite is rewritten onto the ticker seam.

## Commits
```
81b89ef test(rig): RigKit — until, blocking, Hold and the log tail; swift-clocks 1.1.1
a7e45b1 feat(test-seams): ticker, WorkTracker, clocks, SettingsStore.pendingWrite, [UX] sink
8e049d8 fix(test-seams): AudioViewModel.swift under the 500-line lint limit
98da2e1 feat(test-seams): StreamObserver (R4)
7a5b4f6 fix(loudness): decode off the cooperative pool (P2, product)
f23ee85 fix(test): Enhanced rig in lock-step with the completion chain (R4 R5 R6 R7 R8 R9)
6113af1 fix(test): view-model and settings tests (S8 S9 S13 S14)
f365c78 fix(test): analyzer tests on Hold/until (S10)
451fbbb fix(rig): caps on SuspendingClock
961dc5a fix(test): VM-TS-02 without a wall-clock bound (S1)
6be19a7 fix(test): SpectrumHandoff by counts (S2)
79501c4 fix(test): scan-race walks overlap for certain (S11 S12)
a716374 fix(rig): until evaluates its condition on the caller's actor
87e2d21 fix(test): OnDeck/Transport rigs (R1 R2 R3 S13)
7f022d0 lint(test-rig): semgrep rule test-no-raw-time + fixture
e2a5ff0 fix(test): VolumeMonitorPause on an ImmediateClock
c098607 docs(testing): the Swift section
272b9f9, 25959e3 style: swiftformat / swiftlint clean
```

## Honest corrections
- **Commit f365c78 says "10/10 under 16 hogs". That was not true when written.** Run 10 of 10 failed: `until`'s cap used `ContinuousClock`, the Mac slept, and the cap fired after "120 s" in a 7.8 s test. Fixed in 451fbbb (caps on `SuspendingClock`). The 10/10 was obtained after that (`caffeinate`, strict pool, 16 hogs), then again with `make stress`. I did not rewrite history; 451fbbb and 961dc5a's body record it.
- **Commit 7b492bb/79501c4's body said "mutation check: see the lane report".** The mutation is in the table below.
- **Two RigKit bugs found by the migration, both fixed with a proof:**
  1. `until`'s condition ran on the global executor, not the caller's actor (a nonisolated async closure parameter hops). Conditions forwarded as values read main-actor models from another thread: hangs and `Index out of range` in the OnDeck rig. Fixed with `nonisolated(nonsending)`; RIG-15 fails without it.
  2. `logUX`'s sink as a bare closure inside a `Mutex` grew two reabstraction thunks per call. The OnDeck explorer's ~100,000 lines overflowed the stack (SIGBUS) and slowed 30×. The sink is a struct holding the closure; UXLOG-01 runs 200,000 lines.

## Evidence (all exit codes real; pinned PATH `…/9878b9390ce38c3a/bin`)
- `scripts/gate/run.sh --tier check`: toolchain-parity, swiftformat, swiftlint (after the style commits: `--step swiftformat --step swiftlint` exit 0), clang-format, semgrep, semgrep-rule-tests (21/21 incl. mine), suppressions, postures, cppcheck, clang-tidy, actionlint, swift-build, deployment-target, **swift-test 980 tests PASS** all PASS. (googletest submodule had to be initialised in my worktree for parity.)
- `scripts/gate/run.sh --step periphery`: its incremental index is incomplete in this worktree ("index store does not contain data"); with a clean `swift build --build-tests --enable-index-store` then `periphery scan --skip-build` (2.21.2): **exit 0, nothing unused.** `--step main-thread-stall` PASS (C2's check with my ticker seam). `--step swift-test` PASS (980; was 962: +13 RigKit, +1 OffPool, +1 RIG-15, +1 UXLog, +2 LiveReadouts, −… see commits).
- `make stress N=10` (CI-like: 13 hogs, strict pool), exit 0, 10/10:
  - A: LiveReadouts, SeekViewModel, OutputDeviceViewModel, ListeningSettings, CrossfeedPlays, SettingsStore, R11aSettingsBreak, PureVolumeLoanJournal, VolumeMonitorPause, UXLogSink, RigKit, OffPool, LogTailAttachment, TransportSnapshot, SpectrumHandoff, LibraryScanRaceG, TrackLoudnessAnalyzer.
  - B: `Enhanced[A-Za-z]*Tests`.
  - C: OnDeckContract, OnDeckExplorer, TransportContract, TransportExplorer, QueueEditContract.
  - Earlier with my own hog script (16 hogs, strict): analyzer 10/10, Enhanced 10/10.
- Full suite with the strict pool and no hogs: pass (AdaptiveSoundTests 74 s). Default parallel mode: pass (swift-test step).
- `swift build --build-tests`: 0 warnings.
- swift-clocks: **1.1.1 is the latest release** (`git ls-remote --tags`: …1.1.0, 1.1.1). Pinned `exact: "1.1.1"`, test target `AdaptiveSoundTests` only; Package.resolved also pins swift-concurrency-extras 1.4.3 and swift-issue-reporting 2.1.2. No product target links it (product defaults are `ContinuousClock()`).

## Hazards: what each waits on now, and its mutation check
| ID | Now waits on | Mutation (planted, failed, reverted) |
|---|---|---|
| S1 VM-TS-02 | 60 reads complete while a `Hold` keeps the publisher stuck; no duration | `publish` that stores nothing: VM-TS-01 fails |
| S2 SpectrumHandoff | 2000 reads and 50 write-overlapped reads (writer's write count moved across a read), iteration ceiling | reader copies the producer's slot: `torn > 0` |
| S3–S7 LiveReadouts | `ManualTicker.fire()`; `until` for start/pause; positive witness (7 ticks read the snapshot) | earlier (PR #93) mutation: a tick that never stops fails both pause tests; mine asserts `isRunning` |
| S8 (4 files) | `viewModel.settled()` = WorkTracker idle and `pendingWrite == nil` | WorkTracker that never counts out: every `settled()` names its state at the cap |
| S9 SettingsStore | `await store.pendingWrite?.value` | write task that never writes: SETTINGS-04 fails |
| S10 ANALYZER-04 | the cancelled log line via `until`; `Hold` | latest-wins cancel removed: ANALYZER-04 fails (2 issues) |
| S11/S12 scan race | `withHold`: walk A held at its first batch on an `OffPoolExecutor` until walk B ends; bounded `arrived()` | progress callback never fired: "never reached: walk A at its first batch" |
| S13/S14 | `IsolatedDefaults` (UUID suite) in OnDeck rig, every VM suite, SettingsKit suites | n/a (isolation) |
| R1 | `Rig.waitUntil` = RigKit `until` | — |
| R2/R3 | `runViewModelOut`: WorkTracker idle, or every task suspended in a call the engine owes (`owedCallers`) with 3 stable yield rounds; `quiesce` one `until` | `startPlayback` guard removed: 9 contract/explorer tests fail |
| R4 | `StreamLedger`: after each block, every completion due by the frames rendered is delivered (`untilBlocking`), then `resampleQueue` drained twice. Probed: completion k arrives ~150 µs after the block reaching buffer k's end | `streamPlayedOut` guard removed: stop/seek end tests fail; seam count skipped: seam and end-of-queue tests fail |
| R5/R7 | `until` on the tap's delivered frames / the seam count (120 s hang cap) | — |
| R6/R8 | the stop's own completions delivered (`untilSupersededCompletionsLand`) is the positive witness | same as R4 guard removal |
| R9 | `frames(until:)` pulls lock-stepped blocks | — |
| R10/P2 | selection by type name (below); rig renders in `blocking{}` | n/a |
| S14b VolumeMonitorPause | `ImmediateClock` on the reconcile debounce | reconcile never requests its walk: both tests fail |
| P3 | `logUX` sink, `QuietLog`, `.attachingLogTail` (an issue in a suite with the trait attaches the tail; verified in RIG-13) | UXLOG-01 proves the sink |

## Product files touched (defaults unchanged)
`UXLog.swift` (sink, default NSLog), new `TransportTicker.swift` (default the same common-mode `RunLoop.main` timer), new `WorkTracker.swift` and the 8 `AudioViewModel+*` spawn sites, `AudioViewModel.swift` (3 seam properties, init params), `AudioViewModel+Lifecycle.swift` (shutdown log reads `work.isIdle`), `AudioViewModel+QueueMirror.swift`, `LibraryModel.swift`/`+Reconcile.swift`, `ShellToast.swift`, `EQBringBackMessage.swift`, `SongsView.swift` (clock param), `SettingsStore.swift` (`pendingWrite`; `save` reads it as "a write is on its way", equivalent to `pending != nil`), `AudioEngineBridge.swift` + `+StreamObserver` + 4 bridge files (optional `StreamObserver`, nil in the app, one `Mutex` read per scheduled buffer; no render or main thread involvement), and **`TrackLoudnessKit/TrackLoudnessAnalyzer.swift`** (coordinator's addition): the decode runs on a concurrent utility `DispatchQueue` while the job's Task awaits a continuation; `withTaskCancellationHandler` raises an atomic flag the decode checks between reads. Latest-wins, promotion, cache, order, failure handling and log lines unchanged. The sink's callbacks now run on the decode queue.

## P2 audit of the rest of the product (not fixed; no test hits it under the strict pool)
Strict-pool full suite passes. Same pattern, by likely impact:
1. **`MetadataScanner.run`**: up to `min(cores, 6)` pool tasks each doing AVFoundation tag reads and ImageIO thumbnails (CPU/IO-bound, synchronous between awaits). On a 3-core Mac the metadata pass can occupy the whole pool for its duration. Recommend: run `extractOne` on a dedicated concurrent queue (as the analyzer now does), cap at cores − 1.
2. **`LibraryScanner.walk`**: synchronous file enumeration and signature reads in an async function on the pool at `.utility` (one task per walk, two when add and reconcile overlap). Recommend the same off-pool executor.
3. `PlaylistsModel.entryAvailability`: per-entry disk looks in `Task.detached`: short, large playlists only.
4. `AudioViewModel.refreshDuration` / `writePlayCount` detached: opens one `AVAudioFile` header / one SQLite write: short.
Everything else blocking in the app already runs on its own `DispatchQueue`s (the bridge's four, the watcher).

## Heavy real-engine suites (R10): the registry row I request
The `Enhanced…Tests` suites (5 types) are selected by type name; other tests contain "Enhanced", so anchor it:
- serial step: `swift test --no-parallel --filter 'AdaptiveSoundTests\.Enhanced[A-Za-z]*Tests/'` (21 tests, 8.8 s serial)
- main run: add `--skip 'AdaptiveSoundTests\.Enhanced[A-Za-z]*Tests/'` (verified: `--filter Enhanced --skip …` leaves only the 6 non-rig tests).
Note `.build/out/…/index/store` from an incremental build misleads `--step periphery`; a clean indexed build is needed (Lane A may want the step to build its own index).

## Not done, and why
- Seam tests for three UI clocks (ShellToastSlot, EQBringBackMessage, SongsView): the seams exist; no view hosting in the suite. A `ShellToastSlot` `ImmediateClock` test would need its private task exposed.
- ANALYZER-04's 500 ms idle window is gone, but ANALYZER-05/04 reproductions (5 s pause, 31 s stall) were run once under the strict pool with 16 hogs and passed; not part of the repeating stress.
- C++ and Verify* hazards are other lanes'. `FFmpegOptIn.isOn` (process-global switch set by ListeningSettings ffmpeg test) remains shared state; flag for Lane D/the founder.
- `Hold`'s producer cap uses wall `Date` (NSCondition), not `SuspendingClock`; at 300 s a sleeping Mac could expire a hold, which fails loudly (never silently).
- `UnderLoad` trait and `TestPoints`: not built; `make stress` covers load and no migration needed a TestPoint.

## Requests
- Lane A: the registry row above; `periphery` step should do its own full indexed build.
- Lane D: build FakeEngine on `WorkTracker`/`settled()`, `TickerBench`, `IsolatedDefaults`; `OnDeckEngineModel.owedCallers` is the "suspended in the engine" signal.

## Open questions (recommendation first)
1. Leave the analyzer decode on a concurrent queue (done) and fix MetadataScanner and the walk the same way next sprint? Recommend yes: they are the only product code that can starve the pool in the app, on 3-core Macs.
2. Keep `until`'s default 120 s cap? Recommend yes: a passing run pays nothing, and `.timeLimit(.minutes(3))` ends the test if it is somehow cancelled.
