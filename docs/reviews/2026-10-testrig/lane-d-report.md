# Lane D report: one FakeEngine, no mirrors

Branch `testrig/fake-engine` (worktree `.claude/worktrees/testrig-d`), **rebased onto `testrig/integration` @ 99f046f**
(the gate wiring; it touches none of my files, and it gives the periphery step its own index build). 6 commits,
no push, no Co-Authored-By. **No product source changed**: every planted bug was reverted; `git diff -- Sources/` is
empty (checked after the founder's pause, when one plant, P14 in `AudioViewModel+AutoAdvance.swift`, was still in
place — reverted first thing, and the P14…P42 run was redone from the start of P14).

## Commits
```
0b90c7d test(rig): one engine double — FakeEngine (DeviceTestEngine promoted) …; OnDeckEngineModel composes it; the OnDeck rig ticks through TickerBench
c248fee test(view-model): the mirror's … cases, rewritten on the real AudioViewModel — 48 tests over the OnDeck Rig and a FakeEngine player
2473f8a docs(testing): one engine double, no mirrors …
e06a66a test(view-model): VM-AA-06 checks the stop is asked in the turn the playing song is removed … (found by the mutation run)
efef4d2 test(rig): the mirrors are gone … the target that held them is PlaybackQueueKitTests
b19a72a test(rig): the shell toast's lifetime on an injected clock … (optional UI-clock item)
```
46 files, +1488 −2121 (before the report).

## What changed
1. **`FakeEngine`** (`Tests/AdaptiveSoundTests/FakeEngine.swift`, `DeviceTestEngine` promoted). Inputs in
   `engine.state`: devices, the whole `EngineSnapshot` (transport, signal path, loudness, EQ design rate), spectrum
   frames, each call's outcome (`initializeResult`/`initializeError`, `startError`, `selectResult`). The record:
   `calls`, every command in order (`Call` enum), with the per-kind views the existing suites read (`starts`,
   `stops`, `picks`, `masterGains`, …, plus `startedURLs`, `nextTracks`) derived from it. **No logic**: the user's
   output choice — which `DeviceTestEngine` re-implemented — is the product's own `OutputDeviceSelection`
   (`selectDevice` → `choose`, the pin → `pin`, a restore → `restoreChoice`, the engine moving → `adopt`).
   The stray `setNextTrack(_:)` is gone; the real `setNextTrack(_:ticket:)` is recorded (before, the protocol's
   no-op default answered every on-deck request a recording-engine test made). All 8 users moved (rename only;
   their assertions unchanged).
2. **`OnDeckEngineModel` composes it** (`engine.fake`): it keeps only the scripted transport and on-deck state
   machine; lifecycle, devices, levels, DSP, spectrum and the rest of the snapshot are forwarded to the fake (an
   extension, so the type body stays under SwiftLint's limit). The no-op block is gone. New read: `playsPure`.
3. **The `Rig` fires its tick through `TickerBench`**: the view model's tick is armed as at engine-ready and
   `rig.tick()` fires the current ticker, so a tick happens only when the app's would (something plays, or a
   command is on its way). All 35 OnDeck/Transport contract and explorer tests pass unchanged on it.
4. **`FakePlayer`** (`FakePlayer.swift`): the real view model over `FakeEngine`, launched through
   `initializeEngine`, ticked through `TickerBench`, `engineReports(position:transitionCount:ended:)` stamps the
   newest request's epoch. For what the view model does with what the engine reports (a +2 seam count, a lagging
   playhead, a lost device, a refused call) — inputs no single-slot engine model produces.
5. **48 real-view-model tests** replace the 68 mirror tests: `AutoAdvanceTests` (9), `ManualSkipTests` (4),
   `SeamAdvanceTests` (4), `TrackEndTests` (7), `QueueVerbTests` (12), `PlayTrackTests` (4),
   `EngineLifecycleTests` (8). Waits: RigKit `until`, the rigs' `settle`/`quiesce`/`runViewModelOut`
   (`owedCallers`), `AudioViewModel.settled()` (WorkTracker). No new `settle()` copies, no yield counts, no sleeps.
6. **Deleted**: `MockAudioEngine.swift`, `MockAdvanceController.swift`, `AudioEngineProtocolTests.swift`, the four
   `AutoAdvance*Tests.swift`, the `AutoAdvanceTests.swift` index, `QueueOpsTests.swift`, and `AudioViewModelTests.swift`
   (`MockPlaylistController`, a copy of `playTrack(at:)` — a mirror too, so it went with the rest).
7. **`Package.swift`** (test membership only): `AudioViewModelTests` → **`PlaybackQueueKitTests`**
   (`git mv`, history kept). Once the mirrors were gone it held only PlaybackQueueKit tests (87); folding them into
   `AdaptiveSoundTests` would link the app into Kit tests, so it is named like the other Kits' test targets. The
   shuffle stand-in it shared with the mirror moved to `DeterministicPick.swift`. `AdaptiveSoundTests` declares
   `OutputDeviceKit` (FakeEngine imports it). No script, workflow or gate row named the old target.
8. **Optional item**: `ShellToastSlotTests` (3) on `ImmediateClock` / `TestClock`, no product change.
9. **Docs** (outside my listed files; one commit the coordinator can keep or drop): `testing.md` gains "One engine
   double, no mirrors"; `DEVELOPMENT.md` and `validation-strategy.md` stop naming the deleted files/target.
10. `SheetEngine` stays in `Sources/AdaptiveSound/Debug`; no test references it (grep).

## Evidence (pinned PATH `…/9878b9390ce38c3a/bin`; every exit code read, never through a pipe)
- `scripts/gate/run.sh --tier check`: **GATE PASSED, 17/17, exit 0** — toolchain-parity, swiftformat (698 files),
  swiftlint (698), clang-format, semgrep (789 files; `test-no-raw-time` included, zero suppressions),
  semgrep-rule-tests, suppressions, 3 postures, cppcheck, clang-tidy, actionlint, swift-build, deployment-target,
  **swift-test 942 tests** + **swift-test-rig 21 tests** = **963**.
- `scripts/gate/run.sh --step periphery`: **exit 0, "No unused code detected."** (its own index build, b82bea1).
- `make stress … N=10` (CI-like: ncpu−3 hogs in their own process groups, killed by the script's trap; strict
  pool width 1), one `make stress` per suite, each exit 0:
  `AutoAdvanceTests` 10/10, `ManualSkipTests` 10/10, `SeamAdvanceTests` 10/10, `TrackEndTests` 10/10,
  `QueueVerbTests` 10/10, `PlayTrackTests` 10/10, `EngineLifecycleTests` 10/10, `ShellToastSlotTests` 10/10.
  Then the suites whose rig or double changed, together (the five OnDeck/Transport contract and explorer suites,
  the seven FakeEngine users, and `PlaybackQueueKitTests`): 10/10, exit 0 (each iteration 87 + 73 tests).
  11 hogs per run; `pgrep -x yes` empty afterwards. Logs: `scratchpad/testrig/laned/stress/`.
- Builds: `swift build --build-tests` exit 0 with warnings as errors, after every commit.
- SwiftFormat + SwiftLint `--strict` clean on every changed file by explicit path (the worktree trap), and in the gate.

### The QA bar: every rewritten test seen failing against a planted bug in the real view model
A runner (`scratchpad/testrig/laned/plants/run.py`, table `plants.py`) applied one plant at a time to the product
source, built, ran each targeted test by its own `--filter 'AdaptiveSoundTests\.Type/function\('`, recorded the exit
code, and restored the file from git (try/finally, then a check that `Sources/` is clean). Logs per plant and test
are in `scratchpad/testrig/laned/plants/logs/`. **All 48 rewritten tests and the 3 toast tests fail against at least
one plant, and pass on the real code.** 47 plants:

| Plant (P: the view model, `AudioViewModel*.swift`; T: `ShellToast.swift`) | Tests run against it |
|---|---|
| P01-playtrack-starts-before-selecting | `playTrackStartsThatSong` FAILED (exit 1) |
| P02-playtrack-no-range-guard | `anIndexPastTheQueueIsIgnored` FAILED (exit 1); `anEmptyQueueStartsNothing` FAILED (exit 1) |
| P03-replaced-start-still-primes | `aSecondPlayTrackReplacesTheFirst` FAILED (exit 1) |
| P04-end-of-queue-flags-only | `oneSongStopsAtItsEnd` FAILED (exit 1); `lastSongStopsAndStaysSelected` FAILED (exit 1) |
| P05-seam-keeps-the-old-playhead | `seamAdvancesToTheArmedSong` FAILED (exit 1); `aSeamAfterASeekStartsAtTheTop` FAILED (exit 1) |
| P06-repeat-all-ignored | `repeatAllWrapsToTheFirstSong` FAILED (exit 1); `nextOnTheLastSong` FAILED (exit 1) |
| P07-auto-advance-steps-under-repeat-one | `repeatOneReplaysTheSameSong` FAILED (exit 1) |
| P08-failed-start-taken-in-silently | `aStartThatFailsSaysSoAndStops` FAILED (exit 1) |
| P09-shuffle-picks-the-song-playing | `shuffleNeverRepeatsTheSongThatEnded` FAILED (exit 1); `shuffleSkipsToAnotherSong` FAILED (exit 1) |
| P10-seam-baseline-not-kept | `aSeamIsTakenOnce` PASSED (exit 0); `aCountThatJumpsByTwoAdvancesOnce` FAILED (exit 1) |
| P10b-seam-baseline-dropped | `aSeamIsTakenOnce` FAILED (exit 1) |
| P11-start-on-the-other-path | `theAdvancePlaysOnThePathAsked` FAILED (exit 1) |
| P12-manual-next-repeats-under-repeat-one | `nextUnderRepeatOneSteps` FAILED (exit 1) |
| P13-manual-next-always-wraps | `nextOnTheLastSong` FAILED (exit 1) |
| P14-previous-wraps-the-wrong-way-round | `previousSteps` FAILED (exit 1) |
| P15-seam-keeps-the-old-length | `theLengthIsZeroedThenReadForTheNewSong` FAILED (exit 1) |
| P16-seam-recomputes-instead-of-following-the-arm | `aSeamGoesToTheArmedSlotWithoutAStart` FAILED (exit 1) |
| P17-tick-acts-on-a-stale-end-during-a-start | `anEndWithASongQueuedAdvancesOnce` FAILED (exit 1) |
| P18-no-epoch-gate | `aLaggingPlayheadNeverMovesTheScrubberBack` FAILED (exit 1) |
| P19-an-end-always-stops-KI-001 | `aSongThatEndsBeforeItsNextIsArmedGoesOn` FAILED (exit 1); `anEndWithASongQueuedAdvancesOnce` FAILED (exit 1) |
| P20-removing-the-playing-song-does-not-stop | `removingThePlayingSongStops` FAILED (exit 1) |
| P21-clear-does-not-stop | `clearingTheQueueStopsAndClearsEverything` FAILED (exit 1) |
| P22-device-loss-keeps-the-deck | `aLostDevicePausesInPlace` FAILED (exit 1) |
| P23-remove-does-not-rearm | `removingTheOnDeckSongArmsTheNext` FAILED (exit 1) |
| P24-play-now-appends | `playNowReplacesTheQueueAndPlays` FAILED (exit 1) |
| P25-edit-always-rearms | `anAppendMidQueueLeavesTheDeck` FAILED (exit 1); `anAppendUnderShuffleKeepsThePick` FAILED (exit 1) |
| P26-append-keeps-no-deck | `anAppendAtTheEndArmsTheFirstAddedSong` FAILED (exit 1) |
| P27-edit-arms-while-stopped | `anAppendWhileStoppedOnlyQueues` FAILED (exit 1) |
| P28-play-next-goes-to-the-end | `playNextInsertsAfterTheSongAndArmsIt` FAILED (exit 1); `playNextBeatsShuffle` FAILED (exit 1); `playNextWhilePausedInsertsUnarmed` FAILED (exit 1) |
| P29-play-next-never-arms | `playNextBeatsShuffle` FAILED (exit 1); `playNextOnTheLastSongArmsIt` FAILED (exit 1); `playNextInsertsAfterTheSongAndArmsIt` FAILED (exit 1) |
| P30-play-next-with-nothing-selected-goes-first | `playNextWithNothingSelectedAppends` FAILED (exit 1) |
| P31-play-next-arms-while-paused | `playNextWhilePausedInsertsUnarmed` FAILED (exit 1) |
| P32-play-next-takes-nothing-as-an-edit | `emptyInputChangesNothing` FAILED (exit 1) |
| P33-append-dedupes-again-S9 | `theVerbsReturnTheSlotsAdded` FAILED (exit 1) |
| P34-devices-not-listed | `aLaunchListsTheDevices` FAILED (exit 1) |
| P35-no-devices-is-a-failed-launch | `aLaunchWithNoDeviceShowsNone` FAILED (exit 1) |
| P36-a-refused-engine-taken-as-ready | `anEngineThatWillNotStart` FAILED (exit 1) |
| P37-init-guard-stays-latched | `anEngineThatWillNotStart` FAILED (exit 1); `anEngineThatThrowsAtStart` FAILED (exit 1) |
| P38-a-throwing-engine-says-nothing | `anEngineThatThrowsAtStart` FAILED (exit 1) |
| P39-a-refused-pick-taken-as-done | `aRefusedPickSaysSo` FAILED (exit 1) |
| P40-eq-always-on | `theEQGoesToTheEngine` FAILED (exit 1) |
| P41-eq-rate-never-follows | `theEQDesignRateFollowsTheEngine` FAILED (exit 1) |
| P42-shutdown-tears-down-before-the-stop | `shutdownStopsBeforeTearingDown` FAILED (exit 1) |
| T01-toast-never-clears | `aToastClearsItself` FAILED (exit 1) |
| T02-same-message-same-toast | `aReRaiseIsANewToast` FAILED (exit 1) |
| T03-dismiss-leaves-the-toast | `aReRaiseIsANewToast` FAILED (exit 1) |
| T04-superseded-timer-clears-the-newer-message | `aSupersededTimerNeverClearsTheNewerMessage` FAILED (exit 1) |

Notes on the run:
- **P10** (`lastTransitionCount += 1` instead of `= currentCount`) is the real code for a one-step seam, so
  `aSeamIsTakenOnce` rightly passes it; `aCountThatJumpsByTwoAdvancesOnce` catches it, and P10b (the baseline
  dropped) is the plant `aSeamIsTakenOnce` catches.
- **P20 first escaped**: with `removeTrack`'s stop deleted, `removingThePlayingSongStops` still passed, because the
  seam's stale on-deck index (2, past the shortened queue) sent the view model down "out of range, stopping". The
  test now checks the stop is asked in the turn of the removal and that no seam is taken while it waits (e06a66a);
  rerun: FAILED (exit 1) against P20, passes on the real code.
- P23 and P26 first did not build (an unused `armed` is an error under warnings-as-errors); replanted with
  `_ = armed`, both caught.
- P01 is the original `playTrack(at:)` bug the mirror guarded: the engine started the stale `t0` for index 2 and 4.

## Coverage map: every deleted mirror test → the real-view-model test that covers it

68 tests deleted (the brief's "about 61" counted 26 + 15 + 20; the 8 `MockPlaylistController` tests in
`AudioViewModelTests.swift` were a mirror too, so they go with the rest). New suites are in
`Tests/AdaptiveSoundTests/`; "existing" means a suite that already drove the real view model.

### `AutoAdvanceLinearRepeatShuffleTests.swift` (14)
| Mirror test | Real-view-model test |
|---|---|
| VM-AA-01 singleTrackNoRepeatStops | `AutoAdvanceTests.oneSongStopsAtItsEnd` (Pure + Enhanced) |
| VM-AA-02 midPlaylistAdvanceSetsIndex | `AutoAdvanceTests.seamAdvancesToTheArmedSong` (Pure + Enhanced) |
| VM-AA-03 endOfLastNoRepeatStops | `AutoAdvanceTests.lastSongStopsAndStaysSelected` (Pure + Enhanced) |
| VM-AA-04 endOfLastRepeatAllWraps | `AutoAdvanceTests.repeatAllWrapsToTheFirstSong` (Pure + Enhanced) |
| VM-AA-05 repeatOneReplays | `AutoAdvanceTests.repeatOneReplaysTheSameSong` (Pure + Enhanced) |
| VM-AA-08 userInitiatedReplayStartAudioThrows | `AutoAdvanceTests.aStartThatFailsSaysSoAndStops` |
| VM-AA-09 shuffleVisitsMultipleIndices | `AutoAdvanceTests.shuffleNeverRepeatsTheSongThatEnded` |
| VM-AA-10 doubleFireGuard | `AutoAdvanceTests.aSeamIsTakenOnce` |
| VM-AA-11 pureModePassedThroughOnAdvance | `AutoAdvanceTests.theAdvancePlaysOnThePathAsked(pure: true)` |
| VM-AA-12 pureModeOffPreserved | `AutoAdvanceTests.theAdvancePlaysOnThePathAsked(pure: false)` |
| VM-AA-13 manualNextRepeatOneSteps | `ManualSkipTests.nextUnderRepeatOneSteps` |
| VM-AA-14 manualNextEndBehaviour | `ManualSkipTests.nextOnTheLastSong` (repeat all, none) |
| VM-AA-15 manualPreviousWrap | `ManualSkipTests.previousSteps` (repeat all, none) |
| VM-AA-16 manualSkipShufflePicksOther | `ManualSkipTests.shuffleSkipsToAnotherSong` |

VM-AA-13…16 called the mirror's `computeNextIndex`/`computePreviousIndex`, which only delegated to
`QueueAdvance` — they duplicated `QueueAdvanceTests` (VM-QA, kept). The rewrite presses the real Next and
Previous, so the verbs' own guards (nowhere to go → no command) are covered too.

### `AutoAdvanceGaplessSeamTests.swift` (5)
| Mirror test | Real-view-model test |
|---|---|
| VM-AA-14 seekDuringAdvanceIsConsistent | `SeamAdvanceTests.aSeamAfterASeekStartsAtTheTop` (a real seek, through the engine) |
| VM-AA-15 positionResetsOnAdvance | same test, and `AutoAdvanceTests.seamAdvancesToTheArmedSong` |
| VM-AA-16 durationZeroedBeforeRefresh | `SeamAdvanceTests.theLengthIsZeroedThenReadForTheNewSong` — now also proves the refresh reads the new song's file (a real fixture); the mirror could not |
| VM-AA-17 selectedTrackIndexSetBeforeStartPlayback | `SeamAdvanceTests.aSeamGoesToTheArmedSlotWithoutAStart` |
| VM-AA-19 transitionCountJumpByTwoAdvancesOnce | `SeamAdvanceTests.aCountThatJumpsByTwoAdvancesOnce` (FakeEngine input) |

### `AutoAdvanceReconfigureGapTests.swift` (3)
| Mirror test | Real-view-model test |
|---|---|
| VM-AA-RGAP-1 reconfigureGapAdvanceFiresOnce | `TrackEndTests.anEndWithASongQueuedAdvancesOnce` |
| VM-AA-RGAP-2 laggingSnapshotIgnored | `TrackEndTests.aLaggingPlayheadNeverMovesTheScrubberBack` |
| VM-AA-RTR-1 trackEndsBeforeSeamlessSeamAdvances | `TrackEndTests.aSongThatEndsBeforeItsNextIsArmedGoesOn` |

RTR-1's first half asserted `MockAudioEngine.simulateTrackEnd()`'s own branch: the mock agreeing with itself.

### `AutoAdvanceDeviceLossTests.swift` (4)
| Mirror test | Real-view-model test |
|---|---|
| VM-AA-06 removeCurrentTrackStops | `TrackEndTests.removingThePlayingSongStops` (with a seam that lands while the stop waits) |
| VM-AA-07 clearPlaylistMidPlay | `TrackEndTests.clearingTheQueueStopsAndClearsEverything` |
| VM-AA-13 deviceLossInterruptClearsOnDeck | `TrackEndTests.aLostDevicePausesInPlace` |
| VM-AA-18 removeOnDeckTrackReprimesEngine | `TrackEndTests.removingTheOnDeckSongArmsTheNext` |

**VM-AA-13 (device loss) only proved the mirror agreed with itself:** the test set `pendingNextIndex = nil`
and `isPlaying = false` by hand ("mirrors the signalPath.interrupted branch"), then asserted they were nil
and false. No code under test ran. Council panel N93 had noted the view model's branch was untested; it is
now (`signalPath.interrupted` from the engine → paused in place, the deck dropped and the engine told).

### `QueueOpsTests.swift` (15)
| Mirror test | Real-view-model test |
|---|---|
| VM-Q-01 playNowReplacesAndPlays | `QueueVerbTests.playNowReplacesTheQueueAndPlays` |
| VM-Q-02 appendMidListLeavesOnDeck | `QueueVerbTests.anAppendMidQueueLeavesTheDeck` |
| VM-Q-03 appendAtEndArms | `QueueVerbTests.anAppendAtTheEndArmsTheFirstAddedSong` |
| VM-Q-04 appendUnderShuffleNoReRoll | `QueueVerbTests.anAppendUnderShuffleKeepsThePick` |
| VM-Q-05 appendWhileStopped | `QueueVerbTests.anAppendWhileStoppedOnlyQueues` |
| VM-Q-06 playNextInsertsAndArms | `QueueVerbTests.playNextInsertsAfterTheSongAndArmsIt` |
| VM-Q-07 playNextOverridesShuffle | `QueueVerbTests.playNextBeatsShuffle` |
| VM-Q-08 playNextWhileStoppedAppends | `QueueVerbTests.playNextWithNothingSelectedAppends` |
| VM-Q-09 playNextPausedInsertsAfterCurrent | `QueueVerbTests.playNextWhilePausedInsertsUnarmed` (a real pause) |
| VM-Q-10 playNextAtLastTrack | `QueueVerbTests.playNextOnTheLastSongArmsIt` |
| VM-Q-11 dedupeOnAdd | **DRIFT — the app has no such behaviour.** Replaced by `QueueVerbTests.theVerbsReturnTheSlotsAdded` (what ships) |
| VM-Q-12 emptyInputNoOp | `QueueVerbTests.emptyInputChangesNothing` |
| VM-Q-13 returnsPostDedupCount | **DRIFT.** → `theVerbsReturnTheSlotsAdded` |
| VM-Q-14 returnsZeroWhenNothingAdded | **DRIFT** for the all-duplicates half → `theVerbsReturnTheSlotsAdded`; the empty half → `emptyInputChangesNothing` |
| VM-Q-15 multiAddTrueCount | **DRIFT** (within-batch dedupe) → `theVerbsReturnTheSlotsAdded` |

### `AudioViewModelTests.swift` — the `MockPlaylistController` copy of `playTrack(at:)` (8)
| Mirror test | Real-view-model test |
|---|---|
| playTrackSelectsCorrectTrack | `PlayTrackTests.playTrackStartsThatSong(index: 2)` |
| playTrackTriggersStartPlayback | `PlayTrackTests.playTrackStartsThatSong` (exactly one start, every case) |
| startPlaybackSeesUpdatedIndex | `PlayTrackTests.playTrackStartsThatSong` (a stale selection is set first) |
| playTrackIgnoresOutOfBoundsIndex | `PlayTrackTests.anIndexPastTheQueueIsIgnored(index: 99)` |
| playTrackOnEmptyPlaylist | `PlayTrackTests.anEmptyQueueStartsNothing` |
| playTrackAtLastValidIndex | `PlayTrackTests.playTrackStartsThatSong(index: 4)` |
| playTrackAtExactCountIsRejected | `PlayTrackTests.anIndexPastTheQueueIsIgnored(index: 5)` |
| playTrackOverwritesPreviousSelection | `PlayTrackTests.aSecondPlayTrackReplacesTheFirst` |

### `AudioEngineProtocolTests.swift` (19)
`MockAudioEngine — protocol contract` (16) called a mock of a *mirror* protocol and read the mock's own
counters: none of them ran app code. Each now maps to where the real view model's use of that member is
tested:
| Mirror test | Real-view-model test |
|---|---|
| initializeSuccess | `EngineLifecycleTests.aLaunchListsTheDevices` (and every `FakePlayer.launched`) |
| initializeFailure | `EngineLifecycleTests.anEngineThatWillNotStart` |
| initializeError | `EngineLifecycleTests.anEngineThatThrowsAtStart` |
| enumerateDevicesReturnsConfiguredList | `EngineLifecycleTests.aLaunchListsTheDevices` |
| enumerateDevicesCallCounter | none needed: it counted the mock's calls. The view model's re-read on a device change: existing `OutputDeviceViewModelTests.lostDeviceIsNeverPicked` |
| enumerateDevicesEmpty | `EngineLifecycleTests.aLaunchWithNoDeviceShowsNone` |
| selectDeviceForwardsID | existing `OutputDeviceViewModelTests.menuPickIsAPick` |
| selectDeviceFailure | `EngineLifecycleTests.aRefusedPickSaysSo` |
| startAudioRecordsURL | `PlayTrackTests.playTrackStartsThatSong` |
| stopAudioCallCounter | existing `ListeningSettingsTests.pauseIsNotAStop`; `TrackEndTests.clearingTheQueueStopsAndClearsEverything` |
| publishMasterGainCapturesLevel | existing `ListeningSettingsTests.pureIsAskedForAtAnyLevel` |
| publishEQCapturesArgs | `EngineLifecycleTests.theEQGoesToTheEngine` |
| eqSampleRateDefaultsToGraphRate | `EngineLifecycleTests.theEQDesignRateFollowsTheEngine`. (Drift: the protocol has no `eqSampleRate()` any more; the rate is in `EngineSnapshot.eqDesignRate`.) |
| readSpectrumNullCase | none needed: the mock's own stub. The real reader is driven by existing `LiveReadoutsTests` |
| readSpectrumWithData | existing `LiveReadoutsTests.pausedLensShowsTheLatestFrame` |
| shutdownCallCounter | `EngineLifecycleTests.shutdownStopsBeforeTearingDown` (now the P2-C order: stop, then teardown) |

`AudioEngineBridge — device sort order contract` (3: builtinBeforeWireless, alphabeticalWithinType,
unknownTypeSortsLast) sorted with **a copy of the comparator written in the test file**. They never ran the
bridge's sort, which is inline in `AudioEngineBridge.enumerateOutputDevices()` behind a C call on
`engineQueue`, with a `private` `sortOrder`. **No real test is possible without a product seam** (request
below); until then the order is untested, as it was before.

### Count
980 before. −68 mirror tests, +48 real-view-model tests (some cases merged as arguments: VM-AA-11/12, the
eight playTrack tests into four, VM-Q-11/13/14/15 into one), +3 `ShellToastSlotTests` (the optional UI-clock
item) = **963**. The renamed `PlaybackQueueKitTests` keeps its 87.


## Findings: where the mirror drifted from the app (behaviour the real view model does NOT have)
1. **Dedupe on add (VM-Q-11, 13, 14, 15).** The mirror dropped songs already queued and returned the post-dedup
   count (S9, OD-2). The app retired that in S10.2: a slot is a `QueueItem` with its own UUID, the same song may be
   queued twice, and `appendToQueue`/`playNext` return `tracks.count`. Four tests proved a contract the app no longer
   has. Knock-on: `QueueToastDecision`'s `case 0: "Already in Queue"` ("every input was already queued") is now
   reachable only by an empty add, which every caller keeps silent — dead copy (question 1).
2. **The end of the queue (VM-AA-01, 03).** The mirror stopped by flipping flags (`isPlaying = false`,
   `playbackPosition = 0`) — the S10.8 G bug the app fixed (the engine kept playing behind a stopped footer). Plant
   P04 puts exactly the mirror's behaviour into the real view model; the new tests fail on it.
3. **Device loss (VM-AA-13)** ran no code at all (the test set the fields it then asserted). Now tested on the real
   tick (council panel N93 had flagged it untested).
4. **The start and the commands.** The mirror marked playing the moment a start was asked and keyed the tick, Play
   Next, appends and removals on `isPlaying`; the app marks playing only after the prime's request settled (F-P4-1)
   and keys on `transportCommand` / `playIntent` / `onDeckIsLive` (C-15, C-17).
5. **Removing a row.** The mirror re-derived the next song with `computeNextIndex` only when the armed row went;
   the app applies `PlaybackOrder.onDeck(afterEditing:)` after every edit (C-17).
6. **The protocol.** `AudioPlaybackEngineMirror` kept `currentPlaybackPosition()`, `trackTransitionCount()`,
   `playbackEnded()`, `eqSampleRate()`, `setNextTrack(_:)` with no ticket, `startAudio` with no epoch or start
   position — none of them in the live protocol.
7. **The device sort (3 tests)** sorted with a comparator copied into the test; the bridge's sort never ran.

Also seen, not a bug: at init the view model publishes the settings it restored (Master Gain, crossfeed, the pin)
before `initialize()`; the engine ignores them until it is up and gets them again at engine-ready
(`publishPlaybackIntents`). My first launch test assumed `initialize` came first; FakeEngine's ordered record showed
otherwise and the test was corrected, not the code.

## Not done, and why
- **EQBringBackMessage and SongsView clock tests.** Their clock logic lives in private SwiftUI view methods driven by
  `.task` (`EQBringBackMessage.run`/`sleepOut`, `@State` remaining time); testing them needs view hosting or the
  countdown moved into a small model like `ShellToastSlot` — a product change (request 2). ShellToastSlot is done.
- **The device sort order**: untestable without a product seam (request 1). The 3 deleted tests never ran it either.
- `readSpectrumNullCase`'s "false when no frame" is not separately asserted on the real reader (it tested the mock's
  own stub); `LiveReadoutsTests` drives the real reader with frames.
- No plant for "the seam never refreshes the length" (it would only cost a 120 s cap to show; P15 covers the zeroing).

## Requests for other lanes / owners
1. **Product (AudioEngineBridge+Devices):** move the output-menu order out of the inline `models.sort` (and the
   `private` `sortOrder`) into a pure function — e.g. `OutputDeviceKit` or `AudioDeviceModel.menuOrder(_:)` — so a test
   runs the real comparator. Then the three sort cases return as real tests.
2. **Product (EQBringBackMessage, SongsView):** the countdown into an `@Observable` model with the injected clock, as
   `ShellToastSlot` already is; then the same three-test pattern applies.
3. **Product comments now stale** (not mine to edit): `PlaybackQueueKit/QueueAdvance.swift`'s header names the deleted
   `MockAdvanceController`; `AudioPlaybackEngine.swift`'s doc says "tests inject a `MockAudioEngine`" (now `FakeEngine`).
4. **Coordinator:** the docs commit (2473f8a) is outside my listed files; keep or drop it at combine. Lane D's
   commits touch no gate script; the new suites are in the main parallel step (none matches `Enhanced*`).

## Open questions for the founder (recommendation first)
1. **"Already in Queue" can no longer appear.** Since S10.2 the queue accepts a song twice, so adding a song that is
   already queued adds it and says "Added to Queue". Recommend: keep that (it is the shipped, intended behaviour) and
   remove the dead "Already in Queue" branch in a later sprint. The alternative is to bring back a "you already have
   this" message, which would be a new feature.
2. **A latent crash in `playTrack(at:)`.** A negative index passes its guard and indexes the queue at −1. No caller can
   pass one today (they pass row indices or clamped values). Recommend: add `index >= 0` to the guard the next time
   that file is touched, with a test; not urgent.
