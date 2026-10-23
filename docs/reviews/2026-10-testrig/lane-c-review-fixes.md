# Lane C: review fixes L4–L7 (Swift rig)

Branch `testrig/swift-rig-review` (worktree `.claude/worktrees/testrig-c`), off `testrig/integration`. Tests/ and RigKit only; no product change. No push.
Tools: `scripts/toolchain/install.sh` then `export PATH="~/.cache/adaptivesound-toolchain/e3138429f70c84aa/bin:$PATH"` (the first run with an older install failed parity; re-running install fixed it).

## Commits
- `fix(test-rig): Hold's cap is suspend-aware, the log ring is O(1), the UXLOG test swaps nothing, the default ticker has a test, the quiescence heuristic is explained (L4-L7)`
- `test(rig): the default ticker's timer is checked in the run loop's common modes; RIG-11 fails naming the cap if Hold's never fires`
- `style: line length in the default-ticker test`

## Per item
**L4, `OnDeckRig.runViewModelOut`: documented, not replaced. No exact witness exists without a product change.**
- A positive witness would be "every in-flight task is suspended in a call the engine owes", but `WorkTracker` exposes only `isIdle`, and tracked tasks also wait on other tracked tasks (the start awaits the on-deck request), so `owedCallers` alone cannot be compared with a count.
- I checked whether the heuristic is load-bearing: mutating its threshold from 3 stable rounds to 0 made **no** test fail (33 OnDeck/Transport/QueueEdit contract and explorer tests passed). Every verdict is read from `quiesce`'s end-state `until` (work idle, engine idle, everything received). The heuristic only decides how soon the rig stops yielding so the next scripted step can run, which is what makes a seeded schedule replay the same way.
- The doc comment on `runViewModelOut` now says this. **Product request:** make `WorkTracker`'s count readable (`private(set) var inFlight`, read by `isIdle`, so Periphery stays quiet). Then `runViewModelOut` becomes `inFlight == engine.owedCallers + (tasks awaiting a tracked task)`, or the tracker can count "suspended" itself.

**L5, `Hold.wait`: made suspend-aware.**
- The cap is judged on `SuspendingClock` between one-second `NSCondition` slices (`NSCondition` only accepts a wall-clock `Date`), as `until` does.
- Proof: RIG-11 now waits on the hold's own `hasExpired` flag with a 20 s cap (before, it awaited the blocked producer, so a broken cap just hung). Mutation: cap + 100,000 s fails RIG-11 after 20 s ("Known issue was not recorded" / the until names "the producer to give up at its cap").
- Not simulated: a real Mac sleep; the clock choice is the same one `until` was fixed with after the analyzer stress run.

**L6, the log ring.**
- UXLOG-01 no longer swaps the process-wide sink: it installs the quiet sink (idempotent) and counts lines arriving through `LogTail.totalAppended`. Other tests' tails are never lost to it. The old swap-and-restore is gone.
- UXLOG-02 round-trips a `UXLog.Sink` through a local `Mutex` 100,000 times (the access pattern that wrapped itself before).
- `LogTail` is a fixed ring with `next` and a `totalAppended` count: O(1) per line (was `removeFirst` O(capacity) once full). RIG-12 now also checks the count. Mutation: a ring that does not count fails RIG-12 (the `last` and count expectations).
- Not re-proved: the original SIGBUS mutation (a bare closure in the `Mutex`) was proven in the first pass; UXLOG-01 still runs 200,000 lines through the real `logUX`.

**L7, `RunLoopTicker` test.** A test existed (`runLoopTickerFiresAndStops`: fires, stop invalidates), but not for the production seam. Added `defaultTickerIsACommonModeTimer`:
- builds the VM with its default maker, plays, and requires the ticker to be a `RunLoopTicker` at 20 Hz;
- asserts `CFRunLoopContainsTimer(main, timer, .commonModes)`, and that a tick reads the engine through `untilOnMainRunLoop`.
- First attempt (spin only `.eventTracking`) did not catch the mutation: the test's own yields run the loop in its default mode. I replaced it with the common-modes check, and removed the unused `mode:` parameter I had added to `untilOnMainRunLoop`.
- Mutation: `RunLoopTicker` adding its timer in `.default` fails the new test (`CFRunLoopContainsTimer` false).

## Evidence
- `scripts/gate/run.sh --tier check`: **exit 0** (21 steps: swiftformat, swiftlint, semgrep and its rule tests, timelimit-guard, swift-build, swift-test 944, swift-test-rig 21 all PASS).
- `make stress N=10` (CI-like profile) over every suite I touched or that uses Hold/LogTail: RigKit, OffPoolExecutor, LogTailAttachment, LiveReadouts, UXLogSink, OnDeck (contract and explorer), Transport (contract and explorer), QueueEdit, TrackLoudnessAnalyzer, LibraryScanRaceG, TransportSnapshot: **10/10 passed, exit 0**.

## Slip I made and fixed
While running mutations I ran `git checkout <file>` on RigKit files before committing, which discarded the uncommitted L5/L6 edits; I re-applied them and committed before any further mutation. Nothing was lost from history.
