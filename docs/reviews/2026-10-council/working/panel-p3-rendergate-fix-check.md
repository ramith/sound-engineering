# RenderGate R1 fix check (P3a breaker): `fix/render-gate-liveness` @ 7795733 (1ee11dd + 7795733)

**Verdict: SHIP.** The liveness defect is fixed. Exclusion still holds, the new tests prove the guarantee without a clock, and the fix is at least as good as my prototype.

There is one follow-up (DSP-06's teardown window), which is **not a regression**. It could be folded in now (S): `teardown()` should call `requestClose()` + `awaitQuiet()` and **never reopen**, and on a timeout it should park the source instead of letting the session delete it.

## Method
- The files were pulled with `git show` into scratch only (`scratchpad/council/exp-p3/gatefix/`). I did not touch `.claude/worktrees/fix-render-gate`.
- The harnesses:
  - `h4.cpp`: the same 400-close starvation harness as panel P3. Render modes:
    - `hal`: 100 µs of work every 2.67 ms;
    - `heavy`: 2 ms every 2.67 ms;
    - `hot`: 2 µs of work, re-entering back to back, no sleep.
  - Optional 28 CPU-hog threads on a 14-core machine.
  - Each trial is `close(100 ms)`, the production `kHoldRenderTimeout`.
  - Every run was built twice: at `-O2`, and with `-fsanitize=thread`.
  - `run_tests.cpp`: runs the branch's `Tests/RenderGateTests.inc` **verbatim**, against (a) the new header and (b) the a206107 algorithm re-expressed in the new API (`gatefix/oldapi/RenderGate.h`).
  - `py/gate_model.py`: an exhaustive interleaving model, including the timeout and teardown paths.

## 1. Liveness: close() now completes within one in-flight pass

| Build | Load | Render mode | NEW gate (p50 / p99 / max, timeouts) | OLD gate (a206107), same run |
|---|---|---|---|---|
| -O2 | no hogs | hot | **1 µs / 7 µs / 33 µs, 0 / 400** | 100 ms / 100 ms / 100 ms, **246 / 400** |
| -O2 | no hogs | hal | 0 / 142 µs / 388 µs, 0 | 0 / 139 µs / 174 µs, 0 |
| -O2 | no hogs | heavy | 672 µs / 2.0 ms / 2.06 ms, 0 (= the one 2 ms pass) | 597 µs / 2.0 ms / 2.04 ms, 0 |
| -O2 | 28 hogs | hot | 2 µs / 21 ms / 47 ms, **0 / 400** | **101 / 150** time out |
| -O2 | 28 hogs | heavy | 847 µs / 13.9 ms / 20.7 ms, **0 / 400** | **145 / 150** time out |
| -O2 | 28 hogs | hal | 0 / 10.0 ms / 10.0 ms, 0 | 0 / 75 µs / 160 µs, 0 |
| TSan | no hogs | hot | 2 µs / 8 µs / 199 µs, 0 / 400 | 550 µs / 3.2 ms / 3.4 ms, 0 / 200 |
| TSan | 28 hogs | all modes | max 40 ms, **0 / 200** in every mode | — |

- Under hogs, the tail (10–47 ms) is the OS preempting my non-real-time "render" thread **while it is inside**. That is the one pass close() must wait for; it is not starvation. The real HAL IO thread is time-constraint and would not be preempted that way.
- The bound is now a property of the gate: with `heavy`, the maximum wait equals the 2 ms work of a single pass.
- The render side compiles to single LSE instructions (`casab` to enter, `ldclrlb` to leave), so it is wait-free.

## 2. Safety
- **Exclusion holds.**
  - 0 overlaps in every h4 run (about 6,000 closes).
  - The branch's `RenderGate_ConcurrentNeverOverlaps` (a plain-memory "source" that only the gate orders) passes under TSan with no race report.
  - Model check (`seek` variant, 17 states): no state with the render inside while the control uses the source, and **no new pass ever starts while a close is pending**.
- **Why it is correct.** The four operations are read-modify-writes of one atomic, so they are totally ordered:
  - `requestClose`'s `fetch_or` is the linearisation point: any later CAS from 0 sees `kClosed` and fails.
  - `awaitQuiet`'s acquire load reads the value from `leave`'s release `fetch_and`. A failed CAS writes nothing, so no other write can intervene.
  - Timeout semantics are unchanged: `open()` withdraws the request, the pass inside carries on, and `close()` returns false. That is right for a seek.
- **Teardown (DSP-06): the window is still there, but the trigger is now far rarer.**
  - `HALOutputEngine.mm:920-923` (unchanged on the branch) still logs a failed `close()` and continues. On timeout, the new `close()` actively reopens the gate.
  - Model `fix-close-in-teardown`: two use-after-free kinds are reachable.
    - (a) the one pass stuck inside at the timeout;
    - (b) a **new** pass entering after the reopen. In reality that pass must load `source_` before the `source_ = nullptr` store at the end of `teardown()`, and still be running when `pureModeEngineDestroy` deletes the `GaplessSource`.
  - Model `request-no-reopen` (teardown uses `requestClose()` + `awaitQuiet()` and never calls `open()`): only (a) remains.
  - Before the fix, close() could fail through plain starvation under a busy render. Now it fails **only** if one pass stays inside more than 100 ms, which an RT render does essentially never (a stopped process or a page fault inside the pull). So this is not a regression and not an R1 blocker.
  - **Follow-up:**
    1. In `teardown()`, `(void)gate_.requestClose(); if (!gate_.awaitQuiet(kHoldRenderTimeout)) {…}` and never `open()`. The API already supports this.
    2. On that timeout, hand the source to a deferred-reclaim slot (or leak it and log) rather than letting the session delete it (DSP-06 remedy 3).

## 3. Compared with my "close announces itself" prototype
- **Same guarantee.** In both, a request bars re-entry, close waits for at most one pass, the RT side is wait-free, and a timeout withdraws the request.
- **The fix is better.**
  - It uses two bits, each with a single writer (`fetch_or` / `fetch_and`), instead of my four-value CAS state machine. My `leave()` needs a CAS plus a fallback store.
  - It exposes `requestClose` / `awaitQuiet` separately, which is exactly what the teardown follow-up needs.
  - It spins with 64 yields before sleeping. Hot-loop p99 is 7 µs for the fix against 89 µs for mine.
- **No reason to prefer mine.**

## 4. Do the new tests prove the guarantee without a deadline?
**Yes.** Running the branch's test file verbatim:

| Test | NEW gate (-O2 and TSan) | OLD algorithm (a206107, same API) |
|---|---|---|
| `ClosedGateTurnsRenderAway` | PASS | PASS |
| `CloseWaitsForRenderInside` | PASS | **HANGS** (killed by a 20 s alarm) |
| `PendingCloseBarsReentry` | PASS | **FAIL**: "a requested close did not close the gate to new passes at once; the render re-entered past a pending close (the starvation path)" |
| `ConcurrentNeverOverlaps` | PASS (slowest close 1 µs at -O2, 13 µs under TSan) | PASS (slowest close 149 ms under TSan) |

- `RenderGate_PendingCloseBarsReentry` is the real proof. It is single-threaded and deterministic, with no clock and no scheduler involved, and it fails crisply on the old algorithm.
- Two small test weaknesses (non-blocking):
  - **(i)** On a regression, `CloseWaitsForRenderInside` **hangs** instead of failing: its `while (!gate.isClosed()) yield` loop is unbounded. CI would only catch that through the job timeout. A generous iteration bound with a crisp FAIL would be better, and needs no wall clock.
  - **(ii)** `ConcurrentNeverOverlaps` is now exclusion-only, and because close() always wins, the render gets few pulls: 537 pulls for 2000 seeks at -O2. That makes the torn-read check sample thinly. Requiring at least one pull between seeks would restore its coverage.

**Recommendation:** SHIP for R1. Fold in the 2-line teardown change if convenient; otherwise log it under DSP-06 with the source-parking remedy.
