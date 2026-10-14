# D41 design: one contract for "what plays next" (newest request wins, per playback, applied at once)

Author: Plan agent (read-only), saved verbatim-in-substance by the coordinator 2026-10-14.
Base: `main` @ a206107, built on top of `fix/pure-safety` (672fc0a). Scope: D41's six Pure sequences, PURE-REARM-ORDER, NEXT-NEXT/Pure.

## 0. The decision

The VM and both engine paths agree on one contract for `setNextTrack`:

1. **Every request carries a ticket.** It names the start it follows (that start's transport epoch) and its place in the order the VM made requests (a sequence that is never reset).
2. **`engineQueue` admits only the newest request of the current playback.** All other requests are dropped, whatever order they arrive in.
3. **An admitted request takes effect at once.**
   - On Pure, the old pick is taken off the slot immediately, by the existing exactly-once exchange that races the render.
   - The new pick is armed only after its file opens, and only if its request is still the newest.
   - A pick that cannot join gaplessly, or whose file cannot be read, leaves the slot empty. The current track then ends, and the VM's existing ended-and-advance path starts the pick with a short gap.
4. **The end is final.** A track that ended with nothing armed never seams into something armed later.

`GaplessSource` keeps one slot and its exactly-once seam. It gains two mechanism rules: the end is final, and arming first frees the slot the last seam left behind. `TransportSnapshot` and `EngineSnapshot` are unchanged. Seam identity (P4-1) is follow-up F1.

## 1. What real players do (sources opened)

- **SFBAudioEngine** (`exp-p3-sota/ref-sfb`, 9ed712d):
  - The queue changes synchronously: `AudioPlayer::enqueueDecoder` (`AudioPlayer.mm:653-688`) changes `queuedDecoders_` in the caller's thread, under a mutex. `forImmediatePlayback` clears first.
  - The open happens later, on the decoding thread (`prepareDequeuedDecoder` `:1361`, "Open the decoder if necessary" `:1366`).
  - Every decoder has a global sequence number (`:244-250`). Events carry `(sequenceNumber, playbackGeneration)`, and stale generations are discarded (`:2104-2108`).
  - `clearDecoderQueue` only removes decoders still queued (`AudioPlayer.h:490-493`).
  - What plays is reported by identity: `setNowPlaying(decoder)` (`:1894`, `:2343`) leads to `nowPlayingChanged:`.
- **Cog's new engine** (`exp-p3-sota/ref-cog`, fb2ed48):
  - `resetNextStreams()` (`PlaybackEngine.swift:739-743`) calls `Feeder.resetNextTracks()` (`Feeder.swift:203-212`), which forgets any queued track not yet playing and asks again what follows. A track already reached stays.
  - The next track is pulled when needed (`playbackEngineNextTrack(after:)`), and the heard track is reported (`playbackEngineDidBeginTrack`).
- **How this maps here:**
  - Taking the old pick off at admission is SFB's synchronous queue change, and Cog's "forget the queued track".
  - sequence = SFB `sequenceNumber_`; session = SFB `playbackGeneration_`. This extends threading rule 3 (`architecture.md:141`).
  - **Deliberate difference: "the end is final".** The VM owns what happens after the end (ARCH-1), so the engine must not compete with it.

## 2. The contract

### 2.1 API
```swift
// PlaybackQueueKit/OnDeckTicket.swift (new)
public struct OnDeckTicket: Sendable, Equatable {
    public let session: UInt64   // epoch of the start this pick follows (that start's transportEpoch)
    public let sequence: UInt64  // VM request order; monotonic, never reset, starts at 1
}
// AudioPlaybackEngine (signature change; the default implementation stays a no-op)
func setNextTrack(_ fileURL: URL?, ticket: OnDeckTicket) async
```
`nil` means "nothing on deck". It is a request like any other, with a ticket.

### 2.2 Engine guarantees (both paths)
- **G1 Session.**
  - `startAudio(epoch:)` and `stopAudio(epoch:)` call `beginSession(epoch)` at the top, next to `beginTransportOperation`. A seek does not.
  - Admit only if `ticket.session == session`.
  - Older sessions are dropped. A future session not yet begun is dropped too; that start's prime re-arms with a higher sequence.
- **G2 Newest wins.** Within a session, admit only if `sequence > every sequence admitted`. A dropped request has no side effect; on Pure its file is never opened.
- **G3 Applied at once.**
  - Enhanced: set `onDeckURL` (`resampleQueue.sync`) during admission.
  - Pure, step 1: `pureModeEngineClearNextTrack` at admission (an exactly-once exchange that races the seam claim).
  - Pure, step 2: open on a global queue, then arm on `engineQueue` only if `isCurrent(ticket)`, not ended, and gapless-compatible (`fix/pure-safety` predicate). Otherwise the slot stays empty.
- **G4 Exactly one.** At a seam the render takes at most one armed pick, exactly once (unchanged).
- **G5 The end is final.** After a true end with nothing armed, no later request makes that session seam.
- **G6** An arm never fails because the previous seam's track has not been freed yet; arming frees it first.

### 2.3 VM assumptions and duties
- **A1.** When no request is in flight, the engine slot holds the newest request's pick. It is empty if that pick cannot join, could not be opened, or the track already ended; in all those cases `ended` is reported and ended-and-advance starts the pick.
- **A2.** A seam plays the VM's `pendingNextIndex`, except when it fires before the newest request is admitted (the rest of the main-thread turn plus one hop plus any `engineQueue` backlog). This is pre-existing on both paths; F1 closes it.
- **M1.** `armOnDeck(index:)` is the ONLY producer. In one main-actor turn it writes `pendingNextIndex`, resolves the URL, and stamps the ticket.
- **M2.** Ticket session = `onDeckSession` = the epoch of the newest `startPlayback`. A superseded start does not prime.

### 2.4 Why the old pick comes off at admission
Swapping B for C after C opens keeps a superseded pick armed for the whole open time (seconds on a network volume). If A ends during that time, the user hears B and sees C. Taking B off at admission shrinks the wrong-song window to one queue hop, and turns a last-moment change into "right song, short gap". Each slot change stays atomic with respect to the render. The slot is provably empty whenever `armNext` runs, so there is no third slot, and fix/pure-safety's comment stays true.

## 3. Changes per file

- **`PlaybackQueueKit/OnDeckTicket.swift` (new, pure, Sendable):**
  ```swift
  public struct OnDeckGate: Sendable {
      private var session: UInt64 = 0
      private var newest: UInt64 = 0
      public init() {}
      // AMEND-1 (P4 review): sessions only move forward — a stale start that reaches engineQueue
      // after a newer one (START-OVERTAKE) must not roll the session back and drop the newer prime.
      public mutating func beginSession(_ epoch: UInt64) { guard epoch > session else { return }; session = epoch; newest = 0 }
      public mutating func admit(_ t: OnDeckTicket) -> Bool {
          guard t.session == session, t.sequence > newest else { return false }
          newest = t.sequence; return true
      }
      public func isCurrent(_ t: OnDeckTicket) -> Bool { t.session == session && t.sequence == newest }
  }
  ```
- **`GaplessSource.{h,cpp}` (on top of fix/pure-safety):**
  - `armNext`: refuse if something is armed (clear first); NEW refuse if `ended_`; NEW `reapRetired()` before the compatibility check; publish unchanged.
  - `pullFloat` true-EOF branch, before the exchange: `if (ended_.load(relaxed)) return produced;`.
  - An arm that loses the race with the end is left unplayed; the next `setCurrent`/`clearNext` frees it.
  - Docs: `ended()` is final for the session; `armNext` is one slot, refuses after the end, and frees retired first.
- **`PureModeBridge.{h,cpp}`:**
  - Add `kNextTrackEnded = 3`; `pureModeEngineArmOpenedNextTrack` checks `gapless->ended()` before the compatibility check.
  - "Already armed" stays 0 but asserts in DEBUG.
  - Header: "caller clears first; arming never replaces".
  - Fix the stale name `pureModeEngineSetNextTrack` in `architecture.md:108`.
- **`AudioEngineBridge.swift`:** `var onDeckGate = OnDeckGate()`, confined to `engineQueue`.
- **`AudioEngineBridge+Playback.swift`:** `onDeckGate.beginSession(epoch)` in `startAudio` (after `beginTransportOperation`) and in `stopAudio`.
- **`AudioEngineBridge+Gapless.swift`** (replaces :52-133):
  - `setNextTrack(url, ticket:)` runs on `engineQueue`: `admit`, else log "stale, dropped".
  - If `activePathKind == .pure`, call `retractThenArmPure`: clear on `engineQueue`, open on a global queue, then arm on `engineQueue` if `isCurrent`. Log 2 armed / 1 reconfigure / 3 ended / 0 error; destroy the decoder otherwise.
  - Otherwise call `armEnhancedOnDeck` (`prefetchTrackLoudness` plus today's `resampleQueue.sync` body).
  - The path is read at admission (removes the `:57` routing hazard).
- **`AudioPlaybackEngine.swift`:** import PlaybackQueueKit; change the signature; add contract items 5 (newest-per-session), 6 (applied at once / old pick off first), 7 (the end is final).
- **`AudioViewModel.swift`:** `onDeckSession`, `onDeckSequence`, `nextOnDeckTicket()`.
- **`AudioViewModel+Queue.swift`:** `armOnDeck(index:)` is the only producer (sets pending, resolves the URL, stamps the ticket, returns a Task).
- **`AudioViewModel+Playback.swift`:** `onDeckSession = epoch` at `:56`; guard `onDeckSession == epoch` before the prime; `primeGaplessPipeline` → `await armOnDeck(index: nextIdx).value`.
- **Other call sites** go through `armOnDeck`: `+AutoAdvance.swift:44-62`, `+Playlist.swift:106-115`, `+SpectrumTimer.swift:87-88` (nil). `rearmOnDeck`, `playNext` and `appendToQueue` are already there.
- **`+Lifecycle.swift:172,186`:** `setNextTrack(nil)` before `stopAudio` is redundant under G1. Coordinator decision for R1: KEEP these calls as `setNextTrack(nil, ticket: nextOnDeckTicket())`; deletion belongs to P4-2.
- **`architecture.md`:**
  - Rule 3: each on-deck request carries `(start epoch, sequence)`, and `engineQueue` admits only the newest (`OnDeckGate`).
  - `engineQueue` row: add on-deck admission.
  - Gapless paragraph: the old pick comes off at admission, and the end is final.

## 4. Case walk-through (Pure, A playing, B on deck at (S,k))
1. **Play Next C:** admit (S,k+1), take B off, open C, arm. At A's end C plays and the app shows C. If A ends while C is opening: `ended`, then a fresh start of C (gap, right song). C's late arm is refused by the end rule, or dropped by session.
2. **Shuffle on:** R replaces B, same flow.
3. **Shuffle off:** A+1 replaces the random pick, same flow.
4. **Repeat all→one:** the pick becomes A (a second decoder), and the seam goes A→A.
5. **Repeat one→off:** A+1 replaces the second copy of A.
6. **Remove the on-deck B:** the next pick is recomputed as C, and B comes off at admission.
- **Race 1, PURE-REARM-ORDER** (two quick Play Next, (S,6) then (S,7)): whatever the open order, (S,6) fails `isCurrent` and only t11 is armed. If 7 is admitted first, 6 is refused and never opens.
- **Race 2, NEXT-NEXT:** S2's `beginSession(e3)` makes (e2,3) stale (dropped at admission, or at `isCurrent`). S2's prime (e3,4) arms t3; t2 does not play twice.
- **Edges fixed:**
  - pick incompatible → empty slot, then a fresh start;
  - open fails → empty slot, then try and report;
  - arm after the end → refused (no stutter);
  - arm right after a seam, before reap → succeeds (H3e).
- **Residual A2:** see 2.3; F1 closes it.

## 5. Test plan
- **C++ (real GaplessSource + FileDecodeSource), new `Tests/GaplessArmContractTests.inc`,** registered in `DSPKernelNullTest.cpp`. Fixtures are constant-code tracks A=1000, B=2000, C=3000.
  - `ArmContract_RetractArmBeforeEnd` (pass→pass guard)
  - `ArmContract_OccupiedRefuses` (pass→pass)
  - `ArmContract_RetractEndArm` (**FAIL→pass**)
  - `ArmContract_ArmBeforeReap` (**FAIL→pass**, H3e)
  - `ArmContract_ClearRacesSeam` (2000-trial stress, TSan-clean)
  - `ArmContract_ArmRacesEnd` (**intermittent FAIL→pass**)
- **Kit (swift-testing), new `OnDeckGateTests.swift`:**
  - VM-OD-01: every permutation of 5 tickets;
  - VM-OD-02: old and future sessions refused;
  - VM-OD-03: `beginSession` makes the previous ticket stale;
  - VM-OD-04: a 20k random-interleaving property test against an oracle;
  - VM-OD-05: a dropped ticket changes nothing.
- **VM level: real VM sources + an engine model** (adapt P4's `exp-p4/vm/EngineModel.swift`).
  - Coordinator decision: use `@testable import AdaptiveSound` with a model engine conforming to `AudioPlaybackEngine` (proven to work in this repo) rather than a new by-path compile harness or a new make target, unless that is impossible.
  - Model:
    - `setNextTrack` goes to an `inbound` list that scenarios can deliver in any order;
    - admission uses the REAL `OnDeckGate`;
    - Pure: take off, then open, then arm if current, not ended and compatible (per-URL `compatible` and `readable` flags);
    - start/stop call `beginSession`;
    - `trackEnds()` latches `ended`;
    - the arm behaviour is a parameter: refuse / clearThenArm / gatedReplaceAfterOpen / gatedRetractFirst(endFinal:).
  - Scenarios:
    - D41 × 6 on Pure and on Enhanced;
    - PURE-REARM-ORDER and REARM-DELIVERY-ORDER;
    - NEXT-NEXT on Pure and on Enhanced;
    - RETRACT-THEN-END, LATE-ARM-AFTER-END, REARM-INCOMPATIBLE, REARM-OPEN-FAILS;
    - a 3000-schedule explorer with two invariants: armed == pending when idle; heard == shown after every seam, except counted A2 cases.
  - Ablations show each piece is necessary:
    - clearThenArm fails both races;
    - gatedReplaceAfterOpen fails RETRACT-THEN-END;
    - endFinal:false fails LATE-ARM-AFTER-END.
- **Manual (founder, USB DAC):**
  - the six actions mid-song;
  - Play Next in the last 0.5 s on a slow volume: a gap and the right song if the request was admitted before the end; the old pick if it was not yet admitted (A2, see risk 2);
  - mashing shuffle near the end;
  - log lines `stale, dropped` / `retracted` / `ended → not armed`.

## 6. Risks
1. A last-moment change gets a short gap instead of a gapless wrong song. That is honest; tell the founder.
2. Enhanced requests now wait behind `engineQueue`. CORRECTED (AMEND-2, P4 review): a request NOT YET ADMITTED when the track ends leaves the old pick armed on both paths, so the user hears the old pick while the new one is shown (LATE-REQUEST; this is A2). The window is the `engineQueue` backlog plus `resampleQueue`, typically tens of ms. A gap with the right song happens only when the request WAS admitted and the Pure open had not finished. Also A2′: an edit made after a seam but before the next VM tick (≤ 50 ms plus the 33 ms clock) shows the new song while the old pick plays. F1 closes both. The alternative is a second gate on `resampleQueue`, at the cost of the routing hazard.
3. Starts that overtake each other (P4-2) cost the gapless prime; P4-2's "drop older commands" fixes that.
4. A pick left in the slot after the end holds one decode thread until the fresh start (~100 ms).
5. Merge order: land fix/pure-safety first. Both touch `armNext` and the test registration list.
6. The VM model can drift from the bridge (W0 replaces it).
7. Rapid toggling wastes opens. Optional: skip the open if already not current.
8. Under shuffle, a Play Next made during a start is overwritten by the prime. This is pre-existing (P4-2/N17), and the app stays consistent.

## 7. Left for W2 and follow-ups
- **F1 (P4-1 seam identity)** closes A2:
  - the sequence stored on the armed Track;
  - `TransportSnapshot.audibleOnDeck`;
  - Enhanced publishes it in `bumpTransitionCount`;
  - `handleTrackTransition` selects by the engine's report.
  - It is additive given the ticket.
- **Left alone:**
  - P4-2: command gating, a transport state machine, synchronous stop numbering;
  - N13b/c;
  - P4-3: shuffle as a permutation;
  - P4-4: recompute next after edits (now unblocked);
  - `ended` across a seek.
- **Fit with W2:**
  - `OnDeckGate` becomes state inside the Player reducer.
  - Cog's pull model turns "newest wins" into invalidate-and-pull.
  - The `GaplessSource` mechanism rules survive.
  - The two VM counters are deleted in W2.
  - No second state machine is added.
