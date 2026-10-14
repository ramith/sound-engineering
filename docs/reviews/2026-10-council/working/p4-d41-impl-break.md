# P4: breaking the IMPLEMENTED D41 fix (`fix/r1-blockers` @ f93b08e, PR #88)

**Verdict: SHIP (D41), with one-line follow-up F-P4-1 recommended.**
- D41 is implemented as designed, both amendments landed, and I found no regression.
- **F-P4-1 is a wrong-song bug that was already there before D41** (D41 did not cause it). The shipped tests cannot see it, and D41's own invariant A1 says it should not happen. It can ride this PR, or go straight after it.

How I ran this:
- in my worktree `.claude/worktrees/panel-p4`, detached at f93b08e;
- builds at `-j 2` and `nice`; targeted `swift test --filter` only;
- nothing built in `r1-blockers`. The two scratch test files are the only untracked changes.

## 1. My rig against the SHIPPED code: `exp-p4/vm-shipped/`

How the rig is built:
- **VM:** the shipped `AudioViewModel*` sources, copied verbatim and **unpatched**.
- **Gate:** the shipped `PlaybackQueueKit` (`OnDeckTicket` / `OnDeckGate`).
- **My independent engine model:**
  - requests reach `engineQueue` in any order, and Pure opens finish in any order;
  - Pure takes the old pick off at admission, then arms if `isCurrent`, not ended and compatible;
  - an admitted Enhanced request is written to `resampleQueue` as `async`, FIFO before any later start/stop clear and before the seam's EOF hook;
  - the caller resumes when its request is **settled**, as the shipped bridge does, not when it is merely recorded;
  - starts and stops `beginSession`; "the end is final".

| Check | Result |
|---|---|
| D41 × 6 (Play Next, shuffle on/off, repeat all→one / one→off, remove on-deck) × Pure / Enhanced | **12/12 HOLD** |
| PURE-REARM-ORDER (all 4 delivery × open orders) | **HOLDS** |
| NEXT-NEXT (stale request inbound / stale open in flight) × Pure / Enhanced | **4/4 HOLD** (t2 plays once, then t3) |
| START-OVERTAKE (two starts reach the engine reversed) | **HOLDS**: t4 is armed and the join is gapless, the same as before the fix. AMEND-1 works. |
| LATE-REQUEST | A2 as documented (hears t1, shows t9, both paths) |
| SEEK-AFTER-END | Consistent (hears and shows t9). The scrub-back is lost; that is documented. |
| RETRACT-THEN-END, LATE-ARM-AFTER-END, repeat-one gapless, remove the playing row, queue of 1 × repeat 0/1/2 (both paths) | **all HOLD** (30/30 non-A2 cases; `cases-shipped.log`) |

**Explorer: 3000 random schedules.** Verbs interleaved with pause, stop and seek; arbitrary delivery and open orders; up to 2 seams; Pure in 2/3 of runs.

| Class | before the fix (refuse) | shipped |
|---|---|---|
| idle: app's next ≠ engine's armed | 292–294 | **0–1** (the 1 is F-P4-1) |
| wrong song, not A2/A2′ | 8–10 | 6 with the pre-existing N13b count leak, which is out of scope; **0–1 with N13b fixed in the model** (the 1 is F-P4-1 again) |
| wrong song, A2 / A2′ (documented residual) | 66–71 | 54–74 (same range) |
| P4-2: app shows Playing, engine silent | 78–82 | 63–89 (same range: not worse) |

## 2. The amendments

- **AMEND-1 landed.** `OnDeckGate.beginSession` does `guard epoch > session else { return }` (`PlaybackQueueKit/OnDeckTicket.swift`). It is tested by VM-OD and by the shipped test "START-OVERTAKE (AMEND-1)", and it passes in my rig.
- **AMEND-2 landed:**
  - `AudioPlaybackEngine.swift:119-125` states A2 and A2′ with their windows.
  - `architecture.md:109` states A2 / A2′, the Enhanced `resampleQueue` part, and "`ended` latched across a seek: a scrub back into an ended track is lost".
  - The commit message says the same.
  - One precision nit: on Enhanced, "when the track ends" in A2 effectively means **the EOF hook**, which fires up to ~180 ms before the audible end (P3a D40). Optional wording.

## 3. Deviations from `d41-design.md`, each judged

| Deviation | Verdict |
|---|---|
| Enhanced slot write is `resampleQueue.async`, not `.sync` (my O1) | **Good.** FIFO keeps the admission order before a start/stop clear and before the seam hook. `engineQueue` no longer blocks behind a slow roll. |
| A superseded start skips only the prime (`if onDeckSession == epoch { prime }`); it still sets `isPlaying` if the stop gate passes | **Fine.** The newer start sets it too. No harm found. |
| `isCurrent` also requires `newest != 0` | Fine (harmless). |
| `setNextTrack` resumes when the request is settled, after the Pure open, not at admission (my O2 not taken) | Acceptable. The prime still holds `isPlaying = false` through the next file's open. That is the window behind F-P4-1. |
| Bridge DEBUG `assert(ended && "slot occupied")` in `pureModeEngineArmOpenedNextTrack` | From the bridge's side it cannot fire: every armed pick is the current ticket's, and its admission cleared the slot. The C++ breaker's §3 (a re-arm inside the render's seam claim) is the one known way; it is not duplicated here. |
| The device-loss path tears Pure down without `beginSession` | Fine. `withPureEngine` returns nil once the session is detached, so an in-flight open is destroyed. The VM's `armOnDeck(nil)` is admitted and does nothing. |

## 4. Are the shipped tests real? (three mutations)

- **M1: `OnDeckGate.admit` without `sequence > newest`. CAUGHT.** VM-OD-01/04/05 fail, plus REARM-DELIVERY-ORDER and the 3000-schedule explorer in `AdaptiveSoundTests`.
- **M3: C++ `GaplessSource::armNext` without the "end is final" refusal. CAUGHT.** `ArmContract_RetractEndArm` fails. `ArmRacesEnd` still passes, because the `pullFloat` guard covers it.
- **M2: bridge, no Pure retract at admission AND no `beginSession` in start/stop. NOT CAUGHT: all 30 D41 tests pass.**
  - Every Swift D41 test drives the real VM against an engine **model** (`OnDeckEngineModel`).
  - The bridge's own glue is not exercised by any test: admission on `engineQueue`, retract, `isCurrent` at arm, the path read at admission, and `beginSession` placement.
  - That glue is the part that fixes D41 on the real engine.
- **Model deviation that hides a real bug:** `OnDeckEngineModel.setNextTrack` "returns once the request is recorded", while the bridge returns once the request is settled. So the model never shows the prime holding `isPlaying = false` while the next file opens, and F-P4-1 is invisible to it.
- **Remedy (follow-up, not blocking):**
  - Move the bridge's admission decision into a pure Kit reducer (gate plus "retract on Pure" plus "arm iff current, not ended, compatible") that the bridge only executes, and test the reducer. Or add a bridge test with a fake Pure handle.
  - Make the model resume at settle.

## 5. Interaction with the other R1 fixes

- **Pure-safety (b81d170).** The compatibility check sits after the "ended" check and before `armNext` in `pureModeEngineArmOpenedNextTrack`.
  - An incompatible or untranslatable pick leaves the slot empty. The track ends, the VM starts the pick fresh, and Pure-safety's policy then decides Pure or Enhanced (new session, new prime).
  - Covered by REARM-INCOMPATIBLE, which passes in both rigs.
  - Side note: that fresh start can switch Pure→Enhanced, which exposes the pre-existing N13b count-domain leak (out of scope).
- **RenderGate teardown parking (a4050c3 / 2840e39).** Teardown detaches the session first (`detachPureEngineForTeardown`: the field is nil under the lock), so `withPureEngine` returns nil afterwards. D41's clear and arm never reach a parked session; an in-flight open is destroyed. No interaction.
- **N92 device changes (4fddf17 / 2a79914).** A device move or return goes through the VM's `startPlayback(resumeFrom:)` (new session, new prime). Device loss is covered above. No interaction found.

## F-P4-1: Play Next during a start's prime plays the old pick and skips the Play Next song. Already there before D41; LOCAL, one line.

**Repro** (`exp-p4/vm-shipped`, `./run.sh prime`; both paths BROKEN on the shipped code):
1. From stopped, press Play. The start lands, and the prime arms t1 (on Pure, t1 is still opening).
2. During the prime, `isPlaying` is still false. The user presses Play Next on t9.
3. `playNext` with `isPlaying == false` only inserts t9 at current+1. The queue becomes `[t0, t9, t1, …]`, and `pendingNextIndex` (1) now **points at t9**, while the engine armed **t1**.
4. At t0's end: **hears t1, shows t9**, and t9 is never played.

**Window.** From the start landing to the prime's settle:
- on Pure, the next file's open: milliseconds on SSD, seconds on a NAS or a spun-down disk;
- on Enhanced, one `resampleQueue` hop.
- Realistic trigger: Play, then an immediate Play Next, on Pure.

**It was already there before D41.** `main` had the same `playNext` branch, and the same prime that sets `pendingNextIndex` and then awaits the arm. The explorer saw it 0–1 times in 3000 schedules.

**Fix (verified in a patched copy in the rig, not in the repo).** In `AudioViewModel+Queue.swift:122`, change `if isPlaying {` to `if isPlaying || pendingNextIndex != nil {`. While a start's prime is pending, Play Next then arms its slot, and newest-wins supersedes the prime's request. Result:
- PLAYNEXT-DURING-PRIME HOLDS on both paths (hears and shows t9);
- all 30 cases still HOLD;
- explorer: 0 idle mismatches, 0 wrong songs outside A2.

**Add a shipped scenario:** the model must resume `setNextTrack` at settle, and the scenario must Play Next during the prime.
