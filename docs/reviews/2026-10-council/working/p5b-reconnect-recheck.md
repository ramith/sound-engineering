# P5b round 3: recheck of the device-fix follow-up (`fix/r1-blockers` @ 1ebf323, commit 556beeb)

**Verdict: SHIP.** No code defect found. One optional copy fix: the OFF line of the switch (§6).

## Setup
- Worktree: `.claude/worktrees/panel-p5b`, detached at 1ebf323. Nothing was built in `r1-blockers`.
- Builds and tests ran under `nice`, filtered to the device suites only.
- No hardware, no app launch, no default-device changes.

## Tests
- My attack file grows to 15 tests: `Tests/OutputDeviceKitTests/P5bOutputPolicyBreakTests.swift`, archived as `exp-p5b/tests/P5bReconnectBreakTests-round3.swift`.
- Run filtered to `OutputDevice|P5bOutputPolicy`: **59 of 59 pass**. That includes the fix's own suites (`OutputDeviceChoiceTests`, and `OutputDeviceViewModelTests`, which checks that `initializeEngine` and `retryInitialization` never pick). Log: `exp-p5b/test-r3.log`.

## The six checks

**1. Launch is no choice; re-init keeps the choice.** PASS (R3-1)
- Launch on the speakers: the bridge only adopts, `chosenUID` stays `""`, and the pin defaults to on.
- Headphones connect and take the default, then Play → **plays on the headphones**, and the default is never moved back.
- If macOS does not move the default, playback stays on the speakers. That matches "follows your Mac's sound output".
- Re-init while the chosen device is away: `initialize` does `adopt(default)` only, so `chosenUID` stays A. A returns under a new id and becomes the target.
- In code: `AudioViewModel+Lifecycle` no longer calls `selectDevice`. The only remaining caller is the pill (`AudioViewModel+Devices.swift:20`).

**2. H1: alive with 0 output streams is not targeted or re-asserted.** PASS (R3-2)
- `liveDevice` now requires both alive and `isListedOutputDeviceC`. That reuses the menu's own `deviceListVerdict` via `CoreAudioDevice::isListedOutput`.
- Mid-play scenario:
  1. Enhanced is playing on the fallback.
  2. A returns with 0 output streams: no adopt, no re-assert, the default is untouched.
  3. The stream appears: nothing moves on its own.
  4. macOS switches the default → A is adopted, and playback moves there.
- Paused scenario: the next Play adopts A and puts it back as the default.
- Residual (low): no listener watches for the stream appearing. "Back once it can play" therefore waits for the next device event: macOS switching the default (the normal case for Bluetooth headphones), or Play. This is the safe side.

**3. H2: a refused pick racing a rule move keeps the rule's move.** PASS (R3-3)
- Sequence: pick A, pick C (in flight), the rule adopts B (a loss), the user flips the switch off, the system refuses C, `undo` runs.
- Result: target stays **B**, the choice goes back to A, and the switch stays off.
- With no race, the undo restores exactly what the pick replaced.
- Edge case (negligible): if the rule adopts the *same* device as the refused pick during the window, `undo` takes that adopt back too (target 43 → 41). This needs another actor to make C the default at the same instant the app's own attempt fails. The next default event re-adopts it.

**4. Earlier attacks still hold.** PASS
- Round-2 tests S1–S7.
- The 2 160-case property space. "Unpicked" is the `chosen = 0` slice, and P10 proves pinned-unpicked equals follow on every case.
- The fixed point.
- 20 000 flap histories (round 2).
- 20 000 new round-3 histories: unpicked launches, menu picks, switch toggles, outputs not ready yet, ids changing on reconnect. **0 violations**. Specifically:
  - nothing non-chosen or device 0 is ever re-asserted;
  - a ready chosen device is always the target;
  - a not-ready chosen device is never targeted;
  - nothing plays on a dead target;
  - when unpinned or unpicked, the target is the default;
  - everything settles.

**5. N94 is not widened.** PASS
- The start/monitor interleaving model gives identical results to round 2. Unpicked equals the pin-off rows (P10), and a not-ready chosen device equals the "chosen away" rows.
- Before vs after the fix:

| Event during a start | Before the fix | With the fix |
|---|---|---|
| The default moves (pin on) | 1 silent, 2 wrong device | identical |
| The chosen device leaves | 1 silent | identical |
| The chosen device returns (pin on) | 1 silent, 3 wrong device, 26 not on the chosen device | 1 silent, 0, 0 |

- The single silent interleaving is still the pre-existing P5B-04, still open and outside this fix.

**6. The settings copy for each state.** (`OutputDeviceSettingsSection.swift:40-45`)
- **ON**, quoted: *"Playback stays on the device you choose here and goes back to it when it reconnects. Until you choose one, it follows your Mac's sound output."*

| State | Is the ON copy truthful? |
|---|---|
| Nothing chosen | Yes: the rule is exactly follow |
| Chosen and present | Yes: kept while idle, re-asserted while Enhanced plays, bound under Pure |
| Chosen and away | Yes: playback pauses, follows the default meanwhile, and returns once the device lists and an event comes |
| After relaunch | Yes: nothing is chosen, as the copy says (DEV-1 documents that the choice lasts a session) |

  - "Choose here" is accurate: the Settings card hosts the same device pill.

- **OFF**, quoted (unchanged by this commit): *"Playback follows a newly connected device."* **Not exact:**
  - The rule follows the Mac's sound output (the system default).
  - A newly connected device that macOS does not make the default is not followed. Example: AirPods set to "When Last Connected to This Mac".
  - Control Center changes are followed, though they are not new devices.
  - The ON-unpicked state behaves identically, yet its copy describes it differently.
  - Recommended (XS, copy only): *"Playback follows your Mac's sound output."*

## Residuals (no action needed for R1)
- No stream-appearance listener (item 2).
- The same-device H2 edge case (item 3).
- The switch title "Keep playback on this device" stays ON by default, while nothing is held until a pick. The detail line explains this.
