# Product-intent review of failing tests — Sprint 5 EQ + auto-advance

> **⚠️ HISTORICAL (2026-07-03 product-intent review).** Point-in-time review; retained for the intent/rationale provenance.

Reviewer: product-manager. Scope: is the ASSERTED behavior the behavior the product
SHOULD have. No code changes made.

Context used:
- scratchpad/REVIEW-BRIEF.md (shared brief, 22 failures across EQTests + VM-AA-RTR-1)
- Tests/AudioDSPTests/EQTests.swift
- Tests/AudioViewModelTests/AutoAdvanceReconfigureGapTests.swift, MockAdvanceController.swift, AutoAdvanceTests.swift
- Sources/AdaptiveSound/AudioViewModel+Lifecycle.swift (grounds the "20 Hz poll, arm-after-start" architecture the test comments describe — confirmed real, not a test fiction: `performStop()`/`stopPlayback()` clear `pendingNextIndex` synchronously, consistent with an async arm step elsewhere in the advance path)
- Tests/EqFrequencyResponseSweepTests.inc (the production C++ null-test gate's own tolerance, for comparison — see below)

---

## 1. EQ gain linearity ±0.05 dB — WRONG BAR (test bug, not a product gap)

The test asserts every one of 7 gain points (-20…+12 dB) must land within ±0.05 dB, on
BOTH a peaking biquad's single-tone RMS measurement AND cross-path agreement. All of it
fails, with errors from 0.05 dB (borderline) up to 1.9 dB at the -20 dB extreme.

Product read: ±0.05 dB is not a meaningful bar for a consumer enhancement EQ, and it is
not even the bar this product has already committed to. The project's OWN production
gate — `Tests/EqFrequencyResponseSweepTests.inc`, the C++ null-test suite the founder
has already accepted as the source of truth (117/117, cited explicitly in the brief as
authoritative) — uses `kEqFrToleranceDb` = **±1.0 dB** at band center for the exact same
kind of measurement. That's a 20x tighter bar than the thing this app already ships
with and verifies against.

There are also real, well-known reasons a single-tone RMS measurement of a resonant
peaking biquad won't nail the nominal gain to 0.05 dB: windowing/settling transients in
a 0.5s buffer, the Q=1 peaking filter's passband shape sampled slightly off the exact
peak due to bilinear-transform frequency warping at 1kHz/48kHz, and float32 accumulation
—none of which a listener can perceive and none of which matter for "does turning this
band up by 6dB sound like +6dB." No user or reviewer will ever notice a 0.05dB vs 1dB
gain error on a single EQ band; ±1dB is inaudible and is the field-standard casual/
prosumer EQ tolerance (compare to typical EQ plugin datasheets, which spec ±0.5–1dB).

Verdict: **test bug — retune, not a product defect.** Recommend aligning
`gainLinearityTolerance` (and `crossPathTolerance`, which is measuring the same
disagreement, not an independent property) to the existing product bar of ±1.0 dB, or
at minimum ±0.5 dB if the DSP reviewer wants headroom above the C++ gate's own number.
Do not ship a hidden double-standard where the Swift test enforces a tighter number than
the actual gate the app is verified against — that's not "quality-first," that's an
untraceable, arbitrary target nobody signed off on as a product requirement.

Action: **won't-fix as a product ticket.** Retune the test constant to match (or be
looser than) the C++ gate's ±1.0 dB. No DSP code change implied by this alone — this is
a test-methodology finding, not evidence the EQ's real-world accuracy is wrong. (Deferring
the final number to the DSP reviewer's measurement-methodology judgment, but the PRODUCT
bar is: match or exceed the ±1.0 dB the founder already accepted, don't invent a new one.)

---

## 2. EQModule applies masterGainLinear ("-6dB attenuation", actual -0.66dB) — NEEDS DSP TRIAGE, likely P1 if real

This one is different in kind from #1: it's not a tight-tolerance nitpick, it's a 5+dB
gap between expected and measured attenuation — "turn the master gain down by 6dB" only
measured -0.66dB, i.e. the ramp/attenuation barely happened during the test's 512-sample
window even with the test's own generous ±1dB tolerance for ramp settling.

Product read: master gain (this is the overall EQ output-trim/gain-staging control) not
applying within any reasonable margin is a correctness issue IF it reproduces in the real
render path, because a broken master-gain trim is directly audible (wrong loudness) and
touches loudness-safety territory this product already treats seriously (see Sprint 4).
But per the brief, the real EQ module is independently validated by the C++ null-test
gate (117/117), which the brief says exercises this same production code path. That's a
strong signal this is a test-harness artifact (e.g. the one-pole ramp time constant vs.
the 512-frame window, or the test calling the C bridge in a way that doesn't match how
the real render thread primes ramp state — possibly the ramp starts from a stale/default
target because this is the FIRST 512-frame call and the ramp hasn't been kicked off by
whatever normally triggers a ramp update).

Verdict: **do not file as a confirmed product bug yet — needs a DSP-side repro check
first.** If the DSP reviewer confirms the C++ null-test gate exercises this exact
masterGainLinear-changes-mid-stream scenario and it's clean there, this becomes a
test-harness bug (the Swift bridge test isn't priming the ramp the way the real
engine does — e.g., missing a "commit new params" call before the first process()).
If the DSP reviewer CANNOT find an equivalent case in the C++ gate, this becomes a
**P1 bug ticket**: "master gain trim does not apply within one 512-frame render callback"
is a real, audible defect (users adjusting output level would hear it lag by multiple
callbacks — at 48kHz/512 frames that's ~10.6ms per callback, so even a few slow callbacks
is under 50ms and probably inaudible as a defect, but the fact that it's THIS far off in
one call is a flag worth DSP triage, not dismissal).

Priority if it becomes a ticket: **P1** (gain-staging correctness, not P0, because no
loudness-safety limiter is being bypassed and worst case is a fraction-of-a-second slow
fade rather than a wrong final level).

---

## 3. Minimum-phase / no pre-ring (ratio 0.65 vs threshold 0.1) — LIKELY TEST-METHODOLOGY, but WORTH A DSP LOOK

Product read: "no pre-ringing" is a real and correct product requirement — pre-ring
(energy appearing before a transient, characteristic of LINEAR-phase FIR EQ designs) is
exactly the kind of audible smearing artifact that conflicts with this app's "quality-
first, reject artifact-prone complexity" principle and its documented preference for
minimum-phase IIR biquads. So the INTENT of this test is 100% right — this is a real
product requirement, not a nice-to-have.

But the measurement (`firstSamplesMax / maxOutput` over the first 10 samples of white
noise) is a shaky proxy: minimum-phase IIR filters are causal by construction (no
Sample can influence samples before it), so true "pre-ring" in the FIR sense is
structurally impossible for a biquad cascade — what this metric is actually catching is
probably just the FIRST FEW SAMPLES of white noise legitimately having high amplitude
relative to a later windowed max, which is a property of the random draw, not a phase
defect. That reads like a test-methodology gap rather than a real defect, but I'm not
the DSP measurement owner — flagging for the DSP reviewer to confirm mathematically that
biquads can't pre-ring, and if so this is a **test bug** (wrong metric for a causal IIR
filter; should measure impulse response energy before t=0 in a properly windowed test,
which for a causal filter is trivially zero and shouldn't need asserting this way).

Verdict: **test bug (measurement methodology), pending DSP confirmation.** Not a product
behavior gap — the product requirement ("no pre-ring") is correct and already
structurally satisfied by choosing minimum-phase biquads; the test just isn't proving it
correctly.

---

## 4. VM-AA-RTR-1 — track ends before VM arms next → VM stops — REAL GAP, but ACCEPTABLE FOR NOW; schedule, don't block

The test pins current (stop) behavior and its own comment says a future fix should
invert it to "continue." I agree with the test author's framing entirely:

**What SHOULD happen (target product behavior):** for a very short track (<~50ms) that
reaches EOF before the VM's 20Hz poll has a chance to arm the on-deck slot, the player
should CONTINUE to the next track, not stop. Stopping playback because of an internal
polling-race artifact is a correctness bug from the user's point of view — "my playlist
silently stopped mid-song for no reason" is a bad, confusing experience, and it directly
contradicts "correctness over demoability" if left unaddressed indefinitely, because it's
not a cosmetic issue, it's a wrong player-state outcome.

**Is it a P0 that blocks anything now?** No. It requires an unusually short track
(<50ms — shorter than almost any real song, most likely to appear in test fixtures,
extremely short interstitial/silence tracks, or corrupt files) AND a race between engine
EOF and a 20Hz (50ms period) poll — a narrow window that will rarely occur with normal
music libraries. It's also a KNOWN, understood, and explicitly-labeled edge case (not a
silent landmine) with a clean stop rather than a crash, glitch, or data loss. That's
"acceptable current behavior" in the sense of not release-blocking, but it is a real,
scheduled architectural debt item, not a "won't-fix."

**Recommendation:** File as a real bug ticket, **P2** (edge-case correctness gap,
narrow trigger window, graceful current fallback, clear fix path already scoped in the
comment: pre-arm the next track earlier, or add an engine-side look-ahead instead of
polling-then-arm). Do NOT flip the test assertion today — the test is correctly encoding
current, intentional (if imperfect) behavior, with a clear inline TODO marking the
target future behavior. Keep it as documentation-as-test until the architectural fix
(pre-arm / look-ahead) is actually scheduled; flipping the assertion without the fix
would just make the test lie. This should be prioritized alongside other Sprint-6+
gapless/reconfigure-gap work (see project-gapless-playback memory) rather than treated
as a bug that needs to jump the queue.

---

## Prioritized failing-behavior list

**P0 — none.** No failing test in this run encodes a P0 (data-loss, crash, silent
audible-quality regression in the shipped signal path) product defect. The EQ module the
app actually ships is independently validated at 117/117 by the C++ gate; these Swift
test failures are either wrong test bars or narrow, already-mitigated edge cases.

**P1 (needs prompt DSP triage, may become a real ticket):**
- EQModule masterGainLinear attenuation measuring -0.66dB instead of ~-6dB in a single
  512-frame call. Escalate to DSP reviewer: confirm whether the C++ null-test gate
  exercises this same "change masterGain mid-stream, check first-callback attenuation"
  case. If gate covers it and passes → this is a Swift bridge/test-harness bug (ticket:
  fix the test's param-priming, not the DSP). If gate does NOT cover it → open a P1
  product bug: master-gain trim response time in the first render callback after a
  change.

**P2 (real, scheduled, non-blocking):**
- VM-AA-RTR-1 / short-track-before-arm gap: player stops instead of continuing when a
  very short track ends before the on-deck slot is armed. Real UX gap, narrow trigger,
  graceful current fallback, existing test already documents the target fix. File as a
  P2 architectural-debt ticket (pre-arm or engine-side look-ahead), do not flip the
  assertion until the fix lands.

**Test-retune, not product tickets (no code-behavior change implied):**
- Gain linearity ±0.05dB tolerance (EQTests.swift) — retune to the product's own
  accepted ±1.0dB bar (matching the C++ null-test gate's `kEqFrToleranceDb`), or ±0.5dB
  at tightest. This is the single biggest cluster of failures (13 of 16 EQ issues) and
  none of it reflects a real quality problem — it's an untethered, over-tight constant
  nobody validated against the product's actual accepted DSP-quality bar.
- Cross-path tolerance in the same test — same fix, same reasoning; it's measuring the
  same disagreement as the gain-linearity check, not an independent product requirement.
- Minimum-phase pre-ring metric — likely wrong measurement methodology for a causal IIR
  cascade (biquads structurally cannot pre-ring); confirm with DSP reviewer, then retune
  or replace the metric (e.g., assert on impulse-response causality directly) rather than
  keep an unfalsifiable threshold on a noise-signal artifact.

## Note on scope discipline
Per [[feedback-respect-sprint-boundaries]]: none of these findings suggest pulling in
Sprint 6 (clarity) or Sprint 5b (multichannel/binaural) scope. The masterGain and
pre-ring items are Sprint 5 (EQ) DSP-quality bar questions, in-scope for this branch.
The VM-AA-RTR-1 gap belongs with the gapless-playback stream (already tracked per
[[project-gapless-playback]]), not this branch's EQ wiring work — flagging it as a
ticket for that backlog, not asking to fix it here.
