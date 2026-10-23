# P3a breaker: the C++ half of the D41 wrong-song fix (`fix/r1-blockers` @ 1ebf323; commit 04738cf)

**Verdict: SHIP.**
- Every race the fix targets gives only allowed outcomes, at -O2, under TSan and under ASan+UBSan.
- An arm that loses to the end is never heard and is freed later.
- The old "arm while armed" refusal can no longer be reached from the bridge.
- I found **one latent defect** in `GaplessSource`'s arm contract (§3), with a deterministic repro. The shipped bridge cannot reach it in practice, because its clear and its arm are at least about 50 µs apart while the race window is a few instructions. It is a small, control-plane-only fix to make before anything arms right after a clear.

**Setup.**
- My worktree is `.claude/worktrees/panel-p3-breaker`, detached at 1ebf323.
- `cpp/h8_d41.cpp` drives the REAL `GaplessSource` + `FileDecodeSource`: one paced render thread against one control thread, with constant-code fixtures (A 1000 × 2048 frames, B 2000 × 1024, C 3000 × 1024).
- `py/d41_model.py` is an exhaustive interleaving model.
- `d41inst/` is the real `GaplessSource.cpp` plus ONE test hook (a pause point), for the deterministic repro.
- CPU use was one harness process at a time, with no full gate.

## 1. The races the fix targets: only allowed outcomes, never a mix

Allowed means:
- every track is heard whole (A = 2048 frames; B or C = 1024 frames, or not at all);
- one seam per track heard after A;
- the session ends;
- the sequence of tracks heard is one the experiment allows;
- an arm is refused only after the end.

| Experiment (trials) | -O2 (2000) | TSan (3000) | ASan+UBSan (1000) | Outcomes seen (all allowed) |
|---|---|---|---|---|
| E1 clear vs seam | 0 violations | 0, no race report | 0, clean | clear wins → `1000 0`, ended; seam wins → `1000 2000 0`, 1 transition |
| E2 arm vs end | 0 | 0 | 0 | armed in time → B heard; refused after the end; **armed but lost to the end → never heard** (13 / 23 / 29 cases) |
| E3 clear then arm back to back | 0 | 0 | 0 | `1000 0`; `1000 3000 0`; `1000 2000 0`; `1000 2000 3000 0` (2 transitions) |

- **A lost arm is freed.** It sits in `armedNext_`'s slot. `clearNext()` (run after every trial) or `setCurrent()` / the destructor free it, because every source lives in a `tracks_` `unique_ptr`. ASan reports no use-after-free. (ASan leak detection isn't supported on macOS; ownership is structural.)
- **The repo's tests pass** in my worktree: all 16 `ArmContract_*` / `PureGapless_*` / `GaplessContract_*` tests. They cover the end-is-final and clear-vs-seam races, but not §3's window.

## 2. Reaping from the control plane while the render runs
- **The argument.** The render's last use of the retired track (pull, exhausted check, frame count) is ordered before its `retired_.store(cur, release)`. `reapRetired`'s `exchange(acq_rel)` acquires it, and the render never touches a retired slot again: the next call loads `active_`, and the slot comes back only through a new arm.
- **My model agrees.** With a poll-plane `reapRetired` placed between the clear and the arm, the reap itself never destroys a track the render is seaming into or playing. All violations in §3 come from `armNext`'s choice of free slot, not from the reap.
- Moving the reap into `armNext` is sound for the same reason, apart from the window in §3.

## 3. The latent defect: re-arming inside the render's seam claim
**The claims that are false.** "Nothing is armed, so the RT thread cannot seam and retired_ is stable here" (`armNext`), and "with no slot armed the RT thread cannot be mid-seam" (`freeSlotForArm`, pre-existing).
- After the render's `armedNext_.exchange` has claimed B, `armedNext_` is null.
- But until the render publishes `retired_ = A` and `active_ = B` (two instructions later), `freeSlotForArm` still sees B's slot as free (it is neither `active_` nor `retired_`).

**Case 1: the render is paused right after its claim. The control runs `clearNext()` (gets null) then `armNext(C)`:**
- `armNext` picks B's slot, **destroys B**, installs C, and arms the slot the render is adopting.
- Deterministic repro (real code + hook): A is heard × 2048, then **C** × 1024, with **transitions = 2** (a phantom second seam: at C's end the render adopts the armed slot, which is itself).
- The poll plane's `reapRetired` then **frees the ACTIVE track** (`activeSource()` reads null afterwards).
- In production that would be:
  - a data race or use-after-free with the render's next pull;
  - the UI advancing twice;
  - a session that never reports its end, because a slot with a null source returns 0 without the EOF logic.

**Case 2: the render is paused after retiring A, before adopting B:**
- `armNext(C)` finds no free slot and **refuses while not ended**, so the bridge's DEBUG `assert(ended && "slot occupied …")` **fires**. Its premise ("only a caller bug") is false.
- In release the bridge returns 0, B plays, and C starts fresh after B: the right song.

**The model confirms it:** 7–9 interleavings arm over the slot being adopted, and 3–4 arm the active slot.

**Reachability from the shipped bridge: in practice, none.**
- `retractThenArmPure` clears on `engineQueue`, opens the new pick on a global queue, and arms back on `engineQueue`.
- The open alone takes a minimum of 31 µs (p50 32 µs, max 6.4 ms, a cached local WAV, `h9`), plus two queue hops.
- The render's window is a few instructions. To hit it, the time-constraint IO thread must stall for 50 µs or more exactly there.
- Any future caller that arms straight after a clear (a pre-opened or cached decoder, a test helper) gets this window.

**Fix (S, control plane only, no change on the RT thread):**
- Remember the slot last armed (control-owned `lastArmed_`).
- When `clearNext()`'s exchange returns null while `lastArmed_` is set, the render has claimed it. `armNext` should then wait (a bounded spin; the render publishes within a few instructions) until `active_ == lastArmed_` before choosing a slot. Alternatively, use a third slot and exclude `lastArmed_`.
- Narrow the DEBUG assert to `armedNext_` being occupied.
- Add a test using a seam hook like mine.

## 4. The other questions
- **The old D41 "arm while armed" path is unreachable from the bridge.** The re-arm always clears first (`retractThenArmPure`), admission is serial on `engineQueue`, and a superseded open is dropped (`armOpenedPure` → `isCurrent`). My panel's H3a scenario now plays C when the re-arm lands before the end (E3: `1000 3000 0`), or starts it fresh after the end.
- **Interaction with the Pure-safety compatibility check:**
  - `armNext` now reaps before the check, so a refused, incompatible arm still frees the retired slot (harmless).
  - The bridge checks `ended()` before compatibility, so an ended session reports 3 even for an incompatible file. Both mean a fresh start.
  - Inside §3's window the check compares against the stale active track (A instead of B). That is equivalent, because B was compatible with A.
- **RenderGate teardown parking with a pending arm:**
  - `parkIfRenderOutlivedStop` parks the whole `GaplessSource`, armed source included, so a stuck pass that resumes and seams into it reads valid memory. That is correct.
  - Cost: the parked active, armed and retired sources keep their decode threads alive forever, waking periodically (they nap when the ring is full). Parking needs a stuck pass, so this is "never in practice". If wanted, stopping those producers (`FileDecodeSource::close()` only joins the producer side; the stuck consumer only reads the ring) would end the thread leak without freeing memory.
