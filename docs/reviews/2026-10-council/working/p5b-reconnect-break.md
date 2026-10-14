# P5b round 2: breaking the N92 fix (`fix/device-reconnect` @ 013faf0)

**Verdict: SHIP.** I could not break the rule. Two cheap hardening items should go in before or just after R1.

## Setup
- Worktree: `.claude/worktrees/panel-p5b`, detached at 013faf0. I did not build or edit in the owner's worktree.
- No hardware, no app launch, no default-device changes, no library access.
- I read HAL properties read-only (UIDs, stream counts, UID→id translation). Program: `exp-p5b/uids.c`.

## Attack tests
All 10 are uncommitted in `Tests/OutputDeviceKitTests/P5bOutputPolicyBreakTests.swift` (copy: `exp-p5b/tests/P5bReconnectBreakTests-round2.swift`). They are written from the founder-approved behaviour, not from the code. All 10 pass. The fix's own 35 device tests also pass in my worktree, so the full run is 45 of 45 (`exp-p5b/test-r2-all.log`).

| Attack | Result |
|---|---|
| **Property space.** 2 160 reachable cases (5 events × target {0,A,B} × alive × default {0,A,B,C} × chosen {0,A,B,C} × playback × pin). Properties: P1 loss pauses; P3/P4 idle and Pure never touch the default; P5 only the chosen device is re-asserted; P6 device 0 is never adopted or asserted; P7 pinned with the chosen device present → it is the target; P13 the pin holds the chosen device as the default while Enhanced plays or starts; P8 follow is identical to the pre-fix rule; P9 pinned on the chosen device itself is identical to the pre-fix rule; P10 pinned with the chosen device away behaves exactly as follow; P11 re-establish rule; P12 a start never pauses or restarts | **0 violations** |
| **Fixed point.** Apply each action, then replay devices / default / alive events | Settles everywhere, no loop. 63 "start with no live device" cases settle on the next event, as decided in OUTDEV-10 |
| **S1 (the panel's scenario).** A drops, comes back as the default, Play | Plays on A; the default is never moved to the speakers |
| **S2.** A returns under a NEW id, and macOS does **not** make it the default | Target = the new id; Play plays on A |
| **S3.** The user resumes on the fallback (Enhanced, not a pick), then A returns mid-play | Adopt A + re-assert A + re-establish; no pause, no loop |
| **S4.** An explicit pick of the speakers, then the headphones return as the default | The speakers stick |
| **S5.** Pure on the fallback, A returns | Adopt A, default untouched; `playbackMovesWithOutput` moves Pure |
| **S6.** Pin turned off and on while A is away | The fallback becomes the choice. This is documented: turning the switch on is a user act |
| **S7 (flapping).** 20 000 random histories: A (old or new id) and C come and go, Play / Pause, Control Center, pin on or off | **0 violations**: no fallback or 0 re-asserted; the chosen device is the target whenever present; nothing plays on a dead target; follow sits on the default; everything settles |
| **N94 rerun.** The start/monitor interleaving model, old rule vs new rule × {the default moves, the chosen device leaves, the chosen device returns} × pin (results in the next table) | **Not widened** |

N94 rerun results (bad endings / total interleavings):

| External event | Pin | Before the fix | With the fix |
|---|---|---|---|
| The default moves | on | 1 silent, 2 wrong device (of 16) | identical |
| The default moves | off | 1 silent (of 11) | identical |
| The chosen device leaves during the start | on | 1 silent (of 36) | identical |
| The chosen device leaves during the start | off | 1 silent (of 36) | identical |
| The chosen device returns during the start | on | 1 silent, 3 wrong device, 26 "not on the chosen device" (of 30) | **1 silent, 0 wrong, 0 not-chosen (of 21)** |
| The chosen device returns during the start | off | 1 silent (of 21) | identical |

- The fix is neutral or better on the window.
- The one silent interleaving in every row is the pre-existing P5B-04: a config change between `engine.start` and `intent = true`. It is still open and not in this fix's scope.

## Recommended hardening (not blocking; cheap)

**H1: "chosen present" should mean "the menu would list it" (needs hardware to confirm; effort XS).**
- `liveDevice(uid:)` (`+OutputDeviceMonitor.swift:263-282`) checks only TranslateUID and IsAlive.
- The codebase itself documents that a Bluetooth device appears mid-A2DP-handshake with **0 output streams** (`CoreAudioDevice.cpp:94,127`; `DeviceListPolicy.h:52`), and the menu hides it then.
- So in S3 (Enhanced on the fallback, AirPods reconnecting), the rule can adopt the headphones and re-assert them as the system default **before their output exists**. Then one of two things happens:
  - CoreAudio refuses: the target is A while the sound stays on B, the pill shows "No Device", and the per-output EQ falls to the shared slot. This converges when macOS switches the default.
  - CoreAudio accepts: the engine restarts on a device with no output, so "playing" goes silent.
- Before the fix this path was never taken mid-play.
- Remedy: require ≥ 1 output stream in `liveDevice` (or the `deviceListVerdict == Listed` facts). The next event (macOS switching the default, or Play) then brings A back once it is ready.

**H2: a failed pick restores the whole selection (effort XS).**
- `selectDevice` restores the whole selection on failure: `changeOutputSelection { $0 = previous }` (`+Devices.swift`).
- Between the `choose` and the restore, the rule (on `configChangeQueue`) can adopt a new target after a loss, or the main thread can toggle the pin. The restore silently undoes either.
- The window is narrow (one `selectOutputDeviceC`).
- Remedy: undo only what the pick set, and only if it is unchanged.

## Residual observations (no action needed for R1)
- **R1:** a re-initialization re-picks the current default as the choice. `retryInitialization` (Retry banner, or the self-heal on `engineNotInitialized`) runs `initializeEngine`, which runs `selectDevice(default)`. If the chosen device is away at that moment, the fallback becomes the choice and N92 reappears on that path. It is rare: only after an engine init failure or shutdown.
- **R2:** this is a founder decision, already made. "The device the app starts on counts as a pick", and the pin is on by default. So: launch on the speakers, then plug in AirPods (macOS makes them the default), then Play → the app re-asserts the speakers. This is unchanged from before the fix (OUTDEV-05/06). It is likely the most common real path, so worth the founder's eye at the walk.
- **R3:** `selectedDevice = nil` while the engine's device is gone. The pill shows "No Device", the per-output EQ falls to the shared slot, and the limiter transport is 0 until the rule moves the engine. This is transient and every reader is nil-safe (checked).
- Read-only HAL check on this Mac: BT headsets expose separate `:input` and `:output` devices with distinct UIDs. TranslateUID returns the output device, so the input half can't be mistaken for the chosen output.
