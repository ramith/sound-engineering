# The disconnect freeze (2026-10-13): evidence

Switching Bluetooth headphones off froze the app for 3–7 s. This was found in the founder's final check of Sprint G,
and fixed by PR #86 (merged as dd5e02d).

**Before you change the app ↔ engine threading, read:**
- the threading rules in [architecture.md](../../architecture.md);
- the independent audit, [main-thread-audio-audit-2026-10.md](../../main-thread-audio-audit-2026-10.md).

| File | What |
|---|---|
| `rev-breaker.md` | Reviewer 1, the breaker: lock-hold harness on the real bridge (4 modes, 2.5 s), TSan, planted guard violations; found the stale-`ended` regression and a crash |
| `rev-sota.md` | Reviewer 2, the state-of-the-art challenger: compares the fix with SFBAudioEngine, Cog, VLC and Apple's docs (links inside); found the stale-`ended` blocker independently |
| `rev-arch.md` | Reviewer 3, architect + pre-mortem: traceability to the audit's 10 requirements, five failure stories |
| `rev-verify.md` | The verify pass after the one revision: **SHIP** |
| `BreakerHarness.swift.txt`, `BreakerHarness-hook.diff.txt` | The breaker's harness, kept as text. It is stricter than the gate self-test (`Debug/MainThreadStallSelfTest.swift`): every call must stay under 5 ms, and it adds engineQueue-holder and first-play modes. Port those two modes into the self-test after R1. |

**Founder re-test (with `sample` recording the live app):**
- macOS's device teardown still took about 8 s in the background (`HALDevice::Teardown`);
- the main thread had **zero** audio frames and no wait of 20 ms or more across 6 minutes, covering the disconnect,
  Pure seeks, a pause / resume and a seek storm.
