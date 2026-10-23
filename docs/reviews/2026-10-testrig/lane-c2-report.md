# Lane C2 report: verifiers and the main-thread-stall check, judged by behaviour

Worktree `.claude/worktrees/testrig-c2`, branch `testrig/verifiers` (off `testrig/integration` @ ac8e0e3). Nothing pushed. No product source changed (every mutation was reverted, `git status` clean). No Co-Authored-By trailer.

## Commits (oldest first)
- cacab88 main-thread-stall judged by behaviour (V6, V7, V8, V9)
- 0b95afb hang cap runs before the device-loss trigger (found by the mutation run)
- 5ec6fef VerifyLibraryStore: watchdog-thread deadline; GC-05 / ALB-08 in CPU time against 10x tripwires (V1, V3, V4)
- cddcea4 VerifyAUGraph: every semaphore wait capped and named (V5); ALB-08 removes its 2nd fixture store (it leaked into test-data/)
- a7e2e40 VerifyLibraryStore: every park waits with a named cap (V2 confirmed)
- f5341df the three mid-scan rendezvous no longer park a cooperative-pool thread (a real strict-pool deadlock, see Findings)
- 4aa30c4 doc line length
- fcfc668 scripts/gate/main-thread-stall.sh header

Files touched: `Sources/AdaptiveSound/Debug/MainThreadStall{Hold(new),Rig,Probe,SelfTest}.swift`, `Sources/VerifyLibraryStore/{Deadline,CPUTime(new),main,ChecksConcurrency,ChecksGenreCovers,ChecksAlbumFixRound,ChecksScanReconcile,ChecksScanEdge,ChecksMetadataPass}.swift`, `Sources/VerifyAUGraph/{main,VerifyMultichannel}.swift`, `scripts/gate/main-thread-stall.sh` (comment only). steps.tsv: unchanged (no timeout needed changing).

## What changed, per hazard
- **V6 (the oracle).** No millisecond threshold decides. `StallHold` holds the engine lock until the test calls `release()`. The run passes only if, WHILE held, main finishes 20 full probe rounds (every main-thread entry into the engine) and serves 10 main-queue round trips (the 2 ms watchdog posts). A control read (`isPlaying` / `isRunning`) runs on a background thread and must still be waiting when main is done, which proves the lock really was held (replaces "control >= 300 ms"). `StallHangCap` (20 s, separate thread) fails the run naming what main was inside ("main was inside 'bridge.snapshot()'"). Timings and the longest queue wait are printed as information. The old `target/bound/queueBound`, `worst`, `shareOverTarget` are gone.
- **V9.** The holder signals it is INSIDE the lock (`StallHold.isInside`), replacing `pump(0.15)`/`pump(0.05)`.
- **V8.** device-loss waits for the state `!viewModel.isPlaying` (paused) while the lock is held, instead of "within 500 ms". Before the loss it waits for the playhead to pass 0.3 s (before it was ~0.01 s, which made "the place was kept" nearly vacuous), and the place check is on the playhead (abs < 0.25 s), not wall time.
- **V7.** ended-advance: waits for "the clock published the end flag" (`snapshot().transport.ended`), holds B's start with the engine queue blocked until the test releases it (no `Thread.sleep(0.3)`), waits for "the advance happened" (`selectedTrackIndex == 1`), then 12 ticks counted (not 50 ms steps) with the stale end flag still set, releases, waits for `transportCommand == nil`, 6 more ticks, then the verdict.
- **All rig waits** (`built`, `started`, `ready`) now go through `StallVerdict.wait`, which fails naming the state at a cap. `waitFor(state)` pumps the main loop and fails at its cap; nothing carries on past a deadline.
- **V1.** `withDeadline(_ what:, seconds:)` is a watchdog THREAD (outside the cooperative pool) that prints the running check ("check 19 (l-reads-during-scan)") and the phase and exits 1. The old task-group race could not fire while a child was wedged. The driver publishes the current check through `CurrentCheck`. Return type is now `T` (the nil-means-timeout branches are deleted from 6 call sites).
- **V2.** Confirmed condition-bound (SQLite BUSY probe: the holder holds until the contender reports). Its one uncapped `semaphore.wait()` now has a named cap (`awaitState`).
- **V3.** GC-05: cheapest of 5 reads' process CPU time vs a 1000 ms tripwire (measures about 12 ms, so about 80x headroom).
- **V4.** ALB-08: process CPU time of each pass, `shared <= 10 x distinct + 2 s` (measures 0.73 s vs 0.71 s; the regression it guards was about 30x).
- **V5.** `waitOrFail(gate, for:)` (60 s cap, names the AU instantiate) on all 3 waits in VerifyAUGraph.

## Evidence (real exit codes)
- `scripts/gate/run.sh --step main-thread-stall --step verify-library-store --step verify-au-graph --step store-asan` -> exit 0, all PASS (final run: stall 6 s, au-graph 6 s, library-store 14 s, store-asan 31 s). Log: `testrig/c2-gate2.log`.
- `make main-thread-stall` -> exit 0. `swift run VerifyLibraryStore` / `VerifyAUGraph` are exactly the gate steps for `verify-library-store` / `verify-au-graph` (the registry commands) and passed there.
- Library store checks: **162/162** before and after. No check added or removed.
- CI-like stress, 5 rounds: 14 CPU hogs (trap cleanup; 0 hogs left afterwards) plus `LIBDISPATCH_COOPERATIVE_POOL_STRICT=1`; each round runs the 4 stall modes, VerifyAUGraph and VerifyLibraryStore. 30/30 exit 0, `STRESS_DONE failures=0`, library store 162/162 each round. `testrig/c2-stress2.out`. (Before the strict fix the library store failed 5/5 under strict, see Findings.)
- `swift build`: 0 warnings (also the clean `--build-tests --enable-index-store` build). SwiftLint `--strict` on all 15 changed files: exit 0. SwiftFormat `--lint --config .swiftformat` on them: 0 of 15 need formatting. Periphery 2.21.2 with the index-store recipe (after `swift package clean`): exit 0, no findings. A first Periphery run failed only because the index was stale, not on a finding.

### Mutation proofs (all reverted; scripts in `testrig/c2-mut*.sh`, outputs `c2-mut*.out`)
| hazard | mutation | result |
|---|---|---|
| V6 stop/start | `_ = playerNodeRef?.isPlaying` (and `avEngineRef?.isRunning`) planted in `AudioEngineBridge.snapshot()`, a main-thread tick call | exit 1 for stop and start: "main finishing 20 probe rounds and 10 main-queue round trips did not finish within 20 s with the engine lock held, main was inside 'bridge.snapshot()'". ended-advance still passes (no lock held there, correct) |
| V6/V8 device-loss | same mutation | exit 1: "main was inside 'the mode=device-loss trigger'" (first run named only the holder's 40 s cap; fixed by 0b95afb: cap now begins before the trigger) |
| V7 | both defences against a replaced track's end flag removed in `AudioViewModel+TransportTick.swift` (epoch check AND `transportCommand == nil`) | exit 1: "the advance was stopped by the replaced track's end flag" (playing false). Removing only one defence still passes, correctly, because each masks the other |
| V1 | never-signalled `DispatchSemaphore.wait()` planted in check 19's progress closure (a wedged non-cooperative wait) | exit 1 in 20 s: "check 19 (l-reads-during-scan): reads-during-scan did NOT finish within 20 s, a deadlock (the watchdog thread fired...)". The old task-group deadline cannot fire here (a group waits for every child). Real strict-pool case below |
| V3 | 1.5 s CPU burn inside GC-05's measured read | exit 1: "GC-05: the read cost 1513.1 ms of CPU (tripwire 1000.0 ms)" |
| V4 | 12 s CPU burn in the shared-title pass | exit 1: "ALB-08: ... 12.7 s of CPU vs 0.67 s on 100 titles" |
| V5 | AU instantiate completion never signals | exit 1 in 60 s: "AVAudioUnit.instantiate (AdaptiveSoundAU) did not complete within 60 s" |

## Findings
1. **Real deadlock under the strict pool, fixed.** With `LIBDISPATCH_COOPERATIVE_POOL_STRICT=1` (a one-thread pool), check 19 `reads-during-scan` parked the scanner on a semaphore inside the progress closure. The reader task then could never run, so it was a true deadlock, and the old `withDeadline` would have hung forever instead of failing. Same shape in `cancelAfterFirstBatch` (ScanEdge) and `cancelPassAfterFirstApply` (MetadataPass). Fix: no park. reads-during-scan reads `COUNT(*)` on a separate raw GRDB connection from inside the closure (scanner is mid-walk throughout; the same WAL-snapshot property). The two cancel checks cancel their own task from the closure with `withUnsafeCurrentTask { $0?.cancel() }`. They still assert `CancellationError`, the sweep skipped and the orphan surviving, so they are not vacuous. 162/162 pass strict and plain.
2. ALB-08 leaked a second sqlite fixture per run into `test-data/` (never cleaned). Now cleaned.
3. Pre-commit hook note: it passed commits that had SwiftLint warnings (it only blocks errors); the gate's `--strict` would not. I fixed all of them; flagging so nobody trusts the hook alone.

## NOT done / limits
- `FolderWatch` `--fsevents-smoke` has `Task.sleep` polling. It is a manual founder subcommand, never in the gate, so left alone.
- The reads-during-scan read is a raw SQL `COUNT(*)` on a second connection, not a second `LibraryStore` instance (the store API is async and cannot run while the one pool thread is held). The final count is still read through the real store.
- "Instruments/leaks" and the full 45-minute `make strict-gate` were not run (rules: run only touched parts).
- Mutation proofs touch product files temporarily (`AudioEngineBridge.swift`, `AudioViewModel+TransportTick.swift`); reverted, nothing committed.

## Requests for other lanes
- None needed. I used only `tickTransport()` and public bridge/view-model members that already exist. Lane C's seams (injected ticker, Clock, WorkTracker) are not required. If Lane C changes `AudioViewModel.tickTransport` / `transportCommand` / `bridge.snapshot()` / `gaplessPlaybackEnded` / `transportEpoch`, the ended-advance mode depends on those, so re-run `make main-thread-stall` after combining.
- Coordinator: when combining, `Sources/AdaptiveSound/Debug/MainThreadStall*.swift` is mine only; no overlap with C expected.

## Open questions for the founder
1. Recommendation: keep the strict-pool profile (`LIBDISPATCH_COOPERATIVE_POOL_STRICT=1`) as a standing stress run for ALL verifier executables. It found a real deadlock that nothing else would. It costs nothing extra (the checks finish in the same time).
2. Recommendation: leave the hang caps at 20 s (stall, library store phases) and 60 s (AU instantiate). They are 100x above normal and only break hangs. A failing mutation takes 20 s to report, which is fine.
