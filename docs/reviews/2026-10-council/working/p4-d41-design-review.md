# P4 adversarial review of the D41 fix design (`d41-design.md`)

**Verdict: AMEND.** Two small amendments; the mechanism is right.
- **AMEND-1** is one line of code: make `OnDeckGate.beginSession` monotonic.
- **AMEND-2** corrects a claim in the text: risk 2, plus the A2 and manual-test wording.
- Optional: O1 and O2 below.

With AMEND-1, every D41 case, both races and every edge the brief lists **hold** on the real VM sources. The design does not make the P4-2 stop/seek bugs worse.

## Rig

The rig is `exp-p4/vm-d41/`:
- `run.sh` → `patch_vm.py`, `EngineModel.swift`, `main.swift`.
- Logs: `cases.log`, `monocases.log`, `ablate.log`, `scoped.log`.

How it is built:
- **The VM is real.** It is the real `AudioViewModel` sources from main @ 7d7c2cd, with the design's VM side applied to the copies only (§2.3 M1/M2, §3):
  - `armOnDeck` is the only producer and stamps the ticket;
  - `onDeckSession` is set at `startPlayback`;
  - a superseded start does not prime;
  - the prime, the transition, removal, device loss and pause/stop all go through tickets.
- **The engine model:**
  - `OnDeckTicket` / `OnDeckGate` are the design's code verbatim.
  - Every `setNextTrack` lands in an `inbound` list, and the scenario delivers it onto `engineQueue` in **any** order.
  - Pure: take off at admission, then open on a global queue (finishes in **any** order), then arm if `isCurrent`, not ended and compatible.
  - Starts and stops call `beginSession`. "The end is final" is applied. `ended` stays latched across a seek.
  - Ablation modes: `refuse` (today), `clearThenArm` (P3a), `gatedReplaceAfterOpen`, `gatedRetractFirst(endFinal: false | true)`.
- I did not touch `fix/pure-wrong-song`; it was clean at 672fc0a when I read it.

## Results: `gatedRetractFirst(endFinal: true)`

| Check | Result |
|---|---|
| D41 × 6 (Play Next, shuffle on/off, repeat all→one, one→off, remove on-deck), Pure and Enhanced | **12/12 HOLD** |
| PURE-REARM-ORDER, all 4 delivery × open orders | **HOLDS**: the newest is always armed |
| NEXT-NEXT, stale request still inbound / stale open in flight, Pure and Enhanced | **4/4 HOLD** (t2 plays once) |
| RETRACT-THEN-END (A ends while C opens) | **HOLDS**: ended, then a fresh start of C (gap, right song); the late arm is refused |
| LATE-ARM-AFTER-END (open lands after the end, same session) | **HOLDS**: "ended → not armed", C starts once |
| Repeat-one gapless (3 cycles, then one→off mid-song), both paths | **HOLDS**: t0 t0 t0 t0 t1 |
| Remove the playing row, both paths | **HOLDS**: engine silent, nothing armed, app stopped |
| Queue of 1 × repeat off / all / one, both paths | **6/6 HOLD** |
| SEEK-AFTER-END (scrub back in A after a last-moment Play Next left the slot empty) | **HOLDS** (consistent; see below) |
| **LATE-REQUEST** (Play Next sent but not yet admitted when A ends) | **BROKEN on both paths**: hears **t1**, shows **t9**. This is A2, but risk 2 claims "a gap, never a wrong song" (AMEND-2) |

**Ablations:** each piece of the design is necessary.
- `today`: everything fails.
- `clearThenArm`: fails both races, NEXT-NEXT and RETRACT-THEN-END.
- `gatedReplaceAfterOpen`: fails RETRACT-THEN-END and LATE-ARM-AFTER-END.

## Explorer: 3000 random schedules per mode

**What each schedule mixes:**
- **On-deck verbs:** Play Next, shuffle, repeat, remove on-deck, remove playing, append, Next;
- **Transport verbs:** pause, play, stop, seek;
- **Delivery and timing:** arbitrary inbound delivery and open-completion order, main-actor drains, 20 Hz ticks, up to 2 seams;
- **Mix:** Pure 2/3 of runs, shuffle 1/4, repeat random.

| Class (end state) | today | design | design + N13b fixed in the model (epoch-scoped seam count) |
|---|---|---|---|
| idle: app's next ≠ engine's armed | **293–307** | **0** | **0** |
| wrong song, not explained by A2 / A2′ | 10–20 | 8–9 | **0** |
| wrong song, A2 / A2′ (a seam before the newest request was admitted, or an edit between a seam and the tick) | 47–78 | 69–83 | 69–78 |
| P4-2: app shows Playing, engine silent | 79–84 | 81–85 | 84–91 |

**How to read the rows:**
- **The 8–9 left with the design** are all SEAM-AT-START: a stale seam count carried into a start's samples. That is N13b, out of scope. With an epoch-scoped count they go to 0.
- **The A2 counts are statistically the same** across modes. The explorer packs edits around seams far more densely than real use does.
- **P4-2 is unchanged.**
- **A2′, the subtype my classifier also counts:** a seam lands, then the user edits before the VM's tick sees the seam, so the tick selects the *new* pending. It is the same identity-less seam. The design's A2 wording should name it (AMEND-2). F1 closes both.

## AMEND-1 (code, one line): sessions only move forward

**Failing schedule (START-OVERTAKE):**
- t0 is playing. The user clicks t1, then t3 (e2, then e3). The two start ops reach `engineQueue` as `start(e3)`, `start(e2)`. Nothing prevents this: the bridge's nonisolated async methods hop through the global executor, which keeps no order.
- **Design as written:** `beginSession(e2)` rolls the session back, so the e3 prime's ticket is dropped.
  - Hears t1, shows t3 (P4-2, pre-existing), **armed none**.
  - At t1's end: ended, then a fresh start (**a gap**).
- **Today:** t4 is armed, and the join is **gapless**.
- So the design as written makes this P4-2 schedule slightly worse.

**Amendment.** In `OnDeckGate`, write `mutating func beginSession(_ epoch: UInt64) { guard epoch > session else { return }; session = epoch; newest = 0 }`. This mirrors `beginTransportOperation`'s `max`.
- With it: START-OVERTAKE arms t4 (gapless again, same as today).
- All 30 targeted cases still hold (`monocases.log`).
- The explorer is unchanged: 0 idle mismatches; 0 non-A2 wrong songs with the scoped count.
- **Add a test, VM-OD-06:** `beginSession(older)` leaves the session and `newest` unchanged, and a ticket for the newer session is still admitted.

## AMEND-2 (text): a late request gives the wrong song, not a gap, on both paths

- **What the design says.**
  - §6 risk 2: "a very late [Enhanced request] becomes 'ended, then a fresh start' (a gap, never a wrong song)".
  - The manual test: "Play Next in the last 0.5 s on a slow volume (gap, right song)".
- **Both are only true once the request has been admitted.** Until admission, the **old pick stays armed**: Enhanced replaces at admission, and Pure takes the old pick off at admission. LATE-REQUEST shows hears t1 / shows t9 on Pure and Enhanced. This is the design's own A2 (§2.3).
- **What happens to a late request:**
  - not yet admitted at the end → **A2 wrong song** until the next seam;
  - admitted but (Pure) not yet armed → **gap, right song**.
- **The Enhanced A2 window grows.** It was the `resampleQueue` backlog; it becomes the `engineQueue` backlog plus `resampleQueue` (the design's `.sync`). In ordinary use the `engineQueue` backlog is small: the 33 ms clock sample (µs), device enumeration (`AudioEngineBridge+Devices.swift:14-16`, runs on every device-list change; tens of ms, not measured), and starts.
- **Answer to "Play Next during a device enumeration":** it can widen A2 by the enumeration time. On Enhanced it **cannot** cause a gap, because the old pick stays armed. It can give the wrong song if the track's EOF hook fires inside that window, and the hook fires ~50–180 ms before the audible end (P3a D40).
- **Also name A2′ in §2.3:** an edit made after a seam but before the VM's next tick (≤ 50 ms + the 33 ms clock) is shown as the new song while the old pick plays.

## "The end is final" × seek / latched `ended` (as asked)

- **SEEK-AFTER-END.** A last-moment Play Next leaves the slot empty. A ends (`ended` latched). The user's scrub-back lands next:
  - A is audible again from 30 s, while `ended` stays latched.
  - The VM's next current-epoch tick sees `ended` and starts C fresh, so the scrub is lost.
  - The final state is consistent (hears C, shows C).
  - **Today the same schedule ends hearing t1 while showing t9**, so the design is better here.
  - The lost scrub and the brief A-then-C are pre-existing: `ended` is latched across a seek, and the VM acts on any current `ended`.
- **No new bad interaction:**
  - Every path that latches `ended` is followed by the VM restarting or stopping within one tick.
  - Arms refused after the end only ever belong to a session the VM is about to replace.
- Retract-first makes mid-queue ends more frequent (every late edit), so this seek case becomes a little more reachable. It is still contrived (a scrub inside the open window after a late edit).
- Recommendation: leave `ended`-across-seek to W2 as the design says. But record "a seek after `ended` is lost" next to it.

## Optional (not blocking)

- **O1.** Enhanced admission: use `resampleQueue.async`, not `.sync`.
  - The order is still preserved: admissions are serialized on `engineQueue`, and `resampleQueue` is FIFO, so it is equivalent to the seam.
  - It stops a slow roll (a next-file open on a network volume) from blocking `engineQueue`, which would stall the transport clock and every transport op behind it.
- **O2.** Resume `setNextTrack`'s continuation at admission, not after the Pure open.
  - Today the prime awaits the open too, so `isPlaying` stays false for a slow open while audio plays; that is P4-2/N17 amplified.
  - The arm outcome is already reported through `ended` (A1), so the VM need not wait for it.
